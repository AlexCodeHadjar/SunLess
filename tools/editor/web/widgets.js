// Общие элементы интерфейса: чипы тегов с добавлением/удалением, выбор тега, поля ввода.
"use strict";

// Строка тегов. arr — массив, который правим на месте; onChange вызывается после любой правки.
// context=true — теги проверок (data/tags.json), иначе боевые теги (data/combat/tags.json).
function tagRow(arr, onChange, { context = false, small = false } = {}) {
  const row = h("div", { class: "chips" + (small ? " small" : "") });
  const render = () => {
    row.innerHTML = "";
    arr.forEach((name, i) => {
      row.append(tagChip(name, { context, onRemove: () => { arr.splice(i, 1); render(); onChange(); } }));
    });
    const add = h("button", { class: "chip-add", title: "Добавить тег" }, "+");
    add.onclick = async (e) => {
      e.stopPropagation();
      const picked = await tagPicker(add, { context, exclude: arr });
      if (picked && !arr.includes(picked)) { arr.push(picked); render(); onChange(); }
    };
    row.append(add);
  };
  render();
  return row;
}

function tagChip(name, { context = false, onRemove = null, onClick = null } = {}) {
  let chip;
  if (context) {
    const t = ctxTag(name);
    chip = h("span", { class: "chip ctx" + (t ? "" : " missing"), title: t ? `${t.name} (${t.id})` : "Нет такого тега" },
      h("span", { class: "chip-name" }, t ? t.name : name));
  } else {
    const t = combatTag(name);
    const cat = t ? t.category : null;
    chip = h("span", {
      class: "chip" + (t ? "" : " missing"),
      style: { "--c": t ? CATEGORIES[cat]?.[1] || "#8A8D96" : "#B0303C" },
      title: t ? `${CATEGORIES[cat]?.[0] || cat}${t.value ? " · сила " + Math.round(t.value * 100) + "%" : ""}\n${t.text || ""}` : "Нет такого тега в data/combat/tags.json",
    }, h("img", { class: "chip-icon", src: tagIcon(cat), alt: "" }), h("span", { class: "chip-name" }, name));
  }
  if (onClick) { chip.classList.add("link"); chip.onclick = onClick; }
  else chip.ondblclick = () => App.go("tags", { tag: name, context });
  if (onRemove) {
    chip.append(h("button", { class: "chip-x", title: "Убрать тег", onclick: (e) => { e.stopPropagation(); onRemove(); } }, "×"));
  }
  return chip;
}

