class_name CourseworkReworkCareerHandoff
extends RefCounted

## Derives abstract rework and exposes settled daily facts from Story 004 records.

const _EXPECTED_DAILY_FACTS: int = 5
const _NEXT_DAY_REWORK: StringName = &"next_day_rework"
const _FINAL_REVIEW_OUTSTANDING: StringName = &"final_review_outstanding"

var _records_by_day: Dictionary[int, Variant] = {}
var _day_by_delivery_identity: Dictionary[String, int] = {}
var _remediation_by_source_day: Dictionary[int, Variant] = {}
var _advanced_days: Dictionary[int, bool] = {}
var _completed_rework_days: Dictionary[int, bool] = {}
var _daily_facts: Array[Dictionary] = []

## Rebuilds the process-local handoff from already accepted recovery owners.
##
## The returned collaborator has no persistence authority. It only recreates
## the facts that Main would otherwise have accumulated before a restart.
static func from_recovered_owners(
	career_projection_value: Variant, workday_snapshot_value: Variant, rework_minutes: int
) -> CourseworkReworkCareerHandoff:
	var handoff: CourseworkReworkCareerHandoff = CourseworkReworkCareerHandoff.new()
	var career_projection: Dictionary[String, Variant] = handoff._copy_record(career_projection_value)
	var workday_snapshot: Dictionary[String, Variant] = handoff._copy_record(workday_snapshot_value)
	var receipts_by_day: Dictionary[int, Variant] = {}
	for receipt_value: Variant in Array(workday_snapshot.get("committed_receipts", [])):
		var receipt: Dictionary[String, Variant] = handoff._copy_record(receipt_value)
		var receipt_day: int = int(receipt.get("day_index", 0))
		if receipt_day > 0:
			receipts_by_day[receipt_day] = receipt
	for career_record_value: Variant in Array(career_projection.get("records", [])):
		var career_record: Dictionary[String, Variant] = handoff._copy_record(career_record_value)
		var day_index: int = int(career_record.get("day_index", 0))
		if day_index < 1 or not receipts_by_day.has(day_index):
			continue
		var receipt: Dictionary[String, Variant] = handoff._copy_record(receipts_by_day[day_index])
		var failed_case_ids: Array[String] = handoff._recovered_failed_case_ids(career_record.get("failed_case_ids", []))
		var defect_count: int = int(career_record.get("failure_count", failed_case_ids.size()))
		var delivery_identity: String = String(career_record.get("receipt_id", ""))
		if delivery_identity.is_empty() or handoff._records_by_day.has(day_index):
			continue
		var decision: StringName = &"none"
		if defect_count > 0:
			decision = &"final_review_outstanding_60" if day_index == _EXPECTED_DAILY_FACTS else &"next_day_rework_60"
		var fact: Dictionary[String, Variant] = {
			"day_index": day_index,
			"failed_case_ids": failed_case_ids,
			"defect_count": defect_count,
			"overtime_minutes": int(receipt.get("overtime_minutes", 0)),
		}
		var record: Dictionary[String, Variant] = {
			"delivery_identity": delivery_identity,
			"failed_case_ids": failed_case_ids.duplicate(),
			"defect_count": defect_count,
			"receipt": receipt.duplicate(true),
			"overtime_fact": {"overtime_minutes": int(receipt.get("overtime_minutes", 0)), "overtime_used": bool(receipt.get("overtime_used", false))},
			"rework_decision": decision,
			"day_closed": true,
			"career_fact": fact,
		}
		handoff._records_by_day[day_index] = record
		handoff._day_by_delivery_identity[delivery_identity] = day_index
		handoff._daily_facts.append(fact.duplicate(true))
		handoff._restore_remediation(day_index, defect_count, rework_minutes, workday_snapshot)
		if day_index < int(workday_snapshot.get("current_day_index", 1)):
			handoff._advanced_days[day_index] = true
	handoff._daily_facts.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("day_index", 0)) < int(right.get("day_index", 0)))
	return handoff

