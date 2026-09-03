class_name ExecutionBundle
extends RefCounted

const IR = preload("res://src/foundation/canonical_json_ir.gd")

## Immutable GVET `execution_bundle_v2` owner record.
##
## Foundation owns lexical and canonical evidence. This record is created only
## from that evidence and exposes the exact fourteen wire fields; the identity
## digest is metadata and never becomes an additional wire member.

const FIELD_NAMES: Array[StringName] = [
	&"execution_bundle_codec_version",
	&"runtime_codec_version",
	&"authoring_request",
	&"graph",
	&"task_fixture_sha256",
	&"registry_sha256",
	&"authoring_package_binding",
	&"validator_executor_contract_version",
	&"validator_executor_binding",
	&"task_content_contract_version",
	&"sandbox_catalog_sha256",
	&"resource_compatibility",
	&"task_day_index",
	&"public_case_manifest",
]

# GDScript has no language-level private fields. These compatibility
# properties are written only by validated construction and become immutable
# once the one-way latch is set before publication.
var _locked: bool = false:
	set(value):
		if _locked:
			return
		_locked = value

var _fields: Dictionary = {}:
	get:
		var copied: Variant = IR.clone(_fields)
		return copied if typeof(copied) == TYPE_DICTIONARY else {}
	set(value):
		if _locked:
			return
		var copied: Variant = IR.clone(value)
		_fields = copied if typeof(copied) == TYPE_DICTIONARY else {}

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

var _valid: bool = false:
	set(value):
		if _locked:
			return
		_valid = value

## Constructs an immutable bundle from an already validated root and evidence.
## Example: `ExecutionBundle.create(fields, canonical_bytes, digest, raw_bytes)`.
static func create(fields: Dictionary, canonical_bytes: PackedByteArray, digest: String, raw_bytes: PackedByteArray = PackedByteArray()) -> DomainResult:
	if canonical_bytes.is_empty() or raw_bytes.is_empty():
		return DomainResult.failure(&"invalid_bundle", "bundle source and canonical bytes cannot be empty", "$", -1, 0, &"record_not_allocated")
	var profile := ExecutionBundleProfileV2.shape_profile()
	if profile == null:
		return DomainResult.failure(&"profile_invalid", "execution bundle profile could not be initialized", "$", -1, 0, &"record_not_allocated")
	var document_result := ValidatedCanonicalDocument.create(raw_bytes, canonical_bytes, digest, fields, profile)
	if not document_result.is_success():
		return document_result
	return _construct_from_validated_document(document_result.value())

## Raw production entry: the exact GVET profile decode, one semantic proof,
## and owner publication all happen here. This method intentionally does not
## delegate to another publication seam that could be called with forged parts.
static func create_from_raw(raw_bytes: PackedByteArray) -> DomainResult:
	if raw_bytes.is_empty():
		return DomainResult.failure(&"invalid_bundle", "bundle source bytes cannot be empty", "$", -1, 0, &"record_not_allocated")
	var profile := ExecutionBundleProfileV2.shape_profile()
	if profile == null:
		return DomainResult.failure(&"profile_invalid", "execution bundle profile could not be initialized", "$", -1, 0, &"record_not_allocated")
	var document_result := CanonicalCodec.decode(raw_bytes, profile)
	if not document_result.is_success():
		return document_result
	return _construct_from_validated_document(document_result.value())

## Constructs a bundle from a caller-supplied document after rebuilding an
## exact GVET-profile raw proof. The supplied document is not authorization.
## Example: `ExecutionBundle.create_from_document(document, fields, canonical, digest)`.
static func create_from_document(document: ValidatedCanonicalDocument, fields: Dictionary, canonical_bytes: PackedByteArray, digest: String) -> DomainResult:
	if document == null or not is_instance_valid(document) or not document.is_valid():
		return DomainResult.failure(&"invalid_document", "bundle construction requires a validated canonical document", "$", -1, 0, &"record_not_allocated")
	var profile := ExecutionBundleProfileV2.shape_profile()
	if profile == null:
		return DomainResult.failure(&"profile_invalid", "execution bundle profile could not be initialized", "$", -1, 0, &"record_not_allocated")
	var proof_result := ValidatedCanonicalDocument.create(document.original_bytes(), canonical_bytes, digest, fields, profile)
	if not proof_result.is_success():
		return proof_result
	return _construct_from_validated_document(proof_result.value())

func _init(record: ContractRecord = null, canonical_bytes: PackedByteArray = PackedByteArray(), digest: String = "", raw_bytes: PackedByteArray = PackedByteArray(), validated_document: ValidatedCanonicalDocument = null) -> void:
	_locked = false
	if record == null or not record.is_valid() or not _is_lower_sha256(digest) or canonical_bytes.is_empty() or raw_bytes.is_empty():
		_invalidate()
		return
	if record.field_names() != FIELD_NAMES:
		_invalidate()
		return
	var profile: ContractShapeProfile = ExecutionBundleProfileV2.shape_profile()
	if profile == null:
		_invalidate()
		return
	var document: ValidatedCanonicalDocument = validated_document
	if document == null or not is_instance_valid(document) or not document.is_valid():
		var document_result: DomainResult = ValidatedCanonicalDocument.create(raw_bytes, canonical_bytes, digest, record.to_dictionary(), profile)
		if not document_result.is_success():
			_invalidate()
			return
		document = document_result.value()
	else:
		if document.original_bytes() != raw_bytes or document.canonical_bytes() != canonical_bytes or document.sha256_hex() != digest:
			_invalidate()
			return
	var valid_state := _validate_constructor_state(record, document, profile)
	if not valid_state.is_success():
		_invalidate()
		return
	_fields = record.to_dictionary()
	_raw_bytes = raw_bytes
	_canonical_bytes = canonical_bytes
	_sha256 = digest
	_valid = true
	_locked = true

