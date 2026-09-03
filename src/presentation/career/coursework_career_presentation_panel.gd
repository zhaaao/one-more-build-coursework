class_name CourseworkCareerPresentationPanel
extends Control

## Career presentation surface with local feedback/reset visibility only.
## Implements career-progression-and-evaluation.md Sections 1, 5, and 8.

const CAREER_PRESENTATION_ADAPTER = preload("res://src/presentation/career/coursework_career_presentation_adapter.gd")
const SECTION_HEADING_FOCUS_MODE: Control.FocusMode = Control.FOCUS_ALL
const PAPER: Color = Color(0.905882, 0.941176, 0.94902, 1.0)
const GREEN: Color = Color(0.427451, 0.745098, 0.482353, 1.0)

signal presentation_command_accepted(command_name: StringName)
signal presentation_command_rejected(command_name: StringName, reason: String)
signal main_menu_requested

var _adapter: CAREER_PRESENTATION_ADAPTER = CAREER_PRESENTATION_ADAPTER.new()
var _feedback_visible: bool = false
var _reset_confirmation_visible: bool = false
var _presentation_text: String = "Career unavailable."
var _reset_invoker: Control
var _final_only_mode: bool = false
var _final_outcome_id: StringName = &""
var _last_presentation_intent: StringName = &""


func _ready() -> void:
	_adapter.projection_presented.connect(_render_owner_projection)
	_adapter.command_accepted.connect(_handle_command_accepted)
	_adapter.command_rejected.connect(_handle_command_rejected)
	_connect_buttons()
	_set_feedback_visible(false)
	_set_reset_confirmation_visible(false)
	_set_final_only_mode(false)


## Injects narrow Career and Workstation ports without retaining a gameplay owner reference.
func configure_ports(career_port: CAREER_PRESENTATION_ADAPTER.CareerProjectionPort, workstation_route_port: CAREER_PRESENTATION_ADAPTER.WorkstationRoutePort) -> void:
	_adapter.configure(career_port, workstation_route_port)
	_adapter.route(CAREER_PRESENTATION_ADAPTER.PresentationCommand.new(&"inspect_history"))


## Routes a keyboard-equivalent presentation command without performing Career calculation.
func route_keyboard_command(command_name: StringName) -> void:
	if _final_only_mode:
		if command_name == &"main_menu":
			_request_main_menu()
		return
	if _reset_confirmation_visible and command_name != &"reset_cancel" and command_name != &"reset_confirm":
		return
	_route_presentation_command(command_name)


## Routes a pointer-equivalent presentation command without performing Career calculation.
func route_pointer_command(command_name: StringName) -> void:
	if _final_only_mode:
		if command_name == &"main_menu":
			_request_main_menu()
		return
	if _reset_confirmation_visible and command_name != &"reset_cancel" and command_name != &"reset_confirm":
		return
	_route_presentation_command(command_name)


## Returns the visible text representation composed from the accepted owner projection.
func presentation_text() -> String:
	return _presentation_text


## Shows only supplied Career final facts and five-day history; no formula is evaluated here.
func show_final_outcome(projection: Dictionary[String, Variant]) -> void:
	_final_outcome_id = StringName(str(projection.get("outcome_id", "")))
	_set_final_only_mode(true)
	var outcome_label: Label = get_node_or_null("FinalPresentation/Content/Outcome") as Label
	if outcome_label != null:
		outcome_label.text = _outcome_copy(_final_outcome_id)
		outcome_label.add_theme_color_override("font_color", _outcome_accent(_final_outcome_id))
	_apply_outcome_pattern(_final_outcome_id)
	var summary_label: Label = get_node_or_null("FinalPresentation/Content/Summary") as Label
	if summary_label != null:
		summary_label.text = "Final reputation: %s\nRecorded failures (D_total): %s\nOvertime days (O_days): %s" % [str(projection.get("final_reputation", "")), str(projection.get("D_total", "")), str(projection.get("O_days", ""))]
	var outstanding_label: Label = get_node_or_null("FinalPresentation/Content/OutstandingReview") as Label
	if outstanding_label != null:
		outstanding_label.text = _final_review_text(str(projection.get("day5_remediation_state", "")), int(projection.get("final_review_minutes", 0)))
	_render_final_history(projection.get("records", []))
	var main_menu_button: Button = get_node_or_null("FinalPresentation/Content/MainMenu") as Button
	if main_menu_button != null:
		main_menu_button.call_deferred("grab_focus")


