class_name SandboxCaseAdmission
extends RefCounted

## Deterministic validation and static fixture admission for Parcel Bot cases.
##
## This class owns the construction-time rules only. It does not implement an
## Action, Query, pathfinding API, cache, engine object, or external I/O.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const SandboxCaseStateType = preload("res://src/core/sandbox/sandbox_case_state.gd")

const MIN_GRID_AXIS: int = 1
const MAX_GRID_AXIS: int = 32
const MAX_BFS_VISITS: int = 1024
const MIN_PACKAGE_COUNT: int = 1
const MAX_PACKAGE_COUNT: int = 16
const MAX_ASSIGNMENT_PACKAGE_COUNT: int = 12
# These ceilings and colours are fixed GDD schema contracts, not task-tunable values.
const ADMITTED_COLOURS: Array[String] = ["blue", "green", "orange", "purple", "red", "yellow"]

## Validates, detaches, and freezes one bounded case definition.
## Example: `var result := SandboxCaseAdmission.admit(case_definition)`.
static func admit(case_definition: Variant) -> DomainResult:
	var validation: DomainResult = validate_definition(case_definition)
	if not validation.is_success():
		return validation
	var state: SandboxCaseStateType = SandboxCaseStateType._from_validated_record(Dictionary(case_definition).duplicate(true))
	if not state.is_valid():
		return _failure(&"case_state_not_created", "validated case state did not lock")
	return DomainResultType.success(state)

## Validates a definition without allocating or exposing a case state.
## Example: `var admitted := SandboxCaseAdmission.validate_definition(definition)`.
static func validate_definition(case_definition: Variant) -> DomainResult:
	if typeof(case_definition) != TYPE_DICTIONARY:
		return _failure(&"case_shape_invalid", "case definition must be a Dictionary")
	var definition: Dictionary = case_definition
	var shape: DomainResult = _validate_case_shape(definition)
	if not shape.is_success():
		return shape
	var scalar: DomainResult = _validate_scalars(definition)
	if not scalar.is_success():
		return scalar
	var entities: DomainResult = _validate_entities(definition)
	if not entities.is_success():
		return entities
	var partition: DomainResult = _validate_package_partition(definition)
	if not partition.is_success():
		return partition
	return _validate_static_reachability(definition)

static func _validate_case_shape(definition: Dictionary) -> DomainResult:
	var fields: Array[String] = [
		"case_id", "assignment_floor", "charge_enabled", "grid", "bot", "packages",
		"world_packages", "inventory", "deliveries", "crates", "obstacles", "doors",
		"conveyors", "docks", "sensors",
	]
	if not _has_exact_keys(definition, fields):
		return _failure(&"case_shape_invalid", "case definition fields are not exact")
	for field: String in ["packages", "world_packages", "inventory", "deliveries", "crates", "obstacles", "doors", "conveyors", "docks", "sensors"]:
		if typeof(definition[field]) != TYPE_ARRAY:
			return _failure(&"case_shape_invalid", "%s must be an Array" % field)
	if typeof(definition["grid"]) != TYPE_DICTIONARY or typeof(definition["bot"]) != TYPE_DICTIONARY:
		return _failure(&"case_shape_invalid", "grid and bot must be dictionaries")
	return DomainResultType.success(true)

