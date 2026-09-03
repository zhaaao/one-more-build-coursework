class_name CourseworkSandboxPort
extends RefCounted

## Direct synchronous Sandbox boundary for one coursework case.

const DomainResultType = preload("res://src/foundation/domain_result.gd")

## Creates fresh Task-owned state for one exact case definition.
## Example: `var state_result := sandbox.create_case_state(case_definition)`.
func create_case_state(_case_definition: Dictionary) -> DomainResult:
	return DomainResultType.failure(
		&"sandbox_error", "Sandbox case-state creation is not implemented")

## Reads one value without mutating case state.
## Example: `var query_result := sandbox.query(state, {"query_id": "parcel.status"})`.
func query(_state: Dictionary, _call: Dictionary) -> DomainResult:
	return DomainResultType.failure(&"sandbox_error", "Sandbox Query is not implemented")

## Applies one synchronous transition and returns new state plus observation.
## Example: `var action_result := sandbox.act(state, {"action_id": "parcel.load"})`.
func act(_state: Dictionary, _call: Dictionary) -> DomainResult:
	return DomainResultType.failure(&"sandbox_error", "Sandbox Action is not implemented")

## Returns a detached observation of the current case state.
## Example: `var observation_result := sandbox.observe(state)`.
func observe(_state: Dictionary) -> DomainResult:
	return DomainResultType.failure(&"sandbox_error", "Sandbox observation is not implemented")
