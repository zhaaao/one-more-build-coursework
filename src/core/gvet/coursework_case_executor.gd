class_name CourseworkCaseExecutor
extends RefCounted

## Fresh serial case orchestration and deterministic per-control-step data traversal.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const PreparedRunType = preload("res://src/core/gvet/prepared_run.gd")
const SandboxPortType = preload("res://src/core/gvet/coursework_sandbox_port.gd")
const RepeatFrameType = preload("res://src/core/gvet/coursework_repeat_frame.gd")
const RunLimitsType = preload("res://src/core/gvet/coursework_run_limits.gd")
const TraceEntryType = preload("res://src/core/gvet/coursework_trace_entry.gd")

## Story004 supplies concrete node semantics through this synchronous port.
class ExecutionProgramPort extends RefCounted:
	const ResultType = preload("res://src/foundation/domain_result.gd")

	## Returns authored control steps in execution order for one case.
	## Example: `return ResultType.success(control_steps)`.
	func control_steps(_graph: Dictionary, _case_definition: Dictionary) -> DomainResult:
		return ResultType.failure(&"case_execution_error", "control steps are not implemented")

	## Returns data roots bound to one control node's registered input ports.
	## Example: each item has `node_id`, `port_id`, and `registry_order`.
	func input_bindings(_control_step: Dictionary, _graph: Dictionary) -> DomainResult:
		return ResultType.failure(&"case_execution_error", "input bindings are not implemented")

	## Returns one data node's dependency bindings before that node evaluates.
	## Example: `return ResultType.success(dependency_bindings)`.
	func data_dependencies(_data_node_id: String, _graph: Dictionary) -> DomainResult:
		return ResultType.failure(&"case_execution_error", "data dependencies are not implemented")

	## Evaluates one data node after its ordered dependencies have completed.
	## Example: Query implementations call `sandbox_port.query(state, call)`.
	func evaluate_data(
		_data_node_id: String,
		_dependency_values: Array,
		_state: Dictionary,
		_sandbox_port: RefCounted,
		_graph: Dictionary
	) -> DomainResult:
		return ResultType.failure(&"case_execution_error", "data evaluation is not implemented")

	## Executes one control node from detached inputs and returns new state.
	## Example: return `{state = next_state, continue_case = true}`.
	func execute_control(
		_control_step: Dictionary,
		_input_values: Dictionary,
		_state: Dictionary,
		_sandbox_port: RefCounted,
		_graph: Dictionary
	) -> DomainResult:
		return ResultType.failure(&"case_execution_error", "control execution is not implemented")

## Delegates authored-order assertion evaluation without owning aggregation.
class AssertionEvaluationPort extends RefCounted:
	const ResultType = preload("res://src/foundation/domain_result.gd")

	## Evaluates every authored assertion and returns one transient outcome each.
	## Example: `return ResultType.success(assertion_outcomes)`.
	func evaluate_assertions(
		_assertions: Array,
		_state: Dictionary,
		_sandbox_port: RefCounted
	) -> DomainResult:
		return ResultType.failure(
			&"case_execution_error", "assertion evaluation is not implemented")

