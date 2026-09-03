class_name CourseworkGvetRunner
extends RefCounted

## Typed synchronous preparation plus Story003's internal serial-case seam.
## This stateful synchronous owner is single-thread-only and rejects reentry.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const PreparedRunType = preload("res://src/core/gvet/prepared_run.gd")
const SEMANTIC_REPORT_SCRIPT_PATH: String = "res://src/core/gvet/semantic_validation_report.gd"

## Typed process-local semantic validation seam used by the coursework runner.
class SemanticValidationPort extends RefCounted:
	const ResultType = preload("res://src/foundation/domain_result.gd")

	## Returns the semantic result for one exact input.
	## Example: `return ResultType.success(receipt)`.
	func validate_semantics(_input: CourseworkRunInput) -> DomainResult:
		return ResultType.failure(&"semantic_validation_error", "semantic validation port is not implemented")

## Optional post-construction observer; it carries no preparation authority.
class PreparationObserver extends RefCounted:
	## Observes a committed transient preparation without receiving the value.
	## Example: increment a test-only creation counter.
	func on_prepared_run_created() -> void:
		pass

var _semantic_port: RefCounted = null
var _preparation_observer: PreparationObserver = null
var _sandbox_port: RefCounted = null
var _case_executor: RefCounted = null
var _program_port: RefCounted = null
var _prepared_run_creation_count: int = 0
var _case_start_count: int = 0
var _result_freeze_count: int = 0
var _run_active: bool = false
var _preparation_active: bool = false
var _preparation_claim_open: bool = false
var _preparation_input: CourseworkRunInput = null
var _preparation_validation: DomainResult = null

func _init(
	semantic_port: RefCounted = null,
	preparation_observer: PreparationObserver = null,
	sandbox_port: RefCounted = null,
	case_executor: RefCounted = null,
	program_port: RefCounted = null
) -> void:
	_semantic_port = semantic_port
	_preparation_observer = preparation_observer
	_sandbox_port = sandbox_port
	_case_executor = case_executor
	_program_port = program_port

## Runs validation and every admitted case synchronously, then returns one
## complete frozen report. The program and Sandbox ports are constructor-injected.
## Example: `var report: CourseworkRunResult = runner.run(run_input)`.
func run(input: CourseworkRunInput) -> CourseworkRunResult:
	_case_start_count = 0
	_result_freeze_count = 0
	var builder: CourseworkResultBuilder = CourseworkResultBuilder.new(input)
	if _run_active:
		var reentry: DomainResult = builder._record_input_error(
			"run_in_progress", "runner is already executing a Run")
		return _finish_after_operation(builder, reentry)
	_run_active = true
	var report: CourseworkRunResult = _run_once(input, builder)
	_run_active = false
	return report

func _run_once(
	input: CourseworkRunInput, builder: CourseworkResultBuilder
) -> CourseworkRunResult:
	var prepared_result: DomainResult = _prepare_run(input)
	if not prepared_result.is_success():
		if prepared_result.error_code() == &"run_input_error":
			var input_error: DomainResult = builder._record_input_error(
				String(prepared_result.error_code()), prepared_result.error_message())
			return _finish_after_operation(builder, input_error)
		return _preparation_system_error(input, builder, prepared_result)
	var prepared_value: Variant = prepared_result.value()
	if _is_semantic_report(prepared_value):
		var semantic_recorded: DomainResult = builder._record_semantic_report(
			prepared_value)
		return _finish_after_operation(builder, semantic_recorded)
	if not prepared_value is PreparedRunType or not is_instance_valid(prepared_value):
		return _preparation_system_error(
			input, builder,
			DomainResultType.failure(
				&"prepared_run_error", "preparation returned no valid PreparedRun"))
	var validation_recorded: DomainResult = builder._record_validation_pass()
	if not validation_recorded.is_success():
		return _fallback_result(validation_recorded)
	return _execute_run(prepared_value, builder)

func _execute_run(
	prepared_run: PreparedRun, builder: CourseworkResultBuilder
) -> CourseworkRunResult:
	var roster: Array[Dictionary] = prepared_run.case_roster()
	var dependency_error: DomainResult = _execution_dependency_error(prepared_run)
	if not dependency_error.is_success():
		return _stop_with_system_error(builder, roster, 0, dependency_error)
	var cap_result: DomainResult = CourseworkRunLimits.step_cap(prepared_run.day_index())
	if not cap_result.is_success():
		return _stop_with_system_error(builder, roster, 0, cap_result)
	var graph: Dictionary = prepared_run.graph_snapshot()
	for case_index: int in range(roster.size()):
		_case_start_count += 1
		var raw_result: Variant = _case_executor._execute_case(
			roster[case_index], graph, _sandbox_port, _program_port,
			int(cap_result.value()))
		if not raw_result is DomainResultType or not is_instance_valid(raw_result):
			return _stop_with_system_error(
				builder, roster, case_index,
				DomainResultType.failure(
					&"case_execution_error", "case executor returned no result"))
		var case_result: DomainResult = raw_result
		if not case_result.is_success():
			return _stop_with_system_error(
				builder, roster, case_index, case_result)
		var appended: DomainResult = builder._append_executed_case(
			roster[case_index], case_result.value())
		if not appended.is_success():
			return _stop_with_system_error(
				builder, roster, case_index, appended)
	return _finish_builder(builder)

