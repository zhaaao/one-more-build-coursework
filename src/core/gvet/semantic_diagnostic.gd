class_name SemanticDiagnostic
extends RefCounted

const DomainResultType = preload("res://src/foundation/domain_result.gd")

## Immutable coursework semantic finding.
##
## Example: `SemanticDiagnostic.create("UNREACHABLE_NODE", "node", "node.a")`.

const CODE_MISSING_START: String = "MISSING_START"
const CODE_MULTIPLE_START: String = "MULTIPLE_START"
const CODE_MISSING_REQUIRED_CONNECTION: String = "MISSING_REQUIRED_CONNECTION"
const CODE_UNREACHABLE_NODE: String = "UNREACHABLE_NODE"
const CODE_ILLEGAL_DATA_CYCLE: String = "ILLEGAL_DATA_CYCLE"
const CODE_REPEAT_BODY_EXIT: String = "REPEAT_BODY_EXIT"
const CODE_REPEAT_OUTSIDE_CONTINUE: String = "REPEAT_OUTSIDE_CONTINUE"
const CODE_REPEAT_BODY_TO_IN: String = "REPEAT_BODY_TO_IN"
const CODE_REPEAT_CROSSED_REGION: String = "REPEAT_CROSSED_REGION"
const CODE_ILLEGAL_EXECUTION_CYCLE: String = "ILLEGAL_EXECUTION_CYCLE"

const ENTITY_GRAPH: String = "graph"
const ENTITY_NODE: String = "node"
const ENTITY_PORT: String = "port"
const ENTITY_CONNECTION: String = "connection"
const ENTITY_COMPONENT: String = "component"
const ENTITY_NODE_SET: String = "node_set"

var _locked: bool = false:
	set(value):
		if _locked:
			return
		_locked = value
var _reason_code: String = "":
	set(value):
		if _locked:
			return
		_reason_code = value
var _entity_kind: String = "":
	set(value):
		if _locked:
			return
		_entity_kind = value
var _primary_entity_id: String = "":
	set(value):
		if _locked:
			return
		_primary_entity_id = value
var _related_entity_ids: Array[String] = []:
	get:
		return _related_entity_ids.duplicate()
	set(value):
		if _locked:
			return
		_related_entity_ids = value.duplicate()
var _valid: bool = false:
	set(value):
		if _locked:
			return
		_valid = value

## Creates one closed diagnostic in the GDD's stable ten-code vocabulary.
## Related IDs must express the complete offending tuple; construction
## canonicalizes them by ordinal ASCII ID and rejects duplicates.
static func create(
	reason_code: String,
	entity_kind: String,
	primary_entity_id: String = "",
	related_entity_ids: Array = []
) -> DomainResult:
	var fields_result := _validate_fields(
		reason_code, entity_kind, primary_entity_id, related_entity_ids)
	if not fields_result.is_success():
		return fields_result
	var diagnostic := new(
		reason_code,
		entity_kind,
		primary_entity_id,
		_sorted_ids(related_entity_ids))
	if not diagnostic.is_valid():
		return DomainResult.failure(&"invalid_diagnostic", "semantic diagnostic construction failed")
	return DomainResult.success(diagnostic)

func _init(
	reason_code: String = "",
	entity_kind: String = "",
	primary_entity_id: String = "",
	related_entity_ids: Array = []
) -> void:
	if not _validate_fields(
		reason_code, entity_kind, primary_entity_id, related_entity_ids).is_success():
		_locked = true
		return
	_reason_code = reason_code
	_entity_kind = entity_kind
	_primary_entity_id = primary_entity_id
	_related_entity_ids = _sorted_ids(related_entity_ids)
	_valid = true
	_locked = true

## Returns whether the closed record was constructed successfully.
func is_valid() -> bool:
	return _valid

## Returns one of the exact ten coursework semantic codes.
func reason_code() -> String:
	return _reason_code

## Returns the stable offending-entity shape.
func entity_kind() -> String:
	return _entity_kind

## Returns the first stable ID used by total ordering, or empty for graph-level findings.
func primary_entity_id() -> String:
	return _primary_entity_id

## Returns the remaining offending IDs in ordinal ASCII order.
func related_entity_ids() -> Array[String]:
	return _related_entity_ids.duplicate()

## Returns all identified offending entities in display order.
func offending_entity_ids() -> Array[String]:
	var result: Array[String] = []
	if not _primary_entity_id.is_empty():
		result.append(_primary_entity_id)
	result.append_array(_related_entity_ids)
	return result

## Returns the GDD's fixed diagnostic priority from zero to nine.
func priority() -> int:
	return priority_for(_reason_code)

## Returns the exact total-sort tuple: priority, primary ID, related IDs.
func sort_tuple() -> Array:
	return [priority(), _primary_entity_id, _related_entity_ids.duplicate()]

## Returns a detached pure-data representation suitable for a frozen report.
func to_dictionary() -> Dictionary:
	return {
		"reason_code": _reason_code,
		"entity_kind": _entity_kind,
		"primary_entity_id": _primary_entity_id,
		"related_entity_ids": _related_entity_ids.duplicate(),
	}

