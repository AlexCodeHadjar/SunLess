"""Генератор боевых данных из docs/12 — Боевая система, теги и живая кампания.md.

Документ — источник правды: таблицы разделов 7.1–7.17 превращаются в data/combat/*.json.
Запуск: python tools/gen_combat_data.py [путь_к_документу]
"""
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "docs", "12 — Боевая система, теги и живая кампания.md")
OUT = os.path.join(ROOT, "data", "combat")

CATEGORY_BY_SECTION = {
    "7.1": "element", "7.2": "material", "7.3": "anatomy", "7.4": "tactic", "7.5": "mystic",
    "7.6": "mind", "7.7": "state", "7.8": "origin", "7.9": "sense",
}
# Базовая ценность тега (вклад в шаг 3), если тег просто есть у стороны.
BASE_VALUE = {
    "element": 0.12, "material": 0.08, "anatomy": 0.10, "tactic": 0.10, "mystic": 0.12,
    "mind": 0.08, "state": 0.0, "origin": 0.0, "sense": 0.0, "field": 0.0, "time": 0.0,
}
STATE_PENALTY = {"Ранен": -0.05, "Истощение": -0.10, "Переохлаждение": -0.05, "Оглушён": -0.20,
                 "Ослеплён": -0.15, "Горит": -0.10, "Отравлен": -0.10, "Боль": -0.10, "Паника": -0.20,
                 "Уязвимость": -0.20, "Настороженность": 0.10, "Кровотечение": -0.05}
RANK_HUMAN = {"Спящий": 0, "Пробуждённый": 1, "Вознесённый": 2, "Трансцендентный": 3, "Верховный": 4}
RANK_CREATURE = {"Спящий": 0, "Пробуждённый": 1, "Падший": 2, "Порченый": 3, "Великий": 4, "Проклятый": 5, "Нечестивый": 6}
CLASS = {"Зверь": 1, "Монстр": 2, "Демон": 3, "Дьявол": 4, "Тиран": 5, "Ужас": 6, "Титан": 7, "Конструкт": 2}

text = io.open(DOC, encoding="utf-8").read()
sections = re.split(r"\n## (7\.\d+)\. ", text)
sec = {}
for i in range(1, len(sections), 2):
    sec[sections[i]] = sections[i + 1].split("\n## ")[0].split("\n# ")[0]


