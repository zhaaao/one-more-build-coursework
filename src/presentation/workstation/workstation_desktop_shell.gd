## Presentation-only entry shell for the Company Workstation desktop.
##
## This scene owns local visual substate and focus only. It does not retain a
## session, invoke a domain port, or issue owner commands.
class_name WorkstationDesktopShell
extends Control


const CourseworkRunResultType = preload("res://src/core/gvet/coursework_run_result.gd")
const SandboxCaseStateType = preload("res://src/core/sandbox/sandbox_case_state.gd")
const SandboxVisualProjectionScene = preload("res://src/presentation/sandbox/SandboxVisualProjection.tscn")
const WALLPAPER_ASSET_PATH := "res://assets/art/ui_desktop_wallpaper_day1_640x360.png"
const EDITOR_WINDOW_ASSET_PATH := "res://assets/art/ui_editor_window_day1_1024x576.png"
const SKIN_ASSET_PATH := "res://assets/art/ui_coursework_skin_default_256.png"
const ACTIONS_ASSET_PATH := "res://assets/art/ui_action_icons_coursework_256.png"
const STATUS_ASSET_PATH := "res://assets/art/ui_status_markers_default_256.png"
const TRACE_MARKER_ASSET_PATH := "res://assets/art/ui_graph_ports_trace_256.png"
const SILKSCREEN_REGULAR_ASSET_PATH := "res://assets/fonts/Silkscreen-Regular.ttf"
const SILKSCREEN_BOLD_ASSET_PATH := "res://assets/fonts/Silkscreen-Bold.ttf"


const WORKSTATION_VIEW: StringName = &"workstation_view"
const DESKTOP: StringName = &"desktop"
const EDITOR_APP: StringName = &"editor_app"
const ONE_PANE: StringName = &"one_pane"
const TWO_PANE: StringName = &"two_pane"
const THREE_PANE: StringName = &"three_pane"
const EDITOR_STATUS_BAND_BOTTOM: float = -78.0
const ONE_PANE_STATUS_BAND_BOTTOM: float = -62.0
const PAPER: Color = Color(0.91, 0.95, 0.9, 1.0)
const SLATE: Color = Color(0.14, 0.19, 0.25, 1.0)
const SIGNAL_CYAN: Color = Color(0.28, 0.83, 0.86, 1.0)
const EVIDENCE_AMBER: Color = Color(0.98, 0.75, 0.32, 1.0)
const FAULT_CORAL: Color = Color(0.95, 0.38, 0.39, 1.0)
const PASS_GREEN: Color = Color(0.42, 0.82, 0.49, 1.0)
const WORKSTATION_COMPOSITION_SIZE := Vector2(1024.0, 1024.0)
const MONITOR_APERTURE_LOCAL_POSITION := Vector2(204.0, 78.0)
const COMPUTER_TARGET_LOCAL_POSITION := Vector2(160.0, 28.0)
const EDITOR_HEADER_BAND_TOP := 8.0
const EDITOR_BACK_SIZE := Vector2(232.0, 32.0)
const INSPECT_CLOSE_SIZE := Vector2(100.0, 44.0)
const SAVE_HEADER_SIZE := Vector2(96.0, 44.0)
const SAVE_OVERLAY_PANEL_SIZE := Vector2(668.0, 466.0)
const SAVE_OVERLAY_SAFE_MARGIN := 16.0
const SAVE_SLOT_IDS: Array[StringName] = [&"manual.1", &"manual.2", &"manual.3", &"autosave.1"]
const MANUAL_SAVE_SLOT_IDS: Array[StringName] = [&"manual.1", &"manual.2", &"manual.3"]


class EditorGraphRequest extends RefCounted:
	var request_id: int
	var command_id: StringName
	var command: GraphAuthoringPanel.GraphCommandRequest
	var from_node: StringName
	var from_port: int
	var to_node: StringName
	var to_port: int


## Presentation-owned request envelope. The opaque owner token is carried only
## after a destructive operation has been explicitly confirmed by the player.
class SaveRecoveryRequest extends RefCounted:
	var request_id: int
	var operation: StringName
	var slot_id: StringName
	var confirmation_token: Variant


## Presentation request envelope for the existing Workday delivery owner.
class DeliveryRequest extends RefCounted:
	var request_id: int
	var risk_warning_confirmed: bool = false


signal graph_edit_requested(request: EditorGraphRequest)
signal save_recovery_requested(request: SaveRecoveryRequest)
signal delivery_requested(request: DeliveryRequest)
signal startup_load_closed

@onready var _workstation_view: Control = get_node("WorkstationView") as Control
@onready var _environment_far: TextureRect = get_node("WorkstationView/EnvironmentFar") as TextureRect
@onready var _environment_mid: TextureRect = get_node("WorkstationView/EnvironmentMid") as TextureRect
@onready var _environment_near: TextureRect = get_node("WorkstationView/EnvironmentNear") as TextureRect
@onready var _monitor_aperture: Control = get_node("WorkstationView/MonitorAperture") as Control
@onready var _desktop_view: Control = get_node("DesktopView") as Control
@onready var _computer_target: Button = get_node("WorkstationView/ComputerTarget") as Button
@onready var _desktop_back: Button = get_node("DesktopView/DesktopBack") as Button
@onready var _editor_icon: Button = get_node("DesktopView/EditorIcon") as Button
@onready var _desktop_background: ColorRect = get_node("DesktopView/DesktopBackground") as ColorRect
@onready var _desktop_wallpaper: TextureRect = get_node("DesktopView/DesktopWallpaper") as TextureRect
@onready var _workstation_title: Label = get_node("WorkstationView/WorkstationTitle") as Label
@onready var _computer_prompt: Label = get_node("WorkstationView/ComputerTarget/ComputerPrompt") as Label
@onready var _preview_icon_mark: Label = get_node("WorkstationView/ComputerTarget/MonitorFrame/MonitorScreen/PreviewIconMark") as Label
@onready var _preview_icon_label: Label = get_node("WorkstationView/ComputerTarget/MonitorFrame/MonitorScreen/PreviewIconLabel") as Label
@onready var _preview_editor_label: Label = get_node("WorkstationView/MonitorAperture/PreviewEditorLabel") as Label
@onready var _desktop_title: Label = get_node("DesktopView/DesktopTitle") as Label
@onready var _icon_text: Label = get_node("DesktopView/EditorIcon/IconText") as Label
@onready var _pixel_screen: TextureRect = get_node("DesktopView/EditorIcon/PixelScreen") as TextureRect
@onready var _desktop_hint: Label = get_node("DesktopView/DesktopHint") as Label
@onready var _desktop_status: Label = get_node("DesktopView/DesktopStatus") as Label
@onready var _editor_app: Control = get_node("EditorApp") as Control
@onready var _native_window_frame: TextureRect = get_node("EditorApp/NativeWindowFrame") as TextureRect
@onready var _editor_header_row: HBoxContainer = get_node("EditorApp/HeaderBand/HeaderRow") as HBoxContainer
@onready var _editor_back: Button = get_node("EditorApp/HeaderBand/HeaderRow/EditorBack") as Button
@onready var _graph_pane: Control = get_node("EditorApp/GraphPane") as Control
@onready var _authoring_panel: GraphAuthoringPanel = get_node("EditorApp/GraphPane/GraphAuthoringPanel") as GraphAuthoringPanel
@onready var _editor_graph: GraphEdit = get_node("EditorApp/GraphPane/GraphAuthoringPanel/Panel/Layout/Workspace/GraphEdit") as GraphEdit
@onready var _graph_primary_action: Button = get_node("EditorApp/GraphPane/GraphPrimaryAction") as Button
@onready var _requirements_pane: Control = get_node("EditorApp/RequirementsPane") as Control
@onready var _results_pane: Control = get_node("EditorApp/ResultsPane") as Control
@onready var _inspect_pane: Control = get_node("EditorApp/InspectPane") as Control
@onready var _view_tabs: OptionButton = get_node("EditorApp/ViewTabs") as OptionButton
@onready var _editor_status: Label = get_node("EditorApp/EditorStatus") as Label
@onready var _results_layout: VBoxContainer = get_node("EditorApp/ResultsPane/ResultsLayout") as VBoxContainer
@onready var _results_heading: Label = get_node("EditorApp/ResultsPane/ResultsLayout/ResultsHeading") as Label
@onready var _workspace_heading: Label = get_node("EditorApp/HeaderBand/HeaderRow/WorkspaceHeading") as Label
@onready var _graph_heading: Label = get_node("EditorApp/GraphPane/GraphHeading") as Label
@onready var _requirements_heading: Label = get_node("EditorApp/RequirementsPane/RequirementsHeading") as Label
@onready var _requirements_scroll: ScrollContainer = get_node("EditorApp/RequirementsPane/RequirementsScroll") as ScrollContainer
@onready var _requirements_copy: Label = get_node("EditorApp/RequirementsPane/RequirementsScroll/RequirementsCopy") as Label
@onready var _results_message_scroll: ScrollContainer = get_node("EditorApp/ResultsPane/ResultsLayout/ResultsBody/ResultsMessageScroll") as ScrollContainer
@onready var _results_copy: Label = get_node("EditorApp/ResultsPane/ResultsLayout/ResultsBody/ResultsMessageScroll/ResultsCopy") as Label
@onready var _results_cards_scroll: ScrollContainer = get_node("EditorApp/ResultsPane/ResultsLayout/ResultsBody/ResultsCardsScroll") as ScrollContainer
@onready var _results_cards: VBoxContainer = get_node("EditorApp/ResultsPane/ResultsLayout/ResultsBody/ResultsCardsScroll/ResultsCards") as VBoxContainer
@onready var _result_case_select: OptionButton = get_node("EditorApp/ResultsPane/ResultsLayout/ResultsFooter/ResultCaseSelect") as OptionButton
@onready var _inspect_button: Button = get_node("EditorApp/ResultsPane/ResultsLayout/ResultsFooter/InspectButton") as Button
@onready var _inspect_heading: Label = get_node("EditorApp/InspectPane/InspectHeading") as Label
@onready var _inspect_copy: Label = get_node("EditorApp/InspectPane/InspectCopy") as Label
@onready var _inspect_rail_scroll: ScrollContainer = get_node("EditorApp/InspectPane/InspectRail") as ScrollContainer
@onready var _inspect_rail: VBoxContainer = get_node("EditorApp/InspectPane/InspectRail/Rows") as VBoxContainer
@onready var _inspect_close: Button = get_node("EditorApp/InspectPane/InspectClose") as Button
@onready var _sandbox_inspect_host: Control = get_node("EditorApp/InspectPane/SandboxInspectHost") as Control
@onready var _sandbox_frame: Panel = get_node("EditorApp/InspectPane/SandboxFrame") as Panel
@onready var _sandbox_frame_title: Label = get_node("EditorApp/InspectPane/SandboxFrame/SandboxFrameTitle") as Label
@onready var _sandbox_legend: Label = get_node("EditorApp/InspectPane/SandboxFrame/SandboxLegend") as Label

var _substate: StringName = WORKSTATION_VIEW
var _pane_mode: StringName = THREE_PANE
var _next_graph_request_id: int = 1
var _pending_graph_request_id: int = 0
var _accepted_graph_projection: String = "No accepted graph changes."
var _last_editor_focus: Control
var _editor_failed: bool = false
var _completed_report: CourseworkRunResult
var _completed_report_is_out_of_date: bool = false
var _accepted_sandbox_by_case: Dictionary[String, SandboxCaseState] = {}
var _selected_result_index: int = -1
var _inspect_origin: Control
var _sandbox_inspect_projection: Control
var _sandbox_inspect_projection_factory: Callable
var _graph_run_action: Button
var _delivery_action: Button
var _next_delivery_request_id: int = 1
var _pixel_skin_atlas: Texture2D
var _action_icon_atlas: Texture2D
var _status_marker_atlas: Texture2D
var _trace_marker_atlas: Texture2D
var _silkscreen_regular: FontFile
var _silkscreen_bold: FontFile
var _owner_request_counts: Dictionary[StringName, int] = {
	&"graph_edit": 0,
	&"run": 0,
	&"save": 0,
	&"help": 0,
	&"delivery": 0,
	&"sandbox": 0,
	&"telemetry": 0,
	&"persistence": 0,
	&"progression": 0,
}
var _next_save_recovery_request_id: int = 1
var _save_recovery_snapshot: Dictionary = {}
var _save_recovery_origin: Control
var _save_confirmation_origin: Control
var _save_overlay: Control
var _save_overlay_panel: PanelContainer
var _save_overlay_heading: Label
var _save_overlay_status: Label
var _save_overlay_slots: VBoxContainer
var _save_overlay_close: Button
var _save_header_action: Button
var _save_slot_actions: Dictionary[StringName, Dictionary] = {}
var _confirmation_overlay: Control
var _confirmation_copy: Label
var _confirmation_cancel: Button
var _confirmation_confirm: Button
var _pending_confirmation_operation: StringName = &""
var _pending_confirmation_slot_id: StringName = &""
var _pending_confirmation_token: Variant = null
var _interaction_busy: bool = false
var _busy_focus: Control = null
var _current_day_index: int = 1
var _current_task_title: String = "Assignment"
var _current_case_labels: Array[String] = []
var _startup_load_mode: bool = false
var _startup_load_scrim: ColorRect


