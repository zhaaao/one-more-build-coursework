class_name SandboxActionReducer
extends RefCounted

## Pure synchronous reducer for the Story 002 Parcel Bot Sandbox Actions.
##
## This reducer implements GDD Acceptance Criteria 3–5. It operates only on
## admitted immutable state projections and never schedules, signals, or retains
## case truth. Story 005 derives one stable fact observation from each outcome.

const SandboxActionResultType = preload("res://src/core/sandbox/sandbox_action_result.gd")
const SandboxCaseAdmissionType = preload("res://src/core/sandbox/sandbox_case_admission.gd")
const SandboxCaseStateType = preload("res://src/core/sandbox/sandbox_case_state.gd")
const SandboxObservationType = preload("res://src/core/sandbox/sandbox_observation.gd")

const CARDINAL_DIRECTIONS: Array[String] = ["east", "south", "west", "north"]

## Reduces one named Action against one frozen state.
## Example: `var result := SandboxActionReducer.reduce(state, &"move_forward")`.
static func reduce(state: SandboxCaseStateType, action_id: StringName, arguments: Dictionary = {}) -> SandboxActionResultType:
	if state == null or not state.is_valid():
		return SandboxActionResultType.system_error(&"state_invalid", "Action requires an admitted immutable SandboxCaseState")
	var validation: DomainResult = SandboxCaseAdmissionType.validate_definition(state.projection())
	if not validation.is_success():
		return SandboxActionResultType.system_error(&"state_invariant_broken", "Action input failed admission: %s" % String(validation.error_code()))
	match action_id:
		&"move_forward":
			if not arguments.is_empty():
				return _invalid_arguments(action_id)
			return _move_forward(state)
		&"turn":
			return _turn(state, arguments)
		&"pick_up_front":
			if not arguments.is_empty():
				return _invalid_arguments(action_id)
			return _pick_up_front(state)
		&"drop_front":
			if not arguments.is_empty():
				return _invalid_arguments(action_id)
			return _drop_front(state)
		&"charge":
			if not arguments.is_empty():
				return _invalid_arguments(action_id)
			return _charge(state)
		&"advance_conveyors":
			if not arguments.is_empty():
				return _invalid_arguments(action_id)
			return _advance_conveyors(state)
		_:
			return SandboxActionResultType.system_error(&"action_invalid", "Action identifier is not admitted")

## Validates and reduces the exact Dictionary Action-call ABI used by the port.
## Example: `var result := SandboxActionReducer.reduce_call(state, {"action_id": "turn", "direction": "left"})`.
static func reduce_call(state: SandboxCaseStateType, action_call: Dictionary) -> SandboxActionResultType:
	if not action_call.has("action_id") or (typeof(action_call.get("action_id")) != TYPE_STRING and typeof(action_call.get("action_id")) != TYPE_STRING_NAME):
		return SandboxActionResultType.system_error(&"action_descriptor_invalid", "Action call requires a string action_id")
	var action_id: StringName = StringName(action_call["action_id"])
	if action_id == &"turn":
		if action_call.size() != 2 or not action_call.has("direction") or typeof(action_call.get("direction")) != TYPE_STRING:
			return SandboxActionResultType.system_error(&"action_descriptor_invalid", "turn requires exactly action_id and string direction")
		return reduce(state, action_id, {"direction": String(action_call["direction"])})
	if action_call.size() != 1:
		return SandboxActionResultType.system_error(&"action_descriptor_invalid", "Action call has unexpected fields")
	return reduce(state, action_id)

static func _move_forward(state: SandboxCaseStateType) -> SandboxActionResultType:
	var record: Dictionary = state.projection()
	var bot: Dictionary = Dictionary(record["bot"])
	if int(bot["battery_units"]) == 0:
		return _rejected(state, &"battery_empty", "battery has no units")
	var front: Dictionary = _front_cell(bot)
	if not _in_bounds(front, Dictionary(record["grid"])):
		return _rejected(state, &"out_of_bounds", "front cell is outside the grid")
	if _closed_door_at(record, front):
		return _rejected(state, &"front_door_closed", "front cell has a closed door")
	if _entity_at(Array(record["crates"]), front):
		return _rejected(state, &"front_blocked_by_crate", "front cell has a crate")
	if _entity_at(Array(record["obstacles"]), front):
		return _rejected(state, &"front_blocked_by_obstacle", "front cell has an obstacle")
	if not _world_package_at(Array(record["world_packages"]), front).is_empty():
		return _rejected(state, &"front_occupied", "front cell has a world package")
	bot["x"] = int(front["x"])
	bot["y"] = int(front["y"])
	bot["battery_units"] = int(bot["battery_units"]) - 1
	record["bot"] = bot
	return _transitioned(record)

