## Read-only Story 007 projection of accepted Parcel Bot Sandbox records.
##
## This adapter copies accepted state/result observations into Godot nodes. It
## never retains a Core record, invokes a Sandbox port, or calculates a domain
## transition; destroying it therefore cannot affect simulation truth.
class_name SandboxVisualProjection
extends Control


const SandboxVisualAssetCatalogType = preload("res://src/presentation/sandbox/sandbox_visual_asset_catalog.gd")
const SandboxCaseStateType = preload("res://src/core/sandbox/sandbox_case_state.gd")
const SandboxActionResultType = preload("res://src/core/sandbox/sandbox_action_result.gd")
const SandboxQueryResultType = preload("res://src/core/sandbox/sandbox_query_result.gd")

const ATLAS_CELL_PIXELS: int = 32
const PLAYFIELD_PIXELS: int = 192
const GRID_SCALE_OPTIONS: Array[int] = [32, 16, 8, 4]
const LEGEND_OFFSET_X: int = 200
const MONITOR_FONT_PIXELS: int = 12
const MONITOR_SLOT_PATH: NodePath = ^"MonitorContent"
const SANDBOX_SLOT_PATH: NodePath = ^"SandboxContent"
const OBSERVATION_GROUP_ORDER: Array[StringName] = [&"BOT", &"FRONT", &"INVENTORY", &"DELIVERY", &"STATE"]

var _legend_label: Label = null
var _legend_cues: Array[String] = []
var _cell_pixels: int = 4
var _world_rect: Rect2 = Rect2()


## Projects one already-admitted immutable state without retaining the state.
func show_accepted_state(state: SandboxCaseStateType) -> void:
	_clear_projection_slots()
	if state == null or not state.is_valid():
		_render_monitor_lines(["[STATE UNAVAILABLE]", "No admitted SandboxCaseState was supplied."])
		return

	var projection: Dictionary = state.projection()
	_render_state(projection)
	_render_monitor_lines(_state_summary_lines(projection))


## Projects a closed Action result; only its returned state/observation is read.
func show_action_result(result: SandboxActionResultType) -> void:
	if result == null:
		_show_outcome_without_state("[ACTION UNAVAILABLE]", "No closed SandboxActionResult was supplied.", {})
		return

	var returned_state: SandboxCaseStateType = result.state()
	if returned_state != null:
		show_accepted_state(returned_state)
		_append_monitor_lines(_outcome_lines("ACTION", result.kind(), result.reason(), result.detail(), result.observation()))
		return

	_show_outcome_without_state("[ACTION %s]" % String(result.kind()), result.detail(), result.observation(), result.reason())


## Projects a closed Query observation/value without requesting or changing state.
func show_query_result(result: SandboxQueryResultType) -> void:
	_clear_projection_slots()
	if result == null:
		_render_monitor_lines(["[QUERY UNAVAILABLE]", "No closed SandboxQueryResult was supplied."])
		return

	var lines: Array[String] = _outcome_lines("QUERY", result.kind(), result.reason(), result.detail(), result.observation())
	if result.is_produced():
		lines.append("VALUE: %s" % _format_value(result.value()))
	_render_monitor_lines(lines)


## Returns the exact rendered pixel-world bounds for presentation-only cropping.
func sandbox_world_rect() -> Rect2:
	return _world_rect


func _show_outcome_without_state(title: String, detail: String, observation: Dictionary, reason: StringName = &"") -> void:
	_clear_projection_slots()
	var lines: Array[String] = [title]
	if not reason.is_empty():
		lines.append("REASON: %s" % String(reason))
	if not detail.is_empty():
		lines.append("DETAIL: %s" % detail)
	lines.append_array(_observation_lines(observation))
	_render_monitor_lines(lines)