func _ready() -> void:
	_load_pixel_assets()
	_create_graph_run_action()
	_create_delivery_action()
	_create_save_recovery_controls()
	_apply_silkscreen_theme()
	_set_player_text()
	_authoring_panel.enable_embedded_compact_layout()
	_authoring_panel.enable_embedded_admission()
	_authoring_panel.embedded_busy_state_changed.connect(_on_embedded_busy_state_changed)
	_authoring_panel.embedded_run_completed.connect(_on_embedded_run_completed)
	_graph_heading.hide()
	_graph_primary_action.hide()
	_graph_primary_action.disabled = true
	_graph_run_action.hide()
	_graph_run_action.disabled = true
	_apply_focus_styles()
	_apply_pixel_presentation_styles()
	_computer_target.pressed.connect(_on_computer_target_pressed)
	_desktop_back.pressed.connect(_on_desktop_back_pressed)
	_editor_icon.pressed.connect(_on_editor_icon_pressed)
	_editor_back.pressed.connect(_on_editor_back_pressed)
	_save_header_action.pressed.connect(_on_save_header_action_pressed)
	_graph_primary_action.pressed.connect(_on_graph_primary_action_pressed)
	_graph_run_action.pressed.connect(_on_graph_run_action_pressed)
	_delivery_action.pressed.connect(_on_delivery_action_pressed)
	_editor_graph.gui_input.connect(handle_editor_app_gui_input)
	_authoring_panel.embedded_command_requested.connect(_on_authoring_command_requested)
	_editor_app.gui_input.connect(handle_editor_app_gui_input)
	_view_tabs.item_selected.connect(_on_view_tab_selected)
	_result_case_select.item_selected.connect(_on_result_case_selected)
	_inspect_button.pressed.connect(_on_inspect_button_pressed)
	_inspect_close.pressed.connect(_on_inspect_close_pressed)
	_sandbox_inspect_host.resized.connect(_on_sandbox_inspect_host_resized)
	_desktop_background.gui_input.connect(handle_desktop_background_gui_input)
	_configure_focus_navigation()
	_view_tabs.clear()
	_view_tabs.add_item(tr("Graph"))
	_view_tabs.add_item(tr("Requirements"))
	_view_tabs.add_item(tr("Results"))
	_view_tabs.select(0)
	_apply_action_atlas_icons()
	_render_save_recovery_overlay()
	_render_completed_report()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_show_workstation_view()


func _configure_focus_navigation() -> void:
	_computer_target.focus_neighbor_bottom = _computer_target.get_path()
	_desktop_back.focus_next = _editor_icon.get_path()
	_desktop_back.focus_previous = _editor_icon.get_path()
	_desktop_back.focus_neighbor_bottom = _editor_icon.get_path()
	_desktop_back.focus_neighbor_top = _editor_icon.get_path()
	_editor_icon.focus_next = _desktop_back.get_path()
	_editor_icon.focus_previous = _desktop_back.get_path()
	_editor_icon.focus_neighbor_bottom = _desktop_back.get_path()
	_editor_icon.focus_neighbor_top = _desktop_back.get_path()
	_graph_run_action.focus_next = _graph_primary_action.get_path()
	_graph_run_action.focus_previous = _graph_primary_action.get_path()
	_graph_run_action.focus_neighbor_right = _graph_primary_action.get_path()
	_graph_primary_action.focus_previous = _graph_run_action.get_path()
	_graph_primary_action.focus_next = _result_case_select.get_path()
	_graph_primary_action.focus_neighbor_left = _graph_run_action.get_path()
	_result_case_select.focus_neighbor_bottom = _inspect_button.get_path()
	_result_case_select.focus_next = _inspect_button.get_path()
	_result_case_select.focus_previous = _graph_primary_action.get_path()
	_inspect_button.focus_neighbor_top = _result_case_select.get_path()
	_inspect_button.focus_neighbor_bottom = _editor_back.get_path()
	_inspect_button.focus_next = _editor_back.get_path()
	_inspect_button.focus_previous = _result_case_select.get_path()
	_inspect_close.focus_neighbor_top = _result_case_select.get_path()
	_inspect_close.focus_neighbor_bottom = _editor_back.get_path()
	_inspect_close.focus_next = _editor_back.get_path()
	_inspect_close.focus_previous = _result_case_select.get_path()
	_save_header_action.focus_next = _editor_back.get_path()
	_save_header_action.focus_previous = _editor_back.get_path()


func _unhandled_input(event: InputEvent) -> void:
	_handle_run_shortcut_input(event)


## Gives Main one narrow topmost-Back seam before it opens global Pause.
## Base Workstation/Desktop/Editor navigation remains on explicit controls.
func try_handle_back() -> bool:
	if not visible:
		return false
	if _confirmation_overlay != null and _confirmation_overlay.visible:
		_close_save_confirmation()
		return true
	if _save_overlay != null and _save_overlay.visible:
		_close_save_recovery_overlay()
		return true
	if _inspect_pane != null and _inspect_pane.visible:
		_close_inspect()
		return true
	if _substate == EDITOR_APP and _editor_confirmation_is_open():
		var authoring := _current_authoring_panel()
		if authoring != null:
			authoring.handle_embedded_escape()
		return true
	return false


func _input(event: InputEvent) -> void:
	if get_viewport().is_input_handled():
		return
	_handle_run_shortcut_input(event)


func _shortcut_input(event: InputEvent) -> void:
	_handle_run_shortcut_input(event)


func _handle_run_shortcut_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.keycode != KEY_F5 or not key_event.pressed or key_event.echo:
		return
	if (_save_overlay != null and _save_overlay.visible) \
		or (_confirmation_overlay != null and _confirmation_overlay.visible):
		get_viewport().set_input_as_handled()
		return
	if _substate != EDITOR_APP:
		return
	_run_selected_public_case()
	get_viewport().set_input_as_handled()


## Returns the current route-local workstation presentation substate.
func current_substate() -> StringName:
	return _substate


## Returns the stable semantic computer and editor target counts in this shell.
func semantic_target_counts() -> Dictionary[StringName, int]:
	return {
		&"computer": _count_named_buttons(&"ComputerTarget"),
		&"editor_icon": _count_named_buttons(&"EditorIcon"),
	}


## Returns the unchanged owner-request counters for presentation invariance tests.
func owner_request_snapshot() -> Dictionary[StringName, int]:
	return _owner_request_counts.duplicate()


## Activates the physical computer through the same presentation handler as its button.
func activate_computer_for_test() -> void:
	_enter_desktop()


## Activates the editor icon through the same presentation handler as player input.
func activate_editor_for_test() -> void:
	_enter_editor_app()


## Returns the active responsive layout mode using the documented effective width.
func pane_mode() -> StringName:
	return _pane_mode


## Renders only owner-provided slot summaries. This method never derives a
## candidate, eligibility state, generation order, or recovery choice.
func publish_save_recovery_snapshot(snapshot: Dictionary, message: String = "") -> void:
	_save_recovery_snapshot = snapshot.duplicate(true)
	if _save_overlay != null:
		_render_save_recovery_overlay(message)


## Opens the reusable Save/Load overlay through the same header action used by
## pointer and keyboard activation.
func open_save_recovery_overlay_for_test() -> bool:
	if _substate != EDITOR_APP:
		return false
	_open_save_recovery_overlay()
	return _save_overlay != null and _save_overlay.visible


## Opens the existing four-slot recovery surface from Startup. This route keeps
## only the three manual Load actions; autosave remains read-only information.
func open_startup_load_recovery_overlay() -> bool:
	if _save_overlay == null:
		return false
	_startup_load_mode = true
	visible = true
	_substate = EDITOR_APP
	_workstation_view.visible = false
	_desktop_view.visible = false
	_editor_app.visible = true
	_ensure_startup_load_scrim()
	if _startup_load_scrim != null:
		_startup_load_scrim.visible = true
	_save_overlay.visible = true
	_render_save_recovery_overlay()
	var first_slot: Control = _first_manual_slot_control()
	var initial_focus: Control = first_slot if first_slot != null else _save_overlay_close
	if _is_focus_target(initial_focus):
		initial_focus.grab_focus()
	return true


## Closes Startup Load without changing any owner. The composition root restores
## its Startup route from the emitted presentation signal.
func finish_startup_load_route() -> void:
	if not _startup_load_mode:
		return
	_close_save_confirmation()
	if _save_overlay != null:
		_save_overlay.visible = false
	_startup_load_mode = false
	if _startup_load_scrim != null:
		_startup_load_scrim.visible = false


func is_startup_load_mode() -> bool:
	return _startup_load_mode


func prepare_next_day_entry() -> void:
	if _confirmation_overlay != null and _confirmation_overlay.visible:
		_close_save_confirmation()
	if _save_overlay != null and _save_overlay.visible:
		_close_save_recovery_overlay()
	if _inspect_pane != null and _inspect_pane.visible:
		_close_inspect()
	_set_interaction_busy(false)
	# An authoritative day transition supersedes the short fresh-entry pointer
	# guard and must leave the next workstation entry focusable immediately.
	_computer_target.disabled = false
	_show_workstation_view()


## Prevents the pointer release that accepted a fresh-Career confirmation from
## activating the newly revealed full-screen computer target after scene reload.
func guard_fresh_entry_pointer_release() -> void:
	_computer_target.disabled = true
	_restore_fresh_entry_pointer_release.call_deferred()


func _restore_fresh_entry_pointer_release() -> void:
	# UI automation and low-frame-rate hosts can hold the accepted click across
	# a scene reload. Use wall-clock settling because headless and uncapped hosts
	# can render many frames before the injected click sequence fully retires.
	await get_tree().create_timer(0.4).timeout
	var release_wait_frames: int = 0
	while Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and release_wait_frames < 60:
		await get_tree().process_frame
		release_wait_frames += 1
	# Reassert the intended fresh-Career presentation after any release event that
	# was already queued against the newly mounted full-screen computer target.
	_show_workstation_view()
	_computer_target.disabled = false
	if _substate == WORKSTATION_VIEW and _is_focus_target(_computer_target):
		_computer_target.grab_focus()


## Read-only probe for the fixed owner roster order.
func save_recovery_slot_order_for_test() -> Array[StringName]:
	return SAVE_SLOT_IDS.duplicate()


## Dispatches the same typed action as one player slot control.
func request_save_recovery_for_test(operation: StringName, slot_id: StringName) -> bool:
	return _request_save_recovery_operation(operation, slot_id)


## Renders an owner-issued destructive confirmation. The opaque token is carried
## through untouched and is never interpreted by presentation.
func present_save_confirmation_from_owner(
	operation: StringName, slot_id: StringName, token: Variant, owner_message: String
) -> bool:
	return _open_save_confirmation(operation, slot_id, token, owner_message)


## Compatibility alias for deterministic interaction tests.
func present_save_confirmation_for_test(
	operation: StringName, slot_id: StringName, token: Variant, owner_message: String
) -> bool:
	return present_save_confirmation_from_owner(operation, slot_id, token, owner_message)


func confirm_save_recovery_for_test() -> bool:
	return _confirm_save_recovery_operation()


func cancel_save_recovery_for_test() -> void:
	_close_save_confirmation()


## Deterministic seam for exact responsive-boundary tests without a viewport mutation.
func apply_effective_width_for_test(width: float, scale: float) -> StringName:
	_apply_editor_window_layout()
	_apply_pane_mode(width / maxf(scale, 0.01))
	return _pane_mode


## Presentation-to-owner seam. The returned record contains no engine object.
func submit_graph_edit_for_test(command_id: StringName) -> int:
	if command_id.is_empty() or not _ensure_editor_composition():
		return 0
	var authoring := _current_authoring_panel()
	if authoring == null or not authoring.request_embedded_primary_action():
		return 0
	return _pending_graph_request_id


## Applies only the owner-provided typed accepted-state response for the current request.
func resolve_graph_edit_from_owner(
	request_id: int, response: GraphAuthoringPanel.SessionResponse
) -> bool:
	if request_id == 0 or request_id != _pending_graph_request_id:
		return false
	_pending_graph_request_id = 0
	var authoring := _current_authoring_panel()
	if authoring == null:
		_ensure_editor_composition()
		return false
	var admitted: bool = authoring.complete_embedded_admission(response)
	if admitted:
		_accepted_graph_projection = tr("Accepted graph change: %s") % response.player_message
		_editor_status.text = _accepted_graph_projection
	else:
		_editor_status.text = tr("Graph change rejected: %s") % response.player_message
	return admitted


## Read-only test probe for the currently accepted graph projection.
func accepted_graph_projection() -> String:
	return _accepted_graph_projection


## Receives one owner-published frozen report and its report-bound Sandbox
## projections. This presentation seam reads immutable records only.
func publish_completed_coursework_report(
	report: CourseworkRunResult, accepted_sandbox_by_case: Dictionary = {},
	report_is_out_of_date: bool = false
) -> void:
	if report == null or not report.is_valid():
		if _completed_report != null:
			_editor_status.text = tr("Report unavailable; previous accepted result remains displayed.")
		else:
			_editor_status.text = tr("Report unavailable. No accepted result is available.")
			_render_completed_report()
		return
	if _inspect_pane.visible:
		_close_inspect()
	_completed_report = null
	_completed_report_is_out_of_date = false
	_accepted_sandbox_by_case.clear()
	_selected_result_index = -1
	_completed_report = report
	_completed_report_is_out_of_date = report_is_out_of_date and _completed_report != null
	for raw_case_id: Variant in accepted_sandbox_by_case:
		var state := accepted_sandbox_by_case[raw_case_id] as SandboxCaseState
		if state != null and state.is_valid():
			_accepted_sandbox_by_case[String(raw_case_id)] = state
	_selected_result_index = 0 if _completed_report != null and not _completed_report.case_results().is_empty() else -1
	_render_completed_report()


## Clears only the prior Task's read-only Results and Inspect projection after a
## newly admitted Task has rebound the editor. It does not mutate owner state.
func clear_completed_coursework_report_for_new_task() -> void:
	if _inspect_pane.visible:
		_close_inspect()
	_completed_report = null
	_completed_report_is_out_of_date = false
	_accepted_sandbox_by_case.clear()
	_selected_result_index = -1
	_render_completed_report()


