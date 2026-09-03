class_name GraphDiagnostic
extends RefCounted

## Closed diagnostics for the typed graph-authoring boundary.
##
## Example: `return GraphDiagnostic.reject(&"invalid_task", "Task grid size must be between 8 and 32.")`.

var _code: StringName
var _message: String

func _init(code: StringName, message: String) -> void:
	_code = code
	_message = message

## Returns the stable reason code for this rejection.
## Example: `if diagnostic.code() == &"occupied_anchor": pass`.
func code() -> StringName:
	return _code

## Returns player-readable rejection text.
## Example: `var text: String = diagnostic.message()`.
func message() -> String:
	return _message

## Creates a Foundation-compatible rejected result.
## Example: `return GraphDiagnostic.reject(&"occupied_anchor", "The grid anchor is already occupied.")`.
static func reject(code: StringName, message: String) -> DomainResult:
	return DomainResult.failure(code, message)