def rows(block):
    out = []
    for line in block.splitlines():
        if not line.startswith("|") or line.startswith("|---"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        out.append(cells)
    return out[1:]  # без заголовка


def ticks(s):
    return re.findall(r"`([^`]+)`", s)


def pct_effects(s):
    """«`Стая` +15%, `Гигант` −40%» → [(тег, 0.15), (тег, -0.40)]"""
    res = []
    for m in re.finditer(r"`([^`]+)`(?:\s*/\s*`[^`]+`)*\s*([+−-]\d+)%", s):
        group = re.findall(r"`([^`]+)`", m.group(0))
        v = int(m.group(2).replace("−", "-")) / 100.0
        for t in group:
            res.append((t, v))
    return res


tags = {}


def add_tag(name, category, desc, value=None):
    name = name.strip().strip("*")
    if not name or name in tags:
        return
    if value is None:
        value = STATE_PENALTY.get(name, BASE_VALUE.get(category, 0.0))
    tags[name] = {"id": name, "name": name, "category": category, "text": desc, "value": round(value, 2)}


for key, cat in CATEGORY_BY_SECTION.items():
    for c in rows(sec[key]):
        name = c[0].replace("**", "")
        if "/" in name and cat == "origin":
            continue  # строки-группы рангов и классов
        add_tag(name, cat, c[1])

# --- поля боя (7.10) и время/погода (7.11) ---------------------------------
fields = []
for c in rows(sec["7.10"]):
    name = c[0].replace("**", "")
    ftags = ticks(c[1])
    effects = [{"tag": t, "value": v} for t, v in pct_effects(c[2])]
    fid = "F_" + str(len(fields) + 1).zfill(2)
    fields.append({"id": fid, "name": name, "tags": ftags, "effects": effects, "text": re.sub(r"`", "", c[2])})
    for t in ftags:
        add_tag(t, "field", "Свойство места: " + name + ".")
for c in rows(sec["7.11"]):
    name = c[0].replace("**", "")
    add_tag(name, "time", re.sub(r"`", "", c[1]))
    effects = [{"tag": t, "value": v} for t, v in pct_effects(c[1])]
    fields.append({"id": "T_" + str(len(fields) + 1).zfill(2), "name": name, "tags": [name], "effects": effects,
                   "text": re.sub(r"`", "", c[1]), "weather": True})

FIELD_ALIASES = {"Болото": "Болото", "Буран": "Буран", "Гроза": "Гроза", "Кладбище костей": "Кладбище",
                 "Лабиринт кораллов": "Лабиринт кораллов", "Тёмное море (прилив)": "Прилив", "Горный путь": "Скалы"}
for f in fields:
    alias = FIELD_ALIASES.get(f["name"])
    if alias and alias not in f["tags"]:
        f["tags"].append(alias)
    if not f.get("weather") and "Глубина" not in f["tags"]:
        f["tags"].append("суша")

# --- карты раунда (7.12) ------------------------------------------------------
STAT_WORDS = {"Воля": "will", "Хитрость": "cunning", "Сила": "power"}
round_cards = []
for i, c in enumerate(rows(sec["7.12"])):
    rtags = ticks(c[1])
    stat = ""
    for w, s in STAT_WORDS.items():
        if "характеристика раунда: " + w in c[2]:
            stat = s
    effects = [{"tag": t, "value": v} for t, v in pct_effects(c[2])]
    special = ""
    if "+1 карта противника" in c[2]:
        special = "add_enemy"
    elif "герою +10%" in c[2]:
        effects.append({"tag": "*hero", "value": 0.10})
    elif "износа" in c[2]:
        special = "wear"
    round_cards.append({"id": "R" + str(i + 1).zfill(2), "name": c[0], "tags": rtags, "stat": stat,
                        "effects": effects, "special": special, "text": re.sub(r"`", "", c[2])})
    for t in rtags:
        add_tag(t, "time" if t in ("Затмение", "Рассвет", "Ночь") else "sense", "Условие раунда.")

# --- носители ---------------------------------------------------------------------
carriers = {"characters": {}, "enhancements": {}, "enemies": []}
for c in rows(sec["7.13"]):
    carriers["characters"][c[0].replace("**", "")] = {"rank": c[1], "tags": ticks(c[2])}
for c in rows(sec["7.14"]):
    cid = c[0].split(" ")[0]
    carriers["enhancements"][cid] = ticks(c[1])
for c in rows(sec["7.15"]):
    rank_s, _, class_s = c[2].partition("·")
    rank_s = rank_s.strip()
    class_s = class_s.strip()
    rank = 1
    for k, v in RANK_CREATURE.items():
        if k in rank_s:
            rank = v
    if rank_s.startswith("≥"):
        rank = 1
    cls = 1
    for k, v in CLASS.items():
        if k in class_s:
            cls = v
    carriers["enemies"].append({"ids": c[0], "name": c[1], "rank": rank, "class": cls, "tags": ticks(c[3])})

# --- симбиозы (7.16) и конфликты (7.17) --------------------------------------------
synergies = []
for c in rows(sec["7.16"]):
    group = ticks(c[0])
    bonus = re.search(r"([+−-]\d+)%", c[2])
    synergies.append({"id": "SYN_" + str(len(synergies) + 1).zfill(3), "tags": group, "name": c[1],
                      "value": int(bonus.group(1).replace("−", "-")) / 100.0 if bonus else 0.15,
                      "text": re.sub(r"`", "", c[2]), "first_round_only": "1-м раунде" in c[2] or "1-й раунд" in c[2]})

conflicts = []
for c in rows(sec["7.17"]):
    a_tags = ticks(c[0])
    b_tags = ticks(c[1])
    if not b_tags:  # «суша (не море)», «обычное оружие (...)»
        b_tags = ticks(c[1]) or [c[1].split(" ")[0]]
    loser_text = c[2]
    effect = c[3]
    m = re.search(r"−(\d+)%", effect)
    penalty = int(m.group(1)) / 100.0 if m else 0.2
    mode = "penalty"
    if "бонуса" in effect or "отключена" in effect:
        mode = "nullify"
        penalty = int(m.group(1)) / 100.0 if m else 1.0
    if "считаются 2" in effect:
        mode = "crowd"
        penalty = 0.0
    # кто теряет: носитель тега А или тега Б
    loser = "b"
    for t in a_tags:
        if t.lower() in loser_text.lower():
            loser = "a"
    if "носитель железа" in loser_text or "носитель стали" in loser_text or "носитель кости" in loser_text \
            or "носитель удара" in loser_text or "носитель металла" in loser_text or "стрелок" in loser_text \
            or "летун" in loser_text or "одиночка" in loser_text or "дуэлянт" in loser_text or "гордец" in loser_text \
            or "голодный" in loser_text or "инстинктивный" in loser_text or "захватывающий" in loser_text \
            or "атакующий тег" in loser_text or "носитель меха" in loser_text or "носитель взгляда" in loser_text \
            or "носитель страха" in loser_text or "глубинный" == loser_text.strip():
        pass
    # явные подсказки
    for t in a_tags:
        if loser_text.startswith("носитель") and ("носитель " + t.lower()) in loser_text.lower():
            loser = "a"
    special_a = {"носитель железа": "a", "носитель стали": "a", "носитель кости": "a", "носитель удара": "a",
                 "носитель металла": "b", "носитель хитина": "b", "носитель сочленений": "b", "носитель меха": "a",
                 "носитель взгляда": "b", "носитель страха": "b", "стрелок": "b", "летун": "a", "одиночка": "a",
                 "дуэлянт": "a", "гордец": "a", "голодный": "a", "инстинктивный": "a", "захватывающий": "b",
                 "атакующий тег": "b", "глубинный": "a", "мягкое тело": "b", "броня": "b", "носитель": "b"}
    for k, v in special_a.items():
        if loser_text.strip().startswith(k):
            loser = v
            break
    else:
        # «растение», «рой», «лёд», «тень» … — это тег Б; «огонь», «яд», «засада» — чаще Б
        low = loser_text.lower()
        if any(t.lower() in low for t in b_tags):
            loser = "b"
        elif any(t.lower() in low for t in a_tags):
            loser = "a"
    for bt in b_tags:
        conflicts.append({"id": "CON_" + str(len(conflicts) + 1).zfill(3), "a": a_tags[0] if a_tags else c[0],
                          "b": bt, "loser": loser, "value": round(penalty, 2), "mode": mode,
                          "name": c[4] if len(c) > 4 and c[4] else (a_tags[0] + " против " + bt),
                          "text": "%s против %s: %s %s" % (c[0].replace("`", ""), bt, loser_text, effect)})
    if len(a_tags) > 1:
        for at in a_tags[1:]:
            for bt in b_tags:
                conflicts.append({"id": "CON_" + str(len(conflicts) + 1).zfill(3), "a": at, "b": bt, "loser": loser,
                                  "value": round(penalty, 2), "mode": mode, "name": c[4] if len(c) > 4 and c[4] else at + " против " + bt,
                                  "text": "%s против %s: %s %s" % (at, bt, loser_text, effect)})

# --- все упомянутые теги должны существовать ---------------------------------------
mentioned = set()
for s in synergies:
    mentioned.update(s["tags"])
for c in conflicts:
    mentioned.update([c["a"], c["b"]])
for f in fields:
    mentioned.update(f["tags"])
    mentioned.update(e["tag"] for e in f["effects"])
for r in round_cards:
    mentioned.update(r["tags"])
    mentioned.update(e["tag"] for e in r["effects"] if e["tag"] != "*hero")
for v in carriers["characters"].values():
    mentioned.update(v["tags"])
for v in carriers["enhancements"].values():
    mentioned.update(v)
for e in carriers["enemies"]:
    mentioned.update(e["tags"])
missing = sorted(t for t in mentioned if t not in tags)

os.makedirs(OUT, exist_ok=True)
EXTRA = os.path.join(OUT, "tags_extra.json")
extra = json.load(io.open(EXTRA, encoding="utf-8")) if os.path.exists(EXTRA) else []
for e in extra:
    tags[e["id"]] = e
still_missing = [t for t in missing if t not in tags]


def dump(name, data):
    io.open(os.path.join(OUT, name), "w", encoding="utf-8").write(json.dumps(data, ensure_ascii=False, indent=1))


# «−100%» в документе означает «тег проигравшего полностью обесценен», а не «сила стороны = 0».
for c in conflicts:
    if c["mode"] == "penalty" and c["value"] >= 1.0:
        c["mode"] = "nullify"
        c["value"] = 1.0

# --- противники: data/combat/enemies.json ------------------------------------------
ECHO = {"M03": ("U12", 0.25), "M17": ("P27", 0.05)}
TRAUMA_POOL = {"Очарование": "mental", "Ментальное давление": "mental", "Холод": "environment"}
enemies = []
for e in carriers["enemies"]:
    ids = []
    rng = re.match(r"M(\d+)[–-]M(\d+)", e["ids"])
    if rng:
        ids = ["M%02d" % i for i in range(int(rng.group(1)), int(rng.group(2)) + 1)]
    else:
        ids = [e["ids"]]
    for i, eid in enumerate(ids):
        pool = "physical"
        for t in e["tags"]:
            pool = TRAUMA_POOL.get(t, pool)
        kind = "boss" if e["class"] >= 5 else ("elite" if "Элита" in e["tags"] or e["class"] >= 3 else "normal")
        ent = {"id": eid, "name": e["name"], "rank": e["rank"], "class": e["class"], "tags": e["tags"],
               "kind": kind, "trauma_pool": pool, "shards": (e["rank"] + 1) * e["class"],
               "art": "res://art/cards/%s.png" % eid}
        if eid in ECHO:
            ent["echo"] = {"card": ECHO[eid][0], "chance": ECHO[eid][1]}
        enemies.append(ent)
enemies.append({"id": "H_AURO", "name": "Ауро из Девяти", "rank": 1, "class": 1, "human": True, "kind": "elite",
                "tags": ["Дуэль", "Сталь", "Первый удар", "Гордыня", "Человек"], "trauma_pool": "physical", "shards": 3})
dump_later = enemies

CON_EXTRA = [
    {"a": "Холод", "b": "Хладнокровная тварь", "loser": "b", "value": 0.10, "mode": "penalty", "name": "Мороз сковывает",
     "text": "Холод против Хладнокровной твари: тварь теряет 10%"},
]
for c in CON_EXTRA:
    c["id"] = "CON_" + str(len(conflicts) + 1).zfill(3)
    conflicts.append(c)
# --- правки из редактора контента (tools/editor): генератор их не затирает -------------
# editor_overrides.json: {"renamed_tags": {старое: новое}, "removed_tags": [...], "tags": {имя: тег},
#                         "enemies": {id: противник}, "removed_enemies": [...]}
OVERRIDES = os.path.join(OUT, "editor_overrides.json")
ov = json.load(io.open(OVERRIDES, encoding="utf-8")) if os.path.exists(OVERRIDES) else {}


def swap_tag(old, new):
    """Переименовывает тег во всех боевых данных; new=None — убирает его."""
    def fix(lst):
        return [new if x == old else x for x in lst if not (new is None and x == old)]
    for s in synergies:
        s["tags"] = fix(s["tags"])
    for c in conflicts:
        for k in ("a", "b"):
            if c[k] == old:
                c[k] = new
    for f in fields + round_cards:
        f["tags"] = fix(f["tags"])
        f["effects"] = [e for e in f.get("effects", []) if not (new is None and e.get("tag") == old)]
        for e in f["effects"]:
            if e.get("tag") == old:
                e["tag"] = new
    for v in carriers["characters"].values():
        v["tags"] = fix(v["tags"])
    for k in carriers["enhancements"]:
        carriers["enhancements"][k] = fix(carriers["enhancements"][k])
    for e in carriers["enemies"] + enemies:
        e["tags"] = fix(e["tags"])


for old, new in ov.get("renamed_tags", {}).items():
    if old in tags:
        ent = tags.pop(old)
        ent["id"] = ent["name"] = new
        tags.setdefault(new, ent)
    swap_tag(old, new)
for t in ov.get("removed_tags", []):
    tags.pop(t, None)
    swap_tag(t, None)
synergies[:] = [s for s in synergies if len(s["tags"]) >= 2]
conflicts[:] = [c for c in conflicts if c["a"] and c["b"]]
for name, ent in ov.get("tags", {}).items():
    tags[name] = ent
removed_enemies = set(ov.get("removed_enemies", []))
dump_later = [e for e in dump_later if e["id"] not in removed_enemies]
for eid, ent in ov.get("enemies", {}).items():
    idx = next((i for i, e in enumerate(dump_later) if e["id"] == eid), None)
    if idx is None:
        dump_later.append(ent)
    else:
        dump_later[idx] = ent
if ov:
    print("правки редактора применены:", {k: len(v) for k, v in ov.items()})

dump("tags.json", list(tags.values()))
dump("synergies.json", synergies)
dump("conflicts.json", conflicts)
dump("fields.json", fields)
dump("round_cards.json", round_cards)
dump("_carriers_from_doc.json", carriers)
dump("enemies.json", dump_later)
print("tags:", len(tags), "synergies:", len(synergies), "conflicts:", len(conflicts), "fields:", len(fields), "round cards:", len(round_cards))
print("missing tags (%d):" % len(still_missing), ", ".join(still_missing))
