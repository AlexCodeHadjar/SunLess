"""Промты ChatGPT для бродячих боссов (docs/22) → Word: docs/Бродячие боссы — промты ChatGPT.docx.

Просьба владельца 03.10: фишка на карте — 4 кадра с разных ракурсов (босс на своей подставке повёрнут на 90°:
вниз-влево, вниз-вправо, вверх-вправо, вверх-влево; в игре ракурс меняется через прозрачность — по направлению пути
и когда босс оглядывается); к каждому промту — образцы из проекта (картинки прямо в документе и ссылки на файлы);
к промтам карт — шаблон карты docs/assets/cards/templates (пустая обложка и её настройки) и готовые карты-образцы.
Правило на будущее (CLAUDE.md): промты артов карт — всегда с шаблоном и настройками.

Word собирается без сторонних библиотек (WordprocessingML в zip, картинки — уменьшенные PNG внутри документа).
    python tools/gen_boss_prompts.py
"""
import io
import os
import zipfile
from xml.sax.saxutils import escape

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "Бродячие боссы — промты ChatGPT.docx")
TEMPLATE = "docs/assets/cards/templates/SunLess-blank-card-front-7x12.png"
TEMPLATE_TXT = "docs/assets/cards/templates/SunLess-blank-card-prompt.txt"

ANGLES = [
	("вниз-влево", "faces the LOWER-LEFT of the frame: three-quarter FRONT view, its head/front toward the viewer and to the left"),
	("вниз-вправо", "faces the LOWER-RIGHT of the frame: three-quarter FRONT view, its head/front toward the viewer and to the right"),
	("вверх-вправо", "faces the UPPER-RIGHT of the frame: three-quarter BACK view, we see its back/shell and the back of the head, it walks away to the right"),
	("вверх-влево", "faces the UPPER-LEFT of the frame: three-quarter BACK view, we see its back/shell and the back of the head, it walks away to the left"),
]

TOKEN_COMMON = """Use case: map token for SunLess, a dark-fantasy card game. The token is placed ON TOP of a painted isometric map
of small diorama-like places, seen from above at about 35–40 degrees (see the attached map pieces and tokens — match
their style, camera and light). The map itself is the ground under the creature.
SUBJECT: ONLY the creature itself (described below). NO ground, NO base, NO platform, NO patch of sand / ash / stones /
cobbles / asphalt / rubble / water under it, no scenery pieces around it — the creature stands on nothing, on a fully
transparent background, cut out cleanly along its own silhouette. Allowed under its feet: at most a very soft, faint,
small contact shadow (or none) — the game draws the shadow and the ground.
CAMERA: fixed isometric three-quarter top-down view, 35–40° above the horizon. The CAMERA NEVER CHANGES between the four
angles — only the creature is rotated on the spot.
LIGHT: key light always from the UPPER-LEFT of the image (screen space, does not rotate with the creature), cool ambient
fill; one accent glow (stated below), subtle, readable at 120 px.
SCALE AND FRAMING: identical in all four angles — the creature is centred, fills about 75% of the frame, its lowest point
(feet / coils / legs) at about 85% of the frame height, same size every time.
STYLE: painterly realistic dark fantasy like the attached map pieces, detailed but readable silhouette at 120–160 px, rich
materials, muted palette with one accent colour, no outlines, no cartoon.
OUTPUT: 1024×1024 PNG, TRANSPARENT background (no sky, horizon, floor, frame or vignette); if transparency is impossible —
flat solid #FF00FF background with NO ground and NO shadow. No text, letters, logos, UI, no other creatures."""

TOKEN_NEXT = """Use the previous image as the exact reference for the creature: the same creature (same proportions, colours,
materials, damage, accessories), the same size in the frame, the same camera height and the same light from the
upper-left of the image, still with NO ground, NO base and NO platform under it — transparent background. Rotate ONLY
the creature on the spot so that it now {angle}. Nothing else changes."""

SHEET_TIP = """Alternative (better consistency): generate all four angles at once as a 2×2 turnaround sheet, 2048×2048, each cell
1024×1024 on transparent background, order: top-left — lower-left facing, top-right — lower-right facing, bottom-right —
upper-right facing (back view), bottom-left — upper-left facing (back view). Same creature, same scale, same camera,
light always from the upper-left. ONLY the creature in every cell — NO ground, NO base, NO platform under it.
No grid lines, no labels."""

