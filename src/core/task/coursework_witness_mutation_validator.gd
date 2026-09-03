class_name CourseworkWitnessMutationValidator
extends RefCounted

## Development-only deterministic proof that the five retained Task witnesses
## pass their public rosters and that every public case has a non-vacuous
## executed failing mutation. Runtime systems never consume this proof.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CourseworkTaskCatalogType = preload("res://src/core/task/coursework_task_catalog.gd")
const CourseworkTaskSandboxPortType = preload("res://src/core/task/coursework_task_sandbox_port.gd")
const CourseworkRunInputType = preload("res://src/core/gvet/coursework_run_input.gd")
const CourseworkGvetRunnerType = preload("res://src/core/gvet/coursework_gvet_runner.gd")
const CourseworkCaseExecutorType = preload("res://src/core/gvet/coursework_case_executor.gd")
const SemanticDiagnosticValidatorType = preload("res://src/core/gvet/semantic_diagnostic_validator.gd")
const CourseworkRunLimitsType = preload("res://src/core/gvet/coursework_run_limits.gd")
const CourseworkTaskExecutionContractType = preload("res://src/core/task/coursework_task_execution_contract.gd")
const CourseworkPublicEqualityAssertionPortType = preload("res://src/core/gvet/coursework_public_equality_assertion_port.gd")

const _EXPECTED_WITNESSES: Array[Dictionary] = [
	{"nodes": 4, "connections": 3, "edits": 2, "steps": 4, "cap": 40},
	{"nodes": 7, "connections": 6, "edits": 4, "steps": 5, "cap": 48},
	{"nodes": 7, "connections": 8, "edits": 8, "steps": 15, "cap": 56},
	{"nodes": 9, "connections": 8, "edits": 10, "steps": 7, "cap": 64},
	{"nodes": 13, "connections": 14, "edits": 23, "steps": 18, "cap": 72},
]

class CapFixtureProgram extends CourseworkCaseExecutorType.ExecutionProgramPort:
	var executed_nodes: Array[String] = []
	var step_count: int = 0

	func _init(candidate_step_count: int) -> void:
		step_count = candidate_step_count

	func control_steps(_graph: Dictionary, case_definition: Dictionary) -> DomainResult:
		var steps: Array[Dictionary] = []
		for index: int in range(step_count):
			steps.append({"node_id": "cap.%03d" % (index + 1), "category_id": "Action", "case_id": case_definition["case_id"]})
		return ResultType.success(steps)

	func input_bindings(_control_step: Dictionary, _graph: Dictionary) -> DomainResult:
		return ResultType.success([])

	func data_dependencies(_data_node_id: String, _graph: Dictionary) -> DomainResult:
		return ResultType.success([])

	func evaluate_data(_data_node_id: String, _dependency_values: Array, _state: Dictionary, _sandbox_port: RefCounted, _graph: Dictionary) -> DomainResult:
		return ResultType.failure(&"case_execution_error", "cap fixture has no data nodes")

	func execute_control(control_step: Dictionary, input_values: Dictionary, state: Dictionary, _sandbox_port: RefCounted, _graph: Dictionary) -> DomainResult:
		executed_nodes.append(String(control_step["node_id"]))
		return ResultType.success({"state": state.duplicate(true), "continue_case": true, "node_result": {"node_id": control_step["node_id"], "category_id": "Action", "inputs": input_values.duplicate(true), "observation": {}, "selected_connection_id": "", "outcome": "action_evaluated", "terminal_flow": "in_progress", "assertion_results": []}})

## Executes the complete retained witness/mutation proof and returns detached
## evidence. Example: `var proof_result: DomainResult = validator.validate()`.
func validate() -> DomainResult:
	var days: Array[Dictionary] = _task_days()
	if days.size() != 5:
		return _failure("exactly five Task days are required")
	var structures: Array[Dictionary] = []
	var negative_edges: Array[Dictionary] = []
	var witnesses: Array[Dictionary] = []
	var mutations: Array[Dictionary] = []
	for offset: int in days.size():
		var day: Dictionary = days[offset]
		var structure: DomainResult = _verify_structure(day)
		if not structure.is_success():
			return structure
		structures.append(structure.value())
		var negative: DomainResult = _verify_negative_edges(day)
		if not negative.is_success():
			return negative
		negative_edges.append_array(negative.value())
		var witness: DomainResult = _run_witness(day, offset + 1)
		if not witness.is_success():
			return witness
		witnesses.append(witness.value())
		var mutated: DomainResult = _run_case_mutations(day, offset + 1)
		if not mutated.is_success():
			return mutated
		for record: Dictionary in mutated.value():
			mutations.append(record)
	if mutations.size() != 36:
		return _failure("the mutation proof must cover all 36 public cases")
	var ac1_negative_evidence: DomainResult = _ac1_negative_evidence(days)
	if not ac1_negative_evidence.is_success():
		return ac1_negative_evidence
	return DomainResultType.success({
		"witnesses": witnesses.duplicate(true), "mutations": mutations.duplicate(true),
		"structures": structures.duplicate(true), "negative_edges": negative_edges.duplicate(true),
		"ac1_negative_evidence": ac1_negative_evidence.value(),
	})

