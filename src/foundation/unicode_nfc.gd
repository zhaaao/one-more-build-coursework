class_name UnicodeNFC
extends RefCounted

const UnicodeNFCData = preload("res://src/foundation/unicode_nfc_data.gd")

## Pure Unicode 16.0.0 canonical normalization for runtime_json_v1.
##
## The implementation performs recursive canonical decomposition, stable
## canonical-combining-class ordering, canonical composition, and algorithmic
## Hangul handling from the embedded UnicodeNFCData tables. It performs no I/O
## and never consults host locale or host Unicode normalization.

const HANGUL_LBASE: int = 0x1100
const HANGUL_VBASE: int = 0x1161
const HANGUL_TBASE: int = 0x11a7
const HANGUL_SBASE: int = 0xac00
const HANGUL_LCOUNT: int = 19
const HANGUL_VCOUNT: int = 21
const HANGUL_TCOUNT: int = 28
const HANGUL_NCOUNT: int = HANGUL_VCOUNT * HANGUL_TCOUNT
const HANGUL_SCOUNT: int = HANGUL_LCOUNT * HANGUL_NCOUNT

## Returns a normalized scalar string. Invalid scalar input returns an empty
## string; callers validating untrusted JSON should use normalize_result().
## Example: `UnicodeNFC.normalize("e" + "\\u0301") == "é"`.
static func normalize(value: String) -> String:
	var result := normalize_result(value)
	return String(result.value()) if result.is_success() else ""

## Validates scalar input and returns its Unicode-16.0.0 NFC form.
## Example: `var n := UnicodeNFC.normalize_result(source)`.
static func normalize_result(value: String) -> DomainResult:
	var scalar_result := _to_scalars(value)
	if not scalar_result.is_success():
		return scalar_result
	return normalize_scalars_result(PackedInt32Array(scalar_result.value()))

## Normalizes a pure scalar carrier without routing U+0000 through String.
## Example: `var normalized := UnicodeNFC.normalize_scalars_result(scalars)`.
static func normalize_scalars_result(scalars: PackedInt32Array) -> DomainResult:
	if not _tables_have_expected_shape():
		return DomainResult.failure(&"unicode_data_invalid", "embedded Unicode 16.0.0 data failed its fixed shape")
	var decomposed: Array[int] = []
	for scalar: int in scalars:
		if scalar < 0 or scalar > 0x10ffff or (scalar >= 0xd800 and scalar <= 0xdfff):
			return DomainResult.failure(&"invalid_string", "string contains a non-Unicode-scalar value")
		_decompose_scalar(scalar, decomposed)
	var ordered := _canonical_order(decomposed)
	var composed := _canonical_compose(ordered)
	var normalized_scalars := PackedInt32Array()
	for scalar: int in composed:
		normalized_scalars.append(scalar)
	if normalized_scalars.has(0):
		return DomainResult.success(normalized_scalars)
	var characters := PackedStringArray()
	for scalar: int in normalized_scalars:
		var character := String.chr(scalar)
		if character.length() != 1 or character.unicode_at(0) != scalar:
			return DomainResult.success(normalized_scalars)
		characters.append(character)
	var normalized := "".join(characters)
	return DomainResult.success(normalized)

## Returns true only when the embedded table header and deterministic counts
## match Unicode 16.0.0.
## Example: `if not UnicodeNFC.tables_are_valid(): fail_startup()`.
static func tables_are_valid() -> bool:
	if not _tables_have_expected_shape():
		return false
	var decomposition_text: String = "".join(UnicodeNFCData.DECOMPOSITION_DATA)
	var combining_text: String = "".join(UnicodeNFCData.COMBINING_CLASS_DATA)
	var composition_text: String = "".join(UnicodeNFCData.COMPOSITION_DATA)
	var decomposition_source := _parse_decomposition_table(decomposition_text)
	var combining_source := _parse_combining_table(combining_text)
	var composition_source := _parse_composition_table(composition_text)
	return decomposition_source == UnicodeNFCData.DECOMPOSITION_TABLE and combining_source == UnicodeNFCData.COMBINING_CLASS_TABLE and composition_source == UnicodeNFCData.COMPOSITION_TABLE and _table_sha256(decomposition_text, combining_text, composition_text) == UnicodeNFCData.TABLE_SHA256

