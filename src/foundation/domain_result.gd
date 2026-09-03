class_name DomainResult
extends RefCounted

## Closed result carrier for Foundation boundary operations.
##
## A result is either `accepted` with a value or `rejected` with one bounded
## diagnostic.  The diagnostic fields are deliberately data-only so callers
## can compare a rejection without depending on engine objects or callbacks.

var _ok: bool = false
var _value: Variant = null
var _diagnostic: Dictionary = {}

## Creates an accepted result.
## Example: `return DomainResult.success(validated_document)`.
static func success(value: Variant) -> DomainResult:
	var result := DomainResult.new()
	result._ok = true
	result._value = _copy_value(value)
	return result

## Creates a rejected result with a stable closed diagnostic.
## Example: `return DomainResult.failure(&"duplicate_member", "duplicate object member", "$.graph")`.
static func failure(error_code: StringName, error_message: String, path_witness: String = "", byte_offset: int = -1, inspected_byte_count: int = 0, allocation_disposition: StringName = &"record_not_allocated") -> DomainResult:
	var result := DomainResult.new()
	result._ok = false
	result._diagnostic = {
		"discriminant": &"rejected",
		"cause": error_code,
		"message": error_message,
		"path": path_witness,
		"byte_offset": byte_offset,
		"inspected_byte_count": inspected_byte_count,
		"allocation_disposition": allocation_disposition,
	}
	return result

## Returns whether the operation committed successfully.
func is_success() -> bool:
	return _ok

## Returns the closed result discriminant: `accepted` or `rejected`.
func discriminant() -> StringName:
	return &"accepted" if _ok else &"rejected"

## Returns the accepted value, defensively copied for collection values.
func value() -> Variant:
	return _copy_value(_value) if _ok else null

## Returns the diagnostic cause, or an empty name for an accepted result.
func error_code() -> StringName:
	return StringName(_diagnostic.get("cause", &""))

## Returns the bounded diagnostic message, or an empty string when accepted.
func error_message() -> String:
	return String(_diagnostic.get("message", ""))

## Returns a defensive copy of the complete closed diagnostic.
func diagnostic() -> Dictionary:
	return _diagnostic.duplicate(true)

## Returns the stable path witness carried by a rejection.
func path_witness() -> String:
	return String(_diagnostic.get("path", ""))

## Returns the first byte offset associated with a rejection, or -1.
func byte_offset() -> int:
	return int(_diagnostic.get("byte_offset", -1))

## Returns the number of bytes inspected before the rejection.
func inspected_byte_count() -> int:
	return int(_diagnostic.get("inspected_byte_count", 0))

## Returns the allocation disposition for the rejection.
func allocation_disposition() -> StringName:
	return StringName(_diagnostic.get("allocation_disposition", &"none"))

## Short alias for callers that name the witness `path`.
func path() -> String:
	return path_witness()

## Short alias for callers that name the inspected count `inspected_bytes`.
func inspected_bytes() -> int:
	return inspected_byte_count()

static func _copy_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_ARRAY, TYPE_DICTIONARY:
			return value.duplicate(true)
		TYPE_PACKED_BYTE_ARRAY:
			return PackedByteArray(value)
		_:
			return value