func _task_days() -> Array[Dictionary]:
	var days: Array[Dictionary] = []
	var day1_day2_content: Array[Dictionary] = _dictionary_array(CourseworkTaskCatalogType.day1_day2_content())
	for day: Dictionary in day1_day2_content:
		days.append(day.duplicate(true))
	days.append(CourseworkTaskCatalogType.day3_content())
	days.append(CourseworkTaskCatalogType.day4_content())
	days.append(CourseworkTaskCatalogType.day5_content())
	return days

func _dictionary_array(value: Variant) -> Array[Dictionary]:
	if typeof(value) != TYPE_ARRAY:
		return []
	var boundary: Array = value
	var result: Array[Dictionary] = []
	for item: Variant in boundary:
		if typeof(item) != TYPE_DICTIONARY:
			return []
		result.append(item)
	return result

func _run_witness(day: Dictionary, day_index: int) -> DomainResult:
	var witness: Dictionary = Dictionary(day.get("witness", {}))
	var expected: Dictionary = _EXPECTED_WITNESSES[day_index - 1]
	if not _witness_matches(witness, expected):
		return _failure("Day %d witness vector drifted" % day_index)
	var applied_edits: Array[Dictionary] = _dictionary_array(witness.get("edits", []))
	var graph: Dictionary = _execution_graph(_apply_witness_edits(day))
	var budget_result: DomainResult = _validate_witness_budget(day, witness, expected, graph, day_index, applied_edits.size())
	if not budget_result.is_success():
		return budget_result
	var cases: Array[Dictionary] = _execution_cases(_dictionary_array(day.get("public_cases", [])))
	var report_result: DomainResult = _run(day, graph, cases, "witness")
	if not report_result.is_success():
		return report_result
	return _witness_report_evidence(report_result.value(), day, expected, graph, cases, budget_result.value())

func _validate_witness_budget(day: Dictionary, witness: Dictionary, expected: Dictionary, graph: Dictionary, day_index: int, applied_edit_count: int) -> DomainResult:
	var cap_result: DomainResult = CourseworkRunLimitsType.step_cap(day_index)
	if not cap_result.is_success(): return _failure("Day %d could not resolve the GVET step cap" % day_index)
	var live_step_cap: int = int(cap_result.value())
	var authored_step_cap: int = int(witness.get("step_cap", -1))
	var edit_range: Dictionary = Dictionary(witness.get("passing_edit_range", {})).duplicate(true)
	var minimum: int = int(edit_range.get("minimum", -1))
	var maximum: int = int(edit_range.get("maximum", -1))
	var limits: Dictionary = Dictionary(day["limits"])
	if authored_step_cap != live_step_cap or applied_edit_count != int(witness.get("accepted_edit_count", -1)): return _failure("Day %d witness limits drifted" % day_index)
	if applied_edit_count < minimum or applied_edit_count > maximum: return _failure("Day %d witness edits exceed the authored passing range" % day_index)
	if graph["nodes"].size() > int(limits["node_limit"]): return _failure("Day %d witness exceeds Task node limit" % day_index)
	if graph["connections"].size() > int(limits["connection_budget"]): return _failure("Day %d witness exceeds Task connection budget" % day_index)
	if graph["nodes"].size() != int(expected["nodes"]) or graph["connections"].size() != int(expected["connections"]) or applied_edit_count != int(expected["edits"]): return _failure("Day %d witness vector drifted" % day_index)
	var margin: DomainResult = _validate_node_margin(graph["nodes"].size(), int(limits["node_limit"]))
	if not margin.is_success(): return margin
	return DomainResultType.success({"step_cap": live_step_cap, "authored_step_cap": authored_step_cap, "applied_edit_count": applied_edit_count, "authored_edit_count": int(witness["accepted_edit_count"]), "passing_edit_range": edit_range, "node_margin": margin.value()})

