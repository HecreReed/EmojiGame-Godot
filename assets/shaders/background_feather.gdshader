shader_type canvas_item;

uniform float fade_frac : hint_range(0.0, 0.5) = 0.06;
uniform float fade_side : hint_range(-1.0, 1.0) = 0.0; // -1: fade left edge, +1: fade right edge

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float a = 1.0;
	float f = max(fade_frac, 0.0001);

	if (fade_side < -0.5) {
		float t = clamp(UV.x / f, 0.0, 1.0);
		a *= smoothstep(0.0, 1.0, t);
	} else if (fade_side > 0.5) {
		float t = clamp((1.0 - UV.x) / f, 0.0, 1.0);
		a *= smoothstep(0.0, 1.0, t);
	}

	COLOR = vec4(c.rgb, c.a * a);
}

