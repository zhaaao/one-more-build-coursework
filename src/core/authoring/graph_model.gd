class_name GraphModel
extends RefCounted

const GraphCommandType = preload("res://src/core/authoring/graph_command.gd")
const GraphSnapshotType = preload("res://src/core/authoring/graph_snapshot.gd")
const GraphDiagnostic = preload("res://src/core/authoring/graph_diagnostic.gd")
const GraphHistoryType = preload("res://src/core/authoring/graph_history.gd")
const GraphRevisionType = preload("res://src/core/authoring/graph_revision.gd")

## Synchronous owner of typed graph edit admission for Story 001.
##
## Example: `var result: DomainResult = model.admit(GraphCommandType.new(GraphCommandType.Kind.CREATE_NODE, payload))`.

const REQUIRED_CATEGORIES: Array[StringName] = [&"Start", &"Action", &"Query", &"Constant", &"Compare", &"Branch", &"Repeat", &"End"]
const MIN_GRID_SIZE: int = 8
const MAX_GRID_SIZE: int = 32
const MIN_NODE_LIMIT: int = 4
const MAX_NODE_LIMIT: int = 24
const MAX_CONNECTION_LIMIT: int = 96
const MAX_REGISTERED_VARIANTS: int = 32
const MAX_CREATABLE_VARIANTS: int = 16
const MAX_PORTS_PER_VARIANT: int = 8
const MAX_PARAMETERS_PER_VARIANT: int = 6
const MAX_CANVAS_SPAN: int = 4096
const MAX_EXACT_INTEGER: int = 9007199254740992
const MAX_EXACT_INTEGER_FLOAT: float = 9007199254740992.0

var _accepted_snapshot: GraphSnapshotType
var _construction_result: DomainResult
var _history: GraphHistoryType = GraphHistoryType.new()
var _revision: GraphRevisionType = GraphRevisionType.new()
var _completed_report_revision: int = 0
var _player_content_committed: bool = false
var _task_starting_snapshot: GraphSnapshotType = null
var _task_starting_snapshot_finalized: bool = false
var _run_mutation_fenced: bool = false
var _saved_provenance_revision: int = 0

func _init(task: Dictionary = {}, initial_revision: int = GraphRevisionType.INITIAL_REVISION) -> void:
	var revision_result: DomainResult = GraphRevisionType.create_at(initial_revision)
	if not revision_result.is_success():
		_construction_result = revision_result
		return
	_revision = revision_result.value()
	var normalized: DomainResult = _validate_task(task)
	if not normalized.is_success():
		_construction_result = normalized
		return
	_accepted_snapshot = GraphSnapshotType.new({
		"task": normalized.value(),
		"nodes": [],
		"connections": [],
		"next_node_number": 1,
		"next_connection_number": 1,
	})
	_task_starting_snapshot = _accepted_snapshot
	_construction_result = DomainResult.success(self)

## Validates task-owned graph metadata and returns a model only on success.
## Example: `var result: DomainResult = GraphModelType.create(task)`.
static func create(task: Dictionary, initial_revision: int = GraphRevisionType.INITIAL_REVISION) -> DomainResult:
	return new(task, initial_revision).construction_result()

## Rebuilds a fresh editable model from one admitted saved graph. The saved
## revision remains provenance only; the fresh live revision is allocated after
## proving the caller's current revision can advance without wrapping.
static func restore_from_recovery_projection(
	task: Dictionary,
	task_starting_graph: Dictionary,
	saved_graph: Dictionary,
	saved_revision: int,
	current_live_revision: int
) -> DomainResult:
	if saved_revision < 1 or current_live_revision < 1:
		return GraphDiagnostic.reject(&"invalid_revision", "Saved and live graph revisions must be positive.")
	var revision_probe: DomainResult = GraphRevisionType.create_at(current_live_revision)
	if not revision_probe.is_success():
		return revision_probe
	var allocator: GraphRevisionType = revision_probe.value() as GraphRevisionType
	if not allocator.can_allocate():
		return GraphDiagnostic.reject(&"revision_exhausted", "Recovery cannot allocate another positive graph revision.")
	var model_result: DomainResult = create(task, current_live_revision)
	if not model_result.is_success():
		return model_result
	var model: GraphModel = model_result.value() as GraphModel
	var restored_result: DomainResult = model._replace_recovery_graph(saved_graph, task_starting_graph, saved_revision)
	if not restored_result.is_success():
		return restored_result
	var allocated: DomainResult = model._revision.allocate_next()
	if not allocated.is_success():
		return allocated
	return DomainResult.success(model)

## Returns the result of task metadata validation at construction.
## Example: `var result: DomainResult = GraphModelType.new(task).construction_result()`.
func construction_result() -> DomainResult:
	return _construction_result

## Returns the current immutable accepted graph projection.
## Example: `var nodes: Array = model.snapshot().nodes()`.
func snapshot() -> GraphSnapshotType:
	return _accepted_snapshot

## Admits one structural command synchronously or preserves the exact prior snapshot.
## Example: `var result: DomainResult = model.admit(GraphCommand.create_node(&"Start", &"start", {"x": 0, "y": 0}))`.
func admit(command: Variant) -> DomainResult:
	if not _construction_result.is_success():
		return _construction_result
	if _run_mutation_fenced:
		return _run_mutation_rejected()
	var result: DomainResult = _reduce_snapshot(_accepted_snapshot, command)
	if result.is_success():
		return _commit_snapshot(result.value(), &"command")
	return result

## Admits a bounded command sequence atomically as one revision and history entry.
## Example: `var result: DomainResult = model.admit_all([delete_command, connect_command])`.
func admit_all(commands: Array[GraphCommand]) -> DomainResult:
	if not _construction_result.is_success():
		return _construction_result
	if _run_mutation_fenced:
		return _run_mutation_rejected()
	if commands.is_empty():
		return GraphDiagnostic.reject(&"empty_command_batch", "A graph command batch cannot be empty.")
	var candidate_snapshot: GraphSnapshotType = _accepted_snapshot
	for command: GraphCommand in commands:
		var result: DomainResult = _reduce_snapshot(candidate_snapshot, command)
		if not result.is_success():
			return result
		candidate_snapshot = result.value()
	return _commit_snapshot(candidate_snapshot, &"command_batch")

## Creates one task-allowed node as a reversible content operation.
## Example: `var result: DomainResult = model.create_node(&"Action", &"action", {"x": 0, "y": 0})`.
func create_node(category: StringName, variant_id: StringName, anchor: Dictionary) -> DomainResult:
	if _run_mutation_fenced:
		return _run_mutation_rejected()
	if not anchor.has("x") or not anchor.has("y") or not _is_release_coordinate(anchor["x"]) or not _is_release_coordinate(anchor["y"]):
		return GraphDiagnostic.reject(&"invalid_anchor", "Create node anchors require finite numeric x and y values.")
	return _admit_content_state(_admit_create(_accepted_snapshot._state.duplicate(true), {"category": category, "variant_id": variant_id, "anchor": anchor}), &"create_node")

## Moves any existing node as one reversible content operation.
## Example: `var result: DomainResult = model.move_node(&"node_1", 16, 0)`.
func move_node(node_id: StringName, released_x: Variant, released_y: Variant) -> DomainResult:
	if _run_mutation_fenced:
		return _run_mutation_rejected()
	return _admit_content_state(_admit_move(_accepted_snapshot._state.duplicate(true), {"node_id": node_id, "released_x": released_x, "released_y": released_y}), &"move_node")

## Deletes an eligible node and all incident edges as one reversible content operation.
## Example: `var result: DomainResult = model.delete_node(&"node_1")`.
func delete_node(node_id: StringName) -> DomainResult:
	if _run_mutation_fenced:
		return _run_mutation_rejected()
	return _admit_content_state(_admit_delete(_accepted_snapshot._state.duplicate(true), {"node_id": node_id}), &"delete_node")

