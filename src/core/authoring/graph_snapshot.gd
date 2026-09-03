class_name GraphSnapshot
extends RefCounted

## Immutable projection of accepted authoring graph truth.
##
## Example: `var nodes: Array = model.snapshot().nodes()`.

var _locked: bool = false:
	set(value):
		if _locked:
			return
		_locked = value

var _state: Dictionary = {}:
	get:
		return _state.duplicate(true)
	set(value):
		if _locked:
			return
		_state = value.duplicate(true)

const LANGUAGE_CATEGORIES: Array[StringName] = [&"Start", &"Action", &"Query", &"Constant", &"Compare", &"Branch", &"Repeat", &"End"]

func _init(state: Dictionary = {}) -> void:
	_locked = false
	_state = state
	_locked = true

## Returns detached nodes in stable node-id order.
## Example: `var nodes: Array = snapshot.nodes()`.
func nodes() -> Array:
	var projected: Array = Array(_state.get("nodes", [])).duplicate(true)
	projected.sort_custom(_node_id_is_before)
	return projected

## Returns detached connections in stable connection-id order.
## Example: `var connections: Array = snapshot.connections()`.
func connections() -> Array:
	var projected: Array = Array(_state.get("connections", [])).duplicate(true)
	projected.sort_custom(_connection_id_is_before)
	return projected

func _node_id_is_before(left: Dictionary, right: Dictionary) -> bool:
	return String(left["node_id"]) < String(right["node_id"])

func _connection_id_is_before(left: Dictionary, right: Dictionary) -> bool:
	return String(left["connection_id"]) < String(right["connection_id"])

## Returns the accepted task configuration without mutable owner references.
## Example: `var grid_size: int = snapshot.task()["grid_size"]`.
func task() -> Dictionary:
	return Dictionary(_state.get("task", {})).duplicate(true)

## Returns the count of accepted nodes.
## Example: `assert(snapshot.node_count() <= 24)`.
func node_count() -> int:
	return nodes().size()

## Returns the count of accepted connections.
## Example: `assert(snapshot.connection_count() <= 96)`.
func connection_count() -> int:
	return connections().size()

## Returns a node anchor or an empty dictionary when the node is unknown.
## Example: `var anchor: Dictionary = snapshot.anchor_for(&"node_1")`.
func anchor_for(node_id: StringName) -> Dictionary:
	for raw_node: Variant in nodes():
		var node: Dictionary = raw_node
		if StringName(node.get("node_id", &"")) == node_id:
			return Dictionary(node.get("anchor", {})).duplicate(true)
	return {}

## Returns exactly the eight language categories in their stable order.
## Example: `var categories: Array[StringName] = snapshot.language_categories()`.
func language_categories() -> Array[StringName]:
	return LANGUAGE_CATEGORIES.duplicate()

## Returns only categories with at least one task-creatable variant.
## Example: `var palette: Array[StringName] = snapshot.creatable_categories()`.
func creatable_categories() -> Array[StringName]:
	var categories: Array[StringName] = []
	for raw_variant: Variant in Array(task().get("variants", [])):
		var variant: Dictionary = raw_variant
		if bool(variant.get("creatable", false)):
			var category := StringName(variant.get("category", &""))
			if not categories.has(category):
				categories.append(category)
	return categories
