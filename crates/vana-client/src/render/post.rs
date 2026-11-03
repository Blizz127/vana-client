//! Ours (not retail): optional post-processing over the finished 3D scene, before the 2D layer: FXAA 3.11, bloom, a filmic
//! tone curve with exposure, contrast-adaptive sharpening and saturation (Config `graphics`). All off by default; with all
//! off `ensure` keeps no PostFx, so no pipeline or texture exists and the scene goes to the scaling pass as before.
//!
//! The scene is 8-bit and drawn in gamma space (as D3D8 did), so everything here is an LDR grade on those values: FXAA, CAS
//! and saturation work on the gamma values as stored, bloom and the tone curve go through linear (x^2.2). Order: FXAA, then
//! (CAS, bloom added, tone curve, saturation) in one composite pass. The result goes to a texture of its own and the scene
//! texture is left as drawn (a zone change's held frame is copied from it and must not be processed twice).
//!
//! Ambient occlusion and height fog (render/postdepth.rs) read the scene's depth and run first, over the scene as drawn;
//! FXAA and the composite then take their result. They are made only while one is on and the depth is given.

use super::Gpu;
use super::Put;
use super::postdepth::{DepthFx, DepthIn};
use crate::config::GraphicsCfg;

const SHADER: &str = r#"
struct P {
    thr: f32,
    intensity: f32,
    exposure: f32,
    sharpen: f32,
    sat: f32,
    flags: u32,
    pad0: f32,
    pad1: f32,
};
@group(0) @binding(0) var<uniform> p: P;
@group(0) @binding(1) var tex: texture_2d<f32>;
@group(0) @binding(2) var samp: sampler;
// The composite pass: the blurred bright parts (the chain's first level).
@group(0) @binding(3) var tex2: texture_2d<f32>;
struct VOut { @builtin(position) clip: vec4<f32>, @location(0) uv: vec2<f32> };
@vertex fn vs(@builtin(vertex_index) i: u32) -> VOut {
    let q = vec2<f32>(f32((i << 1u) & 2u), f32(i & 2u));
    var o: VOut;
    o.clip = vec4<f32>(q * 2.0 - 1.0, 0.0, 1.0);
    o.uv = vec2<f32>(q.x, 1.0 - q.y);
    return o;
}
fn s(uv: vec2<f32>) -> vec3<f32> { return textureSampleLevel(tex, samp, uv, 0.0).rgb; }
fn lum(c: vec3<f32>) -> f32 { return dot(c, vec3<f32>(0.299, 0.587, 0.114)); }
fn to_lin(c: vec3<f32>) -> vec3<f32> { return pow(max(c, vec3<f32>(0.0)), vec3<f32>(2.2)); }
fn to_gam(c: vec3<f32>) -> vec3<f32> { return pow(max(c, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2)); }

