class_name RuntimeOccupancyState
extends RefCounted

const CANONICAL_CODEC = preload("res://src/foundation/canonical_codec.gd")

## Write-once immutable occupancy record in [current, pending, completed,
## tombstone] order. Illegal vectors return null from from_vector().

const SLOT_COUNT: int = 4
const _LEGAL_VECTOR_CODES: String = "0000|0010|0001|0011|1000|1010|1100|1110|1001|1011"

var _sealed: bool = false:
	set(value):
		if _sealed:
			return
		_sealed = value
var _current: bool = false:
	set(value):
		if _sealed:
			return
		_current = value
var _pending: bool = false:
	set(value):
		if _sealed:
			return
		_pending = value
var _completed: bool = false:
	set(value):
		if _sealed:
			return
		_completed = value
var _tombstone: bool = false:
	set(value):
		if _sealed:
			return
		_tombstone = value
var _state_root: String = "":
	set(value):
		if _sealed:
			return
		_state_root = value
var _valid: bool = false:
	set(value):
		if _sealed:
			return
		_valid = value


## Creates a value from a four-element binary vector; no repair or occupant
## removal is performed. Example: `from_vector(PackedInt32Array([1, 1, 0, 0]))`.
static func from_vector(vector: PackedInt32Array) -> RuntimeOccupancyState:
	var state: RuntimeOccupancyState = new(vector)
	return state if state.is_valid() else null


## Creates a value from named slots in canonical order.
static func from_bits(current: bool, pending: bool, completed: bool, tombstone: bool) -> RuntimeOccupancyState:
	return from_vector(PackedInt32Array([
		int(current),
		int(pending),
		int(completed),
		int(tombstone),
	]))


## Returns true only for one of the ten frozen stable vectors.
static func is_legal_vector(vector: PackedInt32Array) -> bool:
	if vector.size() != SLOT_COUNT:
		return false
	for value: int in vector:
		if value != 0 and value != 1:
			return false
	return _LEGAL_VECTOR_CODES.split("|").has(_encode_vector(vector))


## Returns a defensive ordered copy of the ten frozen stable vector codes.
static func legal_vector_codes() -> PackedStringArray:
	return PackedStringArray([
		"0000", "0010", "0001", "0011", "1000", "1010", "1100", "1110", "1001", "1011",
	])


## Returns a defensive vector copy in [current, pending, completed, tombstone]
## order. Example: `state.vector()` is safe for caller mutation.
func vector() -> PackedInt32Array:
	return PackedInt32Array([
		int(_current),
		int(_pending),
		int(_completed),
		int(_tombstone),
	])


## Returns the canonical four-character occupancy code.
func vector_code() -> String:
	return _encode_vector(vector())


## Returns the write-once construction result.
func is_valid() -> bool:
	return _valid


## Returns a detached immutable copy.
func duplicate_state() -> RuntimeOccupancyState:
	return from_vector(vector())


## Compares immutable records by canonical vector.
func equals(other: RuntimeOccupancyState) -> bool:
	return other != null and _valid and other._valid and vector_code() == other.vector_code()


## Returns the Foundation SHA-256 root of the closed scalar projection.
func state_root() -> String:
	return _state_root


## Re-encodes the closed scalar projection and returns defensive canonical bytes.
func canonical_bytes() -> PackedByteArray:
	var encoded: DomainResult = CANONICAL_CODEC.encode_with_hash(_canonical_projection())
	if not encoded.is_success():
		return PackedByteArray()
	var packet: Dictionary = encoded.value()
	return PackedByteArray(packet["bytes"])


func _init(vector: PackedInt32Array = PackedInt32Array()) -> void:
	if is_legal_vector(vector):
		_current = vector[0] == 1
		_pending = vector[1] == 1
		_completed = vector[2] == 1
		_tombstone = vector[3] == 1
		var encoded: DomainResult = CANONICAL_CODEC.encode_with_hash(_canonical_projection())
		if encoded.is_success():
			var packet: Dictionary = encoded.value()
			_state_root = String(packet["sha256"])
			_valid = true
	_sealed = true


func _canonical_projection() -> Dictionary:
	return {
		"codec": "gvet-runtime-occupancy-v1",
		"current": _current,
		"pending": _pending,
		"completed": _completed,
		"tombstone": _tombstone,
	}


static func _encode_vector(vector: PackedInt32Array) -> String:
	if vector.size() != SLOT_COUNT:
		return ""
	return str(vector[0]) + str(vector[1]) + str(vector[2]) + str(vector[3])
