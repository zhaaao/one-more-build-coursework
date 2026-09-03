class_name GraphHistory
extends RefCounted

const GraphSnapshotType = preload("res://src/core/authoring/graph_snapshot.gd")

## Retains bounded immutable before/after graph snapshots for deterministic replay.
## Example: `history.commit(before_snapshot, after_snapshot)`.

const MAX_ENTRIES: int = 64

class HistoryEntry extends RefCounted:
	var _before: GraphSnapshotType
	var _after: GraphSnapshotType

	func _init(before: GraphSnapshotType, after: GraphSnapshotType) -> void:
		_before = before
		_after = after

	func before_snapshot() -> GraphSnapshotType:
		return _before

	func after_snapshot() -> GraphSnapshotType:
		return _after

var _undo_entries: Array[HistoryEntry] = []
var _redo_entries: Array[HistoryEntry] = []

## Records one accepted content operation and clears the abandoned Redo branch.
## Example: `history.commit(before, after)`.
func commit(before: GraphSnapshotType, after: GraphSnapshotType) -> void:
	_undo_entries.append(HistoryEntry.new(before, after))
	_redo_entries.clear()
	_trim_to_capacity()

## Moves the newest Undo entry to Redo and returns its immutable prior snapshot.
## Example: `var snapshot: GraphSnapshotType = history.undo_snapshot()`.
func undo_snapshot() -> GraphSnapshotType:
	if _undo_entries.is_empty():
		return null
	var entry: HistoryEntry = _undo_entries.pop_back()
	_redo_entries.append(entry)
	return entry.before_snapshot()

## Moves the newest Redo entry to Undo and returns its immutable later snapshot.
## Example: `var snapshot: GraphSnapshotType = history.redo_snapshot()`.
func redo_snapshot() -> GraphSnapshotType:
	if _redo_entries.is_empty():
		return null
	var entry: HistoryEntry = _redo_entries.pop_back()
	_undo_entries.append(entry)
	return entry.after_snapshot()

## Returns the number of currently reversible Undo entries.
## Example: `var undo_count: int = history.undo_count()`.
func undo_count() -> int:
	return _undo_entries.size()

## Returns the number of currently replayable Redo entries.
## Example: `var redo_count: int = history.redo_count()`.
func redo_count() -> int:
	return _redo_entries.size()

## Clears every retained entry, for task load, restore, or reset owners.
## Example: `history.clear()`.
func clear() -> void:
	_undo_entries.clear()
	_redo_entries.clear()

func _trim_to_capacity() -> void:
	while _undo_entries.size() + _redo_entries.size() > MAX_ENTRIES:
		_undo_entries.remove_at(0)
