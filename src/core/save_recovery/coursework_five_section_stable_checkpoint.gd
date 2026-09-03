class_name CourseworkFiveSectionStableCheckpoint
extends RefCounted

const CanonicalCodec = preload("res://src/foundation/canonical_codec.gd")
const CanonicalJsonIR = preload("res://src/foundation/canonical_json_ir.gd")
const ContractShapeProfile = preload("res://src/foundation/contract_shape_profile.gd")
const SettingsTutorialContracts = preload("res://src/core/save_recovery/coursework_settings_tutorial_projection_contracts.gd")

## Owns one atomically replaced five-section stable checkpoint candidate.
##
## Example:
## ```gdscript
## var projections: CourseworkSettingsTutorialProjectionContracts = CourseworkSettingsTutorialProjectionContracts.new()
## var checkpoint_owner: CourseworkFiveSectionStableCheckpoint = CourseworkFiveSectionStableCheckpoint.new(projections)
## var result: DomainResult = checkpoint_owner.submit_raw_snapshot(snapshot_bytes)
## if result.is_success():
##     var checkpoint: Dictionary[String, Variant] = checkpoint_owner.accepted_checkpoint()
## ```

const SECTION_ORDER: Array[String] = ["authoring", "content", "progression", "settings", "tutorial"]
const _TASK_STATES: Array[String] = ["locked", "rework_due", "editable", "completed"]
const _WORKDAY_STATES: Array[String] = ["rework_due", "task_open_regular", "regular_delivery_decision", "task_open_overtime", "forced_delivery_pending", "charged_action_recovery"]
const _COMMON_PROGRESSION_FIELDS: Array[String] = ["playthrough_id", "career_state", "current_day_index", "current_task_id", "task_states", "daily_records", "reputation", "d_total", "o_days", "assignment_complete"]
const _TASK_STATE_FIELDS: Array[String] = ["day_index", "task_id", "state"]
const _DAILY_RECORD_FIELDS: Array[String] = ["day_index", "task_id", "failed_case_count", "failed_case_ids", "overtime_minutes", "overtime_used", "remediation_state", "reputation_before", "reputation_rule_change", "reputation_applied_change", "reputation_after", "feedback_band"]
const _WORKDAY_FIELDS: Array[String] = ["state", "elapsed_minutes", "overtime_authorized", "pending_rework_minutes"]
const _RECOVERY_FIELDS: Array[String] = ["action_kind", "charged_minutes", "graph_revision"]
const _FINAL_OUTCOME_IDS: Array[String] = ["career.outcome.reliable_engineer", "career.outcome.needs_guidance", "career.outcome.firefighter"]

var _projection_owner: SettingsTutorialContracts
var _root_profile: ContractShapeProfile
var _accepted_raw_bytes: PackedByteArray = PackedByteArray()
var _accepted_checkpoint: Dictionary[String, Variant] = {}

## Creates an owner bound to the sole Settings/Tutorial projection owner.
## Example: `CourseworkFiveSectionStableCheckpoint.new(settings_tutorial_owner)`.
func _init(projection_owner: SettingsTutorialContracts) -> void:
	_projection_owner = projection_owner
	var profile_result: DomainResult = ContractShapeProfile.create(_string_names(SECTION_ORDER))
	if profile_result.is_success():
		_root_profile = profile_result.value() as ContractShapeProfile

