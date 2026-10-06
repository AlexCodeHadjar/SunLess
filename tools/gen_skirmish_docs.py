"""Пошаговый бой «Схватка» (docs/24): Word-документы для владельца.

1) ТЗ — из Markdown docs/24 → «docs/ТЗ — Пошаговый бой «Схватка».docx» (Markdown — главный текст, Word собирается из него);
   английская версия — из «docs/24 — Turn-based combat Skirmish (EN).md» → «docs/Design spec — Turn-based combat Skirmish (EN).docx».
2) Промты артов для ChatGPT → «docs/Пошаговый бой — промты ChatGPT.docx»: фигуры героев (позы-кадры), Эхо, врагов,
   трупы, фоны боя по полям регионов, рамки интерфейса, значки состояний и света, иконки своих навыков, карты событий
   поля (по шаблону карты), эффекты ударов. К каждому промту — образцы из проекта картинками и ссылками на файлы
   (правило владельца 03.10: к картам — шаблон docs/assets/cards/templates и образцы готовых карт).
    python tools/gen_skirmish_docs.py
"""
import io
import json
import os

from docx_lib import ROOT, Doc, md_to_doc

TZ_MD = "docs/24 — Пошаговый бой «Схватка».md"
TZ_OUT = "docs/ТЗ — Пошаговый бой «Схватка».docx"
TZ_MD_EN = "docs/24 — Turn-based combat Skirmish (EN).md"
TZ_OUT_EN = "docs/Design spec — Turn-based combat Skirmish (EN).docx"
PR_OUT = "docs/Пошаговый бой — промты ChatGPT.docx"
TEMPLATE = "docs/assets/cards/templates/SunLess-blank-card-front-7x12.png"
TEMPLATE_TXT = "docs/assets/cards/templates/SunLess-blank-card-prompt.txt"
MOCKUP = "docs/assets/art/combat/mockup_skirmish.png"
COLLAGE = "docs/SunLess — Коллаж интерфейса.png"
SRC = "docs/assets/art/combat"     # куда класть готовые картинки (исходники; в игру — tools/import_combat_art.py, фаза 7)


def load(p):
	return json.load(io.open(os.path.join(ROOT, p), encoding="utf-8"))


def art(cid):
	"""Карта-образец: art/cards/<id>.webp|png (если есть)."""
	for ext in ("webp", "png"):
		p = "art/cards/%s.%s" % (cid, ext)
		if os.path.exists(os.path.join(ROOT, p)):
			return p
	return None


# --- общие блоки промтов --------------------------------------------------------------------------------------------

FIGURE_COMMON = """Use case: full-body COMBAT FIGURE for SunLess, a dark-fantasy turn-based card game with side-view battles: heroes
stand on the left and face RIGHT, enemies stand on the right and face LEFT (like a theatre stage seen from the audience).
IDENTITY: the character must be exactly the one on the attached reference card art — same face, hair, body, clothes,
armour, weapon, colours and materials. Do not redesign it.
SUBJECT: ONLY the figure, full body from head to feet (nothing cut off). NO ground, NO floor, NO base, NO platform,
NO cast shadow, NO scenery — cut out cleanly on a fully transparent background.
VIEW: side view turned about 20° toward the viewer (we see the face and the chest a little), camera at chest height,
no top-down tilt. FACING: {facing}.
SCALE AND FRAMING: the feet stand on an invisible baseline at 94% of the frame height, the figure is centred; a
normal human is about 78% of the frame height (space above the head for raised weapons and effects); exactly the
same scale and baseline in every pose of this character.
LIGHT: key light from the upper-left of the image, cool ambient fill, low exposure without blown highlights; one
accent glow only where stated.
STYLE: the same as the attached SunLess card art — dark antique engraved painterly realism, fine etching-like detail,
restrained cool silver-grey palette with one muted accent colour, tactile materials, strong readable silhouette at
300–400 px height. No cartoon, no anime, no glossy fantasy, no thick outlines.
OUTPUT: {size} PNG, transparent background; if transparency is impossible — flat solid #FF00FF background, still with
no ground and no shadow. No text, letters, numbers, UI, frames, no second character."""

POSE_NEXT = """Use the previous image as the exact reference: the same character (face, hair, body, clothes, armour, weapon,
colours, wounds), the same scale, the same baseline at 94% of the height, the same facing ({facing}), the same light,
still on a transparent background with NO ground and NO shadow. Change ONLY the pose: {pose}"""

SHEET_TIP = """Alternative (better consistency): all poses at once as a pose sheet — a grid of {grid} cells, each cell {cell} on
a transparent background, same character, same scale, same baseline in every cell, facing {facing}. Order of cells
(left to right, top to bottom): {order}. No grid lines, no labels, nothing between the cells."""

HERO_SIZE = "1024×1536 (2:3)"
BIG_SIZE = "2048×1536 (4:3) — the creature is wide: it takes TWO positions in the battle line"

HERO_POSES = [   # (файл, название, промт позы)
	("idle", "Стойка", "combat-ready stance, weight on the back foot, weapon ready, calm and alert (the game adds a slow breathing motion)."),
	("strike", "Удар оружием", "mid-attack with the main weapon toward the RIGHT: lunging or swinging forward, body leaning in, the weapon at the end of the motion."),
	("skill1", "Свой навык 1", None),
	("skill2", "Свой навык 2", None),
	("cast", "Карта / Воспоминание", "using a Memory: one hand raised forward, a faint pale soul-light gathering in the palm, focused face (no specific object — the game draws the card's effect)."),
	("defend", "Защита", "braced to block: half-turned, weapon or forearm raised before the chest, feet wide."),
	("hit", "Получил удар", "recoiling from a hit coming from the RIGHT: thrown back to the left, head turned away, off balance, pain."),
	("edge", "На грани смерти", "on the verge of death: down on one knee, bloodied and exhausted, barely holding the weapon, head low but still facing the enemy."),
	("panic", "Паника", "psyche broken: cowering, clutching the head with one hand, wide haunted eyes, the weapon held loosely."),
	("uplift", "Подъём духа", "spirit rising: upright and determined, chin up, weapon raised, a faint warm light on the face."),
]
P1_POSES = ["idle", "strike", "hit", "edge"]   # для прототипа

