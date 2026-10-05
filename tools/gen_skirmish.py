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
Эффекты: bleed / poison {power, turns}, stun, mark {turns}, guard {turns} (на союзника), riposte {turns}, stealth
{turns}, buff / debuff {stat: dmg|acc|dodge|speed|prot|crit, value, turns}, push / pull {n}, heal {min, max},
psyche {value} (± психика героя).
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
	"Меч": {"dmg": [4, 8], "skill": sk("W_SWORD", "Рубящий удар", frm=(1, 2), to=(1, 2), acc=85, mult=1.0,
		vs={"Мягкое тело": 1.2, "Человек": 1.2}, tags=["Режущий"])},
	"Кинжал": {"dmg": [3, 6], "skill": sk("W_DAGGER", "Укол", frm=(1, 2, 3), to=(1, 2), acc=95, mult=1.0, crit=8,
		vs={"Мягкое тело": 1.3}, tags=["Колющий"])},
	"Копьё": {"dmg": [4, 7], "skill": sk("W_SPEAR", "Выпад копьём", frm=(1, 2, 3), to=(1, 2, 3), acc=85, mult=1.0,
		vs={"Гигант": 1.25, "Летучий": 1.25}, tags=["Колющий"])},
	"Тяжёлое оружие": {"dmg": [6, 11], "skill": sk("W_HEAVY", "Сокрушить", frm=(1, 2), to=(1, 2), acc=75, mult=1.0,
		ignore_prot=0.5, effects=[{"type": "stun", "chance": 30}], vs={"Камень": 1.25, "Конструкт": 1.25, "Кость": 1.15}, tags=["Дробящий"])},
	"Лук": {"dmg": [3, 7], "skill": sk("W_BOW", "Выстрел", frm=(2, 3, 4), to=(1, 2, 3, 4), acc=85, mult=1.0, ranged=True,
		tags=["Колющий"])},
	"Без оружия": {"dmg": [1, 3], "skill": sk("W_FIST", "Удар", frm=(1, 2), to=(1,), acc=90, mult=1.0, tags=["Дробящий"])},
}

# --- природное оружие врагов (weapons.json natural) → разброс и удар ---
NATURAL = {
	"Когти": {"dmg": [3, 6], "skill": sk("N_CLAWS", "Рвущий удар", acc=85, mult=1.0,
		effects=[{"type": "bleed", "power": 1, "turns": 3, "chance": 60}], tags=["Режущий"])},
	"Клыки": {"dmg": [3, 7], "skill": sk("N_FANGS", "Укус", acc=85, mult=1.0, crit=5, tags=["Колющий"])},
	"Жало": {"dmg": [2, 4], "skill": sk("N_STING", "Ужалить", frm=(1, 2, 3), to=(1, 2, 3), acc=85, mult=1.0,
		effects=[{"type": "poison", "power": 2, "turns": 3, "chance": 80}], tags=["Колющий", "Яд"])},
	"Кислота": {"dmg": [2, 5], "skill": sk("N_ACID", "Плевок кислотой", frm=(2, 3, 4), to=(1, 2, 3, 4), acc=80, mult=1.0, ranged=True,
		effects=[{"type": "debuff", "stat": "prot", "value": -0.1, "turns": 3, "chance": 80}], tags=["Кислота"])},
	"Щупальца": {"dmg": [2, 4], "skill": sk("N_TENTACLE", "Захват", frm=(1, 2, 3), to=(1, 2, 3, 4), acc=85, mult=1.0,
		effects=[{"type": "pull", "n": 1, "chance": 80}], tags=["Удушение"])},
	"Тяжёлый удар": {"dmg": [5, 9], "skill": sk("N_SLAM", "Сокрушить", frm=(1, 2), to=(1, 2), aoe=True, acc=75, mult=1.0,
		effects=[{"type": "stun", "chance": 60}, {"type": "push", "n": 1, "chance": 60}], tags=["Дробящий"])},
	"Дальний удар": {"dmg": [3, 6], "skill": sk("N_THROW", "Метнуть", frm=(2, 3, 4), to=(1, 2, 3, 4), acc=85, mult=1.0, ranged=True,
		tags=["Колющий"])},
	"Клинок": {"dmg": [4, 7], "skill": sk("N_BLADE", "Выпад", frm=(1, 2), to=(1, 2, 3), acc=85, mult=1.0, tags=["Режущий"])},
	"Рой": {"dmg": [1, 3], "skill": sk("N_SWARM", "Налететь роем", frm=(1, 2, 3, 4), to=(1, 2, 3, 4), aoe=True, acc=80, mult=1.0,
		tags=["Рой"])},
	"Натиск": {"dmg": [3, 5], "skill": sk("N_RUSH", "Натиск", acc=85, mult=1.0, tags=["Дробящий"])},
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

# --- свойства тегов (docs/24 §4.6) ---
TAG_PROPS = {
	"Панцирь": {"prot": 0.25}, "Броня": {"prot": 0.20}, "Хитин": {"prot": 0.15}, "Чешуя": {"prot": 0.15},
	"Камень": {"prot": 0.30, "immune": ["bleed"], "res": {"stun": 30}},
	"Конструкт": {"immune": ["bleed", "poison"], "res": {"stun": 30}},
	"Сталь": {"prot": 0.10},
	"Мягкое тело": {"res": {"bleed": -25}},
	"Нежить": {"immune": ["poison"]}, "Кость": {"immune": ["bleed"]}, "Бесформенный": {"immune": ["bleed"], "no_corpse": True},
	"Скорость": {"speed": 2, "dodge": 5}, "Первый удар": {"speed": 1, "first": 8},
	"Гигант": {"size": 2, "dodge": -10, "hp": 0.5, "speed": -2, "res": {"move": 50}},
	"Летучий": {"dodge": 10},
	"Скрытность": {"dodge": 5, "stealth_start": True},
	"Стойкость": {"res": {"stun": 20, "move": 20}},
	"Слабое тело": {"hp": -0.2, "speed": -1, "res": {"bleed": -10}},
	"Разумный": {"smart": True},
	"Регенерация": {"regen": 2},
}

# --- параметры врагов по типу (docs/24 §6.1) ---
KINDS = {
	"normal": {"hp": 14, "speed": 4, "acc": 0, "dodge": 5, "res": 20, "dmg": 1.0, "crit": 5},
	"elite": {"hp": 30, "speed": 5, "acc": 5, "dodge": 10, "res": 30, "dmg": 1.15, "crit": 6},
	"boss": {"hp": 70, "speed": 4, "acc": 10, "dodge": 5, "res": 40, "dmg": 1.3, "crit": 8},
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
	for s in GENERIC:
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
	}
	io.open(OUT, "w", encoding="utf-8", newline="\n").write(json.dumps(data, ensure_ascii=False, indent=1) + "\n")
	print("навыков: %d → %s" % (len(skills), OUT))


if __name__ == "__main__":
	main()
