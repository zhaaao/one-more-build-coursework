## Presentation-to-owner adapter for the configured Task execution contract.
##
## It translates GraphEdit intent into synchronous Core Authoring operations and
## exposes detached accepted projections only. It owns no Sandbox runtime state.
class_name CourseworkLoopSessionAdapter
extends GraphAuthoringPanel.SessionPort


const CourseworkRunInputType = preload("res://src/core/gvet/coursework_run_input.gd")
const GraphCommandType = preload("res://src/core/authoring/graph_command.gd")
const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CourseworkPublicRunContractType = preload("res://src/core/task/coursework_public_run_contract.gd")
const CourseworkWorkdayLifecycleType = preload("res://src/feature/workday/coursework_workday_lifecycle.gd")
const CourseworkVoluntaryTestTransactionType = preload("res://src/feature/workday/coursework_voluntary_test_transaction.gd")


signal completed_report_available(report: CourseworkRunResult)

var _authoring: AuthoringSession
var _task_binding: Dictionary
var _node_id_aliases: Dictionary[StringName, StringName] = {}
var _connection_id_aliases: Dictionary[StringName, StringName] = {}
var _active_case: Dictionary
var _public_cases: Array[Dictionary] = []
var _creation_options: Array[Dictionary] = []
var _creation_contract: Dictionary = {}
var _authoring_registry: Dictionary
var _fixture_id: String = "coursework.authoring"
var _parameter_names_by_variant: Dictionary[StringName, Array] = {}
var _auto_solve_witness_operations: Array[Dictionary] = []
var _workday_lifecycle: CourseworkWorkdayLifecycle = null
var _public_run_contract: CourseworkPublicRunContract = null
var _request_sequence: int = 0

enum WorkdayConfiguration { LEGACY, READY, INCOMPLETE }


func _init(
	owner: AuthoringSession,
	_legacy_graph_model: GraphModel,
	task_binding: Dictionary,
	active_case: Dictionary,
	authoring_registry: Dictionary,
	fixture_id: String = "coursework.authoring",
	parameter_names_by_variant: Dictionary[StringName, Array] = {},
	workday_lifecycle: CourseworkWorkdayLifecycle = null,
	public_cases: Array[Dictionary] = [],
	creation_contract: Dictionary = {}
) -> void:
	_authoring = owner
	_task_binding = task_binding.duplicate(true)
	_node_id_aliases = _string_name_aliases(Dictionary(_task_binding.get("node_id_aliases", {})))
	_connection_id_aliases = _string_name_aliases(Dictionary(_task_binding.get("connection_id_aliases", {})))
	_active_case = active_case.duplicate(true)
	_public_cases = public_cases.duplicate(true)
	if _public_cases.is_empty() and not _active_case.is_empty():
		_public_cases.append(_active_case.duplicate(true))
	_creation_contract = creation_contract.duplicate(true)
	for raw_option: Variant in Array(_creation_contract.get("variants", [])):
		if typeof(raw_option) == TYPE_DICTIONARY:
			_creation_options.append(Dictionary(raw_option).duplicate(true))
	_authoring_registry = authoring_registry.duplicate(true)
	_fixture_id = fixture_id
	_parameter_names_by_variant = parameter_names_by_variant.duplicate(true)
	_workday_lifecycle = workday_lifecycle

## Injects the optional Feature lifecycle for presentation composition gates.
func configure_workday_lifecycle(workday_lifecycle: CourseworkWorkdayLifecycle) -> void:
	_workday_lifecycle = workday_lifecycle

## Injects the Task-owned public Run contract for the optional Workday composition.
func configure_public_run_contract(public_run_contract: CourseworkPublicRunContract) -> void:
	_public_run_contract = public_run_contract


## Receives detached witness operations from the admitted Task recovery contract.
func configure_auto_solve_witness(operations: Array[Variant]) -> void:
	_auto_solve_witness_operations.clear()
	for raw_operation: Variant in operations:
		if typeof(raw_operation) == TYPE_DICTIONARY:
			_auto_solve_witness_operations.append(Dictionary(raw_operation).duplicate(true))

