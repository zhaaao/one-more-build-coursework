class_name ContractShapeProfile
extends RefCounted

const NFC = preload("res://src/foundation/unicode_nfc.gd")
const IR = preload("res://src/foundation/canonical_json_ir.gd")
const JCS = preload("res://src/foundation/jcs_binary64.gd")

## Pure declarative shape profile for the byte-first Foundation codec.
##
## A profile describes closed object members and primitive bounds.  It contains
## no game-system names and performs no I/O; GVET supplies its own profile from
## the Core layer.  The codec uses the profile after lexical validation and
## before publishing a `ValidatedCanonicalDocument`.

const KIND_ANY: StringName = &"any"
const KIND_JSON: StringName = &"json"
const KIND_STRING: StringName = &"string"
const KIND_BOOLEAN: StringName = &"boolean"
const KIND_INTEGER: StringName = &"integer"
const KIND_NUMBER: StringName = &"number"
const KIND_HASH: StringName = &"sha256"
const KIND_U64: StringName = &"u64"
const KIND_OBJECT: StringName = &"object"
const KIND_ARRAY: StringName = &"array"
const KIND_NULL: StringName = &"null"

const DEFAULT_LIMITS: Dictionary = {
	"maximum_payload_bytes": 16777216,
	"maximum_nesting_depth": 64,
	"maximum_object_members_per_object": 131072,
	"maximum_array_elements_per_array": 131072,
	"maximum_total_tokens": 1000000,
	"maximum_raw_string_token_bytes": 2097152,
	"maximum_numeric_token_bytes": 64,
	"maximum_total_container_entries": 1000000,
	"maximum_total_decoded_scalar_bytes": 16777216,
}

## GDScript has no language-level private fields. These instance properties are
## defensive copies while unlocked and become permanently immutable after the
## validated declaration is published.
var _locked: bool = false:
	set(value):
		if _locked:
			return
		_locked = value

var _field_names: Array[StringName] = []:
	get:
		return _field_names.duplicate()
	set(value):
		if _locked:
			return
		_field_names = value.duplicate()

var _field_rules: Dictionary = {}:
	get:
		return _field_rules.duplicate(true)
	set(value):
		if _locked:
			return
		_field_rules = value.duplicate(true)

var _limits: Dictionary = {}:
	get:
		return _limits.duplicate(true)
	set(value):
		if _locked:
			return
		_limits = value.duplicate(true)

var _valid: bool = false:
	set(value):
		if _locked:
			return
		_valid = value

## Builds an exact closed profile.
## Example: `ContractShapeProfile.new([&"id"], {"id": {"kind": "string"}})`.
func _init(field_names: Array[StringName] = [], field_rules: Dictionary = {}, limits: Dictionary = {}) -> void:
	_locked = false
	var declarations := _validate_declarations(field_names, field_rules, limits)
	if not declarations.is_success():
		_locked = true
		return
	_field_names = field_names.duplicate()
	_field_rules = field_rules.duplicate(true)
	var configured_limits: Dictionary = {}
	for default_key: Variant in DEFAULT_LIMITS.keys():
		configured_limits[StringName(default_key)] = DEFAULT_LIMITS[default_key]
	for raw_key: Variant in limits.keys():
		configured_limits[StringName(raw_key)] = limits[raw_key]
	_limits = configured_limits
	_valid = true
	_locked = true

## Validates profile declarations and returns the profile only when closed.
## Example: `ContractShapeProfile.create([&"codec"], {"codec": {"kind": "string"}})`.
static func create(field_names: Array[StringName], field_rules: Dictionary = {}, limits: Dictionary = {}) -> DomainResult:
	var declarations := _validate_declarations(field_names, field_rules, limits)
	if not declarations.is_success():
		return declarations
	var profile := ContractShapeProfile.new(field_names, field_rules, limits)
	if not profile._valid:
		return DomainResult.failure(&"invalid_profile", "profile could not be initialized")
	return DomainResult.success(profile)

## Returns a profile that accepts every JSON value after lexical checks.
## Example: `CanonicalCodec.decode(raw_bytes, ContractShapeProfile.unrestricted())`.
static func unrestricted() -> ContractShapeProfile:
	var profile := ContractShapeProfile.new([], {}, {})
	return profile if profile._valid else null

## Returns whether this instance completed validated construction.
## Example: `if profile.is_valid(): CanonicalCodec.decode(raw, profile)`.
func is_valid() -> bool:
	return _valid

