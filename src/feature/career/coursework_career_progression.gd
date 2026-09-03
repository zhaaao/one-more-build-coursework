class_name CourseworkCareerProgression
extends RefCounted

## Synchronous Career reducer for settled Workday facts.
## Implements career-progression-and-evaluation.md Sections 3, 4, 6, 7, and 8.

const COURSEWORK_CAREER_POLICY = preload("res://src/feature/career/coursework_career_policy.gd")
const FOUNDATION_REDUCER = preload("res://src/foundation/foundation_reducer.gd")
const ACCEPTED_EVENT = preload("res://src/foundation/accepted_event.gd")
const CANONICAL_CODEC = preload("res://src/foundation/canonical_codec.gd")

const DAILY_FACT_KEY: StringName = &"career.daily_fact"
const RECOVERY_PROJECTION_VERSION: String = "coursework.career.recovery.v1"
const _DAY_COUNT: int = 5
const _MAX_OVERTIME_MINUTES: int = 120
const _FINAL_REVIEW_MINUTES: int = 60
const _REMEDIATION_NONE: String = "none"
const _REMEDIATION_NEXT_DAY: String = "scheduled_next_day"
const _REMEDIATION_FINAL_REVIEW: String = "final_review_outstanding"
const _CAREER_STATE_FINALIZED: String = "finalized"
const _OUTCOME_RELIABLE_ENGINEER: String = "career.outcome.reliable_engineer"
const _OUTCOME_NEEDS_GUIDANCE: String = "career.outcome.needs_guidance"
const _OUTCOME_FIREFIGHTER: String = "career.outcome.firefighter"
const _FACT_KEYS: Array[String] = ["day_index", "task_id", "failure_count", "failed_case_ids", "overtime_minutes", "overtime_day", "remediation_state", "receipt_id"]
const _PROJECTION_KEYS: Array[String] = ["projection_version", "career_identity", "career_state", "next_day", "eligible_task_id", "reputation", "D_total", "O_days", "feedback_band", "records", "final_outcome"]
const _RECORD_KEYS: Array[String] = ["day_index", "task_id", "receipt_id", "failure_count", "failed_case_ids", "overtime_minutes", "overtime_day", "remediation_state", "reputation_before", "rule_delta", "applied_delta", "reputation_after", "feedback_band"]

var _snapshot: Dictionary[String, Variant] = COURSEWORK_CAREER_POLICY.start_new_career()
var _foundation: FOUNDATION_REDUCER = FOUNDATION_REDUCER.new()
var _facts_by_receipt: Dictionary[String, Variant] = {}
var _records_by_receipt: Dictionary[String, Variant] = {}
var _career_generation: int = 1

## Validates and commits one full fact, returning its AcceptedEvent and Career record.
func admit_settled_workday_fact(fact_value: Variant, command_career_identity: String = "") -> DomainResult:
	var fact: Dictionary[String, Variant] = _copy_dictionary(fact_value)
	var shape_result: DomainResult = _validate_fact_shape(fact)
	if not shape_result.is_success():
		return shape_result
	var identity_result: DomainResult = _validate_command_career_identity(command_career_identity)
	if not identity_result.is_success():
		return identity_result
	var receipt_id: String = String(fact["receipt_id"])
	if not _facts_by_receipt.has(receipt_id):
		var state_result: DomainResult = _validate_new_fact_against_state(fact)
		if not state_result.is_success():
			return state_result
	var committed: DomainResult = _foundation.commit(StringName(receipt_id), DAILY_FACT_KEY, fact)
	if not committed.is_success():
		return committed
	return reduce(committed.value(), command_career_identity)

## Accepts an ordered Foundation event and atomically applies its Career fact.
func reduce(event: ACCEPTED_EVENT, command_career_identity: String = "") -> DomainResult:
	var event_result: DomainResult = _validate_event(event)
	if not event_result.is_success():
		return event_result
	var identity_result: DomainResult = _validate_command_career_identity(command_career_identity)
	if not identity_result.is_success():
		return identity_result
	var fact: Dictionary[String, Variant] = event_result.value()
	var receipt_id: String = String(fact["receipt_id"])
	if _facts_by_receipt.has(receipt_id):
		return _replay_event_or_reject_conflict(event, fact)
	var state_result: DomainResult = _validate_new_fact_against_state(fact)
	if not state_result.is_success():
		return state_result
	var accepted: DomainResult = _foundation.accept(event)
	if not accepted.is_success():
		return accepted
	return _apply_accepted_fact(accepted.value(), fact)

## Returns the next Foundation sequence expected by this Career owner.
func next_event_sequence() -> String:
	return _foundation.next_sequence()

## Returns a detached immutable projection of current Career truth.
func snapshot() -> Dictionary[String, Variant]:
	return _snapshot.duplicate(true)