## Attempts to atomically replace the accepted checkpoint from raw bytes.
## Rejection preserves the prior checkpoint, raw bytes, and projection-owner truth.
func submit_raw_snapshot(raw_bytes: PackedByteArray) -> DomainResult:
	if _projection_owner == null:
		return DomainResult.failure(&"missing_projection_owner", "a Settings/Tutorial projection owner is required")
	if _root_profile == null or not _root_profile.is_valid():
		return DomainResult.failure(&"invalid_root_profile", "the frozen root profile could not be initialized")
	var raw_validation: DomainResult = CanonicalCodec.validate_raw_bytes(raw_bytes)
	if not raw_validation.is_success():
		return raw_validation
	var order_result: DomainResult = _validate_raw_root_order(raw_validation.value())
	if not order_result.is_success():
		return order_result
	var decoded: DomainResult = CanonicalCodec.decode_parts(raw_bytes, _root_profile)
	if not decoded.is_success():
		return decoded
	var decoded_parts: Dictionary[String, Variant] = _dictionary_from_variant(decoded.value())
	var root_value: Variant = decoded_parts.get("value", null)
	if typeof(root_value) != TYPE_DICTIONARY:
		return DomainResult.failure(&"invalid_root_shape", "snapshot root must normalize to an object", "$")
	var candidate_result: DomainResult = _prepare_non_owner_candidate(root_value)
	if not candidate_result.is_success():
		return candidate_result
	var candidate: Dictionary[String, Variant] = _dictionary_from_variant(candidate_result.value())

	# submit_pair is intentionally the final fallible action. It validates both
	# owner projections before replacing either one.
	var owner_result: DomainResult = _projection_owner.submit_pair(candidate["settings"], candidate["tutorial"])
	if not owner_result.is_success():
		return owner_result

	# No validation or owner action follows the accepted pair: commit detached data.
	var projections: Dictionary[String, Variant] = _dictionary_from_variant(owner_result.value())
	_accepted_raw_bytes = PackedByteArray(raw_bytes)
	_accepted_checkpoint = {
		"authoring": candidate["authoring"],
		"content": candidate["content"],
		"progression": candidate["progression"],
		"settings": projections["settings"],
		"tutorial": projections["tutorial"],
	}
	return DomainResult.success(accepted_checkpoint())

## Admits a canonical coursework.save.v2 root through the supplied v2 semantic
## admission owner, then retains the reversible five-section source bytes for
## the typed Windows SavePort. The checkpoint does not repeat v2 semantics.
func submit_v2_raw_snapshot(
		raw_bytes: PackedByteArray, candidate_admission: CourseworkCanonicalCandidateAdmission
) -> DomainResult:
	if candidate_admission == null or not is_instance_valid(candidate_admission):
		return DomainResult.failure(
			&"candidate_admission_unavailable", "v2 checkpoint admission requires its semantic validator")
	var sections_result: DomainResult = _v2_sections_from_raw(raw_bytes)
	if not sections_result.is_success():
		return sections_result
	var admitted: DomainResult = _admit_v2_sections(
		_dictionary_from_variant(sections_result.value()), candidate_admission)
	if not admitted.is_success():
		return admitted
	_accept_v2_checkpoint(raw_bytes, _dictionary_from_variant(admitted.value()))
	return DomainResult.success(accepted_checkpoint())

func _v2_sections_from_raw(raw_bytes: PackedByteArray) -> DomainResult:
	var raw_validation: DomainResult = CanonicalCodec.validate_raw_bytes(raw_bytes)
	if not raw_validation.is_success(): return raw_validation
	var order_result: DomainResult = _validate_raw_root_order(raw_validation.value())
	if not order_result.is_success(): return order_result
	var decoded: DomainResult = CanonicalCodec.decode_parts(raw_bytes, _root_profile)
	if not decoded.is_success(): return decoded
	var root_value: Variant = _dictionary_from_variant(decoded.value()).get("value", null)
	if typeof(root_value) != TYPE_DICTIONARY:
		return DomainResult.failure(&"invalid_root_shape", "snapshot root must normalize to an object", "$")
	return _encode_v2_sections(_dictionary_from_variant(root_value))

func _encode_v2_sections(root: Dictionary[String, Variant]) -> DomainResult:
	var sections: Array[Dictionary] = []
	var raw_sections: Array[PackedByteArray] = []
	for section_name: String in SECTION_ORDER:
		if typeof(root.get(section_name, null)) != TYPE_DICTIONARY:
			return DomainResult.failure(&"invalid_section_payload", "each v2 snapshot section must be an object", "$.%s" % section_name)
		var section: Dictionary[String, Variant] = _dictionary_from_variant(root[section_name])
		var encoded: DomainResult = CanonicalCodec.encode(section)
		if not encoded.is_success(): return encoded
		sections.append(section)
		raw_sections.append(PackedByteArray(encoded.value()))
	return DomainResult.success({"sections": sections, "raw_sections": raw_sections})

