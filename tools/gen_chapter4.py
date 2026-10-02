"""Глава 4 по документу «Глава 4 — Путь к Мрачному городу и Мрачный город — карта» (комплект sunless-chapter4-map-kit):
две главы-черновика (решение владельца 01.10.2026 — играбельные черновики, тексты на правку владельцу):
  tree      — «Древо Души» (E33–E48), регион ash_path: пепельные бури (сети троп), Демон Карапакса идёт по следу,
              Маяк смерти — приманка, гнев Владыки Пепла, Бездна (хрупкий мост, опасный спуск), Очарование Древа,
              Чёрная вода — только на лодке и ночью, котловины и островки.
  dark_city — «Мрачный город» (E49–E70), регион dark_city: Светлый замок за дань, территории хозяев-ужасов,
              ночные охотники на шум, живые статуи, обвалы, гавань и каналы тонут в шторм.
Цепочка: Берег (SH32) → tree → dark_city → city. Пишет data/maps/ash_path.json, dark_city.json, missions/ch4_tree.json,
ch5_dark_city.json целиком; по id — регионы, места, лавку, неделю, сюжетные окна, подсказки.
Арт — python tools/import_map_kit.py ash_path / dark_city. Запуск: python tools/gen_chapter4.py
"""
import json
import os

ROOT = os.path.join(os.path.dirname(__file__), "..")


def P(*parts):
	return os.path.join(ROOT, "data", *parts)


def load(p):
	return json.load(open(p, encoding="utf-8"))


def dump(p, d):
	open(p, "w", encoding="utf-8", newline="\n").write(json.dumps(d, ensure_ascii=False, indent=1) + "\n")


def upsert(lst, items):
	ids = {x["id"] for x in items}
	return [x for x in lst if x["id"] not in ids] + items


def camp(rest, beds, danger, *services, **kw):
	d = {"rest": rest, "beds": beds, "danger": danger, "services": list(services)}
	d.update(kw)
	return d


def shards(n):
	return {"cmd": "adjust_resource", "resource": "shards", "value": n}


def mission(mid, loc, typ, title, briefing, arrival, rumors, threat, enemies, field, known, hidden, context, actions, **kw):
	m = {"id": mid, "location": loc, "type": typ, "title": title, "briefing": briefing, "arrival": arrival,
		"rumors": [{"text": t, "tag": g} for t, g in rumors], "threat": threat, "duration": 5, "rest": 15,
		"squad": {"min": 1, "max": 3}, "enemies": enemies, "field": field, "known_tags": known, "hidden_tags": hidden,
		"context": context, "actions": actions, "from_event": enemies[0] if enemies else None}
	m.update(kw)
	return {k: v for k, v in m.items() if v is not None}


def chk(name, req, tags, ok, fail, partial=None):
	d = {"name": name, "req": req, "tags": tags, "ok": ok, "fail": fail}
	if partial:
		d["partial"] = partial
	return d


def fight(name, enemies, field, ok, fail, power=None):
	cb = {"enemies": enemies, "field": field}
	if power is not None:
		cb["power"] = power   # сила врагов этапа: боссы черновиков слабее, чем в общем списке (CombatSession)
	return {"name": name, "combat": cb, "tags": ["combat"], "ok": ok, "fail": fail}


def act(aid, label, text, stages, win, story=False):
	a = {"id": aid, "label": label, "text": text, "stages": stages, "on_success": win}
	if story:
		a["story"] = True
	return a


def retreat(aid, text="Отступить и вернуться позже."):
	return {"id": aid, "label": "Отступить", "text": text, "retreat": True}


def mark(place, st, days=999):
	return {"cmd": "map_mark", "place": place, "state": st, "missions": days}


def story(mid, loc, title, brief, arrival, rumors, threat, enemies, field, known, context, actions, nxt=None, **kw):
	m = mission(mid, loc, "story", title, "(черновик) " + brief, arrival, rumors, threat, enemies, field, known, [], context, actions, **kw)
	if nxt:
		m["next"] = nxt
	return m


# =========================================================================================================
# 4А — Древо Души, Пепельный путь
# =========================================================================================================
TREE = "tree"
ASH = [  # id, имя, точка, размер, облики, текст, лагерь
	("shore_exit", "Выход с Берега", [0.93, 0.55], 0.11, ["dry"], "Последние коралловые гребни переходят в серый пепел. Дальше — только пепел.", camp(15, 1, 0.1)),
	("ash_dunes", "Пепельные дюны", [0.80, 0.36], 0.16, ["dry", "dry_b", "dry_c", "storm"], "Гребни пепла, как застывшие волны. После каждой бури — другие.", camp(5, 0, 0.2)),
	("ash_bones", "Кости в пепле", [0.74, 0.66], 0.18, ["dry", "storm"], "Исполинский череп наполовину в пепле. Внутри можно укрыться — если внутри никого.", camp(15, 1, 0.15)),
	("ash_lord", "Логово Владыки Пепла", [0.63, 0.24], 0.2, ["dry", "wrath"], "Огромная воронка пепла с тлеющим сердцем. Здесь не дерутся — здесь выживают.", camp(0, 0, 0.6)),
	("stone_hulk", "Каменный остов", [0.67, 0.50], 0.14, ["dry", "buried"], "Окаменевший остов древнего существа. Лучшее укрытие в пепле.", camp(30, 2, 0.05, "equip")),
	("demon_trail", "Тропа Демона", [0.56, 0.68], 0.13, ["dry", "hunted"], "Рваные борозды и сломанные кости. Здесь прошёл кто-то очень большой.", camp(5, 0, 0.3)),
	("death_beacon", "Маяк смерти", [0.53, 0.40], 0.13, ["dry", "lit"], "Каменный столб на холме с кострищем наверху. Огонь здесь видно на весь пепел.", camp(20, 1, 0.1, "view")),
	("abyss_bridge", "Мост над Бездной", [0.44, 0.30], 0.14, ["dry", "cracked", "collapsed"], "Каменный мост-хребет над чёрной трещиной. Держится — пока.", camp(5, 0, 0.15)),
	("abyss_edge", "Край Бездны", [0.45, 0.66], 0.13, ["dry", "storm"], "Обрыв со ступенями вниз и старыми верёвками.", camp(10, 0, 0.2)),
	("lake_shore", "Берег Чёрной воды", [0.35, 0.52], 0.12, ["dry", "charmed"], "Плоский берег из чёрного стекла. Вода неподвижна — слишком неподвижна.", camp(20, 1, 0.1)),
	("soul_tree", "Древо Души", [0.24, 0.46], 0.2, ["dry", "night_glow", "charmed"], "Огромное светлое дерево на острове, золотые плоды. Здесь хорошо. Слишком хорошо.", camp(20, 2, 0.0)),
	("tree_nest", "Гнездо над Древом", [0.21, 0.26], 0.1, ["dry", "empty"], "Гнездо в кроне и древнее яйцо. Попасть туда можно только с острова.", camp(5, 0, 0.3)),
	("boat_cove", "Лодочная заводь", [0.33, 0.78], 0.13, ["dry", "boat_ready"], "Мелкая бухта с корягами — из них можно собрать лодку.", camp(15, 1, 0.1, "repair")),
	("black_rocks", "Скалы в чёрной воде", [0.17, 0.70], 0.12, ["dry", "flooded"], "Острые чёрные скалы из воды. Стоянка посреди озера.", camp(10, 0, 0.2)),
	("deep_maw", "Пасть недр", [0.13, 0.36], 0.14, ["dry", "awake"], "Круговая воронка в чёрной воде с зубцами. Под ней кто-то дышит.", camp(0, 0, 0.6)),
	("star_landing", "Звёздный берег", [0.06, 0.56], 0.12, ["dry"], "Берег под звёздами. На горизонте — далёкие стены человеческого города.", camp(25, 2, 0.05)),
]
ASH_EMERGE = [  # id, имя, группа, текст, облики
	("caravan_wreck", "Остов каравана", "ash", "Засыпанный пеплом караван Спящих-путников. Кто-то не дошёл.", ["dry"]),
	("giant_graveyard", "Кладбище гигантов", "ash", "Кости великанов торчат из пепла. Среди них — Воспоминания.", ["dry"]),
	("glass_crater", "Стеклянный кратер", "ash", "Молния ударила в пепел — и он стал стеклом.", ["dry"]),
	("ash_well", "Колодец пепла", "ash", "Спуск в глубину пепла. Внизу — тайник.", ["dry"]),
	("driftwood_isle", "Коряжник", "lake", "Островок коряг посреди озера. Выступает на рассвете.", ["dry"]),
	("turtle_shell", "Скорлупа черепахи", "lake", "Огромный панцирь — островок, пока вода низкая.", ["dry"]),
	("sunken_idol", "Затонувший идол", "lake", "Каменная голова идола выходит из воды на рассвете.", ["dry"]),
	("glowing_moss", "Светящийся мох", "lake", "Мох, светящийся в темноте, на плоском камне.", []),
]
ASH_SOCKETS = [[0.86, 0.5], [0.7, 0.36], [0.86, 0.76], [0.76, 0.8], [0.28, 0.66], [0.2, 0.57], [0.3, 0.34], [0.12, 0.82]]
ASH_PATHS = [
	["stone_hulk", "death_beacon"], ["stone_hulk", "demon_trail"], ["death_beacon", "ash_lord"], ["death_beacon", "abyss_bridge"],
	["abyss_bridge", "lake_shore"], ["abyss_edge", "lake_shore"], ["abyss_edge", "boat_cove"], ["lake_shore", "boat_cove"],
	["lake_shore", "soul_tree"], ["soul_tree", "tree_nest"], ["demon_trail", "abyss_edge"], ["ash_bones", "demon_trail"],
]
# сети троп Пепельного моря — буря меняет их по кругу (Выход с Берега всегда связан с Остовом)
ASH_SETS = [
	[["shore_exit", "ash_dunes"], ["ash_dunes", "stone_hulk"], ["shore_exit", "ash_bones"], ["ash_dunes", "ash_lord"]],
	[["shore_exit", "ash_bones"], ["ash_bones", "stone_hulk"], ["ash_dunes", "ash_lord"], ["shore_exit", "ash_dunes"]],
	[["shore_exit", "ash_dunes"], ["ash_dunes", "stone_hulk"], ["ash_bones", "stone_hulk"], ["ash_bones", "shore_exit"]],
]
ASH_WATER = [["boat_cove", "black_rocks"], ["black_rocks", "star_landing"], ["soul_tree", "deep_maw"], ["deep_maw", "star_landing"]]


