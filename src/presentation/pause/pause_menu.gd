class_name PauseMenu
extends Control

## Presentation-only global pause overlay. It exposes intents and accepted owner
## projections; Main remains responsible for all route, Save, and Career truth.

const PAUSE_ROOT_SURFACE: StringName = &"pause_root"
const SAVE_LOAD_SURFACE: StringName = &"pause_save_load"
const TUTORIAL_SURFACE: StringName = &"pause_tutorial"
const SETTINGS_SURFACE: StringName = &"pause_settings"
const SAVE_CONFIRMATION_SURFACE: StringName = &"pause_save_confirmation"
const MAIN_MENU_CONFIRMATION_SURFACE: StringName = &"pause_main_menu_confirmation"

const FOCUS_RESUME: StringName = &"pause_resume"
const FOCUS_SAVE_LOAD: StringName = &"pause_save_load"
const FOCUS_TUTORIAL: StringName = &"pause_tutorial"
const FOCUS_SETTINGS: StringName = &"pause_settings"
const FOCUS_MAIN_MENU: StringName = &"pause_main_menu"
const FOCUS_SAVE_SLOT_1: StringName = &"pause_save_slot_1"
const FOCUS_LOAD_SLOT_1: StringName = &"pause_load_slot_1"
const FOCUS_SAVE_STATUS: StringName = &"pause_save_status"
const FOCUS_SAVE_BACK: StringName = &"pause_save_back"
const FOCUS_TUTORIAL_BACK: StringName = &"pause_tutorial_back"
const FOCUS_SETTINGS_BACK: StringName = &"pause_settings_back"
const FOCUS_CONFIRM_CANCEL: StringName = &"pause_confirm_cancel"
const FOCUS_CONFIRM_ACCEPT: StringName = &"pause_confirm_accept"
const FOCUS_MAIN_MENU_CANCEL: StringName = &"pause_main_menu_cancel"
const FOCUS_MAIN_MENU_CONFIRM: StringName = &"pause_main_menu_confirm"

const TUTORIAL_STEPS: PackedStringArray = [
	"1. Start at Startup.",
	"2. Read the task briefing.",
	"3. Open Graph and use Auto Solve or edit manually.",
	"4. Run all public.",
	"5. Inspect Results.",
	"6. Confirm delivery and view the final outcome.",
]

signal pause_opened(surface_id: StringName, prior_focus_id: StringName)
signal pause_closed(surface_id: StringName, restored_focus_id: StringName)
signal resume_requested(surface_id: StringName, restored_focus_id: StringName)
signal save_load_operation_requested(operation_name: StringName, slot_id: StringName, opaque_token: Variant)
signal main_menu_requested
signal audio_event_requested(event_id: StringName)

var _current_surface_id: StringName = PAUSE_ROOT_SURFACE
var _current_focus_id: StringName = FOCUS_RESUME
var _prior_surface_id: StringName = &""
var _prior_focus_id: StringName = &""
var _save_recovery_snapshot: Dictionary = {}
var _pending_confirmation_token: Variant = null
var _pending_confirmation_operation: StringName = &""
var _pending_confirmation_slot: StringName = &""


func _ready() -> void:
	_apply_localized_text()
	_connect_buttons()
	_configure_focus_loops()
	visible = false


## Opens the contained overlay over an active Career presentation surface.
func open_for(surface_id: StringName, prior_focus: StringName) -> void:
	_prior_surface_id = surface_id
	_prior_focus_id = prior_focus
	visible = true
	_show_surface(PAUSE_ROOT_SURFACE, FOCUS_RESUME)
	pause_opened.emit(_prior_surface_id, _prior_focus_id)
	audio_event_requested.emit(&"presentation_audio.pause_open")


## Hides the overlay without sending a gameplay command and reports the exact
## semantic focus target that Main should restore when it remains valid.
func close() -> void:
	if not visible:
		return
	visible = false
	pause_closed.emit(_prior_surface_id, _prior_focus_id)


