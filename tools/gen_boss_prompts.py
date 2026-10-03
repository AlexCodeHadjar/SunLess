"""Промты ChatGPT для бродячих боссов (docs/22) → Word-файл docs/Бродячие боссы — промты ChatGPT.docx.

Фишки на карте (4 кадра на босса: анимация в игре — кадры сменяются через прозрачность), карта противника и карта
награды. Word собирается без сторонних библиотек (WordprocessingML в zip).
    python tools/gen_boss_prompts.py
"""
import io
import os
import zipfile
from xml.sax.saxutils import escape

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "Бродячие боссы — промты ChatGPT.docx")

COMMON = """Use case: animated map token for SunLess, a dark-fantasy card game. The token stands on a painted isometric
map of small diorama-like locations, seen from above at about 35–40 degrees. Match the attached reference image
(a crimson crab on a small patch of dark wet sand with coral) in style, camera, scale and lighting.
SUBJECT: one giant creature (described below) standing on a small irregular patch of its own ground — the patch is
part of the token, like a tabletop miniature base (rocks, sand, ash, coral, rubble — stated below).
VIEW: three-quarter top-down view, camera 35–40° above the horizon, the creature faces lower-left, the whole creature
and its ground patch visible and centered; the token fills about 75% of the frame.
LIGHT: soft key light from the upper left, cool ambient fill, gentle contact shadows inside the ground patch;
one accent glow (stated below) — subtle, readable at 120 px.
STYLE: painterly realistic dark fantasy, detailed but readable silhouette at 120–160 px, rich materials
(wet chitin, barnacles, ash, glass, cloth), muted palette with one accent colour, no outlines, no cartoon.
OUTPUT: 1024×1024 PNG, TRANSPARENT background (no sky, no horizon, no frame, no vignette); if transparency is not
possible — flat solid #FF00FF background. No text, no letters, no logos, no UI, no other creatures."""

FRAME_RULE = """ANIMATION FRAME RULE: this is frame {n} of a 4-frame idle loop. Keep EVERYTHING identical to frame 1 — same
camera, same scale, same position in the frame, same ground patch, same lighting and colours — change ONLY: {change}.
The frames will be cross-faded in the game, so even small shifts of the camera or the ground patch will look wrong."""

CARD = """Use case: card illustration for SunLess (dark-fantasy card game). Vertical 2:3 (1024×1536), full-bleed painting,
no frame, no text. Painterly realistic dark fantasy, dramatic but readable: the subject large and centred in the
upper two thirds (the bottom third will be covered by the card name plate). Palette: deep shadows, one accent colour."""