## Connects compatible ports as one reversible content operation.
## Example: `var result: DomainResult = model.connect_ports(&"node_1", &"out", &"node_2", &"in")`.
func connect_ports(output_node_id: StringName, output_port_id: StringName, input_node_id: StringName, input_port_id: StringName) -> DomainResult:
	if _run_mutation_fenced:
		return _run_mutation_rejected()
	return _admit_content_state(_admit_connect(_accepted_snapshot._state.duplicate(true), {"output_node_id": output_node_id, "output_port_id": output_port_id, "input_node_id": input_node_id, "input_port_id": input_port_id}), &"connect")

## Disconnects one stable connection id as a reversible content operation.
## Example: `var result: DomainResult = model.disconnect_connection(&"connection_1")`.
func disconnect_connection(connection_id: StringName) -> DomainResult:
	if _run_mutation_fenced:
		return _run_mutation_rejected()
	var state: Dictionary = _accepted_snapshot._state.duplicate(true)
	var connections: Array = Array(state["connections"])
	for index: int in range(connections.size()):
		if StringName(Dictionary(connections[index])["connection_id"]) == connection_id:
			connections.remove_at(index)
			state["connections"] = connections
			return _commit_snapshot(GraphSnapshotType.new(state), &"disconnect")
	return GraphDiagnostic.reject(&"unknown_connection", "The connection to disconnect does not exist.")

## Replaces the sole edge on an occupied compatible input as one reversible operation.
## Example: `var result: DomainResult = model.replace_connection(&"node_3", &"out", &"node_2", &"in")`.
func replace_connection(output_node_id: StringName, output_port_id: StringName, input_node_id: StringName, input_port_id: StringName) -> DomainResult:
	if _run_mutation_fenced:
		return _run_mutation_rejected()
	var state: Dictionary = _accepted_snapshot._state.duplicate(true)
	var connections: Array = Array(state["connections"])
	var occupied_index: int = -1
	for index: int in range(connections.size()):
		var connection: Dictionary = connections[index]
		if StringName(connection["output_node_id"]) == output_node_id and StringName(connection["output_port_id"]) == output_port_id and StringName(connection["input_node_id"]) == input_node_id and StringName(connection["input_port_id"]) == input_port_id:
			return GraphDiagnostic.reject(&"duplicate_connection", "This connection already exists.")
		if StringName(connection["input_node_id"]) == input_node_id and StringName(connection["input_port_id"]) == input_port_id:
			if occupied_index >= 0:
				return GraphDiagnostic.reject(&"input_not_replaceable", "An input with multiple sources cannot be replaced.")
			occupied_index = index
	if occupied_index < 0:
		return GraphDiagnostic.reject(&"input_not_occupied", "Replacement requires an occupied input port.")
	var input_node: Dictionary = _find_node(Array(state["nodes"]), input_node_id)
	var input_variant: Dictionary = _find_variant(Dictionary(state["task"]), StringName(input_node["variant_id"]))
	var input_port: Dictionary = _find_port(input_variant, input_port_id)
	if bool(input_port.get("multiple_execution_sources", false)):
		return GraphDiagnostic.reject(&"input_not_replaceable", "An input that accepts multiple sources cannot be replaced.")
	connections.remove_at(occupied_index)
	state["connections"] = connections
	return _admit_content_state(_admit_connect(state, {"output_node_id": output_node_id, "output_port_id": output_port_id, "input_node_id": input_node_id, "input_port_id": input_port_id}), &"replace_connection")

## Changes one bounded variant parameter as a reversible content operation.
## Example: `var result: DomainResult = model.change_parameter(&"node_1", 0, 4)`.
func change_parameter(node_id: StringName, parameter_index: int, value: Variant) -> DomainResult:
	if _run_mutation_fenced:
		return _run_mutation_rejected()
	if parameter_index < 0 or not _is_parameter_value(value):
		return GraphDiagnostic.reject(&"invalid_parameter", "Parameter edits require a bounded primitive value and valid index.")
	var state: Dictionary = _accepted_snapshot._state.duplicate(true)
	var node_index: int = _find_node_index(Array(state["nodes"]), node_id)
	if node_index < 0:
		return GraphDiagnostic.reject(&"unknown_node", "The node to edit does not exist.")
	var nodes: Array = Array(state["nodes"])
	var node: Dictionary = nodes[node_index]
	var variant: Dictionary = _find_variant(Dictionary(state["task"]), StringName(node["variant_id"]))
	if parameter_index >= int(variant["parameter_count"]):
		return GraphDiagnostic.reject(&"invalid_parameter", "The parameter index is not declared by this node variant.")
	var parameters: Array = Array(node.get("parameters", []))
	while parameters.size() < int(variant["parameter_count"]):
		parameters.append(null)
	node["parameters"] = parameters
	parameters[parameter_index] = value
	node["parameters"] = parameters
	nodes[node_index] = node
	state["nodes"] = nodes
	return _commit_snapshot(GraphSnapshotType.new(state), &"change_parameter")

## Adds a task-supplied node only during task-load initialization, before any player content commit.
## Example: `var result: DomainResult = model.admit_supplied_node(&"Start", &"start", {"x": 0, "y": 0}, true)`.
func admit_supplied_node(category: StringName, variant_id: StringName, anchor: Dictionary, protected: bool = true) -> DomainResult:
	if _run_mutation_fenced:
		return _run_mutation_rejected()
	if _task_starting_snapshot_finalized:
		return GraphDiagnostic.reject(&"supplied_node_after_finalization", "Task-supplied nodes cannot be loaded after the Task starting graph is finalized.")
	if _player_content_committed:
		return GraphDiagnostic.reject(&"supplied_node_after_edit", "Task-supplied nodes can only be loaded before player edits.")
	var state: Dictionary = _accepted_snapshot._state.duplicate(true)
	var task: Dictionary = state["task"]
	if Array(state["nodes"]).size() >= int(task["node_limit"]):
		return GraphDiagnostic.reject(&"node_limit", "The task node limit has been reached.")
	var variant: Dictionary = _find_variant(task, variant_id)
	if variant.is_empty() or StringName(variant["category"]) != category:
		return GraphDiagnostic.reject(&"variant_not_allowed", "The supplied node variant is not available in this task.")
	var anchor_result: DomainResult = _snap_and_validate_anchor(task, Array(state["nodes"]), &"", anchor.get("x", null), anchor.get("y", null))
	if not anchor_result.is_success():
		return anchor_result
	var nodes: Array = Array(state["nodes"])
	var number: int = state["next_node_number"]
	nodes.append({"node_id": StringName("node_%d" % number), "category": category, "variant_id": variant_id, "anchor": anchor_result.value(), "protected": protected, "parameters": []})
	state["nodes"] = nodes
	state["next_node_number"] = number + 1
	var revision_result: DomainResult = _revision.allocate_next()
	if not revision_result.is_success():
		return revision_result
	_accepted_snapshot = GraphSnapshotType.new(state)
	_task_starting_snapshot = _accepted_snapshot
	_history.clear()
	return DomainResult.success(_accepted_snapshot)

## Replays the newest reversible operation backward and allocates a new revision.
## Example: `var result: DomainResult = model.undo()`.
func undo() -> DomainResult:
	if _run_mutation_fenced:
		return _run_mutation_rejected()
	if not _revision.can_allocate():
		return GraphDiagnostic.reject(&"revision_exhausted", "The session cannot allocate another graph revision.")
	var target_snapshot: GraphSnapshotType = _history.undo_snapshot()
	if target_snapshot == null:
		return GraphDiagnostic.reject(&"undo_unavailable", "There is no graph edit to undo.")
	var revision_result: DomainResult = _revision.allocate_next()
	if not revision_result.is_success():
		return revision_result
	_accepted_snapshot = target_snapshot
	return DomainResult.success(_accepted_snapshot)