## Atomically replaces the recovered Authoring and optional Workday owner binding.
## Example: `var result: DomainResult = adapter.rebind_owner(recovered_authoring, recovered_workday)`.
func rebind_owner(
	authoring_session: AuthoringSession,
	workday_lifecycle: CourseworkWorkdayLifecycle = null
) -> DomainResult:
	if authoring_session == null or not is_instance_valid(authoring_session) \
			or authoring_session.graph_snapshot() == null:
		return DomainResultType.failure(
			&"authoring_owner_invalid", "Rebinding requires a valid recovered Authoring session.")
	if workday_lifecycle != null and not is_instance_valid(workday_lifecycle):
		return DomainResultType.failure(
			&"workday_owner_invalid", "Rebinding requires a valid recovered Workday lifecycle.")
	_authoring = authoring_session
	_workday_lifecycle = workday_lifecycle
	return DomainResultType.success(true)


func request(command: GraphAuthoringPanel.GraphCommandRequest) -> GraphAuthoringPanel.SessionResponse:
	if command == null or command.contains_engine_object_payload():
		return _rejected(&"invalid_graph_request", "Authoring could not accept that graph request.")
	if _authoring == null or not is_instance_valid(_authoring):
		return _rejected(&"session_unavailable", "Authoring session is unavailable.")
	var graph_revision_before: int = _authoring.live_revision()
	if _command_can_mutate_graph(command):
		var workday_gate: DomainResult = _preflight_workday_graph_mutation()
		if not workday_gate.is_success():
			return _rejected(workday_gate.error_code(), workday_gate.error_message())
	var result: DomainResult = _apply_command(command)
	if not result.is_success() and command.kind == GraphAuthoringPanel.GraphCommandRequest.Kind.AUTO_SOLVE:
		var rollback: DomainResult = _restore_auto_solve_starting_graph()
		if not rollback.is_success():
			result = rollback
	var synchronization: DomainResult = _acknowledge_revision_after_request(graph_revision_before)
	if not synchronization.is_success():
		return _rejected(synchronization.error_code(), synchronization.error_message())
	if not result.is_success():
		return _rejected(result.error_code(), result.error_message())
	return GraphAuthoringPanel.SessionResponse.new(
		true, current_snapshot(), &"", "Accepted graph change.",
		_authoring.state() == AuthoringSession.State.RESET_CONFIRMATION,
		_authoring.state() == AuthoringSession.State.EDITABLE)


func _restore_auto_solve_starting_graph() -> DomainResult:
	var requested: DomainResult = _authoring.request_reset(&"reset")
	if not requested.is_success():
		return requested
	return _authoring.confirm_reset([&"reset", &"run"])


func _acknowledge_revision_after_request(previous_revision: int) -> DomainResult:
	var current_revision: int = _authoring.live_revision()
	if current_revision <= previous_revision:
		return DomainResultType.success(true)
	return _acknowledge_committed_graph_revision(current_revision)


func current_snapshot() -> Dictionary:
	return _presentation_graph_projection(_run_graph_from_accepted_snapshot())


func creatable_node_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for source: Dictionary in _creation_options:
		if bool(source.get("creatable", false)):
			options.append(source.duplicate(true))
	return options


func run_public_case(_case_id: StringName) -> Dictionary:
	if _authoring == null or not is_instance_valid(_authoring):
		return {}
	var workday_configuration: int = _workday_configuration()
	if workday_configuration == WorkdayConfiguration.INCOMPLETE:
		return {}
	if workday_configuration == WorkdayConfiguration.READY:
		return _run_workday_public_case(_case_id)
	_request_sequence += 1
	var input_result: DomainResult = CourseworkRunInputType.create(
		String(_task_binding.get("task_id", "")), int(_task_binding.get("day_index", 0)),
		"request.%s.%d" % [String(_task_binding.get("task_id", "coursework")), _request_sequence], _authoring.live_revision(),
		_run_graph_from_accepted_snapshot(), [_active_case])
	if not input_result.is_success():
		return {}
	var run_result: DomainResult = _authoring.run(input_result.value())
	if not run_result.is_success():
		return {}
	var report: CourseworkRunResult = run_result.value()
	if report == null or not report.is_valid():
		return {}
	completed_report_available.emit(report)
	return _player_report_projection(report)