## Returns canonical snapshot bytes or a canonical-codec diagnostic.
func stable_snapshot_bytes() -> DomainResult:
	var encoded: DomainResult = CANONICAL_CODEC.encode(stable_projection())
	if not encoded.is_success():
		return encoded
	return DomainResult.success(PackedByteArray(encoded.value()))

## Exports the complete validated Career summary supplied to SavePort.
func stable_projection() -> Dictionary[String, Variant]:
	var projection: Dictionary[String, Variant] = _canonical_snapshot()
	projection["projection_version"] = RECOVERY_PROJECTION_VERSION
	if String(projection["career_state"]) == "active" and projection["records"].is_empty():
		var catalogue: Array[Variant] = COURSEWORK_CAREER_POLICY.ordered_task_catalogue()
		projection["next_day"] = 1
		projection["eligible_task_id"] = String(catalogue[0]["task_id"])
	projection["career_identity"] = _career_identity()
	return projection.duplicate(true)

## Replaces Career only after the whole stable projection passes strict validation.
func restore_stable_projection(candidate_value: Variant) -> DomainResult:
	var validation: DomainResult = _validate_stable_projection(candidate_value)
	if not validation.is_success():
		return validation
	var replacement: Dictionary[String, Variant] = _copy_dictionary(validation.value())
	var replacement_foundation: FOUNDATION_REDUCER = FOUNDATION_REDUCER.new()
	var replacement_facts: Dictionary[String, Variant] = _copy_dictionary(replacement["facts_by_receipt"])
	# Hydrate only the ordered Foundation fence after whole-projection validation; Career facts are never reduced here.
	var replacement_records: Array[Variant] = _copy_dictionary(replacement["snapshot"])["records"]
	for record_value: Variant in replacement_records:
		var record: Dictionary[String, Variant] = _copy_dictionary(record_value)
		var receipt_id: String = String(record["receipt_id"])
		var accepted: DomainResult = replacement_foundation.commit(StringName(receipt_id), DAILY_FACT_KEY, replacement_facts[receipt_id])
		if not accepted.is_success():
			return _reject(&"career_projection_foundation_invalid", "a validated projection could not restore its event sequence")
	_snapshot = _copy_dictionary(replacement["snapshot"])
	_facts_by_receipt = replacement_facts.duplicate(true)
	_records_by_receipt = _copy_dictionary(replacement["records_by_receipt"])
	_foundation = replacement_foundation
	_career_generation = int(replacement["career_generation"])
	return DomainResult.success(snapshot())

## Cancelling preserves Career exactly; confirmation starts a fresh receipt identity.
func reset_career(confirmed: bool) -> DomainResult:
	if not confirmed:
		return DomainResult.success({"reset": false, "career_identity": _career_identity()})
	_snapshot = COURSEWORK_CAREER_POLICY.start_new_career()
	_foundation = FOUNDATION_REDUCER.new()
	_facts_by_receipt = {}
	_records_by_receipt = {}
	_career_generation += 1
	return DomainResult.success({"reset": true, "career_identity": _career_identity()})

## Returns the current receipt-admission identity; reset and an admitted restore
## establish this identity, so commands bearing an older identity are rejected.
func career_identity() -> String:
	return _career_identity()

func _validate_event(event: ACCEPTED_EVENT) -> DomainResult:
	if event == null or not event.is_valid():
		return _reject(&"career_event_invalid", "a valid AcceptedEvent is required")
	if event.key() != DAILY_FACT_KEY:
		return _reject(&"career_event_key_invalid", "event key is not the Career daily-fact key")
	var fact: Dictionary[String, Variant] = _copy_dictionary(event.value())
	var shape_result: DomainResult = _validate_fact_shape(fact)
	if not shape_result.is_success():
		return shape_result
	if event.command_id() != StringName(String(fact["receipt_id"])):
		return _reject(&"career_event_command_invalid", "event command id must equal the fact receipt id")
	return DomainResult.success(fact)

func _validate_fact_shape(fact: Dictionary[String, Variant]) -> DomainResult:
	var keys_result: DomainResult = _validate_fact_keys(fact)
	if not keys_result.is_success():
		return keys_result
	var types_result: DomainResult = _validate_fact_types(fact)
	if not types_result.is_success():
		return types_result
	var day_result: DomainResult = _validate_day_and_task(fact)
	if not day_result.is_success():
		return day_result
	var failed_ids_result: DomainResult = _validate_failed_case_ids(fact)
	if not failed_ids_result.is_success():
		return failed_ids_result
	var overtime_result: DomainResult = _validate_overtime(fact)
	if not overtime_result.is_success():
		return overtime_result
	return _validate_remediation_and_receipt(fact)

func _validate_fact_keys(fact: Dictionary[String, Variant]) -> DomainResult:
	if fact.size() != _FACT_KEYS.size():
		return _reject(&"career_fact_invalid", "a settled fact must contain exactly the required fields")
	for key: String in _FACT_KEYS:
		if not fact.has(key):
			return _reject(&"career_fact_invalid", "a settled fact is missing a required field")
	return DomainResult.success(true)

