//! Ours (not retail): the post pass's two effects that read the scene's depth (Config `graphics`, render/post.rs runs this
//! first): screen-space ambient occlusion and an exponential height fog. Both off by default; with both off `PostFx` keeps no
//! `DepthFx`, so no pipeline or texture of these exists.
//!
//! AO: a half-resolution normal-oriented hemisphere pass (12 taps, rotated per pixel by interleaved gradient noise, the
//! normal rebuilt from the depth's smaller neighbour differences), a depth-aware blur along x then y, and in the full-size
//! pass a depth-aware 2 x 2 upsample that multiplies the (gamma-space) scene colour by ao^strength. The scenery has baked
//! vertex lighting already, so the taps are tuned moderate, and the AO fades out with distance so far terrain stays clean.
//!
//! Height fog: from the depth and the camera's basis the pixel's world position, then the optical depth along the eye ray of
//! a density that is `fog_density` at the base height and below and falls off e^-(h / fog_height) above it (the world's y is
//! down), mixed toward the zone's own fog colour. The retail distance fog is already in the scene colour; this mixes the
//! rest toward the same colour (a pixel at the retail fog's end is the fog colour already and does not change), so the two
//! combine and are not added twice. The sky (depth 1) is left alone.

use super::post::pipeline;
use super::{Camera, FAR, Gpu, NEAR, Put};
use crate::config::GraphicsCfg;
use glam::Vec3;

const SHADER: &str = r#"
struct U {
    // tan(fov / 2) x and y, near, far.
    cam: vec4<f32>,
    // AO strength, radius (world units), fade start, fade end (view depth).
    ao: vec4<f32>,
    // Eye position, and the world y of the fog's base height.
    eye: vec4<f32>,
    right: vec4<f32>,
    up: vec4<f32>,
    fwd: vec4<f32>,
    // Fog colour (rgb, already scaled by the screen fades) and the density at the base a unit.
    fogc: vec4<f32>,
    // 1 / fog height.
    fog: vec4<f32>,
    // Full size, half size.
    size: vec4<f32>,
    // Bit 0 AO, bit 1 fog.
    flags: vec4<u32>,
};
@group(0) @binding(0) var<uniform> u: U;
@group(0) @binding(1) var tex: texture_2d<f32>;
// The scene's depth through the unfilterable-float view (loaded, never sampled).
@group(0) @binding(2) var depth: texture_2d<f32>;
// The half-size AO (r) and view depth (g).
@group(0) @binding(3) var aot: texture_2d<f32>;
struct VOut { @builtin(position) clip: vec4<f32>, @location(0) uv: vec2<f32> };
@vertex fn vs(@builtin(vertex_index) i: u32) -> VOut {
    let q = vec2<f32>(f32((i << 1u) & 2u), f32(i & 2u));
    var o: VOut;
    o.clip = vec4<f32>(q * 2.0 - 1.0, 0.0, 1.0);
    o.uv = vec2<f32>(q.x, 1.0 - q.y);
    return o;
}

fn full() -> vec2<i32> { return vec2<i32>(u.size.xy); }
fn dep(p: vec2<i32>) -> f32 { return textureLoad(depth, clamp(p, vec2<i32>(0), full() - vec2<i32>(1)), 0).r; }
// The standard 0..1 perspective depth back to the distance along the view axis.
fn lin(d: f32) -> f32 { return u.cam.z * u.cam.w / (u.cam.w - d * (u.cam.w - u.cam.z)); }
// View space: x right, y up, z forward.
fn view_pos(p: vec2<i32>, d: f32) -> vec3<f32> {
    let z = lin(d);
    let uv = (vec2<f32>(p) + 0.5) / u.size.xy;
    return vec3<f32>((uv.x * 2.0 - 1.0) * u.cam.x * z, (1.0 - uv.y * 2.0) * u.cam.y * z, z);
}
fn vp(p: vec2<i32>) -> vec3<f32> { return view_pos(p, dep(p)); }
// Interleaved gradient noise (Jimenez).
fn ign(p: vec2<f32>) -> f32 { return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715)))); }

