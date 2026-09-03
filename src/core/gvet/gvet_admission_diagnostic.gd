class_name GvetAdmissionDiagnostic
extends RefCounted

## Closed GVET admission diagnostic and result carriers.
##
## The stable outcome is deliberately separate from the bounded lower-layer
## cause. Semantic failures retain the complete immutable diagnostic-record
## projection rather than replacing it with a summary string.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CanonicalJsonIRType = preload("res://src/foundation/canonical_json_ir.gd")
const PreparedRunType = preload("res://src/core/gvet/prepared_run.gd")
const SemanticValidationReportType = preload("res://src/core/gvet/semantic_validation_report.gd")

const OUTCOME_REQUEST_RESOURCE_LIMIT: StringName = &"REQUEST_RESOURCE_LIMIT"
const OUTCOME_EXECUTION_CONTRACT_MISMATCH: StringName = &"EXECUTION_CONTRACT_MISMATCH"
const OUTCOME_CASE_CONTENT_INVALID: StringName = &"CASE_CONTENT_INVALID"
const OUTCOME_SANDBOX_PREPARATION_FAILED: StringName = &"SANDBOX_PREPARATION_FAILED"

var _locked: bool = false:
	set(value):
		if _locked:
			return
		_locked = value
var _outcome_code: StringName = &"":
		set(value):
			if _locked:
				return
			_outcome_code = value
var _phase: StringName = &"":
		set(value):
			if _locked:
				return
			_phase = value
var _cause_code: StringName = &"":
		set(value):
			if _locked:
				return
			_cause_code = value
var _message: String = "":
		set(value):
			if _locked:
				return
			_message = value
var _path_witness: String = "":
		set(value):
			if _locked:
				return
			_path_witness = value
var _byte_offset: int = -1:
		set(value):
			if _locked:
				return
			_byte_offset = value
var _inspected_byte_count: int = 0:
		set(value):
			if _locked:
				return
			_inspected_byte_count = value
var _allocation_disposition: StringName = &"record_not_allocated":
		set(value):
			if _locked:
				return
			_allocation_disposition = value
var _witness: Dictionary = {}:
		get:
			var copied: Variant = CanonicalJsonIRType.clone(_witness)
			return copied if typeof(copied) == TYPE_DICTIONARY else {}
		set(value):
			if _locked:
				return
			var copied: Variant = CanonicalJsonIRType.clone(value)
			_witness = copied if typeof(copied) == TYPE_DICTIONARY else {}
var _semantic_report: SemanticValidationReport = null:
		set(value):
			if _locked:
				return
			_semantic_report = value

func _init(
	outcome_code: StringName = &"",
	phase: StringName = &"",
	result: DomainResult = null,
	witness: Dictionary = {},
	semantic_report: SemanticValidationReport = null
) -> void:
	if semantic_report != null and is_instance_valid(semantic_report) and semantic_report.is_valid():
		var records: Array = semantic_report.diagnostic_records()
		var first_reason: StringName = &""
		if not records.is_empty() and typeof(records[0]) == TYPE_DICTIONARY:
			first_reason = StringName(String(records[0].get("reason_code", "")))
		_outcome_code = first_reason
		_phase = &"semantic"
		_cause_code = first_reason
		_message = "semantic validation report is blocking"
		_path_witness = "$.diagnostic_records[0].reason_code"
		_semantic_report = semantic_report
	elif result != null and is_instance_valid(result):
		_outcome_code = outcome_code
		_phase = phase
		_cause_code = result.error_code()
		_message = result.error_message()
		_path_witness = result.path_witness()
		_byte_offset = result.byte_offset()
		_inspected_byte_count = result.inspected_byte_count()
		_allocation_disposition = result.allocation_disposition()
		_witness = CanonicalJsonIRType.clone(witness)
	_locked = true

## Builds a bounded diagnostic from one lower-layer DomainResult.
## Example: `GvetAdmissionDiagnostic.from_result(code, phase, phase_result)`.
static func from_result(outcome_code: StringName, phase: StringName, result: DomainResult, witness: Dictionary = {}) -> GvetAdmissionDiagnostic:
	return GvetAdmissionDiagnostic.new(outcome_code, phase, result, witness, null)

## Builds the exact semantic-report failure arm.
## Example: `GvetAdmissionDiagnostic.semantic_failure(report)`.
static func semantic_failure(report: SemanticValidationReport) -> GvetAdmissionDiagnostic:
	if report == null or not is_instance_valid(report) or not report is SemanticValidationReportType:
		return from_result(OUTCOME_EXECUTION_CONTRACT_MISMATCH, &"semantic", DomainResultType.failure(&"invalid_semantic_report", "semantic failure requires a SemanticValidationReport"))
	var semantic_report: SemanticValidationReport = report
	return GvetAdmissionDiagnostic.new(&"", &"", null, {}, semantic_report)

## Returns the stable caller-facing outcome code.
## Example: `if diagnostic.outcome_code() == GvetAdmissionDiagnostic.OUTCOME_CASE_CONTENT_INVALID: ...`.
func outcome_code() -> StringName:
	return _outcome_code

## Returns the ordered phase that produced this diagnostic.
## Example: `var phase := diagnostic.phase()`.
func phase() -> StringName:
	return _phase

