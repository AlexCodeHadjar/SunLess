"""Город людей (реальный мир) — глава-черновик (docs «Город людей (реальный мир) — нападения из Врат — карта»).
Решения владельца 01.10.2026: играбельная глава-черновик, по сюжету — после Мрачного города (пока связи нет —
начинается из меню «Разработчик»: AutoPlay.to_chapter стартует её сразу со стартовым отрядом региона).
Пишет: data/maps/real_city.json, data/missions/ch6_city.json целиком; по id — регион, места, лавку, модификаторы
рангов Врат, подсказки. Арт — python tools/import_map_kit.py real_city. Запуск: python tools/gen_city.py
Тексты миссий — черновики на правку владельцу.
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


CH = "city"
REGION = {"id": "real_city", "name": "Город людей", "arc": CH, "arc_name": "Город людей", "combat_field": "F_06",
	"start_heroes": ["P01", "P02", "P03"], "start_shards": 30,
	# к этой главе у игрока уже есть вещи — глава-черновик начинается с ними (для меню «Разработчик» и тестов)
	"start_cards": ["K04", "K05", "K06", "K02", "U15", "U14", "U01", "K07"]}

# --- кварталы -----------------------------------------------------------------------------------
# (id, имя, точка на основе, размер виньетки, облики, жителей 0–3, лагерь, текст)
DISTRICT = ["dry", "alarm", "fight", "damaged", "ruined", "repair"]


def camp(rest, beds, danger, *services):
	return {"rest": rest, "beds": beds, "danger": danger, "services": list(services)}


PLACES = [
	("outskirts", "Окраины", [0.12, 0.58], 0.17, DISTRICT, 3, camp(10, 1, 0.25),
		"Тесные коробки-многоэтажки, бельё между домами, самострой. Здесь вырос Санни. Их защищают последними."),
	("industry", "Промзона", [0.21, 0.215], 0.17, DISTRICT, 2, camp(15, 1, 0.15, "repair"),
		"Цеха, трубы, цистерны. Мастерская — и пустыри, где трещины в воздухе появляются чаще всего."),
	("monorail", "Вокзал монорельса", [0.39, 0.19], 0.15, DISTRICT + ["closed"], 2, camp(15, 1, 0.1),
		"Купол вокзала на эстакаде. В Тревогу его закрывают первым."),
	("gov_quarter", "Правительственный квартал", [0.63, 0.14], 0.17, ["dry", "alarm", "fight", "damaged"], 2, camp(30, 2, 0.05, "equip"),
		"Башни из стекла и бетона за второй стеной. Здесь решают, кого спасать."),
	("hospital", "Госпиталь", [0.725, 0.39], 0.16, ["dry", "alarm", "overcrowded", "damaged"], 3, camp(25, 4, 0.1),
		"Большой корпус с площадкой на крыше. Лечат всех — пока хватает коек."),
	("old_center", "Старый центр", [0.475, 0.36], 0.15, DISTRICT, 3, camp(15, 1, 0.1),
		"Старая площадь с башней-часами и аркадами. Сердце города — и туда тянутся волны."),
	("metro_hub", "Узел подземки", [0.57, 0.465], 0.1, ["dry", "closed", "flooded", "infested"], 2, camp(10, 0, 0.15),
		"Стеклянный павильон над спуском в подземку. Быстрые пути — и тёмные туннели."),
	("bunker", "Убежище", [0.257, 0.425], 0.12, ["dry", "crowded", "sealed"], 2, camp(35, 3, 0.02, "equip", "repair"),
		"Бетонный купол бункера в сквере. Самая спокойная ночь в городе."),
	("market", "Рынок", [0.375, 0.54], 0.14, DISTRICT, 3, camp(15, 1, 0.12),
		"Крытые ряды под латаными навесами. Слухи, сделки и толпа."),
	("bridges", "Мосты", [0.54, 0.705], 0.2, ["dry", "damaged", "collapsed", "temporary"], 1, camp(5, 0, 0.2),
		"Два моста через тёмную реку. Волна перейдёт реку только здесь."),
	("port", "Речной порт", [0.585, 0.83], 0.17, DISTRICT + ["flooded"], 1, camp(15, 1, 0.15),
		"Причалы, краны, контейнеры. За рекой — и за мостами."),
	("park", "Старый парк", [0.8, 0.6], 0.15, ["dry", "fight", "burned"], 1, camp(10, 0, 0.15),
		"Старые деревья, пруд и беседка. Тишина — пока не открылись Врата на бульваре."),
	("academy_link", "Дорога в Академию", [0.89, 0.13], 0.12, ["dry", "closed"], 1, camp(20, 1, 0.05, "equip"),
		"Шоссе к воротам Академии и КПП. Отсюда в город приходят Пробуждённые."),
	("wall", "Стена периметра", [0.075, 0.38], 0.1, ["dry", "breached"], 0, camp(5, 0, 0.2),
		"Высокая бетонная стена с вышками. За ней — пустошь, где Врата открываются чаще всего."),
]
SHOP = {"id": "city_market", "chapter": CH, "name": "Рынок Пробуждённых", "pos": [0.33, 0.6],
	"text": "Лотки для тех, кто ходит к Вратам: оружие, Воспоминания, спутники.",
	"stock": [{"card": c} for c in ["P04", "K04", "K05", "K02", "K06", "K07", "K08", "U15", "U14", "U11", "U01"]],
	"slots": 4, "refresh_every": 3, "services": ["sharpen", "unwear"]}
PATHS = [
	["wall", "outskirts"], ["wall", "industry"], ["outskirts", "bunker"], ["outskirts", "market"],
	["industry", "monorail"], ["industry", "bunker"], ["monorail", "old_center"], ["monorail", "gov_quarter"],
	["bunker", "old_center"], ["bunker", "market"], ["market", "old_center"], ["market", "bridges"], ["market", "city_market"],
	["old_center", "metro_hub"], ["metro_hub", "gov_quarter"], ["metro_hub", "hospital"], ["metro_hub", "bridges"],
	["gov_quarter", "academy_link"], ["gov_quarter", "hospital"], ["hospital", "park"], ["hospital", "academy_link"],
	["park", "bridges"], ["bridges", "port"],
]

# --- Врата: точки G1–G8 (docs «Точки врат») --------------------------------------------------------
# (id, имя, точка, квартал, вес, сдвиг ранга, враги волны, хранитель, поле)
GATES = [
	("G1", "пустошь за окраинами", [0.12, 0.84], "outskirts", 3, 0, "M33", "M28", "F_02"),
	("G2", "пустырь у промзоны", [0.29, 0.12], "industry", 3, 0, "M18", "M29", "F_06"),
	("G3", "перекрёсток в центре", [0.47, 0.47], "old_center", 1, 1, "M33", "M25", "F_06"),
	("G4", "двор у рынка", [0.28, 0.56], "market", 2, 0, "M06", "M28", "F_01"),
	("G5", "бульвар у госпиталя", [0.68, 0.54], "hospital", 1, 0, "M32", "M35", "F_02"),
	("G6", "река ниже порта", [0.52, 0.93], "port", 2, 0, "M12", "M09", "F_16"),
	("G7", "у дороги в Академию", [0.84, 0.34], "gov_quarter", 1, 1, "M38", "M35", "F_02"),
	("G8", "набережная у мостов", [0.4, 0.84], "bridges", 2, 0, "M38", "M28", "F_22"),
]

NAMES = {p[0]: p[1] for p in PLACES}
IN = {"outskirts": "на окраинах", "industry": "в промзоне", "monorail": "у вокзала", "gov_quarter": "в правительственном квартале",
	"hospital": "у госпиталя", "old_center": "в старом центре", "metro_hub": "у подземки", "bunker": "у убежища", "market": "на рынке",
	"bridges": "на мостах", "port": "в порту", "park": "в парке", "academy_link": "на дороге в Академию", "wall": "у стены"}


def thr(do, **kw):
	return dict({"cmd": "threat", "do": do}, **kw)


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


def fight(name, enemies, field, ok, fail):
	return {"name": name, "combat": {"enemies": enemies, "field": field}, "tags": ["combat"], "ok": ok, "fail": fail}


def act(aid, label, text, stages, win, story=False):
	a = {"id": aid, "label": label, "text": text, "stages": stages, "on_success": win}
	if story:
		a["story"] = True
	return a


def retreat(aid, text="Отступить и вернуться позже."):
	return {"id": aid, "label": "Отступить", "text": text, "retreat": True}


def gate_missions():
	out = []
	for i, (gid, name, at, near, w, bias, wave, guard, field) in enumerate(GATES):
		n = i + 1
		# предвестие
		out.append(mission("CO%d" % n, near, "random", "Предвестие: %s" % name,
			"Над улицей висит тонкая трещина тёмного света, фонари вокруг гаснут один за другим. Через день-два здесь откроются "
			"Врата Кошмара. Какого ранга — скажет только тот, кто подойдёт ближе.",
			"Воздух дрожит, как над костром. Тишина такая, что слышно, как трещит стекло в окнах.",
			[("Трещина [растёт к ночи]", "Тьма"), ("Люди [не хотят уходить]", "Толпа")], 1,
			[wave], field, ["Тьма"], ["Толпа"], ["stealth", "social", "combat"], [
				act("CO%d_scout" % n, "Разведать трещину", "Подойти ближе и понять, что за ней.",
					[chk("Разведка", {"cunning": 6}, ["stealth", "knowledge"], "Ясно, что за Вратами — и насколько они сильны.",
						"Слишком близко — трещина плюнула холодом.")], [thr("scout", point=gid), shards(1)]),
				act("CO%d_evac" % n, "Эвакуировать квартал", "Увести людей, пока Врата не открылись.",
					[chk("Эвакуация", {"will": 6}, ["social"], "Улицы пустеют. Волна найдёт пустые дома.", "Люди не верят — трещина же маленькая.",
						"Ушли не все.")], [thr("evacuate", place=near)]),
				act("CO%d_ambush" % n, "Засада у трещины", "Встретить первых тварей в момент открытия.",
					[fight("Засада", [wave], field, "Первая волна легла у самого разрыва. Врата открылись — но слабее.",
						"Засада сорвалась.")], [thr("ambush", point=gid), shards(2)]),
				retreat("CO%d_retreat" % n)],
			expires=2))
		# Врата
		out.append(mission("CG%d" % n, near, "random", "Врата Кошмара: %s" % name,
			"Врата стоят посреди улицы — разрыв высотой в дом, внутри чужое беззвёздное небо. Каждую ночь из них выходит волна. "
			"Закрыть их — убить хранителя и удержать разрыв, пока он не схлопнется.",
			"Фонари мертвы, машины отброшены к стенам. Из разрыва тянет холодом и чужим ветром.",
			[("Хранитель [стоит у самого разрыва]", "Элита"), ("Волна [идёт к людям]", "Запах крови")], 2,
			[guard], field, ["Элита", "Тьма"], ["Запах крови"], ["combat", "ritual"], [
				act("CG%d_close" % n, "Закрыть Врата", "Убить хранителя и удержать разрыв.",
					[fight("Хранитель", [guard], field, "Хранитель падает к подножию разрыва.", "Хранитель держит разрыв."),
						chk("Разрыв", {"will": 7}, ["ritual"], "Разрыв схлопывается вспышкой. Осколки света падают и гаснут.",
							"Разрыв рвётся из рук.", "Схлопнулся — но не до конца чисто.")], [thr("close", point=gid), shards(6)]),
				retreat("CG%d_retreat" % n)],
			squad={"min": 1, "max": 4}))
		# шрам
		out.append(mission("CX%d" % n, near, "random", "Шрам Врат: %s" % name,
			"Где стояли Врата — выжженный круг и застывшие стеклянные шипы. Здесь всё ещё опасно, но в трещинах асфальта "
			"находят осколки душ.",
			"Тусклое свечение в трещинах. Шипы звенят от ветра.",
			[("Шипы [острее стекла]", "Камень"), ("В трещинах [что-то шевелится]", "Засада")], 1,
			[wave], field, ["Камень"], ["Засада"], ["survival", "combat"], [
				act("CX%d_dig" % n, "Добыть осколки", "Осторожно, между шипами.",
					[chk("Шрам", {"cunning": 6}, ["survival"], "Горсть осколков из трещин.", "Шип рассекает руку.")], [shards(4)]),
				act("CX%d_clear" % n, "Вычистить шрам", "Добить то, что осталось от Врат.",
					[fight("Остатки", [wave], field, "Шрам затих.", "Остатки уползли в трещины.")], [shards(3), thr("calm", value=5)]),
				retreat("CX%d_retreat" % n)],
			expires=2))
	return out


def wave_missions():
	out = []
	enemies = {"outskirts": "M33", "industry": "M18", "monorail": "M38", "gov_quarter": "M32", "hospital": "M33", "old_center": "M33",
		"metro_hub": "M21", "bunker": "M33", "market": "M06", "bridges": "M38", "port": "M12", "park": "M32", "academy_link": "M38", "wall": "M33"}
	for i, (lid, name, *_r) in enumerate(PLACES):
		mid = "CW%02d" % (i + 1)
		en = enemies[lid]
		acts = [
			act(mid + "_fight", "Остановить волну", "Встать между волной и людьми.",
				[fight("Волна", [en], "F_22" if lid == "bridges" else "F_06", "Волна разбита на улицах.", "Волна прошла сквозь строй.")],
				[thr("clear", place=lid), shards(3), thr("calm", value=5)]),
			act(mid + "_evac", "Увести людей", "Квартал всё равно заденет — но люди уцелеют.",
				[chk("Эвакуация", {"will": 6}, ["social"], "Последний автобус уходит, когда волна уже за углом.", "Люди прячутся по подвалам и не выходят.",
					"Увели почти всех.")], [thr("evacuate", place=lid)]),
		]
		if lid == "bridges":
			acts.append(act(mid + "_blow", "Взорвать мост", "Волна не перейдёт реку — но и порт будет отрезан на неделю.",
				[chk("Подрыв", {"cunning": 6}, ["survival"], "Пролёт рушится в реку. Волна стоит на том берегу.", "Заряды не сработали.")],
				[thr("blow", place="bridges")]))
		acts.append(retreat(mid + "_retreat"))
		out.append(mission(mid, lid, "random", "Волна %s" % IN[lid],
			"Тёмное пятно волны ползёт по улицам. Сегодня оно здесь — дым, опрокинутые машины, крики. Не остановить до ночи — "
			"квартал будет разбит, а волна пойдёт дальше, туда, где больше людей.",
			"Сирены, дым, опрокинутый автобус. Из темноты — шорох тысячи лап.",
			[("Волна [идёт к людям]", "Запах крови"), ("Их [много]", "Стая")], 2,
			[en], "F_22" if lid == "bridges" else "F_06", ["Стая", "Толпа"], ["Запах крови"], ["combat", "social"], acts,
			expires=1))
	return out


def city_randoms():
	out = []
	tpl = [
		("Патруль %s", "Пробуждённых просят пройти по кварталу ночью: где-то в подвале прячется то, что выползло из прошлых Врат.",
			"Пустые улицы, мигающие фонари.", "M33", "F_01", "combat", "Найти и добить", {"power": 6}),
		("Слухи %s", "Люди шепчутся о трещинах, о пропавших и о том, кто наживается на страхе. Послушать — значит знать раньше.",
			"Кухни, лестницы, очереди за хлебом.", None, "F_02", "social", "Слушать", {"cunning": 6}),
		("Бригада %s", "Ремонтной бригаде не хватает рук: завалы, провода, баррикады. Работа тяжёлая — зато люди запомнят.",
			"Леса, прожекторы, треск сварки.", None, "F_06", "survival", "Разбирать завалы", {"power": 6}),
	]
	for i, lid in enumerate(["outskirts", "industry", "old_center", "market", "port", "monorail", "park", "hospital"]):
		t = tpl[i % 3]
		mid = "CR%02d" % (i + 1)
		ok_cmd = [shards(3)] if t[5] != "survival" else [shards(2), thr("calm", value=5)]
		stage = fight("Бой", [t[3]], t[4], "Подвал чист.", "Тварь ушла глубже.") if t[3] else \
			chk(t[6], t[7], [t[5]], "Сделано.", "Не вышло.", "Наполовину.")
		out.append(mission(mid, lid, "random", t[0] % IN[lid], t[1], t[2],
			[("Люди [боятся ночи]", "Страх"), ("В городе [тесно]", "Толпа")], 1, [t[3]] if t[3] else [], t[4], ["Толпа"], [],
			["combat" if t[3] else t[5]], [act(mid + "_go", t[6], "Взяться за дело.", [stage], ok_cmd), retreat(mid + "_retreat")],
			expires=2))
	return out


def story():
	S = []
	def st(mid, loc, title, brief, arrival, rumors, threat, enemies, field, known, context, actions, nxt=None, **kw):
		m = mission(mid, loc, "story", title, brief, arrival, rumors, threat, enemies, field, known, [], context, actions, **kw)
		if nxt:
			m["next"] = nxt
		return m
	S.append(st("CS01", "academy_link", "Возвращение в город",
		"(черновик) Отряд возвращается из Царства Снов в мир людей. Город за стеной живёт по привычке — и по сиренам. На КПП "
		"у шоссе Пробуждённых встречают не как героев, а как тех, кто нужен прямо сейчас.",
		"Шлагбаумы, броневики, усталые лица охраны. Над городом — тусклое зарево фонарей.",
		[("На КПП [проверяют всех]", "Толпа"), ("Город [ждёт Пробуждённых]", "Страх")], 1, [], "F_02", ["Толпа"], ["social"],
		[act("CS01_pass", "Пройти КПП", "Показать метки Пробуждённых и войти в город.",
			[chk("КПП", {"will": 5}, ["social"], "Шлагбаум поднимается. Город — ваш, со всеми его Вратами.", "Охрана тянет время.")], [], story=True),
			retreat("CS01_retreat")], ["CS02"], start=True, requires_heroes=["P01"]))
	S.append(st("CS02", "outskirts", "Окраины помнят",
		"(черновик) Санни возвращается на улицы, где вырос. Здесь его помнят — и здесь первым видят трещины в воздухе. "
		"Над пустошью за стеной уже висит предвестие.",
		"Бельё между домами, дым из бочек, дети, которые замолкают при виде чужих.",
		[("Над пустошью [трещина]", "Тьма"), ("Окраины [никто не защищает]", "Толпа")], 1, [], "F_01", ["Толпа"], ["social", "stealth"],
		[act("CS02_talk", "Поговорить со старыми знакомыми", "Узнать, что видели люди.",
			[chk("Окраины", {"cunning": 5}, ["social"], "Трещину видели три ночи назад — и с тех пор пропадают собаки.", "Здесь не любят тех, кто ушёл.")],
			[thr("raise", point="G1", rank=1)], story=True), retreat("CS02_retreat")], ["CS03"]))
	S.append(st("CS03", "gov_quarter", "Совет Пробуждённых",
		"(черновик) В правительственном квартале решают, кого спасать. Пробуждённым дают власть над городом на время "
		"нападений — и ответственность за каждый разрушенный квартал.",
		"Стеклянные башни, ковры, карта города во всю стену. Красные метки на ней — Врата.",
		[("Совету [нужны козлы отпущения]", "Ложь"), ("Карта [в красных метках]", "Страх")], 1, [], "F_02", ["Толпа"], ["social", "lie"],
		[act("CS03_vow", "Взять город на себя", "Пообещать держать улицы — и требовать помощи.",
			[chk("Совет", {"will": 6}, ["social"], "Армия будет держать блокпосты. Остальное — на вас.", "Совет обещает — и ничего не даёт.",
				"Обещали половину.")], [thr("calm", value=10), thr("raise", point="G2")], story=True), retreat("CS03_retreat")], None))
	S.append(st("CS04", "old_center", "Ночь трёх Врат",
		"(черновик) Над старым центром, рынком и портом одновременно треснул воздух. Отряд один — Врат трое. Решать, что "
		"спасать, придётся этой ночью.",
		"Башня-часы бьёт полночь. Сирены воют сразу с трёх сторон.",
		[("Врат [трое]", "Страх"), ("Центр [ближе всего]", "Толпа")], 2, ["M33"], "F_06", ["Стая", "Толпа"], ["combat"],
		[act("CS04_hold", "Держать площадь", "Встать у башни-часов и не пустить первую волну к центру.",
			[fight("Площадь", ["M33"], "F_06", "Первая волна разбита у башни. Но Врата открылись.", "Площадь не удержать.")],
			[thr("raise", point="G3", rank=2, open=True), thr("raise", point="G4")], story=True),
			retreat("CS04_retreat")], ["CS05"], unlock={"gates_closed": 1, "after_all": ["CS03"]}))
	S.append(st("CS05", "bridges", "Мост",
		"(черновик) Волна идёт к реке. Мосты — единственный путь на южный берег, к порту. Держать мост — значит "
		"драться на узком пролёте. Взорвать — значит отрезать порт на неделю.",
		"Ветер с реки, пролёт в огнях, под ним — чёрная вода.",
		[("Мост [узкий]", "Мост"), ("За мостом [порт и люди]", "Толпа")], 3, ["M38"], "F_22", ["Мост", "Стая"], ["combat", "survival"],
		[act("CS05_hold", "Держать мост", "Встретить волну на пролёте.",
			[fight("Пролёт", ["M38"], "F_22", "Волна сорвалась в реку. Мост стоит.", "Мост не удержать.")], [shards(4)], story=True),
			act("CS05_blow", "Взорвать мост", "Волна не пройдёт. Порт останется один.",
				[chk("Подрыв", {"cunning": 6}, ["survival"], "Пролёт рушится. Волна стоит на том берегу.", "Заряды отсырели.")],
				[thr("blow", place="bridges")], story=True),
			retreat("CS05_retreat")], None))
	S.append(st("CS06", "hospital", "Госпиталь в осаде",
		"(черновик) Раненых везут со всего города, а волна идёт туда, где больше людей. Госпиталь переполнен — и он следующий.",
		"Палатки во дворе, вереница скорых, запах крови на ветру.",
		[("Волна [идёт на запах крови]", "Запах крови"), ("Внутри [сотни людей]", "Толпа")], 2, ["M33"], "F_02", ["Стая", "Толпа"],
		["combat"],
		[act("CS06_defend", "Держать госпиталь", "Бой во дворе, между палатками.",
			[fight("Двор", ["M33"], "F_02", "Волна разбита у самых дверей.", "Волна прорвалась в крыло.")], [shards(5), thr("calm", value=10)],
			story=True), retreat("CS06_retreat")], ["CS07"], unlock={"gates_closed": 3, "after_all": ["CS05"]}))
	S.append(st("CS07", "academy_link", "Восхождённые Врата",
		"(черновик) У дороги в Академию небо раскололось сверху донизу: Врата третьего ранга. Армия держит шоссе, Академия "
		"шлёт всех, кого может. Хранитель таких Врат — не тварь, а ужас.",
		"Небо в трещинах. Броневики стоят полукругом и ждут.",
		[("Врата [третьего ранга]", "Элита"), ("Армия [ждёт приказа]", "Толпа")], 3, ["M35"], "F_02", ["Элита", "Летучий"], ["combat"],
		[act("CS07_scout", "Разведка боем", "Понять, что стоит у разрыва, пока он не вышел сам.",
			[fight("Разведка", ["M35"], "F_02", "Хранитель показался — и отступил в разрыв. Теперь ясно, кого ждать.", "Разведку отбросили.")],
			[thr("raise", point="G7", rank=3, open=True)], story=True), retreat("CS07_retreat")], ["CS08"]))
	S.append(st("CS08", "gov_quarter", "Закрыть Восхождённые",
		"(черновик) Хранитель Восхождённых Врат вышел к правительственному кварталу. Закрыть такие Врата с одного раза "
		"нельзя: каждый заход ранит его — и он возвращается злее. Финал главы.",
		"Стекло башен осыпается дождём. Разрыв над кварталом горит холодным светом.",
		[("Хранитель [отступает и возвращается]", "Элита"), ("Квартал [держится]", "Толпа")], 3, ["M35"], "F_02", ["Элита", "Летучий"],
		["combat"],
		[act("CS08_fight", "Бой за квартал", "Каждый заход — шаг к закрытию разрыва.",
			[fight("Хранитель", ["M35"], "F_02", "Хранитель падает. Разрыв над кварталом схлопывается.", "Хранитель держит разрыв.")],
			[thr("close", point="G7"), thr("calm", value=30)], story=True), retreat("CS08_retreat")], None,
		end_chapter=True, boss={"phases": [{"field": "F_02", "text": "Хранитель отступил в разрыв — и вернётся."},
			{"field": "F_06", "text": "Разрыв дрожит. Последний заход."}]}, memory="boss"))
	return S


def build_map():
	return {
		"_doc": "Город людей (реальный мир) — карта-план (tools/gen_city.py, не править руками). places/paths как у Берега; "
			"threat (kind gate) — Врата Кошмара (core/rules/gate_rules.gd): points G1–G8 {at, near, signal (предвестие), open "
			"(Врата), scar (шрам), weight, rank_bias}, swarm {квартал: миссия волны}, people (жителей — куда идёт волна), "
			"center, ranks, panic, alarm_states (Тревога: двое Врат и больше), open_phases/move_phases (фазы недели).",
		"region": "real_city", "art": "res://art/map/real_city/", "base": "base.webp", "fog": "fog_tile.webp",
		"view_top": 0.06, "foot": 0.28, "zoom": 1.15,
		"places": dict({p[0]: {"at": p[2], "size": p[3], "states": p[4]} for p in PLACES},
			city_market={"at": [0.33, 0.6], "size": 0.06, "states": []}),
		"paths": PATHS,
		"decals": {"alarm": ["decal_police_tape"], "fight": ["decal_burnt_car", "decal_crater_s"], "damaged": ["decal_crater_m", "decal_burnt_car"],
			"ruined": ["decal_crater_l", "decal_fallen_pylon"], "repair": ["decal_checkpoint"], "crowded": ["decal_bus_evac"],
			"overcrowded": ["decal_bus_evac"], "collapsed": ["decal_barricade"], "closed": ["decal_police_tape"],
			"swarm": "wave_stain", "point": "gate", "glow": "gate_glow", "ally": "ally_checkpoint", "evac": "decal_bus_evac",
			"roads": {"damaged": "road_cracks", "ruined": "road_cars", "repair": "road_repair", "collapsed": "road_blocked"}},
		"point_tex": {"signal": "gate_omen", "opening": "gate_opening", "open": "gate_open", "closing": "gate_closing", "scar": "gate_scar"},
		"threat": {
			"kind": "gate", "signal_text": "Предвестие", "open_text": "Врата Кошмара",
			"events": {"signal": "gate_omen", "open": "gate_open", "swarm": "wave"},
			"first_after": 2, "first_delay": 2, "every": [3, 5], "signal_days": [1, 2], "max_gates": 2, "alarm_gates": 2,
			"open_phases": ["night"], "move_phases": ["dusk", "night"],
			"repair": [3, 5], "scar_days": 7, "alarm_danger": 1.2, "scar_chance": 0.3, "evac_days": 5, "bridge_days": 7,
			"ranks": {"1": 6, "2": 3, "3": 1},
			"panic": {"open": 10, "damaged": 5, "ruined": 15, "closed": -15, "calm": -3},
			"center": "old_center", "people": {p[0]: p[5] for p in PLACES}, "sturdy": ["bunker", "hospital", "gov_quarter"],
			"alarm_states": {"bunker": "crowded", "hospital": "overcrowded", "metro_hub": "closed", "monorail": "closed", "academy_link": "closed"},
			"points": {g[0]: {"name": g[1], "at": g[2], "near": g[3], "weight": g[4], "rank_bias": g[5], "size": 0.08,
				"signal": "CO%d" % (i + 1), "open": "CG%d" % (i + 1), "scar": "CX%d" % (i + 1)} for i, g in enumerate(GATES)},
			"swarm": {p[0]: "CW%02d" % (i + 1) for i, p in enumerate(PLACES)},
		},
	}


HINTS = [
	{"id": "T60_gate_omen", "event": "gate_omen", "chapter": CH, "title": "Предвестие Врат", "target": "marker_breach",
		"text": "Трещина в воздухе — через день-два здесь откроются Врата, и только ночью. Разведка узнает ранг, эвакуация уведёт людей, засада ослабит Врата и сорвёт первую волну."},
	{"id": "T61_gate_open", "event": "gate_open", "chapter": CH, "title": "Врата Кошмара", "target": "marker_breach",
		"text": "Врата стоят, пока их не закрыть: убить хранителя и удержать разрыв. Каждую ночь из них выходит волна. Ранг 2–3 — враги сильнее, нужен полный отряд."},
	{"id": "T62_wave", "event": "wave", "chapter": CH, "title": "Волна", "target": "marker_breach",
		"text": "Волна идёт туда, где больше людей. В квартале она стоит до двух ночей: сначала он повреждён, потом разрушен. Остановите её — или уведите людей: волна пройдёт мимо, но квартал заденет. Волна переходит реку только по мостам — мост можно взорвать."},
	{"id": "T63_panic", "event": "panic", "chapter": CH, "title": "Паника города", "target": "tide_banner",
		"text": "Паника растёт от открытых Врат и разрушенных кварталов и падает, когда Врата закрыты. Сильная паника — тревожные ночи и хуже отдых. Двое Врат сразу — Тревога: убежища и госпиталь переполнены, подземка и вокзал закрыты."},
	{"id": "T64_scar", "event": "scar", "chapter": CH, "title": "Шрам Врат", "target": "",
		"text": "Где стояли Врата — шрам: выжженный круг и стеклянные шипы. Там опасно, но в трещинах находят осколки душ. Со временем шрам выцветает."},
]


if __name__ == "__main__":
	dump(P("maps", "real_city.json"), build_map())
	M = story() + gate_missions() + wave_missions() + city_randoms()
	for m in M:
		if m["id"].startswith("CR"):
			pass
	dump(P("missions", "ch6_city.json"), M)
	dump(P("regions.json"), upsert(load(P("regions.json")), [REGION]))
	pools = {}
	for m in M:
		if m["id"].startswith("CR"):
			pools.setdefault(m["location"], []).append(m["id"])
	locs = [dict({"id": p[0], "name": p[1], "chapter": CH, "region": "real_city", "pos": p[2], "text": p[7], "camp": p[6]},
		**({"random": {"pool": pools[p[0]], "every": 3}} if p[0] in pools else {})) for p in PLACES]
	dump(P("locations.json"), upsert(load(P("locations.json")), locs))
	dump(P("shops.json"), upsert(load(P("shops.json")), [SHOP]))
	mods = load(P("modifiers.json"))
	mods["list"] = upsert(mods["list"], [
		{"id": "gate_rank2", "name": "Врата 2-го ранга", "tone": "bad", "roll": False, "text": "Пробуждённые Врата: хранитель — элита, волна сильнее.",
			"enemy_power": 1.25, "threat": 1, "loot_mult": 1.5, "bonus_shards": 2},
		{"id": "gate_rank3", "name": "Врата 3-го ранга", "tone": "bad", "roll": False, "text": "Восхождённые Врата: подкрепление у хранителя, сила как у босса.",
			"enemy_power": 1.5, "extra_enemy": True, "threat": 2, "loot_mult": 2.0, "bonus_shards": 5},
	])
	for m in mods["list"]:   # море и лабиринт — не про город
		if m["id"] in ("fog", "tidepools", "thunder", "armored"):
			m["chapters"] = ["shore", "tree"]
	mods["list"] = upsert(mods["list"], [
		{"id": "blackout", "name": "Темнота", "tone": "mixed", "chapters": [CH], "text": "Фонари погасли на весь квартал: в бою темно, зато в скрытности +1 Хитрость.",
			"field_tags": ["Тьма"], "check": [{"tags": ["stealth"], "stat": "cunning", "value": 1}]},
		{"id": "panic_crowd", "name": "Толпа в панике", "tone": "bad", "chapters": [CH], "text": "Люди бегут куда попало: в бою тесно, уговорить кого-то — −1 Воля.",
			"field_tags": ["Толпа"], "check": [{"tags": ["social"], "stat": "will", "value": -1}]},
	])
	if CH not in mods.get("chapters", []):
		mods["chapters"] = mods.get("chapters", []) + [CH]
	dump(P("modifiers.json"), mods)
	dump(P("tutorial.json"), upsert(load(P("tutorial.json")), HINTS))
	print("миссий Города:", len(M))
