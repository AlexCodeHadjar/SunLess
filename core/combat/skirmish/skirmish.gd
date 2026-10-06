class_name Skirmish
extends RefCounted
## Пошаговый бой «Схватка» по образцу Darkest Dungeon (docs/24). До четырёх героев слева, до четырёх врагов справа;
## раунд — очередь по скорости + бросок 1–8; в ход бойца — навык и цель, шаг или пропуск; герои — игроком,
## враги — ИИ (SkAI). Здоровье 0 у героя — грань смерти (EdgeRules), удар по герою на грани — бросок смерти;
## психика героев — стресс (PsycheRules). Убитый враг оставляет труп, который держит место в строю.
## Работает на копии состояния прохождения; finish() пишет здоровье героев и снимает кризисы боя.
##
## Использование: create(...) → цикл { f := turn(); если f — герой: options(f) → act(f, навык, цель) или retreat(f);
## иначе ai_act(f) } пока outcome == "" → finish(). События каждого шага — в log (для экрана, фаза 4).

const ROUND_LIMIT := 30       # бой не тянется бесконечно: потом враги отходят (outcome "retreat")
const CORPSE_SHARE := 0.3     # здоровье трупа — доля здоровья врага
const CORPSE_ROUNDS := 3      # труп истлевает через столько раундов
const PSY_HERO_CRIT := [8, 4]     # крит героя: ему, остальным героям
const PSY_ENEMY_CRIT := [-10, -3] # крит врага: цели, её соседям
const PSY_EDGE := -8          # товарищ упал на грань
const PSY_KILL := 3           # убил врага
const PSY_RETREAT_FAIL := -5
const RETREAT_BASE := 90
const RETREAT_FAST := 10      # за каждого быстрого врага
const RETREAT_MIN := 40
const FAST_TAGS := ["Скорость", "Охота", "Летучий"]

var content: Content
var state: RunState
var rng: RandomNumberGenerator
var fighters: Array = []      # SkFighter
var round_no := 0
var queue: Array = []         # uid бойцов, кто ещё ходит в этом раунде
var light := "bright"         # bright | dim | dusk | dark (docs/24 §4.10)
var field := ""
var ambush := ""              # "" | heroes (героев застигли) | enemies (врагов застигли)
var no_retreat := false
var outcome := ""             # "" | win | loss | retreat
var log: Array = []           # события по порядку: {kind, …}
var squad: Array = []         # id героев отряда (для психики и доверия)
var shielded := {}            # щиты карт грани, сработавшие в этом бою
var result := {"edge": [], "death": {}}
var entries: Array = []       # записи для отчёта (грань, гибель, кризисы)
var first_uid := ""           # кто ходит первым в этом раунде («Первая кровь»)
var bonus_turn := ""          # «Рывок»: этот боец сразу ходит ещё раз
var ward_rounds := 0          # «Высветить»: столько раундов тьма не бьёт по психике
var lost_echoes: Array = []   # карты Эха, рассыпавшиеся в этом бою
var _xn := 0


## spec: {heroes: [id в порядке строя], enemies: [id], field, light, ambush, power, no_retreat}
static func create(p_content: Content, state_in: RunState, spec: Dictionary) -> Skirmish:
	var sk := Skirmish.new()
	sk.content = p_content
	sk.state = state_in.copy()
	sk.rng = RandomNumberGenerator.new()
	sk.rng.seed = sk.state.rng_seed
	sk.rng.state = sk.state.rng_state
	sk.field = str(spec.get("field", ""))
	sk.light = str(spec.get("light", "bright"))
	sk.ambush = str(spec.get("ambush", ""))
	sk.no_retreat = bool(spec.get("no_retreat", false))
	var heroes: Array = []
	for cid: String in spec.get("heroes", []):
		if sk.state.is_alive(cid) and heroes.size() < SkFormation.SIZE:
			var f := SkBuild.hero(p_content, sk.state, cid)
			f.uid = "h%d" % heroes.size()
			heroes.append(f)
			sk.squad.append(cid)
	# Эхо из кармашков героев — в свободные позиции (docs/24 §4.13)
	var used := 0
	for h: SkFighter in heroes:
		used += h.size
	for h2: SkFighter in heroes.duplicate():
		for card: String in MissionFlow.pocket(sk.state, h2.card):
			if p_content.skirmish.get("echoes", {}).has(card) and used < SkFormation.SIZE:
				var ec := SkBuild.echo(p_content, sk.state, card, h2.card)
				ec.uid = sk._next_echo_uid()
				heroes.append(ec)
				used += 1
	if sk.ambush == "heroes":
		heroes.shuffle()    # застигнутый отряд теряет строй
	SkFormation.place(heroes)
	var foes: Array = []
	for eid: String in spec.get("enemies", []):
		if p_content.enemies.has(eid):
			var e := SkBuild.enemy(p_content, eid, float(spec.get("power", 1.0)))
			e.uid = "e%d" % foes.size()
			foes.append(e)
	SkFormation.place(foes)
	# Отражение (испытание души): навыки и оружие героя испытания
	var mirror := str(spec.get("mirror", ""))
	if mirror != "" and sk.state.is_alive(mirror):
		var src := SkBuild.hero(p_content, sk.state, mirror)
		for e2: SkFighter in foes:
			if e2.tags.has("Зеркало"):
				e2.skills = src.skills.filter(func(x: Dictionary) -> bool: return not x.has("card") and str(x.get("kind", "")) != "recall")
				e2.dmg = src.dmg.duplicate()
				e2.pref = src.pref.duplicate()
	sk.fighters = heroes + foes
	sk.fighters = sk.fighters.filter(func(f: SkFighter) -> bool: return not f.removed)
	return sk