## Rebinds static, current-Task presentation after an admitted task change.
## It resets only presentation projections and never changes owner state.
func rebind_current_task_presentation(
	day_index: int, task_title: String = "Assignment", case_labels: Array[String] = []
) -> void:
	if day_index < 1:
		return
	_current_day_index = day_index
	_current_task_title = task_title if not task_title.is_empty() else tr("Assignment")
	_current_case_labels = case_labels.duplicate()
	_accepted_graph_projection = tr("No accepted graph changes.")
	_workspace_heading.text = tr("Coursework Editor  •  Day %d • %s") % [day_index, _current_task_title]
	_desktop_status.text = tr("1 assignment ready\nOpen Editor to continue Day %d.") % day_index
	_requirements_copy.text = tr("Day %d • %s\nUse the Graph authoring controls to repair the current Task, then Run a public case.") % [day_index, _current_task_title]
	_editor_status.text = tr("Day %d assignment ready.") % day_index
	_reset_delivery_risk_warning_presentation()
	_render_completed_report()


## Legacy deterministic-test alias. Production callers use the owner-published
## coursework method above and never invoke Sandbox or GVET from this shell.
func replace_completed_report_for_test(
	report: CourseworkRunResult, accepted_sandbox_by_case: Dictionary = {}
) -> void:
	publish_completed_coursework_report(report, accepted_sandbox_by_case)


## Selects one visible owner-ordered result row for deterministic presentation tests.
func select_result_for_test(index: int) -> bool:
	if _completed_report == null:
		return false
	var cases: Array[CourseworkCaseResult] = _completed_report.case_results()
	if index < 0 or index >= cases.size():
		return false
	_selected_result_index = index
	_result_case_select.select(index)
	_refresh_inspect_admission()
	return true


## Returns only player-safe Results text for deterministic no-debug-dump assertions.
func results_text_for_test() -> String:
	return _results_copy.text


## Returns only player-safe Inspect text for deterministic no-debug-dump assertions.
func inspect_text_for_test() -> String:
	return _inspect_copy.text


## Returns whether the selected accepted result admits the read-only Inspect surface.
func inspect_is_available_for_test() -> bool:
	return not _inspect_button.disabled


## Opens Inspect through the same admission path as the player-facing control.
func open_inspect_for_test() -> bool:
	return _open_inspect()


## Closes Inspect through the same focus-restoration path as the player-facing control.
func close_inspect_for_test() -> void:
	_close_inspect()


## Returns the visible owner-order case labels without exposing internal case identities.
func result_case_labels_for_test() -> Array[String]:
	var labels: Array[String] = []
	for item_index: int in range(_result_case_select.item_count):
		labels.append(_result_case_select.get_item_text(item_index))
	return labels


## Replaces only the read-only Sandbox projection constructor for boundary-spy tests.
func set_sandbox_projection_factory_for_test(factory: Callable) -> void:
	_sandbox_inspect_projection_factory = factory


## Clears a cached target to exercise the documented focus fallback in tests.
func clear_cached_editor_focus_for_test() -> void:
	_last_editor_focus = null


## Consumes context input that reaches the editor root and never observes desktop return.
func handle_editor_app_gui_input(event: InputEvent) -> bool:
	if _substate != EDITOR_APP or not event is InputEventMouseButton:
		return false
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return false
	_editor_app.accept_event()
	return true


## Returns from desktop through the same presentation handler as the Back command.
func return_to_workstation_for_test() -> void:
	_return_to_workstation()


## Handles a constructed desktop-background event and returns whether it changed state.
func handle_desktop_background_gui_input(event: InputEvent) -> bool:
	if _substate != DESKTOP or not event is InputEventMouseButton:
		return false
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return false
	_desktop_background.accept_event()
	_return_to_workstation()
	return true


func _create_save_recovery_controls() -> void:
	_save_header_action = Button.new()
	_save_header_action.name = "SaveHeaderAction"
	_save_header_action.custom_minimum_size = SAVE_HEADER_SIZE
	_save_header_action.focus_mode = Control.FOCUS_ALL
	_editor_header_row.add_child(_save_header_action)
	_editor_header_row.move_child(_save_header_action, _editor_back.get_index())
	_style_header_button(_save_header_action, Color(0.07, 0.25, 0.22, 1), PAPER)

	_save_overlay = Control.new()
	_save_overlay.name = "SaveLoadOverlay"
	_save_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_save_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_save_overlay.visible = false
	_editor_app.add_child(_save_overlay)
	var dimmer := ColorRect.new()
	dimmer.name = "InertBackground"
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.01, 0.02, 0.04, 0.9)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_save_overlay.add_child(dimmer)
	_save_overlay_panel = PanelContainer.new()
	_save_overlay_panel.name = "SaveLoadPanel"
	_save_overlay_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_save_overlay_panel.add_theme_stylebox_override(&"panel", _make_pixel_style(Color(0.035, 0.06, 0.09, 1), SIGNAL_CYAN, 2))
	_save_overlay.add_child(_save_overlay_panel)
	var layout := VBoxContainer.new()
	layout.name = "Layout"
	layout.custom_minimum_size = Vector2(628.0, 0.0)
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override(&"separation", 10)
	_save_overlay_panel.add_child(layout)
	var heading := Label.new()
	heading.name = "SaveLoadHeading"
	heading.text = tr("Save / Load")
	heading.add_theme_font_size_override(&"font_size", 24)
	heading.add_theme_color_override(&"font_color", PAPER)
	heading.focus_mode = Control.FOCUS_ALL
	_save_overlay_heading = heading
	layout.add_child(heading)
	_save_overlay_status = Label.new()
	_save_overlay_status.name = "OwnerResult"
	_save_overlay_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_save_overlay_status.custom_minimum_size = Vector2(628.0, 52.0)
	_save_overlay_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_overlay_status.add_theme_font_size_override(&"font_size", 18)
	_save_overlay_status.add_theme_color_override(&"font_color", PAPER)
	layout.add_child(_save_overlay_status)
	_save_overlay_slots = VBoxContainer.new()
	_save_overlay_slots.name = "OwnerSlotRoster"
	_save_overlay_slots.custom_minimum_size = Vector2(0.0, 176.0)
	_save_overlay_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_overlay_slots.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_save_overlay_slots)
	_save_overlay_close = Button.new()
	_save_overlay_close.name = "CloseSaveLoad"
	_save_overlay_close.custom_minimum_size = Vector2(140.0, 44.0)
	_save_overlay_close.focus_mode = Control.FOCUS_ALL
	_save_overlay_close.text = tr("Close")
	_style_button(_save_overlay_close, Color(0.09, 0.16, 0.2, 1), PAPER)
	_save_overlay_close.pressed.connect(_close_save_recovery_overlay)
	layout.add_child(_save_overlay_close)

	_confirmation_overlay = Control.new()
	_confirmation_overlay.name = "SaveRecoveryConfirmation"
	_confirmation_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirmation_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirmation_overlay.visible = false
	_save_overlay.add_child(_confirmation_overlay)
	var confirmation_dimmer := ColorRect.new()
	confirmation_dimmer.name = "InertOverlayBackground"
	confirmation_dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	confirmation_dimmer.color = Color(0.0, 0.0, 0.0, 0.82)
	confirmation_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirmation_overlay.add_child(confirmation_dimmer)
	var confirmation_panel := PanelContainer.new()
	confirmation_panel.name = "ConfirmationPanel"
	confirmation_panel.position = Vector2(126.0, 118.0)
	confirmation_panel.size = Vector2(416.0, 214.0)
	confirmation_panel.add_theme_stylebox_override(&"panel", _make_pixel_style(Color(0.12, 0.06, 0.08, 1), FAULT_CORAL, 2))
	_confirmation_overlay.add_child(confirmation_panel)
	var confirmation_layout := VBoxContainer.new()
	confirmation_layout.name = "ConfirmationLayout"
	confirmation_layout.add_theme_constant_override(&"separation", 12)
	confirmation_panel.add_child(confirmation_layout)
	_confirmation_copy = Label.new()
	_confirmation_copy.name = "ConfirmationReason"
	_confirmation_copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirmation_copy.add_theme_font_size_override(&"font_size", 18)
	_confirmation_copy.add_theme_color_override(&"font_color", PAPER)
	confirmation_layout.add_child(_confirmation_copy)
	var confirmation_actions := HBoxContainer.new()
	confirmation_actions.name = "ConfirmationActions"
	confirmation_actions.add_theme_constant_override(&"separation", 12)
	confirmation_layout.add_child(confirmation_actions)
	_confirmation_cancel = Button.new()
	_confirmation_cancel.name = "CancelConfirmation"
	_confirmation_cancel.custom_minimum_size = Vector2(160.0, 44.0)
	_confirmation_cancel.focus_mode = Control.FOCUS_ALL
	_confirmation_cancel.text = tr("Cancel")
	_style_button(_confirmation_cancel, Color(0.11, 0.15, 0.2, 1), PAPER)
	_confirmation_cancel.pressed.connect(_close_save_confirmation)
	confirmation_actions.add_child(_confirmation_cancel)
	_confirmation_confirm = Button.new()
	_confirmation_confirm.name = "ConfirmSaveRecovery"
	_confirmation_confirm.custom_minimum_size = Vector2(160.0, 44.0)
	_confirmation_confirm.focus_mode = Control.FOCUS_ALL
	_confirmation_confirm.text = tr("Confirm")
	_style_button(_confirmation_confirm, Color(0.35, 0.12, 0.14, 1), PAPER)
	_confirmation_confirm.pressed.connect(_confirm_save_recovery_operation)
	confirmation_actions.add_child(_confirmation_confirm)
	_confirmation_cancel.focus_next = _confirmation_confirm.get_path()
	_confirmation_cancel.focus_previous = _confirmation_confirm.get_path()
	_confirmation_confirm.focus_next = _confirmation_cancel.get_path()
	_confirmation_confirm.focus_previous = _confirmation_cancel.get_path()


func _on_save_header_action_pressed() -> void:
	_open_save_recovery_overlay()


func _open_save_recovery_overlay() -> void:
	if _substate != EDITOR_APP or _save_overlay == null:
		return
	var focused := get_viewport().gui_get_focus_owner()
	_save_recovery_origin = focused as Control if focused is Control and _is_focus_target(focused as Control) else _save_header_action
	_save_overlay.visible = true
	_render_save_recovery_overlay()
	var first_slot: Control = _first_manual_slot_control()
	var initial_focus: Control = first_slot if first_slot != null else _save_overlay_close
	if _is_focus_target(initial_focus):
		initial_focus.grab_focus()


func _close_save_recovery_overlay() -> void:
	if _save_overlay == null or not _save_overlay.visible:
		return
	_close_save_confirmation()
	_save_overlay.visible = false
	if _startup_load_mode:
		_startup_load_mode = false
		if _startup_load_scrim != null:
			_startup_load_scrim.visible = false
		_show_workstation_view()
		startup_load_closed.emit()
		return
	var origin := _save_recovery_origin
	_save_recovery_origin = null
	_restore_save_recovery_focus_deferred.call_deferred(origin)


func _restore_save_recovery_focus_deferred(origin: Control) -> void:
	if _is_focus_target(origin):
		origin.grab_focus()
		return
	if _is_focus_target(_workspace_heading):
		_workspace_heading.grab_focus()
		return
	_restore_editor_focus_deferred()


func _render_save_recovery_overlay(message: String = "") -> void:
	if _save_overlay_slots == null:
		return
	var focus_identity := _save_overlay_focus_identity()
	_clear_save_recovery_roster()
	_save_slot_actions.clear()
	_save_overlay_status.text = message if not message.is_empty() else tr("Choose a manual slot. Autosave is shown for recovery information only.")
	for slot_id: StringName in SAVE_SLOT_IDS:
		var row := HBoxContainer.new()
		row.name = "Slot_%s" % String(slot_id).replace(".", "_")
		row.add_theme_constant_override(&"separation", 8)
		_save_overlay_slots.add_child(row)
		var slot: Dictionary = _save_dictionary(_save_recovery_snapshot.get(String(slot_id), {}))
		var summary := Label.new()
		summary.name = "Summary"
		summary.custom_minimum_size = Vector2(340.0, 44.0)
		summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.add_theme_font_size_override(&"font_size", 18)
		summary.add_theme_color_override(&"font_color", PAPER)
		summary.text = _save_slot_summary(slot_id, slot)
		row.add_child(summary)
		var actions: Dictionary = {}
		if MANUAL_SAVE_SLOT_IDS.has(slot_id):
			for operation: StringName in _save_recovery_operations():
				var action := Button.new()
				action.name = "%s_%s" % [String(operation).capitalize(), String(slot_id).replace(".", "_")]
				action.custom_minimum_size = Vector2(72.0, 44.0)
				action.focus_mode = Control.FOCUS_ALL
				action.text = tr(String(operation).capitalize())
				_style_button(action, Color(0.06, 0.16, 0.2, 1), PAPER)
				action.pressed.connect(_on_save_slot_action_pressed.bind(operation, slot_id))
				row.add_child(action)
				actions[operation] = action
		_save_slot_actions[slot_id] = actions
	_configure_save_overlay_focus()
	if not focus_identity.is_empty():
		_restore_save_overlay_focus_deferred.call_deferred(focus_identity)


