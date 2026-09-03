class_name CanonicalCodec
extends RefCounted

const NFC = preload("res://src/foundation/unicode_nfc.gd")
const IR = preload("res://src/foundation/canonical_json_ir.gd")
const JCS = preload("res://src/foundation/jcs_binary64.gd")

# Parser-only lexical number carrier. Integer keys make this shape impossible
# to produce through JSON object syntax, while keeping the intermediate IR
# pure Variant data (no RefCounted token can be retained in an object carrier).
const RAW_NUMBER_TAG_KEY: int = IR.RAW_NUMBER_TAG_KEY
const RAW_NUMBER_TEXT_KEY: int = IR.RAW_NUMBER_TEXT_KEY
const RAW_NUMBER_TAG: String = IR.RAW_NUMBER_TAG
const MIN_EXACT_BINARY64_INTEGER: int = -9007199254740992
const MAX_EXACT_BINARY64_INTEGER: int = 9007199254740992

## Byte-first Foundation codec for the project `runtime_json_v1` profile.
##
## Raw bytes are retained and lexed before any ordinary JSON normalization.
## This preserves malformed UTF-8, duplicate-member, raw-number, and limit
## witnesses. The codec itself is generic; GVET meaning lives in the shape
## profile supplied by the caller.

## Decodes, validates, canonicalizes, and hashes one bounded JSON byte value.
## Example: `CanonicalCodec.decode(raw_bytes, bundle_profile)`.
static func decode(raw_bytes: PackedByteArray, profile: ContractShapeProfile = null) -> DomainResult:
	return ValidatedCanonicalDocument.from_raw(raw_bytes, profile)

## Decodes and proves one raw value without publishing a contract record.
## The returned dictionary is an owned pure-data proof packet consumed by the
## validated-document owner; callers cannot use it as a domain record.
## Example: `var proof := CanonicalCodec.decode_parts(raw_bytes, profile)`.
static func decode_parts(raw_bytes: PackedByteArray, profile: ContractShapeProfile = null) -> DomainResult:
	var active_profile := profile if profile != null else ContractShapeProfile.unrestricted()
	var maximum_payload := active_profile.limit(&"maximum_payload_bytes")
	if maximum_payload > 0 and raw_bytes.size() > maximum_payload:
		return DomainResult.failure(&"payload_limit", "payload exceeds its maximum byte bound", "$", maximum_payload, maximum_payload, &"record_not_allocated")
	var owned_bytes := PackedByteArray(raw_bytes)
	var utf8_result := _validate_utf8(owned_bytes)
	if not utf8_result.is_success():
		return utf8_result
	var parser := _ByteParser.new(owned_bytes, active_profile.limits())
	var parsed := parser.parse_document()
	if not parsed.is_success():
		return parsed
	var normalized := active_profile.validate_and_normalize(parsed.value())
	if not normalized.is_success():
		return DomainResult.failure(normalized.error_code(), normalized.error_message(), normalized.path_witness(), normalized.byte_offset(), owned_bytes.size(), &"record_not_allocated")
	var canonical_result := encode(normalized.value())
	if not canonical_result.is_success():
		return canonical_result
	var canonical_bytes: PackedByteArray = canonical_result.value()
	var digest := sha256_hex(canonical_bytes)
	if digest.is_empty():
		return DomainResult.failure(&"hash_failed", "SHA-256 context could not be initialized")
	return DomainResult.success({
		"raw_bytes": PackedByteArray(owned_bytes),
		"canonical_bytes": PackedByteArray(canonical_bytes),
		"sha256": digest,
		"value": IR.clone(normalized.value()),
	})

## Validates raw JSON bytes without publishing a normalized value.
## Example: `CanonicalCodec.validate_raw_bytes(raw_bytes)` is useful for
## constructors that must prove their retained source before storing it.
static func validate_raw_bytes(raw_bytes: PackedByteArray, profile: ContractShapeProfile = null) -> DomainResult:
	var active_profile := profile if profile != null else ContractShapeProfile.unrestricted()
	var maximum_payload := active_profile.limit(&"maximum_payload_bytes")
	if maximum_payload > 0 and raw_bytes.size() > maximum_payload:
		return DomainResult.failure(&"payload_limit", "payload exceeds its maximum byte bound", "$", maximum_payload, maximum_payload, &"record_not_allocated")
	var owned_bytes := PackedByteArray(raw_bytes)
	var utf8_result := _validate_utf8(owned_bytes)
	if not utf8_result.is_success():
		return utf8_result
	var parser := _ByteParser.new(owned_bytes, active_profile.limits())
	return parser.parse_document()