BOSSES = [
	{
		"id": "W1", "enemy": "MW1", "reward": "LW1", "name": "Багровый Отшельник", "where": "Забытый Берег",
		"ru": "Исполинский краб-отшельник. Раковина — обломки кораллов, кости и ракушки, наросшие за века; клешни "
			"в шипах и ракушках; цвет — тёмно-багровый, мокрый блеск. Бродит по отмелям и коралловым полям. Акцент — "
			"тусклое красное свечение в глубине раковины. Это тот самый образец-краб, только крупнее и древнее.",
		"subject": "CREATURE: a colossal ancient crimson hermit crab (like the reference crab, but older and bigger): a towering "
			"spiral shell made of broken red coral, bleached bones and clusters of barnacles; heavy spiked claws crusted with "
			"barnacles; wet glossy dark-crimson chitin; small stalked eyes. GROUND: a patch of dark wet sand with black pebbles, "
			"tide pools and red coral sprigs. ACCENT GLOW: a dim ember-red glow deep inside the shell opening.",
		"frames": ["the creature at rest: claws lowered and folded in front, legs planted",
			"slow breath: the shell lifted very slightly (2–3%), the front claw raised a little, the ember glow a bit brighter",
			"threat: both claws raised and opened toward the viewer, eyes extended, ember glow at its brightest",
			"shift: claws half-lowered, two right legs stepped a little to the side, glow back to dim"],
		"enemy_card": "Card subject: the Crimson Hermit — a colossal ancient hermit crab rising from a tide pool at night, shell of "
			"broken red coral and bones, barnacle-crusted claws raised, ember-red glow inside the shell, black sea and spray "
			"behind, survivors as tiny silhouettes in the foreground for scale. Accent colour: crimson.",
		"reward_card": "Card subject (a Memory item): a fragment of the Crimson Hermit's shell lying on black sand — a curved plate "
			"of red coral and bone with barnacles, faintly warm-glowing from inside like a living thing, soft mist. "
			"Accent colour: ember red. Mood: protective, ancient.",
	},
	{
		"id": "W2", "enemy": "MW2", "reward": "LW2", "name": "Пепельный Змей", "where": "Древо Души (Пепельное море)",
		"ru": "Змей длиной с караван, плывущий в пепельных дюнах. Чешуя — угольные пластины с тлеющими краями; голова "
			"тяжёлая, костяная; тело уходит в пепел кольцами. Акцент — оранжевое тление в швах чешуи и в глазах.",
		"subject": "CREATURE: a colossal serpent emerging from ash dunes: only the head and two coils of its body rise above a "
			"patch of grey ash, the rest disappears under it; armour of charcoal-black scales with smouldering orange edges, a heavy "
			"bony horned head, ash pouring off it like water. GROUND: a patch of grey ash dune with half-buried bones and small "
			"smoking cracks. ACCENT GLOW: smouldering orange light in the seams between scales and in the eyes.",
		"frames": ["the serpent at rest: head low above the ash, coils still",
			"rising: the head lifted a little higher, a small spill of ash from the coils, seams glowing brighter",
			"threat: jaws open toward the viewer, head reared, embers flying from the seams",
			"diving: the head turned slightly away and lower, one coil sinking deeper into the ash, glow dim"],
		"enemy_card": "Card subject: the Ash Serpent bursting from a grey ash dune under a dark sky, charcoal scales with smouldering "
			"edges, ash pouring off its horned skull, embers in the air. Accent colour: smouldering orange.",
		"reward_card": "Card subject (a Memory item): a single charcoal scale of the Ash Serpent on a bed of grey ash, its edge still "
			"smouldering orange, a thin curl of smoke. Accent colour: ember orange. Mood: hidden danger.",
	},
	{
		"id": "W3", "enemy": "MW3", "reward": "LW3", "name": "Ловчий Теней", "where": "Мрачный город",
		"ru": "Высокий худой ловчий в рваном плаще, лицо скрыто капюшоном и костяной маской; на поясе — фонарь-клетка, в "
			"котором бьются пленные тени; на плече — свёрнутая сеть. Ходит по крышам и пустым улицам. Акцент — холодный "
			"бледно-голубой свет фонаря.",
		"subject": "CREATURE: a very tall, gaunt hunter (about three times human height) in a long tattered black cloak, the face hidden "
			"by a hood and a cracked bone mask; long thin arms; a cage-lantern hangs from the belt with writhing shadow shapes "
			"trapped inside; a coiled net over one shoulder. GROUND: a patch of broken cobblestones with a fallen roof tile and a "
			"rusted gate fragment. ACCENT GLOW: cold pale-blue light from the cage-lantern.",
		"frames": ["standing still, head slightly bowed, lantern hanging",
			"listening: the head turned a little to the side, the lantern swaying slightly, shadows inside the cage moving",
			"threat: the lantern raised toward the viewer, the net held ready in the other hand, the light at its brightest",
			"stepping: one foot moved forward, cloak hem drifting, lantern lower again"],
		"enemy_card": "Card subject: the Shadow Catcher on a ruined rooftop at night, gaunt and tall, tattered cloak, bone mask, raising a "
			"cage-lantern full of trapped writhing shadows, pale-blue light on wet stone. Accent colour: cold pale blue.",
		"reward_card": "Card subject (a Memory item): an old iron cage-lantern standing on cobblestones, empty but still glowing pale "
			"blue inside, faint shadow wisps escaping between the bars. Accent colour: pale blue. Mood: light against darkness.",
	},
	{
		"id": "W4", "enemy": "MW4", "reward": "LW4", "name": "Стеклянная Королева", "where": "Город людей",
		"ru": "Тварь из Врат: длинное многоногое тело в панцире из битого стекла, витрин и автомобильных фар; голова — венец "
			"из острых осколков; за ней ползёт рой мелких стеклянных существ. Бродит по пустым кварталам. Акцент — "
			"холодный бирюзовый отблеск в стекле.",
		"subject": "CREATURE: a monstrous insect-like queen as long as a bus: a segmented many-legged body armoured with shards of "
			"broken glass, shop-window panes and cracked car headlights; a crown of sharp glass spikes on its head; a few tiny "
			"glass crawlers around its legs. GROUND: a patch of cracked asphalt with a broken kerb, scattered glass and a bent "
			"street-lamp base. ACCENT GLOW: cold teal reflections inside the glass armour.",
		"frames": ["at rest: body curled slightly, legs planted, crawlers still",
			"breathing: the glass plates on the back lifted a little, teal glints moving across the armour",
			"threat: the front of the body reared up toward the viewer, glass crown flared, crawlers scattering",
			"settling: body lowered again, two legs shifted, glints fading"],
		"enemy_card": "Card subject: the Glass Queen in an abandoned city street at night, armoured in shattered shop windows and car "
			"headlights, glass crown flared, a glittering swarm of tiny glass crawlers around her, streetlights broken. "
			"Accent colour: cold teal.",
		"reward_card": "Card subject (a Memory item): a long sharp shard of the Glass Queen's armour on cracked asphalt, its edge catching "
			"a cold teal light, tiny reflections of a city inside it. Accent colour: teal. Mood: sharp, ringing.",
	},
]


# --- Word (WordprocessingML) -------------------------------------------------------------------------------------------

def run(text, bold=False, italic=False, mono=False, size=None, color=None):
	pr = ""
	if mono:
		pr += '<w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/>'
	if bold:
		pr += "<w:b/>"
	if italic:
		pr += "<w:i/>"
	if color:
		pr += '<w:color w:val="%s"/>' % color
	if size:
		pr += '<w:sz w:val="%d"/>' % (size * 2)
	out = []
	for i, part in enumerate(text.split("\n")):
		if i:
			out.append("<w:r><w:br/></w:r>")
		out.append('<w:r><w:rPr>%s</w:rPr><w:t xml:space="preserve">%s</w:t></w:r>' % (pr, escape(part)))
	return "".join(out)