## Keeps a roster refresh downstream of owner results from losing the logical
## slot action that initiated the request. The identity is deliberately plain
## data because the old Control is removed during the refresh.
func _save_overlay_focus_identity() -> Dictionary:
	if _save_overlay == null or not _save_overlay.visible:
		return {}
	var focused := get_viewport().gui_get_focus_owner()
	if not (focused is Control):
		return {}
	for slot_id: StringName in MANUAL_SAVE_SLOT_IDS:
		var actions: Dictionary = _save_dictionary(_save_slot_actions.get(slot_id, {}))
		for operation: StringName in _save_recovery_operations():
			if actions.get(operation) == focused:
				return {"slot_id": slot_id, "operation": operation}
	return {}


## Detaches replaced slot controls immediately while deferring destruction until
## the current pressed-signal stack has unwound.
func _clear_save_recovery_roster() -> void:
	for child: Node in _save_overlay_slots.get_children():
		_save_overlay_slots.remove_child(child)
		child.queue_free()


func _restore_save_overlay_focus_deferred(focus_identity: Dictionary) -> void:
	var slot_id := focus_identity.get("slot_id", &"") as StringName
	var operation := focus_identity.get("operation", &"") as StringName
	var actions: Dictionary = _save_dictionary(_save_slot_actions.get(slot_id, {}))
	var replacement := actions.get(operation) as Control
	if _is_focus_target(replacement):
		replacement.grab_focus()
		return
	_restore_save_recovery_heading_focus()


func _save_slot_summary(slot_id: StringName, slot: Dictionary) -> String:
	var current: Dictionary = _save_dictionary(slot.get("current", {}))
	var previous: Dictionary = _save_dictionary(slot.get("previous", {}))
	var current_id := String(current.get("generation_id", ""))
	var previous_id := String(previous.get("generation_id", ""))
	if not MANUAL_SAVE_SLOT_IDS.has(slot_id):
		return tr("Autosave: %s") % (tr("No recovery generation") if current_id.is_empty() else tr("Current recovery generation available"))
	if current_id.is_empty():
		return tr("%s: Empty") % String(slot_id)
	return tr("%s: Current generation available%s") % [String(slot_id), tr("; previous generation available") if not previous_id.is_empty() else ""]


func _configure_save_overlay_focus() -> void:
	var controls: Array[Control] = [_save_overlay_heading]
	for slot_id: StringName in MANUAL_SAVE_SLOT_IDS:
		var actions: Dictionary = _save_dictionary(_save_slot_actions.get(slot_id, {}))
		for operation: StringName in [&"save", &"load", &"delete"]:
			var action := actions.get(operation) as Control
			if action != null:
				controls.append(action)
	controls.append(_save_overlay_close)
	for index: int in range(controls.size()):
		controls[index].focus_next = controls[(index + 1) % controls.size()].get_path()
		controls[index].focus_previous = controls[(index - 1 + controls.size()) % controls.size()].get_path()


func _first_manual_slot_control() -> Control:
	var actions: Dictionary = _save_dictionary(_save_slot_actions.get(&"manual.1", {}))
	return actions.get(&"load" if _startup_load_mode else &"save") as Control


func _on_save_slot_action_pressed(operation: StringName, slot_id: StringName) -> void:
	_request_save_recovery_operation(operation, slot_id)


func _request_save_recovery_operation(operation: StringName, slot_id: StringName) -> bool:
	if _interaction_busy or _substate != EDITOR_APP or not MANUAL_SAVE_SLOT_IDS.has(slot_id):
		return false
	if not _save_recovery_operations().has(operation):
		return false
	_emit_save_recovery_request(operation, slot_id, null)
	return true


func _open_save_confirmation(
	operation: StringName, slot_id: StringName, token: Variant, owner_message: String
) -> bool:
	if _save_overlay == null or not _save_overlay.visible or not MANUAL_SAVE_SLOT_IDS.has(slot_id) \
		or (operation != &"save" and operation != &"delete") or token == null:
		return false
	var focused := get_viewport().gui_get_focus_owner()
	_save_confirmation_origin = focused as Control if focused is Control and _is_focus_target(focused as Control) else null
	_pending_confirmation_operation = operation
	_pending_confirmation_slot_id = slot_id
	_pending_confirmation_token = token
	_confirmation_copy.text = owner_message if not owner_message.is_empty() else tr("Confirm %s for %s. The observed slot state will be checked by the owner.") % [String(operation), String(slot_id)]
	_confirmation_overlay.visible = true
	_confirmation_cancel.grab_focus()
	return true


func _confirm_save_recovery_operation() -> bool:
	if _pending_confirmation_operation.is_empty() or _pending_confirmation_slot_id.is_empty():
		return false
	_emit_save_recovery_request(_pending_confirmation_operation, _pending_confirmation_slot_id, _pending_confirmation_token)
	_close_save_confirmation()
	return true


func _close_save_confirmation() -> void:
	if _confirmation_overlay == null or not _confirmation_overlay.visible:
		return
	_confirmation_overlay.visible = false
	_pending_confirmation_operation = &""
	_pending_confirmation_slot_id = &""
	_pending_confirmation_token = null
	var origin := _save_confirmation_origin
	_save_confirmation_origin = null
	var origin_instance_id := origin.get_instance_id() if is_instance_valid(origin) else 0
	_restore_save_confirmation_focus_deferred.call_deferred(origin_instance_id)


func _restore_save_confirmation_focus_deferred(origin_instance_id: int) -> void:
	var origin := instance_from_id(origin_instance_id) as Control if origin_instance_id != 0 else null
	if _is_focus_target(origin):
		origin.grab_focus()
		return
	_restore_save_recovery_heading_focus()


func _restore_save_recovery_heading_focus() -> void:
	if _is_focus_target(_save_overlay_heading):
		_save_overlay_heading.grab_focus()
		return
	if _is_focus_target(_workspace_heading):
		_workspace_heading.grab_focus()


func _emit_save_recovery_request(operation: StringName, slot_id: StringName, token: Variant) -> void:
	var request := SaveRecoveryRequest.new()
	request.request_id = _next_save_recovery_request_id
	request.operation = operation
	request.slot_id = slot_id
	request.confirmation_token = token
	_next_save_recovery_request_id += 1
	_owner_request_counts[&"save"] += 1
	save_recovery_requested.emit(request)


func _save_dictionary(value: Variant) -> Dictionary:
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}


func _save_recovery_operations() -> Array[StringName]:
	return [&"load"] if _startup_load_mode else [&"save", &"load", &"delete"]


func _ensure_startup_load_scrim() -> void:
	if _startup_load_scrim != null:
		return
	_startup_load_scrim = ColorRect.new()
	_startup_load_scrim.name = "StartupLoadScrim"
	_startup_load_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_startup_load_scrim.color = Color(0.04, 0.07, 0.1, 0.96)
	_startup_load_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_editor_app.add_child(_startup_load_scrim)
	_editor_app.move_child(_startup_load_scrim, _save_overlay.get_index())


func _on_computer_target_pressed() -> void:
	_enter_desktop()


func _on_desktop_back_pressed() -> void:
	_return_to_workstation()


func _on_editor_icon_pressed() -> void:
	_enter_editor_app()


func _enter_desktop() -> void:
	if _substate == DESKTOP:
		return
	_substate = DESKTOP
	_workstation_view.visible = false
	_desktop_view.visible = true
	_restore_focus_deferred.call_deferred(_desktop_back)


func _enter_editor_app() -> void:
	if _substate != DESKTOP:
		return
	_substate = EDITOR_APP
	_editor_app.visible = true
	_apply_responsive_layout()
	if not _ensure_editor_composition():
		return
	_restore_editor_focus_deferred.call_deferred()


func _on_editor_back_pressed() -> void:
	_handle_editor_return_input()


func _handle_editor_return_input() -> void:
	if _editor_failed:
		_return_to_desktop()
		return
	if _editor_confirmation_is_open():
		var authoring := _current_authoring_panel()
		if authoring != null:
			authoring.handle_embedded_escape()
		return
	if not _editor_editing_is_available():
		_editor_status.text = tr("Editing is temporarily unavailable. Return to Desktop is unavailable.")
		return
	_return_to_desktop()


func _return_to_desktop() -> void:
	if _substate != EDITOR_APP:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is Control and _is_focus_target(focused as Control):
		_last_editor_focus = focused as Control
	_substate = DESKTOP
	_workstation_view.visible = false
	_desktop_view.visible = true
	_editor_app.visible = false
	_restore_focus_deferred.call_deferred(_editor_icon)


func _return_to_workstation() -> void:
	if _substate != DESKTOP:
		return
	_show_workstation_view()


func _show_workstation_view() -> void:
	_substate = WORKSTATION_VIEW
	_editor_app.visible = false
	_desktop_view.visible = false
	_workstation_view.visible = true
	_restore_focus_deferred.call_deferred(_computer_target)


func _restore_focus_deferred(target: Control) -> void:
	if _is_focus_target(target):
		target.grab_focus()


func _restore_editor_focus_deferred() -> void:
	if _is_focus_target(_last_editor_focus):
		_last_editor_focus.grab_focus()
		return
	var graph := _current_editor_graph()
	if not _editor_failed and _is_focus_target(graph):
		graph.grab_focus()
		return
	if _is_focus_target(_results_heading):
		_results_heading.grab_focus()
		return
	if _is_focus_target(_workspace_heading):
		_workspace_heading.grab_focus()


## Emits a typed Submit Build intent. Owner confirmation remains mandatory when
## Workday reports a risk warning.
func request_delivery_for_test(risk_warning_confirmed: bool = false) -> int:
	if _interaction_busy:
		return 0
	return _emit_delivery_request(risk_warning_confirmed)


func _emit_delivery_request(risk_warning_confirmed: bool) -> int:
	var request := DeliveryRequest.new()
	request.request_id = _next_delivery_request_id
	request.risk_warning_confirmed = risk_warning_confirmed
	_next_delivery_request_id += 1
	_owner_request_counts[&"delivery"] += 1
	delivery_requested.emit(request)
	return request.request_id


func present_delivery_risk_warning(message: String) -> void:
	_set_interaction_busy(false)
	_editor_status.text = message
	if _delivery_action != null:
		_delivery_action.text = tr("Confirm Submit Build")
		_delivery_action.set_meta(&"risk_warning_pending", true)


func publish_delivery_result(accepted: bool, message: String) -> void:
	_set_interaction_busy(false)
	_editor_status.text = tr("Submit Build: %s") % (tr("Completed.") if accepted else message)
	_reset_delivery_risk_warning_presentation()


func _reset_delivery_risk_warning_presentation() -> void:
	if _delivery_action != null:
		_delivery_action.text = tr("Submit Build")
		_delivery_action.remove_meta(&"risk_warning_pending")


func _on_delivery_action_pressed() -> void:
	if _interaction_busy:
		return
	var confirmed: bool = _delivery_action != null and _delivery_action.has_meta(&"risk_warning_pending")
	_set_interaction_busy(true, tr("Submitting build. Waiting for the owner."))
	call_deferred("_request_delivery_after_process_frame", confirmed)


func _on_graph_primary_action_pressed() -> void:
	_editor_status.text = tr("Use the graph authoring controls to repair this Task.")


func _on_graph_run_action_pressed() -> void:
	_run_selected_public_case()


func _run_selected_public_case() -> bool:
	if not _ensure_editor_composition():
		return false
	var authoring := _current_authoring_panel()
	return authoring != null and authoring.request_embedded_run_selected()


func _request_delivery_after_process_frame(risk_warning_confirmed: bool) -> void:
	await get_tree().process_frame
	if _interaction_busy:
		_emit_delivery_request(risk_warning_confirmed)


func _on_embedded_busy_state_changed(is_busy: bool) -> void:
	_set_interaction_busy(is_busy, tr("Run requested. Waiting for the owner.") if is_busy else "")


func _on_embedded_run_completed(succeeded: bool) -> void:
	_editor_status.text = tr("Run complete.") if succeeded else tr("Run failed. No completed report is available.")
	_restore_results_focus_deferred.call_deferred()


func _set_interaction_busy(is_busy: bool, message: String = "") -> void:
	if _interaction_busy == is_busy:
		_set_busy_status(message)
		return
	_interaction_busy = is_busy
	_capture_busy_focus(is_busy)
	_set_busy_controls(is_busy)
	_set_busy_status(message)
	if not is_busy:
		_restore_focus_deferred.call_deferred(_busy_focus)
		_busy_focus = null


func _capture_busy_focus(is_busy: bool) -> void:
	if not is_busy:
		return
	var focused := get_viewport().gui_get_focus_owner()
	_busy_focus = focused as Control if focused is Control and _is_focus_target(focused as Control) else null


func _set_busy_controls(is_busy: bool) -> void:
	for control: Control in [_graph_primary_action, _graph_run_action, _delivery_action,
		_save_header_action, _result_case_select, _inspect_button]:
		if control != null:
			control.disabled = is_busy
	for slot_id: StringName in _save_slot_actions:
		for action: Variant in Dictionary(_save_slot_actions[slot_id]).values():
			var control := action as Control
			if control != null:
				control.disabled = is_busy


func _set_busy_status(message: String) -> void:
	if not message.is_empty():
		_editor_status.text = message


## Deterministic probe for the no-queue presentation boundary.
func is_interaction_busy_for_test() -> bool:
	return _interaction_busy


func _on_authoring_command_requested(command: GraphAuthoringPanel.GraphCommandRequest) -> void:
	if _editor_failed:
		return
	if _interaction_busy:
		var busy_authoring := _current_authoring_panel()
		if busy_authoring != null:
			busy_authoring.complete_embedded_admission(GraphAuthoringPanel.SessionResponse.new(
				false, {}, &"owner_pending",
				tr("Graph changes are unavailable while the owner is running.")))
		return
	if _pending_graph_request_id != 0:
		return
	var request := EditorGraphRequest.new()
	request.request_id = _next_graph_request_id
	request.command_id = _command_id(command)
	request.command = command
	request.from_node = StringName(command.payload.get("output_node_id", ""))
	request.from_port = int(command.payload.get("output_port_id", -1))
	request.to_node = StringName(command.payload.get("input_node_id", ""))
	request.to_port = int(command.payload.get("input_port_id", -1))
	_next_graph_request_id += 1
	_pending_graph_request_id = request.request_id
	_editor_status.text = tr("Graph change is waiting for authoring.")
	graph_edit_requested.emit(request)


