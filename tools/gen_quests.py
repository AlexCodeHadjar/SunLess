"""Задания справа на экране карты (docs/20, QuestRules) → data/quests.json (цель каждой главы одной строкой)
и подсказка обучения T99 в data/tutorial.json.

Сами задания собираются из состояния (сюжет, побочные линии колоды, угрозы) — здесь только то, чего в состоянии нет.
    python tools/gen_quests.py
"""
import io
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

GOALS = {
	"nightmare": "Пережить Первый Кошмар: пройти с караваном через горы к Храму Бога Теней",
	"academy": "Пережить месяцы Академии и подготовиться к Зимнему солнцестоянию",
	"shore": "Выжить на Забытом Береге и найти путь к Багровому Шпилю",
	"tree": "Пройти Пепельное море к Древу Души и выйти к Звёздному берегу",
	"dark_city": "Закрепиться в Мрачном городе и спуститься в катакомбы",
	"city": "Удержать город людей и закрыть Восхождённые Врата",
}

HINTS = [
	{"id": "T99_quests", "event": "quests", "chapter": "", "title": "Задания", "target": "quests",
		"text": "Справа — задания: что двигает сюжет (золотом), побочные линии (серебром) и угрозы (красным), где это и сколько "
			"идти. Нажмите на значок-прицел — карта покажет место и путь от фигуры. «ЗАДАНИЯ» — свернуть список."},
]


def dump(p, d):
	io.open(p, "w", encoding="utf-8", newline="\n").write(json.dumps(d, ensure_ascii=False, indent=1) + "\n")


if __name__ == "__main__":
	dump(os.path.join(ROOT, "data", "quests.json"),
		{"_doc": "Задания (QuestRules, docs/20): цель главы. Генерируется tools/gen_quests.py — не править руками.", "goals": GOALS})
	tp = os.path.join(ROOT, "data", "tutorial.json")
	tut = json.load(io.open(tp, encoding="utf-8"))
	ids = [h["id"] for h in HINTS]
	tut = [h for h in tut if h["id"] not in ids] + HINTS
	dump(tp, tut)
	print("целей глав: %d, подсказок: %d" % (len(GOALS), len(HINTS)))
