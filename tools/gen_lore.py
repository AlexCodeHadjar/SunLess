"""Генератор сюжетных описаний карт («По книге») из проектных документов.

Источники (docs/ — копия заметок Obsidian):
  03 — Персонажи.md            «# P01 — …» + «**Описание по книге:**», «**Источник:**»
  04 — Усиления и травмы.md    «# U01 / A01 — …» + то же; таблицы травм, знаний и инициаторов
  05, 06, 07 — События         «## E01 — …» + «**Описание:**», «**Источник:**»
  Противники_и_монстры…md      таблица «| M01 | … |»
Результат: data/lore.json — [{id, title, text, source, extra, adaptation}].
Запуск: python tools/gen_lore.py
"""
import glob
import io
import json
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")
OUT = os.path.join(ROOT, "data", "lore.json")

lore = {}


def read(name):
    with io.open(os.path.join(DOCS, name), encoding="utf-8") as f:
        return f.read()


def clean(s):
    s = re.sub(r"\[\[[^\]|]*\|([^\]]*)\]\]", r"\1", s)   # [[ссылка|текст]] → текст
    s = re.sub(r"\[\[([^\]]*)\]\]", r"\1", s)
    s = s.replace("**", "").replace("`", "")
    return re.sub(r"\s+", " ", s).strip()


def field(block, name):
    m = re.search(r"\*\*" + name + r":\*\*\s*(.+)", block)
    return clean(m.group(1)) if m else ""


def put(cid, title, text="", source="", extra="", adaptation=False):
    cur = lore.setdefault(cid, {"title": title, "text": "", "source": "", "extra": "", "adaptation": False})
    for k, v in (("text", text), ("source", source), ("extra", extra)):
        if v and not cur[k]:
            cur[k] = v
    cur["adaptation"] = cur["adaptation"] or adaptation


def headed_blocks(text, level, id_re):
    """Блоки «<#…> ID — Название» до следующего заголовка того же или старшего уровня."""
    pat = re.compile(r"^" + "#" * level + r" (" + id_re + r") — (.+?)\s*$", re.M)
    hits = list(pat.finditer(text))
    for i, m in enumerate(hits):
        end = len(text)
        nxt = re.compile(r"^#{1," + str(level) + r"} ", re.M).search(text, m.end())
        if nxt:
            end = nxt.start()
        yield m.group(1), clean(re.sub(r"\(бывш\..*?\)", "", m.group(2))), text[m.end():end]


def table_rows(text, id_re):
    for line in text.splitlines():
        m = re.match(r"^\|\s*(" + id_re + r")\s*\|(.*)\|\s*$", line)
        if m:
            yield m.group(1), [clean(c) for c in m.group(2).split("|")]


# персонажи, усиления, способности
for doc in ("03 — Персонажи.md", "04 — Усиления и травмы.md"):
    t = read(doc)
    for cid, title, block in headed_blocks(t, 1, r"[PUAK]\d{2}"):
        put(cid, title, field(block, "Описание по книге"), field(block, "Источник"),
            adaptation="адаптация" in field(block, "Статус").lower())

t4 = read("04 — Усиления и травмы.md")
for cid, cols in table_rows(t4, r"T\d{2}"):
    # | ID | Травма | Описание | Эффект | Категория | Тяжесть | В пуле |
    if len(cols) >= 6:
        put(cid, cols[0], cols[1], extra="Категория: %s · тяжесть: %s" % (cols[3], cols[4]))
for cid, cols in table_rows(t4, r"K\d{2}"):
    if len(cols) >= 3:
        put(cid, cols[0], extra="Получение: " + cols[2])
for cid, cols in table_rows(t4, r"I\d{2}"):
    if len(cols) >= 3:
        put(cid, cols[0], extra="Получение: %s · создаёт: %s" % (cols[1], cols[2]))

# события
for doc in sorted(glob.glob(os.path.join(DOCS, "0[5-7] — События*.md"))):
    t = read(os.path.basename(doc))
    for cid, title, block in headed_blocks(t, 2, r"E\d{2,3}"):
        put(cid, title, field(block, "Описание"), field(block, "Источник"))

# противники
tm = read("Противники_и_монстры_Дитя_Теней_Мрачный_город.md")
for cid, cols in table_rows(tm, r"M\d{2}"):
    # | ID | Противник | Книга | Арка | Ранг | Класс | Описание | Опасность |
    if len(cols) >= 7:
        put(cid, cols[0], cols[5], "«%s», %s" % (cols[1], cols[2]), cols[6])

with io.open(OUT, "w", encoding="utf-8") as f:
    json.dump([dict(id=k, **lore[k]) for k in sorted(lore)], f, ensure_ascii=False, indent=1)
with_text = sum(1 for v in lore.values() if v["text"])
print("lore: %d записей, с описанием %d → %s" % (len(lore), with_text, OUT))