def para(runs, style=None, shade=None, space_after=120):
	ppr = ""
	if style:
		ppr += '<w:pStyle w:val="%s"/>' % style
	if shade:
		ppr += '<w:shd w:val="clear" w:color="auto" w:fill="%s"/>' % shade
	ppr += '<w:spacing w:after="%d"/>' % space_after
	return "<w:p><w:pPr>%s</w:pPr>%s</w:p>" % (ppr, runs)


def h1(t):
	return para(run(t), "Heading1")


def h2(t):
	return para(run(t), "Heading2")


def h3(t):
	return para(run(t), "Heading3")


def text(t, **kw):
	return para(run(t, **kw))


def code(t):
	return para(run(t, mono=True, size=9), shade="F2F2F2")


STYLES = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/><w:sz w:val="22"/><w:lang w:val="ru-RU"/></w:rPr></w:rPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>
<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="240"/></w:pPr><w:rPr><w:b/><w:sz w:val="40"/><w:color w:val="5B2A86"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="360" w:after="120"/><w:outlineLvl w:val="0"/></w:pPr><w:rPr><w:b/><w:sz w:val="32"/><w:color w:val="5B2A86"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/><w:outlineLvl w:val="1"/></w:pPr><w:rPr><w:b/><w:sz w:val="26"/><w:color w:val="333333"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="160" w:after="60"/><w:outlineLvl w:val="2"/></w:pPr><w:rPr><w:b/><w:sz w:val="23"/><w:color w:val="555555"/></w:rPr></w:style>
</w:styles>"""

CT = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>"""

RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>"""

DOC_RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>"""


def body():
	b = [para(run("SunLess — бродячие боссы: промты для ChatGPT"), "Title"),
		text("Четыре исполинские твари бродят по картам глав, встают в стороне от пути отряда и ждут там как особое событие "
			"с особой наградой (docs/22). Для каждой нужны: фишка на карте — 4 кадра (анимация в игре — кадры плавно "
			"сменяют друг друга через прозрачность), карта противника и карта награды-Воспоминания.")]
	b.append(h1("Как пользоваться"))
	for t in [
		"1. Новый чат ChatGPT для каждого босса. Приложите образец стиля — картинку краба на камне.",
		"2. Вставьте «Общий блок», затем «Кадр 1» босса. Получите кадр 1.",
		"3. Кадры 2–4 — в том же чате: «Возьми предыдущую картинку за основу» + блок кадра. Кадры должны совпадать во "
			"всём, кроме позы и свечения: в игре они плавно перетекают друг в друга (держится ~1,5 с, переход ~0,8 с).",
		"4. Карты противника и награды — в отдельном чате: блок «Карта» + описание карты.",
		"5. Размер фишки — 1024×1024, прозрачный фон (если не выходит — сплошной #FF00FF, я вырежу). Карты — 1024×1536.",
		"6. Пока картинок нет, игра рисует тёмный силуэт с горящими глазами — всё уже работает.",
	]:
		b.append(text(t))
	b.append(h2("Куда класть файлы"))
	rows = []
	for x in BOSSES:
		rows.append("%s — фишка: art/map/wanderers/%s_1.png … %s_4.png; карта противника: art/cards/%s.png; награда: art/cards/%s.png"
			% (x["name"], x["id"], x["id"], x["enemy"], x["reward"]))
	b.append(code("\n".join(rows)))
	b.append(h1("Общий блок фишки (вставлять первым)"))
	b.append(code(COMMON))
	b.append(h1("Общий блок карты"))
	b.append(code(CARD))
	for x in BOSSES:
		b.append(h1("%s — %s" % (x["name"], x["where"])))
		b.append(text(x["ru"], italic=True))
		b.append(h2("Фишка на карте — 4 кадра"))
		for n, change in enumerate(x["frames"], 1):
			b.append(h3("Кадр %d (%s_%d.png)" % (n, x["id"], n)))
			if n == 1:
				b.append(code(x["subject"] + "\nFRAME 1 of a 4-frame idle loop: " + change + "."))
			else:
				b.append(code("Take the previous image as the base.\n" + FRAME_RULE.format(n=n, change=change)))
		b.append(h2("Карта противника (%s.png)" % x["enemy"]))
		b.append(code(x["enemy_card"]))
		b.append(h2("Карта награды — Воспоминание (%s.png)" % x["reward"]))
		b.append(code(x["reward_card"]))
	return "".join(b)


def main():
	doc = ('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
		'<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>%s'
		'<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134" '
		'w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>') % body()
	with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
		z.writestr("[Content_Types].xml", CT)
		z.writestr("_rels/.rels", RELS)
		z.writestr("word/_rels/document.xml.rels", DOC_RELS)
		z.writestr("word/document.xml", doc)
		z.writestr("word/styles.xml", STYLES)
	print("готово:", OUT)


if __name__ == "__main__":
	main()
