"""Академия на карте-плане (docs «Глава 2 — Академия — карта»): карта, лагеря корпусов, новые места, прорывы.
Пишет: data/maps/academy.json целиком; в locations.json — места Академии по id (лагеря, новые места);
в ch2_academy.json — миссии прорывов BA01–BA27 и команды закрытия у NA01/NA02; из onslaught.json убирает Натиск
Академии (его заменяют прорывы, docs §3); в tutorial.json — подсказки прорывов.
Арт — python tools/import_map_kit.py academy. Запуск: python tools/gen_academy_map.py
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


# --- карта -------------------------------------------------------------------------------------
# центр виньетки и размер — по карте зон комплекта (центроиды корпусов), сверено наложением на основу
BUILD = ["dry", "alarm", "damaged", "burning", "barricaded", "repair"]
PLACES = {
	"gate": {"at": [0.512, 0.775], "size": 0.15, "states": ["dry", "alarm", "damaged", "barricaded", "repair"]},
	"dorm": {"at": [0.27, 0.555], "size": 0.19, "states": BUILD},
	"canteen": {"at": [0.518, 0.548], "size": 0.15, "states": BUILD},
	"medbay": {"at": [0.776, 0.54], "size": 0.18, "states": BUILD + ["crowded"]},
	"library": {"at": [0.705, 0.33], "size": 0.18, "states": BUILD},
	"yard": {"at": [0.275, 0.39], "size": 0.19, "states": ["dry", "alarm", "damaged", "repair"]},
	"arena": {"at": [0.52, 0.335], "size": 0.17, "states": ["dry", "alarm", "damaged", "repair"]},
	"capsules": {"at": [0.53, 0.11], "size": 0.17, "states": ["dry", "alarm", "lockdown", "damaged"]},
	"admin": {"at": [0.35, 0.19], "size": 0.13, "states": ["dry", "alarm", "repair"]},
	"range": {"at": [0.2, 0.2], "size": 0.17, "states": ["dry", "alarm", "damaged"]},
	"lab": {"at": [0.83, 0.18], "size": 0.17, "states": ["dry", "alarm", "leak", "breached", "sealed"]},
	"outskirts": {"at": [0.1, 0.84], "size": 0.12, "states": []},        # за стеной — нарисован на основе
	"academy_store": {"at": [0.615, 0.67], "size": 0.07, "states": []},  # лавка — значком у Общего зала
}
PATHS = [
	["gate", "outskirts"], ["gate", "canteen"], ["gate", "dorm"], ["gate", "medbay"],
	["dorm", "canteen"], ["dorm", "yard"], ["canteen", "arena"], ["canteen", "medbay"], ["canteen", "academy_store"],
	["medbay", "library"], ["yard", "arena"], ["yard", "range"], ["yard", "admin"],
	["arena", "admin"], ["arena", "library"], ["arena", "capsules"], ["admin", "capsules"], ["admin", "range"],
	["library", "lab"], ["lab", "capsules"],
]

# точки прорыва (docs §«Точки прорыва»): где на основе, кого задевают, какие миссии
POINTS = {
	"B0": {"name": "окраина за воротами", "at": [0.13, 0.8], "sprite": False, "near": "outskirts", "enter": "gate",
		"alarm": ["gate"], "weight": 2, "signal": "BA01", "open": "NA01"},
	"B1": {"name": "западная стена", "at": [0.13, 0.47], "near": "dorm", "enter": "dorm", "alarm": ["dorm", "yard"],
		"weight": 2, "signal": "BA02", "open": "BA08"},
	"B2": {"name": "стена у ворот", "at": [0.3, 0.73], "near": "gate", "enter": "gate", "alarm": ["gate", "dorm"],
		"weight": 2, "signal": "BA03", "open": "NA02"},
	"B3": {"name": "восточная стена", "at": [0.89, 0.55], "near": "medbay", "enter": "medbay", "alarm": ["medbay"],
		"weight": 1, "signal": "BA04", "open": "BA09"},
	"B4": {"name": "северо-восточная стена", "at": [0.925, 0.3], "near": "library", "enter": "library", "alarm": ["library"],
		"weight": 1, "signal": "BA05", "open": "BA10"},
	"B5": {"name": "Полигон", "at": [0.12, 0.2], "near": "range", "enter": "range", "alarm": ["range", "yard"],
		"weight": 1, "signal": "BA06", "open": "BA11"},
	"B6": {"name": "Лаборатория Кошмаров", "at": [0.84, 0.1], "sprite": False, "near": "lab", "enter": "lab", "alarm": ["library"],
		"site": "lab", "site_states": {"signal": "leak", "open": "breached", "sealed": "sealed"},
		"weight": 1, "once": True, "after": 6, "signal": "BA07", "open": "BA12"},
}
SWARM_AT = ["gate", "dorm", "canteen", "medbay", "library", "yard", "arena", "admin", "range", "lab"]
FIRE_AT = ["dorm", "canteen", "medbay", "library"]


def build_map():
	swarm = {lid: "BA%02d" % (13 + i) for i, lid in enumerate(SWARM_AT)}
	fire = {lid: "BA%02d" % (23 + i) for i, lid in enumerate(FIRE_AT)}
	return {
		"_doc": "Академия на карте-плане (docs «Глава 2 — Академия — карта», tools/gen_academy_map.py — не править руками). "
			"Как у Берега: places{at,size,states}, paths. Воды нет (нет height). threat — прорывы (core/rules/gate_rules.gd): "
			"points{at, near (миссии), enter (куда входит рой), alarm (места в тревоге), signal/open (миссии стадий), site/site_states "
			"(облик места вместо пролома), weight, once, after}, swarm{место: миссия «Рой в …»}, fire{место: «Пожар»}, core — оборона цели.",
		"region": "academy",
		"art": "res://art/map/academy/",
		"base": "base.webp",
		"fog": "fog_tile.webp",
		"view_top": 0.06,
		"foot": 0.28,
		"zoom": 1.15,
		"places": PLACES,
		"paths": PATHS,
		"decals": {"alarm": ["decal_siren"], "fight": ["decal_siren", "decal_cadet_post"], "damaged": ["decal_scorch", "decal_broken_windows"],
			"burning": ["decal_scorch"], "barricaded": ["decal_furniture_barricade"], "repair": ["decal_broken_windows"],
			"leak": ["decal_ooze"], "breached": ["decal_ooze", "decal_siren"], "lockdown": ["decal_siren", "decal_cadet_post"],
			"swarm": "swarm_stain", "point": "breach"},
		"threat": {
			"kind": "breach", "signal_text": "Сигнал на стене", "open_text": "Прорыв",
			"core_text": "Учебная тревога кончилась настоящей — оборона Зала капсул.",
			"calm_text": "Тревога снята — ремонтные бригады выходят во двор",
			"first_after": 2, "every": [3, 5], "signal_days": 1, "sealed_days": 3, "repair": [2, 3],
			"target": "capsules", "burn_chance": 0.35, "alarm_rest": -10, "core_psyche": -15, "core_shards": -4,
			"points": POINTS, "swarm": swarm, "fire": fire, "core": "BA27",
		},
	}


# --- места и лагеря ------------------------------------------------------------------------------
def camp(rest, beds, danger, *services):
	return {"rest": rest, "beds": beds, "danger": danger, "services": list(services)}


CAMP = {
	"dorm": camp(30, 2, 0.05, "equip"), "medbay": camp(25, 3, 0.05), "canteen": camp(20, 1, 0.05),
	"yard": camp(10, 0, 0.1, "repair"), "library": camp(15, 0, 0.05, "view"), "gate": camp(15, 0, 0.1, "view"),
	"arena": camp(10, 0, 0.1), "capsules": camp(20, 1, 0.05), "admin": camp(15, 0, 0.05, "equip"),
	"range": camp(5, 0, 0.15, "repair"), "lab": camp(5, 0, 0.2), "outskirts": camp(10, 1, 0.15),
}
NEW_LOC = [
	{"id": "admin", "name": "Административный корпус", "chapter": "academy", "region": "academy", "pos": [0.35, 0.19],
		"text": "Строгое здание с флагштоками. Отсюда управляют кампусом — и тревогой."},
	{"id": "range", "name": "Полигон", "chapter": "academy", "region": "academy", "pos": [0.2, 0.2],
		"text": "Мишени, воронки, бетонные укрытия. Здесь учат стрелять — и здесь стена тоньше всего."},
	{"id": "lab", "name": "Лаборатория Кошмаров", "chapter": "academy", "region": "academy", "pos": [0.83, 0.18],
		"text": "Низкий бункер с клетками и антеннами. Здесь изучают тварей. Иногда твари изучают лабораторию."},
]


# --- миссии прорывов ------------------------------------------------------------------------------
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


def stage_check(name, req, tags, ok, fail, partial=None):
	d = {"name": name, "req": req, "tags": tags, "ok": ok, "fail": fail}
	if partial:
		d["partial"] = partial
	return d


def stage_fight(name, enemies, field, ok, fail):
	return {"name": name, "combat": {"enemies": enemies, "field": field}, "tags": ["combat"], "ok": ok, "fail": fail}


def act(aid, label, text, stages, win):
	return {"id": aid, "label": label, "text": text, "stages": stages, "on_success": win}


def retreat(aid, text="Уйти и оставить это другим."):
	return {"id": aid, "label": "Отступить", "text": text, "retreat": True}


def missions():
	out = []
	# сигналы: день на подготовку — укрепить участок, засада у трещины, увести людей из корпуса
	for pid, d in POINTS.items():
		mid = d["signal"]
		lab = pid == "B6"
		near = d["near"]
		title = "Утечка в лаборатории" if lab else "Сигнал: %s" % d["name"]
		brief = ("В лаборатории Кошмаров мигают тревожные огни: из-под двери сдерживания сочится светящаяся слизь. "
			"Если то, что внутри, вырвется — оно окажется в сердце кампуса." if lab else
			"Сирены на стене: %s трескается, у подножия сгущается тёмная дымка. Завтра здесь будет пролом — "
			"если ничего не сделать сегодня." % d["name"])
		out.append(mission(mid, near, "random", title, brief,
			"Бетон в паутине трещин, прожектор мигает. За стеной что-то скребётся." if not lab else
			"Красный свет над дверью. Слизь тянется по полу тонкими нитями.",
			[("Трещина [расходится к ночи]", "Тьма"), ("За стеной [их много]", "Стая")], 1,
			["M33"], "F_02", ["Тьма", "Стая"], [], ["survival", "combat"], [
				act(mid + "_hold", "Укрепить участок", "Плиты, мешки, прожектор — прорыв задержится на день.",
					[stage_check("Укрепление", {"power": 6}, ["survival"], "Участок держится. Прорыв будет позже.",
						"Бетон не успели подвезти.", "Залатали, но наспех.")], [thr("delay", point=pid), shards(1)]),
				act(mid + "_ambush", "Засада у трещины", "Встретить первых тварей в момент прорыва — пока их мало.",
					[stage_fight("Засада", ["M33"], "F_02", "Первые твари легли у самой трещины — пролом заложили сразу.",
						"Твари прорвались мимо засады.")], [thr("seal", point=pid), shards(3)]),
				act(mid + "_evac", "Увести людей", "Закрыть %s и увести кадетов вглубь кампуса." % ("лабораторию" if lab else "ближний корпус"),
					[stage_check("Эвакуация", {"will": 5}, ["social"], "Корпус пуст и заперт — рой пройдёт мимо.",
						"Кадеты не послушали.")], [thr("barricade", place=d["enter"] if d["enter"] != "lab" else "library")]),
				retreat(mid + "_retreat")],
			expires=1))
	# проломы (NA01, NA02 — уже есть)
	opens = {"B1": ("BA08", "dorm", "Пролом в западной стене", "M38"), "B3": ("BA09", "medbay", "Пролом у медкрыла", "M33"),
		"B4": ("BA10", "library", "Пролом у библиотеки", "M38"), "B5": ("BA11", "range", "Прорыв на полигоне", "M33"),
		"B6": ("BA12", "lab", "Прорыв в лаборатории", "M33")}
	for pid, (mid, loc, title, en) in opens.items():
		lab = pid == "B6"
		out.append(mission(mid, loc, "onslaught", title,
			("Дверь сдерживания сорвана. То, что изучали годами, теперь изучает коридоры — в двух шагах от Зала капсул."
				if lab else "Стена не выдержала: в проломе дым и рваная сетка, по двору расползается тёмное пятно роя. "
				"Закрыть пролом нужно сегодня — завтра рой будет в корпусах."),
			"Обломки бетона, прожекторы, крики дежурных. Из темноты пролома лезут твари.",
			[("Они идут [к спящим]", "Запах крови"), ("Их [держит стая]", "Стая")], 3 if lab else 2,
			[en], "F_06", ["Стая", "Голод"], ["Запах крови"], ["combat"], [
				act(mid + "_fight", "Закрыть пролом", "Встать в проломе и не пустить их дальше.",
					[stage_fight("Пролом", [en], "F_06", "Последняя тварь падает в проломе. Его закладывают плитой.",
						"Твари прорываются мимо — пролом не удержать.")], [thr("seal", point=pid), shards(4)]),
				act(mid + "_lure", "Отвлечь рой", "Увести тварей на полигон, пока бригада закладывает пролом.",
					[stage_check("Приманка", {"cunning": 6}, ["lure", "chase"], "Рой уходит за вами — пролом успевают заложить.",
						"Рой не клюнул.", "Отвлекли, но не всех.")], [thr("seal", point=pid), shards(2)]),
				retreat(mid + "_retreat")],
			expires=1, expire_panic=10))
	# рой в корпусе: перехватить или забаррикадировать
	names = {"gate": "у ворот", "dorm": "в общежитии", "canteen": "в общем зале", "medbay": "в медкрыле", "library": "в библиотеке",
		"yard": "на тренировочном дворе", "arena": "на арене", "admin": "у административного корпуса", "range": "на полигоне",
		"lab": "в лаборатории"}
	for i, lid in enumerate(SWARM_AT):
		mid = "BA%02d" % (13 + i)
		out.append(mission(mid, lid, "random", "Рой %s" % names[lid],
			"Тёмное пятно роя ползёт по дорожкам кампуса. Сегодня оно здесь. Не остановить — к ночи корпус будет разбит, "
			"а рой пойдёт дальше, к Залу капсул.",
			"Окна дрожат от гула. По стенам ползёт тень с крыльями.",
			[("Рой [налетает сверху]", "Летучий"), ("В тварях [сидит паразит]", "Паразит")], 2,
			["M38"], "F_02", ["Рой", "Летучий"], ["Паразит"], ["combat", "survival"], [
				act(mid + "_fight", "Перехватить рой", "Бой в узости двора, пока рой не разошёлся по корпусу.",
					[stage_fight("Рой", ["M38"], "F_02", "Рой рассыпается и тает в темноте.", "Рой проходит сквозь строй.")],
					[thr("clear", place=lid), shards(3)]),
				act(mid + "_barricade", "Забаррикадировать", "Столы, шкафы, плиты — корпус закрыт, рой пойдёт мимо.",
					[stage_check("Баррикада", {"will": 6}, ["survival"], "Двери завалены. Рой бьётся о баррикаду — и уходит.",
						"Баррикаду не успели поставить.")], [thr("barricade", place=lid)]),
				retreat(mid + "_retreat")],
			expires=1))
	# пожары
	fnames = {"dorm": "общежитии", "canteen": "общем зале", "medbay": "медкрыле", "library": "библиотеке"}
	for i, lid in enumerate(FIRE_AT):
		mid = "BA%02d" % (23 + i)
		out.append(mission(mid, lid, "random", "Пожар в %s" % fnames[lid],
			"После роя крыло горит. Пожарные расчёты Академии заняты у стены — тушить придётся самим.",
			"Дым валит из окон. Внутри что-то трещит и рушится.",
			[("Огонь [идёт по крыше]", "Огонь"), ("Внутри [ещё есть люди]", "Толпа")], 1,
			[], "F_02", ["Огонь"], [], ["survival"], [
				act(mid + "_water", "Тушить", "Рукава, песок, двери — не дать огню уйти в соседнее крыло.",
					[stage_check("Пожар", {"will": 6}, ["survival", "climb"], "Огонь сбит. Крыло спасли.",
						"Огонь сильнее.", "Сбили, но крыло обгорело.")], [thr("extinguish", place=lid), shards(1)]),
				retreat(mid + "_retreat")],
			expires=2))
	# оборона Зала капсул
	out.append(mission("BA27", "capsules", "onslaught", "Настоящая тревога",
		"Рой дошёл до Зала капсул — до тех, кто ещё спит Первым Кошмаром. Ставни опущены, но стекло не вечно. "
		"Наставники держат вход; им нужны все, кто может держать оружие.",
		"Красный свет над крышей. Гул роя заглушает сирены.",
		[("Рой [бьётся в стекло]", "Летучий"), ("Внутри [спящие]", "Страх")], 3,
		["M38", "M33"], "F_02", ["Рой", "Летучий", "Стая"], ["Страх"], ["combat"], [
			act("BA27_fight", "Держать Зал капсул", "Бой у ставней — до последнего.",
				[stage_fight("Оборона", ["M38", "M33"], "F_02", "Рой отброшен от Зала капсул. Спящие не проснулись.",
					"Стекло трещит.")], [thr("repel"), shards(6)]),
			retreat("BA27_retreat", "Оставить оборону наставникам.")],
		expires=1, expire_panic=15))
	return out


HINTS = [
	{"id": "T50_breach_signal", "event": "breach_signal", "chapter": "academy", "title": "Сигнал на стене", "target": "marker_breach",
		"text": "Сирены на стене — завтра здесь пролом. Сегодня можно укрепить участок (прорыв на день позже), устроить засаду у трещины (закрыть его сразу) или увести людей из корпуса рядом."},
	{"id": "T51_breach", "event": "breach", "chapter": "academy", "title": "Прорыв",
		"target": "marker_breach", "text": "Пролом открыт — Тревога: у корпусов рядом службы закрыты, отдых хуже. Закройте его сегодня: не успеете — рой войдёт в кампус и пойдёт к Залу капсул."},
	{"id": "T52_swarm", "event": "swarm", "chapter": "academy", "title": "Рой в кампусе", "target": "marker_breach",
		"text": "Тёмное пятно на карте — рой. Каждую ночь он идёт на шаг по дорожкам к Залу капсул. Где он стоит, корпус в бою: перехватите рой или забаррикадируйте корпус — рой обойдёт его. Не отбили за день — корпус повреждён или горит."},
	{"id": "T53_repair", "event": "repair", "chapter": "academy", "title": "Ремонт", "target": "end_day",
		"text": "Тревога прошла — бригады чинят кампус за 2–3 дня. Пока идёт ремонт, у корпуса меньше коек и отдых хуже. В Академии всё восстанавливается: цена ошибки — время, службы и психика."},
]


if __name__ == "__main__":
	dump(P("maps", "academy.json"), build_map())
	locs = load(P("locations.json"))
	locs = upsert(locs, NEW_LOC)
	for l in locs:
		if l.get("chapter") == "academy" and l["id"] in CAMP:
			l["camp"] = CAMP[l["id"]]
	dump(P("locations.json"), locs)
	ac = load(P("missions", "ch2_academy.json"))
	ac = upsert(ac, missions())
	for m in ac:
		if m["id"] in ("NA01", "NA02"):
			pid = "B0" if m["id"] == "NA01" else "B2"
			m["on_complete"] = [e for e in m.get("on_complete", []) if e.get("cmd") != "threat"] + [thr("seal", point=pid)]
	dump(P("missions", "ch2_academy.json"), ac)
	dump(P("onslaught.json"), [o for o in load(P("onslaught.json")) if o.get("chapter") != "academy"])
	tut = load(P("tutorial.json"))
	for h in tut:   # переходы, лагерь-стоянка, дела лагеря, путь к миссии — с Академии: там первая карта-план
		if h["id"] in ("T42_travel", "T43_camp_place", "T44_tasks", "T48_far"):
			h["chapter"] = "academy"
	dump(P("tutorial.json"), upsert(tut, HINTS))
	print("миссий прорывов:", len(missions()))
