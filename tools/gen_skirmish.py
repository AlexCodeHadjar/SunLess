"""Пошаговый бой «Схватка» (docs/24) → data/combat/skirmish.json: навыки, свойства тегов, параметры врагов, свет.

Ф1 (ядро): навыки оружия героев, удары врагов по природному оружию и тегам, «Шаг» и «Пропуск», свойства тегов
(защита, уклонение, скорость, иммунитеты), параметры врагов по типу (обычный / элита / босс), уровни света.
Ф2 добавит свои навыки героев, навыки карт способностей и усилений, Эхо; Ф3 — особые навыки элиты и боссов.
Не править JSON руками — только здесь (ручные правки врагов — editor_overrides.json, фаза 3).
    python tools/gen_skirmish.py

Навык: id, name, side (enemy | ally | self), from [позиции бойца], to [позиции целей], aoe (по всем целям в to),
acc (база точности), mult (множитель урона оружия) или dmg [от, до] (свой разброс), crit (+%), effects
[{type, chance, …}], self_move (+ назад, − вперёд), cooldown (своих ходов), once (раз за бой), ranged (не ближний бой —
нет контратаки), vs {тег цели: множитель}, vs_mark (прибавка по Метке), ignore_prot (доля защиты не в счёт), tags.
Эффекты: bleed / poison / burn {power, turns}, stun, mark {turns}, guard {turns} (на союзника), riposte {turns},
stealth {turns}, buff / debuff {stat: dmg|acc|dodge|speed|prot|crit, value, turns}, push / pull {n}, heal {min, max},
heal_pct {value}, psyche {value} (± психика героя); Ф2 (свои состояния SunLess): dodge / block {charges} (Уклон,
Панцирь — жетоны), taunt (Приманка), foresight (Предвидение), blind (Ослепление), fear (Страх), sure (верный удар),
empower (следующий удар вдвое), ignite (удары поджигают), steady (не сдвинуть); cleanse {types}, unstealth,
unstealth_all, remove_buffs, swap (поменяться местами с союзником), extra_turn, summon {card} / recall (Эхо),
light_ward {rounds} (тьма не бьёт по психике). У эффекта: self (на себя), if_tag / if_not_tag (теги цели),
light_only / light_not (свет), dark_double (в сумраке и тьме — вдвое).
Ф3 (враги): charm (Очарование: бьёт своих), grab (Захват: не шагнуть и не сдвинуть, 1 урона в ход), whisper
{power} (Кошмарный шёпот: −психика в начале хода), acid (Разъедание: защита −10% до конца боя, до −30%),
summon_enemy {id, n} (призыв приспешников в свободные позиции). У врага (enemies): skills, size, actions (ходов за
раунд), phases [{at: доля здоровья, add: [навыки], text}], escort / minions (состав строя), flee (бегство при ранах).
Навык Ф2: need {first, hp_below, light_not}, cost {psyche}, uses (раз за бой), lifesteal, from_stealth {mult, crit},
dark_bonus {mult, crit}, ignore_prot_vs [теги], pierce_stealth, adjacent / owner (цели-союзники), not_self, weapon.
"""
import io
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "data", "combat", "skirmish.json")


def sk(id, name, side="enemy", frm=(1, 2), to=(1, 2), **kw):
	d = {"id": id, "name": name, "side": side, "from": list(frm), "to": list(to)}
	d.update(kw)
	return d


# --- навыки оружия героев (docs/24 §5.2): ключ — id оружия в weapons.json ---
WEAPONS = {
	"Меч": {"dmg": [6, 11], "skill": sk("W_SWORD", "Рубящий удар", frm=(1, 2), to=(1, 2), acc=85, mult=1.0,
		vs={"Мягкое тело": 1.2, "Человек": 1.2}, tags=["Режущий"])},
	"Кинжал": {"dmg": [4, 8], "skill": sk("W_DAGGER", "Укол", frm=(1, 2, 3), to=(1, 2), acc=95, mult=1.0, crit=8,
		vs={"Мягкое тело": 1.3}, tags=["Колющий"])},
	"Копьё": {"dmg": [5, 10], "skill": sk("W_SPEAR", "Выпад копьём", frm=(1, 2, 3), to=(1, 2, 3), acc=85, mult=1.0,
		vs={"Гигант": 1.25, "Летучий": 1.25}, tags=["Колющий"])},
	"Тяжёлое оружие": {"dmg": [8, 14], "skill": sk("W_HEAVY", "Сокрушить", frm=(1, 2), to=(1, 2), acc=75, mult=1.0,
		ignore_prot=0.5, effects=[{"type": "stun", "chance": 30}], vs={"Камень": 1.25, "Конструкт": 1.25, "Кость": 1.15}, tags=["Дробящий"])},
	"Лук": {"dmg": [4, 9], "skill": sk("W_BOW", "Выстрел", frm=(2, 3, 4), to=(1, 2, 3, 4), acc=85, mult=1.0, ranged=True,
		tags=["Колющий"])},
	"Без оружия": {"dmg": [2, 4], "skill": sk("W_FIST", "Удар", frm=(1, 2), to=(1,), acc=90, mult=1.0, tags=["Дробящий"])},
}