func _next_echo_uid() -> String:
	_xn += 1
	return "x%d" % _xn


# --- чтение -----------------------------------------------------------------------------------------------------------

func by_uid(uid: String) -> SkFighter:
	for f: SkFighter in fighters:
		if f.uid == uid:
			return f
	return null


static func other(side: String) -> String:
	return "enemy" if side == "hero" else "hero"


func living(side: String) -> Array:
	return fighters.filter(func(f: SkFighter) -> bool: return f.side == side and f.alive())


func heroes_alive() -> Array:
	return fighters.filter(func(f: SkFighter) -> bool: return f.is_hero() and f.alive())


func light_name() -> String:
	return str(content.skirmish.get("light", {}).get(light, {}).get("name", light))


## Поправка света к параметру бойца: acc, dmg, crit, dodge (docs/24 §4.10).
func light_mod(f: SkFighter, key: String) -> float:
	var L: Dictionary = content.skirmish.get("light", {}).get(light, {})
	if f.side == "hero":
		return float(L.get("hero_" + key, 0))
	return float(L.get("enemy_" + key, 0))


# --- раунды и ходы ----------------------------------------------------------------------------------------------------

## Следующий боец, который ходит сейчас (состояния начала хода уже сработали); null — бой окончен.
func turn() -> SkFighter:
	var guard := 0
	if bonus_turn != "" and outcome == "":
		var fb := by_uid(bonus_turn)
		bonus_turn = ""
		if fb != null and fb.alive():
			log.append({"kind": "turn", "who": fb.uid, "bonus": true})
			return fb
	while outcome == "" and guard < 200:
		guard += 1
		if queue.is_empty():
			if round_no > 0:
				_end_round()
			if outcome != "":
				break
			_begin_round()
			continue
		var f := by_uid(str(queue.pop_front()))
		if f == null or not f.alive():
			continue
		if _start_turn(f):
			return f
	return null


func _begin_round() -> void:
	round_no += 1
	if round_no > ROUND_LIMIT:
		outcome = "retreat"
		log.append({"kind": "end", "outcome": outcome, "why": "stalemate"})
		return
	log.append({"kind": "round", "n": round_no})
	var lp := int(content.skirmish.get("light", {}).get(light, {}).get("psyche", 0))
	if ward_rounds > 0:
		ward_rounds -= 1
	elif lp != 0:
		for h: SkFighter in heroes_alive():
			log.append_array(psyche(h, lp, "тьма давит"))
	var order: Array = []
	for f: SkFighter in fighters:
		if not f.alive():
			continue
		if round_no == 1 and ambush == "enemies" and f.side == "enemy":
			continue
		f.init = f.speed + int(SkStatus.mod(f, "speed")) + rng.randi_range(1, 8)
		if round_no == 1:
			f.init += f.first_strike
			if ambush == "heroes" and f.side == "hero":
				f.init -= 100
		order.append(f)
	order.sort_custom(_before)
	queue = order.map(func(f: SkFighter) -> String: return f.uid)
	first_uid = str(queue[0]) if not queue.is_empty() else ""
	log.append({"kind": "queue", "order": queue.duplicate()})


## Порядок очереди: больше скорость раунда; при равенстве герой раньше врага, ближний к врагу раньше.
static func _before(a: SkFighter, b: SkFighter) -> bool:
	if a.init != b.init:
		return a.init > b.init
	if a.side != b.side:
		return a.side == "hero"
	if a.pos != b.pos:
		return a.pos < b.pos
	return a.uid < b.uid


