"""Короткие справки по данным SunLess — чтобы не читать JSON целиком.

python tools/ctx.py missions [глава]   таблица миссий (глава: nightmare | academy | shore …)
python tools/ctx.py mission MS05       миссия кратко: слухи, отряд, действия и этапы
python tools/ctx.py fields MS05        ключи миссии и их типы (для правок)
python tools/ctx.py heroes             герои: характеристики, теги
python tools/ctx.py hero P03           герой целиком
python tools/ctx.py enemy M02          противник
python tools/ctx.py tag Дуэль          где используется тег
python tools/ctx.py locations [глава]  места на карте
python tools/ctx.py shops              магазины
python tools/ctx.py cards [kind]       все карты: character | enhancement | ability | trauma | enemy
"""
import glob
import json
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


def load(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        d = json.load(f)
    return d if isinstance(d, list) else list(d.values())


def missions():
    out = []
    for p in sorted(glob.glob(os.path.join(ROOT, "data", "missions", "*.json"))):
        for m in load(os.path.relpath(p, ROOT)):
            m["_file"] = os.path.basename(p)
            out.append(m)
    return out


def chapter_of(m, locs):
    return locs.get(m.get("location", ""), {}).get("chapter", "?")


def stats(c):
    s = c.get("stats") or c.get("stages", {}).get(c.get("start_stage", ""), {}).get("stats", {})
    return "С%s В%s Х%s" % (s.get("power", "-"), s.get("will", "-"), s.get("cunning", "-"))


def req_text(st):
    if "combat" in st:
        return "бой " + ",".join(st["combat"].get("enemies", []))
    if st.get("auto"):
        return "авто"
    return " ".join("%s%s" % ({"power": "С", "will": "В", "cunning": "Х"}[k], v) for k, v in st.get("req", {}).items())


def cmd_missions(ch=None):
    locs = {l["id"]: l for l in load("data/locations.json")}
    for m in missions():
        c = chapter_of(m, locs)
        if ch and c != ch:
            continue
        flags = "".join([" старт" if m.get("start") else "", " конец" if m.get("end_chapter") else "",
                         " небо:" + m["sky"] if m.get("sky") else ""])
        print("%-5s %-10s %-7s угр%s %-34s → %s%s" % (m["id"], c, m.get("type"), m.get("threat"), m.get("title", "")[:34],
                                                  ",".join(m.get("next", [])) or "-", flags))


def cmd_mission(mid):
    m = next((x for x in missions() if x["id"] == mid), None)
    if not m:
        return print("нет миссии", mid)
    print("%s «%s» [%s, %s] место %s, угроза %s, путь %sс, отдых %sс, отряд %s–%s" % (
        m["id"], m["title"], m["type"], m["_file"], m["location"], m.get("threat"), m.get("duration"), m.get("rest"),
        m.get("squad", {}).get("min"), m.get("squad", {}).get("max")))
    for k in ("requires_heroes", "exclude_heroes", "enemies", "field", "known_tags", "hidden_tags", "context", "sky", "unlock", "next", "next_chapter"):
        if m.get(k):
            print("  %s: %s" % (k, m[k]))
    for r in m.get("rumors", []):
        print("  слух: %s (%s)" % (r["text"], r.get("tag", "")))
    for a in m.get("actions", []):
        extra = []
        for k in ("requires_any", "requires_hero", "conditions", "cost"):
            if a.get(k):
                extra.append("%s=%s" % (k, a[k]))
        star = "★" if a.get("story") else ("↩" if a.get("retreat") else "·")
        print("  %s %s «%s» %s" % (star, a["id"], a["label"], " ".join(extra)))
        for st in a.get("stages", []):
            print("      - %s: %s %s" % (st.get("name"), req_text(st), st.get("tags", "")))
        for k in ("on_success", "on_partial", "on_failure"):
            if a.get(k):
                print("      %s: %s" % (k, [(e.get("cmd"), e.get("card") or e.get("stat") or e.get("flag") or e.get("value")) for e in a[k]]))
    if m.get("on_complete"):
        print("  on_complete:", [(e.get("cmd"), e.get("card") or e.get("stage") or "") for e in m["on_complete"]])


def cmd_fields(mid):
    m = next((x for x in missions() if x["id"] == mid), None)
    for k, v in (m or {}).items():
        print("%-16s %s" % (k, type(v).__name__ + (" [%d]" % len(v) if isinstance(v, (list, dict)) else "")))


def cmd_heroes():
    for c in load("data/characters.json"):
        print("%-4s %-10s %-9s %-10s %s  %s" % (c["id"], c["name"], c.get("status", ""), c.get("rarity", ""), stats(c),
                                               ", ".join(c.get("tags") or c.get("stages", {}).get(c.get("start_stage", ""), {}).get("tags", []))))


def cmd_one(rel, cid):
    for c in load(rel):
        if c.get("id") == cid:
            return print(json.dumps(c, ensure_ascii=False, indent=1))
    print("нет", cid)


def cmd_tag(tag):
    hits = []
    for p in glob.glob(os.path.join(ROOT, "data", "**", "*.json"), recursive=True):
        rel = os.path.relpath(p, ROOT).replace("\\", "/")
        if "lore" in rel or "_carriers" in rel:
            continue
        for o in load(rel):
            if isinstance(o, dict) and ('"%s"' % tag) in json.dumps(o, ensure_ascii=False):
                hits.append("%s:%s" % (rel.replace("data/", ""), o.get("id", "?")))
    print("\n".join(hits) or "не используется")


def cmd_locations(ch=None):
    for l in load("data/locations.json"):
        if ch and l.get("chapter") != ch:
            continue
        print("%-15s %-9s %-24s pos=%s random=%s" % (l["id"], l.get("chapter"), l.get("name"), l.get("pos"), l.get("random", "")))


def cmd_shops():
    for s in load("data/shops.json"):
        print("%s «%s» [%s] слотов %s, раз в %s: %s" % (s["id"], s["name"], s["chapter"], s.get("slots"), s.get("refresh_every"),
                                                      ", ".join("%s%s" % (x["card"], ":" + str(x["price"]) if "price" in x else "") for x in s["stock"])))


def cmd_cards(kind=None):
    files = {"character": "data/characters.json", "enhancement": "data/enhancements.json", "ability": "data/abilities.json",
             "trauma": "data/traumas.json", "enemy": "data/combat/enemies.json"}
    for k, rel in files.items():
        if kind and k != kind:
            continue
        print("## %s: %s" % (k, ", ".join("%s %s" % (c["id"], c.get("name", "")) for c in load(rel))))


if __name__ == "__main__":
    a = sys.argv[1:] or ["help"]
    cmds = {"missions": cmd_missions, "mission": cmd_mission, "fields": cmd_fields, "heroes": cmd_heroes,
            "hero": lambda i: cmd_one("data/characters.json", i), "enemy": lambda i: cmd_one("data/combat/enemies.json", i),
            "tag": cmd_tag, "locations": cmd_locations, "shops": cmd_shops, "cards": cmd_cards}
    if a[0] not in cmds:
        print(__doc__)
    else:
        cmds[a[0]](*a[1:])
