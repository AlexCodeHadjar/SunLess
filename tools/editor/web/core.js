// Ядро редактора: данные проекта, изменения, сохранение, ссылки между данными, проверка.
"use strict";

const F = {
  characters: "data/characters.json",
  enhancements: "data/enhancements.json",
  abilities: "data/abilities.json",
  traumas: "data/traumas.json",
  initiators: "data/initiators.json",
  enemies: "data/combat/enemies.json",
  ctxTags: "data/tags.json",
  tags: "data/combat/tags.json",
  lore: "data/lore.json",
  synergies: "data/combat/synergies.json",
  conflicts: "data/combat/conflicts.json",
  fields: "data/combat/fields.json",
  roundCards: "data/combat/round_cards.json",
  tactics: "data/combat/tactics.json",
  enemyAbilities: "data/combat/enemy_abilities.json",
  chapters: "data/chapters.json",
  regions: "data/regions.json",
};

const STATS = ["power", "will", "cunning"];
const STAT_NAMES = { power: "Сила", will: "Воля", cunning: "Хитрость" };
const STAT_ICONS = { power: "art/ui/icon_power.png", will: "art/ui/icon_will.png", cunning: "art/ui/icon_cunning.png" };
const RARITY = {
  common: ["Обычная", "#8A8D96"], rare: ["Редкая", "#5E86B0"], epic: ["Эпическая", "#8A6BB8"],
  legendary: ["Легендарная", "#B89A5E"], mythic: ["Мифическая", "#E8E8F0"],
};
const CATEGORIES = {
  element: ["Стихия", "#D9975A"], material: ["Материал", "#B8B2A6"], anatomy: ["Анатомия", "#C98F8F"],
  tactic: ["Тактика", "#C9CED6"], mystic: ["Мистика", "#A99BE0"], mind: ["Разум", "#8FB6C9"],
  state: ["Состояние", "#B65F63"], origin: ["Происхождение", "#B89A5E"], sense: ["Чувства", "#9AC7A8"],
  field: ["Местность", "#8DA6BF"], time: ["Время и погода", "#C7C39A"],
};
const EVENT_TYPES = { story: "Сюжетное", reward: "Награда", side: "Побочное", random: "Случайное" };
const POOLS = { all: "Любые", physical: "Физические", environment: "Среда", mental: "Ментальные" };

const DB = {
  files: {}, art: new Set(), layout: {}, godot: false,
  dirty: new Set(), images: new Map(), layoutDirty: false,
};

// --- утилиты -------------------------------------------------------------------

function h(tag, attrs, ...kids) {
  const el = document.createElement(tag);
  if (attrs) {
    for (const [k, v] of Object.entries(attrs)) {
      if (v === undefined || v === null || v === false) continue;
      if (k === "class") el.className = v;
      else if (k === "style" && typeof v === "object") Object.assign(el.style, v);
      else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
      else if (k === "html") el.innerHTML = v;
      else if (v === true) el.setAttribute(k, "");
      else el.setAttribute(k, v);
    }
  }
  for (const kid of kids.flat(Infinity)) {
    if (kid === null || kid === undefined || kid === false) continue;
    el.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
  }
  return el;
}

const clone = (o) => JSON.parse(JSON.stringify(o));
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const projectUrl = (rel) => "/project/" + rel.split("/").map(encodeURIComponent).join("/");

function toast(text, kind = "info", ms = 3500) {
  const t = h("div", { class: "toast " + kind }, text);
  document.getElementById("toasts").append(t);
  setTimeout(() => t.classList.add("out"), ms);
  setTimeout(() => t.remove(), ms + 400);
}

// Модальное окно: возвращает Promise с результатом кнопки.
function modal(title, body, buttons = [{ label: "OK", value: true, primary: true }], opts = {}) {
  return new Promise((resolve) => {
    const ov = document.getElementById("overlay");
    ov.hidden = false;
    ov.innerHTML = "";
    const close = (v) => { ov.hidden = true; ov.innerHTML = ""; document.removeEventListener("keydown", onKey); resolve(v); };
    const onKey = (e) => { if (e.key === "Escape") close(null); };
    document.addEventListener("keydown", onKey);
    const box = h("div", { class: "modal" + (opts.wide ? " wide" : "") },
      h("div", { class: "modal-head" }, h("h3", null, title), h("button", { class: "x", onclick: () => close(null) }, "×")),
      h("div", { class: "modal-body" }, body),
      h("div", { class: "modal-foot" }, buttons.map((b) =>
        h("button", { class: "btn " + (b.primary ? "primary" : b.danger ? "danger" : "ghost"), onclick: () => close(typeof b.value === "function" ? b.value() : b.value) }, b.label))));
    ov.append(box);
    ov.onclick = (e) => { if (e.target === ov) close(null); };
    const first = box.querySelector("input, textarea, select");
    if (first) setTimeout(() => first.focus(), 30);
  });
}

