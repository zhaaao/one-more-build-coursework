class_name CanonicalJsonIR
extends RefCounted

## Pure-data carriers for JSON scalars that Godot String cannot represent
## losslessly. This utility never returns itself or another Object in its data.
## String and PackedInt32Array are semantically equal when they contain the same
## Unicode scalar sequence; a scalar carrier is selected when materialization
## would replace a scalar (notably U+0000) or otherwise lose its value.

## Object carriers use integer sentinel keys because runtime JSON object keys
## are restricted to strings.  The exact shape therefore cannot be forged by
## parsing an ordinary JSON object, while remaining pure Variant data.
const IR_OBJECT_TAG_KEY: int = -2147483647
const IR_OBJECT_MEMBERS_KEY: int = -2147483646
const IR_OBJECT_TAG: String = "canonical_json_object_v1"

# This pure-data lexical carrier is produced only by CanonicalCodec while a
# raw number is waiting for the shape profile.  It must remain cloneable when
# an object also contains a non-materializable string key (for example NUL).
const RAW_NUMBER_TAG_KEY: int = -2147483645
const RAW_NUMBER_TEXT_KEY: int = -2147483644
const RAW_NUMBER_TAG: String = "canonical_raw_number_v1"

## Copies a scalar sequence into the IR carrier form.
## Example: `var nul := CanonicalJsonIR.scalar_carrier(PackedInt32Array([0]))`.
static func scalar_carrier(scalars: PackedInt32Array) -> PackedInt32Array:
	return PackedInt32Array(scalars)

## Builds a defensive pure-data object carrier from ordered members.
## Example: `CanonicalJsonIR.object_carrier([{"key": "id", "value": 1}])`.
static func object_carrier(members: Array) -> Dictionary:
	var copied_members: Array = []
	for raw_member: Variant in members:
		if typeof(raw_member) != TYPE_DICTIONARY:
			return _invalid_object_carrier()
		var member: Dictionary = raw_member
		if member.size() != 2 or not member.has("key") or not member.has("value"):
			return _invalid_object_carrier()
		if not scalar_values(member["key"]).is_success():
			return _invalid_object_carrier()
		if not validate_pure_json(member["value"]).is_success():
			return _invalid_object_carrier()
		copied_members.append({"key": _clone_pure(member["key"]), "value": _clone_pure(member["value"])})
	return _object_carrier_from_owned_members(copied_members)

## Identifies a packed Unicode scalar carrier.
## Example: `CanonicalJsonIR.is_scalar_carrier(PackedInt32Array([0]))`.
static func is_scalar_carrier(value: Variant) -> bool:
	return typeof(value) == TYPE_PACKED_INT32_ARRAY

