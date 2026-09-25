// Экран «Древо событий»: граф переходов между событиями по выборам и редактор события.
"use strict";

const NODE_W = 250, HEAD_H = 48, OPT_H = 22, PAD_B = 10, COL_W = 340, ROW_GAP = 36;
const PSEUDO_W = 170, PSEUDO_H = 44;
const EDGE_STYLE = {
  next: { color: "#B89A5E", label: "далее по сюжету" },
  spawn: { color: "#6F8FD8", label: "создаёт событие" },
  spawn_fail: { color: "#B65F63", label: "при провале" },
  initiator: { color: "#8A6BB8", dash: "7 5", label: "инициатор" },
  chapter: { color: "#6FA47B", label: "открывает главу" },
  anchor: { color: "#6FA47B", dash: "2 5", label: "якорь главы" },
  thread: { color: "#9AC7A8", dash: "2 5", label: "нить" },
  final: { color: "#6FA47B", dash: "10 4", label: "по отсчёту" },
  pool: { color: "#5A5E6E", dash: "3 4", label: "случайное в регионе" },
  reveal: { color: "#8FB6C9", dash: "1 4", label: "раскрывает" },
  combat_mod: { color: "#D9975A", dash: "1 4", label: "меняет бой" },
};

const EventsView = {
  selected: null, query: "", t: { x: 40, y: 60, k: 0.8 }, showReveal: false, showCombat: false, fitted: false,

  render(root, params = {}) {
    if (params.select) this.selected = params.select;
    this.wrap = h("section", { class: "graph-wrap" });
    this.panel = h("section", { class: "ev-panel" });
    root.append(this.wrap, this.panel);
    this.buildToolbar();
    this.draw();
    this.renderPanel();
    if (params.select && this.nodes[params.select]) this.centerOn(params.select);
    else if (!this.fitted) { this.t = { x: 30, y: 70, k: 0.75 }; this.applyTransform(); this.fitted = true; }
  },

  events() {
    const out = {};
    for (const f of eventFiles()) for (const ev of list(f)) out[ev.id] = { ev, file: f };
    return out;
  },

  // ---- модель графа -----------------------------------------------------------------
  buildGraph() {
    const evs = this.events();
    const nodes = {};
    const edges = [];
    for (const [id, { ev, file }] of Object.entries(evs)) nodes[id] = { id, type: "event", ev, file, w: NODE_W, h: HEAD_H + (ev.options || []).length * OPT_H + PAD_B };
    const pseudo = (id, type, title, sub) => {
      if (!nodes[id]) nodes[id] = { id, type, title, sub, w: PSEUDO_W, h: PSEUDO_H };
      return id;
    };
    const initByCard = Object.fromEntries(list(F.initiators).map((i) => [i.id, i]));
    const scanEffects = (from, port, effs, fail) => {
      for (const e of effs || []) {
        if (e.cmd === "spawn_event" && e.event) edges.push({ from, port, to: e.event, type: fail ? "spawn_fail" : "spawn", effs, eff: e });
        if (e.cmd === "add_card" && initByCard[e.card]) {
          const iid = pseudo("init:" + e.card, "init", initByCard[e.card].name, e.card);
          edges.push({ from, port, to: iid, type: "initiator", effs, eff: e });
        }
        if (e.cmd === "start_chapter") edges.push({ from, port, to: pseudo("chapter:" + e.chapter, "chapter", (byId(F.chapters, e.chapter) || {}).title || e.chapter, "глава"), type: "chapter", effs, eff: e });
        if (e.cmd === "reveal" && e.event && this.showReveal) edges.push({ from, port, to: e.event, type: "reveal", effs, eff: e });
        if (e.cmd === "combat_mod" && e.event && this.showCombat) edges.push({ from, port, to: e.event, type: "combat_mod", effs, eff: e });
      }
    };
    for (const [id, { ev }] of Object.entries(evs)) {
      const opts = ev.options || [];
      opts.forEach((o, i) => { scanEffects(id, i, o.on_success, false); scanEffects(id, i, o.on_failure, true); });
      scanEffects(id, "head", ev.on_appear, false);
      scanEffects(id, "head", ev.on_success_common, false);
      if (ev.next) {
        const si = opts.findIndex((o) => o.story);
        edges.push({ from: id, port: si >= 0 ? si : "head", to: ev.next, type: "next", label: ev.next_immediate ? "сразу" : null });
      }
    }
    for (const i of list(F.initiators)) {
      const iid = pseudo("init:" + i.id, "init", i.name, i.id);
      if (i.event) edges.push({ from: iid, port: "head", to: i.event, type: "initiator", init: i });
    }
    for (const ch of list(F.chapters)) {
      const cid = pseudo("chapter:" + ch.id, "chapter", ch.title, "глава");
      for (const a of ch.anchors || []) {
        if (!(a.after || []).length) edges.push({ from: cid, port: "head", to: a.event, type: "anchor", chapter: ch, anchor: a });
        for (const dep of a.after || []) edges.push({ from: dep, port: "head", to: a.event, type: "anchor", chapter: ch, anchor: a, dep, label: a.or_weeks_left ? `или за ${a.or_weeks_left} нед.` : null });
      }
      for (const a of ch.threads || []) for (const dep of a.after || []) edges.push({ from: dep, port: "head", to: a.event, type: "thread", chapter: ch, anchor: a, dep, thread: true });
      if (ch.final) {
        const last = (ch.anchors || []).filter((a) => !(ch.anchors || []).some((b) => (b.after || []).includes(a.event))).map((a) => a.event);
        for (const l of last) edges.push({ from: l, port: "head", to: ch.final, type: "final", chapter: ch, label: `${ch.weeks || "?"} нед.` });
      }
    }
    const pools = [];
    for (const r of list(F.regions)) {
      const rid = pseudo("region:" + r.id, "region", r.name, "регион");
      pools.push({ rid, region: r, events: (r.random_pool || []).filter((e) => nodes[e]) });
      for (const e of r.random_pool || []) edges.push({ from: rid, port: "head", to: e, type: "pool", region: r });
    }
    return { nodes, edges: edges.filter((e) => nodes[e.from] && nodes[e.to]), dangling: edges.filter((e) => !nodes[e.to]), pools };
  },

  // ---- раскладка: слои слева направо по самому длинному пути ------------------------------------
  layout(g) {
    const { nodes, edges, pools } = g;
    const main = edges.filter((e) => !["pool", "reveal", "combat_mod"].includes(e.type));
    const out = {};
    for (const id in nodes) out[id] = [];
    for (const e of main) out[e.from].push(e.to);
    // обратные рёбра (циклы) не учитываем
    const state = {}, back = new Set();
    const dfs = (u) => {
      state[u] = 1;
      for (const v of out[u]) {
        if (state[v] === 1) back.add(u + ">" + v);
        else if (!state[v]) dfs(v);
      }
      state[u] = 2;
    };
    Object.keys(nodes).sort().forEach((id) => { if (!state[id]) dfs(id); });
    const inDeg = {};
    for (const id in nodes) inDeg[id] = 0;
    const dag = main.filter((e) => !back.has(e.from + ">" + e.to));
    for (const e of dag) inDeg[e.to]++;
    const rank = {};
    const queue = Object.keys(nodes).filter((id) => inDeg[id] === 0);
    queue.forEach((id) => (rank[id] = 0));
    const order = [];
    while (queue.length) {
      const u = queue.shift();
      order.push(u);
      for (const e of dag) if (e.from === u) {
        rank[e.to] = Math.max(rank[e.to] || 0, rank[u] + 1);
        if (--inDeg[e.to] === 0) queue.push(e.to);
      }
    }
    // случайные события регионов раскладываем отдельными полосами внизу
    const pooled = new Set();
    for (const p of pools) for (const e of p.events) if (!main.some((m) => m.to === e)) pooled.add(e);
    const hasMain = (id) => main.some((m) => m.from === id || m.to === id);

    // источники без входов подтягиваем к первому потомку (инициаторы, главы)
    for (const id of order) {
      if (nodes[id].type !== "event" && !dag.some((e) => e.to === id)) {
        const kids = dag.filter((e) => e.from === id).map((e) => rank[e.to]);
        if (kids.length) rank[id] = Math.max(0, Math.min(...kids) - 1);
      }
    }
    const cols = {};
    for (const id in nodes) {
      if (pooled.has(id) || nodes[id].type === "region") continue;
      if (!hasMain(id) && nodes[id].type !== "event") continue;
      (cols[rank[id] || 0] = cols[rank[id] || 0] || []).push(id);
    }
    const pos = {};
    // узел стремится на высоту своих предков — цепочки идут ровными строками
    const predY = (e) => (pos[e.from] ? pos[e.from].y : null);
    const colKeys = Object.keys(cols).map(Number).sort((a, b) => a - b);
    for (const c of colKeys) {
      const ids = cols[c];
      const want = {};
      for (const id of ids) {
        const ys = dag.filter((e) => e.to === id).map(predY).filter((y) => y !== null);
        want[id] = ys.length ? Math.min(...ys) : Infinity;
      }
      ids.sort((a, b) => (want[a] - want[b]) || a.localeCompare(b, undefined, { numeric: true }));
      let y = 0;
      for (const id of ids) {
        const target = want[id] === Infinity ? y : Math.max(y, want[id]);
        pos[id] = { x: c * COL_W, y: target };
        y = target + nodes[id].h + ROW_GAP;
      }
    }
    // полосы регионов
    let maxY = 0;
    for (const id in pos) maxY = Math.max(maxY, pos[id].y + nodes[id].h);
    let y = maxY + 110;
    for (const p of pools) {
      pos[p.rid] = { x: 0, y: y + 20 };
      let x = COL_W, rowH = 0, placed = 0;
      for (const e of p.events) {
        if (!pooled.has(e) || pos[e]) continue;
        if (placed && placed % 6 === 0) { x = COL_W; y += rowH + ROW_GAP; rowH = 0; }
        pos[e] = { x, y };
        x += NODE_W + 40;
        rowH = Math.max(rowH, nodes[e].h);
        placed++;
      }
      y += Math.max(rowH, PSEUDO_H) + 90;
    }
    // оставшиеся (без связей)
    let lx = 0;
    for (const id in nodes) if (!pos[id]) { pos[id] = { x: lx, y }; lx += nodes[id].w + 40; }
    return pos;
  },

  // ---- отрисовка ---------------------------------------------------------------------------------
  buildToolbar() {
    const search = h("input", { type: "search", placeholder: "Найти событие…", value: this.query });
    search.oninput = () => { this.query = search.value; this.applyDim(); };
    search.onkeydown = (e) => {
      if (e.key === "Enter") {
        const q = this.query.toLowerCase();
        const hit = Object.values(this.nodes).find((n) => n.type === "event" && (n.id.toLowerCase().includes(q) || (n.ev.title || "").toLowerCase().includes(q)));
        if (hit) { this.select(hit.id); this.centerOn(hit.id); }
      }
    };
    const toggle = (key, label) => h("label", { class: "btn small", style: { display: "flex", gap: "6px", alignItems: "center" } },
      h("input", { type: "checkbox", checked: this[key], onchange: (e) => { this[key] = e.target.checked; this.draw(); } }), label);
    this.wrap.append(
      h("div", { class: "graph-tools" },
        search,
        h("button", { class: "btn small add", onclick: () => this.createEvent() }, "+ Событие"),
        h("button", { class: "btn small", onclick: () => this.fit() }, "Вписать"),
        h("button", { class: "btn small", title: "Сбросить ручное расположение узлов", onclick: () => { DB.layout = {}; DB.layoutDirty = true; App.refreshStatus(); this.draw(); this.fit(); } }, "Авто-раскладка"),
        toggle("showReveal", "раскрытия"), toggle("showCombat", "изменения боя")),
      h("div", { class: "legend" }, Object.entries(EDGE_STYLE).filter(([k]) => (k !== "reveal" || this.showReveal) && (k !== "combat_mod" || this.showCombat))
        .map(([, s]) => h("span", null, h("i", { style: { borderColor: s.color, borderTopStyle: s.dash ? "dashed" : "solid" } }), s.label)),
        h("span", { class: "muted" }, "· тяните от ● варианта к событию, чтобы связать")));
  },

  draw() {
    const g = this.buildGraph();
    this.graph = g;
    this.nodes = g.nodes;
    const auto = this.layout(g);
    this.pos = {};
    for (const id in g.nodes) this.pos[id] = DB.layout[id] ? { ...DB.layout[id] } : auto[id];
    const NS = "http://www.w3.org/2000/svg";
    const svg = (tag, attrs = {}, ...kids) => {
      const el = document.createElementNS(NS, tag);
      for (const [k, v] of Object.entries(attrs)) if (v !== undefined && v !== null) el.setAttribute(k, v);
      for (const k of kids.flat()) if (k) el.append(k instanceof Node ? k : document.createTextNode(k));
      return el;
    };
    this.svgEl = this.svgEl || null;
    if (this.svgEl) this.svgEl.remove();
    // legend зависит от переключателей
    const legend = this.wrap.querySelector(".legend");
    const tools = this.wrap.querySelector(".graph-tools");
    if (legend) { legend.remove(); tools.remove(); this.buildToolbar(); }

    const root = svg("svg", {});
    const defs = svg("defs");
    for (const [k, s] of Object.entries(EDGE_STYLE)) {
      defs.append(svg("marker", { id: "arr-" + k, viewBox: "0 0 10 10", refX: 9, refY: 5, markerWidth: 7, markerHeight: 7, orient: "auto-start-reverse" },
        svg("path", { d: "M0,0 L10,5 L0,10 z", fill: s.color })));
    }
    root.append(defs);
    const world = svg("g", {});
    this.world = world;
    const edgeLayer = svg("g", {});
    const nodeLayer = svg("g", {});
    world.append(edgeLayer, nodeLayer);
    root.append(world);
    this.svgEl = root;
    this.wrap.prepend(root);
    this.edgeLayer = edgeLayer;
    this.svg = svg;

    for (const id in g.nodes) nodeLayer.append(this.drawNode(g.nodes[id]));
    this.drawEdges();
    this.applyTransform();
    this.applyDim();
    this.bindPanZoom(root);
  },

  portPos(id, port, side) {
    const n = this.nodes[id], p = this.pos[id];
    if (side === "in") return { x: p.x, y: p.y + (n.type === "event" ? HEAD_H / 2 : n.h / 2) };
    if (typeof port === "number") return { x: p.x + n.w, y: p.y + HEAD_H + port * OPT_H + OPT_H / 2 };
    return { x: p.x + n.w, y: p.y + (n.type === "event" ? HEAD_H / 2 : n.h / 2) };
  },

  drawEdges() {
    const svg = this.svg;
    this.edgeLayer.innerHTML = "";
    for (const e of this.graph.edges) {
      const a = this.portPos(e.from, e.port, "out");
      const b = this.portPos(e.to, null, "in");
      const st = EDGE_STYLE[e.type];
      const dx = Math.max(60, Math.abs(b.x - a.x) * 0.45);
      const back = b.x <= a.x + 20;
      const d = back
        ? `M${a.x},${a.y} C${a.x + 120},${a.y} ${a.x + 120},${Math.max(a.y, b.y) + 90} ${(a.x + b.x) / 2},${Math.max(a.y, b.y) + 90} S${b.x - 120},${b.y} ${b.x},${b.y}`
        : `M${a.x},${a.y} C${a.x + dx},${a.y} ${b.x - dx},${b.y} ${b.x},${b.y}`;
      const hit = svg("path", { d, class: "edge-hit" });
      const path = svg("path", { d, class: "edge", stroke: st.color, "stroke-dasharray": st.dash || null, "marker-end": `url(#arr-${e.type})` });
      path.dataset.from = e.from; path.dataset.to = e.to;
      hit.onclick = (ev) => { ev.stopPropagation(); this.edgeMenu(e); };
      hit.append(svg("title", {}, `${st.label}: ${e.from} → ${e.to}`));
      this.edgeLayer.append(hit, path);
      if (e.label) {
        const mx = back ? (a.x + b.x) / 2 : (a.x + b.x) / 2, my = back ? Math.max(a.y, b.y) + 84 : (a.y + b.y) / 2 - 6;
        this.edgeLayer.append(svg("text", { x: mx, y: my, "text-anchor": "middle", class: "edge-label" }, e.label));
      }
    }
  },

  drawNode(n) {
    const svg = this.svg;
    const p = this.pos[n.id];
    const g = svg("g", { class: "node" + (n.type !== "event" ? " pseudo" : "") + (n.id === this.selected ? " sel" : ""), transform: `translate(${p.x},${p.y})` });
    g.dataset.id = n.id;
    const clip = (s, max) => (s.length > max ? s.slice(0, max - 1) + "…" : s);
    if (n.type === "event") {
      const ev = n.ev;
      const color = EVENT_COLORS[ev.type] || "#888";
      g.append(svg("rect", { class: "box", width: n.w, height: n.h, rx: 9 }));
      g.append(svg("rect", { width: 5, height: n.h - 2, x: 1, y: 1, rx: 3, fill: color }));
      g.append(svg("text", { x: 14, y: 19, class: "nid" }, `${ev.id}${ev.numeral ? " · " + ev.numeral : ""} · ${EVENT_TYPES[ev.type] || ev.type}${ev.node ? " · " + ev.node : ""}`));
      g.append(svg("text", { x: 14, y: 38, class: "head" }, clip(ev.title || "(без названия)", 28)));
      g.append(svg("line", { x1: 8, x2: n.w - 8, y1: HEAD_H - 2, y2: HEAD_H - 2, stroke: "#2A2D3A" }));
      (ev.options || []).forEach((o, i) => {
        const y = HEAD_H + i * OPT_H;
        const row = svg("g", { class: "opt-row" });
        row.append(svg("rect", { class: "opt-bg", x: 6, y, width: n.w - 12, height: OPT_H, rx: 4 }));
        const req = o.check === "auto" ? "авто" : o.check === "combat" ? "бой" : Object.entries(o.req || {}).map(([s, v]) => STAT_NAMES[s][0] + v).join(" ");
        row.append(svg("text", { x: 14, y: y + 15, class: "opt" + (o.story ? " story" : "") }, `${i + 1}. ${clip(o.label || "", 24)}${o.story ? " ★" : ""}`));
        row.append(svg("text", { x: n.w - 16, y: y + 15, class: "nid", "text-anchor": "end" }, req));
        const port = svg("circle", { class: "port", cx: n.w, cy: y + OPT_H / 2, r: 5.5 });
        port.onmousedown = (e) => this.startLink(e, n.id, i);
        row.append(port);
        g.append(row);
      });
      const hp = svg("circle", { class: "port", cx: n.w, cy: HEAD_H / 2, r: 5.5 });
      hp.append(svg("title", {}, "Связь от события целиком (следующее по сюжету)"));
      hp.onmousedown = (e) => this.startLink(e, n.id, "head");
      g.append(hp);
    } else {
      const color = { init: "#8A6BB8", chapter: "#6FA47B", region: "#5A5E6E" }[n.type];
      g.append(svg("rect", { class: "box", width: n.w, height: n.h, rx: 22, stroke: color }));
      g.append(svg("text", { x: 16, y: 18, class: "nid" }, { init: "инициатор ", chapter: "", region: "" }[n.type] + n.sub));
      g.append(svg("text", { x: 16, y: 35, class: "head" }, clip(n.title || n.id, 22)));
    }
    g.onmousedown = (e) => this.startDrag(e, n.id);
    g.ondblclick = (e) => { e.stopPropagation(); this.centerOn(n.id); };
    return g;
  },

  applyTransform() {
    if (this.world) this.world.setAttribute("transform", `translate(${this.t.x},${this.t.y}) scale(${this.t.k})`);
  },

  applyDim() {
    const q = this.query.trim().toLowerCase();
    this.svgEl.querySelectorAll(".node").forEach((el) => {
      const n = this.nodes[el.dataset.id];
      const text = n.type === "event" ? n.id + " " + (n.ev.title || "") : n.id + " " + (n.title || "");
      el.classList.toggle("dim", !!q && !text.toLowerCase().includes(q));
    });
  },

  fit() {
    const ids = Object.keys(this.pos);
    if (!ids.length) return;
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const id of ids) {
      const p = this.pos[id], n = this.nodes[id];
      x0 = Math.min(x0, p.x); y0 = Math.min(y0, p.y); x1 = Math.max(x1, p.x + n.w); y1 = Math.max(y1, p.y + n.h);
    }
    const W = this.wrap.clientWidth || 1000, H = this.wrap.clientHeight || 700;
    const k = Math.min(1.2, Math.max(0.15, Math.min((W - 60) / (x1 - x0), (H - 110) / (y1 - y0))));
    this.t = { k, x: 30 - x0 * k, y: 60 - y0 * k };
    this.applyTransform();
  },

  centerOn(id) {
    const p = this.pos[id], n = this.nodes[id];
    if (!p) return;
    const W = this.wrap.clientWidth || 1000, H = this.wrap.clientHeight || 700;
    const k = Math.max(this.t.k, 0.8);
    this.t = { k, x: W / 2 - (p.x + n.w / 2) * k, y: H / 2 - (p.y + n.h / 2) * k };
    this.applyTransform();
  },

  toWorld(e) {
    const r = this.wrap.getBoundingClientRect();
    return { x: (e.clientX - r.left - this.t.x) / this.t.k, y: (e.clientY - r.top - this.t.y) / this.t.k };
  },

  bindPanZoom(svgRoot) {
    svgRoot.onmousedown = (e) => {
      if (e.button !== 0 || e.target.closest(".node")) return;
      const sx = e.clientX, sy = e.clientY, t0 = { ...this.t };
      let moved = false;
      this.wrap.classList.add("panning");
      const move = (ev) => {
        if (Math.abs(ev.clientX - sx) + Math.abs(ev.clientY - sy) > 3) moved = true;
        this.t.x = t0.x + ev.clientX - sx; this.t.y = t0.y + ev.clientY - sy; this.applyTransform();
      };
      const up = () => {
        this.wrap.classList.remove("panning");
        window.removeEventListener("mousemove", move); window.removeEventListener("mouseup", up);
        if (!moved) { this.select(null); }
      };
      window.addEventListener("mousemove", move); window.addEventListener("mouseup", up);
    };
    svgRoot.onwheel = (e) => {
      e.preventDefault();
      const r = this.wrap.getBoundingClientRect();
      const mx = e.clientX - r.left, my = e.clientY - r.top;
      const k = Math.min(2.5, Math.max(0.1, this.t.k * Math.exp(-e.deltaY * 0.0015)));
      this.t.x = mx - (mx - this.t.x) * (k / this.t.k);
      this.t.y = my - (my - this.t.y) * (k / this.t.k);
      this.t.k = k;
      this.applyTransform();
    };
  },

  startDrag(e, id) {
    if (e.button !== 0 || e.target.classList.contains("port")) return;
    e.stopPropagation();
    const w0 = this.toWorld(e), p0 = { ...this.pos[id] };
    let moved = false;
    const el = this.svgEl.querySelector(`.node[data-id="${CSS.escape(id)}"]`);
    const move = (ev) => {
      const w = this.toWorld(ev);
      if (!moved && Math.abs(w.x - w0.x) + Math.abs(w.y - w0.y) < 4 / this.t.k) return;
      moved = true;
      this.pos[id] = { x: Math.round(p0.x + w.x - w0.x), y: Math.round(p0.y + w.y - w0.y) };
      el.setAttribute("transform", `translate(${this.pos[id].x},${this.pos[id].y})`);
      this.drawEdges();
    };
    const up = () => {
      window.removeEventListener("mousemove", move); window.removeEventListener("mouseup", up);
      if (moved) {
        DB.layout[id] = this.pos[id];
        DB.layoutDirty = true;
        App.refreshStatus();
      } else if (this.nodes[id].type === "event") this.select(id);
      else if (this.nodes[id].type === "init") App.go("cards", { select: id.slice(5), kind: "initiator" });
    };
    window.addEventListener("mousemove", move); window.addEventListener("mouseup", up);
  },

  // Тянем связь от порта варианта к событию.
  startLink(e, from, port) {
    e.stopPropagation();
    e.preventDefault();
    const a = this.portPos(from, port, "out");
    const line = this.svg("path", { class: "drag-line", d: `M${a.x},${a.y}` });
    this.world.append(line);
    const move = (ev) => {
      const w = this.toWorld(ev);
      line.setAttribute("d", `M${a.x},${a.y} C${a.x + 80},${a.y} ${w.x - 80},${w.y} ${w.x},${w.y}`);
    };
    const up = (ev) => {
      window.removeEventListener("mousemove", move); window.removeEventListener("mouseup", up);
      line.remove();
      const target = document.elementFromPoint(ev.clientX, ev.clientY);
      const node = target && target.closest && target.closest(".node");
      if (node && node.dataset.id !== from && this.nodes[node.dataset.id].type === "event") this.linkDialog(from, port, node.dataset.id);
    };
    window.addEventListener("mousemove", move); window.addEventListener("mouseup", up);
  },

  async linkDialog(from, port, to) {
    const { ev, file } = this.events()[from];
    const opt = typeof port === "number" ? ev.options[port] : null;
    const choices = [];
    choices.push({ label: "Следующее по сюжету (next)", value: "next", primary: !!(opt && opt.story) || !opt });
    if (opt) {
      choices.push({ label: "Создать при успехе", value: "spawn", primary: !opt.story });
      choices.push({ label: "Создать при провале", value: "spawn_fail" });
      choices.push({ label: "Раскрыть последствия", value: "reveal" });
    }
    const text = h("div", null,
      h("p", null, `Связать ${opt ? `вариант «${opt.label}» события` : "событие"} ${from} → ${to} «${this.events()[to].ev.title}».`),
      h("ul", { class: "muted" },
        h("li", null, "Следующее по сюжету — событие появится после успеха сюжетного варианта (поле next)."),
        opt ? h("li", null, "Создать при успехе/провале — последствие spawn_event: событие откроется на карте.") : null,
        opt ? h("li", null, "Раскрыть последствия — игрок заранее увидит варианты того события.") : null));
    const kind = await modal("Новая связь", text, [{ label: "Отмена", value: null }, ...choices]);
    if (!kind) return;
    if (kind === "next") {
      if (ev.next && ev.next !== to && !(await confirmBox("Заменить связь", `У ${from} уже есть следующее событие ${ev.next}. Заменить на ${to}?`, "Заменить"))) return;
      ev.next = to;
      if (opt && !opt.story && ev.type === "story") toast("Подсказка: next срабатывает от сюжетного варианта (★)", "warn", 5000);
    } else if (kind === "reveal") {
      (opt.on_success = opt.on_success || []).push({ cmd: "reveal", event: to, text: `Раскрыто: ${this.events()[to].ev.title}` });
      this.showReveal = true;
    } else {
      const key = kind === "spawn_fail" ? "on_failure" : "on_success";
      (opt[key] = opt[key] || []).push({ cmd: "spawn_event", event: to });
    }
    touch(file);
    this.draw();
    this.renderPanel();
  },

  async edgeMenu(e) {
    const st = EDGE_STYLE[e.type];
    const fromName = this.nodes[e.from].type === "event" ? `${e.from} «${this.nodes[e.from].ev.title}»` : this.nodes[e.from].title;
    const toName = this.nodes[e.to].type === "event" ? `${e.to} «${this.nodes[e.to].ev.title}»` : this.nodes[e.to].title;
    const opt = typeof e.port === "number" ? this.nodes[e.from].ev.options[e.port] : null;
    const body = h("div", null,
      h("p", null, h("b", { style: { color: st.color } }, st.label)),
      h("p", null, fromName, opt ? ` · вариант «${opt.label}»` : "", " → ", toName));
    const r = await modal("Связь", body, [
      { label: "Закрыть", value: null },
      { label: "Открыть источник", value: "from" },
      { label: "Открыть цель", value: "to" },
      { label: "Удалить связь", danger: true, value: "del" }]);
    if (r === "from" && this.nodes[e.from].type === "event") { this.select(e.from); this.centerOn(e.from); }
    if (r === "to" && this.nodes[e.to].type === "event") { this.select(e.to); this.centerOn(e.to); }
    if (r === "del") this.deleteEdge(e);
  },

  deleteEdge(e) {
    const evs = this.events();
    if (e.type === "next") { delete evs[e.from].ev.next; delete evs[e.from].ev.next_immediate; touch(evs[e.from].file); }
    else if (e.eff && e.effs) { e.effs.splice(e.effs.indexOf(e.eff), 1); touch(evs[e.from].file); }
    else if (e.init) { e.init.event = ""; touch(F.initiators); toast("У инициатора не осталось события — выберите новое в карточке", "warn"); }
    else if (e.region) { e.region.random_pool = e.region.random_pool.filter((x) => x !== e.to); touch(F.regions); }
    else if (e.chapter && e.anchor) {
      if (e.dep) e.anchor.after = e.anchor.after.filter((x) => x !== e.dep);
      else { const key = e.thread ? "threads" : "anchors"; e.chapter[key] = e.chapter[key].filter((a) => a !== e.anchor); }
      touch(F.chapters);
    } else if (e.type === "final") { toast("Финал главы меняется в поле «Финальное событие» у главы (data/chapters.json)", "warn"); return; }
    this.draw();
    this.renderPanel();
    toast("Связь удалена", "info");
  },

  select(id) {
    this.selected = id;
    if (this.svgEl) this.svgEl.querySelectorAll(".node").forEach((el) => el.classList.toggle("sel", el.dataset.id === id));
    if (this.svgEl) this.svgEl.querySelectorAll(".edge").forEach((el) => el.classList.toggle("hl", !!id && (el.dataset.from === id || el.dataset.to === id)));
    this.renderPanel();
    App.params = id ? { select: id } : {};
  },

  // Перерисовать один узел после правки (заголовок, варианты).
  redrawNode(id) {
    const old = this.svgEl.querySelector(`.node[data-id="${CSS.escape(id)}"]`);
    const g = this.buildGraph();
    const n = g.nodes[id];
    if (!old || !n) return;
    this.nodes[id] = n;
    old.replaceWith(this.drawNode(n));
  },

  // ---- панель события --------------------------------------------------------------------------
  renderPanel() {
    const P = this.panel;
    P.innerHTML = "";
    const rec = this.selected && this.events()[this.selected];
    if (!rec) {
      const g = this.graph || { dangling: [] };
      P.append(h("div", { class: "detail-body" },
        h("h3", null, "Древо событий"),
        h("p", { class: "muted" }, "Каждый узел — событие с тремя вариантами выбора. Линии показывают, что происходит дальше: какое событие откроется после сюжетного варианта, какие события создаются последствиями, что открывают инициаторы и главы."),
        h("ul", { class: "muted" },
          h("li", null, "Щелчок по событию — редактор справа."),
          h("li", null, "Тяните от кружка ● справа у варианта к другому событию — новая связь."),
          h("li", null, "Щелчок по линии — удалить связь или перейти."),
          h("li", null, "Узлы можно двигать; колесо — масштаб, фон — сдвиг.")),
        g.dangling.length ? h("div", { class: "section" }, h("h4", null, "Связи в никуда"),
          h("ul", { class: "issues" }, g.dangling.map((e) => h("li", { class: "err" }, `${e.from} → ${e.to} (${EDGE_STYLE[e.type].label})`)))) : null));
      return;
    }
    const { ev, file } = rec;
    const changed = () => { touch(file); this.redrawNode(ev.id); this.drawEdges(); };
    const structural = () => { touch(file); this.draw(); this.renderPanel(); };
    const handled = new Set(["id", "type", "title", "text", "tags", "options", "next", "next_immediate", "on_appear", "on_success_common",
      "arc", "region", "chapter", "node", "numeral", "trauma_pool", "source", "source_kind", "once", "map_pos", "art", "enemy", "danger"]);
    const regions = Object.fromEntries(list(F.regions).map((r) => [r.id, r.name]));
    const chapter = byId(F.chapters, ev.chapter);
    const evOpts = Object.fromEntries(Object.entries(this.events()).filter(([id]) => id !== ev.id).map(([id, r]) => [id, `${id} — ${r.ev.title}`]));

    const head = h("div", { class: "detail-head" }, h("div", { class: "head-info" },
      h("div", { class: "kind" }, h("span", { class: "type-dot", style: { background: EVENT_COLORS[ev.type] } }), EVENT_TYPES[ev.type] || ev.type,
        h("span", { class: "id" }, ev.id), h("span", { class: "muted" }, file)),
      bindInput(ev, "title", changed, { cls: "title-input", keepEmpty: true }),
      h("div", { class: "row" },
        h("button", { class: "btn small", onclick: () => App.go("cards", { select: ev.id, kind: "event" }) }, "Карточка и картинка"),
        h("button", { class: "btn small", onclick: () => this.centerOn(ev.id) }, "Показать на древе"))));

    const body = h("div", { class: "detail-body" });
    body.append(
      h("div", { class: "cols" },
        field("Тип", bindSelect(ev, "type", EVENT_TYPES, structural)),
        field("Номер (римский)", bindInput(ev, "numeral", changed)),
        field("Регион", bindSelect(ev, "region", regions, changed, { allowEmpty: true })),
        chapter ? field("Место в главе", bindSelect(ev, "node", Object.fromEntries((chapter.nodes || []).map((n) => [n.id, n.name])), changed, { allowEmpty: true })) : null,
        field("Пул травм", bindSelect(ev, "trauma_pool", POOLS, changed, { allowEmpty: true })),
        field("Источник", bindInput(ev, "source", changed))),
      field("Текст события", bindInput(ev, "text", changed, { type: "textarea", rows: 4, keepEmpty: true })),
      h("div", { class: "section" }, h("h4", null, "Теги проверки"), tagRow(ev.tags = ev.tags || [], changed, { context: true })),
      h("div", { class: "section" }, h("h4", null, "Дальше"),
        h("div", { class: "cols" },
          field("Следующее по сюжету", bindSelect(ev, "next", evOpts, structural, { allowEmpty: true, emptyLabel: "— нет —" }), "появится после успеха сюжетного варианта ★"),
          h("label", { class: "field inline" }, bindInput(ev, "next_immediate", changed, { type: "checkbox" }), h("span", null, "сразу, без задержки")))),
      this.effectsBlock("При появлении события", ev, "on_appear", structural),
      this.effectsBlock("Общее при любом успехе", ev, "on_success_common", structural));

    const optsBox = h("div", { class: "section" }, h("h4", null, "Варианты выбора",
      h("button", { class: "btn small add", onclick: () => {
        const n = (ev.options || []).length + 1;
        (ev.options = ev.options || []).push({ id: `${ev.id}_${n}`, label: `Вариант ${n}`, req: { power: 3 }, on_success: [], ok_text: "", fail_text: "" });
        structural();
      } }, "+ вариант")));
    (ev.options || []).forEach((o, i) => optsBox.append(this.optionCard(ev, o, i, changed, structural)));
    if ((ev.options || []).length !== 3) optsBox.append(h("p", { class: "err" }, `Вариантов ${(ev.options || []).length} — игре нужно ровно 3.`));
    body.append(optsBox, CardsView.extraFields(ev, handled, changed));

    const foot = h("div", { class: "detail-foot" },
      h("button", { class: "btn", onclick: () => this.duplicateEvent(ev, file) }, "Дублировать"),
      h("button", { class: "btn", onclick: async () => {
        const r = await ask("Сменить id события", [{ key: "id", label: "Новый id", value: ev.id, hint: "Ссылки и id вариантов обновятся" }]);
        if (!r || !r.id || r.id === ev.id) return;
        if (this.events()[r.id]) { toast("Такой id уже есть", "err"); return; }
        renameIdEverywhere(ev.id, r.id);
        this.selected = r.id;
        this.draw();
        this.renderPanel();
      } }, "Сменить id"),
      h("span", { class: "grow" }),
      h("button", { class: "btn danger", onclick: () => this.deleteEvent(ev, file) }, "Удалить событие"));
    P.append(head, body, foot);
  },

  optionCard(ev, o, i, changed, structural) {
    const checks = { stat: "Проверка характеристик", gate_stat: "Проверка с условием", auto: "Автоуспех", combat: "Бой" };
    const card = h("div", { class: "opt-card" + (o.story ? " story" : "") });
    const check = o.check || "stat";
    card.append(
      h("div", { class: "opt-head" }, h("span", { class: "num" }, i + 1), bindInput(o, "label", changed, { keepEmpty: true }),
        h("label", { class: "field inline", title: "Сюжетный вариант продвигает историю (next)" },
          h("input", { type: "checkbox", checked: !!o.story, onchange: (e) => {
            if (e.target.checked) { for (const x of ev.options) delete x.story; o.story = true; } else delete o.story;
            structural();
          } }), h("span", null, "★ сюжет")),
        h("button", { class: "icon-btn del", title: "Удалить вариант", onclick: async () => {
          if (!(await confirmBox("Удалить вариант", `Удалить «${o.label}»?`))) return;
          ev.options.splice(i, 1); structural();
        } }, "×")),
      h("div", { class: "cols" },
        field("Проверка", h("select", { onchange: (e) => { if (e.target.value === "stat") delete o.check; else o.check = e.target.value; structural(); } },
          Object.entries(checks).map(([k, v]) => h("option", { value: k, selected: k === check }, v)))),
        field("Травм при провале", bindInput(o, "failure_traumas", changed, { type: "number" })),
        field("Пул травм", bindSelect(o, "trauma_pool", POOLS, changed, { allowEmpty: true, emptyLabel: "как у события" })),
        field("Цена: осколки", this.costInput(o, "shards", changed)),
        field("Цена: мана", this.costInput(o, "mana", changed))));
    if (check === "stat" || check === "gate_stat") {
      o.req = o.req || {};
      card.append(h("div", { class: "mini-h" }, "Требования"), statsEditor(o.req, changed));
    }
    if (check === "combat") {
      const spec = o.combat = o.combat || { enemies: [] };
      card.append(h("div", { class: "mini-h" }, "Бой"), h("div", { class: "cols" },
        field("Противники (id через запятую)", listInput(spec, "enemies", changed, "M01, M01")),
        field("Поле боя", bindSelect(spec, "field", Object.fromEntries(list(F.fields).map((f) => [f.id, `${f.id} — ${f.name}`])), changed, { allowEmpty: true })),
        field("Вид", bindSelect(spec, "kind", { normal: "обычный", elite: "элита", boss: "босс" }, changed, { allowEmpty: true }))));
    }
    o.tags = o.tags || [];
    const tagsRow = tagRow(o.tags, () => { if (!o.tags.length) delete o.tags; changed(); }, { context: true, small: true });
    if (!o.tags.length) delete o.tags;
    card.append(h("div", { class: "row" }, h("span", { class: "mini-h" }, "Доп. теги проверки"), tagsRow));
    card.append(
      field("Текст успеха", bindInput(o, "ok_text", changed, { type: "textarea", rows: 2 })),
      this.effectsBlock("Последствия успеха", o, "on_success", structural),
      check !== "auto" ? field("Текст провала", bindInput(o, "fail_text", changed, { type: "textarea", rows: 2 })) : null,
      check !== "auto" ? this.effectsBlock("Последствия провала", o, "on_failure", structural) : null,
      this.jsonField("Условия доступности", o, "conditions", changed, "[{\"type\": \"in_collection\", \"card\": \"U02\", \"text\": \"Нужен Колокольчик\"}]"),
      o.req_mods ? this.jsonField("Модификаторы требований", o, "req_mods", changed) : null);
    return card;
  },

  costInput(o, res, changed) {
    const inp = h("input", { type: "number", value: (o.cost || {})[res] ?? "" });
    inp.oninput = () => {
      const c = o.cost || {};
      if (inp.value === "") delete c[res]; else c[res] = Number(inp.value);
      if (Object.keys(c).length) o.cost = c; else delete o.cost;
      changed();
    };
    return inp;
  },

  jsonField(label, o, key, changed, placeholder = "") {
    const ta = h("textarea", { class: "json", rows: o[key] ? Math.min(8, JSON.stringify(o[key], null, 1).split("\n").length) : 1, placeholder },
      o[key] ? JSON.stringify(o[key], null, 1) : "");
    const msg = h("small");
    ta.onchange = () => {
      try {
        if (!ta.value.trim()) delete o[key]; else o[key] = JSON.parse(ta.value);
        msg.textContent = ""; changed();
      } catch (e) { msg.textContent = "Ошибка JSON: " + e.message; msg.className = "err"; }
    };
    return h("div", { class: "field" }, h("span", null, label), ta, msg);
  },

  // Список последствий: сводка + форма правки по щелчку.
  effectsBlock(title, obj, key, structural) {
    const box = h("div", { class: "effects" });
    const render = () => {
      box.innerHTML = "";
      const arr = obj[key] || [];
      box.append(h("div", { class: "mini-h" }, title, h("button", { class: "btn small add", onclick: async () => {
        const r = await ask("Новое последствие", [{ key: "cmd", label: "Команда", type: "select", value: "add_temp",
          options: Object.fromEntries(Object.entries(EFFECTS).map(([k, v]) => [k, `${v.name} (${k})`])) }]);
        if (!r) return;
        (obj[key] = obj[key] || []).push({ cmd: r.cmd });
        touchCurrent();
        render();
        box.querySelectorAll(".effect")[obj[key].length - 1].querySelector(".sum").click();
      } }, "+")));
      arr.forEach((e, i) => {
        const row = h("div", { class: "effect" });
        const sum = h("span", { class: "sum", style: { cursor: "pointer" }, title: "Щелчок — изменить" }, effectSummary(e));
        const del = h("button", { class: "icon-btn del", title: "Удалить", onclick: () => { arr.splice(i, 1); if (!arr.length) delete obj[key]; structural(); } }, "×");
        sum.onclick = () => {
          if (row.classList.toggle("open")) row.append(this.effectForm(e, () => { sum.textContent = effectSummary(e); touchCurrent(); }));
          else { row.querySelector(".effect-form")?.remove(); structural(); }
        };
        row.append(h("div", { class: "row" }, sum, del));
        box.append(row);
      });
      if (!arr.length) box.append(h("div", { class: "muted", style: { fontSize: "12px" } }, "нет"));
    };
    const touchCurrent = () => { const r = this.events()[this.selected]; if (r) touch(r.file); };
    render();
    return box;
  },

  effectForm(e, changed) {
    const def = EFFECTS[e.cmd] || { fields: {} };
    const form = h("div", { class: "effect-form" });
    form.append(h("span", null, "Команда"), bindSelect(e, "cmd", Object.fromEntries(Object.entries(EFFECTS).map(([k, v]) => [k, v.name])), () => {
      const r = form.parentElement; changed(); form.replaceWith(this.effectForm(e, changed)); void r;
    }));
    const fields = { ...def.fields, if_flag: "text", unless_flag: "text" };
    for (const [k, t] of Object.entries(fields)) {
      let inp;
      if (t === "card") inp = idSelect(e, k, ["character", "enhancement", "initiator", "ability", "trauma", "enemy"], changed);
      else if (t === "ability") inp = idSelect(e, k, ["ability"], changed);
      else if (t === "trauma") inp = idSelect(e, k, ["trauma"], changed);
      else if (t === "character") inp = idSelect(e, k, ["character"], changed);
      else if (t === "event") inp = idSelect(e, k, ["event"], changed);
      else if (t === "stat") inp = bindSelect(e, k, STAT_NAMES, changed, { allowEmpty: true });
      else if (t === "number") inp = bindInput(e, k, changed, { type: "number" });
      else if (t === "list") inp = listInput(e, k, changed);
      else if (t === "tags" || t === "ctxtags") {
        e[k] = e[k] || [];
        inp = tagRow(e[k], () => { if (!e[k].length) delete e[k]; changed(); }, { context: t === "ctxtags", small: true });
        if (!e[k].length) delete e[k];
      } else if (Array.isArray(t)) inp = bindSelect(e, k, t, changed, { allowEmpty: true });
      else inp = bindInput(e, k, changed);
      form.append(h("span", null, k), inp);
    }
    return form;
  },

  // ---- создание / удаление -------------------------------------------------------------------
  async createEvent() {
    const files = Object.fromEntries(eventFiles().map((f) => [f, f.replace("data/events/", "")]));
    const r = await ask("Новое событие", [
      { key: "file", label: "Файл (арка)", type: "select", value: eventFiles()[0], options: files },
      { key: "id", label: "id", value: "", hint: "Пусто — следующий свободный E…" },
      { key: "type", label: "Тип", type: "select", value: "story", options: EVENT_TYPES },
      { key: "title", label: "Название", value: "" },
    ]);
    if (!r) return;
    const evs = this.events();
    let id = r.id;
    if (!id) { let n = 1; while (evs["E" + String(n).padStart(2, "0")]) n++; id = "E" + String(n).padStart(2, "0"); }
    if (evs[id] || findCard(id)) { toast(`id ${id} уже занят`, "err"); return; }
    const sample = list(r.file)[0] || {};
    const ev = { id, type: r.type, arc: sample.arc, region: sample.region, title: r.title || id, text: "", tags: [], trauma_pool: "all", options: [] };
    if (sample.chapter) { ev.chapter = sample.chapter; ev.node = sample.node; }
    for (let i = 1; i <= 3; i++) {
      const o = { id: `${id}_${i}`, label: `Вариант ${i}`, req: { power: 3 + i }, on_success: [], ok_text: "", fail_text: "" };
      if (r.type === "reward") { delete o.req; delete o.fail_text; o.check = "auto"; }
      if (r.type === "story" && i === 1) o.story = true;
      ev.options.push(o);
    }
    for (const k of Object.keys(ev)) if (ev[k] === undefined) delete ev[k];
    list(r.file).push(ev);
    touch(r.file);
    this.selected = id;
    this.draw();
    this.renderPanel();
    this.centerOn(id);
    toast(`Событие ${id} создано. Свяжите его: тяните от ● варианта другого события.`, "ok", 5000);
  },

  async duplicateEvent(ev, file) {
    const r = await ask("Копия события", [{ key: "id", label: "Новый id", value: ev.id + "_copy" }]);
    if (!r || !r.id) return;
    if (this.events()[r.id]) { toast("Такой id уже есть", "err"); return; }
    const copy = clone(ev);
    copy.id = r.id;
    delete copy.next;
    (copy.options || []).forEach((o, i) => (o.id = `${r.id}_${i + 1}`));
    const arr = list(file);
    arr.splice(arr.indexOf(ev) + 1, 0, copy);
    touch(file);
    this.selected = r.id;
    this.draw();
    this.renderPanel();
    this.centerOn(r.id);
  },

  async deleteEvent(ev, file) {
    const refs = idRefs(ev.id).filter((x) => x.obj !== ev);
    const body = h("div", null, h("p", null, `Удалить событие ${ev.id} «${ev.title}»?`),
      refs.length ? h("div", null, h("p", null, `Ссылки на него (${refs.length}) будут убраны: next, последствия, пулы регионов, якоря глав.`),
        h("ul", { class: "issues" }, refs.slice(0, 15).map((x) => h("li", null, `${x.obj.id} (${x.file}) › ${x.path}`)))) : null);
    if (!(await modal("Удаление события", body, [{ label: "Отмена", value: false }, { label: "Удалить", danger: true, value: true }]))) return;
    const id = ev.id;
    DB.files[file] = list(file).filter((x) => x !== ev);
    touch(file);
    for (const f of eventFiles()) {
      let hit = false;
      for (const e of list(f)) {
        if (e.next === id) { delete e.next; hit = true; }
        const clean = (arr) => arr && arr.filter((x) => !(["spawn_event", "reveal", "combat_mod"].includes(x.cmd) && x.event === id));
        for (const k of ["on_appear", "on_success_common"]) if (e[k]) { const c = clean(e[k]); if (c.length !== e[k].length) { e[k] = c; hit = true; } }
        for (const o of e.options || []) for (const k of ["on_success", "on_failure"]) if (o[k]) { const c = clean(o[k]); if (c.length !== o[k].length) { o[k] = c; hit = true; } }
      }
      if (hit) touch(f);
    }
    for (const r of list(F.regions)) if ((r.random_pool || []).includes(id)) { r.random_pool = r.random_pool.filter((x) => x !== id); touch(F.regions); }
    for (const ch of list(F.chapters)) {
      const before = JSON.stringify(ch);
      ch.anchors = (ch.anchors || []).filter((a) => a.event !== id);
      ch.threads = (ch.threads || []).filter((a) => a.event !== id);
      for (const a of [...ch.anchors, ...ch.threads]) if (a.after) a.after = a.after.filter((x) => x !== id);
      if (JSON.stringify(ch) !== before) touch(F.chapters);
    }
    if (list(F.initiators).some((i) => i.event === id)) toast("Инициатор ссылался на это событие — выберите ему новое", "warn", 6000);
    delete DB.layout[id];
    this.selected = null;
    this.draw();
    this.renderPanel();
    toast(`${id} удалено (сохраните, чтобы применить)`, "info");
  },
};
