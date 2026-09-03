class_name CourseworkProgressionConsistencyReplay
extends RefCounted

## Validates one complete progression projection by replaying its stored records.
##
## Example:
## ```gdscript
## var validator: CourseworkProgressionConsistencyReplay = CourseworkProgressionConsistencyReplay.new()
## var result: DomainResult = validator.submit(progression_projection)
## if result.is_success():
##     var restored: Dictionary[String, Variant] = validator.accepted_progression()
## ```

const _DAY_COUNT: int = 5
const _INITIAL_REPUTATION: int = 50
const _FAILURE_LIMITS: Array[int] = [3, 5, 7, 9, 12]
const _ACTIVE_TASK_STATES: Array[String] = ["rework_due", "editable"]
const _WORKDAY_STATES: Array[String] = ["rework_due", "task_open_regular", "regular_delivery_decision", "task_open_overtime", "forced_delivery_pending", "charged_action_recovery"]
const _OUTCOME_IDS: Array[String] = ["career.outcome.reliable_engineer", "career.outcome.needs_guidance", "career.outcome.firefighter"]
const _TASK_STATE_FIELDS: Array[String] = ["day_index", "task_id", "state"]
const _DAILY_RECORD_FIELDS: Array[String] = ["day_index", "task_id", "failed_case_count", "failed_case_ids", "overtime_minutes", "overtime_used", "remediation_state", "reputation_before", "reputation_rule_change", "reputation_applied_change", "reputation_after", "feedback_band"]
const _WORKDAY_FIELDS: Array[String] = ["state", "elapsed_minutes", "overtime_authorized", "pending_rework_minutes"]
const _RECOVERY_ACTION_FIELDS: Array[String] = ["action_kind", "charged_minutes", "graph_revision"]

var _accepted_progression: Dictionary[String, Variant] = {}

## Atomically accepts a detached progression projection after consistency replay.
## Rejection leaves the previously accepted progression unchanged.
func submit(progression_value: Variant) -> DomainResult:
	var validation: DomainResult = _validate(progression_value)
	if not validation.is_success():
		return validation
	_accepted_progression = _copy_dictionary(validation.value())
	return DomainResult.success(accepted_progression())

## Returns whether a progression has been accepted.
## Example: `if validator.has_accepted_progression(): restore(validator.accepted_progression())`.
func has_accepted_progression() -> bool:
	return not _accepted_progression.is_empty()

## Returns a detached copy of the accepted progression, or an empty dictionary.
## Example: `var saved_progression: Dictionary[String, Variant] = validator.accepted_progression()`.
func accepted_progression() -> Dictionary[String, Variant]:
	return _accepted_progression.duplicate(true)

## ADR-0011 route. It deliberately validates the owner-owned v2 envelope
## without routing it through Story 002's flattened legacy progression form.
func submit_v2(progression_value: Variant) -> DomainResult:
	var envelope_result: DomainResult = _v2_owner_envelope(progression_value)
	if not envelope_result.is_success(): return envelope_result
	var envelope: Dictionary = envelope_result.value()
	var career: Dictionary = envelope["career"]
	var progression: Dictionary = envelope["progression"]
	if String(career["career_state"]) == "finalized":
		return _finalized_v2_result(progression)
	return _active_v2_result(progression, career)

func _v2_owner_envelope(progression_value: Variant) -> DomainResult:
	if typeof(progression_value) != TYPE_DICTIONARY:
		return _reject(&"progression_v2_invalid", "v2 progression must be a dictionary", "$.progression")
	var progression: Dictionary = Dictionary(progression_value)
	if progression.size() != 3 or not progression.has("current_task_id") or not progression.has("career_projection") or not progression.has("workday_projection") or typeof(progression["current_task_id"]) != TYPE_STRING or String(progression["current_task_id"]).is_empty() or typeof(progression["career_projection"]) != TYPE_DICTIONARY:
		return _reject(&"progression_v2_invalid", "v2 progression has an invalid owner envelope", "$.progression")
	var career: Dictionary = Dictionary(progression["career_projection"])
	if String(career.get("projection_version", "")) != "coursework.career.recovery.v1" or typeof(career.get("career_state", null)) != TYPE_STRING or typeof(career.get("eligible_task_id", null)) != TYPE_STRING or typeof(career.get("next_day", null)) != TYPE_INT:
		return _reject(&"career_projection_version_unsupported", "v2 progression requires Career recovery v1", "$.progression.career_projection")
	return DomainResult.success({"progression": progression, "career": career})

