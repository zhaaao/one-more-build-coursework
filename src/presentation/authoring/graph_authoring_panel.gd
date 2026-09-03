class_name GraphAuthoringPanel
extends Control

## Presentation-only GraphEdit adapter for the coursework authoring loop.
##
## The panel accepts player intent, delegates it through an injected session
## seam, and renders only the accepted state returned by that seam.
## It never applies a GraphEdit interaction directly to the graph projection.

const DEFAULT_ZOOM: float = 1.0
const MIN_READABLE_ZOOM: float = 0.6
const FRAME_PADDING: float = 32.0

const EXECUTION_PORT: int = 0
const DATA_PORT: int = 1
const NODE_SIZE: Vector2 = Vector2(156.0, 76.0)
const EMBEDDED_NODE_SIZE: Vector2 = Vector2(112.0, 76.0)
const EMBEDDED_NODE_MAX_HEIGHT: float = 100.0
const EMBEDDED_GRID_COLUMNS: int = 4
const EMBEDDED_GRID_STEP: Vector2 = Vector2(130.0, 130.0)
const TASK_GRID_STEP: int = 8
const EMBEDDED_GRAPH_MINIMUM_SIZE: Vector2 = Vector2(352.0, 205.0)
const CATEGORY_TOKEN_ASSET_PATH := "res://assets/art/ui_node_categories_default_256.png"
const PORT_TOKEN_ASSET_PATH := "res://assets/art/ui_graph_ports_trace_256.png"

const MORE_CONFIGURE: int = 1
const MORE_CONNECT: int = 2
const MORE_DISCONNECT: int = 3
const MORE_DELETE: int = 4
const MORE_ZOOM_IN: int = 5
const MORE_ZOOM_OUT: int = 6
const MORE_CYCLE: int = 7
const MORE_FRAME_ALL: int = 8
const MORE_RESET: int = 9


## Immutable display-only metadata for one accepted node port.
##
## Session adapters provide these records so GraphEdit remains a projection and
## never infers graph typing, identifiers, or connection order from Core state.
class PortDescriptor extends RefCounted:
	var port_id: StringName
	var ordinal: int
	var direction: StringName
	var kind: StringName
	var value_type: StringName
	var label: String

	func _init(
		next_port_id: StringName,
		next_ordinal: int,
		next_direction: StringName,
		next_kind: StringName,
		next_value_type: StringName,
		next_label: String
	) -> void:
		port_id = next_port_id
		ordinal = next_ordinal
		direction = next_direction
		kind = next_kind
		value_type = next_value_type
		label = next_label


## Typed presentation intent. Core code owns conversion to its GraphCommand.
class GraphCommandRequest extends RefCounted:
	enum Kind {
		CREATE, SELECT, MOVE, CONFIGURE, CONNECT, DISCONNECT, DELETE, UNDO, REDO,
		RESET, CONFIRM_RESET, CANCEL_RESET, AUTO_SOLVE,
	}

	var kind: Kind
	var payload: Dictionary

	func _init(next_kind: Kind, next_payload: Dictionary = {}) -> void:
		kind = next_kind
		payload = next_payload.duplicate(true)


	## Guards the presentation-to-owner boundary from engine objects at any depth.
	func contains_engine_object_payload() -> bool:
		return _contains_engine_object(payload)


	func _contains_engine_object(value: Variant) -> bool:
		if typeof(value) == TYPE_OBJECT:
			return true
		if typeof(value) == TYPE_ARRAY:
			for item: Variant in value:
				if _contains_engine_object(item):
					return true
		elif typeof(value) == TYPE_DICTIONARY:
			for key: Variant in value:
				if _contains_engine_object(key) or _contains_engine_object(value[key]):
					return true
		return false


signal embedded_command_requested(command: GraphCommandRequest)
signal embedded_busy_state_changed(is_busy: bool)
signal embedded_run_completed(succeeded: bool)


## Uses still activity cues when the accepted accessibility setting disables motion.
@export var reduced_motion_enabled: bool = false


## Accepted-state response returned by the injected session adapter.
class SessionResponse extends RefCounted:
	var accepted: bool = false
	var graph_snapshot: Dictionary = {}
	var diagnostic_code: StringName = &""
	var player_message: String = ""
	var reset_confirmation_open: bool = false
	var editing_available: bool = true

	func _init(
		next_accepted: bool,
		next_snapshot: Dictionary = {},
		next_diagnostic_code: StringName = &"",
		next_player_message: String = "",
		next_reset_confirmation_open: bool = false,
		next_editing_available: bool = true
	) -> void:
		accepted = next_accepted
		graph_snapshot = next_snapshot.duplicate(true)
		diagnostic_code = next_diagnostic_code
		player_message = next_player_message
		reset_confirmation_open = next_reset_confirmation_open
		editing_available = next_editing_available


## Narrow session seam. It keeps GraphEdit and report widgets out of Core truth.
class SessionPort extends RefCounted:
	func request(_command: GraphCommandRequest) -> SessionResponse:
		return SessionResponse.new(false, {}, &"session_unavailable", "Authoring session is unavailable.")

	func current_snapshot() -> Dictionary:
		return {}

	## Returns detached Task-admitted node choices for the palette projection.
	func creatable_node_options() -> Array[Dictionary]:
		return []

	func run_public_case(_case_id: StringName) -> Dictionary:
		return {}

	## Runs the Task-owned public roster and returns only its frozen projection.
	func run_all_public_cases() -> Dictionary:
		return run_public_case(&"")

	func completed_report() -> Dictionary:
		return {}

	func report_is_out_of_date() -> bool:
		return false

	## Supplies immutable display descriptors for the accepted node projection.
	func port_descriptors_for(_node_snapshot: Dictionary) -> Array[PortDescriptor]:
		return [
			PortDescriptor.new(&"input", 0, &"input", &"data", &"unknown", "Input"),
			PortDescriptor.new(&"output", 0, &"output", &"data", &"unknown", "Output"),
		]

	func record_view_request(_view_token: StringName) -> void:
		pass


@onready var graph_edit: GraphEdit = %GraphEdit
@onready var title_label: Label = %Title
@onready var help_label: Label = %Help
@onready var palette_option: OptionButton = %PaletteOption
@onready var create_button: Button = %CreateButton
@onready var configure_button: Button = %ConfigureButton
@onready var connect_button: Button = %ConnectButton
@onready var disconnect_button: Button = %DisconnectButton
@onready var delete_button: Button = %DeleteButton
@onready var undo_button: Button = %UndoButton
@onready var redo_button: Button = %RedoButton
@onready var move_button: Button = %MoveButton
@onready var zoom_in_button: Button = %ZoomInButton
@onready var zoom_out_button: Button = %ZoomOutButton
@onready var cycle_button: Button = %CycleButton
@onready var frame_all_button: Button = %FrameAllButton
@onready var reset_button: Button = %ResetButton
@onready var more_button: MenuButton = %MoreButton
@onready var auto_solve_button: Button = %AutoSolveButton
@onready var reset_confirmation: HBoxContainer = %ResetConfirmation
@onready var reset_prompt: Label = %ResetPrompt
@onready var reset_cancel_button: Button = %ResetCancelButton
@onready var reset_confirm_button: Button = %ResetConfirmButton
@onready var run_button: Button = %RunButton
@onready var run_all_button: Button = %RunAllButton
@onready var status_label: Label = %StatusLabel
@onready var view_label: Label = %ViewLabel
@onready var report_heading: Label = %ReportHeading
@onready var report_label: RichTextLabel = %ReportLabel
@onready var run_activity_overlay: PanelContainer = %RunActivityOverlay
@onready var run_activity_heading: Label = %RunActivityHeading
@onready var run_activity_state: Label = %RunActivityState
@onready var run_activity_marker: Label = %RunActivityMarker
@onready var _panel_container: PanelContainer = get_node("Panel") as PanelContainer
@onready var _layout: VBoxContainer = get_node("Panel/Layout") as VBoxContainer
@onready var _toolbar: GridContainer = get_node("Panel/Layout/Toolbar") as GridContainer
@onready var _workspace: HSplitContainer = get_node("Panel/Layout/Workspace") as HSplitContainer
@onready var _report_panel: VBoxContainer = get_node("Panel/Layout/Workspace/ReportPanel") as VBoxContainer

var _session: SessionPort = null
var _accepted_snapshot: Dictionary = {}
var _selected_node_id: StringName = &""
var _selected_connection_payload: Dictionary = {}
var _applying_projection_selection: bool = false
var _selected_case_id: StringName = &"public_case_1"
var _last_frame: Dictionary = {}
var _pending_connection_source_id: StringName = &""
var _pending_port_source: Dictionary = {}
var _projection_generation: int = 0
var _queued_projection_finalization_generation: int = -1
var _finalized_projection_generation: int = -1
var _port_ordinals: Dictionary = {}
var _projection_accepted_anchors: Dictionary[StringName, Vector2] = {}
var _embedded_origin_anchors: Dictionary[StringName, Vector2] = {}
var _embedded_origin_positions: Dictionary[StringName, Vector2] = {}
var _pending_node_drags: Dictionary[StringName, Dictionary] = {}
var _pending_embedded_drag_positions: Dictionary[StringName, Vector2] = {}
var _reset_invoker: Control = null
var _embedded_admission_enabled: bool = false
var _embedded_compact_layout_enabled: bool = false
var _embedded_view_initialization_pending: bool = false
var _embedded_admission_pending: bool = false
var _embedded_pending_command: GraphCommandRequest = null
var _editing_available: bool = true
var _embedded_busy: bool = false
var _category_token_atlas: ImageTexture = null
var _port_token_atlas: ImageTexture = null


