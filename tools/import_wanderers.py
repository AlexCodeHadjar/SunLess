"""Картинки бродячих боссов (docs/22) → игра. Исходники лежат в проекте: docs/assets/art/wanderers/
(листы ракурсов W1_sheet.png … W4_sheet.png — 2×2, без подставок; карты MW1–MW4, LW1–LW4).

Фишки: лист режется на 4 ракурса по прозрачной щели у середины (тварь может заходить за середину), каждый ракурс
обрезается по силуэту; у всех ракурсов одного босса — один масштаб и общая линия земли (низ силуэта), чтобы при
смене ракурса тварь не прыгала. Порядок на листе (как в промте): сверху слева — 1 (вниз-влево), сверху справа — 2
(вниз-вправо), снизу справа — 3 (вверх-вправо, спиной), снизу слева — 4 (вверх-влево, спиной).
→ art/map/wanderers/W*_1…4.webp (512×512, прозрачность).

Карты: рамка карты находится по яркой серебряной кромке и вписывается в 476×816 (7:12) с тем же полем, что у
остальных карт игры (кромка в ~6 px от края) → art/cards/MW*.webp, LW*.webp.
    python tools/import_wanderers.py [папка исходников]
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "docs", "assets", "art", "wanderers")
TOKENS = os.path.join(ROOT, "art", "map", "wanderers")
CARDS = os.path.join(ROOT, "art", "cards")
SIZE = 512
GROUND = 0.92      # линия земли (низ силуэта) — доля высоты фишки
FILL_W = 0.92      # самый широкий ракурс занимает такую долю ширины
FILL_H = 0.86      # самый высокий — такую долю высоты
CARD = (476, 816)
CARD_EDGE = (6, 5)  # где у карт игры серебряная кромка: от левого/правого и от верхнего/нижнего края


def _split(alpha, axis):
	"""Где резать лист: линия у середины с наименьшей непрозрачностью (щель между ракурсами)."""
	prof = alpha.sum(axis=axis)
	n = len(prof)
	lo, hi = int(n * 0.38), int(n * 0.62)
	return lo + int(np.argmin(prof[lo:hi]))


def _cells(path):
	im = Image.open(path).convert("RGBA")
	a = np.asarray(im)[..., 3].astype(np.float32)
	cx = _split(a, 0)
	cy = _split(a, 1)
	w, h = im.size
	boxes = {1: (0, 0, cx, cy), 2: (cx, 0, w, cy), 3: (cx, cy, w, h), 4: (0, cy, cx, h)}
	out = {}
	for k, b in boxes.items():
		cell = im.crop(b)
		bb = cell.getchannel("A").point(lambda v: 255 if v > 10 else 0).getbbox()
		out[k] = cell.crop(bb) if bb else cell
	return out


def tokens(boss, src):
	cells = _cells(os.path.join(src, "%s_sheet.png" % boss))
	mw = max(c.width for c in cells.values())
	mh = max(c.height for c in cells.values())
	s = min(SIZE * FILL_W / mw, SIZE * FILL_H / mh)
	os.makedirs(TOKENS, exist_ok=True)
	for k, c in cells.items():
		t = c.resize((max(1, int(c.width * s)), max(1, int(c.height * s))), Image.LANCZOS)
		canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
		canvas.alpha_composite(t, ((SIZE - t.width) // 2, int(SIZE * GROUND) - t.height))
		canvas.save(os.path.join(TOKENS, "%s_%d.webp" % (boss, k)), "WEBP", quality=90, method=6)
	print(boss, "ракурсы:", {k: c.size for k, c in cells.items()}, "масштаб %.3f" % s)


def _edge(lum, axis_len, getter):
	for i in range(min(80, axis_len)):
		if getter(i) > 100:
			return i
	return 0


def card(cid, src):
	im = Image.open(os.path.join(src, "%s.png" % cid)).convert("RGB")
	a = np.asarray(im.convert("L")).astype(np.float32)
	h, w = a.shape
	left = _edge(a, w, lambda i: a[:, i].mean())
	right = _edge(a, w, lambda i: a[:, w - 1 - i].mean())
	top = _edge(a, h, lambda i: a[i, :].mean())
	bottom = _edge(a, h, lambda i: a[h - 1 - i, :].mean())
	fw = (w - 1 - right) - left
	fh = (h - 1 - bottom) - top
	ex, ey = CARD_EDGE
	sx = (CARD[0] - 1 - 2 * ex) / fw
	sy = (CARD[1] - 1 - 2 * ey) / fh
	box = (left - ex / sx, top - ey / sy, w - 1 - right + ex / sx + 1, h - 1 - bottom + ey / sy + 1)
	pad = Image.new("RGB", (w + 200, h + 200), im.getpixel((2, 2)))
	pad.paste(im, (100, 100))
	box = tuple(v + 100 for v in box)
	out = pad.crop(tuple(int(round(v)) for v in box)).resize(CARD, Image.LANCZOS)
	out.save(os.path.join(CARDS, "%s.webp" % cid), "WEBP", quality=88, method=6)
	print(cid, "рамка %dx%d → %s (сжатие по ширине %.1f%%)" % (fw, fh, CARD, 100 * (1 - (sx / sy))))


def main():
	src = sys.argv[1] if len(sys.argv) > 1 else SRC
	for b in ["W1", "W2", "W3", "W4"]:
		tokens(b, src)
	for c in ["MW1", "MW2", "MW3", "MW4", "LW1", "LW2", "LW3", "LW4"]:
		card(c, src)


if __name__ == "__main__":
	main()
