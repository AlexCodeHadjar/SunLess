"""Редактор контента SunLess — локальный сервер.

Отдаёт веб-интерфейс (tools/editor/web) и API для чтения/записи data/*.json и картинок карт.
Только стандартная библиотека Python 3.9+. Запуск: python tools/editor/server.py [--port 8765] [--no-browser]

Сохранение бережное: неизменённые объекты в файлах-массивах пишутся теми же байтами,
что и были (однострочные остаются однострочными), изменённые — в стиле файла.
Перед записью старая версия копируется в tools/editor/backups/<время>/.
"""
import argparse
import base64
import datetime
import hashlib
import http.server
import io
import json
import os
import re
import shutil
import socketserver
import subprocess
import sys
import threading
import urllib.parse
import webbrowser

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
WEB = os.path.join(HERE, "web")
BACKUPS = os.path.join(HERE, "backups")
LAYOUT = os.path.join(HERE, "layout.json")
CONFIG = os.path.join(HERE, "config.json")
DATA = os.path.join(ROOT, "data")
ART_CARDS = os.path.join(ROOT, "art", "cards")

# статика проекта, которую можно отдавать в браузер (картинки, иконки, шрифты)
SERVE_DIRS = ("art/", "ui/fonts/")
IMAGE_EXT = (".png", ".webp", ".jpg", ".jpeg")
GODOT_CANDIDATES = [
    r"D:\Godot_v4.7.2-stable_win64_console.exe",
    r"D:\Godot_v4.7.2-stable_win64.exe",
]

_lock = threading.Lock()
_jobs = {}  # имя задачи → {"running": bool, "code": int|None, "log": str}


# --- JSON с сохранением формата ------------------------------------------------

def _split_items(raw):
    """Разбирает текст JSON-массива верхнего уровня на [(объект, исходный текст, пробелы перед ним)]."""
    dec = json.JSONDecoder()
    i = raw.index("[") + 1
    items = []
    n = len(raw)
    while i < n:
        ws = ""
        while i < n and raw[i] in " \t\r\n,":
            ws = "" if raw[i] == "," else ws + raw[i]
            i += 1
        if i >= n or raw[i] == "]":
            break
        obj, end = dec.raw_decode(raw, i)
        items.append((obj, raw[i:end], ws))
        i = end
    return items


def _detect_style(raw, items):
    """Стиль файла: отступ перед элементом, отступ внутри, однострочные ли элементы."""
    m = re.match(r"\s*\[\r?\n([ \t]*)\S", raw)
    lead = m.group(1) if m else " "
    multi = [t for _, t, _ws in items if "\n" in t]
    single = [t for _, t, _ws in items if "\n" not in t]
    one_line = len(single) > len(multi)
    inner = len(lead) or 1
    if multi:
        mm = re.match(r"\{\r?\n([ \t]*)", multi[0])
        if mm:
            inner = max(1, len(mm.group(1)) - len(lead))
    return {"lead": lead, "inner": inner, "one_line": one_line}


def _key(obj):
    """Ключ сравнения: 0.0 и 0 равны (браузер не различает их в JSON)."""
    def norm(v):
        if isinstance(v, float) and v.is_integer():
            return int(v)
        if isinstance(v, dict):
            return {k: norm(x) for k, x in v.items()}
        if isinstance(v, list):
            return [norm(x) for x in v]
        return v
    return json.dumps(norm(obj), ensure_ascii=False, sort_keys=True)


def _format_item(obj, style):
    if style["one_line"]:
        return json.dumps(obj, ensure_ascii=False)
    s = json.dumps(obj, ensure_ascii=False, indent=style["inner"])
    return s.replace("\n", "\n" + style["lead"])