static func _validate_scalars(definition: Dictionary) -> DomainResult:
	if not _is_stable_id(definition["case_id"]):
		return _failure(&"case_identity_invalid", "case_id must be a stable ASCII identifier")
	if typeof(definition["assignment_floor"]) != TYPE_BOOL or typeof(definition["charge_enabled"]) != TYPE_BOOL:
		return _failure(&"case_shape_invalid", "assignment_floor and charge_enabled must be booleans")
	var grid: Dictionary = definition["grid"]
	if not _has_exact_keys(grid, ["width", "height"]) or not _in_range(grid.get("width"), MIN_GRID_AXIS, MAX_GRID_AXIS) or not _in_range(grid.get("height"), MIN_GRID_AXIS, MAX_GRID_AXIS):
		return _failure(&"grid_bounds_invalid", "grid width and height must be integers between 1 and 32")
	var bot: Dictionary = definition["bot"]
	if not _has_exact_keys(bot, ["id", "x", "y", "orientation", "battery_units", "battery_capacity", "inventory_capacity"]):
		return _failure(&"bot_shape_invalid", "bot fields are not exact")
	if not _is_stable_id(bot.get("id")) or not _coordinate_is_in_bounds(bot, grid):
		return _failure(&"bot_bounds_invalid", "bot identity or coordinate is invalid")
	if not ["east", "north", "south", "west"].has(bot.get("orientation")):
		return _failure(&"bot_orientation_invalid", "bot orientation must be cardinal")
	if not _in_range(bot.get("battery_capacity"), 1, 100) or typeof(bot.get("battery_units")) != TYPE_INT or int(bot["battery_units"]) < 0 or int(bot["battery_units"]) > int(bot["battery_capacity"]):
		return _failure(&"battery_bounds_invalid", "battery units must be between zero and capacity")
	var package_limit: int = MAX_ASSIGNMENT_PACKAGE_COUNT if bool(definition["assignment_floor"]) else MAX_PACKAGE_COUNT
	if Array(definition["packages"]).size() < MIN_PACKAGE_COUNT or Array(definition["packages"]).size() > package_limit:
		return _failure(&"package_count_invalid", "package count exceeds the admitted case limit")
	return DomainResultType.success(true)

static func _validate_entities(definition: Dictionary) -> DomainResult:
	var grid: Dictionary = definition["grid"]
	var identities: Dictionary = {}
	var bot: Dictionary = definition["bot"]
	identities[String(bot["id"])] = true
	var packages: Array = definition["packages"]
	var package_ids: Dictionary = {}
	for raw_package: Variant in packages:
		if typeof(raw_package) != TYPE_DICTIONARY or not _has_exact_keys(raw_package, ["id", "color"]):
			return _failure(&"package_shape_invalid", "package fields are not exact")
		var package: Dictionary = raw_package
		if not _is_stable_id(package.get("id")):
			return _failure(&"package_identity_invalid", "package identity must be a stable identifier")
		if not _is_admitted_colour(package.get("color")):
			return _failure(&"package_colour_invalid", "package colour must be an admitted fixed colour")
		var package_id: String = String(package["id"])
		if identities.has(package_id):
			return _failure(&"entity_identity_duplicate", "entity identities must be unique")
		identities[package_id] = true
		package_ids[package_id] = true
	var collection_result: DomainResult = _validate_positioned_collections(definition, identities, grid)
	if not collection_result.is_success():
		return collection_result
	return _validate_floor_and_structure_occupancy(definition, grid)

static func _validate_positioned_collections(definition: Dictionary, identities: Dictionary, grid: Dictionary) -> DomainResult:
	var specifications: Array[Dictionary] = [
		{"field": "crates", "max": 16, "keys": ["id", "x", "y"]},
		{"field": "obstacles", "max": 64, "keys": ["id", "x", "y"]},
		{"field": "doors", "max": 16, "keys": ["id", "x", "y", "is_open"]},
		{"field": "conveyors", "max": 32, "keys": ["id", "x", "y", "direction"]},
		{"field": "docks", "max": 16, "keys": ["id", "x", "y", "kind", "capacity", "accepted_color"]},
		{"field": "sensors", "max": 16, "keys": ["id", "x", "y", "color"]},
	]
	for specification: Dictionary in specifications:
		var collection_result: DomainResult = _validate_positioned_collection(definition, specification, identities, grid)
		if not collection_result.is_success():
			return collection_result
	return _validate_dock_requirements(definition)

