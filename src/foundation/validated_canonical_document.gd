class_name ValidatedCanonicalDocument
extends RefCounted

const IR = preload("res://src/foundation/canonical_json_ir.gd")

## Immutable Foundation evidence for one validated canonical document.
##
## The original bytes are retained as an owned copy for diagnostics. The
## canonical bytes, digest, and parsed value are all proven from the supplied
## raw bytes before this owner publishes its immutable instance fields.

# GDScript has no language-level private fields. These compatibility properties
# are write-once and defensive: construction writes them while unlocked, then
# the latch permanently rejects caller mutation before publication.
var _locked: bool = false:
	set(value):
		if _locked:
			return
		_locked = value

var _raw_bytes: PackedByteArray = PackedByteArray():
	get:
		return _raw_bytes.duplicate()
	set(value):
		if _locked:
			return
		_raw_bytes = PackedByteArray(value).duplicate()

var _canonical_bytes: PackedByteArray = PackedByteArray():
	get:
		return _canonical_bytes.duplicate()
	set(value):
		if _locked:
			return
		_canonical_bytes = PackedByteArray(value).duplicate()

var _sha256: String = "":
	set(value):
		if _locked:
			return
		_sha256 = value

var _value: Variant = null:
	get:
		return IR.clone(_value)
	set(value):
		if _locked:
			return
		_value = IR.clone(value)

var _valid: bool = false:
	set(value):
		if _locked:
			return
		_valid = value

var _error_code: StringName = &"invalid_document":
	set(value):
		if _locked:
			return
		_error_code = value

var _error_message: String = "validated document is invalid":
	set(value):
		if _locked:
			return
		_error_message = value

var _error_path: String = "":
	set(value):
		if _locked:
			return
		_error_path = value

var _error_byte_offset: int = -1:
	set(value):
		if _locked:
			return
		_error_byte_offset = value

var _error_inspected_byte_count: int = 0:
	set(value):
		if _locked:
			return
		_error_inspected_byte_count = value

var _error_allocation_disposition: StringName = &"record_not_allocated":
	set(value):
		if _locked:
			return
		_error_allocation_disposition = value

## Constructs a document only after re-decoding the supplied raw bytes under
## the same profile and proving the canonical/value/digest tuple.
## Example: `ValidatedCanonicalDocument.create(raw, canonical, digest, value)`.
static func create(raw_bytes: PackedByteArray, canonical_bytes: PackedByteArray, digest: String, value: Variant, profile: ContractShapeProfile = null) -> DomainResult:
	var document := ValidatedCanonicalDocument.new(raw_bytes, canonical_bytes, digest, value, profile, false)
	return document._construction_result()

## Alias for callers using the wire-oriented constructor name.
static func from_parts(raw_bytes: PackedByteArray, canonical_bytes: PackedByteArray, digest: String, value: Variant, profile: ContractShapeProfile = null) -> DomainResult:
	return create(raw_bytes, canonical_bytes, digest, value, profile)

## Raw-only construction path used by CanonicalCodec.decode. It owns the one
## bounded parse and publishes only the complete proof packet it just received.
static func _from_raw(raw_bytes: PackedByteArray, profile: ContractShapeProfile = null) -> DomainResult:
	var document := ValidatedCanonicalDocument.new(raw_bytes, PackedByteArray(), "", null, profile, true)
	return document._construction_result()

## Public raw-only entry with the same one-pass proof semantics as decode().
static func from_raw(raw_bytes: PackedByteArray, profile: ContractShapeProfile = null) -> DomainResult:
	return _from_raw(raw_bytes, profile)

## Direct/legacy underscore entry remains safe because it performs its own
## same-profile proof before publication; no caller-settable trust token exists.
static func _from_verified_parts(raw_bytes: PackedByteArray, canonical_bytes: PackedByteArray, digest: String, value: Variant, profile: ContractShapeProfile = null) -> DomainResult:
	return create(raw_bytes, canonical_bytes, digest, value, profile)

func _init(raw_bytes: PackedByteArray = PackedByteArray(), canonical_bytes: PackedByteArray = PackedByteArray(), digest: String = "", value: Variant = null, profile: ContractShapeProfile = null, raw_only: bool = false) -> void:
	_locked = false
	if raw_bytes.is_empty():
		_finish_invalid(DomainResult.failure(&"invalid_document", "validated document bytes cannot be empty", "$", -1, 0, &"record_not_allocated"))
		return
	var active_profile := profile if profile != null else ContractShapeProfile.unrestricted()
	var parts: DomainResult = CanonicalCodec.decode_parts(raw_bytes, active_profile)
	if not parts.is_success():
		_finish_invalid(parts)
		return
	var proof: Dictionary = parts.value()
	if not raw_only:
		if canonical_bytes.is_empty():
			_finish_invalid(DomainResult.failure(&"invalid_document", "validated document bytes cannot be empty", "$", -1, 0, &"record_not_allocated"))
			return
		var binding: DomainResult = _prove_parts(proof, canonical_bytes, digest, value)
		if not binding.is_success():
			_finish_invalid(binding)
			return
	_raw_bytes = PackedByteArray(proof["raw_bytes"]).duplicate()
	_canonical_bytes = PackedByteArray(proof["canonical_bytes"]).duplicate()
	_sha256 = String(proof["sha256"])
	_value = _copy_value(proof["value"])
	_valid = true
	_locked = true