func _end_round() -> void:
	for f: SkFighter in fighters:
		if f.corpse:
			f.corpse_rounds -= 1
			if f.corpse_rounds <= 0:
				f.corpse = false
				f.removed = true
				log.append({"kind": "corpse_gone", "who": f.uid})
				SkFormation.relayout(fighters, f.side)


## Начало хода: перезарядки, кровотечение и яд, регенерация, оглушение. true — боец ходит.
func _start_turn(f: SkFighter) -> bool:
	log.append({"kind": "turn", "who": f.uid})
	for id: String in f.cooldown.keys():
		f.cooldown[id] = int(f.cooldown[id]) - 1
		if int(f.cooldown[id]) <= 0:
			f.cooldown.erase(id)
	var tk := SkStatus.tick(f)
	if int(tk["dot"]) > 0:
		log.append({"kind": "dot", "who": f.uid, "value": int(tk["dot"])})
		log.append_array(hurt(f, int(tk["dot"]), null, "dot"))
	if not f.alive() or outcome != "":
		_check_end()
		return false
	if int(tk["regen"]) > 0 and f.hp < f.hp_max and not f.edge:
		f.hp = mini(f.hp_max, f.hp + int(tk["regen"]))
		log.append({"kind": "heal", "who": f.uid, "value": int(tk["regen"])})
	if bool(tk["stunned"]):
		log.append({"kind": "stunned", "who": f.uid})
		return false
	if f.has_status("fear") and not f.has_status("steady") and rng.randi_range(1, 100) <= 50:
		if SkFormation.move(fighters, f, 1) != 0:
			log.append({"kind": "fear", "who": f.uid, "pos": f.pos})
	return true


# --- навыки и цели ----------------------------------------------------------------------------------------------------

## Почему навык сейчас нельзя применить ("" — можно).
func usable_why(f: SkFighter, s: Dictionary) -> String:
	var fr: Array = s.get("from", [])
	if not fr.is_empty() and not f.positions().any(func(p: int) -> bool: return fr.has(p)):
		return "не с этой позиции"
	var id := str(s["id"])
	if int(f.cooldown.get(id, 0)) > 0:
		return "перезарядка: %d" % int(f.cooldown[id])
	if bool(s.get("once", false)) and int(f.used.get(id, 0)) > 0:
		return "раз за бой"
	if int(s.get("uses", 0)) > 0 and int(f.used.get(id, 0)) >= int(s["uses"]):
		return "уже применён"
	var need: Dictionary = s.get("need", {})
	if bool(need.get("first", false)) and round_no > 1 and first_uid != f.uid:
		return "только первым ударом"
	if need.has("hp_below") and float(f.hp) >= f.hp_max * float(need["hp_below"]):
		return "только раненым"
	if need.has("light_not") and Array(need["light_not"]).has(light):
		return "не при таком свете"
	for e: Dictionary in s.get("effects", []):
		if str(e["type"]) == "summon":
			var why := _summon_why(f, str(e.get("card", "")))
			if why != "":
				return why
	return ""


func _summon_why(f: SkFighter, card: String) -> String:
	if lost_echoes.has(card):
		return "Эхо рассыпалось"
	if fighters.any(func(x: SkFighter) -> bool: return x.echo and x.card == card and x.alive()):
		return "Эхо уже в бою"
	var used := 0
	for x2: SkFighter in SkFormation.line(fighters, f.side):
		used += x2.size
	if used >= SkFormation.SIZE:
		return "нет места в строю"
	return ""


## Цели навыка: uid бойцов; удар «по всем» — ["all"]; шаг — соседи по строю.
func targets(f: SkFighter, s: Dictionary) -> Array:
	var kind := str(s.get("kind", ""))
	var side := str(s.get("side", "enemy"))
	if kind == "pass":
		return [f.uid]
	if kind == "step":
		var ln := SkFormation.line(fighters, f.side)
		var i := ln.find(f)
		var out: Array = []
		for j in [i - 1, i + 1]:
			if j >= 0 and j < ln.size() and ln[j].alive():
				out.append(ln[j].uid)
		return out
	if side == "self":
		return [f.uid]
	var to: Array = s.get("to", [])
	var pool: Array = []
	if side == "ally":
		pool = living(f.side).filter(func(x: SkFighter) -> bool: return to.is_empty() or x.positions().any(func(p: int) -> bool: return to.has(p)))
		if bool(s.get("not_self", false)):
			pool = pool.filter(func(x: SkFighter) -> bool: return x != f)
		if bool(s.get("adjacent", false)):
			pool = pool.filter(func(x: SkFighter) -> bool: return x.pos + x.size == f.pos or f.pos + f.size == x.pos)
		if bool(s.get("owner", false)):
			pool = pool.filter(func(x: SkFighter) -> bool: return x.card == f.owner)
	else:
		pool = SkFormation.line(fighters, other(f.side)).filter(func(x: SkFighter) -> bool: return x.positions().any(func(p: int) -> bool: return to.has(p)))
		if bool(s.get("need", {}).get("target_rank_above", false)):
			pool = pool.filter(func(x: SkFighter) -> bool: return x.rank > f.rank)
		if not bool(s.get("aoe", false)):
			# скрытного нельзя выбрать целью, пока есть другие цели (кроме ударов «по всем» и сквозь тень)
			if not bool(s.get("pierce_stealth", false)):
				var open := pool.filter(func(x: SkFighter) -> bool: return not x.has_status("stealth"))
				if not open.is_empty():
					pool = open
			# Приманка: если её носитель — среди целей, бить можно только его
			var bait := pool.filter(func(x: SkFighter) -> bool: return x.has_status("taunt") and x.alive())
			if not bait.is_empty():
				pool = bait
	if pool.is_empty():
		return []
	if bool(s.get("aoe", false)):
		return ["all"]
	return pool.map(func(x: SkFighter) -> String: return x.uid)