HEROES = [   # (id, имя, лицом, свои навыки: [(название, промт позы)], образцы)
	("P01", "Санни", [
		("Удар из тени", "striking from the shadows: a fast low thrust with the weapon toward the RIGHT, black shadow wisps trailing behind his body as if he just stepped out of darkness."),
		("Раствориться в тени", "dissolving into shadow: stepping back to the LEFT, the back half of his body turning into black smoke-like shadow, eyes still on the enemy."),
	], ["art/map/figure/sunny.webp"]),
	("P02", "Нефис", [
		("Удар Меняющейся Звезды", "a wide sword swing toward the RIGHT, the blade trailing a ribbon of WHITE flame (accent: white-gold flame light)."),
		("Вызов", "a challenge: the sword pointed straight at the enemy on the RIGHT, chin up, white flame flickering along the blade."),
	], ["art/map/figure/nephis.webp"]),
	("P03", "Касси", [
		("Пророчество", "prophecy: one hand raised toward the RIGHT, eyes glowing faint cold blue-white, thin threads of pale light spreading from her fingers."),
		("Голос во тьме", "a voice in the dark: turned slightly to the LEFT (toward her allies), one hand on the heart, speaking, soft light around her lips."),
	], ["art/map/figure/cassie.webp"]),
	("P04", "Кастер", [
		("Молниеносный выпад", "a lightning-fast lunge toward the RIGHT, fully extended, a faint motion blur behind him."),
		("Первая кровь", "a quick precise slash toward the RIGHT, a thin arc of blood in the air at the end of the blade."),
	], []),
	("P08", "Ауро", [
		("Удар Девяти", "a heavy overhead strike, the sword coming down toward the RIGHT with full body weight."),
		("Стальная стена", "a guarding stance: planted feet, the blade held across the body, shielding someone behind him (to the LEFT)."),
	], []),
	("P09", "Шолар", [
		("Найти слабину", "studying the enemy on the RIGHT: leaning forward, one hand pointing, eyes narrowed, a notebook in the other hand."),
		("Выследить", "tracking: crouched low, touching the ground with two fingers, head turned to the RIGHT."),
	], []),
	("P10", "Шифти", [
		("Грязный приём", "a dirty trick: throwing a handful of sand toward the RIGHT while stepping back to the LEFT, a knife in the other hand."),
		("Ложная тревога", "false alarm: shouting and pointing past the enemy, a sly grin, half-ready to run."),
	], []),
]

ECHOES = [   # (карта, имя, существо, образцы, позы)
	("U12", "Эхо Падальщика Карапакса", "M03", [
		("idle", "Стойка", "standing ready in profile, claws raised."),
		("attack", "Клешни", "snapping both claws forward toward the RIGHT."),
		("guard", "Панцирный заслон", "turned sideways with the shell toward the RIGHT, shielding the hero behind it (to the LEFT)."),
		("hit", "Получил удар", "knocked back to the LEFT, legs scrabbling."),
	]),
	("L16", "Эхо Центуриона", "M04", [
		("idle", "Стойка", "standing ready, disciplined, weapon limbs raised."),
		("attack", "Серповидный выпад", "a sickle-like strike toward the RIGHT."),
		("guard", "Строй Легиона", "a defensive formation stance, guarding to the LEFT side."),
		("hit", "Получил удар", "knocked back to the LEFT."),
	]),
]
ECHO_LOOK = ("It is an ECHO — the soul-shadow of this slain creature serving the hero: the same creature, but its edges are "
	"slightly translucent and pale soul-light (cold blue) glows through the cracks of its body and eyes. It FACES RIGHT "
	"(it fights on the hero's side).")

