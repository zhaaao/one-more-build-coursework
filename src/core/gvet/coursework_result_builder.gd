class_name CourseworkResultBuilder
extends RefCounted

## Private ordered accumulator for one synchronous coursework Run.
## It exposes only underscore-prefixed runner/test seams and freezes once.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CanonicalJsonIRType = preload("res://src/foundation/canonical_json_ir.gd")
const RunInputType = preload("res://src/core/gvet/coursework_run_input.gd")
const AssertionResultType = preload("res://src/core/gvet/coursework_assertion_result.gd")
const CaseResultType = preload("res://src/core/gvet/coursework_case_result.gd")
const RunResultType = preload("res://src/core/gvet/coursework_run_result.gd")
const SemanticReportType = preload("res://src/core/gvet/semantic_validation_report.gd")

var _identity: Dictionary = {}
var _validation_pass: bool = false
var _diagnostics: Array[Dictionary] = []
var _case_results: Array[CourseworkCaseResult] = []
var _run_error: Dictionary = {}
var _frozen: bool = false
var _freeze_count: int = 0

func _init(input: Variant = null) -> void:
	_identity = _identity_from_input(input)

func _record_input_error(code: String, message: String) -> DomainResult:
	if not _may_change_terminal_state() or code.is_empty() or message.is_empty():
		return _failure("input error cannot be recorded in the current builder state")
	_validation_pass = false
	_diagnostics = []
	_run_error = _run_error_record("input_error", code, message, "")
	return DomainResultType.success(true)

func _record_semantic_report(report: Variant) -> DomainResult:
	if not _may_change_terminal_state() or not report is SemanticReportType \
			or not is_instance_valid(report) or not report.is_valid() \
			or not _semantic_identity_matches(report.identity()):
		return _failure("semantic report is invalid or builder state is terminal")
	_validation_pass = report.validation_pass()
	_diagnostics = _clone_dictionary_array(report.diagnostic_records())
	_run_error = {}
	return DomainResultType.success(true)

func _record_validation_pass() -> DomainResult:
	if not _may_change_terminal_state():
		return _failure("validation cannot be recorded in the current builder state")
	_validation_pass = true
	_diagnostics = []
	_run_error = {}
	return DomainResultType.success(true)

func _append_executed_case(
	case_definition: Dictionary, transient_record: Variant
) -> DomainResult:
	if not _may_append_case() or typeof(transient_record) != TYPE_DICTIONARY:
		return _failure("executed case cannot be appended in the current builder state")
	var raw_record: Dictionary = transient_record
	var case_id: String = _case_id(case_definition)
	if case_id.is_empty() or raw_record.get("case_id") != case_id:
		return _failure("executed case identity does not match roster order")
	var assertions_result: DomainResult = _assertion_results(
		case_definition, raw_record)
	if not assertions_result.is_success():
		return assertions_result
	var created: DomainResult = CaseResultType.create_executed(
		case_id,
		raw_record.get("initial_state", null),
		raw_record.get("final_state", null),
		raw_record.get("trace", null),
		assertions_result.value(),
		raw_record.get("terminal_flow", null),
		raw_record.get("ordinary_failure_code", null),
		raw_record.get("ordinary_failure_reason", null))
	if not created.is_success():
		return created
	_case_results.append(created.value())
	return DomainResultType.success(true)

func _append_system_error_case(
	case_definition: Dictionary, run_error: Dictionary
) -> DomainResult:
	if not _may_append_case() or not _system_error_matches_case(
		run_error, _case_id(case_definition)):
		return _failure("active system-error case is invalid")
	var created: DomainResult = CaseResultType.create_system_error(
		_case_id(case_definition), run_error)
	if not created.is_success():
		return created
	_case_results.append(created.value())
	return DomainResultType.success(true)

func _append_not_run_system_error_case(
	case_definition: Dictionary, run_error: Dictionary
) -> DomainResult:
	if not _may_append_case() or not _system_error_is_valid(run_error):
		return _failure("not-run system-error case is invalid")
	var created: DomainResult = CaseResultType.create_not_run_system_error(
		_case_id(case_definition), run_error)
	if not created.is_success():
		return created
	_case_results.append(created.value())
	return DomainResultType.success(true)