// FXAA 3.11 (quality, edge search up to ~30 px): the edge's luma span, its end by stepping both ways, the pixel moved
// across it to the sub-pixel position.
fn fxaa(uv: vec2<f32>) -> vec4<f32> {
    let rcp = 1.0 / vec2<f32>(textureDimensions(tex));
    let m4 = textureSampleLevel(tex, samp, uv, 0.0);
    let lumaM = lum(m4.rgb);
    var lumaS = lum(s(uv + vec2<f32>(0.0, rcp.y)));
    let lumaE = lum(s(uv + vec2<f32>(rcp.x, 0.0)));
    var lumaN = lum(s(uv - vec2<f32>(0.0, rcp.y)));
    let lumaW = lum(s(uv - vec2<f32>(rcp.x, 0.0)));
    let rangeMax = max(max(lumaN, lumaW), max(lumaE, max(lumaS, lumaM)));
    let rangeMin = min(min(lumaN, lumaW), min(lumaE, min(lumaS, lumaM)));
    let range = rangeMax - rangeMin;
    if (range < max(0.0312, rangeMax * 0.125)) { return m4; }
    let lumaNW = lum(s(uv + vec2<f32>(-rcp.x, -rcp.y)));
    let lumaSE = lum(s(uv + vec2<f32>(rcp.x, rcp.y)));
    let lumaNE = lum(s(uv + vec2<f32>(rcp.x, -rcp.y)));
    let lumaSW = lum(s(uv + vec2<f32>(-rcp.x, rcp.y)));
    let lumaNS = lumaN + lumaS;
    let lumaWE = lumaW + lumaE;
    let subpixRcpRange = 1.0 / range;
    let subpixNSWE = lumaNS + lumaWE;
    let edgeHorz1 = -2.0 * lumaM + lumaNS;
    let edgeVert1 = -2.0 * lumaM + lumaWE;
    let lumaNESE = lumaNE + lumaSE;
    let lumaNWNE = lumaNW + lumaNE;
    let edgeHorz2 = -2.0 * lumaE + lumaNESE;
    let edgeVert2 = -2.0 * lumaN + lumaNWNE;
    let lumaNWSW = lumaNW + lumaSW;
    let lumaSWSE = lumaSW + lumaSE;
    let edgeHorz4 = abs(edgeHorz1) * 2.0 + abs(edgeHorz2);
    let edgeVert4 = abs(edgeVert1) * 2.0 + abs(edgeVert2);
    let edgeHorz3 = -2.0 * lumaW + lumaNWSW;
    let edgeVert3 = -2.0 * lumaS + lumaSWSE;
    let edgeHorz = abs(edgeHorz3) + edgeHorz4;
    let edgeVert = abs(edgeVert3) + edgeVert4;
    let subpixNWSWNESE = lumaNWSW + lumaNESE;
    let horzSpan = edgeHorz >= edgeVert;
    var lengthSign = rcp.x;
    if (!horzSpan) { lumaN = lumaW; lumaS = lumaE; }
    if (horzSpan) { lengthSign = rcp.y; }
    let subpixA = subpixNSWE * 2.0 + subpixNWSWNESE;
    let subpixB = subpixA * (1.0 / 12.0) - lumaM;
    let gradientN = lumaN - lumaM;
    let gradientS = lumaS - lumaM;
    var lumaNN = lumaN + lumaM;
    let lumaSS = lumaS + lumaM;
    let pairN = abs(gradientN) >= abs(gradientS);
    let gradient = max(abs(gradientN), abs(gradientS));
    if (pairN) { lengthSign = -lengthSign; }
    let subpixC = clamp(abs(subpixB) * subpixRcpRange, 0.0, 1.0);
    var posB = uv;
    var offNP = vec2<f32>(0.0, 0.0);
    if (horzSpan) { offNP.x = rcp.x; } else { offNP.y = rcp.y; }
    if (!horzSpan) { posB.x += lengthSign * 0.5; }
    if (horzSpan) { posB.y += lengthSign * 0.5; }
    var posN = posB - offNP;
    var posP = posB + offNP;
    let subpixD = -2.0 * subpixC + 3.0;
    var lumaEndN = lum(s(posN));
    let subpixE = subpixC * subpixC;
    var lumaEndP = lum(s(posP));
    if (!pairN) { lumaNN = lumaSS; }
    let gradientScaled = gradient * 0.25;
    let lumaMM = lumaM - lumaNN * 0.5;
    let subpixF = subpixD * subpixE;
    let lumaMLTZero = lumaMM < 0.0;
    lumaEndN -= lumaNN * 0.5;
    lumaEndP -= lumaNN * 0.5;
    var doneN = abs(lumaEndN) >= gradientScaled;
    var doneP = abs(lumaEndP) >= gradientScaled;
    var steps = array<f32, 10>(1.5, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0);
    for (var k = 0; k < 10; k++) {
        if (doneN && doneP) { break; }
        if (!doneN) {
            posN -= offNP * steps[k];
            lumaEndN = lum(s(posN)) - lumaNN * 0.5;
            doneN = abs(lumaEndN) >= gradientScaled;
        }
        if (!doneP) {
            posP += offNP * steps[k];
            lumaEndP = lum(s(posP)) - lumaNN * 0.5;
            doneP = abs(lumaEndP) >= gradientScaled;
        }
    }
    var dstN = uv.x - posN.x;
    var dstP = posP.x - uv.x;
    if (!horzSpan) {
        dstN = uv.y - posN.y;
        dstP = posP.y - uv.y;
    }
    let goodSpanN = (lumaEndN < 0.0) != lumaMLTZero;
    let spanLengthRcp = 1.0 / (dstP + dstN);
    let goodSpanP = (lumaEndP < 0.0) != lumaMLTZero;
    let directionN = dstN < dstP;
    let dst = min(dstN, dstP);
    let goodSpan = select(goodSpanP, goodSpanN, directionN);
    let subpixG = subpixF * subpixF;
    let pixelOffset = dst * (-spanLengthRcp) + 0.5;
    let subpixH = subpixG * 0.75;
    let pixelOffsetGood = select(0.0, pixelOffset, goodSpan);
    let pixelOffsetSubpix = max(pixelOffsetGood, subpixH);
    var posM = uv;
    if (!horzSpan) { posM.x += pixelOffsetSubpix * lengthSign; }
    if (horzSpan) { posM.y += pixelOffsetSubpix * lengthSign; }
    return vec4<f32>(s(posM), m4.a);
}
@fragment fn fxaa_fs(i: VOut) -> @location(0) vec4<f32> { return fxaa(i.uv); }

