"""Коллажи «как меняется карта-план»: карта по дням в каждой главе, облики мест и что их включает, неиспользованные ассеты.

Вход: кадры и timeline.json (Godot --path . -- --mshots=<папка> --mshots-from=timeline --nohints),
покрытие (Godot --headless --path . -s res://tools/map_coverage.gd -- --out=<coverage.json>), комплекты текстур.
    python tools/map_collage.py <папка кадров> <coverage.json> <папка комплектов> <папка вывода>
"""
import io
import json
import os
import re
import sys
import textwrap

from PIL import Image, ImageDraw, ImageEnhance, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "ui", "fonts", "PT_Sans-Regular.ttf")
FONT_B = os.path.join(ROOT, "ui", "fonts", "PT_Sans-Bold.ttf")
TITLE = os.path.join(ROOT, "ui", "fonts", "CormorantSC-SemiBold.ttf")

CHAPTERS = [("academy", "Академия", "academy"), ("shore", "Забытый Берег", "forgotten_shore"), ("city", "Город людей", "real_city"),
	("tree", "Древо Души — Пепельный путь", "ash_path"), ("dark_city", "Мрачный город", "dark_city")]
REGION_CH = {r: (ch, n) for ch, n, r in CHAPTERS}

STATE_RU = {"dry": "обычный", "dry_b": "проход Б", "dry_c": "проход В", "flooded": "под водой", "silt": "ил", "storm": "шторм",
	"ravaged": "разорено", "alarm": "тревога", "fight": "бой", "damaged": "повреждён", "ruined": "разрушен", "burning": "горит",
	"barricaded": "баррикада", "repair": "ремонт", "lockdown": "ставни", "leak": "утечка", "breached": "прорыв", "crowded": "переполнен",
	"overcrowded": "переполнен", "closed": "закрыт", "collapsed": "обрушен", "sealed": "запечатан", "burned": "выгорел",
	"temporary": "понтон", "infested": "заражён", "cracked": "трещины", "wrath": "гнев", "charmed": "чары", "night_glow": "ночное сияние",
	"lit": "огонь горит", "hunted": "следы Демона", "boat_ready": "лодка готова", "awake": "проснулась", "empty": "гнездо пусто",
	"buried": "засыпан", "siege": "осада", "closed_night": "закрыто на ночь", "busy": "торг", "statues_moved": "статуи сдвинулись",
	"cleared": "зачищено", "opened": "открыт", "fresh_graves": "свежие могилы", "hidden": "скрыто", "found": "найдено"}
GATE_GENERIC = {"alarm", "fight", "damaged", "ruined", "burning", "barricaded", "repair"}
GATE_SPECIAL = {"lockdown", "crowded", "overcrowded", "closed", "leak", "breached", "sealed", "collapsed", "temporary", "infested", "burned"}

GREEN, YELLOW, ORANGE, GREY, BLUE = (76, 175, 80), (224, 176, 64), (224, 112, 48), (140, 140, 140), (90, 120, 200)
STATUS = {"seen": (GREEN, "в игре — встречалось в прогонах бота"), "sourced": (YELLOW, "механика есть, но в прогонах не встретилось"),
	"nosource": (ORANGE, "подключено к месту, но ничто его не включает"), "unref": (GREY, "импортировано, но не подключено"),
	"kit": (BLUE, "есть в комплекте, не импортировано")}
BG, PANEL, TEXT, DIM = (14, 15, 20), (26, 28, 36), (226, 220, 205), (150, 146, 136)


def font(path, size):
	return ImageFont.truetype(path, size)


def load_json(*p):
	return json.load(io.open(os.path.join(ROOT, *p), encoding="utf-8"))


def as_dict(x):
	return x if isinstance(x, dict) else {e["id"]: e for e in x}


LOC = as_dict(load_json("data", "locations.json"))
SHOPS = as_dict(load_json("data", "shops.json"))
DAYS = load_json("data", "days.json")