# --- природное оружие врагов (weapons.json natural) → разброс и удар ---
NATURAL = {
	"Когти": {"dmg": [2, 5], "skill": sk("N_CLAWS", "Рвущий удар", acc=85, mult=1.0,
		effects=[{"type": "bleed", "power": 1, "turns": 3, "chance": 60}], tags=["Режущий"])},
	"Клыки": {"dmg": [3, 5], "skill": sk("N_FANGS", "Укус", acc=85, mult=1.0, crit=5, tags=["Колющий"])},
	"Жало": {"dmg": [1, 3], "skill": sk("N_STING", "Ужалить", frm=(1, 2, 3), to=(1, 2, 3), acc=85, mult=1.0,
		effects=[{"type": "poison", "power": 2, "turns": 3, "chance": 80}], tags=["Колющий", "Яд"])},
	"Кислота": {"dmg": [2, 4], "skill": sk("N_ACID", "Плевок кислотой", frm=(2, 3, 4), to=(1, 2, 3, 4), acc=80, mult=1.0, ranged=True,
		effects=[{"type": "debuff", "stat": "prot", "value": -0.1, "turns": 3, "chance": 80}], tags=["Кислота"])},
	"Щупальца": {"dmg": [1, 3], "skill": sk("N_TENTACLE", "Захват", frm=(1, 2, 3), to=(1, 2, 3, 4), acc=85, mult=1.0,
		effects=[{"type": "pull", "n": 1, "chance": 80}], tags=["Удушение"])},
	"Тяжёлый удар": {"dmg": [4, 7], "skill": sk("N_SLAM", "Сокрушить", frm=(1, 2), to=(1, 2), aoe=True, acc=75, mult=1.0,
		effects=[{"type": "stun", "chance": 60}, {"type": "push", "n": 1, "chance": 60}], tags=["Дробящий"])},
	"Дальний удар": {"dmg": [2, 5], "skill": sk("N_THROW", "Метнуть", frm=(2, 3, 4), to=(1, 2, 3, 4), acc=85, mult=1.0, ranged=True,
		tags=["Колющий"])},
	"Клинок": {"dmg": [3, 6], "skill": sk("N_BLADE", "Выпад", frm=(1, 2), to=(1, 2, 3), acc=85, mult=1.0, tags=["Режущий"])},
	"Рой": {"dmg": [1, 2], "skill": sk("N_SWARM", "Налететь роем", frm=(1, 2, 3, 4), to=(1, 2, 3, 4), aoe=True, acc=80, mult=1.0,
		tags=["Рой"])},
	"Натиск": {"dmg": [2, 4], "skill": sk("N_RUSH", "Натиск", acc=85, mult=1.0, tags=["Дробящий"])},
}

# --- навыки врагов от тегов (docs/24 §6.2; Ф1 — состояния Darkest Dungeon) ---
TAG_SKILLS = [
	({"Многоглазый", "Ментальное давление", "Кошмарное существо"}, sk("T_GAZE", "Взгляд бездны", frm=(1, 2, 3, 4), to=(1, 2, 3, 4),
		acc=90, dmg=[0, 0], ranged=True, effects=[{"type": "psyche", "value": -12, "chance": 100}], tags=["Ментальное давление"])),
	({"Тень", "Тьма", "Скрытность"}, sk("T_SHADOW_STRIKE", "Удар из мрака", frm=(1, 2, 3), to=(1, 2, 3, 4), acc=85,
		mult=1.3, effects=[{"type": "stealth", "turns": 1, "chance": 100, "self": True}], tags=["Тень"])),
	({"Предводитель", "Командование"}, sk("T_COMMAND", "Приказ", side="ally", frm=(1, 2, 3, 4), to=(1, 2, 3, 4), aoe=True,
		effects=[{"type": "buff", "stat": "dmg", "value": 0.15, "turns": 2, "chance": 100}], cooldown=2)),
	({"Охота", "Выслеживание"}, sk("T_HUNT_MARK", "Взять след", frm=(2, 3, 4), to=(1, 2, 3, 4), acc=95, dmg=[0, 0], ranged=True,
		effects=[{"type": "mark", "turns": 3, "chance": 100}])),
	({"Дуэль"}, sk("T_DUEL", "Стойка дуэлянта", side="self", frm=(1, 2), to=[],
		effects=[{"type": "riposte", "turns": 2, "chance": 100}], cooldown=2)),
	({"Метание"}, sk("T_VOLLEY", "Град метательных", frm=(3, 4), to=(1, 2, 3), aoe=True, acc=75, mult=0.6, ranged=True)),
	({"Сети", "Ловушка"}, sk("T_NET", "Сеть", frm=(2, 3, 4), to=(1, 2, 3, 4), acc=80, dmg=[0, 0], ranged=True,
		effects=[{"type": "debuff", "stat": "speed", "value": -3, "turns": 2, "chance": 90}, {"type": "pull", "n": 1, "chance": 50}])),
	({"Взгляд"}, sk("T_STONE_GAZE", "Окаменяющий взгляд", frm=(2, 3, 4), to=(1, 2, 3, 4), acc=80, dmg=[0, 0], ranged=True,
		effects=[{"type": "stun", "chance": 50}])),
	({"Пикирование"}, sk("T_DIVE", "Пикирование", frm=(3, 4), to=(1, 2, 3, 4), acc=80, mult=1.2, self_move=3)),
	({"Регенерация", "Оборона"}, sk("T_GUARD_SELF", "Сомкнуться", side="self", frm=(1, 2, 3, 4), to=[],
		effects=[{"type": "buff", "stat": "prot", "value": 0.25, "turns": 2, "chance": 100}], cooldown=2)),
]

