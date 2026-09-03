class_name CourseworkRunResult
extends RefCounted

## Complete immutable terminal report for one synchronous coursework Run.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CanonicalCodecType = preload("res://src/foundation/canonical_codec.gd")
const CanonicalJsonIRType = preload("res://src/foundation/canonical_json_ir.gd")
const CaseResultType = preload("res://src/core/gvet/coursework_case_result.gd")

const REPORT_CODEC_VERSION: String = "coursework_run_result_v1"

var _locked: bool = false:
	set(value):
		if not _locked:
			_locked = value
var _identity: Dictionary = {}:
	get:
		return CanonicalJsonIRType.clone(_identity)
	set(value):
		if not _locked:
			_identity = CanonicalJsonIRType.clone(value)
var _validation_pass: bool = false:
	set(value):
		if not _locked:
			_validation_pass = value
var _diagnostics: Array[Dictionary] = []:
	get:
		return _clone_dictionary_array(_diagnostics)
	set(value):
		if not _locked:
			_diagnostics = _clone_dictionary_array(value)
var _case_results: Array[CourseworkCaseResult] = []:
	get:
		return _copy_cases(_case_results)
	set(value):
		if not _locked:
			_case_results = _copy_cases(value)
var _suite_pass: bool = false:
	set(value):
		if not _locked:
			_suite_pass = value
var _run_error: Dictionary = {}:
	get:
		return CanonicalJsonIRType.clone(_run_error)
	set(value):
		if not _locked:
			_run_error = CanonicalJsonIRType.clone(value)
var _canonical_bytes: PackedByteArray = PackedByteArray():
	get:
		return PackedByteArray(_canonical_bytes)
	set(value):
		if not _locked:
			_canonical_bytes = PackedByteArray(value)
var _sha256: String = "":
	set(value):
		if not _locked:
			_sha256 = value

static func _freeze_from_builder(record: Dictionary) -> DomainResult:
	if not _record_is_valid(record):
		return _failure("run result fields are invalid")
	var result: CourseworkRunResult = CourseworkRunResult.new(record)
	if not result.is_valid():
		return _failure("run result could not be frozen")
	return DomainResultType.success(result)

func _init(record: Dictionary = {}) -> void:
	if not _record_is_valid(record):
		_locked = true
		return
	_identity = record["identity"]
	_validation_pass = record["validation_pass"]
	_diagnostics = record["diagnostics"]
	_case_results = record["case_results"]
	_suite_pass = record["suite_pass"]
	_run_error = record["run_error"]
	var encoded: DomainResult = CanonicalCodecType.encode(_wire_dictionary())
	if not encoded.is_success():
		_locked = true
		return
	_canonical_bytes = encoded.value()
	_sha256 = CanonicalCodecType.sha256_hex(_canonical_bytes)
	_locked = true

## Returns true only for one complete, canonical, frozen terminal report.
## Example: `assert(run_result.is_valid())`.
func is_valid() -> bool:
	if not _locked or not _record_is_valid(_state_record()):
		return false
	var encoded: DomainResult = CanonicalCodecType.encode(_wire_dictionary())
	return encoded.is_success() \
		and PackedByteArray(encoded.value()) == _canonical_bytes \
		and CanonicalCodecType.sha256_hex(_canonical_bytes) == _sha256

## Returns detached input identity fields for the attempted Run.
## Example: `var identity_copy := result.identity()`.
func identity() -> Dictionary:
	return _identity

## Returns whether semantic validation admitted case execution.
## Example: `if not result.validation_pass(): show_diagnostics()`.
func validation_pass() -> bool:
	return _validation_pass

## Returns detached semantic diagnostics in stable order.
## Example: `var rows := result.diagnostics()`.
func diagnostics() -> Array[Dictionary]:
	return _diagnostics

## Returns independently frozen case results in roster order.
## Example: `var cases := result.case_results()`.
func case_results() -> Array[CourseworkCaseResult]:
	return _case_results

## Returns `ValidationPass AND NoSystemFailure AND all(CasePass)`.
## Example: `if result.suite_pass(): show_success()`.
func suite_pass() -> bool:
	return _suite_pass

## Returns a detached input/system error, or an empty dictionary.
## Example: `var error := result.run_error()`.
func run_error() -> Dictionary:
	return _run_error