## Encodes a JSON value using deterministic JCS member ordering.
## Example: `CanonicalCodec.encode({"b": 2, "a": 1})` returns `{"a":1,"b":2}`.
static func encode(value: Variant) -> DomainResult:
	var encoded := _encode_value(value)
	if not encoded.is_success():
		return encoded
	return DomainResult.success(String(encoded.value()).to_utf8_buffer())

## Encodes ordered object members while preserving duplicate-key detection.
## Each member must contain exactly `key` and `value` fields.
## Example: `CanonicalCodec.encode_object_members([{"key": "id", "value": 1}])`.
static func encode_object_members(members: Array[Dictionary]) -> DomainResult:
	var normalized_members: Array = []
	var seen: Dictionary = {}
	for member: Dictionary in members:
		if member.size() != 2 or not member.has("key") or not member.has("value"):
			return DomainResult.failure(&"invalid_member", "object members require key and value")
		var key: Variant = member["key"]
		var key_scalars := IR.scalar_values(key)
		if not key_scalars.is_success():
			return DomainResult.failure(&"invalid_field_name", "object keys must be strings")
		var value_result := IR.validate_pure_json(member["value"], "$." + IR.path_component(key))
		if not value_result.is_success():
			return value_result
		var signature := IR.scalar_signature(key)
		if seen.has(signature):
			return DomainResult.failure(&"duplicate_key", "object contains a duplicate key", "$." + IR.path_component(key))
		seen[signature] = true
		normalized_members.append({"key": key, "value": member["value"]})
	return encode(IR.object_carrier(normalized_members))

