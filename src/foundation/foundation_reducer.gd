class_name FoundationReducer
extends RefCounted

## Synchronous Foundation reducer with idempotent commands and sequence fences.

const U64_VALUE_TYPE = preload("res://src/foundation/u64_value.gd")
const MAX_SEQUENCE: String = U64_VALUE_TYPE.MAX_DECIMAL

const STATE_NEXT_SEQUENCE: StringName = &"next"
const STATE_SEQUENCE_EXHAUSTED: StringName = &"exhausted"
const STATE_VALUES: StringName = &"values"
const STATE_EVENTS: StringName = &"events"
const STATE_RETIREMENT_ID: StringName = &"retirement"

var _locked: bool = false:
	set(value):
		if _locked:
			return
		_locked = value

var _commit_operation: Callable:
	set(value):
		if _locked:
			return
		_commit_operation = value

var _accept_operation: Callable:
	set(value):
		if _locked:
			return
		_accept_operation = value

var _read_operation: Callable:
	set(value):
		if _locked:
			return
		_read_operation = value

var _next_sequence_operation: Callable:
	set(value):
		if _locked:
			return
		_next_sequence_operation = value

var _retire_operation: Callable:
	set(value):
		if _locked:
			return
		_retire_operation = value

# GDScript cannot make a constructor private; this optional seed is the minimum
# path for the underscored test factory. Public new() uses 1, and invalid,
# zero, or out-of-range seeds fall back to the production default.
func _init(initial_sequence: String = "1") -> void:
	var normalized: DomainResult = U64_VALUE_TYPE.normalize(initial_sequence)
	var canonical_sequence: String = "1"
	if normalized.is_success() and String(normalized.value()) != "0":
		canonical_sequence = String(normalized.value())
	var owner_state: Dictionary[StringName, Variant] = {}
	var values: Dictionary[StringName, Variant] = {}
	var events_by_command: Dictionary[StringName, AcceptedEvent] = {}
	owner_state[STATE_NEXT_SEQUENCE] = canonical_sequence
	owner_state[STATE_SEQUENCE_EXHAUSTED] = false
	owner_state[STATE_VALUES] = values
	owner_state[STATE_EVENTS] = events_by_command
	owner_state[STATE_RETIREMENT_ID] = &""
	_commit_operation = func(command_id: StringName, key: StringName, value: Variant) -> DomainResult:
		return FoundationReducer._commit_state(owner_state, command_id, key, value)
	_accept_operation = func(event: AcceptedEvent) -> DomainResult:
		return FoundationReducer._accept_state(owner_state, event)
	_read_operation = func(key: StringName) -> DomainResult:
		return FoundationReducer._read_state(owner_state, key)
	_next_sequence_operation = func() -> String:
		return String(owner_state[STATE_NEXT_SEQUENCE])
	_retire_operation = func(retirement_id: StringName) -> DomainResult:
		return FoundationReducer._retire_state(owner_state, retirement_id)
	_locked = true

## Test-only boundary fixture. Creates a separate reducer at a positive canonical u64 sequence.
static func _for_test_at_sequence(initial_sequence: String) -> DomainResult:
	var normalized: DomainResult = U64_VALUE_TYPE.normalize(initial_sequence)
	if not normalized.is_success():
		return normalized
	var canonical_sequence: String = String(normalized.value())
	if canonical_sequence == "0":
		return DomainResult.failure(&"invalid_test_sequence", "test fixture sequence must be positive")
	var reducer: FoundationReducer = FoundationReducer.new(canonical_sequence)
	return DomainResult.success(reducer)

## Commits a command exactly once and returns the accepted event.
func commit(command_id: StringName, key: StringName, value: Variant) -> DomainResult:
	return _commit_operation.call(command_id, key, value)

## Accepts one externally delivered event after the sequence fence.
func accept(event: AcceptedEvent) -> DomainResult:
	return _accept_operation.call(event)