## Restores the existing Career presentation API and controls after a final route closes.
func show_legacy_mode() -> void:
	_set_final_only_mode(false)


## Returns whether the panel is currently displaying the final-only Career route.
func is_final_only_mode() -> bool:
	return _final_only_mode


## Returns the owner-supplied final outcome ID currently being presented.
func final_outcome_id() -> StringName:
	return _final_outcome_id


## Returns the latest final-route intent for deterministic integration checks.
func last_presentation_intent() -> StringName:
	return _last_presentation_intent


## Appends a localized terminal persistence warning without changing Career truth.
func show_final_autosave_failure(reason: String) -> void:
	var warning: String = tr("Final autosave failed: %s") % reason
	_presentation_text = "%s\n%s" % [_presentation_text, warning]
	if _final_only_mode:
		var final_status_label: Label = get_node_or_null("FinalPresentation/Content/OutstandingReview") as Label
		if final_status_label != null:
			final_status_label.text = "%s\n%s" % [final_status_label.text, warning] if not final_status_label.text.is_empty() else warning
		return
	var status_label: Label = get_node_or_null("Content/Status") as Label
	if status_label != null:
		status_label.text = _presentation_text


func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key_event: InputEventKey = event
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_ESCAPE:
		if try_handle_back():
			get_viewport().set_input_as_handled()
		return
	if _final_only_mode:
		if key_event.keycode == KEY_ENTER or key_event.keycode == KEY_SPACE:
			_request_main_menu()
			get_viewport().set_input_as_handled()
		return
	if _reset_confirmation_visible:
		_handle_reset_modal_key(key_event)
		get_viewport().set_input_as_handled()
		return
	var command_name: StringName = _keyboard_command_for_key(key_event.keycode)
	if command_name == &"":
		return
	_route_presentation_command(command_name)
	get_viewport().set_input_as_handled()


## Lets Main close a Career child modal before considering global Pause.
func try_handle_back() -> bool:
	if not visible or _final_only_mode:
		return false
	if _reset_confirmation_visible:
		_route_presentation_command(&"reset_cancel")
		return true
	if _feedback_visible:
		_route_presentation_command(&"dismiss")
		return true
	return false


func _keyboard_command_for_key(keycode: Key) -> StringName:
	match keycode:
		KEY_S:
			return &"start"
		KEY_C:
			return &"continue"
		KEY_H:
			return &"inspect_history"
		KEY_F:
			return &"inspect_feedback"
		KEY_R:
			return &"request_reset"
		KEY_ESCAPE:
			return &"dismiss"
		KEY_ENTER, KEY_SPACE:
			if _reset_confirmation_visible:
				var confirm_button: Button = get_node_or_null("ResetConfirmation/Content/Actions/Confirm") as Button
				if confirm_button != null and confirm_button.has_focus():
					return &"reset_confirm"
				return &"reset_cancel"
	return &""


func _route_presentation_command(command_name: StringName) -> void:
	var reset_confirmed: bool = command_name == &"reset_confirm"
	var command: CAREER_PRESENTATION_ADAPTER.PresentationCommand = CAREER_PRESENTATION_ADAPTER.PresentationCommand.new(command_name, reset_confirmed)
	_adapter.route(command)