func run_all_public_cases() -> Dictionary:
	if _authoring == null or not is_instance_valid(_authoring):
		return {}
	var workday_configuration: int = _workday_configuration()
	if workday_configuration != WorkdayConfiguration.READY:
		return {}
	var case_ids: Array[String] = []
	for public_case: Dictionary in _public_cases:
		var case_id: String = String(public_case.get("case_id", ""))
		if case_id.is_empty():
			return {}
		case_ids.append(case_id)
	if case_ids.size() < 2:
		return {}
	_request_sequence += 1
	var transaction := CourseworkVoluntaryTestTransactionType.new()
	var result: DomainResult = transaction.admit_and_run(
		_public_run_contract, _workday_lifecycle, _authoring,
		CourseworkVoluntaryTestTransactionType.Action.VOLUNTARY_SUITE,
		String(_task_binding.get("task_id", "")), int(_task_binding.get("day_index", 0)),
		"request.%s.%d" % [String(_task_binding.get("task_id", "coursework")), _request_sequence],
		_authoring.live_revision(), _run_graph_from_accepted_snapshot(), case_ids)
	if not result.is_success() or not result.value() is CourseworkRunResult:
		return {}
	var report: CourseworkRunResult = result.value()
	if not is_instance_valid(report) or not report.is_valid():
		return {}
	completed_report_available.emit(report)
	return _player_report_projection(report)


func _run_workday_public_case(case_id: StringName) -> Dictionary:
	if case_id.is_empty():
		return {}
	_request_sequence += 1
	var transaction := CourseworkVoluntaryTestTransactionType.new()
	var result: DomainResult = transaction.admit_and_run(
		_public_run_contract, _workday_lifecycle, _authoring,
		CourseworkVoluntaryTestTransactionType.Action.TARGETED_CASE,
		String(_task_binding.get("task_id", "")), int(_task_binding.get("day_index", 0)),
		"request.%s.%d" % [String(_task_binding.get("task_id", "coursework")), _request_sequence], _authoring.live_revision(),
		_run_graph_from_accepted_snapshot(), [String(case_id)])
	if not result.is_success() or not result.value() is CourseworkRunResult:
		return {}
	var report: CourseworkRunResult = result.value()
	if not is_instance_valid(report) or not report.is_valid():
		return {}
	completed_report_available.emit(report)
	return _player_report_projection(report)


func completed_report() -> Dictionary:
	if _authoring == null:
		return {}
	var report: CourseworkRunResult = _authoring.report_state().completed_report()
	return _player_report_projection(report) if report != null and report.is_valid() else {}


func report_is_out_of_date() -> bool:
	return _authoring != null and _authoring.report_state().report_status(
		_authoring.live_revision()) == &"out_of_date"


func port_descriptors_for(node_snapshot: Dictionary) -> Array[GraphAuthoringPanel.PortDescriptor]:
	var variant_id: String = String(node_snapshot.get("variant_id", ""))
	for raw_variant: Variant in Array(_authoring_registry.get("variants", [])):
		var variant: Dictionary = raw_variant
		if String(variant.get("variant_id", "")) != variant_id:
			continue
		var descriptors: Array[GraphAuthoringPanel.PortDescriptor] = []
		for raw_port: Variant in Array(variant.get("ports", [])):
			var port: Dictionary = raw_port
			descriptors.append(GraphAuthoringPanel.PortDescriptor.new(
				StringName(port.get("port_id", "")), int(port.get("registry_order", 0)),
				StringName(port.get("direction", "")), StringName(port.get("kind", "")),
				StringName(port.get("data_type", "")), String(port.get("label", ""))))
		return descriptors
	return []


func record_view_request(view_token: StringName) -> void:
	if _authoring != null:
		_authoring.set_view_token(view_token)