## Навыки бойца с целями и причинами недоступности: [{skill, targets, why}].
func options(f: SkFighter) -> Array:
	var out: Array = []
	for s: Dictionary in f.skills:
		var why := usable_why(f, s)
		var tg: Array = targets(f, s) if why == "" else []
		if why == "" and tg.is_empty():
			why = "нет целей"
		out.append({"skill": s, "targets": tg, "why": why})
	return out


## Цели удара «по всем» или одиночного.
func _hit_list(f: SkFighter, s: Dictionary, target_uid: String) -> Array:
	if target_uid != "all":
		var t := by_uid(target_uid)
		return [t] if t != null else []
	var to: Array = s.get("to", [])
	var side := f.side if str(s.get("side", "")) == "ally" else other(f.side)
	var src: Array = living(side) if side == f.side else SkFormation.line(fighters, side)
	return src.filter(func(x: SkFighter) -> bool: return to.is_empty() or x.positions().any(func(p: int) -> bool: return to.has(p)))


## Применить навык. Возвращает события этого действия (они же — в log).
func act(f: SkFighter, skill_id: String, target_uid: String) -> Array:
	var ev: Array = []
	var s := f.skill(skill_id)
	if s.is_empty() or outcome != "" or usable_why(f, s) != "" or not targets(f, s).has(target_uid):
		return [{"kind": "error", "who": f.uid, "skill": skill_id, "target": target_uid}]
	ev.append({"kind": "skill", "who": f.uid, "skill": skill_id, "name": str(s.get("name", "")), "target": target_uid})
	var kind := str(s.get("kind", ""))
	var cost: Dictionary = s.get("cost", {})
	if int(cost.get("psyche", 0)) != 0:
		ev.append_array(psyche(f, int(cost["psyche"]), "цена навыка"))
	if kind == "step":
		var t := by_uid(target_uid)
		SkFormation.move(fighters, f, 1 if t.pos > f.pos else -1)
		ev.append({"kind": "move", "who": f.uid, "pos": f.pos})
	elif kind == "recall":
		f.removed = true
		ev.append({"kind": "recall", "who": f.uid})
		SkFormation.relayout(fighters, f.side)
	elif kind != "pass":
		var hostile := str(s.get("side", "enemy")) == "enemy"
		var list := _hit_list(f, s, target_uid)
		if hostile and target_uid != "all" and not list.is_empty():
			list = [_guarded(list[0], ev)]
		for t: SkFighter in list:
			if not t.in_line() or outcome != "":
				continue
			ev.append_array(_strike(f, s, t))
		if hostile and f.has_status("stealth") and not s.get("effects", []).any(func(e: Dictionary) -> bool: return bool(e.get("self", false)) and str(e["type"]) == "stealth"):
			SkStatus.remove(f, "stealth")
			ev.append({"kind": "reveal", "who": f.uid})
		# контратака: цель одиночного удара ближнего боя отвечает
		if hostile and target_uid != "all" and not bool(s.get("ranged", false)) and f.alive():
			var t2: SkFighter = list[0] if not list.is_empty() else null
			if t2 != null and t2.alive() and t2.has_status("riposte"):
				ev.append_array(_riposte(t2, f))
		if int(s.get("self_move", 0)) != 0 and f.alive():
			if SkFormation.move(fighters, f, int(s["self_move"])) != 0:
				ev.append({"kind": "move", "who": f.uid, "pos": f.pos})
	if int(s.get("cooldown", 0)) > 0:
		f.cooldown[skill_id] = int(s["cooldown"]) + 1   # +1: убывает уже в начале следующего своего хода
	f.used[skill_id] = int(f.used.get(skill_id, 0)) + 1
	ev.append_array(_check_end())
	log.append_array(ev)
	return ev