static func _validate_positioned_collection(definition: Dictionary, specification: Dictionary, identities: Dictionary, grid: Dictionary) -> DomainResult:
	var field: String = specification["field"]
	var values: Array = definition[field]
	if values.size() > int(specification["max"]):
		return _failure(&"entity_count_invalid", "%s exceeds its admitted limit" % field)
	for raw_value: Variant in values:
		var entity_result: DomainResult = _validate_positioned_entity(field, raw_value, specification["keys"], identities, grid)
		if not entity_result.is_success():
			return entity_result
	return DomainResultType.success(true)

static func _validate_positioned_entity(field: String, raw_value: Variant, keys: Array, identities: Dictionary, grid: Dictionary) -> DomainResult:
	if typeof(raw_value) != TYPE_DICTIONARY:
		return _failure(&"entity_shape_invalid", "%s entity fields are not exact" % field)
	var entity: Dictionary = raw_value
	if not _has_exact_keys(entity, keys):
		return _failure(&"entity_shape_invalid", "%s entity fields are not exact" % field)
	if not _is_stable_id(entity.get("id")):
		return _failure(&"entity_bounds_invalid", "%s entity identity or coordinate is invalid" % field)
	if not _coordinate_is_in_bounds(entity, grid):
		return _failure(&"entity_bounds_invalid", "%s entity identity or coordinate is invalid" % field)
	var entity_id: String = String(entity["id"])
	if identities.has(entity_id):
		return _failure(&"entity_identity_duplicate", "entity identities must be unique")
	identities[entity_id] = true
	return _validate_specialized_entity(field, entity)

static func _validate_dock_requirements(definition: Dictionary) -> DomainResult:
	var docks: Array = definition["docks"]
	if docks.is_empty():
		return _failure(&"dock_count_invalid", "at least one dock is required")
	var delivery_dock_count: int = 0
	var charging_dock_count: int = 0
	for raw_dock: Variant in docks:
		if Dictionary(raw_dock)["kind"] == "delivery":
			delivery_dock_count += 1
		else:
			charging_dock_count += 1
	if delivery_dock_count == 0:
		return _failure(&"delivery_dock_missing", "at least one delivery dock is required")
	if bool(definition["charge_enabled"]) and charging_dock_count == 0:
		return _failure(&"charging_dock_missing", "charge-enabled cases require a charging dock")
	return DomainResultType.success(true)

static func _validate_specialized_entity(field: String, entity: Dictionary) -> DomainResult:
	if field == "doors" and typeof(entity.get("is_open")) != TYPE_BOOL:
		return _failure(&"door_state_invalid", "door state must be boolean")
	if field == "conveyors" and not ["east", "north", "south", "west"].has(entity.get("direction")):
		return _failure(&"conveyor_direction_invalid", "conveyor direction must be cardinal")
	if field == "sensors" and not _is_admitted_colour(entity.get("color")):
		return _failure(&"sensor_colour_invalid", "sensor colour must be an admitted fixed colour")
	if field == "docks":
		if not ["delivery", "charging"].has(entity.get("kind")) or not _in_range(entity.get("capacity"), 1, 16):
			return _failure(&"dock_configuration_invalid", "dock kind or capacity is invalid")
		if entity.get("accepted_color") != "none" and not _is_admitted_colour(entity.get("accepted_color")):
			return _failure(&"dock_colour_invalid", "dock accepted colour must be none or an admitted fixed colour")
	return DomainResultType.success(true)

static func _validate_floor_and_structure_occupancy(definition: Dictionary, grid: Dictionary) -> DomainResult:
	var structure_cells: Dictionary = {}
	for field: String in ["crates", "obstacles", "doors"]:
		for raw_entity: Variant in Array(definition[field]):
			var cell: String = _cell_key(Dictionary(raw_entity))
			if structure_cells.has(cell):
				return _failure(&"structure_occupancy_invalid", "structure occupants cannot share a cell")
			structure_cells[cell] = true
	var floor_cells: Dictionary = {}
	for field: String in ["conveyors", "docks", "sensors"]:
		for raw_entity: Variant in Array(definition[field]):
			var cell: String = _cell_key(Dictionary(raw_entity))
			if floor_cells.has(cell):
				return _failure(&"floor_occupancy_invalid", "floor features cannot share a cell")
			floor_cells[cell] = true
	var bot: Dictionary = definition["bot"]
	var bot_cell: String = _cell_key(bot)
	if _blocked_cell_set(definition).has(bot_cell):
		return _failure(&"bot_occupancy_invalid", "bot cannot occupy a solid structure cell")
	return DomainResultType.success(true)