func _witness_report_evidence(report: CourseworkRunResult, day: Dictionary, expected: Dictionary, graph: Dictionary, cases: Array[Dictionary], live_limits: Dictionary) -> DomainResult:
	if not report.validation_pass() or not report.suite_pass(): return _failure("Day %d witness does not pass its complete roster" % int(day["day_index"]))
	var results: Array[CourseworkCaseResult] = report.case_results()
	if results.size() != cases.size(): return _failure("Day %d witness did not execute its complete roster" % int(day["day_index"]))
	var actual_max_steps: int = 0
	for result: CourseworkCaseResult in results:
		if not result.case_pass(): return _failure("Day %d witness has an ordinary case failure" % int(day["day_index"]))
		actual_max_steps = maxi(actual_max_steps, _dictionary_array(result.to_dictionary()["trace"]).size())
	if actual_max_steps != int(expected["steps"]): return _failure("Day %d witness trace vector drifted" % int(day["day_index"]))
	return DomainResultType.success({
		"day_index": int(day["day_index"]), "task_id": String(day["task_id"]),
		"case_count": cases.size(), "vector": expected.duplicate(true),
		"produced": {"nodes": graph["nodes"].size(), "connections": graph["connections"].size(), "edits": int(live_limits["applied_edit_count"]), "steps": actual_max_steps, "cap": int(live_limits["step_cap"])},
		"live_limits": live_limits.duplicate(true),
		"suite_pass": true,
	})

func _validate_node_margin(witness_nodes: int, candidate_limit: int) -> DomainResult:
	var required_margin: int = maxi(1, ceili(float(witness_nodes) * 0.10))
	var minimum_limit: int = maxi(4, witness_nodes + required_margin)
	if candidate_limit < minimum_limit:
		return _failure("candidate node limit does not preserve the witness margin")
	return DomainResultType.success({"witness_nodes": witness_nodes, "required_margin": required_margin, "minimum_node_limit": minimum_limit, "candidate_limit": candidate_limit})

func _ac1_negative_evidence(days: Array[Dictionary]) -> DomainResult:
	var day_one: Dictionary = days[0]
	var witness: Dictionary = Dictionary(day_one["witness"])
	var expected: Dictionary = _EXPECTED_WITNESSES[0]
	var graph: Dictionary = _execution_graph(_apply_witness_edits(day_one))
	var edits: Array[Dictionary] = _dictionary_array(witness["edits"])
	var limits: Dictionary = Dictionary(day_one["limits"])
	var node_candidate: Dictionary = graph.duplicate(true)
	var nodes: Array = node_candidate["nodes"]
	while nodes.size() <= int(limits["node_limit"]): nodes.append({"node_id": "node.ac1.over.%d" % nodes.size(), "variant_id": "flow.end", "parameter_values": []})
	var connection_candidate: Dictionary = graph.duplicate(true)
	var connections: Array = connection_candidate["connections"]
	while connections.size() <= int(limits["connection_budget"]): connections.append({"connection_id": "connection.ac1.over.%d" % connections.size(), "source_node_id": "node.d1.start", "source_port_id": "next", "target_node_id": "node.d1.end", "target_port_id": "in"})
	var edit_candidate: Array[Dictionary] = edits.duplicate(true)
	while edit_candidate.size() <= int(Dictionary(witness["passing_edit_range"])["maximum"]): edit_candidate.append({"kind": "connect", "connection_id": "connection.ac1.edit.%d" % edit_candidate.size()})
	var node_result: DomainResult = _validate_witness_budget(day_one, witness, expected, node_candidate, 1, edits.size())
	var connection_result: DomainResult = _validate_witness_budget(day_one, witness, expected, connection_candidate, 1, edits.size())
	var edit_result: DomainResult = _validate_witness_budget(day_one, witness, expected, graph, 1, edit_candidate.size())
	var day_five: Dictionary = days[4]
	var day_five_graph: Dictionary = _execution_graph(_apply_witness_edits(day_five))
	var margin_14: DomainResult = _validate_node_margin(day_five_graph["nodes"].size(), 14)
	var margin_15: DomainResult = _validate_node_margin(day_five_graph["nodes"].size(), 15)
	var cap_fixture: DomainResult = _run_step_cap_fixture(day_five)
	if node_result.is_success() or connection_result.is_success() or edit_result.is_success() or margin_14.is_success() or not margin_15.is_success() or not cap_fixture.is_success(): return _failure("AC-008-01 negative evidence unexpectedly passed")
	return DomainResultType.success({"node_over_limit": {"candidate_nodes": nodes.size(), "node_limit": int(limits["node_limit"]), "rejected": true}, "connection_over_budget": {"candidate_connections": connections.size(), "connection_budget": int(limits["connection_budget"]), "rejected": true}, "edit_over_maximum": {"candidate_edits": edit_candidate.size(), "maximum": int(Dictionary(witness["passing_edit_range"])["maximum"]), "rejected": true}, "day5_node_margin": {"candidate_14_pass": false, "candidate_15_pass": true, "evidence": margin_15.value()}, "exact_step_cap": cap_fixture.value()})

