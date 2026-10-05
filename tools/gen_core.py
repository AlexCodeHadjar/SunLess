"""Ядро души (docs/23, CoreRules): испытания души → data/missions/trials.json, противники-Отражения MT1/MT2
(enemies.json и editor_overrides.json), подсказки T104–T105.

Испытание — на каждого героя в каждой главе и для двух переходов: TR1_<глава>_<герой> (к Пробуждённому) и
TR2_<глава>_<герой> (к Вознесённому). Открывается, когда ядро героя полно (CoreRules.ensure_trials); приходит к
фигуре (как Натиск): провести можно там, где стоит отряд. Бой один на один с Отражением следующего ранга.
    python tools/gen_core.py
"""
import io
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def P(*p):
	return os.path.join(ROOT, "data", *p)


def load(p):
	return json.load(io.open(p, encoding="utf-8"))


def dump(p, d):
	io.open(p, "w", encoding="utf-8", newline="\n").write(json.dumps(d, ensure_ascii=False, indent=1) + "\n")


ENEMIES = [
	{"id": "MT1", "name": "Отражение Пробуждённого", "rank": 1, "class": 2, "kind": "elite", "shards": 0,
		"tags": ["Зеркало", "Тень", "Эхо", "Кошмарное существо", "Разумный"]},
	{"id": "MT2", "name": "Отражение Вознесённого", "rank": 2, "class": 2, "kind": "elite", "shards": 0,
		"tags": ["Зеркало", "Тень", "Эхо", "Кошмарное существо", "Разумный", "Регенерация"]},
]
FIELDS = {"nightmare": "F_04", "academy": "F_02", "shore": "F_17", "tree": "F_18", "dark_city": "F_06", "city": "F_06"}

HINTS = [
	{"id": "T104_core", "event": "core", "chapter": "", "title": "Ядро души", "target": "",
		"text": "Осколки душ можно не только тратить в лавке, но и впитать в ядро героя — в его планшете, в любой момент. "
			"Каждый уровень ядра — +1 к характеристике на ваш выбор. Пять уровней — ядро полно, и героя ждёт испытание души."},
	{"id": "T105_core_trial", "event": "core_trial", "chapter": "", "title": "Испытание души", "target": "marker_trial",
		"text": "Ядро героя полно. Испытание души приходит к фигуре: герой бьётся один с Отражением следующего ранга. Победа — "
			"новый ранг: враги этого ранга станут ему равны, и +1 ко всем характеристикам. Проигрыш — грань смерти, испытание ждёт."},
]


def main():
	locs = load(P("locations.json"))
	chars = load(P("characters.json"))
	missions = []
	for chapter, field in FIELDS.items():
		place = next((l["id"] for l in locs if l.get("chapter") == chapter), None)
		assert place, chapter
		for c in chars:
			for tr, enemy, rank_name in [(1, "MT1", "Пробуждённого"), (2, "MT2", "Вознесённого")]:
				mid = "TR%d_%s_%s" % (tr, chapter, c["id"])
				missions.append({
					"id": mid, "location": place, "type": "side", "trial": c["id"],
					"title": "Испытание души: %s" % c["name"],
					"briefing": "Ядро души %s наполнилось. Чтобы подняться выше, нужно встретить себя — Отражение %s, "
						"соткано из того же света и той же тьмы. Только один на один." % (c["name"], rank_name),
					"arrival": "Воздух густеет. Напротив встаёт фигура — то же лицо, только глаза пустые.",
					"rumors": [], "threat": 4, "duration": 5, "rest": 0, "squad": {"min": 1, "max": 1},
					"requires_heroes": [c["id"]], "enemies": [enemy], "field": field, "known_tags": ["Зеркало", "Тень"],
					"hidden_tags": [], "context": ["combat"],
					"actions": [
						{"id": mid + "_fight", "label": "Встретить Отражение", "text": "Бой один на один.",
							"stages": [{"name": "Отражение", "combat": {"enemies": [enemy], "field": field, "power": 0.8},
								"ok": "Отражение рассыпается светом — и этот свет теперь твой.",
								"fail": "Отражение сильнее. Пока."}],
							"on_success": [{"cmd": "core_rank", "character": c["id"]}]},
						{"id": mid + "_retreat", "label": "Не сейчас", "text": "Отступить — испытание подождёт.", "retreat": True},
					],
				})
	dump(P("missions", "trials.json"), missions)
	enemies = load(P("combat", "enemies.json"))
	ov_path = P("combat", "editor_overrides.json")
	ov = load(ov_path) if os.path.exists(ov_path) else {}
	ov.setdefault("enemies", {})
	for e in ENEMIES:
		idx = next((i for i, x in enumerate(enemies) if x["id"] == e["id"]), None)
		if idx is None:
			enemies.append(dict(e))
		else:
			enemies[idx] = dict(e)
		ov["enemies"][e["id"]] = dict(e)
	dump(P("combat", "enemies.json"), enemies)
	dump(ov_path, ov)
	tut = [h for h in load(P("tutorial.json")) if h["id"] not in [x["id"] for x in HINTS]] + HINTS
	dump(P("tutorial.json"), tut)
	print("испытаний: %d" % len(missions))


if __name__ == "__main__":
	main()