## Returns stable canonical bytes for complete report equality.
## Example: `var bytes := result.canonical_bytes()`.
func canonical_bytes() -> PackedByteArray:
	return _canonical_bytes

## Returns lowercase SHA-256 of `canonical_bytes()`.
## Example: `assert(result.sha256_hex().length() == 64)`.
func sha256_hex() -> String:
	return _sha256

## Returns the detached complete pure-data terminal report.
## Example: `var report := result.to_dictionary()`.
func to_dictionary() -> Dictionary:
	return _wire_dictionary()

func _state_record() -> Dictionary:
	return {
		"identity": _identity,
		"validation_pass": _validation_pass,
		"diagnostics": _diagnostics,
		"case_results": _case_results,
		"suite_pass": _suite_pass,
		"run_error": _run_error,
	}

func _wire_dictionary() -> Dictionary:
	var cases: Array[Dictionary] = []
	for case_result: CourseworkCaseResult in _case_results:
		cases.append(case_result.to_dictionary())
	return {
		"report_codec_version": REPORT_CODEC_VERSION,
		"identity": CanonicalJsonIRType.clone(_identity),
		"validation_pass": _validation_pass,
		"diagnostics": _clone_dictionary_array(_diagnostics),
		"case_results": cases,
		"suite_pass": _suite_pass,
		"run_error": CanonicalJsonIRType.clone(_run_error),
	}

static func _record_is_valid(record: Dictionary) -> bool:
	if not _has_exact_keys(record, [
		"identity", "validation_pass", "diagnostics", "case_results",
		"suite_pass", "run_error",
	]):
		return false
	if typeof(record["identity"]) != TYPE_DICTIONARY \
			or typeof(record["validation_pass"]) != TYPE_BOOL \
			or typeof(record["diagnostics"]) != TYPE_ARRAY \
			or typeof(record["case_results"]) != TYPE_ARRAY \
			or typeof(record["suite_pass"]) != TYPE_BOOL \
			or typeof(record["run_error"]) != TYPE_DICTIONARY:
		return false
	if not _identity_is_valid(record["identity"]) \
			or not _diagnostics_are_valid(record["diagnostics"]) \
			or not _cases_are_valid(record["case_results"]) \
			or not _run_error_is_valid(record["run_error"]):
		return false
	return _terminal_formula_is_valid(record)

static func _identity_is_valid(value: Dictionary) -> bool:
	if not _has_exact_keys(value, [
		"task_id", "day_index", "request_id", "graph_revision",
		"input_identity_sha256", "admitted_content_digest",
	]):
		return false
	if typeof(value["task_id"]) != TYPE_STRING \
			or typeof(value["day_index"]) != TYPE_INT \
			or typeof(value["request_id"]) != TYPE_STRING \
			or typeof(value["graph_revision"]) != TYPE_INT \
			or typeof(value["input_identity_sha256"]) != TYPE_STRING \
			or typeof(value["admitted_content_digest"]) != TYPE_STRING:
		return false
	var empty_identity: bool = String(value["task_id"]).is_empty() \
		and value["day_index"] == -1 \
		and String(value["request_id"]).is_empty() \
		and value["graph_revision"] == -1 \
		and String(value["input_identity_sha256"]).is_empty() \
		and String(value["admitted_content_digest"]).is_empty()
	if empty_identity:
		return true
	return not String(value["task_id"]).is_empty() \
		and int(value["day_index"]) >= 1 and int(value["day_index"]) <= 5 \
		and not String(value["request_id"]).is_empty() \
		and int(value["graph_revision"]) >= 0 \
		and _lower_sha256_is_valid(value["input_identity_sha256"]) \
		and _lower_sha256_is_valid(value["admitted_content_digest"])

static func _diagnostics_are_valid(value: Array) -> bool:
	for diagnostic: Variant in value:
		if typeof(diagnostic) != TYPE_DICTIONARY \
				or not CanonicalJsonIRType.validate_pure_json(diagnostic).is_success():
			return false
	return true

static func _cases_are_valid(value: Array) -> bool:
	var seen: Dictionary = {}
	for raw_case: Variant in value:
		if not raw_case is CaseResultType \
				or not is_instance_valid(raw_case) or not raw_case.is_valid():
			return false
		var case_result: CourseworkCaseResult = raw_case
		if seen.has(case_result.case_id()):
			return false
		seen[case_result.case_id()] = true
	return true

