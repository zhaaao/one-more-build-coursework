class_name CourseworkSaveService
extends RefCounted

## Story 004's deterministic Feature facade for save-slot eligibility and
## current/previous generation lifecycle. Candidate admission and persistence
## ports are deliberately outside this service.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CanonicalCodecType = preload("res://src/foundation/canonical_codec.gd")
const StableCheckpointType = preload(
	"res://src/core/save_recovery/coursework_five_section_stable_checkpoint.gd")
const SettingsTutorialType = preload(
	"res://src/core/save_recovery/coursework_settings_tutorial_projection_contracts.gd")
const SavePortType = preload("res://src/core/save_recovery/coursework_save_port.gd")

const MANUAL_SLOT_IDS: Array[String] = ["manual.1", "manual.2", "manual.3"]
const AUTOSAVE_SLOT_ID: String = "autosave.1"
const SLOT_IDS: Array[String] = ["manual.1", "manual.2", "manual.3", "autosave.1"]

var _authoring_gate: DomainResult
var _run_active: bool = false
var _persistence_operation_active: bool = false
# Godot 4.7 does not support nested typed collections. Each value is a typed
# slot record validated at construction and copied through _slot_for().
var _slots: Dictionary[String, Variant] = {}
var _slot_revisions: Dictionary[String, int] = {}
var _candidate_admission: CourseworkCanonicalCandidateAdmission = null
var _save_port: SavePortType = null

## Creates the fixed four-slot roster from one synchronous Authoring gate.
func _init(
		authoring_gate: DomainResult,
		candidate_admission: CourseworkCanonicalCandidateAdmission = null,
		save_port: SavePortType = null
) -> void:
	_authoring_gate = authoring_gate
	_candidate_admission = candidate_admission
	_save_port = save_port
	for slot_id: String in SLOT_IDS:
		var empty_slot: Dictionary[String, Variant] = {"current": null, "previous": null}
		_slots[slot_id] = empty_slot
		_slot_revisions[slot_id] = 0

## Updates the synchronous Authoring gate and persistence-operation projection.
func set_eligibility(authoring_gate: DomainResult, run_active: bool, persistence_operation_active: bool) -> void:
	_authoring_gate = authoring_gate
	_run_active = run_active
	_persistence_operation_active = persistence_operation_active

## Returns a detached fixed-roster snapshot with only current and previous roles.
func slot_snapshot() -> Dictionary[String, Variant]:
	var snapshot: Dictionary[String, Variant] = {}
	for slot_id: String in SLOT_IDS:
		snapshot[slot_id] = _slots[slot_id].duplicate(true)
	return snapshot

## Re-observes the typed Windows slot containers without selecting a recovery
## candidate. A caller must still pass current/previous to the recovery root.
func refresh_persisted_slots() -> DomainResult:
	if _save_port == null:
		return DomainResultType.success(slot_snapshot())
	for slot_id: String in SLOT_IDS:
		var observed: DomainResult = _save_port.observe_slot(StringName(slot_id))
		if not observed.is_success():
			return observed
		var adopted: DomainResult = _adopt_observed_slot(slot_id, _dictionary(observed.value()))
		if not adopted.is_success():
			return adopted
	return DomainResultType.success(slot_snapshot())

## Returns a token bound to a slot's currently observed generations and revision.
## Example: `var token: Variant = service.confirmation_for("manual.1").value()`.
func confirmation_for(slot_id: String) -> DomainResult:
	if not _is_known_slot(slot_id):
		return _reject(&"invalid_slot", "slot is not in the fixed roster", slot_id)
	var slot: Dictionary[String, Variant] = _slot_for(slot_id)
	return DomainResultType.success({
		"slot_id": slot_id,
		"current_generation_id": _generation_id(slot["current"]),
		"previous_generation_id": _generation_id(slot["previous"]),
		"slot_revision": _slot_revisions[slot_id],
	})

## Saves a prevalidated candidate to one manual slot, rotating only after valid confirmation.
func save(slot_id: String, candidate: Dictionary[String, Variant], generation_id: String, confirmation_token: Dictionary[String, Variant] = {}) -> DomainResult:
	var eligibility: DomainResult = _check_eligibility()
	if not eligibility.is_success():
		return eligibility
	if not _is_manual_slot(slot_id):
		return _reject(&"invalid_slot", "manual Save targets manual.1 through manual.3", slot_id)
	return _save_to_slot(slot_id, candidate, generation_id, confirmation_token, true)