func _ensure_editor_composition() -> bool:
	if _editor_failed:
		return false
	if _current_authoring_panel() != null and _current_editor_graph() != null:
		return true
	_editor_failed = true
	_pending_graph_request_id = 0
	_graph_primary_action.disabled = true
	_graph_run_action.disabled = true
	_editor_status.text = tr("Editor unavailable. Use Back to Desktop and try again.")
	_restore_focus_deferred.call_deferred(_editor_back)
	return false


func _current_authoring_panel() -> GraphAuthoringPanel:
	var panel: GraphAuthoringPanel = get_node_or_null("EditorApp/GraphPane/GraphAuthoringPanel") as GraphAuthoringPanel
	if panel == null or not is_instance_valid(panel) or not panel.is_inside_tree():
		return null
	return panel


func _current_editor_graph() -> GraphEdit:
	var panel := _current_authoring_panel()
	if panel == null:
		return null
	var graph: GraphEdit = panel.get_node_or_null("Panel/Layout/Workspace/GraphEdit") as GraphEdit
	if graph == null or not is_instance_valid(graph) or not graph.is_inside_tree():
		return null
	return graph


func _editor_confirmation_is_open() -> bool:
	var panel := _current_authoring_panel()
	return panel != null and panel.has_open_confirmation()


func _editor_editing_is_available() -> bool:
	var panel := _current_authoring_panel()
	return panel != null and panel.is_editing_available()


func _command_id(command: GraphAuthoringPanel.GraphCommandRequest) -> StringName:
	match command.kind:
		GraphAuthoringPanel.GraphCommandRequest.Kind.CONNECT:
			return &"connect"
		GraphAuthoringPanel.GraphCommandRequest.Kind.DISCONNECT:
			return &"disconnect"
		GraphAuthoringPanel.GraphCommandRequest.Kind.RESET:
			return &"reset"
		GraphAuthoringPanel.GraphCommandRequest.Kind.CANCEL_RESET:
			return &"cancel_reset"
		_:
			return &"graph_edit"


func _on_view_tab_selected(index: int) -> void:
	if _pane_mode != ONE_PANE:
		return
	_requirements_pane.visible = index == 1
	_results_pane.visible = index == 2
	_graph_pane.visible = index == 0


func _on_result_case_selected(index: int) -> void:
	select_result_for_test(index)


func _on_inspect_button_pressed() -> void:
	if _completed_report != null and not _completed_report.validation_pass():
		_locate_semantic_diagnostic_node()
		return
	_open_inspect()


func _on_inspect_close_pressed() -> void:
	_close_inspect()


func _render_completed_report() -> void:
	var prior_results_focus: Control = _current_results_focus_target()
	_result_case_select.clear()
	_clear_container(_results_cards)
	if _completed_report == null:
		_render_no_completed_report(prior_results_focus)
		return
	if not _completed_report.validation_pass():
		_render_semantic_validation_report(prior_results_focus)
		return
	var cases: Array[CourseworkCaseResult] = _completed_report.case_results()
	var passed_count: int = _count_passed_cases(cases)
	var summary: String = tr("Run complete: %d of %d cases passed.") % [passed_count, cases.size()]
	if _completed_report_is_out_of_date:
		summary = "%s\n%s" % [summary, tr("OUT OF DATE — still readable")]
	_results_message_scroll.visible = false
	_results_cards_scroll.visible = true
	_add_results_summary(summary)
	var lines: Array[String] = _render_result_cases(cases, summary)
	_finalize_result_selection(cases)
	_results_copy.text = "\n".join(lines)
	_refresh_inspect_admission()
	_defer_results_focus_if_current_target_is_inactive(prior_results_focus)


func _render_semantic_validation_report(prior_results_focus: Control) -> void:
	_selected_result_index = -1
	_result_case_select.visible = false
	_result_case_select.disabled = true
	_results_cards_scroll.visible = false
	_results_message_scroll.visible = true
	var lines: Array[String] = [
		tr("Graph validation blocked this run."),
		tr("OUT OF DATE — still readable") if _completed_report_is_out_of_date else "",
		tr("No public cases were run."),
	]
	if lines[1].is_empty():
		lines.remove_at(1)
	var diagnostics: Array[Dictionary] = _completed_report.diagnostics()
	for index: int in range(diagnostics.size()):
		lines.append(tr("Validation %d: %s") % [
			index + 1,
			_validation_diagnostic_text(String(diagnostics[index].get("reason_code", ""))),
		])
	_results_copy.text = "\n".join(lines)
	_configure_semantic_locate_action()
	_defer_results_focus_if_current_target_is_inactive(prior_results_focus)


func _validation_diagnostic_text(reason_code: String) -> String:
	match reason_code:
		"MISSING_START":
			return tr("Add a Start node before running.")
		"MULTIPLE_START":
			return tr("Keep exactly one Start node before running.")
		"MISSING_REQUIRED_CONNECTION":
			return tr("Complete the required connection before running.")
		"UNREACHABLE_NODE":
			return tr("Connect this node to the runnable graph before running.")
		"ILLEGAL_DATA_CYCLE":
			return tr("Remove the data cycle before running.")
		"REPEAT_BODY_EXIT":
			return tr("Repair the Repeat body exit before running.")
		"REPEAT_OUTSIDE_CONTINUE":
			return tr("Move Continue into its Repeat body before running.")
		"REPEAT_BODY_TO_IN":
			return tr("Repair the connection into the Repeat body before running.")
		"REPEAT_CROSSED_REGION":
			return tr("Repair the connection across Repeat regions before running.")
		"ILLEGAL_EXECUTION_CYCLE":
			return tr("Remove the execution cycle before running.")
	return tr("Repair the graph validation problem before running.")


func _render_no_completed_report(prior_results_focus: Control) -> void:
	_selected_result_index = -1
	_result_case_select.visible = false
	_result_case_select.disabled = true
	_results_cards_scroll.visible = false
	_results_message_scroll.visible = true
	_results_copy.text = tr("Day %d • %s\nNo run has been requested.") % [_current_day_index, _current_task_title]
	_set_inspect_unavailable(tr("No accepted result detail is available."))
	_defer_results_focus_if_current_target_is_inactive(prior_results_focus)


func _count_passed_cases(cases: Array[CourseworkCaseResult]) -> int:
	var passed_count: int = 0
	for case_result: CourseworkCaseResult in cases:
		if case_result.case_pass():
			passed_count += 1
	return passed_count


func _render_result_cases(
	cases: Array[CourseworkCaseResult], summary: String
) -> Array[String]:
	var lines: Array[String] = [summary]
	for index: int in range(cases.size()):
		var case_result: CourseworkCaseResult = cases[index]
		var selector_status: String = \
			tr("Passed") if case_result.case_pass() else tr("Failed")
		var result_status: String = \
			tr("PASS") if case_result.case_pass() else tr("FAIL")
		var task_case_count: int = maxi(_current_case_labels.size(), cases.size())
		var case_identity := tr("Day %d • %s — Case %d of %d — %s") % [
			_current_day_index, _current_task_title, index + 1, task_case_count, _case_label(index)]
		# The cards retain the complete task-owned public-case identity. The
		# selector keeps its established concise ordinal/outcome text so it cannot
		# set a two-pane minimum width larger than its owning ResultsPane.
		_result_case_select.add_item(tr("Case %d: %s") % [index + 1, selector_status])
		lines.append(tr("%s: %s") % [case_identity, result_status])
		var reason := ""
		if not case_result.case_pass():
			reason = _player_safe_owner_text(
				String(case_result.to_dictionary().get("ordinary_failure_reason", "")),
				tr("The owner reported that this case did not complete.")
			)
			if not reason.is_empty():
				lines.append(tr("Reason: %s") % reason)
		var trace_summary: String = _player_safe_trace_summary(case_result.trace())
		lines.append(tr("Trace: %s") % trace_summary)
		_add_result_card(index + 1, case_result.case_pass(), reason, trace_summary)
	return lines


func _case_label(index: int) -> String:
	if index >= 0 and index < _current_case_labels.size() and not _current_case_labels[index].is_empty():
		return _current_case_labels[index]
	return tr("Public case %d") % (index + 1)


func _player_safe_trace_summary(trace: Array[Dictionary]) -> String:
	if trace.is_empty():
		return tr("No accepted steps are available.")
	var steps: Array[String] = []
	for index: int in range(trace.size()):
		var entry: Dictionary = trace[index]
		steps.append(tr("%d. %s") % [
			int(entry.get("step_number", index + 1)),
			_player_safe_owner_text(String(entry.get("reason", "")), tr("Accepted trace step.")),
		])
	return " ".join(steps)


func _finalize_result_selection(cases: Array[CourseworkCaseResult]) -> void:
	_result_case_select.visible = not cases.is_empty()
	_result_case_select.disabled = cases.is_empty()
	if _selected_result_index < 0 or _selected_result_index >= cases.size():
		_selected_result_index = 0 if not cases.is_empty() else -1
	if _selected_result_index >= 0:
		_result_case_select.select(_selected_result_index)


func _refresh_inspect_admission() -> void:
	if not _selected_result_has_accepted_detail():
		_set_inspect_unavailable(tr("No accepted detail is available for this result."))
		return
	_clear_status_marker(_inspect_button)
	_inspect_button.disabled = false
	_inspect_button.text = tr("Inspect")
	_inspect_button.tooltip_text = tr("Open Case %d as a read-only snapshot") % (_selected_result_index + 1)
	if _results_copy.text.find(tr("Inspect unavailable:")) >= 0:
		_results_copy.text = _results_copy.text.split("\nInspect unavailable:")[0]


func _configure_semantic_locate_action() -> void:
	if _semantic_diagnostic_node_target().is_empty():
		_set_inspect_unavailable(tr("No graph node is available to locate for these validation diagnostics."))
		return
	_clear_status_marker(_inspect_button)
	_inspect_button.disabled = false
	_inspect_button.text = tr("Locate")
	_inspect_button.tooltip_text = tr("Focus the affected graph node")
	_inspect_button.alignment = HORIZONTAL_ALIGNMENT_CENTER


func _semantic_diagnostic_node_target() -> StringName:
	if _completed_report == null or _completed_report.validation_pass():
		return &""
	var panel := _current_authoring_panel()
	if panel == null:
		return &""
	for diagnostic: Dictionary in _completed_report.diagnostics():
		if String(diagnostic.get("entity_kind", "")) != "node":
			continue
		var node_id := StringName(String(diagnostic.get("primary_entity_id", "")))
		if node_id.is_empty():
			continue
		if panel.has_accepted_node(node_id):
			return node_id
	return &""


func _locate_semantic_diagnostic_node() -> void:
	var node_id := _semantic_diagnostic_node_target()
	var panel := _current_authoring_panel()
	if node_id.is_empty() or panel == null:
		_configure_semantic_locate_action()
		_defer_results_focus_if_current_target_is_inactive()
		return
	if _pane_mode == ONE_PANE:
		_view_tabs.select(0)
		_on_view_tab_selected(0)
		get_tree().process_frame.connect(
			_complete_semantic_diagnostic_node_locate.bind(node_id), CONNECT_ONE_SHOT)
		return
	_complete_semantic_diagnostic_node_locate(node_id)


func _complete_semantic_diagnostic_node_locate(node_id: StringName) -> void:
	var panel := _current_authoring_panel()
	if panel == null or not panel.focus_accepted_node(node_id):
		_configure_semantic_locate_action()
		_defer_results_focus_if_current_target_is_inactive()
		return
	_editor_status.text = tr("Located the affected graph node.")


func _current_results_focus_target() -> Control:
	var focused := get_viewport().gui_get_focus_owner() as Control
	return focused if focused != null and _is_results_focus_target(focused) else null


func _defer_results_focus_if_current_target_is_inactive(prior_target: Control = null) -> void:
	var target: Control = prior_target if prior_target != null else _current_results_focus_target()
	if target == null or _is_focus_target(target):
		return
	_restore_results_focus_deferred.call_deferred()


func _is_results_focus_target(target: Control) -> bool:
	return target == _result_case_select or target == _inspect_button \
		or _results_cards.is_ancestor_of(target)


func _restore_results_focus_deferred() -> void:
	if _is_focus_target(_results_heading):
		_results_heading.grab_focus()
		return
	if _is_focus_target(_workspace_heading):
		_workspace_heading.grab_focus()


func _set_inspect_unavailable(reason: String) -> void:
	_inspect_button.disabled = true
	_inspect_button.text = tr("Inspect")
	_inspect_button.tooltip_text = reason
	_inspect_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_set_control_status_marker(_inspect_button, Rect2(22, 22, 16, 16))
	if _inspect_pane.visible:
		_close_inspect()
	_inspect_rail_scroll.visible = false
	_inspect_copy.visible = true
	_inspect_copy.text = tr("Inspect unavailable: %s") % reason


func _selected_result_has_accepted_detail() -> bool:
	if _completed_report == null:
		return false
	var cases: Array[CourseworkCaseResult] = _completed_report.case_results()
	if _selected_result_index < 0 or _selected_result_index >= cases.size():
		return false
	var result: CourseworkCaseResult = cases[_selected_result_index]
	return not result.trace().is_empty() or _accepted_sandbox_by_case.has(result.case_id())