static func _turn(state: SandboxCaseStateType, arguments: Dictionary) -> SandboxActionResultType:
	if arguments.size() != 1 or typeof(arguments.get("direction")) != TYPE_STRING:
		return _invalid_arguments(&"turn")
	var direction: String = String(arguments["direction"])
	if direction != "left" and direction != "right":
		return _invalid_arguments(&"turn")
	var record: Dictionary = state.projection()
	var bot: Dictionary = Dictionary(record["bot"])
	var orientation_index: int = CARDINAL_DIRECTIONS.find(String(bot["orientation"]))
	if orientation_index < 0:
		return SandboxActionResultType.system_error(&"state_invariant_broken", "bot orientation is not cardinal")
	var offset: int = 3 if direction == "left" else 1
	bot["orientation"] = CARDINAL_DIRECTIONS[(orientation_index + offset) % CARDINAL_DIRECTIONS.size()]
	record["bot"] = bot
	return _transitioned(record)

static func _pick_up_front(state: SandboxCaseStateType) -> SandboxActionResultType:
	var record: Dictionary = state.projection()
	var bot: Dictionary = Dictionary(record["bot"])
	var front: Dictionary = _front_cell(bot)
	if not _in_bounds(front, Dictionary(record["grid"])):
		return _rejected(state, &"out_of_bounds", "front cell is outside the grid")
	var inventory: Array = Array(record["inventory"])
	if inventory.size() >= int(bot["inventory_capacity"]):
		return _rejected(state, &"inventory_full", "inventory is at capacity")
	var world_packages: Array = Array(record["world_packages"])
	var package_index: int = _world_package_index_at(world_packages, front)
	if package_index < 0:
		return _rejected(state, &"no_front_package", "front cell has no world package")
	var world_package: Dictionary = Dictionary(world_packages[package_index])
	world_packages.remove_at(package_index)
	inventory.append(String(world_package["package_id"]))
	record["world_packages"] = world_packages
	record["inventory"] = inventory
	return _transitioned(record)

static func _drop_front(state: SandboxCaseStateType) -> SandboxActionResultType:
	var record: Dictionary = state.projection()
	var inventory: Array[String] = _string_array(record["inventory"])
	if inventory.is_empty():
		return _rejected(state, &"inventory_empty", "inventory has no package")
	var bot: Dictionary = Dictionary(record["bot"])
	var front: Dictionary = _front_cell(bot)
	if not _in_bounds(front, Dictionary(record["grid"])):
		return _rejected(state, &"out_of_bounds", "front cell is outside the grid")
	if _closed_door_at(record, front):
		return _rejected(state, &"front_door_closed", "front cell has a closed door")
	if _entity_at(_dictionary_array(record["crates"]), front):
		return _rejected(state, &"front_blocked_by_crate", "front cell has a crate")
	if _entity_at(_dictionary_array(record["obstacles"]), front):
		return _rejected(state, &"front_blocked_by_obstacle", "front cell has an obstacle")
	if not _world_package_at(_dictionary_array(record["world_packages"]), front).is_empty():
		return _rejected(state, &"front_occupied", "front cell has a world package")
	var package_id: String = String(inventory[0])
	var dock: Dictionary = _dock_at(_dictionary_array(record["docks"]), front)
	if not dock.is_empty() and String(dock["kind"]) == "delivery":
		if not _dock_accepts(record, dock, package_id):
			return _rejected(state, &"wrong_delivery_dock", "front delivery dock rejects the FIFO package colour")
		if _dock_delivery_count(_dictionary_array(record["deliveries"]), String(dock["id"])) >= int(dock["capacity"]):
			return _rejected(state, &"dock_full", "front delivery dock is full")
		inventory.remove_at(0)
		var deliveries: Array[Dictionary] = _dictionary_array(record["deliveries"])
		deliveries.append({"index": deliveries.size() + 1, "package_id": package_id, "dock_id": String(dock["id"])})
		record["inventory"] = inventory
		record["deliveries"] = deliveries
		return _transitioned(record)
	inventory.remove_at(0)
	var world_packages: Array[Dictionary] = _dictionary_array(record["world_packages"])
	world_packages.append({"package_id": package_id, "x": int(front["x"]), "y": int(front["y"])})
	record["inventory"] = inventory
	record["world_packages"] = world_packages
	return _transitioned(record)

