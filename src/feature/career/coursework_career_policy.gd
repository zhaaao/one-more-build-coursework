class_name CourseworkCareerPolicy
extends RefCounted

## Feature-owned deterministic primitives for Career Story 001.
##
## This policy exposes fresh projections only. Daily Workday facts, record
## mutation, final outcomes, persistence, and presentation belong to later
## Career stories.

const _INITIAL_REPUTATION: int = 50
const _MIN_REPUTATION: int = 0
const _MAX_REPUTATION: int = 100
const _INITIAL_DAY_INDEX: int = 1
const _CAREER_STATE_ACTIVE: String = "active"
const _FEEDBACK_SUPPORTIVE_RECOVERY: String = "supportive_recovery"
const _FEEDBACK_DEVELOPING_PRACTICE: String = "developing_practice"
const _FEEDBACK_TRUSTED_MOMENTUM: String = "trusted_momentum"
const _SUPPORTIVE_MAX_REPUTATION: int = 39
const _DEVELOPING_MAX_REPUTATION: int = 69

const _TASK_IDS: Array[String] = [
	"task.day1.delivery_order",
	"task.day2.color_sort",
	"task.day3.patrol_loop",
	"task.day4.low_battery",
	"task.day5.multi_package",
]
const _PUBLIC_CASE_BOUNDS: Array[int] = [3, 5, 7, 9, 12]

## Creates a new detached Career snapshot for one fresh identity.
static func start_new_career() -> Dictionary[String, Variant]:
	var records: Array[Variant] = []
	var initial_snapshot: Dictionary[String, Variant] = {
		"career_state": _CAREER_STATE_ACTIVE,
		"next_day": _INITIAL_DAY_INDEX,
		"reputation": _INITIAL_REPUTATION,
		"records": records,
		"D_total": 0,
		"O_days": 0,
	}
	return initial_snapshot

## Returns the ordered, caller-safe catalogue for the fixed five Career days.
static func ordered_task_catalogue() -> Array[Variant]:
	var catalogue: Array[Variant] = []
	for index: int in _TASK_IDS.size():
		var entry: Dictionary[String, Variant] = {
			"day_index": index + 1,
			"task_id": _TASK_IDS[index],
			"public_case_bound": _PUBLIC_CASE_BOUNDS[index],
		}
		catalogue.append(entry)
	return catalogue

## Returns the pre-clamp rule delta for a legal number of failed public cases.
static func rule_delta_for_failed_public_cases(failed_public_cases: int) -> int:
	match failed_public_cases:
		0:
			return 10
		1:
			return -10
		2:
			return -15
		_:
			return -20

## Calculates a detached daily consequence while retaining both delta meanings.
static func calculate_daily_consequence(reputation: int, failed_public_cases: int) -> Dictionary[String, Variant]:
	var rule_delta: int = rule_delta_for_failed_public_cases(failed_public_cases)
	var final_reputation: int = _clamp_reputation(reputation + rule_delta)
	var applied_delta: int = final_reputation - reputation
	var consequence: Dictionary[String, Variant] = {
		"rule_delta": rule_delta,
		"applied_delta": applied_delta,
		"final_reputation": final_reputation,
	}
	return consequence

## Returns the stable inclusive feedback-band identifier for a legal reputation.
static func feedback_band_for_reputation(reputation: int) -> String:
	if reputation <= _SUPPORTIVE_MAX_REPUTATION:
		return _FEEDBACK_SUPPORTIVE_RECOVERY
	if reputation <= _DEVELOPING_MAX_REPUTATION:
		return _FEEDBACK_DEVELOPING_PRACTICE
	return _FEEDBACK_TRUSTED_MOMENTUM

static func _clamp_reputation(candidate: int) -> int:
	if candidate < _MIN_REPUTATION:
		return _MIN_REPUTATION
	if candidate > _MAX_REPUTATION:
		return _MAX_REPUTATION
	return candidate
