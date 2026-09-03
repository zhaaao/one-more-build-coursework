class_name SandboxActionResult
extends RefCounted

## Closed pure-domain outcome for one synchronous Parcel Bot Sandbox Action.
##
## `transitioned` carries a detached successor, `domain_rejected` retains the
## exact input state, and `system_error` deliberately exposes neither state nor
## observation. Story 005 supplies one finalized state-derived fact schema.

const KIND_TRANSITIONED: StringName = &"transitioned"
const KIND_DOMAIN_REJECTED: StringName = &"domain_rejected"
const KIND_SYSTEM_ERROR: StringName = &"system_error"
const SandboxCaseStateType = preload("res://src/core/sandbox/sandbox_case_state.gd")

var _kind: StringName = KIND_SYSTEM_ERROR
var _state: SandboxCaseStateType = null
var _reason: StringName = &""
var _detail: String = ""
var _observation: Dictionary = {}

## Creates a successful Action outcome with one immutable successor.
## Example: `return SandboxActionResult.transitioned(next_state)`.
static func transitioned(next_state: SandboxCaseStateType, observation: Dictionary = {}) -> SandboxActionResult:
	var result := SandboxActionResult.new()
	result._kind = KIND_TRANSITIONED
	result._state = next_state
	result._observation = observation.duplicate(true)
	return result

## Creates an atomic domain rejection retaining the exact input state.
## Example: `return SandboxActionResult.domain_rejected(state, &"battery_empty", "battery is zero")`.
static func domain_rejected(unchanged_state: SandboxCaseStateType, reason: StringName, detail: String, observation: Dictionary = {}) -> SandboxActionResult:
	var result := SandboxActionResult.new()
	result._kind = KIND_DOMAIN_REJECTED
	result._state = unchanged_state
	result._reason = reason
	result._detail = detail
	result._observation = observation.duplicate(true)
	return result

## Creates a controlled system error without a successor or observation.
## Example: `return SandboxActionResult.system_error(&"action_invalid", "unknown Action")`.
static func system_error(reason: StringName, detail: String) -> SandboxActionResult:
	var result := SandboxActionResult.new()
	result._kind = KIND_SYSTEM_ERROR
	result._reason = reason
	result._detail = detail
	return result

## Returns the closed Action-result discriminant.
## Example: `if result.kind() == SandboxActionResult.KIND_TRANSITIONED: pass`.
func kind() -> StringName:
	return _kind

## Returns whether the Action produced a successor.
## Example: `assert(result.is_transitioned())`.
func is_transitioned() -> bool:
	return _kind == KIND_TRANSITIONED

## Returns whether the Action made no world change for a stable domain reason.
## Example: `assert(result.is_domain_rejected())`.
func is_domain_rejected() -> bool:
	return _kind == KIND_DOMAIN_REJECTED

## Returns whether the caller supplied malformed input or an invalid state.
## Example: `assert(result.is_system_error())`.
func is_system_error() -> bool:
	return _kind == KIND_SYSTEM_ERROR

## Returns the successor or exact unchanged state; system errors return null.
## Example: `var next_state := result.state()`.
func state() -> SandboxCaseStateType:
	return _state

## Returns the stable domain-rejection or system-error code.
## Example: `assert_eq(result.reason(), &"front_occupied")`.
func reason() -> StringName:
	return _reason

## Returns deterministic human-readable context for the outcome.
## Example: `var message := result.detail()`.
func detail() -> String:
	return _detail

## Returns a detached observation seam for the outcome.
## Example: `var facts := result.observation()`.
func observation() -> Dictionary:
	return _observation.duplicate(true)