CARD_COMMON = """Use case: stylized-concept. Edit the attached EMPTY SunLess card as a locked template (and follow the attached
template settings text). Exactly ONE separate {kind} card, vertical 7:12, frontal, all four edges visible, filling the
frame, no surrounding surface. Preserve the moon-silver double border, clipped corners, dark paper texture, horizontal
divider and opaque lower title plaque geometry. Change only the INNER UPPER field by illustrating the subject below, and
add only its exact Cyrillic name in centered pale ivory elegant uppercase serif in the lower panel. No stats, icons, rank,
gems, digits, extra lines, runes, fake writing, watermark, logo or added caption. Keep the illustration inside the frame
and above the divider. Dark antique engraved tarot art, fine painterly etching, restrained cool silver and muted accents,
tactile materials, low exposure without blown white highlights, no glossy fantasy (match the attached example cards).
Output: 952×1632 PNG (7:12)."""

BOSSES = [
	{
		"id": "W1", "enemy": "MW1", "reward": "LW1", "name": "Багровый Отшельник", "where": "Забытый Берег",
		"enemy_title": "БАГРОВЫЙ ОТШЕЛЬНИК", "reward_title": "ПАНЦИРЬ ОТШЕЛЬНИКА", "reward_lines": "ONE line",
		"ru": "Исполинский краб-отшельник. Раковина — обломки кораллов, кости и ракушки, наросшие за века; клешни в шипах и "
			"ракушках; тёмно-багровый мокрый хитин. Бродит по отмелям и коралловым полям Берега. Акцент — тусклое красное "
			"свечение в глубине раковины.",
		"subject": "CREATURE: a colossal ancient crimson hermit crab: a towering spiral shell made of broken red coral, bleached bones and "
			"clusters of barnacles; heavy spiked claws crusted with barnacles; wet glossy dark-crimson chitin; small stalked eyes. "
			"ACCENT GLOW: a dim "
			"ember-red glow deep inside the shell opening.",
		"enemy_card": "a colossal ancient hermit crab rising from a tide pool at night on the Forgotten Shore: a spiral shell of broken red "
			"coral and bleached bones crusted with barnacles, barnacle-covered claws raised, a dim ember-red glow inside the shell, black "
			"sea and spray behind; one creature only, no people.",
		"reward_card": "one curved fragment of the Crimson Hermit's shell lying on black wet sand: a plate of red coral and bone with "
			"barnacles, faintly warm-glowing from inside like something alive, a little mist; an artifact of protection, no creature, no person.",
		"refs_map": ["art/map/forgotten_shore/carapace_nest_dry.webp", "art/map/forgotten_shore/low_tide_dry.webp",
			"art/map/forgotten_shore/coral_maze_dry.webp"],
		"refs_card": ["docs/assets/cards/concepts/09-M03-carapace-scavenger.png",
			"docs/assets/cards/concepts/monsters-template-series/10-M37-Багровый-Ужас.png"],
		"refs_reward": ["docs/assets/cards/concepts/enhancements-template-series-v2/02-U12-Эхо-Падальщика-Карапакса.png",
			"docs/assets/cards/concepts/enhancements-template-series-v2/03-U16-Доспехи-Звёздного-Легиона.png"],
	},
	{
		"id": "W2", "enemy": "MW2", "reward": "LW2", "name": "Пепельный Змей", "where": "Древо Души (Пепельное море)",
		"enemy_title": "ПЕПЕЛЬНЫЙ ЗМЕЙ", "reward_title": "ЧЕШУЯ ПЕПЕЛЬНОГО ЗМЕЯ", "reward_lines": "TWO centered lines",
		"ru": "Змей длиной с караван, плывущий в пепельных дюнах. Чешуя — угольные пластины с тлеющими краями; голова тяжёлая, "
			"костяная, рогатая; тело уходит в пепел кольцами. Акцент — оранжевое тление в швах чешуи и в глазах.",
		"subject": "CREATURE: a colossal serpent emerging from ash: the head and two coils of its body rise above a patch of grey ash, the "
			"rest disappears under it; armour of charcoal-black scales with smouldering orange edges, a heavy bony horned head, ash "
			"pouring off it. ACCENT GLOW: "
			"smouldering orange light in the seams between scales and in the eyes.",
		"enemy_card": "the Ash Serpent bursting from a grey ash dune under a dark sky: charcoal scales with smouldering orange edges, ash "
			"pouring off its horned bony skull, embers in the air; one creature only, no people.",
		"reward_card": "a single large charcoal scale of the Ash Serpent lying on a bed of grey ash, its edge still smouldering orange, a "
			"thin curl of smoke; no creature, no person.",
		"refs_map": ["art/map/ash_path/ash_dunes_dry.webp", "art/map/ash_path/ash_bones_dry.webp", "art/map/ash_path/decal_token_demon.webp"],
		"refs_card": ["docs/assets/cards/concepts/monsters-template-series/03-M15-Кровавый-Изверг.png",
			"docs/assets/cards/concepts/monsters-template-series/10-M37-Багровый-Ужас.png"],
		"refs_reward": ["docs/assets/cards/concepts/enhancements-template-series-v2/05-U20-Костяное-копьё.png",
			"docs/assets/cards/concepts/enhancements-template-series-v2/08-U28-Осколок-Луны.png"],
	},
	{
		"id": "W3", "enemy": "MW3", "reward": "LW3", "name": "Ловчий Теней", "where": "Мрачный город",
		"enemy_title": "ЛОВЧИЙ ТЕНЕЙ", "reward_title": "ФОНАРЬ ЛОВЧЕГО", "reward_lines": "ONE line",
		"ru": "Высокий худой ловчий в рваном плаще, лицо скрыто капюшоном и треснувшей костяной маской; на поясе — фонарь-клетка, "
			"в котором бьются пленные тени; на плече — свёрнутая сеть. Ходит по крышам и пустым улицам Мрачного города. Акцент — "
			"холодный бледно-голубой свет фонаря.",
		"subject": "CREATURE: a very tall gaunt hunter (about three times human height) in a long tattered black cloak, the face hidden by a "
			"hood and a cracked bone mask; long thin arms; a cage-lantern on the belt with writhing shadow shapes trapped inside; a "
			"coiled net over one shoulder. "
			"ACCENT GLOW: cold pale-blue light from the cage-lantern.",
		"enemy_card": "the Shadow Catcher on a ruined rooftop of the Dark City at night: gaunt and very tall, tattered cloak, cracked bone "
			"mask, raising a cage-lantern full of trapped writhing shadows, pale-blue light on wet stone; one figure only.",
		"reward_card": "an old iron cage-lantern standing on cobblestones, empty but still glowing pale blue inside, faint shadow wisps "
			"escaping between the bars; no person.",
		"refs_map": ["art/map/dark_city/statue_plaza_dry.webp", "art/map/dark_city/ruined_cathedral_dry.webp",
			"art/map/dark_city/decal_token_hunter.webp"],
		"refs_card": ["docs/assets/cards/concepts/monsters-template-series/05-M25-Отречённый-Рыцарь.png",
			"docs/assets/cards/concepts/monsters-template-series/06-M26-Повелитель-Мёртвых.png"],
		"refs_reward": ["docs/assets/cards/concepts/enhancements-template-series-v2/04-U19-Капля-Ихора.png",
			"docs/assets/cards/concepts/enhancements-template-series-v2/07-U25-Обычный-Камень.png"],
	},
	{
		"id": "W4", "enemy": "MW4", "reward": "LW4", "name": "Стеклянная Королева", "where": "Город людей",
		"enemy_title": "СТЕКЛЯННАЯ КОРОЛЕВА", "reward_title": "ОСКОЛОК СТЕКЛЯННОЙ КОРОЛЕВЫ", "reward_lines": "TWO centered lines",
		"ru": "Тварь из Врат: длинное многоногое тело в панцире из битого стекла, витрин и автомобильных фар; голова — венец из "
			"острых осколков; вокруг ползают мелкие стеклянные твари. Бродит по пустым кварталам. Акцент — холодный бирюзовый "
			"отблеск в стекле.",
		"subject": "CREATURE: a monstrous insect-like queen as long as a bus: a segmented many-legged body armoured with shards of broken "
			"glass, shop-window panes and cracked car headlights; a crown of sharp glass spikes on its head; a few tiny glass "
			"crawlers by its legs. "
			"ACCENT GLOW: cold teal reflections inside the glass armour.",
		"enemy_card": "the Glass Queen in an abandoned city street at night: armoured in shattered shop windows and car headlights, glass "
			"crown flared, a glittering swarm of tiny glass crawlers around her, broken streetlights; one creature with its swarm, no people.",
		"reward_card": "one long sharp shard of the Glass Queen's armour lying on cracked asphalt, its edge catching a cold teal light, tiny "
			"reflections of a ruined city inside it; no creature, no person.",
		"refs_map": ["art/map/real_city/old_center_dry.webp", "art/map/real_city/market_dry.webp", "art/map/real_city/monorail_dry.webp"],
		"refs_card": ["docs/assets/cards/concepts/monsters-template-series/08-M29-Железный-Паук.png",
			"docs/assets/cards/concepts/monsters-template-series/02-M06-Красные-многоножки-Лабиринта.png"],
		"refs_reward": ["docs/assets/cards/concepts/enhancements-template-series-v2/08-U28-Осколок-Луны.png",
			"docs/assets/cards/concepts/enhancements-template-series-v2/09-U34-Пыльца-Кровавого-Цветка.png"],
	},
]