## Keeps the standalone authoring scene unchanged while exposing the complete
## typed authoring toolbar when the host embeds this panel.
func enable_embedded_compact_layout() -> void:
	if not is_node_ready():
		call_deferred("enable_embedded_compact_layout")
		return
	_embedded_compact_layout_enabled = true
	_embedded_view_initialization_pending = true
	_panel_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_toolbar.visible = true
	_toolbar.columns = 4
	palette_option.fit_to_longest_item = false
	status_label.visible = false
	view_label.visible = false
	title_label.visible = false
	help_label.visible = false
	_report_panel.visible = false
	_workspace.custom_minimum_size = EMBEDDED_GRAPH_MINIMUM_SIZE
	_workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace.split_offset = 0
	graph_edit.custom_minimum_size = EMBEDDED_GRAPH_MINIMUM_SIZE
	graph_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_edit.minimap_enabled = false
	_report_panel.custom_minimum_size = Vector2.ZERO
	_report_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_report_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for control: Control in [palette_option, create_button, configure_button, connect_button,
		disconnect_button, delete_button, undo_button, redo_button, move_button, zoom_in_button,
		zoom_out_button, cycle_button, frame_all_button, reset_button, more_button, auto_solve_button, run_button,
		run_all_button]:
		control.custom_minimum_size = Vector2(0.0, 44.0)
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if control is Button:
			(control as Button).clip_text = true
	for secondary_control: Control in [configure_button, connect_button, disconnect_button,
		delete_button, move_button, zoom_in_button, zoom_out_button, cycle_button,
		frame_all_button, reset_button]:
		secondary_control.hide()
	more_button.show()
	auto_solve_button.show()
	_apply_embedded_toolbar_copy()
	_configure_embedded_focus_graph()
	_reset_embedded_projection_origins()
	_project_accepted_state()
	# Switching from the standalone projection to the embedded grid establishes
	# a new view mode. Frame that mode once, then preserve it across graph edits.
	_frame_all()
	_queue_projection_finalization(_projection_generation)
	graph_edit.resized.connect(_frame_embedded_projection_after_layout)
	graph_edit.visibility_changed.connect(_frame_embedded_projection_after_layout)
	if run_button.pressed.is_connected(run_selected_public_case):
		run_button.pressed.disconnect(run_selected_public_case)
	if not run_button.pressed.is_connected(request_embedded_run_selected):
		run_button.pressed.connect(request_embedded_run_selected)
	if run_all_button.pressed.is_connected(run_all_public_cases):
		run_all_button.pressed.disconnect(run_all_public_cases)
	if not run_all_button.pressed.is_connected(request_embedded_run_all):
		run_all_button.pressed.connect(request_embedded_run_all)


## Uses compact labels only for the constrained embedded workstation pane.
func _apply_embedded_toolbar_copy() -> void:
	palette_option.tooltip_text = tr("Choose a coursework node category.")
	create_button.text = tr("Add")
	create_button.tooltip_text = tr("Create selected node")
	configure_button.text = tr("Edit")
	configure_button.tooltip_text = tr("Configure selected node")
	connect_button.text = tr("Link")
	connect_button.tooltip_text = tr("Connect selected nodes")
	disconnect_button.text = tr("Unlink")
	disconnect_button.tooltip_text = tr("Disconnect selected connection")
	delete_button.text = tr("Delete")
	delete_button.tooltip_text = tr("Delete selected node")
	undo_button.tooltip_text = tr("Undo")
	redo_button.tooltip_text = tr("Redo")
	move_button.text = tr("Move")
	move_button.tooltip_text = tr("Move selected right")
	zoom_in_button.text = tr("Zoom+")
	zoom_in_button.tooltip_text = tr("Zoom in")
	zoom_out_button.text = tr("Zoom-")
	zoom_out_button.tooltip_text = tr("Zoom out")
	cycle_button.text = tr("Cycle")
	cycle_button.tooltip_text = tr("Cycle overlap")
	frame_all_button.text = tr("Frame")
	frame_all_button.tooltip_text = tr("Frame All (Home)")
	reset_button.text = tr("Reset")
	reset_button.tooltip_text = tr("Reset graph")
	more_button.text = tr("Actions")
	more_button.tooltip_text = tr("Configure, connect, delete, view, and reset actions")
	auto_solve_button.text = tr("AUTO SOLVE")
	auto_solve_button.tooltip_text = tr("Restore this Task and apply its admitted witness edits")
	run_button.text = tr("Run")
	run_button.tooltip_text = tr("Run selected public case (F5)")
	run_all_button.text = tr("Run all public")
	run_all_button.tooltip_text = tr("Run all public cases (Ctrl+F5)")


## Enables the host-owned typed admission seam without changing standalone mode.
func enable_embedded_admission() -> void:
	_embedded_admission_enabled = true


## Legacy primary action is deliberately unavailable: player repair uses typed controls.
func request_embedded_primary_action() -> bool:
	_show_rejection(&"legacy_primary_action_removed", tr("Use the graph authoring controls to repair this Task."))
	return false


## Begins a selected-case Run after the next process frame has painted busy state.
func request_embedded_run_selected() -> bool:
	return _request_embedded_run(false)


## Begins a full public-case Run after the next process frame has painted busy state.
func request_embedded_run_all() -> bool:
	return _request_embedded_run(true)


## Requests the Task-owned witness through the same typed owner seam as graph edits.
func request_embedded_auto_solve() -> bool:
	return request_pointer(GraphCommandRequest.new(GraphCommandRequest.Kind.AUTO_SOLVE))


## Reports whether embedded input must reject re-entry while an owner call is pending.
func is_embedded_busy() -> bool:
	return _embedded_busy


## Reports whether the existing Authoring reset confirmation currently owns input.
func has_open_confirmation() -> bool:
	return is_instance_valid(reset_confirmation) and reset_confirmation.visible


## Routes Escape to the existing confirmation cancellation command when it is open.
func handle_embedded_escape() -> bool:
	if not has_open_confirmation():
		return false
	return request_keyboard(GraphCommandRequest.new(GraphCommandRequest.Kind.CANCEL_RESET))


## Completes a host-forwarded admission from the existing typed accepted-state seam.
func complete_embedded_admission(response: SessionResponse) -> bool:
	var pending_command: GraphCommandRequest = _embedded_pending_command
	_embedded_admission_pending = false
	_embedded_pending_command = null
	_editing_available = response.editing_available
	if not response.accepted:
		_show_rejection(response.diagnostic_code, response.player_message)
		if pending_command != null and pending_command.kind == GraphCommandRequest.Kind.AUTO_SOLVE \
				and _is_graph_snapshot(response.graph_snapshot):
			_accepted_snapshot = response.graph_snapshot.duplicate(true)
			_project_accepted_state()
		elif pending_command != null and pending_command.kind == GraphCommandRequest.Kind.MOVE:
			_pending_embedded_drag_positions.erase(StringName(pending_command.payload.get("node_id", "")))
			_project_accepted_state()
		return false
	if not _is_graph_snapshot(response.graph_snapshot):
		_show_rejection(&"owner_projection_unavailable", tr("Authoring could not provide the accepted graph."))
		return false
	_accepted_snapshot = response.graph_snapshot.duplicate(true)
	_retain_accepted_embedded_drag_position(pending_command)
	if pending_command != null and pending_command.kind == GraphCommandRequest.Kind.SELECT:
		_select_node(StringName(pending_command.payload.get("node_id", "")))
	status_label.text = response.player_message
	_set_reset_confirmation(response.reset_confirmation_open)
	if pending_command == null or pending_command.kind != GraphCommandRequest.Kind.SELECT:
		_project_accepted_state()
	return true


## Exposes owner-provided edit availability through the same typed admission seam.
func is_editing_available() -> bool:
	return _editing_available


## Injects the non-UI session adapter. The scene remains testable in isolation.
func configure_session(session: SessionPort) -> void:
	var session_changed: bool = _session != session
	if session_changed:
		_clear_changed_session_interaction_state()
	_session = session
	_accepted_snapshot = session.current_snapshot()
	_pending_node_drags.clear()
	_pending_port_source = {}
	if session_changed:
		_reset_embedded_projection_origins()
	if _embedded_compact_layout_enabled:
		_embedded_view_initialization_pending = true
		graph_edit.zoom = DEFAULT_ZOOM
		graph_edit.scroll_offset = Vector2.ZERO
	if is_node_ready():
		_configure_copy()
		_refresh_palette_options()
		_project_accepted_state()
		if _embedded_compact_layout_enabled:
			_frame_all()
			_queue_projection_finalization(_projection_generation)
		_render_report(session.completed_report())
		if session_changed:
			graph_edit.call_deferred("grab_focus")


func _clear_changed_session_interaction_state() -> void:
	_selected_node_id = &""
	_selected_connection_payload = {}
	_pending_connection_source_id = &""
	_pending_port_source = {}
	_pending_node_drags.clear()
	_pending_embedded_drag_positions.clear()
	_embedded_admission_pending = false
	_embedded_pending_command = null
	_reset_invoker = null
	_set_reset_confirmation(false)
	_clear_selected_connection()