func _record_system_error(run_error: Dictionary) -> DomainResult:
	if _frozen or not _run_error.is_empty() or not _system_error_is_valid(run_error):
		return _failure("system error cannot be recorded in the current builder state")
	_run_error = CanonicalJsonIRType.clone(run_error)
	return DomainResultType.success(true)

func _freeze() -> DomainResult:
	if _frozen:
		return _failure("result builder may freeze only once")
	var no_system_failure: bool = _run_error.is_empty() \
		or _run_error.get("kind") != "system_error"
	var all_cases_pass: bool = not _case_results.is_empty()
	for case_result: CourseworkCaseResult in _case_results:
		all_cases_pass = all_cases_pass and case_result.case_pass()
	var record: Dictionary = {
		"identity": CanonicalJsonIRType.clone(_identity),
		"validation_pass": _validation_pass,
		"diagnostics": _clone_dictionary_array(_diagnostics),
		"case_results": _copy_cases(_case_results),
		"suite_pass": _validation_pass and no_system_failure and all_cases_pass,
		"run_error": CanonicalJsonIRType.clone(_run_error),
	}
	var result: DomainResult = RunResultType._freeze_from_builder(record)
	if not result.is_success():
		return result
	_frozen = true
	_freeze_count += 1
	return result

func _freeze_count_for_test() -> int:
	return _freeze_count

func _assertion_results(
	case_definition: Dictionary, transient_record: Dictionary
) -> DomainResult:
	var authored: Array[Dictionary] = _authored_assertions(case_definition)
	var outcomes_result: DomainResult = _collect_assertion_outcomes(transient_record)
	if not outcomes_result.is_success():
		return outcomes_result
	var outcomes: Array = outcomes_result.value()
	var reached_end: bool = transient_record.get("terminal_flow") == "reached_end"
	if reached_end and outcomes.size() != authored.size():
		return _failure("End must return one assertion outcome per authored assertion")
	if not reached_end and not outcomes.is_empty():
		return _failure("assertion outcomes exist for a case that did not reach End")
	return _build_assertion_results(authored, outcomes)

func _collect_assertion_outcomes(transient_record: Dictionary) -> DomainResult:
	var outcomes: Array = []
	var node_results: Variant = transient_record.get("node_results", null)
	if typeof(node_results) != TYPE_ARRAY:
		return _failure("executed case node results are missing")
	for raw_node_result: Variant in node_results:
		if typeof(raw_node_result) != TYPE_DICTIONARY:
			return _failure("executed node result is invalid")
		var raw_outcomes: Variant = raw_node_result.get("assertion_results", [])
		if typeof(raw_outcomes) != TYPE_ARRAY:
			return _failure("assertion outcomes must be an array")
		outcomes.append_array(raw_outcomes)
	return DomainResultType.success(outcomes)

func _build_assertion_results(
	authored: Array[Dictionary], outcomes: Array
) -> DomainResult:
	var results: Array[CourseworkAssertionResult] = []
	for index: int in range(outcomes.size()):
		if typeof(outcomes[index]) != TYPE_DICTIONARY:
			return _failure("assertion outcome or authored assertion is invalid")
		var outcome: Dictionary = outcomes[index]
		var authored_assertion: Dictionary = authored[index]
		if not _assertion_outcome_matches_authored(outcome, authored_assertion):
			return _failure("assertion outcome does not match its authored assertion")
		var created: DomainResult = AssertionResultType.create(
			outcome["assertion_id"], outcome["expected"], outcome["observed"],
			outcome["comparison"], outcome["pass"])
		if not created.is_success():
			return created
		results.append(created.value())
	return DomainResultType.success(results)

func _assertion_outcome_matches_authored(
	outcome: Dictionary, authored: Dictionary
) -> bool:
	if not _has_exact_keys(
		outcome, ["assertion_id", "expected", "observed", "comparison", "pass"]
	):
		return false
	if outcome["assertion_id"] != authored.get("assertion_id") \
			or not CanonicalJsonIRType.equal(
				outcome["expected"], authored.get("expected")):
		return false
	if outcome["comparison"] != "equal" or typeof(outcome["pass"]) != TYPE_BOOL:
		return false
	return outcome["pass"] == CanonicalJsonIRType.equal(
		outcome["expected"], outcome["observed"])