// Bloom. The bright pass: soft knee on the brightest channel (linear), 4x4 box of the source into the half-size level.
fn bright(c: vec3<f32>) -> vec3<f32> {
    let l = to_lin(c);
    let b = max(l.r, max(l.g, l.b));
    let k = p.thr * 0.5 + 0.0001;
    var rq = clamp(b - p.thr + k, 0.0, 2.0 * k);
    rq = rq * rq / (4.0 * k);
    return l * (max(rq, b - p.thr) / max(b, 0.0001));
}
@fragment fn bright_fs(i: VOut) -> @location(0) vec4<f32> {
    let d = 1.0 / vec2<f32>(textureDimensions(tex));
    let c = bright(s(i.uv + vec2<f32>(-1.0, -1.0) * d)) + bright(s(i.uv + vec2<f32>(1.0, -1.0) * d))
          + bright(s(i.uv + vec2<f32>(-1.0, 1.0) * d)) + bright(s(i.uv + vec2<f32>(1.0, 1.0) * d));
    return vec4<f32>(c * 0.25, 1.0);
}
// Down: the 4x4 box again, no threshold.
@fragment fn down_fs(i: VOut) -> @location(0) vec4<f32> {
    let d = 1.0 / vec2<f32>(textureDimensions(tex));
    let c = s(i.uv + vec2<f32>(-1.0, -1.0) * d) + s(i.uv + vec2<f32>(1.0, -1.0) * d)
          + s(i.uv + vec2<f32>(-1.0, 1.0) * d) + s(i.uv + vec2<f32>(1.0, 1.0) * d);
    return vec4<f32>(c * 0.25, 1.0);
}
// Up: a 3x3 tent of the smaller level, added (One / One) to the level below.
@fragment fn up_fs(i: VOut) -> @location(0) vec4<f32> {
    let d = 1.0 / vec2<f32>(textureDimensions(tex));
    var c = s(i.uv) * 4.0;
    c += (s(i.uv + vec2<f32>(-d.x, 0.0)) + s(i.uv + vec2<f32>(d.x, 0.0)) + s(i.uv + vec2<f32>(0.0, -d.y)) + s(i.uv + vec2<f32>(0.0, d.y))) * 2.0;
    c += s(i.uv + vec2<f32>(-d.x, -d.y)) + s(i.uv + vec2<f32>(d.x, -d.y)) + s(i.uv + vec2<f32>(-d.x, d.y)) + s(i.uv + vec2<f32>(d.x, d.y));
    return vec4<f32>(c * (1.0 / 16.0), 1.0);
}

fn ld(pos: vec2<i32>, dim: vec2<i32>, o: vec2<i32>) -> vec3<f32> {
    return textureLoad(tex, clamp(pos + o, vec2<i32>(0), dim - vec2<i32>(1)), 0).rgb;
}
// Composite: flags 1 tone curve, 2 bloom, 4 CAS, 8 saturation.
@fragment fn composite_fs(i: VOut) -> @location(0) vec4<f32> {
    let dim = vec2<i32>(textureDimensions(tex));
    let pos = vec2<i32>(i.clip.xy);
    let e = ld(pos, dim, vec2<i32>(0, 0));
    var c = e;
    if ((p.flags & 4u) != 0u) {
        // AMD's CAS: the sharpening weight shrinks where the 3x3 is already near black or white.
        let a = ld(pos, dim, vec2<i32>(-1, -1));
        let b = ld(pos, dim, vec2<i32>(0, -1));
        let cc = ld(pos, dim, vec2<i32>(1, -1));
        let d = ld(pos, dim, vec2<i32>(-1, 0));
        let f = ld(pos, dim, vec2<i32>(1, 0));
        let g = ld(pos, dim, vec2<i32>(-1, 1));
        let h = ld(pos, dim, vec2<i32>(0, 1));
        let ii = ld(pos, dim, vec2<i32>(1, 1));
        var mn = min(min(min(d, e), min(f, b)), h);
        mn = mn + min(mn, min(min(a, cc), min(g, ii)));
        var mx = max(max(max(d, e), max(f, b)), h);
        mx = mx + max(mx, max(max(a, cc), max(g, ii)));
        let amp = sqrt(clamp(min(mn, vec3<f32>(2.0) - mx) / max(mx, vec3<f32>(0.0001)), vec3<f32>(0.0), vec3<f32>(1.0)));
        let w = -amp * (p.sharpen * 0.2);
        c = clamp(((b + d + f + h) * w + e) / (4.0 * w + 1.0), vec3<f32>(0.0), vec3<f32>(1.0));
    }
    let bloom = (p.flags & 2u) != 0u;
    let tone = (p.flags & 1u) != 0u;
    if (bloom || tone) {
        var l = to_lin(c);
        if (bloom) { l += textureSampleLevel(tex2, samp, i.uv, 0.0).rgb * p.intensity; }
        if (tone) {
            // Narkowicz's ACES fit, with the input scaled 0.47 and the result divided by its value there so mid grey and
            // white stay put at exposure 1: a gentle S (deeper shadows, a firmer shoulder) rather than a darkening.
            let x = l * (0.47 * p.exposure);
            let y = (x * (2.51 * x + vec3<f32>(0.03))) / (x * (2.43 * x + vec3<f32>(0.59)) + vec3<f32>(0.14));
            l = y / 0.5963;
        }
        c = to_gam(clamp(l, vec3<f32>(0.0), vec3<f32>(1.0)));
    }
    if ((p.flags & 8u) != 0u) {
        c = clamp(mix(vec3<f32>(lum(c)), c, p.sat), vec3<f32>(0.0), vec3<f32>(1.0));
    }
    return vec4<f32>(c, 1.0);
}
"#;