func _open_inspect() -> bool:
	if _substate != EDITOR_APP or not _selected_result_has_accepted_detail():
		return false
	var focused := get_viewport().gui_get_focus_owner()
	_inspect_origin = focused as Control if focused is Control and _is_focus_target(focused as Control) else _result_case_select
	if _pane_mode == ONE_PANE:
		_view_tabs.select(2)
		_on_view_tab_selected(2)
	_inspect_pane.visible = true
	_apply_pane_mode(_effective_width())
	_render_selected_inspect_detail()
	_restore_focus_deferred.call_deferred(_inspect_close)
	return true


func _render_selected_inspect_detail() -> void:
	_clear_sandbox_inspect_projection()
	_clear_container(_inspect_rail)
	if _completed_report == null:
		_render_missing_inspect_detail()
		return
	var result: CourseworkCaseResult = _completed_report.case_results()[_selected_result_index]
	_inspect_heading.text = tr("Case %d details") % (_selected_result_index + 1)
	_inspect_copy.visible = false
	_inspect_rail_scroll.visible = true
	var legacy_lines: Array[String] = _render_inspect_outcome(result)
	_append_inspect_trace(result, legacy_lines)
	_append_inspect_selected_result(result)
	_append_inspect_diagnostic(result, legacy_lines)
	_append_inspect_sandbox(result, legacy_lines)
	_inspect_copy.text = "\n".join(legacy_lines)


func _render_missing_inspect_detail() -> void:
	_inspect_rail_scroll.visible = false
	_inspect_copy.visible = true
	_inspect_copy.text = tr("Inspect unavailable: No accepted result detail is available.")


func _render_inspect_outcome(result: CourseworkCaseResult) -> Array[String]:
	var outcome: String = tr("Passed") if result.case_pass() else tr("Failed")
	var legacy_lines: Array[String] = [
		tr("Outcome: %s") % outcome,
		tr("This is a read-only snapshot. No simulation is running."),
	]
	_add_inspect_section(tr("Snapshot boundary"), tr("Read-only accepted data. No simulation is running."), SIGNAL_CYAN)
	return legacy_lines


func _append_inspect_selected_result(result: CourseworkCaseResult) -> void:
	var outcome: String = tr("Passed") if result.case_pass() else tr("Failed")
	_add_inspect_section(
		tr("Selected result"), tr("Case %d  %s") % [_selected_result_index + 1, outcome],
		PASS_GREEN if result.case_pass() else FAULT_CORAL)


func _append_inspect_diagnostic(
	result: CourseworkCaseResult, legacy_lines: Array[String]
) -> void:
	if not result.case_pass():
		var failure_reason: String = _player_safe_owner_text(
			String(result.to_dictionary().get("ordinary_failure_reason", "")),
			tr("The owner reported that this case did not complete.")
		)
		if not failure_reason.is_empty():
			_add_inspect_section(tr("Accepted diagnostic"), failure_reason, FAULT_CORAL)
			legacy_lines.append(tr("What went wrong: %s") % failure_reason)


func _append_inspect_trace(
	result: CourseworkCaseResult, legacy_lines: Array[String]
) -> void:
	var trace: Array[Dictionary] = result.trace()
	if trace.is_empty():
		_add_inspect_section(tr("Ordered step rail"), tr("No accepted steps are available."), SLATE)
		legacy_lines.append(tr("Steps recorded by the run: No accepted steps are available."))
	else:
		legacy_lines.append(tr("Steps recorded by the run:"))
		for trace_index: int in range(trace.size()):
			var trace_entry: Dictionary = trace[trace_index]
			var step_number: int = int(trace_entry.get("step_number", trace_index + 1))
			var descriptor: String = _player_safe_owner_text(
				String(trace_entry.get("reason", "")), tr("Accepted trace step."))
			_add_inspect_step(step_number, descriptor, trace_index)
			legacy_lines.append(tr("Step %d: %s") % [step_number, descriptor])


func _append_inspect_sandbox(
	result: CourseworkCaseResult, legacy_lines: Array[String]
) -> void:
	var state: SandboxCaseState = _accepted_sandbox_by_case.get(
		result.case_id(), null) as SandboxCaseState
	if state == null or not state.is_valid():
		_add_inspect_section(tr("Available Sandbox"), tr("No accepted Sandbox detail is available."), SLATE)
		legacy_lines.append(tr("Sandbox when this case ended: No accepted Sandbox detail is available."))
	else:
		_add_inspect_section(tr("Available Sandbox"), tr("Accepted read-only snapshot."), SIGNAL_CYAN)
		legacy_lines.append(tr("Sandbox when this case ended:"))
		_sandbox_inspect_projection = _create_sandbox_inspect_projection()
		if _sandbox_inspect_projection == null:
			_add_inspect_section(tr("Snapshot status"), tr("The accepted Sandbox projection is unavailable."), SLATE)
			legacy_lines.append(tr("The accepted Sandbox projection is unavailable."))
		else:
			_sandbox_frame.visible = true
			_sandbox_frame_title.text = tr("SANDBOX • READ-ONLY")
			_sandbox_legend.text = tr("READ-ONLY • STATIC")
			_sandbox_inspect_host.add_child(_sandbox_inspect_projection)
			_sandbox_inspect_projection.call(&"show_accepted_state", state)
			_configure_sandbox_inspect_crop(_sandbox_inspect_projection)


func _add_results_summary(summary: String) -> void:
	var panel := PanelContainer.new()
	panel.name = "FrozenSuiteSummary"
	panel.add_theme_stylebox_override(&"panel", _make_pixel_style(SLATE, EVIDENCE_AMBER, 2))
	# Keep the summary vertically reflowable. A horizontal row lets its long
	# localized label set the ScrollContainer's minimum width and can force the
	# ResultsLayout outside a narrow two-pane surface.
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 4)
	panel.add_child(content)
	if _completed_report_is_out_of_date:
		content.add_child(_make_status_marker(Rect2(42, 2, 16, 16)))
	var label := Label.new()
	label.text = tr("FROZEN SUITE SUMMARY  •  %s") % summary
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override(&"font_color", PAPER)
	label.add_theme_font_size_override(&"font_size", 16)
	content.add_child(label)
	_results_cards.add_child(panel)


func _add_result_card(
	case_number: int, case_passed: bool, failure_reason: String, trace_summary: String
) -> void:
	var outcome_color: Color = PASS_GREEN if case_passed else FAULT_CORAL
	var card := PanelContainer.new()
	card.name = "ResultCard%d" % case_number
	card.add_theme_stylebox_override(
		&"panel", _make_pixel_style(Color(0.055, 0.075, 0.105, 1.0), outcome_color, 2))
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 6)
	card.add_child(content)
	var title := Label.new()
	title.text = tr("CASE %d") % case_number
	title.add_theme_color_override(&"font_color", PAPER)
	title.add_theme_font_size_override(&"font_size", 14)
	content.add_child(title)
	var outcome := Label.new()
	var glyph: String = "[+]" if case_passed else "[X]"
	outcome.text = tr("%s  %s") % [glyph, tr("PASS") if case_passed else tr("FAIL")]
	outcome.add_theme_color_override(&"font_color", outcome_color)
	outcome.add_theme_font_size_override(&"font_size", 18)
	var outcome_row := HBoxContainer.new()
	outcome_row.name = "OutcomeRow"
	outcome_row.add_theme_constant_override(&"separation", 8)
	outcome_row.add_child(_make_status_marker(
		Rect2(2, 2, 16, 16) if case_passed else Rect2(22, 2, 16, 16)))
	outcome_row.add_child(outcome)
	content.add_child(outcome_row)
	if not case_passed and not failure_reason.is_empty():
		var reason_panel := PanelContainer.new()
		reason_panel.name = "FailureReason"
		reason_panel.add_theme_stylebox_override(
			&"panel", _make_pixel_style(Color(0.16, 0.075, 0.09, 1.0), FAULT_CORAL, 2))
		var reason := Label.new()
		reason.text = failure_reason
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason.add_theme_color_override(&"font_color", PAPER)
		reason.add_theme_font_size_override(&"font_size", 14)
		reason_panel.add_child(reason)
		content.add_child(reason_panel)
	var trace := Label.new()
	trace.text = tr("TRACE  %s") % trace_summary
	trace.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trace.add_theme_color_override(&"font_color", PAPER)
	trace.add_theme_font_size_override(&"font_size", 13)
	content.add_child(trace)
	_results_cards.add_child(card)


func _add_inspect_section(title_text: String, body_text: String, accent: Color) -> void:
	var panel := PanelContainer.new()
	panel.name = "Inspect%s" % title_text.replace(" ", "")
	panel.add_theme_stylebox_override(&"panel", _make_pixel_style(Color(0.06, 0.07, 0.105, 1.0), accent, 2))
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 3)
	panel.add_child(content)
	var title := Label.new()
	title.text = title_text.to_upper()
	title.add_theme_color_override(&"font_color", accent)
	title.add_theme_font_size_override(&"font_size", 13)
	content.add_child(title)
	var body := Label.new()
	body.text = body_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override(&"font_color", PAPER)
	body.add_theme_font_size_override(&"font_size", 15)
	content.add_child(body)
	_inspect_rail.add_child(panel)


func _add_inspect_step(step_number: int, descriptor: String, trace_index: int) -> void:
	var panel := PanelContainer.new()
	panel.name = "OrderedStep%d" % trace_index
	panel.add_theme_stylebox_override(&"panel", _make_pixel_style(Color(0.05, 0.09, 0.11, 1.0), SIGNAL_CYAN, 2))
	var content := HBoxContainer.new()
	content.name = "TraceMarkersAndText"
	content.add_theme_constant_override(&"separation", 6)
	content.add_child(_make_trace_marker("TraceMarker", Rect2(2, 22, 16, 16)))
	content.add_child(_make_trace_marker("DirectionMarker", Rect2(22, 22, 16, 16)))
	var label := Label.new()
	label.text = tr("[%02d]  %s") % [step_number, descriptor]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override(&"font_color", PAPER)
	label.add_theme_font_size_override(&"font_size", 14)
	content.add_child(label)
	panel.add_child(content)
	_inspect_rail.add_child(panel)


func _clear_container(container: Container) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.free()


## Enlarges the accepted Sandbox-only composition without changing its record or child ownership.
func _configure_sandbox_inspect_crop(projection: Control) -> void:
	for optional_layer_path: NodePath in [
		^"FarCompanyLayer", ^"MidCompanyLayer", ^"NearWorkstationLayer", ^"MonitorContent",
	]:
		var optional_layer := projection.get_node_or_null(optional_layer_path) as Control
		if optional_layer != null:
			optional_layer.visible = false
	var sandbox_content := projection.get_node_or_null(^"SandboxContent") as Control
	if sandbox_content == null:
		return
	var world_rect: Rect2 = projection.call(&"sandbox_world_rect") \
		if projection.has_method(&"sandbox_world_rect") else Rect2(Vector2.ZERO, sandbox_content.size)
	if not world_rect.has_area():
		world_rect = Rect2(Vector2.ZERO, sandbox_content.size)
	var internal_legend := sandbox_content.get_node_or_null(^"EntityLegend") as Control
	if internal_legend != null:
		internal_legend.visible = false
	sandbox_content.size = world_rect.size
	var crop_size: Vector2 = world_rect.size
	var host_size: Vector2 = _sandbox_inspect_host.size
	if crop_size.x <= 0.0 or crop_size.y <= 0.0 or host_size.x <= 0.0 or host_size.y <= 0.0:
		return
	var crop_scale: float = minf(host_size.x / crop_size.x, host_size.y / crop_size.y)
	# Keep the full accepted snapshot legible at a whole-pixel scale. Rounding
	# down would make a 1.x fit scale too small to satisfy the available height.
	var integer_scale: int = maxi(1, ceili(crop_scale))
	projection.pivot_offset = Vector2.ZERO
	projection.scale = Vector2.ONE * float(integer_scale)
	projection.position = ((host_size - crop_size * float(integer_scale)) * 0.5 \
		- (sandbox_content.position + world_rect.position) * float(integer_scale)).round()


func _on_sandbox_inspect_host_resized() -> void:
	if _sandbox_inspect_projection != null and is_instance_valid(_sandbox_inspect_projection):
		_configure_sandbox_inspect_crop.call_deferred(_sandbox_inspect_projection)


func _close_inspect() -> void:
	if not _inspect_pane.visible:
		return
	_inspect_pane.visible = false
	_clear_sandbox_inspect_projection()
	var origin: Control = _inspect_origin
	_inspect_origin = null
	_restore_inspect_focus_deferred.call_deferred(origin)


func _restore_inspect_focus_deferred(origin: Control) -> void:
	if _is_focus_target(origin):
		origin.grab_focus()
		return
	if _is_focus_target(_results_heading):
		_results_heading.grab_focus()
		return
	if _is_focus_target(_workspace_heading):
		_workspace_heading.grab_focus()


func _clear_sandbox_inspect_projection() -> void:
	if _sandbox_inspect_projection != null and is_instance_valid(_sandbox_inspect_projection):
		_sandbox_inspect_host.remove_child(_sandbox_inspect_projection)
		_sandbox_inspect_projection.free()
	_sandbox_inspect_projection = null
	_sandbox_frame.visible = false
	_sandbox_frame_title.text = ""
	_sandbox_legend.text = ""


func _create_sandbox_inspect_projection() -> Control:
	var projection := (
		_sandbox_inspect_projection_factory.call() as Control
		if _sandbox_inspect_projection_factory.is_valid()
		else SandboxVisualProjectionScene.instantiate() as Control
	)
	if projection == null or not projection.has_method(&"show_accepted_state"):
		if projection != null:
			projection.free()
		return null
	return projection