def place_name(lid):
	return str(LOC.get(lid, SHOPS.get(lid, {})).get("name", lid))


def missions_of(chapter_files):
	out = []
	for f in os.listdir(os.path.join(ROOT, "data", "missions")):
		out += load_json("data", "missions", f)
	return out


ALL_MISSIONS = missions_of(None)


def effects(m):
	for a in m.get("actions", []):
		for key in ("on_success", "on_partial", "on_failure"):
			for e in a.get(key, []):
				yield e
		for st in a.get("stages", []):
			for opt in st.get("fork", {}).get("options", []):
				for e in opt.get("on_success", []):
					yield e
	for e in m.get("on_complete", []):
		yield e


# --- что может включить облик -----------------------------------------------------------------------------

def sources(region, cfg):
	src = {}
	def add(f, why):
		src.setdefault(f, [])
		if why not in src[f]:
			src[f].append(why)
	places = cfg.get("places", {})
	threat = cfg.get("threat", {})
	threat_txt = json.dumps(threat, ensure_ascii=False)
	gate_word = "прорыв" if threat.get("kind", "breach") == "breach" else "Врата и волна"
	week_regions = DAYS.get("weeks", {})
	sky_storm = any(ph in ("storm", "ash_storm") for ph, n in week_regions.get(region, []))
	tide_storm = any(ph == "storm" for ph, n in week_regions.get(region, []))
	for lid, p in places.items():
		for st in p.get("states", []):
			f = "%s_%s" % (lid, st)
			h = str(LOC.get(lid, {}).get("height", ""))
			if st == "dry":
				add(f, "обычный облик")
			elif st == "flooded" and (region == "forgotten_shore" or tide_storm) and h in ("low", "mid"):
				add(f, "вода: прилив / шторм недели")
			elif st == "silt" and region == "forgotten_shore":
				add(f, "ил после отлива")
			elif st == "storm" and sky_storm:
				add(f, "небо: шторм / буря")
			if threat and (st in GATE_GENERIC or ('"%s"' % st) in threat_txt):
				add(f, "%s: %s" % (gate_word, STATE_RU.get(st, st)))
			if threat and st == "lockdown" and lid == threat.get("target"):
				add(f, "прорыв: рой у Зала капсул")
			if threat and st == "collapsed" and threat.get("kind") == "gate":
				add(f, "команда «взорвать мост»")
	for lid, vs in cfg.get("variants", {}).items():
		for v in vs:
			add("%s_%s" % (lid, v), "отлив / буря перестраивает проход")
	for lid, d in cfg.get("phase_states", {}).items():
		for ph, st in d.items():
			add("%s_%s" % (lid, st), "фаза недели: %s" % DAYS["phases"].get(ph, {}).get("name", ph))
	for lid, fr in cfg.get("fragile", {}).items():
		add("%s_%s" % (lid, fr.get("warn", "cracked")), "мост: после переходов")
		add("%s_collapsed" % lid, "мост рушится")
	for m in ALL_MISSIONS:
		for e in effects(m):
			if e.get("cmd") == "map_mark" and e.get("place") in places:
				add("%s_%s" % (e["place"], e.get("state")), "миссия «%s»" % m.get("title", m["id"]))
			if e.get("cmd") == "terrain" and e.get("do") == "set" and e.get("place") in places and e.get("state"):
				add("%s_%s" % (e["place"], e["state"]), "миссия «%s»" % m.get("title", m["id"]))
	return src


def referenced(cfg):
	"""Все строки из настроек карты (метки, точки, полосы) + облики мест + варианты."""
	out = set()
	def walk(x):
		if isinstance(x, str):
			out.add(os.path.splitext(x)[0])
		elif isinstance(x, list):
			for y in x:
				walk(y)
		elif isinstance(x, dict):
			for y in x.values():
				walk(y)
	for key in ("decals", "point_tex", "base", "fog", "height", "water"):
		walk(cfg.get(key))
	for lid, p in cfg.get("places", {}).items():
		for st in p.get("states", []):
			out.add("%s_%s" % (lid, st))
	for lid, vs in cfg.get("variants", {}).items():
		for v in vs:
			out.add("%s_%s" % (lid, v))
	return out


