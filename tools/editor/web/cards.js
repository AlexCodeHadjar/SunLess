// Экран «Карточки»: галерея всех карт и планшет выбранной карты с редактированием.
"use strict";

const LORE_ONLY = { id: "lore", name: "Задуманные (нет в игре)", emblem: "art/ui/emblems/story.png" };
const PREFIX_KIND = { P: "character", U: "enhancement", K: "enhancement", A: "ability", T: "trauma", I: "initiator", M: "enemy", H: "enemy", E: "event" };

const CardsView = {
  kind: "all", query: "", selected: null, tab: "desc", stage: null,
  showPlanned: (() => { try { return localStorage.getItem("sunless-planned") === "1"; } catch (_) { return false; } })(),

  render(root, params = {}) {
    if (params.select) { this.selected = params.select; this.stage = null; }
    if (params.kind) this.kind = params.kind;
    this.root = root;
    this.side = h("aside", { class: "side" });
    this.gridWrap = h("section", { class: "grid-wrap" });
    this.detailEl = h("section", { class: "detail" });
    root.append(this.side, this.gridWrap, this.detailEl);
    this.renderSide();
    this.renderGrid();
    this.renderDetail();
  },

  // карты для галереи (включая задуманные — только описание «По книге»)
  cards() {
    const real = allCards();
    const ids = new Set(real.map((c) => c.id));
    const loreOnly = list(F.lore).filter((l) => !ids.has(l.id))
      .map((l) => ({ kind: "lore", id: l.id, obj: { id: l.id, name: l.title }, file: null, lore: l }));
    return real.concat(loreOnly);
  },

  current() {
    return this.selected ? this.cards().find((c) => c.id === this.selected) || null : null;
  },

  renderSide() {
    const cards = this.cards();
    const count = (k) => cards.filter((c) => k === "all" ? c.kind !== "lore" : c.kind === k).length;
    const item = (id, name, emblem) => h("button", {
      class: "side-item" + (this.kind === id ? " on" : ""),
      onclick: () => { this.kind = id; this.renderSide(); this.renderGrid(); },
    }, emblem ? h("img", { src: projectUrl(emblem), alt: "" }) : h("span", { style: { width: "20px" } }), name, h("span", { class: "n" }, count(id)));
    this.side.innerHTML = "";
    this.side.append(
      h("h4", null, "Карты"),
      h("div", { class: "side-list" },
        item("all", "Все карты в игре", null),
        KINDS.map((k) => item(k.id, k.name, k.emblem)),
        item(LORE_ONLY.id, LORE_ONLY.name, LORE_ONLY.emblem)),
      h("button", { class: "btn add", onclick: () => this.createCard() }, "+ Новая карта"),
      h("button", { class: "btn", title: "Скачать JSON-файл со списком карт (в игре и задуманных), у которых ещё нет картинки", onclick: () => this.exportMissingArt() }, "⭳ Карты без картинок (JSON)"),
    );
  },

  // Категория карты для людей (у задуманных — по букве id).
  kindOf(c) {
    return c.kind === "lore" ? PREFIX_KIND[c.id[0]] || "" : c.kind;
  },

  exportMissingArt() {
    const rows = this.cards().filter((c) => !cardArt(c)).map((c) => ({
      id: c.id,
      "название": c.obj.name || c.obj.title || c.id,
      "категория": (KIND[this.kindOf(c)] || { name: "Другое" }).name,
      "в_игре": c.kind !== "lore",
    }));
    const order = KINDS.map((k) => k.name);
    rows.sort((a, b) => (order.indexOf(a["категория"]) - order.indexOf(b["категория"])) || a.id.localeCompare(b.id, undefined, { numeric: true }));
    const byCat = {};
    for (const r of rows) byCat[r["категория"]] = (byCat[r["категория"]] || 0) + 1;
    const out = { "создано": new Date().toISOString().slice(0, 10), "всего": rows.length, "по_категориям": byCat, "карты": rows };
    const blob = new Blob([JSON.stringify(out, null, 2)], { type: "application/json" });
    const a = h("a", { href: URL.createObjectURL(blob), download: "карты_без_картинок.json" });
    document.body.append(a);
    a.click();
    setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
    toast(`Выгружено карт без картинок: ${rows.length}`, "ok");
  },

  renderGrid() {
    const q = this.query.trim().toLowerCase();
    const planned = (c) => c.kind === "lore" && this.showPlanned && (this.kind === "all" || this.kindOf(c) === this.kind);
    const cards = this.cards().filter((c) => {
      if (!planned(c) && (this.kind === "all" ? c.kind === "lore" : c.kind !== this.kind)) return false;
      if (!q) return true;
      const tags = [...(c.obj.tags || []), ...Object.values(c.obj.stages || {}).flatMap((s) => s.tags || [])];
      return c.id.toLowerCase().includes(q) || (c.obj.name || c.obj.title || "").toLowerCase().includes(q)
        || tags.some((t) => t.toLowerCase().includes(q));
    });
    const title = this.kind === "all" ? "Все карты" : this.kind === "lore" ? LORE_ONLY.name : KIND[this.kind].name;
    const search = h("input", { type: "search", placeholder: "Поиск: имя, id, тег…", value: this.query });
    search.oninput = () => { this.query = search.value; this.renderTiles(); };
    this.gridWrap.innerHTML = "";
    this.tilesEl = h("div", { class: "grid" });
    let toggle = null;
    if (this.kind !== "lore") {
      const nPlanned = this.cards().filter((c) => c.kind === "lore" && (this.kind === "all" || this.kindOf(c) === this.kind)).length;
      const cb = h("input", { type: "checkbox", checked: this.showPlanned });
      cb.onchange = () => {
        this.showPlanned = cb.checked;
        try { localStorage.setItem("sunless-planned", cb.checked ? "1" : "0"); } catch (_) { /* нет хранилища */ }
        this.renderGrid();
      };
      toggle = h("label", { class: "toggle", "data-tip": "Показать карты этой категории, которые описаны в документах («По книге»), но ещё не добавлены в игру. Они отмечены пунктиром; в планшете есть кнопка «Добавить в игру»." },
        cb, `ещё не добавленные в сюжет (${nPlanned})`);
    }
    this.gridWrap.append(h("div", { class: "grid-head" }, h("h2", null, title), h("span", { class: "count" }, cards.length), toggle, search), this.tilesEl);
    this.renderTiles(cards);
  },

  renderTiles(cards) {
    if (!cards) { this.renderGrid(); return; }
    this.tilesEl.innerHTML = "";
    for (const c of cards) this.tilesEl.append(this.tile(c));
  },

  tile(c) {
    const art = cardArt(c);
    const rar = RARITY[c.obj.rarity];
    const kindName = c.kind === "lore" ? ((KIND[this.kindOf(c)] || {}).name || "замысел") + " · замысел" : (KIND[c.kind] || {}).name;
    const sub = c.kind === "event" ? (EVENT_TYPES[c.obj.type] || c.obj.type) : kindName;
    const el = h("button", { class: "tile" + (c.id === this.selected ? " on" : "") + (c.kind === "lore" ? " planned" : ""), "data-id": c.id, onclick: () => this.select(c.id) },
      h("div", { class: "tile-art", style: { "--r": rar ? rar[1] : "#6A6F85" } },
        art ? h("img", { class: "art", src: art, loading: "lazy", alt: "" })
          : h("div", { class: "blank" }, h("img", { src: projectUrl((KIND[c.kind] || LORE_ONLY).emblem), alt: "" }), c.obj.name || c.obj.title || c.id),
        h("span", { class: "badge" }, c.id),
        DB.images.has(c.id) ? h("span", { class: "pending" }, "новая") : null,
        c.kind === "lore" ? h("span", { class: "planned-badge" }, "не в игре") : null),
      h("div", { class: "tile-name" }, c.obj.name || c.obj.title || c.id),
      h("div", { class: "tile-sub" }, sub));
    return el;
  },

  updateTile(id) {
    const old = this.tilesEl && this.tilesEl.querySelector(`[data-id="${CSS.escape(id)}"]`);
    const c = this.cards().find((x) => x.id === id);
    if (old && c) old.replaceWith(this.tile(c));
  },

  select(id) {
    this.selected = id;
    this.stage = null;
    this.tilesEl.querySelectorAll(".tile").forEach((t) => t.classList.toggle("on", t.dataset.id === id));
    this.renderDetail();
    App.params = { select: id, kind: this.kind };
  },

  // ---- планшет карты ----------------------------------------------------------

  renderDetail() {
    const d = this.detailEl;
    d.innerHTML = "";
    const c = this.current();
    if (!c) {
      d.append(h("div", { class: "detail-body" }, h("div", { class: "muted", style: { margin: "auto", textAlign: "center" } },
        h("h3", null, "Выберите карту"), h("p", null, "Щелчок по карте откроет её полное описание и инструменты правки."))));
      return;
    }
    const changed = () => { if (c.file) touch(c.file); this.updateTile(c.id); };
    const loreChanged = () => { touch(F.lore); };

    // картинка
    const art = cardArt(c);
    const artBox = h("div", { class: "big-art", title: "Щелчок или перетащите файл — сменить картинку" },
      art ? h("img", { class: "art", src: art, alt: "" }) : h("div", { class: "muted" }, "нет картинки"),
      h("div", { class: "hint" }, "Сменить картинку"));
    const refresh = () => { this.renderDetail(); this.updateTile(c.id); };
    if (c.kind === "lore") {
      artBox.onclick = () => toast("Сначала добавьте карту в игру — тогда можно задать картинку", "warn");
    } else {
      artBox.onclick = () => pickImage(c, refresh);
      artBox.ondragover = (e) => { e.preventDefault(); artBox.classList.add("drop"); };
      artBox.ondragleave = () => artBox.classList.remove("drop");
      artBox.ondrop = (e) => { e.preventDefault(); artBox.classList.remove("drop"); const f = e.dataTransfer.files[0]; if (f) setImage(c, f, refresh); };
    }

    const kindInfo = KIND[c.kind] || LORE_ONLY;
    const nameKey = c.kind === "event" ? "title" : "name";
    const head = h("div", { class: "head-info" },
      h("div", { class: "kind" }, h("img", { src: projectUrl(kindInfo.emblem), alt: "" }), kindInfo.name, h("span", { class: "id" }, c.id),
        c.file ? h("span", { class: "muted" }, c.file) : null),
      c.kind === "lore"
        ? h("h2", { style: { fontSize: "30px" } }, c.lore.title)
        : bindInput(c.obj, nameKey, changed, { cls: "title-input", keepEmpty: true }),
      c.kind === "lore" ? h("div", { class: "row" },
        h("span", { class: "muted" }, "Этой карты ещё нет в данных игры — есть только описание «По книге»."),
        PREFIX_KIND[c.id[0]] && PREFIX_KIND[c.id[0]] !== "event" ? h("button", { class: "btn add", onclick: () => this.addLoreToGame(c) }, "Добавить в игру") : null) : null,
      c.kind !== "lore" && c.kind !== "event" ? h("div", { class: "row" },
        ("rarity" in c.obj || ["character", "enhancement"].includes(c.kind)) ? field("Редкость", bindSelect(c.obj, "rarity", Object.fromEntries(Object.entries(RARITY).map(([k, v]) => [k, v[0]])), () => { changed(); }, { allowEmpty: true })) : null,
        c.kind !== "event" && c.kind !== "trauma" && c.kind !== "ability" && c.kind !== "initiator" ? field("Картинка", h("label", { class: "field inline" },
          bindInput(c.obj, "art_has_frame", changed, { type: "checkbox" }), h("span", null, "уже с рамкой и названием"))) : null) : null,
      c.kind === "event" ? h("div", { class: "row" },
        h("span", null, h("span", { class: "type-dot", style: { background: EVENT_COLORS[c.obj.type] || "#888" } }), EVENT_TYPES[c.obj.type] || c.obj.type),
        h("button", { class: "btn small", onclick: () => App.go("events", { select: c.id }) }, "Открыть в древе событий →")) : null,
    );

    const tabs = [["desc", "Описание"], ["lore", "Сюжет (По книге)"], ["json", "JSON"]].filter(([t]) => !(c.kind === "lore" && t !== "lore"));
    if (!tabs.some(([t]) => t === this.tab)) this.tab = tabs[0][0];
    const tabBar = h("div", { class: "detail-tabs" }, tabs.map(([t, label]) =>
      h("button", { class: this.tab === t ? "on" : "", onclick: () => { this.tab = t; this.renderDetail(); } }, label)));

    const body = h("div", { class: "detail-body" });
    if (this.tab === "desc") this.descTab(body, c, changed);
    else if (this.tab === "lore") this.loreTab(body, c, loreChanged);
    else body.append(jsonEditor(c.obj, (v) => {
      const arr = list(c.file);
      const i = arr.indexOf(c.obj);
      if (v.id !== c.id) { toast("id менять здесь нельзя — используйте «Сменить id»", "err"); return; }
      arr[i] = v;
      touch(c.file);
      this.renderDetail();
      this.updateTile(c.id);
    }));

    const foot = c.kind === "lore" ? null : h("div", { class: "detail-foot" },
      h("button", { class: "btn", onclick: () => this.duplicate(c) }, "Дублировать"),
      h("button", { class: "btn", onclick: () => this.renameId(c) }, "Сменить id"),
      h("span", { class: "grow" }),
      h("button", { class: "btn danger", onclick: () => this.remove(c) }, "Удалить карту"));

    d.append(h("div", { class: "detail-head" }, artBox, head), tabBar, body, foot);
    applyTips(d);
  },

  // --- вкладка «Описание»: поля по типу карты ----------------------------------------
  descTab(body, c, changed) {
    const o = c.obj;
    const handled = new Set(["id", "name", "title", "art", "art_has_frame", "rarity"]);
    const sec = (title, ...kids) => h("div", { class: "section" }, h("h4", null, title), ...kids);
    const use = (...keys) => keys.forEach((k) => handled.add(k));

    if (c.kind === "character") {
      use("role", "status", "source", "rank", "stages", "start_stage", "stats", "tags", "support_tags", "traits", "start_abilities");
      body.append(h("div", { class: "cols" },
        field("Роль", bindInput(o, "role", changed)),
        field("Статус", bindSelect(o, "status", { playable: "Играбельный", temporary: "Временный спутник" }, changed, { allowEmpty: true })),
        field("Ранг", bindInput(o, "rank", changed, { type: "number" })),
        field("Источник", bindInput(o, "source", changed))));
      if (o.stages && Object.keys(o.stages).length) body.append(this.stagesSection(o, changed));
      else {
        o.stats = o.stats || {};
        o.tags = o.tags || [];
        body.append(sec("Характеристики", statsEditor(o.stats, changed)),
          sec("Боевые теги", tagRow(o.tags, changed)));
      }
      o.support_tags = o.support_tags || [];
      const sup = tagRow(o.support_tags, () => { if (!o.support_tags.length) delete o.support_tags; changed(); });
      body.append(sec("Теги поддержки (в бою союзником)", sup));
      if (!o.support_tags.length) delete o.support_tags;
      body.append(this.traitsSection(o, changed));
      body.append(sec("Стартовые способности", field("id способностей", listInput(o, "start_abilities", changed, "A01, A02"))));
    }

    if (c.kind === "enhancement") {
      use("text", "bonuses", "tags", "origin", "wears", "wear_exempt_arcs", "canon", "source", "soften_first_physical");
      body.append(sec("Описание на карте", bindInput(o, "text", changed, { type: "textarea", rows: 3, keepEmpty: true })));
      body.append(this.bonusSection("Бонусы к характеристикам", o, "bonuses", changed));
      o.tags = o.tags || [];
      body.append(sec("Боевые теги", tagRow(o.tags, changed)));
      body.append(sec("Свойства", h("div", { class: "cols" },
        field("Происхождение", bindSelect(o, "origin", { improvised: "Подручное", knowledge: "Знание", memory: "Воспоминание" }, changed, { allowEmpty: true })),
        field("Канон", bindSelect(o, "canon", ["канон", "адаптация"], changed, { allowEmpty: true })),
        field("Источник", bindInput(o, "source", changed)),
        field("Не изнашивается в арках", listInput(o, "wear_exempt_arcs", changed, "nightmare")),
        h("label", { class: "field inline" }, bindInput(o, "wears", changed, { type: "checkbox" }), h("span", null, "изнашивается")),
        h("label", { class: "field inline" }, bindInput(o, "soften_first_physical", changed, { type: "checkbox" }), h("span", null, "смягчает первую физ. травму")))));
    }

    if (c.kind === "ability") {
      use("text", "owner", "bonuses", "modes", "reveal", "soften_physical");
      body.append(sec("Описание на карте", bindInput(o, "text", changed, { type: "textarea", rows: 3, keepEmpty: true })));
      body.append(h("div", { class: "cols" },
        field("Владелец", idSelect(o, "owner", ["character"], changed)),
        field("Раскрывает вариантов", bindInput(o, "reveal", changed, { type: "number" })),
        h("label", { class: "field inline" }, bindInput(o, "soften_physical", changed, { type: "checkbox" }), h("span", null, "смягчает физические травмы"))));
      body.append(this.bonusSection("Постоянные бонусы", o, "bonuses", changed));
      body.append(this.modesSection(o, changed));
    }

    if (c.kind === "trauma") {
      use("short", "mods", "category", "severity", "random", "context_tag");
      o.mods = o.mods || {};
      body.append(h("div", { class: "cols" },
        field("Короткое имя", bindInput(o, "short", changed)),
        field("Категория", bindSelect(o, "category", { physical: "Физическая", environment: "Среда", mental: "Ментальная" }, changed)),
        field("Тяжесть", bindSelect(o, "severity", { light: "Лёгкая", heavy: "Тяжёлая", critical: "Критическая" }, changed)),
        field("Действует только в", bindSelect(o, "context_tag", Object.fromEntries(list(F.ctxTags).map((t) => [t.id, t.name])), changed, { allowEmpty: true, emptyLabel: "везде" })),
        h("label", { class: "field inline" }, bindInput(o, "random", changed, { type: "checkbox" }), h("span", null, "в случайном пуле"))));
      body.append(sec("Штраф к характеристикам", statsEditor(o.mods, changed, { signed: true })));
    }

    if (c.kind === "initiator") {
      use("text", "event");
      body.append(sec("Описание на карте", bindInput(o, "text", changed, { type: "textarea", rows: 3, keepEmpty: true })));
      body.append(field("Создаёт событие", idSelect(o, "event", ["event"], changed)));
    }

    if (c.kind === "enemy") {
      use("rank", "class", "kind", "human", "trauma_pool", "shards", "tags", "echo");
      body.append(sec("Характеристики", h("div", { class: "cols" },
        field("Ранг", bindInput(o, "rank", changed, { type: "number" }), "×1.6 за ранг"),
        field("Класс", bindInput(o, "class", changed, { type: "number" }), "×1.0…×2.5"),
        field("Вид", bindSelect(o, "kind", { normal: "Обычный", elite: "Элита", boss: "Босс" }, changed)),
        field("Осколки душ за победу", bindInput(o, "shards", changed, { type: "number" })),
        field("Пул травм", bindSelect(o, "trauma_pool", POOLS, changed)),
        h("label", { class: "field inline" }, bindInput(o, "human", changed, { type: "checkbox" }), h("span", null, "человек")))));
      o.tags = o.tags || [];
      body.append(sec("Боевые теги", tagRow(o.tags, changed)));
      const echo = o.echo || {};
      const echoChanged = () => { if (echo.card) o.echo = echo; else delete o.echo; changed(); };
      body.append(sec("Эхо (добыча)", h("div", { class: "cols" },
        field("Карта", idSelect(echo, "card", ["enhancement", "character"], echoChanged)),
        field("Шанс (0–1)", bindInput(echo, "chance", echoChanged, { type: "number" })))));
    }

    if (c.kind === "event") {
      use("text", "type", "tags", "source");
      body.append(sec("Текст события", bindInput(o, "text", changed, { type: "textarea", rows: 5, keepEmpty: true })));
      body.append(field("Источник", bindInput(o, "source", changed)));
      o.tags = o.tags || [];
      body.append(sec("Теги проверки", tagRow(o.tags, changed, { context: true })));
      body.append(h("p", { class: "muted" }, "Варианты выбора, последствия и связи с другими событиями — во вкладке «Древо событий»."));
      use("options", "next", "next_immediate", "on_appear", "on_success_common", "numeral", "arc", "region", "chapter", "node",
        "trauma_pool", "map_pos", "source_kind", "once", "enemy", "danger");
    }

    // тип карт, найденный в коде игры автоматически: общая форма по тому, что есть в карте
    if (KIND[c.kind] && KIND[c.kind].auto) {
      use("text", "tags", "stats", "bonuses");
      if ("text" in o) body.append(sec("Описание на карте", bindInput(o, "text", changed, { type: "textarea", rows: 3, keepEmpty: true })));
      if (o.stats && typeof o.stats === "object") body.append(sec("Характеристики", statsEditor(o.stats, changed)));
      if (Array.isArray(o.bonuses)) body.append(this.bonusSection("Бонусы к характеристикам", o, "bonuses", changed));
      if (Array.isArray(o.tags)) body.append(sec("Боевые теги", tagRow(o.tags, changed)));
      body.append(h("p", { class: "muted" }, "Этот тип карт найден в коде игры автоматически (Content.card_kind). Редкие поля — ниже и во вкладке JSON."));
    }

    body.append(this.extraFields(o, handled, changed));
  },

  stagesSection(o, changed) {
    const stages = o.stages;
    const keys = Object.keys(stages);
    if (!this.stage || !stages[this.stage]) this.stage = o.start_stage && stages[o.start_stage] ? o.start_stage : keys[0];
    const st = stages[this.stage];
    st.stats = st.stats || {};
    st.tags = st.tags || [];
    const wrap = h("div", { class: "section" },
      h("h4", null, "Стадии", h("button", { class: "btn small add", onclick: async () => {
        const r = await ask("Новая стадия", [{ key: "id", label: "id (латиницей)", value: "" }, { key: "name", label: "Название", value: "" }]);
        if (!r || !r.id || stages[r.id]) return;
        stages[r.id] = { name: r.name || r.id, stats: clone(st.stats), tags: clone(st.tags) };
        this.stage = r.id;
        changed();
        this.renderDetail();
      } }, "+ стадия")),
      h("div", { class: "stage-tabs" }, keys.map((k) => h("button", {
        class: k === this.stage ? "on" : "", onclick: () => { this.stage = k; this.renderDetail(); },
      }, stages[k].name || k, k === o.start_stage ? " ★" : ""))),
      h("div", { class: "sub-card" },
        h("div", { class: "row" },
          field("Название стадии", bindInput(st, "name", changed)),
          field("Ранг", bindInput(st, "rank", changed, { type: "number" })),
          h("span", { class: "grow" }),
          h("label", { class: "field inline" }, h("input", { type: "radio", name: "start", checked: o.start_stage === this.stage, onchange: () => { o.start_stage = this.stage; changed(); this.renderDetail(); } }), h("span", null, "стартовая")),
          keys.length > 1 ? h("button", { class: "btn small danger", onclick: async () => {
            if (!(await confirmBox("Удалить стадию", `Удалить стадию «${st.name || this.stage}»?`))) return;
            delete stages[this.stage];
            if (o.start_stage === this.stage) o.start_stage = Object.keys(stages)[0];
            this.stage = null;
            changed();
            this.renderDetail();
          } }, "Удалить стадию") : null),
        h("div", { class: "mini-h" }, "Характеристики"), statsEditor(st.stats, changed),
        h("div", { class: "mini-h" }, "Боевые теги"), tagRow(st.tags, changed)));
    return wrap;
  },

  traitsSection(o, changed) {
    o.traits = o.traits || [];
    const box = h("div", { class: "section" }, h("h4", null, "Черты", h("button", { class: "btn small add", onclick: () => {
      o.traits.push({ name: "Новая черта", text: "", bonuses: [] });
      changed();
      this.renderDetail();
    } }, "+ черта")));
    o.traits.forEach((t, i) => {
      box.append(h("div", { class: "sub-card" },
        h("div", { class: "row" }, bindInput(t, "name", changed, { keepEmpty: true }),
          h("button", { class: "icon-btn del", title: "Удалить черту", onclick: () => { o.traits.splice(i, 1); changed(); this.renderDetail(); } }, "×")),
        bindInput(t, "text", changed, { type: "textarea", rows: 2, keepEmpty: true }),
        this.bonusRows(t, "bonuses", changed)));
    });
    return box;
  },

  bonusSection(title, o, key, changed) {
    return h("div", { class: "section" }, h("h4", null, title), this.bonusRows(o, key, changed));
  },

  // Бонусы: [{stat, value, tags:[контекст]}]
  bonusRows(o, key, changed) {
    o[key] = o[key] || [];
    const box = h("div", { class: "effects" });
    const render = () => {
      box.innerHTML = "";
      o[key].forEach((b, i) => {
        b.tags = b.tags || [];
        box.append(h("div", { class: "bonus-row" },
          bindSelect(b, "stat", STAT_NAMES, changed),
          bindInput(b, "value", changed, { type: "number" }),
          tagRow(b.tags, changed, { context: true, small: true }),
          h("button", { class: "icon-btn del", title: "Удалить бонус", onclick: () => { o[key].splice(i, 1); changed(); render(); } }, "×")));
      });
      box.append(h("div", null, h("button", { class: "btn small add", onclick: () => { o[key].push({ stat: "power", value: 1, tags: [] }); changed(); render(); } }, "+ бонус"),
        o[key].length ? h("span", { class: "muted", style: { marginLeft: "10px", fontSize: "12px" } }, "теги справа — в каких проверках действует (пусто — всегда)") : null));
    };
    render();
    return box;
  },

  modesSection(o, changed) {
    o.modes = o.modes || [];
    const box = h("div", { class: "section" }, h("h4", null, "Режимы (игрок выбирает один)"));
    const rows = h("div", { class: "effects" });
    const render = () => {
      rows.innerHTML = "";
      o.modes.forEach((m, i) => rows.append(h("div", { class: "bonus-row" },
        bindSelect(m, "stat", STAT_NAMES, changed), bindInput(m, "value", changed, { type: "number" }), h("span"),
        h("button", { class: "icon-btn del", onclick: () => { o.modes.splice(i, 1); if (!o.modes.length) delete o.modes; changed(); render(); } }, "×"))));
      rows.append(h("div", null, h("button", { class: "btn small add", onclick: () => { o.modes = o.modes || []; o.modes.push({ stat: "power", value: 2 }); changed(); render(); } }, "+ режим")));
    };
    render();
    if (!o.modes.length) delete o.modes;
    box.append(rows);
    return box;
  },

  // Простые поля, которых нет в форме (строки, числа, флаги) — чтобы ничего не пряталось.
  extraFields(o, handled, changed) {
    const keys = Object.keys(o).filter((k) => !handled.has(k));
    if (!keys.length) return h("span");
    const cols = h("div", { class: "cols" });
    for (const k of keys) {
      const v = o[k];
      if (typeof v === "boolean") cols.append(h("label", { class: "field inline" }, bindInput(o, k, changed, { type: "checkbox" }), h("span", null, k)));
      else if (typeof v === "number") cols.append(field(k, bindInput(o, k, changed, { type: "number" })));
      else if (typeof v === "string") cols.append(field(k, bindInput(o, k, changed, { keepEmpty: true })));
      else cols.append(field(k, h("code", { class: "muted" }, JSON.stringify(v).slice(0, 80)), "правка во вкладке JSON"));
    }
    return h("div", { class: "section" }, h("h4", null, "Прочие поля"), cols);
  },

  // --- вкладка «Сюжет (По книге)» ------------------------------------------------------
  loreTab(body, c, changed) {
    let l = c.lore || lore(c.id);
    if (!l) {
      body.append(h("div", { class: "section" },
        h("p", { class: "muted" }, "У этой карты нет развёрнутого описания «По книге»."),
        h("button", { class: "btn add", onclick: () => {
          list(F.lore).push({ id: c.id, title: c.obj.name || c.obj.title || c.id, text: "", source: c.obj.source || "", extra: "", adaptation: false, edited: true });
          list(F.lore).sort((a, b) => a.id.localeCompare(b.id));
          changed();
          this.renderDetail();
        } }, "+ Создать описание")));
      return;
    }
    const ch = () => { l.edited = true; changed(); };
    body.append(
      field("Заголовок", bindInput(l, "title", ch, { keepEmpty: true })),
      field("Описание по книге", bindInput(l, "text", ch, { type: "textarea", rows: 12, keepEmpty: true, cls: "lore-text" })),
      h("div", { class: "cols" },
        field("Источник", bindInput(l, "source", ch, { keepEmpty: true })),
        field("Дополнительно", bindInput(l, "extra", ch, { keepEmpty: true })),
        h("label", { class: "field inline" }, bindInput(l, "adaptation", ch, { type: "checkbox", keepEmpty: true }), h("span", null, "адаптация (не канон)"))),
      h("p", { class: "muted" }, "Показывается в игре в планшете карты, вкладка «Сюжет». Правки помечаются, и генератор tools/gen_lore.py их не затирает."));
  },

  // --- создание, копирование, удаление -----------------------------------------------------
  nextId(prefix) {
    let max = 0;
    for (const c of this.cards()) {
      const m = c.id.match(new RegExp("^" + prefix + "(\\d+)$"));
      if (m) max = Math.max(max, Number(m[1]));
    }
    return prefix + String(max + 1).padStart(2, "0");
  },

  template(kind, id, name) {
    switch (kind) {
      case "character": return { id, name, status: "playable", rarity: "common", role: "", stats: { power: 3, will: 3, cunning: 3 }, traits: [], tags: [] };
      case "enhancement": return { id, name, origin: "improvised", rarity: "common", wears: true, bonuses: [], text: "", tags: [] };
      case "ability": return { id, name, owner: "P01", bonuses: [], text: "" };
      case "trauma": return { id, name, short: name, mods: { power: -1 }, category: "physical", severity: "light", random: true };
      case "initiator": return { id, name, event: "", text: "" };
      case "enemy": return { id, name, rank: 0, class: 1, tags: [], kind: "normal", trauma_pool: "physical", shards: 1 };
    }
    // новый тип карт: берём набор полей у первой карты этого типа
    const sample = (list((KIND[kind] || {}).file || "")[0]) || {};
    const blank = (v) => Array.isArray(v) ? [] : v && typeof v === "object" ? {} : typeof v === "number" ? 0 : typeof v === "boolean" ? false : "";
    return Object.assign(Object.fromEntries(Object.entries(sample).map(([k, v]) => [k, blank(v)])), { id, name });
  },

  async createCard() {
    const kinds = Object.fromEntries(KINDS.filter((k) => k.id !== "event").map((k) => [k.id, k.name]));
    const start = kinds[this.kind] ? this.kind : "enhancement";
    const r = await ask("Новая карта", [
      { key: "kind", label: "Тип", type: "select", value: start, options: kinds },
      { key: "id", label: "id", value: "", hint: "Пусто — следующий свободный (P…, U…, A…, T…, I…, M…)" },
      { key: "name", label: "Название", value: "" },
    ]);
    if (!r) return;
    const id = r.id || this.nextId(KIND[r.kind].prefix);
    if (findCard(id)) { toast(`id ${id} уже занят`, "err"); return; }
    list(KIND[r.kind].file).push(this.template(r.kind, id, r.name || id));
    touch(KIND[r.kind].file);
    this.kind = r.kind;
    this.selected = id;
    this.renderSide();
    this.renderGrid();
    this.renderDetail();
  },

  addLoreToGame(c) {
    const kind = PREFIX_KIND[c.id[0]];
    const obj = this.template(kind, c.id, c.lore.title);
    if (c.lore.source) obj.source = c.lore.source;
    list(KIND[kind].file).push(obj);
    touch(KIND[kind].file);
    this.kind = kind;
    this.renderSide();
    this.renderGrid();
    this.renderDetail();
    toast(`${c.id} добавлена в ${KIND[kind].file}`, "ok");
  },

  async duplicate(c) {
    if (c.kind === "event") { App.go("events", { select: c.id }); toast("События копируются в древе событий", "info"); return; }
    const r = await ask("Копия карты", [{ key: "id", label: "Новый id", value: this.nextId(c.id.replace(/\d+$/, "")) }]);
    if (!r || !r.id) return;
    if (findCard(r.id)) { toast(`id ${r.id} уже занят`, "err"); return; }
    const copy = clone(c.obj);
    copy.id = r.id;
    delete copy.art;
    const arr = list(c.file);
    arr.splice(arr.indexOf(c.obj) + 1, 0, copy);
    touch(c.file);
    this.selected = r.id;
    this.renderSide();
    this.renderGrid();
    this.renderDetail();
  },

  async renameId(c) {
    const r = await ask("Сменить id", [{ key: "id", label: "Новый id", value: c.id, hint: "Все ссылки на карту в данных тоже будут переименованы" }]);
    if (!r || !r.id || r.id === c.id) return;
    if (findCard(r.id)) { toast(`id ${r.id} уже занят`, "err"); return; }
    renameIdEverywhere(c.id, r.id);
    this.selected = r.id;
    this.renderGrid();
    this.renderDetail();
  },

  async remove(c) {
    const refs = idRefs(c.id).filter((x) => x.obj !== c.obj);
    const body = h("div", null, h("p", null, `Удалить «${c.obj.name || c.obj.title}» (${c.id}) из ${c.file}?`),
      refs.length ? h("div", null, h("p", { class: "err" }, `На карту ссылаются ${refs.length} мест — они станут ошибками, пока их не исправить:`),
        h("ul", { class: "issues" }, refs.slice(0, 20).map((x) => h("li", null, `${x.obj.id} (${x.file}) › ${x.path}`)))) : null,
      h("p", { class: "muted" }, "Файл картинки останется на месте; до сохранения всё можно вернуть кнопкой обновления страницы."));
    const ok = await modal("Удаление карты", body, [{ label: "Отмена", value: false }, { label: "Удалить", danger: true, value: true }]);
    if (!ok) return;
    const arr = list(c.file);
    arr.splice(arr.indexOf(c.obj), 1);
    touch(c.file);
    DB.images.delete(c.id);
    this.selected = null;
    this.renderSide();
    this.renderGrid();
    this.renderDetail();
    toast(`${c.id} удалена (сохраните, чтобы применить)`, "info");
  },
};

