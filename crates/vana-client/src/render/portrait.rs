//! A Lua HUD portrait's finish (client/portrait.rs), after the actor is drawn into its target: the target cut to the
//! oval inscribed in it, then a frame ring round the edge (oval or square). Premultiplied, gamma-encoded as the scene.

use super::Gpu;
use super::Put;

const SHADER: &str = r#"
// size: the target in pixels; frame_w: the ring's width in pixels; oval: 1 or 0; frame: premultiplied colour.
struct U { size: vec2<f32>, frame_w: f32, oval: f32, frame: vec4<f32> };
@group(0) @binding(0) var<uniform> u: U;
struct VOut { @builtin(position) clip: vec4<f32>, @location(0) uv: vec2<f32> };
@vertex fn vs(@builtin(vertex_index) i: u32) -> VOut {
    let p = vec2<f32>(f32((i << 1u) & 2u), f32(i & 2u));
    var o: VOut;
    o.clip = vec4<f32>(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = vec2<f32>(p.x, 1.0 - p.y);
    return o;
}
// Pixels to the edge, negative inside (for the oval the first-order distance to the ellipse).
fn edge(uv: vec2<f32>) -> f32 {
    let r = u.size * 0.5;
    let q = (uv - 0.5) * u.size;
    if (u.oval < 0.5) {
        let d = abs(q) - r;
        return max(d.x, d.y);
    }
    let k = length(q / r);
    let g = length(q / (r * r));
    return (k - 1.0) * k / max(g, 1e-4);
}
const AA: f32 = 1.5;
// Blend ZERO / SRCALPHA: everything outside the oval goes.
@fragment fn mask(i: VOut) -> @location(0) vec4<f32> {
    return vec4<f32>(0.0, 0.0, 0.0, clamp(0.5 - edge(i.uv) / AA, 0.0, 1.0));
}
// Premultiplied over: the ring, rounded across its width and lit from above.
@fragment fn ring(i: VOut) -> @location(0) vec4<f32> {
    let d = edge(i.uv);
    let w = max(u.frame_w, 1.0);
    let cover = clamp((d + w) / AA + 0.5, 0.0, 1.0) * clamp(0.5 - d / AA, 0.0, 1.0);
    let t = (d + w * 0.5) / (w * 0.5);
    let shade = (1.15 - 0.35 * i.uv.y) * (1.0 - 0.35 * t * t);
    return vec4<f32>(min(u.frame.rgb * shade, vec3<f32>(u.frame.a)), u.frame.a) * cover;
}
"#;

/// How a portrait is finished: cut to an oval, and its frame (premultiplied colour, width in target pixels).
#[derive(Clone, Copy, PartialEq, Debug)]
pub struct Finish {
    pub oval: bool,
    pub frame: Option<[f32; 4]>,
    pub frame_px: f32,
}

pub struct PortraitFinish {
    mask: wgpu::RenderPipeline,
    ring: wgpu::RenderPipeline,
    layout: wgpu::BindGroupLayout,
    /// Each portrait slot's uniforms.
    slots: Vec<(wgpu::Buffer, wgpu::BindGroup)>,
}

impl PortraitFinish {
    pub fn new(gpu: &Gpu, format: wgpu::TextureFormat) -> Self {
        let device = &gpu.device;
        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("portrait finish"),
            source: wgpu::ShaderSource::Wgsl(SHADER.into()),
        });
        let layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("portrait finish"),
            entries: &[wgpu::BindGroupLayoutEntry {
                binding: 0,
                visibility: wgpu::ShaderStages::FRAGMENT,
                ty: wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Uniform,
                    has_dynamic_offset: false,
                    min_binding_size: None,
                },
                count: None,
            }],
        });
        let pl = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: Some("portrait finish"),
            bind_group_layouts: &[Some(&layout)],
            immediate_size: 0,
        });
        let pipe = |entry: &str, blend: wgpu::BlendState| {
            device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some("portrait finish"),
                layout: Some(&pl),
                vertex: wgpu::VertexState {
                    module: &shader,
                    entry_point: Some("vs"),
                    compilation_options: Default::default(),
                    buffers: &[],
                },
                primitive: Default::default(),
                depth_stencil: None,
                multisample: Default::default(),
                fragment: Some(wgpu::FragmentState {
                    module: &shader,
                    entry_point: Some(entry),
                    compilation_options: Default::default(),
                    targets: &[Some(wgpu::ColorTargetState {
                        format,
                        blend: Some(blend),
                        write_mask: wgpu::ColorWrites::ALL,
                    })],
                }),
                multiview_mask: None,
                cache: None,
            })
        };
        let keep = wgpu::BlendComponent {
            src_factor: wgpu::BlendFactor::Zero,
            dst_factor: wgpu::BlendFactor::SrcAlpha,
            operation: wgpu::BlendOperation::Add,
        };
        let mask = pipe("mask", wgpu::BlendState { color: keep, alpha: keep });
        let ring = pipe("ring", wgpu::BlendState::PREMULTIPLIED_ALPHA_BLENDING);
        Self { mask, ring, layout, slots: Vec::new() }
    }

    /// Finishes slot `slot`'s target `view` of `size` pixels.
    pub fn run(
        &mut self,
        gpu: &Gpu,
        encoder: &mut wgpu::CommandEncoder,
        slot: usize,
        view: &wgpu::TextureView,
        size: [u32; 2],
        f: Finish,
    ) {
        if !f.oval && f.frame.is_none() {
            return;
        }
        while self.slots.len() <= slot {
            let buf = gpu.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("portrait finish"),
                size: 32,
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });
            let group = gpu.device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("portrait finish"),
                layout: &self.layout,
                entries: &[wgpu::BindGroupEntry { binding: 0, resource: buf.as_entire_binding() }],
            });
            self.slots.push((buf, group));
        }
        let (buf, group) = &self.slots[slot];
        let c = f.frame.unwrap_or([0.0; 4]);
        gpu.queue.put(
            buf,
            0,
            bytemuck::cast_slice(&[
                size[0] as f32,
                size[1] as f32,
                f.frame_px,
                f.oval as u32 as f32,
                c[0],
                c[1],
                c[2],
                c[3],
            ]),
        );
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some("portrait finish"),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view,
                depth_slice: None,
                resolve_target: None,
                ops: wgpu::Operations { load: wgpu::LoadOp::Load, store: wgpu::StoreOp::Store },
            })],
            depth_stencil_attachment: None,
            timestamp_writes: None,
            occlusion_query_set: None,
            multiview_mask: None,
        });
        pass.set_bind_group(0, group, &[]);
        if f.oval {
            pass.set_pipeline(&self.mask);
            pass.draw(0..3, 0..1);
        }
        if f.frame.is_some() {
            pass.set_pipeline(&self.ring);
            pass.draw(0..3, 0..1);
        }
    }
}