func _apply_command(command: GraphAuthoringPanel.GraphCommandRequest) -> DomainResult:
	match command.kind:
		GraphAuthoringPanel.GraphCommandRequest.Kind.SELECT:
			return DomainResultType.success(true)
		GraphAuthoringPanel.GraphCommandRequest.Kind.CREATE:
			var requested_anchor: Dictionary = Dictionary(command.payload.get("anchor", {}))
			if requested_anchor.is_empty():
				requested_anchor = _next_creation_anchor()
			return _authoring.admit(GraphCommandType.create_node(
				StringName(command.payload.get("category", "")),
				_default_variant_for_category(StringName(command.payload.get("category", "")), command.payload),
				requested_anchor))
		GraphAuthoringPanel.GraphCommandRequest.Kind.MOVE:
			return _authoring.admit(GraphCommandType.move_node(
				_resolved_node_id(StringName(command.payload.get("node_id", ""))),
				float(command.payload.get("released_x", command.payload.get("x", 0.0))),
				float(command.payload.get("released_y", command.payload.get("y", 0.0)))))
		GraphAuthoringPanel.GraphCommandRequest.Kind.DELETE:
			return _delete_requested_nodes(command.payload)
		GraphAuthoringPanel.GraphCommandRequest.Kind.CONNECT:
			return _authoring.admit(GraphCommandType.connect_ports(
				_resolved_node_id(StringName(command.payload.get("output_node_id", ""))),
				StringName(command.payload.get("output_port_id", "")),
				_resolved_node_id(StringName(command.payload.get("input_node_id", ""))),
				StringName(command.payload.get("input_port_id", ""))))
		GraphAuthoringPanel.GraphCommandRequest.Kind.DISCONNECT:
			return _authoring.disconnect_connection(_requested_connection_id(command.payload))
		GraphAuthoringPanel.GraphCommandRequest.Kind.CONFIGURE:
			return _authoring.change_parameter(_resolved_node_id(StringName(command.payload.get("node_id", ""))),
				int(command.payload.get("parameter_index", -1)), command.payload.get("value"))
		GraphAuthoringPanel.GraphCommandRequest.Kind.UNDO:
			return _authoring.undo()
		GraphAuthoringPanel.GraphCommandRequest.Kind.REDO:
			return _authoring.redo()
		GraphAuthoringPanel.GraphCommandRequest.Kind.RESET:
			return _authoring.request_reset(&"reset")
		GraphAuthoringPanel.GraphCommandRequest.Kind.CONFIRM_RESET:
			return _authoring.confirm_reset([&"reset", &"run"])
		GraphAuthoringPanel.GraphCommandRequest.Kind.CANCEL_RESET:
			return _authoring.cancel_reset()
		GraphAuthoringPanel.GraphCommandRequest.Kind.AUTO_SOLVE:
			return _apply_auto_solve_witness()
	return DomainResultType.failure(&"unsupported_graph_request", "This graph request is unavailable.")


## Restores the accepted Task graph and reapplies only its admitted witness edits.
func _apply_auto_solve_witness() -> DomainResult:
	if _auto_solve_witness_operations.is_empty():
		return DomainResultType.failure(
			&"auto_solve_witness_unavailable", "Auto Solve is unavailable for this Task.")
	if _authoring.state() != AuthoringSession.State.EDITABLE:
		return DomainResultType.failure(
			&"auto_solve_unavailable", "Auto Solve is unavailable while Authoring is not editable.")
	var reset_requested: DomainResult = _authoring.request_reset(&"reset")
	if not reset_requested.is_success():
		return reset_requested
	var reset_confirmed: DomainResult = _authoring.confirm_reset([&"reset", &"run"])
	if not reset_confirmed.is_success():
		return reset_confirmed
	for operation: Dictionary in _auto_solve_witness_operations:
		var operation_kind: StringName = _witness_operation_kind(operation)
		match operation_kind:
			&"create_node":
				var created: DomainResult = _create_auto_solve_node(operation)
				if not created.is_success():
					return created
			&"delete_node":
				var deleted: DomainResult = _authoring.admit_all([
					GraphCommandType.delete_node(_resolved_node_id(_witness_node_id(operation)))])
				if not deleted.is_success():
					return deleted
			&"connect":
				var connected: DomainResult = _authoring.admit_all([
					GraphCommandType.connect_ports(
						_resolved_node_id(_witness_source_node_id(operation)),
						_witness_source_port_id(operation),
						_resolved_node_id(_witness_target_node_id(operation)),
						_witness_port_id(operation, &"target"))])
				if not connected.is_success():
					return connected
			&"replace_connection":
				var replaced_connection_id: StringName = StringName(
					operation.get("replaces_connection_id", ""))
				var replaced_connection: DomainResult = _authoring.disconnect_connection(
					_requested_connection_id({"connection_id": replaced_connection_id}))
				if not replaced_connection.is_success():
					return replaced_connection
				var replacement_connected: DomainResult = _authoring.admit_all([
					GraphCommandType.connect_ports(
						_resolved_node_id(_witness_source_node_id(operation)),
						_witness_source_port_id(operation),
						_resolved_node_id(_witness_target_node_id(operation)),
						_witness_port_id(operation, &"target"))])
				if not replacement_connected.is_success():
					return replacement_connected
			&"disconnect":
				var disconnected: DomainResult = _authoring.disconnect_connection(
					_requested_connection_id(_witness_connection_payload(operation)))
				if not disconnected.is_success():
					return disconnected
			_:
				return DomainResultType.failure(
					&"auto_solve_witness_invalid", "Auto Solve has an unsupported witness operation.")
	return DomainResultType.success(true)