def tree_map():
	places = {p[0]: {"at": p[2], "size": p[3], "states": p[4]} for p in ASH}
	for i, e in enumerate(ASH_EMERGE):
		places[e[0]] = {"at": ASH_SOCKETS[i], "size": 0.12, "states": e[4]}
	return {
		"_doc": "Путь к Мрачному городу — глава «Древо Души» (tools/gen_chapter4.py, не править руками). places/paths как у Берега; "
			"path_sets — сети троп Пепельного моря (меняет буря storm_phase), emerge_groups — котловины после бури и островки на Рассвете, "
			"fragile — Мост над Бездной, risky — спуск у Края, water_paths — Чёрная вода (лодка, ночью), zones — гнев Владыки и Очарование, "
			"movers — Демон и тень гиганта (core/rules/terrain_rules.gd, zone_rules.gd, mover_rules.gd). Воды-шейдера нет (облики мест).",
		"region": "ash_path", "art": "res://art/map/ash_path/", "base": "base.webp", "fog": "fog_tile.webp",
		"view_top": 0.06, "foot": 0.28, "zoom": 1.15,
		"places": places, "paths": ASH_PATHS, "sockets": ASH_SOCKETS,
		"variants": {"ash_dunes": ["dry", "dry_b", "dry_c"]},
		"path_sets": {"storm_phase": "ash_storm", "sets": ASH_SETS},
		"exposed": ["ash_dunes", "ash_bones", "demon_trail", "shore_exit", "caravan_wreck", "giant_graveyard", "glass_crater", "ash_well"],
		"emerge_groups": {"ash": {"sockets": [0, 1, 2, 3], "phase": "dawn", "day_in": 1, "count": [1, 2], "sink_after": "ash_storm"},
			"lake": {"sockets": [4, 5, 6, 7], "phase": "dawn", "day_in": 1, "count": [1, 2], "sink_after": "dawn"}},
		"fragile": {"abyss_bridge": {"crossings": 4, "storm": False, "warn": "cracked"}},
		"risky": [{"pair": ["demon_trail", "abyss_edge"], "name": "Спуск у Края Бездны", "req": {"power": 7}, "tags": ["climb"]}],
		"water_paths": ASH_WATER, "water_phases": ["night", "blood_moon"],
		"phase_states": {"soul_tree": {"night": "night_glow", "blood_moon": "night_glow"}, "ash_lord": {"night": "wrath", "blood_moon": "wrath"},
			"ash_dunes": {"ash_storm": "storm"}, "ash_bones": {"ash_storm": "storm"}, "abyss_edge": {"ash_storm": "storm"},
			"lake_shore": {"night": "charmed"}},
		"zones": {
			"wrath": {"name": "Гнев Владыки Пепла", "center": "ash_lord", "radius": {"default": 0, "night": 1, "blood_moon": 1},
				"camp": {"danger": 0.8}, "pass_psyche": -4, "color": [1.0, 0.3, 0.2]},
			"charm": {"name": "Очарование Древа", "center": "soul_tree", "radius": {"default": 1, "night": 2, "blood_moon": 2},
				"camp": {"rest": 50}, "charm": True, "color": [1.0, 0.85, 0.4]},
		},
		"movers": {
			"demon": {"name": "Демон Карапакса", "start": "ash_bones", "target": "camp", "step": 1, "enemy": "M05",
				"hunt": {"req": {"power": 9}, "tags": ["combat"], "psyche": -12, "ok_psyche": -4, "edge": True},
				"clash": {"zone": "wrath", "text": "Демон Карапакса сцепился с Владыкой Пепла — ранен и отступил"}},
			"deep_shadow": {"name": "Тень гиганта", "start": "deep_maw", "target": "patrol", "patrol": ["deep_maw", "black_rocks", "star_landing"],
				"phases": ["night", "blood_moon"], "active": True, "enemy": "M12",
				"hunt": {"req": {"cunning": 8}, "tags": ["stealth"], "psyche": -8, "ok_psyche": -2, "edge": True}},
		},
	}