## Writes the fixed autosave slot without manual-overwrite confirmation.
func autosave(candidate: Dictionary[String, Variant], generation_id: String) -> DomainResult:
	var eligibility: DomainResult = _check_eligibility()
	if not eligibility.is_success():
		return eligibility
	return _save_to_slot(AUTOSAVE_SLOT_ID, candidate, generation_id, {}, false)

## Loads only the current manual generation. Recovery selection belongs to a later story.
func load(slot_id: String) -> DomainResult:
	var eligibility: DomainResult = _check_eligibility()
	if not eligibility.is_success():
		return eligibility
	if not _is_manual_slot(slot_id):
		return _reject(&"invalid_slot", "manual Load targets manual.1 through manual.3", slot_id)
	if _save_port != null:
		var observed: DomainResult = _save_port.observe_slot(StringName(slot_id))
		if not observed.is_success():
			return observed
		var adopted: DomainResult = _adopt_observed_slot(slot_id, _dictionary(observed.value()))
		if not adopted.is_success():
			return adopted
	var slot: Dictionary[String, Variant] = _slot_for(slot_id)
	if slot["current"] == null:
		return _reject(&"slot_empty", "the requested slot has no current generation", slot_id)
	return DomainResultType.success({"result_code": &"loaded_current", "generation": slot["current"].duplicate(true)})

## Clears both generations of one manual slot only after matching observed-state confirmation.
func delete(slot_id: String, confirmation_token: Dictionary[String, Variant] = {}) -> DomainResult:
	var eligibility: DomainResult = _check_eligibility()
	if not eligibility.is_success():
		return eligibility
	if not _is_manual_slot(slot_id):
		return _reject(&"invalid_slot", "manual Delete targets manual.1 through manual.3", slot_id)
	var slot: Dictionary[String, Variant] = _slot_for(slot_id)
	if slot["current"] == null:
		return _reject(&"slot_empty", "the requested slot has no generations", slot_id)
	if not _confirmation_matches(slot_id, confirmation_token):
		return _reject(&"confirmation_required", "Delete confirmation does not match the observed slot state", slot_id)
	if _save_port != null:
		var deleted: DomainResult = _save_port.delete_slot(StringName(slot_id))
		if not deleted.is_success():
			return deleted
		var observed: DomainResult = _save_port.observe_slot(StringName(slot_id))
		if not observed.is_success():
			return observed
		var adopted: DomainResult = _adopt_observed_slot(slot_id, _dictionary(observed.value()))
		if not adopted.is_success():
			return adopted
		return DomainResultType.success({"result_code": &"slot_deleted", "slot_id": slot_id})
	var empty_slot: Dictionary[String, Variant] = {"current": null, "previous": null}
	_slots[slot_id] = empty_slot
	_slot_revisions[slot_id] += 1
	return DomainResultType.success({"result_code": &"slot_deleted", "slot_id": slot_id})

func _save_to_slot(slot_id: String, candidate: Dictionary[String, Variant], generation_id: String, confirmation_token: Dictionary[String, Variant], requires_confirmation: bool) -> DomainResult:
	if candidate.is_empty() or generation_id.is_empty():
		return _reject(&"candidate_invalid", "a prevalidated candidate and opaque generation ID are required", slot_id)
	var slot: Dictionary[String, Variant] = _slot_for(slot_id)
	var current: Variant = slot["current"]
	if current != null and _candidate_matches(current, candidate):
		return DomainResultType.success({"result_code": &"save_unchanged", "slot_id": slot_id})
	if requires_confirmation and current != null and not _confirmation_matches(slot_id, confirmation_token):
		return _reject(&"confirmation_required", "Save confirmation does not match the observed slot state", slot_id)
	if _save_port != null:
		var checkpoint_result: DomainResult = _checkpoint_for_v2_candidate(candidate)
		if not checkpoint_result.is_success():
			return checkpoint_result
		var persisted: DomainResult = _save_port.save_checkpoint(
			StringName(slot_id), generation_id, checkpoint_result.value())
		if not persisted.is_success():
			return persisted
		var observed: DomainResult = _save_port.observe_slot(StringName(slot_id))
		if not observed.is_success():
			return observed
		var adopted: DomainResult = _adopt_observed_slot(slot_id, _dictionary(observed.value()))
		if not adopted.is_success():
			return adopted
		var result_code: StringName = persisted.value() as StringName
		return DomainResultType.success({"result_code": result_code, "slot_id": slot_id, "generation_id": generation_id})
	var next_current: Dictionary[String, Variant] = {
		"generation_id": generation_id,
		"candidate": candidate.duplicate(true),
	}
	var next_slot: Dictionary[String, Variant] = {"current": next_current, "previous": current.duplicate(true) if current != null else null}
	_slots[slot_id] = next_slot
	_slot_revisions[slot_id] += 1
	return DomainResultType.success({"result_code": &"save_committed", "slot_id": slot_id, "generation_id": generation_id})

