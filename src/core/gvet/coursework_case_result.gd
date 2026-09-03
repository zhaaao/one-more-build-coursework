class_name CourseworkCaseResult
extends RefCounted

## Frozen terminal result for one rostered coursework case.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CanonicalJsonIRType = preload("res://src/foundation/canonical_json_ir.gd")
const AssertionResultType = preload("res://src/core/gvet/coursework_assertion_result.gd")
const TraceEntryType = preload("res://src/core/gvet/coursework_trace_entry.gd")

const STATUS_PASSED: String = "passed"
const STATUS_FAILED: String = "failed"
const STATUS_SYSTEM_ERROR: String = "system_error"
const STATUS_NOT_RUN_SYSTEM_ERROR: String = "not_run_system_error"

var _locked: bool = false:
	set(value):
		if not _locked:
			_locked = value
var _record: Dictionary = {}:
	get:
		return _copy_record_dictionary(_record)
	set(value):
		if not _locked:
			_record = _copy_record_dictionary(value)

## Freezes one completed ordinary case from its trace and assertion outcomes.
## Example: `var result := CourseworkCaseResult.create_executed(
## "case.a", initial_state, final_state, trace, assertions,
## "reached_end", "", "")`.
static func create_executed(
	case_id: Variant,
	initial_state: Variant,
	final_state: Variant,
	trace: Variant,
	assertions: Array,
	terminal_flow: Variant,
	ordinary_failure_code: Variant,
	ordinary_failure_reason: Variant
) -> DomainResult:
	var reached_end: bool = terminal_flow == "reached_end"
	var all_assertions_pass: bool = not assertions.is_empty()
	for raw_assertion: Variant in assertions:
		if not raw_assertion is AssertionResultType \
				or not is_instance_valid(raw_assertion) or not raw_assertion.is_valid():
			return _failure("executed case assertions must be frozen results")
		all_assertions_pass = all_assertions_pass and raw_assertion.passed()
	var case_pass: bool = reached_end and all_assertions_pass
	var record: Dictionary = {
		"case_id": case_id,
		"status": STATUS_PASSED if case_pass else STATUS_FAILED,
		"reached_end": reached_end,
		"case_pass": case_pass,
		"initial_state": initial_state,
		"final_state": final_state,
		"trace": trace,
		"assertions": assertions,
		"terminal_flow": terminal_flow,
		"ordinary_failure_code": ordinary_failure_code,
		"ordinary_failure_reason": ordinary_failure_reason,
		"system_error": {},
	}
	return _freeze_record(record)

## Freezes the active case that encountered a controlled system error.
## Example: `var result := CourseworkCaseResult.create_system_error(
## "case.b", run_error)`.
static func create_system_error(case_id: Variant, run_error: Variant) -> DomainResult:
	return _freeze_record(_system_record(case_id, STATUS_SYSTEM_ERROR, run_error))

## Freezes one later case suppressed by an earlier controlled system error.
## Example: `var result := CourseworkCaseResult.create_not_run_system_error(
## "case.c", run_error)`.
static func create_not_run_system_error(
	case_id: Variant, run_error: Variant
) -> DomainResult:
	return _freeze_record(
		_system_record(case_id, STATUS_NOT_RUN_SYSTEM_ERROR, run_error))

func _init(record: Dictionary = {}) -> void:
	if not _record_is_valid(record):
		_locked = true
		return
	_record = record
	_locked = true

## Returns true only for one complete frozen case result.
## Example: `assert(case_result.is_valid())`.
func is_valid() -> bool:
	return _locked and _record_is_valid(_record)

## Returns the stable rostered case identity.
## Example: `assert(case_result.case_id() == "case.a")`.
func case_id() -> String:
	return String(_record.get("case_id", ""))

## Returns `passed`, `failed`, `system_error`, or `not_run_system_error`.
## Example: `if result.status() == CourseworkCaseResult.STATUS_FAILED: ...`.
func status() -> String:
	return String(_record.get("status", ""))

## Returns whether End evaluated for this case.
## Example: `assert(result.reached_end())`.
func reached_end() -> bool:
	return bool(_record.get("reached_end", false))

## Returns `ReachedEnd AND all(AssertionPass)`.
## Example: `if result.case_pass(): passed_cases += 1`.
func case_pass() -> bool:
	return bool(_record.get("case_pass", false))

## Returns detached trace entries in evaluation order.
## Example: `var trace_copy := result.trace()`.
func trace() -> Array[Dictionary]:
	return _clone_dictionary_array(_record.get("trace", []))