## Concrete deterministic behavior for the eight coursework node categories.
class NodeSemanticsProgram extends ExecutionProgramPort:
	const FrameType = preload("res://src/core/gvet/coursework_repeat_frame.gd")

	var _variants: Dictionary = {}
	var _assertion_port: AssertionEvaluationPort = null
	var _valid: bool = false

	func _init(
		authoring_registry: Dictionary = {},
		assertion_port: AssertionEvaluationPort = null
	) -> void:
		if assertion_port == null or not is_instance_valid(assertion_port):
			return
		_assertion_port = assertion_port
		if typeof(authoring_registry.get("variants", null)) != TYPE_ARRAY:
			return
		for raw_variant: Variant in authoring_registry["variants"]:
			if typeof(raw_variant) != TYPE_DICTIONARY:
				return
			var variant: Dictionary = raw_variant
			var variant_id: Variant = variant.get("variant_id", null)
			if typeof(variant_id) != TYPE_STRING or String(variant_id).is_empty() \
					or _variants.has(variant_id):
				return
			_variants[variant_id] = variant.duplicate(true)
		_valid = not _variants.is_empty() and _assertion_port != null

	## Returns true when the supplied Authoring registry can resolve variants.
	## Example: `assert(program.is_valid())`.
	func is_valid() -> bool:
		return _valid

	func control_steps(graph: Dictionary, _case_definition: Dictionary) -> DomainResult:
		var starts: Array[Dictionary] = []
		for raw_node: Variant in graph.get("nodes", []):
			if typeof(raw_node) == TYPE_DICTIONARY and _category(raw_node) == "Start":
				starts.append(Dictionary(raw_node))
		if starts.size() != 1:
			return _failure("validated graph must contain exactly one Start")
		var content: Variant = _case_definition.get("content", null)
		if typeof(content) != TYPE_DICTIONARY \
				or typeof(content.get("assertions", null)) != TYPE_ARRAY:
			return _failure("case assertions must be an authored array")
		return ResultType.success([_control_step(
			starts[0]["node_id"], "", [], content["assertions"])])

	func input_bindings(control_step: Dictionary, graph: Dictionary) -> DomainResult:
		return ResultType.success(_incoming_data_bindings(control_step["node_id"], graph))

	func data_dependencies(data_node_id: String, graph: Dictionary) -> DomainResult:
		return ResultType.success(_incoming_data_bindings(data_node_id, graph))

	func evaluate_data(
		data_node_id: String,
		dependency_values: Array,
		state: Dictionary,
		sandbox_port: RefCounted,
		graph: Dictionary
	) -> DomainResult:
		var node: Dictionary = _node(data_node_id, graph)
		var inputs: Dictionary = _dependency_dictionary(dependency_values)
		match _category(node):
			"Constant":
				return ResultType.success(_parameter(node, "value", null))
			"Query":
				return sandbox_port.query(state, _sandbox_call(node, "query_id", inputs))
			"Compare":
				return _compare(node, inputs)
			_:
				return _failure("only Constant, Query, and Compare are data nodes")

	func execute_control(
		control_step: Dictionary,
		input_values: Dictionary,
		state: Dictionary,
		sandbox_port: RefCounted,
		graph: Dictionary
	) -> DomainResult:
		var node: Dictionary = _node(control_step["node_id"], graph)
		match _category(node):
			"Start":
				return _traverse(node, "next", input_values, state, control_step, graph)
			"Branch":
				return _branch(node, input_values, state, control_step, graph)
			"Action":
				return _action(node, input_values, state, sandbox_port, control_step, graph)
			"Repeat":
				return _repeat(node, input_values, state, control_step, graph)
			"End":
				return _end(node, input_values, state, sandbox_port, control_step)
			_:
				return _failure("only control node categories can execute control flow")

	func _branch(
		node: Dictionary, inputs: Dictionary, state: Dictionary,
		step: Dictionary, graph: Dictionary
	) -> DomainResult:
		if typeof(inputs.get("condition", null)) != TYPE_BOOL:
			return _failure("Branch condition must be Boolean")
		var selected_port: String = "true" if inputs["condition"] else "false"
		return _traverse(node, selected_port, inputs, state, step, graph)

	func _action(
		node: Dictionary, inputs: Dictionary, state: Dictionary,
		sandbox_port: RefCounted, step: Dictionary, graph: Dictionary
	) -> DomainResult:
		var action_result: DomainResult = sandbox_port.act(
			state.duplicate(true), _sandbox_call(node, "action_id", inputs))
		if not action_result.is_success():
			if action_result.error_code() != &"action_rejected":
				return action_result
			var rejected: Dictionary = _node_result(node, inputs, "action_rejected")
			rejected["rejection"] = action_result.diagnostic()
			rejected["terminal_flow"] = "action_rejected"
			return _control_result(state, false, rejected)
		var accepted: Variant = action_result.value()
		if not _action_record_is_valid(accepted):
			return _failure("Sandbox Action accepted result is invalid")
		var action_record: Dictionary = accepted
		var selected: DomainResult = _selected_successor(node, "next", step, graph)
		if not selected.is_success():
			return selected
		var result: Dictionary = _node_result(node, inputs, "action_applied")
		result["observation"] = _detached(action_record["observation"])
		return _selected_control_result(action_record["state"], result, selected.value())

	func _repeat(
		node: Dictionary, inputs: Dictionary, state: Dictionary,
		step: Dictionary, graph: Dictionary
	) -> DomainResult:
		var frames: Array = Array(step.get("repeat_frames", [])).duplicate()
		var entry_port: String = String(step.get("entry_port_id", ""))
		var count: Variant = inputs.get("count", _parameter(node, "count", null))
		if typeof(count) != TYPE_INT or int(count) < 0:
			return _failure("Repeat count must be a non-negative integer")
		if entry_port == "in":
			return _enter_repeat(node, int(count), inputs, state, frames, step, graph)
		if entry_port == "continue":
			return _continue_repeat(node, inputs, state, frames, step, graph)
		return _failure("Repeat must be entered through in or continue")

	func _enter_repeat(
		node: Dictionary, count: int, inputs: Dictionary, state: Dictionary,
		frames: Array, step: Dictionary, graph: Dictionary
	) -> DomainResult:
		if count == 0:
			return _repeat_traverse(node, "done", inputs, state, frames, step, graph, -1)
		var frame_result: DomainResult = FrameType.create(node["node_id"], count)
		if not frame_result.is_success():
			return frame_result
		frames.append(frame_result.value())
		return _repeat_traverse(node, "body", inputs, state, frames, step, graph, 0)

	func _continue_repeat(
		node: Dictionary, inputs: Dictionary, state: Dictionary,
		frames: Array, step: Dictionary, graph: Dictionary
	) -> DomainResult:
		if frames.is_empty() or not frames[-1] is FrameType:
			return _failure("Repeat continue requires the active LIFO frame")
		var frame: CourseworkRepeatFrame = frames[-1]
		if not frame.is_valid() or frame.node_id() != node["node_id"]:
			return _failure("Repeat continue does not match the active LIFO frame")
		if frame.has_next_iteration():
			var advanced: DomainResult = frame.advance()
			frames[-1] = advanced.value()
			return _repeat_traverse(
				node, "body", inputs, state, frames, step, graph, frame.iteration() + 1)
		frames.pop_back()
		return _repeat_traverse(
			node, "done", inputs, state, frames, step, graph, frame.iteration())

	func _repeat_traverse(
		node: Dictionary, port_id: String, inputs: Dictionary, state: Dictionary,
		frames: Array, step: Dictionary, graph: Dictionary, iteration: int
	) -> DomainResult:
		var repeat_step: Dictionary = step.duplicate(true)
		repeat_step["repeat_frames"] = frames
		var selected: DomainResult = _selected_successor(node, port_id, repeat_step, graph)
		if not selected.is_success():
			return selected
		var result: Dictionary = _node_result(node, inputs, "repeat_%s" % port_id)
		result["repeat_depth"] = frames.size()
		result["repeat_iteration"] = iteration
		return _selected_control_result(state, result, selected.value())

	func _traverse(
		node: Dictionary, port_id: String, inputs: Dictionary, state: Dictionary,
		step: Dictionary, graph: Dictionary
	) -> DomainResult:
		var selected: DomainResult = _selected_successor(node, port_id, step, graph)
		if not selected.is_success():
			return selected
		return _selected_control_result(
			state, _node_result(node, inputs, "traverse_%s" % port_id), selected.value())

	func _end(
		node: Dictionary, inputs: Dictionary, state: Dictionary,
		sandbox_port: RefCounted, step: Dictionary
	) -> DomainResult:
		var assertions: Array = Array(step.get("assertions", [])).duplicate(true)
		var evaluated: DomainResult = _assertion_port.evaluate_assertions(
			assertions, state.duplicate(true), sandbox_port)
		if not evaluated.is_success() or typeof(evaluated.value()) != TYPE_ARRAY:
			return evaluated if not evaluated.is_success() \
				else _failure("assertion evaluator must return an array")
		var outcomes: Array = evaluated.value()
		if outcomes.size() != assertions.size():
			return _failure("assertion evaluator must return one outcome per assertion")
		var result: Dictionary = _node_result(node, inputs, "reached_end")
		result["assertion_results"] = outcomes.duplicate(true)
		result["terminal_flow"] = "reached_end"
		return _control_result(state, false, result)

	func _selected_successor(
		node: Dictionary, port_id: String, step: Dictionary, graph: Dictionary
	) -> DomainResult:
		var matches: Array[Dictionary] = []
		for raw_connection: Variant in graph.get("connections", []):
			if typeof(raw_connection) != TYPE_DICTIONARY:
				continue
			var connection: Dictionary = raw_connection
			if connection.get("source_node_id") == node["node_id"] \
					and connection.get("source_port_id") == port_id:
				matches.append(connection.duplicate(true))
		matches.sort_custom(_connection_less)
		if matches.size() != 1:
			return _failure("validated execution output must select exactly one connection")
		var selected: Dictionary = matches[0]
		return ResultType.success({
			"connection_id": selected["connection_id"],
			"control_step": _control_step(
				selected["target_node_id"], selected["target_port_id"],
				Array(step.get("repeat_frames", [])).duplicate(),
				Array(step.get("assertions", [])).duplicate(true)),
		})

	func _incoming_data_bindings(node_id: String, graph: Dictionary) -> Array[Dictionary]:
		var bindings: Array[Dictionary] = []
		for raw_connection: Variant in graph.get("connections", []):
			if typeof(raw_connection) != TYPE_DICTIONARY:
				continue
			var connection: Dictionary = raw_connection
			if connection.get("target_node_id") != node_id:
				continue
			var port: Dictionary = _port(node_id, connection["target_port_id"], graph)
			if port.get("kind") != "data" or port.get("direction") != "input":
				continue
			bindings.append({
				"node_id": connection["source_node_id"],
				"port_id": connection["target_port_id"],
				"registry_order": port["registry_order"],
			})
		return bindings

	func _compare(node: Dictionary, inputs: Dictionary) -> DomainResult:
		if not inputs.has("left") or not inputs.has("right"):
			return _failure("Compare requires left and right inputs")
		var left: Variant = inputs["left"]
		var right: Variant = inputs["right"]
		if typeof(left) != typeof(right):
			return _failure("Compare inputs must have the same type")
		var operator_id: String = String(_parameter(node, "operator", ""))
		match operator_id:
			"equal", "==": return ResultType.success(left == right)
			"not_equal", "!=": return ResultType.success(left != right)
			"less_than", "<": return _ordered_compare(left, right, "less")
			"less_or_equal", "<=": return _ordered_compare(left, right, "less_equal")
			"greater_than", ">": return _ordered_compare(left, right, "greater")
			"greater_or_equal", ">=": return _ordered_compare(left, right, "greater_equal")
			_: return _failure("Compare operator is not supported")

	func _ordered_compare(left: Variant, right: Variant, operation: String) -> DomainResult:
		if not [TYPE_INT, TYPE_FLOAT, TYPE_STRING].has(typeof(left)):
			return _failure("ordered Compare requires numeric or label inputs")
		match operation:
			"less": return ResultType.success(left < right)
			"less_equal": return ResultType.success(left <= right)
			"greater": return ResultType.success(left > right)
			"greater_equal": return ResultType.success(left >= right)
		return _failure("ordered Compare operation is invalid")

	func _selected_control_result(
		state: Dictionary, node_result: Dictionary, selection: Dictionary
	) -> DomainResult:
		node_result["selected_connection_id"] = selection["connection_id"]
		return _control_result(state, true, node_result, selection["control_step"])

	func _control_result(
		state: Dictionary, continue_case: bool, node_result: Dictionary,
		next_step: Variant = null
	) -> DomainResult:
		var result: Dictionary = {
			"state": state.duplicate(true),
			"continue_case": continue_case,
			"node_result": node_result.duplicate(true),
		}
		if next_step != null:
			result["next_control_step"] = Dictionary(next_step).duplicate(true)
		return ResultType.success(result)

	func _node_result(node: Dictionary, inputs: Dictionary, outcome: String) -> Dictionary:
		return {
			"node_id": node.get("node_id", ""),
			"category_id": _category(node),
			"inputs": inputs.duplicate(true),
			"observation": {},
			"selected_connection_id": "",
			"outcome": outcome,
			"terminal_flow": "in_progress",
		}

	func _sandbox_call(node: Dictionary, identity_parameter: String, inputs: Dictionary) -> Dictionary:
		var parameters: Dictionary = _parameter_map(node)
		return {
			"node_id": node.get("node_id", ""),
			identity_parameter: parameters.get(identity_parameter, ""),
			"inputs": inputs.duplicate(true),
			"parameters": parameters,
		}

	func _dependency_dictionary(values: Array) -> Dictionary:
		var result: Dictionary = {}
		for raw_value: Variant in values:
			if typeof(raw_value) == TYPE_DICTIONARY:
				result[raw_value["port_id"]] = _detached(raw_value["value"])
		return result

	func _parameter_map(node: Dictionary) -> Dictionary:
		var result: Dictionary = {}
		for raw_parameter: Variant in node.get("parameter_values", []):
			if typeof(raw_parameter) == TYPE_DICTIONARY:
				result[raw_parameter.get("parameter_id", "")] = _detached(
					raw_parameter.get("value"))
		return result

	func _parameter(node: Dictionary, parameter_id: String, fallback: Variant) -> Variant:
		return _parameter_map(node).get(parameter_id, fallback)

	func _node(node_id: String, graph: Dictionary) -> Dictionary:
		for raw_node: Variant in graph.get("nodes", []):
			if typeof(raw_node) == TYPE_DICTIONARY and raw_node.get("node_id") == node_id:
				return Dictionary(raw_node)
		return {}

	func _category(node: Dictionary) -> String:
		var variant: Dictionary = _variants.get(node.get("variant_id", ""), {})
		return String(variant.get("category_id", ""))

	func _port(node_id: String, port_id: String, graph: Dictionary) -> Dictionary:
		var node: Dictionary = _node(node_id, graph)
		var variant: Dictionary = _variants.get(node.get("variant_id", ""), {})
		for raw_port: Variant in variant.get("ports", []):
			if typeof(raw_port) == TYPE_DICTIONARY and raw_port.get("port_id") == port_id:
				return Dictionary(raw_port)
		return {}

	func _control_step(
		node_id: String, entry_port_id: String, frames: Array, assertions: Array
	) -> Dictionary:
		return {
			"node_id": node_id,
			"entry_port_id": entry_port_id,
			"repeat_frames": frames.duplicate(),
			"assertions": assertions.duplicate(true),
		}

	func _action_record_is_valid(value: Variant) -> bool:
		if typeof(value) != TYPE_DICTIONARY:
			return false
		var record: Dictionary = value
		return record.size() == 2 and record.has("state") and record.has("observation") \
			and typeof(record["state"]) == TYPE_DICTIONARY

	func _connection_less(left: Dictionary, right: Dictionary) -> bool:
		return _ordinal_less(left["connection_id"], right["connection_id"])

	func _ordinal_less(left: String, right: String) -> bool:
		var left_bytes: PackedByteArray = left.to_utf8_buffer()
		var right_bytes: PackedByteArray = right.to_utf8_buffer()
		for index: int in range(mini(left_bytes.size(), right_bytes.size())):
			if left_bytes[index] != right_bytes[index]:
				return left_bytes[index] < right_bytes[index]
		return left_bytes.size() < right_bytes.size()

	func _detached(value: Variant) -> Variant:
		if typeof(value) == TYPE_DICTIONARY:
			return Dictionary(value).duplicate(true)
		if typeof(value) == TYPE_ARRAY:
			return Array(value).duplicate(true)
		return value

	func _failure(message: String) -> DomainResult:
		return ResultType.failure(&"case_execution_error", message)

