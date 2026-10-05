"""Макет экрана пошагового боя «Схватка» (docs/24) из готовых картинок проекта → docs/assets/art/combat/mockup_skirmish.png.

Это схема для ТЗ, а не игра: фигуры — временные (каменные фигуры героев с карты-плана и фишки бродячих боссов),
настоящие боевые позы появятся после генерации по «Пошаговый бой — промты ChatGPT.docx».
    python tools/skirmish_mockup.py
"""
import os

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "assets", "art", "combat", "mockup_skirmish.png")
W, H = 1920, 1080
FLOOR = 640           # линия ног бойцов
PANEL = 790           # верх нижней панели

BG_DEEP = (14, 15, 20)
BG_PANEL = (23, 25, 34)
BG_RAISED = (34, 37, 50)
LINE = (58, 62, 78)
TEXT = (230, 225, 214)
DIM = (154, 156, 166)
SILVER = (201, 206, 214)
GOLD = (184, 154, 94)
BLOOD = (176, 48, 60)
PSY = (150, 170, 225)
GOOD = (111, 164, 123)


def P(*p):
	return os.path.join(ROOT, *p)


def font(name, size):
	return ImageFont.truetype(P("ui", "fonts", name), size)


F_CAPS = lambda s: font("CormorantSC-SemiBold.ttf", s)
F_SANS = lambda s: font("PT_Sans-Regular.ttf", s)
F_BOLD = lambda s: font("PT_Sans-Bold.ttf", s)
F_ITAL = lambda s: font("PT_Serif-Italic.ttf", s)


def load(rel):
	return Image.open(P(*rel.split("/"))).convert("RGBA")


def fit_h(im, h):
	return im.resize((max(1, int(im.width * h / im.height)), h), Image.LANCZOS)


def crop_top(card, ratio=0.62):
	"""Верхнее поле карты (без нижней плашки)."""
	w, h = card.size
	return card.crop((int(w * 0.07), int(h * 0.05), int(w * 0.93), int(h * ratio)))


def rounded(d, box, r, fill=None, outline=None, width=1):
	d.rounded_rectangle(box, r, fill=fill, outline=outline, width=width)


def text_c(d, xy, s, f, fill):
	w = d.textlength(s, font=f)
	d.text((xy[0] - w / 2, xy[1]), s, font=f, fill=fill)


def bar(d, x, y, w, h, frac, col, back=(40, 20, 24)):
	d.rectangle((x, y, x + w, y + h), fill=back)
	d.rectangle((x, y, x + int(w * frac), y + h), fill=col)
	d.rectangle((x, y, x + w, y + h), outline=(0, 0, 0))


def pips(d, x, y, frac, n=10):
	"""Психика — 10 делений."""
	on = round(frac * n)
	for i in range(n):
		c = PSY if i < on else (40, 44, 60)
		d.rectangle((x + i * 9, y, x + i * 9 + 6, y + 6), fill=c)


def status(d, x, y, letter, col):
	d.ellipse((x, y, x + 22, y + 22), fill=(20, 20, 26), outline=col, width=2)
	text_c(d, (x + 11, y + 2), letter, F_BOLD(13), col)


def pos_pips(d, x, y, launch, target):
	"""Как в DD: слева 4 позиции героя (откуда), справа 4 позиции врага (куда)."""
	for i in range(4):     # герой: 4 3 2 1
		p = 4 - i
		d.ellipse((x + i * 10, y, x + i * 10 + 7, y + 7), fill=GOLD if p in launch else (50, 52, 64))
	for i in range(4):     # враг: 1 2 3 4
		p = i + 1
		d.ellipse((x + 46 + i * 10, y, x + 46 + i * 10 + 7, y + 7), fill=BLOOD if p in target else (50, 52, 64))


