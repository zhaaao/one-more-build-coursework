class_name CourseworkTaskExecutionContract
extends RefCounted

## Immutable Task-owned input contract for one admitted public execution.
## Example: `var port_result: DomainResult = contract.create_authoring_run_port()`.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CourseworkPublicRunContractType = preload("res://src/core/task/coursework_public_run_contract.gd")
const CourseworkGvetRunnerType = preload("res://src/core/gvet/coursework_gvet_runner.gd")
const SemanticDiagnosticValidatorType = preload("res://src/core/gvet/semantic_diagnostic_validator.gd")
const CourseworkCaseExecutorType = preload("res://src/core/gvet/coursework_case_executor.gd")
const CourseworkPublicEqualityAssertionPortType = preload("res://src/core/gvet/coursework_public_equality_assertion_port.gd")
const CourseworkTaskSandboxPortType = preload("res://src/core/task/coursework_task_sandbox_port.gd")
const AuthoringRunPortType = preload("res://src/core/authoring/authoring_run_port.gd")

var _task_id: String = ""
var _day_index: int = 0
var _graph_model_contract: Dictionary = {}
var _starting_graph: Dictionary = {}
var _authoring_registry: Dictionary = {}
var _ordered_public_cases: Array[Dictionary] = []
var _content_digest: String = ""

static func create(
	task_id: String, day_index: int, graph_model_contract: Dictionary,
	starting_graph: Dictionary, authoring_registry: Dictionary,
	ordered_public_cases: Array, content_digest: String
) -> DomainResult:
	if task_id.is_empty() or day_index < 1 or graph_model_contract.is_empty() \
			or starting_graph.is_empty() or authoring_registry.is_empty() \
			or ordered_public_cases.is_empty() or content_digest.is_empty():
		return DomainResultType.failure(&"task_execution_contract_invalid", "Task execution contract requires complete admitted inputs")
	var cases: Array[Dictionary] = []
	var seen: Dictionary = {}
	for raw_case: Variant in ordered_public_cases:
		if typeof(raw_case) != TYPE_DICTIONARY:
			return DomainResultType.failure(&"task_execution_contract_invalid", "Task public case must be a Dictionary")
		var case_definition: Dictionary = Dictionary(raw_case)
		var case_id: String = String(case_definition.get("case_id", ""))
		if case_id.is_empty() or seen.has(case_id):
			return DomainResultType.failure(&"task_execution_contract_invalid", "Task public case identity must be ordered and unique")
		seen[case_id] = true
		cases.append(case_definition.duplicate(true))
	var result: CourseworkTaskExecutionContract = CourseworkTaskExecutionContract.new()
	result._task_id = task_id
	result._day_index = day_index
	result._graph_model_contract = graph_model_contract.duplicate(true)
	result._starting_graph = starting_graph.duplicate(true)
	result._authoring_registry = authoring_registry.duplicate(true)
	result._ordered_public_cases = cases
	result._content_digest = content_digest
	return DomainResultType.success(result)

## Returns the immutable installed Task identity.
## Example: `var id: String = contract.task_id()`.
func task_id() -> String:
	return _task_id

## Returns the Task's ordered coursework day.
## Example: `var day: int = contract.day_index()`.
func day_index() -> int:
	return _day_index

## Returns a detached GraphModel ABI contract.
## Example: `var graph: Dictionary = contract.graph_model_contract()`.
func graph_model_contract() -> Dictionary:
	return _graph_model_contract.duplicate(true)

## Returns the detached installed starting graph.
## Example: `var graph: Dictionary = contract.starting_graph()`.
func starting_graph() -> Dictionary:
	return _starting_graph.duplicate(true)

## Returns the detached Authoring registry descriptor.
## Example: `var registry: Dictionary = contract.authoring_registry()`.
func authoring_registry() -> Dictionary:
	return _authoring_registry.duplicate(true)

## Returns the admitted registry as a detached projection for composition ports.
## Example: `var registry := contract.authoring_registry_projection()`.
func authoring_registry_projection() -> Dictionary:
	return authoring_registry()

## Returns detached public cases in deterministic installed order.
## Example: `var cases: Array[Dictionary] = contract.ordered_public_cases()`.
func ordered_public_cases() -> Array[Dictionary]:
	return _ordered_public_cases.duplicate(true)

## Returns the canonical digest of this Task's public-case content.
## Example: `assert_false(contract.content_digest().is_empty())`.
func content_digest() -> String:
	return _content_digest

