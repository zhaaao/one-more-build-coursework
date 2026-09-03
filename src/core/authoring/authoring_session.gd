class_name AuthoringSession
extends RefCounted

## Synchronous Core owner for Authoring Run, report, and Reset boundaries.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const GraphModelType = preload("res://src/core/authoring/graph_model.gd")
const GraphSnapshotType = preload("res://src/core/authoring/graph_snapshot.gd")
const AuthoringRunPortType = preload("res://src/core/authoring/authoring_run_port.gd")
const AuthoringReportStateType = preload("res://src/core/authoring/authoring_report_state.gd")
const CourseworkRunInputType = preload("res://src/core/gvet/coursework_run_input.gd")
const CourseworkRunResultType = preload("res://src/core/gvet/coursework_run_result.gd")

enum State {
	EDITABLE,
	RUNNING_READ_ONLY,
	RESET_CONFIRMATION,
}

var _graph_model: GraphModelType = null
var _starting_snapshot: GraphSnapshotType = null
var _run_port: AuthoringRunPortType = null
var _report_state: AuthoringReportStateType = null
var _state: State = State.EDITABLE
var _reset_invoker: StringName = &""
var _view_token: StringName = &""
var _frame_request_count: int = 0
var _focus_target: StringName = &""

## Creates one Core session around a valid GraphModel and synchronous Run port.
## Example: `var session: AuthoringSession = AuthoringSession.new(model, run_port)`.
func _init(
	graph_model: GraphModelType,
	run_port: AuthoringRunPortType,
	report_state: AuthoringReportStateType = null
) -> void:
	_graph_model = graph_model
	_run_port = run_port
	_report_state = report_state if report_state != null else AuthoringReportStateType.new()
	if _graph_model != null and is_instance_valid(_graph_model):
		_starting_snapshot = _graph_model.snapshot()

## Creates an editable recovery session while retaining the Task-owned Reset
## snapshot separately from the restored current graph.
static func restore_from_recovery(
	graph_model: GraphModelType,
	run_port: AuthoringRunPortType,
	report_state: AuthoringReportStateType = null
) -> DomainResultType:
	if graph_model == null or not is_instance_valid(graph_model) \
			or not graph_model.construction_result().is_success():
		return DomainResultType.failure(&"authoring_recovery_model_invalid", "A validated recovered GraphModel is required.")
	if run_port == null or not is_instance_valid(run_port):
		return DomainResultType.failure(&"authoring_recovery_run_port_invalid", "A retained Authoring Run port is required.")
	var session: AuthoringSession = AuthoringSession.new(graph_model, run_port, report_state)
	var task_starting: GraphSnapshotType = graph_model.task_starting_snapshot()
	if task_starting == null or not is_instance_valid(task_starting):
		return DomainResultType.failure(&"authoring_recovery_starting_graph_invalid", "The Task starting graph is unavailable.")
	session._starting_snapshot = task_starting
	return DomainResultType.success(session)

## Returns the current Authoring state without exposing mutable session internals.
## Example: `if session.state() == AuthoringSession.State.EDITABLE: enable_run()`.
func state() -> State:
	return _state

## Returns the current accepted graph snapshot.
## Example: `var graph: GraphSnapshot = session.graph_snapshot()`.
func graph_snapshot() -> GraphSnapshotType:
	return _graph_model.snapshot() if _model_is_valid() else null

## Returns the current fresh process-local GraphModel revision.
## Example: `var revision: int = session.live_revision()`.
func live_revision() -> int:
	return _graph_model.live_revision() if _model_is_valid() else 0

## Returns the selected Save graph revision retained solely as provenance.
## Example: `var saved_revision: int = session.saved_provenance_revision()`.
func saved_provenance_revision() -> int:
	return _graph_model.saved_provenance_revision() if _model_is_valid() else 0

## Returns the recovered or edited Undo-entry count without exposing history.
## Example: `assert(session.undo_count() == 0)`.
func undo_count() -> int:
	return _graph_model.undo_count() if _model_is_valid() else 0