func _validate_fact_types(fact: Dictionary[String, Variant]) -> DomainResult:
	if typeof(fact["day_index"]) != TYPE_INT or typeof(fact["task_id"]) != TYPE_STRING:
		return _reject(&"career_fact_invalid", "day and task fields have invalid types")
	if typeof(fact["failure_count"]) != TYPE_INT or typeof(fact["failed_case_ids"]) != TYPE_ARRAY:
		return _reject(&"career_fact_invalid", "failure fields have invalid types")
	if typeof(fact["overtime_minutes"]) != TYPE_INT or typeof(fact["overtime_day"]) != TYPE_BOOL:
		return _reject(&"career_fact_invalid", "overtime fields have invalid types")
	if typeof(fact["remediation_state"]) != TYPE_STRING or typeof(fact["receipt_id"]) != TYPE_STRING:
		return _reject(&"career_fact_invalid", "remediation and receipt fields have invalid types")
	return DomainResult.success(true)

func _validate_day_and_task(fact: Dictionary[String, Variant]) -> DomainResult:
	var day_index: int = int(fact["day_index"])
	if day_index < 1 or day_index > _DAY_COUNT:
		return _reject(&"career_fact_day_invalid", "a settled fact day must be within the five-day career")
	var catalogue: Array[Variant] = COURSEWORK_CAREER_POLICY.ordered_task_catalogue()
	var entry: Dictionary[String, Variant] = catalogue[day_index - 1]
	if String(fact["task_id"]) != String(entry["task_id"]):
		return _reject(&"career_fact_task_invalid", "a settled fact task must match its Career day")
	var failure_count: int = int(fact["failure_count"])
	if failure_count < 0 or failure_count > int(entry["public_case_bound"]):
		return _reject(&"career_fact_failure_count_invalid", "failure count exceeds the daily public-case bound")
	return DomainResult.success(true)

func _validate_failed_case_ids(fact: Dictionary[String, Variant]) -> DomainResult:
	var ids: Array[String] = []
	var seen: Dictionary[String, bool] = {}
	for raw_id: Variant in fact["failed_case_ids"]:
		if typeof(raw_id) != TYPE_STRING or String(raw_id).is_empty() or seen.has(String(raw_id)):
			return _reject(&"career_fact_failed_case_ids_invalid", "failed case IDs must be unique non-empty strings")
		seen[String(raw_id)] = true
		ids.append(String(raw_id))
	if ids.size() != int(fact["failure_count"]):
		return _reject(&"career_fact_failed_case_ids_invalid", "failed case IDs must equal the stated failure count")
	return DomainResult.success(true)

func _validate_overtime(fact: Dictionary[String, Variant]) -> DomainResult:
	var overtime_minutes: int = int(fact["overtime_minutes"])
	if overtime_minutes < 0 or overtime_minutes > _MAX_OVERTIME_MINUTES:
		return _reject(&"career_fact_overtime_invalid", "overtime minutes must be within the daily range")
	if bool(fact["overtime_day"]) != (overtime_minutes > 0):
		return _reject(&"career_fact_overtime_invalid", "overtime fields must agree")
	return DomainResult.success(true)

func _validate_remediation_and_receipt(fact: Dictionary[String, Variant]) -> DomainResult:
	var expected: String = _expected_remediation(int(fact["day_index"]), int(fact["failure_count"]))
	if String(fact["remediation_state"]) != expected:
		return _reject(&"career_fact_remediation_invalid", "remediation state must match settled defect facts")
	if String(fact["receipt_id"]).is_empty():
		return _reject(&"career_fact_receipt_invalid", "a settled fact requires a stable receipt identity")
	return DomainResult.success(true)

func _validate_new_fact_against_state(fact: Dictionary[String, Variant]) -> DomainResult:
	if String(_snapshot.get("career_state", "")) != "active":
		return _reject(&"career_fact_career_finalized", "a finalized Career cannot admit another fact")
	if int(fact["day_index"]) != int(_snapshot.get("next_day", 0)):
		return _reject(&"career_fact_day_order_invalid", "a settled fact must be admitted for the next Career day")
	return DomainResult.success(true)

func _replay_event_or_reject_conflict(event: ACCEPTED_EVENT, fact: Dictionary[String, Variant]) -> DomainResult:
	var receipt_id: String = String(fact["receipt_id"])
	var existing_fact: Dictionary[String, Variant] = _copy_dictionary(_facts_by_receipt[receipt_id])
	if existing_fact != fact:
		return _reject(&"duplicate_conflict", "a receipt identity cannot be rebound to another fact")
	var accepted: DomainResult = _foundation.accept(event)
	if not accepted.is_success():
		return accepted
	var record: Dictionary[String, Variant] = _copy_dictionary(_records_by_receipt[receipt_id])
	return _accepted_fact_result(true, accepted.value(), record)

