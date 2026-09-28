// Экран «Сила»: баланс противников и персонажей + статистика боёв (tools/combat_stats.gd).
// Противник: ранг, класс, множитель силы (power), природное оружие по тегам. Персонаж: характеристики по стадиям,
// ранг, оружие. Статистика: для каждого боя — шанс лучшего отряда из доступных в этот момент героев с их усилениями.
"use strict";

const CLASS_MULT = [1.0, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5];
const RANK_STEP = 1.6;
const RANK_NAMES = ["Спящий", "Пробуждённый", "Вознесённый", "Трансцендентный", "Верховный", "Священный", "Божественный"];
const CLASS_NAMES = ["", "Зверь", "Монстр", "Демон", "Дьявол", "Тиран", "Ужас", "Титан"];

const BalanceView = {
  stats: null, open: new Set(), tab: "enemies",

  async render(root) {
    this.root = root;
    root.innerHTML = "";
    if (this.stats === null) await this.loadStats();
    const wrap = h("section", { class: "grid-wrap bal" });
    root.append(wrap);
    const st = this.stats;
    wrap.append(
      h("div", { class: "bal-head" },
        h("h2", null, "Сила противников и персонажей"),
        h("div", { class: "bal-tabs" },
          ["enemies", "heroes"].map((t) => h("button", { class: this.tab === t ? "on" : "", onclick: () => { this.tab = t; this.render(root); } },
            t === "enemies" ? "Противники" : "Персонажи"))),
        h("div", { class: "bal-stats-info" },
          st && st.generated ? `Статистика боёв: ${st.generated.replace("T", " ")} · прогонов бота ${st.seeds}` : "Статистики боёв ещё нет",
          h("button", { class: "btn ghost", onclick: () => this.recompute() }, "Пересчитать статистику"))),
      h("p", { class: "muted bal-legend" },
        "Шанс — честный прогноз боя ударами (как в игре). ",
        h("b", null, "Лучший"), " — лучший состав из героев, доступных игроку в момент этого боя, с разложенными кармашками; ",
        h("b", null, "обычный"), " — в среднем по всем составам; ", h("b", null, "один"), " — лучший герой в одиночку; ",
        h("b", null, "без усилений"), " — лучший отряд с пустыми кармашками. После правок: «Сохранить», затем «Пересчитать статистику»."),
      this.tab === "enemies" ? this.enemies() : this.heroes());
  },

  async loadStats() {
    try { this.stats = await (await fetch("/api/stats")).json(); } catch (_) { this.stats = {}; }
  },

  async recompute() {
    if (DB.dirty.size) { toast("Сначала сохраните правки — статистика считается по файлам на диске", "err", 6000); return; }
    const r = await (await fetch("/api/godot/stats", { method: "POST", body: "{}" })).json();
    if (!r.ok) { toast(r.error, "err", 8000); return; }
    toast("Статистика боёв: бот проходит игру…", "info");
    const poll = async () => {
      const j = await (await fetch("/api/job?name=stats")).json();
      if (j.running) { setTimeout(poll, 1500); return; }
      if (j.code !== 0) { modal("Статистика — ошибка", h("pre", { class: "log" }, j.log.slice(-4000))); return; }
      await this.loadStats();
      toast("Статистика боёв обновлена", "ok");
      if (App.view === "balance") this.render(this.root);
    };
    setTimeout(poll, 1500);
  },

  pct(v, cls) {
    if (v === undefined || v === null) return h("td", { class: "muted" }, "—");
    const p = Math.round(v * 100);
    const tone = p < 25 ? "hard" : p > 90 ? "easy" : "";
    return h("td", { class: "pct " + tone + (cls ? " " + cls : "") }, p + "%");
  },

  weaponOf(e) {
    const w = DB.files[F.weapons] || {};
    const tags = e.tags || [];
    let fallback = "";
    for (const n of w.natural || []) {
      if (!n.tags || !n.tags.length) { fallback = n.id; continue; }
      if (n.tags.some((t) => tags.includes(t))) return n.id;
    }
    return fallback;
  },

  power(e) {
    return 100 * Math.pow(RANK_STEP, +e.rank || 0) * CLASS_MULT[Math.min(7, Math.max(1, +e.class || 1))] * (e.power ?? 1);
  },

  enemies() {
    const st = this.stats || {};
    const byEnemy = st.enemies || {};
    const fights = Object.fromEntries((st.fights || []).map((f) => [f.key, f]));
    const changed = () => { touch(F.enemies); this.refreshRow(); };
    const body = h("tbody");
    const rows = list(F.enemies).slice().sort((a, b) => ((byEnemy[b.id] ? 1 : 0) - (byEnemy[a.id] ? 1 : 0)) || this.power(a) - this.power(b));
    this.refreshRow = () => { for (const [e, cell] of this._powerCells) cell.textContent = Math.round(this.power(e)); };
    this._powerCells = [];
    for (const e of rows) {
      const card = { kind: "enemy", id: e.id, obj: e };
      const art = cardArt(card);
      const s = byEnemy[e.id];
      const pw = h("td", { class: "num" }, Math.round(this.power(e)));
      this._powerCells.push([e, pw]);
      const isOpen = this.open.has(e.id);
      const cls = h("select", null, CLASS_NAMES.map((n, i) => i ? h("option", { value: i, selected: +e.class === i }, `${i} · ${n}`) : null));
      cls.onchange = () => { e.class = +cls.value; changed(); };
      const rank = h("select", null, RANK_NAMES.map((n, i) => h("option", { value: i, selected: (+e.rank || 0) === i }, `${i} · ${n}`)));
      rank.onchange = () => { e.rank = +rank.value; changed(); };
      const mult = h("input", { type: "number", step: "0.05", min: "0.1", value: e.power ?? 1, class: "num-in" });
      mult.oninput = () => { const v = Number(mult.value); if (!v || v === 1) delete e.power; else e.power = v; changed(); };
      body.append(h("tr", { class: s ? "" : "unused" },
        h("td", null, art ? h("img", { class: "bal-art", src: art, alt: "" }) : null),
        h("td", { class: "mono" }, e.id),
        h("td", null, h("a", { href: "#", onclick: (ev) => { ev.preventDefault(); App.go("cards", { card: e.id }); } }, e.name || e.id),
          h("div", { class: "muted small" }, (e.tags || []).slice(0, 6).join(", "))),
        h("td", null, rank), h("td", null, cls), h("td", null, mult),
        h("td", null, this.weaponOf(e)), pw,
        h("td", { class: "num" }, s ? s.fights.length : "—"),
        this.pct(s && s.best), this.pct(s && s.typical),
        h("td", null, s ? h("button", { class: "btn ghost small", onclick: () => { isOpen ? this.open.delete(e.id) : this.open.add(e.id); this.render(this.root); } }, isOpen ? "▲ бои" : "▼ бои") : null)));
      if (isOpen && s) {
        const sub = h("table", { class: "bal-sub" },
          h("thead", null, h("tr", null, ["Бой", "Глава", "Действие · этап", "Враги", "Лучший", "Обычный", "Один", "Без усилений", "Лучший отряд"].map((t) => h("th", null, t)))),
          h("tbody", null, s.fights.map((k) => fights[k]).filter(Boolean).map((f) => h("tr", null,
            h("td", null, h("a", { href: "#", onclick: (ev) => { ev.preventDefault(); App.go("missions", { mission: f.mission }); } }, `${f.mission} · ${f.title}`)),
            h("td", null, f.chapter), h("td", null, `${f.action_label} · ${f.stage}`), h("td", null, f.enemies.join(", ")),
            this.pct(f.best), this.pct(f.typical), this.pct(f.solo), this.pct(f.bare),
            h("td", null, (f.team || []).map((c) => cardName(c)).join(", "))))));
        body.append(h("tr", { class: "bal-open" }, h("td", { colspan: 12 }, sub)));
      }
    }
    return h("table", { class: "bal-table" },
      h("thead", null, h("tr", null, ["", "id", "Противник", "Ранг", "Класс", "Сила ×", "Оружие", "Сила", "Боёв", "Лучший", "Обычный", ""].map((t) => h("th", null, t)))),
      body);
  },

  heroes() {
    const weapons = Object.fromEntries(((DB.files[F.weapons] || {}).weapons || []).map((w) => [w.id, w.id]));
    const changed = () => touch(F.characters);
    const body = h("tbody");
    for (const c of list(F.characters)) {
      const art = cardArt({ kind: "character", id: c.id, obj: c });
      const stages = c.stages && Object.keys(c.stages).length ? Object.entries(c.stages) : [["", c]];
      stages.forEach(([sid, sd], i) => {
        sd.stats = sd.stats || { power: 0, will: 0, cunning: 0 };
        const statIn = (k) => {
          const inp = h("input", { type: "number", min: "0", max: "20", value: sd.stats[k] ?? 0, class: "num-in" });
          inp.oninput = () => { sd.stats[k] = Number(inp.value) || 0; changed(); };
          return h("td", null, inp);
        };
        const rankIn = h("input", { type: "number", min: "0", max: "6", value: sd.rank ?? (i === 0 ? c.rank ?? 0 : ""), class: "num-in", placeholder: String(c.rank ?? 0) });
        rankIn.oninput = () => { if (rankIn.value === "") delete sd.rank; else sd.rank = Number(rankIn.value); changed(); };
        body.append(h("tr", null,
          h("td", null, i === 0 && art ? h("img", { class: "bal-art", src: art, alt: "" }) : null),
          h("td", { class: "mono" }, i === 0 ? c.id : ""),
          h("td", null, i === 0 ? h("a", { href: "#", onclick: (ev) => { ev.preventDefault(); App.go("cards", { card: c.id }); } }, c.name) : "",
            sid ? h("div", { class: "muted small" }, "стадия: " + (sd.name || sid)) : null),
          statIn("power"), statIn("will"), statIn("cunning"), h("td", null, rankIn),
          h("td", null, i === 0 ? bindSelect(c, "weapon", weapons, changed, { allowEmpty: true, emptyLabel: "—" }) : null),
          h("td", { class: "muted small" }, (sd.tags || c.tags || []).join(", "))));
      });
    }
    return h("table", { class: "bal-table" },
      h("thead", null, h("tr", null, ["", "id", "Персонаж", "Сила", "Воля", "Хитрость", "Ранг", "Оружие", "Теги"].map((t) => h("th", null, t)))),
      body);
  },
};