static func _validate_package_partition(definition: Dictionary) -> DomainResult:
	var package_lookup: Dictionary = _package_lookup(definition)
	var package_ids: Dictionary = package_lookup["ids"]
	var package_colours: Dictionary = package_lookup["colours"]
	var placements: Dictionary = {}
	var world_result: DomainResult = _validate_world_partition(definition, package_ids, placements)
	if not world_result.is_success():
		return world_result
	var inventory_result: DomainResult = _validate_inventory_partition(definition, package_ids, placements)
	if not inventory_result.is_success():
		return inventory_result
	var delivery_result: DomainResult = _validate_delivery_partition(definition, package_ids, package_colours, placements)
	if not delivery_result.is_success():
		return delivery_result
	if placements.size() != package_ids.size():
		return _failure(&"package_partition_invalid", "every package must occur in exactly one partition")
	return DomainResultType.success(true)

static func _package_lookup(definition: Dictionary) -> Dictionary:
	var package_ids: Dictionary = {}
	var package_colours: Dictionary = {}
	for raw_package: Variant in Array(definition["packages"]):
		var package: Dictionary = raw_package
		package_ids[String(package["id"])] = true
		package_colours[String(package["id"])] = String(package["color"])
	return {"ids": package_ids, "colours": package_colours}

static func _validate_world_partition(definition: Dictionary, package_ids: Dictionary, placements: Dictionary) -> DomainResult:
	var world_cells: Dictionary = {}
	var blocked: Dictionary = _blocked_cell_set(definition)
	var bot_cell: String = _cell_key(Dictionary(definition["bot"]))
	for raw_world: Variant in Array(definition["world_packages"]):
		if typeof(raw_world) != TYPE_DICTIONARY or not _has_exact_keys(raw_world, ["package_id", "x", "y"]):
			return _failure(&"world_package_shape_invalid", "world package fields are not exact")
		var world: Dictionary = raw_world
		if not package_ids.has(String(world.get("package_id", ""))) or not _coordinate_is_in_bounds(world, Dictionary(definition["grid"])):
			return _failure(&"world_package_invalid", "world package identity or coordinate is invalid")
		var package_id: String = String(world["package_id"])
		var cell: String = _cell_key(world)
		if placements.has(package_id) or world_cells.has(cell) or blocked.has(cell) or cell == bot_cell:
			return _failure(&"package_partition_invalid", "world package partition or occupancy is invalid")
		placements[package_id] = true
		world_cells[cell] = true
	return DomainResultType.success(true)

static func _validate_inventory_partition(definition: Dictionary, package_ids: Dictionary, placements: Dictionary) -> DomainResult:
	var inventory: Array = definition["inventory"]
	var inventory_capacity: Variant = Dictionary(definition["bot"])["inventory_capacity"]
	if not _in_range(inventory_capacity, 1, 8) or inventory.size() > int(inventory_capacity):
		return _failure(&"inventory_capacity_invalid", "inventory exceeds its admitted capacity")
	for raw_package_id: Variant in inventory:
		if typeof(raw_package_id) != TYPE_STRING or not package_ids.has(String(raw_package_id)) or placements.has(String(raw_package_id)):
			return _failure(&"package_partition_invalid", "inventory package partition is invalid")
		placements[String(raw_package_id)] = true
	return DomainResultType.success(true)

static func _validate_delivery_partition(definition: Dictionary, package_ids: Dictionary, package_colours: Dictionary, placements: Dictionary) -> DomainResult:
	var docks: Dictionary = _docks_by_id(definition)
	var delivered_to: Dictionary = {}
	var deliveries: Array = definition["deliveries"]
	for expected_index: int in range(1, deliveries.size() + 1):
		var delivery_result: DomainResult = _validate_delivery_record(deliveries[expected_index - 1], expected_index, package_ids, docks, placements, package_colours, delivered_to)
		if not delivery_result.is_success():
			return delivery_result
	return DomainResultType.success(true)