## Creates a fresh public-run façade over this immutable Task contract.
## Example: `var result: DomainResult = contract.create_public_run_contract()`.
func create_public_run_contract() -> DomainResult:
	return DomainResultType.success(CourseworkPublicRunContractType.new(self))

## Creates a fresh Authoring Run adapter with independent collaborators.
## Example: `var result: DomainResult = contract.create_authoring_run_port()`.
func create_authoring_run_port() -> DomainResult:
	var executor: CourseworkCaseExecutor = CourseworkCaseExecutorType.new()
	var program_result: DomainResult = executor.create_node_semantics_program(
		authoring_registry(), CourseworkPublicEqualityAssertionPortType.new())
	if not program_result.is_success():
		return program_result
	var runner: CourseworkGvetRunner = CourseworkGvetRunnerType.new(
		SemanticDiagnosticValidatorType.new(authoring_registry()), null,
		CourseworkTaskSandboxPortType.new(), executor, program_result.value())
	return DomainResultType.success(AuthoringRunPortType.new(runner))

## Returns the installed production Authoring registry descriptor.
## Example: `var registry: Dictionary = CourseworkTaskExecutionContract.production_authoring_registry()`.
static func production_authoring_registry() -> Dictionary:
	return {
		"registry_codec_version": "authoring_registry_v1", "resolved_locale_id": "en-GB",
		"categories": [_category("Start", 0), _category("Action", 1), _category("Query", 2), _category("Constant", 3), _category("Compare", 4), _category("Branch", 5), _category("Repeat", 6), _category("End", 7)],
		"variants": [_variant("flow.start", "Start", 0, [_port("next", 0, "output")]), _variant("flow.end", "End", 1, [_port("in", 0, "input")]), _variant("flow.branch.boolean", "Branch", 2, [_port("in", 0, "input"), _port("condition", 1, "input", "data", "Boolean"), _port("true", 2, "output"), _port("false", 3, "output")]), _variant("flow.repeat.bounded", "Repeat", 3, [_port("in", 0, "input"), _port("continue", 1, "input"), _port("body", 2, "output"), _port("done", 3, "output")]), _variant("value.constant.numeric", "Constant", 4, [_port("value", 0, "output", "data", "numeric")]), _variant("value.compare.numeric", "Compare", 5, [_port("left", 0, "input", "data", "numeric"), _port("right", 1, "input", "data", "numeric"), _port("result", 2, "output", "data", "Boolean")]), _variant("parcel.query.front_sensor_matches_color", "Query", 6, [_port("value", 0, "output", "data", "Boolean")]), _variant("parcel.query.path_is_clear", "Query", 7, [_port("value", 0, "output", "data", "Boolean")]), _variant("parcel.query.battery_units", "Query", 8, [_port("value", 0, "output", "data", "numeric")]), _variant("parcel.action.advance_conveyors", "Action", 9, [_port("in", 0, "input"), _port("next", 1, "output")]), _variant("parcel.action.charge", "Action", 10, [_port("in", 0, "input"), _port("next", 1, "output")]), _variant("parcel.action.drop_front", "Action", 11, [_port("in", 0, "input"), _port("next", 1, "output")]), _variant("parcel.action.move_forward", "Action", 12, [_port("in", 0, "input"), _port("next", 1, "output")]), _variant("parcel.action.pick_up_front", "Action", 13, [_port("in", 0, "input"), _port("next", 1, "output")]), _variant("parcel.action.turn", "Action", 14, [_port("in", 0, "input"), _port("next", 1, "output")])],
		"reasons": [], "trace_outcomes": [], "message_templates": [], "node_actions": [], "editor_controls": [],
	}

static func _category(category_id: String, order: int) -> Dictionary:
	return {"category_id": category_id, "registry_order": order, "title": category_id}

static func _variant(variant_id: String, category_id: String, order: int, ports: Array) -> Dictionary:
	return {"variant_id": variant_id, "category_id": category_id, "registry_order": order, "title": variant_id, "ports": ports, "parameters": [], "node_action_ids": [], "max_footprint_width": 1, "max_footprint_height": 1}

static func _port(port_id: String, order: int, direction: String, kind: String = "execution", data_type: String = "") -> Dictionary:
	var port: Dictionary = {"port_id": port_id, "registry_order": order, "direction": direction, "kind": kind, "maximum_connections": 1, "label": port_id}
	if kind == "data":
		port["data_type"] = data_type
	return port
