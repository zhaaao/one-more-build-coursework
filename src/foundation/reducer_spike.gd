class_name ReducerSpike
extends RefCounted

## Deterministic setup spike for the proposed reducer contract.
## It is intentionally not a gameplay system and has no SceneTree dependency.

var _sequence: int = 0
var _values: Dictionary = {}
var _committed_commands: Dictionary = {}

## Applies a command exactly once. Repeating the same command ID is idempotent.
func apply(command_id: StringName, key: StringName, value: Variant) -> DomainResult:
    if command_id.is_empty() or key.is_empty():
        return DomainResult.failure(&"invalid_command", "command_id and key are required")

    if _committed_commands.has(command_id):
        return DomainResult.success(_committed_commands[command_id])

    _sequence += 1
    var commit := {
        "sequence": _sequence,
        "command_id": command_id,
        "key": key,
        "value": value,
    }
    _values[key] = value
    _committed_commands[command_id] = commit
    return DomainResult.success(commit)

## Returns the latest accepted sequence number.
func latest_sequence() -> int:
    return _sequence

## Reads a committed value without exposing the mutable backing dictionary.
func read(key: StringName) -> DomainResult:
    if not _values.has(key):
        return DomainResult.failure(&"not_found", "key has no committed value")
    return DomainResult.success(_values[key])
