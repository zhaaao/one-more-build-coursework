class_name SandboxQueryReducer
extends RefCounted

## Pure synchronous reducer for Story 003 Parcel Bot Sandbox Queries.
##
## Each valid call takes exactly one detached projection from an admitted state,
## derives a value or stable domain reason from that projection, and never
## retains, schedules, or changes world truth. Story 005 owns final facts.

const SandboxCaseStateType = preload("res://src/core/sandbox/sandbox_case_state.gd")
const SandboxCaseAdmissionType = preload("res://src/core/sandbox/sandbox_case_admission.gd")
const SandboxQueryResultType = preload("res://src/core/sandbox/sandbox_query_result.gd")
const SandboxObservationType = preload("res://src/core/sandbox/sandbox_observation.gd")

const ADMITTED_COLOURS: Array[String] = ["blue", "green", "orange", "purple", "red", "yellow"]

## Reduces one named Query against one frozen state.
## Example: `var result := SandboxQueryReducer.reduce(state, &"path_is_clear")`.
static func reduce(state: SandboxCaseStateType, query_id: StringName, arguments: Dictionary = {}) -> SandboxQueryResultType:
	if state == null or not state.is_valid():
		return _system_error(&"state_invalid", "Query requires an admitted immutable SandboxCaseState")
	var validation: DomainResult = SandboxCaseAdmissionType.validate_definition(state.projection())
	if not validation.is_success():
		return _system_error(&"state_invariant_broken", "Query input failed admission: %s" % String(validation.error_code()))
	if not _arguments_are_valid(query_id, arguments):
		return _system_error(&"query_arguments_invalid", "%s Query arguments are invalid" % String(query_id))
	var record: Dictionary = state.projection()
	match query_id:
		&"battery_units":
			return _produced(record, int(Dictionary(record["bot"])["battery_units"]))
		&"front_door_open":
			return _front_door_open(record)
		&"front_sensor_active":
			return _front_sensor_active(record)
		&"front_sensor_matches_color":
			return _front_sensor_matches_color(record, String(arguments["colour"]))
		&"inventory_count":
			return _produced(record, _string_values(record["inventory"]).size())
		&"inventory_has_package":
			return _produced(record, not _string_values(record["inventory"]).is_empty())
		&"packages_remaining":
			return _produced(record, _remaining_package_count(record) > 0)
		&"path_is_clear":
			return _produced(record, _is_passable(record, _front_cell(Dictionary(record["bot"]))))
		&"remaining_package_count":
			return _produced(record, _remaining_package_count(record))
		_:
			return _system_error(&"query_invalid", "Query identifier is not admitted")

## Validates and reduces the exact Dictionary Query-call ABI used by the port.
## Example: `var result := SandboxQueryReducer.reduce_call(state, {"query_id": "battery_units"})`.
static func reduce_call(state: SandboxCaseStateType, query_call: Dictionary) -> SandboxQueryResultType:
	if not query_call.has("query_id") or (typeof(query_call.get("query_id")) != TYPE_STRING and typeof(query_call.get("query_id")) != TYPE_STRING_NAME):
		return _system_error(&"query_descriptor_invalid", "Query call requires a string query_id")
	var query_id: StringName = StringName(query_call["query_id"])
	if query_id == &"front_sensor_matches_color":
		if query_call.size() != 2 or not query_call.has("colour") or typeof(query_call.get("colour")) != TYPE_STRING:
			return _system_error(&"query_descriptor_invalid", "front_sensor_matches_color requires exactly query_id and string colour")
		return reduce(state, query_id, {"colour": String(query_call["colour"])})
	if query_call.size() != 1:
		return _system_error(&"query_descriptor_invalid", "Query call has unexpected fields")
	return reduce(state, query_id)

static func _arguments_are_valid(query_id: StringName, arguments: Dictionary) -> bool:
	if query_id == &"front_sensor_matches_color":
		return arguments.size() == 1 and arguments.has("colour") and typeof(arguments.get("colour")) == TYPE_STRING and ADMITTED_COLOURS.has(String(arguments["colour"]))
	return arguments.is_empty()

static func _front_door_open(record: Dictionary) -> SandboxQueryResultType:
	var front: Dictionary = _front_cell(Dictionary(record["bot"]))
	var door: Dictionary = _entity_at(_dictionary_records(record["doors"]), front)
	if door.is_empty():
		return _rejected(record, &"no_front_door", "front cell has no door")
	return _produced(record, bool(door["is_open"]))