def tree_story():
	S = []
	S.append(story("TS01", "shore_exit", "Выход с Берега",
		"Забытый Берег позади. Впереди — серое море пепла, и где-то за ним, говорят, город людей.",
		"Коралл кончается. Под ногами хрустит пепел.",
		[("Пепел [скрывает следы]", "Пепел"), ("Впереди [дюны]", "Скорость")], 1, [], "F_18", ["Пепел"], ["survival"],
		[act("TS01_go", "Уйти в пепел", "Запастись водой и выйти на рассвете.",
			[chk("Сборы", {"will": 5}, ["survival"], "Отряд уходит в пепел.", "Пришлось вернуться за водой.")], [], story=True),
			retreat("TS01_retreat")], ["TS02"], start=True, requires_heroes=["P01"]))
	S.append(story("TS02", "ash_dunes", "Пепельное море",
		"Дюны движутся с каждой бурей. Тропы, что были вчера, сегодня засыпаны.",
		"Ветер поднимает пепел столбами. Горизонт исчезает.",
		[("Дюны [меняются]", "Пепел"), ("После бури [тропы другие]", "Буря")], 1, [], "F_18", ["Пепел", "Буря"], ["survival"],
		[act("TS02_path", "Найти тропу", "Читать пепел, как карту.",
			[chk("Тропа", {"cunning": 6}, ["survival"], "Тропа найдена — до следующей бури.", "Отряд петляет по дюнам.")], [], story=True),
			retreat("TS02_retreat")], ["TS03"]))
	S.append(story("TS03", "ash_lord", "Владыка Пепла",
		"В воронке пепла лежит что-то древнее и злое. Драться с ним бессмысленно. Задача — пройти мимо и выжить.",
		"Пепел тёплый. Под ним что-то медленно дышит.",
		[("Владыка [спит неглубоко]", "Тишина"), ("Гнев [ночью шире]", "Тьма")], 2, [], "F_18", ["Тишина", "Жар"], ["stealth", "survival"],
		[act("TS03_sneak", "Пройти мимо", "Тихо, по краю воронки, днём.",
			[chk("Мимо Владыки", {"cunning": 7}, ["stealth"], "Владыка не проснулся. Почти.", "Пепел вздрогнул — бежать!")], [shards(2)], story=True),
			retreat("TS03_retreat")], ["TS04"]))
	S.append(story("TS04", "demon_trail", "Демон идёт следом",
		"Борозды в пепле свежие. Демон Карапакса учуял отряд — и теперь идёт по следу. Каждую ночь — ближе.",
		"Сломанные кости, вывернутые камни. Следы ведут к вашему лагерю.",
		[("Демон [идёт к лагерю]", "Разумный"), ("Огонь [его отвлекает]", "Огонь")], 2, [], "F_18", ["Панцирь", "Разумный"], ["survival"],
		[act("TS04_read", "Прочесть следы", "Понять, откуда он придёт.",
			[chk("Следы", {"cunning": 6}, ["survival"], "Теперь ясно: он придёт ночью, к огню лагеря.", "Следы путаются.")],
			[{"cmd": "mover", "do": "spawn", "mover": "demon", "place": "ash_bones"}, mark("demon_trail", "hunted")], story=True),
			retreat("TS04_retreat")], ["TS05"]))
	S.append(story("TS05", "death_beacon", "Маяк смерти",
		"На холме — каменный столб с кострищем. Если зажечь его, Демон пойдёт на огонь, а не к лагерю. Или к Владыке Пепла.",
		"Холодное кострище, следы старых огней.",
		[("Огонь [видно на весь пепел]", "Огонь"), ("Демон [идёт к огню]", "Разумный")], 2, [], "F_03", ["Высота", "Огонь"], ["survival"],
		[act("TS05_light", "Зажечь Маяк", "Огонь до неба — пусть идёт сюда.",
			[chk("Огонь", {"will": 6}, ["survival"], "Маяк горит. Где-то в пепле Демон поворачивает голову.", "Ветер гасит огонь.")],
			[{"cmd": "mover", "do": "lure", "mover": "demon", "place": "death_beacon", "days": 4}, mark("death_beacon", "lit")], story=True),
			retreat("TS05_retreat")], ["TS06"]))
	S.append(story("TS06", "stone_hulk", "Убийцы Демона",
		"Демон Карапакса. Убить его можно только на выбранном месте — в каменном остове, где ему тесно. Если он ранен Владыкой — легче.",
		"Каменные рёбра остова. Пепел у входа взрыт когтями.",
		[("В остове [ему тесно]", "Узость"), ("Демон [ранен?]", "Регенерация")], 4, ["M05"], "F_01", ["Панцирь", "Узость"], ["combat"],
		[act("TS06_fight", "Бой в остове", "Каждый заход — шаг к победе.",
			[fight("Демон", ["M05"], "F_01", "Демон Карапакса падает в пепел.", "Демон вырывается из остова.", power=0.7)],
			[{"cmd": "mover", "do": "kill", "mover": "demon"}, shards(8)], story=True),
			retreat("TS06_retreat")], ["TS07"], memory="boss",
		boss={"phases": [{"field": "F_01", "text": "Демон отступил, раненый, — и вернётся."}, {"field": "F_18", "text": "Последний заход."}]}))
	S.append(story("TS07", "abyss_bridge", "Бездна",
		"Чёрная трещина без дна режет мир пополам. Мост-хребет — единственный путь. Он трещит под каждым шагом.",
		"Ветер из Бездны. Камни моста осыпаются вниз — и звука падения не слышно.",
		[("Мост [трещит]", "Падение"), ("Внизу [ничего]", "Тьма")], 2, [], "F_22", ["Мост", "Падение"], ["climb"],
		[act("TS07_cross", "Перейти мост", "По одному, не глядя вниз.",
			[chk("Мост", {"will": 6}, ["climb"], "Все на той стороне. Мост за спиной рушится.", "Камень уходит из-под ноги.")],
			[{"cmd": "terrain", "do": "set", "place": "abyss_bridge", "state": "collapsed"}], story=True),
			retreat("TS07_retreat")], ["TS08"]))
	S.append(story("TS08", "lake_shore", "Берег Чёрной воды",
		"Озеро из чёрной воды, неподвижное, как стекло. Посреди — остров с огромным светлым деревом.",
		"Вода не отражает звёзды.",
		[("Вода [неподвижна]", "Вода"), ("Остров [светится]", "Свет")], 1, [], "F_17", ["Вода"], ["survival"],
		[act("TS08_look", "Осмотреть берег", "Найти путь к острову.",
			[chk("Берег", {"cunning": 5}, ["survival"], "Брод к острову есть — по мелям.", "Вода холодна, как лёд.")], [], story=True),
			retreat("TS08_retreat")], ["TS09"]))
	S.append(story("TS09", "soul_tree", "Древо Души",
		"Под Древом тепло, раны заживают за ночь, а еда сама падает с веток. Отсюда не хочется уходить. Никогда.",
		"Золотые плоды, мягкая трава. Тишина.",
		[("Здесь [хорошо]", "Очарование"), ("Уходить [не хочется]", "Ментальное давление")], 1, [], "F_23", ["Очарование", "Растение"], ["survival"],
		[act("TS09_rest", "Остаться на ночь", "Отдохнуть под Древом.",
			[chk("Отдых", {"will": 4}, ["survival"], "Лучшая ночь за много месяцев.", "Сон тревожный.")], [shards(2)], story=True),
			retreat("TS09_retreat")], ["TS10"]))
	S.append(story("TS10", "tree_nest", "Гнездо над Древом",
		"В кроне Древа — гнездо и древнее яйцо. В нём — Капля Ихора, редчайшая вещь Царства Снов.",
		"Ветви качаются. Скорлупа яйца тёплая.",
		[("Яйцо [охраняют]", "Летучий"), ("Ихор [бесценен]", "Древний")], 3, ["M24"], "F_03", ["Высота", "Летучий"], ["climb", "combat"],
		[act("TS10_climb", "Подняться к гнезду", "По ветвям, не глядя вниз.",
			[chk("Подъём", {"power": 6}, ["climb"], "Гнездо рядом.", "Ветка ломается."),
				fight("Страж гнезда", ["M24"], "F_03", "Страж сорвался вниз. Ихор ваш.", "Страж отгоняет вас.", power=0.45)],
			[mark("tree_nest", "empty"), shards(6)], story=True),
			retreat("TS10_retreat")], ["TS11"], memory="strong"))
	S.append(story("TS11", "soul_tree", "Чёрное семя",
		"Санни видит правду: Древо не кормит — оно держит. Чёрное семя в его корнях. Те, кто остался под Древом, не ушли никогда.",
		"Корни шевелятся. Под мягкой травой — кости.",
		[("Корни [держат]", "Захват"), ("Правду [видит Санни]", "Чутьё")], 2, [], "F_23", ["Очарование", "Захват"], ["knowledge"],
		[act("TS11_see", "Разорвать чары", "Санни должен убедить остальных.",
			[chk("Правда", {"will": 6}, ["social", "knowledge"], "Остальные видят кости под травой. Чары спадают.", "Никто не верит.")],
			[{"cmd": "zone", "do": "break", "zone": "charm"}, mark("soul_tree", "charmed", 0)], story=True),
			retreat("TS11_retreat")], ["TS12"], requires_heroes=["P01"]))
	S.append(story("TS12", "boat_cove", "Лодка",
		"Через Чёрную воду — только на лодке. Коряги в заводи, верёвки, смола Древа. Два дня работы — и ночью можно плыть.",
		"Коряги, мокрый песок, звёзды над водой.",
		[("Лодку [собрать из коряг]", "Подручные предметы"), ("Плыть [только ночью]", "Ночь")], 1, [], "F_17", ["Вода"], ["survival"],
		[act("TS12_build", "Строить лодку", "Связать коряги и просмолить.",
			[chk("Каркас", {"power": 6}, ["survival"], "Каркас держит.", "Коряга треснула."),
				chk("Смола", {"cunning": 6}, ["survival", "knowledge"], "Лодка не течёт. Можно плыть.", "Течёт.")],
			[{"cmd": "set_flag", "flag": "boat", "text": "Лодка готова — по Чёрной воде можно плыть ночью"}, mark("boat_cove", "boat_ready")], story=True),
			retreat("TS12_retreat")], ["TS13"]))
	S.append(story("TS13", "deep_maw", "Пасть недр",
		"Воронка посреди озера — пасть огромного существа. Обойти её нельзя: только через неё лежит путь к звёздному берегу.",
		"Вода кружится. Зубцы скал поднимаются из глубины.",
		[("Пасть [просыпается ночью]", "Глубина"), ("Щупальца [из глубины]", "Щупальца")], 4, ["M12"], "F_16", ["Глубина", "Щупальца"], ["combat"],
		[act("TS13_fight", "Бой в недрах", "Удержать лодку и пробиться.",
			[fight("Пасть", ["M12"], "F_16", "Пасть смыкается — без вас.", "Лодку тянет в воронку.", power=0.75)], [mark("deep_maw", "awake"), shards(8)], story=True),
			retreat("TS13_retreat")], ["TS14"], memory="boss",
		boss={"phases": [{"field": "F_16", "text": "Пасть отпустила лодку — но не навсегда."}, {"field": "F_16", "text": "Последний заход."}]}))
	S.append(story("TS14", "star_landing", "Звёздный берег",
		"Звёздный свет. Твёрдая земля. На горизонте — стены города, построенного людьми в Царстве Снов. Мрачный город.",
		"Песок под ногами. Впереди — тёмные стены.",
		[("Стены [на горизонте]", "Камень"), ("Город [ждёт]", "Тьма")], 1, [], "F_02", ["Камень"], ["survival"],
		[act("TS14_go", "К стенам города", "Последний переход.",
			[chk("Путь", {"will": 5}, ["survival"], "Стены всё ближе.", "Ноги не держат.")], [], story=True),
			retreat("TS14_retreat")], None, end_chapter=True, next_chapter="dark_city"))
	return S