pub(super) fn pipeline(device: &wgpu::Device, shader: &wgpu::ShaderModule, pl: &wgpu::PipelineLayout, entry: &str, format: wgpu::TextureFormat, blend: Option<wgpu::BlendState>) -> wgpu::RenderPipeline {
    device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: Some("post fx"),
        layout: Some(pl),
        vertex: wgpu::VertexState { module: shader, entry_point: Some("vs"), compilation_options: Default::default(), buffers: &[] },
        primitive: wgpu::PrimitiveState { cull_mode: None, ..Default::default() },
        depth_stencil: None,
        multisample: Default::default(),
        fragment: Some(wgpu::FragmentState {
            module: shader,
            entry_point: Some(entry),
            compilation_options: Default::default(),
            targets: &[Some(wgpu::ColorTargetState { format, blend, write_mask: wgpu::ColorWrites::ALL })],
        }),
        multiview_mask: None,
        cache: None,
    })
}

/// Bloom chain levels (half size down to 1/32).
const LEVELS: u32 = 5;

/// The chain's length for a first level of `half` pixels: down to 1 x 1 at most.
fn levels(half: [u32; 2]) -> u32 {
    (half[0].min(half[1]).ilog2() + 1).min(LEVELS)
}

struct Scratch {
    tex: wgpu::Texture,
    /// The plain (not sRGB) view: read and written as stored.
    view: wgpu::TextureView,
}

struct Chain {
    size: [u32; 2],
    /// Kept alive for its views.
    _tex: wgpu::Texture,
    /// One view a level, single-mip (a pass reads one level while writing another).
    views: Vec<wgpu::TextureView>,
}

struct Bloom {
    bright: wgpu::RenderPipeline,
    down: wgpu::RenderPipeline,
    up: wgpu::RenderPipeline,
    chain: Option<Chain>,
}

pub struct PostFx {
    shader: wgpu::ShaderModule,
    layout: wgpu::BindGroupLayout,
    pl: wgpu::PipelineLayout,
    sampler: wgpu::Sampler,
    uniform: wgpu::Buffer,
    /// The scene's plain format (what the passes write).
    format: wgpu::TextureFormat,
    fxaa: wgpu::RenderPipeline,
    composite: wgpu::RenderPipeline,
    /// Made when bloom is first on, dropped when it goes off.
    bloom: Option<Bloom>,
    /// FXAA's result when the composite follows it.
    mid: Option<Scratch>,
    /// `run`'s result texture and `in_place`'s copy of the scene.
    out: Option<Scratch>,
    copy: Option<Scratch>,
    /// Ambient occlusion and height fog (render/postdepth.rs): made when one is first on and the depth is given, dropped when
    /// both go off; they run first, and the rest reads their result.
    depthfx: Option<DepthFx>,
}

/// The PostFx for `cfg`: made on first need, dropped (with its textures) when every option is off, so an unused pass costs
/// nothing and the render path is the one without it.
pub fn ensure<'a>(slot: &'a mut Option<PostFx>, gpu: &Gpu, format: wgpu::TextureFormat, cfg: &GraphicsCfg) -> Option<&'a mut PostFx> {
    if !cfg.active() {
        *slot = None;
        return None;
    }
    let format = format.remove_srgb_suffix();
    if slot.as_ref().is_some_and(|p| p.format != format) {
        *slot = None;
    }
    let fx = slot.get_or_insert_with(|| PostFx::new(gpu, format));
    if !cfg.bloom_on() {
        fx.bloom = None;
    }
    if !cfg.depth_on() {
        fx.depthfx = None;
    }
    Some(fx)
}

