class_name CourseworkWindowsGenerationSafeSavePort
extends "res://src/core/save_recovery/coursework_save_port.gd"

## Windows filesystem adapter for one atomically replaced save slot container.

const CanonicalCodec = preload("res://src/foundation/canonical_codec.gd")

const SLOT_SCHEMA: String = "coursework_save_slot_v1"
const TEMPORARY_WRITE_SEAM: StringName = &"temporary_write"
const FLUSH_CLOSE_SEAM: StringName = &"flush_close"
const REPLACEMENT_SEAM: StringName = &"replacement"
const SLOT_IDS: Array[StringName] = [&"manual.1", &"manual.2", &"manual.3", &"autosave.1"]
const _CANDIDATE_ROLES: Array[StringName] = [&"current", &"previous"]

var _storage_root: String
var _injected_failure_seam: StringName = &""
var _last_operation_trace: Array[StringName] = []

## Creates a Windows SavePort rooted in one caller-owned directory.
## Example: `var port: CourseworkWindowsGenerationSafeSavePort = CourseworkWindowsGenerationSafeSavePort.new(root_path)`.
func _init(storage_root: String) -> void:
	_storage_root = storage_root.path_join("saveport_slots")

## Publishes a validated checkpoint with its opaque generation identity.
## Example: `port.save_checkpoint(&"manual.1", "generation-opaque", checkpoint)`.
func save_checkpoint(slot_id: StringName, generation_id: String, checkpoint: StableCheckpoint) -> DomainResult:
	_last_operation_trace.clear()
	if not _is_valid_slot_id(slot_id):
		return DomainResult.failure(&"invalid_slot", "slot ID is outside the fixed Save roster")
	if generation_id.is_empty():
		return DomainResult.failure(&"candidate_invalid", "generation_id must be a non-empty opaque identifier")
	if checkpoint == null or not checkpoint.has_accepted_checkpoint():
		return DomainResult.failure(&"candidate_invalid", "SavePort requires an accepted StableProgressCheckpoint")
	var directory_result: DomainResult = _ensure_storage_root()
	if not directory_result.is_success():
		return directory_result
	var current_raw: PackedByteArray = checkpoint.accepted_raw_bytes()
	if current_raw.is_empty():
		return DomainResult.failure(&"candidate_invalid", "accepted StableProgressCheckpoint has no canonical source bytes")
	var existing_result: DomainResult = _read_slot(slot_id)
	if not existing_result.is_success():
		return existing_result
	var existing: Dictionary[String, Variant] = _dictionary(existing_result.value())
	var prior_current: Variant = existing.get("current", null)
	var prior_previous: Variant = existing.get("previous", null)
	if _matches_generation(prior_current, current_raw):
		return DomainResult.success(&"save_unchanged")
	var retained_previous: Variant = prior_current if _has_complete_generation(prior_current) else prior_previous
	var current_generation: Dictionary[String, Variant] = {"generation_id": generation_id, "raw_bytes": PackedByteArray(current_raw)}
	var slot_data: Dictionary[String, Variant] = {"schema": SLOT_SCHEMA, "current": _stored_generation_record(current_generation), "previous": _stored_generation_record(_dictionary(retained_previous)) if _has_complete_generation(retained_previous) else null}
	var encoded_result: DomainResult = CanonicalCodec.encode(slot_data)
	if not encoded_result.is_success():
		return DomainResult.failure(&"slot_encoding_failed", "could not encode the canonical slot container")
	var encoded: PackedByteArray = PackedByteArray(encoded_result.value())
	var temporary_path: String = _temporary_path(slot_id)
	var target_path: String = _slot_path(slot_id)
	if FileAccess.file_exists(temporary_path):
		var remove_error: Error = DirAccess.remove_absolute(temporary_path)
		if remove_error != OK:
			return DomainResult.failure(&"commit_failed", "temporary cleanup failed before commit", temporary_path)
	_last_operation_trace.append(TEMPORARY_WRITE_SEAM)
	if _injected_failure_seam == TEMPORARY_WRITE_SEAM:
		return DomainResult.failure(&"commit_failed", "temporary_write seam interrupted before commit", temporary_path)
	var temporary_file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if temporary_file == null:
		return DomainResult.failure(&"commit_failed", "temporary_write seam could not open the temporary container", temporary_path)
	var write_succeeded: bool = temporary_file.store_buffer(encoded)
	if not write_succeeded or temporary_file.get_error() != OK:
		temporary_file.close()
		return DomainResult.failure(&"commit_failed", "temporary_write seam could not write the complete container", temporary_path)
	if _injected_failure_seam == FLUSH_CLOSE_SEAM:
		_last_operation_trace.append(FLUSH_CLOSE_SEAM)
		temporary_file.close()
		return DomainResult.failure(&"commit_failed", "flush_close seam interrupted before commit", temporary_path)
	temporary_file.flush()
	if temporary_file.get_error() != OK:
		temporary_file.close()
		return DomainResult.failure(&"commit_failed", "flush_close seam could not flush the temporary container", temporary_path)
	_last_operation_trace.append(&"flush")
	temporary_file.close()
	_last_operation_trace.append(&"close")
	if _injected_failure_seam == REPLACEMENT_SEAM:
		_last_operation_trace.append(REPLACEMENT_SEAM)
		return DomainResult.failure(&"commit_failed", "replacement seam interrupted before commit", temporary_path)
	var replace_error: Error = DirAccess.rename_absolute(temporary_path, target_path)
	if replace_error != OK:
		return DomainResult.failure(&"commit_failed", "replacement seam could not atomically replace the slot container", target_path)
	_last_operation_trace.append(REPLACEMENT_SEAM)
	return DomainResult.success(&"save_committed")