func _finalized_v2_result(progression: Dictionary) -> DomainResult:
	if progression["workday_projection"] != null:
		return _reject(&"progression_v2_workday_finalized", "finalized Career cannot retain Workday", "$.progression.workday_projection")
	return DomainResult.success(progression.duplicate(true))

func _active_v2_result(progression: Dictionary, career: Dictionary) -> DomainResult:
	if String(career["career_state"]) != "active" or String(career["eligible_task_id"]) != String(progression["current_task_id"]) or int(career["next_day"]) < 1:
		return _reject(&"progression_v2_active_invalid", "active Career requires its exact Task and Workday", "$.progression")
	var workday: Variant = progression["workday_projection"]
	if workday == null or typeof(workday) != TYPE_DICTIONARY:
		return _reject(&"progression_v2_active_invalid", "active Career Workday must be an object", "$.progression.workday_projection")
	return _validate_active_workday_v2(progression, career, Dictionary(workday))

func _validate_active_workday_v2(progression: Dictionary, career: Dictionary, projection: Dictionary) -> DomainResult:
	if projection.size() != 3 or String(projection.get("projection_version", "")) != "coursework.workday.recovery.v2" or typeof(projection.get("stable_lifecycle", null)) != TYPE_DICTIONARY or not projection.has("charged_intent"):
		return _reject(&"workday_recovery_projection_invalid", "v2 Workday projection has an invalid shape", "$.progression.workday_projection")
	var stable: Dictionary = Dictionary(projection["stable_lifecycle"])
	if typeof(stable.get("current_day_index", null)) != TYPE_INT or int(stable["current_day_index"]) != int(career["next_day"]):
		return _reject(&"progression_v2_workday_day_mismatch", "v2 Workday day must match Career next day", "$.progression.workday_projection")
	return _validate_v2_charged_intent(progression, projection["charged_intent"])

func _validate_v2_charged_intent(progression: Dictionary, intent: Variant) -> DomainResult:
	if intent == null: return DomainResult.success(progression.duplicate(true))
	if typeof(intent) != TYPE_DICTIONARY:
		return _reject(&"workday_recovery_binding_invalid", "v2 charged intent must be an object", "$.progression.workday_projection.charged_intent")
	var binding: Dictionary = Dictionary(intent)
	if binding.has("graph_snapshot") or binding.size() != 10 or not ["voluntary_locked", "authoritative_locked"].has(String(binding.get("mode", ""))) or typeof(binding.get("charged_minutes", null)) != TYPE_INT or int(binding["charged_minutes"]) <= 0 or String(binding.get("task_id", "")) != String(progression["current_task_id"]):
		return _reject(&"workday_recovery_binding_invalid", "v2 charged intent is invalid", "$.progression.workday_projection.charged_intent")
	var action_kind: String = String(binding.get("action_kind", ""))
	if (String(binding["mode"]) == "voluntary_locked" and not ["targeted_case", "voluntary_suite"].has(action_kind)) or (String(binding["mode"]) == "authoritative_locked" and action_kind != "authoritative_suite"):
		return _reject(&"workday_recovery_binding_invalid", "v2 charged intent mode and action differ", "$.progression.workday_projection.charged_intent")
	return DomainResult.success(progression.duplicate(true))

