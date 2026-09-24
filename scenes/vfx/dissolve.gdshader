// Распад карты в пепел: область сгорает по шуму снизу вверх,
// на границе — раскалённая кромка, за ней обугленная бумага.
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 card_size = vec2(140.0, 240.0);
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec4 edge_color : source_color = vec4(1.0, 0.42, 0.10, 1.0);
uniform vec4 char_color : source_color = vec4(0.05, 0.04, 0.04, 1.0);
uniform float edge_width = 0.07;

varying vec2 local_uv;

void vertex() {
	local_uv = VERTEX / card_size;
}

void fragment() {
	vec4 c = COLOR;
	float n = texture(noise_tex, local_uv * vec2(1.0, card_size.y / card_size.x) * 0.8).r;
	float t = n * 0.7 + (1.0 - clamp(local_uv.y, 0.0, 1.0)) * 0.3;
	float p = progress * 1.12;
	if (t < p) {
		discard;
	}
	float edge = 1.0 - smoothstep(p, p + edge_width, t);
	float char_amt = clamp(progress * 1.6 - (t - p) * 2.5, 0.0, 0.92);
	vec3 rgb = mix(c.rgb, char_color.rgb, char_amt);
	rgb = mix(rgb, edge_color.rgb * 1.8, edge);
	COLOR = vec4(rgb, c.a);
}