def art_files(region):
	d = os.path.join(ROOT, "art", "map", region)
	return {os.path.splitext(f)[0]: os.path.join(d, f) for f in os.listdir(d) if not f.endswith(".import")}


KIT_REGION = [("sunless-map-events-kit-partial", "forgotten_shore"), ("sunless-map-kit", "forgotten_shore"), ("academy-map-kit", "academy"),
	("real-city-map-kit", "real_city"), ("sunless-chapter4-map-kit/art/map/ash_path", "ash_path"),
	("sunless-chapter4-map-kit/art/map/dark_city", "dark_city")]
SKIP_DIRS = ("chroma", "reference", "previews")
TECH = {"zones", "districts", "height", "height_zones", "base"}


def kit_files(kits):
	out = []
	for sub, region in KIT_REGION:
		root = os.path.join(kits, sub)
		if not os.path.isdir(root):
			continue
		for dp, dn, fn in os.walk(root):
			if any(s in dp.replace("\\", "/").split("/") for s in SKIP_DIRS):
				continue
			for f in fn:
				if f.lower().endswith((".png", ".webp", ".jpg")):
					out.append((sub.split("/")[0], region, os.path.splitext(f)[0], os.path.join(dp, f)))
	seen = set()
	uniq = []
	for k in out:
		if (k[1], k[2]) not in seen:
			seen.add((k[1], k[2]))
			uniq.append(k)
	return uniq


# --- рисование ----------------------------------------------------------------------------------------------

def wrap(draw, text, fnt, width):
	lines = []
	for para in text.split("\n"):
		words = para.split(" ")
		cur = ""
		for w in words:
			t = (cur + " " + w).strip()
			if draw.textlength(t, font=fnt) <= width:
				cur = t
			else:
				if cur:
					lines.append(cur)
				cur = w
		lines.append(cur)
	return lines