## Returns the required command IDs in stable focus order for deterministic tests.
func required_command_ids() -> Array[StringName]:
	return [
		&"palette", &"create", &"configure", &"connect", &"disconnect", &"delete",
		&"undo", &"redo", &"move", &"zoom_in", &"zoom_out", &"cycle_overlap",
		&"frame_all", &"reset", &"auto_solve", &"reset_cancel", &"reset_confirm", &"run", &"run_all", &"report",
	]


## Returns non-colour state/error meanings used by the visible command surface.
func critical_meaning_labels() -> Array[String]:
	return ["OUT OF DATE — still readable", "Run did not return a completed report.", "Selected node"]


## Receives a pointer-originated command and routes it through the shared seam.
func request_pointer(command: GraphCommandRequest) -> bool:
	return _submit_command(command)


## Receives a keyboard-originated command and routes it through the shared seam.
func request_keyboard(command: GraphCommandRequest) -> bool:
	return _submit_command(command)


## Requests one selected public case without retaining any execution truth.
func run_selected_public_case() -> bool:
	return _run_cases(false)


## Requests the task's full public-case roster through the injected session.
func run_all_public_cases() -> bool:
	return _run_cases(true)


func _run_cases(run_all: bool) -> bool:
	if _session == null:
		_show_rejection(&"session_unavailable", tr("Authoring session is unavailable."))
		return false
	var report: Dictionary = _session.run_all_public_cases() if run_all \
		else _session.run_public_case(_selected_case_id)
	if report.is_empty():
		_show_rejection(&"run_unavailable", tr("Run did not return a completed report."))
		return false
	_render_report(report)
	return true


func _request_embedded_run(run_all: bool) -> bool:
	if _embedded_busy:
		_show_rejection(&"owner_pending", tr("Run is already waiting for the owner."))
		return false
	if _session == null:
		_show_rejection(&"session_unavailable", tr("Authoring session is unavailable."))
		return false
	_set_embedded_busy(true)
	_show_run_activity_preparing(run_all)
	_run_embedded_after_process_frame(run_all)
	return true


func _run_embedded_after_process_frame(run_all: bool) -> void:
	await get_tree().process_frame
	if not _embedded_busy:
		return
	_show_run_activity_in_progress(run_all, 1)
	await get_tree().process_frame
	if not _embedded_busy:
		return
	if not reduced_motion_enabled:
		_show_run_activity_in_progress(run_all, 2)
		await get_tree().process_frame
		if not _embedded_busy:
			return
	var succeeded: bool = _run_cases(run_all)
	_finish_run_activity(succeeded)
	_set_embedded_busy(false)
	embedded_run_completed.emit(succeeded)


func _set_embedded_busy(next_busy: bool) -> void:
	if _embedded_busy == next_busy:
		return
	_embedded_busy = next_busy
	graph_edit.mouse_filter = Control.MOUSE_FILTER_STOP
	for control: Control in [palette_option, create_button, configure_button, connect_button,
		disconnect_button, delete_button, undo_button, redo_button, move_button, reset_button,
		more_button, auto_solve_button, run_button, run_all_button, reset_cancel_button, reset_confirm_button]:
		control.disabled = next_busy or not _editing_available
	embedded_busy_state_changed.emit(next_busy)


func _show_run_activity_preparing(run_all: bool) -> void:
	run_activity_overlay.show()
	run_activity_heading.text = tr("Preparing Run")
	run_activity_state.text = tr("Preparing Run: %s. The workspace is read-only.") % _run_activity_identity(run_all)
	run_activity_marker.text = tr("Activity: ● ○ ○")
	run_activity_heading.focus_next = run_activity_heading.get_path()
	run_activity_heading.focus_previous = run_activity_heading.get_path()
	run_activity_heading.call_deferred("grab_focus")


func _show_run_activity_in_progress(run_all: bool, step: int) -> void:
	run_activity_heading.text = tr("Run in progress")
	run_activity_state.text = tr("Run in progress: %s. Waiting for the completed Results.") % _run_activity_identity(run_all)
	if reduced_motion_enabled:
		run_activity_marker.text = tr("Activity: ● ○ ○")
		return
	match step:
		1:
			run_activity_marker.text = tr("Activity: ○ ● ○")
		_:
			run_activity_marker.text = tr("Activity: ○ ○ ●")


func _run_activity_identity(run_all: bool) -> String:
	return tr("Run all public") if run_all else tr("Selected public case")


func _finish_run_activity(succeeded: bool) -> void:
	status_label.text = tr("Run complete. Results are ready.") if succeeded \
		else tr("Run ended without a completed report.")
	run_activity_overlay.hide()
	run_activity_heading.focus_next = NodePath()
	run_activity_heading.focus_previous = NodePath()
	if report_label.is_visible_in_tree():
		report_label.grab_focus()


## Calculates the bounded Frame All projection without modifying graph truth.
static func calculate_frame_all(viewport_size: Vector2, node_rects: Array[Rect2]) -> Dictionary:
	if node_rects.is_empty():
		return {"zoom": DEFAULT_ZOOM, "center": Vector2.ZERO, "empty": true}
	var bounds: Rect2 = node_rects[0]
	for index: int in range(1, node_rects.size()):
		bounds = bounds.merge(node_rects[index])
	bounds = bounds.grow(FRAME_PADDING)
	var usable_width: float = maxf(viewport_size.x, 1.0)
	var usable_height: float = maxf(viewport_size.y, 1.0)
	var fit_zoom: float = minf(usable_width / bounds.size.x, usable_height / bounds.size.y)
	return {
		"zoom": maxf(MIN_READABLE_ZOOM, minf(DEFAULT_ZOOM, fit_zoom)),
		"center": bounds.get_center(),
		"empty": false,
	}


## Returns the latest view-only Frame All projection for deterministic tests.
func last_frame_projection() -> Dictionary:
	return _last_frame.duplicate(true)


func _ready() -> void:
	_cache_token_atlases()
	_configure_copy()
	_connect_controls()
	if _session == null:
		_show_rejection(&"session_unavailable", tr("Authoring session is unavailable."))
		return
	_project_accepted_state()
	palette_option.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if _embedded_busy:
		get_viewport().set_input_as_handled()
		return
	if _handle_command_shortcut(event) or _handle_view_shortcut(event) or _handle_action_shortcut(event):
		get_viewport().set_input_as_handled()


func _handle_command_shortcut(event: InputEventKey) -> bool:
	if event.keycode == KEY_F2:
		_configure_selected()
		return true
	elif event.alt_pressed and event.keycode == KEY_DELETE:
		_request_selected_connection_disconnect(false)
		return true
	elif event.keycode == KEY_DELETE:
		request_keyboard(GraphCommandRequest.new(GraphCommandRequest.Kind.DELETE, {"node_id": _selected_node_id}))
		return true
	elif event.ctrl_pressed and event.keycode == KEY_Z:
		request_keyboard(GraphCommandRequest.new(GraphCommandRequest.Kind.UNDO))
		return true
	elif event.ctrl_pressed and event.keycode == KEY_Y:
		request_keyboard(GraphCommandRequest.new(GraphCommandRequest.Kind.REDO))
		return true
	return false


func _handle_view_shortcut(event: InputEventKey) -> bool:
	if event.keycode == KEY_HOME:
		_frame_all()
		return true
	elif event.ctrl_pressed and event.keycode == KEY_EQUAL:
		_increase_zoom()
		return true
	elif event.ctrl_pressed and event.keycode == KEY_MINUS:
		_decrease_zoom()
		return true
	elif event.ctrl_pressed and event.keycode == KEY_PERIOD:
		_cycle_overlap()
		return true
	elif event.keycode == KEY_LEFT or event.keycode == KEY_RIGHT or event.keycode == KEY_UP or event.keycode == KEY_DOWN:
		_move_selected_with_key(event.keycode)
		return true
	return false


func _handle_action_shortcut(event: InputEventKey) -> bool:
	if event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_R:
		_request_reset(_keyboard_reset_invoker(), true)
		return true
	elif event.keycode == KEY_F5:
		if event.ctrl_pressed:
			if _embedded_compact_layout_enabled:
				request_embedded_run_all()
			else:
				run_all_public_cases()
		else:
			if _embedded_compact_layout_enabled:
				request_embedded_run_selected()
			else:
				run_selected_public_case()
		return true
	elif event.keycode == KEY_ESCAPE:
		if reset_confirmation.visible:
			request_keyboard(GraphCommandRequest.new(GraphCommandRequest.Kind.CANCEL_RESET))
		else:
			_pending_connection_source_id = &""
			_pending_port_source = {}
			_clear_selected_connection()
			status_label.text = tr("Connection selection cancelled.")
		return true
	elif event.keycode == KEY_ENTER or event.keycode == KEY_SPACE:
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused is GraphNode:
			request_keyboard(GraphCommandRequest.new(GraphCommandRequest.Kind.SELECT, {"node_id": focused.name}))
			return true
	return false


func _connect_controls() -> void:
	create_button.pressed.connect(_create_from_palette)
	if not palette_option.item_selected.is_connected(_on_palette_option_selected):
		palette_option.item_selected.connect(_on_palette_option_selected)
	configure_button.pressed.connect(_configure_selected)
	connect_button.pressed.connect(_connect_selected_nodes)
	disconnect_button.pressed.connect(_disconnect_selected)
	_connect_command_buttons()
	_connect_view_buttons()
	_connect_reset_and_run_buttons()
	_configure_more_menu()
	_connect_graph_edit_requests()
	_configure_focus_graph()


