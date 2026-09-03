class_name CourseworkAssertionResult
extends RefCounted

## Frozen result of one authored coursework assertion.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CanonicalJsonIRType = preload("res://src/foundation/canonical_json_ir.gd")

var _locked: bool = false:
	set(value):
		if not _locked:
			_locked = value
var _assertion_id: String = "":
	set(value):
		if not _locked:
			_assertion_id = value
var _expected: Variant = null:
	get:
		return CanonicalJsonIRType.clone(_expected)
	set(value):
		if not _locked:
			_expected = CanonicalJsonIRType.clone(value)
var _observed: Variant = null:
	get:
		return CanonicalJsonIRType.clone(_observed)
	set(value):
		if not _locked:
			_observed = CanonicalJsonIRType.clone(value)
var _comparison: String = "":
	set(value):
		if not _locked:
			_comparison = value
var _passed: bool = false:
	set(value):
		if not _locked:
			_passed = value

## Validates, detaches, and freezes one authored-order assertion outcome.
## Example: `var result := CourseworkAssertionResult.create(
## "assert.value", 5, observed_value, "equal", observed_value == 5)`.
static func create(
	assertion_id: Variant,
	expected: Variant,
	observed: Variant,
	comparison: Variant,
	passed: Variant
) -> DomainResult:
	var record: Dictionary = {
		"assertion_id": assertion_id,
		"expected": expected,
		"observed": observed,
		"comparison": comparison,
		"pass": passed,
	}
	if not _record_is_valid(record):
		return DomainResultType.failure(
			&"assertion_result_error", "assertion result fields are invalid")
	var result: CourseworkAssertionResult = CourseworkAssertionResult.new(record)
	if not result.is_valid():
		return DomainResultType.failure(
			&"assertion_result_error", "assertion result could not be frozen")
	return DomainResultType.success(result)

func _init(record: Dictionary = {}) -> void:
	if not _record_is_valid(record):
		_locked = true
		return
	_assertion_id = record["assertion_id"]
	_expected = record["expected"]
	_observed = record["observed"]
	_comparison = record["comparison"]
	_passed = record["pass"]
	_locked = true

## Returns true only for one complete frozen assertion result.
## Example: `assert(assertion_result.is_valid())`.
func is_valid() -> bool:
	return _locked and _record_is_valid(to_dictionary())

## Returns the authored stable assertion identity.
## Example: `assert(result.assertion_id() == "assert.value")`.
func assertion_id() -> String:
	return _assertion_id

## Returns a detached expected fact.
## Example: `var expected_copy := result.expected()`.
func expected() -> Variant:
	return _expected

## Returns a detached observed fact.
## Example: `var observed_copy := result.observed()`.
func observed() -> Variant:
	return _observed

## Returns the authored comparison identifier.
## Example: `assert(result.comparison() == "equal")`.
func comparison() -> String:
	return _comparison

## Returns the frozen assertion outcome.
## Example: `if result.passed(): passed_count += 1`.
func passed() -> bool:
	return _passed

## Returns a detached pure-data assertion result.
## Example: `var row := result.to_dictionary()`.
func to_dictionary() -> Dictionary:
	return {
		"assertion_id": _assertion_id,
		"expected": CanonicalJsonIRType.clone(_expected),
		"observed": CanonicalJsonIRType.clone(_observed),
		"comparison": _comparison,
		"pass": _passed,
	}

## Returns an independently frozen copy.
## Example: `var copy := result.copy_record()`.
func copy_record() -> CourseworkAssertionResult:
	var copied: DomainResult = create(
		_assertion_id, _expected, _observed, _comparison, _passed)
	return copied.value() if copied.is_success() else null

static func _record_is_valid(record: Dictionary) -> bool:
	if not _has_exact_keys(
		record, ["assertion_id", "expected", "observed", "comparison", "pass"]
	):
		return false
	return _stable_id_is_valid(record["assertion_id"]) \
		and typeof(record["comparison"]) == TYPE_STRING \
		and not String(record["comparison"]).is_empty() \
		and typeof(record["pass"]) == TYPE_BOOL \
		and CanonicalJsonIRType.validate_pure_json(record["expected"]).is_success() \
		and CanonicalJsonIRType.validate_pure_json(record["observed"]).is_success()

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
