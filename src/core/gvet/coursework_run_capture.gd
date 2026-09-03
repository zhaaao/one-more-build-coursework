class_name CourseworkRunCapture
extends RefCounted

## Authoring-facing synchronous owner of GVET's single completed-report slot.
## The injected runner and this capture are single-thread-only.

var _runner: CourseworkGvetRunner = null
var _completed_report: CourseworkRunResult = null
var _run_active: bool = false
var _slot_write_count: int = 0

func _init(runner: CourseworkGvetRunner = null) -> void:
	_runner = runner

## Runs one immutable capture synchronously and replaces the completed slot only
## after the runner returns a valid frozen result.
## Example: `var report: CourseworkRunResult = capture.run(run_input)`.
func run(input: CourseworkRunInput) -> CourseworkRunResult:
	if _run_active or _runner == null or not is_instance_valid(_runner):
		return null
	_run_active = true
	var candidate: CourseworkRunResult = _runner.run(input)
	_run_active = false
	if candidate == null or not is_instance_valid(candidate) \
			or not candidate.is_valid():
		return null
	if not _report_matches_input(candidate, input):
		return null
	_completed_report = candidate
	_slot_write_count += 1
	return candidate

## Returns the one most-recent complete frozen report without copying history.
## Example: `var visible: CourseworkRunResult = capture.completed_report()`.
func completed_report() -> CourseworkRunResult:
	return _completed_report

## Derives presentation staleness without mutating or clearing the old report.
## Example: `if capture.is_out_of_date(live_revision): show_stale_badge()`.
func is_out_of_date(live_graph_revision: int) -> bool:
	if live_graph_revision < 0 or _completed_report == null \
			or not is_instance_valid(_completed_report):
		return false
	return int(_completed_report.identity().get("graph_revision", -1)) \
		!= live_graph_revision

func _slot_write_count_for_test() -> int:
	return _slot_write_count

func _report_matches_input(
	report: CourseworkRunResult, input: CourseworkRunInput
) -> bool:
	if input == null or not is_instance_valid(input) or not input.is_valid():
		return false
	return report.identity() == {
		"task_id": input.task_id(),
		"day_index": input.day_index(),
		"request_id": input.request_id(),
		"graph_revision": input.graph_revision(),
		"input_identity_sha256": input.identity_sha256(),
		"admitted_content_digest": input.admitted_content_digest(),
	}
