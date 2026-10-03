"""Перенос комплектов карт (PNG от генерации) в игру: art/map/<регион>/ в webp нужных размеров.
Как у Берега: основа 3072×1536, места и облики 512×512, метки 256×256, полосы 512×128, плитки 512×512,
служебные карты (зоны, кварталы, высоты) — PNG без сжатия цвета, 1024×512.

Запуск: python tools/import_map_kit.py <комплект> [папка комплектов]
  комплекты: academy · real_city · ash_path · dark_city · shore_events (места, облики и метки событий Берега,
  лагерь отряда → art/map/figure/camp_<облик>)
По умолчанию комплекты лежат в C:/Users/alast/Documents/Codex/2026-09-28/new-chat/outputs.
"""
import os
import shutil
import sys

from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..")
KITS = r"C:/Users/alast/Documents/Codex/2026-09-28/new-chat/outputs"

SIZES = {"base": (3072, 1536), "place": (512, 512), "decal": (256, 256), "strip": (512, 128), "tile": (512, 512), "tech": (1024, 512),
	"big": (512, 512)}

# новые места событий Берега: облик по умолчанию — dry (как у всех мест карты-плана)
SHORE_DEFAULT = {"strangers_camp": "occupied", "whale_carcass": "fresh", "tide_grotto": "open", "fallen_star": "glowing",
	"legion_well": "buried", "coral_sinkhole": "open", "sleeping_golem": "dormant", "messenger_nest": "occupied",
	"centipede_lair": "active", "sleepers_graves": "fresh", "stranded_islet": "occupied"}


def out_dir(region):
	d = os.path.join(ROOT, "art", "map", region)
	os.makedirs(d, exist_ok=True)
	return d


def webp(src, dst, size, quality=85):
	im = Image.open(src)
	im = im.convert("RGBA") if im.mode in ("RGBA", "LA", "P") else im.convert("RGB")
	im = im.resize(size, Image.LANCZOS)
	im.save(dst, "WEBP", quality=quality, method=6)


def tech(src, dst):
	# служебная карта: цвета зон должны остаться точными — без сглаживания и без сжатия с потерями
	Image.open(src).convert("RGB").resize(SIZES["tech"], Image.NEAREST).save(dst, "PNG", optimize=True)


def kind_of(name, src=None):
	if name == "base":
		return "base"
	if name.startswith("tile_") or name.endswith("_tile") or name == "crimson_haze":
		return "tile"
	if name.startswith("decal_") or name.startswith("ally_") or name.startswith("party_"):
		if src is not None:
			w, h = Image.open(src).size
			if w >= 3 * h:
				return "strip"   # полоса на тропу
			if w >= 1024:
				return "big"     # большая метка: свечение зоны, отсвет Шпиля
		return "decal"
	if name in ("swarm_stain", "path_blocked", "wave_stain") or name.startswith("road_"):
		return "strip"
	return "place"


def copy_fog(region):
	# туман неизвестного — общая плитка всех карт-планов (из комплекта Берега)
	src = os.path.join(ROOT, "art", "map", "forgotten_shore", "fog_tile.webp")
	shutil.copyfile(src, os.path.join(out_dir(region), "fog_tile.webp"))


def import_flat(region, src_dir, tech_names=()):
	"""Все PNG из папки комплекта: base → основа, служебные карты → PNG, остальное — по префиксу имени."""
	dst = out_dir(region)
	n = 0
	for f in sorted(os.listdir(src_dir)):
		if not f.endswith(".png"):
			continue
		name = f[:-4]
		src = os.path.join(src_dir, f)
		if name in tech_names:
			tech(src, os.path.join(dst, name + ".png"))
		else:
			k = kind_of(name, src)
			webp(src, os.path.join(dst, name + ".webp"), SIZES[k], 82 if k == "base" else 85)
		n += 1
	copy_fog(region)
	return n


def academy(kits):
	return import_flat("academy", os.path.join(kits, "academy-map-kit", "academy"), tech_names=("zones",))


def real_city(kits):
	k = os.path.join(kits, "real-city-map-kit")
	dst = out_dir("real_city")
	webp(os.path.join(k, "base.png"), os.path.join(dst, "base.webp"), SIZES["base"], 82)
	tech(os.path.join(k, "districts.png"), os.path.join(dst, "districts.png"))
	tech(os.path.join(k, "height_zones.png"), os.path.join(dst, "height.png"))
	n = 3
	for sub in ("places",):
		for d in sorted(os.listdir(os.path.join(k, sub))):
			for f in sorted(os.listdir(os.path.join(k, sub, d))):
				webp(os.path.join(k, sub, d, f), os.path.join(dst, f[:-4] + ".webp"), SIZES["place"])
				n += 1
	for sub, kind in (("gates", "place"), ("decals", "decal"), ("roads", "strip"), ("tiles", "tile")):
		for f in sorted(os.listdir(os.path.join(k, sub))):
			webp(os.path.join(k, sub, f), os.path.join(dst, f[:-4] + ".webp"), SIZES[kind])
			n += 1
	copy_fog("real_city")
	return n


def shore_events(kits):
	src_dir = os.path.join(kits, "sunless-map-events-kit", "art", "map", "forgotten_shore")
	dst = out_dir("forgotten_shore")
	fig = os.path.join(ROOT, "art", "map", "figure")
	os.makedirs(fig, exist_ok=True)
	n = 0
	for f in sorted(os.listdir(src_dir)):
		if not f.endswith(".png"):
			continue
		name = f[:-4]
		src = os.path.join(src_dir, f)
		if name.startswith("party_camp_"):
			# лагерь отряда — общий для всех глав (рядом с фигурой ночью)
			webp(src, os.path.join(fig, "camp_" + name[len("party_camp_"):] + ".webp"), (384, 384))
			n += 1
			continue
		for place, default in SHORE_DEFAULT.items():
			if name == "%s_%s" % (place, default):
				name = place + "_dry"
		k = kind_of(name, src)
		webp(src, os.path.join(dst, name + ".webp"), SIZES[k])
		n += 1
	return n


def chapter4(kits, region):
	return import_flat(region, os.path.join(kits, "sunless-chapter4-map-kit", "art", "map", region), tech_names=("height", "districts"))


if __name__ == "__main__":
	kit = sys.argv[1] if len(sys.argv) > 1 else "academy"
	kits = sys.argv[2] if len(sys.argv) > 2 else KITS
	n = {"academy": lambda: academy(kits), "real_city": lambda: real_city(kits),
		"ash_path": lambda: chapter4(kits, "ash_path"), "dark_city": lambda: chapter4(kits, "dark_city"),
		"shore_events": lambda: shore_events(kits)}[kit]()
	print("перенесено файлов:", n)
