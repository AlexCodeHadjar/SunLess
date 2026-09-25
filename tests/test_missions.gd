extends TestCase
## Миссии и локации (docs/15): загрузка и проверка данных.


func test_missions_load() -> void:
	var c := content()
	for i in range(1, 12):
		check(c.missions.has("MS%02d" % i), "сюжетная миссия MS%02d загружена" % i)
	eq(c.missions["MS01"].get("start", false), true, "Первый Кошмар начинается с MS01:")
	eq(c.missions["MS11"].get("end_chapter", false), true, "MS11 завершает главу:")
	check(c.locations.has("fallen_caravan"), "локация «Павший караван» загружена")
	eq(c.missions["MS02"]["next"], ["MS03"], "MS02 открывает MS03:")


func test_validator_catches_broken_mission() -> void:
	var c := content()
	var m: Dictionary = c.missions["MS03"].duplicate(true)
	m["location"] = "nowhere"
	m["threat"] = 9
	m["duration"] = 40
	m["squad"] = {"min": 3, "max": 2}
	m["hidden_tags"].append("Несуществующий тег")
	m["rumors"].append({"text": "без намёка", "tag": "Паразит"})
	m["actions"][0]["stages"] = []
	m["actions"][1]["stages"][0]["req"] = {}
	m["next"] = ["MS999"]
	c.missions["MS03"] = m
	var joined := "\n".join(ContentValidator.validate(c))
	for part: String in ["нет локации «nowhere»", "угроза 9", "время в пути 40", "мест в отряде 3–2",
			"Несуществующий тег", "нет намёка", "этапов 0", "нет требований", "MS999"]:
		check(joined.contains(part), "должна быть ошибка: " + part)


func test_story_mission_needs_story_action() -> void:
	var c := content()
	var m: Dictionary = c.missions["MS02"].duplicate(true)
	for a: Dictionary in m["actions"]:
		a.erase("story")
	c.missions["MS02"] = m
	check("\n".join(ContentValidator.validate(c)).contains("нет сюжетного действия"), "сюжетной миссии нужно сюжетное действие")


func test_mission_needs_real_action() -> void:
	var c := content()
	var m: Dictionary = c.missions["MS02"].duplicate(true)
	m["actions"] = [{"id": "x", "label": "Уйти", "retreat": true}]
	c.missions["MS02"] = m
	check("\n".join(ContentValidator.validate(c)).contains("кроме отступления"), "одного отступления мало")


func test_missions_have_no_mana() -> void:
	var c := content()
	var m: Dictionary = c.missions["MS03"].duplicate(true)
	m["actions"][0]["on_success"].append({"cmd": "adjust_resource", "resource": "mana", "value": 2})
	c.missions["MS03"] = m
	check("\n".join(ContentValidator.validate(c)).contains("маны в миссиях нет"), "мана в миссиях запрещена")