func _publish(raw_bytes: PackedByteArray, canonical_bytes: PackedByteArray, digest: String, value: Variant) -> void:
	if _locked:
		return
	# All public constructors lock synchronously; this guard exists only for
	# legacy callers and intentionally never publishes an unproved value.
	var verified: DomainResult = ValidatedCanonicalDocument.create(raw_bytes, canonical_bytes, digest, value)
	if not verified.is_success():
		_finish_invalid(verified)
		return
	var source: ValidatedCanonicalDocument = verified.value()
	_raw_bytes = source.original_bytes()
	_canonical_bytes = source.canonical_bytes()
	_sha256 = source.sha256_hex()
	_value = source.value()
	_valid = true
	_locked = true

## Returns whether this instance owns a complete validated document.
func is_valid() -> bool:
	return _valid

## Returns the retained source bytes as a fresh packed array.
## Example: `var source := document.original_bytes()`.
func original_bytes() -> PackedByteArray:
	return _raw_bytes.duplicate()

## Alias for `original_bytes`.
func raw_bytes() -> PackedByteArray:
	return original_bytes()

## Returns canonical project bytes as a fresh packed array.
func canonical_bytes() -> PackedByteArray:
	return _canonical_bytes.duplicate()

## Returns the lowercase SHA-256 of the canonical bytes.
func sha256_hex() -> String:
	return _sha256

## Alias for callers that name the digest `digest`.
func digest() -> String:
	return sha256_hex()

## Returns a defensive parsed-value projection.
## Example: `var wire_value := document.value()`.
func value() -> Variant:
	return _copy_value(_value)

## Alias for the parsed root projection.
func document_value() -> Variant:
	return value()

## Returns the parsed root as a dictionary, or an empty dictionary if invalid.
func to_dictionary() -> Dictionary:
	var value_projection: Variant = value()
	return value_projection if typeof(value_projection) == TYPE_DICTIONARY else {}

func _state() -> Dictionary:
	return {
		"raw_bytes": _raw_bytes.duplicate(),
		"canonical_bytes": _canonical_bytes.duplicate(),
		"sha256": _sha256,
		"value": IR.clone(_value),
		"valid": _valid,
	}

func _construction_result() -> DomainResult:
	if _valid:
		return DomainResult.success(self)
	return DomainResult.failure(_error_code, _error_message, _error_path, _error_byte_offset, _error_inspected_byte_count, _error_allocation_disposition)

func _finish_invalid(result: DomainResult) -> void:
	if result == null:
		result = DomainResult.failure(&"invalid_document", "validated document is invalid", "$", -1, 0, &"record_not_allocated")
	_error_code = result.error_code()
	_error_message = result.error_message()
	_error_path = result.path_witness()
	_error_byte_offset = result.byte_offset()
	_error_inspected_byte_count = result.inspected_byte_count()
	_error_allocation_disposition = result.allocation_disposition()
	_valid = false
	_locked = true

static func _prove_parts(source: Dictionary, canonical_bytes: PackedByteArray, digest: String, value: Variant) -> DomainResult:
	if source.is_empty() or not source.has("canonical_bytes") or not source.has("sha256") or not source.has("value"):
		return DomainResult.failure(&"invalid_document", "raw bytes did not produce a validated proof")
	if not _is_lower_sha256(digest):
		return DomainResult.failure(&"invalid_hash", "document digest must be lowercase SHA-256", "$", -1, 0, &"record_not_allocated")
	var inspected := PackedByteArray(source.get("raw_bytes", PackedByteArray())).size()
	if PackedByteArray(source["canonical_bytes"]) != PackedByteArray(canonical_bytes):
		return DomainResult.failure(&"canonical_mismatch", "canonical bytes do not match the raw-derived projection", "$", 0, inspected, &"record_not_allocated")
	if String(source["sha256"]) != digest:
		return DomainResult.failure(&"hash_mismatch", "document digest does not match raw-derived canonical bytes", "$", 0, inspected, &"record_not_allocated")
	if not _values_equal(source["value"], value):
		return DomainResult.failure(&"value_mismatch", "document value does not match the raw-derived projection", "$", 0, inspected, &"record_not_allocated")
	return DomainResult.success(true)

static func _values_equal(left: Variant, right: Variant) -> bool:
	return IR.equal(left, right)

static func _copy_value(value: Variant) -> Variant:
	return IR.clone(value)

static func _is_lower_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character: String in value:
		if (character < "0" or character > "9") and (character < "a" or character > "f"):
			return false
	return true