func _validate(progression_value: Variant) -> DomainResult:
	var inputs_result: DomainResult = _validation_inputs(progression_value)
	if not inputs_result.is_success():
		return inputs_result
	var inputs: Dictionary[String, Variant] = _copy_dictionary(inputs_result.value())
	var progression: Dictionary[String, Variant] = _copy_dictionary(inputs["progression"])
	var task_states: Array[Variant] = _copy_array(inputs["task_states"])
	var daily_records: Array[Variant] = _copy_array(inputs["daily_records"])
	var task_shape_result: DomainResult = _validate_task_states(task_states)
	if not task_shape_result.is_success():
		return task_shape_result
	var replay_result: DomainResult = _replay_records(daily_records, task_states)
	if not replay_result.is_success():
		return replay_result
	var summary_result: DomainResult = _validate_summary(progression, _copy_dictionary(replay_result.value()))
	if not summary_result.is_success():
		return summary_result
	var career_result: DomainResult = _validate_career_state(progression, task_states, daily_records)
	if not career_result.is_success():
		return career_result
	return DomainResult.success(progression.duplicate(true))

func _validation_inputs(progression_value: Variant) -> DomainResult:
	var progression_result: DomainResult = _progression_from_variant(progression_value)
	if not progression_result.is_success():
		return progression_result
	var progression: Dictionary[String, Variant] = _copy_dictionary(progression_result.value())
	var state_result: DomainResult = _required_string(progression, "career_state", "$.progression.career_state")
	if not state_result.is_success():
		return state_result
	var task_states_result: DomainResult = _array_field(progression, "task_states", "$.progression.task_states")
	if not task_states_result.is_success():
		return task_states_result
	var daily_records_result: DomainResult = _array_field(progression, "daily_records", "$.progression.daily_records")
	if not daily_records_result.is_success():
		return daily_records_result
	return DomainResult.success({"progression": progression, "task_states": task_states_result.value(), "daily_records": daily_records_result.value()})

func _validate_career_state(progression: Dictionary[String, Variant], task_states: Array[Variant], daily_records: Array[Variant]) -> DomainResult:
	var career_state: String = String(progression["career_state"])
	if career_state == "active":
		return _validate_active(progression, task_states, daily_records)
	if career_state == "finalized":
		return _validate_finalized(progression, task_states, daily_records)
	return _reject(&"progression_career_state_invalid", "career_state must be active or finalized", "$.progression.career_state")

func _progression_from_variant(value: Variant) -> DomainResult:
	if typeof(value) != TYPE_DICTIONARY:
		return _reject(&"progression_invalid", "progression must be a dictionary", "$.progression")
	return DomainResult.success(_copy_dictionary(value))

func _array_field(progression: Dictionary[String, Variant], field_name: String, path: String) -> DomainResult:
	if not progression.has(field_name) or typeof(progression[field_name]) != TYPE_ARRAY:
		return _reject(&"progression_field_invalid", "%s must be an array" % field_name, path)
	var copied: Array[Variant] = _copy_array(progression[field_name])
	return DomainResult.success(copied)

func _required_string(progression: Dictionary[String, Variant], field_name: String, path: String) -> DomainResult:
	if not progression.has(field_name) or typeof(progression[field_name]) != TYPE_STRING or String(progression[field_name]).is_empty():
		return _reject(&"progression_field_invalid", "%s must be a non-empty string" % field_name, path)
	return DomainResult.success(true)

func _replay_records(records: Array[Variant], task_states: Array[Variant]) -> DomainResult:
	if records.size() > _DAY_COUNT or task_states.size() != _DAY_COUNT:
		return _reject(&"progression_record_count_invalid", "progression must contain at most five records and exactly five task states", "$.progression")
	var expected_reputation: int = _INITIAL_REPUTATION
	var defect_total: int = 0
	var overtime_days: int = 0
	for index: int in range(records.size()):
		var record_result: DomainResult = _record_from_variant(records[index], index)
		if not record_result.is_success():
			return record_result
		var record: Dictionary[String, Variant] = _copy_dictionary(record_result.value())
		var task_result: DomainResult = _task_state_for_record(task_states[index], record, index)
		if not task_result.is_success():
			return task_result
		var consequence_result: DomainResult = _validate_record_consequence(record, expected_reputation, index)
		if not consequence_result.is_success():
			return consequence_result
		expected_reputation = int(record["reputation_after"])
		defect_total += int(record["failed_case_count"])
		if int(record["overtime_minutes"]) > 0:
			overtime_days += 1
	return DomainResult.success({"reputation": expected_reputation, "d_total": defect_total, "o_days": overtime_days})