async function ask(title, fields) {
  // fields: [{key, label, value, type: text|number|select|textarea, options: {v: label}}]
  const inputs = {};
  const body = h("div", { class: "form" }, fields.map((f) => {
    let inp;
    if (f.type === "select") {
      inp = h("select", null, Object.entries(f.options).map(([v, l]) => h("option", { value: v, selected: v === f.value }, l)));
    } else if (f.type === "textarea") {
      inp = h("textarea", { rows: 4 }, f.value || "");
    } else {
      inp = h("input", { type: f.type || "text", value: f.value ?? "" });
    }
    inputs[f.key] = inp;
    return h("label", { class: "field" }, h("span", null, f.label), inp, f.hint ? h("small", null, f.hint) : null);
  }));
  body.addEventListener("keydown", (e) => { if (e.key === "Enter" && e.target.tagName === "INPUT") body.closest(".modal").querySelector(".btn.primary").click(); });
  const res = await modal(title, body, [
    { label: "Отмена", value: null },
    { label: "Готово", primary: true, value: () => Object.fromEntries(Object.entries(inputs).map(([k, i]) => [k, i.type === "number" ? Number(i.value) : i.value.trim()])) },
  ]);
  return res;
}

const confirmBox = (title, text, label = "Удалить") =>
  modal(title, h("div", null, text), [{ label: "Отмена", value: false }, { label, danger: true, value: true }]);

// --- данные ----------------------------------------------------------------------

const list = (rel) => DB.files[rel] || (DB.files[rel] = []);
const eventFiles = () => Object.keys(DB.files).filter((f) => f.startsWith("data/events/")).sort();
const byId = (rel, id) => list(rel).find((x) => x.id === id);

function touch(rel) {
  DB.dirty.add(rel);
  App.refreshStatus();
}

async function loadData() {
  const r = await fetch("/api/data");
  const d = await r.json();
  if (d.error) throw new Error(d.error);
  DB.files = d.files;
  DB.art = new Set(d.art);
  DB.layout = d.layout || {};
  DB.godot = d.godot;
  DB.versions = d.versions || {};
  DB.signature = d.signature || "";
  DB.game = d.game || {};
  DB.dirty.clear();
  DB.images.clear();
  DB.layoutDirty = false;
  applyGameDefs();
  snapshot();
}

// Снимок тегов и противников на момент загрузки/сохранения — для файла правок генератора.
function snapshot() {
  DB.orig = { tags: clone(list(F.tags)), enemies: clone(list(F.enemies)) };
  DB.renames = [];
}

// tools/gen_combat_data.py пересобирает теги и противников из docs/12; всё, что поменяли здесь,
// записываем в editor_overrides.json — генератор применит это поверх документа.
const OVERRIDES = "data/combat/editor_overrides.json";
function updateOverrides() {
  if (!DB.dirty.has(F.tags) && !DB.dirty.has(F.enemies) && !DB.renames.length) return;
  const ov = DB.files[OVERRIDES] || {};
  for (const k of ["renamed_tags", "tags", "enemies"]) ov[k] = ov[k] || {};
  for (const k of ["removed_tags", "removed_enemies"]) ov[k] = ov[k] || [];
  for (const [o, n] of DB.renames) {
    for (const k in ov.renamed_tags) if (ov.renamed_tags[k] === o) ov.renamed_tags[k] = n;
    if (!Object.values(ov.renamed_tags).includes(n)) ov.renamed_tags[o] = n;
    if (ov.tags[o]) { ov.tags[n] = ov.tags[o]; delete ov.tags[o]; }
  }
  const renamedFrom = new Set(DB.renames.map((r) => r[0]));
  const diff = (orig, cur, upserts, removed, skip) => {
    const before = new Map(orig.map((x) => [x.id, JSON.stringify(x)]));
    const now = new Map(cur.map((x) => [x.id, x]));
    for (const [id, x] of now) if (before.get(id) !== JSON.stringify(x)) {
      upserts[id] = clone(x);
      const i = removed.indexOf(id);
      if (i >= 0) removed.splice(i, 1);
    }
    for (const id of before.keys()) if (!now.has(id) && !skip.has(id)) {
      if (!removed.includes(id)) removed.push(id);
      delete upserts[id];
    }
  };
  diff(DB.orig.tags, list(F.tags), ov.tags, ov.removed_tags, renamedFrom);
  diff(DB.orig.enemies, list(F.enemies), ov.enemies, ov.removed_enemies, new Set());
  DB.files[OVERRIDES] = ov;
  DB.dirty.add(OVERRIDES);
}