func _apply_accepted_fact(event: ACCEPTED_EVENT, fact: Dictionary[String, Variant]) -> DomainResult:
	var day_index: int = int(fact["day_index"])
	var previous_reputation: int = int(_snapshot["reputation"])
	var consequence: Dictionary[String, Variant] = COURSEWORK_CAREER_POLICY.calculate_daily_consequence(previous_reputation, int(fact["failure_count"]))
	var next_snapshot: Dictionary[String, Variant] = _snapshot.duplicate(true)
	var records: Array[Variant] = next_snapshot["records"].duplicate(true)
	var record: Dictionary[String, Variant] = _record_from_fact(fact, previous_reputation, consequence)
	next_snapshot["reputation"] = int(consequence["final_reputation"])
	next_snapshot["D_total"] = int(next_snapshot["D_total"]) + int(fact["failure_count"])
	next_snapshot["O_days"] = int(next_snapshot["O_days"]) + (1 if bool(fact["overtime_day"]) else 0)
	records.append(record.duplicate(true))
	next_snapshot["records"] = records
	next_snapshot["feedback_band"] = String(record["feedback_band"])
	if day_index < _DAY_COUNT:
		var catalogue: Array[Variant] = COURSEWORK_CAREER_POLICY.ordered_task_catalogue()
		next_snapshot["next_day"] = day_index + 1
		next_snapshot["eligible_task_id"] = String(catalogue[day_index]["task_id"])
	else:
		_evaluate_final_outcome(next_snapshot)
		next_snapshot["career_state"] = _CAREER_STATE_FINALIZED
		next_snapshot.erase("next_day")
		next_snapshot.erase("eligible_task_id")
	_snapshot = next_snapshot.duplicate(true)
	_facts_by_receipt[String(fact["receipt_id"])] = fact.duplicate(true)
	_records_by_receipt[String(fact["receipt_id"])] = record.duplicate(true)
	return _accepted_fact_result(false, event, record)