func _run_step_cap_fixture(day: Dictionary) -> DomainResult:
	var cap_result: DomainResult = CourseworkRunLimitsType.step_cap(int(day["day_index"]))
	if not cap_result.is_success(): return cap_result
	var cap: int = int(cap_result.value())
	var graph: Dictionary = _execution_graph(_apply_witness_edits(day))
	var cases: Array[Dictionary] = _execution_cases(_dictionary_array(day["public_cases"]))
	var input_result: DomainResult = CourseworkRunInputType.create(String(day["task_id"]), int(day["day_index"]), "request.story008.cap", 1, graph, [cases[0]])
	if not input_result.is_success(): return input_result
	var program: CapFixtureProgram = CapFixtureProgram.new(cap + 1)
	var runner: CourseworkGvetRunner = CourseworkGvetRunnerType.new(SemanticDiagnosticValidatorType.new(_registry()), null, CourseworkTaskSandboxPortType.new(), CourseworkCaseExecutorType.new(), program)
	var report: CourseworkRunResult = runner.run(input_result.value())
	var results: Array[CourseworkCaseResult] = report.case_results()
	if not report.validation_pass() or results.size() != 1: return _failure("step cap fixture did not execute one validated case")
	var trace: Array[Dictionary] = _dictionary_array(results[0].to_dictionary()["trace"])
	var successor: String = "cap.%03d" % (cap + 1)
	if trace.size() != cap or String(trace[-1]["reason_code"]) != "EXECUTION_STEP_CAP" or program.executed_nodes.has(successor): return _failure("step cap fixture executed its scheduled successor")
	return DomainResultType.success({"cap": cap, "trace_length": trace.size(), "reason_code": String(trace[-1]["reason_code"]), "successor_node_id": successor, "successor_executed": false, "case_pass": results[0].case_pass(), "suite_pass": report.suite_pass()})

func _run_case_mutations(day: Dictionary, day_index: int) -> DomainResult:
	var mappings: Array[Dictionary] = []
	var seen_case_ids: Dictionary = {}
	var public_cases: Array[Dictionary] = _dictionary_array(day.get("public_cases", []))
	for public_case: Dictionary in public_cases:
		var case_id: String = String(public_case.get("case_id", ""))
		if case_id.is_empty() or seen_case_ids.has(case_id):
			return _failure("mutation mapping has an invalid case identity")
		seen_case_ids[case_id] = true
		var mutation: Dictionary = _mutation(day, day_index, public_case)
		var baseline_graph: Dictionary = _execution_graph(_apply_witness_edits(day))
		var baseline_case: Dictionary = _execution_case(public_case)
		if not mutation.has("graph") or not mutation.has("case") \
				or (mutation["graph"] == baseline_graph and mutation["case"] == baseline_case):
			return _failure("mutation mapping is vacuous")
		var report_result: DomainResult = _run(
			day, mutation["graph"], [mutation["case"]], String(mutation["mutation_id"]))
		if not report_result.is_success():
			return report_result
		var report: CourseworkRunResult = report_result.value()
		var results: Array[CourseworkCaseResult] = report.case_results()
		if not report.validation_pass() or results.size() != 1 or results[0].case_pass() or report.suite_pass():
			return _failure("mutation %s did not execute one failing case" % mutation["mutation_id"])
		mappings.append({
			"case_id": case_id, "mutation_id": String(mutation["mutation_id"]),
			"validation_pass": report.validation_pass(), "result_count": results.size(),
			"case_pass": results[0].case_pass(), "suite_pass": report.suite_pass(),
		})
	return DomainResultType.success(mappings)