func _render_owner_projection(projection: Dictionary[String, Variant]) -> void:
	if projection.is_empty():
		return
	var outcome: Dictionary[String, Variant] = _copy_dictionary(projection.get("final_outcome", {}))
	var summary_lines: PackedStringArray = [
		"Career identity: %s" % str(projection.get("career_identity", "")),
		"Career state: %s" % str(projection.get("career_state", "")),
		"Next task: %s" % str(projection.get("eligible_task_id", "")),
		"Reputation: %s" % str(projection.get("reputation", "")),
		"Recorded failures: %s" % str(projection.get("D_total", "")),
		"Overtime days: %s" % str(projection.get("O_days", "")),
		"Feedback: %s" % str(projection.get("feedback_band", "")),
	]
	if not outcome.is_empty():
		summary_lines.append("Final outcome: %s" % str(outcome.get("outcome_id", "")))
	_presentation_text = "\n".join(summary_lines)
	var status_label: Label = get_node_or_null("Content/Status") as Label
	if status_label != null:
		status_label.text = _presentation_text
	var history_label: Label = get_node_or_null("Content/History") as Label
	if history_label != null:
		history_label.text = _history_text(projection.get("records", []))


func _history_text(records_value: Variant) -> String:
	if typeof(records_value) != TYPE_ARRAY:
		return "History unavailable."
	var lines: PackedStringArray = ["Career history"]
	for record_value: Variant in records_value:
		if typeof(record_value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary[String, Variant] = _copy_dictionary(record_value)
		lines.append("Day %s: %s; failures %s; reputation %s" % [str(record.get("day_index", "")), str(record.get("task_id", "")), str(record.get("failure_count", "")), str(record.get("reputation_after", ""))])
	return "\n".join(lines)


func _copy_dictionary(value: Variant) -> Dictionary[String, Variant]:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var source: Dictionary[Variant, Variant] = value
	var copy: Dictionary[String, Variant] = {}
	for key: Variant in source.keys():
		if typeof(key) == TYPE_STRING:
			copy[String(key)] = source[key]
	return copy


func _set_feedback_visible(visible: bool) -> void:
	_feedback_visible = visible
	var feedback_panel: Control = get_node_or_null("Content/Feedback") as Control
	if feedback_panel != null:
		feedback_panel.visible = visible


func _set_reset_confirmation_visible(visible: bool, invoker: Control = null) -> void:
	var restoring_focus: bool = _reset_confirmation_visible and not visible
	_reset_confirmation_visible = visible
	if visible:
		_reset_invoker = invoker
	var reset_confirmation: Control = get_node_or_null("ResetConfirmation") as Control
	if reset_confirmation != null:
		reset_confirmation.visible = visible
	_set_background_controls_disabled(visible)
	if visible:
		var cancel_button: Button = get_node_or_null("ResetConfirmation/Content/Actions/Cancel") as Button
		if cancel_button != null:
			cancel_button.call_deferred("grab_focus")
	elif restoring_focus:
		_restore_reset_focus()


func _connect_buttons() -> void:
	_connect_button("Content/Actions/Start", &"start")
	_connect_button("Content/Actions/Continue", &"continue")
	_connect_button("Content/Actions/History", &"inspect_history")
	_connect_button("Content/Actions/Feedback", &"inspect_feedback")
	_connect_button("Content/Actions/Reset", &"request_reset")
	_connect_button("Content/Feedback/Dismiss", &"dismiss")
	_connect_button("ResetConfirmation/Content/Actions/Cancel", &"reset_cancel")
	_connect_button("ResetConfirmation/Content/Actions/Confirm", &"reset_confirm")
	_connect_button("FinalPresentation/Content/MainMenu", &"main_menu")


func _connect_button(node_path: NodePath, command_name: StringName) -> void:
	var button: Button = get_node_or_null(node_path) as Button
	if button != null:
		button.pressed.connect(route_pointer_command.bind(command_name))


func _handle_command_accepted(command: CAREER_PRESENTATION_ADAPTER.PresentationCommand, result: CAREER_PRESENTATION_ADAPTER.PresentationResult) -> void:
	var command_name: StringName = command.name
	match command_name:
		&"inspect_feedback":
			_set_feedback_visible(true)
		&"dismiss":
			_set_feedback_visible(false)
		&"request_reset":
			_set_reset_confirmation_visible(true, get_viewport().gui_get_focus_owner() as Control)
		&"reset_cancel", &"reset_confirm":
			_set_reset_confirmation_visible(false)
	presentation_command_accepted.emit(command_name)


func _handle_command_rejected(command: CAREER_PRESENTATION_ADAPTER.PresentationCommand, result: CAREER_PRESENTATION_ADAPTER.PresentationResult) -> void:
	var command_name: StringName = command.name
	var reason: String = result.reason
	_presentation_text = "Career action unavailable: %s" % reason
	var status_label: Label = get_node_or_null("Content/Status") as Label
	if status_label != null:
		status_label.text = _presentation_text
	presentation_command_rejected.emit(command_name, reason)


func _trap_reset_focus(reverse: bool) -> void:
	var cancel_button: Button = get_node_or_null("ResetConfirmation/Content/Actions/Cancel") as Button
	var confirm_button: Button = get_node_or_null("ResetConfirmation/Content/Actions/Confirm") as Button
	if cancel_button == null or confirm_button == null:
		return
	if reverse or confirm_button.has_focus():
		cancel_button.grab_focus()
	else:
		confirm_button.grab_focus()


func _handle_reset_modal_key(key_event: InputEventKey) -> void:
	match key_event.keycode:
		KEY_TAB:
			_trap_reset_focus(key_event.shift_pressed)
		KEY_ESCAPE:
			_route_presentation_command(&"reset_cancel")
		KEY_ENTER, KEY_SPACE:
			var command_name: StringName = _keyboard_command_for_key(key_event.keycode)
			_route_presentation_command(command_name)


func _set_background_controls_disabled(disabled: bool) -> void:
	var section_heading: Control = get_node_or_null("Content/Heading") as Control
	if section_heading != null:
		section_heading.focus_mode = Control.FOCUS_NONE if disabled else SECTION_HEADING_FOCUS_MODE
	var background_paths: Array[NodePath] = [
		NodePath("Content/Actions/Start"),
		NodePath("Content/Actions/Continue"),
		NodePath("Content/Actions/History"),
		NodePath("Content/Actions/Feedback"),
		NodePath("Content/Actions/Reset"),
		NodePath("Content/Feedback/Dismiss"),
	]
	for node_path: NodePath in background_paths:
		var button: Button = get_node_or_null(node_path) as Button
		if button != null:
			button.disabled = disabled


func _restore_reset_focus() -> void:
	if _reset_invoker != null and is_instance_valid(_reset_invoker):
		_reset_invoker.call_deferred("grab_focus")
		_reset_invoker = null
		return
	var section_heading: Control = get_node_or_null("Content/Heading") as Control
	if section_heading != null:
		section_heading.call_deferred("grab_focus")
	_reset_invoker = null


func _set_final_only_mode(enabled: bool) -> void:
	_final_only_mode = enabled
	var legacy_content: Control = get_node_or_null("Content") as Control
	if legacy_content != null:
		legacy_content.visible = not enabled
	var final_presentation: Control = get_node_or_null("FinalPresentation") as Control
	if final_presentation != null:
		final_presentation.visible = enabled
	if enabled:
		_set_reset_confirmation_visible(false)


func _request_main_menu() -> void:
	_last_presentation_intent = &"main_menu"
	main_menu_requested.emit()


func _outcome_copy(outcome_id: StringName) -> String:
	match _outcome_kind(outcome_id):
		&"reliable_engineer":
			return "[CHECK / UNBROKEN] Reliable Engineer — consistent deliveries built trust."
		&"firefighter":
			return "[PRESSURE / INTERRUPTED] Firefighter — you resolved difficult work under pressure."
		&"needs_guidance":
			return "[WAYPOINT / OPEN] Needs Guidance — you completed the week and have clear next steps."
	return "[REVIEW / OPEN] Outcome unavailable — await the Career-owned final result."


func _outcome_accent(outcome_id: StringName) -> Color:
	return GREEN if _outcome_kind(outcome_id) == &"reliable_engineer" else PAPER


func _outcome_kind(outcome_id: StringName) -> StringName:
	match outcome_id:
		&"career.outcome.reliable_engineer", &"reliable_engineer":
			return &"reliable_engineer"
		&"career.outcome.firefighter", &"firefighter":
			return &"firefighter"
		&"career.outcome.needs_guidance", &"needs_guidance":
			return &"needs_guidance"
	return &""


func _apply_outcome_pattern(outcome_id: StringName) -> void:
	var final_surface: PanelContainer = get_node_or_null("FinalPresentation") as PanelContainer
	if final_surface == null:
		return
	var pattern_style: StyleBoxFlat = final_surface.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if pattern_style == null:
		return
	match _outcome_kind(outcome_id):
		&"reliable_engineer":
			pattern_style.border_width_left = 3
			pattern_style.border_width_top = 3
			pattern_style.border_width_right = 3
			pattern_style.border_width_bottom = 3
			final_surface.set_meta("outcome_pattern", "check_unbroken")
		&"firefighter":
			pattern_style.border_width_left = 4
			pattern_style.border_width_top = 1
			pattern_style.border_width_right = 4
			pattern_style.border_width_bottom = 1
			final_surface.set_meta("outcome_pattern", "pressure_interrupted")
		&"needs_guidance":
			pattern_style.border_width_left = 4
			pattern_style.border_width_top = 4
			pattern_style.border_width_right = 1
			pattern_style.border_width_bottom = 1
			final_surface.set_meta("outcome_pattern", "waypoint_open")
		_:
			final_surface.set_meta("outcome_pattern", "review_open")
	final_surface.add_theme_stylebox_override("panel", pattern_style)


func _final_review_text(day5_remediation_state: String, final_review_minutes: int) -> String:
	var remediation_state: String = day5_remediation_state if not day5_remediation_state.is_empty() else "unavailable"
	var lines: PackedStringArray = ["Day 5 remediation: %s" % remediation_state]
	if final_review_minutes > 0:
		lines.append("Outstanding review: %d minutes (owner-provided final fact)." % final_review_minutes)
	return "\n".join(lines)


func _render_final_history(records_value: Variant) -> void:
	var rows: Array[Label] = []
	for row_index: int in range(1, 6):
		var row: Label = get_node_or_null("FinalPresentation/Content/HistoryRows/Row%d" % row_index) as Label
		if row != null:
			rows.append(row)
	for row_index: int in rows.size():
		rows[row_index].text = "Day %d: facts unavailable" % (row_index + 1)
	if typeof(records_value) != TYPE_ARRAY:
		return
	var records: Array[Variant] = []
	for record_value: Variant in records_value:
		records.append(record_value)
	for row_index: int in min(rows.size(), records.size()):
		if typeof(records[row_index]) != TYPE_DICTIONARY:
			continue
		var record: Dictionary[String, Variant] = _copy_dictionary(records[row_index])
		rows[row_index].text = "Day %s: public %s/%s; reputation %s → %s; failures %s; overtime %s minutes" % [
			_fact_text(record.get("day_index"), str(row_index + 1)),
			_fact_text(record.get("passed_public_cases")),
			_fact_text(record.get("total_public_cases")),
			_fact_text(record.get("reputation_before")),
			_fact_text(record.get("reputation_after")),
			_fact_text(record.get("failure_count")),
			_fact_text(record.get("overtime_minutes")),
		]


func _fact_text(value: Variant, fallback: String = "unavailable") -> String:
	return fallback if value == null else str(value)