## Returns declared fields in declaration order.
## Example: `var names := profile.field_names()`.
func field_names() -> Array[StringName]:
	return _field_names.duplicate() if _valid else []

## Returns a defensive copy of the configured limits.
## Example: `var maximum := profile.limits()[&"maximum_payload_bytes"]`.
func limits() -> Dictionary:
	return _limits.duplicate(true) if _valid else {}

## Returns one configured limit, or zero when the key is not a limit.
## Example: `var maximum := profile.limit(&"maximum_payload_bytes")`.
func limit(name: StringName) -> int:
	return int(_limits.get(name, 0)) if _valid else 0

## Validates and normalizes a parsed JSON value into Foundation-owned data.
## The root is closed when this profile declares fields; unknown/missing fields
## are rejected before any caller can observe a partial document.
## Example: `var checked := profile.validate_and_normalize(parsed_value)`.
func validate_and_normalize(value: Variant) -> DomainResult:
	if not _valid:
		return DomainResult.failure(&"invalid_profile", "profile declaration is invalid")
	var active_field_names: Array[StringName] = _field_names
	var active_rules: Dictionary = _field_rules
	var active_limits: Dictionary = _limits
	if active_field_names.is_empty():
		return _normalize_node(value, {"kind": KIND_JSON}, "$", 0, active_limits)
	var declared_fields: Dictionary = {}
	for field_name: StringName in active_field_names:
		var normalized_name_result: DomainResult = NFC.normalize_result(String(field_name))
		if not normalized_name_result.is_success():
			return DomainResult.failure(&"invalid_profile", "profile field name is not a Unicode scalar string", "$.fields")
		var normalized_name := String(normalized_name_result.value())
		if declared_fields.has(normalized_name):
			return DomainResult.failure(&"invalid_profile", "profile fields collide after Unicode NFC normalization", "$.fields." + normalized_name)
		declared_fields[normalized_name] = _rule_for(field_name, active_rules)
	return _normalize_closed_object(value, declared_fields, "$", 0, active_limits)

## Alias used by callers that prefer the shorter validation name.
## Example: `var checked := profile.validate(parsed_value)`.
func validate(value: Variant) -> DomainResult:
	return validate_and_normalize(value)

func _rule_for(field_name: StringName, active_rules: Dictionary) -> Dictionary:
	var direct: Variant = active_rules.get(field_name, null)
	if direct == null:
		direct = active_rules.get(String(field_name), null)
	if direct == null:
		var normalized_name_result: DomainResult = NFC.normalize_result(String(field_name))
		if normalized_name_result.is_success():
			var normalized_name := String(normalized_name_result.value())
			for raw_key: Variant in active_rules.keys():
				var key_result: DomainResult = NFC.normalize_result(String(raw_key))
				if key_result.is_success() and String(key_result.value()) == normalized_name:
					direct = active_rules[raw_key]
					break
	return direct if typeof(direct) == TYPE_DICTIONARY else {"kind": KIND_JSON}

func _normalize_node(value: Variant, rule: Dictionary, path: String, depth: int, active_limits: Dictionary) -> DomainResult:
	if depth > _profile_limit(active_limits, &"maximum_nesting_depth"):
		return DomainResult.failure(&"nesting_limit", "maximum nesting depth exceeded", path)
	var kind := StringName(rule.get("kind", KIND_JSON))
	if _is_raw_number(value):
		return _normalize_raw_number_for_kind(value, kind, rule, path)
	return _normalize_kind(value, kind, rule, path, depth, active_limits)

func _normalize_raw_number_for_kind(value: Variant, kind: StringName, rule: Dictionary, path: String) -> DomainResult:
	if kind == KIND_INTEGER:
		return _normalize_raw_integer(value, path)
	if kind == KIND_NUMBER or (kind == KIND_JSON and bool(rule.get("allow_raw_numbers", true))):
		return _normalize_raw_number(value, path)
	if kind == KIND_U64:
		return DomainResult.failure(&"invalid_u64_type", "u64 must be a decimal string", path)
	return DomainResult.failure(&"raw_number", "raw number is not legal for this field", path)

func _normalize_kind(value: Variant, kind: StringName, rule: Dictionary, path: String, depth: int, active_limits: Dictionary) -> DomainResult:
	if kind == KIND_ANY or kind == KIND_JSON:
		return _normalize_json_value(value, path, depth, kind == KIND_JSON and bool(rule.get("allow_raw_numbers", true)), active_limits)
	if kind == KIND_STRING:
		return _normalize_string_kind(value, rule, path, active_limits)
	if kind == KIND_BOOLEAN:
		return _normalize_boolean_kind(value, path)
	if kind == KIND_INTEGER:
		return _normalize_integer_kind(value, path)
	if kind == KIND_NUMBER:
		return _normalize_number_kind(value, path)
	return _normalize_remaining_kind(value, kind, rule, path, depth, active_limits)