func _mutation(day: Dictionary, day_index: int, public_case: Dictionary) -> Dictionary:
	var graph: Dictionary = _execution_graph(_apply_witness_edits(day))
	var case_definition: Dictionary = _execution_case(public_case)
	match day_index:
		1:
			if not _set_parameter(graph, "node.d1.pick_up", "action_id", "drop_front"):
				return {"mutation_id": "invalid"}
			return {"mutation_id": "action_rejection", "graph": graph, "case": case_definition}
		2:
			if not _swap_branch_ports(graph, "node.d2.branch"):
				return {"mutation_id": "invalid"}
			return {"mutation_id": "wrong_branch", "graph": graph, "case": case_definition}
		3:
			if not _set_parameter(graph, "node.d3.repeat", "count", 0):
				return {"mutation_id": "invalid"}
			return {"mutation_id": "wrong_repeat_path", "graph": graph, "case": case_definition}
		4:
			var initial_battery: int = int(case_definition["content"]["initial_state"]["bot"]["battery_units"])
			var wrong_operator: String = "less_than" if initial_battery == 2 else "greater_or_equal"
			if not _set_parameter(graph, "node.d4.compare", "operator", wrong_operator):
				return {"mutation_id": "invalid"}
			return {"mutation_id": "wrong_boundary", "graph": graph, "case": case_definition}
		5:
			if not _set_wrong_delivery_slot(case_definition):
				return {"mutation_id": "invalid"}
			return {"mutation_id": "wrong_day5_slot", "graph": graph, "case": case_definition}
	return {"mutation_id": "invalid"}

func _verify_structure(day: Dictionary) -> DomainResult:
	var day_index: int = int(day.get("day_index", 0))
	var graph: Dictionary = _apply_witness_edits(day)
	var nodes: Dictionary = _nodes_by_id(_dictionary_array(graph.get("nodes", [])))
	var routes: Dictionary = _routes(_dictionary_array(graph.get("connections", [])))
	if not _structure_is_present(day_index, nodes, routes):
		return _failure("Day %d instructional structure is not present in typed topology" % day_index)
	return DomainResultType.success({"day_index": day_index, "structure_pass": true})

func _structure_is_present(day_index: int, nodes: Dictionary, routes: Dictionary) -> bool:
	match day_index:
		1: return _day_one_structure(nodes, routes)
		2: return _day_two_structure(nodes, routes)
		3: return _day_three_structure(nodes, routes)
		4: return _day_four_structure(nodes, routes)
		5: return _day_five_structure(nodes, routes)
	return false

func _day_one_structure(nodes: Dictionary, routes: Dictionary) -> bool:
	return _is_variant(nodes, "node.d1.pick_up", "parcel.action.pick_up_front") \
		and _is_variant(nodes, "node.d1.drop_good", "parcel.action.drop_front") \
		and routes.has("node.d1.start:next>node.d1.pick_up:in") \
		and routes.has("node.d1.pick_up:next>node.d1.drop_good:in")

func _day_two_structure(nodes: Dictionary, routes: Dictionary) -> bool:
	return _is_variant(nodes, "node.d2.red_query", "parcel.query.front_sensor_matches_color") \
		and _is_variant(nodes, "node.d2.branch", "flow.branch.boolean") \
		and _parameter_is(nodes, "node.d2.red_query", "colour", "red") \
		and routes.has("node.d2.red_query:value>node.d2.branch:condition") \
		and routes.has("node.d2.branch:true>node.d2.pick_up:in") \
		and routes.has("node.d2.branch:false>node.d2.advance:in")

func _day_three_structure(nodes: Dictionary, routes: Dictionary) -> bool:
	return _is_variant(nodes, "node.d3.repeat", "flow.repeat.bounded") \
		and _parameter_is(nodes, "node.d3.repeat", "count", 3) \
		and routes.has("node.d3.move:next>node.d3.repeat:continue") \
		and routes.has("node.d3.turn_right:next>node.d3.repeat:continue")

func _day_four_structure(nodes: Dictionary, routes: Dictionary) -> bool:
	return _is_variant(nodes, "node.d4.compare", "value.compare.numeric") \
		and _parameter_is(nodes, "node.d4.compare", "operator", "less_or_equal") \
		and _parameter_is(nodes, "node.d4.constant_2", "value", 2) \
		and routes.has("node.d4.battery_query:value>node.d4.compare:left") \
		and routes.has("node.d4.constant_2:value>node.d4.compare:right") \
		and routes.has("node.d4.compare:value>node.d4.branch:condition") \
		and routes.has("node.d4.branch:true>node.d4.charge:in") \
		and routes.has("node.d4.branch:false>node.d4.move:in")