const EVENT_COLORS = { story: "#B89A5E", reward: "#6FA47B", side: "#6F8FD8", random: "#8A6BB8" };

// Переименовывает id карты/события во всех данных (включая описания «По книге» и ожидающие картинки).
function renameIdEverywhere(oldId, newId) {
  const card = findCard(oldId);
  // картинка находилась по id — закрепляем путь явно, чтобы она не потерялась
  if (card && !card.obj.art && !DB.images.has(oldId)) {
    const found = ["webp", "png", "jpg"].map((e) => `art/cards/${oldId}.${e}`).find((p) => DB.art.has(p));
    if (found) card.obj.art = "res://" + found;
  }
  const fix = (node) => {
    if (Array.isArray(node)) {
      node.forEach((v, i) => { if (v === oldId) node[i] = newId; else if (v && typeof v === "object") fix(v); });
    } else if (node && typeof node === "object") {
      for (const [k, v] of Object.entries(node)) {
        if (v === oldId) node[k] = newId;
        else if (v && typeof v === "object") fix(v);
      }
      // варианты события: E01_1 → NEW_1
      if (node.id === newId && Array.isArray(node.options)) {
        for (const op of node.options) if (typeof op.id === "string" && op.id.startsWith(oldId + "_")) op.id = newId + op.id.slice(oldId.length);
      }
    }
  };
  for (const [rel, arr] of Object.entries(DB.files)) {
    if (!Array.isArray(arr)) continue;
    const before = JSON.stringify(arr);
    fix(arr);
    if (JSON.stringify(arr) !== before) touch(rel);
  }
  if (DB.layout[oldId]) { DB.layout[newId] = DB.layout[oldId]; delete DB.layout[oldId]; DB.layoutDirty = true; }
  const im = DB.images.get(oldId);
  if (im) {
    DB.images.delete(oldId);
    im.name = newId + im.name.slice(oldId.length);
    DB.images.set(newId, im);
    const c2 = findCard(newId);
    if (c2) c2.obj.art = "res://art/cards/" + im.name;
  }
}
