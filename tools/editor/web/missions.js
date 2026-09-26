// Экран «Миссии» (ветка gameplay/missions, docs/15): локации, миссии, действия и этапы,
// справа — как миссию увидит игрок.
"use strict";

const MISSION_TYPES = { story: "Сюжетная", side: "Побочная", random: "Случайная" };
const THREAT_WORDS = ["", "Пустяк", "Неприятно", "Опасно", "Очень опасно", "Смертельно"];

const MissionsView = {
  selected: null, locSel: null, shopSel: null, page: "brief", actIdx: 0,

  render(root, params = {}) {
    if (params.select) { this.selected = params.select; this.locSel = null; this.shopSel = null; }
    this.side = h("aside", { class: "side ms-side" });
    this.main = h("section", { class: "detail ms-main" });
    this.preview = h("section", { class: "ms-preview" });
    root.append(this.side, this.main, this.preview);
    this.renderSide();
    this.renderMain();
  },

  missions() {
    const out = [];
    for (const f of missionFiles()) for (const m of list(f)) out.push({ m, file: f });
    return out;
  },
  rec(id) { return this.missions().find((r) => r.m.id === id) || null; },

  renderSide() {
    const S = this.side;
    S.innerHTML = "";
    const byLoc = {};
    for (const r of this.missions()) (byLoc[r.m.location] = byLoc[r.m.location] || []).push(r);
    const locs = list(F.locations);
    S.append(h("h4", null, "Локации и миссии"));
    const box = h("div", { class: "side-list" });
    for (const loc of locs) {
      box.append(h("button", { class: "side-item ms-loc" + (this.locSel === loc.id ? " on" : ""), onclick: () => { this.locSel = loc.id; this.selected = null; this.shopSel = null; this.renderSide(); this.renderMain(); } },
        h("span", { class: "pin-dot" }), loc.name, h("span", { class: "n" }, (byLoc[loc.id] || []).length)));
      for (const r of byLoc[loc.id] || []) box.append(this.missionItem(r));
    }
    const orphans = this.missions().filter((r) => !locs.some((l) => l.id === r.m.location));
    if (orphans.length) {
      box.append(h("div", { class: "muted ms-orphan" }, "Без локации"));
      orphans.forEach((r) => box.append(this.missionItem(r)));
    }
    box.append(h("div", { class: "muted ms-orphan" }, "Магазины"));
    for (const sh of list(F.shops)) {
      box.append(h("button", { class: "side-item ms-loc" + (this.shopSel === sh.id ? " on" : ""), onclick: () => { this.shopSel = sh.id; this.locSel = null; this.selected = null; this.renderSide(); this.renderMain(); } },
        h("span", { class: "pin-dot", style: { background: "#B9A7E6" } }), sh.name || sh.id, h("span", { class: "n", title: "Карт в ассортименте" }, (sh.stock || []).length)));
    }
    S.append(box,
      h("button", { class: "btn add", onclick: () => this.createMission() }, "+ Миссия"),
      h("button", { class: "btn", onclick: () => this.createLocation() }, "+ Локация"),
      h("button", { class: "btn", onclick: () => this.createShop() }, "+ Магазин"),
      h("p", { class: "muted", style: { fontSize: "12px", padding: "0 6px" } }, "Новая механика из ветки gameplay/missions: локации, отряды, действия после прибытия. См. docs/15."));
  },

  missionItem(r) {
    const m = r.m;
    return h("button", { class: "side-item ms-item" + (this.selected === m.id ? " on" : ""), onclick: () => this.select(m.id) },
      h("span", { class: "type-dot", style: { background: m.type === "story" ? "#B89A5E" : m.type === "side" ? "#6F8FD8" : "#8A6BB8" } }),
      h("span", { class: "ms-item-t" }, m.title || m.id), m.start ? h("span", { class: "n", title: "Доступна с начала главы" }, "старт") : null);
  },

  select(id) {
    this.selected = id;
    this.locSel = null;
    this.shopSel = null;
    this.actIdx = 0;
    App.params = { select: id };
    this.renderSide();
    this.renderMain();
  },

  // ---- основная панель ---------------------------------------------------------------
  renderMain() {
    const M = this.main;
    M.innerHTML = "";
    if (this.locSel) { this.renderLocation(M, byId(F.locations, this.locSel)); this.renderPreview(null); return; }
    if (this.shopSel) { this.renderShop(M, byId(F.shops, this.shopSel)); this.renderPreview(null); return; }
    const r = this.selected && this.rec(this.selected);
    if (!r) {
      M.append(h("div", { class: "detail-body" }, h("div", { class: "muted", style: { margin: "auto", textAlign: "center", maxWidth: "440px" } },
        h("h3", null, "Выберите миссию"),
        h("p", null, "Слева — локации глав и их миссии. Миссия: описание со слухами-намёками, разведданные, места в отряде, действия после прибытия и этапы."))));
      this.renderPreview(null);
      return;
    }
    const { m, file } = r;
    const changed = () => { touch(file); this.renderPreview(m); this.refreshSideItem(m); };
    const structural = () => { touch(file); this.renderMain(); this.renderSide(); };

    const title = bindInput(m, "title", changed, { cls: "title-input", keepEmpty: true });
    title.dataset.tip = TIPS["Название миссии"];
    const head = h("div", { class: "detail-head" }, h("div", { class: "head-info" },
      h("div", { class: "kind" }, h("span", { class: "type-dot", style: { background: m.type === "story" ? "#B89A5E" : "#6F8FD8" } }), MISSION_TYPES[m.type] || m.type,
        h("span", { class: "muted" }, "· " + ((byId(F.locations, m.location) || {}).name || "без локации"))),
      title));
    const pages = [["brief", "Описание"], ["intel", "Разведка и отряд"], ["actions", `Действия (${(m.actions || []).length})`], ["links", "Связи"]];
    const tabs = h("div", { class: "detail-tabs" }, pages.map(([p, label]) =>
      h("button", { class: this.page === p ? "on" : "", onclick: () => { this.page = p; this.renderMain(); } }, label)));
    const body = h("div", { class: "detail-body" });
    if (this.page === "brief") this.briefPage(body, m, changed, structural);
    else if (this.page === "intel") this.intelPage(body, m, changed, structural);
    else if (this.page === "actions") this.actionsPage(body, m, file, changed, structural);
    else this.linksPage(body, m, changed, structural);
    const foot = h("div", { class: "detail-foot" }, h("span", { class: "grow" }),
      h("button", { class: "btn danger", onclick: () => this.deleteMission(r) }, "Удалить миссию"));
    M.append(head, tabs, body, foot);
    applyTips(M);
    this.renderPreview(m);
  },

  refreshSideItem(m) {
    const items = this.side.querySelectorAll(".ms-item.on .ms-item-t");
    items.forEach((el) => { el.textContent = m.title || m.id; });
  },

  briefPage(body, m, changed, structural) {
    const lore = byId(F.lore, m.lore || m.from_event);
    body.append(
      h("div", { class: "cols" },
        field("Тип миссии", bindSelect(m, "type", MISSION_TYPES, structural)),
        field("Локация", bindSelect(m, "location", Object.fromEntries(list(F.locations).map((l) => [l.id, l.name])), structural))),
      field("Что происходит", bindInput(m, "briefing", changed, { type: "textarea", rows: 6, keepEmpty: true })),
      this.rumorsBlock(m, changed, structural),
      field("Что увидели по прибытии", bindInput(m, "arrival", changed, { type: "textarea", rows: 5, keepEmpty: true })),
      lore && lore.text ? h("details", { class: "lore-ref" }, h("summary", null, `По книге: ${lore.title || ""}`), h("p", null, lore.text), lore.source ? h("small", { class: "muted" }, lore.source) : null) : null);
  },

  rumorsBlock(m, changed, structural) {
    m.rumors = m.rumors || [];
    const box = h("div", { class: "section" }, h("h4", null, "Что говорят",
      h("button", { class: "btn small add", onclick: () => { m.rumors.push({ text: "«… [намёк] …»", tag: "" }); structural(); } }, "+ слух")));
    box.append(h("p", { class: "muted small-note" }, "Намёк пишите в [квадратных скобках] — игрок увидит его подсвеченным цветом тега справа."));
    m.rumors.forEach((r, i) => {
      const tagBox = h("span", { class: "chips small" });
      const renderTag = () => {
        tagBox.innerHTML = "";
        if (r.tag) tagBox.append(tagChip(r.tag, { context: !combatTag(r.tag) && !!ctxTag(r.tag), onRemove: () => { r.tag = ""; changed(); renderTag(); } }));
        else {
          const add = h("button", { class: "chip-add", title: "Выбрать тег, на который намекает слух" }, "+");
          add.onclick = async () => { const t = await tagPicker(add, {}); if (t) { r.tag = t; changed(); renderTag(); } };
          tagBox.append(add);
        }
      };
      renderTag();
      const warn = /\[.+\]/.test(r.text || "") ? null : h("small", { class: "err" }, "нет намёка в [скобках]");
      box.append(h("div", { class: "rumor-row" },
        bindInput(r, "text", () => { changed(); }, { keepEmpty: true }), tagBox,
        h("button", { class: "icon-btn del", title: "Удалить слух", onclick: () => { m.rumors.splice(i, 1); structural(); } }, "×"), warn));
    });
    return box;
  },

  intelPage(body, m, changed, structural) {
    m.squad = m.squad || { min: 1, max: 1 };
    const threat = h("div", { class: "threat-pick" }, [1, 2, 3, 4, 5].map((n) => h("button", {
      class: "tp" + (n <= (m.threat || 0) ? " on" : ""), title: THREAT_WORDS[n],
      onclick: () => { m.threat = n; changed(); this.renderMain(); },
    }, "●")), h("span", { class: "muted" }, THREAT_WORDS[m.threat || 0] || ""));
    const enemySpec = { enemies: m.enemies || [] };
    const enemyChanged = () => { if (enemySpec.enemies.length) m.enemies = enemySpec.enemies; else delete m.enemies; changed(); };
    body.append(
      h("div", { class: "cols" },
        field("Угроза", threat),
        field("В пути, с", bindInput(m, "duration", changed, { type: "number" })),
        field("Отдых после, с", bindInput(m, "rest", changed, { type: "number" })),
        field("Мест в отряде: от", bindInput(m.squad, "min", changed, { type: "number" })),
        field("Мест в отряде: до", bindInput(m.squad, "max", changed, { type: "number" })),
        field("Пул травм", bindSelect(m, "trauma_pool", POOLS, changed, { allowEmpty: true })),
        field("Небо над картой", bindSelect(m, "sky", { blood_moon: "Кровавая луна", eclipse: "Затмение" }, changed, { allowEmpty: true, emptyLabel: "как обычно (день и ночь)" }),
          "Пока миссия открыта или отряд в пути, фон главы меняется на это небо. Затмение сильнее луны. Только атмосфера — на шансы не влияет.")),
      h("div", { class: "cols" },
        field("Противники", EventsView.enemyPicker(enemySpec, enemyChanged)),
        field("Поле боя", bindSelect(m, "field", Object.fromEntries(list(F.fields).map((f) => [f.id, f.name])), changed, { allowEmpty: true }))),
      h("div", { class: "cols" },
        field("Обязательные герои", heroChips(m, "requires_heroes", changed), "Без них отряд не уйдёт. Если такой герой погибнет до этой сюжетной миссии — прохождение окончено."),
        field("Не могут идти", heroChips(m, "exclude_heroes", changed), "Сюжет: например, беда случилась с самим героем.")),
      h("div", { class: "section" }, h("h4", null, "Известные теги"), tagRow(m.known_tags = m.known_tags || [], changed)),
      h("div", { class: "section" }, h("h4", null, "Скрытые теги"), tagRow(m.hidden_tags = m.hidden_tags || [], changed)),
      h("div", { class: "section" }, h("h4", null, "Теги проверки миссии"), tagRow(m.context = m.context || [], changed, { context: true })));
  },

  actionsPage(body, m, file, changed, structural) {
    const acts = m.actions = m.actions || [];
    if (this.actIdx >= acts.length) this.actIdx = 0;
    const stageWord = (a) => a.retreat ? "отступление" : `${(a.stages || []).length} этап(а)` + ((a.requires_any || []).length ? " · нужен тег" : "");
    body.append(h("div", { class: "opt-tabs" },
      acts.map((a, i) => h("button", { class: (i === this.actIdx ? "on" : "") + (a.story ? " story" : ""), onclick: () => { this.actIdx = i; this.renderMain(); } },
        h("span", { class: "n" }, i + 1), h("span", { class: "t" }, (a.label || "без названия") + (a.story ? " ★" : "")), h("small", null, stageWord(a)))),
      h("button", { class: "btn small add", onclick: () => {
        let n = acts.length + 1;
        while (acts.some((a) => a.id === `${m.id}_a${n}`)) n++;
        acts.push({ id: `${m.id}_a${n}`, label: "Новое действие", text: "", stages: [{ name: "Этап", req: { cunning: 4 }, ok: "", partial: "", fail: "" }] });
        this.actIdx = acts.length - 1;
        structural();
      } }, "+ действие")));
    const a = acts[this.actIdx];
    if (!a) return;
    const onTouch = () => touch(file);
    const card = h("div", { class: "opt-card" + (a.story ? " story" : "") });
    card.append(h("div", { class: "opt-head" },
      h("span", { class: "num" }, this.actIdx + 1),
      field("Название действия", bindInput(a, "label", changed, { keepEmpty: true })),
      h("label", { class: "field inline" }, bindInput(a, "story", structural, { type: "checkbox" }), h("span", null, "★ сюжет")),
      h("label", { class: "field inline" }, bindInput(a, "retreat", structural, { type: "checkbox" }), h("span", null, "отступление")),
      h("button", { class: "icon-btn del", title: "Удалить действие", onclick: async () => {
        if (!(await confirmBox("Удалить действие", `Удалить «${a.label}»?`))) return;
        acts.splice(this.actIdx, 1); this.actIdx = 0; structural();
      } }, "×")));
    card.append(field("Что делает отряд", bindInput(a, "text", changed, { type: "textarea", rows: 2, keepEmpty: true })));
    a.requires_any = a.requires_any || [];
    card.append(h("div", { class: "field" }, h("span", null, "Открывается тегами отряда"),
      tagRow(a.requires_any, () => { if (!a.requires_any.length) delete a.requires_any; changed(); })));
    if (!a.requires_any.length) delete a.requires_any;
    card.append(field("Открывается героем в отряде", heroChips(a, "requires_hero", changed), "Действие доступно, если в отряде есть хотя бы один из этих героев."));
    if (!a.retreat) {
      const stages = a.stages = a.stages || [];
      const sBox = h("div", { class: "opt-block" }, h("div", { class: "mini-h" }, "Этапы",
        stages.length < 3 ? h("button", { class: "btn small add", onclick: () => { stages.push({ name: "Этап", req: { power: 3 }, ok: "", partial: "", fail: "" }); structural(); } }, "+ этап") : null));
      const grid = h("div", { class: "stage-grid" });
      stages.forEach((st, i) => grid.append(this.stageCard(stages, st, i, changed, structural)));
      sBox.append(grid);
      card.append(sBox);
      card.append(h("div", { class: "opt-grid" },
        h("div", { class: "opt-block ok-block" }, EventsView.cmdList("Последствия успеха", a, "on_success", EFFECTS, "cmd", structural, onTouch)),
        h("div", { class: "opt-block part-block" }, EventsView.cmdList("Последствия частичного успеха", a, "on_partial", EFFECTS, "cmd", structural, onTouch)),
        h("div", { class: "opt-block fail-block" }, EventsView.cmdList("Последствия провала", a, "on_failure", EFFECTS, "cmd", structural, onTouch))));
    } else {
      card.append(h("p", { class: "muted" }, "Отступление: миссия не выполнена, ран нет, но отряд устаёт (отдых как после миссии)."));
    }
    body.append(card);
  },

  stageCard(stages, st, i, changed, structural) {
    const kind = st.combat ? "combat" : st.auto ? "auto" : "req";
    const kinds = { req: "Проверка характеристик", combat: "Бой (автобой)", auto: "Без проверки" };
    const card = h("div", { class: "stage-card" });
    card.append(h("div", { class: "row" },
      h("b", { class: "stage-n" }, i + 1), bindInput(st, "name", changed, { keepEmpty: true, cls: "stage-name" }),
      h("button", { class: "icon-btn del", title: "Удалить этап", onclick: () => { stages.splice(i, 1); structural(); } }, "×")),
      field("Вид этапа", h("select", { onchange: (e) => {
        delete st.combat; delete st.auto; delete st.req;
        if (e.target.value === "combat") st.combat = { enemies: [] };
        else if (e.target.value === "auto") st.auto = true;
        else st.req = { power: 3 };
        structural();
      } }, Object.entries(kinds).map(([k, v]) => h("option", { value: k, selected: k === kind }, v)))));
    if (kind === "req") {
      st.req = st.req || {};
      card.append(h("div", { class: "mini-h" }, "Требования"), statsEditor(st.req, changed));
      st.tags = st.tags || [];
      card.append(h("div", { class: "field" }, h("span", null, "Теги проверки этапа"), tagRow(st.tags, () => { if (!st.tags.length) delete st.tags; changed(); }, { context: true, small: true })));
      if (!st.tags.length) delete st.tags;
    }
    if (kind === "combat") {
      card.append(field("Противники", EventsView.enemyPicker(st.combat, changed)),
        field("Поле боя", bindSelect(st.combat, "field", Object.fromEntries(list(F.fields).map((f) => [f.id, f.name])), changed, { allowEmpty: true })));
    }
    card.append(
      field("Текст: успех", bindInput(st, "ok", changed, { type: "textarea", rows: 2 })),
      kind !== "combat" ? field("Текст: частично", bindInput(st, "partial", changed, { type: "textarea", rows: 2 })) : null,
      field("Текст: провал", bindInput(st, "fail", changed, { type: "textarea", rows: 2 })));
    return card;
  },

  linksPage(body, m, changed, structural) {
    const others = this.missions().filter((r) => r.m.id !== m.id);
    const nextBox = h("div", { class: "chips" });
    const renderNext = () => {
      nextBox.innerHTML = "";
      (m.next = m.next || []).forEach((id, i) => {
        const o = this.rec(id);
        nextBox.append(h("span", { class: "chip ctx" + (o ? "" : " missing") }, h("span", { class: "chip-name" }, o ? o.m.title : id),
          h("button", { class: "chip-x", onclick: () => { m.next.splice(i, 1); changed(); renderNext(); } }, "×")));
      });
      const sel = h("select", { class: "enemy-add" }, h("option", { value: "" }, "+ миссия…"),
        others.filter((r) => !m.next.includes(r.m.id)).map((r) => h("option", { value: r.m.id }, r.m.title)));
      sel.onchange = () => { if (sel.value) { m.next.push(sel.value); changed(); renderNext(); } };
      nextBox.append(sel);
    };
    renderNext();
    const incoming = others.filter((r) => (r.m.next || []).includes(m.id));
    const pools = list(F.locations).filter((l) => ((l.random || {}).pool || []).includes(m.id));
    const evOpts = {};
    for (const f of eventFiles()) for (const e of list(f)) evOpts[e.id] = `${e.title} (${e.id})`;
    m.unlock = m.unlock || {};
    const unlockChanged = () => { if (!Object.keys(m.unlock).length) delete m.unlock; changed(); };
    body.append(
      h("label", { class: "field inline" }, bindInput(m, "start", changed, { type: "checkbox" }), h("span", null, "Доступна с начала главы")),
      h("label", { class: "field inline" }, bindInput(m, "end_chapter", changed, { type: "checkbox" }), h("span", null, "Завершает главу")),
      h("div", { class: "opt-block ok-block" }, EventsView.cmdList("После любого удачного действия", m, "on_complete", EFFECTS, "cmd", structural, () => changed())),
      h("div", { class: "section" }, h("h4", null, "Открывает после успеха"), nextBox),
      h("div", { class: "section" }, h("h4", null, "Откуда приходит"),
        incoming.length || pools.length || m.start ? h("ul", { class: "edge-list" },
          m.start ? h("li", null, h("span", { class: "dot", style: { background: "#6FA47B" } }), "с начала главы") : null,
          incoming.map((r) => h("li", null, h("span", { class: "dot", style: { background: "#B89A5E" } }), "после успеха ",
            h("button", { class: "link", onclick: () => this.select(r.m.id) }, r.m.title))),
          pools.map((l) => h("li", null, h("span", { class: "dot", style: { background: "#8A6BB8" } }), `случайная в локации «${l.name}»`)))
          : h("p", { class: "err" }, "Эту миссию ничто не открывает — игрок её не увидит.")),
      h("div", { class: "cols" },
        field("Появляется после N миссий", bindInput(m.unlock, "after_missions", unlockChanged, { type: "number" })),
        field("Из события старой схемы", bindSelect(m, "from_event", evOpts, changed, { allowEmpty: true })),
        field("Описание «По книге»", bindSelect(m, "lore", Object.fromEntries(list(F.lore).map((l) => [l.id, `${l.title} (${l.id})`])), changed, { allowEmpty: true }))));
    if (!Object.keys(m.unlock).length) delete m.unlock;
  },

  // ---- локация ---------------------------------------------------------------------
  renderLocation(M, loc) {
    if (!loc) return;
    const changed = () => { touch(F.locations); };
    loc.random = loc.random || {};
    const rnd = loc.random;
    const rndChanged = () => { if (!Object.keys(rnd).length || (!(rnd.pool || []).length && !rnd.every && !rnd.after_missions)) delete loc.random; else loc.random = rnd; changed(); };
    const title = bindInput(loc, "name", () => { changed(); this.renderSide(); }, { cls: "title-input", keepEmpty: true });
    const mine = this.missions().filter((r) => r.m.location === loc.id);
    const poolBox = h("div", { class: "chips" });
    const renderPool = () => {
      poolBox.innerHTML = "";
      (rnd.pool = rnd.pool || []).forEach((id, i) => {
        const o = this.rec(id);
        poolBox.append(h("span", { class: "chip ctx" }, h("span", { class: "chip-name" }, o ? o.m.title : id),
          h("button", { class: "chip-x", onclick: () => { rnd.pool.splice(i, 1); rndChanged(); renderPool(); } }, "×")));
      });
      const sel = h("select", { class: "enemy-add" }, h("option", { value: "" }, "+ миссия…"),
        this.missions().filter((r) => !rnd.pool.includes(r.m.id)).map((r) => h("option", { value: r.m.id }, r.m.title)));
      sel.onchange = () => { if (sel.value) { rnd.pool.push(sel.value); rndChanged(); renderPool(); } };
      poolBox.append(sel);
    };
    renderPool();
    M.append(
      h("div", { class: "detail-head" }, h("div", { class: "head-info" }, h("div", { class: "kind" }, h("span", { class: "pin-dot" }), "Локация"), title)),
      h("div", { class: "detail-body" },
        field("Описание места", bindInput(loc, "text", changed, { type: "textarea", rows: 4, keepEmpty: true })),
        h("div", { class: "cols" },
          field("Глава", bindInput(loc, "chapter", changed)),
          field("Регион", bindSelect(loc, "region", Object.fromEntries(list(F.regions).map((r) => [r.id, r.name])), changed, { allowEmpty: true })),
          field("Позиция X (0–1)", this.posInput(loc, 0, changed)),
          field("Позиция Y (0–1)", this.posInput(loc, 1, changed))),
        h("div", { class: "section" }, h("h4", null, "Случайные миссии места"), poolBox,
          h("div", { class: "cols" },
            field("Раз в N секунд", bindInput(rnd, "every", rndChanged, { type: "number" })),
            field("После N миссий", bindInput(rnd, "after_missions", rndChanged, { type: "number" })))),
        h("div", { class: "section" }, h("h4", null, `Миссии здесь (${mine.length})`),
          mine.length ? h("ul", { class: "edge-list" }, mine.map((r) => h("li", null, h("button", { class: "link", onclick: () => this.select(r.m.id) }, r.m.title), h("span", { class: "muted" }, MISSION_TYPES[r.m.type] || "")))) : h("p", { class: "muted" }, "Пока нет."))),
      h("div", { class: "detail-foot" }, h("span", { class: "grow" }),
        h("button", { class: "btn danger", onclick: () => this.deleteLocation(loc, mine) }, "Удалить локацию")));
    if (!Object.keys(rnd).length) delete loc.random;
    applyTips(M);
  },

  // ---- магазин (docs/15 §11) -----------------------------------------------------------
  renderShop(M, sh) {
    if (!sh) return;
    const changed = () => { touch(F.shops); };
    const title = bindInput(sh, "name", () => { changed(); this.renderSide(); }, { cls: "title-input", keepEmpty: true });
    const stockBox = h("div", { class: "shop-stock" });
    const renderStock = () => {
      stockBox.innerHTML = "";
      sh.stock = sh.stock || [];
      sh.stock.forEach((it, i) => {
        const c = findCard(it.card);
        const price = h("input", { type: "number", min: "1", value: it.price ?? "", placeholder: String(shopDefaultPrice(it.card)), style: { width: "90px" } });
        price.dataset.tip = "Цена в осколках душ. Пусто — по редкости карты (серое число).";
        price.oninput = () => { if (price.value === "") delete it.price; else it.price = Math.max(1, Number(price.value) || 1); changed(); };
        stockBox.append(h("div", { class: "shop-row" },
          h("span", { class: "type-dot", style: { background: c && c.kind === "character" ? "#C9CED6" : "#8C6B45" } }),
          h("span", { class: "grow" }, cardName(it.card), h("span", { class: "muted" }, "  · " + (c ? (c.kind === "character" ? "персонаж" : "усиление") : "нет такой карты"))),
          h("span", { class: "muted" }, "✧"), price,
          h("button", { class: "chip-x", title: "Убрать из ассортимента", onclick: () => { sh.stock.splice(i, 1); changed(); renderStock(); this.renderSide(); } }, "×")));
      });
      const have = new Set(sh.stock.map((it) => it.card));
      const sel = h("select", { class: "enemy-add" }, h("option", { value: "" }, "+ карта в продажу…"),
        allCards().filter((c) => (c.kind === "character" || c.kind === "enhancement") && !have.has(c.id))
          .map((c) => h("option", { value: c.id }, (c.obj.name || c.id) + " (" + (c.kind === "character" ? "персонаж" : "усиление") + ")")));
      sel.onchange = () => { if (sel.value) { sh.stock.push({ card: sel.value }); changed(); renderStock(); this.renderSide(); } };
      stockBox.append(sel);
    };
    renderStock();
    M.append(
      h("div", { class: "detail-head" }, h("div", { class: "head-info" }, h("div", { class: "kind" }, h("span", { class: "pin-dot", style: { background: "#B9A7E6" } }), "Магазин"), title)),
      h("div", { class: "detail-body" },
        field("Описание (видит игрок)", bindInput(sh, "text", changed, { type: "textarea", rows: 4, keepEmpty: true })),
        h("div", { class: "cols" },
          field("Глава", bindInput(sh, "chapter", changed)),
          field("Позиция X (0–1)", this.posInput(sh, 0, changed)),
          field("Позиция Y (0–1)", this.posInput(sh, 1, changed))),
        h("div", { class: "cols" },
          field("Карт на витрине", bindInput(sh, "slots", changed, { type: "number" }), "Сколько карт из ассортимента выставлено за раз."),
          field("Персонажей не меньше", bindInput(sh, "min_characters", changed, { type: "number" }), "Сколько мест витрины гарантированно отдаётся картам персонажей (если есть кого продать)."),
          field("Обновление раз в N миссий", bindInput(sh, "refresh_every", changed, { type: "number" }), "После каждых N завершённых миссий витрина перекладывается заново.")),
        h("div", { class: "section" }, h("h4", null, "Ассортимент (" + (sh.stock || []).length + ")"),
          h("p", { class: "muted" }, "Из этих карт магазин случайно выбирает витрину. Карты, которые уже у игрока, и погибшие герои не выставляются."), stockBox)),
      h("div", { class: "detail-foot" }, h("span", { class: "grow" }),
        h("button", { class: "btn danger", onclick: () => this.deleteShop(sh) }, "Удалить магазин")));
    applyTips(M);
  },

  async createShop() {
    const r = await ask("Новый магазин", [
      { key: "id", label: "Код (латиницей)", value: "", hint: "например, academy_store" },
      { key: "name", label: "Название", value: "" },
      { key: "chapter", label: "Глава", value: "nightmare" },
    ]);
    if (!r || !r.id) return;
    if (!DB.files[F.shops]) DB.files[F.shops] = [];
    if (byId(F.shops, r.id)) { toast("Такой код уже есть", "err"); return; }
    list(F.shops).push({ id: r.id, chapter: r.chapter, name: r.name || r.id, text: "", pos: [0.5, 0.3], slots: 4, min_characters: 1, refresh_every: 7, stock: [] });
    touch(F.shops);
    this.shopSel = r.id;
    this.locSel = null;
    this.selected = null;
    this.renderSide();
    this.renderMain();
  },

  async deleteShop(sh) {
    if (!(await confirmBox("Удалить магазин", "Удалить «" + sh.name + "»?"))) return;
    DB.files[F.shops] = list(F.shops).filter((x) => x !== sh);
    touch(F.shops);
    this.shopSel = null;
    this.renderSide();
    this.renderMain();
  },

  posInput(loc, i, changed) {
    loc.pos = loc.pos || [0.5, 0.5];
    const inp = h("input", { type: "number", step: "0.01", min: "0", max: "1", value: loc.pos[i] });
    inp.oninput = () => { loc.pos[i] = Math.max(0, Math.min(1, Number(inp.value) || 0)); changed(); };
    return inp;
  },

  // ---- как увидит игрок ------------------------------------------------------------------
  renderPreview(m) {
    const P = this.preview;
    P.innerHTML = "";
    if (!m) { P.append(h("div", { class: "muted pv-empty" }, "Здесь появится миссия так, как её увидит игрок.")); return; }
    const ev = findCard(m.from_event || "");
    const art = ev ? cardArt(ev) : null;
    const hl = (text, tag) => {
      const parts = String(text || "").split(/(\[[^\]]+\])/);
      return parts.map((p) => /^\[.+\]$/.test(p) ? h("span", { class: "pv-hint", style: { "--c": tag ? tagColor(tag) : "#B89A5E" }, title: tag ? "Намёк на тег «" + tag + "»" : "" }, p.slice(1, -1)) : p);
    };
    const enemies = (m.enemies || []).reduce((acc, id) => { acc[id] = (acc[id] || 0) + 1; return acc; }, {});
    P.append(h("div", { class: "pv-label" }, "Как увидит игрок"),
      h("div", { class: "pv-card" },
        art ? h("img", { class: "pv-art", src: art, alt: "" }) : null,
        h("div", { class: "pv-title" }, m.title || "Без названия", m.type === "story" ? h("span", { class: "pv-star" }, "★") : null),
        h("div", { class: "pv-sub" }, (byId(F.locations, m.location) || {}).name || ""),
        h("div", { class: "pv-h" }, "Что происходит"), h("p", { class: "pv-text" }, m.briefing || "—"),
        (m.rumors || []).length ? h("div", null, h("div", { class: "pv-h" }, "Что говорят"),
          h("ul", { class: "pv-rumors" }, m.rumors.map((r) => h("li", null, hl(r.text, r.tag))))) : null,
        h("div", { class: "pv-intel" },
          h("div", null, h("span", null, "Угроза"), h("b", { class: "pv-threat" }, "●".repeat(m.threat || 0), h("i", null, "●".repeat(5 - (m.threat || 0))))),
          h("div", null, h("span", null, "В пути"), h("b", null, `~${m.duration || "?"} с`)),
          h("div", null, h("span", null, "Отряд"), h("b", null, m.squad ? (m.squad.min === m.squad.max ? m.squad.min : `${m.squad.min}–${m.squad.max}`) : "?"))),
        Object.keys(enemies).length ? h("div", { class: "pv-text muted" }, "Возможные противники: " + Object.entries(enemies).map(([id, n]) => `${cardName(id)}${n > 1 ? " ×?" : ""}`).join(", ")) : null,
        h("div", { class: "chips small" }, (m.known_tags || []).map((t) => tagChip(t)), (m.hidden_tags || []).map(() => h("span", { class: "chip unknown" }, "???"))),
        h("div", { class: "pv-h" }, "После прибытия"),
        h("p", { class: "pv-text muted" }, m.arrival || "—"),
        h("ul", { class: "pv-actions" }, (m.actions || []).map((a) => h("li", null,
          (a.requires_any || []).length ? h("span", { class: "pv-need" }, "◆ " + a.requires_any.join(" / ")) : null,
          h("b", null, a.label || "—"), a.story ? " ★" : "", a.retreat ? h("span", { class: "muted" }, " · отступление") : null)))));
  },

  // ---- создание и удаление --------------------------------------------------------------------
  async createMission() {
    const files = missionFiles();
    const r = await ask("Новая миссия", [
      { key: "title", label: "Название", value: "" },
      { key: "location", label: "Локация", type: "select", value: this.locSel || (list(F.locations)[0] || {}).id, options: Object.fromEntries(list(F.locations).map((l) => [l.id, l.name])) },
      { key: "type", label: "Тип", type: "select", value: "side", options: MISSION_TYPES },
      { key: "file", label: "Файл", type: "select", value: files[0] || "data/missions/ch1_nightmare.json", options: Object.fromEntries((files.length ? files : ["data/missions/ch1_nightmare.json"]).map((f) => [f, f.replace("data/missions/", "")])) },
    ]);
    if (!r) return;
    let n = 1;
    while (this.rec("MS" + String(n).padStart(2, "0"))) n++;
    const id = "MS" + String(n).padStart(2, "0");
    list(r.file).push({
      id, location: r.location, type: r.type, title: r.title || id, briefing: "", rumors: [], threat: 1, duration: 8, rest: 20,
      squad: { min: 1, max: 2 }, known_tags: [], hidden_tags: [], context: [], arrival: "",
      actions: [
        { id: id + "_a1", label: "Действовать", text: "", story: r.type === "story" || undefined, stages: [{ name: "Этап", req: { cunning: 4 }, ok: "", partial: "", fail: "" }] },
        { id: id + "_retreat", label: "Отступить", text: "", retreat: true },
      ],
      next: [],
    });
    touch(r.file);
    this.page = "brief";
    this.select(id);
  },

  async createLocation() {
    const r = await ask("Новая локация", [
      { key: "id", label: "Код (латиницей)", value: "", hint: "например, frozen_pass" },
      { key: "name", label: "Название", value: "" },
      { key: "chapter", label: "Глава", value: "nightmare" },
    ]);
    if (!r || !r.id) return;
    if (byId(F.locations, r.id)) { toast("Такой код уже есть", "err"); return; }
    list(F.locations).push({ id: r.id, name: r.name || r.id, chapter: r.chapter, pos: [0.5, 0.5], text: "" });
    touch(F.locations);
    this.locSel = r.id;
    this.selected = null;
    this.renderSide();
    this.renderMain();
  },

  async deleteMission(r) {
    if (!(await confirmBox("Удалить миссию", `Удалить «${r.m.title}»? Ссылки на неё в других миссиях и локациях тоже уберутся.`))) return;
    const id = r.m.id;
    DB.files[r.file] = list(r.file).filter((x) => x !== r.m);
    touch(r.file);
    for (const o of this.missions()) if ((o.m.next || []).includes(id)) { o.m.next = o.m.next.filter((x) => x !== id); touch(o.file); }
    for (const l of list(F.locations)) if (((l.random || {}).pool || []).includes(id)) { l.random.pool = l.random.pool.filter((x) => x !== id); touch(F.locations); }
    this.selected = null;
    this.renderSide();
    this.renderMain();
  },

  async deleteLocation(loc, mine) {
    if (mine.length) { toast(`В локации есть миссии (${mine.length}) — сначала перенесите или удалите их`, "warn", 5000); return; }
    if (!(await confirmBox("Удалить локацию", `Удалить «${loc.name}»?`))) return;
    DB.files[F.locations] = list(F.locations).filter((x) => x !== loc);
    touch(F.locations);
    this.locSel = null;
    this.renderSide();
    this.renderMain();
  },
};