# =========================================================================================================
# 4Б — Мрачный город
# =========================================================================================================
DC = "dark_city"
DARK = [  # id, имя, точка, размер, облики, высота, текст, лагерь
	("bright_castle", "Светлый замок", [0.5, 0.2], 0.24, ["dry", "siege"], "high", "Белая крепость на холме — единственные тёплые огни города. Ночь здесь стоит дани.",
		camp(40, 3, 0.0, "equip", "repair", "view", tribute=3)),
	("castle_gate", "Ворота замка", [0.5, 0.37], 0.12, ["dry", "closed_night"], "high", "Массивные ворота с подъёмным мостом. Ночью закрыты.", camp(15, 1, 0.15)),
	("memory_market", "Рынок Воспоминаний", [0.64, 0.33], 0.12, ["dry", "busy"], "high", "Навесы у стены замка, лотки с оружием и Воспоминаниями.", camp(15, 1, 0.1)),
	("hunters_guild", "Гильдия охотников", [0.36, 0.33], 0.13, ["dry"], "high", "Длинный зал с трофеями на стенах. Здесь берут заказы на ужасов.", camp(20, 1, 0.1, "repair")),
	("statue_plaza", "Площадь статуй", [0.32, 0.56], 0.15, ["dry", "statues_moved", "cleared", "ruined"], "high", "Круглая площадь с каменными статуями-воинами. Ночью они стоят не там, где днём.", camp(10, 0, 0.3)),
	("ruined_cathedral", "Разрушенный собор", [0.63, 0.57], 0.16, ["dry", "cracked", "collapsed", "cleared"], "high", "Собор без крыши, огромная роза-окно.", camp(15, 1, 0.2)),
	("graveyard_hope", "Кладбище надежд", [0.81, 0.40], 0.13, ["dry", "fresh_graves"], "high", "Холм с надгробиями и мечами Спящих.", camp(10, 0, 0.2)),
	("dark_well", "Тёмный колодец", [0.21, 0.70], 0.12, ["dry", "opened"], "mid", "Глубокий колодец в руинах двора, решётка.", camp(10, 0, 0.25)),
	("sunny_lair", "Логово в башне", [0.78, 0.70], 0.12, ["dry", "hidden", "found"], "high", "Полуразрушенная башня с тайным входом. Тихо — ночью особенно.", camp(20, 1, 0.02)),
	("harbour", "Нижняя гавань", [0.5, 0.84], 0.16, ["dry", "flooded"], "low", "Причалы, затонувшие лодки, склады.", camp(10, 0, 0.2)),
	("canals", "Каналы", [0.34, 0.80], 0.13, ["dry", "flooded"], "low", "Каменные каналы с мостиками.", camp(10, 0, 0.2)),
	("catacombs", "Вход в катакомбы", [0.64, 0.80], 0.12, ["dry", "flooded", "opened"], "low", "Лестница вниз под аркой с черепами.", camp(5, 0, 0.3)),
	("east_gate", "Восточные ворота", [0.93, 0.58], 0.11, ["dry"], "high", "Пролом в городской стене. Отсюда приходят те, кто прошёл пепел.", camp(15, 1, 0.1)),
	("lighthouse", "Маяк на утёсе", [0.90, 0.20], 0.1, ["dry", "lit"], "high", "Башня маяка на скале над морем.", camp(15, 1, 0.1, "view")),
	("south_road", "Южный выход", [0.10, 0.45], 0.11, ["dry"], "high", "Дорога на юг сквозь обрушенную арку.", camp(10, 0, 0.2)),
]
DARK_PATHS = [
	["east_gate", "sunny_lair"], ["east_gate", "graveyard_hope"], ["east_gate", "lighthouse"], ["graveyard_hope", "lighthouse"],
	["graveyard_hope", "memory_market"], ["memory_market", "castle_gate"], ["memory_market", "castle_market"], ["castle_gate", "bright_castle"],
	["castle_gate", "hunters_guild"], ["hunters_guild", "south_road"], ["south_road", "statue_plaza"], ["statue_plaza", "dark_well"],
	["statue_plaza", "castle_gate"], ["castle_gate", "ruined_cathedral"], ["ruined_cathedral", "sunny_lair"], ["ruined_cathedral", "catacombs"],
	["statue_plaza", "canals"], ["dark_well", "canals"], ["canals", "harbour"], ["harbour", "catacombs"], ["catacombs", "sunny_lair"],
	["hunters_guild", "statue_plaza"], ["memory_market", "ruined_cathedral"],
]
RUBBLE = {
	"R1": {"at": [0.44, 0.47], "pair": ["statue_plaza", "castle_gate"]}, "R2": {"at": [0.56, 0.47], "pair": ["castle_gate", "ruined_cathedral"]},
	"R3": {"at": [0.25, 0.46], "pair": ["hunters_guild", "statue_plaza"]}, "R4": {"at": [0.72, 0.49], "pair": ["ruined_cathedral", "sunny_lair"]},
	"R5": {"at": [0.42, 0.68], "pair": ["statue_plaza", "canals"]}, "R6": {"at": [0.58, 0.7], "pair": ["ruined_cathedral", "catacombs"]},
}
DARK_SHOP = {"id": "castle_market", "chapter": DC, "name": "Лавка у стены замка", "pos": [0.7, 0.3],
	"text": "Торговцы Светлого замка: всё за осколки — и за молчание.",
	"stock": [{"card": c} for c in ["P04", "K04", "K05", "K06", "K07", "K08", "U11", "U12", "U14", "U15"]],
	"slots": 4, "refresh_every": 3, "services": ["sharpen", "unwear"]}