func _admit_v2_sections(bundle: Dictionary[String, Variant], admission: CourseworkCanonicalCandidateAdmission) -> DomainResult:
	var section_values: Array[Variant] = _array_from_variant(bundle.get("sections", null))
	var raw_section_values: Array[Variant] = _array_from_variant(bundle.get("raw_sections", null))
	if section_values.size() != SECTION_ORDER.size() or raw_section_values.size() != SECTION_ORDER.size():
		return DomainResult.failure(&"invalid_section_count", "encoded v2 bundle must contain exactly five typed sections")
	var sections: Array[Dictionary] = []
	var raw_sections: Array[PackedByteArray] = []
	for index: int in range(SECTION_ORDER.size()):
		if typeof(section_values[index]) != TYPE_DICTIONARY or not raw_section_values[index] is PackedByteArray:
			return DomainResult.failure(&"invalid_section_payload", "encoded v2 bundle crossed an invalid typed section boundary")
		sections.append(_dictionary_from_variant(section_values[index]))
		raw_sections.append(PackedByteArray(raw_section_values[index]))
	var preimage: DomainResult = CanonicalCodec.encode(["coursework.save.v2", sections[0], sections[1], sections[2], sections[3], sections[4]])
	if not preimage.is_success(): return preimage
	return admission.admit_v2(raw_sections[0], raw_sections[1], raw_sections[2], raw_sections[3], raw_sections[4], CanonicalCodec.sha256_hex(preimage.value()))

func _accept_v2_checkpoint(raw_bytes: PackedByteArray, accepted: Dictionary[String, Variant]) -> void:
	_accepted_raw_bytes = raw_bytes.duplicate()
	_accepted_checkpoint = {"authoring": accepted["authoring"], "content": accepted["content"], "progression": accepted["progression"], "settings": accepted["settings"], "tutorial": accepted["tutorial"]}

## Returns whether this owner has accepted a checkpoint.
## Example: `if checkpoint_owner.has_accepted_checkpoint(): restore(checkpoint_owner.accepted_checkpoint())`.
func has_accepted_checkpoint() -> bool:
	return not _accepted_checkpoint.is_empty()

## Returns a detached copy of the last accepted checkpoint, or an empty dictionary.
## Example: `var checkpoint: Dictionary[String, Variant] = checkpoint_owner.accepted_checkpoint()`.
func accepted_checkpoint() -> Dictionary[String, Variant]:
	return _accepted_checkpoint.duplicate(true)

## Returns a detached copy of the raw bytes for the last accepted checkpoint.
## Example: `var bytes: PackedByteArray = checkpoint_owner.accepted_raw_bytes()`.
func accepted_raw_bytes() -> PackedByteArray:
	return _accepted_raw_bytes.duplicate()

func _validate_raw_root_order(raw_root: Variant) -> DomainResult:
	if typeof(raw_root) != TYPE_DICTIONARY:
		return DomainResult.failure(&"invalid_root_shape", "snapshot root must be an object", "$")
	var root: Dictionary[String, Variant] = _dictionary_from_variant(raw_root)
	var ordered_keys: Array[Variant] = _array_from_variant(root.keys())
	if ordered_keys.size() != SECTION_ORDER.size():
		return DomainResult.failure(&"invalid_section_count", "snapshot must contain exactly five top-level sections", "$")
	for index: int in range(SECTION_ORDER.size()):
		if not CanonicalJsonIR.equal(ordered_keys[index], SECTION_ORDER[index]):
			return DomainResult.failure(&"invalid_section_order", "snapshot top-level sections must use the frozen order", "$.%s" % SECTION_ORDER[index])
	return DomainResult.success(true)

func _prepare_non_owner_candidate(root_value: Variant) -> DomainResult:
	var root: Dictionary[String, Variant] = _dictionary_from_variant(root_value)
	for section: String in SECTION_ORDER:
		if typeof(root.get(section, null)) != TYPE_DICTIONARY:
			return DomainResult.failure(&"invalid_section_payload", "each snapshot section must be an object", "$.%s" % section)
	var progression_result: DomainResult = _validate_progression(root["progression"])
	if not progression_result.is_success():
		return progression_result
	var candidate: Dictionary[String, Variant] = {
		"authoring": _dictionary_from_variant(root["authoring"]).duplicate(true),
		"content": _dictionary_from_variant(root["content"]).duplicate(true),
		"progression": progression_result.value(),
		"settings": _dictionary_from_variant(root["settings"]).duplicate(true),
		"tutorial": _dictionary_from_variant(root["tutorial"]).duplicate(true),
	}
	return DomainResult.success(candidate)