## Returns the recovered or edited Redo-entry count without exposing history.
## Example: `assert(session.redo_count() == 0)`.
func redo_count() -> int:
	return _graph_model.redo_count() if _model_is_valid() else 0

## Admits a graph command only while Authoring is Editable.
## Example: `var admitted: DomainResult = session.admit(command)`.
func admit(command: Variant) -> DomainResultType:
	var editable: DomainResultType = _require_editable(&"graph_mutation")
	return _graph_model.admit(command) if editable.is_success() else editable

## Admits an atomic graph command sequence only while Authoring is Editable.
## Example: `var admitted: DomainResult = session.admit_all(commands)`.
func admit_all(commands: Array[GraphCommand]) -> DomainResultType:
	var editable: DomainResultType = _require_editable(&"graph_mutation")
	return _graph_model.admit_all(commands) if editable.is_success() else editable

## Disconnects one graph connection only while Authoring is Editable.
## Example: `var result: DomainResult = session.disconnect_connection(&"connection_1")`.
func disconnect_connection(connection_id: StringName) -> DomainResultType:
	var editable: DomainResultType = _require_editable(&"graph_mutation")
	return _graph_model.disconnect_connection(connection_id) if editable.is_success() else editable

## Changes one node parameter only while Authoring is Editable.
## Example: `var result: DomainResult = session.change_parameter(&"node_1", 0, value)`.
func change_parameter(node_id: StringName, parameter_index: int, value: Variant) -> DomainResultType:
	var editable: DomainResultType = _require_editable(&"graph_mutation")
	return _graph_model.change_parameter(node_id, parameter_index, value) if editable.is_success() else editable

## Replays one graph edit only while Authoring is Editable.
## Example: `var result: DomainResult = session.undo()`.
func undo() -> DomainResultType:
	var editable: DomainResultType = _require_editable(&"undo")
	return _graph_model.undo() if editable.is_success() else editable

## Replays one graph edit forward only while Authoring is Editable.
## Example: `var result: DomainResult = session.redo()`.
func redo() -> DomainResultType:
	var editable: DomainResultType = _require_editable(&"redo")
	return _graph_model.redo() if editable.is_success() else editable

## Starts exactly one synchronous Run from the supplied immutable capture.
## Example: `var result: DomainResult = session.run(captured_input)`.
func run(captured_input: CourseworkRunInputType) -> DomainResultType:
	var editable: DomainResultType = _require_editable(&"run")
	if not editable.is_success():
		return editable
	if captured_input == null or not is_instance_valid(captured_input) \
			or not captured_input.is_valid():
		return _reject(&"invalid_run_capture", "Run requires a valid immutable capture.")
	if captured_input.graph_revision() != _graph_model.live_revision():
		return _reject(&"stale_run_capture", "Run capture must use the last committed graph revision.")
	if not _capture_matches_committed_graph(captured_input):
		return _reject(&"stale_run_capture", "Run capture must contain the last committed graph.")
	if _run_port == null or not is_instance_valid(_run_port):
		return _reject(&"run_port_unavailable", "Run requires a synchronous GVET port.")
	if not _graph_model._begin_run_mutation_fence():
		return _reject(&"run_fence_unavailable", "Run could not acquire the graph mutation fence.")
	_state = State.RUNNING_READ_ONLY
	var candidate: CourseworkRunResultType = _run_port.run(captured_input)
	_graph_model._end_run_mutation_fence()
	_state = State.EDITABLE
	var accepted: DomainResultType = _report_state.accept_completed_result(candidate, captured_input)
	if not accepted.is_success():
		_report_state.record_controlled_system_error(accepted.error_message())
		return accepted
	var report_revision: DomainResultType = _graph_model.set_completed_report_revision(
		captured_input.graph_revision())
	if not report_revision.is_success():
		_report_state.record_controlled_system_error(report_revision.error_message())
		return report_revision
	return accepted

