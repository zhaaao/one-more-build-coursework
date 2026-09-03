class_name StartupDayFlowPanel
extends Control

## Presentation-only Startup, static orientation, Settings, and daily receipt surfaces.
## Every signal is an intent for a composed owner route; this panel owns no Career,
## Workday, Save, Tutorial, or final-outcome truth.

const STARTUP_SURFACE: StringName = &"startup"
const TUTORIAL_SURFACE: StringName = &"tutorial"
const SETTINGS_SURFACE: StringName = &"settings"
const DAY_SUMMARY_SURFACE: StringName = &"day_summary"
const FRESH_START_CONFIRMATION_SURFACE: StringName = &"fresh_start_confirmation"

const FOCUS_START_GAME: StringName = &"startup_start_game"
const FOCUS_LOAD_GAME: StringName = &"startup_load_game"
const FOCUS_TUTORIAL: StringName = &"startup_tutorial"
const FOCUS_SETTINGS: StringName = &"startup_settings"
const FOCUS_QUIT: StringName = &"startup_quit"
const FOCUS_TUTORIAL_BACK: StringName = &"tutorial_back"
const FOCUS_SETTINGS_CLOSE: StringName = &"settings_close"
const FOCUS_DAY_CONTINUE: StringName = &"day_continue"
const FOCUS_FRESH_START_CANCEL: StringName = &"fresh_start_cancel"
const FOCUS_FRESH_START_CONFIRM: StringName = &"fresh_start_confirm"

const TUTORIAL_STEPS: PackedStringArray = [
	"1. Start at Startup.",
	"2. Read the task briefing.",
	"3. Open Graph and use Auto Solve or edit manually.",
	"4. Run all public.",
	"5. Inspect Results.",
	"6. Confirm delivery and view the final outcome.",
]

signal start_game_requested
signal load_game_requested
signal quit_game_requested
signal next_day_requested(next_day_index: int)

var _current_surface_id: StringName = STARTUP_SURFACE
var _current_focus_id: StringName = FOCUS_START_GAME
var _startup_requires_confirmation: bool = false
var _next_day_index: int = 0
var _reduced_motion_enabled: bool = false
var _last_presentation_intent: StringName = &""
var _modal_invoker: Control


func _ready() -> void:
	_connect_buttons()
	show_startup()


## Shows the five-action Startup surface. The caller supplies only whether an
## existing accepted Career requires an explicit fresh-start confirmation and
## may restore one of the five stable Startup focus IDs.
func show_startup(requires_fresh_start_confirmation: bool = false, status_text: String = "", preferred_focus_id: StringName = FOCUS_START_GAME) -> void:
	_startup_requires_confirmation = requires_fresh_start_confirmation
	_current_surface_id = STARTUP_SURFACE
	_set_visible_surface(STARTUP_SURFACE)
	_set_startup_status(status_text)
	_focus_semantic_id(_validated_startup_focus_id(preferred_focus_id))


## Shows the read-only fixed six-step Startup orientation.
func show_tutorial() -> void:
	_modal_invoker = _focus_owner_control()
	_current_surface_id = TUTORIAL_SURFACE
	_set_visible_surface(TUTORIAL_SURFACE)
	_focus_semantic_id(FOCUS_TUTORIAL_BACK)


## Shows the harmless Settings information surface. It has no owner command.
func show_settings_placeholder() -> void:
	_modal_invoker = _focus_owner_control()
	_current_surface_id = SETTINGS_SURFACE
	_set_visible_surface(SETTINGS_SURFACE)
	_focus_semantic_id(FOCUS_SETTINGS_CLOSE)


## Shows a focus-trapping receipt from accepted owner facts for Days 1–4 only.
func show_day_summary(day_index: int, passed_public_cases: int, total_public_cases: int, next_day_index: int, receipt_facts: Dictionary = {}) -> void:
	_current_surface_id = DAY_SUMMARY_SURFACE
	_next_day_index = next_day_index
	_set_visible_surface(DAY_SUMMARY_SURFACE)
	var heading: Label = get_node_or_null("DaySummaryPanel/Content/Heading") as Label
	if heading != null:
		heading.text = "Day %d complete" % day_index
	var summary: Label = get_node_or_null("DaySummaryPanel/Content/Summary") as Label
	if summary != null:
		summary.text = "Accepted public cases: %d/%d\nContinue opens the owner-authorized next day." % [passed_public_cases, total_public_cases]
	var failure_count: int = int(receipt_facts.get("failure_count", 0))
	var receipt_status: Label = get_node_or_null("DaySummaryPanel/Content/ReceiptStatus") as Label
	if receipt_status != null:
		receipt_status.text = "[PASS] Clean accepted receipt" if failure_count == 0 else "[REVIEW] Accepted receipt with rework"
	var receipt_details: Label = get_node_or_null("DaySummaryPanel/Content/ReceiptFacts") as Label
	if receipt_details != null:
		receipt_details.text = _receipt_facts_text(day_index, receipt_facts)
	_focus_semantic_id(FOCUS_DAY_CONTINUE)