## Requests a Presentation-level resume. Main restores the retained focus.
func resume() -> void:
	if not visible:
		return
	audio_event_requested.emit(&"presentation_audio.pause_resume")
	resume_requested.emit(_prior_surface_id, _prior_focus_id)
	close()


## Publishes the existing Save service slot snapshot. It is keyed by
## `manual.1` through `manual.3` and `autosave.1`; this component never derives
## another persistence schema.
func publish_save_recovery_snapshot(snapshot: Dictionary) -> void:
	_save_recovery_snapshot = snapshot.duplicate(true)
	for slot_number: int in range(1, 4):
		var summary: Dictionary = _save_recovery_snapshot.get("manual.%d" % slot_number, {})
		_set_slot_summary(slot_number, summary)
	var autosave: Dictionary = _save_recovery_snapshot.get("autosave.1", {})
	var autosave_label: Label = get_node_or_null("SaveLoadPanel/Content/Autosave") as Label
	if autosave_label != null:
		autosave_label.text = tr("[AUTOSAVE READ-ONLY] %s") % _autosave_summary_text(autosave)
	var status: Label = get_node_or_null("SaveLoadPanel/Content/StatusScroll/Status") as Label
	if status != null:
		status.text = str(_save_recovery_snapshot.get("status", tr("Choose Save or Load. Owner results appear here.")))


## Presents an owner-authorized confirmation. The token is opaque and is only
## sent back unchanged when the player confirms.
func present_save_confirmation(operation_name: StringName, slot_id: StringName, opaque_token: Variant, message: String = "") -> void:
	_pending_confirmation_token = opaque_token
	_pending_confirmation_operation = operation_name
	_pending_confirmation_slot = slot_id
	var text_label: Label = get_node_or_null("SaveConfirmationPanel/Content/Message") as Label
	if text_label != null:
		text_label.text = tr("Confirm the Save / Load operation.") if message.is_empty() else message
	_show_surface(SAVE_CONFIRMATION_SURFACE, FOCUS_CONFIRM_CANCEL)


func show_save_load() -> void:
	_show_surface(SAVE_LOAD_SURFACE, FOCUS_SAVE_SLOT_1)


func show_tutorial() -> void:
	_show_surface(TUTORIAL_SURFACE, FOCUS_TUTORIAL_BACK)


func show_settings() -> void:
	_show_surface(SETTINGS_SURFACE, FOCUS_SETTINGS_BACK)


func show_main_menu_confirmation() -> void:
	_show_surface(MAIN_MENU_CONFIRMATION_SURFACE, FOCUS_MAIN_MENU_CANCEL)


## Emits exactly one opaque Save owner request. The component never inspects or
## transforms the supplied token.
func request_operation(operation_name: StringName, slot_id: StringName, opaque_token: Variant = null) -> void:
	save_load_operation_requested.emit(operation_name, slot_id, opaque_token)


func current_surface_id() -> StringName:
	return _current_surface_id


func current_focus_id() -> StringName:
	return _current_focus_id


func prior_surface_id() -> StringName:
	return _prior_surface_id


func prior_focus_id() -> StringName:
	return _prior_focus_id


func tutorial_steps() -> PackedStringArray:
	return TUTORIAL_STEPS.duplicate()


func route_pointer_command(command_name: StringName) -> void:
	_route_command(command_name)


func route_keyboard_command(command_name: StringName) -> void:
	_route_command(command_name)


## Public Escape route for Main's global precedence arbitration.
func handle_escape() -> bool:
	if not visible:
		return false
	_route_command(&"escape")
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey:
		return
	var key_event: InputEventKey = event
	if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
		handle_escape()
		get_viewport().set_input_as_handled()


