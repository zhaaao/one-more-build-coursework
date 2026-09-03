class_name RuntimeMutationReceipt
extends RefCounted

## Closed validated result of one serialized runtime mutation attempt.

const COMMITTED: String = "committed"
const ILLEGAL_OCCUPANCY: String = "illegal_occupancy"
const STALE_GENERATION: String = "stale_generation"
const REENTRANT_REJECTED: String = "reentrant_rejected"
const IDEMPOTENCY_CONFLICT: String = "idempotency_conflict"
const INVALID_COMMAND: String = "invalid_command"

var _sealed: bool = false:
	set(value):
		if _sealed:
			return
		_sealed = value
var _valid: bool = false:
	set(value):
		if _sealed:
			return
		_valid = value
var _disposition: String = INVALID_COMMAND:
	set(value):
		if _sealed:
			return
		_disposition = value
var _command_id: String = "":
	set(value):
		if _sealed:
			return
		_command_id = value
var _idempotency_key: String = "":
	set(value):
		if _sealed:
			return
		_idempotency_key = value
var _fingerprint: String = "":
	set(value):
		if _sealed:
			return
		_fingerprint = value
var _commit_id: String = "":
	set(value):
		if _sealed:
			return
		_commit_id = value
var _generation: int = 0:
	set(value):
		if _sealed:
			return
		_generation = value
var _state_root: String = "":
	set(value):
		if _sealed:
			return
		_state_root = value
var _accepted: bool = false:
	set(value):
		if _sealed:
			return
		_accepted = value


## Constructs the only accepted receipt arm, deriving its root from snapshot.
static func committed_for(
	command: RuntimeMutationCommand,
	commit_id: String,
	snapshot: RuntimeSessionSnapshot
) -> RuntimeMutationReceipt:
	if not _valid_commit_inputs(command, commit_id, snapshot):
		return null
	var correlations: PackedStringArray = snapshot.correlation_ids()
	if command.expected_generation() + 1 != snapshot.generation():
		return null
	if correlations[0] != command.command_id() or correlations[1] != command.idempotency_key():
		return null
	return new(COMMITTED, command, commit_id, snapshot)


## Constructs a closed no-mutation receipt with a validated disposition.
static func rejected_for(
	disposition: String,
	command: RuntimeMutationCommand,
	snapshot: RuntimeSessionSnapshot
) -> RuntimeMutationReceipt:
	if snapshot == null or not snapshot.is_valid() or not _is_valid_rejection(disposition):
		return null
	if disposition != INVALID_COMMAND and (command == null or not command.is_valid()):
		return null
	return new(disposition, command, "", snapshot)


## Returns a closed invalid-command receipt for an unavailable owner.
static func invalid_command() -> RuntimeMutationReceipt:
	return new(INVALID_COMMAND, null, "", null)


## Returns the closed disposition.
func disposition() -> String:
	return _disposition


## Alias for outcome terminology.
func outcome() -> String:
	return _disposition


## Returns the command correlation ID.
func command_id() -> String:
	return _command_id


## Returns the idempotency key.
func idempotency_key() -> String:
	return _idempotency_key


## Returns the canonical command fingerprint.
func fingerprint() -> String:
	return _fingerprint


## Returns the commit ID, or empty when no commit occurred.
func commit_id() -> String:
	return _commit_id


## Returns the resulting or unchanged generation.
func generation() -> int:
	return _generation


## Returns the resulting or unchanged canonical state root.
func state_root() -> String:
	return _state_root


## Returns true only for the committed arm.
func accepted() -> bool:
	return _accepted


## Alias for commit terminology.
func committed() -> bool:
	return _accepted


## Returns true only for validated factory outcomes.
func is_closed() -> bool:
	return _sealed and _valid


## Returns whether this value passed a closed factory.
func is_valid() -> bool:
	return _valid


## Returns true for a key conflict.
func is_conflict() -> bool:
	return is_closed() and _disposition == IDEMPOTENCY_CONFLICT


## Returns true for the accepted arm.
func is_exact_commit() -> bool:
	return is_closed() and _disposition == COMMITTED and _accepted


func _init(
	disposition: String = "",
	command: RuntimeMutationCommand = null,
	commit_id: String = "",
	snapshot: RuntimeSessionSnapshot = null
) -> void:
	if disposition.is_empty() and command == null and snapshot == null and commit_id.is_empty():
		_sealed = true
		return
	if disposition == INVALID_COMMAND and command == null and snapshot == null and commit_id.is_empty():
		_valid = true
		_sealed = true
		return
	if disposition == COMMITTED:
		_valid = _initialize_commit(command, commit_id, snapshot)
		_sealed = true
		return
	_valid = _initialize_rejection(disposition, command, snapshot)
	_sealed = true


func _initialize_commit(
	command: RuntimeMutationCommand,
	commit_id: String,
	snapshot: RuntimeSessionSnapshot
) -> bool:
	if not _valid_commit_inputs(command, commit_id, snapshot):
		return false
	var correlations: PackedStringArray = snapshot.correlation_ids()
	if command.expected_generation() + 1 != snapshot.generation():
		return false
	if correlations[0] != command.command_id() or correlations[1] != command.idempotency_key():
		return false
	_disposition = COMMITTED
	_command_id = command.command_id()
	_idempotency_key = command.idempotency_key()
	_fingerprint = command.fingerprint()
	_commit_id = commit_id
	_generation = snapshot.generation()
	_state_root = snapshot.state_root()
	_accepted = true
	return true


func _initialize_rejection(
	disposition: String,
	command: RuntimeMutationCommand,
	snapshot: RuntimeSessionSnapshot
) -> bool:
	if not _is_valid_rejection(disposition) or snapshot == null or not snapshot.is_valid():
		return false
	if disposition != INVALID_COMMAND and (command == null or not command.is_valid()):
		return false
	_disposition = disposition
	if command != null and command.is_valid():
		_command_id = command.command_id()
		_idempotency_key = command.idempotency_key()
		_fingerprint = command.fingerprint()
		_generation = snapshot.generation()
		_state_root = snapshot.state_root()
	_accepted = false
	return true


static func _valid_commit_inputs(
	command: RuntimeMutationCommand,
	commit_id: String,
	snapshot: RuntimeSessionSnapshot
) -> bool:
	if command == null or not command.is_valid():
		return false
	if commit_id.is_empty() or not commit_id.begins_with("gvet-commit-"):
		return false
	if snapshot == null or not snapshot.is_valid() or snapshot.generation() <= 0:
		return false
	if snapshot.last_commit_id() != commit_id or snapshot.correlation_ids().size() != 2:
		return false
	return true


static func _is_valid_rejection(disposition: String) -> bool:
	match disposition:
		ILLEGAL_OCCUPANCY, STALE_GENERATION, REENTRANT_REJECTED, IDEMPOTENCY_CONFLICT, INVALID_COMMAND:
			return true
		_:
			return false