## Returns independently frozen assertion results in authored order.
## Example: `var assertion_copy := result.assertion_results()`.
func assertion_results() -> Array[CourseworkAssertionResult]:
	return _copy_assertions(_record.get("assertions", []))

## Returns a detached controlled error for system-error case arms.
## Example: `var error := result.system_error()`.
func system_error() -> Dictionary:
	return CanonicalJsonIRType.clone(_record.get("system_error", {}))

## Returns a detached pure-data terminal case record.
## Example: `var row := result.to_dictionary()`.
func to_dictionary() -> Dictionary:
	var assertions: Array[Dictionary] = []
	for assertion: CourseworkAssertionResult in _record.get("assertions", []):
		assertions.append(assertion.to_dictionary())
	return {
		"case_id": case_id(),
		"status": status(),
		"reached_end": reached_end(),
		"case_pass": case_pass(),
		"initial_state": CanonicalJsonIRType.clone(_record.get("initial_state", {})),
		"final_state": CanonicalJsonIRType.clone(_record.get("final_state", {})),
		"trace": trace(),
		"assertions": assertions,
		"terminal_flow": String(_record.get("terminal_flow", "")),
		"ordinary_failure_code": String(_record.get("ordinary_failure_code", "")),
		"ordinary_failure_reason": String(_record.get("ordinary_failure_reason", "")),
		"system_error": system_error(),
	}

## Returns an independently frozen copy.
## Example: `var copy := result.copy_record()`.
func copy_record() -> CourseworkCaseResult:
	var copied: CourseworkCaseResult = CourseworkCaseResult.new(_record)
	return copied if copied.is_valid() else null

static func _freeze_record(record: Dictionary) -> DomainResult:
	var result: CourseworkCaseResult = CourseworkCaseResult.new(record)
	if not result.is_valid():
		return _failure("case result fields are invalid")
	return DomainResultType.success(result)

static func _system_record(
	case_id: Variant, status: String, run_error: Variant
) -> Dictionary:
	return {
		"case_id": case_id,
		"status": status,
		"reached_end": false,
		"case_pass": false,
		"initial_state": {},
		"final_state": {},
		"trace": [],
		"assertions": [],
		"terminal_flow": status,
		"ordinary_failure_code": "",
		"ordinary_failure_reason": "",
		"system_error": run_error,
	}

static func _record_is_valid(record: Dictionary) -> bool:
	var fields: Array[String] = [
		"case_id", "status", "reached_end", "case_pass", "initial_state",
		"final_state", "trace", "assertions", "terminal_flow",
		"ordinary_failure_code", "ordinary_failure_reason", "system_error",
	]
	if not _has_exact_keys(record, fields) or not _stable_id_is_valid(record["case_id"]):
		return false
	if typeof(record["status"]) != TYPE_STRING \
			or not [STATUS_PASSED, STATUS_FAILED, STATUS_SYSTEM_ERROR,
				STATUS_NOT_RUN_SYSTEM_ERROR].has(String(record["status"])):
		return false
	if typeof(record["reached_end"]) != TYPE_BOOL \
			or typeof(record["case_pass"]) != TYPE_BOOL \
			or typeof(record["initial_state"]) != TYPE_DICTIONARY \
			or typeof(record["final_state"]) != TYPE_DICTIONARY \
			or typeof(record["trace"]) != TYPE_ARRAY \
			or typeof(record["assertions"]) != TYPE_ARRAY \
			or typeof(record["terminal_flow"]) != TYPE_STRING \
			or typeof(record["ordinary_failure_code"]) != TYPE_STRING \
			or typeof(record["ordinary_failure_reason"]) != TYPE_STRING \
			or typeof(record["system_error"]) != TYPE_DICTIONARY:
		return false
	if not CanonicalJsonIRType.validate_pure_json(record["initial_state"]).is_success() \
			or not CanonicalJsonIRType.validate_pure_json(record["final_state"]).is_success():
		return false
	if not _trace_is_valid(record["trace"]) or not _assertions_are_valid(record["assertions"]):
		return false
	var status: String = record["status"]
	if status == STATUS_PASSED or status == STATUS_FAILED:
		return _executed_state_is_valid(record)
	return _system_state_is_valid(record)

static func _executed_state_is_valid(record: Dictionary) -> bool:
	if Array(record["trace"]).is_empty() or not Dictionary(record["system_error"]).is_empty():
		return false
	var reached_end: bool = record["reached_end"]
	var assertions: Array = record["assertions"]
	if reached_end != (record["terminal_flow"] == "reached_end"):
		return false
	if reached_end and assertions.is_empty():
		return false
	if not reached_end and not assertions.is_empty():
		return false
	var expected_pass: bool = reached_end and _all_assertions_pass(assertions)
	if record["case_pass"] != expected_pass:
		return false
	if (record["status"] == STATUS_PASSED) != expected_pass:
		return false
	if not reached_end and String(record["ordinary_failure_code"]).is_empty():
		return false
	if expected_pass and not String(record["ordinary_failure_code"]).is_empty():
		return false
	return true

