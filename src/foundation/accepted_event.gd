class_name AcceptedEvent
extends RefCounted

## Immutable accepted reducer event. Sequence order is assigned by the owner.

## GDScript has no language-level private fields. The underscored properties
## below are compatibility views. Construction writes their backing fields
## while unlocked, then permanently locks the instance before publication.

const U64_VALUE_TYPE = preload("res://src/foundation/u64_value.gd")
# Fixed synchronous safety boundary for Story 003; this is not a tuning/configuration claim.
const MAX_VALUE_NESTING_DEPTH: int = 64

var _locked: bool = false:
	set(value):
		if _locked:
			return
		_locked = value

var _sequence: String = "":
	get:
		return _sequence
	set(value):
		if _locked:
			return
		_sequence = value

var _command_id: StringName = &"":
	get:
		return _command_id
	set(value):
		if _locked:
			return
		_command_id = value

var _key: StringName = &"":
	get:
		return _key
	set(value):
		if _locked:
			return
		_key = value

var _value: Variant = null:
	get:
		return _clone_value(_value)
	set(value):
		if _locked:
			return
		_value = _clone_value(value)

var _valid: bool = false:
	set(value):
		if _locked:
			return
		_valid = value

var _error_code: StringName = &"invalid_event":
	set(value):
		if _locked:
			return
		_error_code = value

var _error_message: String = "event is invalid":
	set(value):
		if _locked:
			return
		_error_message = value

## Validates a payload and constructs a detached immutable event.
static func create(sequence: String, command_id: StringName, key: StringName, value: Variant) -> DomainResult:
	var sequence_result: DomainResult = U64_VALUE_TYPE.normalize(sequence)
	if not sequence_result.is_success():
		return sequence_result
	if command_id.is_empty() or key.is_empty():
		return DomainResult.failure(&"invalid_event", "sequence, command_id, and key are required")
	var copied_value: DomainResult = _copy_value(value)
	if not copied_value.is_success():
		return copied_value
	var event: AcceptedEvent = AcceptedEvent.new(sequence, command_id, key, copied_value.value())
	if not event.is_valid():
		return DomainResult.failure(event.validation_error_code(), event.validation_error_message())
	return DomainResult.success(event)

## Constructs a valid event for direct test vectors. Invalid payloads produce
## an invalid event; callers should use create() to receive its DomainResult.
func _init(sequence: String, command_id: StringName, key: StringName, value: Variant) -> void:
	_sequence = sequence
	_command_id = command_id
	_key = key
	var sequence_result: DomainResult = U64_VALUE_TYPE.normalize(sequence)
	if not sequence_result.is_success():
		_error_code = sequence_result.error_code()
		_error_message = sequence_result.error_message()
		_locked = true
		return
	if command_id.is_empty() or key.is_empty():
		_error_code = &"invalid_event"
		_error_message = "sequence, command_id, and key are required"
		_locked = true
		return
	var copied_value: DomainResult = _copy_value(value)
	if not copied_value.is_success():
		_error_code = copied_value.error_code()
		_error_message = copied_value.error_message()
		_locked = true
		return
	_sequence = String(sequence_result.value())
	_value = copied_value.value()
	_valid = true
	_locked = true

## Returns whether this event passed Foundation validation.
func is_valid() -> bool:
	return _valid

## Returns the validation diagnostic for an invalid direct construction.
func validation_error_code() -> StringName:
	return _error_code

## Returns the validation message for an invalid direct construction.
func validation_error_message() -> String:
	return _error_message

## Returns the owner-assigned monotonic sequence.
func sequence() -> String:
	return _sequence

## Returns the idempotency key.
func command_id() -> StringName:
	return _command_id

## Returns the committed field key.
func key() -> StringName:
	return _key

## Returns a defensive copy of the committed value.
func value() -> Variant:
	return _value

func _matches_command(key: StringName, value: Variant) -> bool:
	var copied_value: DomainResult = _copy_value(value)
	if not copied_value.is_success():
		return false
	return _key == key and _value == copied_value.value()

func _matches_event(other: AcceptedEvent) -> bool:
	return other != null and _sequence == other._sequence and _command_id == other._command_id \
		and _key == other._key and _value == other._value

## Returns a detached transport-shaped snapshot.
func to_dictionary() -> Dictionary:
	if not is_valid():
		return {}
	return {
		"sequence": sequence(),
		"command_id": command_id(),
		"key": key(),
		"value": value(),
	}

static func _copy_value(value: Variant) -> DomainResult:
	var active_containers: Array[Variant] = []
	return _copy_value_at_depth(value, 0, active_containers)

static func _copy_value_at_depth(value: Variant, depth: int, active_containers: Array[Variant]) -> DomainResult:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return DomainResult.success(value)
		TYPE_FLOAT:
			var numeric_value: float = value
			if is_nan(numeric_value) or is_inf(numeric_value):
				return DomainResult.failure(&"invalid_value", "event values must contain finite numbers")
			return DomainResult.success(value)
		TYPE_ARRAY:
			return _copy_array(value, depth, active_containers)
		TYPE_DICTIONARY:
			return _copy_dictionary(value, depth, active_containers)
		_:
			return DomainResult.failure(&"invalid_value", "event values must be Foundation-owned data")

static func _copy_array(value: Variant, depth: int, active_containers: Array[Variant]) -> DomainResult:
	if depth >= MAX_VALUE_NESTING_DEPTH:
		return DomainResult.failure(&"invalid_value", "event values exceed maximum nesting depth")
	if _contains_active_container(value, active_containers):
		return DomainResult.failure(&"invalid_value", "event values cannot contain reference cycles")
	active_containers.append(value)
	var copied_array: Array[Variant] = []
	for item: Variant in value:
		var copied_item: DomainResult = _copy_value_at_depth(item, depth + 1, active_containers)
		if not copied_item.is_success():
			return copied_item
		copied_array.append(copied_item.value())
	active_containers.pop_back()
	return DomainResult.success(copied_array)

static func _copy_dictionary(value: Variant, depth: int, active_containers: Array[Variant]) -> DomainResult:
	if depth >= MAX_VALUE_NESTING_DEPTH:
		return DomainResult.failure(&"invalid_value", "event values exceed maximum nesting depth")
	if _contains_active_container(value, active_containers):
		return DomainResult.failure(&"invalid_value", "event values cannot contain reference cycles")
	active_containers.append(value)
	var copied_dictionary: Dictionary[Variant, Variant] = {}
	for raw_key: Variant in value.keys():
		if typeof(raw_key) != TYPE_STRING and typeof(raw_key) != TYPE_STRING_NAME:
			return DomainResult.failure(&"invalid_value", "dictionary keys must be strings or StringNames")
		var copied_item: DomainResult = _copy_value_at_depth(value[raw_key], depth + 1, active_containers)
		if not copied_item.is_success():
			return copied_item
		copied_dictionary[raw_key] = copied_item.value()
	active_containers.pop_back()
	return DomainResult.success(copied_dictionary)

static func _contains_active_container(value: Variant, active_containers: Array[Variant]) -> bool:
	for active_value: Variant in active_containers:
		if is_same(active_value, value):
			return true
	return false

static func _clone_value(value: Variant) -> Variant:
	var copied_value: DomainResult = _copy_value(value)
	return copied_value.value() if copied_value.is_success() else null