func _render_state(projection: Dictionary) -> void:
	var grid: Dictionary = Dictionary(projection.get("grid", {}))
	_select_cell_scale(grid)
	_world_rect = Rect2(
		Vector2.ZERO,
		Vector2(int(grid.get("width", 0)) * _cell_pixels, int(grid.get("height", 0)) * _cell_pixels),
	)
	_prepare_legend()
	_render_playfield(grid)

	var packages_by_id: Dictionary = _packages_by_id(Array(projection.get("packages", [])))
	_render_record_markers(Array(projection.get("world_packages", [])), SandboxVisualAssetCatalogType.PACKAGES_ATLAS_ID, packages_by_id)
	_render_record_markers(Array(projection.get("docks", [])), SandboxVisualAssetCatalogType.DOCKS_ATLAS_ID, {})
	_render_fixture_markers(Array(projection.get("sensors", [])), &"sensor")
	_render_fixture_markers(Array(projection.get("conveyors", [])), &"conveyor")
	_render_doors(Array(projection.get("doors", [])))
	_render_fixture_markers(Array(projection.get("obstacles", [])), &"obstacle")
	_render_fixture_markers(Array(projection.get("crates", [])), &"crate")

	var bot: Dictionary = Dictionary(projection.get("bot", {}))
	if not bot.is_empty():
		var orientation: StringName = StringName(String(bot.get("orientation", "east")))
		_render_atlas_marker(
			SandboxVisualAssetCatalogType.BOT_ATLAS_ID,
			orientation,
			_grid_position(bot),
			"[BOT %s]" % String(orientation).to_upper(),
		)


func _render_playfield(grid: Dictionary) -> void:
	var width: int = int(grid.get("width", 0))
	var height: int = int(grid.get("height", 0))
	for y: int in range(height):
		for x: int in range(width):
			_render_atlas_marker(
				SandboxVisualAssetCatalogType.PLAYFIELD_ATLAS_ID,
				_playfield_region(x, y, width, height),
				Vector2i(x, y),
				"",
				false,
			)


func _playfield_region(x: int, y: int, width: int, height: int) -> StringName:
	var boundary_parts: Array[String] = []
	if y == 0:
		boundary_parts.append("north")
	if x == width - 1:
		boundary_parts.append("east")
	if y == height - 1:
		boundary_parts.append("south")
	if x == 0:
		boundary_parts.append("west")
	if boundary_parts.is_empty():
		return &"none"
	return StringName("_".join(boundary_parts))


func _render_record_markers(records: Array, atlas_id: StringName, packages_by_id: Dictionary) -> void:
	var ordered_records: Array = records.duplicate(true)
	ordered_records.sort_custom(_sort_grid_records)
	for item: Variant in ordered_records:
		var record: Dictionary = Dictionary(item)
		var region_id: StringName = _region_for_record(atlas_id, record, packages_by_id)
		var cue: String = _cue_for_record(atlas_id, record, region_id)
		_render_atlas_marker(atlas_id, region_id, _grid_position(record), cue)


func _render_fixture_markers(records: Array, base_region: StringName) -> void:
	var ordered_records: Array = records.duplicate(true)
	ordered_records.sort_custom(_sort_grid_records)
	for item: Variant in ordered_records:
		var record: Dictionary = Dictionary(item)
		var region_id: StringName = base_region
		var cue: String = "[%s]" % String(region_id).to_upper()
		if base_region == &"conveyor":
			var direction: String = String(record.get("direction", "east"))
			region_id = StringName("conveyor_%s" % direction)
			cue = "[CONVEYOR %s]" % direction.to_upper()
		_render_atlas_marker(
			SandboxVisualAssetCatalogType.FIXTURES_ATLAS_ID,
			region_id,
			_grid_position(record),
			cue,
		)


func _render_doors(records: Array) -> void:
	var ordered_records: Array = records.duplicate(true)
	ordered_records.sort_custom(_sort_grid_records)
	for item: Variant in ordered_records:
		var record: Dictionary = Dictionary(item)
		if bool(record.get("is_open", false)):
			_render_atlas_marker(SandboxVisualAssetCatalogType.FIXTURES_ATLAS_ID, &"open_door", _grid_position(record), "[DOOR OPEN]")
		else:
			_render_atlas_marker(SandboxVisualAssetCatalogType.FIXTURES_ATLAS_ID, &"closed_door", _grid_position(record), "[DOOR CLOSED]")


