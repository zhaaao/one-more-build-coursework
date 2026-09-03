class_name SemanticValidationReport
extends RefCounted

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CanonicalCodecType = preload("res://src/foundation/canonical_codec.gd")
const SemanticDiagnosticType = preload("res://src/core/gvet/semantic_diagnostic.gd")
const CourseworkRunInputType = preload("res://src/core/gvet/coursework_run_input.gd")

## Frozen result of the one coursework semantic-validation pass.
##
## A report with findings is a valid terminal semantic rejection, not a domain
## construction error. Execution and final case aggregation are owned by later
## stories; therefore this semantic-stage `suite_pass` is false.
## Example: `SemanticValidationReport.create(input, diagnostics)`.

const REPORT_CODEC_VERSION: String = "coursework_semantic_report_v1"

var _locked: bool = false:
	set(value):
		if _locked:
			return
		_locked = value
var _identity: Dictionary = {}:
	get:
		return _identity.duplicate(true)
	set(value):
		if _locked:
			return
		_identity = value.duplicate(true)
var _diagnostics: Array = []:
	get:
		return _copy_diagnostics(_diagnostics)
	set(value):
		if _locked:
			return
		_diagnostics = _copy_diagnostics(value)
var _canonical_bytes: PackedByteArray = PackedByteArray():
	get:
		return PackedByteArray(_canonical_bytes)
	set(value):
		if _locked:
			return
		_canonical_bytes = PackedByteArray(value)
var _sha256: String = "":
	set(value):
		if _locked:
			return
		_sha256 = value
var _valid: bool = false:
	set(value):
		if _locked:
			return
		_valid = value

## Creates a complete immutable report from the exact admitted input identity.
static func create(input: Variant, diagnostics: Array) -> DomainResult:
	if not input is CourseworkRunInputType or not input.is_valid():
		return DomainResult.failure(&"run_input_error", "semantic report requires a valid CourseworkRunInput")
	var prepared := _prepare_diagnostics(diagnostics)
	if not prepared.is_success():
		return prepared
	var ordered: Array = prepared.value()
	var identity := _identity_from_input(input)
	var dictionary := _wire_dictionary(identity, ordered)
	var encoded: DomainResult = CanonicalCodecType.encode(dictionary)
	if not encoded.is_success():
		return DomainResult.failure(&"semantic_report_error", "semantic report could not be canonicalized")
	var canonical_bytes: PackedByteArray = encoded.value()
	var sha256 := CanonicalCodecType.sha256_hex(canonical_bytes)
	if sha256.is_empty():
		return DomainResult.failure(&"semantic_report_error", "semantic report digest could not be calculated")
	var report := new(input, ordered, canonical_bytes, sha256)
	if not report.is_valid():
		return DomainResult.failure(&"semantic_report_error", "semantic report construction failed")
	return DomainResult.success(report)

func _init(
	input: Variant = null,
	diagnostics: Array = [],
	canonical_bytes: PackedByteArray = PackedByteArray(),
	sha256: String = ""
) -> void:
	if not input is CourseworkRunInputType or not input.is_valid():
		_locked = true
		return
	var prepared := _prepare_diagnostics(diagnostics)
	if not prepared.is_success():
		_locked = true
		return
	var ordered: Array = prepared.value()
	var identity := _identity_from_input(input)
	var encoded: DomainResult = CanonicalCodecType.encode(_wire_dictionary(identity, ordered))
	if not encoded.is_success():
		_locked = true
		return
	var expected_bytes: PackedByteArray = encoded.value()
	var expected_sha := CanonicalCodecType.sha256_hex(expected_bytes)
	if canonical_bytes != expected_bytes or sha256 != expected_sha:
		_locked = true
		return
	_identity = identity
	_diagnostics = ordered
	_canonical_bytes = canonical_bytes
	_sha256 = sha256
	_valid = true
	_locked = true

## Returns whether the frozen report passed all constructor checks.
func is_valid() -> bool:
	return _valid

## Returns true only when no semantic diagnostic exists.
func validation_pass() -> bool:
	return _diagnostics.is_empty()

## Returns false at the semantic stage; only the final run result may pass a suite.
func suite_pass() -> bool:
	return false

## Returns whether case execution must be blocked.
func execution_blocked() -> bool:
	return not validation_pass()

## Returns the immutable input identity used by this validation pass.
func identity() -> Dictionary:
	return _identity.duplicate(true)

## Returns detached immutable diagnostic records in total order.
func diagnostics() -> Array:
	return _copy_diagnostics(_diagnostics)

## Returns pure-data diagnostic records in total order.
func diagnostic_records() -> Array:
	var records: Array = []
	for diagnostic: SemanticDiagnostic in _diagnostics:
		records.append(diagnostic.to_dictionary())
	return records