## Replays the newest reversible operation forward and allocates a new revision.
## Example: `var result: DomainResult = model.redo()`.
func redo() -> DomainResult:
	if _run_mutation_fenced:
		return _run_mutation_rejected()
	if not _revision.can_allocate():
		return GraphDiagnostic.reject(&"revision_exhausted", "The session cannot allocate another graph revision.")
	var target_snapshot: GraphSnapshotType = _history.redo_snapshot()
	if target_snapshot == null:
		return GraphDiagnostic.reject(&"redo_unavailable", "There is no graph edit to redo.")
	var revision_result: DomainResult = _revision.allocate_next()
	if not revision_result.is_success():
		return revision_result
	_accepted_snapshot = target_snapshot
	return DomainResult.success(_accepted_snapshot)

## Returns the current positive revision identity without exposing report content.
## Example: `var revision_id: int = model.live_revision()`.
func live_revision() -> int:
	return _revision.live_revision()

## Returns the saved recovery revision retained as provenance only.
## Example: `var saved_revision: int = model.saved_provenance_revision()`.
func saved_provenance_revision() -> int:
	return _saved_provenance_revision

## Returns the retained Task-owned Reset snapshot.
## Example: `var starting: GraphSnapshotType = model.task_starting_snapshot()`.
func task_starting_snapshot() -> GraphSnapshotType:
	return _task_starting_snapshot

## Seals the current accepted graph as the Task-owned Reset truth after composition.
## Example: `var result: DomainResult = model.finalize_task_starting_snapshot()`.
func finalize_task_starting_snapshot() -> DomainResult:
	if not _construction_result.is_success():
		return _construction_result
	if _run_mutation_fenced:
		return _run_mutation_rejected()
	if _task_starting_snapshot_finalized:
		return GraphDiagnostic.reject(&"starting_snapshot_finalized", "The Task starting graph has already been finalized.")
	_task_starting_snapshot = _accepted_snapshot
	_task_starting_snapshot_finalized = true
	_player_content_committed = true
	_history.clear()
	return DomainResult.success(_accepted_snapshot)

## Returns the Task-declared slot identities for one variant, or an empty
## array when a legacy Task omits optional parameter IDs.
## Example: `var ids := model.parameter_ids_for_variant(&"parcel.action.turn")`.
func parameter_ids_for_variant(variant_id: StringName) -> Array[StringName]:
	var variant: Dictionary = _find_variant(_accepted_snapshot.task(), variant_id)
	var result: Array[StringName] = []
	for raw_parameter_id: Variant in Array(variant.get("parameter_ids", [])):
		result.append(StringName(raw_parameter_id))
	return result

## Records the identity of the latest readable completed report without changing graph state.
## Example: `var result: DomainResult = model.set_completed_report_revision(12)`.
func set_completed_report_revision(report_revision: int) -> DomainResult:
	if _run_mutation_fenced:
		return _run_mutation_rejected()
	if report_revision <= 0:
		return GraphDiagnostic.reject(&"invalid_report_revision", "A completed report revision must be positive.")
	if report_revision > live_revision():
		return GraphDiagnostic.reject(&"invalid_report_revision", "A completed report revision cannot be newer than the live graph.")
	_completed_report_revision = report_revision
	return DomainResult.success(report_revision)

## Returns report freshness by revision identity: none, fresh, or out_of_date.
## Example: `var freshness: StringName = model.report_freshness()`.
func report_freshness() -> StringName:
	if _completed_report_revision == 0:
		return &"none"
	return &"fresh" if _completed_report_revision == live_revision() else &"out_of_date"

## Returns the retained Undo-entry count without exposing mutable history state.
## Example: `var count: int = model.undo_count()`.
func undo_count() -> int:
	return _history.undo_count()

## Returns the retained Redo-entry count without exposing mutable history state.
## Example: `var count: int = model.redo_count()`.
func redo_count() -> int:
	return _history.redo_count()

## Restores a retained task starting snapshot, clears reversible history, and
## allocates exactly one new revision.
## Example: `var result: DomainResult = model.reset_to_starting_snapshot(starting_snapshot)`.
func reset_to_starting_snapshot(starting_snapshot: GraphSnapshotType) -> DomainResult:
	if _run_mutation_fenced:
		return _run_mutation_rejected()
	if starting_snapshot == null or not is_instance_valid(starting_snapshot):
		return GraphDiagnostic.reject(&"invalid_starting_snapshot", "Reset requires a retained starting graph snapshot.")
	if _task_starting_snapshot == null or not is_instance_valid(_task_starting_snapshot) \
			or starting_snapshot != _task_starting_snapshot:
		return GraphDiagnostic.reject(&"unregistered_starting_snapshot", "Reset requires this model's retained task starting snapshot.")
	if not _revision.can_allocate():
		return GraphDiagnostic.reject(&"revision_exhausted", "The session cannot allocate another graph revision.")
	var revision_result: DomainResult = _revision.allocate_next()
	if not revision_result.is_success():
		return revision_result
	_accepted_snapshot = _task_starting_snapshot
	_history.clear()
	_player_content_committed = true
	return DomainResult.success(_accepted_snapshot)

## Accepts a view-only request without changing graph content, revision, or history.
## Example: `var result: DomainResult = model.apply_view_only(&"frame_all")`.
func apply_view_only(operation: StringName) -> DomainResult:
	if operation.is_empty():
		return GraphDiagnostic.reject(&"invalid_view_operation", "A named view-only operation is required.")
	return DomainResult.success(_accepted_snapshot)

## Cancels a pending connection gesture without changing graph content or history.
## Example: `var result: DomainResult = model.cancel_connection_drag()`.
func cancel_connection_drag() -> DomainResult:
	return DomainResult.success(_accepted_snapshot)

## Cancels a pending parameter gesture without changing graph content or history.
## Example: `var result: DomainResult = model.cancel_parameter_gesture()`.
func cancel_parameter_gesture() -> DomainResult:
	return DomainResult.success(_accepted_snapshot)

func _begin_run_mutation_fence() -> bool:
	if _run_mutation_fenced or not _construction_result.is_success():
		return false
	_run_mutation_fenced = true
	return true

func _end_run_mutation_fence() -> void:
	_run_mutation_fenced = false

func _run_mutation_rejected() -> DomainResult:
	return GraphDiagnostic.reject(
		&"authoring_run_active", "Graph mutation is unavailable while Authoring Run is active.")

func _admit_content_state(candidate: DomainResult, operation: StringName) -> DomainResult:
	if not candidate.is_success():
		return candidate
	return _commit_snapshot(GraphSnapshotType.new(candidate.value()), operation)

func _commit_snapshot(next_snapshot: GraphSnapshotType, operation: StringName) -> DomainResult:
	var revision_result: DomainResult = _revision.allocate_next()
	if not revision_result.is_success():
		return revision_result
	_history.commit(_accepted_snapshot, next_snapshot)
	_accepted_snapshot = next_snapshot
	_player_content_committed = true
	return DomainResult.success(next_snapshot)

func _replace_recovery_graph(saved_graph: Dictionary, task_starting_graph: Dictionary, saved_revision: int) -> DomainResult:
	if not _is_recovery_graph_shape(saved_graph) or not _is_recovery_graph_shape(task_starting_graph):
		return GraphDiagnostic.reject(&"recovery_graph_invalid", "Saved and Task starting graphs require nodes and connections arrays.")
	var task_value: Dictionary = _accepted_snapshot.task()
	var saved_shape_result: DomainResult = _validate_saved_recovery_graph_shape(saved_graph, task_value)
	if not saved_shape_result.is_success():
		return saved_shape_result
	var saved_result: DomainResult = _normalize_recovery_graph(saved_graph, task_value, false)
	if not saved_result.is_success():
		return saved_result
	var starting_result: DomainResult = _normalize_recovery_graph(task_starting_graph, task_value, true)
	if not starting_result.is_success():
		return starting_result
	_accepted_snapshot = GraphSnapshotType.new(saved_result.value())
	_task_starting_snapshot = GraphSnapshotType.new(starting_result.value())
	_task_starting_snapshot_finalized = true
	_history = GraphHistoryType.new()
	_saved_provenance_revision = saved_revision
	return DomainResult.success(_accepted_snapshot)