// Список героев-чипов (requires_heroes, exclude_heroes, requires_hero): пустой — ключ удаляется.
function heroChips(obj, key, changed) {
  const box = h("div", { class: "chips" });
  const render = () => {
    box.innerHTML = "";
    const arr = obj[key] || [];
    arr.forEach((id, i) => box.append(h("span", { class: "chip ctx" }, h("span", { class: "chip-name" }, cardName(id)),
      h("button", { class: "chip-x", onclick: () => { arr.splice(i, 1); if (!arr.length) delete obj[key]; changed(); render(); } }, "×"))));
    const sel = h("select", { class: "enemy-add" }, h("option", { value: "" }, "+ герой…"),
      allCards().filter((c) => c.kind === "character" && !arr.includes(c.id)).map((c) => h("option", { value: c.id }, c.obj.name || c.id)));
    sel.onchange = () => { if (sel.value) { obj[key] = [...arr, sel.value]; changed(); render(); } };
    box.append(sel);
  };
  render();
  return box;
}

// Цена по умолчанию — как ShopRules.PRICE (core/rules/shop_rules.gd).
const SHOP_PRICE = {
  enhancement: { common: 5, rare: 9, epic: 16, legendary: 28 },
  character: { common: 8, rare: 14, epic: 20, legendary: 35 },
};
function shopDefaultPrice(id) {
  const c = findCard(id);
  if (!c) return 10;
  return (SHOP_PRICE[c.kind] || SHOP_PRICE.enhancement)[c.obj.rarity || "common"] || 10;
}