## Creates the concrete deterministic coursework node program.
## Example: `var program_result: DomainResult =
## executor.create_node_semantics_program(registry, assertion_port)`.
func create_node_semantics_program(
	authoring_registry: Dictionary,
	assertion_port: AssertionEvaluationPort
) -> DomainResult:
	var program: NodeSemanticsProgram = NodeSemanticsProgram.new(
		authoring_registry, assertion_port)
	if not program.is_valid():
		return _failure("authoring registry cannot construct node semantics")
	return DomainResultType.success(program)

## Executes every prepared case serially and returns transient testable records.
## Example: `var result := executor.execute_cases(prepared, sandbox, program)`.
func execute_cases(
	prepared_run: Variant,
	sandbox_port: Variant,
	program_port: Variant
) -> DomainResult:
	if not _dependencies_are_valid(prepared_run, sandbox_port, program_port):
		return _failure("executor requires valid PreparedRun, Sandbox, and program ports")
	var cap_result: DomainResult = RunLimitsType.step_cap(prepared_run.day_index())
	if not cap_result.is_success():
		return cap_result
	var step_cap: int = cap_result.value()
	var case_records: Array[Dictionary] = []
	var graph: Dictionary = prepared_run.graph_snapshot()
	for case_definition: Dictionary in prepared_run.case_roster():
		var case_result: DomainResult = _execute_case(
			case_definition, graph, sandbox_port, program_port, step_cap)
		if not case_result.is_success():
			return case_result
		case_records.append(case_result.value())
	return DomainResultType.success(case_records)