func _create_auto_solve_node(operation: Dictionary) -> DomainResult:
	var alias: StringName = _witness_node_id(operation)
	var variant: StringName = StringName(operation.get("variant_id", ""))
	var category: StringName = StringName(operation.get(
		"category_id", operation.get("category", _category_id_for_variant(variant))))
	if alias.is_empty() or variant.is_empty() or category.is_empty():
		return DomainResultType.failure(
			&"auto_solve_witness_invalid", "Auto Solve has an invalid create operation.")
	var node_ids_before: Dictionary[StringName, bool] = _accepted_node_ids()
	var created: DomainResult = _authoring.admit(GraphCommandType.create_node(
		category, variant, _next_creation_anchor()))
	if not created.is_success():
		return created
	var node_ids_after: Dictionary[StringName, bool] = _accepted_node_ids()
	var created_node_id: StringName = &""
	for node_id: StringName in node_ids_after:
		if not node_ids_before.has(node_id):
			if not created_node_id.is_empty():
				return DomainResultType.failure(
					&"auto_solve_alias_ambiguous", "Auto Solve could not resolve a created Task node.")
			created_node_id = node_id
	if created_node_id.is_empty():
		return DomainResultType.failure(
			&"auto_solve_alias_unavailable", "Auto Solve could not resolve a created Task node.")
	_node_id_aliases[alias] = created_node_id
	var parameters: Dictionary = Dictionary(operation.get("parameters", {}))
	var parameter_names: Array[String] = []
	for raw_name: Variant in parameters.keys():
		parameter_names.append(String(raw_name))
	parameter_names.sort()
	for parameter_name: String in parameter_names:
		var parameter_index: int = _witness_created_parameter_index(variant, parameter_name)
		if parameter_index < 0:
			return DomainResultType.failure(
				&"auto_solve_witness_invalid", "Auto Solve has an unknown created-node parameter.")
		var parameter_value: Variant = parameters[parameter_name]
		if typeof(parameter_value) == TYPE_STRING:
			parameter_value = StringName(parameter_value)
		var configured: DomainResult = _authoring.change_parameter(
			created_node_id, parameter_index, parameter_value)
		if not configured.is_success():
			return configured
	return DomainResultType.success(true)


func _accepted_node_ids() -> Dictionary[StringName, bool]:
	var node_ids: Dictionary[StringName, bool] = {}
	for raw_node: Variant in _authoring.graph_snapshot().nodes():
		var node_id: StringName = StringName(Dictionary(raw_node).get("node_id", ""))
		if not node_id.is_empty():
			node_ids[node_id] = true
	return node_ids


func _witness_created_parameter_index(variant_id: StringName, parameter_name: String) -> int:
	var parameter_names: Array[String] = _parameter_names(variant_id)
	var direct_index: int = parameter_names.find(parameter_name)
	if direct_index >= 0:
		return direct_index
	if parameter_name == "operation_id":
		var action_index: int = parameter_names.find("action_id")
		if action_index >= 0:
			return action_index
		var query_index: int = parameter_names.find("query_id")
		if query_index >= 0:
			return query_index
	if parameter_names.size() == 1:
		return 0
	return -1


func _witness_operation_kind(operation: Dictionary) -> StringName:
	return StringName(String(operation.get("operation", operation.get("kind", operation.get("type", "")))).to_lower())


func _witness_node_id(operation: Dictionary) -> StringName:
	return StringName(operation.get("node_id", operation.get("target_node_id", operation.get("alias", ""))))


func _witness_source_node_id(operation: Dictionary) -> StringName:
	return StringName(operation.get("source_node_id", operation.get("output_node_id", "")))


func _witness_target_node_id(operation: Dictionary) -> StringName:
	return StringName(operation.get("target_node_id", operation.get("input_node_id", "")))


func _witness_port_id(operation: Dictionary, endpoint: StringName) -> StringName:
	if endpoint == &"source":
		return StringName(operation.get("source_port_id", operation.get("output_port_id", "")))
	return StringName(operation.get("target_port_id", operation.get("input_port_id", "")))