func _receipt_facts_text(day_index: int, receipt_facts: Dictionary) -> String:
	var overtime_minutes: int = int(receipt_facts.get("overtime_minutes", 0))
	var overtime_day: bool = bool(receipt_facts.get("overtime_day", false))
	return "History: Day %d of 5 · Receipt: %s\nReputation: %s → %s (applied delta %s)\nFailures: %s · Overtime: %d minutes (%s)\nRemediation: %s · Next-day rework: %s" % [
		day_index,
		_receipt_status(receipt_facts.get("receipt_id")),
		_fact_text(receipt_facts.get("reputation_before")),
		_fact_text(receipt_facts.get("reputation_after")),
		_fact_text(receipt_facts.get("applied_delta")),
		_fact_text(receipt_facts.get("failure_count")),
		overtime_minutes,
		"overtime day" if overtime_day else "regular day",
		_fact_text(receipt_facts.get("remediation_state")),
		_fact_text(receipt_facts.get("next_day_rework")),
	]


func _fact_text(value: Variant, fallback: String = "unavailable") -> String:
	return fallback if value == null else str(value)


func _receipt_status(receipt_id: Variant) -> String:
	if receipt_id == null or str(receipt_id).is_empty():
		return "Receipt unavailable"
	return "Accepted receipt recorded"


## Enables the still-frame presentation variant without changing any route fact.
func set_reduced_motion_enabled(enabled: bool) -> void:
	_reduced_motion_enabled = enabled


## Returns the visible surface semantic ID for deterministic integration checks.
func current_surface_id() -> StringName:
	return _current_surface_id


## Returns the stable semantic focus ID; it is never derived from child order.
func current_focus_id() -> StringName:
	return _current_focus_id


## Returns the latest emitted presentation intent for deterministic integration checks.
func last_presentation_intent() -> StringName:
	return _last_presentation_intent


## Returns the fixed static orientation steps without touching Tutorial progress.
func tutorial_steps() -> PackedStringArray:
	return TUTORIAL_STEPS.duplicate()


## Returns whether reduced motion currently selects the still-frame variant.
func is_reduced_motion_enabled() -> bool:
	return _reduced_motion_enabled


## Routes keyboard-equivalent actions to the same presentation intent as buttons.
func route_keyboard_command(command_name: StringName) -> void:
	_route_command(command_name)


## Routes pointer-equivalent actions to the same presentation intent as buttons.
func route_pointer_command(command_name: StringName) -> void:
	_route_command(command_name)


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key_event: InputEventKey = event
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ESCAPE and try_handle_back():
		get_viewport().set_input_as_handled()


## Lets Main close the visible Startup child before considering global Pause.
func try_handle_back() -> bool:
	if not visible or _current_surface_id not in [
		TUTORIAL_SURFACE, SETTINGS_SURFACE, FRESH_START_CONFIRMATION_SURFACE
	]:
		return false
	_route_command(&"close")
	return true


func _connect_buttons() -> void:
	_connect_button("StartupPanel/Content/StartGame", &"start_game")
	_connect_button("StartupPanel/Content/LoadGame", &"load_game")
	_connect_button("StartupPanel/Content/Tutorial", &"tutorial")
	_connect_button("StartupPanel/Content/Settings", &"settings")
	_connect_button("StartupPanel/Content/Quit", &"quit")
	_connect_button("TutorialPanel/Content/Back", &"close")
	_connect_button("SettingsPanel/Content/Close", &"close")
	_connect_button("DaySummaryPanel/Content/Continue", &"continue_day")
	_connect_button("FreshStartConfirmation/Content/Actions/Cancel", &"cancel_fresh_start")
	_connect_button("FreshStartConfirmation/Content/Actions/Confirm", &"confirm_fresh_start")


func _connect_button(node_path: NodePath, command_name: StringName) -> void:
	var button: Button = get_node_or_null(node_path) as Button
	if button != null:
		button.pressed.connect(route_pointer_command.bind(command_name))


