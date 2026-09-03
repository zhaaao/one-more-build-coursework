class_name CourseworkRunLimits
extends RefCounted

## Exact coursework execution and trace bounds from the GVET GDD.

const DomainResultType = preload("res://src/foundation/domain_result.gd")

const MIN_DAY: int = 1
const MAX_DAY: int = 5
const MIN_CASE_COUNT: int = 1
const MAX_CASE_COUNT: int = 12
const STEP_CAP_BASE: int = 32
const STEP_CAP_PER_DAY: int = 8
const MAX_TRACE_STEPS: int = 864

## Returns S_cap(D)=32+8D for one valid coursework day.
## Example: `var cap_result: DomainResult = CourseworkRunLimits.step_cap(3)`.
static func step_cap(day: Variant) -> DomainResult:
	if typeof(day) != TYPE_INT:
		return _invalid("coursework day must be an integer")
	var day_value: int = day
	if day_value < MIN_DAY or day_value > MAX_DAY:
		return _invalid("coursework day must be in 1..5")
	return DomainResultType.success(STEP_CAP_BASE + STEP_CAP_PER_DAY * day_value)

## Returns T_max(N,D)=N*S_cap(D) for one valid admitted roster.
## Example: `var max_result: DomainResult = CourseworkRunLimits.trace_max(7, 3)`.
static func trace_max(case_count: Variant, day: Variant) -> DomainResult:
	if typeof(case_count) != TYPE_INT:
		return _invalid("case count must be an integer")
	var count_value: int = case_count
	if count_value < MIN_CASE_COUNT or count_value > MAX_CASE_COUNT:
		return _invalid("case count must be in 1..12")
	var cap_result: DomainResult = step_cap(day)
	if not cap_result.is_success():
		return cap_result
	var result: int = count_value * int(cap_result.value())
	if result > MAX_TRACE_STEPS:
		return _invalid("run trace bound exceeds the coursework maximum")
	return DomainResultType.success(result)

static func _invalid(message: String) -> DomainResult:
	return DomainResultType.failure(&"run_limit_error", message)
