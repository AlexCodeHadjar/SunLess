extends TestCase
## Данные проходят проверку; характеристики героя считаются верно.


func test_data_is_valid() -> void:
	var errors := ContentValidator.validate(content())
	for e in errors:
		check(false, e)


func test_no_old_mode_leftovers() -> void:
	check(not DirAccess.dir_exists_absolute("res://data/events"), "старых событий по неделям больше нет")
	check(not FileAccess.file_exists("res://data/chapters.json"), "Хроники глав больше нет — места живут в locations.json")
	var s := MissionFlow.new_run(content(), 1)
	check(not s.resources.has("mana"), "маны нет")


func test_stat_resolver_basics() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 1)
	var ev := {"id": "MS03", "tags": ["combat", "survival"]}
	var o := {"id": "MS03_fight", "tags": ["survival"]}
	var r := StatResolver.resolve(c, s, "P01", [], ev, o)
	eq(r["totals"], {"power": 3, "will": 5, "cunning": 6}, "Санни-раб:")
	EffectApplier.add_card(c, s, "U01")
	r = StatResolver.resolve(c, s, "P01", ["U01"], ev, o)
	eq(r["totals"]["power"], 5, "с U01 Сила:")
	eq(r["totals"]["cunning"], 7, "U01 даёт +1 Хитрость в выживании:")
	s.characters["P01"]["traumas"].append("T02")
	r = StatResolver.resolve(c, s, "P01", ["U01"], ev, o)
	eq(r["totals"]["power"], 4, "с Рваной раной:")


func test_trait_by_tag() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 1)
	var r := StatResolver.resolve(c, s, "P01", [], {"id": "MS09", "tags": ["duel", "lure"]}, {"id": "MS09_bell", "tags": ["lure"]})
	eq(r["totals"]["cunning"], 7, "«Дитя Теней» +1 в приманке:")


func test_bell_does_not_wear_in_nightmare() -> void:
	var c := content()
	var s := MissionFlow.new_run(c, 1)
	EffectApplier.add_card(c, s, "U02")
	check(not WearRules.wears(c, s, "U02"), "Колокольчик не изнашивается в Первом Кошмаре")
	s.chapter = "academy"
	check(WearRules.wears(c, s, "U02"), "в Академии — изнашивается")


## Все скрипты игры компилируются (ловит ссылки на удалённое — например, старый режим).
func test_all_scripts_compile() -> void:
	var bad: Array = []
	for dir: String in ["res://autoload", "res://core", "res://scenes", "res://ui", "res://tools"]:
		_collect_bad(dir, bad)
	eq(bad, [], "скрипты с ошибками:")


func _collect_bad(dir: String, bad: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub: String in d.get_directories():
		if sub != "editor":
			_collect_bad(dir + "/" + sub, bad)
	for f: String in d.get_files():
		if f.ends_with(".gd"):
			var scr: GDScript = ResourceLoader.load(dir + "/" + f, "", ResourceLoader.CACHE_MODE_IGNORE)
			if scr == null or not scr.can_instantiate():
				bad.append(dir + "/" + f)