def dump_preserving(path, new_data):
    """Пишет new_data в path, сохраняя байты неизменённых элементов массива."""
    old_raw = None
    if os.path.exists(path):
        with io.open(path, encoding="utf-8", newline="") as f:
            old_raw = f.read()
    if old_raw is None or not isinstance(new_data, list) or not old_raw.lstrip().startswith("["):
        text = json.dumps(new_data, ensure_ascii=False, indent=1)
        nl = "\r\n" if old_raw and "\r\n" in old_raw else "\n"
        return _write_text(path, text.replace("\n", nl), old_raw)

    crlf = "\r\n" in old_raw
    raw = old_raw.replace("\r\n", "\n")
    items = _split_items(raw)
    style = _detect_style(raw, items)
    old_by_key = {}
    for obj, txt, ws in items:
        key = _key(obj)
        old_by_key.setdefault(key, (txt, ws))
    lead = style["lead"]
    parts = []
    for obj in new_data:
        key = _key(obj)
        txt, ws = old_by_key.get(key) or (_format_item(obj, style), "\n" + lead)
        parts.append(ws + txt)
    close = raw.rindex("]")
    tail = raw[len(raw[:close].rstrip()):close] or "\n"
    text = "[" + ",".join(parts) + tail + "]" if parts else "[]"
    if raw.endswith("\n"):
        text += "\n"
    if crlf:
        text = text.replace("\n", "\r\n")
    return _write_text(path, text, old_raw)


def _write_text(path, text, old_raw):
    if old_raw == text:
        return False
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with io.open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)
    return True


# --- данные ----------------------------------------------------------------------

def data_files():
    out = []
    for base, _dirs, files in os.walk(DATA):
        for fn in files:
            if fn.endswith(".json"):
                full = os.path.join(base, fn)
                out.append(os.path.relpath(full, ROOT).replace("\\", "/"))
    return sorted(out)


def safe_path(rel):
    """Путь внутри проекта; запрещает выход наружу."""
    rel = rel.replace("\\", "/").lstrip("/")
    full = os.path.normpath(os.path.join(ROOT, rel))
    if not full.startswith(os.path.normpath(ROOT) + os.sep):
        raise ValueError("путь вне проекта: " + rel)
    return full, rel


def versions():
    """Отпечаток каждого файла данных (время изменения + размер) — чтобы замечать правки извне."""
    out = {}
    for rel in data_files():
        st = os.stat(os.path.join(ROOT, rel))
        out[rel] = "%d-%d" % (st.st_mtime_ns, st.st_size)
    return out


def signature():
    """Общий отпечаток данных и картинок: меняется, если что-то добавили, удалили или изменили."""
    parts = sorted(versions().items())
    art_dir = os.path.join(ROOT, "art")
    for base, _dirs, fs in os.walk(art_dir):
        for fn in fs:
            if fn.lower().endswith(IMAGE_EXT):
                st = os.stat(os.path.join(base, fn))
                parts.append((os.path.relpath(os.path.join(base, fn), ROOT), "%d" % st.st_mtime_ns))
    return hashlib.md5(repr(parts).encode("utf-8")).hexdigest()


# --- определения из кода игры: редактор подхватывает новое сам -------------------------

def _read_code(rel):
    full = os.path.join(ROOT, rel)
    if not os.path.exists(full):
        return ""
    with io.open(full, encoding="utf-8") as f:
        return f.read()


def _const_list(code, name):
    m = re.search(r"const " + name + r"\s*:?=\s*\[(.*?)\]", code, re.S)
    return re.findall(r'"([^"]+)"', m.group(1)) if m else []


def _const_dict(code, name):
    m = re.search(r"const " + name + r"\s*:?=\s*\{(.*?)\}", code, re.S)
    return dict(re.findall(r'"([^"]+)"\s*:\s*"([^"]*)"', m.group(1))) if m else {}


def _match_keys(code, var):
    """Для каждой ветки match "имя": — какие ключи читаются из словаря var (e["x"], e.get("x"), e.has("x"))."""
    out = {}
    cur = None
    tab = chr(9)
    for line in code.splitlines():
        m = re.match(tab * 2 + r'"(\w+)":\s*$', line)
        if m:
            cur = m.group(1)
            out.setdefault(cur, [])
            continue
        if line.strip() and not line.startswith(tab * 3):
            cur = None  # вышли из ветки match
        if cur:
            for k in re.findall(var + r'(?:\[|\.get\(|\.has\()"(\w+)"', line):
                if k not in out[cur]:
                    out[cur].append(k)
    return out