// Всплывающий выбор тега с поиском и созданием нового. Возвращает имя/id или null.
function tagPicker(anchor, { context = false, exclude = [] } = {}) {
  return new Promise((resolve) => {
    document.querySelectorAll(".picker").forEach((p) => p.remove());
    const pop = h("div", { class: "picker" });
    const input = h("input", { type: "search", placeholder: context ? "Тег проверки…" : "Найти или создать тег…" });
    const listEl = h("div", { class: "picker-list" });
    pop.append(input, listEl);
    document.body.append(pop);
    const r = anchor.getBoundingClientRect();
    pop.style.left = Math.min(r.left, window.innerWidth - 340) + "px";
    const below = r.bottom + 6;
    if (below + 360 > window.innerHeight) pop.style.bottom = window.innerHeight - r.top + 6 + "px";
    else pop.style.top = below + "px";

    let done = false;
    const finish = (v) => {
      if (done) return;
      done = true;
      pop.remove();
      document.removeEventListener("mousedown", outside, true);
      resolve(v);
    };
    const outside = (e) => { if (!pop.contains(e.target)) finish(null); };
    setTimeout(() => document.addEventListener("mousedown", outside, true), 0);

    let first = null;
    const render = () => {
      const q = input.value.trim().toLowerCase();
      listEl.innerHTML = "";
      first = null;
      if (context) {
        const items = list(F.ctxTags).filter((t) => !exclude.includes(t.id) && (!q || t.name.toLowerCase().includes(q) || t.id.includes(q)));
        for (const t of items) {
          first = first || t.id;
          listEl.append(h("button", { class: "pick", onclick: () => finish(t.id) }, h("b", null, t.name), h("small", null, t.id)));
        }
      } else {
        const groups = {};
        for (const t of list(F.tags)) {
          if (exclude.includes(t.id)) continue;
          if (q && !t.id.toLowerCase().includes(q)) continue;
          (groups[t.category] = groups[t.category] || []).push(t);
        }
        for (const cat of Object.keys(CATEGORIES)) {
          const items = groups[cat];
          if (!items) continue;
          items.sort((a, b) => a.id.localeCompare(b.id, "ru"));
          listEl.append(h("div", { class: "pick-group", style: { color: CATEGORIES[cat][1] } },
            h("img", { src: tagIcon(cat), alt: "" }), CATEGORIES[cat][0]));
          for (const t of items.slice(0, q ? 50 : 400)) {
            first = first || t.id;
            listEl.append(h("button", { class: "pick", title: t.text || "", onclick: () => finish(t.id) },
              h("span", { class: "dot", style: { background: CATEGORIES[cat][1] } }), t.id));
          }
        }
        const exact = list(F.tags).some((t) => t.id.toLowerCase() === q);
        if (q && !exact) {
          listEl.prepend(h("button", { class: "pick create", onclick: async () => {
            const name = input.value.trim();
            document.removeEventListener("mousedown", outside, true);
            pop.remove();
            finish(await createTagDialog(name));
          } }, "+ Создать тег «", input.value.trim(), "»"));
        }
      }
      if (!listEl.children.length) listEl.append(h("div", { class: "muted pad" }, "Ничего не найдено"));
    };
    input.oninput = render;
    input.onkeydown = (e) => {
      if (e.key === "Escape") finish(null);
      if (e.key === "Enter") { e.preventDefault(); const c = listEl.querySelector(".pick"); if (c) c.click(); }
    };
    render();
    setTimeout(() => input.focus(), 0);
  });
}

// Диалог создания боевого тега. Возвращает имя или null.
async function createTagDialog(name = "", category = "state") {
  const res = await ask("Новый боевой тег", [
    { key: "name", label: "Название", value: name },
    { key: "category", label: "Категория", type: "select", value: category, options: Object.fromEntries(Object.entries(CATEGORIES).map(([k, v]) => [k, v[0]])) },
    { key: "value", label: "Сила тега (доля, 0.05–0.2)", type: "number", value: 0.1 },
    { key: "text", label: "Описание", type: "textarea", value: "" },
  ]);
  if (!res || !res.name) return null;
  if (combatTag(res.name)) { toast(`Тег «${res.name}» уже есть`, "warn"); return res.name; }
  list(F.tags).push({ id: res.name, name: res.name, category: res.category, text: res.text, value: Number(res.value) || 0 });
  touch(F.tags);
  toast(`Создан тег «${res.name}»`, "ok");
  return res.name;
}

// --- поля ввода, привязанные к объекту ------------------------------------------------------

// obj[key] ← значение поля; onChange вызывается после правки.
function bindInput(obj, key, onChange, { type = "text", placeholder = "", rows = 3, keepEmpty = false, cls = "" } = {}) {
  let el;
  const val = obj[key];
  if (type === "textarea") {
    el = h("textarea", { rows, placeholder, class: cls }, val ?? "");
  } else if (type === "checkbox") {
    el = h("input", { type: "checkbox", checked: !!val, class: cls });
  } else {
    el = h("input", { type, value: val ?? "", placeholder, class: cls });
  }
  const apply = () => {
    let v;
    if (type === "checkbox") v = el.checked;
    else if (type === "number") v = el.value === "" ? undefined : Number(el.value);
    else v = el.value;
    if ((v === undefined || v === "") && !keepEmpty) delete obj[key];
    else obj[key] = v;
    onChange();
  };
  el.addEventListener(type === "checkbox" ? "change" : "input", apply);
  return el;
}

function bindSelect(obj, key, options, onChange, { allowEmpty = false, emptyLabel = "—" } = {}) {
  const opts = Array.isArray(options) ? Object.fromEntries(options.map((o) => [o, o])) : options;
  const cur = obj[key] ?? "";
  const sel = h("select", null,
    allowEmpty ? h("option", { value: "" }, emptyLabel) : null,
    Object.entries(opts).map(([v, l]) => h("option", { value: v, selected: String(cur) === v }, l)));
  if (cur !== "" && !(cur in opts)) sel.append(h("option", { value: cur, selected: true }, cur + " (?)"));
  sel.onchange = () => {
    if (sel.value === "" && allowEmpty) delete obj[key]; else obj[key] = sel.value;
    onChange();
  };
  return sel;
}

