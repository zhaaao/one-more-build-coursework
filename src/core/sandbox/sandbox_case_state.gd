class_name SandboxCaseState
extends RefCounted

## Frozen pure-domain state for one admitted Parcel Bot Sandbox case.
##
## The state is constructed only by `SandboxCaseAdmission` after all bounded
## construction rules have passed. Public accessors always return detached data.

var _record: Dictionary = {}
var _locked: bool = false

func _init() -> void:
	# Direct construction is intentionally inert; only admission may freeze a state.
	pass

static func _from_validated_record(validated_record: Dictionary) -> SandboxCaseState:
	var state := new()
	state._record = validated_record.duplicate(true)
	state._locked = not state._record.is_empty()
	return state

## Returns whether this state was produced by the validated construction seam.
## Example: `assert(state.is_valid())`.
func is_valid() -> bool:
	return _locked

## Returns the immutable public case identity.
## Example: `var id := state.case_id()`.
func case_id() -> String:
	return String(_record.get("case_id", ""))

## Returns a detached complete state projection for a later pure reducer.
## Example: `var next_input := state.projection()`.
func projection() -> Dictionary:
	return _record.duplicate(true)

## Returns a detached bot projection including position and battery fields.
## Example: `var battery := state.bot()["battery_units"]`.
func bot() -> Dictionary:
	return Dictionary(_record.get("bot", {})).duplicate(true)

## Returns the detached FIFO inventory package identifiers.
## Example: `var first_package := state.inventory()[0]`.
func inventory() -> Array[String]:
	var copied: Array[String] = []
	for package_id: Variant in Array(_record.get("inventory", [])):
		copied.append(String(package_id))
	return copied

## Returns detached contiguous delivery records in delivery-index order.
## Example: `var deliveries := state.deliveries()`.
func deliveries() -> Array[Dictionary]:
	var copied: Array[Dictionary] = []
	for delivery: Variant in Array(_record.get("deliveries", [])):
		copied.append(Dictionary(delivery).duplicate(true))
	return copied

## Returns detached world package placements.
## Example: `var world_packages := state.world_packages()`.
func world_packages() -> Array[Dictionary]:
	var copied: Array[Dictionary] = []
	for world_package: Variant in Array(_record.get("world_packages", [])):
		copied.append(Dictionary(world_package).duplicate(true))
	return copied
