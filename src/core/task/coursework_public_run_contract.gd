class_name CourseworkPublicRunContract
extends RefCounted

## Task-owned public Run coordinator for Story 007's admitted roster boundary.
##
## This coordinator reads only `CourseworkPublicRosterStateValidator.snapshot()`,
## accepts one declared public case or the exact current-day roster, and builds
## an immutable GVET input before delegating execution and report publication to
## Authoring. Example: `contract.run(session, task_id, day, request, revision,
## graph, [case_id])`.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CourseworkPublicRosterStateValidatorType = preload("res://src/core/task/coursework_public_roster_state_validator.gd")
const CourseworkRunInputType = preload("res://src/core/gvet/coursework_run_input.gd")
const CourseworkRunResultType = preload("res://src/core/gvet/coursework_run_result.gd")
const AuthoringSessionType = preload("res://src/core/authoring/authoring_session.gd")

var _admitted_source: RefCounted = null


## Creates a coordinator over the one admitted Task public-roster projection.
## Example: `var contract := CourseworkPublicRunContract.new(validator)`.
func _init(admitted_source: RefCounted) -> void:
	_admitted_source = admitted_source


## Validates the selected public IDs and returns one immutable GVET Run input.
##
## The caller provides only scalar capture identity and an Authoring graph; case
## definitions always come from the admitted Task snapshot. Example:
## `contract.prepare_run_input(task_id, day, request, revision, graph, [case])`.
func prepare_run_input(
	task_id: String,
	day_index: int,
	request_id: String,
	graph_revision: int,
	graph_snapshot: Dictionary,
	selected_case_ids: Variant
) -> DomainResult:
	var selected_cases: DomainResult = _selected_cases(task_id, day_index, selected_case_ids)
	if not selected_cases.is_success():
		return selected_cases
	return CourseworkRunInputType.create(
		task_id,
		day_index,
		request_id,
		graph_revision,
		graph_snapshot.duplicate(true),
		selected_cases.value()
	)


## Delegates one selection-validated immutable input to Authoring synchronously.
##
## Selection rejection occurs before `AuthoringSession.run`, preserving its
## completed-report slot. Authoring owns graph freshness and report staleness;
## GVET and Sandbox own fresh state, ordinary failure, and system-error flow.
## Example: `contract.run(session, task_id, day, request, revision, graph, ids)`.
func run(
	authoring_session: AuthoringSession,
	task_id: String,
	day_index: int,
	request_id: String,
	graph_revision: int,
	graph_snapshot: Dictionary,
	selected_case_ids: Variant
) -> DomainResult:
	var input_result: DomainResult = prepare_run_input(
		task_id, day_index, request_id, graph_revision, graph_snapshot, selected_case_ids)
	if not input_result.is_success():
		return input_result
	if authoring_session == null or not is_instance_valid(authoring_session):
		return _failure(&"authoring_session_unavailable", "Public Run requires an Authoring session.")
	return authoring_session.run(input_result.value())

## Validates that one already frozen public input may reach Authoring.
## This lets Feature owners reject an unavailable endpoint before charging.
func validate_prepared_run(
		authoring_session: AuthoringSession, prepared_input: CourseworkRunInput
) -> DomainResult:
	if authoring_session == null or not is_instance_valid(authoring_session):
		return _failure(&"authoring_session_unavailable", "Public Run requires an Authoring session.")
	if prepared_input == null or not prepared_input.is_valid():
		return _failure(&"public_run_input_invalid", "Public Run requires a valid immutable input.")
	return DomainResultType.success(true)

## Dispatches exactly the supplied frozen input without rebuilding task/roster truth.
func run_prepared(
		authoring_session: AuthoringSession, prepared_input: CourseworkRunInput
) -> DomainResult:
	var availability: DomainResult = validate_prepared_run(authoring_session, prepared_input)
	if not availability.is_success():
		return availability
	var execution: DomainResult = authoring_session.run(prepared_input)
	if not execution.is_success():
		return execution
	var terminal_value: Variant = execution.value()
	if not terminal_value is CourseworkRunResultType \
			or not is_instance_valid(terminal_value) or not terminal_value.is_valid():
		return _failure(&"public_run_terminal_invalid", "Authoring must return a valid CourseworkRunResult.")
	return execution


func _selected_cases(
	task_id: String, day_index: int, selected_case_ids: Variant
) -> DomainResult:
	var day_result: DomainResult = _admitted_day(task_id, day_index)
	if not day_result.is_success():
		return day_result
	if typeof(selected_case_ids) != TYPE_ARRAY:
		return _selection_failure("Public Run selection must be an Array of case IDs.")
	var requested_ids: Array[Variant] = []
	for requested_case_id: Variant in Array(selected_case_ids):
		requested_ids.append(requested_case_id)
	var day: Dictionary = day_result.value()
	var admitted_cases: Array[Dictionary] = []
	for raw_admitted_case: Variant in Array(day["public_cases"]):
		if typeof(raw_admitted_case) != TYPE_DICTIONARY:
			return _failure(&"public_roster_invalid", "Admitted public roster case is malformed.")
		admitted_cases.append(Dictionary(raw_admitted_case))
	if requested_ids.size() == 1:
		if typeof(requested_ids[0]) != TYPE_STRING:
			return _selection_failure("Public Run singleton selection must contain one case ID.")
		var requested_id: String = String(requested_ids[0])
		for admitted_case: Dictionary in admitted_cases:
			if String(admitted_case.get("case_id", "")) == requested_id:
				var execution_case: DomainResult = execution_case(admitted_case)
				return execution_case if not execution_case.is_success() \
					else DomainResultType.success([execution_case.value()])
		return _selection_failure("Public Run singleton must be a public case for the selected day.")
	if requested_ids.size() != admitted_cases.size():
		return _selection_failure("Public Run must select one case or the complete current-day roster.")
	var copied_cases: Array[Dictionary] = []
	for index: int in admitted_cases.size():
		if typeof(requested_ids[index]) != TYPE_STRING \
				or String(requested_ids[index]) != String(admitted_cases[index].get("case_id", "")):
			return _selection_failure("Complete public Run selection must match the admitted roster order exactly.")
		var execution_case: DomainResult = execution_case(admitted_cases[index])
		if not execution_case.is_success():
			return execution_case
		copied_cases.append(execution_case.value())
	return DomainResultType.success(copied_cases)