## Saved projections are exact GraphSnapshot records. Task starting graphs use
## a distinct installed-authority normalization path and are intentionally not
## validated here.
func _validate_saved_recovery_graph_shape(graph: Dictionary, task: Dictionary) -> DomainResult:
	if not _has_exact_recovery_keys(graph, ["nodes", "connections"]):
		return GraphDiagnostic.reject(&"recovery_graph_invalid", "Saved graph projections contain unknown or missing fields.")
	for raw_node: Variant in Array(graph["nodes"]):
		if typeof(raw_node) != TYPE_DICTIONARY:
			return GraphDiagnostic.reject(&"recovery_graph_invalid", "Saved graph nodes must be dictionaries.")
		var node: Dictionary = Dictionary(raw_node)
		if not _has_exact_recovery_keys(node, ["node_id", "category", "variant_id", "anchor", "protected", "parameters"]):
			return GraphDiagnostic.reject(&"recovery_graph_invalid", "Saved graph nodes contain unknown or missing fields.")
		if typeof(node["anchor"]) != TYPE_DICTIONARY or not _has_exact_recovery_keys(Dictionary(node["anchor"]), ["x", "y"]):
			return GraphDiagnostic.reject(&"recovery_graph_invalid", "Saved graph anchors require exactly x and y.")
		if typeof(node["parameters"]) != TYPE_ARRAY:
			return GraphDiagnostic.reject(&"recovery_graph_invalid", "Saved graph parameters must be ordered arrays.")
		if not _recovery_id(node["variant_id"]):
			return GraphDiagnostic.reject(&"recovery_graph_invalid", "Saved graph variants require stable identities.")
		var variant: Dictionary = _find_variant(task, StringName(node["variant_id"]))
		if variant.is_empty() or StringName(variant["category"]) != StringName(node["category"]):
			return GraphDiagnostic.reject(&"variant_not_allowed", "Saved graph nodes must use an installed Task variant.")
		if Array(node["parameters"]).size() != int(variant["parameter_count"]):
			return GraphDiagnostic.reject(&"invalid_parameter", "Saved graph parameter cardinality must match its Task variant.")
	for raw_connection: Variant in Array(graph["connections"]):
		if typeof(raw_connection) != TYPE_DICTIONARY or not _has_exact_recovery_keys(Dictionary(raw_connection), ["connection_id", "output_node_id", "output_port_id", "input_node_id", "input_port_id"]):
			return GraphDiagnostic.reject(&"recovery_graph_invalid", "Saved graph connections contain unknown or missing fields.")
	return DomainResult.success(null)

func _has_exact_recovery_keys(value: Dictionary, required_keys: Array[String]) -> bool:
	if value.size() != required_keys.size():
		return false
	for key: String in required_keys:
		if not value.has(key):
			return false
	return true

## Normalizes Task source aliases and saved GraphSnapshot records into one
## admitted immutable state without allocating a player-visible revision.
func _normalize_recovery_graph(graph: Dictionary, task: Dictionary, task_starting: bool) -> DomainResult:
	var state: Dictionary = {"task": task.duplicate(true), "nodes": [], "connections": [], "next_node_number": 1, "next_connection_number": 1}
	var nodes_result: DomainResult = _normalize_recovery_nodes(Array(graph["nodes"]), state, task_starting)
	if not nodes_result.is_success():
		return nodes_result
	state = nodes_result.value()
	var connections_result: DomainResult = _normalize_recovery_connections(Array(graph["connections"]), state, task_starting)
	if not connections_result.is_success():
		return connections_result
	state = connections_result.value()
	state["next_node_number"] = _next_recovery_number(Array(state["nodes"]), "node_id", "node_")
	state["next_connection_number"] = _next_recovery_number(Array(state["connections"]), "connection_id", "connection_")
	return DomainResult.success(state)

func _normalize_recovery_nodes(raw_nodes: Array, initial_state: Dictionary, task_starting: bool) -> DomainResult:
	var state: Dictionary = initial_state
	var node_ids: Dictionary[StringName, bool] = {}
	for raw_node: Variant in raw_nodes:
		if Array(state["nodes"]).size() >= int(Dictionary(state["task"])["node_limit"]):
			return GraphDiagnostic.reject(&"node_limit", "The task node limit has been reached.")
		var node_result: DomainResult = _normalize_recovery_node(raw_node, state, task_starting)
		if not node_result.is_success():
			return node_result
		var node: Dictionary = node_result.value()
		var node_id: StringName = node["node_id"]
		if node_ids.has(node_id):
			return GraphDiagnostic.reject(&"recovery_graph_invalid", "Recovered node identities must be unique.")
		node_ids[node_id] = true
		var admitted_nodes: Array = Array(state["nodes"])
		admitted_nodes.append(node)
		state["nodes"] = admitted_nodes
	return DomainResult.success(state)

func _normalize_recovery_connections(raw_connections: Array, initial_state: Dictionary, task_starting: bool) -> DomainResult:
	var state: Dictionary = initial_state
	var connection_ids: Dictionary[StringName, bool] = {}
	for raw_connection: Variant in raw_connections:
		if typeof(raw_connection) != TYPE_DICTIONARY:
			return GraphDiagnostic.reject(&"recovery_graph_invalid", "Recovered connections must be dictionaries.")
		var source: Dictionary = raw_connection
		var connection_id: Variant = source.get("connection_id", null)
		var output_node_id: Variant = source.get("output_node_id", source.get("source_node_id", null))
		var output_port_id: Variant = source.get("output_port_id", source.get("source_port_id", null))
		var input_node_id: Variant = source.get("input_node_id", source.get("target_node_id", null))
		var input_port_id: Variant = source.get("input_port_id", source.get("target_port_id", null))
		if not _recovery_id(connection_id) or not _recovery_id(output_node_id) or not _recovery_id(output_port_id) \
				or not _recovery_id(input_node_id) or not _recovery_id(input_port_id):
			return GraphDiagnostic.reject(&"recovery_graph_invalid", "Recovered connection identities must be non-empty strings.")
		var recovered_connection_id: StringName = StringName(connection_id)
		if connection_ids.has(recovered_connection_id):
			return GraphDiagnostic.reject(&"recovery_graph_invalid", "Recovered connection identities must be unique.")
		if task_starting and StringName(output_port_id) == &"value":
			var output_node: Dictionary = _find_node(Array(state["nodes"]), StringName(output_node_id))
			if not output_node.is_empty() and StringName(output_node["category"]) == &"Compare":
				output_port_id = &"result"
		var admitted: DomainResult = _admit_connect(state, {
			"output_node_id": StringName(output_node_id), "output_port_id": StringName(output_port_id),
			"input_node_id": StringName(input_node_id), "input_port_id": StringName(input_port_id),
		})
		if not admitted.is_success():
			return admitted
		state = admitted.value()
		var connections: Array = Array(state["connections"])
		var connection: Dictionary = connections[connections.size() - 1]
		connection["connection_id"] = recovered_connection_id
		connections[connections.size() - 1] = connection
		state["connections"] = connections
		connection_ids[recovered_connection_id] = true
	return DomainResult.success(state)

