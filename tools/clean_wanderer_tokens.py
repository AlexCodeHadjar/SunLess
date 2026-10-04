"""Фишки бродячих боссов без подставки (просьба владельца 04.10): у сгенерированных фишек под тварью своя плита земли
(песок, пепел, брусчатка, асфальт) — на карте она выделяется на любой текстуре. Скрипт убирает землю и оставляет тело.

Как: цвета земли берутся с внешнего края подставки (нижняя часть силуэта — почти сплошь земля), всё близкое к ним
по цвету становится прозрачным; тело (багровый хитин, угольная чешуя, чёрный плащ, стекло) остаётся. Дырки в теле
заделываются, мелкие острова земли выбрасываются, край смягчается. Тень у ног рисует игра (WanderToken).
    python tools/clean_wanderer_tokens.py [папка с W*_*.png 1024] [--preview папка]
Пишет art/map/wanderers/W*_*.webp (512×512, прозрачность).
"""
import glob
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = r"C:/Users/alast/Documents/Codex/2026-10-04/new-chat/outputs/sunless-wanderers/art/map/wanderers"
SIZE = 512
# порог отличия от цветов земли (0–441, RGB): ниже t0 — земля, выше t1 — тело; keep_top — доля силуэта сверху,
# где земли не бывает (там всё — тело)
# r0–r1 — где по овалу плиты начинается и кончается растворение (1 — край плиты); up — насколько выше центра плиты
# всё считается телом; t0–t1 — насколько цвет должен отличаться от земли, чтобы не раствориться
PARAMS = {
	"W1": {"r0": 0.52, "r1": 0.82, "up": 0.55, "t0": 55, "t1": 85},
	"W2": {"r0": 0.56, "r1": 0.88, "up": 0.55, "t0": 60, "t1": 90},
	"W3": {"r0": 0.40, "r1": 0.68, "up": 0.40, "t0": 45, "t1": 75},
	"W4": {"r0": 0.58, "r1": 0.86, "up": 0.45, "t0": 55, "t1": 85},
}


def kmeans(x, k, iters=12, seed=1):
	rng = np.random.default_rng(seed)
	c = x[rng.choice(len(x), size=min(k, len(x)), replace=False)].astype(np.float32)
	for _ in range(iters):
		d = ((x[:, None, :] - c[None, :, :]) ** 2).sum(-1)
		lab = d.argmin(1)
		for j in range(len(c)):
			m = x[lab == j]
			if len(m):
				c[j] = m.mean(0)
	return c


def morph(mask, size, op):
	im = Image.fromarray((mask * 255).astype(np.uint8))
	im = im.filter(ImageFilter.MaxFilter(size) if op == "dilate" else ImageFilter.MinFilter(size))
	return np.asarray(im) > 127


def components(mask):
	"""Метки связных областей (4-связность) — простой проход с объединением."""
	h, w = mask.shape
	lab = np.zeros((h, w), np.int32)
	parent = [0]

	def find(a):
		while parent[a] != a:
			parent[a] = parent[parent[a]]
			a = parent[a]
		return a
	nxt = 1
	for y in range(h):
		row = mask[y]
		for x in range(w):
			if not row[x]:
				continue
			up = lab[y - 1, x] if y else 0
			left = lab[y, x - 1] if x else 0
			if up and left:
				a, b = find(up), find(left)
				lab[y, x] = min(a, b)
				if a != b:
					parent[max(a, b)] = min(a, b)
			elif up or left:
				lab[y, x] = up or left
			else:
				parent.append(nxt)
				lab[y, x] = nxt
				nxt += 1
	roots = np.array([find(i) for i in range(len(parent))], np.int32)
	return roots[lab]


def clean(path, prm):
	"""Подставка растворяется по овалу: середина под тварью остаётся (тень у ног), края плиты и её бока — прозрачные;
	части тела, явно не похожие на землю (хитин, свечение, стекло, плащ), под растворение не попадают."""
	im = Image.open(path).convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
	a = np.asarray(im).astype(np.float32)
	rgb, alpha = a[..., :3], a[..., 3] / 255.0
	inside = alpha > 0.5
	ys, xs = np.nonzero(inside)
	top, bottom = ys.min(), ys.max()
	hgt = bottom - top
	# верх плиты — овал: ширина — самая широкая строка нижней половины силуэта
	widths = inside.sum(1)
	lower = np.arange(SIZE) > top + 0.45 * hgt
	row = int(np.argmax(np.where(lower, widths, 0)))
	cols = np.nonzero(inside[row])[0]
	cx = (cols.min() + cols.max()) / 2.0
	rx = (cols.max() - cols.min()) / 2.0
	ry = rx * prm.get("iso", 0.52)
	cy = row - ry * 0.15
	yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
	e = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)
	fade = 1.0 - np.clip((e - prm["r0"]) / (prm["r1"] - prm["r0"]), 0, 1)
	# выше плиты — тело целиком; переход к растворению плавный (без горизонтального шва)
	edge = cy - ry * prm["up"]
	w = np.clip((yy - (edge - 40.0)) / 80.0, 0, 1)
	w = w * w * (3 - 2 * w)
	fade = (1.0 - w) + fade * w
	# цвета земли — с внешнего края плиты; явно другое — тело, его не растворяем
	rim = inside & ~morph(inside, 17, "erode") & (yy > top + 0.55 * hgt)
	centers = kmeans(rgb[rim].reshape(-1, 3), 20)
	flat = rgb.reshape(-1, 3)
	d = np.full(len(flat), 1e9, np.float32)
	for c in centers:
		d = np.minimum(d, np.sqrt(((flat - c) ** 2).sum(1)))
	d = d.reshape(SIZE, SIZE)
	protect = np.clip((d - prm["t0"]) / (prm["t1"] - prm["t0"]), 0, 1)
	protect = np.asarray(Image.fromarray((protect * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(3))) / 255.0
	keep = np.maximum(fade, protect)
	keep = np.asarray(Image.fromarray((keep * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2.0))) / 255.0
	out_a = np.clip(alpha * keep, 0, 1)
	return Image.fromarray(np.dstack([rgb, out_a * 255]).astype(np.uint8), "RGBA")


def main():
	argv = sys.argv[1:]
	preview = None
	if "--preview" in argv:
		i = argv.index("--preview")
		preview = argv[i + 1]
		argv = argv[:i] + argv[i + 2:]
	src = argv[0] if argv else SRC
	out_dir = preview or os.path.join(ROOT, "art", "map", "wanderers")
	os.makedirs(out_dir, exist_ok=True)
	for p in sorted(glob.glob(os.path.join(src, "W*_*.png"))):
		name = os.path.splitext(os.path.basename(p))[0]
		img = clean(p, PARAMS[name.split("_")[0]])
		if preview:
			img.save(os.path.join(out_dir, name + ".png"))
		else:
			img.save(os.path.join(out_dir, name + ".webp"), "WEBP", quality=90, method=6)
		print(name, "ok")


if __name__ == "__main__":
	main()