func _execute_case(
	case_definition: Dictionary,
	graph: Dictionary,
	sandbox_port: RefCounted,
	program_port: ExecutionProgramPort,
	step_cap: int = RunLimitsType.MAX_TRACE_STEPS
) -> DomainResult:
	var state_result: DomainResult = sandbox_port.create_case_state(case_definition)
	if not state_result.is_success() or typeof(state_result.value()) != TYPE_DICTIONARY:
		return _failure("Sandbox did not create fresh dictionary state")
	var state: Dictionary = state_result.value()
	var initial_state: Dictionary = state.duplicate(true)
	var steps_result: DomainResult = program_port.control_steps(graph, case_definition)
	if not steps_result.is_success() or typeof(steps_result.value()) != TYPE_ARRAY:
		return _failure("execution program did not provide control steps")
	var runtime_result: DomainResult = _execute_control_steps(
		state, steps_result.value(), graph, sandbox_port, program_port, step_cap)
	if not runtime_result.is_success():
		return runtime_result
	return DomainResultType.success(
		_case_record(case_definition, initial_state, runtime_result.value()))

func _execute_control_steps(
	state: Dictionary, raw_steps: Array, graph: Dictionary,
	sandbox_port: RefCounted, program_port: ExecutionProgramPort, step_cap: int
) -> DomainResult:
	var runtime: Dictionary = _new_case_runtime(state, raw_steps)
	while not runtime["pending_steps"].is_empty():
		if runtime["trace_entries"].size() >= step_cap:
			_mark_cap_failure(runtime)
			break
		var raw_step: Variant = runtime["pending_steps"].pop_front()
		if typeof(raw_step) != TYPE_DICTIONARY:
			return _failure("control steps must be dictionaries")
		var step_result: DomainResult = _execute_control_step(
			raw_step, runtime["state"], graph, sandbox_port, program_port,
			runtime["trace_entries"].size() + 1,
			step_cap - runtime["trace_entries"].size())
		if not step_result.is_success():
			return step_result
		var step_record: Dictionary = step_result.value()
		_append_step_record(runtime, step_record)
		if not step_record["continue_case"]:
			break
		if runtime["trace_entries"].size() >= step_cap:
			_mark_cap_failure(runtime)
			break
		if step_record.has("next_control_step"):
			runtime["pending_steps"] = [step_record["next_control_step"]]
	return DomainResultType.success(runtime)