GENERIC = [
	sk("STEP", "Шаг", side="self", frm=(1, 2, 3, 4), to=[], kind="step"),
	sk("PASS", "Пропуск", side="self", frm=(1, 2, 3, 4), to=[], kind="pass"),
]

ALL = (1, 2, 3, 4)
DARK = ["dusk", "dark"]

# --- свои навыки героев (docs/24 §5.1): бьют текущим оружием героя ---
HERO_SKILLS = {
	"P01": [
		sk("H_P01_1", "Удар из тени", frm=(1, 2, 3), to=(1, 2), acc=90, mult=1.0, crit=10,
			from_stealth={"mult": 1.5, "crit": 100}, tags=["Тень", "Колющий"]),
		sk("H_P01_2", "Раствориться в тени", side="self", frm=ALL, to=[], self_move=1, cooldown=1,
			effects=[{"type": "stealth", "turns": 2, "light_not": ["bright"]}, {"type": "dodge", "charges": 1, "light_only": ["bright"]}]),
	],
	"P02": [
		sk("H_P02_1", "Удар Меняющейся Звезды", frm=(1, 2), to=(1, 2), acc=90, mult=1.15,
			vs={"Тьма": 1.25, "Тень": 1.25, "Нежить": 1.25}, tags=["Свет", "Режущий"]),
		sk("H_P02_2", "Вызов", side="self", frm=(1, 2, 3), to=[], cooldown=2,
			effects=[{"type": "taunt", "turns": 2}, {"type": "riposte", "turns": 2}], tags=["Дуэль"]),
	],
	"P03": [
		sk("H_P03_1", "Пророчество", frm=(3, 4), to=ALL, acc=100, dmg=[0, 0], ranged=True,
			effects=[{"type": "foresight", "turns": 3, "chance": 100}, {"type": "mark", "turns": 3, "chance": 100}]),
		sk("H_P03_2", "Голос во тьме", side="ally", frm=(2, 3, 4), to=ALL, cooldown=1,
			effects=[{"type": "psyche", "value": 10}, {"type": "cleanse", "types": ["fear"]}]),
	],
	"P04": [
		sk("H_P04_1", "Молниеносный выпад", frm=(1, 2), to=(1, 2, 3), acc=95, mult=0.85,
			effects=[{"type": "buff", "stat": "speed", "value": 3, "turns": 1, "self": True}], tags=["Колющий"]),
		sk("H_P04_2", "Первая кровь", frm=(1, 2), to=(1, 2), acc=90, mult=1.4, need={"first": True},
			effects=[{"type": "bleed", "power": 2, "turns": 3, "chance": 100}], tags=["Режущий"]),
	],
	"P08": [
		sk("H_P08_1", "Удар Девяти", frm=(1, 2), to=(1, 2), acc=85, mult=1.3, effects=[{"type": "stun", "chance": 50}], tags=["Режущий"]),
		sk("H_P08_2", "Стальная стена", side="ally", frm=(1, 2), to=ALL, not_self=True, cooldown=1,
			effects=[{"type": "guard", "turns": 2}, {"type": "block", "charges": 1, "self": True}]),
	],
	"P09": [
		sk("H_P09_1", "Найти слабину", frm=(2, 3, 4), to=ALL, acc=95, dmg=[0, 0], ranged=True,
			effects=[{"type": "mark", "turns": 3, "chance": 100}, {"type": "reveal"}]),
		sk("H_P09_2", "Выследить", frm=(2, 3, 4), to=ALL, acc=95, dmg=[0, 0], ranged=True, pierce_stealth=True,
			effects=[{"type": "unstealth"}, {"type": "debuff", "stat": "dodge", "value": -10, "turns": 2, "chance": 100}]),
	],
	"P10": [
		sk("H_P10_1", "Грязный приём", frm=(1, 2, 3), to=(1, 2), acc=90, mult=0.6, self_move=1,
			effects=[{"type": "blind", "turns": 2, "chance": 80}]),
		sk("H_P10_2", "Ложная тревога", frm=(2, 3, 4), to=ALL, acc=90, dmg=[0, 0], ranged=True, cooldown=1,
			effects=[{"type": "fear", "turns": 2, "chance": 70}]),
	],
}

# --- навыки карт способностей (docs/24 §5.3) ---
ABILITY_SKILLS = {
	"A01": sk("C_A01", "Тень-разведчик", frm=ALL, to=ALL, acc=100, dmg=[0, 0], ranged=True, cooldown=2,
		effects=[{"type": "foresight", "turns": 2, "chance": 100}, {"type": "debuff", "stat": "dodge", "value": -10, "turns": 2, "chance": 100}]),
	"A02": sk("C_A02", "Тень крепнет", side="self", frm=ALL, to=[], cooldown=3, need={"light_not": ["bright"]},
		effects=[{"type": "buff", "stat": "dmg", "value": 0.25, "turns": 3, "dark_double": True},
			{"type": "buff", "stat": "acc", "value": 10, "turns": 3, "dark_double": True}]),
	"A03": sk("C_A03", "Вспышка пламени", side="self", frm=ALL, to=[], once=True, cost={"psyche": -8},
		effects=[{"type": "heal_pct", "value": 0.35}, {"type": "cleanse", "types": ["bleed", "poison"]}, {"type": "ignite", "turns": 2}]),
	"A04": sk("C_A04", "Видение", side="ally", frm=(2, 3, 4), to=ALL, cooldown=2, effects=[{"type": "sure", "turns": 2, "crit": 15}]),
	"A05": sk("C_A05", "Рывок", side="self", frm=ALL, to=[], once=True, effects=[{"type": "extra_turn"}]),
	"A06": sk("C_A06", "Тени не оставят", side="ally", frm=ALL, to=ALL, cooldown=2, effects=[{"type": "dodge", "charges": 2}]),
	"A07": sk("C_A07", "Кровь зовёт", frm=(1, 2, 3), to=(1, 2), acc=90, mult=1.5, lifesteal=0.5, cooldown=2, need={"hp_below": 0.5},
		tags=["Кровь"]),
}