static func _front_sensor_active(record: Dictionary) -> SandboxQueryResultType:
	var front: Dictionary = _front_cell(Dictionary(record["bot"]))
	if _entity_at(_dictionary_records(record["sensors"]), front).is_empty():
		return _rejected(record, &"no_front_sensor", "front cell has no sensor")
	return _produced(record, not _world_package_at(_dictionary_records(record["world_packages"]), front).is_empty())

static func _front_sensor_matches_color(record: Dictionary, colour: String) -> SandboxQueryResultType:
	var front: Dictionary = _front_cell(Dictionary(record["bot"]))
	if _entity_at(_dictionary_records(record["sensors"]), front).is_empty():
		return _rejected(record, &"no_front_sensor", "front cell has no sensor")
	var world_package: Dictionary = _world_package_at(_dictionary_records(record["world_packages"]), front)
	if world_package.is_empty():
		return _rejected(record, &"sensor_no_package", "front sensor has no world package")
	var package_id: String = String(world_package["package_id"])
	for package: Dictionary in _dictionary_records(record["packages"]):
		if String(package["id"]) == package_id:
			return _produced(record, String(package["color"]) == colour)
	return _system_error(&"state_invariant_broken", "front world package has no immutable definition")

static func _remaining_package_count(record: Dictionary) -> int:
	return _dictionary_records(record["world_packages"]).size() + _string_values(record["inventory"]).size()

static func _is_passable(record: Dictionary, cell: Dictionary) -> bool:
	if not _in_bounds(cell, Dictionary(record["grid"])):
		return false
	if not _entity_at(_dictionary_records(record["crates"]), cell).is_empty():
		return false
	if not _entity_at(_dictionary_records(record["obstacles"]), cell).is_empty():
		return false
	var door: Dictionary = _entity_at(_dictionary_records(record["doors"]), cell)
	if not door.is_empty() and not bool(door["is_open"]):
		return false
	return _world_package_at(_dictionary_records(record["world_packages"]), cell).is_empty()

static func _produced(record: Dictionary, value: Variant) -> SandboxQueryResultType:
	return SandboxQueryResultType.produced(value, SandboxObservationType.derive_projection(record))

static func _rejected(record: Dictionary, reason: StringName, detail: String) -> SandboxQueryResultType:
	return SandboxQueryResultType.domain_rejected(reason, detail, SandboxObservationType.derive_projection(record))

static func _system_error(reason: StringName, detail: String) -> SandboxQueryResultType:
	return SandboxQueryResultType.system_error(reason, detail)

static func _front_cell(bot: Dictionary) -> Dictionary:
	match String(bot["orientation"]):
		"east":
			return {"x": int(bot["x"]) + 1, "y": int(bot["y"])}
		"south":
			return {"x": int(bot["x"]), "y": int(bot["y"]) + 1}
		"west":
			return {"x": int(bot["x"]) - 1, "y": int(bot["y"])}
		"north":
			return {"x": int(bot["x"]), "y": int(bot["y"]) - 1}
		_:
			return {"x": int(bot["x"]), "y": int(bot["y"])}

static func _in_bounds(cell: Dictionary, grid: Dictionary) -> bool:
	return int(cell["x"]) >= 0 and int(cell["x"]) < int(grid["width"]) and int(cell["y"]) >= 0 and int(cell["y"]) < int(grid["height"])

static func _entity_at(entities: Array[Dictionary], cell: Dictionary) -> Dictionary:
	for entity: Dictionary in entities:
		if _same_cell(entity, cell):
			return entity
	return {}

static func _world_package_at(world_packages: Array[Dictionary], cell: Dictionary) -> Dictionary:
	for world_package: Dictionary in world_packages:
		if _same_cell(world_package, cell):
			return world_package
	return {}

static func _dictionary_records(source: Variant) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	records.assign(source)
	return records

static func _string_values(source: Variant) -> Array[String]:
	var values: Array[String] = []
	values.assign(source)
	return values

static func _same_cell(left: Dictionary, right: Dictionary) -> bool:
	return int(left["x"]) == int(right["x"]) and int(left["y"]) == int(right["y"])