func _player_safe_owner_text(value: String, fallback: String) -> String:
	var lowered_value: String = value.to_lower()
	var forbidden_fragments: Array[String] = [
		"\n", "\r", "\t", "res://", "user://", "://", ":\\", "\\",
		"{", "}", "<", ">", "=", "\"", "stack", "traceback",
		"payload", "protocol", "serializ", ".gd:", ".tscn:", ".tres:", ".cs:",
		".cpp:",
	]
	for fragment: String in forbidden_fragments:
		if lowered_value.contains(fragment):
			return fallback
	var player_text: String = value.strip_edges()
	if player_text.is_empty():
		return ""
	if _contains_engine_path_token(player_text) \
		or _contains_internal_identifier_token(player_text):
		return fallback
	return player_text


func _contains_engine_path_token(value: String) -> bool:
	const EDGE_PUNCTUATION := ".,!?;()'"
	const ENGINE_ROOTS: Array[String] = [
		"addons", "assets", "engine", "res:", "src", "tests", "user:",
	]
	for raw_token: String in value.to_lower().split(" ", false):
		var token: String = raw_token
		while not token.is_empty() and EDGE_PUNCTUATION.contains(token.left(1)):
			token = token.substr(1)
		while not token.is_empty() and EDGE_PUNCTUATION.contains(token.right(1)):
			token = token.left(token.length() - 1)
		if token.begins_with("/") or token.begins_with("./") \
			or token.begins_with("../") or token.count("/") > 1:
			return true
		if token.length() >= 3:
			var first_code: int = token.unicode_at(0)
			var drive_letter: bool = (first_code >= 65 and first_code <= 90) \
				or (first_code >= 97 and first_code <= 122)
			if drive_letter and token.substr(1, 2) == ":/":
				return true
		var slash_index: int = token.find("/")
		if slash_index > 0 and ENGINE_ROOTS.has(token.left(slash_index)):
			return true
	return false


func _contains_internal_identifier_token(value: String) -> bool:
	const EDGE_PUNCTUATION := ".,!?;()'[]"
	for raw_token: String in value.split(" ", false):
		var token: String = raw_token
		while not token.is_empty() and EDGE_PUNCTUATION.contains(token.left(1)):
			token = token.substr(1)
		while not token.is_empty() and EDGE_PUNCTUATION.contains(token.right(1)):
			token = token.left(token.length() - 1)
		if token.begins_with("case.") or token.begins_with("raw_") \
			or token.begins_with("assert_") or token.begins_with("node_"):
			return true
	return false


func _apply_responsive_layout() -> void:
	_apply_workstation_environment_layout()
	_apply_wallpaper_integer_layout()
	_apply_editor_window_layout()
	_apply_pane_mode(_effective_width())
	if _sandbox_inspect_projection != null and is_instance_valid(_sandbox_inspect_projection):
		_configure_sandbox_inspect_crop.call_deferred(_sandbox_inspect_projection)


func _apply_workstation_environment_layout() -> void:
	if _workstation_view.size.x <= 0.0:
		return
	var origin_x := floorf(maxf(0.0, (_workstation_view.size.x - WORKSTATION_COMPOSITION_SIZE.x) * 0.5))
	var composition_origin := Vector2(origin_x, 0.0)
	for layer: TextureRect in [_environment_far, _environment_mid, _environment_near]:
		layer.position = composition_origin
		layer.size = WORKSTATION_COMPOSITION_SIZE
		layer.scale = Vector2.ONE
		layer.rotation = 0.0
	_monitor_aperture.position = composition_origin + MONITOR_APERTURE_LOCAL_POSITION
	_computer_target.position = composition_origin + COMPUTER_TARGET_LOCAL_POSITION


func _apply_editor_window_layout() -> void:
	const NATIVE_EDITOR_SIZE := Vector2(1024.0, 576.0)
	_editor_app.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_editor_app.size = NATIVE_EDITOR_SIZE
	_editor_app.position = Vector2(
		maxf(0.0, floorf((size.x - NATIVE_EDITOR_SIZE.x) * 0.5)),
		maxf(0.0, floorf((size.y - NATIVE_EDITOR_SIZE.y) * 0.5)))
	_native_window_frame.position = Vector2.ZERO
	_native_window_frame.size = NATIVE_EDITOR_SIZE
	_native_window_frame.scale = Vector2.ONE
	_native_window_frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_native_window_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_native_window_frame.stretch_mode = TextureRect.STRETCH_KEEP
	_editor_back.custom_minimum_size = EDITOR_BACK_SIZE
	_apply_save_recovery_layout()


func _apply_save_recovery_layout() -> void:
	if _save_header_action == null or _save_overlay_panel == null:
		return
	_save_header_action.custom_minimum_size = SAVE_HEADER_SIZE
	_save_overlay_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var available_size := _editor_app.size - Vector2.ONE * (SAVE_OVERLAY_SAFE_MARGIN * 2.0)
	var panel_size := Vector2(
		minf(SAVE_OVERLAY_PANEL_SIZE.x, available_size.x),
		minf(SAVE_OVERLAY_PANEL_SIZE.y, available_size.y))
	_save_overlay_panel.size = panel_size
	_save_overlay_panel.position = ((_editor_app.size - panel_size) * 0.5).floor()


func _apply_wallpaper_integer_layout() -> void:
	if _desktop_wallpaper == null:
		return
	const NATIVE_SIZE := Vector2(640.0, 360.0)
	var host_size := _desktop_view.size
	if host_size.x <= 0.0 or host_size.y <= 0.0:
		return
	var integer_scale: int = maxi(1, floori(minf(host_size.x / NATIVE_SIZE.x, host_size.y / NATIVE_SIZE.y)))
	_desktop_wallpaper.size = NATIVE_SIZE
	_desktop_wallpaper.scale = Vector2.ONE * float(integer_scale)
	_desktop_wallpaper.position = ((host_size - NATIVE_SIZE * float(integer_scale)) * 0.5).round()


func _effective_width() -> float:
	return get_viewport().get_visible_rect().size.x / maxf(get_window().content_scale_factor, 0.01)


func _apply_pane_mode(effective_width: float) -> void:
	if effective_width >= 1440.0:
		_pane_mode = THREE_PANE
	elif effective_width >= 960.0:
		_pane_mode = TWO_PANE
	else:
		_pane_mode = ONE_PANE
	if _pane_mode == ONE_PANE and _inspect_pane.visible:
		_view_tabs.select(2)
	_view_tabs.visible = _pane_mode == ONE_PANE
	_graph_pane.visible = _pane_mode != ONE_PANE or _view_tabs.selected == 0
	_requirements_pane.visible = _pane_mode != ONE_PANE or _view_tabs.selected == 1
	_results_pane.visible = _pane_mode != ONE_PANE or _view_tabs.selected == 2
	if _pane_mode == THREE_PANE:
		_set_pane_rect(_graph_pane, 24.0, 112.0, 0.45, EDITOR_STATUS_BAND_BOTTOM)
		_set_pane_rect(_requirements_pane, 0.47, 112.0, 0.71, EDITOR_STATUS_BAND_BOTTOM)
		_set_pane_rect(_results_pane, 0.73, 112.0, 0.98, EDITOR_STATUS_BAND_BOTTOM)
		_set_pane_rect(_inspect_pane, 0.73, 96.0, 0.98, EDITOR_STATUS_BAND_BOTTOM)
	elif _pane_mode == TWO_PANE:
		_set_pane_rect(_graph_pane, 24.0, 112.0, 0.58, EDITOR_STATUS_BAND_BOTTOM)
		_set_pane_rect(_requirements_pane, 0.60, 112.0, 0.98, 0.30)
		_set_pane_rect(_results_pane, 0.60, 0.32, 0.98, EDITOR_STATUS_BAND_BOTTOM)
		_set_pane_rect(_inspect_pane, 0.60, 96.0, 0.98, EDITOR_STATUS_BAND_BOTTOM)
	else:
		_set_pane_rect(_graph_pane, 24.0, 156.0, 0.98, ONE_PANE_STATUS_BAND_BOTTOM)
		_set_pane_rect(_requirements_pane, 24.0, 156.0, 0.98, ONE_PANE_STATUS_BAND_BOTTOM)
		_set_pane_rect(_results_pane, 24.0, 156.0, 0.98, ONE_PANE_STATUS_BAND_BOTTOM)
		_set_pane_rect(_inspect_pane, 24.0, 156.0, 0.98, ONE_PANE_STATUS_BAND_BOTTOM)
	_apply_inspect_content_layout()
	_apply_graph_action_layout()
	_apply_requirements_content_layout()
	_apply_results_content_layout()


func _apply_inspect_content_layout() -> void:
	if _pane_mode == ONE_PANE:
		_apply_compact_inspect_layout()
		return
	_apply_standard_inspect_layout()


func _apply_graph_action_layout() -> void:
	const ACTION_TOP := 8.0
	const ACTION_HEIGHT := 44.0
	const ACTION_GAP := 22.0
	const PRIMARY_WIDTH := 220.0
	const RUN_WIDTH := 168.0
	var primary_left: float = _graph_pane.size.x - 12.0 - PRIMARY_WIDTH
	var run_left: float = primary_left - ACTION_GAP - RUN_WIDTH
	_graph_primary_action.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_graph_primary_action.position = Vector2(roundf(primary_left), ACTION_TOP)
	_graph_primary_action.size = Vector2(PRIMARY_WIDTH, ACTION_HEIGHT)
	_graph_run_action.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_graph_run_action.position = Vector2(roundf(run_left), ACTION_TOP)
	_graph_run_action.size = Vector2(RUN_WIDTH, ACTION_HEIGHT)


func _apply_requirements_content_layout() -> void:
	if _pane_mode == TWO_PANE:
		_requirements_heading.hide()
		_requirements_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_requirements_scroll.offset_left = 12.0
		_requirements_scroll.offset_top = 8.0
		_requirements_scroll.offset_right = -12.0
		_requirements_scroll.offset_bottom = -8.0
		return
	_requirements_heading.show()
	_requirements_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_requirements_scroll.offset_left = 16.0
	_requirements_scroll.offset_top = 58.0
	_requirements_scroll.offset_right = -16.0
	_requirements_scroll.offset_bottom = -16.0


func _apply_results_content_layout() -> void:
	# ResultsLayout owns the heading, content, and footer relationship in every pane mode.
	# Force its parent-owned available rect after a pane reflow so long card content
	# becomes scrollable rather than expanding the results surface beyond its pane.
	_results_layout.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_results_layout.position = Vector2(16.0, 12.0)
	_results_layout.size = Vector2(
		maxf(0.0, _results_pane.size.x - 32.0),
		maxf(0.0, _results_pane.size.y - 26.0))


func _apply_compact_inspect_layout() -> void:
	_set_inspect_rect(_inspect_close, 1.0, 1.0, 0.0, -116.0, 10.0, -16.0, 54.0)
	_inspect_close.size = INSPECT_CLOSE_SIZE
	_set_inspect_rect(_inspect_copy, 0.0, 0.36, 1.0, 16.0, 64.0, -8.0, -8.0)
	_set_inspect_rect(_inspect_rail_scroll, 0.0, 0.36, 1.0, 16.0, 64.0, -8.0, -8.0)
	_set_inspect_rect(_sandbox_frame, 0.38, 1.0, 1.0, 0.0, 20.0, -16.0, -8.0)
	_set_inspect_rect(_sandbox_inspect_host, 0.38, 1.0, 1.0, 10.0, 52.0, -26.0, -52.0)
	_sandbox_legend.offset_top = -28.0
	_sandbox_legend.offset_bottom = 0.0


func _apply_standard_inspect_layout() -> void:
	_set_inspect_rect(_inspect_copy, 0.0, 1.0, 0.0, 16.0, 56.0, -16.0, 188.0)
	_set_inspect_rect(_inspect_rail_scroll, 0.0, 1.0, 0.0, 16.0, 56.0, -16.0, 188.0)
	_set_inspect_rect(_sandbox_frame, 0.0, 1.0, 1.0, 16.0, 192.0, -16.0, -16.0)
	_set_inspect_rect(_sandbox_inspect_host, 0.0, 1.0, 1.0, 26.0, 227.0, -26.0, -62.0)
	_sandbox_legend.offset_top = -44.0
	_sandbox_legend.offset_bottom = -4.0


func _set_inspect_rect(
		control: Control, left_anchor: float, right_anchor: float, bottom_anchor: float,
		left: float, top: float, right: float, bottom: float) -> void:
	control.anchor_left = left_anchor
	control.anchor_right = right_anchor
	control.anchor_top = 0.0
	control.anchor_bottom = bottom_anchor
	control.offset_left = left
	control.offset_top = top
	control.offset_right = right
	control.offset_bottom = bottom


func _set_pane_rect(pane: Control, left: float, top: float, right: float, bottom: float) -> void:
	pane.anchor_left = left if left <= 1.0 else 0.0
	pane.anchor_right = right if right <= 1.0 else 1.0
	pane.anchor_top = top if top >= 0.0 and top <= 1.0 else 0.0
	pane.anchor_bottom = bottom if bottom >= 0.0 and bottom <= 1.0 else 1.0
	pane.offset_left = left if left > 1.0 else 0.0
	pane.offset_top = top if top > 1.0 or top < 0.0 else 0.0
	pane.offset_right = right if right > 1.0 else 0.0
	pane.offset_bottom = bottom if bottom > 1.0 or bottom < 0.0 else 0.0


func _is_focus_target(target: Control) -> bool:
	if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
		return false
	if target.get_focus_mode_with_override() == Control.FOCUS_NONE:
		return false
	return not (target is BaseButton and (target as BaseButton).disabled)