// force — записать, даже если файл успели изменить вне редактора.
async function saveAll(force = false) {
  updateOverrides();
  const files = {}, base = {};
  for (const rel of DB.dirty) { files[rel] = DB.files[rel]; if (DB.versions[rel]) base[rel] = DB.versions[rel]; }
  const images = [...DB.images.values()].map((im) => ({ name: im.name, data: im.data, remove: im.remove }));
  const body = { files, images, base, force };
  if (DB.layoutDirty) body.layout = DB.layout;
  const r = await fetch("/api/save", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  const res = await r.json();
  if (res.conflict) { const e = new Error("файлы изменены вне редактора"); e.conflict = res.conflict; throw e; }
  if (!res.ok) throw new Error(res.error || "ошибка сохранения");
  DB.versions = res.versions || DB.versions;
  DB.signature = res.signature || DB.signature;
  for (const im of DB.images.values()) {
    for (const rm of im.remove || []) DB.art.delete(rm);
    DB.art.add("art/cards/" + im.name);
  }
  const hadImages = DB.images.size > 0;
  DB.dirty.clear();
  DB.images.clear();
  DB.layoutDirty = false;
  snapshot();
  return { ...res, hadImages };
}

// --- карты -------------------------------------------------------------------------

const KINDS = [
  { id: "character", name: "Персонажи", file: F.characters, emblem: "art/ui/emblems/character.png", prefix: "P" },
  { id: "enhancement", name: "Усиления", file: F.enhancements, emblem: "art/ui/emblems/enhancement.png", prefix: "U" },
  { id: "ability", name: "Способности", file: F.abilities, emblem: "art/ui/emblems/will.png", prefix: "A" },
  { id: "trauma", name: "Травмы", file: F.traumas, emblem: "art/ui/emblems/trauma.png", prefix: "T" },
  { id: "initiator", name: "Инициаторы", file: F.initiators, emblem: "art/ui/emblems/story.png", prefix: "I" },
  { id: "enemy", name: "Противники", file: F.enemies, emblem: "art/ui/emblems/monster.png", prefix: "M" },
  { id: "event", name: "События", file: null, emblem: "art/ui/emblems/story.png", prefix: "E" },
];
const KIND = Object.fromEntries(KINDS.map((k) => [k.id, k]));

// --- определения из кода игры --------------------------------------------------------
// Сервер читает их из core/content/*.gd, core/rules/*.gd и tag_text.gd. Всё новое, что появилось
// в игре (тип карт, команда последствия, условие, категория тегов, тип события), редактор
// подхватывает сам: русские названия и подсказки можно добавить позже, но работать можно сразу.
const AUTO_NOTES = [];

function guessFieldType(key) {
  if (["value", "min", "max", "remaining", "count", "chance", "delta", "weeks", "amount"].includes(key)) return "number";
  if (["card", "cards_card"].includes(key)) return "card";
  if (key === "event") return "event";
  if (key === "character" || key === "target") return "character";
  if (key === "ability") return "ability";
  if (key === "trauma") return "trauma";
  if (key === "stat") return "stat";
  if (key === "chapter") return "chapter";
  if (key === "region") return "region";
  if (key === "field") return "field";
  if (key === "tags") return "ctxtags";
  if (key.endsWith("_tags")) return "tags";
  if (/(s|ies)$/.test(key) && !["text", "status"].includes(key)) return "list";
  return "text";
}

function applyGameDefs() {
  const g = DB.game || {};
  AUTO_NOTES.length = 0;
  // категории боевых тегов
  for (const [k, name] of Object.entries(g.category_names || {})) {
    if (!CATEGORIES[k]) AUTO_NOTES.push(`категория тегов «${name}»`);
    CATEGORIES[k] = [name, (g.category_colors || {})[k] || (CATEGORIES[k] || [0, "#8A8D96"])[1]];
  }
  for (const t of g.event_types || []) if (!EVENT_TYPES[t]) { EVENT_TYPES[t] = t; AUTO_NOTES.push(`тип события «${t}»`); }
  for (const t of g.pools || []) if (!POOLS[t]) POOLS[t] = t;
  // команды последствий и условия: неизвестным — форма по ключам, которые читает код игры
  const merge = (schema, names, keys, what) => {
    for (const cmd of names || []) {
      const ks = ((keys || {})[cmd] || []).filter((k) => !["cmd", "type", "if_flag", "unless_flag"].includes(k));
      if (!schema[cmd]) {
        schema[cmd] = { name: cmd, auto: true, fields: Object.fromEntries(ks.map((k) => [k, guessFieldType(k)])) };
        AUTO_NOTES.push(`${what} «${cmd}» (поля: ${ks.join(", ") || "нет"})`);
      } else {
        for (const k of ks) if (!(k in schema[cmd].fields)) schema[cmd].fields[k] = guessFieldType(k);
      }
    }
  };
  merge(EFFECTS, g.commands, g.command_keys, "команда последствия");
  merge(CONDITIONS, g.conditions, g.condition_keys, "условие");
  // типы карт: всё, что игра считает картой (Content.card_kind), попадает в галерею
  for (const ck of g.card_kinds || []) {
    if (KIND[ck.kind]) { KIND[ck.kind].file = ck.file; continue; }
    const arr = DB.files[ck.file] || [];
    const prefix = arr.length ? String(arr[0].id).replace(/\d+$/, "") : ck.kind[0].toUpperCase();
    const k = { id: ck.kind, name: ck.var.charAt(0).toUpperCase() + ck.var.slice(1), file: ck.file, emblem: "art/ui/emblems/story.png", prefix, auto: true };
    KINDS.splice(KINDS.length - 1, 0, k);
    KIND[k.id] = k;
    if (typeof PREFIX_KIND !== "undefined" && prefix && !PREFIX_KIND[prefix[0]]) PREFIX_KIND[prefix[0]] = k.id;
    if (arr.some((o) => (o.tags || []).some((t) => combatTag(t)))) COMBAT_TAG_PATHS[ck.file] = ["tags[]"];
    AUTO_NOTES.push(`тип карт «${ck.kind}» (${ck.file})`);
  }
}

function allCards() {
  const out = [];
  for (const k of KINDS) {
    if (k.id === "event") {
      for (const f of eventFiles()) for (const o of list(f)) out.push({ kind: "event", id: o.id, obj: o, file: f });
    } else {
      for (const o of list(k.file)) out.push({ kind: k.id, id: o.id, obj: o, file: k.file });
    }
  }
  return out;
}

function findCard(id) {
  return allCards().find((c) => c.id === id) || null;
}

function cardName(id) {
  const c = findCard(id);
  if (c) return c.obj.name || c.obj.title || id;
  return id;
}

// Картинка карты — как в игре (scenes/cards/card_view.gd, event_tablet.gd).
function cardArt(card) {
  const pending = DB.images.get(card.id);
  if (pending) return pending.url;
  const def = card.obj;
  const fromRes = (p) => (p && p.startsWith("res://") ? p.slice(6) : p);
  const candidates = [];
  if (card.kind === "event") candidates.push("art/cards/" + card.id + ".webp", fromRes(def.art));
  else candidates.push(fromRes(def.art), "art/cards/" + card.id + ".webp", "art/cards/" + card.id + ".png");
  for (const p of candidates) if (p && DB.art.has(p)) return projectUrl(p);
  return null;
}

function lore(id) {
  return list(F.lore).find((l) => l.id === id) || null;
}

// --- теги ---------------------------------------------------------------------------

const combatTag = (name) => list(F.tags).find((t) => t.id === name);
const ctxTag = (id) => list(F.ctxTags).find((t) => t.id === id);
const tagColor = (name) => (CATEGORIES[(combatTag(name) || {}).category] || [0, "#8A8D96"])[1];
const tagIcon = (cat) => projectUrl("art/ui/tags/" + (CATEGORIES[cat] ? cat : "state") + ".png");

// Где хранятся ссылки на боевые теги: файл → пути (a/b/* — любой ключ, [] — элементы массива).
const COMBAT_TAG_PATHS = {
  [F.characters]: ["tags[]", "support_tags[]", "stages/*/tags[]"],
  [F.enhancements]: ["tags[]"],
  [F.enemies]: ["tags[]"],
  [F.synergies]: ["tags[]"],
  [F.conflicts]: ["a", "b"],
  [F.fields]: ["tags[]", "effects[]/tag"],
  [F.roundCards]: ["tags[]", "effects[]/tag"],
  [F.tactics]: ["add_tags[]", "blocked_by_env[]", "cancel_enemy_tags[]", "double_tags[]", "enemy_penalty_if/tags[]", "requires/hero_any[]", "self_tags[]"],
  [F.enemyAbilities]: ["when_tags[]", "negated_by[]", "cancel_hero_tags[]", "backfire_tags[]", "reduced_by/tags[]"],
  "@events": ["options[]/on_success[]/hero_tags[]", "options[]/on_success[]/enemy_tags[]",
    "options[]/on_failure[]/hero_tags[]", "options[]/on_failure[]/enemy_tags[]",
    "on_appear[]/hero_tags[]", "on_appear[]/enemy_tags[]", "on_success_common[]/hero_tags[]", "on_success_common[]/enemy_tags[]"],
};
// Пути, которые проверяет сама игра (core/content/content_validator.gd): ошибка там — игра не запустится.
const STRICT_TAG_PATHS = new Set([
  F.characters + ":tags[]", F.characters + ":support_tags[]", F.characters + ":stages/*/tags[]",
  F.enhancements + ":tags[]", F.enemies + ":tags[]", F.synergies + ":tags[]", F.conflicts + ":a", F.conflicts + ":b",
  F.fields + ":tags[]", F.roundCards + ":tags[]", F.tactics + ":add_tags[]", F.tactics + ":self_tags[]",
  ...["when_tags[]", "negated_by[]", "cancel_hero_tags[]", "backfire_tags[]", "reduced_by/tags[]"].map((p) => F.enemyAbilities + ":" + p),
]);
const CTX_TAG_PATHS = {
  [F.characters]: ["traits[]/bonuses[]/tags[]"],
  [F.enhancements]: ["bonuses[]/tags[]"],
  [F.abilities]: ["bonuses[]/tags[]"],
  [F.traumas]: ["context_tag"],
  "@events": ["tags[]", "options[]/tags[]", "options[]/on_success[]/tags[]", "options[]/on_failure[]/tags[]",
    "on_appear[]/tags[]", "on_success_common[]/tags[]"],
};

// Обходит все места по пути и вызывает fn(value, set, remove) для каждой строки.
function walkPath(obj, parts, fn) {
  if (obj === null || obj === undefined) return;
  const [head, ...rest] = parts;
  const isArr = head.endsWith("[]");
  const key = isArr ? head.slice(0, -2) : head;
  const keys = key === "*" ? Object.keys(obj) : [key];
  for (const k of keys) {
    const v = obj[k];
    if (v === undefined) continue;
    if (isArr) {
      if (!Array.isArray(v)) continue;
      if (rest.length === 0) {
        for (let i = v.length - 1; i >= 0; i--) {
          if (typeof v[i] === "string") fn(v[i], (nv) => { v[i] = nv; }, () => v.splice(i, 1));
        }
      } else for (const item of v) walkPath(item, rest, fn);
    } else if (rest.length === 0) {
      if (typeof v === "string") fn(v, (nv) => { obj[k] = nv; }, () => { delete obj[k]; });
    } else walkPath(v, rest, fn);
  }
}

// Все ссылки на тег: [{file, obj, path}] (obj — верхний объект файла).
function tagRefs(name, context = false) {
  const table = context ? CTX_TAG_PATHS : COMBAT_TAG_PATHS;
  const out = [];
  for (const [fk, paths] of Object.entries(table)) {
    const files = fk === "@events" ? eventFiles() : [fk];
    for (const f of files) {
      for (const obj of list(f)) {
        for (const p of paths) {
          walkPath(obj, p.split("/"), (v) => { if (v === name) out.push({ file: f, obj, path: p }); });
        }
      }
    }
  }
  return out;
}

// Переименовывает (newName) или удаляет (newName = null) тег во всех ссылках.
function replaceTag(name, newName, context = false) {
  const table = context ? CTX_TAG_PATHS : COMBAT_TAG_PATHS;
  let n = 0;
  for (const [fk, paths] of Object.entries(table)) {
    const files = fk === "@events" ? eventFiles() : [fk];
    for (const f of files) {
      let changed = false;
      for (const obj of list(f)) {
        for (const p of paths) {
          walkPath(obj, p.split("/"), (v, set, remove) => {
            if (v !== name) return;
            if (newName === null) remove(); else set(newName);
            changed = true; n++;
          });
        }
      }
      if (changed) touch(f);
    }
  }
  if (!context && newName === null) {
    // связи из одного тега бессмысленны — убираем симбиозы с ним и конфликты, где он был стороной
    const syn = list(F.synergies);
    const keep = syn.filter((s) => (s.tags || []).length >= 2);
    if (keep.length !== syn.length) { DB.files[F.synergies] = keep; touch(F.synergies); }
    const con = list(F.conflicts);
    const keepC = con.filter((c) => c.a !== undefined && c.b !== undefined);
    if (keepC.length !== con.length) { DB.files[F.conflicts] = keepC; touch(F.conflicts); }
  }
  return n;
}

// Подпись места ссылки для людей.
function refLabel(ref) {
  const o = ref.obj;
  const f = ref.file;
  const who = o.name || o.title || o.id;
  const group = {
    [F.characters]: "Персонаж", [F.enhancements]: "Усиление", [F.enemies]: "Противник", [F.abilities]: "Способность",
    [F.traumas]: "Травма", [F.synergies]: "Симбиоз", [F.conflicts]: "Конфликт", [F.fields]: "Поле боя",
    [F.roundCards]: "Карта раунда", [F.tactics]: "Приём", [F.enemyAbilities]: "Намерение врага",
  }[f] || (f.startsWith("data/events/") ? "Событие" : f);
  return { group, who, id: o.id, where: ref.path.replace(/\[\]/g, "").replace(/\//g, " › ") };
}

// --- эффекты (последствия вариантов) --------------------------------------------------

const EFFECTS = {
  add_card: { name: "Дать карту", fields: { card: "card" } },
  remove_card: { name: "Забрать карту", fields: { card: "card", text: "text" } },
  add_ability: { name: "Дать способность", fields: { ability: "ability", character: "character" } },
  add_trauma: { name: "Нанести травму", fields: { trauma: "trauma", target: "character" } },
  remove_trauma: { name: "Снять травму", fields: { target: "character", categories: "list", severities: "list" } },
  clear_traumas: { name: "Снять все травмы", fields: { target: "character", categories: "list", text: "text" } },
  set_flag: { name: "Поставить флаг", fields: { flag: "text", text: "text" } },
  clear_flag: { name: "Снять флаг", fields: { flag: "text" } },
  adjust_resource: { name: "Осколки или мана ±", fields: { resource: { shards: "осколки душ", mana: "мана" }, value: "number" } },
  add_temp: { name: "Временный бонус", fields: { stat: "stat", value: "number", label: "text", tags: "ctxtags", remaining: "number" } },
  add_perm: { name: "Бонус навсегда", fields: { stat: "stat", value: "number", character: "character" } },
  set_stage: { name: "Новая стадия персонажа", fields: { character: "character", stage: "text" } },
  reveal: { name: "Раскрыть последствия", fields: { event: "event", options: "list", text: "text" } },
  add_codex: { name: "Запись в кодекс", fields: { entry: "text", text: "text" } },
  set_region: { name: "Сменить регион", fields: { region: "region", arc: "text" } },
  remove_temporaries: { name: "Временные спутники уходят", fields: {} },
  combat_mod: { name: "Изменить будущий бой", fields: { event: "event", hero_tags: "tags", enemy_tags: "tags", add_enemies: "list", allies: "list", field: "field", text: "text" } },
  spawn_event: { name: "Открыть событие", fields: { event: "event" } },
  start_chapter: { name: "Открыть главу", fields: { chapter: "chapter" } },
  reset_wear: { name: "Сбросить износ (кузнец)", fields: {} },
  end_demo: { name: "Конец демоверсии", fields: { text: "text" } },
  text: { name: "Показать текст", fields: { text: "text" } },
};

// Условия доступности варианта (core/rules/condition_checker.gd).
const CONDITIONS = {
  in_collection: { name: "Карта есть в коллекции", fields: { card: "card" } },
  not_owned: { name: "Карты ещё нет", fields: { card: "card" } },
  executor_is: { name: "Исполнитель — определённый персонаж", fields: { ids: "list" } },
  has_flag: { name: "Стоит флаг", fields: { flag: "text", text: "text" } },
  not_flag: { name: "Флага нет", fields: { flag: "text", text: "text" } },
  owned_count: { name: "Несколько карт из списка", fields: { cards: "list", min: "number", text: "text" } },
  attached: { name: "Карта приложена к событию", fields: { card: "card" } },
  executor_has_trauma: { name: "У исполнителя есть травма", fields: { severity: "list", categories: "list", text: "text" } },
};

const FIELD_LABELS = {
  card: "Карта", text: "Текст игроку", ability: "Способность", character: "Персонаж", target: "Цель", trauma: "Травма",
  categories: "Категории травм", severities: "Тяжесть травм", severity: "Тяжесть травм", flag: "Флаг", resource: "Ресурс",
  value: "Значение", stat: "Характеристика", label: "Подпись", tags: "Теги", remaining: "Сколько проверок", stage: "Стадия",
  event: "Событие", options: "Варианты (id)", entry: "Запись кодекса", region: "Регион", arc: "Арка", hero_tags: "Теги героя",
  enemy_tags: "Теги врага", add_enemies: "Доп. противники", allies: "Союзники", field: "Поле боя", chapter: "Глава",
  if_flag: "Только если флаг", unless_flag: "Только если нет флага",
};
const COND_LABELS = { text: "Подсказка игроку", ids: "Исполнитель — один из", cards: "Карты", min: "Минимум карт" };

const REF_KEYS = ["card", "ability", "trauma", "character", "target", "event"];

function describeValue(k, v) {
  if (Array.isArray(v)) return v.map((x) => (typeof x === "string" && findCard(x) ? cardName(x) : x)).join(", ");
  if (REF_KEYS.includes(k) && typeof v === "string") return cardName(v);
  if (k === "stat") return STAT_NAMES[v] || v;
  if (k === "resource") return { shards: "осколки", mana: "мана" }[v] || v;
  if (k === "value" || k === "delta") return (v > 0 ? "+" : "") + v;
  return String(v);
}

function effectSummary(e) {
  const d = EFFECTS[e.cmd];
  const parts = Object.entries(e).filter(([k]) => k !== "cmd").map(([k, v]) => describeValue(k, v));
  return (d ? d.name : e.cmd) + (parts.length ? ": " + parts.join(" · ") : "");
}

function conditionSummary(c) {
  const d = CONDITIONS[c.type];
  const parts = Object.entries(c).filter(([k]) => k !== "type" && k !== "text").map(([k, v]) => describeValue(k, v));
  return (d ? d.name : c.type) + (parts.length ? ": " + parts.join(" · ") : "");
}

// --- проверка -----------------------------------------------------------------------------

function validate() {
  const errs = [];
  // warn — игра это не проверяет и запустится; без warn — ContentValidator покажет ошибку вместо меню
  const add = (where, text, nav, warn = false) => errs.push({ where, text, nav, warn });
  const events = {};
  for (const f of eventFiles()) for (const e of list(f)) events[e.id] = e;
  const cards = new Set(allCards().filter((c) => c.kind !== "event").map((c) => c.id));
  const tagSet = new Set(list(F.tags).map((t) => t.id));
  const ctxSet = new Set(list(F.ctxTags).map((t) => t.id));

  // дубликаты id
  for (const rel of Object.keys(DB.files)) {
    const arr = DB.files[rel];
    if (!Array.isArray(arr) || rel === F.lore) continue;
    const seen = new Set();
    for (const o of arr) {
      if (!o || o.id === undefined) { add(rel, "объект без id"); continue; }
      if (seen.has(o.id)) add(rel, `дубликат id ${o.id}`);
      seen.add(o.id);
    }
  }
  // теги
  const strict = (f, p) => STRICT_TAG_PATHS.has(f + ":" + p);
  for (const [fk, paths] of Object.entries(COMBAT_TAG_PATHS)) {
    for (const f of fk === "@events" ? eventFiles() : [fk]) for (const o of list(f)) for (const p of paths)
      walkPath(o, p.split("/"), (v) => {
        if (!tagSet.has(v) && !v.startsWith("*")) add(`${o.id}`, `нет боевого тега «${v}» (${p.replace(/\[\]/g, "")})`, { tag: v }, !strict(fk, p));
      });
  }
  for (const [fk, paths] of Object.entries(CTX_TAG_PATHS)) {
    for (const f of fk === "@events" ? eventFiles() : [fk]) for (const o of list(f)) for (const p of paths)
      walkPath(o, p.split("/"), (v) => { if (!ctxSet.has(v)) add(`${o.id}`, `нет тега проверки «${v}»`, null, !(fk === "@events" && (p === "tags[]" || p === "options[]/tags[]"))); });
  }
  // события
  const checkEffects = (where, effs) => {
    for (const e of effs || []) {
      if (!EFFECTS[e.cmd]) { add(where, `неизвестная команда «${e.cmd}»`); continue; }
      if (e.card && !cards.has(e.card)) add(where, `${e.cmd}: нет карты ${e.card}`);
      if (e.ability && !byId(F.abilities, e.ability)) add(where, `нет способности ${e.ability}`);
      if (e.trauma && !byId(F.traumas, e.trauma)) add(where, `нет травмы ${e.trauma}`);
      if (e.stat && !STATS.includes(e.stat)) add(where, `неизвестная характеристика ${e.stat}`);
      if (["reveal", "spawn_event", "combat_mod"].includes(e.cmd) && e.event && !events[e.event]) add(where, `${e.cmd}: нет события ${e.event}`);
      if (e.cmd === "start_chapter" && !byId(F.chapters, e.chapter)) add(where, `нет главы ${e.chapter}`);
    }
  };
  for (const [eid, ev] of Object.entries(events)) {
    const nav = { event: eid };
    if (!EVENT_TYPES[ev.type]) add(eid, `неизвестный тип «${ev.type}»`, nav);
    if (!ev.title) add(eid, "нет заголовка", nav);
    if (ev.next && !events[ev.next]) add(eid, `next → несуществующее ${ev.next}`, nav);
    const opts = ev.options || [];
    if (opts.length !== 3) add(eid, `вариантов ${opts.length}, нужно ровно 3`, nav);
    let story = 0;
    const ids = new Set();
    for (const o of opts) {
      const ow = `${eid} / ${o.id}`;
      if (!o.id || ids.has(o.id)) add(ow, "пустой или повторный id варианта", nav);
      ids.add(o.id);
      if (!o.label) add(ow, "нет названия", nav);
      const check = o.check || "stat";
      const sum = Object.values(o.req || {}).reduce((a, b) => a + Number(b), 0);
      if ((check === "stat" || check === "gate_stat") && sum <= 0) add(ow, "проверка без требований — нужен check: auto", nav);
      if (check === "combat") {
        const en = (o.combat || {}).enemies || [];
        if (!en.length) add(ow, "бой без противников", nav);
        for (const m of en) if (!byId(F.enemies, m)) add(ow, `нет противника ${m}`, nav);
      }
      if (o.story) story++;
      checkEffects(ow, o.on_success);
      checkEffects(ow, o.on_failure);
    }
    if (ev.type === "story" && story !== 1) add(eid, `сюжетных вариантов ${story}, нужен ровно 1`, nav);
    if (ev.type !== "story" && story > 0) add(eid, "сюжетный вариант у несюжетного события", nav);
    if (ev.type === "reward" && opts.some((o) => (o.check || "stat") !== "auto")) add(eid, "у наградного события все варианты должны быть auto", nav);
    checkEffects(eid, ev.on_appear);
    checkEffects(eid, ev.on_success_common);
  }
  for (const i of list(F.initiators)) if (!events[i.event]) add(i.id, `инициатор ведёт в несуществующее событие ${i.event}`);
  for (const r of list(F.regions)) for (const e of r.random_pool || []) if (!events[e]) add(r.id, `в пуле региона нет события ${e}`);
  for (const ch of list(F.chapters)) {
    for (const a of [...(ch.anchors || []), ...(ch.threads || [])]) {
      if (!events[a.event]) add(ch.id, `нет события ${a.event}`);
      for (const d of a.after || []) if (!events[d]) add(ch.id, `условие ссылается на несуществующее ${d}`);
    }
    if (ch.final && !events[ch.final]) add(ch.id, `нет финального события ${ch.final}`);
  }
  // сюжетная цепочка от E01
  const seen = new Set();
  let cur = "E01";
  while (cur) {
    if (seen.has(cur)) { add("Сюжет", `цепочка зациклена на ${cur}`); break; }
    seen.add(cur);
    if (!events[cur]) { add("Сюжет", `цепочка ведёт в несуществующее ${cur}`); break; }
    cur = events[cur].next || "";
  }
  return errs;
}

// Все ссылки на карту/событие по id (для удаления и переименования).
function idRefs(id) {
  const out = [];
  const scan = (file, root, node, path) => {
    if (Array.isArray(node)) node.forEach((v, i) => scan(file, root, v, path));
    else if (node && typeof node === "object") {
      for (const [k, v] of Object.entries(node)) {
        if (k === "id" && node === root) continue;
        if (typeof v === "string" && v === id) out.push({ file, obj: root, path: path + k });
        else if (Array.isArray(v) && v.includes(id)) out.push({ file, obj: root, path: path + k });
        else scan(file, root, v, path + k + "/");
      }
    }
  };
  for (const [rel, arr] of Object.entries(DB.files)) {
    if (rel === F.lore || !Array.isArray(arr)) continue;
    for (const o of arr) scan(rel, o, o, "");
  }
  return out;
}