def game_defs():
    validator = _read_code("core/content/content_validator.gd")
    content = _read_code("core/content/content.gd")
    tag_text = _read_code("scenes/combat/tag_text.gd")
    kinds = re.findall(r'if (\w+)\.has\(card_id\):\s*return "(\w+)"', content)
    files = dict(re.findall(r'c\.(\w+) = c\._load_map\(dir \+ "/([^"]+)"\)', content))
    return {
        "commands": _const_list(validator, "KNOWN_CMDS"),
        "conditions": _const_list(validator, "KNOWN_CONDITIONS"),
        "checks": _const_list(validator, "CHECKS"),
        "pools": _const_list(validator, "POOLS"),
        "event_types": _const_list(validator, "EVENT_TYPES"),
        "stats": _const_list(validator, "STATS"),
        "command_keys": _match_keys(_read_code("core/rules/effect_applier.gd"), "e"),
        "condition_keys": _match_keys(_read_code("core/rules/condition_checker.gd"), "c"),
        "card_kinds": [{"var": v, "kind": k, "file": "data/" + files[v]} for v, k in kinds if v in files],
        "category_names": _const_dict(tag_text, "CATEGORY_NAMES"),
        "category_colors": _const_dict(tag_text, "CATEGORY_COLORS"),
    }


def load_all():
    files = {}
    for rel in data_files():
        with io.open(os.path.join(ROOT, rel), encoding="utf-8") as f:
            files[rel] = json.load(f)
    arts = []
    for base, _dirs, fs in os.walk(os.path.join(ROOT, "art")):
        for fn in fs:
            if fn.lower().endswith(IMAGE_EXT):
                arts.append(os.path.relpath(os.path.join(base, fn), ROOT).replace("\\", "/"))
    layout = {}
    if os.path.exists(LAYOUT):
        with io.open(LAYOUT, encoding="utf-8") as f:
            layout = json.load(f)
    return {"files": files, "art": sorted(arts), "layout": layout, "godot": bool(find_godot()),
            "versions": versions(), "signature": signature(), "game": game_defs()}


def backup(rels, stamp):
    dst_root = os.path.join(BACKUPS, stamp)
    for rel in rels:
        src = os.path.join(ROOT, rel)
        if os.path.exists(src):
            dst = os.path.join(dst_root, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
    # храним последние 30 копий
    if os.path.isdir(BACKUPS):
        stamps = sorted(os.listdir(BACKUPS))
        for old in stamps[:-30]:
            shutil.rmtree(os.path.join(BACKUPS, old), ignore_errors=True)


def save(payload):
    files = payload.get("files", {})
    images = payload.get("images", [])
    layout = payload.get("layout")
    base = payload.get("base") or {}
    force = bool(payload.get("force"))
    stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    written, image_paths, removed = [], [], []
    with _lock:
        targets = []
        for rel in files:
            full, rel2 = safe_path(rel)
            if not rel2.startswith("data/") or not rel2.endswith(".json"):
                raise ValueError("писать можно только data/*.json: " + rel)
            targets.append((full, rel2, files[rel]))
        # файл изменили вне редактора после загрузки — не затираем чужие правки
        now = versions()
        conflicts = [rel for _full, rel, _d in targets if rel in base and now.get(rel) and now[rel] != base[rel]]
        if conflicts and not force:
            return {"ok": False, "conflict": conflicts}
        img_targets = []
        for im in images:
            name = os.path.basename(im["name"])
            if not name.lower().endswith(IMAGE_EXT):
                raise ValueError("картинка должна быть png/webp/jpg: " + name)
            full, rel2 = safe_path("art/cards/" + name)
            img_targets.append((full, rel2, base64.b64decode(im["data"])))
            # старые картинки той же карты (другое расширение) уходят в резервную копию
            for old in im.get("remove") or []:
                ofull, orel = safe_path(old)
                if orel.startswith("art/cards/") and orel != rel2 and os.path.exists(ofull):
                    removed.append((ofull, orel))
        backup([t[1] for t in targets] + [t[1] for t in img_targets] + [r[1] for r in removed], stamp)
        for ofull, orel in removed:
            os.remove(ofull)
            if os.path.exists(ofull + ".import"):
                os.remove(ofull + ".import")
        for full, rel2, data in targets:
            if dump_preserving(full, data):
                written.append(rel2)
        for full, rel2, blob in img_targets:
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "wb") as f:
                f.write(blob)
            image_paths.append(rel2)
        if layout is not None:
            with io.open(LAYOUT, "w", encoding="utf-8") as f:
                json.dump(layout, f, ensure_ascii=False, indent=1)
    return {"ok": True, "written": written, "images": image_paths,
            "removed": [r[1] for r in removed], "backup": stamp,
            "versions": versions(), "signature": signature()}


# --- Godot -----------------------------------------------------------------------