func _normalize_recovery_node(raw_node: Variant, state: Dictionary, task_starting: bool) -> DomainResult:
	if typeof(raw_node) != TYPE_DICTIONARY:
		return GraphDiagnostic.reject(&"recovery_graph_invalid", "Recovered nodes must be dictionaries.")
	var source: Dictionary = raw_node
	var node_id: Variant = source.get("node_id", null)
	var category: Variant = source.get("category", null)
	var variant_id: Variant = source.get("variant_id", null)
	if not _recovery_id(node_id) or not _recovery_id(category) or not _recovery_id(variant_id):
		return GraphDiagnostic.reject(&"recovery_graph_invalid", "Recovered nodes require stable identity, category, and variant fields.")
	var variant: Dictionary = _find_variant(Dictionary(state["task"]), StringName(variant_id))
	if variant.is_empty() or StringName(variant["category"]) != StringName(category):
		return GraphDiagnostic.reject(&"variant_not_allowed", "Recovered nodes must use an installed Task variant.")
	var task_value: Dictionary = Dictionary(state["task"])
	var origin: Dictionary = Dictionary(task_value["grid_origin"])
	var generated_x: int = int(origin["x"]) + Array(state["nodes"]).size() * int(task_value["grid_size"])
	if not task_starting and not source.has("anchor"):
		return GraphDiagnostic.reject(&"recovery_graph_invalid", "Saved recovered nodes require explicit anchors.")
	var raw_anchor: Variant = source.get("anchor", {"x": generated_x, "y": int(origin["y"])})
	if typeof(raw_anchor) != TYPE_DICTIONARY:
		return GraphDiagnostic.reject(&"invalid_anchor", "Recovered node anchors must be dictionaries.")
	var anchor: Dictionary = Dictionary(raw_anchor)
	var anchor_result: DomainResult = _snap_and_validate_anchor(Dictionary(state["task"]), Array(state["nodes"]), &"", anchor.get("x", null), anchor.get("y", null))
	if not anchor_result.is_success():
		return anchor_result
	var parameters_result: DomainResult = _normalize_recovery_parameters(source, int(variant["parameter_count"]))
	if not parameters_result.is_success():
		return parameters_result
	# Installed coursework Tasks declare their starting nodes as deletable. A
	# future Task can still opt one node out by carrying an explicit protected
	# flag in its starting graph.
	var protected: Variant = source.get("protected", false)
	if typeof(protected) != TYPE_BOOL:
		return GraphDiagnostic.reject(&"recovery_graph_invalid", "Recovered node protection must be Boolean.")
	return DomainResult.success({
		"node_id": StringName(node_id), "category": StringName(category), "variant_id": StringName(variant_id),
		"anchor": anchor_result.value(), "protected": bool(protected), "parameters": parameters_result.value(),
	})

func _normalize_recovery_parameters(node: Dictionary, parameter_count: int) -> DomainResult:
	var source: Variant = node.get("parameters", node.get("parameter_values", []))
	var values: Array = []
	if typeof(source) == TYPE_ARRAY:
		values = Array(source).duplicate(true)
	elif typeof(source) == TYPE_DICTIONARY:
		if parameter_count == 0:
			return DomainResult.success(values)
		var parameter_ids: Array[String] = []
		for raw_id: Variant in Dictionary(source).keys():
			if typeof(raw_id) != TYPE_STRING:
				return GraphDiagnostic.reject(&"recovery_graph_invalid", "Recovered parameter identities must be strings.")
			parameter_ids.append(String(raw_id))
		parameter_ids.sort()
		for parameter_id: String in parameter_ids:
			values.append(Dictionary(source)[parameter_id])
	else:
		return GraphDiagnostic.reject(&"recovery_graph_invalid", "Recovered parameters must be an array or dictionary.")
	if values.size() != parameter_count:
		return GraphDiagnostic.reject(&"invalid_parameter", "Recovered parameter cardinality must match its Task variant.")
	for index: int in range(values.size()):
		var value: Variant = values[index]
		if typeof(value) == TYPE_STRING:
			values[index] = StringName(value)
			value = values[index]
		if not _is_parameter_value(value):
			return GraphDiagnostic.reject(&"invalid_parameter", "Recovered parameter values are outside the admitted primitive domain.")
	return DomainResult.success(values)

static func _recovery_id(value: Variant) -> bool:
	return (typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME) and not StringName(value).is_empty()

static func _next_recovery_number(records: Array, field: String, prefix: String) -> int:
	var next_number: int = 1
	var seen: Dictionary[StringName, bool] = {}
	for raw_record: Variant in records:
		var record: Dictionary = raw_record
		var identifier: StringName = StringName(record[field])
		seen[identifier] = true
		var suffix: String = String(identifier).trim_prefix(prefix)
		if String(identifier).begins_with(prefix) and suffix.is_valid_int():
			next_number = maxi(next_number, int(suffix) + 1)
	while seen.has(StringName("%s%d" % [prefix, next_number])):
		next_number += 1
	return next_number

static func _is_recovery_graph_shape(value: Dictionary) -> bool:
	return value.has("nodes") and value.has("connections") \
		and typeof(value["nodes"]) == TYPE_ARRAY and typeof(value["connections"]) == TYPE_ARRAY