func _record_from_variant(value: Variant, index: int) -> DomainResult:
	if typeof(value) != TYPE_DICTIONARY:
		return _reject(&"progression_record_invalid", "each daily record must be a dictionary", "$.progression.daily_records[%d]" % index)
	var record: Dictionary[String, Variant] = _copy_dictionary(value)
	var shape_result: DomainResult = _validate_exact_fields(record, _DAILY_RECORD_FIELDS, "$.progression.daily_records[%d]" % index)
	if not shape_result.is_success():
		return shape_result
	var identity_result: DomainResult = _validate_record_identity(record, index)
	if not identity_result.is_success():
		return identity_result
	var failures_result: DomainResult = _validate_record_failures(record, index)
	if not failures_result.is_success():
		return failures_result
	var overtime_result: DomainResult = _validate_record_overtime(record, index)
	if not overtime_result.is_success():
		return overtime_result
	var text_result: DomainResult = _validate_record_text_fields(record, index)
	if not text_result.is_success():
		return text_result
	var reputation_result: DomainResult = _validate_record_reputation_fields(record, index)
	if not reputation_result.is_success():
		return reputation_result
	return DomainResult.success(record)

func _validate_record_identity(record: Dictionary[String, Variant], index: int) -> DomainResult:
	if typeof(record["day_index"]) != TYPE_INT or int(record["day_index"]) != index + 1:
		return _reject(&"progression_record_order_invalid", "daily records must use consecutive day order", "$.progression.daily_records[%d].day_index" % index)
	if typeof(record["task_id"]) != TYPE_STRING or String(record["task_id"]).is_empty():
		return _reject(&"progression_record_invalid", "daily records require a task identity", "$.progression.daily_records[%d].task_id" % index)
	return DomainResult.success(true)

func _validate_record_failures(record: Dictionary[String, Variant], index: int) -> DomainResult:
	if typeof(record["failed_case_count"]) != TYPE_INT or int(record["failed_case_count"]) < 0 or int(record["failed_case_count"]) > _FAILURE_LIMITS[index]:
		return _reject(&"progression_failure_count_invalid", "daily failure count exceeds its day bound", "$.progression.daily_records[%d].failed_case_count" % index)
	if typeof(record["failed_case_ids"]) != TYPE_ARRAY:
		return _reject(&"progression_failed_case_ids_invalid", "daily failed case IDs must be an array", "$.progression.daily_records[%d].failed_case_ids" % index)
	var failed_case_ids: Array[Variant] = _copy_array(record["failed_case_ids"])
	var ids_result: DomainResult = _validate_failed_case_ids(failed_case_ids, index)
	if not ids_result.is_success():
		return ids_result
	if failed_case_ids.size() != int(record["failed_case_count"]):
		return _reject(&"progression_failed_case_ids_invalid", "daily failed case IDs must equal the stored failure count", "$.progression.daily_records[%d].failed_case_ids" % index)
	return DomainResult.success(true)

func _validate_failed_case_ids(failed_case_ids: Array[Variant], index: int) -> DomainResult:
	var seen_ids: Dictionary[String, bool] = {}
	for failed_case_id_value: Variant in failed_case_ids:
		if typeof(failed_case_id_value) != TYPE_STRING or String(failed_case_id_value).is_empty() or seen_ids.has(String(failed_case_id_value)):
			return _reject(&"progression_failed_case_ids_invalid", "daily failed case IDs must be unique non-empty strings", "$.progression.daily_records[%d].failed_case_ids" % index)
		seen_ids[String(failed_case_id_value)] = true
	return DomainResult.success(true)