## Observes detached complete role records without selecting owner restoration.
## Example: `var observed: DomainResult = port.observe_slot(&"manual.1")`.
func observe_slot(slot_id: StringName) -> DomainResult:
	_last_operation_trace.clear()
	if not _is_valid_slot_id(slot_id):
		return DomainResult.failure(&"invalid_slot", "slot ID is outside the fixed Save roster")
	var observed_result: DomainResult = _read_slot(slot_id)
	if not observed_result.is_success():
		return observed_result
	var observed: Dictionary[String, Variant] = _dictionary(observed_result.value())
	if typeof(observed.get("current", null)) == TYPE_DICTIONARY:
		_last_operation_trace.append(&"observe_current")
	if typeof(observed.get("previous", null)) == TYPE_DICTIONARY:
		_last_operation_trace.append(&"observe_previous")
	return DomainResult.success(observed)

## Durably clears one slot by first moving its container out of the observable
## path, then removing that detached container.
## Example: `var deleted: DomainResult = port.delete_slot(&"manual.1")`.
func delete_slot(slot_id: StringName) -> DomainResult:
	_last_operation_trace.clear()
	if not _is_valid_slot_id(slot_id):
		return DomainResult.failure(&"invalid_slot", "slot ID is outside the fixed Save roster")
	var directory_result: DomainResult = _ensure_storage_root()
	if not directory_result.is_success():
		return directory_result
	var target_path: String = _slot_path(slot_id)
	if not FileAccess.file_exists(target_path):
		return DomainResult.success(&"slot_deleted")
	var deleted_path: String = _deleted_path(slot_id)
	if FileAccess.file_exists(deleted_path):
		var stale_remove_error: Error = DirAccess.remove_absolute(deleted_path)
		if stale_remove_error != OK:
			return DomainResult.failure(&"commit_failed", "could not clear the prior detached deletion container", deleted_path)
	var move_error: Error = DirAccess.rename_absolute(target_path, deleted_path)
	if move_error != OK:
		return DomainResult.failure(&"commit_failed", "could not detach the slot container before deletion", target_path)
	_last_operation_trace.append(&"delete_detach")
	var remove_error: Error = DirAccess.remove_absolute(deleted_path)
	if remove_error != OK:
		DirAccess.rename_absolute(deleted_path, target_path)
		return DomainResult.failure(&"commit_failed", "could not remove the detached slot container", deleted_path)
	_last_operation_trace.append(&"delete_remove")
	return DomainResult.success(&"slot_deleted")

## Returns the only legal generation candidate order.
## Example: `for role: StringName in port.candidate_roles(): inspect(role)`.
func candidate_roles() -> Array[StringName]:
	return _CANDIDATE_ROLES.duplicate()

## Returns bounded filesystem ordering evidence for the last operation.
## Example: `assert_eq(port.last_operation_trace(), [&"temporary_write", &"flush", &"close", &"replacement"])`.
func last_operation_trace() -> Array[StringName]:
	return _last_operation_trace.duplicate()

## Selects one bounded deterministic commit-failure seam for an integration vector.
## Example: `port.inject_failure_for_test(CourseworkWindowsGenerationSafeSavePort.REPLACEMENT_SEAM)`.
func inject_failure_for_test(failure_seam: StringName) -> DomainResult:
	if failure_seam != TEMPORARY_WRITE_SEAM and failure_seam != FLUSH_CLOSE_SEAM and failure_seam != REPLACEMENT_SEAM:
		return DomainResult.failure(&"invalid_failure_seam", "failure injection must target temporary_write, flush_close, or replacement")
	_injected_failure_seam = failure_seam
	return DomainResult.success(failure_seam)

## Clears the bounded deterministic failure seam after an integration vector.
## Example: `port.clear_failure_injection()`.
func clear_failure_injection() -> void:
	_injected_failure_seam = &""

func _ensure_storage_root() -> DomainResult:
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(_storage_root)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return DomainResult.failure(&"storage_unavailable", "could not create the SavePort storage root", _storage_root)
	return DomainResult.success(true)

