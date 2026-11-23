shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D front_tex : source_color, filter_linear_mipmap;
uniform sampler2D back_tex : source_color, filter_linear_mipmap;
uniform bool outline_active = false;
uniform bool playable_sheen = false;
uniform float foil_amount : hint_range(0.0, 1.0) = 0.0;
uniform float corner_radius : hint_range(0.0, 0.25) = 0.045;

float rounded_box_sdf(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

vec3 rainbow_hue(float t) {
	vec3 c = vec3(0.0, 0.33, 0.67);
	return 0.5 + 0.5 * cos(6.28318 * (t + c));
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = rounded_box_sdf(centered, vec2(0.5), corner_radius);
	if (dist > 0.0) {
		discard;
	}

	vec4 tex_col = FRONT_FACING ? texture(front_tex, UV) : texture(back_tex, vec2(1.0 - UV.x, UV.y));
	vec3 final_col = tex_col.rgb;
	vec3 emit_col = vec3(0.0);

	if (FRONT_FACING && foil_amount > 0.01) {
		float view_ang = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
		float band = UV.x * 1.45 + UV.y * 0.95 + view_ang * 1.1 + TIME * 0.28;
		vec3 holo = rainbow_hue(band);
		float shimmer = pow(0.5 + 0.5 * sin(band * 6.28318), 2.0);
		float mask = clamp(0.18 + 0.42 * view_ang + 0.25 * shimmer, 0.0, 0.65) * foil_amount;
		final_col = mix(final_col, final_col * 0.88 + holo * 0.48, mask);
		emit_col += holo * (0.14 * shimmer + 0.12 * view_ang) * foil_amount;
		ROUGHNESS = mix(0.45, 0.14, foil_amount);
		METALLIC = mix(0.0, 0.42, foil_amount);
	} else {
		ROUGHNESS = 0.45;
		METALLIC = 0.0;
	}

	if (playable_sheen && FRONT_FACING) {
		float pulse = 0.72 + 0.28 * sin(TIME * 3.4);
		vec3 gold = vec3(1.0, 0.82, 0.22);
		float sweep = fract(TIME * 0.42);
		float diag = (UV.x * 0.65 + UV.y * 0.35);
		float glint = exp(-pow((diag - sweep) * 7.5, 2.0)) * 0.28;
		if (dist > -0.022) {
			final_col = mix(final_col, gold, 0.72 * pulse);
			emit_col += gold * (0.75 * pulse);
		} else if (glint > 0.01) {
			final_col = mix(final_col, gold, glint * 0.55);
			emit_col += gold * glint;
		}
	}

	if (outline_active && dist > -0.022) {
		vec3 glow = vec3(1.0, 0.85, 0.25);
		final_col = mix(final_col, glow, 0.75);
		emit_col += glow * 0.8;
	}

	ALBEDO = final_col;
	EMISSION = emit_col;
}