func _connect_command_buttons() -> void:
	delete_button.pressed.connect(func() -> void:
		request_pointer(GraphCommandRequest.new(GraphCommandRequest.Kind.DELETE, {"node_id": _selected_node_id})))
	undo_button.pressed.connect(func() -> void:
		request_pointer(GraphCommandRequest.new(GraphCommandRequest.Kind.UNDO)))
	redo_button.pressed.connect(func() -> void:
		request_pointer(GraphCommandRequest.new(GraphCommandRequest.Kind.REDO)))
	move_button.pressed.connect(_move_selected_pointer_right)


func _connect_view_buttons() -> void:
	zoom_in_button.pressed.connect(_increase_zoom)
	zoom_out_button.pressed.connect(_decrease_zoom)
	cycle_button.pressed.connect(_cycle_overlap)
	frame_all_button.pressed.connect(_frame_all)


func _connect_reset_and_run_buttons() -> void:
	reset_button.pressed.connect(func() -> void: _request_reset(reset_button))
	reset_cancel_button.pressed.connect(func() -> void:
		request_pointer(GraphCommandRequest.new(GraphCommandRequest.Kind.CANCEL_RESET)))
	reset_confirm_button.pressed.connect(func() -> void:
		request_pointer(GraphCommandRequest.new(GraphCommandRequest.Kind.CONFIRM_RESET)))
	auto_solve_button.pressed.connect(request_embedded_auto_solve)
	run_button.pressed.connect(request_embedded_run_selected)
	run_all_button.pressed.connect(request_embedded_run_all)


func _configure_more_menu() -> void:
	var popup: PopupMenu = more_button.get_popup()
	popup.clear()
	popup.add_item(tr("Configure selected node (F2)"), MORE_CONFIGURE)
	popup.add_item(tr("Connect selected nodes"), MORE_CONNECT)
	popup.add_item(tr("Disconnect selected connection (Alt+Delete)"), MORE_DISCONNECT)
	popup.add_item(tr("Delete selected node (Delete)"), MORE_DELETE)
	popup.add_separator()
	popup.add_item(tr("Zoom in (Ctrl+=)"), MORE_ZOOM_IN)
	popup.add_item(tr("Zoom out (Ctrl+-)"), MORE_ZOOM_OUT)
	popup.add_item(tr("Cycle overlapping nodes (Ctrl+.)"), MORE_CYCLE)
	popup.add_item(tr("Frame all (Home)"), MORE_FRAME_ALL)
	popup.add_separator()
	popup.add_item(tr("Reset graph… (Ctrl+Shift+R)"), MORE_RESET)
	if not popup.id_pressed.is_connected(_on_more_action_selected):
		popup.id_pressed.connect(_on_more_action_selected)


func _on_more_action_selected(action_id: int) -> void:
	match action_id:
		MORE_CONFIGURE: _configure_selected()
		MORE_CONNECT: _connect_selected_nodes()
		MORE_DISCONNECT: _disconnect_selected()
		MORE_DELETE:
			request_pointer(GraphCommandRequest.new(
				GraphCommandRequest.Kind.DELETE, {"node_id": _selected_node_id}))
		MORE_ZOOM_IN: _increase_zoom()
		MORE_ZOOM_OUT: _decrease_zoom()
		MORE_CYCLE: _cycle_overlap()
		MORE_FRAME_ALL: _frame_all()
		MORE_RESET: _request_reset(more_button)


func _connect_graph_edit_requests() -> void:
	graph_edit.connection_request.connect(_on_connection_request)
	graph_edit.disconnection_request.connect(_on_disconnection_request)
	graph_edit.delete_nodes_request.connect(_on_delete_nodes_request)
	graph_edit.gui_input.connect(_on_graph_edit_gui_input)


func _configure_focus_graph() -> void:
	palette_option.focus_neighbor_bottom = create_button.get_path()
	create_button.focus_neighbor_right = configure_button.get_path()
	configure_button.focus_neighbor_right = connect_button.get_path()
	connect_button.focus_neighbor_right = disconnect_button.get_path()
	disconnect_button.focus_neighbor_right = delete_button.get_path()
	delete_button.focus_neighbor_right = undo_button.get_path()
	undo_button.focus_neighbor_right = redo_button.get_path()
	redo_button.focus_neighbor_right = move_button.get_path()
	move_button.focus_neighbor_right = zoom_in_button.get_path()
	zoom_in_button.focus_neighbor_right = zoom_out_button.get_path()
	zoom_out_button.focus_neighbor_right = cycle_button.get_path()
	cycle_button.focus_neighbor_right = frame_all_button.get_path()
	frame_all_button.focus_neighbor_right = reset_button.get_path()
	reset_button.focus_neighbor_right = auto_solve_button.get_path()
	auto_solve_button.focus_neighbor_right = run_button.get_path()
	run_button.focus_neighbor_right = run_all_button.get_path()
	reset_cancel_button.focus_neighbor_right = reset_confirm_button.get_path()
	reset_confirm_button.focus_neighbor_left = reset_cancel_button.get_path()
	reset_cancel_button.focus_next = reset_confirm_button.get_path()
	reset_cancel_button.focus_previous = reset_confirm_button.get_path()
	reset_confirm_button.focus_next = reset_cancel_button.get_path()
	reset_confirm_button.focus_previous = reset_cancel_button.get_path()


func _configure_embedded_focus_graph() -> void:
	var focus_order: Array[Control] = [
		palette_option, create_button, undo_button, redo_button, more_button,
		auto_solve_button, run_button, run_all_button, graph_edit,
	]
	for index: int in range(focus_order.size()):
		var control: Control = focus_order[index]
		var previous: Control = focus_order[(index - 1 + focus_order.size()) % focus_order.size()]
		var next: Control = focus_order[(index + 1) % focus_order.size()]
		control.focus_previous = previous.get_path()
		control.focus_next = next.get_path()
		control.focus_neighbor_left = previous.get_path()
		control.focus_neighbor_right = next.get_path()


func _create_from_palette() -> void:
	var metadata: Variant = palette_option.get_item_metadata(palette_option.selected)
	var category: StringName = StringName(palette_option.get_item_text(palette_option.selected))
	var variant_id: StringName = &""
	if typeof(metadata) == TYPE_DICTIONARY:
		var option: Dictionary = metadata
		category = StringName(option.get("category", category))
		variant_id = StringName(option.get("variant_id", ""))
	request_pointer(GraphCommandRequest.new(GraphCommandRequest.Kind.CREATE, {
		"category": category, "variant_id": variant_id,
		"anchor": {},
	}))


func _refresh_palette_options() -> void:
	if _session == null:
		return
	var options: Array[Dictionary] = _session.creatable_node_options()
	if options.is_empty():
		return
	palette_option.clear()
	for option: Dictionary in options:
		var category: String = String(option.get("category", ""))
		var variant_id: String = String(option.get("id", option.get("variant_id", "")))
		var detail: String = _player_readable_variant_label(category, variant_id)
		palette_option.add_item("%s · %s" % [category, detail])
		palette_option.set_item_metadata(palette_option.item_count - 1, {
			"category": category, "variant_id": variant_id,
		})
	_on_palette_option_selected(palette_option.selected)


func _on_palette_option_selected(index: int) -> void:
	if index >= 0 and index < palette_option.item_count:
		palette_option.tooltip_text = palette_option.get_item_text(index)


func _configure_selected() -> void:
	request_pointer(GraphCommandRequest.new(GraphCommandRequest.Kind.CONFIGURE, {
		"node_id": _selected_node_id,
		"parameter_index": 0,
		"value": true,
	}))


func _disconnect_selected() -> void:
	_request_selected_connection_disconnect(true)


## Captures a player-selected GraphEdit connection without changing owner state.
func _on_graph_edit_gui_input(event: InputEvent) -> void:
	if _embedded_busy:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo \
				and (_handle_command_shortcut(key_event) \
				or _handle_view_shortcut(key_event) \
				or _handle_action_shortcut(key_event)):
			graph_edit.accept_event()
		return
	if not event is InputEventMouseButton:
		return
	var pointer_event := event as InputEventMouseButton
	if pointer_event.button_index != MOUSE_BUTTON_LEFT or not pointer_event.pressed:
		return
	var closest: Dictionary = graph_edit.get_closest_connection_at_point(pointer_event.position, 12.0)
	if closest.is_empty():
		_clear_selected_connection()
		return
	var source_node := StringName(closest.get("from_node", closest.get("output_node_id", "")))
	var target_node := StringName(closest.get("to_node", closest.get("input_node_id", "")))
	var source_port := int(closest.get("from_port", closest.get("output_port", -1)))
	var target_port := int(closest.get("to_port", closest.get("input_port", -1)))
	graph_edit.grab_focus()
	_select_connection_endpoints(source_node, source_port, target_node, target_port)


func _select_connection_endpoints(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
) -> bool:
	if from_node.is_empty() or to_node.is_empty() or from_port < 0 or to_port < 0:
		_clear_selected_connection()
		return false
	_selected_connection_payload = _connection_endpoint_payload(from_node, from_port, to_node, to_port)
	status_label.text = tr("Selected connection. Disconnect is ready.")
	return true


## Returns the selected connection as a typed disconnect payload for tests.
func selected_connection_payload_for_test() -> Dictionary:
	return _selected_connection_payload.duplicate(true)