## Admits exactly one detached Story 004 committed record for its delivery ID.
func admit_committed_delivery(record_value: Variant, lifecycle: CourseworkWorkdayLifecycle) -> DomainResult:
	var record: Dictionary[String, Variant] = _copy_record(record_value)
	var shape_result: DomainResult = _validate_record_shape(record)
	if not shape_result.is_success():
		return shape_result
	var delivery_identity: String = String(record["delivery_identity"])
	if _day_by_delivery_identity.has(delivery_identity):
		return _replay_or_conflict(record, delivery_identity)
	var day_index: int = int(record["career_fact"]["day_index"])
	if _records_by_day.has(day_index):
		return _reject(&"career_handoff_day_conflict", "a different delivery cannot replace a settled daily fact")
	var lifecycle_result: DomainResult = _validate_new_record_against_lifecycle(record, lifecycle)
	if not lifecycle_result.is_success():
		return lifecycle_result
	var schedule_result: DomainResult = _schedule_new_rework(record, lifecycle)
	if not schedule_result.is_success():
		return schedule_result
	_records_by_day[day_index] = record.duplicate(true)
	_day_by_delivery_identity[delivery_identity] = day_index
	_daily_facts.append(_copy_record(record["career_fact"]))
	_store_remediation(record, lifecycle.rework_minutes())
	return DomainResult.success({"replayed": false, "daily_fact": _copy_record(record["career_fact"])})

## Advances one admitted committed day, scheduling its derived rework if needed.
func advance_after_committed_delivery(lifecycle: CourseworkWorkdayLifecycle) -> DomainResult:
	if lifecycle == null:
		return _reject(&"career_handoff_lifecycle_unavailable", "a lifecycle is required")
	var day_index: int = int(lifecycle.snapshot().get("current_day_index", 0))
	if not _records_by_day.has(day_index):
		return _reject(&"career_handoff_record_unavailable", "the current committed day requires an admitted record")
	if _advanced_days.has(day_index):
		return DomainResult.success({"replayed": true, "snapshot": lifecycle.snapshot()})
	var advance_result: DomainResult = lifecycle.advance_day()
	if not advance_result.is_success():
		return advance_result
	_advanced_days[day_index] = true
	return DomainResult.success({"replayed": false, "snapshot": lifecycle.snapshot()})

## Completes one due abstract rework block without dispatching prior execution.
func complete_due_rework(lifecycle: CourseworkWorkdayLifecycle) -> DomainResult:
	if lifecycle == null:
		return _reject(&"rework_lifecycle_unavailable", "a lifecycle is required")
	var current_day: int = int(lifecycle.snapshot().get("current_day_index", 0))
	var source_day: int = current_day - 1
	var remediation: Dictionary[String, Variant] = _remediation_for(source_day)
	if remediation.is_empty() or StringName(remediation.get("kind", &"")) != _NEXT_DAY_REWORK:
		return _reject(&"rework_completion_unavailable", "the current day has no scheduled rework")
	if _completed_rework_days.has(source_day):
		return DomainResult.success({"replayed": true, "remediation": remediation.duplicate(true)})
	var completion_result: DomainResult = lifecycle.complete_scheduled_rework()
	if not completion_result.is_success():
		return completion_result
	_completed_rework_days[source_day] = true
	remediation["status"] = &"completed"
	_remediation_by_source_day[source_day] = remediation.duplicate(true)
	return DomainResult.success({"replayed": false, "remediation": remediation.duplicate(true)})

## Returns one detached remediation record for a settled source day.
func remediation_for_day(source_day: int) -> Dictionary[String, Variant]:
	return _remediation_for(source_day).duplicate(true)

## Returns exactly five detached Career-owned daily fact inputs after Day 5.
func career_daily_facts() -> DomainResult:
	if _daily_facts.size() != _EXPECTED_DAILY_FACTS:
		return _reject(&"career_handoff_incomplete", "Career receives facts only after all five daily receipts")
	var copies: Array[Dictionary] = []
	for fact: Dictionary in _daily_facts:
		copies.append(fact.duplicate(true))
	return DomainResult.success(copies)