func _new_case_runtime(state: Dictionary, steps: Array) -> Dictionary:
	return {
		"state": state.duplicate(true),
		"pending_steps": steps.duplicate(true),
		"evaluation_order": [],
		"data_results": [],
		"node_results": [],
		"selected_connections": [],
		"trace_entries": [],
		"terminal_flow": "in_progress",
		"ordinary_failure_code": "",
		"ordinary_failure_reason": "",
		"completed_steps": 0,
	}

func _append_step_record(runtime: Dictionary, step_record: Dictionary) -> void:
	runtime["state"] = step_record["state"]
	runtime["evaluation_order"].append_array(step_record["evaluation_order"])
	runtime["data_results"].append_array(step_record["data_results"])
	runtime["trace_entries"].append_array(step_record["trace_entries"])
	if step_record["control_evaluated"]:
		runtime["completed_steps"] += 1
	if not step_record.has("node_result"):
		_apply_runtime_failure(runtime, step_record)
		return
	var node_result: Dictionary = step_record["node_result"]
	runtime["node_results"].append(node_result)
	runtime["terminal_flow"] = node_result.get(
		"terminal_flow", runtime["terminal_flow"])
	var selected_id: String = String(node_result.get("selected_connection_id", ""))
	if not selected_id.is_empty():
		runtime["selected_connections"].append(selected_id)
	_apply_runtime_failure(runtime, step_record)

func _apply_runtime_failure(runtime: Dictionary, step_record: Dictionary) -> void:
	var code: String = String(step_record.get("ordinary_failure_code", ""))
	if code.is_empty():
		return
	runtime["ordinary_failure_code"] = code
	runtime["ordinary_failure_reason"] = step_record["ordinary_failure_reason"]
	if not step_record.has("node_result"):
		runtime["terminal_flow"] = code.to_lower()

func _case_record(
	case_definition: Dictionary, initial_state: Dictionary, runtime: Dictionary
) -> Dictionary:
	return {
		"case_id": _case_id(case_definition),
		"initial_state": initial_state,
		"final_state": Dictionary(runtime["state"]).duplicate(true),
		"completed_control_steps": runtime["completed_steps"],
		"data_evaluation_order": runtime["evaluation_order"],
		"data_results": runtime["data_results"],
		"node_results": runtime["node_results"],
		"selected_connections": runtime["selected_connections"],
		"trace": runtime["trace_entries"],
		"terminal_flow": runtime["terminal_flow"],
		"ordinary_failure_code": runtime["ordinary_failure_code"],
		"ordinary_failure_reason": runtime["ordinary_failure_reason"],
	}

func _execute_control_step(
	control_step: Dictionary,
	state: Dictionary,
	graph: Dictionary,
	sandbox_port: RefCounted,
	program_port: ExecutionProgramPort,
	first_step_number: int,
	available_steps: int
) -> DomainResult:
	var bindings_result: DomainResult = program_port.input_bindings(control_step, graph)
	var ordered_result: DomainResult = _ordered_bindings(bindings_result)
	if not ordered_result.is_success():
		return ordered_result
	var cache: Dictionary = {}
	var visiting: Dictionary = {}
	var input_values: Dictionary = {}
	var evaluation_order: Array[String] = []
	var data_results: Array[Dictionary] = []
	var trace_entries: Array[Dictionary] = []
	for binding: Dictionary in ordered_result.value():
		var value_result: DomainResult = _resolve_data_node(
			binding["node_id"], state, graph, sandbox_port, program_port,
			cache, visiting, evaluation_order, data_results, trace_entries,
			first_step_number, available_steps)
		if not value_result.is_success():
			return _resolve_partial_failure(
				value_result, state, evaluation_order, data_results, trace_entries)
		input_values[binding["port_id"]] = value_result.value()
	if trace_entries.size() >= available_steps:
		return _cap_partial_step(state, evaluation_order, data_results, trace_entries)
	return _execute_resolved_control(
		control_step, input_values, state, graph, sandbox_port, program_port,
		first_step_number, trace_entries, evaluation_order, data_results)