static func _charge(state: SandboxCaseStateType) -> SandboxActionResultType:
	var record: Dictionary = state.projection()
	var bot: Dictionary = Dictionary(record["bot"])
	var current_cell: Dictionary = {"x": int(bot["x"]), "y": int(bot["y"])}
	var dock: Dictionary = _dock_at(Array(record["docks"]), current_cell)
	if dock.is_empty() or String(dock["kind"]) != "charging":
		return _rejected(state, &"not_on_charging_dock", "bot is not standing on a charging dock")
	bot["battery_units"] = int(bot["battery_capacity"])
	record["bot"] = bot
	return _transitioned(record)

static func _advance_conveyors(state: SandboxCaseStateType) -> SandboxActionResultType:
	var record: Dictionary = state.projection()
	var world_packages: Array[Dictionary] = _dictionary_array(record["world_packages"])
	var proposals: Array[Dictionary] = _build_conveyor_proposals(record, world_packages)
	if proposals.is_empty():
		return _transitioned(record)
	var jam_detail: String = _conveyor_jam_detail(record, world_packages, proposals)
	if not jam_detail.is_empty():
		return _rejected(state, &"conveyor_jam", jam_detail)
	_commit_conveyor_proposals(record, world_packages, proposals)
	return _transitioned(record)

static func _build_conveyor_proposals(record: Dictionary, world_packages: Array[Dictionary]) -> Array[Dictionary]:
	var conveyors_by_cell: Dictionary = _entities_by_cell(_dictionary_array(record["conveyors"]))
	var selected: Array[Dictionary] = []
	for world_package: Dictionary in world_packages:
		if conveyors_by_cell.has(_cell_key(world_package)):
			selected.append(world_package)
	_sort_records_by_id(selected, "package_id")
	var proposals: Array[Dictionary] = []
	for world_package: Dictionary in selected:
		var conveyor: Dictionary = Dictionary(conveyors_by_cell[_cell_key(world_package)])
		proposals.append({
			"package_id": String(world_package["package_id"]),
			"destination": _step_from_direction(world_package, String(conveyor["direction"])),
		})
	return proposals

static func _conveyor_jam_detail(record: Dictionary, world_packages: Array[Dictionary], proposals: Array[Dictionary]) -> String:
	var selected_ids: Dictionary = {}
	var destination_counts: Dictionary = {}
	for proposal: Dictionary in proposals:
		var package_id: String = String(proposal["package_id"])
		var destination: Dictionary = Dictionary(proposal["destination"])
		selected_ids[package_id] = true
		var destination_key: String = _cell_key(destination)
		destination_counts[destination_key] = int(destination_counts.get(destination_key, 0)) + 1
	var world_by_cell: Dictionary = _entities_by_cell(world_packages)
	var bot: Dictionary = Dictionary(record["bot"])
	var bot_cell: String = _cell_key(bot)
	var docks_by_cell: Dictionary = _entities_by_cell(_dictionary_array(record["docks"]))
	for proposal: Dictionary in proposals:
		var package_id: String = String(proposal["package_id"])
		var destination: Dictionary = Dictionary(proposal["destination"])
		var destination_key: String = _cell_key(destination)
		if not _in_bounds(destination, Dictionary(record["grid"])):
			return "a conveyor destination is outside the grid"
		if _conveyor_destination_blocked(record, bot_cell, destination):
			return "a conveyor destination is blocked"
		if int(destination_counts[destination_key]) > 1:
			return "multiple conveyors propose the same destination"
		if world_by_cell.has(destination_key) and not selected_ids.has(String(Dictionary(world_by_cell[destination_key])["package_id"])):
			return "a conveyor destination package is not moving away"
		if _conveyor_delivery_dock_jams(record, docks_by_cell, destination_key, package_id):
			return "a conveyor destination delivery dock is incompatible or full"
	return ""