func _replay_or_conflict(record: Dictionary[String, Variant], delivery_identity: String) -> DomainResult:
	var day_index: int = _day_by_delivery_identity[delivery_identity]
	var existing: Dictionary[String, Variant] = _copy_record(_records_by_day[day_index])
	if existing == record:
		return DomainResult.success({"replayed": true, "daily_fact": _copy_record(existing["career_fact"])})
	return _reject(&"career_handoff_delivery_conflict", "a delivery identity cannot be rebound to another daily fact")

func _validate_record_shape(record: Dictionary[String, Variant]) -> DomainResult:
	if record.is_empty() or typeof(record.get("delivery_identity")) != TYPE_STRING \
			or String(record.get("delivery_identity", "")).is_empty():
		return _reject(&"career_handoff_record_invalid", "a committed delivery identity is required")
	if not bool(record.get("day_closed", false)) or typeof(record.get("defect_count")) != TYPE_INT:
		return _reject(&"career_handoff_record_invalid", "a closed committed defect record is required")
	var receipt: Dictionary[String, Variant] = _copy_record(record.get("receipt"))
	var fact: Dictionary[String, Variant] = _copy_record(record.get("career_fact"))
	if receipt.is_empty() or fact.is_empty() or int(record["defect_count"]) < 0:
		return _reject(&"career_handoff_record_invalid", "receipt and Career fact must be present")
	return _validate_fact_consistency(record, receipt, fact)

func _validate_fact_consistency(record: Dictionary[String, Variant], receipt: Dictionary[String, Variant], fact: Dictionary[String, Variant]) -> DomainResult:
	var failed_ids_result: DomainResult = _failed_case_ids(record.get("failed_case_ids"))
	if not failed_ids_result.is_success():
		return failed_ids_result
	var failed_ids: Array[String] = failed_ids_result.value()
	var day_index: int = int(receipt.get("day_index", 0))
	if day_index < 1 or day_index > _EXPECTED_DAILY_FACTS or failed_ids.size() != int(record["defect_count"]):
		return _reject(&"career_handoff_record_invalid", "receipt day and failed-case facts must be valid")
	if int(fact.get("day_index", 0)) != day_index or int(fact.get("defect_count", -1)) != failed_ids.size():
		return _reject(&"career_handoff_record_invalid", "Career fact must preserve the receipt defect facts")
	var fact_ids_result: DomainResult = _failed_case_ids(fact.get("failed_case_ids"))
	if not fact_ids_result.is_success() or fact_ids_result.value() != failed_ids:
		return _reject(&"career_handoff_record_invalid", "Career fact must preserve ordered failed case IDs")
	return _validate_rework_decision(record, day_index, failed_ids.size())

func _validate_rework_decision(record: Dictionary[String, Variant], day_index: int, defect_count: int) -> DomainResult:
	var expected: StringName = &"none"
	if defect_count > 0:
		expected = &"final_review_outstanding_60" if day_index == _EXPECTED_DAILY_FACTS else &"next_day_rework_60"
	if StringName(record.get("rework_decision", &"")) != expected:
		return _reject(&"career_handoff_record_invalid", "rework decision must match the committed daily defects")
	return DomainResult.success(true)

func _validate_new_record_against_lifecycle(record: Dictionary[String, Variant], lifecycle: CourseworkWorkdayLifecycle) -> DomainResult:
	if lifecycle == null:
		return _reject(&"career_handoff_lifecycle_unavailable", "a lifecycle is required")
	var snapshot: Dictionary[String, Variant] = lifecycle.snapshot()
	var receipt: Dictionary[String, Variant] = _copy_record(record["receipt"])
	if snapshot.get("state", &"") != &"day_committed" or int(snapshot.get("current_day_index", 0)) != int(receipt["day_index"]):
		return _reject(&"career_handoff_lifecycle_mismatch", "record admission requires the current committed lifecycle day")
	if _daily_facts.size() + 1 != int(receipt["day_index"]):
		return _reject(&"career_handoff_day_order_invalid", "daily facts must be admitted in day order")
	var receipts: Array[Variant] = snapshot.get("committed_receipts", [])
	if receipts.is_empty() or _copy_record(receipts.back()) != receipt:
		return _reject(&"career_handoff_receipt_mismatch", "record receipt must match lifecycle receipt truth")
	return DomainResult.success(true)