## Returns stable reason codes in total order.
func reason_codes() -> Array[String]:
	var codes: Array[String] = []
	for diagnostic: SemanticDiagnostic in _diagnostics:
		codes.append(diagnostic.reason_code())
	return codes

## Compatibility alias for callers that render code lists.
func projected_reason_codes() -> Array[String]:
	return reason_codes()

## Returns the complete number of semantic findings.
func diagnostic_count() -> int:
	return _diagnostics.size()

## Returns stable canonical bytes for report equality and the later result boundary.
func canonical_bytes() -> PackedByteArray:
	return PackedByteArray(_canonical_bytes)

## Returns lowercase SHA-256 of `canonical_bytes()`.
func sha256_hex() -> String:
	return _sha256

## Returns the complete pure-data report.
func to_dictionary() -> Dictionary:
	return _wire_dictionary(_identity, _diagnostics)

## Converts a successful semantic pass into the internal Story001 receipt.
## A rejection remains the frozen report and cannot construct `PreparedRun`.
func preparation_receipt() -> DomainResult:
	if not validation_pass():
		return DomainResult.failure(&"semantic_invalid", "semantic diagnostics block case execution")
	return DomainResult.success({
		"validation_pass": true,
		"input_identity_sha256": String(_identity["input_identity_sha256"]),
		"diagnostics": [],
	})

## Compares complete frozen semantic content.
func equals(other: SemanticValidationReport) -> bool:
	return other != null and _canonical_bytes == other.canonical_bytes()

static func _identity_from_input(input: CourseworkRunInput) -> Dictionary:
	return {
		"task_id": input.task_id(),
		"day_index": input.day_index(),
		"request_id": input.request_id(),
		"graph_revision": input.graph_revision(),
		"input_identity_sha256": input.identity_sha256(),
	}

static func _wire_dictionary(identity: Dictionary, diagnostics: Array) -> Dictionary:
	var records: Array = []
	for diagnostic: SemanticDiagnostic in diagnostics:
		records.append(diagnostic.to_dictionary())
	return {
		"report_codec_version": REPORT_CODEC_VERSION,
		"task_id": String(identity.get("task_id", "")),
		"day_index": int(identity.get("day_index", 0)),
		"request_id": String(identity.get("request_id", "")),
		"graph_revision": int(identity.get("graph_revision", -1)),
		"input_identity_sha256": String(identity.get("input_identity_sha256", "")),
		"validation_pass": records.is_empty(),
		"suite_pass": false,
		"diagnostics": records,
	}

static func _prepare_diagnostics(diagnostics: Array) -> DomainResult:
	var copied: Array = []
	var seen: Dictionary = {}
	for raw_diagnostic: Variant in diagnostics:
		if not raw_diagnostic is SemanticDiagnosticType or not raw_diagnostic.is_valid():
			return DomainResult.failure(&"invalid_diagnostic", "semantic report accepts only valid diagnostics")
		var diagnostic: SemanticDiagnostic = raw_diagnostic.copy_record()
		var key := _diagnostic_key(diagnostic)
		if seen.has(key):
			continue
		seen[key] = true
		copied.append(diagnostic)
	copied.sort_custom(_diagnostic_less)
	return DomainResult.success(copied)

static func _copy_diagnostics(diagnostics: Array) -> Array:
	var copied: Array = []
	for raw_diagnostic: Variant in diagnostics:
		if raw_diagnostic is SemanticDiagnosticType:
			copied.append(raw_diagnostic.copy_record())
	return copied

static func _diagnostic_key(diagnostic: SemanticDiagnostic) -> String:
	var encoded: DomainResult = CanonicalCodecType.encode(diagnostic.to_dictionary())
	return PackedByteArray(encoded.value()).hex_encode() if encoded.is_success() else ""

static func _diagnostic_less(left: SemanticDiagnostic, right: SemanticDiagnostic) -> bool:
	if left.priority() != right.priority():
		return left.priority() < right.priority()
	if left.primary_entity_id() != right.primary_entity_id():
		return _ordinal_less(left.primary_entity_id(), right.primary_entity_id())
	return _id_arrays_less(left.related_entity_ids(), right.related_entity_ids())

static func _id_arrays_less(left: Array[String], right: Array[String]) -> bool:
	var shared: int = mini(left.size(), right.size())
	for index: int in range(shared):
		if left[index] != right[index]:
			return _ordinal_less(left[index], right[index])
	return left.size() < right.size()

static func _ordinal_less(left: String, right: String) -> bool:
	var left_bytes := left.to_utf8_buffer()
	var right_bytes := right.to_utf8_buffer()
	var shared: int = mini(left_bytes.size(), right_bytes.size())
	for index: int in range(shared):
		if left_bytes[index] != right_bytes[index]:
			return left_bytes[index] < right_bytes[index]
	return left_bytes.size() < right_bytes.size()