# враги: id → (описание для художника, крупный, особые позы для элиты и боссов)
ENEMIES = {
	"M01": ("a pale, soft, segmented larva of the Mountain King, as large as a big dog, rows of thorny spines along its back, a round maw of tiny teeth, glistening mucus; low and crawling, head toward the LEFT", False, []),
	"M02": ("the Mountain King: a hulking ancient giant beast in matted fur, many eyes across its head, enormous claws; towering and hunched, head and claws toward the LEFT", True,
		[("special", "Сокрушить", "slamming both huge claws down toward the LEFT, shockwave of snow and stone dust."), ("special2", "Взгляд многих глаз", "all its eyes wide open and glaring, head thrust forward to the LEFT."), ("phase2", "Ярость", "wounded and enraged, fur bristling, roaring toward the LEFT.")]),
	"M03": ("a giant scavenger crab with a spiked, barnacled carapace overgrown with crimson coral and huge serrated claws; in profile, claws toward the LEFT", False, []),
	"M04": ("the Carapace Centurion: a tall armoured carapace warrior with segmented chitin plates and blade-like limbs, a disciplined upright stance", False,
		[("special", "Метнуть", "throwing a spine-javelin toward the LEFT from the back line.")]),
	"M05": ("the Carapace Demon: a massive intelligent carapace creature, commander of the swarm, regenerating chitin and a crown-like crest; heavy and menacing", True,
		[("special", "Приказ", "commanding: raising its crest and fore-limbs, a deep call (other creatures obey).")]),
	"M06": ("a giant red centipede with many legs, acid dripping from its mandibles; body coiled low, head raised toward the LEFT", False, []),
	"M07": ("carnivorous worms bursting up from below: two or three fleshy worms rising from an invisible ground line (cut flat at the bottom), round toothed mouths toward the LEFT", False, []),
	"M08": ("carnivorous blood-red flowers with grasping thorny vines and petal-mouths, rooted (roots cut flat at the bottom), reaching to the LEFT", False, []),
	"M09": ("translucent glassy tentacles of an unseen creature rising from below (cut flat at the bottom), faintly luminous inside, curling toward the LEFT", False, []),
	"M10": ("the Soul Tree: an ancient enchanting tree with pale glowing blossoms and hypnotic soft light, roots cut flat at the bottom", True, []),
	"M11": ("the spawn of the Foul Bird: a monstrous ancient hatchling with shards of eggshell still on it, a soul-devouring maw, wet feathers and bone", False,
		[("special", "Пожирание душ", "maw wide open, pulling pale soul-light toward itself from the LEFT.")]),
	"M12": ("a deep-sea tentacled dweller: a bulbous creature from the deep with many tentacles and pale eyes", False, []),
	"M15": ("the Blood Fiend: a gaunt, raging humanoid fiend with long claws and blood-stained skin", False, []),
	"M17": ("the Stone Saint: a living statue of a knight in grey stone armour with a stone sword and shield, cracked surface, a duelist's stance", False, []),
	"M18": ("an iron spider of a brood: a dog-sized spider with iron-plated legs and body, metallic sheen", False, []),
	"M19": ("a porcupine-like monster covered in bone quills it can throw, with armoured hide", False, []),
	"M20": ("a basilisk: a scaled serpent-lizard with a petrifying gaze, eyes glowing", False, []),
	"M21": ("a termite colony: a cluster of soldier termites with big mandibles crawling over a fragment of their mound (cut flat at the bottom)", False,
		[("special", "Рой", "the whole cluster surging forward to the LEFT.")]),
	"M23": ("the Rolling Stone: a living boulder, a huge rounded rock with a crack-like maw", True, []),
	"M24": ("the Spire Messenger: a winged predator with long talons, hovering above the ground", False, []),
	"M25": ("the Black Knight: a tall knight in dark steel armour with a long sword, a duelist's stance", False,
		[("special", "Выпад", "a long precise lunge toward the LEFT.")]),
	"M26": ("the Lord of the Dead: a skeletal undead lord in tattered regal robes with a staff of bone", False,
		[("special", "Призыв", "raising the bone staff, dead hands reaching up around him."), ("special2", "Шёпот", "leaning forward, whispering, dark smoke flowing from his mouth to the LEFT."), ("phase2", "Ярость мёртвых", "robes torn, bones cracked, burning with cold fury.")]),
	"M27": ("a skeleton warrior with a rusty blade and a broken shield", False, []),
	"M28": ("the Corpse Eater: a gaunt hound-like ghoul beast with long fangs, blood-stained", False, []),
	"M29": ("the Iron Spider Matriarch: a large iron spider with web sacs and heavy plated legs", False, []),
	"M32": ("a giant locust with tattered wings, hovering", False, []),
	"M33": ("the Flesh Devourer: a lean hungry pack beast with a wide fanged mouth", False, []),
	"M34": ("the Blood Flower: a parasitic blood-red flower puppeteering a withered human husk", False, []),
	"M35": ("the Cursed Messenger: a winged elite creature wrapped in cursed dark energy, long talons", False,
		[("special", "Пикирование", "diving down toward the LEFT, wings folded.")]),
	"M36": ("a coral golem of the Seven: a humanoid construct of crimson coral and stone", False, []),
	"M37": ("the Crimson Terror: an ancient colossal horror of crimson coral emitting an eerie inner light", True,
		[("special", "Ментальное давление", "its inner light pulsing in waves toward the LEFT."), ("special2", "Порча", "coral spines erupting, red haze around it."), ("phase2", "Пробуждение", "cracked open, blazing from inside.")]),
	"M38": ("the siege horde: a small swarm of flying parasitic creatures — several of them in one figure", False, []),
	"H_GOLEM": ("the Academy training golem: a humanoid construct of grey stone blocks with a simple stone shield", False, []),
	"MW1": ("the Crimson Hermit: a giant hermit crab in a shell of crimson coral and bone, barnacles, huge claws", True,
		[("special", "Уйти в раковину", "withdrawn into its shell, claws guarding the opening."), ("special2", "Клешни", "both claws snapping forward to the LEFT."), ("phase2", "Раковина треснула", "shell cracked, enraged.")]),
	"MW2": ("the Ash Serpent: a gigantic serpent of ash-grey scales glowing with embers between them, erupting from below (cut flat at the bottom)", True,
		[("special", "Удар из-под земли", "bursting up toward the LEFT, jaws wide."), ("special2", "Жар", "breathing a wave of hot ash to the LEFT."), ("phase2", "Пепельная ярость", "embers blazing through cracked scales.")]),
	"MW3": ("the Shadow Hunter: a tall hooded hunter of the dark city with a cage-lantern and nets, a hunter's stance", False,
		[("special", "Сеть", "throwing a net toward the LEFT."), ("special2", "Удар из мрака", "striking out of darkness, half of the body still in shadow."), ("phase2", "Охота началась", "lantern blazing, cloak torn.")]),
	"MW4": ("the Glass Queen: a gigantic insect queen of glass and crystal, translucent plates, a venomous sting", True,
		[("special", "Рой", "glass shards and small crystal insects bursting around her."), ("special2", "Звон стекла", "her body ringing, cracks of light running across it."), ("phase2", "Треснувшая королева", "shattered plates, blazing light inside.")]),
}
REUSE = {   # не рисуем отдельно
	"M16": "как M17 (Каменная Святая — тот же облик)",
	"M30": "как M29 (Железные пауки / Матриарх)",
	"M31": "как M29 (Железные пауки / Матриарх)",
	"H_AURO": "фигура героя Ауро (P08), отражённая — смотрит влево",
	"H_CASTER": "фигура героя Кастера (P04), отражённая",
	"H_NEPHIS": "фигура героини Нефис (P02), отражённая",
	"MT1": "Отражение: фигура героя испытания, перекрашенная в игре (тёмное стекло, пустые глаза)",
	"MT2": "Отражение: как MT1",
}
ENEMY_POSES = {
	"normal": [("idle", "Стойка", "standing ready, facing LEFT."), ("attack", "Атака", "attacking toward the LEFT with its main weapon (claws, fangs, sting, blade…)."),
		("hit", "Получил удар", "recoiling from a hit coming from the LEFT: thrown back to the RIGHT.")],
}
ENEMY_POSES["elite"] = ENEMY_POSES["normal"][:2] + [None] + ENEMY_POSES["normal"][2:]
ENEMY_POSES["boss"] = ENEMY_POSES["normal"][:2] + [None, None] + ENEMY_POSES["normal"][2:] + [None]

CORPSES = [
	("carapace", "Панцирные и насекомые", "broken remains of a giant carapace creature: cracked shell plates, curled legs, a severed claw, pale ichor."),
	("beast", "Звери", "remains of a beast: a fur-covered carcass lying on its side, bones showing, dark blood soaked into nothing (no ground)."),
	("bones", "Люди и нежить", "a heap of bones, a cracked skull, rusted armour pieces and a broken blade."),
	("plant", "Растения и щупальца", "withered, blackened vines and limp tentacles, dried petals."),
	("stone", "Камень и конструкты", "a pile of broken carved stone and coral blocks, a cracked stone face among them."),
]
CORPSE_COMMON = """Use case: CORPSE sprite for SunLess side-view battles: what is left on a battle position after a creature dies.
SUBJECT: {subject} Lying flat on an invisible ground line at 90% of the frame height, seen from the side at chest
height. NO ground, NO puddle, NO shadow — transparent background. Style: the attached SunLess card art (dark engraved
painterly realism, muted cool palette). Readable at 200 px wide. OUTPUT: 1024×512 PNG, transparent."""