def main():
	img = Image.new("RGBA", (W, H), BG_DEEP + (255,))
	# фон места (Берег) — приглушён, как «сумрак»
	bg = load("art/regions/forgotten_shore_day.webp")
	bg = bg.resize((W, int(bg.height * W / bg.width)))
	bg = ImageEnhance.Brightness(bg).enhance(0.55)
	img.alpha_composite(bg.crop((0, 60, W, 60 + PANEL)), (0, 0))
	d = ImageDraw.Draw(img)
	# полоса «пола» сцены
	floor = Image.new("RGBA", (W, PANEL - FLOOR + 40), (0, 0, 0, 0))
	fd = ImageDraw.Draw(floor)
	for i in range(floor.height):
		fd.line((0, i, W, i), fill=(8, 9, 12, min(200, 40 + i * 2)))
	img.alpha_composite(floor, (0, FLOOR - 40))
	# виньетка сверху
	top = Image.new("RGBA", (W, 120), (0, 0, 0, 0))
	td = ImageDraw.Draw(top)
	for i in range(120):
		td.line((0, i, W, i), fill=(8, 9, 12, max(0, 200 - i * 2)))
	img.alpha_composite(top, (0, 0))

	# --- бойцы ------------------------------------------------------------------------------------------------------
	heroes = [   # позиция → (картинка, имя, здоровье, психика, состояния)
		(1, "art/map/figure/nephis.webp", "Нефис", 0.82, 0.7, [("З", GOLD)]),
		(2, "art/map/figure/sunny.webp", "Санни", 0.55, 0.45, [("С", SILVER), ("К", BLOOD)]),
		(3, "art/map/figure/cassie.webp", "Касси", 0.9, 0.8, []),
	]
	hx = {1: 760, 2: 600, 3: 440, 4: 280}
	ex = {1: 1160, 2: 1320, 3: 1480, 4: 1640}
	for p, path, name, hp, psy, st in heroes:
		fig = fit_h(load(path), 300)
		fig = fig.crop((0, 0, fig.width, int(fig.height * 0.86)))       # без постамента — на сцене его не будет
		x = hx[p] - fig.width // 2
		if p == 2:       # ходит сейчас: золотое кольцо
			d.ellipse((hx[p] - 70, FLOOR - 14, hx[p] + 70, FLOOR + 14), outline=GOLD, width=4)
		img.alpha_composite(fig, (x, FLOOR - fig.height))
		bar(d, hx[p] - 55, FLOOR + 22, 110, 9, hp, BLOOD)
		pips(d, hx[p] - 45, FLOOR + 36, psy)
		for i, (l, c) in enumerate(st):
			status(d, hx[p] - 55 + i * 26, FLOOR + 48, l, c)
		text_c(d, (hx[p], FLOOR - 330), name, F_CAPS(26), TEXT)
	# свободная позиция 4 — место для Эха
	d.ellipse((hx[4] - 60, FLOOR - 12, hx[4] + 60, FLOOR + 12), outline=(120, 120, 140), width=2)
	text_c(d, (hx[4], FLOOR - 120), "позиция 4", F_SANS(18), DIM)
	text_c(d, (hx[4], FLOOR - 96), "свободна — Эхо", F_ITAL(20), DIM)

	crab = fit_h(load("art/map/wanderers/W1_1.webp"), 230)
	for p in (1, 2):
		if p == 1:   # цель под курсором: красное кольцо
			d.ellipse((ex[p] - 75, FLOOR - 14, ex[p] + 75, FLOOR + 14), outline=BLOOD, width=4)
		img.alpha_composite(crab, (ex[p] - crab.width // 2, FLOOR - crab.height + 20))
		bar(d, ex[p] - 55, FLOOR + 22, 110, 9, 0.62 if p == 1 else 1.0, BLOOD)
		if p == 2:   # над целью — урон, имя только у второго
			text_c(d, (ex[p], FLOOR - 250), "Падальщик", F_CAPS(24), TEXT)
	status(d, ex[1] - 55, FLOOR + 38, "М", (230, 120, 60))
	status(d, ex[1] - 29, FLOOR + 38, "К", BLOOD)
	# труп на позиции 3
	d.ellipse((ex[3] - 60, FLOOR - 26, ex[3] + 60, FLOOR + 6), fill=(30, 26, 28))
	text_c(d, (ex[3], FLOOR - 70), "труп", F_ITAL(22), DIM)
	text_c(d, (ex[3], FLOOR - 46), "держит место", F_SANS(16), DIM)
	hunter = fit_h(load("art/map/wanderers/W3_1.webp"), 250)
	img.alpha_composite(hunter, (ex[4] - hunter.width // 2, FLOOR - hunter.height + 10))
	bar(d, ex[4] - 55, FLOOR + 22, 110, 9, 0.9, BLOOD)
	status(d, ex[4] - 55, FLOOR + 38, "С", SILVER)
	text_c(d, (ex[4], FLOOR - 270), "Ловчий", F_CAPS(24), TEXT)
	# номера позиций
	for p in range(1, 5):
		text_c(d, (hx[p], FLOOR + 74), str(p), F_BOLD(16), (110, 110, 125))
		text_c(d, (ex[p], FLOOR + 74), str(p), F_BOLD(16), (110, 110, 125))
	# удар: числа над целью
	text_c(d, (ex[1], FLOOR - 330), "−7", F_BOLD(48), (235, 90, 90))
	text_c(d, (ex[1], FLOOR - 280), "Кровотечение", F_SANS(18), (235, 120, 120))

	# --- верхняя полоса ---------------------------------------------------------------------------------------------
	rounded(d, (24, 18, 520, 74), 10, fill=(14, 15, 20, 220), outline=LINE)
	d.text((40, 24), "ОТМЕЛЬ  ·  Песок · Вода", font=F_CAPS(26), fill=TEXT)
	d.text((40, 52), "поле: огонь слабее, скользко у воды", font=F_SANS(15), fill=DIM)
	rounded(d, (W // 2 - 330, 14, W // 2 + 330, 86), 12, fill=(14, 15, 20, 230), outline=LINE)
	text_c(d, (W // 2, 18), "РАУНД 2 · очередь ходов", F_CAPS(20), DIM)
	order = [("art/cards/P01.webp", GOLD), ("art/cards/M03.png", BLOOD), ("art/cards/P02.webp", SILVER),
		("art/cards/MW3.webp", BLOOD), ("art/cards/P03.webp", SILVER), ("art/cards/M03.png", BLOOD)]
	for i, (path, col) in enumerate(order):
		face = crop_top(load(path), 0.45).resize((46, 46))
		x = W // 2 - 3 * 58 + i * 58 + 6
		mask = Image.new("L", (46, 46), 0)
		ImageDraw.Draw(mask).ellipse((0, 0, 45, 45), fill=255)
		img.paste(face, (x, 38), mask)
		d.ellipse((x - 2, 36, x + 48, 86), outline=col, width=3 if i == 0 else 2)
	rounded(d, (W - 560, 18, W - 200, 74), 10, fill=(14, 15, 20, 220), outline=LINE)
	d.text((W - 544, 24), "СВЕТ: ТУСКЛЫЙ", font=F_CAPS(24), fill=(210, 190, 140))
	d.text((W - 544, 52), "вторая половина дня · психика тает быстрее", font=F_SANS(15), fill=DIM)
	rounded(d, (W - 186, 18, W - 24, 74), 10, fill=(40, 18, 22, 230), outline=BLOOD)
	text_c(d, (W - 105, 30), "Отступить", F_CAPS(26), TEXT)

	# мысль героя
	rounded(d, (330, 236, 870, 282), 20, fill=(20, 22, 30, 230), outline=LINE)
	d.polygon([(590, 282), (612, 282), (600, 300)], fill=(20, 22, 30, 230))
	text_c(d, (600, 244), "«Клешни. Значит, не в лоб — сбоку и из тени.»", F_ITAL(22), TEXT)

	# --- нижняя панель ---------------------------------------------------------------------------------------------
	d.rectangle((0, PANEL, W, H), fill=BG_PANEL)
	d.line((0, PANEL, W, PANEL), fill=GOLD, width=2)
	# слева — ходящий герой
	card = crop_top(load("art/cards/P01.webp"), 0.6).resize((150, 190))
	img.alpha_composite(card, (24, PANEL + 22))
	d.rectangle((24, PANEL + 22, 174, PANEL + 212), outline=SILVER, width=2)
	d.text((190, PANEL + 18), "САННИ", font=F_CAPS(34), fill=TEXT)
	d.text((190, PANEL + 58), "Спящий · ядро 2/5", font=F_SANS(17), fill=DIM)
	d.text((190, PANEL + 86), "Здоровье 13 / 23", font=F_BOLD(18), fill=(230, 130, 130))
	bar(d, 190, PANEL + 110, 260, 10, 13 / 23, BLOOD)
	d.text((190, PANEL + 126), "Психика 45 — тревожно", font=F_BOLD(18), fill=PSY)
	pips(d, 190, PANEL + 150, 0.45)
	tags = ["Хладнокровие", "Скрытность", "Тень", "Чутьё", "Человек"]
	x, y = 190, PANEL + 168
	for t in tags:
		w = d.textlength(t, font=F_SANS(15)) + 16
		if x + w > 560:
			x, y = 190, y + 28
		rounded(d, (x, y, x + w, y + 24), 6, fill=BG_RAISED, outline=LINE)
		d.text((x + 8, y + 3), t, font=F_SANS(15), fill=SILVER)
		x += w + 6
	# центр — навыки
	d.text((600, PANEL + 14), "НАВЫКИ", font=F_CAPS(20), fill=GOLD)
	skills = [   # (подпись, картинка или None, откуда, куда, отметка)
		("Удар из тени", None, [1, 2, 3], [1, 2], "свой"),
		("Раствориться", None, [1, 2, 3, 4], [], "свой"),
		("Цепь-хлыст", "art/cards/U01.webp", [1, 2], [1, 2], "оружие"),
		("Колокольчик", "art/cards/U02.png", [2, 3, 4], [1, 2, 3, 4], "1 ход"),
		("Тень-разведчик", "art/cards/A01.webp", [1, 2, 3, 4], [1, 2, 3, 4], "раз за бой"),
		("Шаг", None, [1, 2, 3, 4], [], ""),
		("Пропуск", None, [1, 2, 3, 4], [], ""),
	]
	for i, (name, art, la, ta, note) in enumerate(skills):
		x = 600 + i * 132
		y = PANEL + 44
		sel = i == 0
		rounded(d, (x, y, x + 118, y + 150), 8, fill=BG_RAISED, outline=GOLD if sel else LINE, width=3 if sel else 1)
		if art:
			pic = crop_top(load(art), 0.6).resize((106, 96))
			img.alpha_composite(pic, (x + 6, y + 6))
		else:
			d.rectangle((x + 6, y + 6, x + 112, y + 102), fill=(26, 28, 38))
			text_c(d, (x + 59, y + 40), "иконка", F_ITAL(16), (90, 92, 104))
		text_c(d, (x + 59, y + 106), name, F_SANS(14), TEXT)
		if la and name not in ("Шаг", "Пропуск", "Раствориться"):
			pos_pips(d, x + 18, y + 128, la, ta)
		if note:
			text_c(d, (x + 59, y + 152), note, F_ITAL(14), DIM)
	# справа — цель и расчёт удара (по наведению)
	x0 = 1540
	rounded(d, (x0, PANEL + 14, W - 20, H - 16), 10, fill=(18, 19, 26), outline=LINE)
	d.text((x0 + 14, PANEL + 20), "ПАДАЛЬЩИК КАРАПАКСА", font=F_CAPS(22), fill=TEXT)
	d.text((x0 + 14, PANEL + 50), "Здоровье 11 / 18 · Панцирь, Когти", font=F_SANS(15), fill=DIM)
	lines = [
		("Попадание", "78%", TEXT), ("Урон", "5–8", (235, 120, 120)), ("Крит", "13%", GOLD),
		("Кровотечение", "60% · 2 × 3 хода", (235, 120, 120)), ("из тени", "×1,5 урона, верный крит", SILVER),
		("Панцирь", "−25% урона", DIM), ("Хитин", "удар в сочленения: +10%", GOOD),
	]
	for i, (a, b, c) in enumerate(lines):
		y = PANEL + 80 + i * 26
		d.text((x0 + 14, y), a, font=F_SANS(16), fill=DIM)
		w = d.textlength(b, font=F_BOLD(16))
		d.text((W - 34 - w, y), b, font=F_BOLD(16), fill=c)

	# подпись
	d.text((24, PANEL - 34), "МАКЕТ · фигуры временные (с карты-плана), будут боевые позы", font=F_SANS(15), fill=(150, 150, 160))
	os.makedirs(os.path.dirname(OUT), exist_ok=True)
	img.convert("RGB").save(OUT, "PNG", optimize=True)
	print("макет:", OUT)


if __name__ == "__main__":
	main()