// Проверка миссий — те же правила, что в core/content/content_validator.gd (_validate_missions).
function validateMissions(add) {
  const locs = new Set(list(F.locations).map((l) => l.id));
  const all = {};
  for (const f of missionFiles()) for (const m of list(f)) all[m.id] = m;
  const tagOk = (t) => !!combatTag(t);
  for (const l of list(F.locations)) for (const id of (l.random || {}).pool || []) if (!all[id]) add(l.id, `в пуле нет миссии ${id}`);
  for (const sh of list(F.shops)) {
    const w = "Магазин " + (sh.name || sh.id);
    if (!(sh.slots >= 1)) add(w, "карт на витрине должно быть не меньше 1");
    if (!(sh.refresh_every >= 1)) add(w, "обновление — не реже чем раз в 1 миссию");
    if (!(sh.stock || []).length) add(w, "пустой ассортимент");
    for (const it of sh.stock || []) {
      const c = findCard(it.card);
      if (!c || (c.kind !== "character" && c.kind !== "enhancement")) add(w, "в продаже может быть только персонаж или усиление, а не «" + it.card + "»");
      if (it.price !== undefined && !(it.price >= 1)) add(w, "у " + it.card + " цена меньше 1");
    }
  }
  for (const [id, m] of Object.entries(all)) {
    const nav = { mission: id };
    const w = `${m.title || id}`;
    if (!locs.has(m.location)) add(w, `нет локации «${m.location}»`, nav);
    if (!MISSION_TYPES[m.type]) add(w, `неизвестный тип «${m.type}»`, nav);
    for (const k of ["title", "briefing", "arrival"]) if (!m[k]) add(w, `пустое поле «${{ title: "Название", briefing: "Что происходит", arrival: "Что увидели" }[k]}»`, nav);
    if (!(m.threat >= 1 && m.threat <= 5)) add(w, "угроза должна быть 1–5", nav);
    if (m.sky !== undefined && !["eclipse", "blood_moon"].includes(m.sky)) add(w, `небо «${m.sky}» — только eclipse или blood_moon`, nav);
    if (!(m.duration >= 5 && m.duration <= 15)) add(w, "время в пути должно быть 5–15 с", nav);
    const sq = m.squad || {};
    if (!(sq.min >= 1 && sq.max <= 5 && sq.min <= sq.max)) add(w, "мест в отряде: нужно 1 ≤ от ≤ до ≤ 5", nav);
    for (const e of m.enemies || []) if (!byId(F.enemies, e)) add(w, `нет противника ${e}`, nav);
    for (const t of [...(m.known_tags || []), ...(m.hidden_tags || [])]) if (!tagOk(t)) add(w, `нет боевого тега «${t}»`, nav);
    for (const r of m.rumors || []) {
      if (!/\[.+\]/.test(r.text || "")) add(w, `в слухе нет намёка в [скобках]: ${r.text}`, nav);
      if (r.tag && !combatTag(r.tag) && !ctxTag(r.tag)) add(w, `слух ссылается на неизвестный тег «${r.tag}»`, nav);
    }
    for (const n of m.next || []) if (!all[n]) add(w, `открывает несуществующую миссию ${n}`, nav);
    const acts = m.actions || [];
    if (!acts.some((a) => !a.retreat)) add(w, "нет ни одного действия, кроме отступления", nav);
    if (m.type === "story" && !acts.some((a) => a.story)) add(w, "у сюжетной миссии нет сюжетного действия ★", nav);
    for (const a of acts) {
      if (a.retreat) continue;
      const st = a.stages || [];
      if (!st.length || st.length > 3) add(w, `«${a.label}»: этапов ${st.length}, нужно 1–3`, nav);
      for (const s of st) {
        if (s.combat) { if (!(s.combat.enemies || []).length) add(w, `«${a.label}» / ${s.name}: бой без противников`, nav); }
        else if (!s.auto && !Object.values(s.req || {}).some((v) => v > 0)) add(w, `«${a.label}» / ${s.name}: этап без требований`, nav);
      }
      for (const t of a.requires_any || []) if (!tagOk(t)) add(w, `«${a.label}»: нет боевого тега «${t}»`, nav);
      for (const k of ["on_success", "on_partial", "on_failure"]) for (const e of a[k] || [])
        if (e.resource === "mana") add(w, `«${a.label}»: маны в миссиях нет`, nav);
    }
  }
}