func _checkpoint_for_v2_candidate(candidate: Dictionary[String, Variant]) -> DomainResult:
	if _candidate_admission == null or not is_instance_valid(_candidate_admission):
		return _reject(&"candidate_admission_unavailable", "persistent Save requires v2 candidate admission")
	var root_bytes: DomainResult = _root_bytes_from_candidate(candidate)
	if not root_bytes.is_success():
		return root_bytes
	var checkpoint: CourseworkFiveSectionStableCheckpoint = StableCheckpointType.new(SettingsTutorialType.new())
	var accepted: DomainResult = checkpoint.submit_v2_raw_snapshot(
		root_bytes.value(), _candidate_admission)
	if not accepted.is_success():
		return accepted
	return DomainResultType.success(checkpoint)

func _adopt_observed_slot(slot_id: String, observed: Dictionary[String, Variant]) -> DomainResult:
	var current_result: DomainResult = _detached_candidate_from_observed_generation(observed.get("current", null))
	if not current_result.is_success():
		return current_result
	var previous_result: DomainResult = _detached_candidate_from_observed_generation(observed.get("previous", null))
	if not previous_result.is_success():
		return previous_result
	var prior: Dictionary[String, Variant] = _slot_for(slot_id)
	var next_slot: Dictionary[String, Variant] = {
		"current": current_result.value(), "previous": previous_result.value(),
	}
	if prior != next_slot:
		_slot_revisions[slot_id] += 1
	_slots[slot_id] = next_slot
	return DomainResultType.success(next_slot.duplicate(true))

func _detached_candidate_from_observed_generation(generation: Variant) -> DomainResult:
	if generation == null:
		return DomainResultType.success(null)
	var record: Dictionary[String, Variant] = _dictionary(generation)
	var raw_value: Variant = record.get("raw_bytes", null)
	if not raw_value is PackedByteArray:
		return DomainResultType.success({
			"generation_id": String(record.get("generation_id", "")), "candidate": null,
		})
	var candidate: DomainResult = _detached_candidate_from_root_bytes(PackedByteArray(raw_value))
	if not candidate.is_success():
		return DomainResultType.success({
			"generation_id": String(record.get("generation_id", "")), "candidate": null,
		})
	return DomainResultType.success({
		"generation_id": String(record.get("generation_id", "")),
		"candidate": candidate.value(),
	})

func _detached_candidate_from_root_bytes(root_bytes: PackedByteArray) -> DomainResult:
	var decoded: DomainResult = CanonicalCodecType.decode_parts(root_bytes)
	if not decoded.is_success():
		return decoded
	var root: Dictionary[String, Variant] = _dictionary(_dictionary(decoded.value()).get("value", null))
	var sections: Dictionary[String, Variant] = {}
	for section_name: String in ["authoring", "content", "progression", "settings", "tutorial"]:
		var section_value: Variant = root.get(section_name, null)
		if typeof(section_value) != TYPE_DICTIONARY:
			return _reject(&"candidate_invalid", "persisted root section must be an object", section_name)
		sections[section_name] = _dictionary(section_value)
	return _encoded_candidate_sections(sections)

func _root_bytes_from_candidate(candidate: Dictionary[String, Variant]) -> DomainResult:
	var sections_result: DomainResult = _decoded_candidate_sections(candidate)
	if not sections_result.is_success():
		return sections_result
	var sections: Dictionary[String, Variant] = _dictionary(sections_result.value())
	return CanonicalCodecType.encode({
		"authoring": sections["authoring"], "content": sections["content"],
		"progression": sections["progression"], "settings": sections["settings"],
		"tutorial": sections["tutorial"],
	})