func _route_command(command_name: StringName) -> void:
	if not visible:
		return
	match command_name:
		&"escape":
			if _current_surface_id == PAUSE_ROOT_SURFACE:
				resume()
			elif _current_surface_id == SAVE_CONFIRMATION_SURFACE:
				show_save_load()
			elif _current_surface_id == MAIN_MENU_CONFIRMATION_SURFACE:
				_show_surface(PAUSE_ROOT_SURFACE, FOCUS_MAIN_MENU)
			else:
				_show_surface(PAUSE_ROOT_SURFACE, _root_return_focus_id())
		&"resume":
			if _current_surface_id == PAUSE_ROOT_SURFACE:
				resume()
		&"save_load":
			if _current_surface_id == PAUSE_ROOT_SURFACE:
				show_save_load()
				_emit_ui_press()
		&"tutorial":
			if _current_surface_id == PAUSE_ROOT_SURFACE:
				show_tutorial()
				_emit_ui_press()
		&"settings":
			if _current_surface_id == PAUSE_ROOT_SURFACE:
				show_settings()
				_emit_ui_press()
		&"main_menu":
			if _current_surface_id == PAUSE_ROOT_SURFACE:
				show_main_menu_confirmation()
				_emit_ui_press()
		&"save_slot_1", &"save_slot_2", &"save_slot_3", &"load_slot_1", &"load_slot_2", &"load_slot_3":
			if _current_surface_id == SAVE_LOAD_SURFACE:
				_request_slot_operation(command_name)
		&"save_back":
			if _current_surface_id == SAVE_LOAD_SURFACE:
				_show_surface(PAUSE_ROOT_SURFACE, FOCUS_SAVE_LOAD)
				_emit_ui_press()
		&"tutorial_back":
			if _current_surface_id == TUTORIAL_SURFACE:
				_show_surface(PAUSE_ROOT_SURFACE, FOCUS_TUTORIAL)
				_emit_ui_press()
		&"settings_back":
			if _current_surface_id == SETTINGS_SURFACE:
				_show_surface(PAUSE_ROOT_SURFACE, FOCUS_SETTINGS)
				_emit_ui_press()
		&"confirmation_cancel":
			if _current_surface_id == SAVE_CONFIRMATION_SURFACE:
				show_save_load()
				_emit_ui_press()
		&"confirmation_accept":
			if _current_surface_id == SAVE_CONFIRMATION_SURFACE:
				request_operation(_pending_confirmation_operation, _pending_confirmation_slot, _pending_confirmation_token)
		&"main_menu_cancel":
			if _current_surface_id == MAIN_MENU_CONFIRMATION_SURFACE:
				_show_surface(PAUSE_ROOT_SURFACE, FOCUS_MAIN_MENU)
				_emit_ui_press()
		&"main_menu_confirm":
			if _current_surface_id == MAIN_MENU_CONFIRMATION_SURFACE:
				main_menu_requested.emit()


func _request_slot_operation(command_name: StringName) -> void:
	var parts: PackedStringArray = command_name.split("_")
	var operation_name: StringName = StringName(parts[0])
	var slot_id: StringName = StringName("manual.%s" % parts[2])
	request_operation(operation_name, slot_id, null)
	_current_focus_id = _focus_for_slot_command(command_name)


func _show_surface(surface_id: StringName, focus_id: StringName) -> void:
	_current_surface_id = surface_id
	_set_node_visible("PauseRootPanel", surface_id == PAUSE_ROOT_SURFACE)
	_set_node_visible("SaveLoadPanel", surface_id == SAVE_LOAD_SURFACE)
	_set_node_visible("TutorialPanel", surface_id == TUTORIAL_SURFACE)
	_set_node_visible("SettingsPanel", surface_id == SETTINGS_SURFACE)
	_set_node_visible("SaveConfirmationPanel", surface_id == SAVE_CONFIRMATION_SURFACE)
	_set_node_visible("MainMenuConfirmationPanel", surface_id == MAIN_MENU_CONFIRMATION_SURFACE)
	_focus_semantic_id(focus_id)