## The Task witness uses its content-level Compare value alias; execution exposes result.
func _witness_source_port_id(operation: Dictionary) -> StringName:
	var source_port_id: StringName = _witness_port_id(operation, &"source")
	var source_node_id: StringName = _resolved_node_id(_witness_source_node_id(operation))
	if source_port_id != &"value":
		return source_port_id
	for raw_node: Variant in _authoring.graph_snapshot().nodes():
		var node: Dictionary = Dictionary(raw_node)
		if StringName(node.get("node_id", "")) == source_node_id \
				and StringName(node.get("variant_id", "")) == &"value.compare.numeric":
			return &"result"
	return source_port_id


func _witness_connection_payload(operation: Dictionary) -> Dictionary:
	return {
		"connection_id": operation.get("connection_id", ""),
		"output_node_id": _witness_source_node_id(operation),
		"output_port_id": _witness_source_port_id(operation),
		"input_node_id": _witness_target_node_id(operation),
		"input_port_id": _witness_port_id(operation, &"target"),
	}


func _witness_parameter_index(operation: Dictionary) -> int:
	if operation.has("parameter_index"):
		return int(operation.get("parameter_index", -1))
	var node_id: StringName = _resolved_node_id(_witness_node_id(operation))
	var parameter_id: String = String(operation.get("parameter_id", ""))
	for raw_node: Variant in _authoring.graph_snapshot().nodes():
		var node: Dictionary = Dictionary(raw_node)
		if StringName(node.get("node_id", "")) == node_id:
			return _parameter_names(StringName(node.get("variant_id", ""))).find(parameter_id)
	return -1


## Resolves a visible category to the Task-admitted variant when a pointer route
## intentionally carries only the player-facing category token.
func _default_variant_for_category(category_id: StringName, payload: Dictionary) -> StringName:
	var explicit_variant := StringName(payload.get("variant_id", ""))
	if not explicit_variant.is_empty():
		return explicit_variant
	for raw_variant: Variant in Array(_authoring_registry.get("variants", [])):
		var variant: Dictionary = raw_variant
		if StringName(variant.get("category_id", "")) == category_id:
			return StringName(variant.get("variant_id", ""))
	return &""


func _next_creation_anchor() -> Dictionary:
	var grid_size: int = int(_creation_contract.get("grid_size", 8))
	var origin: Dictionary = Dictionary(_creation_contract.get("grid_origin", {"x": 0, "y": 0}))
	var bounds: Dictionary = Dictionary(_creation_contract.get(
		"bounds", {"min_x": -128, "max_x": 128, "min_y": -32, "max_y": 32}))
	var occupied: Dictionary = {}
	for node: Dictionary in current_snapshot().get("nodes", []):
		var anchor_x: int = int(node.get("anchor_x", Dictionary(node.get("anchor", {})).get("x", 0)))
		var anchor_y: int = int(node.get("anchor_y", Dictionary(node.get("anchor", {})).get("y", 0)))
		occupied["%d:%d" % [anchor_x, anchor_y]] = true
	for y: int in range(int(bounds.get("min_y", -32)), int(bounds.get("max_y", 32)) + 1, grid_size):
		for x: int in range(int(bounds.get("min_x", -128)), int(bounds.get("max_x", 128)) + 1, grid_size):
			if x < int(origin.get("x", 0)) or y < int(origin.get("y", 0)):
				continue
			if not occupied.has("%d:%d" % [x, y]):
				return {"x": x, "y": y}
	return {"x": int(origin.get("x", 0)), "y": int(origin.get("y", 0))}


## Resolves Task-authored graph aliases to the generated Authoring identities.
func _resolved_node_id(node_id: StringName) -> StringName:
	return _node_id_aliases.get(node_id, node_id)


func _string_name_aliases(source: Dictionary) -> Dictionary[StringName, StringName]:
	var aliases: Dictionary[StringName, StringName] = {}
	for raw_source: Variant in source.keys():
		var source_id := StringName(raw_source)
		var target_id := StringName(source[raw_source])
		if not source_id.is_empty() and not target_id.is_empty():
			aliases[source_id] = target_id
	return aliases


