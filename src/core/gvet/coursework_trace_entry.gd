class_name CourseworkTraceEntry
extends RefCounted

## Immutable process-local explanation for exactly one evaluated node.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CanonicalJsonIRType = preload("res://src/foundation/canonical_json_ir.gd")

var _locked: bool = false:
	set(value):
		if not _locked:
			_locked = value
var _record: Dictionary = {}:
	get:
		return _record.duplicate(true)
	set(value):
		if not _locked:
			_record = value.duplicate(true)

func _init(record: Dictionary = {}) -> void:
	if not _record_is_valid(record):
		return
	_record = record
	_locked = true

## Creates one complete entry with explicit optional-value presence.
##
## Example:
## [codeblock]
## var result := CourseworkTraceEntry.create(
##     1, "start", "control", "flow", {}, false, null,
##     "edge_start_end", "edge_start_end", null, "completed", "", "Start completed")
## assert(result.is_success())
## [/codeblock]
static func create(
	step_number: int,
	node_id: String,
	node_kind: String,
	category_id: String,
	consumed_values: Dictionary,
	produced_value_present: bool,
	produced_value: Variant,
	selected_connection_id: String,
	traversed_connection_id: String,
	observation: Variant,
	outcome: String,
	reason_code: String,
	reason: String
) -> DomainResult:
	if not _payload_is_pure(consumed_values, produced_value, observation):
		return DomainResultType.failure(
			&"trace_entry_error", "trace entry values must be recursive pure data")
	var record: Dictionary = {
		"step_number": step_number,
		"node_id": node_id,
		"node_kind": node_kind,
		"category_id": category_id,
		"consumed_values": consumed_values.duplicate(true),
		"produced_value_present": produced_value_present,
		"produced_value": _detached(produced_value),
		"selected_connection_id": selected_connection_id,
		"traversed_connection_id": traversed_connection_id,
		"observation": _detached(observation),
		"outcome": outcome,
		"reason_code": reason_code,
		"reason": reason,
	}
	var entry: CourseworkTraceEntry = CourseworkTraceEntry.new(record)
	if not entry.is_valid():
		return DomainResultType.failure(
			&"trace_entry_error", "trace entry fields are invalid")
	return DomainResultType.success(entry)

## Returns true only for a complete locked trace value.
## Example: `assert(entry.is_valid())` after accepting a `create()` result.
func is_valid() -> bool:
	return _locked and _record_is_valid(_record)

## Returns the one-based consecutive step number.
## Example: `assert(entry.step_number() == 1)` for the first evaluated node.
func step_number() -> int:
	return int(_record.get("step_number", 0))

## Returns the stable active node identity.
## Example: `assert(entry.node_id() == "start")` for a Start trace entry.
func node_id() -> String:
	return String(_record.get("node_id", ""))

## Returns the stable readable reason code, empty on ordinary success.
## Example: `assert(entry.reason_code().is_empty())` for ordinary success.
func reason_code() -> String:
	return String(_record.get("reason_code", ""))

## Returns a detached data projection for tests and later freezing.
## Example: `var projection := entry.to_dictionary(); projection.clear()` leaves
## the immutable `entry` valid and unchanged.
func to_dictionary() -> Dictionary:
	return _record

## Returns an immutable replacement carrying a located ordinary failure.
## Example:
## [codeblock]
## var changed := entry.with_failure("QUERY_UNAVAILABLE", "No query provider")
## assert(changed.is_success())
## assert(changed.value().reason_code() == "QUERY_UNAVAILABLE")
## [/codeblock]
func with_failure(code: String, reason: String) -> DomainResult:
	if not is_valid() or code.is_empty() or reason.is_empty():
		return DomainResultType.failure(
			&"trace_entry_error", "failure trace requires a valid entry and reason")
	var changed: Dictionary = _record
	changed["outcome"] = code.to_lower()
	changed["reason_code"] = code
	changed["reason"] = reason
	var entry: CourseworkTraceEntry = CourseworkTraceEntry.new(changed)
	return DomainResultType.success(entry) if entry.is_valid() else DomainResultType.failure(
		&"trace_entry_error", "failure trace replacement is invalid")

static func _record_is_valid(record: Dictionary) -> bool:
	var fields: Array[String] = [
		"step_number", "node_id", "node_kind", "category_id",
		"consumed_values", "produced_value_present", "produced_value",
		"selected_connection_id", "traversed_connection_id", "observation",
		"outcome", "reason_code", "reason",
	]
	if not _has_exact_keys(record, fields):
		return false
	if not _scalar_fields_are_valid(record):
		return false
	return _payload_is_pure(
		record["consumed_values"], record["produced_value"], record["observation"])

static func _scalar_fields_are_valid(record: Dictionary) -> bool:
	return _identity_fields_are_valid(record) \
		and _value_fields_are_valid(record) \
		and _connection_fields_are_valid(record) \
		and _outcome_fields_are_valid(record)

static func _identity_fields_are_valid(record: Dictionary) -> bool:
	return typeof(record["step_number"]) == TYPE_INT \
		and int(record["step_number"]) > 0 \
		and typeof(record["node_id"]) == TYPE_STRING \
		and not String(record["node_id"]).is_empty() \
		and typeof(record["node_kind"]) == TYPE_STRING \
		and ["control", "data"].has(String(record["node_kind"]))

static func _value_fields_are_valid(record: Dictionary) -> bool:
	return typeof(record["category_id"]) == TYPE_STRING \
		and typeof(record["consumed_values"]) == TYPE_DICTIONARY \
		and typeof(record["produced_value_present"]) == TYPE_BOOL

static func _connection_fields_are_valid(record: Dictionary) -> bool:
	return typeof(record["selected_connection_id"]) == TYPE_STRING \
		and typeof(record["traversed_connection_id"]) == TYPE_STRING

static func _outcome_fields_are_valid(record: Dictionary) -> bool:
	return typeof(record["outcome"]) == TYPE_STRING \
		and not String(record["outcome"]).is_empty() \
		and typeof(record["reason_code"]) == TYPE_STRING \
		and typeof(record["reason"]) == TYPE_STRING \
		and not String(record["reason"]).is_empty()

static func _payload_is_pure(
	consumed_values: Variant, produced_value: Variant, observation: Variant
) -> bool:
	return CanonicalJsonIRType.validate_pure_json(consumed_values).is_success() \
		and CanonicalJsonIRType.validate_pure_json(produced_value).is_success() \
		and CanonicalJsonIRType.validate_pure_json(observation).is_success()

static func _has_exact_keys(record: Dictionary, fields: Array[String]) -> bool:
	if record.size() != fields.size():
		return false
	for raw_key: Variant in record.keys():
		if typeof(raw_key) != TYPE_STRING or not fields.has(String(raw_key)):
			return false
	return true

static func _detached(value: Variant) -> Variant:
	return CanonicalJsonIRType.clone(value)
