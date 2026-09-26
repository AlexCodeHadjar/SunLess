class_name HintTargets
extends RefCounted
## Куда указывает подсказка обучения (docs/16 Ф12): окна и карта регистрируют свои элементы по имени,
## HintPopup каждый кадр спрашивает их прямоугольник на экране — и обводит его золотой нитью.
## Имя может означать несколько элементов (например, все кнопки развилки) — тогда берётся их общая рамка.
## Для того, что вычисляется на лету (карта героя с травмой, метка миссии со сроком), карта задаёт resolver.

const LAYER := "hint_layer"      # группа окон поверх карты (миссия, магазин, планшет, бой…)

static var _items := {}          # имя -> Array[Control]
static var resolver := Callable() # func(name: String) -> Rect2 (пустой — не нашлось)


static func put(name: String, controls: Array) -> void:
	_items[name] = controls.duplicate()


static func add(name: String, c: Control) -> void:
	var list: Array = _items.get(name, [])
	list = list.filter(func(x: Variant) -> bool: return is_instance_valid(x))
	list.append(c)
	_items[name] = list


## Самое верхнее открытое окно (или null — открыта только карта).
static func top_layer() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var top: Node = null
	for n: Node in tree.get_nodes_in_group(LAYER):
		if n is CanvasItem and (n as CanvasItem).is_visible_in_tree() and not n.is_queued_for_deletion():
			if top == null or n.is_greater_than(top):
				top = n
	return top


## Рамка цели на экране (пустая, если цели сейчас нет, она скрыта или её закрывает окно поверх).
static func rect(name: String) -> Rect2:
	var out := Rect2()
	var top := top_layer()
	for c: Variant in _items.get(name, []):
		if is_instance_valid(c) and (c as Control).is_visible_in_tree() and (top == null or top.is_ancestor_of(c)):
			var r := (c as Control).get_global_rect()
			out = r if out.size == Vector2.ZERO else out.merge(r)
	if out.size == Vector2.ZERO and top == null and resolver.is_valid():
		out = resolver.call(name)
	return out