func _normalize_remaining_kind(value: Variant, kind: StringName, rule: Dictionary, path: String, depth: int, active_limits: Dictionary) -> DomainResult:
	if kind == KIND_HASH:
		return _normalize_hash(value, path, active_limits)
	if kind == KIND_U64:
		return _normalize_u64(value, path, active_limits)
	if kind == KIND_OBJECT:
		return _normalize_object(value, rule, path, depth, active_limits)
	if kind == KIND_ARRAY:
		return _normalize_array(value, rule, path, depth, active_limits)
	if kind == KIND_NULL:
		if value != null:
			return DomainResult.failure(&"type_mismatch", "value must be null", path)
		return DomainResult.success(null)
	return DomainResult.failure(&"invalid_profile", "unknown profile kind", path)

func _normalize_string_kind(value: Variant, rule: Dictionary, path: String, active_limits: Dictionary) -> DomainResult:
	if typeof(value) != TYPE_STRING and typeof(value) != TYPE_STRING_NAME and not IR.is_scalar_carrier(value):
		return DomainResult.failure(&"type_mismatch", "value must be a string", path)
	return _normalize_string(value, rule, path, active_limits)

func _normalize_boolean_kind(value: Variant, path: String) -> DomainResult:
	if typeof(value) != TYPE_BOOL:
		return DomainResult.failure(&"type_mismatch", "value must be a boolean", path)
	return DomainResult.success(value)

func _normalize_integer_kind(value: Variant, path: String) -> DomainResult:
	if typeof(value) != TYPE_INT:
		return DomainResult.failure(&"type_mismatch", "value must be an integer", path)
	return DomainResult.success(value)

func _normalize_number_kind(value: Variant, path: String) -> DomainResult:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return DomainResult.failure(&"type_mismatch", "value must be a number", path)
	if typeof(value) == TYPE_FLOAT and (is_nan(value) or is_inf(value)):
		return DomainResult.failure(&"invalid_number", "number must be finite", path)
	return DomainResult.success(value)

func _normalize_json_value(value: Variant, path: String, depth: int, allow_raw_numbers: bool, active_limits: Dictionary) -> DomainResult:
	if _is_raw_number(value):
		return _normalize_json_raw_number(value, path, allow_raw_numbers)
	if IR.is_scalar_carrier(value):
		return _normalize_string(value, {}, path, active_limits)
	if IR.is_object_carrier(value):
		return _normalize_open_object(value, path, depth, allow_raw_numbers, active_limits)
	return _normalize_json_typed_value(value, path, depth, allow_raw_numbers, active_limits)

func _normalize_json_raw_number(value: Variant, path: String, allow_raw_numbers: bool) -> DomainResult:
	if allow_raw_numbers:
		return _normalize_raw_number(value, path)
	return DomainResult.failure(&"raw_number", "raw number is not legal", path)

func _normalize_json_typed_value(value: Variant, path: String, depth: int, allow_raw_numbers: bool, active_limits: Dictionary) -> DomainResult:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
			return _normalize_json_scalar(value, path)
		TYPE_STRING, TYPE_STRING_NAME:
			return _normalize_string(value, {}, path, active_limits)
		TYPE_ARRAY:
			return _normalize_json_array(value, path, depth, allow_raw_numbers, active_limits)
		TYPE_DICTIONARY:
			return _normalize_open_object(value, path, depth, allow_raw_numbers, active_limits)
		_:
			return DomainResult.failure(&"unsupported_value", "value is outside JSON data", path)

func _normalize_json_scalar(value: Variant, path: String) -> DomainResult:
	if typeof(value) == TYPE_FLOAT and (is_nan(value) or is_inf(value)):
		return DomainResult.failure(&"invalid_number", "number must be finite", path)
	return DomainResult.success(value)

func _normalize_json_array(value: Array, path: String, depth: int, allow_raw_numbers: bool, active_limits: Dictionary) -> DomainResult:
	if value.size() > _profile_limit(active_limits, &"maximum_array_elements_per_array"):
		return DomainResult.failure(&"array_limit", "maximum array elements exceeded", path)
	var normalized_array: Array = []
	for index: int in range(value.size()):
		var child := _normalize_json_value(value[index], "%s[%d]" % [path, index], depth + 1, allow_raw_numbers, active_limits)
		if not child.is_success():
			return child
		normalized_array.append(child.value())
	return DomainResult.success(normalized_array)