def wcard(id, name, weapon, **kw):
	"""Навык карты-оружия: удар этим оружием (свой разброс урона), с поворотом карты."""
	base = dict(WEAPONS[weapon]["skill"])
	base.update({"id": id, "name": name, "dmg": list(WEAPONS[weapon]["dmg"]), "weapon": weapon})
	base.update(kw)
	return base


# --- навыки карт усиления (docs/24 §5.4) ---
CARD_SKILLS = {
	"U01": wcard("C_U01", "Место становится оружием", "Тяжёлое оружие"),
	"U02": sk("C_U02", "Дальний звон", frm=(2, 3, 4), to=ALL, aoe=True, acc=100, dmg=[0, 0], ranged=True, cooldown=2,
		effects=[{"type": "debuff", "stat": "dmg", "value": -0.2, "turns": 2, "chance": 100},
			{"type": "push", "n": 1, "chance": 100, "if_not_tag": ["Разумный"]}], tags=["Звук"]),
	"U06": sk("C_U06", "Покров", side="ally", frm=ALL, to=ALL, cooldown=2, effects=[{"type": "dodge", "charges": 1}, {"type": "block", "charges": 1}]),
	"K01": sk("C_K01", "Знание Заклинания", frm=ALL, to=ALL, acc=100, dmg=[0, 0], ranged=True,
		effects=[{"type": "remove_buffs"}, {"type": "foresight", "turns": 2, "chance": 100}]),
	"K02": sk("C_K02", "Горы на вашей стороне", side="ally", frm=ALL, to=ALL, aoe=True,
		effects=[{"type": "buff", "stat": "dodge", "value": 5, "turns": 2}]),
	"K03": sk("C_K03", "Раскрыть Аспект", side="self", frm=ALL, to=[], cooldown=2, effects=[{"type": "empower", "turns": 3}]),
	"K04": sk("C_K04", "Знаешь, куда бить", frm=ALL, to=ALL, acc=100, dmg=[0, 0], ranged=True, need={"target_rank_above": True},
		effects=[{"type": "mark", "turns": 2, "chance": 100}, {"type": "debuff", "stat": "dodge", "value": -10, "turns": 2, "chance": 100}]),
	"K05": sk("C_K05", "Знание Царства Снов", frm=ALL, to=ALL, aoe=True, acc=100, dmg=[0, 0], ranged=True, cooldown=3,
		effects=[{"type": "foresight", "turns": 1, "chance": 100}]),
	"K06": sk("C_K06", "Предчувствие", side="ally", frm=ALL, to=ALL, aoe=True, cooldown=2,
		effects=[{"type": "buff", "stat": "dodge", "value": 10, "turns": 1}]),
	"K07": sk("C_K07", "Удар в сустав", frm=(1, 2), to=(1, 2), acc=90, mult=1.1, crit=10, cooldown=1,
		ignore_prot_vs=["Панцирь", "Хитин"], tags=["Колющий"]),
	"K08": sk("C_K08", "Знаешь, где дно", side="ally", frm=ALL, to=ALL, adjacent=True, not_self=True,
		effects=[{"type": "swap"}, {"type": "dodge", "charges": 1, "self": True}]),
	"U14": sk("C_U14", "Тысяча ударов", frm=(1, 2), to=(1, 2), acc=100, mult=1.1, once=True,
		effects=[{"type": "riposte", "turns": 1, "self": True}], tags=["Дуэль", "Режущий"]),
	"U15": sk("C_U15", "Уроки Юлия", side="ally", frm=ALL, to=ALL, cooldown=2,
		effects=[{"type": "cleanse", "types": ["bleed", "poison", "debuff", "blind"]}, {"type": "heal", "min": 3, "max": 3}]),
	"U07": wcard("C_U07", "Удар в сочленение", "Меч", mult=1.05, ignore_prot=1.0),
	"U11": sk("C_U11", "Верёвка", side="ally", frm=ALL, to=ALL, not_self=True, cooldown=2,
		effects=[{"type": "swap"}, {"type": "steady", "turns": 2}]),
	"U12": sk("C_U12", "Призвать Эхо", side="self", frm=ALL, to=[], once=True, effects=[{"type": "summon", "card": "U12"}]),
	"U16": sk("C_U16", "Сомкнуть щит", side="ally", frm=ALL, to=ALL, adjacent=True, not_self=True, once=True,
		effects=[{"type": "guard", "turns": 1}, {"type": "block", "charges": 2, "self": True}]),
	"L01": wcard("C_L01", "Укол хитином", "Кинжал"),
	"L02": sk("C_L02", "Слиться с тенью", side="self", frm=ALL, to=[], effects=[{"type": "stealth", "turns": 1, "dark_double": True}]),
	"L03": sk("C_L03", "Держать страх", side="ally", frm=ALL, to=ALL, effects=[{"type": "psyche", "value": 6}, {"type": "cleanse", "types": ["fear"]}]),
	"L04": sk("C_L04", "Зацепить", frm=(1, 2, 3), to=(2, 3, 4), acc=85, dmg=[2, 4], effects=[{"type": "pull", "n": 1, "chance": 90}]),
	"L05": sk("C_L05", "Глоток", side="ally", frm=ALL, to=ALL, uses=2, effects=[{"type": "heal", "min": 3, "max": 5}]),
	"L06": sk("C_L06", "Бесконечный родник", side="ally", frm=ALL, to=ALL, cooldown=1,
		effects=[{"type": "heal", "min": 4, "max": 6}, {"type": "psyche", "value": 3}]),
	"L07": sk("C_L07", "Принять на наруч", side="self", frm=ALL, to=[], cooldown=1, effects=[{"type": "block", "charges": 2}]),
	"L08": wcard("C_L08", "Ядовитый укол", "Кинжал", effects=[{"type": "poison", "power": 2, "turns": 3, "chance": 80}]),
	"L09": sk("C_L09", "Хлыст", frm=(1, 2, 3), to=(2, 3), acc=85, dmg=[2, 5], cooldown=1,
		effects=[{"type": "pull", "n": 1, "chance": 80}, {"type": "debuff", "stat": "speed", "value": -2, "turns": 2, "chance": 80}]),
	"L10": sk("C_L10", "Глаз глубин", frm=ALL, to=ALL, acc=100, dmg=[0, 0], ranged=True, cooldown=1, pierce_stealth=True,
		effects=[{"type": "foresight", "turns": 2, "chance": 100}, {"type": "unstealth_all"}]),
	"L11": wcard("C_L11", "Клинок режет своих", "Меч", mult=1.05, ignore_prot_vs=["Панцирь", "Хитин"]),
	"L12": sk("C_L12", "Щит Легиона", side="ally", frm=ALL, to=ALL, adjacent=True, not_self=True, once=True,
		effects=[{"type": "guard", "turns": 2}, {"type": "block", "charges": 1, "self": True}]),
	"L13": wcard("C_L13", "Удар Легиона", "Копьё"),
	"L14": sk("C_L14", "Сердце бури", frm=ALL, to=(2, 3, 4), acc=85, dmg=[4, 8], ranged=True, once=True,
		effects=[{"type": "stun", "chance": 25}], tags=["Молния"]),
	"L15": wcard("C_L15", "Клинок пьёт темноту", "Меч", mult=1.1, dark_bonus={"mult": 0.25, "crit": 10}),
	"L16": sk("C_L16", "Призвать Эхо Центуриона", side="self", frm=ALL, to=[], once=True, effects=[{"type": "summon", "card": "L16"}]),
	"L17": sk("C_L17", "За мной!", side="ally", frm=ALL, to=ALL, aoe=True, once=True,
		effects=[{"type": "buff", "stat": "dmg", "value": 0.15, "turns": 2}, {"type": "buff", "stat": "acc", "value": 10, "turns": 2},
			{"type": "psyche", "value": 5}]),
	"LW1": sk("C_LW1", "Уйти в раковину", side="self", frm=ALL, to=[], once=True,
		effects=[{"type": "block", "charges": 3}, {"type": "buff", "stat": "prot", "value": 0.25, "turns": 2}, {"type": "riposte", "turns": 2}]),
	"LW2": sk("C_LW2", "Удар из-под земли", frm=ALL, to=ALL, acc=95, mult=1.2, once=True, ignore_prot=1.0, pierce_stealth=True,
		tags=["Пепел"]),
	"LW3": sk("C_LW3", "Высветить", frm=ALL, to=ALL, aoe=True, acc=100, dmg=[0, 0], ranged=True, once=True, pierce_stealth=True,
		effects=[{"type": "unstealth"}, {"type": "mark", "turns": 2, "chance": 100}, {"type": "light_ward", "rounds": 3, "self": True}],
		tags=["Свет"]),
	"LW4": sk("C_LW4", "Звон осколка", frm=ALL, to=ALL, aoe=True, acc=90, dmg=[3, 5], ranged=True, once=True,
		vs={"Рой": 2.0, "Стая": 2.0}, effects=[{"type": "debuff", "stat": "dmg", "value": -0.15, "turns": 2, "chance": 100,
			"if_tag": ["Рой", "Стая"]}], tags=["Стекло", "Звук"]),
}
CARD_PASSIVE = {"L07": {"prot": 0.10}, "U16": {"prot": 0.15}, "L13": {"first": 8}}

