class_name CourseworkWorkdayPolicy
extends RefCounted

## Feature-owned admission seam for the fixed coursework Workday policy.
##
## Candidate data is completely validated before typed records are built. A
## rejection therefore leaves the last accepted snapshot unchanged, and every
## published value is a detached projection rather than a live tuning surface.

const _ROOT_KEYS: Array[String] = [
	"regular_capacity_minutes",
	"overtime_capacity_minutes",
	"action_cost_minutes",
	"career_days",
]
const _ACTION_KEYS: Array[String] = [
	"targeted_case",
	"voluntary_suite",
	"submission",
	"rework",
	"edit",
	"inspect",
]
const _DAY_KEYS: Array[String] = ["day_index", "authoritative_receipt_limit"]
const _APPROVED_DAY_INDICES: Array[int] = [1, 2, 3, 4, 5]
const _MAX_POLICY_INTEGER: int = 2147483647

## Immutable typed record for one admitted career-day receipt limit.
class CareerDayPolicy extends RefCounted:
	var _locked: bool = false:
		set(value):
			if not _locked:
				_locked = value
	var _day_index: int = 0:
		set(value):
			if not _locked:
				_day_index = value
	var _authoritative_receipt_limit: int = 0:
		set(value):
			if not _locked:
				_authoritative_receipt_limit = value

	func _init(day_index: int, authoritative_receipt_limit: int) -> void:
		_day_index = day_index
		_authoritative_receipt_limit = authoritative_receipt_limit
		_locked = true

	## Returns a detached projection of this admitted day record.
	func projection() -> Dictionary[String, Variant]:
		return {
			"day_index": _day_index,
			"authoritative_receipt_limit": _authoritative_receipt_limit,
		}

## Immutable typed record for the complete admitted coursework policy.
class WorkdayPolicySnapshot extends RefCounted:
	var _locked: bool = false:
		set(value):
			if not _locked:
				_locked = value
	var _regular_capacity_minutes: int = 0:
		set(value):
			if not _locked:
				_regular_capacity_minutes = value
	var _overtime_capacity_minutes: int = 0:
		set(value):
			if not _locked:
				_overtime_capacity_minutes = value
	var _targeted_case_minutes: int = 0:
		set(value):
			if not _locked:
				_targeted_case_minutes = value
	var _voluntary_suite_minutes: int = 0:
		set(value):
			if not _locked:
				_voluntary_suite_minutes = value
	var _submission_minutes: int = 0:
		set(value):
			if not _locked:
				_submission_minutes = value
	var _rework_minutes: int = 0:
		set(value):
			if not _locked:
				_rework_minutes = value
	var _edit_minutes: int = 0:
		set(value):
			if not _locked:
				_edit_minutes = value
	var _inspect_minutes: int = 0:
		set(value):
			if not _locked:
				_inspect_minutes = value
	var _career_days: Array[CareerDayPolicy] = []:
		get:
			return _career_days.duplicate()
		set(value):
			if not _locked:
				_career_days = value.duplicate()

	func _init(capacities: Array[int], action_costs: Array[int], career_days: Array[CareerDayPolicy]) -> void:
		_regular_capacity_minutes = capacities[0]
		_overtime_capacity_minutes = capacities[1]
		_targeted_case_minutes = action_costs[0]
		_voluntary_suite_minutes = action_costs[1]
		_submission_minutes = action_costs[2]
		_rework_minutes = action_costs[3]
		_edit_minutes = action_costs[4]
		_inspect_minutes = action_costs[5]
		_career_days = career_days.duplicate()
		_locked = true

	## Returns a detached projection of the complete accepted policy.
	func projection() -> Dictionary[String, Variant]:
		var days: Array[Variant] = []
		for day: CareerDayPolicy in _career_days:
			days.append(day.projection())
		var action_costs: Dictionary[String, Variant] = {
			"targeted_case": _targeted_case_minutes,
			"voluntary_suite": _voluntary_suite_minutes,
			"submission": _submission_minutes,
			"rework": _rework_minutes,
			"edit": _edit_minutes,
			"inspect": _inspect_minutes,
		}
		var accepted_policy: Dictionary[String, Variant] = {
			"regular_capacity_minutes": _regular_capacity_minutes,
			"overtime_capacity_minutes": _overtime_capacity_minutes,
			"action_cost_minutes": action_costs,
			"career_days": days,
		}
		return accepted_policy