def find_godot():
    cfg = {}
    if os.path.exists(CONFIG):
        with io.open(CONFIG, encoding="utf-8") as f:
            cfg = json.load(f)
    for p in [cfg.get("godot", ""), os.environ.get("GODOT", "")] + GODOT_CANDIDATES:
        if p and os.path.exists(p):
            return p
    return shutil.which("godot") or ""


def run_job(name, args, timeout):
    godot = find_godot()
    if not godot:
        return {"ok": False, "error": "Godot не найден: укажите путь в tools/editor/config.json {\"godot\": \"...\"}"}
    job = _jobs.get(name)
    if job and job["running"]:
        return {"ok": True, "started": False}
    job = {"running": True, "code": None, "log": ""}
    _jobs[name] = job

    def work():
        try:
            p = subprocess.run([godot] + args, cwd=ROOT, capture_output=True, timeout=timeout)
            out = (p.stdout or b"").decode("utf-8", "replace") + (p.stderr or b"").decode("utf-8", "replace")
            job["code"] = p.returncode
            job["log"] = re.sub(chr(27) + r"\[[0-9;]*m", "", out)[-20000:]  # без цветовых кодов консоли
        except subprocess.TimeoutExpired:
            job["code"] = -1
            job["log"] = "Превышено время ожидания (%d с)" % timeout
        except OSError as e:
            job["code"] = -1
            job["log"] = str(e)
        job["running"] = False

    threading.Thread(target=work, daemon=True).start()
    return {"ok": True, "started": True}


# --- HTTP ------------------------------------------------------------------------

MIME = {
    ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8", ".json": "application/json; charset=utf-8",
    ".png": "image/png", ".webp": "image/webp", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
    ".svg": "image/svg+xml", ".ttf": "font/ttf",
}


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def _send(self, code, body, ctype="application/json; charset=utf-8", cache=False):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode("utf-8")
        elif isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "max-age=3600" if cache else "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _file(self, full, cache=False):
        if not os.path.isfile(full):
            return self._send(404, {"error": "нет файла"})
        ext = os.path.splitext(full)[1].lower()
        with open(full, "rb") as f:
            self._send(200, f.read(), MIME.get(ext, "application/octet-stream"), cache)

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        path = urllib.parse.unquote(url.path)
        try:
            if path == "/api/data":
                return self._send(200, load_all())
            if path == "/api/version":
                return self._send(200, {"signature": signature()})
            if path == "/api/job":
                name = urllib.parse.parse_qs(url.query).get("name", [""])[0]
                return self._send(200, _jobs.get(name, {"running": False, "code": None, "log": ""}))
            if path.startswith("/project/"):
                full, rel = safe_path(path[len("/project/"):])
                if not rel.startswith(SERVE_DIRS):
                    return self._send(403, {"error": "нельзя"})
                return self._file(full, cache=False)
            rel = path.lstrip("/") or "index.html"
            full = os.path.normpath(os.path.join(WEB, rel))
            if not full.startswith(os.path.normpath(WEB)):
                return self._send(403, {"error": "нельзя"})
            return self._file(full)
        except Exception as e:  # noqa: BLE001 — показываем ошибку в интерфейсе
            return self._send(500, {"error": str(e)})

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
        length = int(self.headers.get("Content-Length", "0"))
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8") or "{}")
            if path == "/api/save":
                return self._send(200, save(payload))
            if path == "/api/godot/import":
                return self._send(200, run_job("import", ["--headless", "--path", ".", "--import"], 600))
            if path == "/api/godot/test":
                return self._send(200, run_job("test", ["--headless", "--path", ".", "-s", "res://tests/run_tests.gd"], 900))
            return self._send(404, {"error": "нет такого метода"})
        except Exception as e:  # noqa: BLE001
            return self._send(500, {"ok": False, "error": str(e)})


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main():
    ap = argparse.ArgumentParser(description="Редактор контента SunLess")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--no-browser", action="store_true")
    a = ap.parse_args()
    try:
        srv = Server(("127.0.0.1", a.port), Handler)
    except OSError:
        url = "http://127.0.0.1:%d/" % a.port
        print("Порт %d занят — похоже, редактор уже запущен: %s" % (a.port, url))
        if not a.no_browser:
            webbrowser.open(url)
        return
    url = "http://127.0.0.1:%d/" % a.port
    print("Редактор SunLess: %s  (Ctrl+C — остановить)" % url)
    print("Проект:", ROOT)
    if not a.no_browser:
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    main()