# --- Эхо (docs/24 §4.13): своё здоровье и 2 навыка, третий — «Отозвать» ---
ECHO_SKILLS = [
	sk("E_CLAWS", "Клешни", acc=85, dmg=[3, 6], effects=[{"type": "bleed", "power": 1, "turns": 3, "chance": 60}], tags=["Режущий"]),
	sk("E_SHELL", "Панцирный заслон", side="ally", frm=(1, 2), to=ALL, owner=True, cooldown=1,
		effects=[{"type": "guard", "turns": 2}, {"type": "block", "charges": 1, "self": True}]),
	sk("E_SICKLE", "Серповидный выпад", frm=(1, 2, 3), to=(1, 2, 3), acc=85, dmg=[4, 8], tags=["Режущий"]),
	sk("E_LEGION", "Строй Легиона", side="ally", frm=(1, 2), to=ALL, adjacent=True, not_self=True, cooldown=1,
		effects=[{"type": "guard", "turns": 1}, {"type": "riposte", "turns": 2, "self": True}]),
	sk("ECHO_RECALL", "Отозвать", side="self", frm=ALL, to=[], kind="recall"),
]
# --- враги (docs/24 §6): особые навыки элиты и боссов, размер, ходы, фазы, свита ---
ENEMY_SKILLS = [
	sk("X_PIERCE", "Пронзающий бросок", frm=(2, 3, 4), to=ALL, acc=85, mult=1.3, ranged=True,
		effects=[{"type": "bleed", "power": 2, "turns": 3, "chance": 70}], tags=["Колющий"]),
	sk("X_FORMATION", "Строй Легиона", side="ally", frm=ALL, to=ALL, not_self=True, cooldown=2,
		effects=[{"type": "guard", "turns": 2}, {"type": "riposte", "turns": 2, "self": True}]),
	sk("X_SHELL", "Панцирь Демона", side="self", frm=ALL, to=[], cooldown=3, effects=[{"type": "block", "charges": 2}]),
	sk("X_CRACK", "Раскол", frm=(1, 2), to=(1, 2), aoe=True, acc=80, mult=0.9,
		effects=[{"type": "push", "n": 1, "chance": 70}, {"type": "acid", "chance": 60}], tags=["Дробящий"]),
	sk("X_DEVOUR_SOUL", "Пожрать душу", frm=(1, 2, 3), to=(1, 2, 3), acc=85, mult=1.2, lifesteal=0.5,
		effects=[{"type": "psyche", "value": -10, "chance": 100}], tags=["Пожирание душ"]),
	sk("X_COLONY", "Ярость колонии", side="ally", frm=ALL, to=ALL, aoe=True, cooldown=3,
		effects=[{"type": "buff", "stat": "dmg", "value": 0.2, "turns": 2}]),
	sk("X_DARK_LUNGE", "Тёмный выпад", frm=(1, 2), to=(1, 2, 3), acc=90, mult=1.5, ignore_prot=0.5, cooldown=1, tags=["Режущий", "Тьма"]),
	sk("X_CURSE", "Проклятие", frm=ALL, to=ALL, acc=90, dmg=[0, 0], ranged=True, cooldown=1,
		effects=[{"type": "debuff", "stat": "dmg", "value": -0.25, "turns": 2, "chance": 90}, {"type": "whisper", "power": 3, "turns": 3, "chance": 90}]),
	sk("X_ROAR", "Рёв Короля", frm=ALL, to=ALL, aoe=True, acc=100, dmg=[0, 0], ranged=True, cooldown=2,
		effects=[{"type": "psyche", "value": -8, "chance": 100}, {"type": "fear", "turns": 2, "chance": 50}]),
	sk("X_RAISE", "Поднять мёртвых", side="self", frm=(2, 3, 4), to=[], cooldown=3, effects=[{"type": "summon_enemy", "id": "M27", "n": 2}]),
	sk("X_DEATH_WHISPER", "Шёпот смерти", frm=(2, 3, 4), to=ALL, aoe=True, acc=90, dmg=[0, 0], ranged=True, cooldown=2,
		effects=[{"type": "whisper", "power": 3, "turns": 3, "chance": 80}]),
	sk("X_BONE_BOLT", "Костяной снаряд", frm=(2, 3, 4), to=ALL, acc=85, dmg=[3, 6], ranged=True, tags=["Кость"]),
	sk("X_MIND_PRESS", "Ментальное давление", frm=ALL, to=ALL, aoe=True, acc=100, dmg=[0, 0], ranged=True, cooldown=1,
		effects=[{"type": "psyche", "value": -8, "chance": 100}, {"type": "charm", "turns": 1, "chance": 25}]),
	sk("X_CORAL_SPIKES", "Коралловые шипы", frm=(1, 2), to=(1, 2), aoe=True, acc=85, mult=0.8,
		effects=[{"type": "bleed", "power": 2, "turns": 3, "chance": 80}], tags=["Коралл"]),
	sk("X_HERMIT_SHELL", "Уйти в раковину", side="self", frm=ALL, to=[], cooldown=3,
		effects=[{"type": "block", "charges": 3}, {"type": "riposte", "turns": 2}]),
	sk("X_CRUSH", "Раздавить", frm=(1, 2), to=(1, 2), acc=85, mult=1.6, effects=[{"type": "stun", "chance": 60}], tags=["Дробящий"]),
	sk("X_UNDER", "Удар из-под земли", frm=ALL, to=ALL, acc=90, mult=1.3, pierce_stealth=True, cooldown=1, tags=["Пепел"]),
	sk("X_HEAT", "Жар", frm=ALL, to=(1, 2, 3), aoe=True, acc=85, mult=0.6, ranged=True,
		effects=[{"type": "burn", "power": 2, "turns": 2, "chance": 80}], tags=["Жар", "Огонь"]),
	sk("X_COIL", "Обвить", frm=(1, 2), to=(1, 2, 3), acc=85, mult=0.7, effects=[{"type": "grab", "turns": 3, "chance": 80}]),
	sk("X_LANTERN", "Фонарь Ловчего", frm=ALL, to=ALL, aoe=True, acc=100, dmg=[0, 0], ranged=True, pierce_stealth=True, cooldown=2,
		effects=[{"type": "unstealth"}, {"type": "mark", "turns": 2, "chance": 100}]),
	sk("X_HUNT", "Охота началась", side="self", frm=ALL, to=[], cooldown=3,
		effects=[{"type": "buff", "stat": "speed", "value": 4, "turns": 2}, {"type": "stealth", "turns": 1}]),
	sk("X_GLASS_SWARM", "Рой стекла", frm=ALL, to=ALL, aoe=True, acc=80, mult=0.5, ranged=True,
		effects=[{"type": "bleed", "power": 1, "turns": 3, "chance": 70}], tags=["Стекло", "Рой"]),
	sk("X_GLASS_RING", "Звон стекла", frm=ALL, to=ALL, aoe=True, acc=100, dmg=[0, 0], ranged=True, cooldown=2,
		effects=[{"type": "psyche", "value": -6, "chance": 100}, {"type": "blind", "turns": 1, "chance": 40}]),
	sk("X_CALL_SWARM", "Призвать рой", side="self", frm=ALL, to=[], cooldown=4, effects=[{"type": "summon_enemy", "id": "M38", "n": 1}]),
	sk("X_CHARM", "Зов", frm=(2, 3, 4), to=ALL, acc=85, dmg=[0, 0], ranged=True, cooldown=2,
		effects=[{"type": "charm", "turns": 1, "chance": 70}], tags=["Очарование"]),
	sk("X_GRAB", "Схватить", frm=(1, 2, 3), to=ALL, acc=85, mult=0.6,
		effects=[{"type": "pull", "n": 3, "chance": 90}, {"type": "grab", "turns": 3, "chance": 80}], tags=["Удушение"]),
	sk("X_ACID", "Едкий плевок", frm=(2, 3, 4), to=ALL, acc=85, mult=0.8, ranged=True,
		effects=[{"type": "acid", "chance": 80}], tags=["Кислота"]),
	sk("X_DEVOUR", "Пожрать падаль", side="self", frm=(1, 2), to=[], cooldown=2, effects=[{"type": "devour"}]),
]
# особые навыки и свойства врагов; «skills» добавляются к удару природным оружием и навыкам от тегов
ENEMY = {
	"M04": {"skills": ["X_PIERCE", "X_FORMATION"], "escort": ["M03", "M03"]},
	"M05": {"skills": ["X_SHELL", "X_CRACK"], "size": 2, "escort": ["M03", "M04"]},
	"M11": {"skills": ["X_DEVOUR_SOUL"]},
	"M21": {"skills": ["X_COLONY"]},
	"M25": {"skills": ["X_DARK_LUNGE"], "escort": ["M27", "M27"]},
	"M35": {"skills": ["X_CURSE"], "escort": ["M24"]},
	"M02": {"skills": ["X_ROAR"], "actions": 2, "minions": ["M01", "M01"],
		"phases": [{"at": 0.5, "add": ["X_CRUSH"], "text": "Горный Король в ярости — бьёт, не разбирая"}]},
	"M26": {"skills": ["X_RAISE", "X_DEATH_WHISPER", "X_BONE_BOLT"], "minions": ["M27", "M27"],
		"phases": [{"at": 0.5, "add": ["X_CURSE"], "text": "Повелитель Мёртвых проклинает живых"}]},
	"M37": {"skills": ["X_MIND_PRESS", "X_CORAL_SPIKES"], "size": 2, "actions": 2, "minions": ["M36"],
		"phases": [{"at": 0.5, "add": ["X_CHARM"], "text": "Багровый Ужас пробуждается — свет зовёт"}]},
	"MW1": {"skills": ["X_HERMIT_SHELL", "X_CRUSH"], "actions": 2,
		"phases": [{"at": 0.4, "add": ["X_CORAL_SPIKES"], "text": "Раковина треснула — Отшельник в ярости"}]},
	"MW2": {"skills": ["X_UNDER", "X_HEAT", "X_COIL"], "actions": 2,
		"phases": [{"at": 0.5, "add": ["X_DEVOUR"], "text": "Пепельный Змей раскаляется"}]},
	"MW3": {"skills": ["X_LANTERN", "X_HUNT"], "actions": 2,
		"phases": [{"at": 0.5, "add": ["X_DARK_LUNGE"], "text": "Охота началась всерьёз"}]},
	"MW4": {"skills": ["X_GLASS_SWARM", "X_GLASS_RING", "X_CALL_SWARM"], "actions": 2,
		"phases": [{"at": 0.5, "add": ["X_ACID"], "text": "Стеклянная Королева треснула — осколки режут"}]},
	"M03": {"skills": ["X_DEVOUR"]},
	"M28": {"skills": ["X_DEVOUR"]},
	"M08": {"skills": ["X_GRAB"]},
	"M09": {"skills": ["X_GRAB"]},
	"M12": {"skills": ["X_GRAB"]},
	"M10": {"skills": ["X_CHARM"], "size": 2},
	"M34": {"skills": ["X_CHARM"]},
	"M06": {"skills": ["X_ACID"]},
	"M33": {"flee": True},
	"M38": {"flee": True},
}

