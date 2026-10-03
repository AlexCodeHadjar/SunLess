"""Бродячие боссы (просьба владельца 03.10, docs/22, WanderRules): исполинские твари бродят по карте-плану главы,
останавливаются на несколько дней в стороне от пути игрока и появляются там как особое событие с особой наградой.

Пишет (не править руками — всё отсюда):
  data/wanderers.json             — боссы: глава, противник, излюбленные места, стоянка, появление, награда;
  data/missions/wanderers.json    — событие боя с боссом на каждом излюбленном месте (W1_<место>…);
  data/combat/enemies.json        — противники MW1–MW4 (и в editor_overrides.json, чтобы gen_combat_data их не стёр);
  data/enhancements.json          — награды LW1–LW4 (легендарные Воспоминания, не из общей добычи);
  data/tutorial.json              — подсказка T100 «Бродячий босс».
    python tools/gen_wanderers.py
"""
import io
import json
import os
import glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def P(*p):
	return os.path.join(ROOT, "data", *p)


def load(p):
	return json.load(io.open(p, encoding="utf-8"))


def dump(p, d):
	io.open(p, "w", encoding="utf-8", newline="\n").write(json.dumps(d, ensure_ascii=False, indent=1) + "\n")


BOSSES = [
	{
		"id": "W1", "name": "Багровый Отшельник", "chapter": "shore", "appear_day": 4, "rest": [2, 3],
		"enemy": {"id": "MW1", "name": "Багровый Отшельник", "rank": 2, "class": 5, "kind": "boss", "shards": 18,
			"tags": ["Гигант", "Панцирь", "Хитин", "Коралл", "Когти", "Древний", "Регенерация", "Соль моря"]},
		"field": "F_17", "known": ["Панцирь", "Гигант", "Коралл"], "power": 0.9,
		"rumors": [("Панцирь [не пробить в лоб]", "Панцирь"), ("Клешни [ломают щиты]", "Когти"),
			("Под ракушками [мягкие сочленения]", "Сочленения")],
		"briefing": "По отмелям бродит исполинский краб-отшельник. Его раковина — обломки кораллов, кости и ракушки, "
			"наросшие за века. Он не охотится — просто идёт, и всё живое уступает ему дорогу. Говорят, в глубине "
			"раковины тлеет то, что он когда-то проглотил.",
		"arrival": "Песок дрожит. Из-за коралловой гряды медленно поднимается красная гора — и у неё есть клешни.",
		"ok": "Панцирь треснул по старому шву — Отшельник оседает в песок. В раковине что-то тускло светится.",
		"fail": "Клешня сметает отряд, как волна. Отшельник даже не оборачивается.",
		"stop": "встал на отдых",
		"reward": {"id": "LW1", "name": "Панцирь Отшельника", "origin": "memory", "rarity": "legendary", "wears": False,
			"bonuses": [{"stat": "will", "value": 3, "tags": []}, {"stat": "power", "value": 1, "tags": []}],
			"text": "Воспоминание: обломок раковины Багрового Отшельника — тёплый, как живой. +3 Воля, +1 Сила. "
				"Принимает удар, который должен был сломать.",
			"tags": ["Панцирь", "Коралл", "Воспоминание"],
			"memory": {"name": "Под панцирем", "cond": "Бой проигран", "text": "Раковина принимает удар: с шансом 50% герой не падает на грань",
				"phase": "lose", "when": {}, "effect": {"guard": 50}, "once": True, "wear": 0}},
		"shards": 15,
	},
	{
		"id": "W2", "name": "Пепельный Змей", "chapter": "tree", "appear_day": 3, "rest": [2, 3],
		"enemy": {"id": "MW2", "name": "Пепельный Змей", "rank": 2, "class": 5, "kind": "boss", "shards": 20,
			"tags": ["Гигант", "Пепел", "Жар", "Чешуя", "Засада", "Скорость", "Подземный", "Древний"]},
		"field": "F_18", "known": ["Пепел", "Засада", "Гигант"], "power": 0.85,
		"rumors": [("Змей [ныряет в пепел]", "Засада"), ("Чешуя [горячая, как угли]", "Жар"),
			("На твёрдом камне [он медленнее]", "Камень")],
		"briefing": "Пепельные дюны дышат: под ними плывёт змей длиной с караван. Он выныривает там, где его не ждут, "
			"и уходит обратно в серую толщу, оставляя за собой дымящуюся борозду. Его чешуя не остывает никогда.",
		"arrival": "Дюна вздувается и лопается. Над пеплом поднимается голова — и пепел течёт с неё, как вода.",
		"ok": "Змей бьётся и затихает, наполовину зарывшись в пепел. Одна чешуйка всё ещё тлеет.",
		"fail": "Земля уходит из-под ног — Змей утягивает бой в пепел, и отряду остаётся только бежать.",
		"stop": "залёг в пепле",
		"reward": {"id": "LW2", "name": "Чешуя Пепельного Змея", "origin": "memory", "rarity": "legendary", "wears": False,
			"bonuses": [{"stat": "cunning", "value": 3, "tags": []}, {"stat": "power", "value": 1, "tags": []}],
			"text": "Воспоминание: тлеющая чешуйка Пепельного Змея. +3 Хитрость, +1 Сила. Первый удар — из-под земли.",
			"tags": ["Чешуя", "Пепел", "Засада", "Воспоминание"],
			"memory": {"name": "Нырок в пепел", "cond": "Первый раунд на пепле, песке или в пыли", "text": "Удар из-под земли: +12%",
				"phase": "round", "when": {"round": [1], "env_any": ["Пепел", "Песок", "Жар"]}, "effect": {"bonus": 0.12}, "once": True, "wear": 0}},
		"shards": 16,
	},
	{
		"id": "W3", "name": "Ловчий Теней", "chapter": "dark_city", "appear_day": 3, "rest": [2, 3],
		"enemy": {"id": "MW3", "name": "Ловчий Теней", "rank": 2, "class": 5, "kind": "boss", "shards": 20,
			"tags": ["Охота", "Выслеживание", "Тень", "Тьма", "Ловушка", "Сети", "Одиночка", "Разумный"]},
		"field": "F_06", "known": ["Тьма", "Ловушка", "Охота"], "power": 0.85,
		"rumors": [("Ловчий [ставит сети заранее]", "Ловушка"), ("Фонарь [держит пленные тени]", "Тень"),
			("При свете [он слепнет]", "Свет")],
		"briefing": "По крышам и пустым улицам Мрачного города ходит высокий ловчий в рваном плаще. На поясе у него "
			"фонарь-клетка, и в клетке бьются чужие тени. Он никогда не охотится дважды на одном месте.",
		"arrival": "Тени на стенах вдруг вытягиваются в одну сторону — туда, где мерцает фонарь.",
		"ok": "Фонарь падает и раскалывается — тени разлетаются по стенам. Ловчий исчезает вместе с ними.",
		"fail": "Сеть падает с крыши. Когда отряд вырывается, фонарь уже далеко.",
		"stop": "раскинул сети",
		"reward": {"id": "LW3", "name": "Фонарь Ловчего", "origin": "memory", "rarity": "legendary", "wears": False,
			"bonuses": [{"stat": "cunning", "value": 2, "tags": []}, {"stat": "will", "value": 2, "tags": []}],
			"text": "Воспоминание: фонарь-клетка Ловчего Теней, пустой и всё ещё тёплый. +2 Хитрость, +2 Воля. "
				"Свет в нём не даёт тьме спрятать врага.",
			"tags": ["Свет", "Охота", "Воспоминание"],
			"memory": {"name": "Свет в клетке", "cond": "Враг прячется во тьме или тени", "text": "Фонарь высвечивает врага: его тьма и тени не в счёт, +5%",
				"phase": "round", "when": {"enemy_any": ["Тьма", "Тень", "Скрытность"]},
				"effect": {"cancel_enemy_tags": ["Тьма", "Тень", "Скрытность"], "bonus": 0.05}, "once": True, "wear": 0}},
		"shards": 16,
	},
	{
		"id": "W4", "name": "Стеклянная Королева", "chapter": "city", "appear_day": 3, "rest": [2, 3],
		"enemy": {"id": "MW4", "name": "Стеклянная Королева", "rank": 3, "class": 5, "kind": "boss", "shards": 22,
			"tags": ["Стекло", "Кристалл", "Рой", "Предводитель", "Многоногость", "Жало", "Кошмарное существо", "Гигант"]},
		"field": "F_06", "known": ["Стекло", "Рой", "Предводитель"], "power": 0.8,
		"rumors": [("Королева [не ходит одна]", "Рой"), ("Стекло [звенит перед ударом]", "Звон"),
			("Тяжёлый удар [раскалывает панцирь]", "Тяжёлый удар")],
		"briefing": "Из Врат вышла тварь, которую люди прозвали Стеклянной Королевой: длинное тело в панцире из "
			"битого стекла, витрин и фар. Она бродит по пустым кварталам, плетёт гнёзда в выбитых окнах, и за ней "
			"ползёт звенящий рой.",
		"arrival": "Квартал звенит, будто тысяча бокалов разом. В витринах отражается то, чего на улице нет.",
		"ok": "Панцирь лопается дождём осколков. Рой рассыпается в стеклянную пыль — и затихает.",
		"fail": "Звон становится невыносимым — отряд отступает, прикрывая головы от стеклянного дождя.",
		"stop": "свила гнездо",
		"reward": {"id": "LW4", "name": "Осколок Стеклянной Королевы", "origin": "memory", "rarity": "legendary", "wears": False,
			"bonuses": [{"stat": "power", "value": 4, "tags": []}],
			"text": "Воспоминание: осколок панциря Стеклянной Королевы — острый, как память о ней. +4 Сила. "
				"Рои рассыпаются от его звона.",
			"tags": ["Стекло", "Режущий", "Воспоминание"],
			"memory": {"name": "Звон осколка", "cond": "Против роя и стаи", "text": "Звон рассыпает рой: враг −15%",
				"phase": "round", "when": {"enemy_any": ["Рой", "Стая"]},
				"effect": {"enemy_penalty": {"tags": ["Рой", "Стая"], "value": 0.15}}, "once": True, "wear": 0}},
		"shards": 18,
	},
]

