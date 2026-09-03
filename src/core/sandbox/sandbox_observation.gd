class_name SandboxObservation
extends RefCounted

## Stable raw facts derived from exactly one immutable Sandbox case state.
##
## This Story 005 seam intentionally exposes simulation facts only. It never
## derives Workday, Career, grading, reputation, defect, optimality, or ending
## values. Callers receive a detached Dictionary in the GDD-defined fact order.

const SandboxCaseStateType = preload("res://src/core/sandbox/sandbox_case_state.gd")
const SandboxCaseAdmissionType = preload("res://src/core/sandbox/sandbox_case_admission.gd")

const ABSENT: StringName = &"none"
const DELIVERY_SLOT_COUNT: int = 12
const FRONT_KIND_CANDIDATES: Array[Dictionary] = [
	{"field": "crates", "kind": &"crate"}, {"field": "obstacles", "kind": &"obstacle"},
	{"field": "doors", "kind": &"door"}, {"field": "docks", "kind": &"dock"},
	{"field": "conveyors", "kind": &"conveyor"}, {"field": "sensors", "kind": &"sensor"},
]
const FACT_ORDER: Array[String] = [
	"bot_x", "bot_y", "bot_orientation", "battery_units",
	"front_entity_kind", "front_package_colour", "front_door_state", "front_sensor_state", "path_clear", "front_dock_kind",
	"current_dock_kind", "current_cell_sensor_state", "inventory_count", "inventory_front_package_colour",
	"delivered_count", "last_delivered_colour", "remaining_package_count",
	"delivery_slot_1", "delivery_slot_2", "delivery_slot_3", "delivery_slot_4", "delivery_slot_5", "delivery_slot_6",
	"delivery_slot_7", "delivery_slot_8", "delivery_slot_9", "delivery_slot_10", "delivery_slot_11", "delivery_slot_12",
]

## Returns the complete stable observation for one admitted state.
## Example: `var facts := SandboxObservation.derive(state)`.
static func derive(state: SandboxCaseStateType) -> Dictionary:
	if state == null or not state.is_valid():
		return {}
	return derive_projection(state.projection())

## Returns facts for one detached projection after full invariant revalidation.
## This supports reducers that already captured exactly one state projection.
static func derive_projection(record: Dictionary) -> Dictionary:
	if not SandboxCaseAdmissionType.validate_definition(record).is_success():
		return {}
	return _derive_record(record)

static func _derive_record(record: Dictionary) -> Dictionary:
	var bot: Dictionary = Dictionary(record["bot"])
	var front: Dictionary = _front_cell(bot)
	var front_package: Dictionary = _world_package_at(record, front)
	var front_door: Dictionary = _entity_at(_dictionary_records(record["doors"]), front)
	var front_sensor: Dictionary = _entity_at(_dictionary_records(record["sensors"]), front)
	var front_dock: Dictionary = _entity_at(_dictionary_records(record["docks"]), front)
	var current: Dictionary = {"x": int(bot["x"]), "y": int(bot["y"])}
	var inventory: Array[String] = _string_values(record["inventory"])
	var deliveries: Array[Dictionary] = _dictionary_records(record["deliveries"])
	var world_packages: Array[Dictionary] = _dictionary_records(record["world_packages"])
	var facts: Dictionary = {"fact_order": FACT_ORDER.duplicate()}
	var values: Dictionary = {
		"bot_x": int(bot["x"]), "bot_y": int(bot["y"]), "bot_orientation": String(bot["orientation"]), "battery_units": int(bot["battery_units"]),
		"front_entity_kind": _front_kind(record, front, front_package), "front_package_colour": _package_colour(record, String(front_package.get("package_id", ""))),
		"front_door_state": _door_state(front_door), "front_sensor_state": _sensor_state(record, front_sensor, front), "path_clear": _path_is_clear(record, front), "front_dock_kind": _dock_kind(front_dock),
		"current_dock_kind": _dock_kind(_entity_at(_dictionary_records(record["docks"]), current)), "current_cell_sensor_state": _sensor_state(record, _entity_at(_dictionary_records(record["sensors"]), current), current),
		"inventory_count": inventory.size(), "inventory_front_package_colour": _package_colour(record, String(inventory[0]) if not inventory.is_empty() else ""),
		"delivered_count": deliveries.size(), "last_delivered_colour": _last_delivery_colour(record, deliveries), "remaining_package_count": world_packages.size() + inventory.size(),
	}
	_append_delivery_slots(values, record, deliveries)
	for fact_name: String in FACT_ORDER:
		facts[fact_name] = values[fact_name]
	return facts

