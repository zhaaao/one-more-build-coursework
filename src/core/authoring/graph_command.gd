class_name GraphCommand
extends RefCounted

## Immutable intent record for one synchronous typed graph edit.
##
## Example: `model.admit(GraphCommand.new(GraphCommand.Kind.CREATE_NODE, payload))`.

enum Kind { CREATE_NODE, MOVE_NODE, DELETE_NODE, CONNECT }

var _locked: bool = false:
	set(value):
		if _locked:
			return
		_locked = value

var _kind: Kind:
	set(value):
		if _locked:
			return
		_kind = value
var _payload: Dictionary = {}:
	get:
		return _payload.duplicate(true)
	set(value):
		if _locked:
			return
		_payload = value.duplicate(true)

func _init(kind: Kind, payload: Dictionary = {}) -> void:
	_locked = false
	_kind = kind
	_payload = payload
	_locked = true

## Creates a node-creation intent from unsnapped finite release coordinates.
## Example: `GraphCommand.create_node(&"Start", &"start", {"x": 0, "y": 0})`.
static func create_node(category: StringName, variant_id: StringName, anchor: Dictionary) -> GraphCommand:
	return new(Kind.CREATE_NODE, {"category": category, "variant_id": variant_id, "anchor": anchor})

## Creates a move intent using the unsnapped release coordinates.
## Example: `GraphCommand.move_node(&"node_1", 113.0, 74.0)`.
static func move_node(node_id: StringName, released_x: float, released_y: float) -> GraphCommand:
	return new(Kind.MOVE_NODE, {"node_id": node_id, "released_x": released_x, "released_y": released_y})

## Creates a deletion intent for one eligible node.
## Example: `GraphCommand.delete_node(&"node_1")`.
static func delete_node(node_id: StringName) -> GraphCommand:
	return new(Kind.DELETE_NODE, {"node_id": node_id})

## Creates a directed output-to-input connection intent.
## Example: `GraphCommand.connect_ports(&"node_1", &"out", &"node_2", &"in")`.
static func connect_ports(output_node_id: StringName, output_port_id: StringName, input_node_id: StringName, input_port_id: StringName) -> GraphCommand:
	return new(Kind.CONNECT, {
		"output_node_id": output_node_id,
		"output_port_id": output_port_id,
		"input_node_id": input_node_id,
		"input_port_id": input_port_id,
	})

## Returns the command category without exposing mutable payload data.
## Example: `if command.kind() == GraphCommand.Kind.MOVE_NODE: pass`.
func kind() -> Kind:
	return _kind

## Returns a detached payload projection.
## Example: `var payload: Dictionary = command.payload()`.
func payload() -> Dictionary:
	return _payload.duplicate(true)
