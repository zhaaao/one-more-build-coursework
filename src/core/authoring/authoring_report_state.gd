class_name AuthoringReportState
extends RefCounted

## Read-only Authoring projection of GVET's one complete terminal report slot.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CourseworkRunInputType = preload("res://src/core/gvet/coursework_run_input.gd")
const CourseworkRunResultType = preload("res://src/core/gvet/coursework_run_result.gd")

var _completed_report: CourseworkRunResultType = null
var _last_system_error: String = ""

## Replaces the visible report only when it is a complete result for the exact
## immutable input that Authoring captured.
## Example: `var accepted: DomainResult = state.accept_completed_result(report, input)`.
func accept_completed_result(
	candidate: CourseworkRunResultType, captured_input: CourseworkRunInputType
) -> DomainResultType:
	if captured_input == null or not is_instance_valid(captured_input) \
			or not captured_input.is_valid():
		return _reject(&"invalid_run_capture", "A valid immutable Run input is required.")
	if candidate == null or not is_instance_valid(candidate) or not candidate.is_valid():
		return _reject(&"malformed_run_result", "GVET returned no complete frozen result.")
	if candidate.identity() != _identity_for(captured_input):
		return _reject(&"run_result_identity_mismatch", "GVET returned a result for a different Run capture.")
	_completed_report = candidate
	_last_system_error = ""
	return DomainResultType.success(candidate)

## Records a readable controlled error without replacing the prior valid report.
## Example: `state.record_controlled_system_error("GVET returned no result.")`.
func record_controlled_system_error(message: String) -> DomainResultType:
	if message.is_empty():
		return _reject(&"invalid_system_error", "A controlled system error requires readable text.")
	_last_system_error = message
	return DomainResultType.success(message)

## Returns the last valid frozen report, or null before the first valid Run.
## Example: `var report: CourseworkRunResult = state.completed_report()`.
func completed_report() -> CourseworkRunResultType:
	return _completed_report

## Returns none, fresh, or out_of_date without changing completed report truth.
## Example: `var status: StringName = state.report_status(live_revision)`.
func report_status(live_revision: int) -> StringName:
	if _completed_report == null or not is_instance_valid(_completed_report):
		return &"none"
	return &"fresh" if int(_completed_report.identity().get("graph_revision", -1)) == live_revision else &"out_of_date"

## Returns the last readable controlled system error, or an empty string.
## Example: `if not state.last_system_error().is_empty(): show_error()`.
func last_system_error() -> String:
	return _last_system_error

func _identity_for(captured_input: CourseworkRunInputType) -> Dictionary:
	return {
		"task_id": captured_input.task_id(),
		"day_index": captured_input.day_index(),
		"request_id": captured_input.request_id(),
		"graph_revision": captured_input.graph_revision(),
		"input_identity_sha256": captured_input.identity_sha256(),
		"admitted_content_digest": captured_input.admitted_content_digest(),
	}

func _reject(code: StringName, message: String) -> DomainResultType:
	return DomainResultType.failure(code, message)