## Identifies the exact pure-data object carrier marker shape.
## Example: `CanonicalJsonIR.is_object_carrier(candidate)`.
static func is_object_carrier(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var dictionary: Dictionary = value
	return dictionary.size() == 2 and dictionary.get(IR_OBJECT_TAG_KEY, null) == IR_OBJECT_TAG and typeof(dictionary.get(IR_OBJECT_MEMBERS_KEY, null)) == TYPE_ARRAY

## Returns validated Unicode scalar values for a JSON string representation.
## Example: `var scalars := CanonicalJsonIR.scalar_values("text")`.
static func scalar_values(value: Variant) -> DomainResult:
	if typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME:
		var text := String(value)
		var scalars := PackedInt32Array()
		for index: int in range(text.length()):
			var scalar := text.unicode_at(index)
			if not _is_scalar(scalar):
				return DomainResult.failure(&"invalid_string", "string contains a non-Unicode-scalar value")
			scalars.append(scalar)
		return DomainResult.success(scalars)
	if is_scalar_carrier(value):
		var carrier: PackedInt32Array = value
		for scalar: int in carrier:
			if not _is_scalar(scalar):
				return DomainResult.failure(&"invalid_string", "scalar carrier contains a non-Unicode-scalar value")
		return DomainResult.success(PackedInt32Array(carrier))
	return DomainResult.failure(&"type_mismatch", "value must be a JSON string")

## Materializes validated scalars as a String when lossless, otherwise a carrier.
## Example: `CanonicalJsonIR.from_scalars(PackedInt32Array([0x61]))`.
static func from_scalars(scalars: PackedInt32Array) -> DomainResult:
	for scalar: int in scalars:
		if not _is_scalar(scalar):
			return DomainResult.failure(&"invalid_string", "scalar carrier contains a non-Unicode-scalar value")
		if scalar == 0:
			return DomainResult.success(PackedInt32Array(scalars))
	var characters := PackedStringArray()
	for scalar: int in scalars:
		var character := String.chr(scalar)
		if character.length() != 1 or character.unicode_at(0) != scalar:
			return DomainResult.success(PackedInt32Array(scalars))
		characters.append(character)
	var text := "".join(characters)
	return DomainResult.success(text)

## Returns a stable hexadecimal identity for a Unicode scalar sequence.
## Example: `var signature := CanonicalJsonIR.scalar_signature("id")`.
static func scalar_signature(value: Variant) -> String:
	var scalar_result := scalar_values(value)
	if not scalar_result.is_success():
		return ""
	var signature_bytes := PackedByteArray()
	for scalar: int in scalar_result.value():
		signature_bytes.append((scalar >> 24) & 0xff)
		signature_bytes.append((scalar >> 16) & 0xff)
		signature_bytes.append((scalar >> 8) & 0xff)
		signature_bytes.append(scalar & 0xff)
	return signature_bytes.hex_encode()

## Returns a bounded diagnostic path component for a JSON string key.
## Example: `var path_key := CanonicalJsonIR.path_component("id")`.
static func path_component(value: Variant) -> String:
	var scalar_result := scalar_values(value)
	if not scalar_result.is_success():
		return "<invalid-string>"
	var text_result := from_scalars(scalar_result.value())
	if text_result.is_success() and typeof(text_result.value()) == TYPE_STRING:
		var text := String(text_result.value())
		var text_bytes := text.to_utf8_buffer()
		if text_bytes.size() <= 64:
			return text
		return "<key:" + text_bytes.slice(0, 16).hex_encode() + ":" + _sha256_hex(text_bytes) + ">"
	var scalar_bytes := _scalar_utf8_bytes(PackedInt32Array(scalar_result.value()))
	if scalar_bytes.size() <= 16:
		return "<scalar-key:" + scalar_signature(value) + ">"
	return "<scalar-key:" + scalar_bytes.slice(0, 16).hex_encode() + ":" + _sha256_hex(scalar_bytes) + ">"

## Validates an object carrier and every nested pure-data member.
## Example: `var checked := CanonicalJsonIR.validate_object_carrier(candidate)`.
static func validate_object_carrier(value: Variant) -> DomainResult:
	if not is_object_carrier(value):
		return DomainResult.failure(&"invalid_json_ir", "object carrier has an invalid marker shape")
	var members: Array = value[IR_OBJECT_MEMBERS_KEY]
	var seen: Dictionary = {}
	for index: int in range(members.size()):
		if typeof(members[index]) != TYPE_DICTIONARY:
			return DomainResult.failure(&"invalid_json_ir", "object carrier members must be dictionaries", "[%d]" % index)
		var member: Dictionary = members[index]
		if member.size() != 2 or not member.has("key") or not member.has("value"):
			return DomainResult.failure(&"invalid_json_ir", "object carrier members require key and value", "[%d]" % index)
		var key_result := scalar_values(member["key"])
		if not key_result.is_success():
			return DomainResult.failure(&"invalid_json_ir", "object carrier member key is not a string", "[%d].key" % index)
		var signature := scalar_signature(member["key"])
		if seen.has(signature):
			return DomainResult.failure(&"duplicate_member", "object contains a duplicate member", "[%d].key" % index)
		seen[signature] = true
		var child := validate_pure_json(member["value"], "[%d].value" % index)
		if not child.is_success():
			return child
	return DomainResult.success(true)

## Validates a complete pure JSON/IR value without coercing unsupported types.
## Example: `var checked := CanonicalJsonIR.validate_pure_json(value)`.
static func validate_pure_json(value: Variant, path: String = "$") -> DomainResult:
	if _is_raw_number_token(value):
		return DomainResult.success(true)
	if typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME or is_scalar_carrier(value):
		return _validate_pure_scalar(value, path)
	if is_object_carrier(value):
		return validate_object_carrier(value)
	return _validate_pure_typed_value(value, path)

static func _validate_pure_scalar(value: Variant, path: String) -> DomainResult:
	var scalar_result := scalar_values(value)
	if scalar_result.is_success():
		return DomainResult.success(true)
	return DomainResult.failure(&"invalid_json_ir", "string scalar data is invalid", path)

static func _validate_pure_typed_value(value: Variant, path: String) -> DomainResult:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return DomainResult.success(true)
		TYPE_FLOAT:
			return _validate_pure_float(value, path)
		TYPE_ARRAY:
			return _validate_pure_array(value, path)
		TYPE_DICTIONARY:
			return _validate_pure_dictionary(value, path)
		_:
			return DomainResult.failure(&"invalid_json_ir", "JSON IR contains an unsupported value", path)

static func _validate_pure_float(value: float, path: String) -> DomainResult:
	if is_nan(value) or is_inf(value):
		return DomainResult.failure(&"invalid_number", "number must be finite", path)
	return DomainResult.success(true)

static func _validate_pure_array(value: Array, path: String) -> DomainResult:
	for index: int in range(value.size()):
		var child := validate_pure_json(value[index], "%s[%d]" % [path, index])
		if not child.is_success():
			return child
	return DomainResult.success(true)

static func _validate_pure_dictionary(value: Dictionary, path: String) -> DomainResult:
	for raw_key: Variant in value.keys():
		if typeof(raw_key) != TYPE_STRING and typeof(raw_key) != TYPE_STRING_NAME:
			return DomainResult.failure(&"invalid_json_ir", "ordinary JSON object keys must be strings", path)
		var child := validate_pure_json(value[raw_key], path + "." + String(raw_key))
		if not child.is_success():
			return child
	return DomainResult.success(true)

## Materializes ordered object members, retaining a carrier when a key is not a String.
## Example: `var object := CanonicalJsonIR.materialize_object(members)`.
static func materialize_object(members: Array) -> Variant:
	var object: Dictionary = {}
	for member: Dictionary in members:
		var key: Variant = member["key"]
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
			return object_carrier(members)
		object[String(key)] = member["value"]
	return object

## Deep-copies a pure JSON/IR value, including packed arrays.
## Example: `var owned := CanonicalJsonIR.clone(untrusted_value)`.
static func clone(value: Variant) -> Variant:
	if typeof(value) == TYPE_PACKED_BYTE_ARRAY:
		return PackedByteArray(value)
	if not validate_pure_json(value).is_success():
		return null
	return _clone_pure(value)

static func _clone_pure(value: Variant) -> Variant:
	if is_scalar_carrier(value):
		return PackedInt32Array(value)
	if is_object_carrier(value):
		return _clone_object_carrier(value)
	return _clone_typed_value(value)

static func _clone_object_carrier(value: Dictionary) -> Dictionary:
	var copied_members: Array = []
	for member: Dictionary in value[IR_OBJECT_MEMBERS_KEY]:
		copied_members.append({"key": _clone_pure(member["key"]), "value": _clone_pure(member["value"])})
	return _object_carrier_from_owned_members(copied_members)

static func _clone_typed_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_ARRAY:
			return _clone_array(value)
		TYPE_DICTIONARY:
			return _clone_dictionary(value)
		TYPE_PACKED_INT32_ARRAY:
			return PackedInt32Array(value)
		TYPE_PACKED_BYTE_ARRAY:
			return PackedByteArray(value)
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return value
		_:
			return null

static func _clone_array(value: Array) -> Array:
	var copied_array: Array = []
	for item: Variant in value:
		copied_array.append(_clone_pure(item))
	return copied_array

static func _clone_dictionary(value: Dictionary) -> Dictionary:
	var copied_dictionary: Dictionary = {}
	for raw_key: Variant in value.keys():
		copied_dictionary[raw_key] = _clone_pure(value[raw_key])
	return copied_dictionary

## Compares JSON strings by scalar sequence and objects by normalized member identity.
## Example: `CanonicalJsonIR.equal("e" + "\\u0301", "é")`.
static func equal(left: Variant, right: Variant) -> bool:
	var scalar_equal: Variant = _equal_scalar_values(left, right)
	if scalar_equal != null:
		return bool(scalar_equal)
	if is_object_carrier(left) or is_object_carrier(right):
		return _equal_object_values(left, right)
	return _equal_typed_values(left, right)

static func _equal_scalar_values(left: Variant, right: Variant) -> Variant:
	var left_scalars := scalar_values(left)
	var right_scalars := scalar_values(right)
	if not left_scalars.is_success() and not right_scalars.is_success():
		return null
	if not left_scalars.is_success() or not right_scalars.is_success():
		return false
	return PackedInt32Array(left_scalars.value()) == PackedInt32Array(right_scalars.value())

static func _equal_object_values(left: Variant, right: Variant) -> bool:
	var left_members_value: Variant = _object_members_for_equality(left)
	var right_members_value: Variant = _object_members_for_equality(right)
	if left_members_value == null or right_members_value == null:
		return false
	var left_members: Array = left_members_value
	var right_members: Array = right_members_value
	if left_members.size() != right_members.size():
		return false
	var right_by_key: Dictionary = {}
	for member: Dictionary in right_members:
		right_by_key[scalar_signature(member["key"])] = member["value"]
	for left_member: Dictionary in left_members:
		var key_signature := scalar_signature(left_member["key"])
		if not right_by_key.has(key_signature) or not equal(left_member["value"], right_by_key[key_signature]):
			return false
	return true

static func _equal_typed_values(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	match typeof(left):
		TYPE_ARRAY:
			return _equal_arrays(left, right)
		TYPE_DICTIONARY:
			return _equal_dictionaries(left, right)
		TYPE_PACKED_INT32_ARRAY:
			return PackedInt32Array(left) == PackedInt32Array(right)
		_:
			return left == right

static func _equal_arrays(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	for index: int in range(left.size()):
		if not equal(left[index], right[index]):
			return false
	return true

static func _equal_dictionaries(left: Dictionary, right: Dictionary) -> bool:
	if left.size() != right.size():
		return false
	for key: Variant in left.keys():
		if not right.has(key) or not equal(left[key], right[key]):
			return false
	return true

static func _is_scalar(value: int) -> bool:
	return value >= 0 and value <= 0x10ffff and not (value >= 0xd800 and value <= 0xdfff)

static func _object_members_for_equality(value: Variant) -> Variant:
	if is_object_carrier(value):
		if not validate_object_carrier(value).is_success():
			return null
		return value[IR_OBJECT_MEMBERS_KEY]
	if typeof(value) != TYPE_DICTIONARY:
		return null
	var members: Array = []
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
			return null
		members.append({"key": key, "value": value[key]})
	return members

static func _object_carrier_from_owned_members(members: Array) -> Dictionary:
	return {IR_OBJECT_TAG_KEY: IR_OBJECT_TAG, IR_OBJECT_MEMBERS_KEY: members}

static func _invalid_object_carrier() -> Dictionary:
	# Keep the failure marker pure and structurally recognizable so the next
	# codec/profile boundary rejects it instead of coercing an Object to null.
	return {IR_OBJECT_TAG_KEY: IR_OBJECT_TAG, IR_OBJECT_MEMBERS_KEY: [{"invalid": true}]}

static func _is_raw_number_token(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var token: Dictionary = value
	return token.size() == 2 and token.get(RAW_NUMBER_TAG_KEY, null) == RAW_NUMBER_TAG and typeof(token.get(RAW_NUMBER_TEXT_KEY, null)) == TYPE_STRING

static func _scalar_utf8_bytes(scalars: PackedInt32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	for scalar: int in scalars:
		if scalar <= 0x7f:
			bytes.append(scalar)
		elif scalar <= 0x7ff:
			bytes.append(0xc0 | (scalar >> 6))
			bytes.append(0x80 | (scalar & 0x3f))
		elif scalar <= 0xffff:
			bytes.append(0xe0 | (scalar >> 12))
			bytes.append(0x80 | ((scalar >> 6) & 0x3f))
			bytes.append(0x80 | (scalar & 0x3f))
		else:
			bytes.append(0xf0 | (scalar >> 18))
			bytes.append(0x80 | ((scalar >> 12) & 0x3f))
			bytes.append(0x80 | ((scalar >> 6) & 0x3f))
			bytes.append(0x80 | (scalar & 0x3f))
	return bytes

static func _sha256_hex(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(bytes)
	return context.finish().hex_encode()
