class_name CourseworkPublicRosterStateValidator
extends RefCounted

## Validates and atomically admits the fixed Assignment-Floor public roster.
##
## The validator owns only the public roster boundary. It accepts detached
## day-content projections, preserves the GDD table order, delegates every
## supplied Sandbox state to `SandboxCaseAdmission`, and exposes copy-on-read
## snapshots. It neither repairs content nor constructs playable case state.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const SandboxCaseAdmission = preload("res://src/core/sandbox/sandbox_case_admission.gd")

const EXPECTED_DAY_INDICES: Array[int] = [1, 2, 3, 4, 5]
const EXPECTED_TASK_IDS: Array[String] = [
	"task.day1.delivery_order",
	"task.day2.color_sort",
	"task.day3.patrol_loop",
	"task.day4.low_battery",
	"task.day5.multi_package",
]
const EXPECTED_CASE_IDS: Array[Array] = [
	["case.d1.01.red", "case.d1.02.blue", "case.d1.03.yellow"],
	["case.d2.01.red_hold", "case.d2.02.blue_release", "case.d2.03.green_release", "case.d2.04.orange_release", "case.d2.05.yellow_release"],
	["case.d3.01.clear_east", "case.d3.02.obstacle_after_one", "case.d3.03.east_boundary", "case.d3.04.closed_door", "case.d3.05.crate_after_one", "case.d3.06.package_blocker", "case.d3.07.north_obstacle"],
	["case.d4.01.empty_0", "case.d4.02.low_1", "case.d4.03.boundary_2", "case.d4.04.above_3", "case.d4.05.above_4", "case.d4.06.mid_5", "case.d4.07.mid_6", "case.d4.08.high_9", "case.d4.09.full_10"],
	["case.d5.01.red_low_mixed", "case.d5.02.blue_low_mixed", "case.d5.03.red_high_mixed", "case.d5.04.green_high_three", "case.d5.05.red_low_three", "case.d5.06.yellow_low_distance2", "case.d5.07.blue_high_distance2", "case.d5.08.red_high_distance1", "case.d5.09.orange_low_all_far", "case.d5.10.red_high_all_far", "case.d5.11.purple_low_near", "case.d5.12.red_full_mixed"],
]

var _admitted_snapshot: Dictionary = {}


## Validates all five candidate day packages and commits one detached snapshot.
##
## Example: `validator.admit(candidate_days)` accepts only the exact 36-case
## public GDD roster. Any rejection leaves the previously admitted snapshot
## unchanged.
func admit(candidate_days: Variant) -> DomainResult:
	var validation: DomainResult = _validate_candidate(candidate_days)
	if not validation.is_success():
		return validation
	var next_snapshot: Dictionary = {"days": Array(candidate_days).duplicate(true)}
	_admitted_snapshot = next_snapshot
	return DomainResultType.success(snapshot())


## Returns the last admitted roster as a detached public projection.
##
## Example: `var snapshot := validator.snapshot()`.
func snapshot() -> Dictionary:
	return _admitted_snapshot.duplicate(true)


func _validate_candidate(candidate_days: Variant) -> DomainResult:
	if typeof(candidate_days) != TYPE_ARRAY:
		return _failure(&"public_roster_shape_invalid", "candidate day content must be an Array")
	var days: Array = candidate_days
	if days.size() != EXPECTED_DAY_INDICES.size():
		return _failure(&"public_roster_count_invalid", "candidate must contain exactly five day packages")
	var globally_seen_case_ids: Dictionary = {}
	for day_offset: int in EXPECTED_DAY_INDICES.size():
		var day_result: DomainResult = _validate_day(days[day_offset], day_offset, globally_seen_case_ids)
		if not day_result.is_success():
			return day_result
	if globally_seen_case_ids.size() != 36:
		return _failure(&"public_roster_unique_count_invalid", "candidate must contain exactly 36 unique public case IDs")
	return DomainResultType.success(true)


func _validate_day(raw_day: Variant, day_offset: int, globally_seen_case_ids: Dictionary) -> DomainResult:
	if typeof(raw_day) != TYPE_DICTIONARY:
		return _failure(&"public_day_shape_invalid", "day package must be a Dictionary")
	var day: Dictionary = raw_day
	if day.get("day_index") != EXPECTED_DAY_INDICES[day_offset] or String(day.get("task_id", "")) != EXPECTED_TASK_IDS[day_offset]:
		return _failure(&"public_day_identity_invalid", "day package identity or order differs from the GDD roster")
	if typeof(day.get("public_cases")) != TYPE_ARRAY:
		return _failure(&"public_roster_shape_invalid", "day public_cases must be an Array")
	var public_cases: Array = day["public_cases"]
	var expected_case_ids: Array = EXPECTED_CASE_IDS[day_offset]
	if public_cases.size() != expected_case_ids.size():
		return _failure(&"public_roster_count_invalid", "day public case count differs from the GDD roster")
	for case_offset: int in expected_case_ids.size():
		var case_result: DomainResult = _validate_public_case(public_cases[case_offset], String(expected_case_ids[case_offset]), globally_seen_case_ids)
		if not case_result.is_success():
			return case_result
	return DomainResultType.success(true)


func _validate_public_case(raw_case: Variant, expected_case_id: String, globally_seen_case_ids: Dictionary) -> DomainResult:
	if typeof(raw_case) != TYPE_DICTIONARY:
		return _failure(&"public_case_shape_invalid", "public case must be a Dictionary")
	var public_case: Dictionary = raw_case
	var case_id: String = String(public_case.get("case_id", ""))
	if case_id != expected_case_id:
		return _failure(&"public_roster_order_invalid", "public case ID differs from the GDD table order")
	if globally_seen_case_ids.has(case_id):
		return _failure(&"public_case_identity_duplicate", "public case IDs must be globally unique")
	if typeof(public_case.get("initial_state")) != TYPE_DICTIONARY:
		return _failure(&"public_state_shape_invalid", "public case initial_state must be a Dictionary")
	var initial_state: Dictionary = public_case["initial_state"]
	if String(initial_state.get("case_id", "")) != case_id:
		return _failure(&"public_state_identity_invalid", "initial state must retain its public case ID")
	var state_validation: DomainResult = SandboxCaseAdmission.validate_definition(initial_state)
	if not state_validation.is_success():
		return state_validation
	globally_seen_case_ids[case_id] = true
	return DomainResultType.success(true)


func _failure(error_code: StringName, message: String) -> DomainResult:
	return DomainResultType.failure(error_code, message)