func _set_node_visible(node_path: NodePath, is_visible: bool) -> void:
	var node: Control = get_node_or_null(node_path) as Control
	if node != null:
		node.visible = is_visible


func _focus_semantic_id(focus_id: StringName) -> void:
	_current_focus_id = focus_id
	var control: Control = _control_for_focus_id(focus_id)
	if control != null:
		control.call_deferred("grab_focus")


func _root_return_focus_id() -> StringName:
	match _current_surface_id:
		SAVE_LOAD_SURFACE:
			return FOCUS_SAVE_LOAD
		TUTORIAL_SURFACE:
			return FOCUS_TUTORIAL
		SETTINGS_SURFACE:
			return FOCUS_SETTINGS
	return FOCUS_RESUME


func _focus_for_slot_command(command_name: StringName) -> StringName:
	match command_name:
		&"save_slot_1": return FOCUS_SAVE_SLOT_1
		&"load_slot_1": return FOCUS_LOAD_SLOT_1
		&"save_slot_2": return &"pause_save_slot_2"
		&"load_slot_2": return &"pause_load_slot_2"
		&"save_slot_3": return &"pause_save_slot_3"
		&"load_slot_3": return &"pause_load_slot_3"
	return FOCUS_SAVE_SLOT_1


func _set_slot_summary(slot_number: int, summary: Dictionary) -> void:
	var label: Label = get_node_or_null("SaveLoadPanel/Content/Slot%d/Summary" % slot_number) as Label
	if label != null:
		label.text = tr("[MANUAL SLOT %d] %s") % [slot_number, _manual_summary_text(summary)]


func _manual_summary_text(slot_snapshot: Dictionary) -> String:
	var test_display_text: String = str(slot_snapshot.get("display_text", ""))
	if not test_display_text.is_empty():
		return test_display_text
	var current: Dictionary = _dictionary_value(slot_snapshot.get("current", null))
	if str(current.get("generation_id", "")).is_empty():
		return tr("Empty slot")
	var previous: Dictionary = _dictionary_value(slot_snapshot.get("previous", null))
	var previous_suffix: String = tr(" · Previous recovery available") if not str(previous.get("generation_id", "")).is_empty() else ""
	return tr("Current recovery available") + previous_suffix


func _autosave_summary_text(slot_snapshot: Dictionary) -> String:
	var test_display_text: String = str(slot_snapshot.get("display_text", ""))
	if not test_display_text.is_empty():
		return test_display_text
	var current: Dictionary = _dictionary_value(slot_snapshot.get("current", null))
	return tr("Current recovery available") if not str(current.get("generation_id", "")).is_empty() else tr("No recovery available")


func _dictionary_value(value: Variant) -> Dictionary:
	return Dictionary(value).duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}


func _emit_ui_press() -> void:
	audio_event_requested.emit(&"presentation_audio.ui_press")