func _render_atlas_marker(atlas_id: StringName, region_id: StringName, cell: Vector2i, fallback_cue: String, show_legend: bool = true) -> void:
	var slot := get_node_or_null(SANDBOX_SLOT_PATH) as Control
	if slot == null:
		return
	var region_map: Dictionary = SandboxVisualAssetCatalogType.get_region_map(atlas_id)
	var region: Rect2 = region_map.get(region_id, Rect2())
	var texture := _load_texture(atlas_id)
	if texture == null or region.size != Vector2(ATLAS_CELL_PIXELS, ATLAS_CELL_PIXELS):
		if show_legend and not fallback_cue.is_empty():
			_append_legend_cue("%s [RASTER UNAVAILABLE]" % fallback_cue)
		return

	var sprite := Sprite2D.new()
	sprite.name = "Atlas_%s_%s_%d_%d" % [String(atlas_id), String(region_id), cell.x, cell.y]
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.region_enabled = true
	sprite.region_rect = region
	sprite.scale = Vector2.ONE * float(_cell_pixels) / float(ATLAS_CELL_PIXELS)
	var cell_centre: float = float(_cell_pixels) / 2.0
	sprite.position = Vector2(cell.x * _cell_pixels + cell_centre, cell.y * _cell_pixels + cell_centre)
	slot.add_child(sprite)
	if show_legend and not fallback_cue.is_empty():
		_append_legend_cue(fallback_cue)


func _load_texture(atlas_id: StringName) -> Texture2D:
	var texture_path: String = SandboxVisualAssetCatalogType.get_texture_path(atlas_id)
	return load(texture_path) as Texture2D


func _prepare_legend() -> void:
	var slot := get_node_or_null(SANDBOX_SLOT_PATH) as Control
	if slot == null:
		return
	_legend_label = Label.new()
	_legend_label.name = "EntityLegend"
	_legend_label.position = Vector2(LEGEND_OFFSET_X, 0)
	_legend_label.size = Vector2(slot.size.x - LEGEND_OFFSET_X, slot.size.y)
	_legend_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_legend_label.add_theme_font_size_override("font_size", 10)
	_legend_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(_legend_label)


func _append_legend_cue(cue: String) -> void:
	if _legend_label == null or _legend_cues.has(cue):
		return
	_legend_cues.append(cue)
	_legend_label.text = "\n".join(_legend_cues)


func _render_monitor_lines(lines: Array[String]) -> void:
	var slot := get_node_or_null(MONITOR_SLOT_PATH) as Control
	if slot == null:
		return
	var monitor := Label.new()
	monitor.name = "ProjectionFacts"
	monitor.text = "\n".join(lines)
	monitor.position = Vector2i.ZERO
	monitor.size = slot.size
	monitor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	monitor.add_theme_font_size_override("font_size", MONITOR_FONT_PIXELS)
	monitor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(monitor)


func _append_monitor_lines(lines: Array[String]) -> void:
	var monitor := get_node_or_null("MonitorContent/ProjectionFacts") as Label
	if monitor == null:
		_render_monitor_lines(lines)
		return
	monitor.text = "%s\n%s" % [monitor.text, "\n".join(lines)]


func _clear_projection_slots() -> void:
	_legend_label = null
	_legend_cues.clear()
	_world_rect = Rect2()
	_clear_slot(MONITOR_SLOT_PATH)
	_clear_slot(SANDBOX_SLOT_PATH)


func _select_cell_scale(grid: Dictionary) -> void:
	var width: int = int(grid.get("width", 0))
	var height: int = int(grid.get("height", 0))
	for candidate: int in GRID_SCALE_OPTIONS:
		if width * candidate <= PLAYFIELD_PIXELS and height * candidate <= PLAYFIELD_PIXELS:
			_cell_pixels = candidate
			return
	_cell_pixels = 4


func _clear_slot(path: NodePath) -> void:
	var slot := get_node_or_null(path)
	if slot == null:
		return
	for child: Node in slot.get_children():
		slot.remove_child(child)
		child.queue_free()


func _state_summary_lines(projection: Dictionary) -> Array[String]:
	var bot: Dictionary = Dictionary(projection.get("bot", {}))
	var grid: Dictionary = Dictionary(projection.get("grid", {}))
	return [
		"[ACCEPTED SANDBOX STATE]",
		"CASE: %s" % String(projection.get("case_id", "")),
		"GRID: %d x %d" % [int(grid.get("width", 0)), int(grid.get("height", 0))],
		"BOT: (%d,%d) %s battery %d/%d" % [int(bot.get("x", 0)), int(bot.get("y", 0)), String(bot.get("orientation", "")), int(bot.get("battery_units", 0)), int(bot.get("battery_capacity", 0))],
		"INVENTORY: %d | DELIVERIES: %d | WORLD PACKAGES: %d" % [Array(projection.get("inventory", [])).size(), Array(projection.get("deliveries", [])).size(), Array(projection.get("world_packages", [])).size()],
	]