def dark_map():
	places = {p[0]: {"at": p[2], "size": p[3], "states": p[4]} for p in DARK}
	places["castle_market"] = {"at": [0.71, 0.29], "size": 0.06, "states": []}
	return {
		"_doc": "Мрачный город (tools/gen_chapter4.py, не править руками). Как у Берега; гавань, каналы, катакомбы — низины (тонут в шторм, "
			"TideRules); rubble — завалы R1–R6 на тропах (обвал/лаз), zones — территории хозяев, movers — охотники и статуи; "
			"Светлый замок — лагерь за дань (camp.tribute, tribute_fallback). Воды-шейдера нет.",
		"region": "dark_city", "art": "res://art/map/dark_city/", "base": "base.webp", "fog": "fog_tile.webp",
		"view_top": 0.06, "foot": 0.28, "zoom": 1.15,
		"places": places, "paths": DARK_PATHS, "rubble": RUBBLE, "rubble_phase": "storm", "tribute_fallback": "castle_gate",
		"phase_states": {"castle_gate": {"night": "closed_night", "blood_moon": "closed_night"},
			"memory_market": {"dawn": "busy"}, "statue_plaza": {"night": "statues_moved", "blood_moon": "statues_moved"}},
		"zones": {
			"statues": {"name": "Территория живых статуй", "center": "statue_plaza", "radius": {"default": 0}, "grow": 1, "max": 2,
				"camp": {"danger": 0.3}, "owner": "статуи", "color": [0.7, 0.75, 0.8]},
			"spiders": {"name": "Паутина железных пауков", "center": "dark_well", "radius": {"default": 0}, "grow": 1, "max": 1,
				"camp": {"danger": 0.3}, "owner": "пауки", "color": [0.6, 0.6, 0.7]},
			"flowers": {"name": "Плотоядные цветы", "center": "graveyard_hope", "radius": {"default": 0}, "grow": 1, "max": 1,
				"camp": {"danger": 0.25}, "owner": "цветы", "color": [0.85, 0.2, 0.35]},
			"eaters": {"name": "Логово пожирателей", "center": "catacombs", "radius": {"default": 0}, "grow": 1, "max": 2,
				"camp": {"danger": 0.3}, "owner": "пожиратели", "color": [0.5, 0.3, 0.25]},
		},
		"movers": {
			"fiend": {"name": "Кровавый Изверг", "start": "south_road", "target": "noise", "patrol": ["south_road", "statue_plaza", "dark_well"],
				"phases": ["night", "blood_moon"], "active": True, "enemy": "M15",
				"hunt": {"req": {"power": 9}, "tags": ["combat"], "psyche": -12, "ok_psyche": -4, "edge": True}},
			"corpse_eater": {"name": "Пожиратель Трупов", "start": "catacombs", "target": "noise", "patrol": ["catacombs", "harbour", "sunny_lair"],
				"phases": ["night", "blood_moon"], "active": True, "enemy": "M28",
				"hunt": {"req": {"power": 8}, "tags": ["combat"], "psyche": -10, "ok_psyche": -3, "edge": True}},
			"statues": {"name": "Живые статуи", "start": "statue_plaza", "target": "patrol", "patrol": ["statue_plaza", "hunters_guild", "south_road"],
				"phases": ["night"], "active": True, "enemy": "M16",
				"hunt": {"req": {"power": 8}, "tags": ["combat"], "psyche": -8, "ok_psyche": -2, "edge": True}},
		},
	}


CONTRACTS = [  # заказы Гильдии охотников: id, место, имя, текст, слухи, враг, поле, сила, зона, тихий путь (имя, текст, req, теги)
	("DK01", "dark_well", "Заказ: железные пауки", "Пауки из колодца плетут сети уже по соседним дворам. Гильдия платит за каждую порванную сеть.",
		[("Пауки [в сетях]", "Сети"), ("Огонь [жжёт паутину]", "Огонь")], "M18", "F_21", 0.45, "spiders",
		("Выжечь сети", "Факелы в колодец — и бежать.", {"cunning": 7}, ["stealth", "survival"])),
	("DK02", "graveyard_hope", "Заказ: плотоядные цветы", "Цветы с Кладбища надежд ползут к рынку. Гильдия просит выполоть их с корнем.",
		[("Цветы [ползут]", "Растение"), ("Корни [глубоко]", "Захват")], "M08", "F_19", 0.85, "flowers",
		("Выполоть корни", "Днём, пока цветы спят.", {"power": 7}, ["survival"])),
	("DK03", "catacombs", "Заказ: пожиратели", "Пожиратели выходят из катакомб к гавани. Гильдия хочет, чтобы ход завалили — или пожирателей стало меньше.",
		[("Пожиратели [у входа]", "Кость"), ("Ход [можно завалить]", "Камень")], "M28", "F_21", 0.45, "eaters",
		("Завалить ход", "Камни с арки — вниз.", {"power": 7, "cunning": 5}, ["climb"])),
]