## Returns a detached copy of this record.
func copy_record() -> SemanticDiagnostic:
	var result: DomainResult = create(
		_reason_code, _entity_kind, _primary_entity_id, _related_entity_ids)
	return result.value() if result.is_success() else null

## Compares complete semantic content.
func equals(other: SemanticDiagnostic) -> bool:
	return other != null and to_dictionary() == other.to_dictionary()

## Maps the exact ten codes to their GDD-defined priority.
static func priority_for(reason_code: String) -> int:
	match reason_code:
		CODE_MISSING_START:
			return 0
		CODE_MULTIPLE_START:
			return 1
		CODE_MISSING_REQUIRED_CONNECTION:
			return 2
		CODE_UNREACHABLE_NODE:
			return 3
		CODE_ILLEGAL_DATA_CYCLE:
			return 4
		CODE_REPEAT_BODY_EXIT:
			return 5
		CODE_REPEAT_OUTSIDE_CONTINUE:
			return 6
		CODE_REPEAT_BODY_TO_IN:
			return 7
		CODE_REPEAT_CROSSED_REGION:
			return 8
		CODE_ILLEGAL_EXECUTION_CYCLE:
			return 9
	return -1

static func _validate_fields(
	reason_code: String,
	entity_kind: String,
	primary_entity_id: String,
	related_entity_ids: Array
) -> DomainResult:
	if priority_for(reason_code) < 0:
		return DomainResult.failure(&"invalid_reason", "semantic reason code is not registered")
	if not _reason_accepts_entity_kind(reason_code, entity_kind):
		return DomainResult.failure(&"invalid_locator", "semantic reason and entity kind do not match")
	if reason_code == CODE_MISSING_START:
		if not primary_entity_id.is_empty() or not related_entity_ids.is_empty():
			return DomainResult.failure(&"invalid_locator", "MISSING_START is graph-level")
		return DomainResult.success(true)
	if not _valid_ascii_id(primary_entity_id):
		return DomainResult.failure(&"invalid_locator", "diagnostic requires a valid primary entity ID")
	var seen: Dictionary = {primary_entity_id: true}
	for raw_id: Variant in related_entity_ids:
		if typeof(raw_id) != TYPE_STRING or not _valid_ascii_id(String(raw_id)):
			return DomainResult.failure(&"invalid_locator", "related entity IDs must be valid ASCII IDs")
		var entity_id := String(raw_id)
		if seen.has(entity_id):
			return DomainResult.failure(&"invalid_locator", "diagnostic entity IDs must be unique")
		seen[entity_id] = true
	if reason_code == CODE_MULTIPLE_START and related_entity_ids.is_empty():
		return DomainResult.failure(&"invalid_locator", "MULTIPLE_START requires at least two Start IDs")
	return DomainResult.success(true)

static func _reason_accepts_entity_kind(reason_code: String, entity_kind: String) -> bool:
	match reason_code:
		CODE_MISSING_START:
			return entity_kind == ENTITY_GRAPH
		CODE_MULTIPLE_START:
			return entity_kind == ENTITY_NODE_SET
		CODE_MISSING_REQUIRED_CONNECTION:
			return entity_kind == ENTITY_PORT
		CODE_UNREACHABLE_NODE:
			return entity_kind == ENTITY_NODE
		CODE_ILLEGAL_DATA_CYCLE, CODE_ILLEGAL_EXECUTION_CYCLE:
			return entity_kind == ENTITY_COMPONENT
		CODE_REPEAT_BODY_EXIT:
			return entity_kind == ENTITY_CONNECTION
		CODE_REPEAT_OUTSIDE_CONTINUE, CODE_REPEAT_BODY_TO_IN, CODE_REPEAT_CROSSED_REGION:
			return entity_kind == ENTITY_CONNECTION
	return false

static func _sorted_ids(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(String(value))
	result.sort_custom(_ordinal_less)
	return result

static func _ordinal_less(left: String, right: String) -> bool:
	var left_bytes := left.to_utf8_buffer()
	var right_bytes := right.to_utf8_buffer()
	var shared_length: int = mini(left_bytes.size(), right_bytes.size())
	for index: int in range(shared_length):
		if left_bytes[index] != right_bytes[index]:
			return left_bytes[index] < right_bytes[index]
	return left_bytes.size() < right_bytes.size()

static func _valid_ascii_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	var bytes := value.to_utf8_buffer()
	var first: int = bytes[0]
	if not ((first >= 0x41 and first <= 0x5a) or (first >= 0x61 and first <= 0x7a)):
		return false
	for byte: int in bytes:
		var alpha := (byte >= 0x41 and byte <= 0x5a) or (byte >= 0x61 and byte <= 0x7a)
		var digit := byte >= 0x30 and byte <= 0x39
		if not alpha and not digit and byte not in [0x2e, 0x5f, 0x2d]:
			return false
	return true