func _normalize_object(value: Variant, rule: Dictionary, path: String, depth: int, active_limits: Dictionary) -> DomainResult:
	var fields: Dictionary = rule.get("fields", {})
	var normalized_fields: Dictionary = {}
	for raw_field: Variant in fields.keys():
		var normalized_name_result: DomainResult = NFC.normalize_result(String(raw_field))
		if not normalized_name_result.is_success():
			return DomainResult.failure(&"invalid_profile", "profile field name is not a Unicode scalar string", path)
		var normalized_name := String(normalized_name_result.value())
		if normalized_fields.has(normalized_name):
			return DomainResult.failure(&"invalid_profile", "profile fields collide after Unicode NFC normalization", path + "." + normalized_name)
		normalized_fields[normalized_name] = fields[raw_field]
	return _normalize_closed_object(value, normalized_fields, path, depth, active_limits)

func _normalize_array(value: Variant, rule: Dictionary, path: String, depth: int, active_limits: Dictionary) -> DomainResult:
	if typeof(value) != TYPE_ARRAY:
		return DomainResult.failure(&"type_mismatch", "value must be an array", path)
	var array: Array = value
	var minimum := int(rule.get("minimum", 0))
	var maximum := int(rule.get("maximum", _profile_limit(active_limits, &"maximum_array_elements_per_array")))
	if array.size() < minimum:
		return DomainResult.failure(&"array_minimum", "array has fewer than its minimum elements", path)
	if array.size() > maximum:
		return DomainResult.failure(&"array_limit", "array has more than its maximum elements", path)
	var item_rule: Dictionary = rule.get("items", {"kind": KIND_JSON})
	var normalized: Array = []
	for index: int in range(array.size()):
		var child := _normalize_node(array[index], item_rule, "%s[%d]" % [path, index], depth + 1, active_limits)
		if not child.is_success():
			return child
		normalized.append(child.value())
	return DomainResult.success(normalized)

func _normalize_hash(value: Variant, path: String, active_limits: Dictionary) -> DomainResult:
	if not _is_string_value(value):
		return DomainResult.failure(&"invalid_hash", "hash must be a string", path)
	var string_result := _normalize_string(value, {}, path, active_limits)
	if not string_result.is_success():
		return string_result
	var digest_scalars := IR.scalar_values(string_result.value())
	if not digest_scalars.is_success():
		return DomainResult.failure(&"invalid_hash", "hash must be a string", path)
	var digest := String(string_result.value()) if typeof(string_result.value()) == TYPE_STRING else ""
	if digest.is_empty() and digest_scalars.value().size() > 0:
		return DomainResult.failure(&"invalid_hash", "hash must contain only ASCII hexadecimal characters", path)
	if digest.length() != 64:
		return DomainResult.failure(&"invalid_hash", "SHA-256 must contain 64 hexadecimal characters", path)
	for character: String in digest:
		if (character < "0" or character > "9") and (character < "a" or character > "f"):
			return DomainResult.failure(&"invalid_hash", "SHA-256 must be lowercase hexadecimal", path)
	return DomainResult.success(digest)

func _normalize_u64(value: Variant, path: String, active_limits: Dictionary) -> DomainResult:
	if not _is_string_value(value):
		return DomainResult.failure(&"invalid_u64_type", "u64 must be a decimal string", path)
	var string_result := _normalize_string(value, {}, path, active_limits)
	if not string_result.is_success():
		return string_result
	if typeof(string_result.value()) != TYPE_STRING:
		return DomainResult.failure(&"invalid_u64", "u64 must contain only ASCII decimal characters", path)
	var normalized := U64Value.normalize(String(string_result.value()))
	if not normalized.is_success():
		return DomainResult.failure(normalized.error_code(), normalized.error_message(), path)
	return normalized

func _normalize_raw_integer(value: Variant, path: String) -> DomainResult:
	var token := _raw_token(value)
	if token.find(".") >= 0 or token.find("e") >= 0 or token.find("E") >= 0:
		return DomainResult.failure(&"raw_number", "integer field requires an integer token", path)
	var parsed := token.to_int()
	if token != "-0" and str(parsed) != token:
		return DomainResult.failure(&"invalid_number", "integer token is outside the supported signed range", path)
	return DomainResult.success(parsed)