static func _docks_by_id(definition: Dictionary) -> Dictionary:
	var docks: Dictionary = {}
	for raw_dock: Variant in Array(definition["docks"]):
		var dock: Dictionary = raw_dock
		docks[String(dock["id"])] = dock
	return docks

static func _validate_delivery_record(raw_delivery: Variant, expected_index: int, package_ids: Dictionary, docks: Dictionary, placements: Dictionary, package_colours: Dictionary, delivered_to: Dictionary) -> DomainResult:
	var delivery_result: DomainResult = _validate_delivery_reference(raw_delivery, expected_index, package_ids, docks)
	if not delivery_result.is_success():
		return delivery_result
	var delivery: Dictionary = delivery_result.value()
	var package_id: String = String(delivery["package_id"])
	var dock_id: String = String(delivery["dock_id"])
	var dock: Dictionary = docks[dock_id]
	return _commit_delivery_partition(package_id, dock_id, dock, placements, package_colours, delivered_to)

static func _validate_delivery_reference(raw_delivery: Variant, expected_index: int, package_ids: Dictionary, docks: Dictionary) -> DomainResult:
	if typeof(raw_delivery) != TYPE_DICTIONARY:
		return _failure(&"delivery_shape_invalid", "delivery fields are not exact")
	var delivery: Dictionary = raw_delivery
	if not _has_exact_keys(delivery, ["index", "package_id", "dock_id"]):
		return _failure(&"delivery_shape_invalid", "delivery fields are not exact")
	if delivery.get("index") != expected_index:
		return _failure(&"delivery_index_invalid", "delivery index, package, or dock is invalid")
	if not package_ids.has(String(delivery.get("package_id", ""))):
		return _failure(&"delivery_index_invalid", "delivery index, package, or dock is invalid")
	if not docks.has(String(delivery.get("dock_id", ""))):
		return _failure(&"delivery_index_invalid", "delivery index, package, or dock is invalid")
	return DomainResultType.success(delivery)

static func _commit_delivery_partition(package_id: String, dock_id: String, dock: Dictionary, placements: Dictionary, package_colours: Dictionary, delivered_to: Dictionary) -> DomainResult:
	if placements.has(package_id):
		return _failure(&"package_partition_invalid", "delivery package partition or dock kind is invalid")
	if dock["kind"] != "delivery":
		return _failure(&"package_partition_invalid", "delivery package partition or dock kind is invalid")
	if dock["accepted_color"] != "none" and dock["accepted_color"] != package_colours[package_id]:
		return _failure(&"delivery_colour_invalid", "delivery does not match dock colour")
	delivered_to[dock_id] = int(delivered_to.get(dock_id, 0)) + 1
	if int(delivered_to[dock_id]) > int(dock["capacity"]):
		return _failure(&"delivery_capacity_invalid", "delivery exceeds dock capacity")
	placements[package_id] = true
	return DomainResultType.success(true)

static func _validate_static_reachability(definition: Dictionary) -> DomainResult:
	var grid: Dictionary = definition["grid"]
	var blocked: Dictionary = _blocked_cell_set(definition)
	var bot: Dictionary = definition["bot"]
	if blocked.has(_cell_key(bot)):
		return _failure(&"reachability_start_blocked", "bot cannot start on a blocked structure cell")
	var reachable: Dictionary = _reachable_cells(grid, bot, blocked)
	var required: Array[Dictionary] = []
	for raw_world: Variant in Array(definition["world_packages"]):
		required.append(Dictionary(raw_world))
	for raw_dock: Variant in Array(definition["docks"]):
		required.append(Dictionary(raw_dock))
	for raw_sensor: Variant in Array(definition["sensors"]):
		required.append(Dictionary(raw_sensor))
	for interactable: Dictionary in required:
		if not _has_reachable_stand_cell(interactable, grid, reachable):
			return _failure(&"interactable_unreachable", "required interactable has no reachable adjacent stand cell")
	return DomainResultType.success(true)