def thumb(path, size):
	im = Image.open(path).convert("RGBA")
	im.thumbnail((size, size), Image.LANCZOS)
	bg = Image.new("RGBA", (size, size), PANEL + (255,))
	bg.alpha_composite(im, ((size - im.width) // 2, (size - im.height) // 2))
	return bg.convert("RGB")


def legend(draw, x, y, keys):
	f = font(FONT, 20)
	for k in keys:
		col, txt = STATUS[k]
		draw.rectangle([x, y + 4, x + 22, y + 26], outline=col, width=4)
		draw.text((x + 32, y), txt, font=f, fill=TEXT)
		x += 48 + int(draw.textlength(txt, font=f))
	return y + 36


# --- 1. карта по дням ---------------------------------------------------------------------------------------

def diff_lines(prev, cur):
	lines = []
	if prev is None:
		bad = [p for p in cur["places"].values() if p["state"] not in ("dry", "")]
		lines.append("Начало главы: открыто мест — %d из %d (остальное в тумане)." % (sum(1 for p in cur["places"].values() if p["known"]), len(cur["places"])))
		for p in bad[:3]:
			lines.append("%s — %s (%s)" % (p["name"], STATE_RU.get(p["state"], p["state"]), p["why"] or "обычный облик"))
		return lines
	pp, cp = prev["places"], cur["places"]
	changed = []
	for lid, p in cp.items():
		was = pp.get(lid, {}).get("state", "—")
		if was != p["state"]:
			why = p["why"] or ("снова обычный облик" if p["state"] == "dry" else "")
			changed.append("%s: %s › %s%s" % (p["name"], STATE_RU.get(was, was), STATE_RU.get(p["state"], p["state"]), (" — " + why) if why else ""))
	new_known = sum(1 for lid, p in cp.items() if p["known"] and not pp.get(lid, {}).get("known", False))
	em_new = [place_name(l) for l in cur.get("emerged", []) if l not in prev.get("emerged", [])]
	em_gone = [place_name(l) for l in prev.get("emerged", []) if l not in cur.get("emerged", [])]
	if em_new:
		lines.append("Поднялись новые места: " + ", ".join(em_new))
	if em_gone:
		lines.append("Ушли с карты: " + ", ".join(em_gone))
	if len(cur.get("flooded", [])) != len(prev.get("flooded", [])):
		lines.append("Под водой мест: %d" % len(cur.get("flooded", [])))
	if cur.get("path_set") != prev.get("path_set"):
		lines.append("Буря: тропы Пепельного моря другие")
	if cur.get("boat") and not prev.get("boat"):
		lines.append("Лодка готова: по Чёрной воде ночью можно плыть")
	gch = ["%s: %s" % (g, {"signal": "предвестие", "open": "открыты", "sealed": "закрыты", "scar": "шрам"}.get(st, st))
		for g, st in cur.get("gates", {}).items() if prev.get("gates", {}).get(g) != st]
	if gch:
		lines.append(("Проломы " if cur["chapter"] == "academy" else "Врата ") + ", ".join(gch))
	if cur.get("swarms", 0) != prev.get("swarms", 0):
		lines.append(("Роёв в кампусе: %d" if cur["chapter"] == "academy" else "Волн в городе: %d") % cur.get("swarms", 0))
	if cur.get("panic", 0) != prev.get("panic", 0) and cur["chapter"] == "city":
		lines.append("Паника: %d" % cur.get("panic", 0))
	zn = {"wrath": "гнев Владыки", "charm": "Очарование", "statues": "статуи", "spiders": "пауки", "flowers": "цветы", "eaters": "пожиратели"}
	zch = ["%s — %s мест" % (zn.get(z, z), n) for z, n in cur.get("zones", {}).items() if prev.get("zones", {}).get(z) != n]
	zch += ["%s зачищено" % zn.get(z, z) for z in prev.get("zones", {}) if z not in cur.get("zones", {})]
	if zch:
		lines.append("Зоны: " + ", ".join(zch))
	mn = {"demon": "Демон", "deep_shadow": "тень гиганта", "fiend": "Изверг", "corpse_eater": "Пожиратель", "statues": "статуи"}
	mch = ["%s › %s" % (mn.get(m, m), place_name(at)) for m, at in cur.get("movers", {}).items() if prev.get("movers", {}).get(m) != at]
	if mch:
		lines.append("Угрозы идут: " + ", ".join(mch))
	if cur.get("rubble") != prev.get("rubble"):
		lines.append("Завалы: %s" % (", ".join(cur.get("rubble", [])) or "расчищены"))
	if new_known:
		lines.append("Туман расступился: +%d мест" % new_known)
	return lines + changed


def timeline_collage(tl_dir, chapter, title, frames, out):
	W = 1960
	cw, ch = 940, 529
	cap_h = 210
	header = 130
	rows = (len(frames) + 1) // 2
	img = Image.new("RGB", (W, header + rows * (ch + cap_h + 24) + 20), BG)
	d = ImageDraw.Draw(img)
	d.text((30, 22), "%s — карта по дням" % title, font=font(TITLE, 54), fill=TEXT)
	note = "Сценарий прорыва (бот гасит прорывы на сигнале — дальше сигнала в 12 прогонах не доходило)" if chapter == "academy" \
		else "Прогон бота (как игрок): дни с самыми заметными переменами; подписи — что изменилось с прошлого кадра и почему"
	d.text((32, 88), note, font=font(FONT, 22), fill=DIM)
	prev = None
	fb, fr = font(FONT_B, 24), font(FONT, 19)
	for i, f in enumerate(frames):
		x = 30 + (i % 2) * (cw + 30)
		y = header + (i // 2) * (ch + cap_h + 24)
		shot = Image.open(os.path.join(tl_dir, f["file"])).convert("RGB").resize((cw, ch), Image.LANCZOS)
		shot = ImageEnhance.Brightness(shot).enhance(1.25)
		img.paste(shot, (x, y))
		d.rectangle([x, y + ch, x + cw, y + ch + cap_h], fill=PANEL)
		head = "%d. День %d · %s" % (i + 1, f["day"], f["phase"]) + (" — " + f["note"] if f.get("note") else "")
		d.text((x + 14, y + ch + 8), head, font=fb, fill=(240, 200, 120))
		ty = y + ch + 42
		for line in diff_lines(prev, f):
			for wl in wrap(d, "• " + line, fr, cw - 30):
				if ty > y + ch + cap_h - 24:
					break
				d.text((x + 16, ty), wl, font=fr, fill=TEXT)
				ty += 24
		prev = f
	img.save(out, quality=88)


# --- 2. облики мест ------------------------------------------------------------------------------------------

def states_collage(region, ch_title, cfg, cov, files, out):
	src = sources(region, cfg)
	seen = cov.get("files", {}) if cov else {}
	whys = cov.get("why", {}) if cov else {}
	runs = cov.get("runs", 0) if cov else 0
	blocks = []
	for lid, p in cfg.get("places", {}).items():
		sts = list(p.get("states", []))
		for v in cfg.get("variants", {}).get(lid, []):
			if v not in sts:
				sts.append(v)
		extra = [k[len(lid) + 1:] for k in files if k.startswith(lid + "_") and k[len(lid) + 1:] not in sts and "_" not in k[len(lid) + 1:].replace("dry_", "")]
		if len(sts) + len(extra) < 2:
			continue
		blocks.append((lid, [(st, "%s_%s" % (lid, st)) for st in sts] + [(st, "%s_%s" % (lid, st)) for st in extra]))
	tile, gap = 150, 12
	fb, fs, fx = font(FONT_B, 21), font(FONT, 16), font(FONT_B, 16)
	W = 1960
	# раскладка блоков по строкам
	layout, x, y, row_h = [], 30, 0, 0
	for lid, items in blocks:
		bw = 20 + len(items) * (tile + gap) + 10
		if x + bw > W - 20:
			x, y = 30, y + row_h + 26
		layout.append((lid, items, x, y))
		x += bw + 18
		row_h = 70 + tile + 92
	header = 190
	img = Image.new("RGB", (W, header + y + row_h + 40), BG)
	d = ImageDraw.Draw(img)
	d.text((30, 22), "%s — облики мест и что их меняет" % ch_title, font=font(TITLE, 50), fill=TEXT)
	d.text((32, 84), "Рамка — статус картинки; подпись — облик и механика, которая его включает (по данным и %d прогонам бота)" % runs, font=font(FONT, 21), fill=DIM)
	legend(d, 32, 124, ["seen", "sourced", "nosource", "unref"])
	for lid, items, bx, by in layout:
		by += header
		bw = 20 + len(items) * (tile + gap) + 10
		d.rectangle([bx, by, bx + bw, by + 70 + tile + 92], fill=PANEL)
		d.text((bx + 12, by + 10), place_name(lid), font=fb, fill=(240, 200, 120))
		d.text((bx + 12, by + 40), lid, font=fs, fill=DIM)
		for j, (st, fname) in enumerate(items):
			tx, ty = bx + 14 + j * (tile + gap), by + 70
			path = files.get(fname)
			if path:
				img.paste(thumb(path, tile), (tx, ty))
			else:
				d.rectangle([tx, ty, tx + tile, ty + tile], outline=DIM)
				d.text((tx + 10, ty + tile // 2 - 10), "нет картинки", font=fs, fill=DIM)
			if fname in seen:
				status = "seen"
			elif fname in src and fname in referenced(cfg):
				status = "sourced"
			elif fname in referenced(cfg):
				status = "nosource"
			else:
				status = "unref"
			d.rectangle([tx - 3, ty - 3, tx + tile + 3, ty + tile + 3], outline=STATUS[status][0], width=4)
			d.text((tx, ty + tile + 6), STATE_RU.get(st, st), font=fx, fill=TEXT)
			why = (whys.get(fname) or src.get(fname) or ([] if status != "unref" else ["не подключено"]))
			why = [w for w in why if w != "обычный облик"] or (["обычный облик"] if st == "dry" else ["ничто не включает"])
			for k, wl in enumerate(wrap(d, why[0], fs, tile)[:3]):
				d.text((tx, ty + tile + 28 + k * 19), wl, font=fs, fill=DIM)
	# метки, точки, полосы (Академия, Город)
	img.save(out, quality=88)
	return img


def decals_collage(region, ch_title, cfg, cov, files, out):
	ref = referenced(cfg)
	seen = cov.get("files", {}) if cov else {}
	place_files = set()
	for lid in cfg.get("places", {}):
		for k in files:
			if k.startswith(lid + "_"):
				place_files.add(k)
	items = sorted(k for k in files if k not in place_files and k not in TECH and k not in ("fog_tile", "water_tile", "black_water_tile"))
	if not items:
		return None
	tile, gap = 150, 16
	W = 1960
	per = (W - 60) // (tile + gap)
	rows = (len(items) + per - 1) // per
	header = 190
	img = Image.new("RGB", (W, header + rows * (tile + 80) + 30), BG)
	d = ImageDraw.Draw(img)
	d.text((30, 22), "%s — метки, точки угроз, полосы дорог" % ch_title, font=font(TITLE, 50), fill=TEXT)
	d.text((32, 84), "Рисуются поверх мест и троп (прорывы, Врата, волна, эвакуация, разрушения)", font=font(FONT, 21), fill=DIM)
	legend(d, 32, 124, ["seen", "sourced", "unref"])
	fs = font(FONT, 15)
	for i, k in enumerate(items):
		x = 30 + (i % per) * (tile + gap)
		y = header + (i // per) * (tile + 80)
		img.paste(thumb(files[k], tile), (x, y))
		status = "seen" if k in seen else ("sourced" if k in ref else "unref")
		d.rectangle([x - 3, y - 3, x + tile + 3, y + tile + 3], outline=STATUS[status][0], width=4)
		for j, wl in enumerate(wrap(d, k, fs, tile)[:2]):
			d.text((x, y + tile + 6 + j * 18), wl, font=fs, fill=TEXT)
	img.save(out, quality=88)
	return img


# --- 3. неиспользованные ------------------------------------------------------------------------------------

def unused_collage(kits, cov_all, out):
	groups = []
	kf = kit_files(kits)
	imported = {r: art_files(r) for _, _, r in CHAPTERS}
	cfgs = {r: load_json("data", "maps", "%s.json" % r) for _, _, r in CHAPTERS}
	not_imp = {}
	for kit, region, name, path in kf:
		if name in TECH or name in ("base",):
			continue
		if name not in imported[region]:
			not_imp.setdefault((kit, region), []).append((name, path))
	for (kit, region), lst in not_imp.items():
		groups.append(("kit", "Не импортировано — %s (%s): %d" % (kit, REGION_CH[region][1], len(lst)), sorted(lst)))
	for _, title, region in CHAPTERS:
		cfg = cfgs[region]
		ref = referenced(cfg)
		src = sources(region, cfg)
		seen = cov_all.get(REGION_CH[region][0], {}).get("files", {})
		files = imported[region]
		unref = [(k, p) for k, p in sorted(files.items()) if k not in ref and k not in seen and k not in TECH
			and k not in ("fog_tile", "water_tile", "black_water_tile")]
		place_refs = {"%s_%s" % (lid, st) for lid, p in cfg.get("places", {}).items() for st in p.get("states", [])}
		place_refs |= {"%s_%s" % (lid, v) for lid, vs in cfg.get("variants", {}).items() for v in vs}
		# метки, точки и полосы рисует слой угроз, когда случается своя механика — у них «источник» есть всегда
		nosrc = [(k, files[k]) for k in sorted(ref) if k in files and k in place_refs and k not in src and k not in seen]
		srcd = [(k, files[k]) for k in sorted(ref) if k in files and k not in seen and k not in TECH
			and k not in ("fog_tile", "water_tile", "black_water_tile") and (k in src or k not in place_refs)]
		if unref:
			groups.append(("unref", "%s — импортировано, но не подключено: %d" % (title, len(unref)), unref))
		if nosrc:
			groups.append(("nosource", "%s — подключено к месту, но ни одна механика не включает: %d" % (title, len(nosrc)), nosrc))
		if srcd:
			groups.append(("sourced", "%s — механика есть, но в 12 прогонах бота не встретилось: %d" % (title, len(srcd)), srcd))
	tile, gap = 128, 14
	W = 1960
	per = (W - 60) // (tile + gap)
	h = 200
	for kind, t, lst in groups:
		h += 56 + ((len(lst) + per - 1) // per) * (tile + 62)
	img = Image.new("RGB", (W, h + 30), BG)
	d = ImageDraw.Draw(img)
	d.text((30, 22), "Ассеты карт, которые игра пока не показывает", font=font(TITLE, 50), fill=TEXT)
	d.text((32, 84), "Синие — лежат в комплектах; серые — в art/map, но не подключены; оранжевые — подключены к месту, но их ничто не включает; "
		"жёлтые — механика есть, но в прогонах не встретилось", font=font(FONT, 19), fill=DIM)
	legend(d, 32, 130, ["kit", "unref", "nosource", "sourced"])
	y = 190
	fs = font(FONT, 14)
	for kind, t, lst in groups:
		d.text((30, y + 10), t, font=font(FONT_B, 26), fill=STATUS[kind][0])
		y += 56
		for i, (k, p) in enumerate(lst):
			x = 30 + (i % per) * (tile + gap)
			yy = y + (i // per) * (tile + 62)
			try:
				img.paste(thumb(p, tile), (x, yy))
			except Exception:
				pass
			d.rectangle([x - 2, yy - 2, x + tile + 2, yy + tile + 2], outline=STATUS[kind][0], width=3)
			for j, wl in enumerate(wrap(d, k, fs, tile)[:3]):
				d.text((x, yy + tile + 4 + j * 16), wl, font=fs, fill=TEXT)
		y += ((len(lst) + per - 1) // per) * (tile + 62)
	img.save(out, quality=88)
	return groups


def main():
	tl_dir, cov_path, kits, out = sys.argv[1:5]
	os.makedirs(out, exist_ok=True)
	tl = json.load(io.open(os.path.join(tl_dir, "timeline.json"), encoding="utf-8"))
	cov = json.load(io.open(cov_path, encoding="utf-8"))
	n = 1
	for chapter, title, region in CHAPTERS:
		if chapter in tl:
			timeline_collage(tl_dir, chapter, title, tl[chapter], os.path.join(out, "1.%d %s — карта по дням.jpg" % (n, title.split(" — ")[0])))
		cfg = load_json("data", "maps", "%s.json" % region)
		files = art_files(region)
		states_collage(region, title, cfg, cov.get(chapter), files, os.path.join(out, "2.%d %s — облики мест.jpg" % (n, title.split(" — ")[0])))
		decals_collage(region, title, cfg, cov.get(chapter), files, os.path.join(out, "2.%db %s — метки и точки.jpg" % (n, title.split(" — ")[0])))
		n += 1
	groups = unused_collage(kits, cov, os.path.join(out, "3 Неиспользованные ассеты.jpg"))
	for kind, t, lst in groups:
		print(t)


if __name__ == "__main__":
	main()
