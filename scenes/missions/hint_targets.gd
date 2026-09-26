class_name HintTargets
extends RefCounted
## Куда указывает подсказка обучения (docs/16 Ф12): окна и карта регистрируют свои элементы по имени,
## HintPopup каждый кадр спрашивает их прямоугольник на экране — и обводит его золотой нитью.
## Имя может означать несколько элементов (например, все кнопки развилки) — тогда берётся их общая рамка.
## Для того, что вычисляется на лету (карта героя с травмой, метка миссии со сроком), карта задаёт resolver.

static var _items := {}          # имя -> Array[Control]
static var resolver := Callable() # func(name: String) -> Rect2 (пустой — не нашлось)


static func put(name: String, controls: Array) -> void:
	_items[name] = controls.duplicate()


static func add(name: String, c: Control) -> void:
	var list: Array = _items.get(name, [])
	list = list.filter(func(x: Variant) -> bool: return is_instance_valid(x))
	list.append(c)
	_items[name] = list


## Рамка цели на экране (пустая, если цели сейчас нет или она скрыта).
static func rect(name: String) -> Rect2:
	var out := Rect2()
	for c: Variant in _items.get(name, []):
		if is_instance_valid(c) and (c as Control).is_visible_in_tree():
			var r := (c as Control).get_global_rect()
			out = r if out.size == Vector2.ZERO else out.merge(r)
	if out.size == Vector2.ZERO and resolver.is_valid():
		out = resolver.call(name)
	return out