impl PostFx {
    fn new(gpu: &Gpu, format: wgpu::TextureFormat) -> Self {
        let device = &gpu.device;
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor { label: Some("post fx"), source: wgpu::ShaderSource::Wgsl(SHADER.into()) });
        let tex_entry = |binding| wgpu::BindGroupLayoutEntry {
            binding,
            visibility: wgpu::ShaderStages::FRAGMENT,
            ty: wgpu::BindingType::Texture { sample_type: wgpu::TextureSampleType::Float { filterable: true }, view_dimension: wgpu::TextureViewDimension::D2, multisampled: false },
            count: None,
        };
        let layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("post fx"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: false, min_binding_size: None },
                    count: None,
                },
                tex_entry(1),
                wgpu::BindGroupLayoutEntry { binding: 2, visibility: wgpu::ShaderStages::FRAGMENT, ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering), count: None },
                tex_entry(3),
            ],
        });
        let pl = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: Some("post fx"), bind_group_layouts: &[Some(&layout)], immediate_size: 0 });
        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            ..Default::default()
        });
        let uniform = device.create_buffer(&wgpu::BufferDescriptor { label: Some("post fx"), size: 32, usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false });
        let fxaa = pipeline(device, &shader, &pl, "fxaa_fs", format, None);
        let composite = pipeline(device, &shader, &pl, "composite_fs", format, None);
        Self { shader, layout, pl, sampler, uniform, format, fxaa, composite, bloom: None, mid: None, out: None, copy: None, depthfx: None }
    }

    fn scratch(gpu: &Gpu, slot: &mut Option<Scratch>, label: &str, size: wgpu::Extent3d, format: wgpu::TextureFormat, usage: wgpu::TextureUsages) {
        if slot.as_ref().is_some_and(|s| s.tex.size() == size && s.tex.format() == format) {
            return;
        }
        let tex = gpu.device.create_texture(&wgpu::TextureDescriptor {
            label: Some(label),
            size,
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format,
            usage,
            view_formats: &[format.remove_srgb_suffix()],
        });
        let view = tex.create_view(&wgpu::TextureViewDescriptor { format: Some(format.remove_srgb_suffix()), ..Default::default() });
        *slot = Some(Scratch { tex, view });
    }

    /// The scene texture `scene` (a render target and sampled, as the scaling pass's) processed into a texture of this
    /// struct's own, at the same size and format; the scene texture is not touched. Read it through its default view.
    /// `depth`: the scene's depth and camera for the AO and fog; without it those two are skipped (the lobby has no camera).
    pub fn run(&mut self, gpu: &Gpu, enc: &mut wgpu::CommandEncoder, scene: &wgpu::Texture, cfg: &GraphicsCfg, depth: Option<DepthIn>) -> wgpu::Texture {
        let usage = wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_SRC;
        Self::scratch(gpu, &mut self.out, "post fx output", scene.size(), scene.format(), usage);
        let out = self.out.as_ref().unwrap();
        let (tex, view) = (out.tex.clone(), out.view.clone());
        self.apply(gpu, enc, scene, &view, cfg, depth);
        tex
    }

    /// As `run`, writing back over `tex` (which needs COPY_SRC and RENDER_ATTACHMENT), through a copy of it: for the offscreen
    /// shot tools.
    pub fn in_place(&mut self, gpu: &Gpu, enc: &mut wgpu::CommandEncoder, tex: &wgpu::Texture, cfg: &GraphicsCfg, depth: Option<DepthIn>) {
        Self::scratch(gpu, &mut self.copy, "post fx input", tex.size(), tex.format(), wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST);
        let copy = self.copy.as_ref().unwrap().tex.clone();
        enc.copy_texture_to_texture(tex.as_image_copy(), copy.as_image_copy(), tex.size());
        let view = tex.create_view(&wgpu::TextureViewDescriptor { format: Some(tex.format().remove_srgb_suffix()), ..Default::default() });
        self.apply(gpu, enc, &copy, &view, cfg, depth);
    }

    /// Whether the depth effects' pipelines and textures exist (tests).
    #[cfg(test)]
    pub fn has_depth_fx(&self) -> bool {
        self.depthfx.is_some()
    }

    /// The passes: `src` through its plain view into `dst` (a plain view of the same size).
    fn apply(&mut self, gpu: &Gpu, enc: &mut wgpu::CommandEncoder, src: &wgpu::Texture, dst: &wgpu::TextureView, cfg: &GraphicsCfg, depth: Option<DepthIn>) {
        let device = &gpu.device;
        let size = src.size();
        let plain = src.format().remove_srgb_suffix();
        let sv = src.create_view(&wgpu::TextureViewDescriptor { format: Some(plain), ..Default::default() });
        // AO and height fog first, over the scene as drawn; every pass after reads their result in its place.
        let sv = match depth.filter(|_| cfg.depth_on()) {
            Some(d) => self.depthfx.get_or_insert_with(|| DepthFx::new(gpu, plain)).run(gpu, enc, &sv, [size.width, size.height], d, cfg),
            // No depth this frame (a flash, a held frame): skipped, and kept for the next; `ensure` drops it with the option.
            None => sv,
        };
        let comp = cfg.composite_on();
        let half = [(size.width / 2).max(1), (size.height / 2).max(1)];
        let bloom = cfg.bloom_on();
        let flags = cfg.tonemap as u32 | (bloom as u32) << 1 | (cfg.sharpen_on() as u32) << 2 | (cfg.saturation_on() as u32) << 3;
        let clamp = |v: f32, lo: f32, hi: f32| if v.is_finite() { v.clamp(lo, hi) } else { lo };
        let params: [u32; 8] = [
            clamp(cfg.bloom_threshold, 0.0, 0.99).powf(2.2).to_bits(),
            (clamp(cfg.bloom_intensity, 0.0, 2.0) / levels(half) as f32).to_bits(),
            clamp(cfg.exposure, 0.25, 4.0).to_bits(),
            clamp(cfg.sharpen, 0.0, 1.0).to_bits(),
            clamp(cfg.saturation, 0.0, 2.0).to_bits(),
            flags,
            0,
            0,
        ];
        gpu.queue.put(&self.uniform, 0, bytemuck::cast_slice(&params));
        let group = |a: &wgpu::TextureView, b: &wgpu::TextureView| {
            device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("post fx"),
                layout: &self.layout,
                entries: &[
                    wgpu::BindGroupEntry { binding: 0, resource: self.uniform.as_entire_binding() },
                    wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(a) },
                    wgpu::BindGroupEntry { binding: 2, resource: wgpu::BindingResource::Sampler(&self.sampler) },
                    wgpu::BindGroupEntry { binding: 3, resource: wgpu::BindingResource::TextureView(b) },
                ],
            })
        };
        let draw = |enc: &mut wgpu::CommandEncoder, target: &wgpu::TextureView, load: wgpu::LoadOp<wgpu::Color>, pipe: &wgpu::RenderPipeline, g: &wgpu::BindGroup| {
            let mut pass = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("post fx"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment { view: target, depth_slice: None, resolve_target: None, ops: wgpu::Operations { load, store: wgpu::StoreOp::Store } })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });
            pass.set_pipeline(pipe);
            pass.set_bind_group(0, g, &[]);
            pass.draw(0..3, 0..1);
        };
        let clear = wgpu::LoadOp::Clear(wgpu::Color::BLACK);

        // Bloom: the bright pass into the first level, down the chain, then back up adding.
        let mut bloom_view = None;
        if bloom {
            if self.bloom.is_none() {
                let add = wgpu::BlendComponent { src_factor: wgpu::BlendFactor::One, dst_factor: wgpu::BlendFactor::One, operation: wgpu::BlendOperation::Add };
                let f = wgpu::TextureFormat::Rgba16Float;
                let mk = |entry, blend| pipeline(device, &self.shader, &self.pl, entry, f, blend);
                self.bloom = Some(Bloom { bright: mk("bright_fs", None), down: mk("down_fs", None), up: mk("up_fs", Some(wgpu::BlendState { color: add, alpha: add })), chain: None });
            }
            let b = self.bloom.as_mut().unwrap();
            if b.chain.as_ref().is_none_or(|c| c.size != half) {
                let levels = levels(half);
                let tex = device.create_texture(&wgpu::TextureDescriptor {
                    label: Some("post fx bloom"),
                    size: wgpu::Extent3d { width: half[0], height: half[1], depth_or_array_layers: 1 },
                    mip_level_count: levels,
                    sample_count: 1,
                    dimension: wgpu::TextureDimension::D2,
                    format: wgpu::TextureFormat::Rgba16Float,
                    usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
                    view_formats: &[],
                });
                let views = (0..levels).map(|l| tex.create_view(&wgpu::TextureViewDescriptor { base_mip_level: l, mip_level_count: Some(1), ..Default::default() })).collect();
                b.chain = Some(Chain { size: half, _tex: tex, views });
            }
            let b = self.bloom.as_ref().unwrap();
            let chain = b.chain.as_ref().unwrap();
            draw(enc, &chain.views[0], clear, &b.bright, &group(&sv, &sv));
            for l in 1..chain.views.len() {
                draw(enc, &chain.views[l], clear, &b.down, &group(&chain.views[l - 1], &chain.views[l - 1]));
            }
            for l in (0..chain.views.len().saturating_sub(1)).rev() {
                draw(enc, &chain.views[l], wgpu::LoadOp::Load, &b.up, &group(&chain.views[l + 1], &chain.views[l + 1]));
            }
            bloom_view = Some(chain.views[0].clone());
        }

        let fxaa = cfg.fxaa;
        if fxaa && comp {
            Self::scratch(gpu, &mut self.mid, "post fx mid", size, plain, wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING);
            let mid = self.mid.as_ref().unwrap().view.clone();
            draw(enc, &mid, clear, &self.fxaa, &group(&sv, &sv));
            draw(enc, dst, clear, &self.composite, &group(&mid, bloom_view.as_ref().unwrap_or(&mid)));
        } else if fxaa {
            draw(enc, dst, clear, &self.fxaa, &group(&sv, &sv));
        } else {
            draw(enc, dst, clear, &self.composite, &group(&sv, bloom_view.as_ref().unwrap_or(&sv)));
        }
        if !(fxaa && comp) {
            self.mid = None;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FMT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8Unorm;

    fn texture(gpu: &Gpu, w: u32, h: u32, f: impl Fn(u32, u32) -> [u8; 3]) -> wgpu::Texture {
        let tex = gpu.device.create_texture(&wgpu::TextureDescriptor {
            label: None,
            size: wgpu::Extent3d { width: w, height: h, depth_or_array_layers: 1 },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: FMT,
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_SRC | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        });
        let f = &f;
        let data: Vec<u8> = (0..h).flat_map(|y| (0..w).flat_map(move |x| { let c = f(x, y); [c[0], c[1], c[2], 255] })).collect();
        gpu.queue.write_texture(tex.as_image_copy(), &data, wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(w * 4), rows_per_image: Some(h) }, wgpu::Extent3d { width: w, height: h, depth_or_array_layers: 1 });
        tex
    }

    fn read(gpu: &Gpu, tex: &wgpu::Texture) -> Vec<[u8; 3]> {
        let (w, h) = (tex.width(), tex.height());
        let row = (w * 4).div_ceil(256) * 256;
        let buf = gpu.device.create_buffer(&wgpu::BufferDescriptor { label: None, size: (row * h) as u64, usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ, mapped_at_creation: false });
        let mut enc = gpu.device.create_command_encoder(&Default::default());
        enc.copy_texture_to_buffer(
            tex.as_image_copy(),
            wgpu::TexelCopyBufferInfo { buffer: &buf, layout: wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(row), rows_per_image: Some(h) } },
            wgpu::Extent3d { width: w, height: h, depth_or_array_layers: 1 },
        );
        gpu.queue.submit([enc.finish()]);
        buf.slice(..).map_async(wgpu::MapMode::Read, |_| {});
        gpu.device.poll(wgpu::PollType::Wait { submission_index: None, timeout: None }).unwrap();
        let d = buf.slice(..).get_mapped_range().unwrap();
        (0..h)
            .flat_map(|y| (0..w).map(move |x| (y, x)))
            .map(|(y, x)| {
                let o = (y * row + x * 4) as usize;
                [d[o], d[o + 1], d[o + 2]]
            })
            .collect()
    }

    /// `src` run through the post pass with `cfg`, as pixels (the scene texture itself is left as drawn).
    fn run(gpu: &Gpu, src: &wgpu::Texture, cfg: &GraphicsCfg) -> Vec<[u8; 3]> {
        let mut slot = None;
        let fx = ensure(&mut slot, gpu, FMT, cfg).expect("an option is on");
        let mut enc = gpu.device.create_command_encoder(&Default::default());
        let out = fx.run(gpu, &mut enc, src, cfg, None);
        gpu.queue.submit([enc.finish()]);
        read(gpu, &out)
    }

    fn gpu() -> Option<Gpu> {
        let g = Gpu::headless().ok();
        if g.is_none() {
            eprintln!("no GPU adapter: post fx pixel tests skipped");
        }
        g
    }

    fn near(a: [u8; 3], b: [u8; 3], tol: i32) -> bool {
        (0..3).all(|i| (a[i] as i32 - b[i] as i32).abs() <= tol)
    }

    /// Every option off keeps no PostFx (no pipeline, no texture); on makes it, off again drops it.
    #[test]
    fn nothing_made_while_off() {
        let Some(gpu) = gpu() else { return };
        let mut slot = None;
        assert!(ensure(&mut slot, &gpu, FMT, &GraphicsCfg::default()).is_none() && slot.is_none());
        // Options that do nothing (bloom at zero, sharpen 0, saturation 1) count as off.
        assert!(ensure(&mut slot, &gpu, FMT, &GraphicsCfg { bloom: true, bloom_intensity: 0.0, ..Default::default() }).is_none());
        assert!(ensure(&mut slot, &gpu, FMT, &GraphicsCfg { fxaa: true, ..Default::default() }).is_some() && slot.is_some());
        assert!(ensure(&mut slot, &gpu, FMT, &GraphicsCfg::default()).is_none() && slot.is_none());
    }

    /// A flat colour comes out as it went in through every option; saturation 0 is grey; the tone curve keeps mid grey and
    /// white.
    #[test]
    fn flat_and_grades() {
        let Some(gpu) = gpu() else { return };
        let flat = texture(&gpu, 16, 16, |_, _| [153, 102, 51]);
        let all = GraphicsCfg { fxaa: true, bloom: true, sharpen: 1.0, ..Default::default() };
        for (name, cfg) in [("fxaa", GraphicsCfg { fxaa: true, ..Default::default() }), ("sharpen", GraphicsCfg { sharpen: 1.0, ..Default::default() }), ("bloom", GraphicsCfg { bloom: true, ..Default::default() }), ("all", all)] {
            for p in run(&gpu, &flat, &cfg) {
                assert!(near(p, [153, 102, 51], 2), "{name}: {p:?}");
            }
        }
        for p in run(&gpu, &flat, &GraphicsCfg { saturation: 0.0, ..Default::default() }) {
            assert!(near([p[0], p[0], p[0]], p, 1), "{p:?}");
        }
        let grey = texture(&gpu, 4, 4, |x, _| if x < 2 { [128, 128, 128] } else { [255, 255, 255] });
        let out = run(&gpu, &grey, &GraphicsCfg { tonemap: true, ..Default::default() });
        assert!(near(out[0], [128, 128, 128], 4) && near(out[3], [255, 255, 255], 2), "{:?} {:?}", out[0], out[3]);
        // Exposure up brightens.
        let out = run(&gpu, &grey, &GraphicsCfg { tonemap: true, exposure: 2.0, ..Default::default() });
        assert!(out[0][0] > 150, "{:?}", out[0]);
    }

    /// FXAA softens a hard stair edge but leaves the flat areas; sharpening makes a step steeper.
    #[test]
    fn fxaa_and_cas_change_edges_only() {
        let Some(gpu) = gpu() else { return };
        let stair = texture(&gpu, 16, 16, |x, y| if x > y + 3 { [255, 255, 255] } else { [20, 20, 20] });
        let before = read(&gpu, &stair);
        let out = run(&gpu, &stair, &GraphicsCfg { fxaa: true, ..Default::default() });
        let changed = out.iter().zip(&before).filter(|(a, b)| !near(**a, **b, 2)).count();
        assert!(changed > 0, "fxaa left the stair as it was");
        assert_eq!(out[0], before[0]);
        assert_eq!(out[15 * 16], before[15 * 16]);
        assert_eq!(out[15], before[15]);
        let step = texture(&gpu, 16, 4, |x, _| if x < 8 { [100; 3] } else { [160; 3] });
        let s = run(&gpu, &step, &GraphicsCfg { sharpen: 1.0, ..Default::default() });
        assert!(s[7][0] < 100 && s[8][0] > 160, "{:?} {:?}", s[7], s[8]);
    }

    /// Bloom spreads a bright block's light onto the dark around it; with nothing over the threshold the picture is as it was.
    #[test]
    fn bloom_spreads_light() {
        let Some(gpu) = gpu() else { return };
        let block = texture(&gpu, 64, 64, |x, y| if (28..36).contains(&x) && (28..36).contains(&y) { [255; 3] } else { [0; 3] });
        let on = run(&gpu, &block, &GraphicsCfg { bloom: true, bloom_intensity: 1.0, bloom_threshold: 0.5, ..Default::default() });
        assert!(on[32 * 64 + 40][0] > 8, "{:?}", on[32 * 64 + 40]);
        assert!(on[32 * 64 + 32][0] >= 250, "the block itself stays bright");
        assert!(on[0][0] <= on[32 * 64 + 40][0]);
        let dim = texture(&gpu, 64, 64, |_, _| [60; 3]);
        for p in run(&gpu, &dim, &GraphicsCfg { bloom: true, bloom_threshold: 0.5, ..Default::default() }) {
            assert!(near(p, [60; 3], 2), "{p:?}");
        }
    }
}