func _apply_localized_text() -> void:
	var localized_text: Dictionary = {
		"PauseRootPanel/Content/Heading": "[PAUSED]",
		"PauseRootPanel/Content/Hint": "Game controls are paused. Escape resumes.",
		"PauseRootPanel/Content/Resume": "Resume",
		"PauseRootPanel/Content/SaveLoad": "Save / Load",
		"PauseRootPanel/Content/Tutorial": "Tutorial",
		"PauseRootPanel/Content/Settings": "Settings",
		"PauseRootPanel/Content/MainMenu": "Main Menu",
		"SaveLoadPanel/Content/Heading": "Save / Load",
		"SaveLoadPanel/Content/StatusScroll/Status": "Choose Save or Load. Owner results appear here.",
		"SaveLoadPanel/Content/Slot1/Summary": "[MANUAL SLOT 1] Empty slot",
		"SaveLoadPanel/Content/Slot2/Summary": "[MANUAL SLOT 2] Empty slot",
		"SaveLoadPanel/Content/Slot3/Summary": "[MANUAL SLOT 3] Empty slot",
		"SaveLoadPanel/Content/Slot1/Actions/Save": "Save",
		"SaveLoadPanel/Content/Slot1/Actions/Load": "Load",
		"SaveLoadPanel/Content/Slot2/Actions/Save": "Save",
		"SaveLoadPanel/Content/Slot2/Actions/Load": "Load",
		"SaveLoadPanel/Content/Slot3/Actions/Save": "Save",
		"SaveLoadPanel/Content/Slot3/Actions/Load": "Load",
		"SaveLoadPanel/Content/Autosave": "[AUTOSAVE READ-ONLY] No autosave summary available.",
		"SaveLoadPanel/Content/Back": "Back",
		"TutorialPanel/Content/Heading": "Tutorial — 6 steps",
		"TutorialPanel/Content/Steps": "1. Start at Startup.\n2. Read the task briefing.\n3. Open Graph and use Auto Solve or edit manually.\n4. Run all public.\n5. Inspect Results.\n6. Confirm delivery and view the final outcome.",
		"TutorialPanel/Content/Back": "Back",
		"SettingsPanel/Content/Heading": "[UNAVAILABLE] Settings",
		"SettingsPanel/Content/Message": "Settings are unavailable here. No value is previewed, changed, applied, or saved.",
		"SettingsPanel/Content/Back": "Back",
		"SaveConfirmationPanel/Content/Heading": "Confirm Save / Load",
		"SaveConfirmationPanel/Content/Message": "Confirm the Save / Load operation.",
		"SaveConfirmationPanel/Content/Actions/Cancel": "Cancel",
		"SaveConfirmationPanel/Content/Actions/Confirm": "Confirm",
		"MainMenuConfirmationPanel/Content/Heading": "Return to Main Menu?",
		"MainMenuConfirmationPanel/Content/Message": "This returns to Startup. It does not save, load, reset, or recalculate your Career.",
		"MainMenuConfirmationPanel/Content/Actions/Cancel": "Cancel",
		"MainMenuConfirmationPanel/Content/Actions/Confirm": "Main Menu",
	}
	for node_path: String in localized_text:
		var text_node: Node = get_node_or_null(NodePath(node_path))
		if text_node != null:
			text_node.set("text", tr(str(localized_text[node_path])))


func _connect_buttons() -> void:
	_connect_button("PauseRootPanel/Content/Resume", &"resume")
	_connect_button("PauseRootPanel/Content/SaveLoad", &"save_load")
	_connect_button("PauseRootPanel/Content/Tutorial", &"tutorial")
	_connect_button("PauseRootPanel/Content/Settings", &"settings")
	_connect_button("PauseRootPanel/Content/MainMenu", &"main_menu")
	for slot_number: int in range(1, 4):
		_connect_button("SaveLoadPanel/Content/Slot%d/Actions/Save" % slot_number, StringName("save_slot_%d" % slot_number))
		_connect_button("SaveLoadPanel/Content/Slot%d/Actions/Load" % slot_number, StringName("load_slot_%d" % slot_number))
	_connect_button("SaveLoadPanel/Content/Back", &"save_back")
	_connect_button("TutorialPanel/Content/Back", &"tutorial_back")
	_connect_button("SettingsPanel/Content/Back", &"settings_back")
	_connect_button("SaveConfirmationPanel/Content/Actions/Cancel", &"confirmation_cancel")
	_connect_button("SaveConfirmationPanel/Content/Actions/Confirm", &"confirmation_accept")
	_connect_button("MainMenuConfirmationPanel/Content/Actions/Cancel", &"main_menu_cancel")
	_connect_button("MainMenuConfirmationPanel/Content/Actions/Confirm", &"main_menu_confirm")


func _connect_button(node_path: NodePath, command_name: StringName) -> void:
	var button: Button = get_node_or_null(node_path) as Button
	if button != null:
		button.pressed.connect(route_pointer_command.bind(command_name))