## Защита (guard): одиночный удар по подзащитному принимает защитник.
func _guarded(t: SkFighter, ev: Array) -> SkFighter:
	var g := t.status("guard")
	if g.is_empty():
		return t
	var by := by_uid(str(g.get("by", "")))
	if by != null and by.alive() and by != t:
		ev.append({"kind": "guarded", "who": t.uid, "by": by.uid})
		return by
	return t


## Удар (или помощь) по одной цели: бросок, урон, крит, эффекты.
func _strike(a: SkFighter, s: Dictionary, t: SkFighter) -> Array:
	var ev: Array = []
	var pv := SkStrike.preview(self, a, s, t)
	var r := SkStrike.roll(self, pv)
	var hostile := str(s.get("side", "enemy")) == "enemy"
	# Уклон (жетон): тратится на любой удар по бойцу; попадание — 50% промаха (как в Darkest Dungeon II)
	if hostile and t.has_status("dodge") and not a.has_status("sure") and SkStatus.spend(t, "dodge") and bool(r["hit"]):
		if rng.randi_range(1, 100) <= 50:
			r["hit"] = false
			r["effects"] = []
			ev.append({"kind": "dodge", "who": t.uid})
	if hostile:
		SkStatus.remove(a, "sure")
	if not bool(r["hit"]):
		ev.append({"kind": "miss", "who": a.uid, "to": t.uid})
	elif int(r["dmg"]) > 0:
		var dmg := int(r["dmg"])
		if t.has_status("block"):
			SkStatus.spend(t, "block")
			dmg = int(ceil(dmg * 0.5))
			ev.append({"kind": "block", "who": t.uid})
		SkStatus.remove(a, "empower")
		ev.append({"kind": "hit", "who": a.uid, "to": t.uid, "dmg": dmg, "crit": bool(r["crit"])})
		ev.append_array(hurt(t, dmg, a, "hit"))
		if float(s.get("lifesteal", 0.0)) > 0.0 and a.alive():
			ev.append_array(heal(a, int(floor(dmg * float(s["lifesteal"])))))
		if a.has_status("ignite") and t.alive():
			ev.append_array(apply_effect(a, t, {"type": "burn", "power": 2, "turns": 2}))
		if bool(r["crit"]):
			ev.append_array(_on_crit(a, t))
	var effs: Array = s.get("effects", [])
	for i: int in r["effects"]:
		var e: Dictionary = effs[i]
		var target := a if bool(e.get("self", false)) else t
		if not target.in_line():
			continue
		ev.append_array(apply_effect(a, target, e, bool(r["crit"])))
	return ev