func _outcome_lines(prefix: String, kind: StringName, reason: StringName, detail: String, observation: Dictionary) -> Array[String]:
	var lines: Array[String] = ["[%s %s]" % [prefix, String(kind).to_upper()]]
	if not reason.is_empty():
		lines.append("REASON: %s" % String(reason))
	if not detail.is_empty():
		lines.append("DETAIL: %s" % detail)
	lines.append_array(_observation_lines(observation))
	return lines


func _observation_lines(observation: Dictionary) -> Array[String]:
	var grouped: Dictionary = {}
	for group: StringName in OBSERVATION_GROUP_ORDER:
		grouped[group] = []
	var keys: Array = observation.keys()
	keys.sort_custom(func(left: Variant, right: Variant) -> bool: return String(left) < String(right))
	for key: Variant in keys:
		var key_name: String = String(key)
		if key_name == "fact_order":
			continue
		var group: StringName = _observation_group(key_name)
		var group_facts: Array = grouped[group]
		group_facts.append("%s=%s" % [key_name, _format_value(observation[key])])
		grouped[group] = group_facts
	var lines: Array[String] = []
	for group: StringName in OBSERVATION_GROUP_ORDER:
		var group_facts: Array = grouped[group]
		if not group_facts.is_empty():
			lines.append("FACTS %s: %s" % [String(group), ", ".join(group_facts)])
	return lines


func _observation_group(key_name: String) -> StringName:
	if key_name.begins_with("battery") or key_name.begins_with("bot"):
		return &"BOT"
	if key_name.begins_with("front") or key_name.begins_with("path"):
		return &"FRONT"
	if key_name.begins_with("inventory"):
		return &"INVENTORY"
	if key_name.begins_with("delivery") or key_name.begins_with("delivered") or key_name.begins_with("remaining"):
		return &"DELIVERY"
	return &"STATE"


func _packages_by_id(packages: Array) -> Dictionary:
	var result: Dictionary = {}
	for item: Variant in packages:
		var package: Dictionary = Dictionary(item)
		result[String(package.get("id", ""))] = package.duplicate(true)
	return result


func _region_for_record(atlas_id: StringName, record: Dictionary, packages_by_id: Dictionary) -> StringName:
	if atlas_id == SandboxVisualAssetCatalogType.PACKAGES_ATLAS_ID:
		var package: Dictionary = Dictionary(packages_by_id.get(String(record.get("package_id", "")), {}))
		return StringName(String(package.get("color", "red")))
	if atlas_id == SandboxVisualAssetCatalogType.DOCKS_ATLAS_ID:
		return StringName("%s_dock" % String(record.get("kind", "delivery")))
	return &""


func _cue_for_record(atlas_id: StringName, record: Dictionary, region_id: StringName) -> String:
	if atlas_id == SandboxVisualAssetCatalogType.PACKAGES_ATLAS_ID:
		return "[PACKAGE %s]" % String(region_id).to_upper()
	return "[DOCK %s]" % String(record.get("kind", region_id)).to_upper()


func _grid_position(record: Dictionary) -> Vector2i:
	return Vector2i(int(record.get("x", 0)), int(record.get("y", 0)))


func _sort_grid_records(left: Variant, right: Variant) -> bool:
	var left_record: Dictionary = Dictionary(left)
	var right_record: Dictionary = Dictionary(right)
	var left_y: int = int(left_record.get("y", 0))
	var right_y: int = int(right_record.get("y", 0))
	if left_y != right_y:
		return left_y < right_y
	var left_x: int = int(left_record.get("x", 0))
	var right_x: int = int(right_record.get("x", 0))
	if left_x != right_x:
		return left_x < right_x
	return String(left_record.get("id", left_record.get("package_id", ""))) < String(right_record.get("id", right_record.get("package_id", "")))


func _format_value(value: Variant) -> String:
	if value == null:
		return "none"
	return str(value)