## Returns the exact lower-layer cause code.
## Example: `var cause := diagnostic.cause_code()`.
func cause_code() -> StringName:
	return _cause_code

## Returns the bounded lower-layer message.
## Example: `var message := diagnostic.message()`.
func message() -> String:
	return _message

## Returns the deterministic locator/path witness.
## Example: `var path := diagnostic.path_witness()`.
func path_witness() -> String:
	return _path_witness

## Returns the byte offset retained by a codec/transport cause.
## Example: `var offset := diagnostic.byte_offset()`.
func byte_offset() -> int:
	return _byte_offset

## Returns the bounded inspected-byte count.
## Example: `var count := diagnostic.inspected_byte_count()`.
func inspected_byte_count() -> int:
	return _inspected_byte_count

## Returns the failure allocation disposition.
## Example: `var disposition := diagnostic.allocation_disposition()`.
func allocation_disposition() -> StringName:
	return _allocation_disposition

## Returns detached witness data, never the owner dictionary.
## Example: `var witness := diagnostic.witness()`.
func witness() -> Dictionary:
	return CanonicalJsonIRType.clone(_witness)

## Returns whether this diagnostic carries the exact semantic report arm.
## Example: `if diagnostic.has_semantic_report(): inspect(diagnostic.semantic_report())`.
func has_semantic_report() -> bool:
	return _semantic_report != null and is_instance_valid(_semantic_report) and _semantic_report.is_valid()

## Returns the immutable semantic report, or null for pre-semantic failures.
## Example: `var report := diagnostic.semantic_report()`.
func semantic_report() -> SemanticValidationReport:
	return _semantic_report

## Returns a detached closed projection suitable for canonical comparison.
## Example: `var projection := diagnostic.to_dictionary()`.
func to_dictionary() -> Dictionary:
	var projection: Dictionary = {
		"outcome_code": String(_outcome_code),
		"phase": String(_phase),
		"cause_code": String(_cause_code),
		"message": _message,
		"path_witness": _path_witness,
		"byte_offset": _byte_offset,
		"inspected_byte_count": _inspected_byte_count,
		"allocation_disposition": String(_allocation_disposition),
		"witness": CanonicalJsonIRType.clone(_witness),
	}
	if has_semantic_report():
		projection["semantic_report"] = _semantic_report.to_dictionary()
		projection["semantic_report_sha256"] = _semantic_report.sha256_hex()
	return projection

## Returns a closed result carrying either PreparedRun or this diagnostic.
class AdmissionResult extends RefCounted:
	var _locked: bool = false:
		set(value):
			if _locked:
				return
			_locked = value
	var _ok: bool = false:
		set(value):
			if _locked:
				return
			_ok = value
	var _prepared_run: PreparedRun = null:
		set(value):
			if _locked:
				return
			_prepared_run = value
	var _diagnostic: GvetAdmissionDiagnostic = null:
		set(value):
			if _locked:
				return
			_diagnostic = value

	func _init(
		ok: bool = false,
		prepared_run: PreparedRun = null,
		diagnostic: GvetAdmissionDiagnostic = null
	) -> void:
		if ok and prepared_run != null and is_instance_valid(prepared_run) and prepared_run.is_valid():
			_ok = true
			_prepared_run = prepared_run
		elif not ok and diagnostic != null and is_instance_valid(diagnostic):
			_diagnostic = diagnostic
		_locked = true

	## Creates a successful admission result.
	## Example: `return GvetAdmissionDiagnostic.AdmissionResult.success(run)`.
	static func success(prepared_run: RefCounted) -> AdmissionResult:
		if prepared_run == null or not is_instance_valid(prepared_run) or not prepared_run is PreparedRunType:
			return AdmissionResult.new()
		var valid_run: PreparedRun = prepared_run
		if not valid_run.is_valid():
			return AdmissionResult.new()
		return AdmissionResult.new(true, valid_run, null)

	## Creates a failed admission result with the exact phase diagnostic.
	## Example: `return GvetAdmissionDiagnostic.AdmissionResult.failure(diagnostic)`.
	static func failure(diagnostic: GvetAdmissionDiagnostic) -> AdmissionResult:
		return AdmissionResult.new(false, null, diagnostic)

	## Returns whether all admission phases committed a PreparedRun.
	## Example: `if result.is_success(): use(result.prepared_run())`.
	func is_success() -> bool:
		return _ok

	## Returns the closed result discriminant.
	## Example: `assert_eq(result.discriminant(), &"accepted")`.
	func discriminant() -> StringName:
		return &"accepted" if _ok else &"rejected"

	## Returns the immutable prepared value on success, otherwise null.
	## Example: `var run: PreparedRun = result.prepared_run() as PreparedRun`.
	func prepared_run() -> PreparedRun:
		return _prepared_run

	## Returns the exact stable failure diagnostic, otherwise null.
	## Example: `var diagnostic := result.diagnostic()`.
	func diagnostic() -> GvetAdmissionDiagnostic:
		return _diagnostic

	## Returns a detached closed result projection.
	## Example: `var projection := result.to_dictionary()`.
	func to_dictionary() -> Dictionary:
		if _ok:
			return {"discriminant": "accepted"}
		return {
			"discriminant": "rejected",
			"diagnostic": _diagnostic.to_dictionary() if _diagnostic != null else {},
		}