static func _commit_state(owner_state: Dictionary[StringName, Variant], command_id: StringName, key: StringName, value: Variant) -> DomainResult:
	var events_by_command: Dictionary[StringName, AcceptedEvent] = owner_state[STATE_EVENTS]
	if command_id.is_empty():
		return DomainResult.failure(&"invalid_command", "command_id and key are required")
	var retirement_id: StringName = owner_state[STATE_RETIREMENT_ID]
	if not retirement_id.is_empty():
		return DomainResult.failure(&"retired", "reducer has already retired")
	if events_by_command.has(command_id):
		var existing: AcceptedEvent = events_by_command[command_id]
		if not existing._matches_command(key, value):
			return DomainResult.failure(&"duplicate_conflict", "command id is already bound to another event")
		return DomainResult.success(existing)
	if key.is_empty():
		return DomainResult.failure(&"invalid_command", "command_id and key are required")
	var sequence_exhausted: bool = owner_state[STATE_SEQUENCE_EXHAUSTED]
	if sequence_exhausted:
		return DomainResult.failure(&"sequence_exhausted", "reducer sequence has reached the u64 maximum")
	var next_sequence: String = owner_state[STATE_NEXT_SEQUENCE]
	var candidate_result: DomainResult = AcceptedEvent.create(next_sequence, command_id, key, value)
	if not candidate_result.is_success():
		return candidate_result
	var event: AcceptedEvent = candidate_result.value()
	var advance_result: DomainResult = _advance_state(owner_state)
	if not advance_result.is_success():
		return advance_result
	var values: Dictionary[StringName, Variant] = owner_state[STATE_VALUES]
	values[key] = event.value()
	events_by_command[command_id] = event
	return DomainResult.success(event)

static func _accept_state(owner_state: Dictionary[StringName, Variant], event: AcceptedEvent) -> DomainResult:
	if event == null:
		return DomainResult.failure(&"invalid_event", "event is required")
	var retirement_id: StringName = owner_state[STATE_RETIREMENT_ID]
	if not retirement_id.is_empty():
		return DomainResult.failure(&"retired", "reducer has already retired")
	var incoming_command_id: StringName = event.command_id()
	if incoming_command_id.is_empty():
		return DomainResult.failure(&"invalid_event", "command_id and key are required")
	var duplicate_result: DomainResult = _resolve_duplicate(owner_state, incoming_command_id, event)
	if not duplicate_result.is_success():
		return duplicate_result
	var duplicate_value: Variant = duplicate_result.value()
	if duplicate_value != null:
		var existing: AcceptedEvent = duplicate_value
		return DomainResult.success(existing)
	if not event.is_valid():
		return DomainResult.failure(event.validation_error_code(), event.validation_error_message())
	if event.key().is_empty():
		return DomainResult.failure(&"invalid_event", "command_id and key are required")
	var sequence_exhausted: bool = owner_state[STATE_SEQUENCE_EXHAUSTED]
	if sequence_exhausted:
		return DomainResult.failure(&"sequence_exhausted", "reducer sequence has reached the u64 maximum")
	return _accept_at_fence(owner_state, event)

static func _resolve_duplicate(owner_state: Dictionary[StringName, Variant], command_id: StringName, event: AcceptedEvent) -> DomainResult:
	var events_by_command: Dictionary[StringName, AcceptedEvent] = owner_state[STATE_EVENTS]
	if not events_by_command.has(command_id):
		return DomainResult.success(null)
	var existing: AcceptedEvent = events_by_command[command_id]
	if not event.is_valid() or not existing._matches_event(event):
		return DomainResult.failure(&"duplicate_conflict", "command id is already bound to another event")
	return DomainResult.success(existing)

