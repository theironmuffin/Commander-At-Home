shader_type spatial;
render_mode cull_disabled;

uniform sampler2D front_tex : source_color, filter_linear_mipmap;
uniform sampler2D back_tex : source_color, filter_linear_mipmap;
uniform bool outline_active = false;

void fragment() {
    // 1. Rounded-corner SDF in actual card dimensions (0.635 x 0.889)
    vec2 card_size = vec2(0.635, 0.889);
    float corner_radius = 0.032; // ~3.2mm (real MTG corner radius)
    vec2 p = (UV - 0.5) * card_size;
    vec2 half_size = card_size * 0.5 - vec2(corner_radius);
    vec2 d = abs(p) - half_size;
    float dist = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - corner_radius;

    if (dist > 0.0) {
        discard;
    }

    vec2 uv = UV;
    if (FRONT_FACING) {
        ALBEDO = texture(front_tex, uv).rgb;
    } else {
        uv.x = 1.0 - uv.x;
        ALBEDO = texture(back_tex, uv).rgb;
    }

    if (outline_active && dist > -0.016) {
        ALBEDO = vec3(1.0, 0.85, 0.25);
        EMISSION = vec3(0.8, 0.65, 0.15);
    }
}