TOKEN_REFS = ["art/map/ash_path/decal_token_demon.webp", "art/map/dark_city/decal_token_hunter.webp", "art/map/figure/sunny.webp"]


# --- Word (WordprocessingML): абзацы, ссылки, картинки --------------------------------------------------------------------

class Doc:
	def __init__(self):
		self.body = []
		self.rels = []      # (id, type, target, external)
		self.media = []     # (name, bytes)
		self.pic = 0

	def rel(self, typ, target, external=False):
		rid = "rId%d" % (len(self.rels) + 10)
		self.rels.append((rid, typ, target, external))
		return rid

	def run(self, text, bold=False, italic=False, mono=False, size=None, color=None, under=False):
		pr = ""
		if mono:
			pr += '<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/>'
		if bold:
			pr += "<w:b/>"
		if italic:
			pr += "<w:i/>"
		if color:
			pr += '<w:color w:val="%s"/>' % color
		if under:
			pr += '<w:u w:val="single"/>'
		if size:
			pr += '<w:sz w:val="%d"/>' % int(size * 2)
		out = []
		for i, part in enumerate(text.split("\n")):
			if i:
				out.append("<w:r><w:br/></w:r>")
			out.append('<w:r><w:rPr>%s</w:rPr><w:t xml:space="preserve">%s</w:t></w:r>' % (pr, escape(part)))
		return "".join(out)

	def para(self, runs, style=None, shade=None, after=120, keep=False):
		ppr = ""
		if style:
			ppr += '<w:pStyle w:val="%s"/>' % style
		if keep:
			ppr += "<w:keepNext/>"
		if shade:
			ppr += '<w:shd w:val="clear" w:color="auto" w:fill="%s"/>' % shade
		ppr += '<w:spacing w:after="%d"/>' % after
		self.body.append("<w:p><w:pPr>%s</w:pPr>%s</w:p>" % (ppr, runs))

	def h(self, level, t):
		self.para(self.run(t), "Heading%d" % level)

	def text(self, t, **kw):
		self.para(self.run(t, **kw))

	def code(self, t):
		self.para(self.run(t, mono=True, size=8.5), shade="F2F2F2")

	def link(self, rel_path, label=None):
		"""Ссылка на файл проекта (кликабельная, file:///)."""
		# кириллица — как есть (Word читает %-кодировку как cp1252 и ломает путь), пробелы — %20, разделители — «\»
		abs_path = os.path.normpath(os.path.join(ROOT, rel_path))
		url = "file:///" + abs_path.replace(" ", "%20")
		rid = self.rel("http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink", url, True)
		return '<w:hyperlink r:id="%s" w:history="1">%s</w:hyperlink>' % (rid, self.run(label or rel_path, color="0563C1", under=True, size=9.5))

	def image(self, rel_path, height_cm=3.6):
		"""Картинка-образец внутри документа (уменьшенная PNG)."""
		p = os.path.join(ROOT, rel_path)
		im = Image.open(p).convert("RGBA")
		h = 360
		w = max(1, int(im.width * h / im.height))
		im = im.resize((w, h), Image.LANCZOS)
		bg = Image.new("RGBA", im.size, (40, 40, 48, 255))   # прозрачные фишки — на тёмном, как на карте
		bg.alpha_composite(im)
		buf = io.BytesIO()
		bg.convert("RGB").save(buf, "PNG", optimize=True)
		self.pic += 1
		name = "ref%d.png" % self.pic
		self.media.append((name, buf.getvalue()))
		rid = self.rel("http://schemas.openxmlformats.org/officeDocument/2006/relationships/image", "media/" + name)
		cy = int(height_cm * 360000)
		cx = int(cy * w / h)
		return ('<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="72000"><wp:extent cx="%d" cy="%d"/>'
			'<wp:docPr id="%d" name="Образец %d"/><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
			'<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
			'<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="%d" name="%s"/>'
			'<pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="%s"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
			'<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="%d" cy="%d"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
			'</pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>'
			% (cx, cy, self.pic, self.pic, self.pic, name, rid, cx, cy))

	def refs(self, title, paths, height_cm=3.6):
		"""Блок «Образцы»: картинки рядом и под ними ссылки на файлы."""
		self.para(self.run(title, bold=True, color="5B2A86"), after=40, keep=True)
		self.para("".join(self.image(p, height_cm) for p in paths), after=40, keep=True)
		for p in paths:
			self.para(self.run("• ") + self.link(p), after=20)
		self.para("", after=80)

	def save(self, path):
		doc = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
			'<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
			'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
			'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"><w:body>%s'
			'<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1000" w:right="1000" w:bottom="1000" w:left="1000" '
			'w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>') % "".join(self.body)
		rels = ['<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>']
		for rid, typ, target, ext in self.rels:
			rels.append('<Relationship Id="%s" Type="%s" Target="%s"%s/>' % (rid, typ, escape(target, {'"': "&quot;"}),
				' TargetMode="External"' if ext else ""))
		with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
			z.writestr("[Content_Types].xml", CT)
			z.writestr("_rels/.rels", RELS)
			z.writestr("word/_rels/document.xml.rels", '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
				'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">%s</Relationships>' % "".join(rels))
			z.writestr("word/document.xml", doc)
			z.writestr("word/styles.xml", STYLES)
			for name, data in self.media:
				z.writestr("word/media/" + name, data)