func _read_slot(slot_id: StringName) -> DomainResult:
	var slot_path: String = _slot_path(slot_id)
	if not FileAccess.file_exists(slot_path):
		return DomainResult.success({"current": null, "previous": null})
	var slot_file: FileAccess = FileAccess.open(slot_path, FileAccess.READ)
	if slot_file == null:
		return DomainResult.failure(&"candidate_invalid", "could not read the slot container", slot_path)
	var encoded: PackedByteArray = slot_file.get_buffer(slot_file.get_length())
	slot_file.close()
	var decoded_result: DomainResult = CanonicalCodec.decode_parts(encoded)
	if not decoded_result.is_success():
		return DomainResult.failure(&"candidate_invalid", "slot container is not canonical valid data", slot_path)
	var decoded: Dictionary[String, Variant] = _dictionary(decoded_result.value())
	var value: Variant = decoded.get("value", null)
	if typeof(value) != TYPE_DICTIONARY:
		return DomainResult.failure(&"candidate_invalid", "slot container must be an object", slot_path)
	var container: Dictionary[String, Variant] = _dictionary(value)
	if String(container.get("schema", "")) != SLOT_SCHEMA or not container.has("current") or not container.has("previous"):
		return DomainResult.failure(&"candidate_invalid", "slot container schema or roles are invalid", slot_path)
	var current: Variant = _generation_for_observation(container["current"], slot_path)
	var previous_value: Variant = container["previous"]
	var previous: Variant = null
	if previous_value != null:
		previous = _generation_for_observation(previous_value, slot_path)
	return DomainResult.success({"current": current, "previous": previous})

func _generation_for_observation(value: Variant, slot_path: String) -> Variant:
	var decoded: DomainResult = _decode_generation(value, slot_path)
	if decoded.is_success():
		return decoded.value()
	var record: Dictionary[String, Variant] = _dictionary(value)
	return {"generation_id": String(record.get("generation_id", "")), "raw_bytes": null}

func _decode_generation(value: Variant, slot_path: String) -> DomainResult:
	if typeof(value) != TYPE_DICTIONARY:
		return DomainResult.failure(&"candidate_invalid", "generation record must be complete", slot_path)
	var record: Dictionary[String, Variant] = _dictionary(value)
	if record.size() != 3 or typeof(record.get("generation_id", null)) != TYPE_STRING or typeof(record.get("raw_base64", null)) != TYPE_STRING or typeof(record.get("sha256", null)) != TYPE_STRING:
		return DomainResult.failure(&"candidate_invalid", "generation record fields are invalid", slot_path)
	var generation_id: String = String(record["generation_id"])
	var raw_bytes: PackedByteArray = Marshalls.base64_to_raw(String(record["raw_base64"]))
	if generation_id.is_empty() or raw_bytes.is_empty() or CanonicalCodec.sha256_hex(raw_bytes) != String(record["sha256"]):
		return DomainResult.failure(&"candidate_invalid", "generation identity or digest does not match canonical source bytes", slot_path)
	return DomainResult.success({"generation_id": generation_id, "raw_bytes": PackedByteArray(raw_bytes)})

func _stored_generation_record(generation: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
	var generation_id: String = String(generation.get("generation_id", ""))
	var raw_value: Variant = generation.get("raw_bytes", null)
	var raw_bytes: PackedByteArray = PackedByteArray(raw_value) if raw_value is PackedByteArray else PackedByteArray()
	return {"generation_id": generation_id, "raw_base64": Marshalls.raw_to_base64(raw_bytes), "sha256": CanonicalCodec.sha256_hex(raw_bytes)}

func _matches_generation(value: Variant, raw_bytes: PackedByteArray) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var generation: Dictionary[String, Variant] = _dictionary(value)
	var stored_raw: Variant = generation.get("raw_bytes", null)
	return stored_raw is PackedByteArray and PackedByteArray(stored_raw) == raw_bytes

func _has_complete_generation(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var generation: Dictionary[String, Variant] = _dictionary(value)
	var raw_value: Variant = generation.get("raw_bytes", null)
	return not String(generation.get("generation_id", "")).is_empty() \
		and raw_value is PackedByteArray and not PackedByteArray(raw_value).is_empty()

func _slot_path(slot_id: StringName) -> String:
	return _storage_root.path_join("%s.slot" % String(slot_id))

func _temporary_path(slot_id: StringName) -> String:
	return _storage_root.path_join("%s.slot.pending" % String(slot_id))

func _deleted_path(slot_id: StringName) -> String:
	return _storage_root.path_join("%s.slot.deleted" % String(slot_id))

func _is_valid_slot_id(slot_id: StringName) -> bool:
	return SLOT_IDS.has(slot_id)

func _dictionary(value: Variant) -> Dictionary[String, Variant]:
	var copied: Dictionary[String, Variant] = {}
	if typeof(value) != TYPE_DICTIONARY:
		return copied
	for key: Variant in value.keys():
		if typeof(key) == TYPE_STRING:
			copied[String(key)] = value[key]
	return copied