static func _accept_at_fence(owner_state: Dictionary[StringName, Variant], event: AcceptedEvent) -> DomainResult:
	var candidate_result: DomainResult = AcceptedEvent.create(event.sequence(), event.command_id(), event.key(), event.value())
	if not candidate_result.is_success():
		return candidate_result
	var accepted_event: AcceptedEvent = candidate_result.value()
	var next_sequence: String = owner_state[STATE_NEXT_SEQUENCE]
	var ordering: int = _compare_u64(accepted_event.sequence(), next_sequence)
	if ordering < 0:
		return DomainResult.failure(&"stale_event", "event sequence is older than the fence")
	if ordering > 0:
		return DomainResult.failure(&"sequence_gap", "event sequence is ahead of the fence")
	var advance_result: DomainResult = _advance_state(owner_state)
	if not advance_result.is_success():
		return advance_result
	var values: Dictionary[StringName, Variant] = owner_state[STATE_VALUES]
	var events_by_command: Dictionary[StringName, AcceptedEvent] = owner_state[STATE_EVENTS]
	values[accepted_event.key()] = accepted_event.value()
	events_by_command[accepted_event.command_id()] = accepted_event
	return DomainResult.success(accepted_event)

## Reads the latest committed value without exposing mutable owner state.
func read(key: StringName) -> DomainResult:
	return _read_operation.call(key)

## Returns the next sequence expected by the reducer.
func next_sequence() -> String:
	return String(_next_sequence_operation.call())

## Retires the reducer exactly once; a duplicate retirement is idempotent.
func retire(retirement_id: StringName) -> DomainResult:
	return _retire_operation.call(retirement_id)

static func _read_state(owner_state: Dictionary[StringName, Variant], key: StringName) -> DomainResult:
	var values: Dictionary[StringName, Variant] = owner_state[STATE_VALUES]
	if not values.has(key):
		return DomainResult.failure(&"not_found", "key has no committed value")
	return DomainResult.success(_clone_value(values[key]))

static func _retire_state(owner_state: Dictionary[StringName, Variant], retirement_id: StringName) -> DomainResult:
	if retirement_id.is_empty():
		return DomainResult.failure(&"invalid_retirement", "retirement_id is required")
	var current_retirement_id: StringName = owner_state[STATE_RETIREMENT_ID]
	if current_retirement_id.is_empty():
		owner_state[STATE_RETIREMENT_ID] = retirement_id
		return DomainResult.success(retirement_id)
	if current_retirement_id == retirement_id:
		return DomainResult.success(retirement_id)
	return DomainResult.failure(&"retirement_conflict", "reducer already retired with another id")

static func _advance_state(owner_state: Dictionary[StringName, Variant]) -> DomainResult:
	var next_sequence: String = owner_state[STATE_NEXT_SEQUENCE]
	var next_result: DomainResult = _increment_u64(next_sequence)
	if next_result.is_success():
		owner_state[STATE_NEXT_SEQUENCE] = String(next_result.value())
		return DomainResult.success(null)
	if String(next_result.error_code()) == "sequence_exhausted":
		owner_state[STATE_SEQUENCE_EXHAUSTED] = true
		return DomainResult.success(null)
	return next_result

static func _clone_value(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value

static func _increment_u64(decimal: String) -> DomainResult:
	var normalized: DomainResult = U64_VALUE_TYPE.normalize(decimal)
	if not normalized.is_success():
		return normalized
	decimal = String(normalized.value())
	if decimal == MAX_SEQUENCE:
		return DomainResult.failure(&"sequence_exhausted", "reducer sequence has reached the u64 maximum")
	var digits: String = "0123456789"
	var result: String = ""
	var carry: int = 1
	for index: int in range(decimal.length() - 1, -1, -1):
		var digit: int = decimal.unicode_at(index) - 48 + carry
		if digit >= 10:
			digit -= 10
			carry = 1
		else:
			carry = 0
		result = digits.substr(digit, 1) + result
	if carry == 1:
		result = "1" + result
	return DomainResult.success(result)

static func _compare_u64(left: String, right: String) -> int:
	if left.length() < right.length():
		return -1
	if left.length() > right.length():
		return 1
	for index: int in range(left.length()):
		var left_digit: int = left.unicode_at(index)
		var right_digit: int = right.unicode_at(index)
		if left_digit < right_digit:
			return -1
		if left_digit > right_digit:
			return 1
	return 0
