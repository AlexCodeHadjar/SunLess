"""Word (.docx) без сторонних библиотек: WordprocessingML в zip — абзацы, заголовки, таблицы, ссылки на файлы проекта,
картинки внутри документа; плюс перевод простого Markdown (заголовки, списки, таблицы, код, цитаты, картинки) в Word.

Используют: tools/gen_boss_prompts.py, tools/gen_skirmish_docs.py (ТЗ «Схватки» из docs/24 и промты артов).
"""
import io
import os
import re
import zipfile
from xml.sax.saxutils import escape

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGE_W_CM = 17.5     # ширина текста на A4 при полях 1000 twips


class Doc:
	def __init__(self):
		self.body = []
		self.rels = []      # (id, type, target, external)
		self.media = []     # (name, bytes)
		self.pic = 0
		self.cache = {}   # (путь, высота, формат) → (имя, rId, ширина)

	def rel(self, typ, target, external=False):
		rid = "rId%d" % (len(self.rels) + 10)
		self.rels.append((rid, typ, target, external))
		return rid

	# --- текст -------------------------------------------------------------------------------------------------------

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
		if size:   # порядок по схеме WordprocessingML: color, sz, u
			pr += '<w:sz w:val="%d"/>' % int(size * 2)
		if under:
			pr += '<w:u w:val="single"/>'
		out = []
		for i, part in enumerate(text.split("\n")):
			if i:
				out.append("<w:r><w:br/></w:r>")
			out.append('<w:r><w:rPr>%s</w:rPr><w:t xml:space="preserve">%s</w:t></w:r>' % (pr, escape(part)))
		return "".join(out)

	def rich(self, text, size=None, color=None):
		"""Строка с разметкой **жирный**, *курсив*, `код`, [подпись](адрес) → runs."""
		out = []
		pos = 0
		for m in INLINE.finditer(text):
			if m.start() > pos:
				out.append(self.run(text[pos:m.start()], size=size, color=color))
			if m.group("b") is not None:
				out.append(self.run(m.group("b"), bold=True, size=size, color=color))
			elif m.group("i") is not None:
				out.append(self.run(m.group("i"), italic=True, size=size, color=color))
			elif m.group("c") is not None:
				out.append(self.run(m.group("c"), mono=True, size=(size or 11) - 1, color="5B2A86"))
			else:
				out.append(self.url(m.group("u"), m.group("t"), size=size))
			pos = m.end()
		if pos < len(text):
			out.append(self.run(text[pos:], size=size, color=color))
		return "".join(out)

	def para(self, runs, style=None, shade=None, after=120, keep=False, indent=0, align=None):
		ppr = ""
		if style:
			ppr += '<w:pStyle w:val="%s"/>' % style
		if keep:
			ppr += "<w:keepNext/>"
		if shade:
			ppr += '<w:shd w:val="clear" w:color="auto" w:fill="%s"/>' % shade
		ppr += '<w:spacing w:after="%d"/>' % after
		if indent:
			ppr += '<w:ind w:left="%d" w:hanging="220"/>' % indent
		if align:
			ppr += '<w:jc w:val="%s"/>' % align
		self.body.append("<w:p><w:pPr>%s</w:pPr>%s</w:p>" % (ppr, runs))

	def h(self, level, t):
		self.para(self.rich(t), "Heading%d" % level)

	def text(self, t, **kw):
		self.para(self.run(t, **kw))

	def code(self, t):
		self.para(self.run(t, mono=True, size=8.5), shade="F2F2F2")

	def note(self, t):
		self.para(self.rich(t), shade="EEE8F6", after=160)

	def bullet(self, t, level=0):
		self.para(self.run("•  ") + self.rich(t), after=60, indent=360 + 360 * level)

	# --- ссылки ------------------------------------------------------------------------------------------------------

	def url(self, target, label, size=None):
		"""Внешняя ссылка (http…) или файл проекта (относительный путь)."""
		if not re.match(r"^[a-z]+://", target):
			abs_path = os.path.normpath(os.path.join(ROOT, target))
			# кириллица — как есть (Word читает %-кодировку как cp1252 и ломает путь), пробелы — %20
			target = "file:///" + abs_path.replace(" ", "%20")
		rid = self.rel("http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink", target, True)
		return '<w:hyperlink r:id="%s" w:history="1">%s</w:hyperlink>' % (rid, self.run(label, color="0563C1", under=True, size=size or 10))

	def link(self, rel_path, label=None):
		"""Ссылка на файл проекта (кликабельная, file:///)."""
		return self.url(rel_path, label or rel_path, size=9.5)

	# --- картинки ----------------------------------------------------------------------------------------------------

	def _media(self, im, fmt):
		buf = io.BytesIO()
		if fmt == "jpeg":
			im.convert("RGB").save(buf, "JPEG", quality=84, optimize=True)
		else:
			im.convert("RGB").save(buf, "PNG", optimize=True)
		name = "ref%d.%s" % (len(self.media) + 1, "jpeg" if fmt == "jpeg" else "png")
		self.media.append((name, buf.getvalue()))
		return name, self.rel("http://schemas.openxmlformats.org/officeDocument/2006/relationships/image", "media/" + name)

	def _drawing(self, name, rid, cx, cy):
		self.pic += 1
		return ('<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="72000"><wp:extent cx="%d" cy="%d"/>'
			'<wp:docPr id="%d" name="Образец %d"/><a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
			'<a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
			'<pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="%d" name="%s"/>'
			'<pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="%s"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
			'<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="%d" cy="%d"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
			'</pic:spPr></pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r>'
			% (cx, cy, self.pic, self.pic, self.pic, name, rid, cx, cy))

	def image(self, rel_path, height_cm=3.6, px=360, fmt="png"):
		"""Картинка-образец внутри документа (уменьшенная; прозрачное — на тёмном, как в игре). Повтор той же
		картинки не добавляет файл в документ — ссылается на уже вставленный."""
		key = (rel_path, px, fmt)
		if key not in self.cache:
			im = Image.open(os.path.join(ROOT, rel_path)).convert("RGBA")
			w = max(1, int(im.width * px / im.height))
			im = im.resize((w, px), Image.LANCZOS)
			bg = Image.new("RGBA", im.size, (40, 40, 48, 255))
			bg.alpha_composite(im)
			self.cache[key] = self._media(bg, fmt) + (w,)
		name, rid, w = self.cache[key]
		cy = int(height_cm * 360000)
		return self._drawing(name, rid, int(cy * w / px), cy)

	def image_wide(self, rel_path, width_cm=PAGE_W_CM, px=1400):
		"""Картинка на ширину страницы (макеты, схемы)."""
		im = Image.open(os.path.join(ROOT, rel_path)).convert("RGBA")
		h = max(1, int(im.height * px / im.width))
		im = im.resize((px, h), Image.LANCZOS)
		cx = int(width_cm * 360000)
		name, rid = self._media(im, "jpeg")
		return self._drawing(name, rid, cx, int(cx * h / px))

	def refs(self, title, paths, height_cm=3.6, fmt="png"):
		"""Блок «Образцы»: картинки рядом и под ними ссылки на файлы."""
		self.para(self.run(title, bold=True, color="5B2A86"), after=40, keep=True)
		self.para("".join(self.image(p, height_cm, fmt=fmt) for p in paths), after=40, keep=True)
		for p in paths:
			self.para(self.run("• ") + self.link(p), after=20)
		self.para("", after=80)

	# --- таблицы -----------------------------------------------------------------------------------------------------

	def table(self, rows, header=True, widths=None, size=9):
		"""rows — список строк (список ячеек, разметка как в rich). widths — доли ширины колонок."""
		n = max(len(r) for r in rows)
		total = 9906
		if not widths:
			lens = [max(min(len(r[i]) if i < len(r) else 0, 60) for r in rows) + 4 for i in range(n)]
			widths = [x / sum(lens) for x in lens]
		tw = [int(total * w) for w in widths]
		b = '<w:%s w:val="single" w:sz="4" w:space="0" w:color="B8B0C8"/>'
		borders = "".join(b % s for s in ["top", "left", "bottom", "right", "insideH", "insideV"])
		out = ['<w:tbl><w:tblPr><w:tblW w:w="%d" w:type="dxa"/><w:tblBorders>%s</w:tblBorders>'
			'<w:tblCellMar><w:left w:w="70" w:type="dxa"/><w:right w:w="70" w:type="dxa"/></w:tblCellMar></w:tblPr><w:tblGrid>%s</w:tblGrid>'
			% (total, borders, "".join('<w:gridCol w:w="%d"/>' % w for w in tw))]
		for ri, r in enumerate(rows):
			head = header and ri == 0
			out.append("<w:tr>%s" % ("<w:trPr><w:tblHeader/><w:cantSplit/></w:trPr>" if head else "<w:trPr><w:cantSplit/></w:trPr>"))
			for ci in range(n):
				cell = r[ci] if ci < len(r) else ""
				shade = '<w:shd w:val="clear" w:color="auto" w:fill="EDE7F6"/>' if head else ""
				runs = self.rich(cell, size=size) if not head else self.run(cell.replace("**", ""), bold=True, size=size)
				out.append('<w:tc><w:tcPr><w:tcW w:w="%d" w:type="dxa"/>%s</w:tcPr><w:p><w:pPr><w:spacing w:after="0"/></w:pPr>%s</w:p></w:tc>'
					% (tw[ci], shade, runs))
			out.append("</w:tr>")
		out.append("</w:tbl>")
		self.body.append("".join(out))
		self.para("", after=60)

	def page_break(self):
		self.body.append('<w:p><w:r><w:br w:type="page"/></w:r></w:p>')

	# --- файл --------------------------------------------------------------------------------------------------------

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


