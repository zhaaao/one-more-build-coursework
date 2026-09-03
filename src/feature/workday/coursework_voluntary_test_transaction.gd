class_name CourseworkVoluntaryTestTransaction
extends RefCounted

## Story 003's sole Feature facade for voluntary public-test admission.
## WorkdayLifecycle owns charge, live locks, request-key idempotence, and the
## transient immutable binding. Task/Authoring owns prepared-input execution.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CourseworkPublicRunContractType = preload("res://src/core/task/coursework_public_run_contract.gd")
const CourseworkRunInputType = preload("res://src/core/gvet/coursework_run_input.gd")
const AuthoringSessionType = preload("res://src/core/authoring/authoring_session.gd")
const CourseworkWorkdayLifecycleType = preload("res://src/feature/workday/coursework_workday_lifecycle.gd")

enum Action { TARGETED_CASE, VOLUNTARY_SUITE }

## Prepares, validates endpoint availability, admits once, then dispatches the
## exact frozen input. A terminal result stays owned by Authoring/GVET.
func admit_and_run(public_run_contract: CourseworkPublicRunContract, lifecycle: CourseworkWorkdayLifecycle, authoring_session: AuthoringSession, action: int, task_id: String, day_index: int, request_id: String, graph_revision: int, graph_snapshot: Dictionary, selected_case_ids: Variant) -> DomainResult:
	var selection_result: DomainResult = _validate_action_selection(action, selected_case_ids)
	if not selection_result.is_success():
		return selection_result
	if public_run_contract == null or lifecycle == null:
		return _reject(&"voluntary_dependency_unavailable", "Task and Workday dependencies are required")
	var input_result: DomainResult = public_run_contract.prepare_run_input(task_id, day_index, request_id, graph_revision, graph_snapshot, selected_case_ids)
	if not input_result.is_success():
		return input_result
	var input_value: Variant = input_result.value()
	if not input_value is CourseworkRunInputType or not input_value.is_valid():
		return _reject(&"voluntary_binding_invalid", "Task did not produce a valid immutable public Run input")
	var replay_lookup: DomainResult = lifecycle.lookup_voluntary_request_replay(action, input_value)
	if not replay_lookup.is_success():
		return replay_lookup
	var replay_value: Dictionary[String, Variant] = _typed_dictionary(replay_lookup.value())
	if replay_value.is_empty() or not replay_value.has("found"):
		return _reject(&"voluntary_replay_record_invalid", "Workday returned an invalid voluntary replay record")
	if bool(replay_value["found"]):
		return DomainResultType.success(replay_value["status"])
	var endpoint_result: DomainResult = public_run_contract.validate_prepared_run(authoring_session, input_value)
	if not endpoint_result.is_success():
		return endpoint_result
	var admission: DomainResult = lifecycle.admit_voluntary_transaction(action, input_value)
	if not admission.is_success():
		return admission
	var admission_record: Dictionary[String, Variant] = _typed_dictionary(admission.value())
	if admission_record.is_empty() or not admission_record.has("replayed"):
		return _reject(&"voluntary_admission_record_invalid", "Workday returned an invalid voluntary admission record")
	if bool(admission_record["replayed"]):
		return DomainResultType.success(admission_record["status"])
	return _run_bound_input(public_run_contract, lifecycle, authoring_session)

## Retries only the lifecycle-owned charged binding after explicit interruption.
func retry_same_binding(public_run_contract: CourseworkPublicRunContract, lifecycle: CourseworkWorkdayLifecycle, authoring_session: AuthoringSession, candidate: CourseworkRunInput) -> DomainResult:
	if public_run_contract == null or lifecycle == null:
		return _reject(&"voluntary_dependency_unavailable", "Task and Workday dependencies are required")
	var endpoint_result: DomainResult = public_run_contract.validate_prepared_run(authoring_session, candidate)
	if not endpoint_result.is_success():
		return endpoint_result
	var retry_result: DomainResult = lifecycle.retry_voluntary_transaction(candidate)
	if not retry_result.is_success():
		return retry_result
	return _run_bound_input(public_run_contract, lifecycle, authoring_session)

## Explicitly abandons the lifecycle-owned binding with no terminal result.
func abandon(lifecycle: CourseworkWorkdayLifecycle) -> DomainResult:
	if lifecycle == null:
		return _reject(&"voluntary_dependency_unavailable", "a Workday lifecycle is required")
	return lifecycle.abandon_voluntary_transaction()

## Returns Workday's transient source-of-truth projection.
func status(lifecycle: CourseworkWorkdayLifecycle) -> Dictionary[String, Variant]:
	return {} if lifecycle == null else lifecycle.voluntary_transaction_status()

func _run_bound_input(public_run_contract: CourseworkPublicRunContract, lifecycle: CourseworkWorkdayLifecycle, authoring_session: AuthoringSession) -> DomainResult:
	var bound_input: CourseworkRunInput = lifecycle.voluntary_binding()
	var execution: DomainResult = public_run_contract.run_prepared(authoring_session, bound_input)
	if execution.is_success():
		var completion: DomainResult = lifecycle.complete_voluntary_transaction()
		return execution if completion.is_success() else completion
	if execution.error_code() == &"recoverable_interruption":
		lifecycle.record_voluntary_recoverable_interruption()
	else:
		lifecycle.abandon_voluntary_transaction()
	return execution

func _validate_action_selection(action: int, selected_case_ids: Variant) -> DomainResult:
	if action != Action.TARGETED_CASE and action != Action.VOLUNTARY_SUITE:
		return _reject(&"voluntary_action_invalid", "voluntary action is not supported")
	if typeof(selected_case_ids) != TYPE_ARRAY:
		return _reject(&"voluntary_selection_invalid", "selected public cases must be an Array")
	var selection: Array = selected_case_ids
	if action == Action.TARGETED_CASE and selection.size() != 1:
		return _reject(&"voluntary_targeted_selection_invalid", "a targeted run binds exactly one public case")
	if action == Action.VOLUNTARY_SUITE and selection.size() < 2:
		return _reject(&"voluntary_suite_selection_invalid", "a voluntary suite binds the complete ordered roster")
	return DomainResultType.success(true)

func _reject(error_code: StringName, message: String) -> DomainResult:
	return DomainResultType.failure(error_code, message, "workday.voluntary_test_transaction")

func _typed_dictionary(value: Variant) -> Dictionary[String, Variant]:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var source: Dictionary = value
	var copy: Dictionary[String, Variant] = {}
	for raw_key: Variant in source.keys():
		if typeof(raw_key) != TYPE_STRING:
			return {}
		copy[String(raw_key)] = source[raw_key]
	return copy
