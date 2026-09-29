shader_type canvas_item;
// Туман неизвестного на «Карте Спящего»: бумага с дымкой поверх всего, кроме открытых мест (круги holes).

uniform sampler2D fog_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 holes[40];      // xy — центр (доли основы), z — радиус (доли высоты основы), w — 0..1 (проявление)
uniform int hole_count = 0;
uniform float aspect = 2.0;
uniform float density = 0.86;

void fragment() {
	float clear = 0.0;
	for (int i = 0; i < hole_count; i++) {
		vec4 hl = holes[i];
		vec2 dd = UV - hl.xy;
		dd.x *= aspect;
		float r = hl.z * hl.w;
		clear = max(clear, 1.0 - smoothstep(r * 0.55, r, length(dd)));
	}
	vec2 fuv = UV * vec2(2.2 * aspect, 2.2);
	vec3 f = texture(fog_tex, fuv + vec2(TIME * 0.004, -TIME * 0.002)).rgb;
	vec3 f2 = texture(fog_tex, fuv * 0.6 + vec2(-TIME * 0.003, TIME * 0.0015)).rgb;
	vec3 col = mix(f, f2, 0.5) * 0.4;
	// у кромки открытого — тушь дорисовывается: тёмная линия
	float edge = smoothstep(0.08, 0.35, clear) * (1.0 - smoothstep(0.35, 0.8, clear));
	col = mix(col, vec3(0.07, 0.07, 0.09), edge * 0.6);
	COLOR = vec4(col, (1.0 - clear) * density);
}