func _day_five_structure(nodes: Dictionary, routes: Dictionary) -> bool:
	return _all_categories_present(nodes) \
		and _parameter_is(nodes, "node.d5.repeat", "count", 2) \
		and _parameter_is(nodes, "node.d5.battery_compare", "operator", "less_or_equal") \
		and _parameter_is(nodes, "node.d5.red_query", "colour", "red") \
		and routes.has("node.d5.repeat:body>node.d5.battery_branch:in") \
		and routes.has("node.d5.battery_query:value>node.d5.battery_compare:left") \
		and routes.has("node.d5.constant_2:value>node.d5.battery_compare:right") \
		and routes.has("node.d5.battery_compare:value>node.d5.battery_branch:condition") \
		and routes.has("node.d5.charge:next>node.d5.repeat:continue") \
		and routes.has("node.d5.advance:next>node.d5.repeat:continue") \
		and routes.has("node.d5.repeat:done>node.d5.colour_branch:in") \
		and routes.has("node.d5.red_query:value>node.d5.colour_branch:condition") \
		and routes.has("node.d5.colour_branch:true>node.d5.hold_red:in") \
		and routes.has("node.d5.colour_branch:false>node.d5.end_non_red:in")

func _verify_negative_edges(day: Dictionary) -> DomainResult:
	var candidate: Dictionary = day.duplicate(true)
	var name: String = _apply_primary_negative(candidate)
	var records: Array[Dictionary] = []
	var result: DomainResult = _verify_structure(candidate)
	if result.is_success(): return _failure("negative edge %s unexpectedly passed" % name)
	records.append({"day_index": int(day["day_index"]), "edge": name, "structure_pass": false})
	if int(day["day_index"]) == 2:
		var label_candidate: Dictionary = day.duplicate(true)
		Dictionary(label_candidate["starting_graph"])["nodes"][1]["variant_id"] = "flow.start"
		Dictionary(label_candidate["starting_graph"])["nodes"][1]["label"] = "parcel.query.front_sensor_matches_color"
		var label_result: DomainResult = _verify_structure(label_candidate)
		if label_result.is_success(): return _failure("label-only duplicate unexpectedly passed")
		records.append({"day_index": 2, "edge": "label_only_renamed_duplicate", "structure_pass": false})
	return DomainResultType.success(records)

func _apply_primary_negative(candidate: Dictionary) -> String:
	match int(candidate["day_index"]):
		1:
			Dictionary(candidate["starting_graph"])["nodes"][2]["variant_id"] = "parcel.action.drop_front"
			return "swapped_arms"
		2:
			Dictionary(candidate["starting_graph"])["nodes"][1]["parameters"]["colour"] = "blue"
			return "wrong_colour"
		3:
			Dictionary(candidate["starting_graph"])["nodes"][5]["parameters"]["count"] = 0
			return "zero_repeat"
		4:
			Dictionary(candidate["starting_graph"])["nodes"][3]["parameters"]["operator"] = "less_than"
			return "less_than_boundary"
		5:
			var earlier_day: Dictionary = CourseworkTaskCatalogType.day4_content()
			candidate["starting_graph"] = Dictionary(earlier_day["starting_graph"]).duplicate(true)
			candidate["witness"] = Dictionary(earlier_day["witness"]).duplicate(true)
			return "copied_earlier_day"
	return "unknown"

func _run(day: Dictionary, graph: Dictionary, cases: Array[Dictionary], suffix: String) -> DomainResult:
	var input_result: DomainResult = CourseworkRunInputType.create(
		String(day["task_id"]), int(day["day_index"]),
		"request.story008.d%d.%s" % [int(day["day_index"]), suffix], 1, graph, cases)
	if not input_result.is_success():
		return _failure("Run input construction failed: %s" % input_result.error_message())
	var registry: Dictionary = _registry()
	var executor: CourseworkCaseExecutor = CourseworkCaseExecutorType.new()
	var program_result: DomainResult = executor.create_node_semantics_program(registry, CourseworkPublicEqualityAssertionPortType.new())
	if not program_result.is_success():
		return _failure("node semantics program construction failed")
	var runner: CourseworkGvetRunner = CourseworkGvetRunnerType.new(
		SemanticDiagnosticValidatorType.new(registry), null,
		CourseworkTaskSandboxPortType.new(), executor, program_result.value())
	return DomainResultType.success(runner.run(input_result.value()))

