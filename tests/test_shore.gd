extends TestCase
## Ф13: глава «Забытый Берег» — переход из Академии, Санни один до SH22, небо шторма.


func test_transition() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 21)
	for cid: String in ["P02", "P03", "P04"]:
		EffectApplier.add_card(c, s, cid)
	s.characters["P04"]["bought"] = true
	var ma18: Dictionary = c.missions["MA18"]
	eq(str(ma18.get("next_chapter", "")), "shore", "после Академии — Берег:")
	EffectApplier.apply_all(c, s, ma18.get("on_complete", []), "P01", RandomNumberGenerator.new())
	check(not s.owns("P02") and not s.owns("P03"), "Нефис и Касси уходят (по книге)")
	check(s.owns("P04"), "купленный Кастер остаётся (решение владельца)")
	MissionFlow.start_chapter(c, s, "shore")
	eq(s.region, "forgotten_shore", "регион Берега:")
	check(MissionFlow.open_missions(s).has("SH19"), "глава начинается с «Беззвёздной Пустоты»")
	EffectApplier.apply_all(c, s, c.missions["SH22"].get("on_complete", []), "P01", RandomNumberGenerator.new())
	check(s.owns("P02") and s.owns("P03"), "в SH22 Нефис и Касси возвращаются")


func test_storm_sky() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 21)
	MissionFlow.start_chapter(c, s, "shore")
	MissionFlow.open(c, s, "SH27")
	eq(Atmosphere.sky(c, s), "storm", "шторм над Берегом, пока открыт SH27:")
	var parts := Atmosphere.check_parts(c, s, ["climb"])
	check(parts.size() == 1 and int(parts[0]["value"]) < 0, "шторм мешает подъёму")
	check(not OnslaughtRules.config(c, "shore").is_empty(), "у Берега свои натиски")
