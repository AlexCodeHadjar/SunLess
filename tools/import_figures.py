"""Фигуры (docs/18): картинки владельца docs/assets/art/map/figure/*.png → art/map/figure/*.webp.

Обрезка по непрозрачному контуру с небольшим полем, длинная сторона — 512 px, прозрачность сохраняется.
    python tools/import_figures.py
"""
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "docs", "assets", "art", "map", "figure")
DST = os.path.join(ROOT, "art", "map", "figure")
MAX = 512


def main():
	os.makedirs(DST, exist_ok=True)
	for f in sorted(os.listdir(SRC)):
		if not f.lower().endswith(".png"):
			continue
		im = Image.open(os.path.join(SRC, f)).convert("RGBA")
		bb = im.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
		if bb:
			pad = int(max(bb[2] - bb[0], bb[3] - bb[1]) * 0.03)
			bb = (max(0, bb[0] - pad), max(0, bb[1] - pad), min(im.width, bb[2] + pad), min(im.height, bb[3] + pad))
			im = im.crop(bb)
		k = MAX / max(im.size)
		if k < 1.0:
			im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
		out = os.path.join(DST, os.path.splitext(f)[0] + ".webp")
		im.save(out, "WEBP", quality=92, method=6)
		print("%s → %s %s" % (f, os.path.relpath(out, ROOT), im.size))


if __name__ == "__main__":
	main()