## Эффект навыка (уже прошедший бросок и сопротивление).
func apply_effect(a: SkFighter, t: SkFighter, e: Dictionary, crit: bool = false) -> Array:
	if bool(e.get("dark_double", false)) and light in SkStrike.DARK:
		e = e.duplicate()
		e["value"] = float(e.get("value", 0)) * 2.0
		e["turns"] = int(e.get("turns", 1)) * 2 if str(e["type"]) == "stealth" else int(e.get("turns", 1))
	var et := str(e["type"])
	var ev: Array = []
	match et:
		"bleed", "poison":
			if t.corpse:
				return []
			var pw := int(e.get("power", 1)) + (1 if crit else 0)
			if SkStatus.add(t, {"type": et, "power": pw, "turns": int(e.get("turns", 3))}):
				ev.append({"kind": "status", "to": t.uid, "type": et, "power": pw})
		"stun", "mark", "riposte", "stealth":
			if t.corpse:
				return []
			if SkStatus.add(t, {"type": et, "turns": int(e.get("turns", 1 if et == "stun" else 2))}):
				ev.append({"kind": "status", "to": t.uid, "type": et})
		"guard":
			if t != a and t.alive():
				SkStatus.add(t, {"type": "guard", "by": a.uid, "turns": int(e.get("turns", 2))})
				SkStatus.add(a, {"type": "guarding", "ward": t.uid, "turns": int(e.get("turns", 2))})
				ev.append({"kind": "status", "to": t.uid, "type": "guard", "by": a.uid})
		"buff", "debuff":
			if t.corpse:
				return []
			if SkStatus.add(t, {"type": et, "stat": str(e.get("stat", "dmg")), "value": float(e.get("value", 0)), "turns": int(e.get("turns", 2))}):
				ev.append({"kind": "status", "to": t.uid, "type": et, "stat": str(e.get("stat", ""))})
		"push", "pull":
			if t.has_status("steady"):
				return []
			var n := int(e.get("n", 1)) * (1 if et == "push" else -1)
			if SkFormation.move(fighters, t, n) != 0:
				ev.append({"kind": "move", "who": t.uid, "pos": t.pos})
		"heal":
			ev.append_array(heal(t, rng.randi_range(int(e.get("min", 2)), int(e.get("max", 4)))))
		"psyche":
			var pv2 := int(e.get("value", 0))
			ev.append_array(psyche(t, pv2, "удар по рассудку" if pv2 < 0 else "слова поддержки"))
		"burn":
			if t.corpse:
				return []
			if SkStatus.add(t, {"type": "burn", "power": int(e.get("power", 2)) + (1 if crit else 0), "turns": int(e.get("turns", 2))}):
				SkStatus.remove(t, "stealth")
				ev.append({"kind": "status", "to": t.uid, "type": "burn"})
		"dodge", "block":
			SkStatus.add(t, {"type": et, "charges": int(e.get("charges", 1))})
			ev.append({"kind": "status", "to": t.uid, "type": et})
		"taunt", "foresight", "blind", "fear", "ignite", "steady", "empower":
			if t.corpse:
				return []
			var turns := int(e.get("turns", 2))
			if SkStatus.add(t, {"type": et, "turns": turns}):
				ev.append({"kind": "status", "to": t.uid, "type": et})
		"sure":
			SkStatus.add(t, {"type": "sure", "turns": int(e.get("turns", 2)), "crit": int(e.get("crit", 0))})
			ev.append({"kind": "status", "to": t.uid, "type": "sure"})
		"heal_pct":
			ev.append_array(heal(t, int(ceil(t.hp_max * float(e.get("value", 0.25))))))
		"cleanse":
			var gone: Array = []
			for ct: String in e.get("types", []):
				if t.has_status(ct):
					SkStatus.remove(t, ct)
					gone.append(ct)
			if not gone.is_empty():
				ev.append({"kind": "cleanse", "who": t.uid, "types": gone})
		"remove_buffs":
			for bt: String in SkStatus.BUFFS:
				SkStatus.remove(t, bt)
			ev.append({"kind": "strip", "who": t.uid})
		"unstealth":
			if t.has_status("stealth"):
				SkStatus.remove(t, "stealth")
				ev.append({"kind": "reveal", "who": t.uid})
		"unstealth_all":
			for x: SkFighter in living(t.side):
				if x.has_status("stealth"):
					SkStatus.remove(x, "stealth")
					ev.append({"kind": "reveal", "who": x.uid})
		"reveal":
			ev.append({"kind": "know", "who": t.uid, "tags": t.tags.duplicate()})
		"swap":
			if t != a and t.side == a.side and t.alive() and not t.has_status("steady"):
				var ln := SkFormation.line(fighters, a.side)
				var ia := ln.find(a)
				var it := ln.find(t)
				SkFormation.move(fighters, a, it - ia)
				ev.append({"kind": "swap", "who": a.uid, "with": t.uid})
		"extra_turn":
			bonus_turn = t.uid
			ev.append({"kind": "extra_turn", "who": t.uid})
		"summon":
			ev.append_array(_summon(a, str(e.get("card", ""))))
		"light_ward":
			ward_rounds = maxi(ward_rounds, int(e.get("rounds", 3)))
			ev.append({"kind": "ward", "rounds": ward_rounds})
	return ev


## Призвать Эхо карты на свободную позицию в конце строя.
func _summon(owner: SkFighter, card: String) -> Array:
	if _summon_why(owner, card) != "":
		return []
	var old: SkFighter = null
	for x: SkFighter in fighters:
		if x.echo and x.card == card:
			old = x
	var ec := old
	if ec == null:
		ec = SkBuild.echo(content, state, card, owner.card)
		ec.uid = _next_echo_uid()
		fighters.append(ec)
	ec.removed = false
	ec.pos = 99
	SkFormation.relayout(fighters, owner.side)
	return [{"kind": "summon", "who": ec.uid, "by": owner.uid, "pos": ec.pos}]


func _riposte(t: SkFighter, a: SkFighter) -> Array:
	var s: Dictionary = {}
	for x: Dictionary in t.skills:
		if str(x.get("side", "")) == "enemy" and int(x.get("dmg", t.dmg)[1]) > 0:
			s = x.duplicate()
			break
	if s.is_empty():
		return []
	s["mult"] = float(s.get("mult", 1.0)) * 0.75
	s["effects"] = []
	var ev: Array = [{"kind": "riposte", "who": t.uid, "to": a.uid}]
	ev.append_array(_strike(t, s, a))
	return ev