func _count_named_buttons(target_name: StringName) -> int:
	var count: int = 0
	for node: Node in find_children("*", "Button", true, false):
		if node.name == target_name:
			count += 1
	return count


func _set_player_text() -> void:
	_workstation_title.text = tr("Company Workstation")
	_computer_prompt.text = tr("Open Workstation  [Enter / Space]")
	_preview_icon_mark.text = tr("E")
	_preview_icon_label.text = tr("Editor")
	_preview_editor_label.text = tr("EDITOR")
	_desktop_title.text = tr("COMPANY OS  •  WORKSTATION 01")
	_desktop_back.text = tr("Back to Workstation")
	_icon_text.text = tr("EDITOR")
	_desktop_hint.text = tr("Right-click wallpaper: Back to Workstation")
	_desktop_status.text = tr("1 assignment ready\nOpen Editor to continue Day 1.")
	_workspace_heading.text = tr("Coursework Editor  •  Day 1 Assignment")
	_editor_back.text = tr("Close Editor")
	_save_header_action.text = tr("Save")
	_graph_heading.text = tr("Graph")
	_graph_run_action.text = tr("Run Case (F5)")
	_graph_primary_action.text = tr("Request Graph Edit")
	_requirements_heading.text = tr("Requirements")
	_requirements_copy.text = tr("Task requirements are shown here when accepted by the task owner.")
	_results_heading.text = tr("Results")
	_results_copy.text = tr("No run has been requested.")
	_result_case_select.tooltip_text = tr("Select an accepted result")
	_inspect_button.text = tr("Inspect")
	_inspect_heading.text = tr("Inspect")
	_inspect_copy.text = tr("Inspect unavailable: No accepted result detail is available.")
	_inspect_close.text = tr("Back")
	_inspect_close.tooltip_text = tr("Back to Results")
	_sandbox_frame_title.text = tr("SANDBOX • READ-ONLY")
	_sandbox_legend.text = tr("READ-ONLY • STATIC")
	_editor_status.text = tr("Ready to edit the accepted graph.")


func _apply_focus_styles() -> void:
	_style_computer_target()
	_style_button(_desktop_back, Color(0.08, 0.24, 0.29, 1), Color(0.92, 0.96, 0.72, 1))
	_style_button(_editor_icon, Color(0.08, 0.3, 0.38, 1), Color(0.92, 0.96, 0.72, 1))
	_style_header_button(_editor_back, Color(0.09, 0.16, 0.2, 1), PAPER)
	_style_button(_graph_run_action, Color(0.06, 0.25, 0.22, 1), PAPER)
	_style_button(_graph_primary_action, Color(0.07, 0.18, 0.25, 1), SIGNAL_CYAN)
	_style_button(_inspect_button, Color(0.07, 0.16, 0.13, 1), PAPER)
	_style_button(_inspect_close, Color(0.12, 0.11, 0.18, 1), PAPER)
	_style_option_button(_result_case_select, Color(0.06, 0.11, 0.16, 1), SIGNAL_CYAN)


func _style_computer_target() -> void:
	_computer_target.add_theme_stylebox_override(&"normal", _make_target_style(Color.TRANSPARENT, 0))
	_computer_target.add_theme_stylebox_override(
		&"hover", _make_target_style(Color(0.7, 0.9, 0.9, 0.55), 1))
	_computer_target.add_theme_stylebox_override(
		&"pressed", _make_target_style(Color(0.92, 0.96, 0.72, 0.8), 1))
	_computer_target.add_theme_stylebox_override(&"focus", _make_target_style(PAPER, 2))


func _make_target_style(border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = border
	style.set_border_width_all(border_width)
	return style


func _create_delivery_action() -> void:
	_delivery_action = Button.new()
	_delivery_action.name = "SubmitBuildAction"
	_delivery_action.text = tr("Submit Build")
	_delivery_action.custom_minimum_size = Vector2(148.0, 38.0)
	_delivery_action.position = Vector2(168.0, 50.0)
	_delivery_action.focus_mode = Control.FOCUS_ALL
	_editor_app.add_child(_delivery_action)


func _create_graph_run_action() -> void:
	_graph_run_action = Button.new()
	_graph_run_action.name = "GraphRunAction"
	_graph_run_action.focus_mode = Control.FOCUS_ALL
	_graph_run_action.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_graph_run_action.custom_minimum_size = Vector2(168.0, 44.0)
	_graph_pane.add_child(_graph_run_action)
	_graph_heading.offset_right = 160.0


func _apply_pixel_presentation_styles() -> void:
	_apply_flat_panel("EditorApp/GraphPane", Color(0.045, 0.075, 0.11, 1.0), SIGNAL_CYAN, 2)
	_apply_flat_panel("EditorApp/RequirementsPane", Color(0.06, 0.075, 0.11, 1.0), SLATE, 2)
	_apply_flat_panel("EditorApp/ResultsPane", Color(0.07, 0.065, 0.09, 1.0), EVIDENCE_AMBER, 2)
	_apply_flat_panel("EditorApp/InspectPane", Color(0.045, 0.065, 0.105, 1.0), SIGNAL_CYAN, 2)
	_requirements_copy.remove_theme_stylebox_override(&"normal")
	_results_copy.add_theme_stylebox_override(
		&"normal", _make_pixel_style(Color(0.035, 0.045, 0.065, 1.0), EVIDENCE_AMBER, 2))
	_computer_prompt.add_theme_stylebox_override(
		&"normal", _make_pixel_style(Color(0.025, 0.04, 0.06, 1.0), SIGNAL_CYAN, 2))
	_editor_status.add_theme_stylebox_override(
		&"normal", _make_pixel_style(Color(0.025, 0.04, 0.06, 1.0), SIGNAL_CYAN, 2))
	_sandbox_frame.add_theme_stylebox_override(
		&"panel", _make_pixel_style(Color(0.035, 0.055, 0.08, 1.0), SIGNAL_CYAN, 2))
	_sandbox_frame_title.add_theme_color_override(&"font_color", SIGNAL_CYAN)
	_sandbox_legend.add_theme_color_override(&"font_color", PAPER)


func _style_button(button: Button, fill: Color, focus_border: Color) -> void:
	button.add_theme_stylebox_override(&"normal", _make_pixel_style(fill, SLATE, 2))
	button.add_theme_stylebox_override(&"hover", _make_pixel_style(fill, focus_border, 2))
	button.add_theme_stylebox_override(&"focus", _make_pixel_style(fill, focus_border, 2))
	button.add_theme_stylebox_override(&"pressed", _make_pixel_style(fill.darkened(0.15), focus_border, 2))
	button.add_theme_stylebox_override(&"disabled", _make_pixel_style(SLATE.darkened(0.45), SLATE, 2))


func _style_header_button(button: Button, fill: Color, focus_border: Color) -> void:
	button.add_theme_stylebox_override(&"normal", _make_header_pixel_style(fill, SLATE))
	button.add_theme_stylebox_override(&"hover", _make_header_pixel_style(fill, focus_border))
	button.add_theme_stylebox_override(&"focus", _make_header_pixel_style(fill, focus_border))
	button.add_theme_stylebox_override(&"pressed", _make_header_pixel_style(fill.darkened(0.15), focus_border))
	button.add_theme_stylebox_override(&"disabled", _make_header_pixel_style(SLATE.darkened(0.45), SLATE))


func _style_option_button(option: OptionButton, fill: Color, focus_border: Color) -> void:
	option.add_theme_stylebox_override(&"normal", _make_pixel_style(fill, SLATE, 2))
	option.add_theme_stylebox_override(&"hover", _make_pixel_style(fill, focus_border, 2))
	option.add_theme_stylebox_override(&"focus", _make_pixel_style(fill, focus_border, 2))
	option.add_theme_stylebox_override(&"pressed", _make_pixel_style(fill.darkened(0.15), focus_border, 2))
	option.add_theme_stylebox_override(&"disabled", _make_pixel_style(SLATE.darkened(0.45), SLATE, 2))
	var popup := option.get_popup()
	popup.add_theme_stylebox_override(&"panel", _make_pixel_style(fill, focus_border, 2))


func _apply_flat_panel(path: NodePath, fill: Color, border: Color, border_width: int) -> void:
	var panel := get_node_or_null(path) as Panel
	if panel != null:
		panel.add_theme_stylebox_override(&"panel", _make_pixel_style(fill, border, border_width))


func _apply_silkscreen_theme() -> void:
	if _silkscreen_regular == null or _silkscreen_bold == null:
		return
	for label: Label in [_desktop_title, _icon_text, _workspace_heading, _graph_heading, _requirements_heading, _requirements_copy, _results_heading, _results_copy, _inspect_heading, _inspect_copy, _editor_status, _sandbox_frame_title, _sandbox_legend]:
		label.add_theme_font_override(&"font", _silkscreen_regular)
	for button: Button in [_desktop_back, _editor_icon, _editor_back, _save_header_action, _graph_primary_action, _graph_run_action, _delivery_action, _inspect_button, _inspect_close]:
		button.add_theme_font_override(&"font", _silkscreen_regular)
	for heading: Label in [_workspace_heading, _graph_heading, _requirements_heading, _results_heading, _inspect_heading]:
		heading.add_theme_font_override(&"font", _silkscreen_bold)


func _load_pixel_assets() -> void:
	_action_icon_atlas = _load_pixel_texture(ACTIONS_ASSET_PATH)
	_status_marker_atlas = _load_pixel_texture(STATUS_ASSET_PATH)
	_trace_marker_atlas = _load_pixel_texture(TRACE_MARKER_ASSET_PATH)
	_desktop_wallpaper.texture = _load_pixel_texture(WALLPAPER_ASSET_PATH)
	_desktop_wallpaper.set_meta(&"asset_path", WALLPAPER_ASSET_PATH)
	_native_window_frame.set_meta(&"asset_path", EDITOR_WINDOW_ASSET_PATH)
	var editor_icon := _make_atlas_texture(
		_action_icon_atlas, ACTIONS_ASSET_PATH, Rect2(2, 2, 32, 32))
	_pixel_screen.texture = editor_icon
	_pixel_screen.set_meta(&"asset_path", ACTIONS_ASSET_PATH)
	_silkscreen_regular = FontFile.new()
	_silkscreen_regular.load_dynamic_font(SILKSCREEN_REGULAR_ASSET_PATH)
	_silkscreen_regular.set_meta(&"asset_path", SILKSCREEN_REGULAR_ASSET_PATH)
	_silkscreen_bold = FontFile.new()
	_silkscreen_bold.load_dynamic_font(SILKSCREEN_BOLD_ASSET_PATH)
	_silkscreen_bold.set_meta(&"asset_path", SILKSCREEN_BOLD_ASSET_PATH)


func _apply_action_atlas_icons() -> void:
	_set_button_action_icon(_desktop_back, Rect2(46, 10, 16, 16))
	_set_button_action_icon(_editor_back, Rect2(82, 10, 16, 16))
	_set_button_action_icon(_graph_run_action, Rect2(118, 10, 16, 16))
	_set_button_action_icon(_graph_primary_action, Rect2(154, 10, 16, 16))
	_view_tabs.set_item_icon(
		1, _make_atlas_texture(_action_icon_atlas, ACTIONS_ASSET_PATH, Rect2(190, 10, 16, 16)))
	_view_tabs.set_item_icon(
		2, _make_atlas_texture(_action_icon_atlas, ACTIONS_ASSET_PATH, Rect2(226, 10, 16, 16)))
	_set_button_action_icon(_inspect_button, Rect2(10, 46, 16, 16))
	_set_button_action_icon(_inspect_close, Rect2(46, 10, 16, 16))


func _set_button_action_icon(button: Button, region: Rect2) -> void:
	button.icon = _make_atlas_texture(_action_icon_atlas, ACTIONS_ASSET_PATH, region)
	button.expand_icon = false


func _set_control_status_marker(control: Control, region: Rect2) -> void:
	_clear_status_marker(control)
	var marker := _make_status_marker(region)
	control.add_child(marker)
	marker.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	marker.offset_left = -24.0
	marker.offset_top = -8.0
	marker.offset_right = -8.0
	marker.offset_bottom = 8.0


func _clear_status_marker(control: Control) -> void:
	var marker := control.get_node_or_null(^"StatusMarker")
	if marker != null:
		control.remove_child(marker)
		marker.free()


func _make_status_marker(region: Rect2) -> TextureRect:
	var marker := TextureRect.new()
	marker.name = "StatusMarker"
	marker.custom_minimum_size = Vector2(16, 16)
	marker.size = Vector2(16, 16)
	marker.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	marker.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	marker.texture = _make_atlas_texture(_status_marker_atlas, STATUS_ASSET_PATH, region)
	return marker


func _make_trace_marker(marker_name: String, region: Rect2) -> TextureRect:
	var marker := TextureRect.new()
	marker.name = marker_name
	marker.custom_minimum_size = Vector2(16, 16)
	marker.size = Vector2(16, 16)
	marker.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	marker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	marker.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	marker.texture = _make_atlas_texture(_trace_marker_atlas, TRACE_MARKER_ASSET_PATH, region)
	return marker


func _make_atlas_texture(
		atlas: Texture2D, asset_path: String, region: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = region
	texture.set_meta(&"asset_path", asset_path)
	return texture


func _load_pixel_texture(asset_path: String) -> Texture2D:
	var texture := load(asset_path) as Texture2D
	if texture == null:
		return null
	texture.set_meta(&"asset_path", asset_path)
	return texture


func _make_pixel_style(fill: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.anti_aliasing = false
	style.content_margin_left = 10.0
	style.content_margin_top = 8.0
	style.content_margin_right = 10.0
	style.content_margin_bottom = 8.0
	return style


func _make_header_pixel_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := _make_pixel_style(fill, border, 2)
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style