function field(label, input, hint) {
  return h("label", { class: "field" }, h("span", null, label), input, hint ? h("small", null, hint) : null);
}

function statIcon(stat) {
  return h("img", { class: "stat-icon", src: projectUrl(STAT_ICONS[stat]), alt: STAT_NAMES[stat], title: STAT_NAMES[stat] });
}

// Три характеристики (Сила/Воля/Хитрость) с иконками. allowEmpty — пустое поле убирает ключ.
function statsEditor(stats, onChange, { signed = false } = {}) {
  return h("div", { class: "stats" }, STATS.map((s) => h("label", { class: "stat" + (signed ? " signed" : "") },
    statIcon(s), h("span", null, STAT_NAMES[s]), bindInput(stats, s, onChange, { type: "number" }))));
}

// Выбор карты/события из списка по id.
function idSelect(obj, key, kinds, onChange, { allowEmpty = true } = {}) {
  const opts = {};
  for (const c of allCards()) if (kinds.includes(c.kind)) opts[c.id] = `${c.id} — ${c.obj.name || c.obj.title || ""}`;
  return bindSelect(obj, key, opts, onChange, { allowEmpty });
}

// Список строк через запятую ↔ массив.
function listInput(obj, key, onChange, placeholder = "через запятую") {
  const el = h("input", { type: "text", value: (obj[key] || []).join(", "), placeholder });
  el.oninput = () => {
    const arr = el.value.split(",").map((s) => s.trim()).filter(Boolean);
    if (arr.length) obj[key] = arr; else delete obj[key];
    onChange();
  };
  return el;
}

// Редактор JSON объекта целиком (для редких полей). apply(newObj) — заменить.
function jsonEditor(obj, apply) {
  const ta = h("textarea", { class: "json", rows: 24, spellcheck: "false" }, JSON.stringify(obj, null, 2));
  const msg = h("span", { class: "muted" });
  const btn = h("button", { class: "btn", onclick: () => {
    try {
      const v = JSON.parse(ta.value);
      if (typeof v !== "object" || Array.isArray(v) || v === null) throw new Error("нужен объект { … }");
      apply(v);
      msg.textContent = "Применено";
      msg.className = "ok";
    } catch (e) { msg.textContent = "Ошибка: " + e.message; msg.className = "err"; }
  } }, "Применить JSON");
  return h("div", { class: "json-wrap" }, ta, h("div", { class: "row" }, btn, msg));
}

// Выбор картинки: читает файл, кладёт в очередь загрузки до сохранения.
function pickImage(card, onDone) {
  const inp = h("input", { type: "file", accept: ".png,.webp,.jpg,.jpeg,image/png,image/webp,image/jpeg" });
  inp.onchange = () => {
    const file = inp.files[0];
    if (file) setImage(card, file, onDone);
  };
  inp.click();
}

function setImage(card, file, onDone) {
  const ext = (file.name.split(".").pop() || "png").toLowerCase().replace("jpeg", "jpg");
  if (!["png", "webp", "jpg"].includes(ext)) { toast("Нужна картинка png, webp или jpg", "err"); return; }
  const reader = new FileReader();
  reader.onload = () => {
    const url = reader.result;
    const name = `${card.id}.${ext}`;
    const remove = [...DB.art].filter((p) => p !== "art/cards/" + name && new RegExp(`^art/cards/${card.id}\\.(png|webp|jpe?g)$`).test(p));
    DB.images.set(card.id, { name, data: url.split(",")[1], url, remove });
    card.obj.art = "res://art/cards/" + name;
    // раньше картинка находилась по id и считалась готовой картой с рамкой — сохраняем это
    if (card.kind !== "event" && card.obj.art_has_frame === undefined) card.obj.art_has_frame = true;
    touch(card.file);
    toast(`Картинка ${name} будет записана при сохранении`, "info");
    onDone && onDone();
  };
  reader.readAsDataURL(file);
}