static func _reachable_cells(grid: Dictionary, bot: Dictionary, blocked: Dictionary) -> Dictionary:
	var reachable: Dictionary = {}
	var queue: Array[Dictionary] = [{"x": int(bot["x"]), "y": int(bot["y"])}]
	var head: int = 0
	while head < queue.size() and reachable.size() < MAX_BFS_VISITS:
		var cell: Dictionary = queue[head]
		head += 1
		var key: String = _cell_key(cell)
		if reachable.has(key) or blocked.has(key):
			continue
		reachable[key] = true
		for delta: Dictionary in [{"x": 1, "y": 0}, {"x": -1, "y": 0}, {"x": 0, "y": 1}, {"x": 0, "y": -1}]:
			var next: Dictionary = {"x": int(cell["x"]) + int(delta["x"]), "y": int(cell["y"]) + int(delta["y"])}
			if _coordinate_is_in_bounds(next, grid) and not reachable.has(_cell_key(next)) and not blocked.has(_cell_key(next)):
				queue.append(next)
	return reachable

static func _has_reachable_stand_cell(interactable: Dictionary, grid: Dictionary, reachable: Dictionary) -> bool:
	for delta: Dictionary in [{"x": 1, "y": 0}, {"x": -1, "y": 0}, {"x": 0, "y": 1}, {"x": 0, "y": -1}]:
		var stand: Dictionary = {"x": int(interactable["x"]) + int(delta["x"]), "y": int(interactable["y"]) + int(delta["y"])}
		if _coordinate_is_in_bounds(stand, grid) and reachable.has(_cell_key(stand)):
			return true
	return false

static func _blocked_cell_set(definition: Dictionary) -> Dictionary:
	var blocked: Dictionary = {}
	for field: String in ["crates", "obstacles"]:
		for raw_entity: Variant in Array(definition[field]):
			blocked[_cell_key(Dictionary(raw_entity))] = true
	for raw_door: Variant in Array(definition["doors"]):
		var door: Dictionary = raw_door
		if not bool(door["is_open"]):
			blocked[_cell_key(door)] = true
	return blocked

static func _coordinate_is_in_bounds(value: Dictionary, grid: Dictionary) -> bool:
	return typeof(value.get("x")) == TYPE_INT and typeof(value.get("y")) == TYPE_INT and int(value["x"]) >= 0 and int(value["x"]) < int(grid["width"]) and int(value["y"]) >= 0 and int(value["y"]) < int(grid["height"])

static func _in_range(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= minimum and int(value) <= maximum

static func _cell_key(value: Dictionary) -> String:
	return "%d,%d" % [int(value["x"]), int(value["y"])]

static func _has_exact_keys(value: Variant, fields: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var dictionary: Dictionary = value
	if dictionary.size() != fields.size():
		return false
	for key: Variant in dictionary.keys():
		if typeof(key) != TYPE_STRING or not fields.has(key):
			return false
	return true

static func _is_stable_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var bytes: PackedByteArray = String(value).to_utf8_buffer()
	if bytes.is_empty() or bytes.size() > 64 or not _is_ascii_letter(bytes[0]):
		return false
	for index: int in range(1, bytes.size()):
		var byte: int = bytes[index]
		if not _is_ascii_letter(byte) and not _is_ascii_digit(byte) and not [45, 46, 95].has(byte):
			return false
	return true

static func _is_admitted_colour(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and ADMITTED_COLOURS.has(String(value))

static func _is_ascii_letter(byte: int) -> bool:
	return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)

static func _is_ascii_digit(byte: int) -> bool:
	return byte >= 48 and byte <= 57

static func _failure(code: StringName, message: String) -> DomainResult:
	return DomainResultType.failure(code, message, "$.case", -1, 0, &"record_not_allocated")
