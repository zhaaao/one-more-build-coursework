class_name CourseworkTaskSandboxPort
extends CourseworkSandboxPort

## Adapts real Parcel Bot Sandbox outcomes to GVET's synchronous Dictionary ABI.
##
## Example: `var state := port.create_case_state(task_case)` returns one detached
## Task-owned initial projection; no mutable Sandbox state is retained by the port.

const SandboxCasePortType = preload("res://src/core/sandbox/sandbox_case_port.gd")
const SandboxCaseStateType = preload("res://src/core/sandbox/sandbox_case_state.gd")
const SandboxActionResultType = preload("res://src/core/sandbox/sandbox_action_result.gd")
const SandboxQueryResultType = preload("res://src/core/sandbox/sandbox_query_result.gd")

var _sandbox_port: SandboxCasePort = SandboxCasePortType.new()

func create_case_state(case_definition: Dictionary) -> DomainResult:
	var content: Variant = case_definition.get("content", null)
	if typeof(content) != TYPE_DICTIONARY:
		return DomainResultType.failure(&"task_case_invalid", "Task case requires content")
	var initial_state: Variant = Dictionary(content).get("initial_state", null)
	if typeof(initial_state) != TYPE_DICTIONARY:
		return DomainResultType.failure(&"task_case_invalid", "Task case requires an initial Sandbox state")
	var admitted: DomainResult = _admit_projection(Dictionary(initial_state))
	if not admitted.is_success():
		return admitted
	var state: SandboxCaseState = admitted.value()
	return DomainResultType.success(state.projection())

func query(state: Dictionary, call: Dictionary) -> DomainResult:
	var admitted: DomainResult = _admit_projection(state)
	if not admitted.is_success():
		return admitted
	var raw: SandboxQueryResult = _sandbox_port.query(
		admitted.value(), _query_call(call))
	if raw.is_produced():
		return DomainResultType.success(raw.value())
	if raw.is_domain_rejected():
		return DomainResultType.failure(
			&"query_unavailable", _reason_message(raw.reason(), raw.detail()))
	return DomainResultType.failure(raw.reason(), raw.detail())

func act(state: Dictionary, call: Dictionary) -> DomainResult:
	var admitted: DomainResult = _admit_projection(state)
	if not admitted.is_success():
		return admitted
	var raw: SandboxActionResult = _sandbox_port.act(
		admitted.value(), _action_call(call))
	if raw.is_transitioned():
		return DomainResultType.success({
			"state": raw.state().projection(),
			"observation": raw.observation(),
		})
	if raw.is_domain_rejected():
		return DomainResultType.failure(
			&"action_rejected", _reason_message(raw.reason(), raw.detail()))
	return DomainResultType.failure(raw.reason(), raw.detail())

func observe(state: Dictionary) -> DomainResult:
	var admitted: DomainResult = _admit_projection(state)
	if not admitted.is_success():
		return admitted
	var raw: SandboxQueryResult = _sandbox_port.observe(admitted.value())
	if raw.is_produced():
		return DomainResultType.success(raw.observation())
	if raw.is_domain_rejected():
		return DomainResultType.failure(
			&"query_rejected", _reason_message(raw.reason(), raw.detail()))
	return DomainResultType.failure(raw.reason(), raw.detail())

func _admit_projection(projection: Dictionary) -> DomainResult:
	var admitted: DomainResult = _sandbox_port.create_case_state(projection.duplicate(true))
	if not admitted.is_success():
		return DomainResultType.failure(admitted.error_code(), admitted.error_message())
	var state: Variant = admitted.value()
	if not state is SandboxCaseStateType or not is_instance_valid(state):
		return DomainResultType.failure(&"sandbox_state_invalid", "Sandbox admission returned no state")
	return DomainResultType.success(state)

func _reason_message(reason: StringName, detail: String) -> String:
	return "%s: %s" % [String(reason), detail]

func _action_call(call: Dictionary) -> Dictionary:
	var action_id: Variant = call.get("action_id", "")
	if String(action_id) != "turn":
		return {"action_id": action_id}
	var parameters: Dictionary = Dictionary(call.get("parameters", {}))
	return {"action_id": action_id, "direction": parameters.get("direction", "")}

func _query_call(call: Dictionary) -> Dictionary:
	var query_id: Variant = call.get("query_id", "")
	if String(query_id) != "front_sensor_matches_color":
		return {"query_id": query_id}
	var parameters: Dictionary = Dictionary(call.get("parameters", {}))
	return {"query_id": query_id, "colour": parameters.get("colour", "")}