func _validate_record_overtime(record: Dictionary[String, Variant], index: int) -> DomainResult:
	if typeof(record["overtime_minutes"]) != TYPE_INT or int(record["overtime_minutes"]) < 0 or int(record["overtime_minutes"]) > 120 or typeof(record["overtime_used"]) != TYPE_BOOL or bool(record["overtime_used"]) != (int(record["overtime_minutes"]) > 0):
		return _reject(&"progression_overtime_invalid", "daily overtime fields are inconsistent", "$.progression.daily_records[%d]" % index)
	return DomainResult.success(true)

func _validate_record_text_fields(record: Dictionary[String, Variant], index: int) -> DomainResult:
	if typeof(record["remediation_state"]) != TYPE_STRING or String(record["remediation_state"]).is_empty() or typeof(record["feedback_band"]) != TYPE_STRING or String(record["feedback_band"]).is_empty():
		return _reject(&"progression_record_invalid", "daily remediation and feedback fields must be non-empty strings", "$.progression.daily_records[%d]" % index)
	return DomainResult.success(true)

func _validate_record_reputation_fields(record: Dictionary[String, Variant], index: int) -> DomainResult:
	for field_name: String in ["reputation_before", "reputation_rule_change", "reputation_applied_change", "reputation_after"]:
		if typeof(record[field_name]) != TYPE_INT:
			return _reject(&"progression_reputation_invalid", "daily reputation fields must be integers", "$.progression.daily_records[%d].%s" % [index, field_name])
	return DomainResult.success(true)

func _task_state_for_record(value: Variant, record: Dictionary[String, Variant], index: int) -> DomainResult:
	var task_state: Dictionary[String, Variant] = _copy_dictionary(value)
	if String(task_state["task_id"]) != String(record["task_id"]):
		return _reject(&"progression_task_record_mismatch", "daily record identity must match its ordered task state", "$.progression.task_states[%d]" % index)
	return DomainResult.success(true)

func _validate_record_consequence(record: Dictionary[String, Variant], expected_reputation: int, index: int) -> DomainResult:
	if int(record["reputation_before"]) != expected_reputation:
		return _reject(&"progression_reputation_chain_invalid", "daily reputation must chain from the preceding stored record", "$.progression.daily_records[%d].reputation_before" % index)
	var expected_rule_change: int = _delta_rule_for_failures(int(record["failed_case_count"]))
	if int(record["reputation_rule_change"]) != expected_rule_change:
		return _reject(&"progression_rule_delta_invalid", "stored rule delta must match the recorded failure count", "$.progression.daily_records[%d].reputation_rule_change" % index)
	var replayed_reputation: int = clampi(expected_reputation + expected_rule_change, 0, 100)
	var replayed_applied_change: int = replayed_reputation - expected_reputation
	if int(record["reputation_applied_change"]) != replayed_applied_change or int(record["reputation_after"]) != replayed_reputation:
		return _reject(&"progression_reputation_replay_invalid", "stored reputation must match the deterministic replay", "$.progression.daily_records[%d]" % index)
	return DomainResult.success(true)

func _delta_rule_for_failures(failed_case_count: int) -> int:
	if failed_case_count == 0:
		return 10
	if failed_case_count == 1:
		return -10
	if failed_case_count == 2:
		return -15
	return -20

func _validate_task_states(task_states: Array[Variant]) -> DomainResult:
	if task_states.size() != _DAY_COUNT:
		return _reject(&"progression_task_state_count_invalid", "progression must contain exactly five task states", "$.progression.task_states")
	for index: int in range(_DAY_COUNT):
		var task_state_result: DomainResult = _task_state_from_variant(task_states[index], index)
		if not task_state_result.is_success():
			return task_state_result
	return DomainResult.success(true)