func _configure_focus_loops() -> void:
	_set_focus_loop([FOCUS_RESUME, FOCUS_SAVE_LOAD, FOCUS_TUTORIAL, FOCUS_SETTINGS, FOCUS_MAIN_MENU])
	_set_focus_loop([FOCUS_SAVE_SLOT_1, FOCUS_LOAD_SLOT_1, &"pause_save_slot_2", &"pause_load_slot_2", &"pause_save_slot_3", &"pause_load_slot_3", FOCUS_SAVE_STATUS, FOCUS_SAVE_BACK])
	_set_focus_loop([FOCUS_TUTORIAL_BACK])
	_set_focus_loop([FOCUS_SETTINGS_BACK])
	_set_focus_loop([FOCUS_CONFIRM_CANCEL, FOCUS_CONFIRM_ACCEPT])
	_set_focus_loop([FOCUS_MAIN_MENU_CANCEL, FOCUS_MAIN_MENU_CONFIRM])


func _set_focus_loop(focus_ids: Array[StringName]) -> void:
	for index: int in focus_ids.size():
		var control: Control = _control_for_focus_id(focus_ids[index])
		if control == null:
			continue
		var next_control: Control = _control_for_focus_id(focus_ids[(index + 1) % focus_ids.size()])
		var previous_control: Control = _control_for_focus_id(focus_ids[(index - 1 + focus_ids.size()) % focus_ids.size()])
		if next_control != null:
			control.focus_next = control.get_path_to(next_control)
		if previous_control != null:
			control.focus_previous = control.get_path_to(previous_control)


func _control_for_focus_id(focus_id: StringName) -> Control:
	var node_path: NodePath = NodePath()
	match focus_id:
		FOCUS_RESUME: node_path = NodePath("PauseRootPanel/Content/Resume")
		FOCUS_SAVE_LOAD: node_path = NodePath("PauseRootPanel/Content/SaveLoad")
		FOCUS_TUTORIAL: node_path = NodePath("PauseRootPanel/Content/Tutorial")
		FOCUS_SETTINGS: node_path = NodePath("PauseRootPanel/Content/Settings")
		FOCUS_MAIN_MENU: node_path = NodePath("PauseRootPanel/Content/MainMenu")
		FOCUS_SAVE_SLOT_1: node_path = NodePath("SaveLoadPanel/Content/Slot1/Actions/Save")
		FOCUS_LOAD_SLOT_1: node_path = NodePath("SaveLoadPanel/Content/Slot1/Actions/Load")
		&"pause_save_slot_2": node_path = NodePath("SaveLoadPanel/Content/Slot2/Actions/Save")
		&"pause_load_slot_2": node_path = NodePath("SaveLoadPanel/Content/Slot2/Actions/Load")
		&"pause_save_slot_3": node_path = NodePath("SaveLoadPanel/Content/Slot3/Actions/Save")
		&"pause_load_slot_3": node_path = NodePath("SaveLoadPanel/Content/Slot3/Actions/Load")
		FOCUS_SAVE_STATUS: node_path = NodePath("SaveLoadPanel/Content/StatusScroll")
		FOCUS_SAVE_BACK: node_path = NodePath("SaveLoadPanel/Content/Back")
		FOCUS_TUTORIAL_BACK: node_path = NodePath("TutorialPanel/Content/Back")
		FOCUS_SETTINGS_BACK: node_path = NodePath("SettingsPanel/Content/Back")
		FOCUS_CONFIRM_CANCEL: node_path = NodePath("SaveConfirmationPanel/Content/Actions/Cancel")
		FOCUS_CONFIRM_ACCEPT: node_path = NodePath("SaveConfirmationPanel/Content/Actions/Confirm")
		FOCUS_MAIN_MENU_CANCEL: node_path = NodePath("MainMenuConfirmationPanel/Content/Actions/Cancel")
		FOCUS_MAIN_MENU_CONFIRM: node_path = NodePath("MainMenuConfirmationPanel/Content/Actions/Confirm")
	return get_node_or_null(node_path) as Control
