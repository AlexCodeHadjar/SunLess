"""Забытый Берег — места, облики и следы событий на карте-плане (docs «Забытый Берег — локации и текстуры для событий»,
комплект sunless-map-events-kit; картинки — python tools/import_map_kit.py shore_events).

Что делает (после tools/gen_shore.py, shore_deck.py, shore_local.py — дописывает их результат):
- data/maps/forgotten_shore.json: площадки S7–S14 (в море, на скалах), места отлива — только на S1–S6 (ebb_sockets);
  11 новых мест событий (emerge_groups: когда поднимаются, когда уходят); новые облики существующих мест
  (event_states: костёр у статуи и огонь на Высоте — пока там лагерь; кровавый алтарь, линька — в Кровавую луну;
  красный Шпиль — со второй недели; лабиринт горит — на утро после шторма; зал открыт — на Рассвете);
  метки у мест и полосы на тропах (place_decals, path_decals, mod_decals — по модификаторам встреч), следы на дни
  (traces: отступили, погибли — и Могилы Спящих рядом, ночное нападение, шторм), дымка и отсвет Шпиля;
- data/locations.json — новые места; data/missions/ch3_shore_events.json — по две встречи на место (SE01–SE22):
  спокойная и с боем, после встречи место меняет облик (лагерь брошен, туша обглодана, голем разбит…);
- data/missions/ch3_shore.json — «Обрывок знамени» (SC04) поднимает знамя Легиона, «Видение замка» (SH23) — голову
  статуи навсегда.
    python tools/shore_events_map.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_chapter4 import P, load, dump, upsert, camp, mission, chk, fight, act, retreat, shards  # noqa: E402

CH = "shore"
# площадки событий S7–S14 (индексы 6…13 после S1–S6)
NEW_SOCKETS = [[0.470, 0.175], [0.495, 0.600], [0.215, 0.790], [0.585, 0.835], [0.165, 0.410], [0.300, 0.105], [0.255, 0.620], [0.440, 0.880]]
S = {"S%d" % (i + 1): i for i in range(14)}
LAND = [S["S1"], S["S2"], S["S3"], S["S4"], S["S5"], S["S6"], S["S7"], S["S8"], S["S13"]]


def mark(place, st):
	return {"cmd": "map_mark", "place": place, "state": st, "missions": 999}


# место: (имя, высота, размер, облики, группа: {площадки, фаза, день фазы, с какого дня, когда уходит}, текст,
#         спокойная встреча, встреча с боем)
PLACES = {
	"strangers_camp": ("Чужой лагерь", "mid", 0.095, ["dry", "abandoned", "ravaged", "flooded"],
		{"sockets": LAND, "phase": "dawn", "day_in": 2, "sink_after": "storm"},
		"Палатки из латаной ткани, кострище, сушатся плащи. Здесь стоят чужие Спящие.",
		("Чужой лагерь: поговорить", "Дым над палатками — у берега стоят чужие Спящие. Держатся настороже, но разговор возможен.",
			"Чужаки молча смотрят из-за костра. Руки — у оружия.", [("Чужаки [насторожены]", "Засада"), ("У них [запасы]", "Укрытия")],
			"Переговоры", {"will": 6}, ["social"], "Чужаки делятся запасами и уходят на рассвете.", "Разговор не сложился.", 4, "abandoned"),
		("Чужой лагерь: ночной гость", "К палаткам повадилась тварь. Чужаки отбиваются — без помощи не выстоят.",
			"Порванная ткань, следы когтей. Тварь вернётся.", [("Тварь [возвращается]", "Когти"), ("Чужие [ранены]", "Засада")],
			["M03"], "F_06", 1.0, "Тварь убита. Лагерь разорён, но люди живы.", "Тварь утаскивает добычу.", 5, "ravaged")),
	"whale_carcass": ("Туша исполина", "low", 0.1, ["dry", "picked", "flooded"],
		{"sockets": [S["S9"], S["S10"]], "phase": "blood_moon", "day_in": 1, "sink_after": "blood_moon"},
		"После шторма море выбросило тушу огромного зверя. На запах уже идут.",
		("Туша исполина: срезать жир", "Шторм вынес на мель тушу морского исполина. Жир, кость, чешуя — пока не пришли падальщики.",
			"Запах бьёт в нос. Под шкурой что-то ещё шевелится.", [("Туша [свежая]", "Вода"), ("Падальщики [рядом]", "Когти")],
			"Разделка", {"power": 6}, ["survival"], "Срезали лучшее до прихода тварей.", "Туша слишком скользкая.", 5, "picked"),
		("Падальщики у туши", "К туше сползлись Падальщики Карапакса. Добыча — тому, кто их отгонит.",
			"Хитин блестит на мясе. Твари рвут тушу.", [("Их [несколько]", "Когти"), ("Они [сыты]", "Панцирь")],
			["M03", "M03"], "F_17", 0.8, "Падальщики разбежались. Туша ваша.", "Падальщики теснят к воде.", 6, "picked")),
	"tide_grotto": ("Грот отлива", "low", 0.095, ["dry", "flooded"],
		{"sockets": [S["S11"]], "phase": "dawn", "day_in": 1, "sink_after": "dawn"},
		"Пещера у кромки воды: открывается только в большой отлив. Изнутри — синий отсвет.",
		("Грот отлива: войти до воды", "Отлив открыл пещеру в утёсе. Внутри отсвет и, говорят, вещи утонувших. Вода вернётся к ночи.",
			"Мокрые камни, лужи, тихий плеск в глубине.", [("Вода [вернётся]", "Вода"), ("Внутри [отсвет]", "Глубина")],
			"Грот", {"cunning": 6}, ["stealth", "survival"], "В нише — вещи утонувшего Спящего.", "Пришлось уйти раньше воды.", 6, ""),
		("Хозяин грота", "В гроте живёт то, что приходит с приливом. Сейчас оно сонное — и голодное.",
			"Щупальца шевелятся в тёмной луже.", [("В луже [щупальца]", "Щупальца"), ("Вода [холодная]", "Глубина")],
			["M09"], "F_17", 0.9, "Хозяин грота уполз в глубину.", "Щупальца тянут в воду.", 6, "")),
	"fallen_star": ("Звёздный осколок", "high", 0.09, ["dry", "dim"],
		{"sockets": LAND, "phase": "night", "day_in": 2, "from_day": 8, "sink_after": "night"},
		"Ночью что-то упало с неба: в иле дымится свежая воронка, в ней светится осколок.",
		("Звёздный осколок: достать", "Ночью с неба упал осколок света. Он ещё горит в воронке — и манит всё живое.",
			"Серебряные искры над илом. Тепло, как у костра.", [("Осколок [горит]", "Свет"), ("На свет [идут]", "Засада")],
			"Осколок", {"will": 6}, ["ritual"], "Осколок в руках — тёплый и тяжёлый.", "Свет обжигает.", 7, "dim"),
		("Твари на свет звезды", "На свет осколка сползлись твари. Сначала — они.",
			"У воронки — хитин и когти.", [("Твари [на свету]", "Свет"), ("Их [много]", "Когти")],
			["M03"], "F_03", 1.0, "Твари отогнаны, осколок погас в руках.", "Твари не подпускают.", 5, "dim")),
	"legion_well": ("Колодец Легиона", "mid", 0.09, ["dry", "dug"],
		{"sockets": [S["S7"]], "phase": "night", "day_in": 1, "from_day": 6},
		"Каменный колодец Звёздного Легиона, почти занесённый илом. Звёзды на ободе ещё видны.",
		("Колодец Легиона: раскопать", "Из ила торчит обод колодца со звёздами Легиона. Если раскопать — будет пресная вода и, может, что-то ещё.",
			"Обод в иле, под ним — пустота и запах старой воды.", [("Под илом [пустота]", "Камень"), ("Звёзды [Легиона]", "Укрытия")],
			"Раскопки", {"power": 7}, ["survival"], "Колодец открыт: вода чистая, на дне — тайник легионера.", "Ил осыпается обратно.", 4, "dug"),
		("Что-то в колодце", "Из колодца ночью слышен скрежет. Что бы там ни жило, оно стережёт воду.",
			"Скрежет внизу затих, когда вы подошли.", [("Внизу [скрежет]", "Тьма"), ("Вода [чистая]", "Вода")],
			["M09"], "F_06", 0.9, "Колодец свободен — вода чистая.", "Тварь утаскивает ведро вместе с верёвкой.", 5, "dug")),
	"coral_sinkhole": ("Коралловый провал", "low", 0.095, ["dry", "flooded"],
		{"sockets": [S["S8"]], "phase": "blood_moon", "day_in": 1, "sink_after": "blood_moon"},
		"Шторм обрушил коралл: на краю лабиринта открылся провал, на дне что-то блестит.",
		("Провал: спуститься за блеском", "На краю лабиринта провалился коралл. На дне блестит — кости и что-то металлическое.",
			"Края провала крошатся. Внизу — блеск.", [("Края [крошатся]", "Высота"), ("На дне [блеск]", "Кость")],
			"Спуск", {"power": 6}, ["climb"], "На дне — оружие павшего Спящего.", "Коралл обвалился под ногой.", 6, ""),
		("Многоножки в провале", "Из провала лезут красные многоножки — коралл открыл их ходы.",
			"Шорох тысячи ног под кораллом.", [("Их [ходы]", "Засада"), ("Они [ядовиты]", "Когти")],
			["M06"], "F_06", 1.0, "Ходы завалены телами многоножек.", "Многоножки лезут отовсюду.", 5, "")),
	"sleeping_golem": ("Спящий голем", "mid", 0.1, ["dry", "broken"],
		{"sockets": [S["S3"], S["S4"], S["S13"]], "phase": "blood_moon", "day_in": 2, "sink_after": "night"},
		"Огромная фигура из коралла и камня лежит в иле, как холм. В груди — слабый свет.",
		("Голем: забрать сердце тихо", "Коралловый голем спит в иле. В его груди светится сердце — если взять его тихо, он не проснётся.",
			"Каменная грудь медленно поднимается. Свет пульсирует.", [("Он [спит]", "Тишина"), ("Сердце [светится]", "Свет")],
			"Тихо", {"cunning": 7}, ["stealth"], "Сердце голема в руках, свет гаснет.", "Голем шевелится — уходите.", 7, ""),
		("Разбить голема", "Голем просыпается от шагов. Если разбить его сейчас — коралл и камень станут добычей.",
			"Ил вздрагивает. Огромная рука поднимается.", [("Он [просыпается]", "Камень"), ("Удар [сокрушительный]", "Панцирь")],
			["M04"], "F_06", 0.7, "Голем рассыпается грудой коралла.", "Голем отбрасывает вас.", 9, "broken")),
	"messenger_nest": ("Гнездо посланника", "high", 0.09, ["dry", "empty"],
		{"sockets": [S["S12"]], "phase": "night", "day_in": 1, "from_day": 8},
		"На скальном шпиле — гнездо из костей и коралла. Посланник Шпиля возвращается сюда.",
		("Гнездо: подобраться", "На шпиле гнездо Посланника. Пока он на охоте — можно забрать то, что он натащил.",
			"Перья, кости, ветер. Гнездо пустует — пока.", [("Его [нет]", "Высота"), ("Он [вернётся]", "Засада")],
			"Подъём", {"power": 6}, ["climb"], "В гнезде — блестящие вещи Спящих.", "Скала не держит.", 5, ""),
		("Разорить гнездо", "Посланник дома. Разорить гнездо — значит выгнать его с этого берега.",
			"Чёрные крылья раскрываются над шпилем.", [("Он [дома]", "Летучий"), ("Гнездо [высоко]", "Высота")],
			["M03"], "F_03", 1.1, "Гнездо разорено, Посланник улетел.", "Посланник сбрасывает со скалы.", 7, "empty")),
	"centipede_lair": ("Логово многоножек", "mid", 0.095, ["dry", "burned"],
		{"sockets": [S["S13"], S["S8"]], "phase": "dawn", "day_in": 2, "from_day": 5},
		"Холм пористого коралла в норах: логово красных многоножек. Пока его не выжгут, они будут лезть.",
		("Логово: выкурить огнём", "Логово многоножек можно выжечь: дым по норам, огонь у выходов.",
			"Норы дышат теплом. Внутри шуршит.", [("Норы [глубокие]", "Засада"), ("Огонь [их гонит]", "Огонь")],
			"Огонь", {"will": 6}, ["survival"], "Логово выжжено. Многоножки ушли.", "Дым ушёл не туда.", 4, "burned"),
		("Бой в ходах логова", "Чтобы логово замолчало, придётся войти в ходы.",
			"Красные сегменты мелькают в темноте.", [("Их [сотни]", "Когти"), ("Ходы [тесные]", "Засада")],
			["M06", "M06"], "F_06", 0.8, "Логово мертво и выжжено.", "Многоножки выдавливают наружу.", 6, "burned")),
	"sleepers_graves": ("Могилы Спящих", "high", 0.085, ["dry", "old"],
		{"sockets": LAND},
		"Холмики камней на иле и меч в одном из них. Здесь лежат те, кто шёл с вами.",
		("Могилы: почтить павших", "Здесь похоронены павшие. Постоять у могил — и стать немного крепче.",
			"Ветер звенит о сломанный клинок.", [("Здесь [свои]", "Кость"), ("Ветер [тихий]", "Тишина")],
			"Память", {"will": 4}, ["ritual"], "Отряд постоял у могил. Стало легче.", "Слишком больно.", 0, "old"),
		("Падальщики у могил", "К могилам пришли Падальщики. Этого нельзя позволить.",
			"Камни разбросаны. Хитин скребёт.", [("Они [роют]", "Когти"), ("Это [свои]", "Кость")],
			["M03"], "F_03", 1.0, "Могилы целы.", "Падальщики не уходят.", 3, "old")),
	"stranded_islet": ("Островок отрезанных", "high", 0.09, ["dry", "empty", "flooded"],
		{"sockets": [S["S14"], S["S10"]], "phase": "storm", "day_in": 1, "sink_after": "storm"},
		"В шторм на скале посреди моря остались отрезанные Спящие: обрывок навеса и верёвка.",
		("Островок: перебросить верёвку", "Шторм отрезал кого-то на скале в море. Верёвка, бросок, переправа — пока волны не смыли их.",
			"Волны бьют в скалу. С островка машут.", [("Волны [выше]", "Вода"), ("Верёвка [одна]", "Высота")],
			"Переправа", {"power": 6}, ["climb"], "Отрезанных перевели на берег — они отдали всё, что было.", "Верёвка оборвалась.", 5, "empty"),
		("Твари вокруг островка", "Вокруг островка кружат щупальца. Сначала — они.",
			"В пене мелькают щупальца.", [("Щупальца [в пене]", "Щупальца"), ("Скала [скользкая]", "Вода")],
			["M09"], "F_17", 0.9, "Щупальца ушли в глубину, островок свободен.", "Волна смывает с камней.", 5, "empty")),
}

# новые облики существующих мест
NEW_STATES = {"statue_hill": ["bonfire", "restored"], "high_ground": ["beacon"], "drowned_hall": ["open"], "shore_altar": ["blood"],
	"spire_view": ["red"], "coral_maze": ["burning"], "hunting_grounds": ["molting"], "legion_ruins": ["banner"], "centurion_gate": ["molting"]}
EVENT_STATES = [
	{"place": "statue_hill", "state": "bonfire", "camp": True, "phase": ["night", "blood_moon"]},
	{"place": "high_ground", "state": "beacon", "camp": True, "phase": ["night", "blood_moon"]},
	{"place": "drowned_hall", "state": "open", "phase": ["dawn"]},
	{"place": "shore_altar", "state": "blood", "phase": ["blood_moon"]},
	{"place": "spire_view", "state": "red", "phase": ["blood_moon"], "from_day": 8},
	{"place": "hunting_grounds", "state": "molting", "phase": ["blood_moon"]},
	{"place": "centurion_gate", "state": "molting", "phase": ["blood_moon"], "from_day": 8},
	{"place": "coral_maze", "state": "burning", "phase": ["blood_moon"], "day_in": 1},
]
PLACE_DECALS = [
	{"decal": "decal_legion_trap", "place": "legion_ruins", "open": True},
	{"decal": "decal_ghost_column", "place": "legion_ruins", "phase": ["night"]},
	{"decal": "decal_blood_pools", "place": "low_tide", "phase": ["blood_moon"]},
	{"decal": "decal_moon_reflection", "place": "shell_field", "phase": ["blood_moon"]},
	{"decal": "decal_blood_flowers", "place": "coral_maze", "phase": ["blood_moon"]},
	{"decal": "decal_chalk_arrows", "place": "coral_maze", "variant": ["coral_maze", "dry_b"]},
	{"decal": "decal_egg_clutch", "place": "carapace_nest"},
	{"decal": "decal_smoke_far", "place": "strangers_camp", "fog": True},
	{"decal": "decal_lure_lights", "camp": True, "phase": ["night"], "height": ["low", "mid"]},
]
PATH_DECALS = [
	{"decal": "decal_patrol_mark", "path": ["coral_maze", "centurion_gate"], "phase": ["blood_moon"]},
	{"decal": "decal_shortcut", "path": ["coral_maze", "high_ground"], "variant": ["coral_maze", "dry_b"]},
	{"decal": "decal_coral_overgrowth", "path": ["coral_maze", "shelter"], "variant": ["coral_maze", "dry_c"]},
	{"decal": "decal_rope_crossing", "to": "stranded_islet"},
	{"decal": "decal_fog_bank", "path": ["stone_isle", "low_tide"], "phase": ["storm"]},
]
MOD_DECALS = {"fog": "decal_fog_bank", "cache": "decal_cairn", "cursed": "decal_cursed_glint", "ambush": "decal_bait_carcass",
	"nest": "decal_egg_clutch", "wounded": "decal_blood_trail", "thunder": "decal_lightning_scorch", "armored": "decal_claw_tracks",
	"tidepools": "decal_deep_pool"}
TRACES = {"retreat": "decal_abandoned_gear", "death": "decal_fallen_sleepers", "graves": "sleepers_graves",
	"attack": "decal_hunter_mark", "attack_path": "decal_claw_tracks", "storm_chest": "decal_sea_chest", "storm_scorch": "decal_lightning_scorch"}


HINTS = [
	{"id": "T97_event_place", "event": "event_place", "chapter": CH, "title": "Берег живёт", "target": "",
		"text": "Берег меняется сам: в отлив у берега встаёт чужой лагерь, после шторма на мель выносит тушу исполина, в шторм кого-то "
			"отрезает на скале, ночью падает звёздный осколок, со второй недели — гнездо посланника и логово многоножек. Такие места "
			"держатся недолго, у каждого свои встречи; после встречи место меняет облик."},
	{"id": "T98_traces", "event": "traces", "chapter": "", "title": "Следы на карте", "target": "",
		"text": "Следы у мест подсказывают, что там случилось или ждёт: туман, кровь, тайник, проклятый блеск у встречи — её особенности; "
			"брошенное снаряжение — там отступили; павшие и могилы — там погибли свои; метка охотника у лагеря — ночью приходили гости; "
			"сундук и опалённый коралл — следы шторма. В Главе 4 — фишки угроз, свечение зон, завалы и логова охотников."},
]


def encounters():
	out = []
	n = 1
	for lid, (name, h, size, states, grp, text, calm, figh) in PLACES.items():
		t, br, arr, rum, cname, req, tags, ok, fail, reward, st = calm
		win = ([shards(reward)] if reward else [{"cmd": "psyche", "value": 8, "text": "почтили павших"}]) + ([mark(lid, st)] if st else [])
		out.append(mission("SE%02d" % n, lid, "random", t, br, arr, rum, 1, [], "F_03", [rum[0][1]], [], ["survival"],
			[act("SE%02d_go" % n, cname, "Осторожно.", [chk(cname, req, tags, ok, fail)], win), retreat("SE%02d_retreat" % n)],
			expires=2, local=True, local_kind="calm", xp_mult=1.5))
		n += 1
		t, br, arr, rum, en, fld, pw, ok, fail, reward, st = figh
		out.append(mission("SE%02d" % n, lid, "random", t, br, arr, rum, 2, en, fld, [rum[0][1]], [], ["combat"],
			[act("SE%02d_fight" % n, "Бой", "Каждый удар на счету.", [fight("Бой", en, fld, ok, fail, power=pw)],
				[shards(reward)] + ([mark(lid, st)] if st else [])), retreat("SE%02d_retreat" % n)],
			expires=2, local=True, local_kind="fight", xp_mult=1.5))
		n += 1
	return out


def main():
	ms = encounters()
	ids = {}
	for m in ms:
		ids.setdefault(m["location"], []).append(m["id"])
	dump(P("missions", "ch3_shore_events.json"), ms)
	# места
	locs = []
	for lid, (name, h, size, states, grp, text, calm, figh) in PLACES.items():
		locs.append({"id": lid, "name": name, "chapter": CH, "region": "forgotten_shore", "pos": [0.5, 0.5], "height": h, "text": text,
			"emerge": True, "raid_only": True, "socket_group": lid, "camp": camp(15, 1, 0.15),
			"random": {"pool": ids[lid], "local": ids[lid]}})
	dump(P("locations.json"), upsert(load(P("locations.json")), locs))
	# карта
	m = load(P("maps", "forgotten_shore.json"))
	m["sockets"] = m["sockets"][:6] + NEW_SOCKETS
	m["ebb_sockets"] = [0, 1, 2, 3, 4, 5]
	for lid, (name, h, size, states, grp, text, calm, figh) in PLACES.items():
		m["places"][lid] = {"size": size, "states": states}
	for lid, extra in NEW_STATES.items():
		st = m["places"][lid]["states"]
		for e in extra:
			if e not in st:
				st.append(e)
	m["emerge_groups"] = {lid: dict(PLACES[lid][4], count=[1, 1]) for lid in PLACES}
	m["emerge_groups"]["sleepers_graves"]["phase"] = ""   # только после гибели героя (traces)
	paths = [sorted(p) for p in m["paths"]]
	for d in PATH_DECALS:
		if "path" in d:
			assert sorted(d["path"]) in paths, d["path"]
	m["event_states"] = EVENT_STATES
	m["place_decals"] = PLACE_DECALS
	m["path_decals"] = PATH_DECALS
	m["mod_decals"] = MOD_DECALS
	m["traces"] = TRACES
	m["haze"] = {"tex": "crimson_haze", "phase": ["blood_moon"]}
	m["edge_glow"] = {"decal": "decal_spire_beam", "phase": ["blood_moon"], "from_day": 8}
	dump(P("maps", "forgotten_shore.json"), m)
	# знамя Легиона и голова статуи — навсегда после своих миссий
	sh = load(P("missions", "ch3_shore.json"))
	for mm in sh:
		for mid, place, st in (("SC04", "legion_ruins", "banner"), ("SH23", "statue_hill", "restored")):
			if mm["id"] != mid:
				continue
			for a in mm["actions"]:
				if a.get("retreat"):
					continue
				win = a.setdefault("on_success", [])
				if not any(e.get("cmd") == "map_mark" and e.get("state") == st for e in win):
					win.append(mark(place, st))
	dump(P("missions", "ch3_shore.json"), sh)
	dump(P("tutorial.json"), upsert(load(P("tutorial.json")), HINTS))
	print("встреч: %d, мест: %d" % (len(ms), len(PLACES)))


if __name__ == "__main__":
	main()