func _task_state_from_variant(value: Variant, index: int) -> DomainResult:
	if typeof(value) != TYPE_DICTIONARY:
		return _reject(&"progression_task_state_invalid", "each task state must be a dictionary", "$.progression.task_states[%d]" % index)
	var task_state: Dictionary[String, Variant] = _copy_dictionary(value)
	var shape_result: DomainResult = _validate_exact_fields(task_state, _TASK_STATE_FIELDS, "$.progression.task_states[%d]" % index)
	if not shape_result.is_success():
		return shape_result
	if typeof(task_state["day_index"]) != TYPE_INT or int(task_state["day_index"]) != index + 1 or typeof(task_state["task_id"]) != TYPE_STRING or String(task_state["task_id"]).is_empty() or typeof(task_state["state"]) != TYPE_STRING:
		return _reject(&"progression_task_state_invalid", "task state identity or state is invalid", "$.progression.task_states[%d]" % index)
	return DomainResult.success(task_state)

func _validate_summary(progression: Dictionary[String, Variant], replay: Dictionary[String, Variant]) -> DomainResult:
	for field_name: String in ["reputation", "d_total", "o_days"]:
		if not progression.has(field_name) or typeof(progression[field_name]) != TYPE_INT:
			return _reject(&"progression_summary_invalid", "progression totals must be integers", "$.progression.%s" % field_name)
	if int(progression["reputation"]) != int(replay["reputation"]) or int(progression["d_total"]) != int(replay["d_total"]) or int(progression["o_days"]) != int(replay["o_days"]):
		return _reject(&"progression_summary_replay_invalid", "progression totals must equal the replayed records", "$.progression")
	if int(replay["d_total"]) < 0 or int(replay["d_total"]) > 36 or int(replay["o_days"]) < 0 or int(replay["o_days"]) > _DAY_COUNT:
		return _reject(&"progression_summary_bounds_invalid", "replayed totals are outside their stable bounds", "$.progression")
	return DomainResult.success(true)

func _validate_active(progression: Dictionary[String, Variant], task_states: Array[Variant], records: Array[Variant]) -> DomainResult:
	var current_day_result: DomainResult = _active_day(progression, records.size())
	if not current_day_result.is_success():
		return current_day_result
	if records.size() == _DAY_COUNT:
		return _reject(&"progression_active_record_count_invalid", "active progression requires zero through four daily records", "$.progression.daily_records")
	var current_day: int = int(current_day_result.value())
	if not progression.has("assignment_complete") or typeof(progression["assignment_complete"]) != TYPE_BOOL or bool(progression["assignment_complete"]):
		return _reject(&"progression_active_completion_invalid", "active progression cannot be complete", "$.progression.assignment_complete")
	if not progression.has("workday"):
		return _reject(&"progression_active_workday_missing", "active progression requires a stable Workday", "$.progression.workday")
	var workday_result: DomainResult = _validate_workday(progression["workday"])
	if not workday_result.is_success():
		return workday_result
	for index: int in range(_DAY_COUNT):
		var task_state_result: DomainResult = _active_task_state(task_states[index], index, current_day)
		if not task_state_result.is_success():
			return task_state_result
	return _validate_active_current_task_and_outcome(progression, task_states, current_day)

func _validate_active_current_task_and_outcome(progression: Dictionary[String, Variant], task_states: Array[Variant], current_day: int) -> DomainResult:
	var current_task: Dictionary[String, Variant] = _copy_dictionary(task_states[current_day - 1])
	if not progression.has("current_task_id") or typeof(progression["current_task_id"]) != TYPE_STRING or String(progression["current_task_id"]) != String(current_task["task_id"]):
		return _reject(&"progression_current_task_invalid", "current_task_id must restore the active task", "$.progression.current_task_id")
	if progression.has("final_outcome"):
		return _reject(&"progression_active_outcome_invalid", "active progression cannot contain a final outcome", "$.progression.final_outcome")
	return DomainResult.success(true)