static func _tables_have_expected_shape() -> bool:
	var decomposition_valid: bool = UnicodeNFCData.DECOMPOSITION_TABLE.size() == UnicodeNFCData.DECOMPOSITION_ENTRY_COUNT
	var combining_valid: bool = UnicodeNFCData.COMBINING_CLASS_TABLE.size() == UnicodeNFCData.COMBINING_CLASS_ENTRY_COUNT
	var composition_valid: bool = UnicodeNFCData.COMPOSITION_TABLE.size() == UnicodeNFCData.COMPOSITION_ENTRY_COUNT
	return UnicodeNFCData.UNICODE_VERSION == "16.0.0" and decomposition_valid and combining_valid and composition_valid

## Performs the cold integrity check against the generated source chunks.
## Example: `assert(UnicodeNFC.raw_table_hash_is_valid())` in a startup test.
static func raw_table_hash_is_valid() -> bool:
	return tables_are_valid()

static func _parse_decomposition_table(text: String) -> Dictionary:
	var table: Dictionary = {}
	for entry: String in text.split(";"):
		var separator := entry.find(":")
		if separator <= 0:
			continue
		var scalar := _parse_hex(entry.substr(0, separator))
		var values := entry.substr(separator + 1).split(",")
		if values.size() == 0 or values.size() > 2:
			return {}
		var first := _parse_hex(values[0])
		var second := _parse_hex(values[1]) if values.size() == 2 else -1
		table[scalar] = Vector2i(first, second)
	return table

static func _parse_combining_table(text: String) -> Dictionary:
	var table: Dictionary = {}
	for entry: String in text.split(";"):
		var separator := entry.find(":")
		if separator <= 0:
			continue
		var scalar := _parse_hex(entry.substr(0, separator))
		table[scalar] = int(entry.substr(separator + 1))
	return table

static func _parse_composition_table(text: String) -> Dictionary:
	var table: Dictionary = {}
	for entry: String in text.split(";"):
		var separator := entry.find(":")
		if separator <= 0:
			continue
		var pair := entry.substr(0, separator).split(",")
		if pair.size() != 2:
			return {}
		var first := _parse_hex(pair[0])
		var second := _parse_hex(pair[1])
		var key: int = (first << 21) | second
		table[key] = _parse_hex(entry.substr(separator + 1))
	return table

static func _to_scalars(value: String) -> DomainResult:
	var scalars: Array[int] = []
	for index: int in range(value.length()):
		var scalar: int = value.unicode_at(index)
		if scalar < 0 or scalar > 0x10ffff or (scalar >= 0xd800 and scalar <= 0xdfff):
			return DomainResult.failure(&"invalid_string", "string contains a non-Unicode-scalar value")
		scalars.append(scalar)
	return DomainResult.success(scalars)

static func _decompose_scalar(scalar: int, output: Array[int]) -> void:
	if scalar >= HANGUL_SBASE and scalar < HANGUL_SBASE + HANGUL_SCOUNT:
		var syllable_index := scalar - HANGUL_SBASE
		output.append(HANGUL_LBASE + syllable_index / HANGUL_NCOUNT)
		output.append(HANGUL_VBASE + (syllable_index % HANGUL_NCOUNT) / HANGUL_TCOUNT)
		var trailing_index := syllable_index % HANGUL_TCOUNT
		if trailing_index != 0:
			output.append(HANGUL_TBASE + trailing_index)
		return
	var decomposition: Vector2i = UnicodeNFCData.DECOMPOSITION_TABLE.get(scalar, Vector2i(-1, -1))
	if decomposition.x < 0:
		output.append(scalar)
		return
	_decompose_scalar(decomposition.x, output)
	if decomposition.y >= 0:
		_decompose_scalar(decomposition.y, output)