var _operations_locked: bool = false:
	set(value):
		if not _operations_locked:
			_operations_locked = value
var _snapshot_operation: Callable:
	set(value):
		if not _operations_locked:
			_snapshot_operation = value
var _admit_operation: Callable:
	set(value):
		if not _operations_locked:
			_admit_operation = value

func _init() -> void:
	var snapshot_slot: Array[WorkdayPolicySnapshot] = [null]
	_snapshot_operation = func() -> Dictionary[String, Variant]:
		var empty_snapshot: Dictionary[String, Variant] = {}
		return empty_snapshot if snapshot_slot[0] == null else snapshot_slot[0].projection()
	_admit_operation = func(candidate: Variant) -> DomainResult:
		var validation_result: DomainResult = _validate_candidate(candidate)
		if not validation_result.is_success():
			return validation_result
		snapshot_slot[0] = _build_snapshot(candidate)
		return DomainResult.success(snapshot_slot[0].projection())
	_operations_locked = true

## Returns a fresh candidate containing the only approved coursework values.
## Example: `var candidate := CourseworkWorkdayPolicy.approved_candidate()`.
static func approved_candidate() -> Dictionary[String, Variant]:
	var career_days: Array[Variant] = []
	for day_index: int in _APPROVED_DAY_INDICES:
		var career_day: Dictionary[String, Variant] = {
			"day_index": day_index,
			"authoritative_receipt_limit": 1,
		}
		career_days.append(career_day)
	var action_costs: Dictionary[String, Variant] = {
		"targeted_case": 20,
		"voluntary_suite": 45,
		"submission": 15,
		"rework": 60,
		"edit": 0,
		"inspect": 0,
	}
	var approved_policy: Dictionary[String, Variant] = {
		"regular_capacity_minutes": 480,
		"overtime_capacity_minutes": 120,
		"action_cost_minutes": action_costs,
		"career_days": career_days,
	}
	return approved_policy

## Returns a detached accepted projection, or an empty dictionary before the
## first successful admission. Example: `var policy := owner.snapshot()`.
func snapshot() -> Dictionary[String, Variant]:
	return _snapshot_operation.call()

## Validates and atomically admits one complete policy candidate. No arithmetic
## or record construction occurs before validation succeeds.
## Example: `var result := owner.admit(CourseworkWorkdayPolicy.approved_candidate())`.
func admit(candidate: Variant) -> DomainResult:
	return _admit_operation.call(candidate)

static func _validate_candidate(candidate: Variant) -> DomainResult:
	if typeof(candidate) != TYPE_DICTIONARY:
		return _reject(&"policy_type_invalid", "policy candidate must be a dictionary", "$")
	var root_shape: DomainResult = _validate_exact_keys(candidate, _ROOT_KEYS, "$")
	if not root_shape.is_success():
		return root_shape
	var capacity_result: DomainResult = _validate_capacities(candidate)
	if not capacity_result.is_success():
		return capacity_result
	var action_result: DomainResult = _validate_actions(candidate["action_cost_minutes"])
	if not action_result.is_success():
		return action_result
	return _validate_career_days(candidate["career_days"])

static func _validate_capacities(policy: Variant) -> DomainResult:
	var regular_result: DomainResult = _validate_exact_integer(policy["regular_capacity_minutes"], 480, "$.regular_capacity_minutes")
	if not regular_result.is_success():
		return regular_result
	return _validate_exact_integer(policy["overtime_capacity_minutes"], 120, "$.overtime_capacity_minutes")