## Returns lowercase SHA-256 for exact canonical bytes.
## Example: `CanonicalCodec.sha256_hex(canonical_bytes)` hashes those exact bytes.
static func sha256_hex(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	# Godot 4.7 exposes HashingContext.update() as void; completion failure is
	# reported by finish(), whose empty result is handled by callers.
	context.update(PackedByteArray(bytes))
	var digest := context.finish()
	return digest.hex_encode()

## Encodes a value and hashes the resulting bytes.
## Example: `CanonicalCodec.encode_with_hash({"id": "graph-1"})` returns bytes and digest.
static func encode_with_hash(value: Variant) -> DomainResult:
	var encoded := encode(value)
	if not encoded.is_success():
		return encoded
	var bytes: PackedByteArray = encoded.value()
	var digest := sha256_hex(bytes)
	if digest.is_empty():
		return DomainResult.failure(&"hash_failed", "SHA-256 context could not be initialized")
	return DomainResult.success({"bytes": PackedByteArray(bytes), "sha256": digest})

static func _validate_utf8(bytes: PackedByteArray) -> DomainResult:
	var index := 0
	while index < bytes.size():
		var first: int = bytes[index]
		var leading := _utf8_leading_sequence(first)
		if leading.is_empty():
			return DomainResult.failure(&"malformed_utf8", "invalid UTF-8 leading byte", "", index, index + 1, &"record_not_allocated")
		var width: int = leading[0]
		var minimum: int = leading[1]
		if width == 1:
			index += 1
			continue
		if index + width > bytes.size():
			return DomainResult.failure(&"malformed_utf8", "truncated UTF-8 sequence", "", index, bytes.size(), &"record_not_allocated")
		var codepoint_result := _decode_utf8_codepoint(bytes, index, width)
		if not codepoint_result.is_success():
			return codepoint_result
		var codepoint: int = codepoint_result.value()
		if codepoint < minimum or codepoint > 0x10ffff or (codepoint >= 0xd800 and codepoint <= 0xdfff):
			return DomainResult.failure(&"malformed_utf8", "non-shortest or surrogate UTF-8 sequence", "", index, index + width, &"record_not_allocated")
		index += width
	return DomainResult.success(true)

static func _utf8_leading_sequence(first: int) -> PackedInt32Array:
	if first <= 0x7f:
		return PackedInt32Array([1, 0])
	if first >= 0xc2 and first <= 0xdf:
		return PackedInt32Array([2, 0x80])
	if first >= 0xe0 and first <= 0xef:
		return PackedInt32Array([3, 0x800])
	if first >= 0xf0 and first <= 0xf4:
		return PackedInt32Array([4, 0x10000])
	return PackedInt32Array()

static func _decode_utf8_codepoint(bytes: PackedByteArray, index: int, width: int) -> DomainResult:
	var codepoint: int = bytes[index] & ((1 << (8 - width - 1)) - 1)
	for continuation_index: int in range(1, width):
		var next: int = bytes[index + continuation_index]
		if next < 0x80 or next > 0xbf:
			return DomainResult.failure(&"malformed_utf8", "invalid UTF-8 continuation byte", "", index + continuation_index, index + continuation_index + 1, &"record_not_allocated")
		codepoint = (codepoint << 6) | (next & 0x3f)
	return DomainResult.success(codepoint)

static func _encode_value(value: Variant) -> DomainResult:
	if IR.is_scalar_carrier(value):
		return _encode_string_value(value)
	if IR.is_object_carrier(value):
		return _encode_object_carrier(value)
	return _encode_typed_value(value)

static func _encode_typed_value(value: Variant) -> DomainResult:
	match typeof(value):
		TYPE_NIL:
			return DomainResult.success("null")
		TYPE_BOOL:
			return DomainResult.success("true" if value else "false")
		TYPE_INT:
			return _encode_integer(value)
		TYPE_FLOAT:
			return _encode_float(value)
		TYPE_STRING:
			return _encode_string_value(value)
		TYPE_STRING_NAME:
			return _encode_string_value(value)
		TYPE_ARRAY:
			return _encode_array(value)
		TYPE_DICTIONARY:
			return _encode_dictionary(value)
		_:
			return DomainResult.failure(&"unsupported_value", "value type is outside the canonical slice")

static func _encode_integer(value: int) -> DomainResult:
	if value >= MIN_EXACT_BINARY64_INTEGER and value <= MAX_EXACT_BINARY64_INTEGER:
		return DomainResult.success(str(value))
	return _encode_float(float(value))

static func _encode_float(value: float) -> DomainResult:
	if is_nan(value) or is_inf(value):
		return DomainResult.failure(&"invalid_number", "non-finite numbers are not canonical JSON")
	var encoded := JCS.encode(value)
	if encoded.is_empty():
		return DomainResult.failure(&"invalid_number", "number cannot be represented as finite binary64")
	return DomainResult.success(encoded)

static func _encode_array(value: Array) -> DomainResult:
	var array_parts: Array[String] = []
	for item: Variant in value:
		var item_result := _encode_value(item)
		if not item_result.is_success():
			return item_result
		array_parts.append(String(item_result.value()))
	return DomainResult.success("[" + ",".join(array_parts) + "]")

static func _encode_dictionary(value: Dictionary) -> DomainResult:
	var normalized := _normalize_dictionary(value)
	if not normalized.is_success():
		return normalized
	var normalized_value: Dictionary = normalized.value()
	var keys: Array[String] = normalized_value["keys"]
	var values: Dictionary = normalized_value["values"]
	keys.sort_custom(_sort_utf8)
	var object_parts: Array[String] = []
	for key: String in keys:
		var member_result := _encode_value(values[key])
		if not member_result.is_success():
			return member_result
		var encoded_key := _encode_string(key)
		if not encoded_key.is_success():
			return encoded_key
		object_parts.append(String(encoded_key.value()) + ":" + String(member_result.value()))
	return DomainResult.success("{" + ",".join(object_parts) + "}")

static func _encode_object_carrier(value: Dictionary) -> DomainResult:
	var valid := IR.validate_object_carrier(value)
	if not valid.is_success():
		return valid
	var entries: Array = []
	var seen: Dictionary = {}
	for member: Dictionary in value[IR.IR_OBJECT_MEMBERS_KEY]:
		var key_result := _normalize_string_value(member["key"])
		if not key_result.is_success():
			return key_result
		var key: Variant = key_result.value()
		var signature := IR.scalar_signature(key)
		if seen.has(signature):
			return DomainResult.failure(&"normalized_key_collision", "object keys collide after Unicode NFC normalization", "$." + IR.path_component(key))
		seen[signature] = true
		var encoded_value := _encode_value(member["value"])
		if not encoded_value.is_success():
			return encoded_value
		entries.append({"key": key, "encoded": String(encoded_value.value())})
	entries.sort_custom(_sort_encoded_member_utf8)
	var object_parts: Array[String] = []
	for entry: Dictionary in entries:
		var encoded_key := _encode_string_value(entry["key"])
		if not encoded_key.is_success():
			return encoded_key
		object_parts.append(String(encoded_key.value()) + ":" + String(entry["encoded"]))
	return DomainResult.success("{" + ",".join(object_parts) + "}")

static func _sort_encoded_member_utf8(left: Dictionary, right: Dictionary) -> bool:
	return _sort_scalar_values(left["key"], right["key"])

static func _sort_scalar_values(left: Variant, right: Variant) -> bool:
	var left_result := IR.scalar_values(left)
	var right_result := IR.scalar_values(right)
	if not left_result.is_success() or not right_result.is_success():
		return false
	var left_bytes := _scalar_utf8_bytes(PackedInt32Array(left_result.value()))
	var right_bytes := _scalar_utf8_bytes(PackedInt32Array(right_result.value()))
	var shared_length: int = mini(left_bytes.size(), right_bytes.size())
	for index: int in range(shared_length):
		if left_bytes[index] != right_bytes[index]:
			return left_bytes[index] < right_bytes[index]
	return left_bytes.size() < right_bytes.size()


static func _normalize_dictionary(value: Dictionary) -> DomainResult:
	var keys: Array[String] = []
	var values: Dictionary = {}
	for raw_key: Variant in value.keys():
		if typeof(raw_key) != TYPE_STRING and typeof(raw_key) != TYPE_STRING_NAME:
			return DomainResult.failure(&"invalid_field_name", "object keys must be strings")
		var normalized_key_result: DomainResult = NFC.normalize_result(String(raw_key))
		if not normalized_key_result.is_success():
			return normalized_key_result
		var string_key := String(normalized_key_result.value())
		if values.has(string_key):
			return DomainResult.failure(&"normalized_key_collision", "object keys collide after Unicode NFC normalization", "$." + string_key)
		keys.append(string_key)
		values[string_key] = value[raw_key]
	return DomainResult.success({"keys": keys, "values": values})

static func _sort_utf8(left: String, right: String) -> bool:
	var left_bytes := left.to_utf8_buffer()
	var right_bytes := right.to_utf8_buffer()
	var shared_length: int = mini(left_bytes.size(), right_bytes.size())
	for index: int in range(shared_length):
		if left_bytes[index] != right_bytes[index]:
			return left_bytes[index] < right_bytes[index]
	return left_bytes.size() < right_bytes.size()

static func _encode_string(value: String) -> DomainResult:
	return _encode_string_value(value)

static func _encode_string_value(value: Variant) -> DomainResult:
	var normalized_result := _normalize_string_value(value)
	if not normalized_result.is_success():
		return normalized_result
	var scalar_result := IR.scalar_values(normalized_result.value())
	if not scalar_result.is_success():
		return scalar_result
	return _encode_scalars(PackedInt32Array(scalar_result.value()))

static func _encode_scalars(scalars: PackedInt32Array) -> DomainResult:
	var parts := PackedStringArray()
	parts.append("\"")
	for scalar: int in scalars:
		parts.append(_encode_scalar(scalar))
	parts.append("\"")
	return DomainResult.success("".join(parts))

static func _encode_scalar(scalar: int) -> String:
	var escaped := _short_escape_for_scalar(scalar)
	if not escaped.is_empty():
		return escaped
	if scalar < 0x20:
		return "\\" + ("u%04x" % scalar)
	return String.chr(scalar)

static func _short_escape_for_scalar(scalar: int) -> String:
	match scalar:
		0:
			return "\\u0000"
		0x08:
			return "\\b"
		0x09:
			return "\\t"
		0x0a:
			return "\\n"
		0x0c:
			return "\\f"
		0x0d:
			return "\\r"
		0x22:
			return "\\\""
		0x5c:
			return "\\\\"
		_:
			return ""

static func _normalize_string_value(value: Variant) -> DomainResult:
	var scalar_result := IR.scalar_values(value)
	if not scalar_result.is_success():
		return scalar_result
	var normalized_result: DomainResult = NFC.normalize_scalars_result(PackedInt32Array(scalar_result.value()))
	if not normalized_result.is_success():
		return normalized_result
	var normalized_scalars := PackedInt32Array(scalar_result.value())
	var normalized_value: Variant = normalized_result.value()
	if typeof(normalized_value) == TYPE_PACKED_INT32_ARRAY:
		normalized_scalars = PackedInt32Array(normalized_value)
	else:
		var normalized_scalar_result := IR.scalar_values(normalized_value)
		if not normalized_scalar_result.is_success():
			return normalized_scalar_result
		normalized_scalars = PackedInt32Array(normalized_scalar_result.value())
	return IR.from_scalars(normalized_scalars)

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

## Returns true only for the codec's private lexical-number carrier.
## Integer sentinel keys prevent a legal JSON object from being mistaken for a
## parser token and keep open-object IR pure data.
## Example: `CanonicalCodec.is_raw_number_token(candidate)`.
static func is_raw_number_token(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var token: Dictionary = value
	return token.size() == 2 and token.get(RAW_NUMBER_TAG_KEY, null) == RAW_NUMBER_TAG and typeof(token.get(RAW_NUMBER_TEXT_KEY, null)) == TYPE_STRING

## Returns the text of a codec-owned lexical-number token.
## Example: `var token_text := CanonicalCodec.raw_number_token_text(candidate)`.
static func raw_number_token_text(value: Variant) -> String:
	if not is_raw_number_token(value):
		return ""
	return String(value[RAW_NUMBER_TEXT_KEY])

## Creates the private lexical-number carrier used between parsing and shape validation.
## Example: `CanonicalCodec.raw_number_token("1e+2")`.
static func raw_number_token(token_text: String) -> Dictionary:
	return {RAW_NUMBER_TAG_KEY: RAW_NUMBER_TAG, RAW_NUMBER_TEXT_KEY: token_text}

class _ByteParser extends RefCounted:
	var _bytes: PackedByteArray
	var _limits: Dictionary
	var _index: int = 0
	var _token_count: int = 0
	var _container_entries: int = 0
	var _decoded_scalar_bytes: int = 0

	func _init(bytes: PackedByteArray, limits: Dictionary) -> void:
		_bytes = PackedByteArray(bytes)
		_limits = limits.duplicate(true)

	func parse_document() -> DomainResult:
		_skip_whitespace()
		if _index >= _bytes.size():
			return _failure(&"malformed_json", "JSON document is empty")
		var value := _parse_value(0, "$")
		if not value.is_success():
			return value
		_skip_whitespace()
		if _index != _bytes.size():
			return _failure(&"malformed_json", "trailing bytes follow the JSON value")
		return value

	func _parse_value(depth: int, path: String) -> DomainResult:
		_token_count += 1
		if _token_count > _limit(&"maximum_total_tokens"):
			return _failure(&"token_limit", "maximum token count exceeded", path)
		_skip_whitespace()
		if _index >= _bytes.size():
			return _failure(&"malformed_json", "value is truncated", path)
		return _parse_value_marker(depth, path, _bytes[_index])

	func _parse_value_marker(depth: int, path: String, marker: int) -> DomainResult:
		if marker == 0x2d or (marker >= 0x30 and marker <= 0x39):
			return _parse_number(path)
		match marker:
			0x7b:
				return _parse_object(depth, path)
			0x5b:
				return _parse_array(depth, path)
			0x22:
				return _parse_string(path)
			0x74:
				return _parse_literal("true", true, path)
			0x66:
				return _parse_literal("false", false, path)
			0x6e:
				return _parse_literal("null", null, path)
			_:
				return _failure(&"malformed_json", "unexpected JSON value byte", path)

	func _parse_object(depth: int, path: String) -> DomainResult:
		if depth + 1 > _limit(&"maximum_nesting_depth"):
			return _failure(&"nesting_limit", "maximum nesting depth exceeded", path)
		_index += 1
		_skip_whitespace()
		var members: Array = []
		var seen: Dictionary = {}
		if _consume(0x7d):
			return DomainResult.success({})
		while true:
			var member_result := _parse_object_member(depth, path, members, seen)
			if not member_result.is_success():
				return member_result
			_skip_whitespace()
			if _consume(0x7d):
				return DomainResult.success(IR.materialize_object(members))
			if not _consume(0x2c):
				return _failure(&"malformed_json", "object member separator is missing", path)
		return _failure(&"malformed_json", "object parser terminated unexpectedly", path)

	func _parse_object_member(depth: int, path: String, members: Array, seen: Dictionary) -> DomainResult:
		_container_entries += 1
		if members.size() + 1 > _limit(&"maximum_object_members_per_object"):
			return _failure(&"object_limit", "maximum object members exceeded", path)
		if _container_entries > _limit(&"maximum_total_container_entries"):
			return _failure(&"container_entry_limit", "maximum container entries exceeded", path)
		_skip_whitespace()
		if _index >= _bytes.size() or _bytes[_index] != 0x22:
			return _failure(&"malformed_json", "object member name must be a string", path)
		var key_result := _parse_string(path)
		if not key_result.is_success():
			return key_result
		var key: Variant = key_result.value()
		var key_signature := IR.scalar_signature(key)
		var key_path := path + "." + IR.path_component(key)
		if seen.has(key_signature):
			return _failure(&"duplicate_member", "object contains a duplicate member", key_path)
		_skip_whitespace()
		if not _consume(0x3a):
			return _failure(&"malformed_json", "object member is missing a colon", key_path)
		var child := _parse_value(depth + 1, key_path)
		if not child.is_success():
			return child
		seen[key_signature] = true
		members.append({"key": key, "value": child.value()})
		return DomainResult.success(true)

	func _parse_array(depth: int, path: String) -> DomainResult:
		if depth + 1 > _limit(&"maximum_nesting_depth"):
			return _failure(&"nesting_limit", "maximum nesting depth exceeded", path)
		_index += 1
		_skip_whitespace()
		var array: Array = []
		if _consume(0x5d):
			return DomainResult.success(array)
		var item_count := 0
		while true:
			item_count += 1
			_container_entries += 1
			if item_count > _limit(&"maximum_array_elements_per_array"):
				return _failure(&"array_limit", "maximum array elements exceeded", path)
			if _container_entries > _limit(&"maximum_total_container_entries"):
				return _failure(&"container_entry_limit", "maximum container entries exceeded", path)
			var child_path := "%s[%d]" % [path, item_count - 1]
			var child := _parse_value(depth + 1, child_path)
			if not child.is_success():
				return child
			array.append(child.value())
			_skip_whitespace()
			if _consume(0x5d):
				return DomainResult.success(array)
			if not _consume(0x2c):
				return _failure(&"malformed_json", "array item separator is missing", path)
			_skip_whitespace()
		return _failure(&"malformed_json", "array parser terminated unexpectedly", path)

	func _parse_literal(expected: String, value: Variant, path: String) -> DomainResult:
		var expected_bytes := expected.to_utf8_buffer()
		var end := _index + expected_bytes.size()
		if end > _bytes.size():
			return _failure(&"malformed_json", "literal is truncated", path)
		var actual := _bytes.slice(_index, end).get_string_from_utf8()
		if actual != expected:
			return _failure(&"malformed_json", "invalid JSON literal", path)
		_index = end
		_decoded_scalar_bytes += expected_bytes.size()
		if _decoded_scalar_bytes > _limit(&"maximum_total_decoded_scalar_bytes"):
			return _failure(&"decoded_scalar_limit", "decoded scalar bytes exceeded", path)
		return DomainResult.success(value)

	func _parse_string(path: String) -> DomainResult:
		var start := _index
		_index += 1
		var scalars := PackedInt32Array()
		while _index < _bytes.size():
			if _index - start > _limit(&"maximum_raw_string_token_bytes"):
				return _failure(&"raw_string_limit", "raw string token is too large", path)
			var byte: int = _bytes[_index]
			if byte == 0x22:
				return _finish_string(start, path, scalars)
			if byte < 0x20:
				return _failure(&"malformed_json", "control byte is not legal in a JSON string", path)
			if byte != 0x5c:
				var scalar := _read_utf8_scalar()
				if scalar < 0:
					return _failure(&"malformed_utf8", "invalid UTF-8 scalar in JSON string", path)
				scalars.append(scalar)
				continue
			var escape_result := _parse_string_escape(path, scalars)
			if not escape_result.is_success():
				return escape_result
		return _failure(&"malformed_json", "string is unterminated", path)

	func _finish_string(start: int, path: String, scalars: PackedInt32Array) -> DomainResult:
		_index += 1
		if _index - start > _limit(&"maximum_raw_string_token_bytes"):
			return _failure(&"raw_string_limit", "raw string token is too large", path)
		_decoded_scalar_bytes += _scalar_byte_count(scalars)
		if _decoded_scalar_bytes > _limit(&"maximum_total_decoded_scalar_bytes"):
			return _failure(&"decoded_scalar_limit", "decoded scalar bytes exceeded", path)
		return IR.from_scalars(scalars)

	func _parse_string_escape(path: String, scalars: PackedInt32Array) -> DomainResult:
		_index += 1
		if _index >= _bytes.size():
			return _failure(&"malformed_json", "string escape is truncated", path)
		var escaped: int = _bytes[_index]
		_index += 1
		if escaped == 0x75:
			var codepoint_result := _parse_unicode_escape(path)
			if not codepoint_result.is_success():
				return codepoint_result
			scalars.append(int(codepoint_result.value()))
			return DomainResult.success(true)
		var scalar := _simple_escape_scalar(escaped)
		if scalar < 0:
			return _failure(&"malformed_json", "unknown JSON string escape", path)
		scalars.append(scalar)
		return DomainResult.success(true)

	func _simple_escape_scalar(escaped: int) -> int:
		match escaped:
			0x22, 0x5c, 0x2f:
				return escaped
			0x62:
				return 0x08
			0x66:
				return 0x0c
			0x6e:
				return 0x0a
			0x72:
				return 0x0d
			0x74:
				return 0x09
			_:
				return -1

	func _read_utf8_scalar() -> int:
		if _index >= _bytes.size():
			return -1
		var first: int = _bytes[_index]
		if first <= 0x7f:
			_index += 1
			return first
		var width := 0
		if first >= 0xc2 and first <= 0xdf:
			width = 2
		elif first >= 0xe0 and first <= 0xef:
			width = 3
		elif first >= 0xf0 and first <= 0xf4:
			width = 4
		else:
			return -1
		if _index + width > _bytes.size():
			return -1
		var scalar := first & ((1 << (8 - width - 1)) - 1)
		for continuation_index: int in range(1, width):
			var next: int = _bytes[_index + continuation_index]
			if next < 0x80 or next > 0xbf:
				return -1
			scalar = (scalar << 6) | (next & 0x3f)
		_index += width
		return scalar

	func _scalar_byte_count(scalars: PackedInt32Array) -> int:
		var count := 0
		for scalar: int in scalars:
			if scalar <= 0x7f:
				count += 1
			elif scalar <= 0x7ff:
				count += 2
			elif scalar <= 0xffff:
				count += 3
			else:
				count += 4
		return count

	func _parse_unicode_escape(path: String, allow_low_surrogate: bool = false) -> DomainResult:
		if _index + 4 > _bytes.size():
			return _failure(&"malformed_json", "unicode escape is truncated", path)
		var codepoint := 0
		for _digit: int in range(4):
			var value := _hex_value(_bytes[_index])
			if value < 0:
				return _failure(&"malformed_json", "unicode escape contains a non-hex digit", path)
			codepoint = (codepoint << 4) | value
			_index += 1
		if codepoint >= 0xd800 and codepoint <= 0xdbff:
			if _index + 6 > _bytes.size() or _bytes[_index] != 0x5c or _bytes[_index + 1] != 0x75:
				return _failure(&"malformed_json", "high surrogate lacks a low surrogate", path)
			_index += 2
			var low_result := _parse_unicode_escape(path, true)
			if not low_result.is_success():
				return low_result
			var low := int(low_result.value())
			if low < 0xdc00 or low > 0xdfff:
				return _failure(&"malformed_json", "surrogate pair is invalid", path)
			return DomainResult.success(0x10000 + ((codepoint - 0xd800) << 10) + (low - 0xdc00))
		if codepoint >= 0xdc00 and codepoint <= 0xdfff and not allow_low_surrogate:
			return _failure(&"malformed_json", "low surrogate has no high surrogate", path)
		return DomainResult.success(codepoint)

	func _parse_number(path: String) -> DomainResult:
		var start := _index
		var integer_result := _parse_number_integer(path)
		if not integer_result.is_success():
			return integer_result
		var fraction_result := _parse_number_fraction(path)
		if not fraction_result.is_success():
			return fraction_result
		var exponent_result := _parse_number_exponent(path)
		if not exponent_result.is_success():
			return exponent_result
		var token_bytes := _bytes.slice(start, _index)
		if token_bytes.size() > _limit(&"maximum_numeric_token_bytes"):
			return _failure(&"numeric_token_limit", "numeric token is too large", path)
		_decoded_scalar_bytes += token_bytes.size()
		if _decoded_scalar_bytes > _limit(&"maximum_total_decoded_scalar_bytes"):
			return _failure(&"decoded_scalar_limit", "decoded scalar bytes exceeded", path)
		var token := token_bytes.get_string_from_utf8()
		return DomainResult.success(CanonicalCodec.raw_number_token(token))

	func _parse_number_integer(path: String) -> DomainResult:
		if _bytes[_index] == 0x2d:
			_index += 1
			if _index >= _bytes.size():
				return _failure(&"malformed_json", "number is missing digits", path)
		if _bytes[_index] == 0x30:
			_index += 1
			if _index < _bytes.size() and _bytes[_index] >= 0x30 and _bytes[_index] <= 0x39:
				return _failure(&"raw_number", "leading zero is not a legal JSON number", path)
		elif _bytes[_index] >= 0x31 and _bytes[_index] <= 0x39:
			while _index < _bytes.size() and _bytes[_index] >= 0x30 and _bytes[_index] <= 0x39:
				_index += 1
		else:
			return _failure(&"malformed_json", "number integer part is missing", path)
		return DomainResult.success(true)

	func _parse_number_fraction(path: String) -> DomainResult:
		if _index >= _bytes.size() or _bytes[_index] != 0x2e:
			return DomainResult.success(true)
		_index += 1
		var fraction_start := _index
		while _index < _bytes.size() and _bytes[_index] >= 0x30 and _bytes[_index] <= 0x39:
			_index += 1
		if fraction_start == _index:
			return _failure(&"raw_number", "fraction is missing digits", path)
		return DomainResult.success(true)

	func _parse_number_exponent(path: String) -> DomainResult:
		if _index >= _bytes.size() or (_bytes[_index] != 0x65 and _bytes[_index] != 0x45):
			return DomainResult.success(true)
		_index += 1
		if _index < _bytes.size() and (_bytes[_index] == 0x2b or _bytes[_index] == 0x2d):
			_index += 1
		var exponent_start := _index
		while _index < _bytes.size() and _bytes[_index] >= 0x30 and _bytes[_index] <= 0x39:
			_index += 1
		if exponent_start == _index:
			return _failure(&"raw_number", "exponent is missing digits", path)
		return DomainResult.success(true)

	func _skip_whitespace() -> void:
		while _index < _bytes.size():
			var byte: int = _bytes[_index]
			if byte != 0x20 and byte != 0x09 and byte != 0x0a and byte != 0x0d:
				break
			_index += 1

	func _consume(expected: int) -> bool:
		if _index < _bytes.size() and _bytes[_index] == expected:
			_index += 1
			return true
		return false

	func _limit(name: StringName) -> int:
		return int(_limits.get(name, ContractShapeProfile.DEFAULT_LIMITS.get(name, 0)))

	func _failure(code: StringName, message: String, path: String = "") -> DomainResult:
		return DomainResult.failure(code, message, path, _index, _index, &"record_not_allocated")

	static func _hex_value(byte: int) -> int:
		if byte >= 0x30 and byte <= 0x39:
			return byte - 0x30
		if byte >= 0x41 and byte <= 0x46:
			return byte - 0x41 + 10
		if byte >= 0x61 and byte <= 0x66:
			return byte - 0x61 + 10
		return -1