BG_COMMON = """Use case: side-view BATTLE BACKGROUND for SunLess, a dark-fantasy turn-based card game. The game draws the
fighters ON TOP of this picture: heroes on the left half facing right, enemies on the right half facing left, all
standing on one line. So the picture is a STAGE:
- a wide panorama of the place, camera at human eye level, looking straight at a flat strip of ground that runs
  across the whole width;
- the walkable strip is between 70% and 95% of the image height: flat and readable, without big objects, holes
  or steps (small stones, puddles, ash, sand, cracks are fine);
- the middle of the picture is calmer and a bit darker (characters stand there); big framing shapes (pillars,
  coral, rocks, broken walls) only near the far left and far right edges;
- nothing important in the top 15% (the game puts the round info there);
- NO people, creatures, corpses, text or UI.
LIGHT: neutral soft daylight from the upper-left, low contrast, moderate exposure — the game re-colours the picture
for dusk, night, storm, eclipse and blood moon, so do NOT paint night or strong coloured light.
STYLE: like the attached SunLess region pictures and card art: painterly realism with fine engraved detail, muted
cool palette with the one accent colour of this place, atmospheric depth (haze in the distance).
OUTPUT: 2560×1080 (21:9) PNG."""

BGS = [   # (регион, глава, [(поле, название, описание)], образцы)
	("mountain_pass", "Первый Кошмар — горный перевал", [
		("F04", "Горный путь", "a narrow snowy mountain path along a cliff, ancient carved stones half buried in snow, wind-blown snow in the air, grey peaks far away"),
		("F05", "Павший караван", "a wrecked slave caravan on a mountain road: broken wooden carts, dropped chains and crates half covered with snow (no bodies)"),
		("F03", "Обрыв", "a stone ledge above a misty abyss, broken ancient stairs, the far side of the gorge in haze"),
	], ["art/regions/mountain_pass_day.webp", "art/regions/mountain_pass_night.webp", "art/cards/M02.png"]),
	("academy", "Академия", [
		("F02", "Тренировочное поле", "the training grounds of the Academy for Awakened: packed sand, concrete walls with old scorch marks, weapon racks and floodlights at the edges, a modern-yet-austere military campus"),
		("F06", "Разрушенный корпус", "a campus building broken by a Nightmare breach: torn walls, scattered debris, dust in the air, emergency lights off"),
		("SPAR", "Тренировочный зал", "a big indoor sparring hall: worn mats, stone pillars, high narrow windows, dust in the light"),
	], ["art/map/academy/arena_dry.webp", "art/map/academy/gate_damaged.webp", "art/map/academy/dorm_dry.webp"]),
	("forgotten_shore", "Забытый Берег", [
		("F17", "Отмель (отлив)", "wet sand flats after the dark sea has retreated: shallow puddles, crimson coral stumps, bones of sea creatures, the black sea far behind"),
		("F08", "Лабиринт кораллов", "a passage between tall walls of blood-red coral, narrow side ways, dripping water"),
		("F06", "Руины", "ruins of an ancient drowned city of black stone: broken arches and columns overgrown with crimson coral"),
		("F03", "Высота", "a high rock ledge above the coral maze, the sea and the ruins below in haze"),
		("F21", "Грот и логово", "a coral grotto / creature lair: low vault of coral and black rock, gnawed shells on the floor, pale light from openings"),
		("F16", "Тёмное море (прилив)", "knee-deep black water of the rising tide, half-submerged ruins and coral, small waves"),
	], ["art/regions/forgotten_shore_day.webp", "art/map/forgotten_shore/coral_maze_dry.webp", "art/map/forgotten_shore/legion_ruins_dry.webp", "art/map/forgotten_shore/drowned_hall_dry.webp"]),
	("ash_path", "Древо Души — Пепельный путь", [
		("F18", "Пепельное поле", "grey ash dunes under a heavy sky, bleached giant bones, faint ember glow deep in the ash"),
		("F17", "Берег Чёрной воды", "the shore of a still black lake, black rocks, ash on the stones"),
		("F22", "Мост над Бездной", "an ancient narrow stone bridge over a bottomless abyss, broken parapets, fog below"),
		("F23", "Под Древом Души", "a clearing under the enormous Soul Tree: huge roots at the edges, glowing pale moss, drifting petals"),
	], ["art/map/ash_path/ash_dunes_dry.webp", "art/map/ash_path/abyss_bridge_dry.webp", "art/map/ash_path/soul_tree_dry.webp", "art/map/ash_path/lake_shore_dry.webp"]),
	("dark_city", "Мрачный город", [
		("F06", "Руины улиц", "gothic ruined streets of the Dark City: collapsed houses, broken lanterns, cobbles, a dead cathedral spire far away"),
		("F21", "Катакомбы", "underground catacombs: stone vaults, niches with old bones (no bodies on the floor), a narrow light shaft"),
		("F19", "Кладбище", "an overgrown cemetery: leaning gravestones, a broken iron fence, dead trees"),
		("F07", "Собор", "inside a ruined cathedral: tall broken columns, shattered stained glass, rubble at the edges"),
		("F24", "Площадь Светлого замка", "the square before the Bright Castle: clean stone, banners, the castle walls behind, a wary crowd's absence"),
	], ["art/map/dark_city/ruined_cathedral_dry.webp", "art/map/dark_city/catacombs_dry.webp", "art/map/dark_city/graveyard_hope_dry.webp", "art/map/dark_city/bright_castle_dry.webp"]),
	("real_city", "Город людей", [
		("F06", "Разрушенный квартал", "a modern city block wrecked by a Nightmare Gate: torn asphalt, burnt cars at the edges, broken facades, dust"),
		("F02", "Проспект", "a wide avenue / square of a modern city under alarm, empty, abandoned barricades at the edges"),
		("F01", "Переулок", "a narrow back alley between tall buildings, fire escapes, trash, a flickering sign (no readable text)"),
		("F22", "Мост", "a road bridge over a river, damaged railing, the city skyline in haze"),
		("F16", "Набережная", "a flooded embankment: dark water over the pavement, a broken parapet, the river behind"),
	], ["art/map/real_city/gov_quarter_damaged.webp", "art/map/real_city/market_ruined.webp", "art/map/real_city/bridges_damaged.webp", "art/map/real_city/gate_open.webp"]),
]

ICON_COMMON = """Use case: SKILL ICON for the SunLess combat UI. A square engraved vignette (like a tiny tarot illustration)
showing the action below, centred and readable at 96×96 px; dark background fading to black at the edges; no frame,
no text, letters or numbers. Style: the attached SunLess card art — dark antique engraving, silver-grey with one
muted accent colour. OUTPUT: 512×512 PNG."""

