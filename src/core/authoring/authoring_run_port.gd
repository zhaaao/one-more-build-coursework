class_name AuthoringRunPort
extends RefCounted

## Synchronous boundary from an accepted Authoring capture to the GVET runner.

const CourseworkGvetRunnerType = preload("res://src/core/gvet/coursework_gvet_runner.gd")
const CourseworkRunInputType = preload("res://src/core/gvet/coursework_run_input.gd")
const CourseworkRunResultType = preload("res://src/core/gvet/coursework_run_result.gd")

var _runner: CourseworkGvetRunnerType = null

## Creates a port backed by the completed coursework runner.
## Example: `var port: AuthoringRunPort = AuthoringRunPort.new(runner)`.
func _init(runner: CourseworkGvetRunnerType = null) -> void:
	_runner = runner

## Runs one already-frozen input and returns only its complete GVET result.
## Example: `var result: CourseworkRunResult = port.run(captured_input)`.
func run(captured_input: CourseworkRunInputType) -> CourseworkRunResultType:
	if _runner == null or not is_instance_valid(_runner):
		return null
	return _runner.run(captured_input)