static func _conveyor_destination_blocked(record: Dictionary, bot_cell: String, destination: Dictionary) -> bool:
	if _cell_key(destination) == bot_cell:
		return true
	if _entity_at(_dictionary_array(record["crates"]), destination):
		return true
	if _entity_at(_dictionary_array(record["obstacles"]), destination):
		return true
	return _closed_door_at(record, destination)

static func _conveyor_delivery_dock_jams(record: Dictionary, docks_by_cell: Dictionary, destination_key: String, package_id: String) -> bool:
	if not docks_by_cell.has(destination_key):
		return false
	var dock: Dictionary = Dictionary(docks_by_cell[destination_key])
	if String(dock["kind"]) != "delivery":
		return false
	return not _dock_accepts(record, dock, package_id) or _dock_delivery_count(_dictionary_array(record["deliveries"]), String(dock["id"])) >= int(dock["capacity"])

static func _commit_conveyor_proposals(record: Dictionary, world_packages: Array[Dictionary], proposals: Array[Dictionary]) -> void:
	var proposals_by_id: Dictionary = {}
	for proposal: Dictionary in proposals:
		proposals_by_id[String(proposal["package_id"])] = proposal
	var docks_by_cell: Dictionary = _entities_by_cell(_dictionary_array(record["docks"]))
	var next_world_packages: Array[Dictionary] = []
	var delivery_proposals: Array[Dictionary] = []
	for world_package: Dictionary in world_packages:
		var package_id: String = String(world_package["package_id"])
		if not proposals_by_id.has(package_id):
			next_world_packages.append(world_package.duplicate(true))
			continue
		var destination: Dictionary = Dictionary(Dictionary(proposals_by_id[package_id])["destination"])
		var destination_dock: Dictionary = Dictionary(docks_by_cell.get(_cell_key(destination), {}))
		if not destination_dock.is_empty() and String(destination_dock["kind"]) == "delivery":
			delivery_proposals.append({"package_id": package_id, "dock_id": String(destination_dock["id"])})
		else:
			next_world_packages.append({"package_id": package_id, "x": int(destination["x"]), "y": int(destination["y"])})
	_sort_records_by_id(next_world_packages, "package_id")
	_sort_delivery_proposals(delivery_proposals)
	var deliveries: Array[Dictionary] = _dictionary_array(record["deliveries"])
	for proposal: Dictionary in delivery_proposals:
		deliveries.append({"index": deliveries.size() + 1, "package_id": String(proposal["package_id"]), "dock_id": String(proposal["dock_id"])})
	record["world_packages"] = next_world_packages
	record["deliveries"] = deliveries

static func _transitioned(record: Dictionary) -> SandboxActionResultType:
	var admission: DomainResult = SandboxCaseAdmissionType.admit(record)
	if not admission.is_success():
		return SandboxActionResultType.system_error(&"state_invariant_broken", "candidate state failed admission: %s" % String(admission.error_code()))
	var next_state: SandboxCaseStateType = admission.value()
	return SandboxActionResultType.transitioned(next_state, SandboxObservationType.derive(next_state))

static func _rejected(state: SandboxCaseStateType, reason: StringName, detail: String) -> SandboxActionResultType:
	return SandboxActionResultType.domain_rejected(state, reason, detail, SandboxObservationType.derive(state))

static func _invalid_arguments(action_id: StringName) -> SandboxActionResultType:
	return SandboxActionResultType.system_error(&"action_arguments_invalid", "%s Action arguments are invalid" % String(action_id))

static func _front_cell(bot: Dictionary) -> Dictionary:
	return _step_from_direction(bot, String(bot["orientation"]))

static func _step_from_direction(cell: Dictionary, direction: String) -> Dictionary:
	match direction:
		"east":
			return {"x": int(cell["x"]) + 1, "y": int(cell["y"])}
		"south":
			return {"x": int(cell["x"]), "y": int(cell["y"]) + 1}
		"west":
			return {"x": int(cell["x"]) - 1, "y": int(cell["y"])}
		"north":
			return {"x": int(cell["x"]), "y": int(cell["y"]) - 1}
		_:
			return {"x": int(cell["x"]), "y": int(cell["y"])}

