class_name CourseworkSavePort
extends RefCounted

## Typed Core persistence boundary for complete stable checkpoints.
## Platform adapters implement this port; Feature code depends only on this
## contract and never on a platform filesystem implementation.
##
## Example:
## ```gdscript
## var port: CourseworkSavePort = CourseworkWindowsGenerationSafeSavePort.new(root_path)
## var observed: DomainResult = port.observe_slot(&"manual.1")
## ```

const DomainResult = preload("res://src/foundation/domain_result.gd")
const StableCheckpoint = preload("res://src/core/save_recovery/coursework_five_section_stable_checkpoint.gd")

## Publishes one already-admitted whole checkpoint for a fixed slot.
## Example: `port.save_checkpoint(&"manual.1", "generation-opaque", checkpoint)`.
func save_checkpoint(_slot_id: StringName, _generation_id: String, _checkpoint: StableCheckpoint) -> DomainResult:
	return DomainResult.failure(&"save_port_unimplemented", "SavePort must be implemented by a platform adapter")

## Observes detached current and previous generation records for a fixed slot.
## Example: `var observed: DomainResult = port.observe_slot(&"manual.1")`.
func observe_slot(_slot_id: StringName) -> DomainResult:
	return DomainResult.failure(&"save_port_unimplemented", "SavePort must be implemented by a platform adapter")

## Durably removes both retained roles for one fixed slot.
## Example: `var deleted: DomainResult = port.delete_slot(&"manual.1")`.
func delete_slot(_slot_id: StringName) -> DomainResult:
	return DomainResult.failure(&"save_port_unimplemented", "SavePort must be implemented by a platform adapter")