## Rejects a Save attempt during Run; persistence implementation remains external.
## Example: `var gate: DomainResult = session.request_save()`.
func request_save() -> DomainResultType:
	return _require_editable(&"save")

## Rejects a Load attempt during Run; persistence implementation remains external.
## Example: `var gate: DomainResult = session.request_load()`.
func request_load() -> DomainResultType:
	return _require_editable(&"load")

## Opens Reset confirmation only while Authoring is Editable.
## Example: `var result: DomainResult = session.request_reset(&"toolbar_reset")`.
func request_reset(invoker: StringName) -> DomainResultType:
	var editable: DomainResultType = _require_editable(&"reset")
	if not editable.is_success():
		return editable
	_state = State.RESET_CONFIRMATION
	_reset_invoker = invoker
	return DomainResultType.success(true)

## Cancels Reset without changing graph, history, report, or view state.
## Example: `var result: DomainResult = session.cancel_reset()`.
func cancel_reset() -> DomainResultType:
	if _state != State.RESET_CONFIRMATION:
		return _reject(&"reset_not_pending", "Reset Cancel requires an open reset confirmation.")
	_state = State.EDITABLE
	return DomainResultType.success(true)

## Confirms Reset, restores the starting graph, and emits deterministic view and
## focus requests for the Presentation adapter.
## Example: `var result: DomainResult = session.confirm_reset([&"toolbar_reset", &"run"])`.
func confirm_reset(available_focus_targets: Array[StringName] = []) -> DomainResultType:
	if _state != State.RESET_CONFIRMATION:
		return _reject(&"reset_not_pending", "Reset Confirm requires an open reset confirmation.")
	if _starting_snapshot == null or not is_instance_valid(_starting_snapshot):
		_state = State.EDITABLE
		return _reject(&"starting_snapshot_unavailable", "Reset requires the task starting graph.")
	var restored: DomainResultType = _graph_model.reset_to_starting_snapshot(_starting_snapshot)
	_state = State.EDITABLE
	if not restored.is_success():
		return restored
	_frame_request_count += 1
	_focus_target = _resolve_focus_target(available_focus_targets)
	return restored

## Records an adapter-owned view token without changing graph content or history.
## Example: `session.set_view_token(&"zoom_125")`.
func set_view_token(view_token: StringName) -> DomainResultType:
	if _state != State.EDITABLE:
		return _reject(&"authoring_read_only", "View changes are unavailable while Authoring is not editable.")
	_view_token = view_token
	return DomainResultType.success(view_token)

## Returns the current adapter view token for deterministic projection tests.
## Example: `var token: StringName = session.view_token()`.
func view_token() -> StringName:
	return _view_token

## Returns how many Frame All requests Reset Confirm emitted.
## Example: `assert(session.frame_request_count() == 1)`.
func frame_request_count() -> int:
	return _frame_request_count

## Returns the currently requested post-reset focus target.
## Example: `adapter.restore_focus(session.focus_target())`.
func focus_target() -> StringName:
	return _focus_target

## Returns Cancel as the initial focus target while Reset confirmation is open.
## Example: `assert(session.reset_initial_focus() == &"reset_cancel")`.
func reset_initial_focus() -> StringName:
	return &"reset_cancel" if _state == State.RESET_CONFIRMATION else &""

## Returns the immutable report projection state.
## Example: `var report: AuthoringReportState = session.report_state()`.
func report_state() -> AuthoringReportStateType:
	return _report_state

func _model_is_valid() -> bool:
	return _graph_model != null and is_instance_valid(_graph_model) \
		and _graph_model.construction_result().is_success()

func _require_editable(action: StringName) -> DomainResultType:
	if not _model_is_valid():
		return _reject(&"authoring_unavailable", "Authoring requires a valid GraphModel.")
	if _state != State.EDITABLE:
		return _reject(&"authoring_read_only", "%s is unavailable while Authoring is read-only." % action)
	return DomainResultType.success(true)