func _active_day(progression: Dictionary[String, Variant], record_count: int) -> DomainResult:
	if not progression.has("current_day_index") or typeof(progression["current_day_index"]) != TYPE_INT or int(progression["current_day_index"]) != record_count + 1:
		return _reject(&"progression_active_day_invalid", "active progression must restore the day after its stored records", "$.progression.current_day_index")
	return DomainResult.success(int(progression["current_day_index"]))

func _active_task_state(value: Variant, index: int, current_day: int) -> DomainResult:
	var task_state: Dictionary[String, Variant] = _copy_dictionary(value)
	var state: String = String(task_state["state"])
	if index < current_day - 1 and state != "completed":
		return _reject(&"progression_active_task_state_invalid", "earlier active tasks must be completed", "$.progression.task_states[%d]" % index)
	if index == current_day - 1 and not _ACTIVE_TASK_STATES.has(state):
		return _reject(&"progression_active_task_state_invalid", "the current active task must be editable or rework_due", "$.progression.task_states[%d]" % index)
	if index > current_day - 1 and state != "locked":
		return _reject(&"progression_active_task_state_invalid", "later active tasks must be locked", "$.progression.task_states[%d]" % index)
	return DomainResult.success(true)

func _validate_finalized(progression: Dictionary[String, Variant], task_states: Array[Variant], records: Array[Variant]) -> DomainResult:
	if records.size() != _DAY_COUNT:
		return _reject(&"progression_finalized_record_count_invalid", "finalized progression requires five daily records", "$.progression.daily_records")
	if not progression.has("assignment_complete") or typeof(progression["assignment_complete"]) != TYPE_BOOL or not bool(progression["assignment_complete"]):
		return _reject(&"progression_finalized_completion_invalid", "finalized progression must be complete", "$.progression.assignment_complete")
	if progression.has("workday"):
		return _reject(&"progression_finalized_workday_invalid", "finalized progression cannot contain a current Workday", "$.progression.workday")
	if not progression.has("final_outcome") or typeof(progression["final_outcome"]) != TYPE_STRING or not _OUTCOME_IDS.has(String(progression["final_outcome"])):
		return _reject(&"progression_final_outcome_invalid", "finalized progression requires an accepted Career outcome", "$.progression.final_outcome")
	if not progression.has("current_day_index") or typeof(progression["current_day_index"]) != TYPE_INT or int(progression["current_day_index"]) != _DAY_COUNT:
		return _reject(&"progression_finalized_day_invalid", "finalized progression must retain Day 5 identity", "$.progression.current_day_index")
	for index: int in range(_DAY_COUNT):
		var task_state: Dictionary[String, Variant] = _copy_dictionary(task_states[index])
		if String(task_state["state"]) != "completed":
			return _reject(&"progression_finalized_task_state_invalid", "finalized progression requires five completed task states", "$.progression.task_states[%d]" % index)
	var final_task: Dictionary[String, Variant] = _copy_dictionary(task_states[_DAY_COUNT - 1])
	if not progression.has("current_task_id") or typeof(progression["current_task_id"]) != TYPE_STRING or String(progression["current_task_id"]) != String(final_task.get("task_id", "")):
		return _reject(&"progression_finalized_task_invalid", "finalized progression must retain its fifth task identity", "$.progression.current_task_id")
	return DomainResult.success(true)

func _validate_workday(value: Variant) -> DomainResult:
	var workday_result: DomainResult = _workday_from_variant(value)
	if not workday_result.is_success():
		return workday_result
	var workday: Dictionary[String, Variant] = _copy_dictionary(workday_result.value())
	var fields_result: DomainResult = _validate_workday_fields(workday)
	if not fields_result.is_success():
		return fields_result
	if String(workday["state"]) == "charged_action_recovery":
		return _validate_recovery_action(workday["recovery_action"])
	return DomainResult.success(true)

