// Оболочка: вкладки, статус изменений, сохранение, проверка, задачи Godot.
"use strict";

const Views = { cards: CardsView, tags: TagsView, events: EventsView };

const App = {
  view: null,
  params: {},

  go(name, params = {}) {
    this.view = name;
    this.params = params;
    document.querySelectorAll("#tabs button").forEach((b) => b.classList.toggle("on", b.dataset.view === name));
    const root = document.getElementById("view");
    root.innerHTML = "";
    root.className = "view-" + name;
    Views[name].render(root, params);
    try { localStorage.setItem("sunless-editor-view", JSON.stringify({ name, params })); } catch (_) { /* нет хранилища */ }
  },

  refresh() { this.go(this.view, this.params); },

  refreshStatus() {
    const n = DB.dirty.size + DB.images.size + (DB.layoutDirty ? 1 : 0);
    const el = document.getElementById("dirty");
    el.textContent = n ? `Несохранённых изменений: ${n}` : "Все изменения сохранены";
    el.classList.toggle("on", n > 0);
    document.getElementById("btn-save").disabled = n === 0;
  },

  async save() {
    const errs = validate().filter((e) => !e.warn);
    if (errs.length) {
      const ok = await modal(`Найдено ошибок: ${errs.length}`, h("div", null,
        h("p", null, "Игра при запуске покажет эти ошибки вместо меню. Всё равно сохранить?"),
        issuesList(errs, 30)),
        [{ label: "Отмена", value: false }, { label: "Сохранить всё равно", danger: true, value: true }], { wide: true });
      if (!ok) return;
    }
    const btn = document.getElementById("btn-save");
    btn.disabled = true;
    btn.textContent = "Сохраняю…";
    try {
      const res = await saveAll();
      const parts = [];
      if (res.written.length) parts.push("файлов: " + res.written.length);
      if (res.images.length) parts.push("картинок: " + res.images.length);
      toast("Сохранено в проект — " + (parts.join(", ") || "без изменений") + ". Резервная копия: " + res.backup, "ok", 5000);
      if (res.hadImages && DB.godot) {
        toast("Импортирую новые картинки в Godot…", "info");
        runJob("import", true);
      }
    } catch (e) {
      toast("Не удалось сохранить: " + e.message, "err", 8000);
    }
    btn.textContent = "Сохранить";
    this.refreshStatus();
  },

  async check() {
    const all = validate();
    if (!all.length) { toast("Проверка пройдена: ошибок нет", "ok"); return; }
    const errs = all.filter((e) => !e.warn), warns = all.filter((e) => e.warn);
    modal(`Ошибок: ${errs.length} · предупреждений: ${warns.length}`, h("div", null,
      errs.length ? h("div", null, h("h4", { class: "err" }, "Ошибки — игра их не пропустит"), issuesList(errs, 200)) : h("p", { class: "ok" }, "Ошибок нет — игра запустится."),
      warns.length ? h("div", { style: { marginTop: "14px" } }, h("h4", { style: { color: "var(--warn)" } }, "Предупреждения — игра их не проверяет, но стоит взглянуть"), issuesList(warns, 200)) : null),
      undefined, { wide: true });
  },
};

function issuesList(errs, max) {
  return h("ul", { class: "issues" }, errs.slice(0, max).map((e) => h("li", null,
    h("b", null, e.where), " — ", e.text,
    e.nav ? h("button", { class: "link", onclick: () => {
      document.getElementById("overlay").hidden = true;
      if (e.nav.event) App.go("events", { select: e.nav.event });
      if (e.nav.tag) App.go("tags", { tag: e.nav.tag });
    } }, "открыть") : null)),
  errs.length > max ? h("li", { class: "muted" }, `…и ещё ${errs.length - max}`) : null);
}

async function runJob(name, quiet = false) {
  if (!DB.godot) { toast("Godot не найден. Укажите путь в tools/editor/config.json: {\"godot\": \"D:\\\\...exe\"}", "err", 8000); return; }
  const titles = { import: "Импорт картинок в Godot", test: "Тесты Godot" };
  const r = await (await fetch("/api/godot/" + name, { method: "POST", body: "{}" })).json();
  if (!r.ok) { toast(r.error, "err", 8000); return; }
  if (!quiet) toast(titles[name] + ": запущено…", "info");
  const poll = async () => {
    const j = await (await fetch("/api/job?name=" + name)).json();
    if (j.running) { setTimeout(poll, 1500); return; }
    const ok = j.code === 0;
    if (quiet && ok) { toast(titles[name] + ": готово", "ok"); return; }
    modal(titles[name] + (ok ? " — успешно" : " — ошибка (код " + j.code + ")"),
      h("pre", { class: "log" }, j.log.trim().split("\n").slice(-200).join("\n") || "(пусто)"), undefined, { wide: true });
  };
  setTimeout(poll, 1500);
}

async function boot() {
  document.querySelectorAll("#tabs button").forEach((b) => (b.onclick = () => App.go(b.dataset.view)));
  document.getElementById("btn-save").onclick = () => App.save();
  document.getElementById("btn-check").onclick = () => App.check();
  const menu = document.getElementById("godot-menu");
  document.getElementById("btn-godot").onclick = (e) => { e.stopPropagation(); menu.classList.toggle("open"); };
  document.addEventListener("click", () => menu.classList.remove("open"));
  menu.querySelectorAll("button").forEach((b) => (b.onclick = () => runJob(b.dataset.job)));
  document.addEventListener("keydown", (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "s") { e.preventDefault(); if (!document.getElementById("btn-save").disabled) App.save(); }
  });
  window.addEventListener("beforeunload", (e) => {
    if (DB.dirty.size || DB.images.size || DB.layoutDirty) { e.preventDefault(); e.returnValue = ""; }
  });
  try {
    await loadData();
  } catch (e) {
    document.getElementById("view").append(h("div", { class: "fatal" }, "Не удалось загрузить данные: " + e.message));
    return;
  }
  App.refreshStatus();
  let start = { name: "cards", params: {} };
  try { start = JSON.parse(localStorage.getItem("sunless-editor-view")) || start; } catch (_) { /* нет хранилища */ }
  App.go(Views[start.name] ? start.name : "cards", start.params || {});
}

boot();