static func _is_parameter_value(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL or typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_STRING_NAME

static func _reduce_snapshot(accepted_snapshot: GraphSnapshotType, command: Variant) -> DomainResult:
	if typeof(command) != TYPE_OBJECT or not command is GraphCommandType or not is_instance_valid(command):
		return GraphDiagnostic.reject(&"invalid_command", "A graph command is required.")
	var payload_result := _validate_command_payload(command)
	if not payload_result.is_success():
		return payload_result
	var state: Dictionary = accepted_snapshot._state.duplicate(true)
	var candidate: DomainResult
	match command.kind():
		GraphCommandType.Kind.CREATE_NODE:
			candidate = _admit_create(state, command.payload())
		GraphCommandType.Kind.MOVE_NODE:
			candidate = _admit_move(state, command.payload())
		GraphCommandType.Kind.DELETE_NODE:
			candidate = _admit_delete(state, command.payload())
		GraphCommandType.Kind.CONNECT:
			candidate = _admit_connect(state, command.payload())
		_:
			return GraphDiagnostic.reject(&"invalid_command", "The graph command kind is not supported.")
	if not candidate.is_success():
		return candidate
	return DomainResult.success(GraphSnapshotType.new(candidate.value()))

## Returns the fixed coursework language registry in stable order.
## Example: `var categories: Array[StringName] = GraphModel.required_categories()`.
static func required_categories() -> Array[StringName]:
	return REQUIRED_CATEGORIES.duplicate()

static func _validate_task(task: Dictionary) -> DomainResult:
	var required_keys: Array[String] = ["grid_size", "grid_origin", "bounds", "node_limit", "connection_limit", "variants"]
	for key: String in required_keys:
		if not task.has(key):
			return GraphDiagnostic.reject(&"invalid_task", "Task metadata is missing %s." % key)
	var grid_size: Variant = task["grid_size"]
	if typeof(grid_size) != TYPE_INT or int(grid_size) < MIN_GRID_SIZE or int(grid_size) > MAX_GRID_SIZE:
		return GraphDiagnostic.reject(&"invalid_grid_size", "Task grid size must be between 8 and 32.")
	var origin_result := _validated_anchor(task["grid_origin"], "Task grid origin")
	if not origin_result.is_success():
		return origin_result
	var bounds_result := _validate_bounds(task["bounds"], int(grid_size), origin_result.value())
	if not bounds_result.is_success():
		return bounds_result
	var node_limit: Variant = task["node_limit"]
	if typeof(node_limit) != TYPE_INT or int(node_limit) < MIN_NODE_LIMIT or int(node_limit) > MAX_NODE_LIMIT:
		return GraphDiagnostic.reject(&"invalid_node_limit", "Task node limit must be between 4 and 24.")
	var connection_limit: Variant = task["connection_limit"]
	if typeof(connection_limit) != TYPE_INT or int(connection_limit) < 0 or int(connection_limit) > MAX_CONNECTION_LIMIT:
		return GraphDiagnostic.reject(&"invalid_connection_limit", "Task connection limit must be between 0 and 96.")
	if typeof(task["variants"]) != TYPE_ARRAY:
		return GraphDiagnostic.reject(&"invalid_variants", "Task variants must be an array.")
	var variants_result := _validate_variants(Array(task["variants"]))
	if not variants_result.is_success():
		return variants_result
	return DomainResult.success({
		"grid_size": int(grid_size),
		"grid_origin": origin_result.value(),
		"bounds": bounds_result.value(),
		"node_limit": int(node_limit),
		"connection_limit": int(connection_limit),
		"variants": variants_result.value(),
	})

static func _validate_bounds(raw_bounds: Variant, grid_size: int, origin: Dictionary) -> DomainResult:
	if typeof(raw_bounds) != TYPE_DICTIONARY:
		return GraphDiagnostic.reject(&"invalid_bounds", "Task canvas bounds must be a dictionary.")
	var bounds: Dictionary = raw_bounds
	var keys: Array[String] = ["min_x", "max_x", "min_y", "max_y"]
	for key: String in keys:
		if not bounds.has(key) or typeof(bounds[key]) != TYPE_INT:
			return GraphDiagnostic.reject(&"invalid_bounds", "Task canvas bounds require integer %s." % key)
	var min_x: int = bounds["min_x"]
	var max_x: int = bounds["max_x"]
	var min_y: int = bounds["min_y"]
	var max_y: int = bounds["max_y"]
	if not _is_exact_integer(min_x) or not _is_exact_integer(max_x) or not _is_exact_integer(min_y) or not _is_exact_integer(max_y):
		return GraphDiagnostic.reject(&"invalid_bounds", "Task canvas bounds must use exactly representable integers.")
	if min_x > max_x or min_y > max_y or max_x - min_x > MAX_CANVAS_SPAN or max_y - min_y > MAX_CANVAS_SPAN:
		return GraphDiagnostic.reject(&"invalid_bounds", "Task canvas bounds must be finite, ordered, and at most 4096 units per axis.")
	for axis: String in ["x", "y"]:
		var minimum: int = min_x if axis == "x" else min_y
		var maximum: int = max_x if axis == "x" else max_y
		var axis_origin: int = int(origin[axis])
		if posmod(minimum - axis_origin, grid_size) != 0 or posmod(maximum - axis_origin, grid_size) != 0:
			return GraphDiagnostic.reject(&"invalid_bounds", "Task canvas bounds must align to the task grid.")
	return DomainResult.success({"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y})

static func _validate_variants(raw_variants: Array) -> DomainResult:
	if raw_variants.size() > MAX_REGISTERED_VARIANTS:
		return GraphDiagnostic.reject(&"registered_variant_limit", "A task can register at most 32 variants.")
	var variant_ids: Dictionary = {}
	var normalized: Array[Dictionary] = []
	var creatable_count: int = 0
	for raw_variant: Variant in raw_variants:
		if typeof(raw_variant) != TYPE_DICTIONARY:
			return GraphDiagnostic.reject(&"invalid_variant", "Every task variant must be a dictionary.")
		var variant: Dictionary = raw_variant
		for key: String in ["id", "category", "creatable", "ports", "parameter_count"]:
			if not variant.has(key):
				return GraphDiagnostic.reject(&"invalid_variant", "Task variant metadata is missing %s." % key)
		if typeof(variant["id"]) != TYPE_STRING_NAME or typeof(variant["category"]) != TYPE_STRING_NAME:
			return GraphDiagnostic.reject(&"invalid_variant", "Variant id and category must be StringName values.")
		var id: StringName = variant["id"]
		var category: StringName = variant["category"]
		if id.is_empty() or variant_ids.has(id):
			return GraphDiagnostic.reject(&"invalid_variant", "Task variant ids must be unique and non-empty.")
		if not REQUIRED_CATEGORIES.has(category):
			return GraphDiagnostic.reject(&"invalid_category", "A task cannot introduce an unknown node category.")
		if typeof(variant["creatable"]) != TYPE_BOOL or typeof(variant["parameter_count"]) != TYPE_INT or int(variant["parameter_count"]) < 0 or int(variant["parameter_count"]) > MAX_PARAMETERS_PER_VARIANT:
			return GraphDiagnostic.reject(&"invalid_variant", "Variant creatable state and parameter count are invalid.")
		if bool(variant["creatable"]):
			creatable_count += 1
		if creatable_count > MAX_CREATABLE_VARIANTS:
			return GraphDiagnostic.reject(&"creatable_variant_limit", "A task can expose at most 16 creatable variants.")
		if typeof(variant["ports"]) != TYPE_ARRAY:
			return GraphDiagnostic.reject(&"invalid_ports", "Variant ports must be an array.")
		var ports_result := _validate_ports(Array(variant["ports"]), category)
		if not ports_result.is_success():
			return ports_result
		variant_ids[id] = true
		var parameter_ids_result: DomainResult = _normalize_parameter_ids(variant, int(variant["parameter_count"]))
		if not parameter_ids_result.is_success():
			return parameter_ids_result
		var normalized_variant: Dictionary = {"id": id, "category": category, "creatable": bool(variant["creatable"]), "ports": ports_result.value(), "parameter_count": int(variant["parameter_count"])}
		var parameter_ids: Array[StringName] = parameter_ids_result.value()
		if not parameter_ids.is_empty():
			normalized_variant["parameter_ids"] = parameter_ids
		if variant.has("default_parameters"):
			var defaults: Variant = variant["default_parameters"]
			if typeof(defaults) != TYPE_ARRAY or Array(defaults).size() != int(variant["parameter_count"]):
				return GraphDiagnostic.reject(&"invalid_variant", "Variant default parameters must match parameter_count.")
			for value: Variant in Array(defaults):
				if not _is_parameter_value(value):
					return GraphDiagnostic.reject(&"invalid_variant", "Variant default parameters must be bounded primitive values.")
			normalized_variant["default_parameters"] = Array(defaults).duplicate()
		normalized.append(normalized_variant)
	return DomainResult.success(normalized)

static func _normalize_parameter_ids(variant: Dictionary, parameter_count: int) -> DomainResult:
	if not variant.has("parameter_ids"):
		var empty_parameter_ids: Array[StringName] = []
		return DomainResult.success(empty_parameter_ids)
	if typeof(variant["parameter_ids"]) != TYPE_ARRAY:
		return GraphDiagnostic.reject(&"invalid_parameter_ids", "Task parameter IDs must be an array when declared.")
	var raw_ids: Array = Array(variant["parameter_ids"])
	if raw_ids.size() != parameter_count:
		return GraphDiagnostic.reject(&"invalid_parameter_ids", "Task parameter IDs must match the declared parameter count.")
	var seen: Dictionary = {}
	var normalized: Array[StringName] = []
	for raw_id: Variant in raw_ids:
		if typeof(raw_id) != TYPE_STRING_NAME or StringName(raw_id).is_empty() or seen.has(raw_id):
			return GraphDiagnostic.reject(&"invalid_parameter_ids", "Task parameter IDs must be unique non-empty StringName values.")
		seen[raw_id] = true
		normalized.append(raw_id)
	return DomainResult.success(normalized)

static func _validate_ports(raw_ports: Array, category: StringName) -> DomainResult:
	if raw_ports.size() > MAX_PORTS_PER_VARIANT:
		return GraphDiagnostic.reject(&"port_limit", "A variant can define at most 8 ports.")
	var port_ids: Dictionary = {}
	var normalized: Array[Dictionary] = []
	for raw_port: Variant in raw_ports:
		if typeof(raw_port) != TYPE_DICTIONARY:
			return GraphDiagnostic.reject(&"invalid_port", "Every port must be a dictionary.")
		var port: Dictionary = raw_port
		for key: String in ["id", "direction", "kind"]:
			if not port.has(key):
				return GraphDiagnostic.reject(&"invalid_port", "Port metadata is missing %s." % key)
		if typeof(port["id"]) != TYPE_STRING_NAME or typeof(port["direction"]) != TYPE_STRING_NAME or typeof(port["kind"]) != TYPE_STRING_NAME:
			return GraphDiagnostic.reject(&"invalid_port", "Port id, direction, and kind must be StringName values.")
		var id: StringName = port["id"]
		var direction: StringName = port["direction"]
		var kind: StringName = port["kind"]
		if id.is_empty() or port_ids.has(id) or not [&"input", &"output"].has(direction) or not [&"execution", &"data"].has(kind):
			return GraphDiagnostic.reject(&"invalid_port", "Port id, direction, or kind is invalid.")
		if port.has("data_type") and typeof(port["data_type"]) != TYPE_STRING_NAME:
			return GraphDiagnostic.reject(&"invalid_port", "Port data type must be a StringName value.")
		var data_type: StringName = port.get("data_type", &"")
		if kind == &"data" and not [&"Boolean", &"numeric", &"label"].has(data_type):
			return GraphDiagnostic.reject(&"invalid_port", "Data ports require Boolean, numeric, or label type.")
		if kind == &"execution" and not data_type.is_empty():
			return GraphDiagnostic.reject(&"invalid_port", "Execution ports cannot declare a data type.")
		if port.has("multiple_execution_sources") and typeof(port["multiple_execution_sources"]) != TYPE_BOOL:
			return GraphDiagnostic.reject(&"invalid_port", "Multiple execution sources must be a bool value.")
		var multiple_sources: bool = port.get("multiple_execution_sources", false)
		if multiple_sources and not (category == &"Repeat" and id == &"continue" and direction == &"input" and kind == &"execution"):
			return GraphDiagnostic.reject(&"invalid_port", "Only Repeat.continue may accept multiple execution sources.")
		port_ids[id] = true
		normalized.append({"id": id, "direction": direction, "kind": kind, "data_type": data_type, "multiple_execution_sources": multiple_sources})
	return DomainResult.success(normalized)

static func _admit_create(state: Dictionary, payload: Dictionary) -> DomainResult:
	var task: Dictionary = state["task"]
	if Array(state["nodes"]).size() >= int(task["node_limit"]):
		return GraphDiagnostic.reject(&"node_limit", "The task node limit has been reached.")
	var category: StringName = payload["category"]
	var variant_id: StringName = payload["variant_id"]
	var variant := _find_variant(task, variant_id)
	if variant.is_empty() or StringName(variant["category"]) != category or not bool(variant["creatable"]):
		return GraphDiagnostic.reject(&"variant_not_allowed", "This category or variant is not allowed by the loaded task.")
	var raw_anchor: Dictionary = payload["anchor"]
	var anchor_result := _snap_and_validate_anchor(task, Array(state["nodes"]), &"", raw_anchor["x"], raw_anchor["y"])
	if not anchor_result.is_success():
		return anchor_result
	var number: int = state["next_node_number"]
	var nodes: Array = Array(state["nodes"])
	var created_node: Dictionary = {"node_id": StringName("node_%d" % number), "category": category, "variant_id": variant_id, "anchor": anchor_result.value(), "protected": false}
	if variant.has("default_parameters"):
		created_node["parameters"] = Array(variant["default_parameters"]).duplicate()
	nodes.append(created_node)
	state["nodes"] = nodes
	state["next_node_number"] = number + 1
	return DomainResult.success(state)

static func _admit_move(state: Dictionary, payload: Dictionary) -> DomainResult:
	var node_id: StringName = payload["node_id"]
	var node_index := _find_node_index(Array(state["nodes"]), node_id)
	if node_index < 0:
		return GraphDiagnostic.reject(&"unknown_node", "The node to move does not exist.")
	var task: Dictionary = state["task"]
	var anchor_result := _snap_and_validate_anchor(task, Array(state["nodes"]), node_id, payload["released_x"], payload["released_y"])
	if not anchor_result.is_success():
		return anchor_result
	var nodes: Array = Array(state["nodes"])
	var moved: Dictionary = nodes[node_index]
	moved["anchor"] = anchor_result.value()
	nodes[node_index] = moved
	state["nodes"] = nodes
	return DomainResult.success(state)

static func _admit_delete(state: Dictionary, payload: Dictionary) -> DomainResult:
	var node_id: StringName = payload["node_id"]
	var node_index := _find_node_index(Array(state["nodes"]), node_id)
	if node_index < 0:
		return GraphDiagnostic.reject(&"unknown_node", "The node to delete does not exist.")
	var nodes: Array = Array(state["nodes"])
	var node: Dictionary = nodes[node_index]
	if bool(node.get("protected", false)):
		return GraphDiagnostic.reject(&"protected_node", "The supplied node is protected and cannot be deleted.")
	nodes.remove_at(node_index)
	var connections: Array = []
	for raw_connection: Variant in Array(state["connections"]):
		var connection: Dictionary = raw_connection
		if StringName(connection["output_node_id"]) != node_id and StringName(connection["input_node_id"]) != node_id:
			connections.append(connection)
	state["nodes"] = nodes
	state["connections"] = connections
	return DomainResult.success(state)

static func _admit_connect(state: Dictionary, payload: Dictionary) -> DomainResult:
	var output_node_id: StringName = payload["output_node_id"]
	var input_node_id: StringName = payload["input_node_id"]
	var output_node := _find_node(Array(state["nodes"]), output_node_id)
	var input_node := _find_node(Array(state["nodes"]), input_node_id)
	if output_node.is_empty() or input_node.is_empty():
		return GraphDiagnostic.reject(&"unknown_node", "Both connection nodes must exist.")
	var task: Dictionary = state["task"]
	var output_port_id: StringName = payload["output_port_id"]
	var input_port_id: StringName = payload["input_port_id"]
	var output_port := _find_port(_find_variant(task, StringName(output_node["variant_id"])), output_port_id)
	var input_port := _find_port(_find_variant(task, StringName(input_node["variant_id"])), input_port_id)
	if output_port.is_empty() or input_port.is_empty():
		return GraphDiagnostic.reject(&"unknown_port", "Both connection ports must exist.")
	if StringName(output_port["direction"]) != &"output" or StringName(input_port["direction"]) != &"input":
		return GraphDiagnostic.reject(&"direction_mismatch", "Connections must run from an output port to an input port.")
	if StringName(output_port["kind"]) != StringName(input_port["kind"]):
		return GraphDiagnostic.reject(&"kind_mismatch", "Execution ports cannot connect to data ports.")
	if StringName(output_port["kind"]) == &"data" and StringName(output_port["data_type"]) != StringName(input_port["data_type"]):
		return GraphDiagnostic.reject(&"data_type_mismatch", "Data ports must use the same data type.")
	var connections: Array = Array(state["connections"])
	for raw_connection: Variant in connections:
		var connection: Dictionary = raw_connection
		if StringName(connection["output_node_id"]) == output_node_id and StringName(connection["output_port_id"]) == StringName(output_port["id"]) and StringName(connection["input_node_id"]) == input_node_id and StringName(connection["input_port_id"]) == StringName(input_port["id"]):
			return GraphDiagnostic.reject(&"duplicate_connection", "This connection already exists.")
	if connections.size() >= int(task["connection_limit"]):
		return GraphDiagnostic.reject(&"connection_limit", "The task connection limit has been reached.")
	if _input_is_occupied(connections, input_node_id, input_port):
		return GraphDiagnostic.reject(&"input_occupied", "This input port already has a connection.")
	if _execution_output_is_occupied(connections, output_node_id, output_port):
		return GraphDiagnostic.reject(&"cardinality_exceeded", "This port has reached its connection cardinality.")
	var number: int = state["next_connection_number"]
	connections.append({"connection_id": StringName("connection_%d" % number), "output_node_id": output_node_id, "output_port_id": StringName(output_port["id"]), "input_node_id": input_node_id, "input_port_id": StringName(input_port["id"])})
	state["connections"] = connections
	state["next_connection_number"] = number + 1
	return DomainResult.success(state)

static func _input_is_occupied(connections: Array, input_node_id: StringName, input_port: Dictionary) -> bool:
	if bool(input_port["multiple_execution_sources"]):
		return false
	for raw_connection: Variant in connections:
		var connection: Dictionary = raw_connection
		if StringName(connection["input_node_id"]) == input_node_id and StringName(connection["input_port_id"]) == StringName(input_port["id"]):
			return true
	return false

static func _execution_output_is_occupied(connections: Array, output_node_id: StringName, output_port: Dictionary) -> bool:
	if StringName(output_port["kind"]) != &"execution":
		return false
	for raw_connection: Variant in connections:
		var connection: Dictionary = raw_connection
		if StringName(connection["output_node_id"]) == output_node_id and StringName(connection["output_port_id"]) == StringName(output_port["id"]):
			return true
	return false

static func _snap_and_validate_anchor(task: Dictionary, nodes: Array, moving_node_id: StringName, released_x: Variant, released_y: Variant) -> DomainResult:
	var origin: Dictionary = task["grid_origin"]
	var grid_size: int = task["grid_size"]
	var delta_x_result := _released_grid_delta(released_x, int(origin["x"]), "x")
	var delta_y_result := _released_grid_delta(released_y, int(origin["y"]), "y")
	if not delta_x_result.is_success() or not delta_y_result.is_success():
		return delta_x_result if not delta_x_result.is_success() else delta_y_result
	var snapped_x: float = float(origin["x"]) + grid_size * _half_away(float(delta_x_result.value()) / grid_size)
	var snapped_y: float = float(origin["y"]) + grid_size * _half_away(float(delta_y_result.value()) / grid_size)
	if not is_finite(snapped_x) or not is_finite(snapped_y) or abs(snapped_x) > MAX_EXACT_INTEGER_FLOAT or abs(snapped_y) > MAX_EXACT_INTEGER_FLOAT:
		return GraphDiagnostic.reject(&"non_representable_anchor", "The snapped anchor cannot be represented.")
	return _validate_legal_free_anchor(task, nodes, {"x": int(snapped_x), "y": int(snapped_y)}, moving_node_id)

static func _half_away(value: float) -> float:
	if value < 0.0:
		return -floor(abs(value) + 0.5)
	if value > 0.0:
		return floor(abs(value) + 0.5)
	return 0.0

static func _validate_legal_free_anchor(task: Dictionary, nodes: Array, raw_anchor: Variant, ignored_node_id: StringName) -> DomainResult:
	var anchor_result := _validated_anchor(raw_anchor, "Anchor")
	if not anchor_result.is_success():
		return anchor_result
	var anchor: Dictionary = anchor_result.value()
	var bounds: Dictionary = task["bounds"]
	var origin: Dictionary = task["grid_origin"]
	var grid_size: int = task["grid_size"]
	if int(anchor["x"]) < int(bounds["min_x"]) or int(anchor["x"]) > int(bounds["max_x"]) or int(anchor["y"]) < int(bounds["min_y"]) or int(anchor["y"]) > int(bounds["max_y"]):
		return GraphDiagnostic.reject(&"out_of_bounds", "The grid anchor lies outside the task canvas bounds.")
	if posmod(int(anchor["x"]) - int(origin["x"]), grid_size) != 0 or posmod(int(anchor["y"]) - int(origin["y"]), grid_size) != 0:
		return GraphDiagnostic.reject(&"invalid_anchor", "The anchor must align to the task grid.")
	for raw_node: Variant in nodes:
		var node: Dictionary = raw_node
		if StringName(node["node_id"]) != ignored_node_id and Dictionary(node["anchor"]) == anchor:
			return GraphDiagnostic.reject(&"occupied_anchor", "The grid anchor is already occupied.")
	return DomainResult.success(anchor)

static func _validated_anchor(raw_anchor: Variant, label: String) -> DomainResult:
	if typeof(raw_anchor) != TYPE_DICTIONARY:
		return GraphDiagnostic.reject(&"invalid_anchor", "%s must be an integer x/y dictionary." % label)
	var anchor: Dictionary = raw_anchor
	if not anchor.has("x") or not anchor.has("y") or typeof(anchor["x"]) != TYPE_INT or typeof(anchor["y"]) != TYPE_INT:
		return GraphDiagnostic.reject(&"invalid_anchor", "%s must contain integer x and y values." % label)
	var x: int = anchor["x"]
	var y: int = anchor["y"]
	if not _is_exact_integer(x) or not _is_exact_integer(y):
		return GraphDiagnostic.reject(&"non_representable_anchor", "%s must use exactly representable integers." % label)
	return DomainResult.success({"x": x, "y": y})

static func _validate_command_payload(command: GraphCommandType) -> DomainResult:
	var payload: Dictionary = command.payload()
	match command.kind():
		GraphCommandType.Kind.CREATE_NODE:
			if not _has_string_names(payload, ["category", "variant_id"]) or not payload.has("anchor") or typeof(payload["anchor"]) != TYPE_DICTIONARY:
				return GraphDiagnostic.reject(&"invalid_command", "Create commands require StringName category, variant, and dictionary anchor.")
			var anchor: Dictionary = payload["anchor"]
			if not anchor.has("x") or not anchor.has("y") or not _is_release_coordinate(anchor["x"]) or not _is_release_coordinate(anchor["y"]):
				return GraphDiagnostic.reject(&"invalid_command", "Create command anchors require finite numeric x and y values.")
		GraphCommandType.Kind.MOVE_NODE:
			if not _has_string_names(payload, ["node_id"]) or not payload.has("released_x") or not payload.has("released_y"):
				return GraphDiagnostic.reject(&"invalid_command", "Move commands require a StringName node id and released coordinates.")
		GraphCommandType.Kind.DELETE_NODE:
			if not _has_string_names(payload, ["node_id"]):
				return GraphDiagnostic.reject(&"invalid_command", "Delete commands require a StringName node id.")
		GraphCommandType.Kind.CONNECT:
			if not _has_string_names(payload, ["output_node_id", "output_port_id", "input_node_id", "input_port_id"]):
				return GraphDiagnostic.reject(&"invalid_command", "Connection commands require StringName endpoint and port ids.")
		_:
			return GraphDiagnostic.reject(&"invalid_command", "The graph command kind is not supported.")
	return DomainResult.success(payload)

static func _has_string_names(payload: Dictionary, keys: Array[String]) -> bool:
	for key: String in keys:
		if not payload.has(key) or typeof(payload[key]) != TYPE_STRING_NAME:
			return false
	return true

static func _released_grid_delta(released: Variant, origin: int, axis: String) -> DomainResult:
	if typeof(released) == TYPE_INT:
		var integer_release: int = released
		if not _is_exact_integer(integer_release):
			return GraphDiagnostic.reject(&"non_representable_anchor", "Released %s coordinate exceeds exact representation." % axis)
		var integer_delta: int = integer_release - origin
		if not _is_exact_integer(integer_delta):
			return GraphDiagnostic.reject(&"non_representable_anchor", "Released %s coordinate is too distant from the grid origin." % axis)
		return DomainResult.success(float(integer_delta))
	if typeof(released) != TYPE_FLOAT or not is_finite(float(released)) or abs(float(released)) > MAX_EXACT_INTEGER_FLOAT:
		return GraphDiagnostic.reject(&"non_representable_anchor", "Released coordinates must be finite and exactly representable.")
	var float_delta: float = float(released) - float(origin)
	if not is_finite(float_delta) or abs(float_delta) > MAX_EXACT_INTEGER_FLOAT:
		return GraphDiagnostic.reject(&"non_representable_anchor", "Released coordinates must be within the exact grid range.")
	return DomainResult.success(float_delta)

static func _is_exact_integer(value: int) -> bool:
	return value >= -MAX_EXACT_INTEGER and value <= MAX_EXACT_INTEGER

static func _is_release_coordinate(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

static func _find_variant(task: Dictionary, variant_id: StringName) -> Dictionary:
	for raw_variant: Variant in Array(task["variants"]):
		var variant: Dictionary = raw_variant
		if StringName(variant["id"]) == variant_id:
			return variant
	return {}

static func _find_port(variant: Dictionary, port_id: StringName) -> Dictionary:
	for raw_port: Variant in Array(variant.get("ports", [])):
		var port: Dictionary = raw_port
		if StringName(port["id"]) == port_id:
			return port
	return {}

static func _find_node(nodes: Array, node_id: StringName) -> Dictionary:
	var index := _find_node_index(nodes, node_id)
	return Dictionary(nodes[index]) if index >= 0 else {}

static func _find_node_index(nodes: Array, node_id: StringName) -> int:
	for index: int in range(nodes.size()):
		if StringName(Dictionary(nodes[index])["node_id"]) == node_id:
			return index
	return -1