func _validate_progression(value: Variant) -> DomainResult:
	if typeof(value) != TYPE_DICTIONARY:
		return DomainResult.failure(&"invalid_progression", "progression must be an object", "$.progression")
	var progression: Dictionary[String, Variant] = _dictionary_from_variant(value)
	var state_value: Variant = progression.get("career_state", null)
	if typeof(state_value) != TYPE_STRING or not ["active", "finalized"].has(state_value):
		return DomainResult.failure(&"invalid_career_state", "career_state must be active or finalized", "$.progression.career_state")
	var expected_fields: Array[String] = _COMMON_PROGRESSION_FIELDS.duplicate()
	if state_value == "active":
		expected_fields.append("workday")
	else:
		expected_fields.append("final_outcome")
	if progression.has("outstanding_day5_remediation"):
		expected_fields.append("outstanding_day5_remediation")
	var shape_result: DomainResult = _validate_exact_fields(progression, expected_fields, "$.progression")
	if not shape_result.is_success():
		return shape_result
	if not _is_non_empty_string(progression["playthrough_id"]) or not _is_integer_in_range(progression["current_day_index"], 1, 5) or not _is_non_empty_string(progression["current_task_id"]):
		return DomainResult.failure(&"invalid_progression_identity", "progression identity fields are invalid", "$.progression")
	if not _is_integer_in_range(progression["reputation"], 0, 100) or not _is_integer_in_range(progression["d_total"], 0, 36) or not _is_integer_in_range(progression["o_days"], 0, 5) or typeof(progression["assignment_complete"]) != TYPE_BOOL:
		return DomainResult.failure(&"invalid_progression_summary", "progression summary fields are invalid", "$.progression")
	var task_result: DomainResult = _validate_task_states(progression["task_states"])
	if not task_result.is_success():
		return task_result
	var record_result: DomainResult = _validate_daily_records(progression["daily_records"])
	if not record_result.is_success():
		return record_result
	var task_states: Array[Variant] = _array_from_variant(task_result.value())
	var records: Array[Variant] = _array_from_variant(record_result.value())
	if progression.has("outstanding_day5_remediation") and typeof(progression["outstanding_day5_remediation"]) != TYPE_DICTIONARY:
		return DomainResult.failure(&"invalid_remediation", "outstanding_day5_remediation must be an object", "$.progression.outstanding_day5_remediation")
	if state_value == "active":
		return _validate_active_progression(progression, task_states, records)
	return _validate_finalized_progression(progression, task_states, records)

func _validate_task_states(value: Variant) -> DomainResult:
	if typeof(value) != TYPE_ARRAY:
		return DomainResult.failure(&"invalid_task_states", "task_states must be an array", "$.progression.task_states")
	var states: Array[Variant] = _array_from_variant(value)
	if states.size() != 5:
		return DomainResult.failure(&"invalid_task_state_count", "task_states must contain exactly five ordered entries", "$.progression.task_states")
	var copied: Array[Variant] = []
	for index: int in range(states.size()):
		var entry_value: Variant = states[index]
		if typeof(entry_value) != TYPE_DICTIONARY:
			return DomainResult.failure(&"invalid_task_state", "each task state must be an object", "$.progression.task_states[%d]" % index)
		var entry: Dictionary[String, Variant] = _dictionary_from_variant(entry_value)
		var shape_result: DomainResult = _validate_exact_fields(entry, _TASK_STATE_FIELDS, "$.progression.task_states[%d]" % index)
		if not shape_result.is_success():
			return shape_result
		if not _is_integer_in_range(entry["day_index"], 1, 5) or int(entry["day_index"]) != index + 1 or not _is_non_empty_string(entry["task_id"]) or typeof(entry["state"]) != TYPE_STRING or not _TASK_STATES.has(entry["state"]):
			return DomainResult.failure(&"invalid_task_state", "task state identity, order, or domain is invalid", "$.progression.task_states[%d]" % index)
		copied.append(entry.duplicate(true))
	return DomainResult.success(copied)