HINTS = [
	{"id": "T100_wanderer", "event": "wanderer", "chapter": "shore", "title": "Бродячий босс", "target": "marker_wander",
		"text": "По карте бродит исполинская тварь — Бродячий босс. Раз в несколько дней она переходит на новое место, в стороне от "
			"вашего пути, и ждёт там. Бой с ней — особое событие: очень опасно, зато награда — легендарное Воспоминание. "
			"Не готовы — обходите стороной: босс не нападает сам."},
]


def chapter_places():
	"""Глава -> места карты-плана, где боссу можно встать: не лавки и не появляющиеся (сюжет и путь — в игре)."""
	locs = {l["id"]: l for l in load(P("locations.json"))}
	maps = {}
	for f in glob.glob(P("maps", "*.json")):
		m = load(f)
		maps[m["region"]] = m
	story = set()
	for f in glob.glob(P("missions", "*.json")):
		if f.endswith("wanderers.json"):
			continue
		d = load(f)
		for m in (d.values() if isinstance(d, dict) else d):
			if isinstance(m, dict) and m.get("type") == "story":
				story.add(m.get("location"))
	shops = set(load(P("shops.json")).keys()) if isinstance(load(P("shops.json")), dict) else {s["id"] for s in load(P("shops.json"))}
	out = {}
	for lid, l in locs.items():
		ch = l.get("chapter")
		region = l.get("region")
		if region not in maps or lid not in maps[region].get("places", {}):
			continue
		if lid in shops or l.get("emerge"):   # сюжет «сейчас» и путь к нему — проверяет WanderRules в игре
			continue
		out.setdefault(ch, []).append(lid)
	return out