ECHOES = {
	"U12": {"base": "M03", "name": "Эхо Падальщика", "skills": ["E_CLAWS", "E_SHELL", "ECHO_RECALL"]},
	"L16": {"base": "M04", "name": "Эхо Центуриона", "skills": ["E_SICKLE", "E_LEGION", "ECHO_RECALL"]},
}

# --- свойства тегов (docs/24 §4.6) ---
TAG_PROPS = {
	"Панцирь": {"prot": 0.25}, "Броня": {"prot": 0.20}, "Хитин": {"prot": 0.15}, "Чешуя": {"prot": 0.15},
	"Камень": {"prot": 0.30, "immune": ["bleed"], "res": {"stun": 30}},
	"Конструкт": {"immune": ["bleed", "poison"], "res": {"stun": 30}},
	"Сталь": {"prot": 0.10},
	"Мягкое тело": {"res": {"bleed": -25}},
	"Нежить": {"immune": ["poison"]}, "Кость": {"immune": ["bleed"]}, "Бесформенный": {"immune": ["bleed"], "no_corpse": True},
	"Скорость": {"speed": 2, "dodge": 5}, "Первый удар": {"speed": 1, "first": 8},
	"Гигант": {"size": 2, "dodge": -10, "hp": 0.25, "speed": -2, "res": {"move": 50}},
	"Летучий": {"dodge": 10},
	"Скрытность": {"dodge": 5, "stealth_start": True},
	"Стойкость": {"res": {"stun": 20, "move": 20}},
	"Слабое тело": {"hp": -0.2, "speed": -1, "res": {"bleed": -10}},
	"Разумный": {"smart": True},
	"Слепота": {"immune": ["blind"]},
	"Регенерация": {"regen": 2},
	"Ярость": {"rage": True}, "Жажда крови": {"rage": True},
	"Трус": {"flee": True},
}