static func _in_bounds(cell: Dictionary, grid: Dictionary) -> bool:
	return int(cell["x"]) >= 0 and int(cell["x"]) < int(grid["width"]) and int(cell["y"]) >= 0 and int(cell["y"]) < int(grid["height"])

static func _cell_key(cell: Dictionary) -> String:
	return "%d,%d" % [int(cell["x"]), int(cell["y"])]

static func _entity_at(entities: Array, cell: Dictionary) -> bool:
	for raw_entity: Variant in entities:
		if _cell_key(Dictionary(raw_entity)) == _cell_key(cell):
			return true
	return false

static func _world_package_at(world_packages: Array, cell: Dictionary) -> Dictionary:
	for raw_world_package: Variant in world_packages:
		var world_package: Dictionary = Dictionary(raw_world_package)
		if _cell_key(world_package) == _cell_key(cell):
			return world_package
	return {}

static func _world_package_index_at(world_packages: Array, cell: Dictionary) -> int:
	for index: int in range(world_packages.size()):
		if _cell_key(Dictionary(world_packages[index])) == _cell_key(cell):
			return index
	return -1

static func _closed_door_at(record: Dictionary, cell: Dictionary) -> bool:
	for raw_door: Variant in Array(record["doors"]):
		var door: Dictionary = Dictionary(raw_door)
		if _cell_key(door) == _cell_key(cell) and not bool(door["is_open"]):
			return true
	return false

static func _dock_at(docks: Array, cell: Dictionary) -> Dictionary:
	for raw_dock: Variant in docks:
		var dock: Dictionary = Dictionary(raw_dock)
		if _cell_key(dock) == _cell_key(cell):
			return dock
	return {}

static func _dock_accepts(record: Dictionary, dock: Dictionary, package_id: String) -> bool:
	if String(dock["accepted_color"]) == "none":
		return true
	for raw_package: Variant in Array(record["packages"]):
		var package: Dictionary = Dictionary(raw_package)
		if String(package["id"]) == package_id:
			return String(dock["accepted_color"]) == String(package["color"])
	return false

static func _dock_delivery_count(deliveries: Array[Dictionary], dock_id: String) -> int:
	var count: int = 0
	for delivery: Dictionary in deliveries:
		if String(delivery["dock_id"]) == dock_id:
			count += 1
	return count

static func _dictionary_array(raw_values: Variant) -> Array[Dictionary]:
	var copied: Array[Dictionary] = []
	for raw_value: Variant in Array(raw_values):
		copied.append(Dictionary(raw_value).duplicate(true))
	return copied

static func _string_array(raw_values: Variant) -> Array[String]:
	var copied: Array[String] = []
	for raw_value: Variant in Array(raw_values):
		copied.append(String(raw_value))
	return copied

static func _entities_by_cell(entities: Array) -> Dictionary:
	var by_cell: Dictionary = {}
	for raw_entity: Variant in entities:
		var entity: Dictionary = Dictionary(raw_entity)
		by_cell[_cell_key(entity)] = entity
	return by_cell

static func _sort_records_by_id(records: Array[Dictionary], field: String) -> void:
	for index: int in range(1, records.size()):
		var candidate: Dictionary = records[index]
		var previous_index: int = index - 1
		while previous_index >= 0 and String(records[previous_index][field]) > String(candidate[field]):
			records[previous_index + 1] = records[previous_index]
			previous_index -= 1
		records[previous_index + 1] = candidate

static func _sort_delivery_proposals(proposals: Array[Dictionary]) -> void:
	for index: int in range(1, proposals.size()):
		var candidate: Dictionary = proposals[index]
		var previous_index: int = index - 1
		while previous_index >= 0 and _delivery_proposal_after(proposals[previous_index], candidate):
			proposals[previous_index + 1] = proposals[previous_index]
			previous_index -= 1
		proposals[previous_index + 1] = candidate

static func _delivery_proposal_after(left: Dictionary, right: Dictionary) -> bool:
	var left_dock_id: String = String(left["dock_id"])
	var right_dock_id: String = String(right["dock_id"])
	if left_dock_id != right_dock_id:
		return left_dock_id > right_dock_id
	return String(left["package_id"]) > String(right["package_id"])