func _record_from_fact(fact: Dictionary[String, Variant], previous_reputation: int, consequence: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
	var failed_case_ids: Array[String] = []
	for raw_id: Variant in fact["failed_case_ids"]:
		failed_case_ids.append(String(raw_id))
	var reputation_after: int = int(consequence["final_reputation"])
	return {"day_index": int(fact["day_index"]), "task_id": String(fact["task_id"]), "receipt_id": String(fact["receipt_id"]), "failure_count": int(fact["failure_count"]), "failed_case_ids": failed_case_ids, "overtime_minutes": int(fact["overtime_minutes"]), "overtime_day": bool(fact["overtime_day"]), "remediation_state": String(fact["remediation_state"]), "reputation_before": previous_reputation, "rule_delta": int(consequence["rule_delta"]), "applied_delta": int(consequence["applied_delta"]), "reputation_after": reputation_after, "feedback_band": COURSEWORK_CAREER_POLICY.feedback_band_for_reputation(reputation_after)}

func _evaluate_final_outcome(next_snapshot: Dictionary[String, Variant]) -> void:
	next_snapshot["final_outcome"] = _final_outcome_snapshot(next_snapshot)

func _final_outcome_snapshot(snapshot: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
	var records: Array[Variant] = snapshot["records"].duplicate(true)
	var day_five_record: Dictionary[String, Variant] = _copy_dictionary(records[_DAY_COUNT - 1])
	return {
		"outcome_id": _outcome_id_for_totals(int(snapshot["reputation"]), int(snapshot["D_total"]), int(snapshot["O_days"])),
		"final_reputation": int(snapshot["reputation"]),
		"D_total": int(snapshot["D_total"]),
		"O_days": int(snapshot["O_days"]),
		"records": records,
		"day5_remediation_state": String(day_five_record["remediation_state"]),
		"final_review_minutes": _final_review_minutes(day_five_record),
	}

func _outcome_id_for_totals(final_reputation: int, defect_total: int, overtime_days: int) -> String:
	if final_reputation >= 70 and defect_total <= 2 and overtime_days <= 2:
		return _OUTCOME_RELIABLE_ENGINEER
	if final_reputation < 40 or defect_total >= 8:
		return _OUTCOME_NEEDS_GUIDANCE
	return _OUTCOME_FIREFIGHTER

func _final_review_minutes(day_five_record: Dictionary[String, Variant]) -> int:
	if String(day_five_record["remediation_state"]) == _REMEDIATION_FINAL_REVIEW:
		return _FINAL_REVIEW_MINUTES
	return 0

func _accepted_fact_result(replayed: bool, event: ACCEPTED_EVENT, record: Dictionary[String, Variant]) -> DomainResult:
	var result: Dictionary[String, Variant] = {"replayed": replayed, "event": event, "record": record.duplicate(true)}
	if int(record["day_index"]) == _DAY_COUNT:
		result["final_outcome"] = _copy_dictionary(_snapshot["final_outcome"])
	return DomainResult.success(result)

func _canonical_snapshot() -> Dictionary[String, Variant]:
	var canonical_records: Array[Variant] = []
	for source_record: Variant in _snapshot.get("records", []):
		canonical_records.append(_copy_dictionary(source_record))
	return {"career_state": String(_snapshot.get("career_state", "")), "next_day": int(_snapshot.get("next_day", 0)), "eligible_task_id": String(_snapshot.get("eligible_task_id", "")), "reputation": int(_snapshot.get("reputation", 0)), "D_total": int(_snapshot.get("D_total", 0)), "O_days": int(_snapshot.get("O_days", 0)), "feedback_band": String(_snapshot.get("feedback_band", "")), "records": canonical_records, "final_outcome": _copy_dictionary(_snapshot.get("final_outcome", {}))}

func _validate_stable_projection(candidate_value: Variant) -> DomainResult:
	var candidate_result: DomainResult = _validate_projection_candidate_shape(candidate_value)
	if not candidate_result.is_success():
		return candidate_result
	var candidate: Dictionary[String, Variant] = _copy_dictionary(candidate_result.value())
	var identity_result: DomainResult = _validate_projection_identity(String(candidate["career_identity"]))
	if not identity_result.is_success():
		return identity_result
	var records_result: DomainResult = _validate_projection_records(candidate["records"])
	if not records_result.is_success():
		return records_result
	var stable_components: Dictionary[String, Variant] = _copy_dictionary(records_result.value())
	var snapshot_result: DomainResult = _validate_projection_aggregates_and_state(candidate, stable_components)
	if not snapshot_result.is_success():
		return snapshot_result
	return DomainResult.success({"snapshot": snapshot_result.value(), "facts_by_receipt": stable_components["facts_by_receipt"], "records_by_receipt": stable_components["records_by_receipt"], "career_generation": int(identity_result.value())})

func _validate_projection_candidate_shape(candidate_value: Variant) -> DomainResult:
	if typeof(candidate_value) != TYPE_DICTIONARY:
		return _reject(&"career_projection_invalid", "a stable Career projection must be a dictionary")
	var raw_candidate: Dictionary = candidate_value
	var raw_outcome_result: DomainResult = _validate_raw_projection_final_outcome_keys(raw_candidate)
	if not raw_outcome_result.is_success():
		return raw_outcome_result
	var candidate: Dictionary[String, Variant] = _copy_dictionary(candidate_value)
	var keys_result: DomainResult = _validate_projection_required_keys(candidate)
	if not keys_result.is_success():
		return keys_result
	var types_result: DomainResult = _validate_projection_field_types(candidate)
	if not types_result.is_success():
		return types_result
	return DomainResult.success(candidate)

func _validate_raw_projection_final_outcome_keys(raw_candidate: Dictionary) -> DomainResult:
	if not raw_candidate.has("final_outcome") or typeof(raw_candidate["final_outcome"]) != TYPE_DICTIONARY:
		return DomainResult.success(true)
	for raw_key: Variant in raw_candidate["final_outcome"].keys():
		if typeof(raw_key) != TYPE_STRING:
			return _reject(&"career_projection_outcome_invalid", "a final outcome cannot contain non-string keys")
	return DomainResult.success(true)

func _validate_projection_required_keys(candidate: Dictionary[String, Variant]) -> DomainResult:
	if candidate.size() != _PROJECTION_KEYS.size():
		return _reject(&"career_projection_invalid", "a stable Career projection must contain exactly the required fields")
	for key: String in _PROJECTION_KEYS:
		if not candidate.has(key):
			return _reject(&"career_projection_invalid", "a stable Career projection is missing a required field")
	return DomainResult.success(true)

func _validate_projection_field_types(candidate: Dictionary[String, Variant]) -> DomainResult:
	if typeof(candidate["projection_version"]) != TYPE_STRING or String(candidate["projection_version"]) != RECOVERY_PROJECTION_VERSION:
		return _reject(&"career_projection_version_unsupported", "Career recovery projection version is unsupported")
	var identity_result: DomainResult = _validate_projection_identity_and_state_types(candidate)
	if not identity_result.is_success():
		return identity_result
	var active_day_result: DomainResult = _validate_projection_active_day_field_types(candidate)
	if not active_day_result.is_success():
		return active_day_result
	var aggregate_result: DomainResult = _validate_projection_aggregate_field_types(candidate)
	if not aggregate_result.is_success():
		return aggregate_result
	return _validate_projection_stable_field_types(candidate)

func _validate_projection_identity_and_state_types(candidate: Dictionary[String, Variant]) -> DomainResult:
	if typeof(candidate["career_identity"]) != TYPE_STRING or typeof(candidate["career_state"]) != TYPE_STRING:
		return _reject(&"career_projection_invalid", "Career projection identity and state must be strings")
	return DomainResult.success(true)

func _validate_projection_active_day_field_types(candidate: Dictionary[String, Variant]) -> DomainResult:
	if typeof(candidate["next_day"]) != TYPE_INT or typeof(candidate["eligible_task_id"]) != TYPE_STRING:
		return _reject(&"career_projection_invalid", "Career projection active-day fields have invalid types")
	return DomainResult.success(true)

func _validate_projection_aggregate_field_types(candidate: Dictionary[String, Variant]) -> DomainResult:
	if typeof(candidate["reputation"]) != TYPE_INT or typeof(candidate["D_total"]) != TYPE_INT or typeof(candidate["O_days"]) != TYPE_INT:
		return _reject(&"career_projection_invalid", "Career projection aggregate fields have invalid types")
	return DomainResult.success(true)

func _validate_projection_stable_field_types(candidate: Dictionary[String, Variant]) -> DomainResult:
	if typeof(candidate["feedback_band"]) != TYPE_STRING or typeof(candidate["records"]) != TYPE_ARRAY or typeof(candidate["final_outcome"]) != TYPE_DICTIONARY:
		return _reject(&"career_projection_invalid", "Career projection stable fields have invalid types")
	return DomainResult.success(true)

func _validate_projection_identity(identity: String) -> DomainResult:
	var generation_result: DomainResult = _generation_from_identity(identity)
	if not generation_result.is_success():
		return generation_result
	var candidate_generation: int = int(generation_result.value())
	if candidate_generation < _career_generation:
		return _reject(&"career_projection_identity_stale", "a stable Career projection cannot roll back the current Career identity")
	return DomainResult.success(candidate_generation)

func _validate_projection_records(records_value: Variant) -> DomainResult:
	var records: Array[Variant] = records_value
	if records.size() > _DAY_COUNT:
		return _reject(&"career_projection_records_invalid", "a Career projection cannot contain more than five records")
	var initial_snapshot: Dictionary[String, Variant] = COURSEWORK_CAREER_POLICY.start_new_career()
	var previous_reputation: int = int(initial_snapshot["reputation"])
	var total_failures: int = 0
	var total_overtime_days: int = 0
	var expected_feedback_band: String = String(initial_snapshot.get("feedback_band", ""))
	var facts_by_receipt: Dictionary[String, Variant] = {}
	var records_by_receipt: Dictionary[String, Variant] = {}
	var normalized_records: Array[Variant] = []
	for record_index: int in range(records.size()):
		var record_result: DomainResult = _validate_projection_record(records[record_index], record_index + 1, previous_reputation)
		if not record_result.is_success():
			return record_result
		var record: Dictionary[String, Variant] = record_result.value()
		var receipt_id: String = String(record["receipt_id"])
		if facts_by_receipt.has(receipt_id):
			return _reject(&"career_projection_duplicate_receipt", "a Career projection cannot contain duplicate receipt identities")
		var fact: Dictionary[String, Variant] = _fact_from_record(record)
		facts_by_receipt[receipt_id] = fact.duplicate(true)
		records_by_receipt[receipt_id] = record.duplicate(true)
		normalized_records.append(record.duplicate(true))
		previous_reputation = int(record["reputation_after"])
		total_failures += int(record["failure_count"])
		total_overtime_days += 1 if bool(record["overtime_day"]) else 0
		expected_feedback_band = String(record["feedback_band"])
	return DomainResult.success({"records": normalized_records, "facts_by_receipt": facts_by_receipt, "records_by_receipt": records_by_receipt, "reputation": previous_reputation, "D_total": total_failures, "O_days": total_overtime_days, "feedback_band": expected_feedback_band})

func _validate_projection_aggregates_and_state(candidate: Dictionary[String, Variant], stable_components: Dictionary[String, Variant]) -> DomainResult:
	var final_reputation: int = int(stable_components["reputation"])
	var total_failures: int = int(stable_components["D_total"])
	var total_overtime_days: int = int(stable_components["O_days"])
	var expected_feedback_band: String = String(stable_components["feedback_band"])
	var normalized_records: Array[Variant] = stable_components["records"]
	if int(candidate["reputation"]) != final_reputation or int(candidate["D_total"]) != total_failures or int(candidate["O_days"]) != total_overtime_days:
		return _reject(&"career_projection_aggregate_invalid", "Career projection totals must match every accepted record")
	if String(candidate["feedback_band"]) != expected_feedback_band:
		return _reject(&"career_projection_feedback_invalid", "Career projection feedback must match its final reputation")
	var normalized_snapshot: Dictionary[String, Variant] = {
		"career_state": String(candidate["career_state"]),
		"next_day": int(candidate["next_day"]),
		"eligible_task_id": String(candidate["eligible_task_id"]),
		"reputation": final_reputation,
		"D_total": total_failures,
		"O_days": total_overtime_days,
		"feedback_band": expected_feedback_band,
		"records": normalized_records,
		"final_outcome": _copy_dictionary(candidate["final_outcome"]),
	}
	var state_result: DomainResult = _validate_projection_state(normalized_snapshot)
	if not state_result.is_success():
		return state_result
	return DomainResult.success(normalized_snapshot)

func _validate_projection_record(record_value: Variant, expected_day: int, previous_reputation: int) -> DomainResult:
	var shape_result: DomainResult = _validate_projection_record_shape(record_value)
	if not shape_result.is_success():
		return shape_result
	var record: Dictionary[String, Variant] = _copy_dictionary(shape_result.value())
	var fact_result: DomainResult = _validate_projection_record_fact(record, expected_day)
	if not fact_result.is_success():
		return fact_result
	var consequence_result: DomainResult = _validate_projection_record_consequence(record, previous_reputation)
	if not consequence_result.is_success():
		return consequence_result
	return DomainResult.success(record.duplicate(true))

func _validate_projection_record_shape(record_value: Variant) -> DomainResult:
	if typeof(record_value) != TYPE_DICTIONARY:
		return _reject(&"career_projection_record_invalid", "every Career record must be a dictionary")
	var record: Dictionary[String, Variant] = _copy_dictionary(record_value)
	var keys_result: DomainResult = _validate_projection_record_required_keys(record)
	if not keys_result.is_success():
		return keys_result
	var types_result: DomainResult = _validate_projection_record_field_types(record)
	if not types_result.is_success():
		return types_result
	return DomainResult.success(record)

func _validate_projection_record_required_keys(record: Dictionary[String, Variant]) -> DomainResult:
	if record.size() != _RECORD_KEYS.size():
		return _reject(&"career_projection_record_invalid", "every Career record must contain exactly the required fields")
	for key: String in _RECORD_KEYS:
		if not record.has(key):
			return _reject(&"career_projection_record_invalid", "a Career record is missing a required field")
	return DomainResult.success(true)

func _validate_projection_record_field_types(record: Dictionary[String, Variant]) -> DomainResult:
	var identity_result: DomainResult = _validate_projection_record_identity_field_types(record)
	if not identity_result.is_success():
		return identity_result
	var failure_result: DomainResult = _validate_projection_record_failure_field_types(record)
	if not failure_result.is_success():
		return failure_result
	var workday_result: DomainResult = _validate_projection_record_workday_field_types(record)
	if not workday_result.is_success():
		return workday_result
	return _validate_projection_record_consequence_field_types(record)

func _validate_projection_record_identity_field_types(record: Dictionary[String, Variant]) -> DomainResult:
	if typeof(record["day_index"]) != TYPE_INT or typeof(record["task_id"]) != TYPE_STRING or typeof(record["receipt_id"]) != TYPE_STRING:
		return _reject(&"career_projection_record_invalid", "Career record identity fields have invalid types")
	return DomainResult.success(true)

func _validate_projection_record_failure_field_types(record: Dictionary[String, Variant]) -> DomainResult:
	if typeof(record["failure_count"]) != TYPE_INT or typeof(record["failed_case_ids"]) != TYPE_ARRAY:
		return _reject(&"career_projection_record_invalid", "Career record failure fields have invalid types")
	return DomainResult.success(true)

func _validate_projection_record_workday_field_types(record: Dictionary[String, Variant]) -> DomainResult:
	if typeof(record["overtime_minutes"]) != TYPE_INT or typeof(record["overtime_day"]) != TYPE_BOOL or typeof(record["remediation_state"]) != TYPE_STRING:
		return _reject(&"career_projection_record_invalid", "Career record workday fields have invalid types")
	return DomainResult.success(true)

func _validate_projection_record_consequence_field_types(record: Dictionary[String, Variant]) -> DomainResult:
	if typeof(record["reputation_before"]) != TYPE_INT or typeof(record["rule_delta"]) != TYPE_INT or typeof(record["applied_delta"]) != TYPE_INT or typeof(record["reputation_after"]) != TYPE_INT or typeof(record["feedback_band"]) != TYPE_STRING:
		return _reject(&"career_projection_record_invalid", "Career record consequence fields have invalid types")
	return DomainResult.success(true)

func _validate_projection_record_fact(record: Dictionary[String, Variant], expected_day: int) -> DomainResult:
	if int(record["day_index"]) != expected_day:
		return _reject(&"career_projection_record_order_invalid", "Career records must be in consecutive day order")
	var fact: Dictionary[String, Variant] = _fact_from_record(record)
	var fact_result: DomainResult = _validate_fact_shape(fact)
	if not fact_result.is_success():
		return _reject(&"career_projection_record_invalid", "a Career projection record contains an invalid settled fact")
	return DomainResult.success(true)

func _validate_projection_record_consequence(record: Dictionary[String, Variant], previous_reputation: int) -> DomainResult:
	if int(record["reputation_before"]) != previous_reputation:
		return _reject(&"career_projection_record_invalid", "Career record reputation must chain from the prior record")
	var consequence: Dictionary[String, Variant] = COURSEWORK_CAREER_POLICY.calculate_daily_consequence(previous_reputation, int(record["failure_count"]))
	if int(record["rule_delta"]) != int(consequence["rule_delta"]) or int(record["applied_delta"]) != int(consequence["applied_delta"]) or int(record["reputation_after"]) != int(consequence["final_reputation"]):
		return _reject(&"career_projection_record_invalid", "Career record consequence must match its settled fact")
	if String(record["feedback_band"]) != COURSEWORK_CAREER_POLICY.feedback_band_for_reputation(int(record["reputation_after"])):
		return _reject(&"career_projection_record_invalid", "Career record feedback must match its settled reputation")
	return DomainResult.success(true)

func _validate_projection_state(candidate: Dictionary[String, Variant]) -> DomainResult:
	var records: Array[Variant] = candidate["records"]
	var career_state: String = String(candidate["career_state"])
	var catalogue: Array[Variant] = COURSEWORK_CAREER_POLICY.ordered_task_catalogue()
	if career_state == "active":
		if records.size() >= _DAY_COUNT:
			return _reject(&"career_projection_state_invalid", "a complete Career projection must be finalized")
		var expected_next_day: int = records.size() + 1
		if int(candidate["next_day"]) != expected_next_day:
			return _reject(&"career_projection_next_day_invalid", "an active Career projection must name its exact next day")
		if String(candidate["eligible_task_id"]) != String(catalogue[expected_next_day - 1]["task_id"]):
			return _reject(&"career_projection_eligible_task_invalid", "an active Career projection must name its exact next task")
		if not _copy_dictionary(candidate["final_outcome"]).is_empty():
			return _reject(&"career_projection_active_outcome_invalid", "an active Career projection cannot contain a final outcome")
		return DomainResult.success(true)
	if career_state != _CAREER_STATE_FINALIZED or records.size() != _DAY_COUNT:
		return _reject(&"career_projection_state_invalid", "a finalized Career projection must contain exactly five records")
	if int(candidate["next_day"]) != 0 or not String(candidate["eligible_task_id"]).is_empty():
		return _reject(&"career_projection_state_invalid", "a finalized Career projection cannot name a next day or task")
	var expected_outcome: Dictionary[String, Variant] = _final_outcome_snapshot(candidate)
	if _copy_dictionary(candidate["final_outcome"]) != expected_outcome:
		return _reject(&"career_projection_outcome_invalid", "a finalized Career projection outcome must match its stable records and totals")
	return DomainResult.success(true)

func _fact_from_record(record: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
	return {"day_index": int(record["day_index"]), "task_id": String(record["task_id"]), "failure_count": int(record["failure_count"]), "failed_case_ids": record["failed_case_ids"].duplicate(true), "overtime_minutes": int(record["overtime_minutes"]), "overtime_day": bool(record["overtime_day"]), "remediation_state": String(record["remediation_state"]), "receipt_id": String(record["receipt_id"])}

func _generation_from_identity(identity: String) -> DomainResult:
	var parts: PackedStringArray = identity.split(".")
	if parts.size() != 2 or parts[0] != "career" or not parts[1].is_valid_int() or int(parts[1]) < 1:
		return _reject(&"career_projection_identity_invalid", "a Career projection requires a valid Career identity")
	return DomainResult.success(int(parts[1]))

func _career_identity() -> String:
	return "career.%d" % _career_generation

func _validate_command_career_identity(command_career_identity: String) -> DomainResult:
	if command_career_identity.is_empty() and _career_generation == 1:
		return DomainResult.success(true)
	if command_career_identity != _career_identity():
		return _reject(&"career_identity_invalid", "a Career command must name the current Career identity")
	return DomainResult.success(true)

func _expected_remediation(day_index: int, failure_count: int) -> String:
	if failure_count == 0:
		return _REMEDIATION_NONE
	if day_index == _DAY_COUNT:
		return _REMEDIATION_FINAL_REVIEW
	return _REMEDIATION_NEXT_DAY

func _copy_dictionary(value: Variant) -> Dictionary[String, Variant]:
	var copy: Dictionary[String, Variant] = {}
	if typeof(value) != TYPE_DICTIONARY:
		return copy
	for raw_key: Variant in value.keys():
		if typeof(raw_key) != TYPE_STRING:
			return {}
		copy[String(raw_key)] = value[raw_key]
	return copy.duplicate(true)

func _reject(error_code: StringName, message: String) -> DomainResult:
	return DomainResult.failure(error_code, message, "career.progression")
