// Экран «Теги»: каталог по категориям, где используется, связи, создание/правка/удаление.
"use strict";

const TagsView = {
  cat: "all", query: "", selected: null, context: false,

  render(root, params = {}) {
    if (params.tag) {
      this.context = !!params.context;
      this.selected = params.tag;
      const t = this.context ? ctxTag(params.tag) : combatTag(params.tag);
      this.cat = this.context ? "@ctx" : t ? t.category : "all";
      this.query = "";
    }
    this.side = h("aside", { class: "side" });
    this.main = h("section", { class: "grid-wrap" });
    this.detailEl = h("section", { class: "detail" });
    root.append(this.side, this.main, this.detailEl);
    this.renderSide();
    this.renderMain();
    this.renderDetail();
  },

  usage() {
    // счётчики использования всех боевых тегов за один проход
    const n = {};
    for (const [fk, paths] of Object.entries(COMBAT_TAG_PATHS)) {
      for (const f of filesFor(fk)) for (const o of list(f)) for (const p of paths)
        walkPath(o, p.split("/"), (v) => { n[v] = (n[v] || 0) + 1; });
    }
    return n;
  },

  renderSide() {
    const tags = list(F.tags);
    const item = (id, name, color, icon, count) => h("button", {
      class: "side-item" + (this.cat === id ? " on" : ""),
      onclick: () => { this.cat = id; this.context = id === "@ctx"; this.renderSide(); this.renderMain(); },
    }, icon ? h("img", { src: icon, alt: "" }) : h("span", { style: { width: "20px" } }),
      h("span", { style: { color } }, name), h("span", { class: "n" }, count));
    this.side.innerHTML = "";
    this.side.append(
      h("h4", null, "Боевые теги"),
      h("div", { class: "side-list" },
        item("all", "Все боевые", null, null, tags.length),
        Object.entries(CATEGORIES).map(([k, [name, color]]) => item(k, name, color, tagIcon(k), tags.filter((t) => t.category === k).length)),
        tags.some((t) => !CATEGORIES[t.category]) ? item("?", "Без категории", "#B65F63", null, tags.filter((t) => !CATEGORIES[t.category]).length) : null),
      h("h4", null, "Проверки событий"),
      h("div", { class: "side-list" }, item("@ctx", "Теги проверок", "#8FB6C9", null, list(F.ctxTags).length)),
      h("p", { class: "muted", style: { fontSize: "12px", padding: "0 6px" } },
        "Боевые теги — у карт, противников и полей в бою «Столкновение». Теги проверок — у событий и условных бонусов («в скрытности +1»)."),
    );
  },

  renderMain() {
    this.main.innerHTML = "";
    const ctx = this.cat === "@ctx";
    const q = this.query.trim().toLowerCase();
    const search = h("input", { type: "search", placeholder: "Поиск тега…", value: this.query });
    search.oninput = () => { this.query = search.value; this.renderRows(); };
    const catInfo = CATEGORIES[this.cat];
    const title = ctx ? "Теги проверок" : this.cat === "all" ? "Все боевые теги" : this.cat === "?" ? "Без категории" : catInfo[0];
    this.main.append(h("div", { class: "grid-head" },
      h("div", { class: "cat-title" }, catInfo ? h("img", { src: tagIcon(this.cat), alt: "" }) : null, h("h2", { style: { color: catInfo ? catInfo[1] : "" } }, title)),
      search,
      h("button", { class: "btn add", onclick: () => this.create() }, "+ Новый тег")));
    this.rowsEl = h("div", { class: "tag-table" });
    this.main.append(this.rowsEl);
    this.renderRows();
  },

  renderRows() {
    const ctx = this.cat === "@ctx";
    const q = this.query.trim().toLowerCase();
    this.rowsEl.innerHTML = "";
    if (ctx) {
      for (const t of list(F.ctxTags)) {
        if (q && !t.name.toLowerCase().includes(q) && !t.id.includes(q)) continue;
        const uses = tagRefs(t.id, true).length;
        this.rowsEl.append(h("button", { class: "tag-line" + (this.context && this.selected === t.id ? " on" : ""), onclick: () => this.select(t.id, true) },
          tagChip(t.id, { context: true }), h("span", { class: "val" }, t.id), h("span", { class: "txt" }, ""),
          h("span", { class: "uses" + (uses ? "" : " zero") }, uses ? uses + " исп." : "не исп.")));
      }
      return;
    }
    const usage = this.usage();
    const tags = list(F.tags).filter((t) =>
      (this.cat === "all" || t.category === this.cat || (this.cat === "?" && !CATEGORIES[t.category]))
      && (!q || t.id.toLowerCase().includes(q) || (t.text || "").toLowerCase().includes(q)));
    tags.sort((a, b) => a.id.localeCompare(b.id, "ru"));
    for (const t of tags) {
      const uses = usage[t.id] || 0;
      this.rowsEl.append(h("button", { class: "tag-line" + (!this.context && this.selected === t.id ? " on" : ""), onclick: () => this.select(t.id, false) },
        tagChip(t.id), h("span", { class: "val" }, t.value ? "+" + Math.round(t.value * 100) + "%" : "—"),
        h("span", { class: "txt", title: t.text || "" }, t.text || ""),
        h("span", { class: "uses" + (uses ? "" : " zero") }, uses ? uses + " исп." : "не исп.")));
    }
    if (!tags.length) this.rowsEl.append(h("p", { class: "muted" }, "Тегов нет"));
  },

  select(id, context) {
    this.selected = id;
    this.context = context;
    this.rowsEl.querySelectorAll(".tag-line").forEach((r) => r.classList.remove("on"));
    this.renderRows();
    this.renderDetail();
    App.params = { tag: id, context };
  },

  renderDetail() {
    const d = this.detailEl;
    d.innerHTML = "";
    const t = this.selected ? (this.context ? ctxTag(this.selected) : combatTag(this.selected)) : null;
    if (!t) {
      d.append(h("div", { class: "detail-body" }, h("div", { class: "muted", style: { margin: "auto", textAlign: "center" } },
        h("h3", null, "Выберите тег"), h("p", null, "Справа появятся его свойства, связи и все карты, где он встречается."),
        this.selected ? h("p", { class: "err" }, `Тега «${this.selected}» нет в каталоге.`) : null,
        this.selected && !this.context ? h("button", { class: "btn add", onclick: async () => { const n = await createTagDialog(this.selected); if (n) this.refreshAll(); } }, "Создать его") : null)));
      return;
    }
    if (this.context) return this.renderCtxDetail(d, t);

    const file = F.tags;
    const changed = () => { touch(file); this.renderRows(); };
    const cat = CATEGORIES[t.category];
    const nameInput = h("input", { type: "text", value: t.id, class: "title-input" });
    nameInput.onchange = () => this.rename(t, nameInput.value.trim());

    const refs = tagRefs(t.id);
    const links = this.links(t.id);

    d.append(
      h("div", { class: "detail-head" },
        h("div", { class: "head-info" },
          h("div", { class: "kind" }, h("img", { src: tagIcon(t.category), alt: "" }), h("span", { style: { color: cat ? cat[1] : "" } }, cat ? cat[0] : t.category), h("span", { class: "muted" }, "боевой тег")),
          nameInput,
          h("small", { class: "muted" }, "Смена названия переименует тег во всех картах, противниках, полях и связях."))),
      h("div", { class: "detail-body" },
        h("div", { class: "cols" },
          field("Категория", bindSelect(t, "category", Object.fromEntries(Object.entries(CATEGORIES).map(([k, v]) => [k, v[0]])), () => { changed(); this.renderSide(); this.renderDetail(); })),
          field("Сила тега", bindInput(t, "value", changed, { type: "number" }), "доля: 0.12 = +12% к силе стороны")),
        field("Описание", bindInput(t, "text", changed, { type: "textarea", rows: 4, keepEmpty: true })),
        h("div", { class: "section" }, h("h4", null, `Связи (${links.length})`),
          links.length ? h("div", { class: "refs" }, links.map((l) => h("div", { class: "link-line" },
            h("span", { class: "kind " + l.type }, l.type === "syn" ? "симбиоз" : "конфликт"),
            h("b", null, l.name), h("span", { class: "muted" }, l.text),
            h("span", { class: "chips small" }, l.others.map((o) => tagChip(o, { onClick: () => this.select(o, false) }))))))
            : h("p", { class: "muted" }, "Нет симбиозов и конфликтов с этим тегом.")),
        h("div", { class: "section" }, h("h4", null, `Где используется (${refs.length})`), this.refsList(refs))),
      h("div", { class: "detail-foot" }, h("span", { class: "grow" }), h("button", { class: "btn danger", onclick: () => this.remove(t, refs) }, "Удалить тег")));
    applyTips(d);
  },

  renderCtxDetail(d, t) {
    setTimeout(() => applyTips(d), 0);
    const changed = () => { touch(F.ctxTags); this.renderRows(); };
    const idInput = h("input", { type: "text", value: t.id });
    idInput.onchange = () => this.renameCtx(t, idInput.value.trim());
    const refs = tagRefs(t.id, true);
    d.append(
      h("div", { class: "detail-head" }, h("div", { class: "head-info" },
        h("div", { class: "kind" }, h("span", { class: "muted" }, "тег проверки")),
        bindInput(t, "name", changed, { cls: "title-input", keepEmpty: true }))),
      h("div", { class: "detail-body" },
        field("id (латиницей)", idInput, "Смена id переименует его во всех событиях и бонусах"),
        h("div", { class: "section" }, h("h4", null, `Где используется (${refs.length})`), this.refsList(refs))),
      h("div", { class: "detail-foot" }, h("span", { class: "grow" }), h("button", { class: "btn danger", onclick: () => this.remove(t, refs, true) }, "Удалить тег")));
  },

  refsList(refs) {
    if (!refs.length) return h("p", { class: "muted" }, "Нигде не используется.");
    const groups = {};
    for (const r of refs) {
      const l = refLabel(r);
      (groups[l.group] = groups[l.group] || []).push(l);
    }
    return h("div", { class: "refs" }, Object.entries(groups).map(([g, items]) => h("div", { class: "ref-group" },
      h("h5", null, `${g} · ${items.length}`),
      h("ul", null, items.map((l) => h("li", null,
        h("span", { class: "id" }, l.id),
        findCard(l.id) ? h("button", { class: "link", onclick: () => this.open(l.id) }, l.who) : h("span", null, l.who),
        h("span", { class: "where" }, l.where)))))));
  },

  open(id) {
    const c = findCard(id);
    if (!c) return;
    if (c.kind === "event") App.go("events", { select: id });
    else App.go("cards", { select: id, kind: c.kind });
  },

  links(tag) {
    const out = [];
    for (const s of list(F.synergies)) if ((s.tags || []).includes(tag))
      out.push({ type: "syn", name: s.name, text: s.text, others: s.tags.filter((x) => x !== tag) });
    for (const c of list(F.conflicts)) if (c.a === tag || c.b === tag)
      out.push({ type: "con", name: c.name, text: c.text, others: [c.a === tag ? c.b : c.a] });
    return out;
  },

  refreshAll() { this.renderSide(); this.renderMain(); this.renderDetail(); },

  async create() {
    if (this.cat === "@ctx") {
      const r = await ask("Новый тег проверки", [
        { key: "id", label: "id (латиницей, например climb)", value: "" },
        { key: "name", label: "Название", value: "" }]);
      if (!r || !r.id) return;
      if (ctxTag(r.id)) { toast("Такой id уже есть", "err"); return; }
      list(F.ctxTags).push({ id: r.id, name: r.name || r.id });
      touch(F.ctxTags);
      this.selected = r.id;
      this.context = true;
      this.refreshAll();
      return;
    }
    const name = await createTagDialog("", CATEGORIES[this.cat] ? this.cat : "state");
    if (name) { this.selected = name; this.context = false; this.refreshAll(); }
  },

  async rename(t, name) {
    if (!name || name === t.id) return;
    if (combatTag(name)) { toast(`Тег «${name}» уже существует`, "err"); this.renderDetail(); return; }
    const old = t.id;
    const n = replaceTag(old, name);
    DB.renames.push([old, name]);
    t.id = name;
    t.name = name;
    touch(F.tags);
    this.selected = name;
    toast(`«${old}» → «${name}»: обновлено ссылок: ${n}`, "ok");
    this.refreshAll();
  },

  async renameCtx(t, id) {
    if (!id || id === t.id) return;
    if (ctxTag(id)) { toast(`id «${id}» уже занят`, "err"); this.renderDetail(); return; }
    const old = t.id;
    const n = replaceTag(old, id, true);
    t.id = id;
    touch(F.ctxTags);
    this.selected = id;
    toast(`${old} → ${id}: обновлено ссылок: ${n}`, "ok");
    this.refreshAll();
  },

  async remove(t, refs, context = false) {
    const links = context ? [] : this.links(t.id);
    const body = h("div", null,
      h("p", null, `Удалить тег «${t.name || t.id}»?`),
      refs.length ? h("p", { class: "err" }, `Он будет убран из ${refs.length} мест.`) : null,
      links.length ? h("p", { class: "err" }, `Симбиозы и конфликты с ним (${links.length}) будут удалены.`) : null);
    const ok = await modal("Удаление тега", body, [{ label: "Отмена", value: false }, { label: "Удалить", danger: true, value: true }]);
    if (!ok) return;
    replaceTag(t.id, null, context);
    const file = context ? F.ctxTags : F.tags;
    DB.files[file] = list(file).filter((x) => x !== t);
    touch(file);
    this.selected = null;
    toast("Тег удалён (сохраните, чтобы применить)", "info");
    this.refreshAll();
  },
};