# --- урон, лечение, грань, психика --------------------------------------------------------------------------------------

## Урон бойцу. source: hit | dot. Герой на нуле — грань; по герою на грани — бросок смерти.
func hurt(t: SkFighter, amount: int, by: SkFighter, source: String) -> Array:
	var ev: Array = []
	if amount <= 0 or not t.in_line():
		return ev
	if t.corpse:
		t.hp -= amount
		if t.hp <= 0:
			t.corpse = false
			t.removed = true
			ev.append({"kind": "corpse_gone", "who": t.uid})
			SkFormation.relayout(fighters, t.side)
		return ev
	if t.is_hero() and t.edge:
		return _edge_hit(t)
	t.hp -= amount
	ev.append({"kind": "dmg", "to": t.uid, "value": amount, "hp": maxi(0, t.hp)})
	if t.hp > 0:
		return ev
	t.hp = 0
	if t.side == "enemy":
		ev.append_array(_kill_enemy(t, by, source))
	elif t.echo:
		t.dead = true
		lost_echoes.append(t.card)
		state.collection.erase(t.card)
		Array(state.character(t.owner).get("pocket", [])).erase(t.card)
		entries.append({"kind": "broken", "card": t.card, "text": "%s рассыпается — карта потеряна" % t.name})
		ev.append({"kind": "echo_lost", "who": t.uid})
		SkFormation.relayout(fighters, t.side)
	else:
		ev.append_array(_hero_falls(t))
	return ev


func _kill_enemy(t: SkFighter, by: SkFighter, source: String) -> Array:
	var ev: Array = [{"kind": "kill", "who": t.uid, "by": by.uid if by != null else ""}]
	t.statuses = []
	if t.no_corpse or t.size > 1 or source == "dot":
		t.dead = true
		SkFormation.relayout(fighters, t.side)
	else:
		t.corpse = true
		t.hp = maxi(1, int(ceil(t.hp_max * CORPSE_SHARE)))
		t.corpse_rounds = CORPSE_ROUNDS
		ev.append({"kind": "corpse", "who": t.uid})
	if by != null and by.is_hero():
		ev.append_array(psyche(by, PSY_KILL, "враг повержен"))
	return ev


func _pocket(cid: String) -> Array:
	return MissionFlow.pocket(state, cid)


## Здоровье героя упало до нуля: грань (или щит карты — остаётся 1 здоровья).
func _hero_falls(t: SkFighter) -> Array:
	var ev: Array = []
	EdgeRules.defeat(content, state, t.card, _pocket(t.card), rng, result, entries, shielded)
	if EdgeRules.on_edge(state, t.card):
		t.edge = true
		ev.append({"kind": "edge", "who": t.uid})
		for h: SkFighter in heroes_alive():
			if h != t:
				ev.append_array(psyche(h, PSY_EDGE, "товарищ на грани"))
	else:
		t.hp = 1
		ev.append({"kind": "shield", "who": t.uid})
	return ev


## Удар по герою на грани — бросок смерти.
func _edge_hit(t: SkFighter) -> Array:
	var ev: Array = []
	result["death"] = {}
	EdgeRules.defeat(content, state, t.card, _pocket(t.card), rng, result, entries, shielded)
	var d: Dictionary = result.get("death", {})
	if not state.is_alive(t.card):
		t.dead = true
		ev.append({"kind": "death", "who": t.uid, "chance": int(d.get("chance", 0)), "roll": int(d.get("roll", 0))})
		SkFormation.relayout(fighters, t.side)
		for h: SkFighter in heroes_alive():
			ev.append_array(psyche(h, PsycheRules.DEATH, "гибель товарища"))
	else:
		ev.append({"kind": "survive", "who": t.uid, "chance": int(d.get("chance", 0)), "roll": int(d.get("roll", 0))})
	return ev


## Лечение. Герой на грани с лечением отходит от грани, но до лагеря — «Слабость после грани».
func heal(t: SkFighter, amount: int) -> Array:
	if amount <= 0 or not t.alive():
		return []
	var ev: Array = []
	t.hp = mini(t.hp_max, t.hp + amount)
	ev.append({"kind": "heal", "who": t.uid, "value": amount})
	if t.is_hero() and t.edge and t.hp > 0:
		t.edge = false
		EdgeRules.recover(content, state, t.card, "лечение в бою", entries)
		SkStatus.add(t, {"type": "weak", "turns": 999})
		ev.append({"kind": "edge_off", "who": t.uid})
	return ev