def dark_story():
	S = []
	S.append(story("DS01", "east_gate", "Восточные ворота",
		"Мрачный город. Руины кольцом вокруг холма, на холме — белый замок с тёплыми окнами. Санни решает войти один и посмотреть.",
		"Пролом в стене. Тишина руин, которую нарушает только ветер.",
		[("Руины [кишат ужасами]", "Тьма"), ("В замке [люди]", "Толпа")], 1, [], "F_06", ["Укрытия", "Тьма"], ["stealth"],
		[act("DS01_in", "Войти в город", "Тихо, тенью.",
			[chk("Вход", {"cunning": 6}, ["stealth"], "Никто не заметил.", "Что-то шевельнулось в руинах.")], [], story=True),
			retreat("DS01_retreat")], ["DS02"], start=True, requires_heroes=["P01"]))
	S.append(story("DS02", "sunny_lair", "Логово в башне",
		"Полуразрушенная башня с тайным входом — идеальное логово для того, кто не хочет платить дань и не хочет, чтобы его нашли.",
		"Пыль, паутина, узкая лестница наверх.",
		[("Башня [тайная]", "Скрытность"), ("Внутри [кто-то был]", "Засада")], 1, [], "F_06", ["Укрытия"], ["stealth", "survival"],
		[act("DS02_lair", "Устроить логово", "Спрятать вход и обжиться.",
			[chk("Логово", {"cunning": 6}, ["stealth"], "Логово готово — дёшево и тихо.", "Вход слишком заметен.")], [mark("sunny_lair", "hidden")], story=True),
			retreat("DS02_retreat")], ["DS03"]))
	S.append(story("DS03", "statue_plaza", "Каменная Святая",
		"На Площади статуй одна статуя не похожа на другие. Каменная Святая — хозяйка площади. Победить её — значит освободить район.",
		"Статуи стоят полукругом. Одна из них повернула голову.",
		[("Святая [двигается]", "Конструкт"), ("Камень [не берёт сталь]", "Камень")], 4, ["M17"], "F_06", ["Конструкт", "Камень"], ["combat"],
		[act("DS03_fight", "Бой на площади", "Каждый заход — трещина в камне.",
			[fight("Святая", ["M17"], "F_06", "Каменная Святая рассыпается. Площадь затихает.", "Святая отбрасывает вас.", power=0.6)],
			[{"cmd": "zone", "do": "clear", "zone": "statues", "days": 30}, mark("statue_plaza", "cleared", 30), shards(8)], story=True),
			retreat("DS03_retreat")], ["DS04"], memory="boss",
		boss={"phases": [{"field": "F_06", "text": "Святая отступила за статуи — и вернётся."}, {"field": "F_06", "text": "Последний заход."}]}))
	S.append(story("DS04", "castle_gate", "Светлый замок",
		"Ворота замка. Здесь живут сотни Спящих под защитой Гунлауга — за дань. Нефис и Касси уже внутри.",
		"Подъёмный мост, стража, очередь у ворот.",
		[("Стража [берёт дань]", "Толпа"), ("Внутри [свои законы]", "Ложь")], 1, [], "F_24", ["Толпа", "Свет"], ["social"],
		[act("DS04_enter", "Войти в замок", "Заплатить и войти.",
			[chk("Ворота", {"will": 5}, ["social"], "Стража пропускает. Замок живёт по своим законам.", "Стража не верит.")], [shards(-2)], story=True),
			retreat("DS04_retreat")], ["DS05"]))
	S.append(story("DS05", "bright_castle", "Законы Гунлауга",
		"Гунлауг держит замок железной рукой. Дань, лейтенанты, право сильного. Чтобы здесь жить, надо понять, как здесь всё устроено.",
		"Тёплые огни, сытые лица — и страх в каждом взгляде.",
		[("Лейтенанты [следят]", "Страх"), ("Дань [каждую ночь]", "Толпа")], 1, [], "F_24", ["Толпа"], ["social", "lie"],
		[act("DS05_learn", "Узнать законы", "Слушать и молчать.",
			[chk("Законы", {"cunning": 6}, ["social"], "Теперь ясно, кто здесь кто.", "Лишний вопрос — лишний взгляд.")], [], story=True),
			retreat("DS05_retreat")], ["DS06"]))
	S.append(story("DS06", "memory_market", "Рынок Воспоминаний",
		"У стены замка торгуют Воспоминаниями и оружием. Здесь можно купить всё — и продать всё, что принёс из руин.",
		"Навесы, крики торговцев, блеск стали.",
		[("Торговцы [хитрят]", "Ложь"), ("Товар [из руин]", "Подручные предметы")], 1, [], "F_24", ["Толпа"], ["social"],
		[act("DS06_trade", "Торговать", "Продать добычу из руин.",
			[chk("Торг", {"cunning": 6}, ["social", "lie"], "Сделка удалась.", "Обманули.")], [shards(6)], story=True),
			retreat("DS06_retreat")], ["DS07"]))
	S.append(story("DS07", "hunters_guild", "Гильдия охотников",
		"Гильдия берёт заказы на ужасов руин. Ночью великие охотники — Кровавый Изверг, Пожиратель Трупов — выходят на шум.",
		"Трофеи на стенах: когти, черепа, клочья паутины.",
		[("Охотники [идут на шум]", "Шум"), ("Заказы [платят]", "Толпа")], 2, [], "F_06", ["Шум"], ["social"],
		[act("DS07_contract", "Взять заказ", "Записаться в охотники.",
			[chk("Заказ", {"will": 6}, ["social"], "Заказ ваш: зачистить два района руин — тогда Гильдия скажет, где логово Чёрного Рыцаря.",
				"Новичкам не доверяют.")], [shards(3)], story=True),
			retreat("DS07_retreat")], ["DK01", "DK02", "DK03"]))
	# заказы Гильдии: зачистить хозяев районов (ZoneRules); сюжет дальше — когда зачищено три района (Святая + два заказа)
	for mid, loc, title, brief, rum, en, fld, pw, zone, alt in CONTRACTS:
		S.append(mission(mid, loc, "side", title, "(черновик) " + brief, "Гильдия ждёт трофей.", rum, 3, [en], fld, [rum[0][1]], [], ["combat"],
			[act(mid + "_fight", "Выгнать хозяина", "Бой на его земле.",
				[fight("Хозяин района", [en], fld, "Хозяин района повержен.", "Хозяин держит район.", power=pw)],
				[{"cmd": "zone", "do": "clear", "zone": zone, "days": 12}, shards(5)]),
			 act(mid + "_alt", alt[0], alt[1], [chk(alt[0], alt[2], alt[3], "Район затих.", "Хозяева заметили вас.")],
				[{"cmd": "zone", "do": "clear", "zone": zone, "days": 8}, shards(3)]),
			 retreat(mid + "_retreat")]))
	S.append(story("DS08", "ruined_cathedral", "Разрушенный собор",
		"В соборе без крыши живёт Чёрный Рыцарь. Пока он там — путь в южные руины закрыт.",
		"Роза-окно, лунный свет, шаги в доспехах.",
		[("Рыцарь [в доспехах]", "Сталь"), ("Собор [трещит]", "Камень")], 4, ["M25"], "F_07", ["Сталь", "Тьма"], ["combat"],
		[act("DS08_fight", "Бой в соборе", "Против Чёрного Рыцаря.",
			[fight("Рыцарь", ["M25"], "F_07", "Чёрный Рыцарь падает на колени.", "Рыцарь неуязвим.", power=0.4)],
			[mark("ruined_cathedral", "cleared", 30), shards(8)], story=True),
			retreat("DS08_retreat")], ["DS09"], memory="boss", unlock={"zones_cleared": 3, "after_all": ["DS07"]},
		boss={"phases": [{"field": "F_07", "text": "Рыцарь отступил в тень нефа."}, {"field": "F_07", "text": "Последний заход."}]}))
	S.append(story("DS09", "graveyard_hope", "Кладбище надежд",
		"На холме — мечи Спящих над могилами. Каждый, кто пришёл в город и не вернулся, оставил здесь меч.",
		"Ветер звенит мечами.",
		[("Мечи [помнят хозяев]", "Сталь"), ("Цветы [плотоядные]", "Растение")], 2, ["M08"], "F_19", ["Кость", "Растение"], ["combat", "ritual"],
		[act("DS09_honor", "Почтить павших", "И отогнать цветы от могил.",
			[fight("Цветы", ["M08"], "F_19", "Могилы чисты.", "Цветы оплетают ноги.", power=0.85)],
			[{"cmd": "zone", "do": "clear", "zone": "flowers", "days": 20}, mark("graveyard_hope", "fresh_graves", 30)], story=True),
			retreat("DS09_retreat")], ["DS10"]))
	S.append(story("DS10", "bright_castle", "Право вызова",
		"Право вызова: любой может бросить вызов лейтенанту Гунлауга. Победитель получает его место. Нефис решает драться.",
		"Круг во дворе замка. Толпа молчит.",
		[("Лейтенант [сильнее]", "Дуэль"), ("Толпа [смотрит]", "Толпа")], 3, ["M25"], "F_24", ["Дуэль", "Толпа"], ["combat", "duel"],
		[act("DS10_duel", "Принять вызов", "Бой в круге.",
			[fight("Вызов", ["M25"], "F_24", "Лейтенант повержен. Замок замолкает.", "Лейтенант сильнее.", power=0.4)], [shards(6)], story=True),
			retreat("DS10_retreat")], ["DS11"]))
	S.append(story("DS11", "dark_well", "Тёмный колодец",
		"Под решёткой колодца — ход в нижние руины. Железные пауки плетут там сети.",
		"Решётка, ржавчина, тонкие нити паутины в лунном свете.",
		[("Пауки [в сетях]", "Сети"), ("Внизу [ход]", "Тьма")], 3, ["M18"], "F_21", ["Сети", "Железо"], ["combat", "climb"],
		[act("DS11_open", "Открыть колодец", "Спуститься и расчистить сети.",
			[fight("Пауки", ["M18"], "F_21", "Сети порваны. Ход открыт.", "Сети держат.", power=0.45)],
			[{"cmd": "zone", "do": "clear", "zone": "spiders", "days": 30}, mark("dark_well", "opened"), shards(5)], story=True),
			retreat("DS11_retreat")], ["DS12"]))
	S.append(story("DS12", "catacombs", "Вход в катакомбы",
		"Арка с черепами и лестница вниз. Катакомбы ведут под город — и, говорят, к выходу из Царства Снов. Финал главы.",
		"Холод снизу. Черепа в нишах смотрят пустыми глазницами.",
		[("Внизу [пожиратели]", "Кость"), ("Лестница [в темноту]", "Тьма")], 3, ["M28"], "F_21", ["Кость", "Тьма"], ["combat"],
		[act("DS12_descend", "Спуститься", "Пробиться через пожирателей.",
			[fight("Катакомбы", ["M28"], "F_21", "Путь вниз свободен.", "Пожиратели теснят.", power=0.45)],
			[mark("catacombs", "opened"), {"cmd": "zone", "do": "clear", "zone": "eaters", "days": 30}], story=True),
			retreat("DS12_retreat")], None, end_chapter=True, next_chapter="city"))
	return S