static func _canonical_order(input: Array[int]) -> Array[int]:
	var output: Array[int] = []
	var buckets: Dictionary = {}
	var active_classes: Array[int] = []
	for scalar: int in input:
		var combining_class := _combining_class_of(scalar)
		if combining_class == 0:
			_flush_combining_buckets(output, buckets, active_classes)
			buckets = {}
			active_classes = []
			output.append(scalar)
			continue
		if not buckets.has(combining_class):
			buckets[combining_class] = []
			active_classes.append(combining_class)
		var class_bucket: Array = buckets[combining_class]
		class_bucket.append(scalar)
		buckets[combining_class] = class_bucket
	_flush_combining_buckets(output, buckets, active_classes)
	return output

static func _flush_combining_buckets(output: Array[int], buckets: Dictionary, active_classes: Array[int]) -> void:
	if active_classes.is_empty():
		return
	active_classes.sort()
	for combining_class: int in active_classes:
		var class_bucket: Array = buckets[combining_class]
		for scalar: int in class_bucket:
			output.append(scalar)

static func _canonical_compose(input: Array[int]) -> Array[int]:
	var output: Array[int] = []
	var starter_index := -1
	var last_combining_class := 0
	for scalar: int in input:
		var combining_class := _combining_class_of(scalar)
		if combining_class == 0:
			if starter_index >= 0 and last_combining_class == 0:
				var hangul_composed := _compose_pair(output[starter_index], scalar)
				if hangul_composed >= 0:
					output[starter_index] = hangul_composed
					last_combining_class = 0
					continue
			output.append(scalar)
			starter_index = output.size() - 1
			last_combining_class = 0
			continue
		var composed := -1
		if starter_index >= 0 and (last_combining_class == 0 or last_combining_class < combining_class):
			composed = _compose_pair(output[starter_index], scalar)
		if composed >= 0:
			output[starter_index] = composed
			continue
		output.append(scalar)
		last_combining_class = combining_class
	return output

static func _combining_class_of(scalar: int) -> int:
	return int(UnicodeNFCData.COMBINING_CLASS_TABLE.get(scalar, 0))

static func _compose_pair(first: int, second: int) -> int:
	if first >= HANGUL_LBASE and first < HANGUL_LBASE + HANGUL_LCOUNT and second >= HANGUL_VBASE and second < HANGUL_VBASE + HANGUL_VCOUNT:
		return HANGUL_SBASE + ((first - HANGUL_LBASE) * HANGUL_VCOUNT + (second - HANGUL_VBASE)) * HANGUL_TCOUNT
	if first >= HANGUL_SBASE and first < HANGUL_SBASE + HANGUL_SCOUNT and (first - HANGUL_SBASE) % HANGUL_TCOUNT == 0 and second > HANGUL_TBASE and second < HANGUL_TBASE + HANGUL_TCOUNT:
		return first + second - HANGUL_TBASE
	var key: int = (first << 21) | second
	return int(UnicodeNFCData.COMPOSITION_TABLE.get(key, -1))

static func _table_sha256(decomposition_text: String, combining_text: String, composition_text: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update((decomposition_text + combining_text + composition_text).to_utf8_buffer())
	return context.finish().hex_encode()

static func _parse_hex(token: String) -> int:
	var result := 0
	for index: int in range(token.length()):
		var code := token.unicode_at(index)
		var digit := 0
		if code >= 0x30 and code <= 0x39:
			digit = code - 0x30
		elif code >= 0x41 and code <= 0x46:
			digit = code - 0x41 + 10
		elif code >= 0x61 and code <= 0x66:
			digit = code - 0x61 + 10
		else:
			return -1
		result = (result << 4) | digit
	return result