static func _system_state_is_valid(record: Dictionary) -> bool:
	var system_error: Dictionary = record["system_error"]
	if record["status"] == STATUS_SYSTEM_ERROR \
			and system_error.get("case_id") != record["case_id"]:
		return false
	if record["status"] == STATUS_NOT_RUN_SYSTEM_ERROR \
			and system_error.get("case_id") == record["case_id"]:
		return false
	return not record["reached_end"] and not record["case_pass"] \
		and Dictionary(record["initial_state"]).is_empty() \
		and Dictionary(record["final_state"]).is_empty() \
		and Array(record["trace"]).is_empty() \
		and Array(record["assertions"]).is_empty() \
		and String(record["ordinary_failure_code"]).is_empty() \
		and String(record["ordinary_failure_reason"]).is_empty() \
		and record["terminal_flow"] == record["status"] \
		and _run_error_is_valid(system_error)

static func _trace_is_valid(trace: Array) -> bool:
	var expected_step: int = 1
	for raw_entry: Variant in trace:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			return false
		var entry: CourseworkTraceEntry = TraceEntryType.new(raw_entry)
		if not entry.is_valid() or entry.step_number() != expected_step:
			return false
		expected_step += 1
	return true

static func _assertions_are_valid(assertions: Array) -> bool:
	var seen: Dictionary = {}
	for raw_assertion: Variant in assertions:
		if not raw_assertion is AssertionResultType \
				or not is_instance_valid(raw_assertion) or not raw_assertion.is_valid():
			return false
		var assertion: CourseworkAssertionResult = raw_assertion
		if seen.has(assertion.assertion_id()):
			return false
		seen[assertion.assertion_id()] = true
	return true

static func _all_assertions_pass(assertions: Array) -> bool:
	for assertion: CourseworkAssertionResult in assertions:
		if not assertion.passed():
			return false
	return true

static func _run_error_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var error: Dictionary = value
	if not _has_exact_keys(error, ["kind", "code", "message", "case_id"]):
		return false
	return error["kind"] == "system_error" \
		and typeof(error["code"]) == TYPE_STRING and not String(error["code"]).is_empty() \
		and typeof(error["message"]) == TYPE_STRING and not String(error["message"]).is_empty() \
		and _stable_id_is_valid(error["case_id"])

static func _copy_record_dictionary(value: Dictionary) -> Dictionary:
	var result: Dictionary = value.duplicate(true)
	if typeof(value.get("assertions", null)) == TYPE_ARRAY:
		result["assertions"] = _copy_assertions(value["assertions"])
	return result

static func _copy_assertions(value: Variant) -> Array[CourseworkAssertionResult]:
	var result: Array[CourseworkAssertionResult] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for raw_assertion: Variant in value:
		if raw_assertion is AssertionResultType and is_instance_valid(raw_assertion):
			var copy: CourseworkAssertionResult = raw_assertion.copy_record()
			if copy != null:
				result.append(copy)
	return result

static func _clone_dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for raw_entry: Variant in value:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			return []
		result.append(CanonicalJsonIRType.clone(raw_entry))
	return result

static func _stable_id_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var identity: String = value
	if identity.is_empty() or identity.length() > 64:
		return false
	var bytes: PackedByteArray = identity.to_utf8_buffer()
	var first: int = bytes[0]
	if not _is_alpha(first):
		return false
	for byte: int in bytes:
		if not _is_alpha(byte) and not _is_digit(byte) \
				and byte not in [0x2e, 0x5f, 0x2d]:
			return false
	return true

static func _is_alpha(byte: int) -> bool:
	return byte >= 0x41 and byte <= 0x5a or byte >= 0x61 and byte <= 0x7a

static func _is_digit(byte: int) -> bool:
	return byte >= 0x30 and byte <= 0x39

static func _has_exact_keys(dictionary: Dictionary, fields: Array[String]) -> bool:
	if dictionary.size() != fields.size():
		return false
	for raw_key: Variant in dictionary.keys():
		if typeof(raw_key) != TYPE_STRING or not fields.has(String(raw_key)):
			return false
	return true

static func _failure(message: String) -> DomainResult:
	return DomainResultType.failure(&"case_result_error", message)
