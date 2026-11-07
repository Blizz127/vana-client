-- The world's look (the render tweak add-ons): brightness and colour, cel shading (colour in bands, outlines where
-- the depth jumps) as one post pass; wireframe through the client's switch.

local WGSL = [[
fn view_dist(d: f32) -> f32 {
  return 0.1 * 2000.0 / (2000.0 - d * 1999.9);
}

@fragment fn fs_main(in: VsOut) -> @location(0) vec4<f32> {
  let c = textureSample(scene, samp, in.uv);
  let l = dot(c.rgb, vec3<f32>(0.299, 0.587, 0.114));
  var rgb = mix(vec3<f32>(l), c.rgb, post.p[0].y) * post.p[0].x;
  if (post.p[0].z > 0.5) {
    // Brightness in bands, the hue kept.
    let lb = dot(rgb, vec3<f32>(0.299, 0.587, 0.114));
    let lq = (floor(lb * 4.0) + 0.5) / 4.0;
    rgb = rgb * (lq / max(lb, 0.02));
    // Outlines where the depth jumps against the pixels around.
    let p = vec2<i32>(in.pos.xy);
    let d0 = view_dist(textureLoad(depth, p, 0));
    var jump = 0.0;
    for (var i = 0; i < 4; i = i + 1) {
      let o = array<vec2<i32>, 4>(vec2<i32>(2, 0), vec2<i32>(-2, 0), vec2<i32>(0, 2), vec2<i32>(0, -2))[i];
      jump = max(jump, view_dist(textureLoad(depth, p + o, 0)) - d0);
    }
    if (jump / max(d0, 0.5) > 0.12 && d0 < 300.0) {
      rgb = rgb * 0.1;
    }
  }
  return vec4<f32>(rgb, c.a);
}
]]

local loaded = false

local function apply()
  local on = settings.get("on")
  local plain = settings.get("brightness") == 1 and settings.get("saturation") == 1 and not settings.get("toon")
  if on and not plain then
    if not loaded then
      render.shader("look", WGSL)
      loaded = true
    end
    render.shader_params("look", { { settings.get("brightness"), settings.get("saturation"),
      settings.get("toon") and 1 or 0, 0 } })
  elseif loaded then
    render.shader("look", nil)
    loaded = false
  end
  client.set_option("wireframe", on and settings.get("wireframe") or false)
end

apply()
events.on("settings_changed", apply)