func _execute_resolved_control(
	control_step: Dictionary, input_values: Dictionary, state: Dictionary,
	graph: Dictionary, sandbox_port: RefCounted, program_port: ExecutionProgramPort,
	first_step_number: int, trace_entries: Array[Dictionary],
	evaluation_order: Array[String], data_results: Array[Dictionary]
) -> DomainResult:
	var control_result: DomainResult = program_port.execute_control(
		control_step, input_values, state.duplicate(true), sandbox_port, graph)
	var validated_result: DomainResult = _validated_control_result(
		control_result, evaluation_order, data_results)
	if not validated_result.is_success():
		return validated_result
	var validated: Dictionary = validated_result.value()
	var trace_result: DomainResult = _control_trace(
		first_step_number + trace_entries.size(), control_step, input_values, validated)
	if not trace_result.is_success():
		return trace_result
	trace_entries.append(trace_result.value())
	validated["trace_entries"] = trace_entries
	validated["control_evaluated"] = true
	return DomainResultType.success(_apply_control_failure(validated))

func _resolve_data_node(
	node_id: String, state: Dictionary, graph: Dictionary,
	sandbox_port: RefCounted, program_port: ExecutionProgramPort,
	cache: Dictionary, visiting: Dictionary, evaluation_order: Array[String],
	data_results: Array[Dictionary], trace_entries: Array[Dictionary],
	first_step_number: int, available_steps: int
) -> DomainResult:
	if cache.has(node_id):
		return DomainResultType.success(_detached_value(cache[node_id]))
	if node_id.is_empty() or visiting.has(node_id):
		return _failure("data dependency traversal reached an invalid cycle or identity")
	visiting[node_id] = true
	var dependencies_result: DomainResult = program_port.data_dependencies(node_id, graph)
	var ordered_result: DomainResult = _ordered_bindings(dependencies_result)
	if not ordered_result.is_success():
		visiting.erase(node_id)
		return ordered_result
	var dependency_result: DomainResult = _resolve_data_dependencies(
		ordered_result.value(), state, graph, sandbox_port, program_port, cache,
		visiting, evaluation_order, data_results, trace_entries,
		first_step_number, available_steps)
	if not dependency_result.is_success():
		visiting.erase(node_id)
		return dependency_result
	return _finish_data_evaluation(
		node_id, dependency_result.value(), state, graph, sandbox_port, program_port,
		cache, visiting, evaluation_order, data_results, trace_entries,
		first_step_number, available_steps)

func _finish_data_evaluation(
	node_id: String, dependency_values: Array, state: Dictionary, graph: Dictionary,
	sandbox_port: RefCounted, program_port: ExecutionProgramPort,
	cache: Dictionary, visiting: Dictionary, evaluation_order: Array[String],
	data_results: Array[Dictionary], trace_entries: Array[Dictionary],
	first_step_number: int, available_steps: int
) -> DomainResult:
	if trace_entries.size() >= available_steps:
		visiting.erase(node_id)
		return DomainResultType.failure(
			&"execution_step_cap", "required successor exceeds the case step cap")
	var value_result: DomainResult = program_port.evaluate_data(
		node_id, dependency_values, state.duplicate(true), sandbox_port, graph)
	visiting.erase(node_id)
	var trace_result: DomainResult = _data_trace(
		first_step_number + trace_entries.size(), node_id, dependency_values, value_result)
	if not trace_result.is_success():
		return trace_result
	trace_entries.append(trace_result.value())
	if not value_result.is_success():
		return value_result
	cache[node_id] = _detached_value(value_result.value())
	evaluation_order.append(node_id)
	data_results.append({"node_id": node_id, "value": _detached_value(cache[node_id])})
	return DomainResultType.success(_detached_value(cache[node_id]))

func _resolve_data_dependencies(
	bindings: Array, state: Dictionary, graph: Dictionary,
	sandbox_port: RefCounted, program_port: ExecutionProgramPort,
	cache: Dictionary, visiting: Dictionary, evaluation_order: Array[String],
	data_results: Array[Dictionary], trace_entries: Array[Dictionary],
	first_step_number: int, available_steps: int
) -> DomainResult:
	var dependency_values: Array = []
	for binding: Dictionary in bindings:
		var child_result: DomainResult = _resolve_data_node(
			binding["node_id"], state, graph, sandbox_port, program_port,
			cache, visiting, evaluation_order, data_results, trace_entries,
			first_step_number, available_steps)
		if not child_result.is_success():
			return child_result
		dependency_values.append({
			"port_id": binding["port_id"],
			"value": child_result.value(),
		})
	return DomainResultType.success(dependency_values)

func _ordered_bindings(raw_result: Variant) -> DomainResult:
	if not raw_result is DomainResultType or not raw_result.is_success():
		return raw_result if raw_result is DomainResultType else _failure("binding result is invalid")
	if typeof(raw_result.value()) != TYPE_ARRAY:
		return _failure("bindings must be an array")
	var bindings: Array[Dictionary] = []
	var port_ids: Dictionary = {}
	for raw_binding: Variant in Array(raw_result.value()):
		if not _binding_is_valid(raw_binding):
			return _failure("data binding is invalid")
		var binding: Dictionary = raw_binding
		if port_ids.has(binding["port_id"]):
			return _failure("data binding port identities must be unique")
		port_ids[binding["port_id"]] = true
		bindings.append(binding.duplicate(true))
	bindings.sort_custom(_binding_less)
	return DomainResultType.success(bindings)