static func _run_error_is_valid(value: Dictionary) -> bool:
	if value.is_empty():
		return true
	if not _has_exact_keys(value, ["kind", "code", "message", "case_id"]):
		return false
	if typeof(value["kind"]) != TYPE_STRING \
			or not ["input_error", "system_error"].has(String(value["kind"])) \
			or typeof(value["code"]) != TYPE_STRING or String(value["code"]).is_empty() \
			or typeof(value["message"]) != TYPE_STRING or String(value["message"]).is_empty() \
			or typeof(value["case_id"]) != TYPE_STRING:
		return false
	return value["kind"] == "input_error" and String(value["case_id"]).is_empty() \
		or value["kind"] == "system_error" and _stable_id_is_valid(value["case_id"])

static func _terminal_formula_is_valid(record: Dictionary) -> bool:
	var validation_pass: bool = record["validation_pass"]
	var diagnostics: Array = record["diagnostics"]
	var cases: Array = record["case_results"]
	var run_error: Dictionary = record["run_error"]
	if validation_pass and not diagnostics.is_empty():
		return false
	if not validation_pass and diagnostics.is_empty() \
			and (run_error.is_empty() or run_error.get("kind") != "input_error"):
		return false
	if not validation_pass and not cases.is_empty():
		return false
	if not run_error.is_empty() and run_error["kind"] == "input_error" \
			and validation_pass:
		return false
	if not _system_topology_is_valid(cases, run_error):
		return false
	var no_system_failure: bool = run_error.is_empty() \
		or run_error["kind"] != "system_error"
	var all_cases_pass: bool = not cases.is_empty()
	for case_result: CourseworkCaseResult in cases:
		all_cases_pass = all_cases_pass and case_result.case_pass()
	var expected_suite: bool = validation_pass and no_system_failure and all_cases_pass
	return record["suite_pass"] == expected_suite

static func _system_topology_is_valid(
	cases: Array, run_error: Dictionary
) -> bool:
	if run_error.is_empty():
		return _has_no_system_cases(cases)
	if run_error["kind"] == "input_error":
		return cases.is_empty()
	return _system_case_sequence_is_valid(cases, run_error)

static func _has_no_system_cases(cases: Array) -> bool:
	for case_result: CourseworkCaseResult in cases:
		if [CaseResultType.STATUS_SYSTEM_ERROR,
				CaseResultType.STATUS_NOT_RUN_SYSTEM_ERROR].has(case_result.status()):
			return false
	return true

static func _system_case_sequence_is_valid(
	cases: Array, run_error: Dictionary
) -> bool:
	var active_error_seen: bool = false
	for case_result: CourseworkCaseResult in cases:
		if active_error_seen:
			if case_result.status() != CaseResultType.STATUS_NOT_RUN_SYSTEM_ERROR \
					or case_result.system_error() != run_error:
				return false
			continue
		if case_result.status() == CaseResultType.STATUS_NOT_RUN_SYSTEM_ERROR:
			return false
		if case_result.status() == CaseResultType.STATUS_SYSTEM_ERROR:
			if case_result.case_id() != run_error["case_id"] \
					or case_result.system_error() != run_error:
				return false
			active_error_seen = true
	return active_error_seen

static func _copy_cases(value: Variant) -> Array[CourseworkCaseResult]:
	var result: Array[CourseworkCaseResult] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for raw_case: Variant in value:
		if raw_case is CaseResultType and is_instance_valid(raw_case):
			var copied: CourseworkCaseResult = raw_case.copy_record()
			if copied != null:
				result.append(copied)
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

static func _lower_sha256_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or String(value).length() != 64:
		return false
	for byte: int in String(value).to_utf8_buffer():
		if not (byte >= 0x30 and byte <= 0x39) \
				and not (byte >= 0x61 and byte <= 0x66):
			return false
	return true

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

static func _has_exact_keys(dictionary: Dictionary, fields: Array[String]) -> bool:
	if dictionary.size() != fields.size():
		return false
	for raw_key: Variant in dictionary.keys():
		if typeof(raw_key) != TYPE_STRING or not fields.has(String(raw_key)):
			return false
	return true

static func _failure(message: String) -> DomainResult:
	return DomainResultType.failure(&"run_result_error", message)
