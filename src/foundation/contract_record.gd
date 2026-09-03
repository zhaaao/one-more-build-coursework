class_name ContractRecord
extends RefCounted

const IR = preload("res://src/foundation/canonical_json_ir.gd")

## Copy-on-write closed record for the Foundation contract slice.
## Implements the project's canonical record and recovery boundary.
## GDScript has no language-level private fields. `_fields` and `_field_names`
## are write-once compatibility properties. Construction writes their
## defensive copies while unlocked, then permanently locks the instance before
## publication; callers can only observe detached projections afterward.

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

var _field_names: Array[StringName] = []:
	get:
		var copied_names: Array[StringName] = []
		for raw_name: StringName in _field_names:
			copied_names.append(StringName(raw_name))
		return copied_names
	set(value):
		if _locked:
			return
		_field_names = value.duplicate()

var _valid: bool = false:
	set(value):
		if _locked:
			return
		_valid = value

## Validates and constructs a closed record through the only successful path.
## Dictionary input cannot represent duplicate keys; use the occurrence array
## form when duplicate-member diagnostics must be preserved.
static func create(fields: Variant, required_fields: Array[StringName]) -> DomainResult:
	var declarations := _validate_required_fields(required_fields)
	if not declarations.is_success():
		return declarations
	var members := _members_from_input(fields)
	if not members.is_success():
		return members
	var normalized := _normalize_members(members.value(), required_fields)
	if not normalized.is_success():
		return normalized
	var ordered_fields := _ordered_fields(normalized.value(), required_fields)
	var record := _construct_validated(ordered_fields, required_fields)
	if not record.is_valid():
		return DomainResult.failure(&"construction_failed", "validated record could not be initialized")
	return DomainResult.success(record)

static func _construct_validated(fields: Dictionary, field_names: Array[StringName]) -> ContractRecord:
	return ContractRecord.new(fields, field_names)

static func _members_from_input(fields: Variant) -> DomainResult:
	var members: Array[Dictionary] = []
	match typeof(fields):
		TYPE_DICTIONARY:
			var field_dictionary: Dictionary = fields
			for raw_key: Variant in field_dictionary.keys():
				members.append({"name": raw_key, "value": field_dictionary[raw_key]})
		TYPE_ARRAY:
			var field_members: Array = fields
			for raw_member: Variant in field_members:
				if typeof(raw_member) != TYPE_DICTIONARY:
					return DomainResult.failure(&"invalid_field_member", "field members must be dictionaries")
				var member: Dictionary = raw_member
				if member.size() != 2 or not member.has("name") or not member.has("value"):
					return DomainResult.failure(&"invalid_field_member", "field members require name and value")
				members.append(member)
		_:
			return DomainResult.failure(&"invalid_fields", "closed record fields must be a dictionary or member array")
	return DomainResult.success(members)

static func _normalize_members(members: Array, required_fields: Array[StringName]) -> DomainResult:
	var normalized: Dictionary = {}
	for raw_member: Variant in members:
		var member: Dictionary = raw_member
		var raw_name: Variant = member["name"]
		if typeof(raw_name) != TYPE_STRING and typeof(raw_name) != TYPE_STRING_NAME:
			return DomainResult.failure(&"invalid_field_name", "field names must be strings")
		var field_name := StringName(raw_name)
		if not required_fields.has(field_name):
			return DomainResult.failure(&"unknown_field", "field is not part of the closed record")
		if normalized.has(field_name):
			return DomainResult.failure(&"duplicate_field", "field appears more than once")
		var copied_value := _copy_value(member["value"])
		if not copied_value.is_success():
			return copied_value
		normalized[field_name] = copied_value.value()
	for required_name: StringName in required_fields:
		if not normalized.has(required_name):
			return DomainResult.failure(&"missing_field", "required field is missing")
	return DomainResult.success(normalized)

static func _ordered_fields(normalized: Dictionary, required_fields: Array[StringName]) -> Dictionary:
	var ordered: Dictionary = {}
	for required_name: StringName in required_fields:
		ordered[required_name] = normalized[required_name]
	return ordered

static func _validate_required_fields(required_fields: Array[StringName]) -> DomainResult:
	var declared: Dictionary = {}
	for required_name: StringName in required_fields:
		if required_name.is_empty():
			return DomainResult.failure(&"invalid_field_name", "required field names cannot be empty")
		if declared.has(required_name):
			return DomainResult.failure(&"duplicate_field", "required field appears more than once")
		declared[required_name] = true
	return DomainResult.success(true)

func _init(fields: Dictionary = {}, field_names: Array[StringName] = []) -> void:
	_locked = false
	var declarations := _validate_required_fields(field_names)
	if not declarations.is_success():
		_locked = true
		return
	var copied_fields := _copy_declared_fields(fields, field_names)
	if not copied_fields.is_success():
		_locked = true
		return
	_fields = copied_fields.value()
	_field_names = field_names.duplicate()
	_valid = true
	_locked = true

## Returns whether this instance owns a successfully validated record.
func is_valid() -> bool:
	return _valid

## Returns whether this record contains a declared field.
func has_field(field_name: StringName) -> bool:
	return _valid and _fields.has(field_name)

## Returns a defensive copy of one field value.
func get_field(field_name: StringName) -> Variant:
	if not has_field(field_name):
		return null
	var copied_value := _copy_value(_fields[field_name])
	return copied_value.value() if copied_value.is_success() else null

## Returns declared field names in required-field order.
func field_names() -> Array[StringName]:
	if not _valid:
		return []
	return _field_names.duplicate()

## Returns a deep defensive copy in declaration order.
func to_dictionary() -> Dictionary:
	if not _valid:
		return {}
	var copied_fields := _copy_value(_fields)
	return copied_fields.value() if copied_fields.is_success() else {}

func _state_snapshot() -> Dictionary:
	return {
		"fields": IR.clone(_fields),
		"field_names": _field_names.duplicate(),
		"valid": _valid,
	}

static func _copy_declared_fields(fields: Dictionary, field_names: Array[StringName]) -> DomainResult:
	if fields.size() != field_names.size():
		return DomainResult.failure(&"invalid_field_set", "fields must match the declared names")
	var copied_fields: Dictionary = {}
	for field_name: StringName in field_names:
		if not fields.has(field_name):
			return DomainResult.failure(&"missing_field", "required field is missing")
		var copied_value := _copy_value(fields[field_name])
		if not copied_value.is_success():
			return copied_value
		copied_fields[field_name] = copied_value.value()
	for raw_key: Variant in fields.keys():
		if typeof(raw_key) != TYPE_STRING and typeof(raw_key) != TYPE_STRING_NAME:
			return DomainResult.failure(&"invalid_field_name", "field names must be strings")
		if not field_names.has(StringName(raw_key)):
			return DomainResult.failure(&"unknown_field", "field is not part of the closed record")
	return DomainResult.success(copied_fields)

static func _copy_value(value: Variant) -> DomainResult:
	var valid := IR.validate_pure_json(value)
	if not valid.is_success():
		return DomainResult.failure(&"invalid_value", "record values must be Foundation-owned data")
	return DomainResult.success(IR.clone(value))