## Projects one admitted public Task row into the immutable case ABI consumed by
## GVET and the Sandbox. The Task-owned source projection remains unchanged.
func execution_case(admitted_case: Dictionary) -> DomainResult:
	var case_id: Variant = admitted_case.get("case_id", null)
	var initial_state: Variant = admitted_case.get("initial_state", null)
	var authored_assertions: Variant = admitted_case.get("assertions", null)
	if typeof(case_id) != TYPE_STRING or String(case_id).is_empty() \
			or typeof(initial_state) != TYPE_DICTIONARY \
			or typeof(authored_assertions) != TYPE_ARRAY:
		return _content_failure("Admitted public case requires case_id, initial_state, and assertions.")
	var assertions: DomainResult = _execution_assertions(Array(authored_assertions))
	if not assertions.is_success():
		return assertions
	return DomainResultType.success({
		"case_id": String(case_id),
		"content": {
			"initial_state": Dictionary(initial_state).duplicate(true),
			"assertions": assertions.value(),
		},
	})


## Converts the Task's ordered expected-fact list into GVET's typed equality
## map without changing the authored facts or assertion order.
func _execution_assertions(authored_assertions: Array) -> DomainResult:
	if authored_assertions.is_empty():
		return _content_failure("Admitted public case requires at least one assertion.")
	var execution_assertions: Array[Dictionary] = []
	for raw_assertion: Variant in authored_assertions:
		if typeof(raw_assertion) != TYPE_DICTIONARY:
			return _content_failure("Admitted public assertion must be a Dictionary.")
		var authored_assertion: Dictionary = raw_assertion
		var assertion_id: Variant = authored_assertion.get("assertion_id", null)
		var expected_facts: Variant = authored_assertion.get("expected_facts", null)
		if typeof(assertion_id) != TYPE_STRING or String(assertion_id).is_empty() \
				or typeof(expected_facts) != TYPE_ARRAY or Array(expected_facts).is_empty():
			return _content_failure("Admitted public assertion requires assertion_id and expected_facts.")
		var expected: Dictionary = {}
		for raw_fact: Variant in Array(expected_facts):
			if typeof(raw_fact) != TYPE_DICTIONARY:
				return _content_failure("Expected fact must be a Dictionary.")
			var fact: Dictionary = raw_fact
			var fact_id: Variant = fact.get("fact_id", null)
			if typeof(fact_id) != TYPE_STRING or String(fact_id).is_empty() \
					or not fact.has("value") or expected.has(String(fact_id)):
				return _content_failure("Expected facts require unique fact_id and value fields.")
			expected[String(fact_id)] = fact["value"]
		execution_assertions.append({
			"assertion_id": String(assertion_id),
			"expected": expected,
		})
	return DomainResultType.success(execution_assertions)


func _admitted_day(task_id: String, day_index: int) -> DomainResult:
	if _admitted_source == null or not is_instance_valid(_admitted_source):
		return _failure(&"public_roster_unavailable", "Public Run requires an admitted public roster.")
	if _admitted_source.has_method("ordered_public_cases"):
		if String(_admitted_source.call("task_id")) != task_id \
				or int(_admitted_source.call("day_index")) != day_index:
			return _selection_failure("Public Run task/day does not match the admitted current-day roster.")
		return DomainResultType.success({
			"task_id": task_id, "day_index": day_index,
			"public_cases": _admitted_source.call("ordered_public_cases"),
		})
	if not _admitted_source.has_method("snapshot"):
		return _failure(&"public_roster_unavailable", "Public Run requires an admitted public roster.")
	var snapshot: Dictionary = _admitted_source.call("snapshot")
	var raw_days: Variant = snapshot.get("days", null)
	if typeof(raw_days) != TYPE_ARRAY or day_index < 1 or day_index > Array(raw_days).size():
		return _selection_failure("Public Run day is not present in the admitted roster.")
	var day: Variant = Array(raw_days)[day_index - 1]
	if typeof(day) != TYPE_DICTIONARY:
		return _failure(&"public_roster_invalid", "Admitted public roster day is malformed.")
	var admitted_day: Dictionary = day
	if int(admitted_day.get("day_index", -1)) != day_index \
			or String(admitted_day.get("task_id", "")) != task_id \
			or typeof(admitted_day.get("public_cases", null)) != TYPE_ARRAY:
		return _selection_failure("Public Run task/day does not match the admitted current-day roster.")
	return DomainResultType.success(admitted_day.duplicate(true))


func _selection_failure(message: String) -> DomainResult:
	return _failure(&"public_run_selection_invalid", message)


func _content_failure(message: String) -> DomainResult:
	return _failure(&"public_case_content_invalid", message)


func _failure(error_code: StringName, message: String) -> DomainResult:
	return DomainResultType.failure(error_code, message)