func _store_remediation(record: Dictionary[String, Variant], rework_minutes: int) -> void:
	var fact: Dictionary[String, Variant] = _copy_record(record["career_fact"])
	var defect_count: int = int(fact["defect_count"])
	if defect_count <= 0:
		return
	var day_index: int = int(fact["day_index"])
	var kind: StringName = _FINAL_REVIEW_OUTSTANDING if day_index == _EXPECTED_DAILY_FACTS else _NEXT_DAY_REWORK
	var status: StringName = _FINAL_REVIEW_OUTSTANDING if day_index == _EXPECTED_DAILY_FACTS else &"scheduled"
	_remediation_by_source_day[day_index] = {"source_day_index": day_index, "kind": kind, "minutes": rework_minutes, "status": status}

func _restore_remediation(day_index: int, defect_count: int, rework_minutes: int, snapshot: Dictionary[String, Variant]) -> void:
	if defect_count <= 0:
		return
	var kind: StringName = _FINAL_REVIEW_OUTSTANDING if day_index == _EXPECTED_DAILY_FACTS else _NEXT_DAY_REWORK
	var status: StringName = _FINAL_REVIEW_OUTSTANDING if day_index == _EXPECTED_DAILY_FACTS else &"completed"
	if kind == _NEXT_DAY_REWORK and int(snapshot.get("current_day_index", 0)) == day_index + 1 \
			and StringName(snapshot.get("state", &"")) == &"rework_due":
		status = &"scheduled"
	if status == &"completed":
		_completed_rework_days[day_index] = true
	_remediation_by_source_day[day_index] = {"source_day_index": day_index, "kind": kind, "minutes": rework_minutes, "status": status}

func _recovered_failed_case_ids(value: Variant) -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in Array(value):
		if typeof(raw_id) == TYPE_STRING:
			ids.append(String(raw_id))
	return ids

func _schedule_new_rework(record: Dictionary[String, Variant], lifecycle: CourseworkWorkdayLifecycle) -> DomainResult:
	var fact: Dictionary[String, Variant] = _copy_record(record["career_fact"])
	if int(fact["day_index"]) == _EXPECTED_DAILY_FACTS or int(fact["defect_count"]) == 0:
		return DomainResult.success(true)
	return lifecycle.schedule_next_day_rework(lifecycle.rework_minutes())

func _remediation_for(source_day: int) -> Dictionary[String, Variant]:
	if not _remediation_by_source_day.has(source_day):
		return {}
	return _copy_record(_remediation_by_source_day[source_day])

func _failed_case_ids(value: Variant) -> DomainResult:
	if typeof(value) != TYPE_ARRAY:
		return _reject(&"career_handoff_record_invalid", "failed case IDs must be an ordered array")
	var ids: Array[String] = []
	var seen: Dictionary[String, bool] = {}
	for raw_id: Variant in value:
		if typeof(raw_id) != TYPE_STRING or String(raw_id).is_empty() or seen.has(String(raw_id)):
			return _reject(&"career_handoff_record_invalid", "failed case IDs must be unique non-empty strings")
		seen[String(raw_id)] = true
		ids.append(String(raw_id))
	return DomainResult.success(ids)

func _copy_record(value: Variant) -> Dictionary[String, Variant]:
	var copy: Dictionary[String, Variant] = {}
	if typeof(value) != TYPE_DICTIONARY:
		return copy
	for raw_key: Variant in value.keys():
		if typeof(raw_key) != TYPE_STRING:
			return {}
		copy[String(raw_key)] = value[raw_key]
	return copy.duplicate(true)

func _reject(error_code: StringName, message: String) -> DomainResult:
	return DomainResult.failure(error_code, message, "workday.rework_career_handoff")