func _validated_control_result(
	raw_result: Variant, order: Array[String], data_results: Array[Dictionary]
) -> DomainResult:
	if not raw_result is DomainResultType or not raw_result.is_success():
		return raw_result if raw_result is DomainResultType else _failure("control result is invalid")
	if typeof(raw_result.value()) != TYPE_DICTIONARY:
		return _failure("control result must be a dictionary")
	var record: Dictionary = raw_result.value()
	if not _control_result_keys_are_valid(record):
		return _failure("control result fields are invalid")
	if typeof(record["state"]) != TYPE_DICTIONARY or typeof(record["continue_case"]) != TYPE_BOOL:
		return _failure("control result field types are invalid")
	var validated: Dictionary = {
		"state": Dictionary(record["state"]).duplicate(true),
		"continue_case": record["continue_case"],
		"evaluation_order": order.duplicate(),
		"data_results": data_results.duplicate(true),
	}
	if record.has("next_control_step"):
		if typeof(record["next_control_step"]) != TYPE_DICTIONARY:
			return _failure("next control step must be a dictionary")
		validated["next_control_step"] = Dictionary(record["next_control_step"]).duplicate(true)
	if record.has("node_result"):
		if typeof(record["node_result"]) != TYPE_DICTIONARY:
			return _failure("node result must be a dictionary")
		validated["node_result"] = Dictionary(record["node_result"]).duplicate(true)
	return DomainResultType.success(validated)

func _resolve_partial_failure(
	failure: DomainResult, state: Dictionary, order: Array[String],
	data_results: Array[Dictionary], trace_entries: Array[Dictionary]
) -> DomainResult:
	if failure.error_code() == &"execution_step_cap":
		return _cap_partial_step(state, order, data_results, trace_entries)
	if failure.error_code() != &"query_unavailable":
		return failure
	var reason: String = failure.error_message()
	if reason.is_empty():
		reason = "Query result is unavailable"
	return DomainResultType.success(_partial_step_record(
		state, order, data_results, trace_entries, "QUERY_UNAVAILABLE", reason))

func _cap_partial_step(
	state: Dictionary, order: Array[String], data_results: Array[Dictionary],
	trace_entries: Array[Dictionary]
) -> DomainResult:
	var reason: String = "required successor exceeds S_cap; successor did not execute"
	if not _mark_last_trace_failure(trace_entries, "EXECUTION_STEP_CAP", reason):
		return _failure("step cap was reached without an evaluated node")
	return DomainResultType.success(_partial_step_record(
		state, order, data_results, trace_entries, "EXECUTION_STEP_CAP", reason))

func _partial_step_record(
	state: Dictionary, order: Array[String], data_results: Array[Dictionary],
	trace_entries: Array[Dictionary], code: String, reason: String
) -> Dictionary:
	return {
		"state": state.duplicate(true),
		"continue_case": false,
		"evaluation_order": order.duplicate(),
		"data_results": data_results.duplicate(true),
		"trace_entries": trace_entries.duplicate(true),
		"control_evaluated": false,
		"ordinary_failure_code": code,
		"ordinary_failure_reason": reason,
	}

func _data_trace(
	step_number: int, node_id: String, dependency_values: Array,
	value_result: DomainResult
) -> DomainResult:
	var consumed: Dictionary = _dependency_value_map(dependency_values)
	var succeeded: bool = value_result.is_success()
	var reason: String = "data node produced a deterministic value"
	var code: String = ""
	if not succeeded:
		code = String(value_result.error_code()).to_upper()
		reason = value_result.error_message()
		if reason.is_empty():
			reason = "data node evaluation failed"
	return _make_trace(
		step_number, node_id, "data", "", consumed, succeeded,
		value_result.value(), "", {}, "value_produced" if succeeded else
		"evaluation_failed", code, reason)

func _control_trace(
	step_number: int, control_step: Dictionary, input_values: Dictionary,
	validated: Dictionary
) -> DomainResult:
	var node_result: Dictionary = validated.get("node_result", {})
	var node_id: String = String(node_result.get(
		"node_id", _control_node_id(control_step)))
	var category_id: String = String(node_result.get("category_id", ""))
	var selected_id: String = String(node_result.get("selected_connection_id", ""))
	var outcome: String = String(node_result.get("outcome", "control_evaluated"))
	var reason: String = outcome.replace("_", " ")
	var consumed: Dictionary = input_values.duplicate(true)
	if typeof(node_result.get("inputs", null)) == TYPE_DICTIONARY:
		consumed = Dictionary(node_result["inputs"]).duplicate(true)
	return _make_trace(
		step_number, node_id, "control", category_id, consumed, false, null,
		selected_id, node_result.get("observation", {}), outcome, "", reason)

func _make_trace(
	step_number: int, node_id: String, node_kind: String, category_id: String,
	consumed: Dictionary, has_value: bool, value: Variant,
	connection_id: String, observation: Variant, outcome: String,
	reason_code: String, reason: String
) -> DomainResult:
	var created: DomainResult = TraceEntryType.create(
		step_number, node_id, node_kind, category_id, consumed, has_value, value,
		connection_id, connection_id, observation, outcome, reason_code, reason)
	if not created.is_success():
		return created
	var entry: CourseworkTraceEntry = created.value()
	return DomainResultType.success(entry.to_dictionary())