SKILL_ICONS = [   # (файл, название, что изобразить)
	("P01_s1", "Санни — Удар из тени", "a dark blade thrusting out of a pool of black shadow"),
	("P01_s2", "Санни — Раствориться в тени", "a hooded silhouette dissolving into black smoke"),
	("P02_s1", "Нефис — Удар Меняющейся Звезды", "a sword arc trailing white flame"),
	("P02_s2", "Нефис — Вызов", "a sword pointed forward, white flame along the blade"),
	("P03_s1", "Касси — Пророчество", "an open hand with threads of pale light, a closed eye above"),
	("P03_s2", "Касси — Голос во тьме", "lips speaking, soft light rings in the darkness"),
	("P04_s1", "Кастер — Молниеносный выпад", "a thin blade with motion streaks"),
	("P04_s2", "Кастер — Первая кровь", "a blade tip with a single drop of blood"),
	("P08_s1", "Ауро — Удар Девяти", "a heavy sword coming down, cracks below"),
	("P08_s2", "Ауро — Стальная стена", "a blade held across like a wall"),
	("P09_s1", "Шолар — Найти слабину", "an eye over a cracked armour plate"),
	("P09_s2", "Шолар — Выследить", "footprints and a pointing finger"),
	("P10_s1", "Шифти — Грязный приём", "a hand throwing sand, a hidden knife"),
	("P10_s2", "Шифти — Ложная тревога", "a shouting mouth and a pointing hand"),
	("echo_s1", "Эхо — Клешни", "two crab claws snapping"),
	("echo_s2", "Эхо — Заслон", "a chitin shell as a shield"),
	("echo_s3", "Эхо — Серповидный выпад", "a sickle-shaped chitin blade"),
	("echo_s4", "Эхо — Отозвать", "a pale soul-light flowing back into a card"),
	("step", "Шаг", "two footprints and a curved arrow"),
	("pass", "Пропуск", "an hourglass"),
	("retreat", "Отступить", "a torn banner turned backward"),
	("summon", "Призвать Эхо", "a card with a pale creature rising from it"),
]

TOKEN_BASE = """Use case: STATUS TOKEN for the SunLess combat UI (shown at 22–32 px under a fighter and at 64 px in tooltips).
First image — the EMPTY token base: a round dark-iron medallion with a thin moon-silver rim, slightly worn, flat
front view, transparent background, no symbol inside. OUTPUT: 512×512 PNG, transparent."""
TOKEN_NEXT = """Use the previous image (the empty token) exactly: same medallion, same rim, same size and light. Put inside ONLY
this symbol, engraved and simple, readable at 24 px: {glyph}. Accent colour: {color}. No text, letters or numbers."""
STATUSES = [   # (файл, состояние, символ, цвет)
	("bleed", "Кровотечение", "a falling drop of blood", "crimson"),
	("poison", "Яд", "a fang with a drop of venom", "sickly green"),
	("stun", "Оглушение", "a cracked star burst", "pale yellow"),
	("mark", "Метка", "a thin crosshair with a dot", "orange-red"),
	("guard", "Защита", "a shield with a small figure behind it", "silver-blue"),
	("riposte", "Контратака", "two crossed blades with a curved arrow", "steel"),
	("stealth", "Скрытность", "a half-closed eye in fog", "grey"),
	("shadow", "В тени", "a figure dissolving into black wisps", "black-violet"),
	("burn", "Горение", "a white flame", "white-gold"),
	("charm", "Очарование", "a spiral blossom", "pink-violet"),
	("fear", "Страх", "a wide-eyed face", "pale bone"),
	("grab", "Захват", "a tentacle coiled around a wrist", "teal"),
	("whisper", "Кошмарный шёпот", "a mouth whispering dark smoke", "purple"),
	("blind", "Ослепление", "an eye crossed by a bright slash", "white"),
	("foresight", "Предвидение", "an eye with a thread leading to an arrow", "cold blue"),
	("block", "Панцирь", "overlapping chitin plates", "bronze"),
	("dodge", "Уклон", "a figure with a motion echo", "silver"),
	("rage", "Ярость", "clenched fangs with red streaks", "red"),
	("regen", "Регенерация", "a sprouting vein-leaf", "green"),
	("acid", "Разъедание", "a cracked armour plate with drops", "acid yellow-green"),
	("taunt", "Приманка", "a small bell with sound arcs", "silver"),
	("cold", "Холод", "a snow crystal", "ice blue"),
	("buff", "Усиление", "two upward chevrons", "gold"),
	("debuff", "Ослабление", "two downward chevrons", "dull red"),
	("weak", "Слабость после грани", "a cracked heart", "grey-red"),
	("edge", "Грань смерти", "a skull on a thin edge line", "deep red"),
	("panic", "Паника", "a cracked head silhouette", "violet"),
	("uplift", "Подъём духа", "a rising star over a head", "gold"),
]
LIGHTS = [
	("light_bright", "Яркий", "a sun disk with fine rays"),
	("light_dim", "Тусклый", "a low sun behind haze"),
	("light_dusk", "Сумрак", "a moon behind clouds"),
	("light_dark", "Тьма (затмение)", "a black sun with a thin corona"),
	("light_blood", "Тьма (кровавая луна)", "a blood-red moon"),
]

UI_COMMON = """Use case: UI ART for the SunLess combat screen (1920×1080). Match the attached SunLess card border exactly: moon-silver
double border, clipped corners, dark paper texture, restrained ornaments; see the attached interface collage for the
current UI. Plain dark inner area (the game draws text and pictures there). No text, letters, numbers, icons or
characters. Transparent background outside the frame."""
UI_ITEMS = [
	("ui_panel", "Нижняя панель", "a wide horizontal frame for the bottom panel. OUTPUT: 1920×300 PNG, the frame along the edges, the inner area dark and empty."),
	("ui_skill", "Кнопка навыка — 4 состояния", "a square button frame with clipped corners in 4 states side by side: normal (silver), hover (brighter silver), selected (gold glow), disabled (dim). OUTPUT: 4 cells 256×256 in one 1024×256 PNG."),
	("ui_turn", "Медальон очереди", "round portrait medallions in 3 variants side by side: hero (silver rim), enemy (crimson rim), acting now (gold rim with a soft glow); the centre empty and transparent. OUTPUT: 3 cells 256×256 in one 768×256 PNG."),
	("ui_plate", "Плашка сверху", "a horizontal plate for the field name and light level, same border style. OUTPUT: 640×96 PNG."),
	("ui_retreat", "Кнопка «Отступить»", "a plate-button with a darker crimson inner field (the game writes the word). OUTPUT: 320×96 PNG."),
	("ui_target", "Кольца под бойцами", "flat ellipse rings seen from the side in 3 colours one above another: gold (acting), crimson (enemy target), pale green (ally target). Engraved, thin, soft glow. OUTPUT: 3 rings 512×128 in one 512×384 PNG."),
]