func _connection_endpoint_payload(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
) -> Dictionary:
	return {
		"output_node_id": from_node,
		"output_port_id": _stable_port_id(from_node, &"output", from_port),
		"input_node_id": to_node,
		"input_port_id": _stable_port_id(to_node, &"input", to_port),
	}


func _request_selected_connection_disconnect(is_pointer: bool) -> void:
	if _selected_connection_payload.is_empty():
		_show_rejection(&"connection_selection_required", tr("Select a connection before disconnecting."))
		return
	var command := GraphCommandRequest.new(
		GraphCommandRequest.Kind.DISCONNECT, _selected_connection_payload)
	if is_pointer:
		request_pointer(command)
	else:
		request_keyboard(command)


func _clear_selected_connection() -> void:
	_selected_connection_payload = {}


func _connect_selected_nodes() -> void:
	if _selected_node_id.is_empty():
		_show_rejection(&"connection_selection_required", tr("Select a source node, then a target node."))
		return
	if _pending_connection_source_id.is_empty():
		_pending_connection_source_id = _selected_node_id
		status_label.text = tr("Connection source selected: %s. Select a target and activate Connect again.") % _selected_node_id
		return
	if _pending_connection_source_id == _selected_node_id:
		_show_rejection(&"connection_target_required", tr("Choose a different target node for the connection."))
		return
	request_pointer(GraphCommandRequest.new(GraphCommandRequest.Kind.CONNECT, {
		"output_node_id": _pending_connection_source_id,
		"output_port_id": _stable_port_id(_pending_connection_source_id, &"output", 0),
		"input_node_id": _selected_node_id,
		"input_port_id": _stable_port_id(_selected_node_id, &"input", 0),
	}))
	_pending_connection_source_id = &""


func _on_connection_request(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
) -> void:
	request_pointer(GraphCommandRequest.new(GraphCommandRequest.Kind.CONNECT, {
		"output_node_id": from_node,
		"output_port_id": _stable_port_id(from_node, &"output", from_port),
		"input_node_id": to_node,
		"input_port_id": _stable_port_id(to_node, &"input", to_port),
	}))


func _on_disconnection_request(
	from_node: StringName, from_port: int, to_node: StringName, to_port: int
) -> void:
	request_pointer(GraphCommandRequest.new(GraphCommandRequest.Kind.DISCONNECT, {
		"output_node_id": from_node,
		"output_port_id": _stable_port_id(from_node, &"output", from_port),
		"input_node_id": to_node,
		"input_port_id": _stable_port_id(to_node, &"input", to_port),
	}))


func _on_delete_nodes_request(node_ids: Array[StringName]) -> void:
	if node_ids.is_empty():
		return
	request_pointer(GraphCommandRequest.new(GraphCommandRequest.Kind.DELETE, {
		"node_ids": node_ids.duplicate(true),
	}))


func _submit_command(command: GraphCommandRequest) -> bool:
	if _embedded_busy:
		_show_rejection(&"owner_pending", tr("Graph changes are unavailable while the owner is running."))
		return false
	if command.contains_engine_object_payload():
		_show_rejection(&"invalid_owner_payload", tr("This graph request cannot be sent."))
		return false
	if _embedded_admission_enabled:
		if _embedded_admission_pending:
			_show_rejection(&"owner_pending", tr("Graph change is waiting for authoring."))
			return false
		_embedded_admission_pending = true
		_embedded_pending_command = command
		embedded_command_requested.emit(command)
		return true
	if _session == null:
		_show_rejection(&"session_unavailable", tr("Authoring session is unavailable."))
		return false
	var response: SessionResponse = _session.request(command)
	if not response.accepted:
		_show_rejection(response.diagnostic_code, response.player_message)
		return false
	_accepted_snapshot = response.graph_snapshot
	_editing_available = response.editing_available
	_retain_accepted_embedded_drag_position(command)
	if command.kind == GraphCommandRequest.Kind.SELECT:
		_select_node(StringName(command.payload.get("node_id", "")))
	_set_reset_confirmation(response.reset_confirmation_open)
	if command.kind != GraphCommandRequest.Kind.SELECT:
		_project_accepted_state()
		_render_report(_session.completed_report())
	return true


func _project_accepted_state() -> void:
	if not is_node_ready():
		return
	var initialize_view := _projection_generation == 0
	var preserved_zoom := graph_edit.zoom
	var preserved_scroll_offset := graph_edit.scroll_offset
	_clear_selected_connection()
	graph_edit.clear_connections()
	_port_ordinals = {}
	_projection_accepted_anchors = {}
	for child: Node in graph_edit.get_children():
		if child is GraphNode:
			graph_edit.remove_child(child)
			child.queue_free()
	var projection_index: int = 0
	for raw_node: Variant in _accepted_snapshot.get("nodes", []):
		if typeof(raw_node) == TYPE_DICTIONARY:
			_add_node_projection(Dictionary(raw_node), projection_index)
			projection_index += 1
	for raw_connection: Variant in _accepted_snapshot.get("connections", []):
		if typeof(raw_connection) == TYPE_DICTIONARY:
			var connection: Dictionary = raw_connection
			var output_node_id: StringName = StringName(connection.get("output_node_id", connection.get("source_node_id", "")))
			var input_node_id: StringName = StringName(connection.get("input_node_id", connection.get("target_node_id", "")))
			graph_edit.connect_node(
				output_node_id,
				_projected_port_ordinal(output_node_id, &"output", connection.get(
					"output_port_id", connection.get("source_port_id", connection.get("output_port", 0)))),
				input_node_id,
				_projected_port_ordinal(input_node_id, &"input", connection.get(
					"input_port_id", connection.get("target_port_id", connection.get("input_port", 0)))))
	_projection_generation += 1
	if initialize_view:
		_frame_all()
		_queue_projection_finalization(_projection_generation)
	else:
		graph_edit.zoom = preserved_zoom
		graph_edit.scroll_offset = preserved_scroll_offset
		call_deferred(
			"_restore_projection_view_after_layout",
			_projection_generation,
			preserved_zoom,
			preserved_scroll_offset)


func _is_graph_snapshot(snapshot: Dictionary) -> bool:
	return snapshot.has("nodes") and snapshot.has("connections") \
		and typeof(snapshot["nodes"]) == TYPE_ARRAY and typeof(snapshot["connections"]) == TYPE_ARRAY


## Defers one layout-dependent Frame All pass for each accepted projection.
## A Frame All may resize GraphEdit, so the generation gate prevents feedback.
func _queue_projection_finalization(generation: int) -> void:
	if generation != _projection_generation \
			or generation == _queued_projection_finalization_generation \
			or generation == _finalized_projection_generation:
		return
	_queued_projection_finalization_generation = generation
	call_deferred("_finalize_projection_after_layout", generation)


func _finalize_projection_after_layout(generation: int) -> void:
	if generation != _projection_generation or generation != _queued_projection_finalization_generation \
			or not is_instance_valid(graph_edit):
		return
	_queued_projection_finalization_generation = -1
	if not graph_edit.is_visible_in_tree() or graph_edit.size.x <= 0.0 or graph_edit.size.y <= 0.0:
		return
	_finalized_projection_generation = generation
	_frame_all()
	_embedded_view_initialization_pending = false


func _restore_projection_view_after_layout(
	generation: int, preserved_zoom: float, preserved_scroll_offset: Vector2
) -> void:
	if generation != _projection_generation or not is_instance_valid(graph_edit):
		return
	graph_edit.zoom = preserved_zoom
	graph_edit.scroll_offset = preserved_scroll_offset


func _frame_embedded_projection_after_layout() -> void:
	if _embedded_compact_layout_enabled and _embedded_view_initialization_pending:
		_queue_projection_finalization(_projection_generation)


func _fit_compact_node_size(graph_node: GraphNode) -> void:
	graph_node.reset_size()
	var maximum_height: float = EMBEDDED_NODE_MAX_HEIGHT if _embedded_compact_layout_enabled else 130.0
	var width: float = EMBEDDED_NODE_SIZE.x if _embedded_compact_layout_enabled else NODE_SIZE.x
	graph_node.size = Vector2(
		width,
		minf(maxf(graph_node.size.y, NODE_SIZE.y), maximum_height))


func _add_node_projection(node_data: Dictionary, projection_index: int) -> void:
	var graph_node := GraphNode.new()
	var node_id: StringName = StringName(node_data.get("node_id", ""))
	var anchor: Dictionary = Dictionary(node_data.get("anchor", {
		"x": node_data.get("anchor_x", 0), "y": node_data.get("anchor_y", 0),
	}))
	graph_node.name = node_id
	var category_id: StringName = StringName(node_data.get("category_id", node_data.get("category", "")))
	var category: String = str(category_id) if not category_id.is_empty() else str(node_data.get("variant_id", "Node"))
	var variant: String = str(node_data.get("variant_id", ""))
	graph_node.title = category
	graph_node.tooltip_text = tr("Category: %s · Detail: %s") % [category, variant]
	graph_node.selected = node_id == _selected_node_id
	var accepted_anchor := Vector2(float(anchor.get("x", 0)), float(anchor.get("y", 0)))
	_projection_accepted_anchors[node_id] = accepted_anchor
	graph_node.position_offset = _projection_position(node_id, accepted_anchor, projection_index)
	graph_node.clip_contents = true
	graph_node.mouse_filter = Control.MOUSE_FILTER_STOP
	graph_node.draggable = true
	_add_variant_detail_label(graph_node, category, variant)
	_add_port_projection(graph_node, node_id, _port_descriptors_for_projection(node_data))
	_add_category_token(graph_node, category_id)
	graph_node.focus_mode = Control.FOCUS_ALL
	graph_node.node_selected.connect(func() -> void:
		if _applying_projection_selection or node_id == _selected_node_id:
			return
		request_pointer(GraphCommandRequest.new(GraphCommandRequest.Kind.SELECT, {"node_id": node_id})))
	graph_node.dragged.connect(func(from: Vector2, to: Vector2) -> void:
		_queue_node_drag(node_id, from, to))
	graph_edit.add_child(graph_node)
	graph_node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	graph_node.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_fit_compact_node_size(graph_node)