## Resolves GraphEdit endpoint payloads to the accepted connection identity.
func _requested_connection_id(payload: Dictionary) -> StringName:
	var direct_id := StringName(payload.get("connection_id", ""))
	if not direct_id.is_empty():
		return _connection_id_aliases.get(direct_id, direct_id)
	var source_node := StringName(payload.get("output_node_id", ""))
	var source_port := StringName(payload.get("output_port_id", ""))
	var target_node := StringName(payload.get("input_node_id", ""))
	var target_port := StringName(payload.get("input_port_id", ""))
	for raw_connection: Variant in Array(_run_graph_from_accepted_snapshot().get("connections", [])):
		var connection: Dictionary = raw_connection
		if StringName(connection.get("source_node_id", connection.get("output_node_id", ""))) == source_node \
				and StringName(connection.get("source_port_id", connection.get("output_port_id", ""))) == source_port \
				and StringName(connection.get("target_node_id", connection.get("input_node_id", ""))) == target_node \
				and StringName(connection.get("target_port_id", connection.get("input_port_id", ""))) == target_port:
			return StringName(connection.get("connection_id", ""))
	return &""


## Applies every GraphEdit-selected node deletion through the existing owner batch seam.
func _delete_requested_nodes(payload: Dictionary) -> DomainResult:
	var node_ids: Array[StringName] = []
	for raw_node_id: Variant in Array(payload.get("node_ids", [])):
		node_ids.append(_resolved_node_id(StringName(raw_node_id)))
	if node_ids.is_empty():
		node_ids.append(_resolved_node_id(StringName(payload.get("node_id", ""))))
	var commands: Array[GraphCommand] = []
	for node_id: StringName in node_ids:
		if not node_id.is_empty():
			commands.append(GraphCommandType.delete_node(node_id))
	if commands.is_empty():
		return DomainResultType.failure(&"delete_target_missing", "Choose a node to delete.")
	return _authoring.admit_all(commands)

func _command_can_mutate_graph(command: GraphAuthoringPanel.GraphCommandRequest) -> bool:
	return command.kind != GraphAuthoringPanel.GraphCommandRequest.Kind.SELECT \
		and command.kind != GraphAuthoringPanel.GraphCommandRequest.Kind.CANCEL_RESET

func _preflight_workday_graph_mutation() -> DomainResult:
	var workday_configuration: int = _workday_configuration()
	if workday_configuration == WorkdayConfiguration.LEGACY:
		return DomainResultType.success(true)
	if workday_configuration == WorkdayConfiguration.INCOMPLETE:
		return DomainResultType.failure(
			&"workday_configuration_incomplete",
			"Workday graph mutation requires both lifecycle and public Run contract.")
	var lifecycle_gate: DomainResult = _workday_lifecycle.preflight_authoring_graph_mutation()
	if not lifecycle_gate.is_success():
		return lifecycle_gate
	if _workday_lifecycle.operational_authoring_revision() != _authoring.live_revision():
		return DomainResultType.failure(
			&"workday_authoring_revision_mismatch",
			"Workday and GraphModel revisions must match before graph mutation.")
	return DomainResultType.success(true)

func _acknowledge_committed_graph_revision(committed_revision: int) -> DomainResult:
	if _workday_configuration() != WorkdayConfiguration.READY:
		return DomainResultType.success(true)
	var acknowledgement: DomainResult = _workday_lifecycle.accept_authoring_revision_change(committed_revision)
	if not acknowledgement.is_success():
		return acknowledgement
	return DomainResultType.success(true)


func _workday_configuration() -> int:
	if _workday_lifecycle == null and _public_run_contract == null:
		return WorkdayConfiguration.LEGACY
	if _workday_lifecycle != null and _public_run_contract != null:
		return WorkdayConfiguration.READY
	return WorkdayConfiguration.INCOMPLETE


## Returns the current Task-owned public Run graph without any Task witness data.
func accepted_run_graph() -> Dictionary:
	return _run_graph_from_accepted_snapshot()