FIELD_EVENTS = [   # карты событий поля (по шаблону карты): (id, название, иллюстрация)
	("FE01", "Прилив подступает", "black sea water rushing over wet sand and coral toward the viewer, foam, ruins half submerged"),
	("FE02", "Молния", "a lightning bolt striking ancient ruins in a storm, rain"),
	("FE03", "Обвал", "stones and broken columns falling in a dusty collapse"),
	("FE04", "Туман сгущается", "thick fog swallowing a coral passage, faint silhouettes lost in it"),
	("FE05", "Пепельный порыв", "a gust of grey ash sweeping across dunes, embers in it"),
	("FE06", "Зов Кошмара", "a dark sky cracking open with a faint red glow, whispers drawn as smoke"),
	("FE07", "Кровь на снегу", "fresh blood drops on white snow by a mountain path, wolfish tracks"),
	("FE08", "Коралл режет", "razor-sharp crimson coral with a torn cloth caught on it"),
	("FE09", "Скользкий ил", "glistening wet silt with a slipping footprint"),
	("FE10", "Эхо в темноте", "a dark cave mouth with sound rings echoing inside"),
	("FE11", "Буран", "a blizzard over a mountain ridge, snow streaks"),
	("FE12", "Жар земли", "cracks in ash-covered ground glowing with heat"),
]
CARD_COMMON = """Use case: stylized-concept. Edit the attached EMPTY SunLess card as a locked template (and follow the attached
template settings text). Exactly ONE separate event card, vertical 7:12, frontal, all four edges visible, filling the
frame, no surrounding surface. Preserve the moon-silver double border, clipped corners, dark paper texture, horizontal
divider and opaque lower title plaque geometry. Change only the INNER UPPER field by illustrating the subject below,
and add only its exact Cyrillic name in centered pale ivory elegant uppercase serif in the lower panel. No stats,
icons, rank, gems, digits, extra lines, runes, fake writing, watermark, logo or added caption. Dark antique engraved
tarot art, fine painterly etching, restrained cool silver and muted accents, low exposure (match the attached example
cards). Output: 952×1632 PNG (7:12)."""
CARD_EXAMPLES = ["docs/assets/cards/concepts/enhancements-template-series-v2/01-U01-Импровизированное-оружие.png",
	"docs/assets/cards/concepts/09-M03-carapace-scavenger.png"]

FX_COMMON = """Use case: single-frame EFFECT sprite for SunLess side-view battles (the game animates it: scale, fade, rotation).
SUBJECT: {subject} Centred, on a fully transparent background, no ground, no characters, no text. Painterly, matching
the muted engraved SunLess style, with the stated accent colour. OUTPUT: 1024×1024 PNG, transparent."""
FX = [
	("fx_slash", "Рубящий удар", "a curved silver slash arc, fading at the ends."),
	("fx_pierce", "Колющий удар", "a thin straight piercing streak with a small spark at the tip."),
	("fx_blunt", "Дробящий удар", "a dust-and-stone impact burst with radiating cracks."),
	("fx_blood", "Кровь", "a spray of dark red droplets from left to right."),
	("fx_poison", "Яд", "a small cloud of sickly green vapour with drops."),
	("fx_flame", "Белое пламя", "a burst of white-gold flame."),
	("fx_shadow", "Тень", "black shadow tendrils bursting outward."),
	("fx_psyche", "Удар по психике", "concentric violet ripples, distorted like a mirage."),
	("fx_heal", "Лечение", "rising warm golden motes and a soft glow."),
	("fx_shield", "Защита", "a translucent curved silver barrier shimmer."),
	("fx_lightning", "Молния", "a forked blue-white lightning bolt from top to bottom."),
	("fx_acid", "Кислота", "an acid splash, yellow-green, with smoking drops."),
]


def code_pose(d, title, text):
	d.h(3, title)
	d.code(text)