func _projection_position(
		node_id: StringName, accepted_anchor: Vector2, projection_index: int
) -> Vector2:
	if not _embedded_compact_layout_enabled:
		return accepted_anchor
	if not _embedded_origin_anchors.has(node_id):
		_embedded_origin_anchors[node_id] = accepted_anchor
		_embedded_origin_positions[node_id] = _next_embedded_grid_position(
			node_id, projection_index)
	return _embedded_origin_positions[node_id] + accepted_anchor - _embedded_origin_anchors[node_id]


func _next_embedded_grid_position(node_id: StringName, fallback_index: int) -> Vector2:
	var slot_index: int = maxi(fallback_index, 0)
	var node_token := String(node_id)
	if node_token.begins_with("node_"):
		var numeric_suffix := node_token.trim_prefix("node_")
		if numeric_suffix.is_valid_int() and numeric_suffix.to_int() > 0:
			slot_index = numeric_suffix.to_int() - 1
	var occupied_positions: Array = _embedded_origin_positions.values()
	var candidate := _embedded_grid_position(slot_index)
	while occupied_positions.has(candidate):
		slot_index += 1
		candidate = _embedded_grid_position(slot_index)
	return candidate


func _embedded_grid_position(slot_index: int) -> Vector2:
	return Vector2(
		float(slot_index % EMBEDDED_GRID_COLUMNS) * EMBEDDED_GRID_STEP.x,
		float(floori(float(slot_index) / float(EMBEDDED_GRID_COLUMNS))) * EMBEDDED_GRID_STEP.y)


func _queue_node_drag(node_id: StringName, from: Vector2, to: Vector2) -> void:
	if from.is_equal_approx(to):
		return
	if _pending_node_drags.has(node_id):
		_pending_node_drags[node_id]["to"] = to
		return
	_pending_node_drags[node_id] = {"from": from, "to": to}
	call_deferred("_commit_node_drag", node_id)


func _commit_node_drag(node_id: StringName) -> void:
	if not _pending_node_drags.has(node_id):
		return
	var pending: Dictionary = _pending_node_drags[node_id]
	_pending_node_drags.erase(node_id)
	var from: Vector2 = pending.get("from", Vector2.ZERO)
	var to: Vector2 = pending.get("to", from)
	var released_anchor: Vector2 = _released_task_anchor_for_drag(node_id, from, to)
	var visible_target: Vector2 = _embedded_drag_grid_position(from, to)
	if _embedded_compact_layout_enabled:
		_pending_embedded_drag_positions[node_id] = visible_target
	var accepted: bool = request_pointer(GraphCommandRequest.new(GraphCommandRequest.Kind.MOVE, {
		"node_id": node_id,
		"released_x": roundi(released_anchor.x),
		"released_y": roundi(released_anchor.y),
	}))
	if not accepted:
		_pending_embedded_drag_positions.erase(node_id)
		var graph_node := graph_edit.get_node_or_null(NodePath(node_id)) as GraphNode
		if graph_node != null:
			graph_node.position_offset = from


## Maps compact canvas deltas to one Task grid step per visible compact-grid step.
func _released_task_anchor_for_drag(node_id: StringName, from: Vector2, to: Vector2) -> Vector2:
	if not _embedded_compact_layout_enabled:
		var accepted_anchor: Vector2 = _projection_accepted_anchors.get(node_id, from)
		return accepted_anchor + to - from
	var accepted_anchor: Vector2 = _projection_accepted_anchors.get(node_id, from)
	var compact_delta: Vector2 = _embedded_drag_grid_position(Vector2.ZERO, to - from)
	return Vector2(
		accepted_anchor.x + compact_delta.x / EMBEDDED_GRID_STEP.x * float(TASK_GRID_STEP),
		accepted_anchor.y + compact_delta.y / EMBEDDED_GRID_STEP.y * float(TASK_GRID_STEP))


func _embedded_drag_grid_position(from: Vector2, to: Vector2) -> Vector2:
	if not _embedded_compact_layout_enabled:
		return to
	var delta: Vector2 = to - from
	return from + Vector2(
		float(roundi(delta.x / EMBEDDED_GRID_STEP.x)) * EMBEDDED_GRID_STEP.x,
		float(roundi(delta.y / EMBEDDED_GRID_STEP.y)) * EMBEDDED_GRID_STEP.y)


## Keeps an owner-accepted compact drop at its visible canvas location after rebuild.
func _retain_accepted_embedded_drag_position(command: GraphCommandRequest) -> void:
	if command == null or command.kind != GraphCommandRequest.Kind.MOVE:
		return
	var node_id: StringName = StringName(command.payload.get("node_id", ""))
	if not _pending_embedded_drag_positions.has(node_id):
		return
	var visible_position: Vector2 = _pending_embedded_drag_positions.get(node_id, Vector2.ZERO)
	_pending_embedded_drag_positions.erase(node_id)
	for raw_node: Variant in _accepted_snapshot.get("nodes", []):
		if typeof(raw_node) != TYPE_DICTIONARY:
			continue
		var node_data: Dictionary = Dictionary(raw_node)
		if StringName(node_data.get("node_id", "")) != node_id:
			continue
		var anchor: Dictionary = Dictionary(node_data.get("anchor", {}))
		_embedded_origin_anchors[node_id] = Vector2(
			float(anchor.get("x", node_data.get("anchor_x", 0))),
			float(anchor.get("y", node_data.get("anchor_y", 0))))
		_embedded_origin_positions[node_id] = visible_position
		return


func _reset_embedded_projection_origins() -> void:
	_embedded_origin_anchors.clear()
	_embedded_origin_positions.clear()


func _port_descriptors_for_projection(node_data: Dictionary) -> Array[PortDescriptor]:
	if _session != null:
		return _session.port_descriptors_for(node_data)
	return SessionPort.new().port_descriptors_for(node_data)


func _add_port_projection(
	graph_node: GraphNode, node_id: StringName, descriptors: Array[PortDescriptor]
) -> void:
	var inputs: Array[PortDescriptor] = []
	var outputs: Array[PortDescriptor] = []
	for descriptor: PortDescriptor in descriptors:
		if descriptor.direction == &"input":
			inputs.append(descriptor)
		elif descriptor.direction == &"output":
			outputs.append(descriptor)
	inputs.sort_custom(func(first: PortDescriptor, second: PortDescriptor) -> bool: return first.ordinal < second.ordinal)
	outputs.sort_custom(func(first: PortDescriptor, second: PortDescriptor) -> bool: return first.ordinal < second.ordinal)
	for input_index: int in range(inputs.size()):
		_record_port_ordinal(node_id, inputs[input_index], input_index)
	for output_index: int in range(outputs.size()):
		_record_port_ordinal(node_id, outputs[output_index], output_index)
	if inputs.is_empty() and outputs.is_empty():
		_add_port_row(graph_node, node_id, null, null)
		return
	for row_index: int in range(maxi(inputs.size(), outputs.size())):
		var input: PortDescriptor = inputs[row_index] if row_index < inputs.size() else null
		var output: PortDescriptor = outputs[row_index] if row_index < outputs.size() else null
		_add_port_row(graph_node, node_id, input, output)


func _add_port_row(
	graph_node: GraphNode, node_id: StringName,
	input: PortDescriptor, output: PortDescriptor
) -> void:
	var row: int = graph_node.get_child_count()
	var port_row := HBoxContainer.new()
	port_row.custom_minimum_size.y = 22.0
	port_row.add_theme_constant_override(&"separation", 6)
	port_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var input_label := Label.new()
	input_label.text = _port_description(input)
	input_label.tooltip_text = tr("Typed ports: text, icon, and shape identify their direction and meaning.")
	input_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_label.clip_text = true
	input_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	input_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if input != null:
		port_row.add_child(_new_port_token(node_id, input))
	port_row.add_child(input_label)
	var output_label := Label.new()
	output_label.text = _port_description(output)
	output_label.tooltip_text = input_label.tooltip_text
	output_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	output_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output_label.clip_text = true
	output_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	output_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	port_row.add_child(output_label)
	if output != null:
		port_row.add_child(_new_port_token(node_id, output))
	graph_node.add_child(port_row)
	graph_node.set_slot(
		row,
		input != null, _graph_port_type(input), Color("e7a84b"),
		output != null, _graph_port_type(output), Color("e7a84b"))


## Renders a player-readable accepted node detail without exposing graph IDs.
func _add_variant_detail_label(graph_node: GraphNode, category: String, variant: String) -> void:
	var detail_label := Label.new()
	detail_label.name = &"VariantDetail"
	detail_label.text = _player_readable_variant_label(category, variant)
	detail_label.tooltip_text = detail_label.text
	detail_label.custom_minimum_size.y = 18.0
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.clip_text = true
	detail_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	graph_node.add_child(detail_label)