func _validate_daily_records(value: Variant) -> DomainResult:
	if typeof(value) != TYPE_ARRAY:
		return DomainResult.failure(&"invalid_daily_records", "daily_records must be an array", "$.progression.daily_records")
	var records: Array[Variant] = _array_from_variant(value)
	if records.size() > 5:
		return DomainResult.failure(&"invalid_daily_record_count", "daily_records may contain zero to five entries", "$.progression.daily_records")
	var copied: Array[Variant] = []
	for index: int in range(records.size()):
		var record_value: Variant = records[index]
		if typeof(record_value) != TYPE_DICTIONARY:
			return DomainResult.failure(&"invalid_daily_record", "each daily record must be an object", "$.progression.daily_records[%d]" % index)
		var record: Dictionary[String, Variant] = _dictionary_from_variant(record_value)
		var shape_result: DomainResult = _validate_exact_fields(record, _DAILY_RECORD_FIELDS, "$.progression.daily_records[%d]" % index)
		if not shape_result.is_success():
			return shape_result
		if not _is_integer_in_range(record["day_index"], 1, 5) or int(record["day_index"]) != index + 1 or not _is_non_empty_string(record["task_id"]) or not _is_integer_in_range(record["failed_case_count"], 0, 36) or typeof(record["failed_case_ids"]) != TYPE_ARRAY or not _are_strings(record["failed_case_ids"]) or not _is_integer_in_range(record["overtime_minutes"], 0, 120) or typeof(record["overtime_used"]) != TYPE_BOOL or not _is_non_empty_string(record["remediation_state"]) or not _is_non_empty_string(record["feedback_band"]):
			return DomainResult.failure(&"invalid_daily_record", "daily record shape, identity, or domain is invalid", "$.progression.daily_records[%d]" % index)
		for field_name: String in ["reputation_before", "reputation_rule_change", "reputation_applied_change", "reputation_after"]:
			if typeof(record[field_name]) != TYPE_INT:
				return DomainResult.failure(&"invalid_reputation_record", "daily reputation fields must be integers", "$.progression.daily_records[%d].%s" % [index, field_name])
		copied.append(record.duplicate(true))
	return DomainResult.success(copied)

func _validate_active_progression(progression: Dictionary[String, Variant], task_states: Array[Variant], records: Array[Variant]) -> DomainResult:
	var current_day: int = int(progression["current_day_index"])
	if records.size() != current_day - 1 or bool(progression["assignment_complete"]):
		return DomainResult.failure(&"invalid_active_progression", "active progression record count or completion is invalid", "$.progression")
	for index: int in range(task_states.size()):
		var state: String = String(task_states[index]["state"])
		if index < current_day - 1 and state != "completed":
			return DomainResult.failure(&"invalid_active_task_states", "earlier active task states must be completed", "$.progression.task_states[%d]" % index)
		if index == current_day - 1 and state != "editable" and state != "rework_due":
			return DomainResult.failure(&"invalid_active_task_states", "the current task state must be editable or rework_due", "$.progression.task_states[%d]" % index)
		if index > current_day - 1 and state != "locked":
			return DomainResult.failure(&"invalid_active_task_states", "later active task states must be locked", "$.progression.task_states[%d]" % index)
	if String(progression["current_task_id"]) != String(task_states[current_day - 1]["task_id"]):
		return DomainResult.failure(&"invalid_current_task", "current_task_id must match the active task", "$.progression.current_task_id")
	var workday_result: DomainResult = _validate_workday(progression["workday"])
	if not workday_result.is_success():
		return workday_result
	var copied: Dictionary[String, Variant] = _dictionary_from_variant(progression.duplicate(true))
	copied["task_states"] = task_states.duplicate(true)
	copied["daily_records"] = records.duplicate(true)
	return DomainResult.success(copied)

func _validate_finalized_progression(progression: Dictionary[String, Variant], task_states: Array[Variant], records: Array[Variant]) -> DomainResult:
	if records.size() != 5 or not bool(progression["assignment_complete"]) or int(progression["current_day_index"]) != 5 or String(progression["current_task_id"]) != String(task_states[4]["task_id"]):
		return DomainResult.failure(&"invalid_finalized_progression", "finalized progression summary is invalid", "$.progression")
	for index: int in range(task_states.size()):
		if String(task_states[index]["state"]) != "completed":
			return DomainResult.failure(&"invalid_finalized_task_states", "all finalized task states must be completed", "$.progression.task_states[%d]" % index)
	if typeof(progression["final_outcome"]) != TYPE_STRING or not _FINAL_OUTCOME_IDS.has(String(progression["final_outcome"])):
		return DomainResult.failure(&"invalid_final_outcome", "final_outcome must be one accepted Career outcome ID", "$.progression.final_outcome")
	var copied: Dictionary[String, Variant] = _dictionary_from_variant(progression.duplicate(true))
	copied["task_states"] = task_states.duplicate(true)
	copied["daily_records"] = records.duplicate(true)
	return DomainResult.success(copied)