const TAPS: i32 = 12;
// The half-size pass: r = 1 - occlusion, g = the view depth (the far plane for the sky).
@fragment fn ao_fs(i: VOut) -> @location(0) vec4<f32> {
    let hp = vec2<i32>(i.clip.xy);
    let fp = hp * 2;
    let d = dep(fp);
    if (d >= 1.0) { return vec4<f32>(1.0, u.cam.w, 0.0, 1.0); }
    let p = view_pos(fp, d);
    let fade = 1.0 - smoothstep(u.ao.z, u.ao.w, p.z);
    if (fade <= 0.0) { return vec4<f32>(1.0, p.z, 0.0, 1.0); }
    // The normal from whichever neighbour is nearer in depth on each axis (no smearing over an edge).
    let dr = vp(fp + vec2<i32>(1, 0)) - p;
    let dl = p - vp(fp - vec2<i32>(1, 0));
    let dd = vp(fp + vec2<i32>(0, 1)) - p;
    let du = p - vp(fp - vec2<i32>(0, 1));
    let ddx = select(dl, dr, abs(dr.z) < abs(dl.z));
    let ddy = select(du, dd, abs(dd.z) < abs(du.z));
    let n = normalize(cross(ddx, ddy));
    // The radius, kept to 48 pixels on the screen when the surface is close.
    let r = min(u.ao.y, 48.0 * 2.0 * u.cam.y * p.z / u.size.y);
    let bias = 0.04 * r + 0.002 * p.z;
    var t = select(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(0.0, 1.0, 0.0), abs(n.x) > 0.9);
    t = normalize(t - n * dot(t, n));
    let b = cross(n, t);
    let turn = 6.2831853 * ign(vec2<f32>(hp));
    var acc = 0.0;
    for (var k = 0; k < TAPS; k++) {
        let f = (f32(k) + 0.5) / f32(TAPS);
        let a = turn + f32(k) * 2.39996323;
        let lift = sqrt(f);
        let ring = sqrt(1.0 - f);
        let len = mix(0.2, 1.0, fract(f32(k) * 0.6180339887 + 0.37));
        let sp = p + (t * (cos(a) * ring) + b * (sin(a) * ring) + n * lift) * (r * len);
        if (sp.z <= u.cam.z) { continue; }
        let ndc = vec2<f32>(sp.x / (sp.z * u.cam.x), sp.y / (sp.z * u.cam.y));
        let q = vec2<i32>(floor(vec2<f32>((ndc.x * 0.5 + 0.5) * u.size.x, (0.5 - ndc.y * 0.5) * u.size.y)));
        let sd = dep(q);
        if (sd >= 1.0) { continue; }
        let sz = lin(sd);
        // Occluded when the scene is in front of the tap; a surface far in front (another object) counts for less.
        let hit = select(0.0, 1.0, sz < sp.z - bias);
        acc += hit * smoothstep(0.0, 1.0, r / max(abs(p.z - sz), 0.001));
    }
    // x1.5: the taps are sparse and the scenery is already lit, so a crease reads at strength 1 without going black.
    return vec4<f32>(1.0 - clamp(fade * acc * 1.5 / f32(TAPS), 0.0, 0.85), p.z, 0.0, 1.0);
}

// The blur along one axis: 9 taps, weighted by distance and by how near in depth they are to the centre's.
fn blur(hp: vec2<i32>, dir: vec2<i32>) -> vec4<f32> {
    let hsz = vec2<i32>(u.size.zw);
    let c = textureLoad(aot, clamp(hp, vec2<i32>(0), hsz - vec2<i32>(1)), 0);
    if (c.g >= u.cam.w) { return c; }
    let tol = 0.08 * c.g + 0.05;
    var sum = c.r;
    var wsum = 1.0;
    for (var k = -4; k <= 4; k++) {
        if (k == 0) { continue; }
        let s = textureLoad(aot, clamp(hp + dir * k, vec2<i32>(0), hsz - vec2<i32>(1)), 0);
        let dz = (s.g - c.g) / tol;
        let w = exp(-f32(k * k) * 0.125) * exp(-dz * dz);
        sum += s.r * w;
        wsum += w;
    }
    return vec4<f32>(sum / wsum, c.g, 0.0, 1.0);
}
@fragment fn blur_h_fs(i: VOut) -> @location(0) vec4<f32> { return blur(vec2<i32>(i.clip.xy), vec2<i32>(1, 0)); }
@fragment fn blur_v_fs(i: VOut) -> @location(0) vec4<f32> { return blur(vec2<i32>(i.clip.xy), vec2<i32>(0, 1)); }

