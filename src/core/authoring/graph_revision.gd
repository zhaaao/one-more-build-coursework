class_name GraphRevision
extends RefCounted

const GraphDiagnostic = preload("res://src/core/authoring/graph_diagnostic.gd")

## Owns the positive, session-local revision identity for accepted graph content.
## Example: `var result: DomainResult = revision.allocate_next()`.

const INITIAL_REVISION: int = 1

var _live_revision: int = INITIAL_REVISION

## Constructs a revision allocator at a positive session-local identity.
## Example: `var revision := GraphRevision.new(GraphRevision.INITIAL_REVISION)`.
func _init(initial_revision: int = INITIAL_REVISION) -> void:
	if initial_revision > 0:
		_live_revision = initial_revision

## Creates a revision allocator only for a representable positive identity.
## Example: `var result: DomainResult = GraphRevision.create_at(12)`.
static func create_at(initial_revision: int) -> DomainResult:
	if initial_revision <= 0:
		return GraphDiagnostic.reject(&"invalid_revision", "A graph revision must be positive.")
	return DomainResult.success(new(initial_revision))

## Returns the current positive graph revision.
## Example: `var revision_id: int = revision.live_revision()`.
func live_revision() -> int:
	return _live_revision

## Returns whether another positive revision can be allocated without overflow.
## Example: `if revision.can_allocate(): revision.allocate_next()`.
func can_allocate() -> bool:
	return _live_revision < 9223372036854775807

## Allocates the next monotonic revision, or rejects before integer overflow.
## Example: `var result: DomainResult = revision.allocate_next()`.
func allocate_next() -> DomainResult:
	if _live_revision == 9223372036854775807:
		return GraphDiagnostic.reject(&"revision_exhausted", "The session cannot allocate another graph revision.")
	_live_revision += 1
	return DomainResult.success(_live_revision)
