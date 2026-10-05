"""Старты «разбитое стекло» (docs/16 §11.5, StartRules) → data/starts.json и подсказка T103.

Решения владельца: три осколка — Санни / Нефис / Касси; выбор доступен сразу при новой игре (05.10); старт с Берега,
Санни всегда в отряде; сложность словами не подписывать.
    python tools/gen_starts.py
"""
import io
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

STARTS = [
	{"id": "sunny", "hero": "P01", "name": "Санни", "title": "Тень одна",
		"text": "Санни выходит на Забытый Берег один. С ним — Тень, Саван Кукловода и Серебряный Колокольчик. "
			"Осколков почти нет. Спутники найдутся позже — если он доживёт.",
		"heroes": [], "cards": ["U06", "U02"], "shards": 6, "trust": {}, "reveal": False},
	{"id": "nephis", "hero": "P02", "name": "Нефис", "title": "Звезда рядом",
		"text": "Санни и Нефис очнулись рядом и уже доверяют друг другу. Она учит его держать клинок — «Уроки меча "
			"Нефис». Осколков с собой больше.",
		"heroes": ["P02"], "cards": ["U14"], "shards": 20, "trust": {"P01+P02": 3}, "reveal": False},
	{"id": "cassie", "hero": "P03", "name": "Касси", "title": "Голос Оракула",
		"text": "Санни и Касси. Она не видит глазами, но знает Царство Снов и чувствует Берег. В бою от неё мало толку — "
			"зато скрытое в событиях видно сразу.",
		"heroes": ["P03"], "cards": ["K05", "K06"], "shards": 12, "trust": {"P01+P03": 1}, "reveal": True},
]

HINTS = [
	{"id": "T103_start", "event": "start_pick", "chapter": "", "title": "Начало на Берегу", "target": "",
		"text": "Вы начали с Забытого Берега. Санни уже прошёл Первый Кошмар и Академию: с ним Тень. Спутники, карты и "
			"осколки — от выбранного осколка. Остальные герои присоединятся по сюжету."},
]


def dump(p, d):
	io.open(p, "w", encoding="utf-8", newline="\n").write(json.dumps(d, ensure_ascii=False, indent=1) + "\n")


if __name__ == "__main__":
	dump(os.path.join(ROOT, "data", "starts.json"),
		{"_doc": "Старты «разбитое стекло» (StartRules, docs/16 §11.5). Генерируется tools/gen_starts.py — не править руками.",
		"list": STARTS})
	tp = os.path.join(ROOT, "data", "tutorial.json")
	tut = json.load(io.open(tp, encoding="utf-8"))
	ids = [h["id"] for h in HINTS]
	dump(tp, [h for h in tut if h["id"] not in ids] + HINTS)
	print("стартов: %d" % len(STARTS))