# --- параметры врагов по типу (docs/24 §6.1) ---
KINDS = {
	"normal": {"hp": 14, "speed": 4, "acc": 0, "dodge": 5, "res": 20, "dmg": 1.0, "crit": 5},
	"elite": {"hp": 26, "speed": 5, "acc": 5, "dodge": 10, "res": 30, "dmg": 1.15, "crit": 6},
	"boss": {"hp": 44, "speed": 4, "acc": 8, "dodge": 5, "res": 40, "dmg": 1.0, "crit": 6},
}

# --- свет (docs/24 §4.10) ---
LIGHT = {
	"bright": {"name": "Яркий", "hero_dodge": 5, "hero_crit": 0, "enemy_acc": 0, "enemy_dmg": 0.0, "enemy_crit": 0, "psyche": 0, "loot": 0.0},
	"dim": {"name": "Тусклый", "hero_dodge": 0, "hero_crit": 0, "enemy_acc": 0, "enemy_dmg": 0.0, "enemy_crit": 1, "psyche": -1, "loot": 0.10},
	"dusk": {"name": "Сумрак", "hero_dodge": 0, "hero_crit": 2, "enemy_acc": 5, "enemy_dmg": 0.10, "enemy_crit": 0, "psyche": -2, "loot": 0.25},
	"dark": {"name": "Тьма", "hero_dodge": 0, "hero_crit": 3, "enemy_acc": 10, "enemy_dmg": 0.20, "enemy_crit": 3, "psyche": -3, "loot": 0.50},
}