func _apply_witness_edits(day: Dictionary) -> Dictionary:
	var graph: Dictionary = Dictionary(day.get("starting_graph", {})).duplicate(true)
	var nodes: Array[Dictionary] = _dictionary_array(graph.get("nodes", []))
	var connections: Array[Dictionary] = _dictionary_array(graph.get("connections", []))
	var edits: Array[Dictionary] = _dictionary_array(Dictionary(day.get("witness", {})).get("edits", []))
	for edit: Dictionary in edits:
		match String(edit.get("kind", "")):
			"delete_node":
				var node_id: String = String(edit.get("node_id", ""))
				var remaining_nodes: Array = nodes.filter(func(node: Dictionary) -> bool: return String(node.get("node_id", "")) != node_id)
				nodes.assign(remaining_nodes)
				var remaining_connections: Array = connections.filter(func(connection: Dictionary) -> bool: return String(connection.get("source_node_id", "")) != node_id and String(connection.get("target_node_id", "")) != node_id)
				connections.assign(remaining_connections)
			"disconnect":
				var connection_id: String = String(edit.get("connection_id", ""))
				var disconnected_connections: Array = connections.filter(func(connection: Dictionary) -> bool: return String(connection.get("connection_id", "")) != connection_id)
				connections.assign(disconnected_connections)
			"replace_connection":
				var replaces_id: String = String(edit.get("replaces_connection_id", ""))
				var replaced_connections: Array = connections.filter(func(connection: Dictionary) -> bool: return String(connection.get("connection_id", "")) != replaces_id)
				connections.assign(replaced_connections)
				connections.append(_connection_from(edit))
			"create_node": nodes.append(_node_from(edit))
			"connect": connections.append(_connection_from(edit))
	graph["nodes"] = nodes
	graph["connections"] = connections
	return graph

func _execution_graph(content_graph: Dictionary) -> Dictionary:
	var nodes: Array[Dictionary] = []
	var content_nodes: Array[Dictionary] = _dictionary_array(content_graph.get("nodes", []))
	for content_node: Dictionary in content_nodes:
		var parameters: Dictionary = Dictionary(content_node.get("parameters", {})).duplicate(true)
		var category: String = String(content_node.get("category", ""))
		if category == "Action":
			parameters["action_id"] = parameters.get("operation_id", "")
			parameters.erase("operation_id")
		elif category == "Query":
			parameters["query_id"] = parameters.get("operation_id", "")
			parameters.erase("operation_id")
		nodes.append(_graph_node(String(content_node["node_id"]), String(content_node["variant_id"]), parameters))
	var connections: Array[Dictionary] = []
	var content_connections: Array[Dictionary] = _dictionary_array(content_graph.get("connections", []))
	for connection: Dictionary in content_connections:
		var copied: Dictionary = _connection_from(connection)
		if String(copied["source_port_id"]) == "value":
			var source: Dictionary = _find_content_node(content_nodes, String(copied["source_node_id"]))
			if String(source.get("category", "")) == "Compare":
				copied["source_port_id"] = "result"
		connections.append(copied)
	nodes.sort_custom(_record_id_less)
	connections.sort_custom(_record_id_less)
	return {"graph_codec_version": "authoring_graph_v1", "fixture_id": "fixture.story008.day%d" % int(content_graph.get("day_index", 0)), "nodes": nodes, "connections": connections}