static func _validate_constructor_state(record: ContractRecord, document: ValidatedCanonicalDocument, profile: ContractShapeProfile) -> DomainResult:
	var normalized_result: DomainResult = profile.validate_and_normalize(document.value())
	if not normalized_result.is_success():
		return normalized_result
	var fields: Dictionary = record.to_dictionary()
	if not IR.equal(normalized_result.value(), fields):
		return DomainResult.failure(&"value_mismatch", "bundle record does not match validated document")
	return ExecutionBundleProfileV2.validate_normalized_fields(fields)

func _invalidate() -> void:
	_valid = false
	_locked = true

static func _construct_from_validated_document(document: ValidatedCanonicalDocument) -> DomainResult:
	if document == null or not is_instance_valid(document) or not document.is_valid():
		return DomainResult.failure(&"invalid_document", "bundle construction requires a validated canonical document", "$", -1, 0, &"record_not_allocated")
	var normalized_value: Variant = document.value()
	if typeof(normalized_value) != TYPE_DICTIONARY:
		return DomainResult.failure(&"closed_shape", "execution bundle root must be an object", "$", 0, document.original_bytes().size(), &"record_not_allocated")
	var normalized_fields: Dictionary = normalized_value
	var semantics: DomainResult = ExecutionBundleProfileV2.validate_normalized_fields(normalized_fields)
	if not semantics.is_success():
		return DomainResult.failure(semantics.error_code(), semantics.error_message(), semantics.path_witness(), semantics.byte_offset(), document.original_bytes().size(), &"record_not_allocated")
	var record_result: DomainResult = ContractRecord.create(normalized_fields, FIELD_NAMES)
	if not record_result.is_success():
		return record_result
	var bundle: ExecutionBundle = ExecutionBundle.new(record_result.value(), document.canonical_bytes(), document.sha256_hex(), document.original_bytes(), document)
	if not bundle.is_valid():
		return DomainResult.failure(&"construction_failed", "validated bundle could not be initialized", "$", -1, document.original_bytes().size(), &"record_not_allocated")
	return DomainResult.success(bundle)

## Returns whether the complete fourteen-field record was committed.
## Example: `if bundle.is_valid(): use(bundle.to_dictionary())`.
func is_valid() -> bool:
	return _valid

## Returns the exact fourteen field names in wire declaration order.
## Example: `var names := bundle.field_names()`.
func field_names() -> Array[StringName]:
	return FIELD_NAMES.duplicate()

## Returns whether a wire field is present.
## Example: `if bundle.has_field(&"graph"): inspect(bundle.get_field(&"graph"))`.
func has_field(field_name: StringName) -> bool:
	return _valid and _fields.has(String(field_name))

## Returns one field as a defensive copy.
## Example: `var graph := bundle.get_field(&"graph")`.
func get_field(field_name: StringName) -> Variant:
	return IR.clone(_fields.get(String(field_name), null)) if _valid else null

## Returns the exact fourteen-field wire projection with no metadata member.
## Example: `var wire := bundle.to_dictionary()`.
func to_dictionary() -> Dictionary:
	return IR.clone(_fields) if _valid else {}

## Alias for the wire projection.
## Example: `var wire := bundle.wire_projection()`.
func wire_projection() -> Dictionary:
	return to_dictionary()

## Returns canonical bytes as a fresh packed array.
## Example: `var bytes := bundle.canonical_bytes()`.
func canonical_bytes() -> PackedByteArray:
	return _canonical_bytes.duplicate()

## Returns the retained source bytes as a fresh packed array.
## Example: `var source := bundle.original_bytes()`.
func original_bytes() -> PackedByteArray:
	return _raw_bytes.duplicate()

## Alias for `original_bytes`.
## Example: `var source := bundle.raw_bytes()`.
func raw_bytes() -> PackedByteArray:
	return original_bytes()

## Returns the lowercase SHA-256 identity over the final canonical record.
## Example: `var digest := bundle.execution_bundle_sha256()`.
func execution_bundle_sha256() -> String:
	return _sha256

## Alias for callers that name the identity `sha256`.
## Example: `var digest := bundle.sha256_hex()`.
func sha256_hex() -> String:
	return execution_bundle_sha256()

## Returns whether another bundle has byte-identical canonical truth.
## Example: `if bundle.equals_bundle(peer_bundle): reuse(bundle)`.
func equals_bundle(other: ExecutionBundle) -> bool:
	return other != null and execution_bundle_sha256() == other.execution_bundle_sha256() and canonical_bytes() == other.canonical_bytes()

## Typed convenience accessor for the codec version.
## Example: `var version := bundle.execution_bundle_codec_version()`.
func execution_bundle_codec_version() -> String:
	return String(get_field(&"execution_bundle_codec_version"))

## Typed convenience accessor for the runtime codec version.
## Example: `var version := bundle.runtime_codec_version()`.
func runtime_codec_version() -> String:
	return String(get_field(&"runtime_codec_version"))

## Typed convenience accessor for the bound task day.
## Example: `var day := bundle.task_day_index()`.
func task_day_index() -> int:
	return int(get_field(&"task_day_index"))

func _state() -> Dictionary:
	return {
		"fields": IR.clone(_fields),
		"raw_bytes": _raw_bytes.duplicate(),
		"canonical_bytes": _canonical_bytes.duplicate(),
		"sha256": _sha256,
		"valid": _valid,
	}

static func _is_lower_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character: String in value:
		if (character < "0" or character > "9") and (character < "a" or character > "f"):
			return false
	return true
