class_name RuntimeMutationCommand
extends RefCounted

const CANONICAL_CODEC = preload("res://src/foundation/canonical_codec.gd")
const OCCUPANCY_STATE = preload("res://src/core/gvet/runtime_occupancy_state.gd")

## Write-once closed command for the serialized owner lane.  The candidate
## vector is preserved exactly; legality is decided by the owner.

var _sealed: bool = false:
	set(value):
		if _sealed:
			return
		_sealed = value
var _command_id: String = "":
	set(value):
		if _sealed:
			return
		_command_id = value
var _expected_generation: int = -1:
	set(value):
		if _sealed:
			return
		_expected_generation = value
var _idempotency_key: String = "":
	set(value):
		if _sealed:
			return
		_idempotency_key = value
var _target_current: bool = false:
	set(value):
		if _sealed:
			return
		_target_current = value
var _target_pending: bool = false:
	set(value):
		if _sealed:
			return
		_target_pending = value
var _target_completed: bool = false:
	set(value):
		if _sealed:
			return
		_target_completed = value
var _target_tombstone: bool = false:
	set(value):
		if _sealed:
			return
		_target_tombstone = value
var _fingerprint: String = "":
	set(value):
		if _sealed:
			return
		_fingerprint = value
var _valid: bool = false:
	set(value):
		if _sealed:
			return
		_valid = value


## Creates a command with a Foundation canonical SHA-256 fingerprint.
## Example: `RuntimeMutationCommand.create("cmd", 0, "retry", vector)`.
static func create(
	command_id: String,
	expected_generation: int,
	idempotency_key: String,
	target_vector: PackedInt32Array
) -> RuntimeMutationCommand:
	var command: RuntimeMutationCommand = new(command_id, expected_generation, idempotency_key, target_vector)
	return command if command.is_valid() else null


## Alias emphasizing the full occupancy candidate.
static func for_occupancy(
	command_id: String,
	expected_generation: int,
	idempotency_key: String,
	target_vector: PackedInt32Array
) -> RuntimeMutationCommand:
	return create(command_id, expected_generation, idempotency_key, target_vector)


## Returns the caller-supplied command correlation ID.
func command_id() -> String:
	return _command_id


## Returns the expected owner generation.
func expected_generation() -> int:
	return _expected_generation


## Alias for the expected generation.
func generation() -> int:
	return _expected_generation


## Returns the fixed key used for exact retry matching.
func idempotency_key() -> String:
	return _idempotency_key


## Returns an exact defensive candidate vector copy.
func target_vector() -> PackedInt32Array:
	return PackedInt32Array([
		int(_target_current),
		int(_target_pending),
		int(_target_completed),
		int(_target_tombstone),
	])


## Alias for occupancy terminology.
func occupancy_vector() -> PackedInt32Array:
	return target_vector()


## Returns the Foundation SHA-256 identity fingerprint.
func fingerprint() -> String:
	return _fingerprint


## Re-encodes the exact closed command projection into defensive bytes.
func canonical_bytes() -> PackedByteArray:
	var encoded: DomainResult = CANONICAL_CODEC.encode_with_hash(_canonical_projection())
	if not encoded.is_success():
		return PackedByteArray()
	var packet: Dictionary = encoded.value()
	return PackedByteArray(packet["bytes"])


## Returns whether all command fields and the binary vector shape are valid.
func is_valid() -> bool:
	return _valid


## Returns a detached command with the same canonical fingerprint.
func duplicate_command() -> RuntimeMutationCommand:
	return create(_command_id, _expected_generation, _idempotency_key, target_vector()) if _valid else null


func _init(
	command_id: String = "",
	expected_generation: int = -1,
	idempotency_key: String = "",
	target_vector: PackedInt32Array = PackedInt32Array()
) -> void:
	if command_id.is_empty() or expected_generation < 0 or idempotency_key.is_empty() or not _is_binary_vector(target_vector):
		_sealed = true
		return
	_command_id = command_id
	_expected_generation = expected_generation
	_idempotency_key = idempotency_key
	_target_current = target_vector[0] == 1
	_target_pending = target_vector[1] == 1
	_target_completed = target_vector[2] == 1
	_target_tombstone = target_vector[3] == 1
	var encoded: DomainResult = CANONICAL_CODEC.encode_with_hash(_canonical_projection())
	if encoded.is_success():
		var packet: Dictionary = encoded.value()
		_fingerprint = String(packet["sha256"])
		_valid = not _fingerprint.is_empty()
	_sealed = true


func _canonical_projection() -> Dictionary:
	var target: Array[int] = [
		int(_target_current),
		int(_target_pending),
		int(_target_completed),
		int(_target_tombstone),
	]
	return {
		"codec": "gvet-runtime-mutation-command-v1",
		"command_id": _command_id,
		"expected_generation": _expected_generation,
		"idempotency_key": _idempotency_key,
		"target_vector": target,
	}


static func _is_binary_vector(vector: PackedInt32Array) -> bool:
	if vector.size() != OCCUPANCY_STATE.SLOT_COUNT:
		return false
	for value: int in vector:
		if value != 0 and value != 1:
			return false
	return true