def mission(b, lid):
	mid = "%s_%s" % (b["id"], lid)
	return {
		"id": mid, "location": lid, "type": "side", "wander": b["id"],
		"title": "Бродячий босс: %s" % b["name"],
		"briefing": b["briefing"], "arrival": b["arrival"],
		"rumors": [{"text": t, "tag": tag} for t, tag in b["rumors"]],
		"threat": 5, "duration": 8, "rest": 0, "squad": {"min": 1, "max": 3},
		"enemies": [b["enemy"]["id"]], "field": b["field"], "known_tags": b["known"], "hidden_tags": [],
		"context": ["combat"],
		"actions": [
			{"id": mid + "_fight", "label": "Бой с боссом", "text": "Встать у неё на пути и выдержать три раунда.",
				"stages": [{"name": b["name"], "combat": {"enemies": [b["enemy"]["id"]], "field": b["field"], "power": b["power"]},
					"ok": b["ok"], "fail": b["fail"]}],
				"on_success": [{"cmd": "add_card", "card": b["reward"]["id"]},
					{"cmd": "adjust_resource", "resource": "shards", "value": b["shards"]},
					{"cmd": "set_flag", "flag": "wander_%s_done" % b["id"]}]},
			{"id": mid + "_retreat", "label": "Отступить", "text": "Отойти, пока тварь не заметила, и вернуться позже.",
				"retreat": True},
		],
	}