func _preparation_system_error(
	input: CourseworkRunInput,
	builder: CourseworkResultBuilder,
	failure: DomainResult
) -> CourseworkRunResult:
	if input is CourseworkRunInput and is_instance_valid(input) and input.is_valid():
		var validation_recorded: DomainResult = builder._record_validation_pass()
		if not validation_recorded.is_success():
			return _fallback_result(validation_recorded)
		return _stop_with_system_error(builder, input.case_roster(), 0, failure)
	var input_error: DomainResult = builder._record_input_error(
		String(failure.error_code()),
		failure.error_message() if not failure.error_message().is_empty() \
		else "Run preparation failed")
	return _finish_after_operation(builder, input_error)

func _execution_dependency_error(prepared_run: PreparedRun) -> DomainResult:
	if prepared_run == null or not prepared_run.is_valid():
		return DomainResultType.failure(
			&"case_execution_error", "runner requires a valid PreparedRun")
	if not _sandbox_port_is_valid():
		return DomainResultType.failure(
			&"case_execution_error", "runner requires a typed Sandbox port")
	if _case_executor == null or not is_instance_valid(_case_executor) \
			or not _case_executor.has_method("_execute_case"):
		return DomainResultType.failure(
			&"case_execution_error", "runner requires a case executor")
	if not _program_port_is_valid():
		return DomainResultType.failure(
			&"case_execution_error", "runner requires a typed execution program")
	return DomainResultType.success(true)

func _sandbox_port_is_valid() -> bool:
	return _sandbox_port != null and is_instance_valid(_sandbox_port) \
		and _sandbox_port is CourseworkSandboxPort

func _program_port_is_valid() -> bool:
	return _program_port != null and is_instance_valid(_program_port) \
		and _program_port is CourseworkCaseExecutor.ExecutionProgramPort

func _stop_with_system_error(
	builder: CourseworkResultBuilder,
	roster: Array[Dictionary],
	failure_index: int,
	failure: DomainResult
) -> CourseworkRunResult:
	if roster.is_empty() or failure_index < 0 or failure_index >= roster.size():
		var input_error: DomainResult = builder._record_input_error(
			String(failure.error_code()),
			failure.error_message() if not failure.error_message().is_empty() \
			else "Run failed before a rostered case could start")
		return _finish_after_operation(builder, input_error)
	var case_id: String = _case_id(roster[failure_index])
	var run_error: Dictionary = {
		"kind": "system_error",
		"code": String(failure.error_code()) \
			if not String(failure.error_code()).is_empty() else "system_error",
		"message": failure.error_message() \
			if not failure.error_message().is_empty() else "unexpected coursework system failure",
		"case_id": case_id,
	}
	var active_appended: DomainResult = builder._append_system_error_case(
		roster[failure_index], run_error)
	if not active_appended.is_success():
		return _fallback_result(active_appended)
	for later_index: int in range(failure_index + 1, roster.size()):
		var later_appended: DomainResult = builder._append_not_run_system_error_case(
			roster[later_index], run_error)
		if not later_appended.is_success():
			return _fallback_result(later_appended)
	var error_recorded: DomainResult = builder._record_system_error(run_error)
	return _finish_after_operation(builder, error_recorded)

func _finish_after_operation(
	builder: CourseworkResultBuilder, operation: DomainResult
) -> CourseworkRunResult:
	if not operation.is_success():
		return _fallback_result(operation)
	return _finish_builder(builder)

func _finish_builder(builder: CourseworkResultBuilder) -> CourseworkRunResult:
	var frozen: DomainResult = builder._freeze()
	_result_freeze_count = builder._freeze_count_for_test()
	if not frozen.is_success():
		return _fallback_result(frozen)
	return frozen.value()

func _fallback_result(failure: DomainResult) -> CourseworkRunResult:
	var fallback: CourseworkResultBuilder = CourseworkResultBuilder.new(null)
	var message: String = failure.error_message()
	if message.is_empty():
		message = "coursework result aggregation failed"
	var recorded: DomainResult = fallback._record_input_error(
		"result_builder_error", message)
	if not recorded.is_success():
		return CourseworkRunResult.new()
	var frozen: DomainResult = fallback._freeze()
	_result_freeze_count = fallback._freeze_count_for_test()
	return frozen.value() if frozen.is_success() else CourseworkRunResult.new()

func _result_freeze_count_for_test() -> int:
	return _result_freeze_count

func _case_id(case_definition: Dictionary) -> String:
	return String(case_definition.get(
		"case_id", case_definition.get("test_case_id", "")))

## Validates exactly once and creates one transient PreparedRun on success.
## Example: `var result := runner._prepare_run(input)`.
func _prepare_run(input: Variant) -> DomainResult:
	if _preparation_active:
		return DomainResultType.failure(&"run_in_progress", "runner is already preparing a Run")
	_clear_preparation_claim()
	_preparation_active = true
	var result: DomainResult = _prepare_run_once(input)
	_preparation_active = false
	return result