func _may_change_terminal_state() -> bool:
	return not _frozen and _case_results.is_empty() and _run_error.is_empty()

func _may_append_case() -> bool:
	return not _frozen and _validation_pass and _run_error.is_empty()

static func _identity_from_input(input: Variant) -> Dictionary:
	if input is RunInputType and is_instance_valid(input) and input.is_valid():
		return {
			"task_id": input.task_id(),
			"day_index": input.day_index(),
			"request_id": input.request_id(),
			"graph_revision": input.graph_revision(),
			"input_identity_sha256": input.identity_sha256(),
			"admitted_content_digest": input.admitted_content_digest(),
		}
	return {
		"task_id": "",
		"day_index": -1,
		"request_id": "",
		"graph_revision": -1,
		"input_identity_sha256": "",
		"admitted_content_digest": "",
	}

static func _authored_assertions(case_definition: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var content: Variant = case_definition.get(
		"content", case_definition.get("case_content", case_definition))
	if typeof(content) != TYPE_DICTIONARY:
		return result
	var assertions: Variant = content.get("assertions", [])
	if typeof(assertions) != TYPE_ARRAY:
		return result
	for raw_assertion: Variant in assertions:
		if typeof(raw_assertion) != TYPE_DICTIONARY:
			return []
		result.append(Dictionary(raw_assertion).duplicate(true))
	return result

static func _case_id(case_definition: Dictionary) -> String:
	return String(case_definition.get(
		"case_id", case_definition.get("test_case_id", "")))

static func _run_error_record(
	kind: String, code: String, message: String, case_id: String
) -> Dictionary:
	return {
		"kind": kind,
		"code": code,
		"message": message,
		"case_id": case_id,
	}

static func _system_error_matches_case(error: Dictionary, case_id: String) -> bool:
	return _system_error_is_valid(error) and not case_id.is_empty() \
		and error["case_id"] == case_id

static func _system_error_is_valid(error: Dictionary) -> bool:
	return error.size() == 4 \
		and error.get("kind") == "system_error" \
		and typeof(error.get("code")) == TYPE_STRING \
		and not String(error.get("code")).is_empty() \
		and typeof(error.get("message")) == TYPE_STRING \
		and not String(error.get("message")).is_empty() \
		and _stable_id_is_valid(error.get("case_id"))

func _semantic_identity_matches(report_identity: Dictionary) -> bool:
	return report_identity.get("task_id") == _identity.get("task_id") \
		and report_identity.get("day_index") == _identity.get("day_index") \
		and report_identity.get("request_id") == _identity.get("request_id") \
		and report_identity.get("graph_revision") == _identity.get("graph_revision") \
		and report_identity.get("input_identity_sha256") \
			== _identity.get("input_identity_sha256")

static func _stable_id_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var identity: String = value
	if identity.is_empty() or identity.length() > 64:
		return false
	var bytes: PackedByteArray = identity.to_utf8_buffer()
	var first: int = bytes[0]
	if not (first >= 0x41 and first <= 0x5a or first >= 0x61 and first <= 0x7a):
		return false
	for byte: int in bytes:
		var alpha: bool = byte >= 0x41 and byte <= 0x5a \
			or byte >= 0x61 and byte <= 0x7a
		var digit: bool = byte >= 0x30 and byte <= 0x39
		if not alpha and not digit and byte not in [0x2e, 0x5f, 0x2d]:
			return false
	return true

static func _copy_cases(value: Array) -> Array[CourseworkCaseResult]:
	var result: Array[CourseworkCaseResult] = []
	for case_result: CourseworkCaseResult in value:
		result.append(case_result.copy_record())
	return result

static func _clone_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for raw_item: Variant in value:
		if typeof(raw_item) != TYPE_DICTIONARY:
			return []
		result.append(CanonicalJsonIRType.clone(raw_item))
	return result

static func _has_exact_keys(dictionary: Dictionary, fields: Array[String]) -> bool:
	if dictionary.size() != fields.size():
		return false
	for raw_key: Variant in dictionary.keys():
		if typeof(raw_key) != TYPE_STRING or not fields.has(String(raw_key)):
			return false
	return true

static func _failure(message: String) -> DomainResult:
	return DomainResultType.failure(&"result_builder_error", message)