func _apply_control_failure(record: Dictionary) -> Dictionary:
	if not record.has("node_result"):
		return record
	var failure: Dictionary = _ordinary_control_failure(record["node_result"])
	if failure.is_empty():
		return record
	var traces: Array = record["trace_entries"]
	if not _mark_last_trace_failure(traces, failure["code"], failure["reason"]):
		return record
	record["trace_entries"] = traces
	record["continue_case"] = false
	record["ordinary_failure_code"] = failure["code"]
	record["ordinary_failure_reason"] = failure["reason"]
	return record

func _ordinary_control_failure(node_result: Dictionary) -> Dictionary:
	if node_result.get("terminal_flow") == "action_rejected":
		var diagnostic: Dictionary = node_result.get("rejection", {})
		var reason: String = String(diagnostic.get("message", "Action was rejected"))
		return {"code": "ACTION_REJECTED", "reason": reason}
	for raw_outcome: Variant in node_result.get("assertion_results", []):
		if typeof(raw_outcome) != TYPE_DICTIONARY:
			continue
		var outcome: Dictionary = raw_outcome
		if typeof(outcome.get("pass", null)) == TYPE_BOOL and not outcome["pass"]:
			return {
				"code": "ASSERTION_FAILURE",
				"reason": _assertion_failure_reason(outcome),
			}
	return {}

func _assertion_failure_reason(outcome: Dictionary) -> String:
	var assertion_id: String = String(outcome.get("assertion_id", "assertion"))
	return "%s failed: expected %s, observed %s" % [
		assertion_id, str(outcome.get("expected")), str(outcome.get("observed"))]

func _mark_cap_failure(runtime: Dictionary) -> void:
	var reason: String = "required successor exceeds S_cap; successor did not execute"
	var traces: Array = runtime["trace_entries"]
	if _mark_last_trace_failure(traces, "EXECUTION_STEP_CAP", reason):
		runtime["trace_entries"] = traces
		runtime["terminal_flow"] = "execution_step_cap"
		runtime["ordinary_failure_code"] = "EXECUTION_STEP_CAP"
		runtime["ordinary_failure_reason"] = reason

func _mark_last_trace_failure(
	trace_entries: Array, code: String, reason: String
) -> bool:
	if trace_entries.is_empty():
		return false
	var current: CourseworkTraceEntry = TraceEntryType.new(trace_entries[-1])
	if not current.is_valid():
		return false
	var changed: DomainResult = current.with_failure(code, reason)
	if not changed.is_success():
		return false
	var replacement: CourseworkTraceEntry = changed.value()
	trace_entries[-1] = replacement.to_dictionary()
	return true

func _dependency_value_map(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for raw_value: Variant in values:
		if typeof(raw_value) == TYPE_DICTIONARY:
			result[raw_value.get("port_id", "")] = _detached_value(
				raw_value.get("value"))
	return result

func _control_node_id(control_step: Dictionary) -> String:
	return String(control_step.get(
		"node_id", control_step.get("control_node_id", "")))

func _control_result_keys_are_valid(record: Dictionary) -> bool:
	if not record.has("state") or not record.has("continue_case"):
		return false
	var allowed: Array[String] = [
		"state", "continue_case", "next_control_step", "node_result"]
	for raw_key: Variant in record.keys():
		if typeof(raw_key) != TYPE_STRING or not allowed.has(String(raw_key)):
			return false
	return true

func _dependencies_are_valid(prepared_run: Variant, sandbox_port: Variant, program_port: Variant) -> bool:
	return prepared_run is PreparedRunType and is_instance_valid(prepared_run) and prepared_run.is_valid() \
		and sandbox_port is SandboxPortType and is_instance_valid(sandbox_port) \
		and program_port is ExecutionProgramPort and is_instance_valid(program_port)

func _binding_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var binding: Dictionary = value
	return _has_exact_keys(binding, ["node_id", "port_id", "registry_order"]) \
		and typeof(binding["node_id"]) == TYPE_STRING and not String(binding["node_id"]).is_empty() \
		and typeof(binding["port_id"]) == TYPE_STRING and not String(binding["port_id"]).is_empty() \
		and typeof(binding["registry_order"]) == TYPE_INT and int(binding["registry_order"]) >= 0

func _binding_less(left: Dictionary, right: Dictionary) -> bool:
	if left["registry_order"] != right["registry_order"]:
		return left["registry_order"] < right["registry_order"]
	return _ordinal_less(left["port_id"], right["port_id"])

func _ordinal_less(left: String, right: String) -> bool:
	var left_bytes: PackedByteArray = left.to_utf8_buffer()
	var right_bytes: PackedByteArray = right.to_utf8_buffer()
	for index: int in range(mini(left_bytes.size(), right_bytes.size())):
		if left_bytes[index] != right_bytes[index]:
			return left_bytes[index] < right_bytes[index]
	return left_bytes.size() < right_bytes.size()

func _detached_value(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		return Dictionary(value).duplicate(true)
	if typeof(value) == TYPE_ARRAY:
		return Array(value).duplicate(true)
	return value

func _case_id(case_definition: Dictionary) -> String:
	return String(case_definition.get("case_id", case_definition.get("test_case_id", "")))

func _has_exact_keys(dictionary: Dictionary, fields: Array[String]) -> bool:
	if dictionary.size() != fields.size():
		return false
	for raw_key: Variant in dictionary.keys():
		if typeof(raw_key) != TYPE_STRING or not fields.has(String(raw_key)):
			return false
	return true

func _failure(message: String) -> DomainResult:
	return DomainResultType.failure(&"case_execution_error", message)