func _validate_workday(value: Variant) -> DomainResult:
	if typeof(value) != TYPE_DICTIONARY:
		return DomainResult.failure(&"invalid_workday", "active progression requires a Workday object", "$.progression.workday")
	var workday: Dictionary[String, Variant] = _dictionary_from_variant(value)
	var state_value: Variant = workday.get("state", null)
	if typeof(state_value) != TYPE_STRING or not _WORKDAY_STATES.has(state_value):
		return DomainResult.failure(&"invalid_workday_state", "Workday state is outside the stable domain", "$.progression.workday.state")
	var expected_fields: Array[String] = _WORKDAY_FIELDS.duplicate()
	if state_value == "charged_action_recovery":
		expected_fields.append("recovery_action")
	var shape_result: DomainResult = _validate_exact_fields(workday, expected_fields, "$.progression.workday")
	if not shape_result.is_success():
		return shape_result
	if not _is_integer_in_range(workday["elapsed_minutes"], 0, 600) or typeof(workday["overtime_authorized"]) != TYPE_BOOL or typeof(workday["pending_rework_minutes"]) != TYPE_INT or not [0, 60].has(int(workday["pending_rework_minutes"])):
		return DomainResult.failure(&"invalid_workday", "Workday time, authorization, or rework data is invalid", "$.progression.workday")
	if state_value == "charged_action_recovery":
		var recovery_value: Variant = workday["recovery_action"]
		if typeof(recovery_value) != TYPE_DICTIONARY:
			return DomainResult.failure(&"invalid_recovery_action", "recovery_action must be an object", "$.progression.workday.recovery_action")
		var recovery: Dictionary[String, Variant] = _dictionary_from_variant(recovery_value)
		var recovery_shape: DomainResult = _validate_exact_fields(recovery, _RECOVERY_FIELDS, "$.progression.workday.recovery_action")
		if not recovery_shape.is_success():
			return recovery_shape
		var revision: Variant = recovery["graph_revision"]
		if not _is_non_empty_string(recovery["action_kind"]) or not _is_integer_in_range(recovery["charged_minutes"], 0, 600) or not ((typeof(revision) == TYPE_INT and int(revision) >= 0) or _is_non_empty_string(revision)):
			return DomainResult.failure(&"invalid_recovery_action", "recovery action is outside its stable domain", "$.progression.workday.recovery_action")
	return DomainResult.success(workday.duplicate(true))

func _validate_exact_fields(candidate: Dictionary[String, Variant], expected_fields: Array[String], path: String) -> DomainResult:
	if candidate.size() != expected_fields.size():
		return DomainResult.failure(&"invalid_record_shape", "record has an unexpected field count", path)
	for expected_field: String in expected_fields:
		if not candidate.has(expected_field):
			return DomainResult.failure(&"invalid_record_shape", "record fields do not match the stable roster", path)
	return DomainResult.success(true)

func _are_strings(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	var values: Array[Variant] = _array_from_variant(value)
	for item: Variant in values:
		if not _is_non_empty_string(item):
			return false
	return true

func _is_non_empty_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not String(value).is_empty()

func _is_integer_in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= minimum and int(value) <= maximum

func _string_names(values: Array[String]) -> Array[StringName]:
	var names: Array[StringName] = []
	for value: String in values:
		names.append(StringName(value))
	return names

func _dictionary_from_variant(value: Variant) -> Dictionary[String, Variant]:
	var copied: Dictionary[String, Variant] = {}
	if typeof(value) != TYPE_DICTIONARY:
		return copied
	for key: Variant in value.keys():
		if typeof(key) == TYPE_STRING:
			copied[String(key)] = value[key]
	return copied

func _array_from_variant(value: Variant) -> Array[Variant]:
	var copied: Array[Variant] = []
	if typeof(value) != TYPE_ARRAY:
		return copied
	for item: Variant in value:
		copied.append(item)
	return copied