func _workday_from_variant(value: Variant) -> DomainResult:
	if typeof(value) != TYPE_DICTIONARY:
		return _reject(&"progression_workday_invalid", "active Workday must be a dictionary", "$.progression.workday")
	var workday: Dictionary[String, Variant] = _copy_dictionary(value)
	if not workday.has("state") or typeof(workday["state"]) != TYPE_STRING or not _WORKDAY_STATES.has(String(workday["state"])):
		return _reject(&"progression_workday_invalid", "active Workday is outside its stable domain", "$.progression.workday.state")
	var expected_fields: Array[String] = _WORKDAY_FIELDS.duplicate()
	if String(workday["state"]) == "charged_action_recovery":
		expected_fields.append("recovery_action")
	var shape_result: DomainResult = _validate_exact_fields(workday, expected_fields, "$.progression.workday")
	if not shape_result.is_success():
		return shape_result
	return DomainResult.success(workday)

func _validate_workday_fields(workday: Dictionary[String, Variant]) -> DomainResult:
	if typeof(workday["elapsed_minutes"]) != TYPE_INT or int(workday["elapsed_minutes"]) < 0 or int(workday["elapsed_minutes"]) > 600 or typeof(workday["overtime_authorized"]) != TYPE_BOOL or typeof(workday["pending_rework_minutes"]) != TYPE_INT or not [0, 60].has(int(workday["pending_rework_minutes"])):
		return _reject(&"progression_workday_invalid", "active Workday is outside its stable domain", "$.progression.workday")
	return DomainResult.success(true)

func _validate_recovery_action(recovery_value: Variant) -> DomainResult:
	if typeof(recovery_value) != TYPE_DICTIONARY:
		return _reject(&"progression_recovery_action_invalid", "charged-action recovery requires a recovery action", "$.progression.workday.recovery_action")
	var recovery_action: Dictionary[String, Variant] = _copy_dictionary(recovery_value)
	var recovery_shape_result: DomainResult = _validate_exact_fields(recovery_action, _RECOVERY_ACTION_FIELDS, "$.progression.workday.recovery_action")
	if not recovery_shape_result.is_success():
		return recovery_shape_result
	if typeof(recovery_action["action_kind"]) != TYPE_STRING or String(recovery_action["action_kind"]).is_empty() or typeof(recovery_action["charged_minutes"]) != TYPE_INT or int(recovery_action["charged_minutes"]) < 0 or int(recovery_action["charged_minutes"]) > 600:
		return _reject(&"progression_recovery_action_invalid", "charged-action recovery fields are outside the stable domain", "$.progression.workday.recovery_action")
	var graph_revision: Variant = recovery_action["graph_revision"]
	if not ((typeof(graph_revision) == TYPE_INT and int(graph_revision) >= 0) or (typeof(graph_revision) == TYPE_STRING and not String(graph_revision).is_empty())):
		return _reject(&"progression_recovery_action_invalid", "charged-action recovery requires a valid graph revision", "$.progression.workday.recovery_action.graph_revision")
	return DomainResult.success(true)

func _validate_exact_fields(candidate: Dictionary[String, Variant], expected_fields: Array[String], path: String) -> DomainResult:
	if candidate.size() != expected_fields.size():
		return _reject(&"progression_record_shape_invalid", "record fields do not match the frozen stable roster", path)
	for field_name: String in expected_fields:
		if not candidate.has(field_name):
			return _reject(&"progression_record_shape_invalid", "record fields do not match the frozen stable roster", path)
	return DomainResult.success(true)

func _copy_dictionary(value: Variant) -> Dictionary[String, Variant]:
	var copy: Dictionary[String, Variant] = {}
	if typeof(value) != TYPE_DICTIONARY:
		return copy
	for raw_key: Variant in value.keys():
		if typeof(raw_key) != TYPE_STRING:
			return {}
		copy[String(raw_key)] = value[raw_key]
	return copy.duplicate(true)

func _copy_array(value: Variant) -> Array[Variant]:
	var copy: Array[Variant] = []
	if typeof(value) != TYPE_ARRAY:
		return copy
	for item: Variant in value:
		copy.append(item)
	return copy.duplicate(true)

func _reject(error_code: StringName, message: String, path: String) -> DomainResult:
	return DomainResult.failure(error_code, message, path)
