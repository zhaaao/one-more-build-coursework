class_name SandboxCasePort
extends RefCounted

## Direct synchronous construction port for fresh Parcel Bot Sandbox states.
##
## Each call admits and detaches the supplied Task-owned case definition. The
## port owns no cache, retained case, engine object, callback, or external I/O.

const SandboxCaseAdmissionType = preload("res://src/core/sandbox/sandbox_case_admission.gd")
const SandboxActionReducerType = preload("res://src/core/sandbox/sandbox_action_reducer.gd")
const SandboxActionResultType = preload("res://src/core/sandbox/sandbox_action_result.gd")
const SandboxCaseStateType = preload("res://src/core/sandbox/sandbox_case_state.gd")
const SandboxQueryReducerType = preload("res://src/core/sandbox/sandbox_query_reducer.gd")
const SandboxQueryResultType = preload("res://src/core/sandbox/sandbox_query_result.gd")
const SandboxObservationType = preload("res://src/core/sandbox/sandbox_observation.gd")

## Creates one fresh immutable case state or returns a controlled rejection.
## Example: `var result := SandboxCasePort.new().create_case_state(case_definition)`.
func create_case_state(case_definition: Dictionary) -> DomainResult:
	return SandboxCaseAdmissionType.admit(case_definition)

## Directly reduces one exact Dictionary Action call without retaining case state.
## Example: `var result := SandboxCasePort.new().act(state, {"action_id": "move_forward"})`.
func act(state: SandboxCaseStateType, action_call: Dictionary) -> SandboxActionResultType:
	return SandboxActionReducerType.reduce_call(state, action_call)

## Directly reads one exact Dictionary Query call without retaining case state.
## Example: `var result := SandboxCasePort.new().query(state, {"query_id": "path_is_clear"})`.
func query(state: SandboxCaseStateType, query_call: Dictionary) -> SandboxQueryResultType:
	return SandboxQueryReducerType.reduce_call(state, query_call)

## Directly observes one admitted state without retaining it or mutating it.
## Example: `var result := SandboxCasePort.new().observe(state)`.
func observe(state: SandboxCaseStateType) -> SandboxQueryResultType:
	if state == null or not state.is_valid():
		return SandboxQueryResultType.system_error(&"state_invalid", "Observation requires an admitted immutable SandboxCaseState")
	var validation: DomainResult = SandboxCaseAdmissionType.validate_definition(state.projection())
	if not validation.is_success():
		return SandboxQueryResultType.system_error(&"state_invariant_broken", "Observation input failed admission: %s" % String(validation.error_code()))
	return SandboxQueryResultType.produced(null, SandboxObservationType.derive(state))