def build_prompts():
	enemies = {e["id"]: e for e in load("data/combat/enemies.json")}
	heroes = {c["id"]: c for c in load("data/characters.json")}
	d = Doc()
	d.para(d.run("SunLess — пошаговый бой «Схватка»: промты для ChatGPT"), "Title")
	d.text("Картинки для нового боя (ТЗ — docs/24 и «ТЗ — Пошаговый бой «Схватка».docx»): фигуры героев и врагов "
		"в полный рост сбоку, позы-кадры для ударов, фоны боя по местам, рамки интерфейса, значки состояний, иконки "
		"навыков, карты событий поля и вспышки ударов. Стиль — как карты SunLess. Образцы для ChatGPT — прямо здесь "
		"картинками; ссылки ведут к файлам проекта (щелчок по ссылке открывает файл).")
	d.refs("Как это будет выглядеть (макет из готовых картинок, фигуры временные):", [MOCKUP], 8.0, fmt="jpeg")

	d.h(2, "Что нужно и в каком порядке")
	n_en = len(ENEMIES)
	poses_en = sum(len(ENEMY_POSES[enemies.get(i, {}).get("kind", "normal")]) for i in ENEMIES)
	d.table([
		["Группа", "Сколько", "Для прототипа (сначала)", "Куда класть"],
		["Герои — позы-кадры", "%d героев × %d поз = %d" % (len(HEROES), len(HERO_POSES), len(HEROES) * len(HERO_POSES)),
			"Санни, Нефис, Касси, Кастер × 4 позы (стойка, удар, получил удар, на грани) = 16", SRC + "/heroes/P01_idle.png …"],
		["Эхо", "%d × 4 позы = %d" % (len(ECHOES), len(ECHOES) * 4), "Эхо Падальщика × 4", SRC + "/echo/U12_idle.png …"],
		["Враги", "%d врагов, %d поз (обычный 3, элита 4, босс 6)" % (n_en, poses_en), "Падальщик, Центурион, Щупальца, Скелеты, Личинка — стойка, атака", SRC + "/enemies/M03_idle.png …"],
		["Трупы", "%d" % len(CORPSES), "панцирные, кости", SRC + "/corpses/carapace.png …"],
		["Фоны боя", "%d (по полям регионов)" % sum(len(x[2]) for x in BGS), "Берег: Отмель, Лабиринт кораллов", SRC + "/bg/forgotten_shore_F17.png …"],
		["Интерфейс", "%d рамок" % len(UI_ITEMS), "панель, кнопка навыка, медальон", SRC + "/ui/ui_panel.png …"],
		["Значки состояний и света", "%d + %d" % (len(STATUSES), len(LIGHTS)), "основа жетона + 8 состояний DD", SRC + "/icons/bleed.png …"],
		["Иконки своих навыков", "%d" % len(SKILL_ICONS), "Санни и Нефис, Шаг, Пропуск", SRC + "/skills/P01_s1.png …"],
		["Карты событий поля", "%d (по шаблону карты)" % len(FIELD_EVENTS), "Прилив, Обвал", SRC + "/cards/FE01.png …"],
		["Вспышки ударов", "%d" % len(FX), "рубящий, колющий, кровь", SRC + "/fx/fx_slash.png …"],
	], widths=[0.2, 0.25, 0.3, 0.25])
	d.note("Карты навыков из кармашка и портреты в очереди ходов берутся из уже готовых карт — рисовать их не нужно. "
		"Пока картинок нет, в игре стоят заглушки (карта героя или врага в рамке), так что рисовать можно в любом порядке.")

	d.h(2, "Как пользоваться")
	for t in [
		"1. Один персонаж — один новый чат. Приложите образцы из его раздела (картинки здесь, файлы — по ссылкам).",
		"2. Вставьте «Общий блок фигуры» (с подставленным «лицом вправо/влево» и размером — уже подставлено в разделе персонажа), "
			"затем первую позу — «Стойка». Это опорная картинка.",
		"3. Остальные позы — в том же чате блоком «Следующая поза»: он просит взять прошлую картинку за основу и поменять "
			"только позу. Масштаб, линия ног и свет не меняются — в игре позы сменяют друг друга на месте.",
		"   Вариант надёжнее: сразу лист поз (блок «Лист поз») — персонаж выйдет одинаковым во всех позах, я разрежу лист.",
		"4. Фоны, рамки, значки, эффекты — отдельные чаты, у каждого свой общий блок.",
		"5. Карты событий поля — как все карты игры: ПУСТОЙ шаблон карты + его настройки (текст) + 1–2 готовые карты-образца.",
		"6. Готовые файлы кладите в папки из таблицы выше (или пришлите — я переведу в нужный формат и подключу).",
	]:
		d.text(t)

	d.h(2, "Общий блок фигуры")
	d.code(FIGURE_COMMON.format(facing="{RIGHT for heroes and echoes | LEFT for enemies}", size="{1024×1536 | 2048×1536 for big creatures}"))
	d.h(2, "Шаблон карты (для карт событий поля)")
	d.refs("Шаблон:", [TEMPLATE], 5.0)
	d.para(d.run("• Настройки шаблона (текст): ") + d.link(TEMPLATE_TXT), after=60)
	d.code(io.open(os.path.join(ROOT, TEMPLATE_TXT), encoding="utf-8").read().strip())

	# --- герои ---
	d.h(1, "Герои — позы-кадры (лицом вправо)")
	d.table([["Поза", "Файл", "Что за поза"]] + [[t, "<id>_%s.png" % f, (p or "свой навык героя — в разделе героя")]
		for f, t, p in HERO_POSES], widths=[0.18, 0.2, 0.62])
	d.text("Для прототипа сначала: стойка, удар, получил удар, на грани (P1). Позы «паника» и «подъём духа» — для кризиса "
		"психики; «карта» — общая поза для навыков карт и Воспоминаний.", italic=True)
	for hid, name, own, extra in HEROES:
		c = heroes.get(hid, {})
		d.h(2, "%s (%s)" % (name, hid))
		w = c.get("weapon", "—")
		d.text("Оружие в данных: %s. Свои навыки: «%s», «%s»." % (w, own[0][0], own[1][0]))
		refs = [p for p in [art(hid)] + extra if p]
		d.refs("Образцы (облик героя — строго по карте):", refs, 4.2, fmt="jpeg")
		fac = "RIGHT (the hero stands on the left side of the battle)"
		first = True
		for f, t, p in HERO_POSES:
			if f == "skill1":
				p = own[0][1]
				t = "Свой навык 1 — " + own[0][0]
			elif f == "skill2":
				p = own[1][1]
				t = "Свой навык 2 — " + own[1][0]
			label = "%s (%s_%s.png)%s" % (t, hid, f, " · P1" if f in P1_POSES and hid in ("P01", "P02", "P03", "P04") else "")
			if first:
				code_pose(d, label, FIGURE_COMMON.format(facing=fac, size=HERO_SIZE) + "\nCHARACTER: %s, as on the attached card.\nPOSE: %s" % (name, p))
				first = False
			else:
				code_pose(d, label, POSE_NEXT.format(facing="RIGHT", pose=p))
		d.h(3, "Лист поз 4×3 (вместо отдельных)")
		d.code(SHEET_TIP.format(grid="4 columns × 3 rows (2 last cells empty)", cell="1024×1536", facing="RIGHT",
			order=", ".join(t for _, t, _ in HERO_POSES)))

	# --- Эхо ---
	d.h(1, "Эхо (лицом вправо)")
	d.text("Эхо — призванный боец: занимает свободную позицию в строю героев. Облик — убитое существо, но «душа-тень»: "
		"полупрозрачные края и холодный свет в трещинах.")
	for cid, name, beast, poses in ECHOES:
		d.h(2, "%s (%s)" % (name, cid))
		d.refs("Образцы — существо и карта Эха:", [p for p in [art(beast), art(cid)] if p], 4.2, fmt="jpeg")
		for i, (f, t, p) in enumerate(poses):
			label = "%s (%s_%s.png)" % (t, cid, f)
			if i == 0:
				code_pose(d, label, FIGURE_COMMON.format(facing="RIGHT", size=HERO_SIZE) + "\nCHARACTER: %s\n%s\nPOSE: %s"
					% (ENEMIES[beast][0], ECHO_LOOK, p))
			else:
				code_pose(d, label, POSE_NEXT.format(facing="RIGHT", pose=p))

	# --- враги ---
	d.h(1, "Враги (лицом влево)")
	d.text("Обычный враг — 3 позы (стойка, атака, получил удар), элита — 4 (+ особый навык), босс — 6 (+ два особых "
		"навыка и вторая фаза). Крупные (Гигант, крупные боссы) занимают две позиции — кадр шире. Стаи: рисуется ОДНО "
		"существо, в бою их ставится несколько.", italic=True)
	d.table([["Враг", "Как рисуем"]] + [["%s %s" % (k, enemies.get(k, {}).get("name", "")), v] for k, v in REUSE.items()],
		widths=[0.35, 0.65])
	order = sorted(ENEMIES, key=lambda k: ({"normal": 0, "elite": 1, "boss": 2}.get(enemies.get(k, {}).get("kind", "normal"), 0), k))
	for eid in order:
		desc, big, specials = ENEMIES[eid]
		e = enemies.get(eid, {})
		kind = e.get("kind", "normal")
		d.h(2, "%s — %s (%s%s)" % (eid, e.get("name", eid), {"normal": "обычный", "elite": "элита", "boss": "босс"}[kind],
			", 2 позиции" if big else ""))
		d.text("Теги: %s." % ", ".join(e.get("tags", [])), size=9.5, color="555555")
		a = art(eid)
		if a:
			d.refs("Образец (облик — строго по карте):", [a], 4.2, fmt="jpeg")
		poses = []
		sp = list(specials)
		for x in ENEMY_POSES[kind]:
			if x is None:
				x = sp.pop(0) if sp else ("special", "Особый навык", "its signature attack toward the LEFT.")
			poses.append(x)
		poses += sp   # если особых больше, чем мест
		size = BIG_SIZE if big else HERO_SIZE
		for i, (f, t, p) in enumerate(poses):
			label = "%s (%s_%s.png)" % (t, eid, f)
			if i == 0:
				code_pose(d, label, FIGURE_COMMON.format(facing="LEFT (the enemy stands on the right side of the battle)", size=size)
					+ "\nCHARACTER: %s, exactly as on the attached card.\nPOSE: %s" % (desc, p))
			else:
				code_pose(d, label, POSE_NEXT.format(facing="LEFT", pose=p))

	d.h(2, "Трупы")
	d.text("После гибели врага на его позиции остаётся труп (держит место в строю). Один набор на тип тела.")
	d.refs("Образцы стиля:", [art("M03"), art("M27"), art("M17")], 3.6, fmt="jpeg")
	for f, t, s in CORPSES:
		code_pose(d, "%s (corpses/%s.png)" % (t, f), CORPSE_COMMON.format(subject=s))

	# --- фоны ---
	d.h(1, "Фоны боя — по полям регионов")
	d.text("Фон — сцена: бойцы стоят на полосе земли внизу (70–95% высоты), середина спокойнее, рамка из скал и руин "
		"по краям. Свет нейтральный дневной: ночь, бурю, затмение и кровавую луну игра делает сама.")
	d.h(2, "Общий блок фона")
	d.code(BG_COMMON)
	for reg, title, items, refs in BGS:
		d.h(2, title)
		d.refs("Образцы места (материалы, цвета, свет):", refs, 3.4, fmt="jpeg")
		for fid, name, desc in items:
			code_pose(d, "%s (bg/%s_%s.png)" % (name, reg, fid), BG_COMMON + "\nPLACE: %s." % desc)

	# --- интерфейс ---
	d.h(1, "Интерфейс боя")
	d.refs("Образцы — рамка карты, нынешний интерфейс:", [TEMPLATE, COLLAGE], 5.0, fmt="jpeg")
	d.h(2, "Общий блок рамок")
	d.code(UI_COMMON)
	for f, t, s in UI_ITEMS:
		code_pose(d, "%s (ui/%s.png)" % (t, f), UI_COMMON + "\nITEM: " + s)

	d.h(2, "Значки состояний (жетоны)")
	d.text("Сначала пустой жетон-основа, потом в том же чате — каждый символ на нём (так все значки выйдут одинаковыми).")
	d.refs("Образцы стиля:", ["art/ui/emblems/power.png", "art/ui/emblems/will.png", "art/ui/emblems/cunning.png", "art/ui/tags/mystic.png"], 2.4)
	code_pose(d, "Основа жетона (icons/token_base.png)", TOKEN_BASE)
	d.table([["Файл", "Состояние", "Символ", "Цвет"]] + [["icons/%s.png" % f, n, g, c] for f, n, g, c in STATUSES],
		widths=[0.22, 0.24, 0.36, 0.18])
	d.code(TOKEN_NEXT.format(glyph="{символ из таблицы}", color="{цвет из таблицы}"))
	d.h(2, "Значки света")
	d.table([["Файл", "Свет", "Символ"]] + [["icons/%s.png" % f, n, g] for f, n, g in LIGHTS], widths=[0.3, 0.3, 0.4])
	d.code(TOKEN_NEXT.format(glyph="{символ из таблицы}", color="warm silver; blood moon — deep red"))

	d.h(2, "Иконки своих навыков")
	d.refs("Образцы стиля (карты способностей):", [art("A01"), art("A03"), art("A04")], 3.4, fmt="jpeg")
	d.code(ICON_COMMON)
	d.table([["Файл", "Навык", "Что изобразить"]] + [["skills/%s.png" % f, t, s] for f, t, s in SKILL_ICONS], widths=[0.22, 0.33, 0.45])

	# --- карты событий поля ---
	d.h(1, "Карты событий поля (по шаблону карты)")
	d.text("Событие поля приходит раз в 2–3 раунда (ТЗ, 4.6) и показывается картой. Как все карты игры — по пустому "
		"шаблону и его настройкам, с образцами готовых карт.")
	d.refs("Приложить: шаблон и образцы готовых карт:", [TEMPLATE] + CARD_EXAMPLES, 4.2, fmt="jpeg")
	d.para(d.run("• Настройки шаблона: ") + d.link(TEMPLATE_TXT), after=80)
	for fid, name, s in FIELD_EVENTS:
		code_pose(d, "%s «%s» (cards/%s.png)" % (fid, name, fid),
			CARD_COMMON + "\n%s “%s”: %s. Exact lower title “%s”." % (fid, name, s, name.upper()))

	# --- эффекты ---
	d.h(1, "Вспышки ударов")
	d.text("Одна картинка на эффект — игра сама анимирует её (растягивает, поворачивает, гасит).")
	for f, t, s in FX:
		code_pose(d, "%s (fx/%s.png)" % (t, f), FX_COMMON.format(subject=s))

	d.save(os.path.join(ROOT, PR_OUT))
	return d