static func _validate_actions(candidate: Variant) -> DomainResult:
	if typeof(candidate) != TYPE_DICTIONARY:
		return _reject(&"action_cost_shape_invalid", "action costs must be a dictionary", "$.action_cost_minutes")
	var shape_result: DomainResult = _validate_exact_keys(candidate, _ACTION_KEYS, "$.action_cost_minutes")
	if not shape_result.is_success():
		return shape_result
	var approved_values: Array[int] = [20, 45, 15, 60, 0, 0]
	for index: int in _ACTION_KEYS.size():
		var key: String = _ACTION_KEYS[index]
		var value_result: DomainResult = _validate_exact_integer(candidate[key], approved_values[index], "$.action_cost_minutes.%s" % key)
		if not value_result.is_success():
			return value_result
	return DomainResult.success(true)

static func _validate_career_days(candidate: Variant) -> DomainResult:
	if typeof(candidate) != TYPE_ARRAY:
		return _reject(&"career_days_shape_invalid", "career days must be an array", "$.career_days")
	if candidate.size() != _APPROVED_DAY_INDICES.size():
		return _reject(&"career_day_count_invalid", "career must contain exactly five days", "$.career_days")
	for index: int in candidate.size():
		var day_result: DomainResult = _validate_career_day(candidate[index], index)
		if not day_result.is_success():
			return day_result
	return DomainResult.success(true)

static func _validate_career_day(candidate: Variant, index: int) -> DomainResult:
	var day_path: String = "$.career_days[%d]" % index
	if typeof(candidate) != TYPE_DICTIONARY:
		return _reject(&"career_day_shape_invalid", "career day must be a dictionary", day_path)
	var shape_result: DomainResult = _validate_exact_keys(candidate, _DAY_KEYS, day_path)
	if not shape_result.is_success():
		return shape_result
	var index_result: DomainResult = _validate_exact_integer(candidate["day_index"], _APPROVED_DAY_INDICES[index], "%s.day_index" % day_path)
	if not index_result.is_success():
		return index_result
	return _validate_exact_integer(candidate["authoritative_receipt_limit"], 1, "%s.authoritative_receipt_limit" % day_path)

static func _validate_exact_keys(candidate: Variant, expected_keys: Array[String], path: String) -> DomainResult:
	for expected_key: String in expected_keys:
		if not candidate.has(expected_key):
			return _reject(&"required_field_missing", "required policy field is missing", "%s.%s" % [path, expected_key])
	for candidate_key: Variant in candidate.keys():
		if typeof(candidate_key) != TYPE_STRING or not expected_keys.has(String(candidate_key)):
			return _reject(&"unknown_field", "policy field is not in the closed shape", "%s.%s" % [path, String(candidate_key)])
	return DomainResult.success(true)

static func _validate_exact_integer(candidate: Variant, expected: int, path: String) -> DomainResult:
	if typeof(candidate) != TYPE_INT:
		return _reject(&"integer_type_invalid", "policy value must be an integer", path)
	var value: int = candidate
	if value < 0 or value > _MAX_POLICY_INTEGER:
		return _reject(&"integer_range_invalid", "policy value is outside the admitted integer range", path)
	if value != expected:
		return _reject(&"fixed_value_mismatch", "policy value is not the approved coursework value", path)
	return DomainResult.success(true)

static func _build_snapshot(candidate: Variant) -> WorkdayPolicySnapshot:
	var action_costs: Variant = candidate["action_cost_minutes"]
	var capacities: Array[int] = [candidate["regular_capacity_minutes"], candidate["overtime_capacity_minutes"]]
	var costs: Array[int] = [
		action_costs["targeted_case"], action_costs["voluntary_suite"],
		action_costs["submission"], action_costs["rework"],
		action_costs["edit"], action_costs["inspect"],
	]
	var career_days: Array[CareerDayPolicy] = []
	for day_candidate: Variant in candidate["career_days"]:
		career_days.append(CareerDayPolicy.new(day_candidate["day_index"], day_candidate["authoritative_receipt_limit"]))
	return WorkdayPolicySnapshot.new(capacities, costs, career_days)

static func _reject(error_code: StringName, message: String, path: String) -> DomainResult:
	return DomainResult.failure(error_code, message, path)
