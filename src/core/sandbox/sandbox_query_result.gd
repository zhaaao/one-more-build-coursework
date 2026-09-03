class_name SandboxQueryResult
extends RefCounted

## Closed pure-domain outcome for one synchronous Parcel Bot Sandbox Query.
##
## `produced` and `domain_rejected` expose a detached observation fact set.
## `system_error` deliberately exposes neither a value nor an observation.
## Story 005 owns the final observation-fact schema.

const KIND_PRODUCED: StringName = &"produced"
const KIND_DOMAIN_REJECTED: StringName = &"domain_rejected"
const KIND_SYSTEM_ERROR: StringName = &"system_error"

var _kind: StringName = KIND_SYSTEM_ERROR
var _value: Variant = null
var _reason: StringName = &""
var _detail: String = ""
var _observation: Dictionary = {}

## Creates a successful Query outcome with its deterministic value.
## Example: `return SandboxQueryResult.produced(3, observation)`.
static func produced(value: Variant, observation: Dictionary = {}) -> SandboxQueryResult:
	var result: SandboxQueryResult = new()
	result._kind = KIND_PRODUCED
	result._value = _copy_value(value)
	result._observation = observation.duplicate(true)
	return result

## Creates a stable domain rejection with its detached observation projection.
## Example: `return SandboxQueryResult.domain_rejected(&"no_front_door", "front cell has no door", observation)`.
static func domain_rejected(reason: StringName, detail: String, observation: Dictionary = {}) -> SandboxQueryResult:
	var result: SandboxQueryResult = new()
	result._kind = KIND_DOMAIN_REJECTED
	result._reason = reason
	result._detail = detail
	result._observation = observation.duplicate(true)
	return result

## Creates a controlled malformed-input or invalid-state outcome.
## Example: `return SandboxQueryResult.system_error(&"query_invalid", "Query identifier is not admitted")`.
static func system_error(reason: StringName, detail: String) -> SandboxQueryResult:
	var result: SandboxQueryResult = new()
	result._kind = KIND_SYSTEM_ERROR
	result._reason = reason
	result._detail = detail
	return result

## Returns the closed Query-result discriminant.
## Example: `assert(result.kind() == SandboxQueryResult.KIND_PRODUCED)`.
func kind() -> StringName:
	return _kind

## Returns whether the Query produced a value.
## Example: `if result.is_produced(): use_value(result.value())`.
func is_produced() -> bool:
	return _kind == KIND_PRODUCED

## Returns whether the Query found a stable unavailable world condition.
## Example: `if result.is_domain_rejected(): show_reason(result.reason())`.
func is_domain_rejected() -> bool:
	return _kind == KIND_DOMAIN_REJECTED

## Returns whether the Query call descriptor or state was invalid.
## Example: `if result.is_system_error(): report_error(result.detail())`.
func is_system_error() -> bool:
	return _kind == KIND_SYSTEM_ERROR

## Returns the produced value; non-produced outcomes return null.
## Example: `var battery_units: int = result.value()`.
func value() -> Variant:
	return _copy_value(_value)

## Returns the stable domain-rejection or system-error code.
## Example: `assert(result.reason() == &"no_front_sensor")`.
func reason() -> StringName:
	return _reason

## Returns deterministic human-readable context for the outcome.
## Example: `print(result.detail())`.
func detail() -> String:
	return _detail

## Returns the detached stable state-derived observation facts.
## Example: `var observation: Dictionary = result.observation()`.
func observation() -> Dictionary:
	return _observation.duplicate(true)

static func _copy_value(value: Variant) -> Variant:
	if value is Dictionary:
		return Dictionary(value).duplicate(true)
	if value is Array:
		return Array(value).duplicate(true)
	return value
