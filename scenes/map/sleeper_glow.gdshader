// Подсветка участка карты-плана (docs/18): участок «загорается» — картинка светлеет снизу вверх, по краю — ореол.
// glow — цвет света (серебро — куда можно поставить фигуру, золото — участок под фигурой, красный — нельзя),
// amount 0..1 — сила, dim — притушить (участок, куда нельзя).
shader_type canvas_item;

uniform vec4 glow : source_color = vec4(0.85, 0.9, 1.0, 1.0);
uniform float amount = 0.0;
uniform float dim = 0.0;
uniform float halo_px = 6.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float pulse = 0.82 + 0.18 * sin(TIME * 3.2);
	float k = amount * pulse;
	// внутри: светлеет, сильнее снизу (свет поднимается от земли)
	float rise = mix(0.55, 1.0, UV.y);
	vec3 lit = c.rgb * (1.0 + 0.45 * k * rise) + glow.rgb * 0.14 * k * rise;
	lit = mix(lit, lit * vec3(0.55, 0.35, 0.35), dim);
	// ореол: прозрачные пиксели рядом с непрозрачными — свет по краю участка
	float halo = 0.0;
	vec2 px = TEXTURE_PIXEL_SIZE * halo_px;
	for (int i = 0; i < 12; i++) {
		float a = 6.2831853 * float(i) / 12.0;
		halo = max(halo, texture(TEXTURE, UV + vec2(cos(a), sin(a)) * px).a);
	}
	float edge = halo * (1.0 - c.a) * k;
	COLOR = vec4(mix(lit, glow.rgb, edge), max(c.a, edge * 0.85));
}