func _execution_cases(public_cases: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for public_case: Dictionary in public_cases:
		result.append(_execution_case(public_case))
	return result

func _execution_case(public_case: Dictionary) -> Dictionary:
	return {"case_id": String(public_case["case_id"]), "content": {"initial_state": Dictionary(public_case["initial_state"]).duplicate(true), "assertions": _execution_assertions(_dictionary_array(public_case["assertions"]))}}

func _execution_assertions(authored: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_assertion: Variant in authored:
		if typeof(raw_assertion) != TYPE_DICTIONARY:
			return []
		var assertion: Dictionary = raw_assertion
		var expected: Dictionary = {}
		var expected_facts: Array = assertion.get("expected_facts", [])
		for raw_fact: Variant in expected_facts:
			if typeof(raw_fact) != TYPE_DICTIONARY:
				return []
			var fact: Dictionary = raw_fact
			expected[String(fact.get("fact_id", ""))] = fact.get("value", null)
		result.append({"assertion_id": String(assertion.get("assertion_id", "")), "expected": expected})
	return result

func _set_wrong_delivery_slot(case_definition: Dictionary) -> bool:
	var assertions: Array[Dictionary] = _dictionary_array(Dictionary(case_definition["content"])["assertions"])
	var expected: Dictionary = Dictionary(assertions[0]["expected"])
	if expected.has("delivery_slot_1"):
		expected["delivery_slot_1"] = "wrong_slot"
		return true
	return false


func _swap_branch_ports(graph: Dictionary, node_id: String) -> bool:
	var true_changed: bool = false
	var false_changed: bool = false
	for connection: Dictionary in graph["connections"]:
		if String(connection.get("source_node_id", "")) == node_id:
			if String(connection.get("source_port_id", "")) == "true":
				connection["source_port_id"] = "false"
				true_changed = true
			elif String(connection.get("source_port_id", "")) == "false":
				connection["source_port_id"] = "true"
				false_changed = true
	return true_changed and false_changed

func _set_parameter(graph: Dictionary, node_id: String, parameter_id: String, value: Variant) -> bool:
	for node: Dictionary in graph["nodes"]:
		if String(node.get("node_id", "")) != node_id: continue
		for parameter: Dictionary in node["parameter_values"]:
			if String(parameter.get("parameter_id", "")) == parameter_id:
				if parameter["value"] == value:
					return false
				parameter["value"] = value
				return true
	return false

func _registry() -> Dictionary:
	return CourseworkTaskExecutionContractType.production_authoring_registry()

func _graph_node(node_id: String, variant_id: String, parameters: Dictionary) -> Dictionary:
	var values: Array[Dictionary] = []
	for parameter_id: String in parameters: values.append({"parameter_id": parameter_id, "value": parameters[parameter_id]})
	values.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return String(left["parameter_id"]) < String(right["parameter_id"]))
	return {"node_id": node_id, "variant_id": variant_id, "anchor_x": 0, "anchor_y": 0, "parameter_values": values}
func _node_from(value: Dictionary) -> Dictionary: return {"node_id": String(value["node_id"]), "category": String(value["category"]), "variant_id": String(value["variant_id"]), "parameters": Dictionary(value.get("parameters", {})).duplicate(true)}
func _connection_from(value: Dictionary) -> Dictionary: return {"connection_id": String(value["connection_id"]), "source_node_id": String(value["source_node_id"]), "source_port_id": String(value["source_port_id"]), "target_node_id": String(value["target_node_id"]), "target_port_id": String(value["target_port_id"])}
func _find_content_node(nodes: Array[Dictionary], node_id: String) -> Dictionary:
	for node: Dictionary in nodes:
		if String(node.get("node_id", "")) == node_id:
			return node
	return {}

func _nodes_by_id(nodes: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for node: Dictionary in nodes:
		result[String(node["node_id"])] = node
	return result

func _routes(connections: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for connection: Dictionary in connections:
		result["%s:%s>%s:%s" % [connection["source_node_id"], connection["source_port_id"], connection["target_node_id"], connection["target_port_id"]]] = true
	return result
func _is_variant(nodes: Dictionary, node_id: String, variant_id: String) -> bool: return nodes.has(node_id) and String(nodes[node_id].get("variant_id", "")) == variant_id
func _parameter_is(nodes: Dictionary, node_id: String, parameter_id: String, expected: Variant) -> bool: return nodes.has(node_id) and Dictionary(nodes[node_id].get("parameters", {})).get(parameter_id, null) == expected
func _all_categories_present(nodes: Dictionary) -> bool:
	var categories: Dictionary = {}
	for node_id: String in nodes:
		categories[String(nodes[node_id].get("category", ""))] = true
	for category: String in ["Start", "Action", "Query", "Constant", "Compare", "Branch", "Repeat", "End"]:
		if not categories.has(category):
			return false
	return categories.size() == 8
func _witness_matches(witness: Dictionary, expected: Dictionary) -> bool: return int(witness.get("final_node_count", -1)) == int(expected["nodes"]) and int(witness.get("final_connection_count", -1)) == int(expected["connections"]) and int(witness.get("accepted_edit_count", -1)) == int(expected["edits"]) and int(witness.get("max_steps", -1)) == int(expected["steps"]) and int(witness.get("step_cap", -1)) == int(expected["cap"])
func _record_id_less(left: Dictionary, right: Dictionary) -> bool: return String(left.get("node_id", left.get("connection_id", ""))) < String(right.get("node_id", right.get("connection_id", "")))
func _failure(message: String) -> DomainResult: return DomainResultType.failure(&"witness_mutation_invalid", message)