def build_tz(src: str = TZ_MD, out: str = TZ_OUT):
	md = io.open(os.path.join(ROOT, src), encoding="utf-8").read()
	d = Doc()
	md_to_doc(md, d, base="docs")
	d.save(os.path.join(ROOT, out))
	return d


if __name__ == "__main__":
	paths = [TEMPLATE, TEMPLATE_TXT, MOCKUP, COLLAGE] + CARD_EXAMPLES + sum([x[3] for x in BGS], []) + \
		["art/ui/emblems/power.png", "art/ui/emblems/will.png", "art/ui/emblems/cunning.png", "art/ui/tags/mystic.png"]
	missing = [p for p in paths if not os.path.exists(os.path.join(ROOT, p))]
	assert not missing, missing
	t = build_tz()
	print("ТЗ:", TZ_OUT, "· картинок:", len(t.media), "· ссылок:", sum(1 for r in t.rels if r[3]))
	te = build_tz(TZ_MD_EN, TZ_OUT_EN)
	print("ТЗ (англ.):", TZ_OUT_EN, "· картинок:", len(te.media), "· ссылок:", sum(1 for r in te.rels if r[3]))
	p = build_prompts()
	print("промты:", PR_OUT, "· картинок:", len(p.media), "· вставок:", p.pic, "· ссылок:", sum(1 for r in p.rels if r[3]))