func _resolve_focus_target(available_focus_targets: Array[StringName]) -> StringName:
	if not _reset_invoker.is_empty() and available_focus_targets.has(_reset_invoker):
		return _reset_invoker
	if not available_focus_targets.is_empty():
		return available_focus_targets[0]
	return &"canvas"

func _capture_matches_committed_graph(captured_input: CourseworkRunInputType) -> bool:
	var captured_graph: Dictionary = captured_input.graph_snapshot()
	var captured_nodes: Array = Array(captured_graph.get("nodes", []))
	var captured_connections: Array = Array(captured_graph.get("connections", []))
	var accepted_snapshot: GraphSnapshotType = _graph_model.snapshot()
	var accepted_nodes: Array = accepted_snapshot.nodes()
	var accepted_connections: Array = accepted_snapshot.connections()
	if captured_nodes.size() != accepted_nodes.size() \
			or captured_connections.size() != accepted_connections.size():
		return false
	for index: int in range(accepted_nodes.size()):
		if not _captured_node_matches(Dictionary(captured_nodes[index]), Dictionary(accepted_nodes[index])):
			return false
	for index: int in range(accepted_connections.size()):
		if not _captured_connection_matches(
				Dictionary(captured_connections[index]), Dictionary(accepted_connections[index])):
			return false
	return true

func _captured_node_matches(captured: Dictionary, accepted: Dictionary) -> bool:
	if String(captured.get("node_id", "")) != String(accepted.get("node_id", "")) \
			or String(captured.get("variant_id", "")) != String(accepted.get("variant_id", "")):
		return false
	var anchor: Dictionary = Dictionary(accepted.get("anchor", {}))
	if captured.get("anchor_x", null) != anchor.get("x", null) \
			or captured.get("anchor_y", null) != anchor.get("y", null):
		return false
	var captured_parameters: Array = Array(captured.get("parameter_values", []))
	var accepted_parameters: Array = Array(accepted.get("parameters", []))
	if captured_parameters.size() != accepted_parameters.size():
		return false
	var parameter_ids: Array[StringName] = _graph_model.parameter_ids_for_variant(
		StringName(accepted.get("variant_id", "")))
	if parameter_ids.is_empty():
		for index: int in range(accepted_parameters.size()):
			if Dictionary(captured_parameters[index]).get("value", null) != accepted_parameters[index]:
				return false
		return true
	if parameter_ids.size() != accepted_parameters.size():
		return false
	var captured_by_id: Dictionary = {}
	for raw_parameter: Variant in captured_parameters:
		if typeof(raw_parameter) != TYPE_DICTIONARY:
			return false
		var captured_parameter: Dictionary = raw_parameter
		var parameter_id: StringName = StringName(captured_parameter.get("parameter_id", ""))
		if parameter_id.is_empty() or captured_by_id.has(parameter_id):
			return false
		captured_by_id[parameter_id] = captured_parameter.get("value", null)
	for index: int in range(parameter_ids.size()):
		var parameter_id: StringName = parameter_ids[index]
		if not captured_by_id.has(parameter_id) \
				or captured_by_id[parameter_id] != accepted_parameters[index]:
			return false
	return true

func _captured_connection_matches(captured: Dictionary, accepted: Dictionary) -> bool:
	return String(captured.get("connection_id", "")) == String(accepted.get("connection_id", "")) \
		and String(captured.get("source_node_id", "")) == String(accepted.get("output_node_id", "")) \
		and String(captured.get("source_port_id", "")) == String(accepted.get("output_port_id", "")) \
		and String(captured.get("target_node_id", "")) == String(accepted.get("input_node_id", "")) \
		and String(captured.get("target_port_id", "")) == String(accepted.get("input_port_id", ""))

func _reject(code: StringName, message: String) -> DomainResultType:
	return DomainResultType.failure(code, message)