func _prepare_run_once(input: Variant) -> DomainResult:
	if typeof(input) != TYPE_OBJECT or not input is CourseworkRunInput or not is_instance_valid(input):
		return DomainResultType.failure(&"run_input_error", "runner requires a valid CourseworkRunInput")
	var coursework_input: CourseworkRunInput = input
	if not coursework_input.is_valid():
		return DomainResultType.failure(&"run_input_error", "CourseworkRunInput is invalid")
	if _semantic_port == null or not is_instance_valid(_semantic_port):
		return DomainResultType.failure(&"semantic_validation_error", "semantic validation port is required")
	if not _semantic_port.has_method("validate_semantics"):
		return DomainResultType.failure(&"semantic_validation_error", "semantic validation port has no validation operation")
	return _resolve_semantic_preparation(
		coursework_input, _semantic_port.validate_semantics(coursework_input))

func _resolve_semantic_preparation(
	input: CourseworkRunInput,
	raw_result: Variant
) -> DomainResult:
	if (
		typeof(raw_result) != TYPE_OBJECT
		or not raw_result is DomainResultType
		or not is_instance_valid(raw_result)
	):
		return DomainResultType.failure(
			&"semantic_validation_error", "semantic validation port returned no result")
	var semantic_result: DomainResult = raw_result
	if not semantic_result.is_success():
		return semantic_result
	var semantic_value: Variant = semantic_result.value()
	if not _is_semantic_report(semantic_value):
		return _commit_prepared_run(input, semantic_result)
	var report: RefCounted = semantic_value
	if not report.is_valid():
		return DomainResultType.failure(
			&"semantic_validation_error", "semantic validation returned an invalid report")
	if not report.validation_pass():
		return DomainResultType.success(report)
	return _commit_prepared_run(input, report.preparation_receipt())

func _commit_prepared_run(
	input: CourseworkRunInput,
	semantic_result: DomainResult
) -> DomainResult:
	if not semantic_result.is_success():
		return semantic_result
	_preparation_claim_open = true
	_preparation_input = input
	_preparation_validation = semantic_result
	var prepared: PreparedRun = PreparedRunType.new(self, input, semantic_result)
	_clear_preparation_claim()
	if not prepared.is_valid():
		return DomainResultType.failure(&"prepared_run_error", "semantic receipt could not admit PreparedRun")
	_prepared_run_creation_count += 1
	_notify_prepared_run_created()
	return DomainResultType.success(prepared)

func _is_semantic_report(value: Variant) -> bool:
	if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
		return false
	var value_script: Script = value.get_script()
	return (
		value_script != null
		and value_script.resource_path == SEMANTIC_REPORT_SCRIPT_PATH
		and value.has_method("validation_pass")
		and value.has_method("preparation_receipt"))

## Executes a valid preparation through the injected Story003 domain seams.
## Example: `var cases := runner._execute_prepared(prepared, program_port)`.
func _execute_prepared(prepared_run: Variant, program_port: RefCounted) -> DomainResult:
	_case_start_count = 0
	if not prepared_run is PreparedRunType or not is_instance_valid(prepared_run) or not prepared_run.is_valid():
		return DomainResultType.failure(&"case_execution_error", "runner requires a valid PreparedRun")
	if _sandbox_port == null or not is_instance_valid(_sandbox_port):
		return DomainResultType.failure(&"case_execution_error", "runner requires a Sandbox port")
	if _case_executor == null or not is_instance_valid(_case_executor):
		return DomainResultType.failure(&"case_execution_error", "runner requires a case executor")
	if not _case_executor.has_method("execute_cases"):
		return DomainResultType.failure(&"case_execution_error", "case executor has no execution operation")
	var result: Variant = _case_executor.execute_cases(prepared_run, _sandbox_port, program_port)
	if not result is DomainResultType or not is_instance_valid(result):
		return DomainResultType.failure(&"case_execution_error", "case executor returned no result")
	if not result.is_success():
		return result
	if typeof(result.value()) != TYPE_ARRAY:
		return DomainResultType.failure(&"case_execution_error", "case executor returned invalid records")
	_case_start_count += Array(result.value()).size()
	return result

## Returns the number of valid transient preparations made by this runner.
## Example: `assert(runner.prepared_run_creation_count() == 1)`.
func prepared_run_creation_count() -> int:
	return _prepared_run_creation_count

## Returns case starts committed by the most recent internal execution attempt.
## Example: `assert(runner.case_start_count() == 0)`.
func case_start_count() -> int:
	return _case_start_count

func _claim_prepared_run(
	input: CourseworkRunInput,
	semantic_validation: DomainResult
) -> bool:
	if not _preparation_claim_open:
		return false
	if input != _preparation_input or semantic_validation != _preparation_validation:
		return false
	_clear_preparation_claim()
	return true

func _clear_preparation_claim() -> void:
	_preparation_claim_open = false
	_preparation_input = null
	_preparation_validation = null

func _notify_prepared_run_created() -> void:
	if _preparation_observer != null and is_instance_valid(_preparation_observer):
		_preparation_observer.on_prepared_run_created()