// The full-size pass: the scene colour times the upsampled AO, then the height fog.
@fragment fn comp_fs(i: VOut) -> @location(0) vec4<f32> {
    let fp = vec2<i32>(i.clip.xy);
    var c = textureLoad(tex, fp, 0).rgb;
    let d = dep(fp);
    if (d >= 1.0) { return vec4<f32>(c, 1.0); }
    let p = view_pos(fp, d);
    if ((u.flags.x & 1u) != 0u) {
        // Depth-aware 2 x 2 from the half-size texels around this pixel.
        let hsz = vec2<i32>(u.size.zw);
        let q = (vec2<f32>(fp) - 0.5) * 0.5;
        let base = vec2<i32>(floor(q));
        let fr = q - floor(q);
        let tol = 0.05 * p.z + 0.05;
        var sum = 0.0;
        var wsum = 0.0;
        for (var j = 0; j < 2; j++) {
            for (var k = 0; k < 2; k++) {
                let s = textureLoad(aot, clamp(base + vec2<i32>(k, j), vec2<i32>(0), hsz - vec2<i32>(1)), 0);
                let bl = select(1.0 - fr.x, fr.x, k == 1) * select(1.0 - fr.y, fr.y, j == 1);
                let dz = (s.g - p.z) / tol;
                let w = bl * exp(-dz * dz) + 0.0001;
                sum += s.r * w;
                wsum += w;
            }
        }
        c = c * pow(clamp(sum / wsum, 0.0, 1.0), u.ao.x);
    }
    if ((u.flags.x & 2u) != 0u) {
        let wv = u.right.xyz * p.x + u.up.xyz * p.y + u.fwd.xyz * p.z;
        let dist = length(wv);
        // The unit ray's rise (the world's y is down), and the eye's height over the base.
        let rise = -wv.y / dist;
        let h0 = u.eye.w - u.eye.y;
        let steps = 10;
        let dt = dist / f32(steps);
        var tau = 0.0;
        for (var k = 0; k < steps; k++) {
            let h = h0 + rise * (f32(k) + 0.5) * dt;
            tau += exp(-max(h, 0.0) * u.fog.x) * dt;
        }
        c = mix(c, u.fogc.rgb, 1.0 - exp(-tau * u.fogc.w));
    }
    return vec4<f32>(c, 1.0);
}
"#;

/// What the depth effects need of the camera: its basis (the pixel's world position from the depth), the base height of the
/// fog and its colour.
#[derive(Clone, Copy, Debug)]
pub struct PostCam {
    pub eye: Vec3,
    pub right: Vec3,
    pub up: Vec3,
    pub fwd: Vec3,
    /// tan(fov_y / 2) times the aspect, and tan(fov_y / 2).
    pub tan_half: [f32; 2],
    /// The world y (down) of the fog's densest level; it thins above.
    pub base_y: f32,
    /// The fog colour (gamma space), already scaled by the screen fades over the scene (black stays black).
    pub fog_color: [f32; 3],
}

impl PostCam {
    pub fn new(camera: &Camera, aspect: f32, base_y: f32, fog_color: [f32; 3]) -> Self {
        let fwd = (camera.target - camera.eye).normalize_or(Vec3::Z);
        let right = fwd.cross(camera.up).normalize_or(Vec3::X);
        let up = right.cross(fwd);
        let t = (camera.fov_y * 0.5).tan();
        Self { eye: camera.eye, right, up, fwd, tan_half: [t * aspect, t], base_y, fog_color }
    }
}

