class_name CourseworkRepeatFrame
extends RefCounted

## Immutable process-local counter for one active coursework Repeat node.

const DomainResultType = preload("res://src/foundation/domain_result.gd")

var _locked: bool = false:
	set(value):
		if not _locked:
			_locked = value
var _node_id: String = "":
	set(value):
		if not _locked:
			_node_id = value
var _count: int = 0:
	set(value):
		if not _locked:
			_count = value
var _iteration: int = -1:
	set(value):
		if not _locked:
			_iteration = value

## Creates the first iteration of a positive-count Repeat.
## Example: `var frame_result: DomainResult = CourseworkRepeatFrame.create("repeat.1", 3)`.
static func create(node_id: Variant, count: Variant) -> DomainResult:
	if typeof(node_id) != TYPE_STRING or String(node_id).is_empty():
		return DomainResultType.failure(&"invalid_repeat_frame", "Repeat node_id is required")
	if typeof(count) != TYPE_INT or int(count) < 1:
		return DomainResultType.failure(&"invalid_repeat_frame", "Repeat count must be positive")
	return DomainResultType.success(CourseworkRepeatFrame.new(String(node_id), int(count), 0))

func _init(node_id: String = "", count: int = 0, iteration: int = -1) -> void:
	_node_id = node_id
	_count = count
	_iteration = iteration
	_locked = is_valid()

## Returns whether this frame contains a valid active iteration.
## Example: `assert(frame.is_valid())`.
func is_valid() -> bool:
	return not _node_id.is_empty() and _count > 0 and _iteration >= 0 and _iteration < _count

## Returns the owning Repeat node identity.
## Example: `assert(frame.node_id() == "repeat.1")`.
func node_id() -> String:
	return _node_id

## Returns the fixed authored iteration count.
## Example: `assert(frame.count() == 3)`.
func count() -> int:
	return _count

## Returns the active zero-based iteration.
## Example: `assert(frame.iteration() == 0)`.
func iteration() -> int:
	return _iteration

## Returns true when `advance()` can create another immutable iteration.
## Example: `if frame.has_next_iteration(): frame.advance()`.
func has_next_iteration() -> bool:
	return is_valid() and _iteration + 1 < _count

## Returns a new frame for the next iteration without mutating this frame.
## Example: `var next_frame: CourseworkRepeatFrame = frame.advance().value()`.
func advance() -> DomainResult:
	if not has_next_iteration():
		return DomainResultType.failure(&"repeat_complete", "Repeat frame has no next iteration")
	return DomainResultType.success(
		CourseworkRepeatFrame.new(_node_id, _count, _iteration + 1))