# --- местные встречи: по одной на место, шаблон по виду места ---------------------------------------------
def locals_for(prefix, places, kinds, chapter_enemy):
	out = []
	for i, (lid, name, kind) in enumerate(places):
		mid = "%s%02d" % (prefix, i + 1)
		en, field = chapter_enemy[kind]
		tpl = {
			"ash": ("Пепел у %s" % name, "Пепел вокруг шевелится: что-то роет ходы. В пепле — кости и осколки.", "Пепел дымится под ногами.",
				[("Пепел [скрывает]", "Пепел"), ("Внизу [кто-то роет]", "Засада")], ["Пепел"], "Раскопать", {"cunning": 6}, ["survival"]),
			"lake": ("У чёрной воды: %s" % name, "У воды что-то блестит — и что-то смотрит из воды на того, кто нагнётся.", "Вода неподвижна.",
				[("Вода [смотрит]", "Вода"), ("На дне [блестит]", "Глубина")], ["Вода"], "Достать со дна", {"power": 6}, ["survival"]),
			"ruin": ("Руины у %s" % name, "В руинах — тайник прежних хозяев города. И нынешние хозяева где-то рядом.", "Обломки колонн, следы когтей.",
				[("Тайник [где-то здесь]", "Укрытия"), ("Хозяева [рядом]", "Засада")], ["Укрытия", "Камень"], "Обыскать руины", {"cunning": 6}, ["stealth"]),
		}[kind]
		out.append(mission(mid, lid, "random", tpl[0], tpl[1], tpl[2], tpl[3], 2, [en], field, tpl[4], [], ["survival", "combat"], [
			act(mid + "_search", tpl[5], "Осторожно.", [chk("Поиск", tpl[6], tpl[7], "Находка ваша.", "Ничего.", "Немного нашли.")], [shards(3)]),
			act(mid + "_fight", "Выгнать тварь", "Бой у места.", [fight("Бой", [en], field, "Тварь ушла.", "Тварь держит место.")], [shards(4)]),
			retreat(mid + "_retreat")], expires=2, xp_mult=1.5, local=True))
	return out


ASH_KIND = {"shore_exit": "ash", "ash_dunes": "ash", "ash_bones": "ash", "ash_lord": "ash", "stone_hulk": "ash", "demon_trail": "ash",
	"death_beacon": "ash", "abyss_bridge": "ash", "abyss_edge": "ash", "lake_shore": "lake", "soul_tree": "lake", "tree_nest": "lake",
	"boat_cove": "lake", "black_rocks": "lake", "deep_maw": "lake", "star_landing": "lake", "caravan_wreck": "ash", "giant_graveyard": "ash",
	"glass_crater": "ash", "ash_well": "ash", "driftwood_isle": "lake", "turtle_shell": "lake", "sunken_idol": "lake", "glowing_moss": "lake"}