if __name__ == "__main__":
	places = chapter_places()
	bosses = []
	missions = []
	for b in BOSSES:
		haunts = sorted(places.get(b["chapter"], []))
		assert len(haunts) >= 4, (b["id"], haunts)
		bosses.append({"id": b["id"], "name": b["name"], "chapter": b["chapter"], "enemy": b["enemy"]["id"],
			"appear_day": b["appear_day"], "rest": b["rest"], "haunts": haunts, "reward": b["reward"]["id"],
			"shards": b["shards"], "stop": b["stop"]})
		for lid in haunts:
			missions.append(mission(b, lid))
	dump(P("wanderers.json"), {"_doc": "Бродячие боссы (WanderRules, docs/22). Генерируется tools/gen_wanderers.py — не править руками.",
		"list": bosses})
	dump(P("missions", "wanderers.json"), missions)
	# противники — и в правки редактора, чтобы gen_combat_data.py их сохранил (вместе с уже добавленными H_*)
	enemies = load(P("combat", "enemies.json"))
	ov_path = P("combat", "editor_overrides.json")
	ov = load(ov_path) if os.path.exists(ov_path) else {}
	ov.setdefault("enemies", {})
	for e in enemies:
		if e["id"].startswith("H_") and e["id"] != "H_AURO":
			ov["enemies"].setdefault(e["id"], e)
	for b in BOSSES:
		ent = dict(b["enemy"])
		ent["art"] = "res://art/cards/%s.png" % ent["id"]
		idx = next((i for i, e in enumerate(enemies) if e["id"] == ent["id"]), None)
		if idx is None:
			enemies.append(ent)
		else:
			enemies[idx] = ent
		ov["enemies"][ent["id"]] = ent
	dump(P("combat", "enemies.json"), enemies)
	dump(ov_path, ov)
	# награды — легендарные Воспоминания, только за боссов (не в общей добыче)
	enh = load(P("enhancements.json"))
	for b in BOSSES:
		r = dict(b["reward"])
		r.update({"canon": "адаптация", "source": "бродячий босс: %s (docs/22)" % b["name"], "loot": False})
		idx = next((i for i, e in enumerate(enh) if e["id"] == r["id"]), None)
		if idx is None:
			enh.append(r)
		else:
			enh[idx] = r
	dump(P("enhancements.json"), enh)
	tut = [h for h in load(P("tutorial.json")) if h["id"] not in [x["id"] for x in HINTS]] + HINTS
	dump(P("tutorial.json"), tut)
	print("боссов %d, событий %d, мест: %s" % (len(bosses), len(missions), {b["id"]: len(b["haunts"]) for b in bosses}))