static func _append_delivery_slots(facts: Dictionary, record: Dictionary, deliveries: Array[Dictionary]) -> void:
	for slot: int in range(1, DELIVERY_SLOT_COUNT + 1):
		var package_id: String = ""
		if slot <= deliveries.size():
			package_id = String(Dictionary(deliveries[slot - 1]).get("package_id", ""))
		facts["delivery_slot_%d" % slot] = _package_colour(record, package_id)

static func _front_kind(record: Dictionary, front: Dictionary, front_package: Dictionary) -> StringName:
	if not front_package.is_empty():
		return &"package"
	for candidate: Dictionary in FRONT_KIND_CANDIDATES:
		if not _entity_at(_dictionary_records(record[String(candidate["field"])]), front).is_empty():
			return candidate["kind"]
	return ABSENT

static func _package_colour(record: Dictionary, package_id: String) -> StringName:
	if package_id.is_empty():
		return ABSENT
	for package: Dictionary in _dictionary_records(record["packages"]):
		if String(package["id"]) == package_id:
			return StringName(String(package["color"]))
	return ABSENT

static func _last_delivery_colour(record: Dictionary, deliveries: Array[Dictionary]) -> StringName:
	if deliveries.is_empty():
		return ABSENT
	return _package_colour(record, String(Dictionary(deliveries.back())["package_id"]))

static func _door_state(door: Dictionary) -> StringName:
	if door.is_empty():
		return ABSENT
	return &"open" if bool(door["is_open"]) else &"closed"

static func _sensor_state(record: Dictionary, sensor: Dictionary, cell: Dictionary) -> StringName:
	if sensor.is_empty():
		return ABSENT
	return &"active" if not _world_package_at(record, cell).is_empty() else &"inactive"

static func _dock_kind(dock: Dictionary) -> StringName:
	return StringName(String(dock["kind"])) if not dock.is_empty() else ABSENT

static func _path_is_clear(record: Dictionary, cell: Dictionary) -> bool:
	var grid: Dictionary = Dictionary(record["grid"])
	if int(cell["x"]) < 0 or int(cell["x"]) >= int(grid["width"]) or int(cell["y"]) < 0 or int(cell["y"]) >= int(grid["height"]):
		return false
	if not _entity_at(_dictionary_records(record["crates"]), cell).is_empty() or not _entity_at(_dictionary_records(record["obstacles"]), cell).is_empty() or not _world_package_at(record, cell).is_empty():
		return false
	var door: Dictionary = _entity_at(_dictionary_records(record["doors"]), cell)
	return door.is_empty() or bool(door["is_open"])

static func _front_cell(bot: Dictionary) -> Dictionary:
	match String(bot["orientation"]):
		"east": return {"x": int(bot["x"]) + 1, "y": int(bot["y"])}
		"south": return {"x": int(bot["x"]), "y": int(bot["y"]) + 1}
		"west": return {"x": int(bot["x"]) - 1, "y": int(bot["y"])}
		_: return {"x": int(bot["x"]), "y": int(bot["y"]) - 1}

static func _entity_at(entities: Array[Dictionary], cell: Dictionary) -> Dictionary:
	for entity: Dictionary in entities:
		if int(entity["x"]) == int(cell["x"]) and int(entity["y"]) == int(cell["y"]):
			return entity
	return {}

static func _world_package_at(record: Dictionary, cell: Dictionary) -> Dictionary:
	return _entity_at(_dictionary_records(record["world_packages"]), cell)

static func _dictionary_records(source: Variant) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for raw_value: Variant in Array(source):
		records.append(Dictionary(raw_value).duplicate(true))
	return records

static func _string_values(source: Variant) -> Array[String]:
	var values: Array[String] = []
	for raw_value: Variant in Array(source):
		values.append(String(raw_value))
	return values