## Психика героя (± значение). Кризис на нуле — PsycheRules (паника или подъём духа до конца боя).
func psyche(f: SkFighter, delta: int, reason: String) -> Array:
	if not f.is_hero() or not f.alive() or delta == 0:
		return []
	var before := PsycheRules.psyche(state, f.card)
	var rec := PsycheRules.change(content, state, f.card, delta, reason, squad, rng, "combat")
	var ev: Array = []
	var after := PsycheRules.psyche(state, f.card)
	if after != before:
		ev.append({"kind": "psyche", "who": f.uid, "value": after - before, "psyche": after})
	for r: Dictionary in rec:
		if str(r.get("kind", "")) == "crisis":
			ev.append({"kind": "crisis", "who": f.uid, "state": str(r.get("state", "")), "quote": str(r.get("quote", ""))})
			entries.append(r)
	return ev


func _on_crit(a: SkFighter, t: SkFighter) -> Array:
	var ev: Array = []
	if a.is_hero():
		ev.append_array(psyche(a, PSY_HERO_CRIT[0], "точный удар"))
		for h: SkFighter in heroes_alive():
			if h != a:
				ev.append_array(psyche(h, PSY_HERO_CRIT[1], "точный удар товарища"))
	elif t.is_hero() and t.alive():
		ev.append_array(psyche(t, PSY_ENEMY_CRIT[0], "страшный удар"))
		for h: SkFighter in heroes_alive():
			if h != t and absi(h.pos - t.pos) == 1:
				ev.append_array(psyche(h, PSY_ENEMY_CRIT[1], "страшный удар рядом"))
	return ev


# --- отступление и итог -----------------------------------------------------------------------------------------------

func retreat_chance() -> int:
	if no_retreat:
		return 0
	var fast := living("enemy").filter(func(e: SkFighter) -> bool: return e.tags.any(func(t: String) -> bool: return FAST_TAGS.has(t))).size()
	return maxi(RETREAT_MIN, RETREAT_BASE - RETREAT_FAST * fast)


## Отступить в ход героя f (ход тратится). Удача — бой окончен (outcome "retreat").
func retreat(f: SkFighter) -> Array:
	var ev: Array = []
	var ch := retreat_chance()
	if ch <= 0:
		ev.append({"kind": "retreat_blocked", "who": f.uid})
	elif rng.randi_range(1, 100) <= ch:
		outcome = "retreat"
		ev.append({"kind": "retreat", "who": f.uid, "chance": ch})
		ev.append({"kind": "end", "outcome": outcome})
	else:
		ev.append({"kind": "retreat_failed", "who": f.uid, "chance": ch})
		for h: SkFighter in heroes_alive():
			ev.append_array(psyche(h, PSY_RETREAT_FAIL, "не удалось отступить"))
	log.append_array(ev)
	return ev


func _check_end() -> Array:
	if outcome != "":
		return []
	var why := ""
	if living("enemy").is_empty():
		outcome = "win"
	else:
		var hs := heroes_alive()
		if hs.is_empty():
			outcome = "loss"
		elif hs.all(func(h: SkFighter) -> bool: return h.edge):
			outcome = "loss"
			why = "rout"    # все живые на грани — отряд вырывается из боя
	if outcome == "":
		return []
	var e := {"kind": "end", "outcome": outcome, "why": why}
	log.append(e)
	return [e]


## Ход ИИ (враги; герои — у бота и в тестах).
func ai_act(f: SkFighter) -> Array:
	var c := SkAI.choose(self, f)
	if c.is_empty():
		return act(f, "PASS", f.uid)
	return act(f, str(c["skill"]), str(c["target"]))


## Провести бой целиком ИИ за обе стороны (бот, тесты, прогноз).
func auto(max_turns: int = 400) -> String:
	var n := 0
	while outcome == "" and n < max_turns:
		var f := turn()
		if f == null:
			break
		if f.side == "hero" and SkAI.should_retreat(self):
			retreat(f)
		else:
			ai_act(f)
		n += 1
	return outcome


## Итог: здоровье героев — в состояние, кризисы боя кончаются. {outcome, state, entries, rounds}.
func finish() -> Dictionary:
	var echo_hp: Dictionary = state.flags.get("echo_hp", {})
	for f: SkFighter in fighters:
		if f.is_hero() and state.is_alive(f.card):
			state.character(f.card)["hp"] = f.hp
			PsycheRules.reset(state, f.card, "combat")
		elif f.echo and not f.dead:
			echo_hp[f.card] = f.hp
	for card: String in lost_echoes:
		echo_hp.erase(card)
	state.flags["echo_hp"] = echo_hp
	state.rng_state = rng.state
	return {"outcome": outcome, "state": state, "entries": entries, "rounds": round_no}