## Converts the accepted variant token into display copy; it never displays node IDs.
func _player_readable_variant_label(category: String, variant: String) -> String:
	var display_token := variant
	var category_prefix := "%s." % category.to_lower()
	if display_token.to_lower().begins_with(category_prefix):
		display_token = display_token.substr(category_prefix.length())
	display_token = display_token.replace(".", " ").replace("_", " ").strip_edges()
	if display_token.is_empty():
		return tr("Configured node")
	return tr(display_token.capitalize())


func _cache_token_atlases() -> void:
	_category_token_atlas = _load_runtime_image_texture(CATEGORY_TOKEN_ASSET_PATH)
	_port_token_atlas = _load_runtime_image_texture(PORT_TOKEN_ASSET_PATH)


func _load_runtime_image_texture(asset_path: String) -> ImageTexture:
	var image := Image.load_from_file(ProjectSettings.globalize_path(asset_path))
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


func _add_category_token(graph_node: GraphNode, category: StringName) -> void:
	var region := _category_token_region(category)
	if not region.has_area():
		return
	var token := _new_atlas_token(
		_category_token_atlas, CATEGORY_TOKEN_ASSET_PATH, region, Vector2(24, 24))
	token.name = &"CategoryToken"
	graph_node.get_titlebar_hbox().add_child(token)


func _new_port_token(node_id: StringName, descriptor: PortDescriptor) -> Control:
	var host := Control.new()
	host.name = "PortToken_%s_%s" % [descriptor.direction, descriptor.port_id]
	host.custom_minimum_size = Vector2(20, 20)
	host.size = Vector2(20, 20)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var token: TextureRect = _new_atlas_token(
		_port_token_atlas, PORT_TOKEN_ASSET_PATH,
		_port_token_region(descriptor), Vector2(16, 16))
	token.position = Vector2(2, 2)
	host.add_child(token)
	var target := Button.new()
	target.name = &"PortTarget"
	target.flat = true
	target.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	target.focus_mode = Control.FOCUS_ALL
	target.mouse_filter = Control.MOUSE_FILTER_STOP
	target.z_index = 1
	target.tooltip_text = tr("Select %s port %s for a connection.") % [descriptor.direction, descriptor.port_id]
	target.pressed.connect(_on_port_token_pressed.bind(node_id, descriptor))
	host.add_child(target)
	return host


func _on_port_token_pressed(node_id: StringName, descriptor: PortDescriptor) -> void:
	if descriptor.direction == &"output":
		_pending_port_source = {"node_id": node_id, "port_id": descriptor.port_id}
		status_label.text = tr("Connection source selected. Choose a compatible input port.")
		return
	if descriptor.direction != &"input":
		_show_rejection(
			&"connection_selection_required",
			tr("Choose an output port before an input port."))
		return
	if _pending_port_source.is_empty():
		if _select_connection_at_input(node_id, descriptor.port_id):
			return
		_show_rejection(
			&"connection_selection_required",
			tr("Choose an output port before an unconnected input port."))
		return
	var source: Dictionary = _pending_port_source.duplicate()
	_pending_port_source = {}
	request_pointer(GraphCommandRequest.new(GraphCommandRequest.Kind.CONNECT, {
		"output_node_id": source.get("node_id", &""),
		"output_port_id": source.get("port_id", &""),
		"input_node_id": node_id,
		"input_port_id": descriptor.port_id,
	}))


## Makes the GDD's occupied-input disconnect route reachable without requiring
## a player to hit a thin, overlapping wire in the compact embedded canvas.
func _select_connection_at_input(node_id: StringName, port_id: StringName) -> bool:
	for raw_connection: Variant in Array(_accepted_snapshot.get("connections", [])):
		if typeof(raw_connection) != TYPE_DICTIONARY:
			continue
		var connection: Dictionary = raw_connection
		var input_node_id := StringName(connection.get(
			"input_node_id", connection.get("target_node_id", "")))
		var input_port_id := StringName(connection.get(
			"input_port_id", connection.get("target_port_id", "")))
		if input_node_id != node_id or input_port_id != port_id:
			continue
		var output_node_id := StringName(connection.get(
			"output_node_id", connection.get("source_node_id", "")))
		var output_port_id := StringName(connection.get(
			"output_port_id", connection.get("source_port_id", "")))
		if output_node_id.is_empty() or output_port_id.is_empty():
			continue
		_pending_port_source = {}
		_selected_connection_payload = {
			"output_node_id": output_node_id,
			"output_port_id": output_port_id,
			"input_node_id": input_node_id,
			"input_port_id": input_port_id,
		}
		graph_edit.grab_focus()
		status_label.text = tr("Selected connection. Disconnect is ready.")
		return true
	return false


func _new_atlas_token(
	base_atlas: ImageTexture, asset_path: String, region: Rect2, token_size: Vector2
) -> TextureRect:
	var token := TextureRect.new()
	token.custom_minimum_size = token_size
	token.size = token_size
	token.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	token.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	token.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	token.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	token.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if base_atlas == null:
		return token
	var atlas := AtlasTexture.new()
	atlas.atlas = base_atlas
	atlas.region = region
	atlas.set_meta(&"asset_path", asset_path)
	token.texture = atlas
	return token


func _category_token_region(category: StringName) -> Rect2:
	match category:
		&"Start": return Rect2(2, 2, 24, 24)
		&"Action": return Rect2(30, 2, 24, 24)
		&"Query": return Rect2(58, 2, 24, 24)
		&"Constant": return Rect2(86, 2, 24, 24)
		&"Compare": return Rect2(2, 30, 24, 24)
		&"Branch": return Rect2(30, 30, 24, 24)
		&"Repeat": return Rect2(58, 30, 24, 24)
		&"End": return Rect2(86, 30, 24, 24)
		_: return Rect2()


func _port_token_region(descriptor: PortDescriptor) -> Rect2:
	if descriptor.kind == &"execution":
		return Rect2(2, 2, 16, 16)
	match descriptor.value_type:
		&"boolean": return Rect2(22, 2, 16, 16)
		&"numeric": return Rect2(42, 2, 16, 16)
		_: return Rect2(62, 2, 16, 16)


func _record_port_ordinal(
	node_id: StringName, descriptor: PortDescriptor, projected_ordinal: int
) -> void:
	if not _port_ordinals.has(node_id):
		_port_ordinals[node_id] = {
			&"input": {&"ids": {}, &"ordinals": {}},
			&"output": {&"ids": {}, &"ordinals": {}},
		}
	var directions: Dictionary = _port_ordinals[node_id]
	var direction_map: Dictionary = directions[descriptor.direction]
	var port_ids: Dictionary = direction_map[&"ids"]
	var ordinals: Dictionary = direction_map[&"ordinals"]
	port_ids[str(descriptor.port_id)] = projected_ordinal
	ordinals[projected_ordinal] = descriptor.port_id


func _projected_port_ordinal(node_id: StringName, direction: StringName, port_id: Variant) -> int:
	var directions: Dictionary = _port_ordinals.get(node_id, {})
	var direction_map: Dictionary = directions.get(direction, {})
	var port_ids: Dictionary = direction_map.get(&"ids", {})
	if port_ids.has(str(port_id)):
		return int(port_ids[str(port_id)])
	return int(port_id) if typeof(port_id) == TYPE_INT else 0


func _stable_port_id(node_id: StringName, direction: StringName, ordinal: int) -> StringName:
	var directions: Dictionary = _port_ordinals.get(node_id, {})
	var direction_map: Dictionary = directions.get(direction, {})
	var ordinals: Dictionary = direction_map.get(&"ordinals", {})
	return StringName(ordinals.get(ordinal, ""))


func _graph_port_type(descriptor: PortDescriptor) -> int:
	return EXECUTION_PORT if descriptor != null and descriptor.kind == &"execution" else DATA_PORT


func _port_description(descriptor: PortDescriptor) -> String:
	if descriptor == null:
		return ""
	var direction_text: String = tr("IN") if descriptor.direction == &"input" else tr("OUT")
	var shape_icon: String = "▶" if descriptor.kind == &"execution" else _data_shape_icon(descriptor.value_type)
	return "%s · %s · %s" % [direction_text, shape_icon, tr(descriptor.label)]


func _port_type_text(descriptor: PortDescriptor) -> String:
	if descriptor.kind == &"execution":
		return tr("Execution")
	match descriptor.value_type:
		&"boolean": return tr("Boolean")
		&"numeric": return tr("Numeric")
		&"label": return tr("Label")
		_: return tr("Data")


func _data_shape_icon(value_type: StringName) -> String:
	match value_type:
		&"boolean": return "◆"
		&"numeric": return "#"
		&"label": return "▱"
		_: return "●"


func _select_node(node_id: StringName) -> void:
	_selected_node_id = node_id
	_applying_projection_selection = true
	for child: Node in graph_edit.get_children():
		if child is GraphNode:
			(child as GraphNode).selected = child.name == node_id
	_applying_projection_selection = false
	status_label.text = tr("Selected node: %s") % node_id
	_update_view_label()


## Returns whether the accepted snapshot contains the requested node identity.
func has_accepted_node(node_id: StringName) -> bool:
	if node_id.is_empty():
		return false
	for raw_node: Variant in Array(_accepted_snapshot.get("nodes", [])):
		if typeof(raw_node) == TYPE_DICTIONARY \
				and StringName(Dictionary(raw_node).get("node_id", "")) == node_id:
			return true
	return false