# любимые позиции врагов: ближний бой вперёд, дальний назад
RANGED_TAGS = ["Дальний удар", "Метание", "Кислота", "Ментальное давление", "Призыв", "Предводитель", "Командование", "Сети"]


def main():
	skills = {}
	for w in WEAPONS.values():
		skills[w["skill"]["id"]] = w["skill"]
	for n in NATURAL.values():
		skills[n["skill"]["id"]] = n["skill"]
	for _, s in TAG_SKILLS:
		skills[s["id"]] = s
	for s in GENERIC + ECHO_SKILLS + ENEMY_SKILLS + list(ABILITY_SKILLS.values()) + list(CARD_SKILLS.values()):
		skills[s["id"]] = s
	for lst in HERO_SKILLS.values():
		for s in lst:
			skills[s["id"]] = s
	data = {
		"_doc": "Пошаговый бой «Схватка» (docs/24). Генерирует tools/gen_skirmish.py — не править руками.",
		"skills": skills,
		"weapons": {k: {"dmg": v["dmg"], "skill": v["skill"]["id"]} for k, v in WEAPONS.items()},
		"natural": {k: {"dmg": v["dmg"], "skill": v["skill"]["id"]} for k, v in NATURAL.items()},
		"tag_skills": [{"tags": sorted(t), "skill": s["id"]} for t, s in TAG_SKILLS],
		"tag_props": TAG_PROPS,
		"kinds": KINDS,
		"light": LIGHT,
		"ranged_tags": RANGED_TAGS,
		"heroes": {cid: [s["id"] for s in lst] for cid, lst in HERO_SKILLS.items()},
		"cards": dict({k: v["id"] for k, v in ABILITY_SKILLS.items()}, **{k: v["id"] for k, v in CARD_SKILLS.items()}),
		"card_passive": CARD_PASSIVE,
		"echoes": ECHOES,
		"enemies": ENEMY,
	}
	io.open(OUT, "w", encoding="utf-8", newline="\n").write(json.dumps(data, ensure_ascii=False, indent=1) + "\n")
	print("навыков: %d → %s" % (len(skills), OUT))


if __name__ == "__main__":
	main()
