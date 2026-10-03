shader_type canvas_item;
// Туман неизвестного на «Карте Спящего»: бумага с дымкой поверх всего, кроме открытого.
// Открыто: круги мест (holes) и коридоры между открытыми соседями (segs — тропа или места рядом; просьба владельца
// 03.10: открытые места сливаются в одну область, без тёмных перемычек). Круги и коридоры сливаются мягко (smooth max).

uniform sampler2D fog_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 holes[48];      // xy — центр (доли основы), z — радиус (доли высоты основы), w — 0..1 (проявление)
uniform int hole_count = 0;
uniform vec4 segs[64];       // xy — один конец, zw — другой (доли основы)
uniform vec2 seg_w[64];      // x — полуширина коридора (доли высоты основы), y — 0..1 (проявление)
uniform int seg_count = 0;
uniform float aspect = 2.0;
uniform float density = 0.86;

float smax(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(a, b, h) + k * h * (1.0 - h);
}

void fragment() {
	float clear = 0.0;
	for (int i = 0; i < hole_count; i++) {
		vec4 hl = holes[i];
		vec2 dd = UV - hl.xy;
		dd.x *= aspect;
		float r = hl.z * hl.w;
		clear = smax(clear, 1.0 - smoothstep(r * 0.55, r, length(dd)), 0.12);
	}
	for (int j = 0; j < seg_count; j++) {
		vec4 sg = segs[j];
		vec2 a = sg.xy;
		vec2 b = sg.zw;
		vec2 pa = UV - a;
		vec2 ba = b - a;
		pa.x *= aspect;
		ba.x *= aspect;
		float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
		float d = length(pa - ba * h);
		float r = seg_w[j].x * seg_w[j].y;
		clear = smax(clear, 1.0 - smoothstep(r * 0.45, r, d), 0.12);
	}
	clear = clamp(clear, 0.0, 1.0);
	vec2 fuv = UV * vec2(2.2 * aspect, 2.2);
	vec3 f = texture(fog_tex, fuv + vec2(TIME * 0.004, -TIME * 0.002)).rgb;
	vec3 f2 = texture(fog_tex, fuv * 0.6 + vec2(-TIME * 0.003, TIME * 0.0015)).rgb;
	vec3 col = mix(f, f2, 0.5) * 0.4;
	// у кромки открытого — тушь дорисовывается: тёмная линия
	float edge = smoothstep(0.08, 0.35, clear) * (1.0 - smoothstep(0.35, 0.8, clear));
	col = mix(col, vec3(0.07, 0.07, 0.09), edge * 0.6);
	COLOR = vec4(col, (1.0 - clear) * density);
}