/// The scene's depth view (a render target of the scene's size, with TEXTURE_BINDING) and the camera it was drawn from.
#[derive(Clone, Copy)]
pub struct DepthIn<'a> {
    pub depth: &'a wgpu::TextureView,
    pub cam: PostCam,
}

/// View depth fading the AO out: full to here, none from the second.
const FADE: [f32; 2] = [50.0, 220.0];
/// The fog's density a unit at `fog_density` 1.
const FOG_UNIT: f32 = 0.004;

struct Half {
    size: [u32; 2],
    a: wgpu::TextureView,
    b: wgpu::TextureView,
    _tex: [wgpu::Texture; 2],
}

pub struct DepthFx {
    layout: wgpu::BindGroupLayout,
    uniform: wgpu::Buffer,
    ao: wgpu::RenderPipeline,
    blur_h: wgpu::RenderPipeline,
    blur_v: wgpu::RenderPipeline,
    comp: wgpu::RenderPipeline,
    format: wgpu::TextureFormat,
    /// The half-size AO ping-pong pair; only while AO is on.
    half: Option<Half>,
    /// The result: the scene colour with the effects applied.
    out: Option<(wgpu::Texture, wgpu::TextureView)>,
}

const AO_FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Rg16Float;

impl DepthFx {
    pub fn new(gpu: &Gpu, format: wgpu::TextureFormat) -> Self {
        let device = &gpu.device;
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor { label: Some("post depth fx"), source: wgpu::ShaderSource::Wgsl(SHADER.into()) });
        let tex_entry = |binding| wgpu::BindGroupLayoutEntry {
            binding,
            visibility: wgpu::ShaderStages::FRAGMENT,
            ty: wgpu::BindingType::Texture { sample_type: wgpu::TextureSampleType::Float { filterable: false }, view_dimension: wgpu::TextureViewDimension::D2, multisampled: false },
            count: None,
        };
        let layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("post depth fx"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: false, min_binding_size: None },
                    count: None,
                },
                tex_entry(1),
                tex_entry(2),
                tex_entry(3),
            ],
        });
        let pl = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: Some("post depth fx"), bind_group_layouts: &[Some(&layout)], immediate_size: 0 });
        let uniform = device.create_buffer(&wgpu::BufferDescriptor { label: Some("post depth fx"), size: 160, usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false });
        let mk = |entry, f| pipeline(device, &shader, &pl, entry, f, None);
        Self { ao: mk("ao_fs", AO_FORMAT), blur_h: mk("blur_h_fs", AO_FORMAT), blur_v: mk("blur_v_fs", AO_FORMAT), comp: mk("comp_fs", format), layout, uniform, format, half: None, out: None }
    }

    /// The scene colour `src` (plain view of the scene's size) with the effects of `cfg` applied, through the scene's `depth`
    /// seen from `cam`; the result view is this struct's own and valid until the next call.
    pub fn run(&mut self, gpu: &Gpu, enc: &mut wgpu::CommandEncoder, src: &wgpu::TextureView, size: [u32; 2], input: DepthIn, cfg: &GraphicsCfg) -> wgpu::TextureView {
        let device = &gpu.device;
        let clamp = |v: f32, lo: f32, hi: f32| if v.is_finite() { v.clamp(lo, hi) } else { lo };
        let (ao_on, fog_on) = (cfg.ao_on(), cfg.fog_on());
        let half = [size[0].div_ceil(2).max(1), size[1].div_ceil(2).max(1)];
        let cam = input.cam;
        if self.out.as_ref().is_none_or(|(t, _)| t.width() != size[0] || t.height() != size[1] || t.format() != self.format) {
            let tex = device.create_texture(&wgpu::TextureDescriptor {
                label: Some("post depth fx output"),
                size: wgpu::Extent3d { width: size[0], height: size[1], depth_or_array_layers: 1 },
                mip_level_count: 1,
                sample_count: 1,
                dimension: wgpu::TextureDimension::D2,
                format: self.format,
                usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_SRC,
                view_formats: &[],
            });
            let view = tex.create_view(&Default::default());
            self.out = Some((tex, view));
        }
        if !ao_on {
            self.half = None;
        } else if self.half.as_ref().is_none_or(|h| h.size != half) {
            let mk = |label| {
                let tex = device.create_texture(&wgpu::TextureDescriptor {
                    label: Some(label),
                    size: wgpu::Extent3d { width: half[0], height: half[1], depth_or_array_layers: 1 },
                    mip_level_count: 1,
                    sample_count: 1,
                    dimension: wgpu::TextureDimension::D2,
                    format: AO_FORMAT,
                    usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
                    view_formats: &[],
                });
                (tex.create_view(&Default::default()), tex)
            };
            let (a, ta) = mk("post ao a");
            let (b, tb) = mk("post ao b");
            self.half = Some(Half { size: half, a, b, _tex: [ta, tb] });
        }
        let fade = cam.fog_color.map(|c| clamp(c, 0.0, 1.0));
        let u: [f32; 40] = [
            cam.tan_half[0], cam.tan_half[1], NEAR, FAR,
            clamp(cfg.ao_strength, 0.0, 2.0), clamp(cfg.ao_radius, 0.25, 4.0), FADE[0], FADE[1],
            cam.eye.x, cam.eye.y, cam.eye.z, cam.base_y,
            cam.right.x, cam.right.y, cam.right.z, 0.0,
            cam.up.x, cam.up.y, cam.up.z, 0.0,
            cam.fwd.x, cam.fwd.y, cam.fwd.z, 0.0,
            fade[0], fade[1], fade[2], clamp(cfg.fog_density, 0.0, 2.0) * FOG_UNIT,
            1.0 / clamp(cfg.fog_height, 2.0, 200.0), 0.0, 0.0, 0.0,
            size[0] as f32, size[1] as f32, half[0] as f32, half[1] as f32,
            f32::from_bits(ao_on as u32 | (fog_on as u32) << 1), 0.0, 0.0, 0.0,
        ];
        gpu.queue.put(&self.uniform, 0, bytemuck::cast_slice(&u));
        let group = |colour: &wgpu::TextureView, ao: &wgpu::TextureView| {
            device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("post depth fx"),
                layout: &self.layout,
                entries: &[
                    wgpu::BindGroupEntry { binding: 0, resource: self.uniform.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(colour) },
                    wgpu::BindGroupEntry { binding: 2, resource: wgpu::BindingResource::TextureView(input.depth) },
                    wgpu::BindGroupEntry { binding: 3, resource: wgpu::BindingResource::TextureView(ao) },
                ],
            })
        };
        let draw = |enc: &mut wgpu::CommandEncoder, target: &wgpu::TextureView, pipe: &wgpu::RenderPipeline, g: &wgpu::BindGroup| {
            let mut pass = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("post depth fx"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment { view: target, depth_slice: None, resolve_target: None, ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color::BLACK), store: wgpu::StoreOp::Store } })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });
            pass.set_pipeline(pipe);
            pass.set_bind_group(0, g, &[]);
            pass.draw(0..3, 0..1);
        };
        // A texture a pass writes is never also bound to it: each pass gets the pair's other one (or the scene) for binding 3.
        let mut ao_view = src.clone();
        if let Some(h) = &self.half {
            draw(enc, &h.a, &self.ao, &group(src, &h.b));
            draw(enc, &h.b, &self.blur_h, &group(src, &h.a));
            draw(enc, &h.a, &self.blur_v, &group(src, &h.b));
            ao_view = h.a.clone();
        }
        let out = self.out.as_ref().unwrap().1.clone();
        draw(enc, &out, &self.comp, &group(src, &ao_view));
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FMT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8Unorm;
    const N: u32 = 64;

    /// A synthetic depth buffer: the view space (x right, y up, z forward) with a floor at y = -1 (kind 0 and 1) and / or a
    /// wall at z = `wall` (kinds 0 and 2), as a ray's first hit (0.5 tan half angles); the sky stays at depth 1.
    const DEPTH_SHADER: &str = r#"
    struct K { kind: u32, wall: f32, pad0: f32, pad1: f32 };
    @group(0) @binding(0) var<uniform> k: K;
    struct VOut { @builtin(position) clip: vec4<f32>, @location(0) uv: vec2<f32> };
    @vertex fn vs(@builtin(vertex_index) i: u32) -> VOut {
        let q = vec2<f32>(f32((i << 1u) & 2u), f32(i & 2u));
        var o: VOut;
        o.clip = vec4<f32>(q * 2.0 - 1.0, 0.0, 1.0);
        o.uv = vec2<f32>(q.x, 1.0 - q.y);
        return o;
    }
    @fragment fn fs(i: VOut) -> @builtin(frag_depth) f32 {
        let dy = (1.0 - i.uv.y * 2.0) * 0.5;
        var z = 1.0e9;
        if (k.kind != 2u && dy < -0.0001) { z = min(z, -1.0 / dy); }
        if (k.kind != 1u) { z = min(z, k.wall); }
        if (z > 1.0e8) { return 1.0; }
        let n = 0.1; let f = 2000.0;
        return f * (z - n) / (z * (f - n));
    }
    "#;

    fn gpu() -> Option<Gpu> {
        let g = Gpu::headless().ok();
        if g.is_none() {
            eprintln!("no GPU adapter: depth fx pixel tests skipped");
        }
        g
    }

    fn depth(gpu: &Gpu, kind: u32, wall: f32) -> wgpu::TextureView {
        let device = &gpu.device;
        let view = super::super::depth_view(device, N, N);
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor { label: None, source: wgpu::ShaderSource::Wgsl(DEPTH_SHADER.into()) });
        let layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: None,
            entries: &[wgpu::BindGroupLayoutEntry { binding: 0, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: false, min_binding_size: None }, count: None }],
        });
        let pl = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: None, bind_group_layouts: &[Some(&layout)], immediate_size: 0 });
        let pipe = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: None,
            layout: Some(&pl),
            vertex: wgpu::VertexState { module: &shader, entry_point: Some("vs"), compilation_options: Default::default(), buffers: &[] },
            primitive: Default::default(),
            depth_stencil: Some(wgpu::DepthStencilState { format: super::super::DEPTH_FORMAT, depth_write_enabled: Some(true), depth_compare: Some(wgpu::CompareFunction::Always), stencil: Default::default(), bias: Default::default() }),
            multisample: Default::default(),
            fragment: Some(wgpu::FragmentState { module: &shader, entry_point: Some("fs"), compilation_options: Default::default(), targets: &[] }),
            multiview_mask: None,
            cache: None,
        });
        let buf = device.create_buffer(&wgpu::BufferDescriptor { label: None, size: 16, usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false });
        gpu.queue.write_buffer(&buf, 0, bytemuck::cast_slice(&[kind, wall.to_bits(), 0, 0]));
        let group = device.create_bind_group(&wgpu::BindGroupDescriptor { label: None, layout: &layout, entries: &[wgpu::BindGroupEntry { binding: 0, resource: buf.as_entire_binding() }] });
        let mut enc = device.create_command_encoder(&Default::default());
        {
            let mut pass = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: None,
                color_attachments: &[],
                depth_stencil_attachment: Some(wgpu::RenderPassDepthStencilAttachment { view: &view, depth_ops: Some(wgpu::Operations { load: wgpu::LoadOp::Clear(1.0), store: wgpu::StoreOp::Store }), stencil_ops: None }),
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });
            pass.set_pipeline(&pipe);
            pass.set_bind_group(0, &group, &[]);
            pass.draw(0..3, 0..1);
        }
        gpu.queue.submit([enc.finish()]);
        view
    }

    /// The camera of the synthetic depth: at the origin looking along +z with y up (the world's y is down: y = -up).
    fn cam(eye_up: f32, base_up: f32, fog: [f32; 3]) -> PostCam {
        PostCam { eye: Vec3::new(0.0, -eye_up, 0.0), right: Vec3::X, up: Vec3::NEG_Y, fwd: Vec3::Z, tan_half: [0.5, 0.5], base_y: -base_up, fog_color: fog }
    }

    /// A flat grey scene colour through `cfg` and the synthetic depth; the pixels (red) row by row.
    fn run(gpu: &Gpu, kind: u32, wall: f32, cam: PostCam, cfg: &GraphicsCfg) -> Vec<u8> {
        let colour = gpu.device.create_texture(&wgpu::TextureDescriptor {
            label: None,
            size: wgpu::Extent3d { width: N, height: N, depth_or_array_layers: 1 },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: FMT,
            usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        let data: Vec<u8> = (0..N * N).flat_map(|_| [128u8, 128, 128, 255]).collect();
        gpu.queue.write_texture(colour.as_image_copy(), &data, wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(N * 4), rows_per_image: Some(N) }, wgpu::Extent3d { width: N, height: N, depth_or_array_layers: 1 });
        let d = depth(gpu, kind, wall);
        let mut fx = DepthFx::new(gpu, FMT);
        let mut enc = gpu.device.create_command_encoder(&Default::default());
        let out = fx.run(gpu, &mut enc, &colour.create_view(&Default::default()), [N, N], DepthIn { depth: &d, cam }, cfg);
        let _ = out;
        let tex = fx.out.as_ref().unwrap().0.clone();
        let row = (N * 4).div_ceil(256) * 256;
        let buf = gpu.device.create_buffer(&wgpu::BufferDescriptor { label: None, size: (row * N) as u64, usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ, mapped_at_creation: false });
        enc.copy_texture_to_buffer(
            tex.as_image_copy(),
            wgpu::TexelCopyBufferInfo { buffer: &buf, layout: wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(row), rows_per_image: Some(N) } },
            wgpu::Extent3d { width: N, height: N, depth_or_array_layers: 1 },
        );
        gpu.queue.submit([enc.finish()]);
        buf.slice(..).map_async(wgpu::MapMode::Read, |_| {});
        gpu.device.poll(wgpu::PollType::Wait { submission_index: None, timeout: None }).unwrap();
        let m = buf.slice(..).get_mapped_range().unwrap();
        (0..N).flat_map(|y| (0..N).map(move |x| (y, x))).map(|(y, x)| m[(y * row + x * 4) as usize]).collect()
    }

    fn at(px: &[u8], x: u32, y: u32) -> u8 {
        px[(y * N + x) as usize]
    }

    fn ao_cfg() -> GraphicsCfg {
        GraphicsCfg { ao: true, ..Default::default() }
    }

    /// The depth effects are made only while one is on: the AO's half-size textures go with AO, and no effect leaves the
    /// colour as it was.
    #[test]
    fn nothing_made_while_off() {
        let Some(gpu) = gpu() else { return };
        let mut slot = None;
        assert!(super::super::post::ensure(&mut slot, &gpu, FMT, &GraphicsCfg { ao: true, ao_strength: 0.0, ..Default::default() }).is_none());
        let fx = super::super::post::ensure(&mut slot, &gpu, FMT, &GraphicsCfg { fxaa: true, ..Default::default() }).unwrap();
        assert!(!fx.has_depth_fx(), "fxaa alone makes no depth effect");
        let fx = super::super::post::ensure(&mut slot, &gpu, FMT, &ao_cfg()).unwrap();
        assert!(!fx.has_depth_fx(), "made on the first run, not by ensure");
        // A run with the depth makes it; a frame without one (a flash, a held frame) keeps it; ensure drops it with the option.
        let scene = gpu.device.create_texture(&wgpu::TextureDescriptor {
            label: None,
            size: wgpu::Extent3d { width: N, height: N, depth_or_array_layers: 1 },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: FMT,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_SRC,
            view_formats: &[],
        });
        let d = depth(&gpu, 0, 6.0);
        let mut enc = gpu.device.create_command_encoder(&Default::default());
        fx.run(&gpu, &mut enc, &scene, &ao_cfg(), Some(DepthIn { depth: &d, cam: cam(0.0, 0.0, [1.0; 3]) }));
        assert!(fx.has_depth_fx());
        let fx = super::super::post::ensure(&mut slot, &gpu, FMT, &ao_cfg()).unwrap();
        fx.run(&gpu, &mut enc, &scene, &ao_cfg(), None);
        assert!(fx.has_depth_fx(), "a frame without the depth does not rebuild it next frame");
        gpu.queue.submit([enc.finish()]);
        let fx = super::super::post::ensure(&mut slot, &gpu, FMT, &GraphicsCfg { fxaa: true, ..Default::default() }).unwrap();
        assert!(!fx.has_depth_fx(), "dropped with the option");
        assert!(super::super::post::ensure(&mut slot, &gpu, FMT, &GraphicsCfg::default()).is_none() && slot.is_none());
    }

    /// A tilted flat plane is not occluded by itself; a floor meeting a wall darkens near the crease only.
    #[test]
    fn ao_darkens_a_crease_and_leaves_a_plane() {
        let Some(gpu) = gpu() else { return };
        let c = cam(0.0, 0.0, [1.0; 3]);
        let plane = run(&gpu, 1, 0.0, c, &ao_cfg());
        // Rows 41..61 are the floor from 7.5 to 2.1 units away, columns 8..56 clear of the sides.
        for y in 41..62 {
            for x in 8..56 {
                assert!(at(&plane, x, y) >= 124, "floor ({x}, {y}) = {}", at(&plane, x, y));
            }
        }
        let crease = run(&gpu, 0, 6.0, c, &ao_cfg());
        // The crease is at row 42 (6 units out); the floor and the wall 3+ units from it are as drawn.
        let low = (36..50).flat_map(|y| (16..48).map(move |x| (x, y))).map(|(x, y)| at(&crease, x, y)).min().unwrap();
        assert!(low < 112, "the crease darkens: {low}");
        for (x, y) in [(32, 58), (20, 60), (32, 6), (40, 10)] {
            assert!(at(&crease, x, y) >= 124, "({x}, {y}) away from the crease = {}", at(&crease, x, y));
        }
        // Strength 0 is as drawn, and more strength is darker.
        let more = run(&gpu, 0, 6.0, c, &GraphicsCfg { ao: true, ao_strength: 2.0, ..Default::default() });
        let low2 = (36..50).flat_map(|y| (16..48).map(move |x| (x, y))).map(|(x, y)| at(&more, x, y)).min().unwrap();
        assert!(low2 < low, "{low2} {low}");
    }

    /// The fog grows with the distance, and is denser looking down (staying in the fog) than up (leaving it).
    #[test]
    fn fog_grows_with_depth_and_below_the_height() {
        let Some(gpu) = gpu() else { return };
        let cfg = GraphicsCfg { fog: true, fog_density: 1.0, fog_height: 5.0, ..Default::default() };
        let white = cam(0.0, 0.0, [1.0; 3]);
        let near = run(&gpu, 2, 10.0, white, &cfg);
        let far = run(&gpu, 2, 60.0, white, &cfg);
        assert!(at(&near, 32, 32) > 128 && at(&far, 32, 32) > at(&near, 32, 32), "{} {}", at(&near, 32, 32), at(&far, 32, 32));
        // At 40 units, the bottom row (looking down, 20 below the base) against the top row (20 above it).
        let wall = run(&gpu, 2, 40.0, white, &cfg);
        assert!(at(&wall, 32, 60) > at(&wall, 32, 4), "below {} above {}", at(&wall, 32, 60), at(&wall, 32, 4));
        // The zone's colour tints it: a dark fog colour darkens, and one faded to black stays black.
        let dark = run(&gpu, 2, 60.0, cam(0.0, 0.0, [0.0; 3]), &cfg);
        assert!(at(&dark, 32, 32) < at(&far, 32, 32) && at(&dark, 32, 32) < 128);
        // Fog off (zero density) leaves the colour exactly.
        let off = run(&gpu, 2, 60.0, white, &GraphicsCfg { fog: true, fog_density: 0.0, ..Default::default() });
        assert!(off.iter().all(|p| *p == 128));
    }
}