func _run_graph_from_accepted_snapshot() -> Dictionary:
	if _authoring == null:
		return {}
	var snapshot: GraphSnapshot = _authoring.graph_snapshot()
	if snapshot == null:
		return {}
	var nodes: Array[Dictionary] = []
	for raw_node: Variant in snapshot.nodes():
		var node: Dictionary = raw_node
		var parameters: Array[Dictionary] = []
		var variant_id: StringName = StringName(node.get("variant_id", ""))
		var parameter_names: Array[String] = _parameter_names(variant_id)
		for index: int in range(parameter_names.size()):
			var values: Array = Array(node.get("parameters", []))
			var parameter_value: Variant = values[index] if index < values.size() else null
			if typeof(parameter_value) == TYPE_STRING_NAME:
				parameter_value = String(parameter_value)
			parameters.append({
				"parameter_id": parameter_names[index],
				"value": parameter_value,
			})
		parameters.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return String(left.get("parameter_id", "")) < String(right.get("parameter_id", "")))
		nodes.append({
			"node_id": String(node.get("node_id", "")),
			"variant_id": String(node.get("variant_id", "")),
			"anchor_x": int(Dictionary(node.get("anchor", {})).get("x", 0)),
			"anchor_y": int(Dictionary(node.get("anchor", {})).get("y", 0)),
			"parameter_values": parameters,
		})
	nodes.sort_custom(_stable_id_less)
	var connections: Array[Dictionary] = []
	for raw_connection: Variant in snapshot.connections():
		var connection: Dictionary = raw_connection
		connections.append({
			"connection_id": String(connection.get("connection_id", "")),
			"source_node_id": String(connection.get("output_node_id", "")),
			"source_port_id": String(connection.get("output_port_id", "")),
			"target_node_id": String(connection.get("input_node_id", "")),
			"target_port_id": String(connection.get("input_port_id", "")),
		})
	connections.sort_custom(_stable_id_less)
	return {
		"graph_codec_version": "authoring_graph_v1",
		"fixture_id": _fixture_id,
		"nodes": nodes,
		"connections": connections,
	}


func _presentation_graph_projection(graph_snapshot: Dictionary) -> Dictionary:
	var projection := graph_snapshot.duplicate(true)
	var nodes: Array = Array(projection.get("nodes", []))
	for index: int in range(nodes.size()):
		var node: Dictionary = Dictionary(nodes[index])
		node["category_id"] = String(_category_id_for_variant(StringName(node.get("variant_id", ""))))
		nodes[index] = node
	projection["nodes"] = nodes
	return projection


func _category_id_for_variant(variant_id: StringName) -> StringName:
	for raw_variant: Variant in Array(_authoring_registry.get("variants", [])):
		var variant: Dictionary = raw_variant
		if StringName(variant.get("variant_id", "")) == variant_id:
			return StringName(variant.get("category_id", ""))
	return &""


func _player_report_projection(report: CourseworkRunResult) -> Dictionary:
	var cases: Array[CourseworkCaseResult] = report.case_results()
	var selected: CourseworkCaseResult = cases[0] if not cases.is_empty() else null
	var selected_record: Dictionary = selected.to_dictionary() if selected != null else {}
	return {
		"outcome": "PASS" if report.suite_pass() else "FAIL",
		"trace": selected.trace() if selected != null else [],
		"reason": String(selected_record.get("ordinary_failure_reason", "")),
	}


func _parameter_names(variant_id: StringName) -> Array[String]:
	if _parameter_names_by_variant.has(variant_id):
		return Array(_parameter_names_by_variant[variant_id]).duplicate()
	match variant_id:
		&"value.constant.numeric", &"v.constant": return ["value"]
		&"value.compare.numeric": return ["operator"]
		&"flow.repeat.bounded": return ["count"]
		&"parcel.query.front_sensor_matches_color": return ["colour", "query_id"]
		&"parcel.query.path_is_clear", &"parcel.query.battery_units": return ["query_id"]
		&"parcel.action.turn": return ["direction", "action_id"]
		&"parcel.action.advance_conveyors", &"parcel.action.charge", &"parcel.action.drop_front", &"parcel.action.move_forward", &"parcel.action.pick_up_front", &"v.action": return ["action_id"]
	return []


func _rejected(code: StringName, message: String) -> GraphAuthoringPanel.SessionResponse:
	return GraphAuthoringPanel.SessionResponse.new(false, current_snapshot(), code, message,
		_authoring != null and _authoring.state() == AuthoringSession.State.RESET_CONFIRMATION,
		_authoring != null and _authoring.state() == AuthoringSession.State.EDITABLE)


func _stable_id_less(left: Dictionary, right: Dictionary) -> bool:
	var left_id: String = String(left.get("node_id", left.get("connection_id", "")))
	var right_id: String = String(right.get("node_id", right.get("connection_id", "")))
	return left_id < right_id