## Focuses an existing accepted GraphEdit node without issuing an owner request
## or changing graph truth. Used only by presentation Locate affordances.
func focus_accepted_node(node_id: StringName) -> bool:
	if not has_accepted_node(node_id):
		return false
	var node := graph_edit.get_node_or_null(NodePath(String(node_id))) as GraphNode
	if node == null or not node.is_visible_in_tree():
		return false
	_selected_node_id = node_id
	_applying_projection_selection = true
	for child: Node in graph_edit.get_children():
		if child is GraphNode:
			(child as GraphNode).selected = child.name == node_id
	_applying_projection_selection = false
	node.set_focus_mode(Control.FOCUS_ALL)
	node.set_focus_behavior_recursive(Control.FOCUS_BEHAVIOR_ENABLED)
	node.grab_focus()
	status_label.text = tr("Located the affected node.")
	_update_view_label()
	return true


func _frame_all() -> void:
	if not is_node_ready():
		return
	var rectangles: Array[Rect2] = []
	for child: Node in graph_edit.get_children():
		if child is GraphNode:
			var graph_node: GraphNode = child
			graph_node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			graph_node.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			rectangles.append(Rect2(graph_node.position_offset, graph_node.size))
	_last_frame = calculate_frame_all(graph_edit.size, rectangles)
	graph_edit.zoom = DEFAULT_ZOOM if _embedded_compact_layout_enabled else float(_last_frame["zoom"])
	# Embedded projection positions are a bounded local grid. Keeping the canvas
	# origin at the interaction rect avoids translating visible nodes beyond the
	# GraphEdit hit region after the host's two-pane resize.
	graph_edit.scroll_offset = Vector2.ZERO if _embedded_compact_layout_enabled \
		else Vector2(_last_frame["center"]) - graph_edit.size / (2.0 * graph_edit.zoom)
	_update_view_label()
	if _session != null:
		_session.record_view_request(&"frame_all")


func _increase_zoom() -> void:
	graph_edit.zoom = DEFAULT_ZOOM if _embedded_compact_layout_enabled else minf(DEFAULT_ZOOM, graph_edit.zoom + 0.1)
	_update_view_label()
	if _session != null:
		_session.record_view_request(&"zoom_in")


func _decrease_zoom() -> void:
	graph_edit.zoom = DEFAULT_ZOOM if _embedded_compact_layout_enabled else maxf(MIN_READABLE_ZOOM, graph_edit.zoom - 0.1)
	_update_view_label()
	if _session != null:
		_session.record_view_request(&"zoom_out")


func _move_selected_with_key(keycode: Key) -> void:
	if _selected_node_id.is_empty():
		return
	var anchor: Dictionary = _selected_anchor()
	var delta := Vector2i.ZERO
	if keycode == KEY_LEFT:
		delta.x = -16
	elif keycode == KEY_RIGHT:
		delta.x = 16
	elif keycode == KEY_UP:
		delta.y = -16
	else:
		delta.y = 16
	request_keyboard(GraphCommandRequest.new(GraphCommandRequest.Kind.MOVE, {
		"node_id": _selected_node_id,
		"released_x": int(anchor.get("x", 0)) + delta.x,
		"released_y": int(anchor.get("y", 0)) + delta.y,
	}))


func _move_selected_pointer_right() -> void:
	if _selected_node_id.is_empty():
		return
	var anchor: Dictionary = _selected_anchor()
	request_pointer(GraphCommandRequest.new(GraphCommandRequest.Kind.MOVE, {
		"node_id": _selected_node_id,
		"released_x": int(anchor.get("x", 0)) + 16,
		"released_y": int(anchor.get("y", 0)),
	}))


func _selected_anchor() -> Dictionary:
	for raw_node: Variant in _accepted_snapshot.get("nodes", []):
		var node: Dictionary = raw_node
		if StringName(node.get("node_id", "")) == _selected_node_id:
			return Dictionary(node.get("anchor", {"x": node.get("anchor_x", 0), "y": node.get("anchor_y", 0)}))
	return {"x": 0, "y": 0}


func _cycle_overlap() -> void:
	var node_ids: Array[StringName] = []
	for child: Node in graph_edit.get_children():
		if child is GraphNode:
			node_ids.append(child.name)
	node_ids.sort()
	if node_ids.is_empty():
		return
	var selected_index: int = node_ids.find(_selected_node_id)
	_select_node(node_ids[(selected_index + 1) % node_ids.size()])
	if _session != null:
		_session.record_view_request(&"cycle_overlap")


func _render_report(report: Dictionary) -> void:
	if not is_node_ready():
		return
	if report.is_empty():
		report_label.text = tr("Report: none. Run a public case to inspect its frozen trace.")
		return
	var freshness: String = tr("OUT OF DATE — still readable") if _session.report_is_out_of_date() else tr("Current")
	report_label.text = "%s\n%s\n%s" % [
		tr("Report: %s") % freshness,
		tr("Outcome: %s") % _display_value(report.get("outcome", "unknown")),
		tr("Trace: %s") % _display_value(report.get("trace", "No trace details returned.")),
	]
	_update_view_label()


func _display_value(value: Variant) -> String:
	return JSON.stringify(value) if typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_DICTIONARY else str(value)


func _set_reset_confirmation(is_open: bool) -> void:
	if not is_node_ready():
		return
	var was_open: bool = reset_confirmation.visible
	reset_confirmation.visible = is_open
	if is_open:
		call_deferred("_focus_reset_cancel")
	elif was_open:
		call_deferred("_restore_focus_after_reset")
	_update_view_label()


func _request_reset(invoker: Control, from_keyboard: bool = false) -> void:
	_reset_invoker = invoker
	var command := GraphCommandRequest.new(GraphCommandRequest.Kind.RESET)
	if from_keyboard:
		request_keyboard(command)
	else:
		request_pointer(command)


func _keyboard_reset_invoker() -> Control:
	var focused: Control = get_viewport().gui_get_focus_owner()
	return focused if focused != null else reset_button


func _focus_reset_cancel() -> void:
	if reset_confirmation.visible and reset_cancel_button.visible:
		reset_cancel_button.grab_focus()


func _restore_focus_after_reset() -> void:
	var invoker: Control = _reset_invoker
	_reset_invoker = null
	if _is_focusable_visible(invoker):
		invoker.grab_focus()
		return
	var fallback: Control = _stable_top_level_focus_fallback()
	if fallback != null:
		fallback.grab_focus()
	elif _is_focusable_visible(graph_edit):
		graph_edit.grab_focus()


func _stable_top_level_focus_fallback() -> Control:
	for candidate: Control in [palette_option, create_button, configure_button, connect_button]:
		if _is_focusable_visible(candidate):
			return candidate
	return null


func _is_focusable_visible(control: Control) -> bool:
	return control != null and is_instance_valid(control) and control.is_visible_in_tree() \
		and control.focus_mode != Control.FOCUS_NONE


func _update_view_label() -> void:
	if not is_node_ready():
		return
	view_label.text = tr("Nodes: %d   Zoom: %d%%   State: %s") % [
		_accepted_snapshot.get("nodes", []).size(), roundi(graph_edit.zoom * 100.0),
		tr("Connecting") if not _pending_connection_source_id.is_empty() else tr("Editable"),
	]


func _show_rejection(code: StringName, message: String) -> void:
	if is_node_ready():
		status_label.text = "%s: %s" % [code, message]


func _configure_copy() -> void:
	title_label.text = tr("Graph Authoring — accessible player loop")
	help_label.text = tr(
		"Create and edit nodes, inspect text feedback, then rerun. Keyboard: arrows move, Ctrl+. cycles overlaps, F5 runs, Home frames.")
	palette_option.clear()
	palette_option.tooltip_text = tr("Choose a coursework node category.")
	for category: StringName in [&"Start", &"Action", &"Query", &"Constant", &"Compare", &"Branch", &"Repeat", &"End"]:
		palette_option.add_item(category)
	create_button.text = tr("Create selected node")
	configure_button.text = tr("Configure selected node")
	connect_button.text = tr("Connect selected nodes")
	disconnect_button.text = tr("Disconnect selected")
	delete_button.text = tr("Delete selected")
	undo_button.text = tr("Undo")
	redo_button.text = tr("Redo")
	move_button.text = tr("Move selected right")
	zoom_in_button.text = tr("Zoom in")
	zoom_out_button.text = tr("Zoom out")
	cycle_button.text = tr("Cycle overlap")
	frame_all_button.text = tr("Frame All (Home)")
	reset_button.text = tr("Reset graph")
	more_button.text = tr("Actions")
	auto_solve_button.text = tr("AUTO SOLVE")
	auto_solve_button.tooltip_text = tr("Restore this Task and apply its admitted witness edits")
	reset_prompt.text = tr("Reset confirmation: Cancel is focused first.")
	reset_cancel_button.text = tr("Cancel reset")
	reset_confirm_button.text = tr("Confirm reset")
	run_button.text = tr("Run") if _embedded_compact_layout_enabled else tr("Run public case")
	run_all_button.text = tr("Run all public") if _embedded_compact_layout_enabled else tr("Run all public cases")
	report_heading.text = tr("Frozen report and trace")
	status_label.text = tr("Ready. Use pointer or keyboard routes; errors appear here as text.")
	_update_view_label()
