//! `shadow-shot`: a zone offscreen with actor ground shadows (blobs and quads) drawn by the client's own
//! client/shadows.rs mode gate and render/shadow.rs, for checking them on the software renderer. The actors are
//! positions only (no model): each casts as an NPC would, so mode 0 (projected blob) or, past view depth 20 or on
//! a covered face, mode 2 (quad).

use crate::client::shadows::{self, Seen};
use crate::{client, config, dat, render};
use anyhow::Result;
use glam::Vec3;
use std::collections::HashMap;
use std::path::Path;

pub struct Shot<'a> {
    pub zone: u32,
    pub out: &'a Path,
    pub eye: Vec3,
    pub target: Vec3,
    pub hour: f32,
    /// Feet positions x, y, z (y is snapped to the floor under it).
    pub actors: Vec<Vec3>,
    pub size: [u32; 2],
    /// The kage texture alone to this PNG, as the client uploads it (decoded RGBA).
    pub dump_kage: Option<&'a Path>,
}

pub fn run(s: &Shot) -> Result<()> {
    if std::env::var_os("FFXI_UNCOMPRESSED").is_some() {
        render::UNCOMPRESSED.store(true, std::sync::atomic::Ordering::Relaxed);
    }
    let cfg = config::Config::load();
    let index = dat::DatIndex::open(&cfg.ffxi_dir())?;
    let keys = dat::zone::Keys::from_ffximain(&std::fs::read(cfg.ffxi_dir().join("FFXiMain.dll"))?)?;
    let file = index.read(dat::zone::file_id(s.zone))?;
    let scene = dat::zone::load_scene(&keys, &file)?;
    let lighting = dat::weather::ZoneWeather::parse(&file).ok().and_then(|w| w.at("suny", s.hour * 60.0)).map(|e| dat::weather::Lighting::from_env(&e, s.hour * 60.0));
    let ground = client::ground::Ground::build(&scene);
    let kage = shadows::kage_texture(&index).ok_or_else(|| anyhow::anyhow!("no kage texture"))?;
    println!("kage_tex {} {}x{} dxt {:?}", kage.name, kage.width, kage.height, kage.dxt.as_ref().map(|d| d.0));
    if let Some(p) = s.dump_kage {
        let mut enc = png::Encoder::new(std::io::BufWriter::new(std::fs::File::create(p)?), kage.width, kage.height);
        enc.set_color(png::ColorType::Rgba);
        enc.write_header()?.write_image_data(&kage.rgba)?;
        // The border texels, which a CLAMP sampler repeats over every face past the blob.
        let at = |x: u32, y: u32| &kage.rgba[((y * kage.width + x) * 4) as usize..][..4];
        let (w, h) = (kage.width - 1, kage.height - 1);
        println!("kage corners {:?} {:?} {:?} {:?}; edge mid {:?} {:?}", at(0, 0), at(w, 0), at(0, h), at(w, h), at(w / 2, 0), at(0, h / 2));
    }
    let camera = render::Camera { eye: s.eye, target: s.target, up: Vec3::NEG_Y, fov_y: 50f32.to_radians() };
    let view = camera.view();
    let mut seen: HashMap<u32, Seen> = HashMap::new();
    for (i, a) in s.actors.iter().enumerate() {
        let mut pos = *a;
        pos.y = ground.snap(pos.x, pos.z, pos.y).unwrap_or(pos.y);
        // A 1 x 3.5 x 1 box standing on the feet (y points down).
        let corners: [Vec3; 8] = std::array::from_fn(|k| Vec3::new(if k & 1 == 0 { -0.5 } else { 0.5 }, if k & 2 == 0 { 0.0 } else { -3.5 }, if k & 4 == 0 { -0.5 } else { 0.5 }));
        let world = corners.map(|c| c + pos);
        let depth = world.iter().map(|c| -view.transform_point3(*c).z).fold(f32::MIN, f32::max);
        let (kind, covered) = ground.surface(pos);
        println!("actor {i} at {pos} depth {depth:.2} surface kind {kind} covered {covered}");
        seen.insert(i as u32 + 1, Seen { pos, corners: world, depth });
    }
    let has = |_: u32| false;
    let flags = |_: u32| (false, false);
    let ctx = shadows::Ctx { ground: &ground, setting: 0, me: 0xffff_ff00, zone: s.zone as u16, has: &has, flags: &flags, layers: 0 };
    let mut far = shadows::Far::default();
    let modes = shadows::modes(&ctx, &mut far, &seen, s.eye);
    for (id, m, _) in &modes {
        println!("actor {} shadow mode {m}", id - 1);
    }
    let casters: Vec<render::shadow::Caster> = modes
        .iter()
        .enumerate()
        .map(|(k, (_, m, c))| render::shadow::Caster { mode: *m, pos: c.pos, corners: c.corners, lights: [0; 4], state: k as u32, fresh: true, cells: (*m != 2).then(|| ground.decal_range(c.pos)).flatten(), actor: None, layer: 0 })
        .collect();
    let list = [(&camera, s.out, lighting)];
    let mut post = |gpu: &render::Gpu, enc: &mut wgpu::CommandEncoder, (color, _): (&wgpu::TextureView, &wgpu::Texture), depth: &wgpu::TextureView, _: &render::Camera, l: Option<&dat::weather::Lighting>, zr: &mut render::ZoneRenderer| {
        if !zr.has_shadow_texture() {
            zr.set_shadow_texture(gpu, &kage, wgpu::TextureFormat::Rgba8Unorm);
        }
        gpu.run_mips(enc, u64::MAX);
        let sun = l.map_or([0.0; 4], |l| [l.actor_dir.x, l.actor_dir.y, l.actor_dir.z, 1.0]);
        zr.draw_shadows(gpu, enc, color, depth, s.size, &ground, &casters, sun, 1.0);
    };
    render::render_pngs_post(&scene, &list, s.size[0], s.size[1], &|_, _| Vec::new(), &mut post)?;
    println!("wrote {}", s.out.display());
    Ok(())
}