INLINE = re.compile(r"\*\*(?P<b>.+?)\*\*|(?<![\w*])\*(?P<i>[^*\s][^*]*?)\*(?!\w)|`(?P<c>[^`]+)`|\[(?P<t>[^\]]+)\]\((?P<u>[^)\s]+)\)")


def md_to_doc(md, d, base=""):
	"""Простой Markdown → Doc: # заголовки, - списки, | таблицы |, ``` код ```, > заметки, ![подпись](картинка), абзацы.
	Картинки — относительно base (папки Markdown-файла от корня проекта). Строки «<!--» пропускаются."""
	lines = md.replace("\r\n", "\n").split("\n")
	i = 0
	first_h1 = True
	while i < len(lines):
		ln = lines[i]
		s = ln.strip()
		if not s or s.startswith("<!--") or s == "---":
			i += 1
			continue
		if s.startswith("```"):
			buf = []
			i += 1
			while i < len(lines) and not lines[i].strip().startswith("```"):
				buf.append(lines[i])
				i += 1
			d.code("\n".join(buf))
			i += 1
			continue
		if s.startswith("|"):
			rows = []
			while i < len(lines) and lines[i].strip().startswith("|"):
				cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
				if not all(re.fullmatch(r":?-{2,}:?", c) for c in cells):
					rows.append(cells)
				i += 1
			d.table(rows)
			continue
		m = re.match(r"^(#{1,3})\s+(.*)$", s)
		if m:
			level = len(m.group(1))
			if level == 1 and first_h1:
				d.para(d.rich(m.group(2)), "Title")
				first_h1 = False
			else:
				d.h(level, m.group(2))
			i += 1
			continue
		m = re.match(r"^!\[(.*?)\]\((.+?)\)$", s)
		if m:
			d.para(d.image_wide(os.path.join(base, m.group(2))), after=40, align="center")
			if m.group(1):
				d.para(d.run(m.group(1), italic=True, size=9.5, color="555555"), after=160, align="center")
			i += 1
			continue
		if s.startswith(">"):
			buf = []
			while i < len(lines) and lines[i].strip().startswith(">"):
				buf.append(lines[i].strip()[1:].strip())
				i += 1
			d.note("\n".join(x for x in buf if not x.startswith("[!")))
			continue
		m = re.match(r"^(\s*)[-*]\s+(.*)$", ln)
		if m:
			d.bullet(m.group(2), len(m.group(1)) // 2)
			i += 1
			continue
		# абзац: подряд идущие строки
		buf = [s]
		i += 1
		while i < len(lines) and lines[i].strip() and not re.match(r"^\s*([-*]\s|#|\||>|```|!\[)", lines[i]):
			buf.append(lines[i].strip())
			i += 1
		d.para(d.rich(" ".join(buf)))


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
<Default Extension="jpeg" ContentType="image/jpeg"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>"""

RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>"""