func _encoded_candidate_sections(sections: Dictionary[String, Variant]) -> DomainResult:
	var raw_sections: Dictionary[String, PackedByteArray] = {}
	for section_name: String in ["authoring", "content", "progression", "settings", "tutorial"]:
		var encoded: DomainResult = CanonicalCodecType.encode(sections.get(section_name, null))
		if not encoded.is_success():
			return encoded
		raw_sections[section_name] = PackedByteArray(encoded.value())
	var preimage: DomainResult = CanonicalCodecType.encode([
		"coursework.save.v2", sections["authoring"], sections["content"], sections["progression"],
		sections["settings"], sections["tutorial"]])
	if not preimage.is_success():
		return preimage
	return DomainResultType.success({
		"save_version": "coursework.save.v2", "authoring_raw": raw_sections["authoring"],
		"content_raw": raw_sections["content"], "progression_raw": raw_sections["progression"],
		"settings_raw": raw_sections["settings"], "tutorial_raw": raw_sections["tutorial"],
		"checksum": CanonicalCodecType.sha256_hex(preimage.value()),
	})

func _decoded_candidate_sections(candidate: Dictionary[String, Variant]) -> DomainResult:
	if String(candidate.get("save_version", "")) != "coursework.save.v2":
		return _reject(&"unsupported_version", "persistent Save accepts coursework.save.v2 only")
	var sections: Dictionary[String, Variant] = {}
	for pair: Dictionary in [
		{"name": "authoring", "raw": "authoring_raw"}, {"name": "content", "raw": "content_raw"},
		{"name": "progression", "raw": "progression_raw"}, {"name": "settings", "raw": "settings_raw"},
		{"name": "tutorial", "raw": "tutorial_raw"},
	]:
		var raw_value: Variant = candidate.get(String(pair["raw"]), null)
		if not raw_value is PackedByteArray:
			return _reject(&"candidate_invalid", "candidate section bytes are required", String(pair["raw"]))
		var decoded: DomainResult = CanonicalCodecType.decode_parts(PackedByteArray(raw_value))
		if not decoded.is_success():
			return decoded
		var value: Variant = _dictionary(decoded.value()).get("value", null)
		if typeof(value) != TYPE_DICTIONARY:
			return _reject(&"candidate_invalid", "candidate section must be an object", String(pair["name"]))
		sections[String(pair["name"])] = _dictionary(value)
	var preimage: DomainResult = CanonicalCodecType.encode([
		"coursework.save.v2", sections["authoring"], sections["content"], sections["progression"],
		sections["settings"], sections["tutorial"]])
	if not preimage.is_success():
		return preimage
	if String(candidate.get("checksum", "")) != CanonicalCodecType.sha256_hex(preimage.value()):
		return _reject(&"integrity_failed", "candidate checksum does not match canonical v2 bytes")
	return DomainResultType.success(sections)

func _check_eligibility() -> DomainResult:
	if _run_active:
		return _reject(&"run_active", "persistence commands are rejected during a synchronous Run")
	if _persistence_operation_active:
		return _reject(&"operation_busy", "another persistence operation is active")
	if not _authoring_gate.is_success():
		return _authoring_gate
	return DomainResultType.success(true)

func _confirmation_matches(slot_id: String, token: Dictionary[String, Variant]) -> bool:
	if token.is_empty() or String(token.get("slot_id", "")) != slot_id:
		return false
	if int(token.get("slot_revision", -1)) != _slot_revisions[slot_id]:
		return false
	var slot: Dictionary[String, Variant] = _slot_for(slot_id)
	return String(token.get("current_generation_id", "")) == _generation_id(slot["current"]) and String(token.get("previous_generation_id", "")) == _generation_id(slot["previous"])

func _candidate_matches(current: Variant, candidate: Dictionary[String, Variant]) -> bool:
	return _dictionary(current).get("candidate", null) == candidate

func _generation_id(generation: Variant) -> String:
	return String(_dictionary(generation).get("generation_id", ""))

func _dictionary(value: Variant) -> Dictionary[String, Variant]:
	var copy: Dictionary[String, Variant] = {}
	if typeof(value) != TYPE_DICTIONARY:
		return copy
	for raw_key: Variant in value.keys():
		if typeof(raw_key) != TYPE_STRING:
			return {}
		copy[String(raw_key)] = value[raw_key]
	return copy

func _slot_for(slot_id: String) -> Dictionary[String, Variant]:
	return _dictionary(_slots.get(slot_id, {}))

func _is_manual_slot(slot_id: String) -> bool:
	return MANUAL_SLOT_IDS.has(slot_id)

func _is_known_slot(slot_id: String) -> bool:
	return SLOT_IDS.has(slot_id)

func _reject(error_code: StringName, message: String, path: String = "") -> DomainResult:
	return DomainResultType.failure(error_code, message, path)