STYLES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:lang w:val="ru-RU"/></w:rPr></w:rPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="240"/></w:pPr><w:rPr><w:b/><w:sz w:val="40"/><w:color w:val="5B2A86"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:pageBreakBefore/><w:spacing w:before="120" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="32"/><w:color w:val="5B2A86"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="27"/><w:color w:val="333333"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="160" w:after="60"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:sz w:val="23"/><w:color w:val="555555"/></w:rPr></w:style>
</w:styles>"""

CT = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Default Extension="png" ContentType="image/png"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>"""

RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>"""


def build():
	d = Doc()
	d.para(d.run("SunLess — бродячие боссы: промты для ChatGPT"), "Title")
	d.text("ВАЖНО: фишка — только тело твари, без земли и подставки (землю даёт карта; у первого комплекта подставки срезаны скриптом tools/clean_wanderer_tokens.py). "
		"Четыре исполинские твари бродят по картам глав, встают в стороне от пути отряда и ждут там как особое событие "
		"с особой наградой (docs/22). Для каждой: фишка на карте в 4 ракурсах, карта противника, карта награды-Воспоминания. "
		"Образцы для ChatGPT — прямо здесь картинками, ссылки ведут к файлам проекта (щелчок по ссылке открывает файл).")

	d.h(2, "Как пользоваться")
	for t in [
		"1. Фишка — новый чат на каждого босса. Приложите к сообщению образцы из раздела «Образцы» (сами файлы — по ссылкам).",
		"2. Вставьте «Общий блок фишки», затем блок «Ракурс 1» босса — получите ракурс 1.",
		"3. Ракурсы 2–4 — в том же чате: блок ракурса (он просит взять прошлую картинку за основу и только повернуть тварь). "
			"Камера, размер, подставка и свет не меняются — в игре ракурсы сменяют друг друга через прозрачность.",
		"   Вариант надёжнее: сразу лист 2×2 со всеми ракурсами (блок «Лист ракурсов») — твари выйдут одинаковыми, я разрежу.",
		"4. Карты — отдельный чат: приложите ПУСТОЙ шаблон карты и его настройки (текст) из раздела «Шаблон карты», 1–2 "
			"готовые карты-образца, затем «Общий блок карты» и описание карты.",
		"5. Готовые файлы положите в папки ниже (или пришлите — я переведу в нужный формат и подключу).",
	]:
		d.text(t)

	d.h(2, "Как ракурсы работают в игре")
	d.text("Ракурс 1 — босс смотрит вниз-влево (на зрителя), 2 — вниз-вправо, 3 — вверх-вправо (спиной), 4 — вверх-влево "
		"(спиной). Когда босс уходит на новое место, фишка поворачивается по направлению пути и идёт туда; пока стоит — "
		"изредка оглядывается (переход на соседний ракурс через прозрачность ~0,8 с). Пока картинок нет — тёмный силуэт "
		"с горящими глазами.")

	d.h(2, "Настройки и куда класть файлы")
	d.code("ФИШКА: 4 PNG 1024×1024, прозрачный фон (или сплошной #FF00FF), тварь ~75% кадра, камера изометрия 35–40°, свет слева сверху.\n"
		"  art/map/wanderers/W1_1.png … W1_4.png (Багровый Отшельник), W2_… (Пепельный Змей), W3_… (Ловчий Теней), W4_… (Стеклянная Королева)\n"
		"  на карте — 110–160 px, левее места, над местом — ромб события.\n"
		"КАРТА: PNG 952×1632 (7:12) по пустому шаблону, название кириллицей в нижней плашке, без цифр и значков;\n"
		"  в игре — WebP 476×816 (качество 88): art/cards/MW1.webp … MW4 (противники), art/cards/LW1.webp … LW4 (награды).")

	d.h(2, "Шаблон карты (прикладывать к каждому промту карты)")
	d.text("Пустая обложка и её настройки — основа всех карт игры: рамка, разделитель и плашка остаются, рисуется только "
		"верхнее поле и название в плашке.")
	d.refs("Шаблон:", [TEMPLATE], 5.0)
	d.para(d.run("• Настройки шаблона (текст): ") + d.link(TEMPLATE_TXT), after=60)
	d.code(io.open(os.path.join(ROOT, TEMPLATE_TXT), encoding="utf-8").read().strip())
	d.para(d.run("• Образцы промтов по шаблону: ") + d.link("docs/assets/cards/concepts/enhancements-template-series-v2/prompts.md"), after=120)

	d.h(2, "Общие образцы фишек (стиль карты-плана)")
	d.refs("Фишки на карте и фигура героя — масштаб, камера, свет:", TOKEN_REFS, 3.2)

	d.h(2, "Общий блок фишки (вставлять первым)")
	d.code(TOKEN_COMMON)
	d.h(2, "Общий блок карты")
	d.code(CARD_COMMON.format(kind="{monster | enhancement}"))

	for x in BOSSES:
		d.h(1, "%s — %s" % (x["name"], x["where"]))
		d.text(x["ru"], italic=True)
		d.refs("Образцы места (материалы, свет, масштаб):", x["refs_map"], 3.2)

		d.h(2, "Фишка на карте — 4 ракурса")
		d.h(3, "Ракурс 1 — %s (%s_1.png)" % (ANGLES[0][0], x["id"]))
		d.code(x["subject"] + "\nANGLE 1 of 4: the creature " + ANGLES[0][1] + ".")
		for n in range(1, 4):
			d.h(3, "Ракурс %d — %s (%s_%d.png)" % (n + 1, ANGLES[n][0], x["id"], n + 1))
			d.code(TOKEN_NEXT.format(angle=ANGLES[n][1]))
		d.h(3, "Лист ракурсов 2×2 (вместо четырёх отдельных)")
		d.code(x["subject"] + "\n" + SHEET_TIP)

		d.h(2, "Карта противника (%s → art/cards/%s.webp)" % (x["enemy"], x["enemy"]))
		d.refs("Приложить: шаблон и образцы готовых карт монстров:", [TEMPLATE] + x["refs_card"], 4.2)
		d.code(CARD_COMMON.format(kind="monster") + "\n%s “%s”: %s Exact lower title “%s” on ONE line."
			% (x["enemy"], x["enemy_title"], x["enemy_card"], x["enemy_title"]))

		d.h(2, "Карта награды — Воспоминание (%s → art/cards/%s.webp)" % (x["reward"], x["reward"]))
		d.refs("Приложить: шаблон и образцы готовых карт Воспоминаний:", [TEMPLATE] + x["refs_reward"], 4.2)
		d.code(CARD_COMMON.format(kind="enhancement") + "\n%s “%s”: %s Exact lower title “%s” on %s."
			% (x["reward"], x["reward_title"], x["reward_card"], x["reward_title"], x["reward_lines"]))
	d.save(OUT)
	print("готово:", OUT, "· картинок-образцов:", d.pic, "· ссылок:", sum(1 for r in d.rels if r[3]))


if __name__ == "__main__":
	missing = [p for p in [TEMPLATE, TEMPLATE_TXT] + TOKEN_REFS + sum([x["refs_map"] + x["refs_card"] + x["refs_reward"] for x in BOSSES], [])
		if not os.path.exists(os.path.join(ROOT, p))]
	assert not missing, missing
	build()