HINTS = [
	{"id": "T70_demon", "event": "mover", "chapter": TREE, "title": "Погоня", "target": "",
		"text": "Демон Карапакса идёт по следу: каждую ночь — шаг по тропам к лагерю. Пришёл к лагерю — ночной бой. Уйдите, зажгите Маяк смерти (он пойдёт на огонь) или заведите его к Владыке Пепла — твари сцепятся."},
	{"id": "T71_wrath", "event": "zone_wrath", "chapter": TREE, "title": "Гнев Владыки", "target": "",
		"text": "Красное свечение — зона гнева Владыки Пепла. Ночью она шире. Проход через неё стоит психики, лагерь в ней — нападение почти наверняка."},
	{"id": "T72_charm", "event": "zone_charm", "chapter": TREE, "title": "Очарование", "target": "",
		"text": "Под Древом — лучший отдых, но каждая ночь там прибавляет герою Очарования. На третьей ночи герой откажется уходить — отряд не покинет остров, пока чары не разорваны."},
	{"id": "T73_ash_storm", "event": "ash_storm", "chapter": TREE, "title": "Пепельная буря", "target": "day_label",
		"text": "В бурю дюны сдвигаются: тропы Пепельного моря становятся другими, открытое снова скрыто пеплом, котловины засыпает. Ночь в открытом пепле — лагерь засыплет. После бури в котловинах поднимается новое."},
	{"id": "T74_fragile", "event": "fragile", "chapter": TREE, "title": "Мост над Бездной", "target": "",
		"text": "Мост держит не вечно: после нескольких переходов он трещит, потом рушится. Дальше — только спуском у Края Бездны, а это проверка и риск грани."},
	{"id": "T75_water", "event": "water", "chapter": TREE, "title": "Чёрная вода", "target": "",
		"text": "По Чёрной воде — только на лодке и только ночью. Ночью же по озеру ходит тень гиганта: лагерь рядом с ней — испытание. На Рассвете из воды выступают островки."},
	{"id": "T76_tribute", "event": "tribute", "chapter": DC, "title": "Дань", "target": "end_day",
		"text": "Ночь в Светлом замке — лучший отдых и все службы, но каждую ночь — дань осколками. Нечем платить — стража выставит за ворота."},
	{"id": "T77_territory", "event": "territory", "chapter": DC, "title": "Хозяева районов", "target": "",
		"text": "У районов руин свои хозяева: статуи, пауки, цветы, пожиратели. Их территория каждую ночь расползается к соседям, лагерь на ней опаснее. Зачистите хозяина — район на время безопасен. Заказы Гильдии охотников — как раз такие зачистки: сюжет дальше Гильдии ждёт трёх зачищенных районов (строка «Сегодня» внизу справа)."},
	{"id": "T78_hunters", "event": "hunters", "chapter": DC, "title": "Ночные охотники", "target": "",
		"text": "Ночью из логов выходят великие охотники и идут на шум — туда, где днём был бой. Лагерь в тихом месте (логово в башне, замок) — безопаснее."},
	{"id": "T79_rubble", "event": "rubble", "chapter": DC, "title": "Обвалы", "target": "",
		"text": "Руины рушатся: в шторм завал может закрыть проход или пробить новый лаз. Гавань, каналы и катакомбы в шторм уходят под воду."},
]


if __name__ == "__main__":
	dump(P("maps", "ash_path.json"), tree_map())
	dump(P("maps", "dark_city.json"), dark_map())
	T = tree_story() + locals_for("TL", [(p[0], p[1], ASH_KIND[p[0]]) for p in ASH] + [(e[0], e[1], ASH_KIND[e[0]]) for e in ASH_EMERGE],
		None, {"ash": ("M03", "F_18"), "lake": ("M09", "F_17")})
	D = dark_story() + locals_for("DL", [(p[0], p[1], "ruin") for p in DARK], None, {"ruin": ("M27", "F_06")})
	dump(P("missions", "ch4_tree.json"), T)
	dump(P("missions", "ch5_dark_city.json"), D)
	dump(P("regions.json"), upsert(load(P("regions.json")), [
		{"id": "ash_path", "name": "Путь к Мрачному городу", "arc": TREE, "arc_name": "Древо Души", "combat_field": "F_18",
			"start_heroes": ["P01", "P02", "P03"], "start_shards": 25, "start_cards": ["K04", "K05", "K06", "U15", "U14", "U01"]},
		{"id": "dark_city", "name": "Мрачный город", "arc": DC, "arc_name": "Мрачный город", "combat_field": "F_06",
			"start_heroes": ["P01", "P02", "P03"], "start_shards": 30, "start_cards": ["K04", "K05", "K06", "K07", "U15", "U14", "U01"]}]))
	loc_of = {m["location"]: m["id"] for m in T + D if m.get("local")}
	locs = []
	for p in ASH:
		locs.append({"id": p[0], "name": p[1], "chapter": TREE, "region": "ash_path", "pos": p[2], "text": p[5], "camp": p[6],
			"random": {"local": [loc_of[p[0]]]}})
	for e in ASH_EMERGE:
		locs.append({"id": e[0], "name": e[1], "chapter": TREE, "region": "ash_path", "pos": [0.5, 0.5], "text": e[3], "emerge": True,
			"socket_group": e[2], "camp": camp(15, 1, 0.15), "random": {"pool": [loc_of[e[0]]], "local": [loc_of[e[0]]]}})
	for p in DARK:
		locs.append({"id": p[0], "name": p[1], "chapter": DC, "region": "dark_city", "pos": p[2], "height": p[5], "text": p[6], "camp": p[7],
			"random": {"local": [loc_of[p[0]]]}})
	dump(P("locations.json"), upsert(load(P("locations.json")), locs))
	dump(P("shops.json"), upsert(load(P("shops.json")), [DARK_SHOP]))
	d = load(P("days.json"))
	d["phases"]["ash_storm"] = {"name": "Пепельная буря", "sky": "storm",
		"hint": "Пепельная буря: дюны сдвигаются, тропы Пепельного моря другие, открытое скрыто пеплом; ночь в открытом пепле — засыплет"}
	d["weeks"]["ash_path"] = [["night", 2], ["dawn", 2], ["ash_storm", 1], ["blood_moon", 2]]
	d["weeks"]["dark_city"] = [["night", 2], ["dawn", 2], ["storm", 1], ["blood_moon", 2]]
	dump(P("days.json"), d)
	st = [x for x in load(P("story.json")) if x["id"] not in (TREE, DC)]
	st.append({"id": TREE, "pages": [
		{"image": "res://art/map/ash_path/base.webp", "side": "left", "title": "Пепельное море",
			"text": "(черновик) За Забытым Берегом — серое море пепла, Бездна без дна и чёрное озеро со светлым Древом на острове.\n\nПуть к Мрачному городу лежит через всё это. И кто-то уже идёт по вашему следу."}]})
	st.append({"id": DC, "pages": [
		{"image": "res://art/map/dark_city/base.webp", "side": "left", "title": "Мрачный город",
			"text": "(черновик) Город людей в Царстве Снов: руины кольцом вокруг холма и белый замок с тёплыми огнями — единственными на много дней пути.\n\nВ замке за дань живут сотни Спящих. В руинах — ужасы и те, кто платить не хочет."}]})
	dump(P("story.json"), st)
	dump(P("tutorial.json"), upsert(load(P("tutorial.json")), HINTS))
	# модификаторы: «Вода у ног» — только Берег; побочные Мрачного города (заказы, встречи) тоже с модификаторами
	mods = load(P("modifiers.json"))
	for m in mods["list"]:
		if m["id"] == "tidepools":
			m["chapters"] = ["shore"]
	if DC not in mods.get("chapters", []):
		mods["chapters"] = mods.get("chapters", []) + [DC]
	dump(P("modifiers.json"), mods)
	print("миссий: Древо Души %d, Мрачный город %d" % (len(T), len(D)))
