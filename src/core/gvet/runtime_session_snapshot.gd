class_name RuntimeSessionSnapshot
extends RefCounted

const CANONICAL_CODEC = preload("res://src/foundation/canonical_codec.gd")

## Write-once publication containing only an immutable occupancy record,
## scalar generation/commit values, and scalar correlation IDs.

var _sealed: bool = false:
	set(value):
		if _sealed:
			return
		_sealed = value
var _occupancy: RuntimeOccupancyState:
	set(value):
		if _sealed:
			return
		_occupancy = value
var _generation: int = -1:
	set(value):
		if _sealed:
			return
		_generation = value
var _last_commit_id: String = "":
	set(value):
		if _sealed:
			return
		_last_commit_id = value
var _correlation_count: int = 0:
	set(value):
		if _sealed:
			return
		_correlation_count = value
var _correlation_a: String = "":
	set(value):
		if _sealed:
			return
		_correlation_a = value
var _correlation_b: String = "":
	set(value):
		if _sealed:
			return
		_correlation_b = value
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


## Builds a snapshot and derives its root from the closed scalar projection.
## An arbitrary caller-supplied root is not accepted.
static func create(
	occupancy: RuntimeOccupancyState,
	generation: int,
	last_commit_id: String,
	correlation_ids: PackedStringArray
) -> RuntimeSessionSnapshot:
	var snapshot: RuntimeSessionSnapshot = new(occupancy, generation, last_commit_id, correlation_ids)
	return snapshot if snapshot.is_valid() else null


## Returns a defensive immutable occupancy record copy.
func get_occupancy_state() -> RuntimeOccupancyState:
	return _occupancy.duplicate_state() if _valid else null


## Returns a defensive vector copy in canonical slot order.
func get_occupancy_vector() -> PackedInt32Array:
	return _occupancy.vector() if _valid else PackedInt32Array()


## Alias for vector-oriented callers.
func occupancy_vector() -> PackedInt32Array:
	return get_occupancy_vector()


## Returns the canonical occupancy code for this snapshot.
func occupancy_vector_code() -> String:
	return _occupancy.vector_code() if _valid else ""


## Returns the committed generation.
func generation() -> int:
	return _generation


## Returns the Foundation SHA-256 state root.
func state_root() -> String:
	return _state_root


## Returns the accepted commit correlation ID, or empty for the initial state.
func last_commit_id() -> String:
	return _last_commit_id


## Returns defensive copies of correlation IDs only.
func correlation_ids() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	if _correlation_count > 0:
		result.append(_correlation_a)
	if _correlation_count > 1:
		result.append(_correlation_b)
	return result


## Returns whether this object is a valid published snapshot.
func is_valid() -> bool:
	return _valid


## Re-encodes the same closed scalar projection into defensive canonical bytes.
func canonical_bytes() -> PackedByteArray:
	var encoded: DomainResult = CANONICAL_CODEC.encode_with_hash(_canonical_projection())
	if not encoded.is_success():
		return PackedByteArray()
	var packet: Dictionary = encoded.value()
	return PackedByteArray(packet["bytes"])


## Returns a detached snapshot with no mutable collection aliases.
func duplicate_snapshot() -> RuntimeSessionSnapshot:
	return create(_occupancy, _generation, _last_commit_id, correlation_ids()) if _valid else null


func _init(
	occupancy: RuntimeOccupancyState = null,
	generation: int = -1,
	last_commit_id: String = "",
	correlation_ids: PackedStringArray = PackedStringArray()
) -> void:
	if occupancy == null or not occupancy.is_valid() or generation < 0:
		_sealed = true
		return
	if generation == 0 and (not last_commit_id.is_empty() or not correlation_ids.is_empty()):
		_sealed = true
		return
	if generation > 0 and (last_commit_id.is_empty() or not last_commit_id.begins_with("gvet-commit-") or correlation_ids.size() != 2):
		_sealed = true
		return
	if correlation_ids.size() > 2:
		_sealed = true
		return
	for correlation_id: String in correlation_ids:
		if correlation_id.is_empty():
			_sealed = true
			return
	_occupancy = occupancy.duplicate_state()
	_generation = generation
	_last_commit_id = last_commit_id
	_correlation_count = correlation_ids.size()
	if _correlation_count > 0:
		_correlation_a = correlation_ids[0]
	if _correlation_count > 1:
		_correlation_b = correlation_ids[1]
	var encoded: DomainResult = CANONICAL_CODEC.encode_with_hash(_canonical_projection())
	if encoded.is_success():
		var packet: Dictionary = encoded.value()
		_state_root = String(packet["sha256"])
		_valid = true
	_sealed = true


func _canonical_projection() -> Dictionary:
	var correlations: Array[String] = []
	if _correlation_count > 0:
		correlations.append(_correlation_a)
	if _correlation_count > 1:
		correlations.append(_correlation_b)
	return {
		"codec": "gvet-runtime-session-snapshot-v1",
		"occupancy": _occupancy.vector_code() if _occupancy != null else "",
		"occupancy_root": _occupancy.state_root() if _occupancy != null else "",
		"generation": _generation,
		"last_commit_id": _last_commit_id,
		"correlation_ids": correlations,
	}