func _route_command(command_name: StringName) -> void:
	match command_name:
		&"start_game":
			if _current_surface_id != STARTUP_SURFACE:
				return
			if _startup_requires_confirmation:
				_show_fresh_start_confirmation()
			else:
				_emit_start_game_intent()
		&"confirm_fresh_start":
			if _current_surface_id == FRESH_START_CONFIRMATION_SURFACE:
				_emit_start_game_intent()
		&"cancel_fresh_start":
			if _current_surface_id == FRESH_START_CONFIRMATION_SURFACE:
				show_startup(_startup_requires_confirmation)
				_restore_focus(FOCUS_START_GAME)
		&"load_game":
			if _current_surface_id == STARTUP_SURFACE:
				_last_presentation_intent = &"load_game"
				load_game_requested.emit()
		&"tutorial":
			if _current_surface_id == STARTUP_SURFACE:
				show_tutorial()
		&"settings":
			if _current_surface_id == STARTUP_SURFACE:
				show_settings_placeholder()
		&"quit":
			if _current_surface_id == STARTUP_SURFACE:
				_last_presentation_intent = &"quit"
				quit_game_requested.emit()
		&"continue_day":
			if _current_surface_id == DAY_SUMMARY_SURFACE:
				_last_presentation_intent = &"continue_day"
				next_day_requested.emit(_next_day_index)
		&"close":
			if _current_surface_id == TUTORIAL_SURFACE:
				show_startup(_startup_requires_confirmation)
				_restore_focus(FOCUS_TUTORIAL)
			elif _current_surface_id == SETTINGS_SURFACE:
				show_startup(_startup_requires_confirmation)
				_restore_focus(FOCUS_SETTINGS)
			elif _current_surface_id == FRESH_START_CONFIRMATION_SURFACE:
				_route_command(&"cancel_fresh_start")


func _emit_start_game_intent() -> void:
	_last_presentation_intent = &"start_game"
	start_game_requested.emit()


func _show_fresh_start_confirmation() -> void:
	_modal_invoker = _focus_owner_control()
	_current_surface_id = FRESH_START_CONFIRMATION_SURFACE
	_set_visible_surface(FRESH_START_CONFIRMATION_SURFACE)
	_focus_semantic_id(FOCUS_FRESH_START_CANCEL)


func _set_visible_surface(surface_id: StringName) -> void:
	_set_node_visible("StartupPanel", surface_id == STARTUP_SURFACE)
	_set_node_visible("TutorialPanel", surface_id == TUTORIAL_SURFACE)
	_set_node_visible("SettingsPanel", surface_id == SETTINGS_SURFACE)
	_set_node_visible("DaySummaryPanel", surface_id == DAY_SUMMARY_SURFACE)
	_set_node_visible("FreshStartConfirmation", surface_id == FRESH_START_CONFIRMATION_SURFACE)


func _set_node_visible(node_path: NodePath, visible: bool) -> void:
	var node: Control = get_node_or_null(node_path) as Control
	if node != null:
		node.visible = visible


func _set_startup_status(status_text: String) -> void:
	var status: Label = get_node_or_null("StartupPanel/Content/Status") as Label
	if status != null and not status_text.is_empty():
		status.text = status_text


func _validated_startup_focus_id(preferred_focus_id: StringName) -> StringName:
	if preferred_focus_id in [FOCUS_START_GAME, FOCUS_LOAD_GAME, FOCUS_TUTORIAL, FOCUS_SETTINGS, FOCUS_QUIT]:
		return preferred_focus_id
	return FOCUS_START_GAME


func _focus_semantic_id(focus_id: StringName) -> void:
	_current_focus_id = focus_id
	var control: Control = _control_for_focus_id(focus_id)
	if control != null:
		control.call_deferred("grab_focus")


func _restore_focus(fallback_focus_id: StringName) -> void:
	if _modal_invoker != null and is_instance_valid(_modal_invoker):
		_modal_invoker.call_deferred("grab_focus")
		_current_focus_id = fallback_focus_id
		_modal_invoker = null
		return
	_focus_semantic_id(fallback_focus_id)


func _focus_owner_control() -> Control:
	return get_viewport().gui_get_focus_owner() as Control


func _control_for_focus_id(focus_id: StringName) -> Control:
	var node_path: NodePath = NodePath()
	match focus_id:
		FOCUS_START_GAME:
			node_path = NodePath("StartupPanel/Content/StartGame")
		FOCUS_LOAD_GAME:
			node_path = NodePath("StartupPanel/Content/LoadGame")
		FOCUS_TUTORIAL:
			node_path = NodePath("StartupPanel/Content/Tutorial")
		FOCUS_SETTINGS:
			node_path = NodePath("StartupPanel/Content/Settings")
		FOCUS_QUIT:
			node_path = NodePath("StartupPanel/Content/Quit")
		FOCUS_TUTORIAL_BACK:
			node_path = NodePath("TutorialPanel/Content/Back")
		FOCUS_SETTINGS_CLOSE:
			node_path = NodePath("SettingsPanel/Content/Close")
		FOCUS_DAY_CONTINUE:
			node_path = NodePath("DaySummaryPanel/Content/Continue")
		FOCUS_FRESH_START_CANCEL:
			node_path = NodePath("FreshStartConfirmation/Content/Actions/Cancel")
		FOCUS_FRESH_START_CONFIRM:
			node_path = NodePath("FreshStartConfirmation/Content/Actions/Confirm")
	return get_node_or_null(node_path) as Control