func _normalize_raw_number(value: Variant, path: String) -> DomainResult:
	var token := _raw_token(value)
	var number := token.to_float()
	if is_nan(number) or is_inf(number):
		return DomainResult.failure(&"invalid_number", "number must be finite", path)
	if token == "-0":
		return DomainResult.success(0)
	if token.find(".") < 0 and token.find("e") < 0 and token.find("E") < 0 and token.length() <= 18 and JCS.encode(number) == token:
		return DomainResult.success(token.to_int())
	return DomainResult.success(number)

func _normalize_string(value: Variant, rule: Dictionary, path: String, active_limits: Dictionary) -> DomainResult:
	if not _is_string_value(value):
		return DomainResult.failure(&"type_mismatch", "value must be a string", path)
	var source_scalars := IR.scalar_values(value)
	if not source_scalars.is_success():
		return DomainResult.failure(&"invalid_string", "value contains invalid Unicode scalar data", path)
	var normalized_result: DomainResult = NFC.normalize_scalars_result(PackedInt32Array(source_scalars.value()))
	if not normalized_result.is_success():
		return normalized_result
	var normalized_value: Variant = normalized_result.value()
	var normalized_scalars := IR.scalar_values(normalized_value)
	if not normalized_scalars.is_success():
		return DomainResult.failure(&"invalid_string", "normalized value is not scalar data", path)
	return _check_scalar_bounds(PackedInt32Array(normalized_scalars.value()), rule, path, normalized_value, active_limits)

func _normalize_object_keys(value: Dictionary, path: String, active_limits: Dictionary) -> DomainResult:
	var normalized: Dictionary = {}
	for raw_key: Variant in value.keys():
		if not _is_string_value(raw_key):
			return DomainResult.failure(&"invalid_field_name", "object keys must be strings", path)
		var normalized_key_result: DomainResult = _normalize_string(raw_key, {}, path, active_limits)
		if not normalized_key_result.is_success():
			return normalized_key_result
		var normalized_key: Variant = normalized_key_result.value()
		var signature := IR.scalar_signature(normalized_key)
		if normalized.has(signature):
			return DomainResult.failure(&"normalized_key_collision", "object keys collide after Unicode NFC normalization", path + "." + IR.path_component(normalized_key))
		normalized[signature] = {"key": normalized_key, "value": value[raw_key]}
	return DomainResult.success(normalized)

func _check_scalar_bounds(scalars: PackedInt32Array, rule: Dictionary, path: String, value: Variant, active_limits: Dictionary) -> DomainResult:
	var minimum := int(rule.get("minimum", 0))
	var maximum := int(rule.get("maximum", -1))
	var bytes := _scalar_utf8_size(scalars)
	if scalars.size() < minimum or (maximum >= 0 and scalars.size() > maximum):
		return DomainResult.failure(&"string_limit", "string length is outside its profile bounds", path)
	if bytes > _profile_limit(active_limits, &"maximum_total_decoded_scalar_bytes"):
		return DomainResult.failure(&"decoded_scalar_limit", "decoded scalar bytes exceeded", path)
	return DomainResult.success(value)

func _is_string_value(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME or IR.is_scalar_carrier(value)

func _scalar_utf8_size(scalars: PackedInt32Array) -> int:
	var total := 0
	for scalar: int in scalars:
		if scalar <= 0x7f:
			total += 1
		elif scalar <= 0x7ff:
			total += 2
		elif scalar <= 0xffff:
			total += 3
		else:
			total += 4
	return total

func _object_members(value: Variant, path: String) -> DomainResult:
	if IR.is_object_carrier(value):
		return _object_carrier_members(value, path)
	if typeof(value) != TYPE_DICTIONARY:
		return DomainResult.failure(&"closed_shape", "value must be a JSON object", path)
	return _dictionary_members(value, path)

func _object_carrier_members(value: Variant, path: String) -> DomainResult:
	var members: Array = value[IR.IR_OBJECT_MEMBERS_KEY]
	var seen: Dictionary = {}
	for index: int in range(members.size()):
		if typeof(members[index]) != TYPE_DICTIONARY:
			return DomainResult.failure(&"invalid_json_ir", "object carrier members must be dictionaries", path)
		var member: Dictionary = members[index]
		if member.size() != 2 or not member.has("key") or not member.has("value"):
			return DomainResult.failure(&"invalid_json_ir", "object carrier members require key and value", path)
		var key_result := IR.scalar_values(member["key"])
		if not key_result.is_success():
			return DomainResult.failure(&"invalid_json_ir", "object carrier member key is not a string", path)
		var signature := IR.scalar_signature(member["key"])
		if seen.has(signature):
			return DomainResult.failure(&"duplicate_member", "object contains a duplicate member", path + "." + IR.path_component(member["key"]))
		seen[signature] = true
	return DomainResult.success(members)

func _dictionary_members(value: Variant, path: String) -> DomainResult:
	var members: Array = []
	var dictionary: Dictionary = value
	for raw_key: Variant in dictionary.keys():
		if not _is_string_value(raw_key):
			return DomainResult.failure(&"invalid_field_name", "object keys must be strings", path)
		members.append({"key": raw_key, "value": dictionary[raw_key]})
	return DomainResult.success(members)

func _normalize_open_object(value: Variant, path: String, depth: int, allow_raw_numbers: bool, active_limits: Dictionary) -> DomainResult:
	var members_result := _object_members(value, path)
	if not members_result.is_success():
		return members_result
	var members: Array = members_result.value()
	if members.size() > _profile_limit(active_limits, &"maximum_object_members_per_object"):
		return DomainResult.failure(&"object_limit", "maximum object members exceeded", path)
	var normalized_members: Array = []
	var seen: Dictionary = {}
	for index: int in range(members.size()):
		var member: Dictionary = members[index]
		var normalized_key_result := _normalize_string(member["key"], {}, path, active_limits)
		if not normalized_key_result.is_success():
			return normalized_key_result
		var normalized_key: Variant = normalized_key_result.value()
		var signature := IR.scalar_signature(normalized_key)
		if seen.has(signature):
			return DomainResult.failure(&"normalized_key_collision", "object keys collide after Unicode NFC normalization", path + "." + IR.path_component(normalized_key))
		seen[signature] = true
		var child_path := path + "." + IR.path_component(normalized_key)
		var child: DomainResult
		if _is_raw_number(member["value"]):
			child = _normalize_raw_number(member["value"], child_path) if allow_raw_numbers else DomainResult.failure(&"raw_number", "raw number is not legal", child_path)
		else:
			child = _normalize_json_value(member["value"], child_path, depth + 1, allow_raw_numbers, active_limits)
		if not child.is_success():
			return child
		normalized_members.append({"key": normalized_key, "value": child.value()})
	return DomainResult.success(IR.materialize_object(normalized_members))

func _normalize_closed_object(value: Variant, fields: Dictionary, path: String, depth: int, active_limits: Dictionary) -> DomainResult:
	var members_result := _object_members(value, path)
	if not members_result.is_success():
		return members_result
	var members: Array = members_result.value()
	if members.size() > _profile_limit(active_limits, &"maximum_object_members_per_object"):
		return DomainResult.failure(&"object_limit", "maximum object members exceeded", path)
	var normalized_values: Dictionary = {}
	var seen: Dictionary = {}
	for member: Dictionary in members:
		var normalized_member := _normalize_closed_member(member, fields, path, depth, active_limits, seen)
		if not normalized_member.is_success():
			return normalized_member
		var member_value: Dictionary = normalized_member.value()
		normalized_values[String(member_value["field_name"])] = member_value["value"]
	var missing_result := _validate_closed_members_present(fields, normalized_values, path)
	if not missing_result.is_success():
		return missing_result
	var output: Dictionary = {}
	for field_name: Variant in fields.keys():
		output[String(field_name)] = normalized_values[field_name]
	return DomainResult.success(output)

func _normalize_closed_member(member: Dictionary, fields: Dictionary, path: String, depth: int, active_limits: Dictionary, seen: Dictionary) -> DomainResult:
	var normalized_key_result := _normalize_string(member["key"], {}, path, active_limits)
	if not normalized_key_result.is_success():
		return normalized_key_result
	var normalized_key: Variant = normalized_key_result.value()
	var signature := IR.scalar_signature(normalized_key)
	if seen.has(signature):
		return DomainResult.failure(&"normalized_key_collision", "object keys collide after Unicode NFC normalization", path + "." + IR.path_component(normalized_key))
	seen[signature] = true
	if typeof(normalized_key) != TYPE_STRING and typeof(normalized_key) != TYPE_STRING_NAME:
		return DomainResult.failure(&"unknown_field", "object member is not declared by the closed shape", path + "." + IR.path_component(normalized_key))
	var field_name := String(normalized_key)
	if not fields.has(field_name):
		return DomainResult.failure(&"unknown_field", "object member is not declared by the closed shape", path + "." + field_name)
	var child := _normalize_node(member["value"], fields[field_name], path + "." + field_name, depth + 1, active_limits)
	if not child.is_success():
		return child
	return DomainResult.success({"field_name": field_name, "value": child.value()})

func _validate_closed_members_present(fields: Dictionary, normalized_values: Dictionary, path: String) -> DomainResult:
	for field_name: Variant in fields.keys():
		if not normalized_values.has(field_name):
			return DomainResult.failure(&"missing_field", "required field is missing", path + "." + String(field_name))
	return DomainResult.success(true)

func _is_raw_number(value: Variant) -> bool:
	return CanonicalCodec.is_raw_number_token(value)

func _raw_token(value: Variant) -> String:
	return CanonicalCodec.raw_number_token_text(value) if _is_raw_number(value) else ""

func _profile_limit(active_limits: Dictionary, name: StringName) -> int:
	return int(active_limits.get(name, 0))

static func _validate_declarations(field_names: Array[StringName], field_rules: Dictionary, limits: Dictionary) -> DomainResult:
	var seen: Dictionary = {}
	for field_name: StringName in field_names:
		if field_name.is_empty():
			return DomainResult.failure(&"invalid_profile", "profile field names cannot be empty")
		if seen.has(field_name):
			return DomainResult.failure(&"duplicate_field", "profile field appears more than once")
		seen[field_name] = true
	var limits_result := _validate_limits(limits)
	if not limits_result.is_success():
		return limits_result
	for raw_key: Variant in field_rules.keys():
		if typeof(raw_key) != TYPE_STRING and typeof(raw_key) != TYPE_STRING_NAME:
			return DomainResult.failure(&"invalid_profile", "profile rule names must be strings", "$.fields")
		var key := StringName(raw_key)
		if not seen.has(key):
			return DomainResult.failure(&"unknown_field", "profile rule names must be declared fields", "$." + String(key))
		var rule_result := _validate_rule(field_rules[raw_key], "$." + String(key))
		if not rule_result.is_success():
			return rule_result
	return DomainResult.success(true)

static func _validate_pure_data(value: Variant, path: String) -> DomainResult:
	var value_type := typeof(value)
	if value_type == TYPE_NIL or value_type == TYPE_BOOL or value_type == TYPE_INT or value_type == TYPE_STRING or value_type == TYPE_STRING_NAME:
		return DomainResult.success(true)
	if value_type == TYPE_FLOAT:
		return _validate_pure_profile_float(value, path)
	if value_type == TYPE_ARRAY:
		return _validate_pure_profile_array(value, path)
	if value_type == TYPE_DICTIONARY:
		return _validate_pure_profile_dictionary(value, path)
	return DomainResult.failure(&"invalid_profile", "profile data cannot contain objects or packed arrays", path)

static func _validate_pure_profile_float(value: float, path: String) -> DomainResult:
	if is_nan(value) or is_inf(value):
		return DomainResult.failure(&"invalid_profile", "profile data must be finite", path)
	return DomainResult.success(true)

static func _validate_pure_profile_array(value: Array, path: String) -> DomainResult:
	for index: int in range(value.size()):
		var child := _validate_pure_data(value[index], "%s[%d]" % [path, index])
		if not child.is_success():
			return child
	return DomainResult.success(true)

static func _validate_pure_profile_dictionary(value: Dictionary, path: String) -> DomainResult:
	for raw_key: Variant in value.keys():
		if typeof(raw_key) != TYPE_STRING and typeof(raw_key) != TYPE_STRING_NAME:
			return DomainResult.failure(&"invalid_profile", "profile data keys must be strings", path)
		var child := _validate_pure_data(value[raw_key], path + "." + String(raw_key))
		if not child.is_success():
			return child
	return DomainResult.success(true)

static func _validate_rule(rule: Variant, path: String) -> DomainResult:
	var pure := _validate_pure_data(rule, path)
	if not pure.is_success():
		return pure
	if typeof(rule) != TYPE_DICTIONARY:
		return DomainResult.failure(&"invalid_profile", "field rules must be dictionaries", path)
	var dictionary: Dictionary = rule
	var kind := StringName(dictionary.get("kind", KIND_JSON))
	var allowed := [KIND_ANY, KIND_JSON, KIND_STRING, KIND_BOOLEAN, KIND_INTEGER, KIND_NUMBER, KIND_HASH, KIND_U64, KIND_OBJECT, KIND_ARRAY, KIND_NULL]
	if not allowed.has(kind):
		return DomainResult.failure(&"invalid_profile", "unknown field rule kind", path)
	var members_result := _validate_rule_members(dictionary, path)
	if not members_result.is_success():
		return members_result
	var bounds_result := _validate_rule_bounds(dictionary, path)
	if not bounds_result.is_success():
		return bounds_result
	var nested_result := _validate_nested_rules(dictionary, kind, path)
	if not nested_result.is_success():
		return nested_result
	return DomainResult.success(true)

static func _validate_rule_members(dictionary: Dictionary, path: String) -> DomainResult:
	var allowed_keys := ["kind", "minimum", "maximum", "items", "fields", "allow_raw_numbers"]
	for raw_key: Variant in dictionary.keys():
		if typeof(raw_key) != TYPE_STRING and typeof(raw_key) != TYPE_STRING_NAME:
			return DomainResult.failure(&"invalid_profile", "rule members must be strings", path)
		if not allowed_keys.has(String(raw_key)):
			return DomainResult.failure(&"invalid_profile", "rule contains an undeclared member", path + "." + String(raw_key))
	return DomainResult.success(true)

static func _validate_rule_bounds(dictionary: Dictionary, path: String) -> DomainResult:
	if dictionary.has("minimum") and (typeof(dictionary["minimum"]) != TYPE_INT or int(dictionary["minimum"]) < 0):
		return DomainResult.failure(&"invalid_profile", "rule minimum must be a non-negative integer", path)
	if dictionary.has("maximum") and (typeof(dictionary["maximum"]) != TYPE_INT or int(dictionary["maximum"]) < 0):
		return DomainResult.failure(&"invalid_profile", "rule maximum must be a non-negative integer", path)
	if dictionary.has("minimum") and dictionary.has("maximum") and int(dictionary["minimum"]) > int(dictionary["maximum"]):
		return DomainResult.failure(&"invalid_profile", "rule minimum cannot exceed maximum", path)
	if dictionary.has("allow_raw_numbers") and typeof(dictionary["allow_raw_numbers"]) != TYPE_BOOL:
		return DomainResult.failure(&"invalid_profile", "rule allow_raw_numbers must be boolean", path)
	return DomainResult.success(true)

static func _validate_nested_rules(dictionary: Dictionary, kind: StringName, path: String) -> DomainResult:
	if kind == KIND_OBJECT:
		var fields: Variant = dictionary.get("fields", {})
		if typeof(fields) != TYPE_DICTIONARY:
			return DomainResult.failure(&"invalid_profile", "object rule fields must be a dictionary", path)
		for raw_key: Variant in fields.keys():
			if typeof(raw_key) != TYPE_STRING and typeof(raw_key) != TYPE_STRING_NAME:
				return DomainResult.failure(&"invalid_profile", "object rule field names must be strings", path)
			var child := _validate_rule(fields[raw_key], path + "." + String(raw_key))
			if not child.is_success():
				return child
	if kind == KIND_ARRAY and dictionary.has("items"):
		var item := _validate_rule(dictionary["items"], path + "[]")
		if not item.is_success():
			return item
	return DomainResult.success(true)

static func _validate_limits(limits: Dictionary) -> DomainResult:
	var pure := _validate_pure_data(limits, "$.limits")
	if not pure.is_success():
		return pure
	for raw_key: Variant in limits.keys():
		if typeof(raw_key) != TYPE_STRING and typeof(raw_key) != TYPE_STRING_NAME:
			return DomainResult.failure(&"invalid_profile", "limit names must be strings", "$.limits")
		var key := String(raw_key)
		if not DEFAULT_LIMITS.has(key) and not DEFAULT_LIMITS.has(StringName(raw_key)):
			return DomainResult.failure(&"invalid_profile", "unknown profile limit", "$.limits." + key)
		if typeof(limits[raw_key]) != TYPE_INT or int(limits[raw_key]) <= 0:
			return DomainResult.failure(&"invalid_profile", "profile limits must be positive integers", "$.limits." + key)
	return DomainResult.success(true)

static func _contains_key(dictionary: Dictionary, field_name: StringName) -> bool:
	return dictionary.has(field_name) or dictionary.has(String(field_name))

static func _source_key(dictionary: Dictionary, field_name: StringName) -> Variant:
	return field_name if dictionary.has(field_name) else String(field_name)

static func _contains_declared_name(names: Array[StringName], field_name: String) -> bool:
	for declared_name: StringName in names:
		if String(declared_name) == field_name:
			return true
	return false

static func _contains_rule_key(fields: Dictionary, field_name: String) -> bool:
	for declared_name: Variant in fields.keys():
		if String(declared_name) == field_name:
			return true
	return false
