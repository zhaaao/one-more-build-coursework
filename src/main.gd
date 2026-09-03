class_name OneMoreBuildMain
extends Node

## Configured composition root for the bounded Day-1 coursework repair loop.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const GraphModelType = preload("res://src/core/authoring/graph_model.gd")
const GraphCommandType = preload("res://src/core/authoring/graph_command.gd")
const AuthoringSessionType = preload("res://src/core/authoring/authoring_session.gd")
const AuthoringRunPortType = preload("res://src/core/authoring/authoring_run_port.gd")
const CourseworkTaskCatalogType = preload("res://src/core/task/coursework_task_catalog.gd")
const CourseworkTaskSandboxPortType = preload("res://src/core/task/coursework_task_sandbox_port.gd")
const CourseworkGvetRunnerType = preload("res://src/core/gvet/coursework_gvet_runner.gd")
const CourseworkCaseExecutorType = preload("res://src/core/gvet/coursework_case_executor.gd")
const SemanticDiagnosticValidatorType = preload("res://src/core/gvet/semantic_diagnostic_validator.gd")
const SandboxCaseAdmissionType = preload("res://src/core/sandbox/sandbox_case_admission.gd")
const CourseworkLoopSessionAdapterType = preload(
	"res://src/presentation/authoring/coursework_loop_session_adapter.gd")
const CourseworkSaveServiceType = preload(
	"res://src/feature/save_recovery/coursework_save_service.gd")
const CanonicalCodecType = preload("res://src/foundation/canonical_codec.gd")
const CandidateAdmissionType = preload(
	"res://src/core/save_recovery/coursework_canonical_candidate_admission.gd")
const StableCommitAutosaveType = preload(
	"res://src/feature/save_recovery/coursework_stable_commit_autosave.gd")
const WindowsSavePortType = preload(
	"res://src/platform/save_recovery/coursework_windows_generation_safe_save_port.gd")
const WholeGenerationRecoveryType = preload(
	"res://src/feature/save_recovery/coursework_whole_generation_recovery.gd")
const LiveOwnerSetType = preload("res://src/feature/save_recovery/coursework_live_owner_set.gd")
const WorkdayPolicyType = preload("res://src/feature/workday/coursework_workday_policy.gd")
const WorkdayLifecycleType = preload("res://src/feature/workday/coursework_workday_lifecycle.gd")
const WorkdayRecoveryProjectionType = preload(
	"res://src/feature/workday/coursework_workday_recovery_projection.gd")
const IssuerProviderType = preload(
	"res://src/feature/save_recovery/coursework_accepted_outcome_issuer_provider.gd")
const CareerProgressionType = preload("res://src/feature/career/coursework_career_progression.gd")
const SettingsTutorialType = preload(
	"res://src/core/save_recovery/coursework_settings_tutorial_projection_contracts.gd")
const AuthoritativeDeliveryTransactionType = preload(
	"res://src/feature/workday/coursework_authoritative_delivery_transaction.gd")
const ReworkCareerHandoffType = preload(
	"res://src/feature/workday/coursework_rework_career_handoff.gd")
const CareerPresentationAdapterType = preload(
	"res://src/presentation/career/coursework_career_presentation_adapter.gd")
const StartupDayFlowPanelType = preload(
	"res://src/presentation/flow/startup_day_flow_panel.gd")
const PauseMenuType = preload("res://src/presentation/pause/pause_menu.gd")
const PresentationAudioType = preload("res://src/presentation/audio/presentation_audio.gd")
const FRESH_CAREER_RELOAD_META: StringName = &"company_workstation_story007_fresh_career"

## Applies the installed Day-1 operation identity only after Authoring has
## captured its unchanged graph. It never retains or changes Sandbox state.
class Day1OperationSandboxPort extends CourseworkSandboxPort:
	const ALLOWED_OPERATIONS: Dictionary[String, bool] = {
		"drop_front": true,
		"pick_up_front": true,
	}
	var _delegate: CourseworkSandboxPort

	func _init(delegate: CourseworkSandboxPort) -> void:
		_delegate = delegate

	func create_case_state(case_definition: Dictionary) -> DomainResult:
		return _delegate.create_case_state(case_definition)

	func query(state: Dictionary, call: Dictionary) -> DomainResult:
		return _delegate.query(state, call)

	func act(state: Dictionary, call: Dictionary) -> DomainResult:
		if _delegate == null or not is_instance_valid(_delegate):
			return DomainResultType.failure(
				&"sandbox_port_unavailable", "Day-1 Sandbox port is unavailable.")
		if typeof(call.get("action_id", null)) != TYPE_STRING \
				or not String(call["action_id"]).is_empty():
			return DomainResultType.failure(
				&"day1_action_identity_invalid", "Day-1 action identity must be supplied by operation_id.")
		var parameters: Variant = call.get("parameters", null)
		if typeof(parameters) != TYPE_DICTIONARY:
			return DomainResultType.failure(
				&"day1_operation_identity_invalid", "Day-1 action requires a typed operation identity.")
		var operation_id: Variant = Dictionary(parameters).get("operation_id", null)
		if typeof(operation_id) != TYPE_STRING and typeof(operation_id) != TYPE_STRING_NAME \
				or not ALLOWED_OPERATIONS.has(String(operation_id)):
			return DomainResultType.failure(
				&"day1_operation_identity_invalid", "Day-1 action operation identity is unavailable.")
		var projected_call: Dictionary = call.duplicate(true)
		projected_call["action_id"] = String(operation_id)
		return _delegate.act(state, projected_call)

	func observe(state: Dictionary) -> DomainResult:
		return _delegate.observe(state)


class Day1AssertionPort extends CourseworkCaseExecutorType.AssertionEvaluationPort:
	const LABEL_DOMAINS: Dictionary[String, String] = {
		"delivery_slot_1": "parcel_colour_or_none",
		"delivery_slot_2": "parcel_colour_or_none",
		"delivery_slot_3": "parcel_colour_or_none",
	}

	func evaluate_assertions(
		assertions: Array, state: Dictionary, sandbox_port: RefCounted
	) -> DomainResult:
		var observed_result: DomainResult = sandbox_port.observe(state)
		if not observed_result.is_success():
			return observed_result
		var facts: Dictionary = observed_result.value()
		var outcomes: Array[Dictionary] = []
		for raw_assertion: Variant in assertions:
			if typeof(raw_assertion) != TYPE_DICTIONARY:
				return DomainResultType.failure(
					&"typed_assertion_invalid", "Day-1 assertion is not a typed record.")
			var assertion: Dictionary = raw_assertion
			var expected: Array = Array(assertion.get("expected_facts", []))
			var observed: Array[Dictionary] = []
			var passed: bool = not expected.is_empty()
			for raw_expected_fact: Variant in expected:
				if typeof(raw_expected_fact) != TYPE_DICTIONARY:
					passed = false
					continue
				var expected_fact: Dictionary = raw_expected_fact
				var fact_id: Variant = expected_fact.get("fact_id", null)
				var value_type: Variant = expected_fact.get("value_type", null)
				if typeof(fact_id) != TYPE_STRING or typeof(value_type) != TYPE_STRING \
						or not facts.has(fact_id):
					passed = false
					continue
				var observed_value: Variant = facts[fact_id]
				var observed_fact: Dictionary = expected_fact.duplicate(true)
				match String(value_type):
					"integer":
						if typeof(observed_value) != TYPE_INT:
							passed = false
					"boolean":
						if typeof(observed_value) != TYPE_BOOL:
							passed = false
					"label":
						if typeof(observed_value) != TYPE_STRING and typeof(observed_value) != TYPE_STRING_NAME \
								or not expected_fact.has("label_domain") \
								or LABEL_DOMAINS.get(fact_id, "") != expected_fact["label_domain"]:
							passed = false
						observed_value = String(observed_value)
					_:
						passed = false
				observed_fact["value"] = observed_value
				observed.append(observed_fact)
				if observed_fact != expected_fact:
					passed = false
			outcomes.append({
				"assertion_id": assertion["assertion_id"],
				"expected": expected,
				"observed": observed,
				"comparison": "equal",
				"pass": passed,
			})
		return DomainResultType.success(outcomes)


var _authoring: AuthoringSession
var _adapter: GraphAuthoringPanel.SessionPort
var _save_service: CourseworkSaveService
var _task_catalog: CourseworkTaskCatalog
var _workday_policy: CourseworkWorkdayPolicy
var _issuer_provider: CourseworkAcceptedOutcomeIssuerProvider
var _workday: CourseworkWorkdayLifecycle
var _career: CourseworkCareerProgression
var _settings_tutorial: CourseworkSettingsTutorialProjectionContracts
var _live_owner_set: CourseworkLiveOwnerSet
var _recovery_root: CourseworkWholeGenerationRecovery
var _candidate_admission: CourseworkCanonicalCandidateAdmission
var _run_port: AuthoringRunPort
var _active_task_id: String = ""
var _active_day_index: int = 0
var _active_execution_contract: CourseworkTaskExecutionContract
var _active_public_run_contract: CourseworkPublicRunContract
var _delivery_transaction: CourseworkAuthoritativeDeliveryTransaction
var _rework_career_handoff: CourseworkReworkCareerHandoff
var _delivery_request_sequence: int = 0
var _next_generation_sequence: int = 1
var _autosave_commit_count: int = 0
var _career_panel: CourseworkCareerPresentationPanel
var _startup_panel
var _pause_menu
var _presentation_audio
var _legacy_start_game_requested: bool = false
var _legacy_configured_main_mode: bool = false


func _ready() -> void:
	var shell: WorkstationDesktopShell = get_node_or_null("WorkstationDesktopShell") as WorkstationDesktopShell
	_career_panel = get_node_or_null("CareerPresentationPanel") as CourseworkCareerPresentationPanel
	_startup_panel = get_node_or_null("StartupDayFlowPanel")
	_pause_menu = get_node_or_null("PauseMenu")
	_presentation_audio = get_node_or_null("PresentationAudio")
	var panel: GraphAuthoringPanel = get_node_or_null(
		"WorkstationDesktopShell/EditorApp/GraphPane/GraphAuthoringPanel") as GraphAuthoringPanel
	if shell == null or panel == null or _career_panel == null or _startup_panel == null:
		return
	_career_panel.hide()
	_startup_panel.start_game_requested.connect(_on_start_game_requested)
	_startup_panel.load_game_requested.connect(_on_startup_load_requested)
	_startup_panel.quit_game_requested.connect(_on_startup_quit_requested)
	_startup_panel.next_day_requested.connect(_on_next_day_requested)
	_career_panel.main_menu_requested.connect(_on_final_main_menu_requested)
	shell.startup_load_closed.connect(_on_startup_load_closed)
	_configure_pause_and_audio()
	_adapter = _create_day1_adapter()
	if _adapter == null:
		return
	panel.configure_session(_adapter)
	panel._selected_case_id = &"case.d1.01.red"
	_publish_current_task_identity(shell)
	shell.graph_edit_requested.connect(_resolve_graph_edit)
	shell.delivery_requested.connect(_resolve_delivery_request)
	if not _compose_save_recovery_owners():
		return
	shell.publish_save_recovery_snapshot(_save_service.slot_snapshot())
	shell.save_recovery_requested.connect(_resolve_save_recovery_request)
	_adapter.connect(&"completed_report_available", _on_completed_report_available)
	_apply_startup_settings_projection()
	var tree: SceneTree = get_tree()
	if tree.has_meta(FRESH_CAREER_RELOAD_META):
		tree.remove_meta(FRESH_CAREER_RELOAD_META)
		_show_gameplay_shell(false)
		shell.guard_fresh_entry_pointer_release()
	elif _legacy_start_game_requested:
		start_game_for_test()
	else:
		_show_startup_route()
	_connect_existing_button_audio(self)
	if not get_tree().node_added.is_connected(_on_presentation_node_added):
		get_tree().node_added.connect(_on_presentation_node_added)


func _configure_pause_and_audio() -> void:
	if _pause_menu == null:
		return
	if not _pause_menu.resume_requested.is_connected(_on_pause_resume_requested):
		_pause_menu.resume_requested.connect(_on_pause_resume_requested)
	if not _pause_menu.pause_opened.is_connected(_on_pause_opened):
		_pause_menu.pause_opened.connect(_on_pause_opened)
	if not _pause_menu.pause_closed.is_connected(_on_pause_closed):
		_pause_menu.pause_closed.connect(_on_pause_closed)
	if not _pause_menu.save_load_operation_requested.is_connected(_on_pause_save_load_operation_requested):
		_pause_menu.save_load_operation_requested.connect(_on_pause_save_load_operation_requested)
	if not _pause_menu.main_menu_requested.is_connected(_on_pause_main_menu_requested):
		_pause_menu.main_menu_requested.connect(_on_pause_main_menu_requested)
	if not _pause_menu.audio_event_requested.is_connected(_on_presentation_audio_requested):
		_pause_menu.audio_event_requested.connect(_on_presentation_audio_requested)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if _pause_menu != null and _pause_menu.visible:
		if key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE:
			_pause_menu.handle_escape()
			get_viewport().set_input_as_handled()
		elif _is_pause_navigation_or_activation_key(key_event):
			# Windows injection and some keyboards report only physical_keycode.
			# Normalize that form before Control/Button GUI handling sees it.
			if key_event.keycode == KEY_NONE:
				key_event.keycode = key_event.physical_keycode
		else:
			# Pause buttons retain only their navigation/activation keys. Every
			# other shortcut is consumed before an underlying Presentation node.
			get_viewport().set_input_as_handled()
		return
	if key_event.keycode != KEY_ESCAPE and key_event.physical_keycode != KEY_ESCAPE:
		return
	if _try_handle_topmost_back():
		get_viewport().set_input_as_handled()
		return
	if _pause_is_eligible():
		_open_pause_menu()
		get_viewport().set_input_as_handled()


func _is_pause_navigation_or_activation_key(key_event: InputEventKey) -> bool:
	const PAUSE_KEYS: Array[Key] = [
		KEY_TAB, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_ENTER, KEY_SPACE,
	]
	return key_event.keycode in PAUSE_KEYS or key_event.physical_keycode in PAUSE_KEYS


func _try_handle_topmost_back() -> bool:
	if _startup_panel != null and _startup_panel.visible and _startup_panel.try_handle_back():
		return true
	if _career_panel != null and _career_panel.visible and _career_panel.try_handle_back():
		return true
	var shell := get_node_or_null("WorkstationDesktopShell") as WorkstationDesktopShell
	return shell != null and shell.visible and shell.try_handle_back()


func _pause_is_eligible() -> bool:
	var shell := get_node_or_null("WorkstationDesktopShell") as WorkstationDesktopShell
	if shell != null and shell.visible and not shell.is_startup_load_mode():
		return true
	if _startup_panel != null and _startup_panel.visible \
			and _startup_panel.current_surface_id() == StartupDayFlowPanelType.DAY_SUMMARY_SURFACE:
		return true
	return _career_panel != null and _career_panel.visible and _career_panel.is_final_only_mode()


func _open_pause_menu() -> bool:
	if _pause_menu == null or _pause_menu.visible or not _pause_is_eligible():
		return false
	var focused := get_viewport().gui_get_focus_owner() as Control
	var focus_path := StringName(String(focused.get_path())) \
		if _is_valid_pause_focus(focused) else &""
	_pause_menu.publish_save_recovery_snapshot(_pause_save_projection())
	_pause_menu.open_for(_current_pause_origin_surface(), focus_path)
	return true


func _current_pause_origin_surface() -> StringName:
	if _startup_panel != null and _startup_panel.visible \
			and _startup_panel.current_surface_id() == StartupDayFlowPanelType.DAY_SUMMARY_SURFACE:
		return &"day_summary"
	if _career_panel != null and _career_panel.visible and _career_panel.is_final_only_mode():
		return &"career_final"
	var shell := get_node_or_null("WorkstationDesktopShell") as WorkstationDesktopShell
	return shell.current_substate() if shell != null else &""


func _is_valid_pause_focus(control: Control) -> bool:
	return control != null and is_instance_valid(control) and control.is_visible_in_tree() \
		and control.focus_mode != Control.FOCUS_NONE


func _on_pause_opened(_surface_id: StringName, _prior_focus_id: StringName) -> void:
	if _presentation_audio != null:
		_presentation_audio.set_pause_ducked(true)


func _on_pause_closed(_surface_id: StringName, _prior_focus_id: StringName) -> void:
	if _presentation_audio != null:
		_presentation_audio.set_pause_ducked(false)


func _on_pause_resume_requested(surface_id: StringName, prior_focus_id: StringName) -> void:
	_restore_pause_focus.call_deferred(surface_id, prior_focus_id)


func _restore_pause_focus(surface_id: StringName, prior_focus_id: StringName) -> void:
	if not prior_focus_id.is_empty():
		var restored := get_node_or_null(NodePath(String(prior_focus_id))) as Control
		if _is_valid_pause_focus(restored):
			restored.grab_focus()
			return
	var fallback := _pause_focus_fallback(surface_id)
	if _is_valid_pause_focus(fallback):
		fallback.grab_focus()


func _pause_focus_fallback(surface_id: StringName) -> Control:
	match surface_id:
		&"workstation_view":
			return get_node_or_null("WorkstationDesktopShell/WorkstationView/ComputerTarget") as Control
		&"desktop":
			return get_node_or_null("WorkstationDesktopShell/DesktopView/EditorIcon") as Control
		&"editor_app":
			return get_node_or_null(
				"WorkstationDesktopShell/EditorApp/HeaderBand/HeaderRow/EditorBack") as Control
		&"day_summary":
			return get_node_or_null("StartupDayFlowPanel/DaySummaryPanel/Content/Continue") as Control
		&"career_final":
			return get_node_or_null("CareerPresentationPanel/FinalPresentation/Content/MainMenu") as Control
	return null


func _pause_save_projection(message: String = "") -> Dictionary:
	var snapshot: Dictionary = _save_service.slot_snapshot().duplicate(true) \
		if _save_service != null else {}
	if not message.is_empty():
		snapshot["status"] = message
	return snapshot


func _on_pause_save_load_operation_requested(
	operation: StringName, slot_id: StringName, confirmation_token: Variant
) -> void:
	if _pause_menu == null or not _pause_menu.visible \
			or (operation != &"save" and operation != &"load"):
		return
	var result := _execute_save_recovery_operation(operation, slot_id, confirmation_token)
	var message := tr("Confirmation required. No save data has changed.") \
		if result.error_code() == &"confirmation_required" \
		else tr("Save / Load result: %s") % (
			tr("Completed.") if result.is_success() else result.error_message())
	_pause_menu.publish_save_recovery_snapshot(_pause_save_projection(message))
	if result.error_code() == &"confirmation_required":
		var confirmation := _save_service.confirmation_for(String(slot_id))
		if confirmation.is_success():
			_pause_menu.present_save_confirmation(
				operation, slot_id, confirmation.value(),
				tr("Confirm this change. The owner will recheck the exact observed slot state."))
	if result.error_code() != &"confirmation_required":
		_play_save_recovery_audio(operation, result.is_success())
	if operation == &"load" and result.is_success():
		_pause_menu.close()
		if String(_career.stable_projection().get("career_state", "")) == "finalized":
			_present_final_career()
		else:
			_show_gameplay_shell(false)


func _on_pause_main_menu_requested() -> void:
	if _pause_menu != null:
		_pause_menu.close()
	_show_startup_route()


func _on_presentation_audio_requested(event_id: StringName) -> void:
	if _presentation_audio != null:
		_presentation_audio.route_event(event_id)


func _play_save_recovery_audio(operation: StringName, succeeded: bool) -> void:
	if _presentation_audio == null:
		return
	if operation == &"save":
		_presentation_audio.route_event(
			PresentationAudioType.SAVE_SUCCESS_EVENT if succeeded \
			else PresentationAudioType.SAVE_FAILURE_EVENT)
	elif operation == &"load":
		_presentation_audio.route_event(
			PresentationAudioType.LOAD_SUCCESS_EVENT if succeeded \
			else PresentationAudioType.LOAD_FAILURE_EVENT)


func _connect_existing_button_audio(root: Node) -> void:
	for child: Node in root.get_children():
		if child is Button:
			_connect_button_audio(child as Button)
		_connect_existing_button_audio(child)


func _on_presentation_node_added(node: Node) -> void:
	if node is Button:
		_connect_button_audio.call_deferred(node as Button)


func _connect_button_audio(button: Button) -> void:
	if button == null or not is_instance_valid(button) or _presentation_audio == null:
		return
	if _pause_menu != null and _pause_menu.is_ancestor_of(button):
		return
	if not button.pressed.is_connected(_on_global_button_pressed):
		button.pressed.connect(_on_global_button_pressed)


func _on_global_button_pressed() -> void:
	if _presentation_audio != null:
		_presentation_audio.route_event(PresentationAudioType.UI_PRESS_EVENT)


## Deterministic integration probes; they route through the same Pause seams.
func open_pause_for_test() -> bool:
	return _open_pause_menu()


func pause_is_open_for_test() -> bool:
	return _pause_menu != null and _pause_menu.visible


## Deterministic compatibility route for configured-main integration suites.
## It reveals the already-composed fresh Career without issuing an owner command.
func start_game_for_test() -> bool:
	_legacy_start_game_requested = true
	return _show_gameplay_shell(true)


func _show_gameplay_shell(legacy_configured_main_mode: bool) -> bool:
	_legacy_configured_main_mode = legacy_configured_main_mode
	var shell: WorkstationDesktopShell = get_node_or_null("WorkstationDesktopShell") as WorkstationDesktopShell
	if shell == null:
		return false
	shell.finish_startup_load_route()
	if _startup_panel != null:
		_startup_panel.hide()
	if _career_panel != null:
		_career_panel.hide()
		_career_panel.show_legacy_mode()
	shell.show()
	return true


func _show_startup_route(
	status_text: String = "", preferred_focus_id: StringName = StartupDayFlowPanelType.FOCUS_START_GAME
) -> void:
	if _pause_menu != null and _pause_menu.visible:
		_pause_menu.close()
	var shell: WorkstationDesktopShell = get_node_or_null("WorkstationDesktopShell") as WorkstationDesktopShell
	if shell != null:
		shell.finish_startup_load_route()
		shell.prepare_next_day_entry()
		shell.hide()
	if _career_panel != null:
		_career_panel.hide()
		_career_panel.show_legacy_mode()
	if _startup_panel != null:
		_startup_panel.show()
		_startup_panel.show_startup(
			_career_requires_fresh_confirmation(), status_text, preferred_focus_id)


func _career_requires_fresh_confirmation() -> bool:
	if _career == null:
		return false
	var records: Array = Array(_career.stable_projection().get("records", []))
	return not records.is_empty()


func _apply_startup_settings_projection() -> void:
	if _startup_panel == null or _settings_tutorial == null:
		return
	var settings: Dictionary = _settings_tutorial.settings_projection()
	if settings.has("reduced_motion"):
		var reduced_motion_enabled: bool = bool(settings["reduced_motion"])
		_startup_panel.set_reduced_motion_enabled(reduced_motion_enabled)
		var panel: GraphAuthoringPanel = get_node_or_null(
			"WorkstationDesktopShell/EditorApp/GraphPane/GraphAuthoringPanel") as GraphAuthoringPanel
		if panel != null:
			panel.reduced_motion_enabled = reduced_motion_enabled


func _on_start_game_requested() -> void:
	if not _career_requires_fresh_confirmation():
		if _show_gameplay_shell(false):
			var shell := get_node_or_null("WorkstationDesktopShell") as WorkstationDesktopShell
			if shell != null:
				shell.guard_fresh_entry_pointer_release()
		return
	var tree: SceneTree = get_tree()
	tree.set_meta(FRESH_CAREER_RELOAD_META, true)
	tree.call_deferred("reload_current_scene")


func _on_startup_load_requested() -> void:
	var shell: WorkstationDesktopShell = get_node_or_null("WorkstationDesktopShell") as WorkstationDesktopShell
	if shell != null and shell.open_startup_load_recovery_overlay():
		_startup_panel.hide()
		return
	_show_startup_route(tr("Load is unavailable."))


func _on_startup_load_closed() -> void:
	_show_startup_route("", StartupDayFlowPanelType.FOCUS_LOAD_GAME)


func _on_next_day_requested(next_day_index: int) -> void:
	if next_day_index != _active_day_index:
		return
	var shell: WorkstationDesktopShell = get_node_or_null("WorkstationDesktopShell") as WorkstationDesktopShell
	if shell != null:
		_startup_panel.hide()
		shell.prepare_next_day_entry()
		shell.show()


func _on_final_main_menu_requested() -> void:
	_show_startup_route()


func _on_startup_quit_requested() -> void:
	get_tree().quit()


func _resolve_save_recovery_request(
	request: WorkstationDesktopShell.SaveRecoveryRequest
) -> void:
	var shell: WorkstationDesktopShell = get_node_or_null("WorkstationDesktopShell") as WorkstationDesktopShell
	if shell == null or _save_service == null or _recovery_root == null:
		return
	var startup_load_mode: bool = shell.is_startup_load_mode()
	var result: DomainResult = _execute_save_recovery_operation(
		request.operation, request.slot_id, request.confirmation_token)
	if result.error_code() == &"confirmation_required":
		var confirmation: DomainResult = _save_service.confirmation_for(String(request.slot_id))
		if confirmation.is_success():
			shell.present_save_confirmation_from_owner(
				request.operation, request.slot_id, confirmation.value(),
				tr("Confirm this change. The owner will recheck the exact observed slot state."))
	shell.publish_save_recovery_snapshot(
		_save_service.slot_snapshot(),
		tr("Save/Load result: %s") % (
			tr("Completed.") if result.is_success() else result.error_message()))
	if result.error_code() != &"confirmation_required":
		_play_save_recovery_audio(request.operation, result.is_success())
	if request.operation == &"load" and result.is_success() and startup_load_mode:
		shell.finish_startup_load_route()
		if String(_career.stable_projection().get("career_state", "")) == "finalized":
			_present_final_career()
		else:
			_show_gameplay_shell(false)


## Shared composition seam for Workstation and Pause Save/Load presentation.
## It invokes the existing owners and introduces no second persistence path.
func _execute_save_recovery_operation(
	operation: StringName, slot_id: StringName, confirmation_token: Variant = null
) -> DomainResult:
	if _save_service == null or _recovery_root == null:
		return DomainResultType.failure(
			&"save_recovery_unavailable", tr("Save / Load is unavailable."))
	_refresh_save_eligibility()
	match operation:
		&"load":
			return _load_and_rebind(String(slot_id))
		&"delete":
			return _save_service.delete(
				String(slot_id), _typed_dictionary(confirmation_token))
		&"save":
			return _save_current_generation(
				String(slot_id), _typed_dictionary(confirmation_token))
	return DomainResultType.failure(
		&"invalid_save_operation", tr("The requested Save/Load action is unavailable."))


## Routes the Company Workstation Submit Build intent through the existing
## Workday transaction; presentation never interprets the delivery outcome.
func _resolve_delivery_request(request: WorkstationDesktopShell.DeliveryRequest) -> void:
	var task_id_before_delivery: String = _active_task_id
	var result: DomainResult = submit_active_build(request.risk_warning_confirmed)
	var shell: WorkstationDesktopShell = get_node_or_null("WorkstationDesktopShell") as WorkstationDesktopShell
	if shell == null:
		return
	if result.is_success() and typeof(result.value()) == TYPE_DICTIONARY \
			and bool(Dictionary(result.value()).get("risk_warning_pending", false)):
		shell.present_delivery_risk_warning(String(Dictionary(result.value()).get("message", "Confirm delivery risk warning.")))
	else:
		shell.publish_delivery_result(result.is_success(), result.error_message())
		if result.is_success() and task_id_before_delivery != _active_task_id:
			_publish_current_task_identity(shell)


## Production owner composition for the active Task's complete public roster.
## A second request explicitly confirms the exact pending owner warning.
func submit_active_build(confirm_risk_warning: bool = false) -> DomainResult:
	if _adapter == null or _authoring == null or _workday == null or _career == null \
			or _active_execution_contract == null or _active_public_run_contract == null \
			or _delivery_transaction == null or _rework_career_handoff == null:
		return DomainResultType.failure(&"delivery_dependencies_unavailable", "Submit Build is unavailable.")
	if confirm_risk_warning:
		var pending: Dictionary[String, Variant] = _delivery_transaction.status()
		var warning_result: DomainResult = _delivery_transaction.accept_pending_risk_warning(
			_risk_warning_from_name(String(pending.get("pending_warning", ""))),
			String(pending.get("pending_evidence_identity", "")), int(pending.get("pending_graph_revision", -1)))
		if not warning_result.is_success():
			return warning_result
	if not confirm_risk_warning:
		_delivery_request_sequence += 1
	var roster: Array[String] = []
	for public_case: Dictionary in _active_execution_contract.ordered_public_cases():
		roster.append(String(public_case.get("case_id", "")))
	var issued: DomainResult = _delivery_transaction.admit_and_run(
		_active_public_run_contract, _workday, _authoring,
		WorkdayLifecycleType.AcceptedOutcomeIssuer.new(),
		AuthoritativeDeliveryTransactionType.DeliveryTrigger.SUBMIT,
		_active_task_id, _active_day_index, "delivery.%d" % _delivery_request_sequence,
		_authoring.live_revision(), _typed_dictionary(_adapter.accepted_run_graph()), roster)
	if not issued.is_success():
		return issued
	if typeof(issued.value()) == TYPE_DICTIONARY:
		var status: Dictionary = Dictionary(issued.value())
		if String(status.get("state", "")) == "risk_warning_pending":
			return DomainResultType.success({"risk_warning_pending": true,
				"message": "Submit Build requires explicit risk-warning confirmation."})
		if status.has("career_fact"):
			return _settle_committed_delivery(status)
	return DomainResultType.failure(&"delivery_result_invalid", "Submit Build did not return a delivery record.")


func _settle_committed_delivery(record: Dictionary) -> DomainResult:
	var handoff: DomainResult = _rework_career_handoff.admit_committed_delivery(record, _workday)
	if not handoff.is_success():
		return handoff
	var handoff_fact: Dictionary = Dictionary(handoff.value()).get("daily_fact", {})
	var fact: Dictionary[String, Variant] = _career_fact_from_committed_record(record, handoff_fact)
	var career_result: DomainResult = _career.admit_settled_workday_fact(fact, _career.career_identity())
	if not career_result.is_success():
		return career_result
	var completed_day_index: int = int(fact.get("day_index", _active_day_index))
	var completed_public_case_total: int = _active_execution_contract.ordered_public_cases().size()
	var completed_record: Dictionary[String, Variant] = _accepted_daily_record(completed_day_index)
	var completed_failure_count: int = int(completed_record.get("failure_count", 0))
	var completed_public_case_passed: int = maxi(0, completed_public_case_total - completed_failure_count)
	var advance: DomainResult = _rework_career_handoff.advance_after_committed_delivery(_workday)
	if not advance.is_success():
		return advance
	if _workday.lifecycle_state_name() == &"rework_due":
		var rework: DomainResult = _rework_career_handoff.complete_due_rework(_workday)
		if not rework.is_success():
			return rework
	if _workday.lifecycle_state_name() == &"career_complete":
		var terminal_commit: DomainResult = commit_stable_terminal()
		_present_final_career()
		if not terminal_commit.is_success():
			var terminal_message: String = tr("Final autosave failed: %s") % terminal_commit.error_message()
			if _career_panel != null:
				_career_panel.show_final_autosave_failure(terminal_commit.error_message())
			return DomainResultType.failure(
				&"final_autosave_failed", terminal_message)
		return DomainResultType.success(_career.stable_projection())
	var next_task_id: String = String(_career.stable_projection().get("eligible_task_id", ""))
	if next_task_id.is_empty() or not _bind_next_task(next_task_id):
		return DomainResultType.failure(&"next_task_binding_unavailable", "The next admitted Task could not be bound.")
	_present_day_summary(
		completed_day_index, completed_public_case_passed,
		completed_public_case_total, _active_day_index, _day_summary_receipt_facts(completed_record))
	return DomainResultType.success(_career.stable_projection())


func _accepted_daily_record(day_index: int) -> Dictionary[String, Variant]:
	if _career == null:
		return {}
	var records: Array = Array(_career.stable_projection().get("records", []))
	for record_value: Variant in records:
		if typeof(record_value) == TYPE_DICTIONARY and int(Dictionary(record_value).get("day_index", -1)) == day_index:
			return _typed_dictionary(record_value)
	return {}


func _day_summary_receipt_facts(record: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
	var facts: Dictionary[String, Variant] = {}
	for field: String in ["reputation_before", "reputation_after", "applied_delta", "failure_count", "overtime_minutes", "overtime_day", "remediation_state", "receipt_id"]:
		if record.has(field):
			facts[field] = record[field]
	if String(record.get("remediation_state", "")) == "scheduled_next_day" and _workday != null:
		facts["next_day_rework"] = "%d minutes" % _workday.rework_minutes()
	else:
		facts["next_day_rework"] = "None"
	return facts


func _present_day_summary(
	completed_day_index: int, passed_public_cases: int,
	total_public_cases: int, next_day_index: int, receipt_facts: Dictionary[String, Variant] = {}
) -> void:
	if _legacy_configured_main_mode:
		return
	var shell: WorkstationDesktopShell = get_node_or_null("WorkstationDesktopShell") as WorkstationDesktopShell
	if shell != null:
		shell.hide()
	if _startup_panel != null:
		_startup_panel.show()
		_startup_panel.show_day_summary(
			completed_day_index, passed_public_cases, total_public_cases, next_day_index, receipt_facts)
		if _presentation_audio != null:
			_presentation_audio.route_event(PresentationAudioType.DAY_COMPLETE_EVENT)


## Projects the Workday-owned committed record into Career's explicit settled-fact
## command shape. It introduces no delivery or Career truth of its own.
func _career_fact_from_committed_record(record: Dictionary, handoff_fact: Dictionary) -> Dictionary[String, Variant]:
	var failures: Array = Array(handoff_fact.get("failed_case_ids", record.get("failed_case_ids", []))).duplicate()
	var failure_count: int = int(handoff_fact.get("defect_count", record.get("defect_count", 0)))
	var overtime_minutes: int = int(Dictionary(record.get("overtime_fact", {})).get("overtime_minutes", 0))
	var day_index: int = int(handoff_fact.get("day_index", _active_day_index))
	var remediation_state: String = "none"
	if failure_count > 0:
		remediation_state = "final_review_outstanding" if day_index == 5 else "scheduled_next_day"
	return {
		"day_index": day_index,
		"task_id": _active_task_id,
		"failure_count": failure_count,
		"failed_case_ids": failures,
		"overtime_minutes": overtime_minutes,
		"overtime_day": overtime_minutes > 0,
		"remediation_state": remediation_state,
		"receipt_id": String(record.get("delivery_identity", "")),
	}


func _bind_next_task(task_id: String) -> bool:
	var next_adapter: GraphAuthoringPanel.SessionPort = _create_adapter_for_task(task_id)
	if next_adapter == null:
		return false
	var next_cases: Array[Dictionary] = _active_execution_contract.ordered_public_cases()
	if next_cases.is_empty():
		return false
	var next_case_id: StringName = StringName(String(next_cases[0].get("case_id", "")))
	if next_case_id.is_empty():
		return false
	_adapter = next_adapter
	_adapter.configure_workday_lifecycle(_workday)
	_adapter.configure_public_run_contract(_active_public_run_contract)
	if not _workday.accept_authoring_revision_change(_authoring.live_revision()).is_success():
		return false
	_delivery_transaction = AuthoritativeDeliveryTransactionType.new()
	var panel: GraphAuthoringPanel = get_node_or_null("WorkstationDesktopShell/EditorApp/GraphPane/GraphAuthoringPanel") as GraphAuthoringPanel
	if panel != null:
		panel.configure_session(_adapter)
		panel._selected_case_id = next_case_id
	var shell: WorkstationDesktopShell = get_node_or_null("WorkstationDesktopShell") as WorkstationDesktopShell
	if shell != null:
		shell.clear_completed_coursework_report_for_new_task()
	_adapter.connect(&"completed_report_available", _on_completed_report_available)
	var recovery_root_rebuilt: bool = _rebuild_recovery_root()
	if recovery_root_rebuilt and shell != null:
		_publish_current_task_identity(shell)
	return recovery_root_rebuilt


## Projects Task-owned day and public-case data into player-readable labels.
func _publish_current_task_identity(shell: WorkstationDesktopShell) -> void:
	if shell == null or _active_execution_contract == null:
		return
	var case_labels: Array[String] = []
	for public_case: Dictionary in _active_execution_contract.ordered_public_cases():
		case_labels.append(_player_case_label(public_case, case_labels.size() + 1))
	shell.rebind_current_task_presentation(
		_active_day_index, _player_task_title(_active_task_id), case_labels)


func _player_task_title(task_id: String) -> String:
	match task_id:
		"task.day1.delivery_order": return tr("Delivery Order")
		"task.day2.color_sort": return tr("Colour Sort")
		"task.day3.patrol_loop": return tr("Patrol Loop")
		"task.day4.low_battery": return tr("Low Battery")
		"task.day5.multi_package": return tr("Multi-package Delivery")
	return tr("Assignment")


func _player_case_label(public_case: Dictionary, ordinal: int) -> String:
	var initial_state: Dictionary = Dictionary(public_case.get("initial_state", {}))
	for raw_package: Variant in Array(initial_state.get("packages", [])):
		var colour: String = String(Dictionary(raw_package).get("color", ""))
		if not colour.is_empty():
			return tr("%s parcel") % colour.capitalize()
	for raw_package: Variant in Array(initial_state.get("inventory", [])):
		var colour: String = String(Dictionary(raw_package).get("color", ""))
		if not colour.is_empty():
			return tr("%s parcel") % colour.capitalize()
	return tr("Public case %d") % ordinal


func _rebuild_recovery_root() -> bool:
	var owner_set_result: DomainResult = LiveOwnerSetType.create(
		_authoring, _task_catalog, _workday, _career, _settings_tutorial)
	if not owner_set_result.is_success():
		return false
	_live_owner_set = owner_set_result.value() as CourseworkLiveOwnerSet
	var recovery_result: DomainResult = WholeGenerationRecoveryType.create(
		_live_owner_set, _task_catalog, _run_port, _authoring.report_state(),
		_authoring.live_revision(), _workday_policy, _issuer_provider)
	if not recovery_result.is_success():
		return false
	_recovery_root = recovery_result.value() as CourseworkWholeGenerationRecovery
	_refresh_save_eligibility()
	return true


func _risk_warning_from_name(value: String) -> int:
	match value:
		"zero_voluntary_evidence": return AuthoritativeDeliveryTransactionType.RiskWarning.ZERO_VOLUNTARY_EVIDENCE
		"stale_voluntary_evidence": return AuthoritativeDeliveryTransactionType.RiskWarning.STALE_VOLUNTARY_EVIDENCE
		"failed_voluntary_evidence": return AuthoritativeDeliveryTransactionType.RiskWarning.FAILED_VOLUNTARY_EVIDENCE
	return AuthoritativeDeliveryTransactionType.RiskWarning.NONE


func _resolve_graph_edit(request: WorkstationDesktopShell.EditorGraphRequest) -> void:
	if _adapter == null:
		return
	var response: GraphAuthoringPanel.SessionResponse = _adapter.request(request.command)
	var shell: WorkstationDesktopShell = get_node_or_null("WorkstationDesktopShell") as WorkstationDesktopShell
	if shell != null:
		shell.resolve_graph_edit_from_owner(request.request_id, response)
		if response.accepted and _authoring != null:
			_publish_owner_report(
				_authoring.report_state().completed_report(), _adapter.report_is_out_of_date())


func _publish_owner_report(report: CourseworkRunResult, report_is_out_of_date: bool = false) -> void:
	var accepted_sandbox_by_case: Dictionary = {}
	if report != null and report.is_valid():
		for case_result: CourseworkCaseResult in report.case_results():
			var admitted: DomainResult = SandboxCaseAdmissionType.admit(
				case_result.to_dictionary().get("final_state", {}))
			if admitted.is_success():
				accepted_sandbox_by_case[case_result.case_id()] = admitted.value()
	var shell: WorkstationDesktopShell = get_node_or_null("WorkstationDesktopShell") as WorkstationDesktopShell
	if shell != null:
		shell.publish_completed_coursework_report(
			report, accepted_sandbox_by_case, report_is_out_of_date)


## Accepted terminal reports commit their stable generation before presentation.
func _on_completed_report_available(report: CourseworkRunResult) -> void:
	var autosave_result: DomainResult = commit_stable_terminal()
	var shell: WorkstationDesktopShell = get_node_or_null("WorkstationDesktopShell") as WorkstationDesktopShell
	if shell != null and _save_service != null:
		var autosave_message: String = tr("Autosave result: %s") % (
			tr("Completed.") if autosave_result.is_success() else autosave_result.error_message())
		shell.publish_save_recovery_snapshot(_save_service.slot_snapshot(), autosave_message)
	_publish_owner_report(report, _adapter.report_is_out_of_date())


func _create_day1_adapter() -> GraphAuthoringPanel.SessionPort:
	_task_catalog = CourseworkTaskCatalogType.new()
	if not _admit_installed_task_catalog(_task_catalog):
		return null
	return _create_adapter_for_task("task.day1.delivery_order")


## Binds one admitted Task execution contract to the configured Authoring surface.
## The production route observes only the Task starting graph and public contract.
func _create_adapter_for_task(task_id: String) -> GraphAuthoringPanel.SessionPort:
	if _task_catalog == null:
		return null
	var execution_result: DomainResult = _task_catalog.execution_contract(task_id)
	if not execution_result.is_success():
		return null
	var execution: CourseworkTaskExecutionContract = execution_result.value()
	if execution == null:
		return null
	var port_result: DomainResult = execution.create_authoring_run_port()
	var public_result: DomainResult = execution.create_public_run_contract()
	if not port_result.is_success() or not public_result.is_success():
		return null
	var model_result: DomainResult = GraphModelType.create(execution.graph_model_contract(), 1)
	if not model_result.is_success():
		return null
	var model: GraphModel = model_result.value()
	var starting_graph: Dictionary = execution.starting_graph()
	if not _admit_contract_starting_graph(model, starting_graph):
		return null
	_authoring = AuthoringSessionType.new(model, port_result.value())
	_run_port = port_result.value()
	_active_task_id = execution.task_id()
	_active_day_index = execution.day_index()
	_active_execution_contract = execution
	_active_public_run_contract = public_result.value()
	var cases: Array[Dictionary] = execution.ordered_public_cases()
	if cases.is_empty():
		return null
	var adapter: CourseworkLoopSessionAdapter = CourseworkLoopSessionAdapterType.new(
		_authoring, model, _presentation_task_binding(starting_graph),
		cases[0], execution.authoring_registry_projection(),
		String(starting_graph.get("fixture_id", _active_task_id)),
		_parameter_names_from_starting_graph(starting_graph), null, cases,
		execution.graph_model_contract())
	if not _configure_auto_solve_witness(adapter, task_id):
		return null
	return adapter


## Passes only detached Task witness operations to the presentation adapter.
func _configure_auto_solve_witness(adapter: CourseworkLoopSessionAdapter, task_id: String) -> bool:
	if adapter == null or _task_catalog == null or task_id.is_empty():
		return false
	var recovery_result: DomainResult = _task_catalog.recovery_contract(task_id)
	if not recovery_result.is_success():
		return false
	var recovery_contract: CourseworkTaskRecoveryContract = recovery_result.value()
	if recovery_contract == null:
		return false
	adapter.configure_auto_solve_witness(recovery_contract.witness_operations())
	return true


## Maps Task-authored graph identifiers onto generated Authoring identities.
func _presentation_task_binding(starting_graph: Dictionary) -> Dictionary:
	var node_aliases: Dictionary[StringName, StringName] = {}
	for index: int in range(Array(starting_graph.get("nodes", [])).size()):
		var node: Dictionary = Dictionary(Array(starting_graph["nodes"])[index])
		node_aliases[StringName(node.get("node_id", ""))] = StringName("node_%d" % (index + 1))
	var connection_aliases: Dictionary[StringName, StringName] = {}
	for index: int in range(Array(starting_graph.get("connections", [])).size()):
		var connection: Dictionary = Dictionary(Array(starting_graph["connections"])[index])
		connection_aliases[StringName(connection.get("connection_id", ""))] = StringName("connection_%d" % (index + 1))
	return {"task_id": _active_task_id, "day_index": _active_day_index, "node_id_aliases": node_aliases, "connection_id_aliases": connection_aliases}

func _parameter_names_from_starting_graph(starting_graph: Dictionary) -> Dictionary[StringName, Array]:
	var names: Dictionary[StringName, Array] = {}
	for raw_node: Variant in Array(starting_graph.get("nodes", [])):
		if typeof(raw_node) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = raw_node
		var variant_id: StringName = StringName(node.get("variant_id", ""))
		var raw_names: Array[String] = []
		for raw_name: Variant in Dictionary(node.get("parameters", {})).keys():
			raw_names.append(String(raw_name))
		raw_names.sort()
		var values: Array[String] = []
		for raw_name: String in raw_names:
			var parameter_name: String = raw_name
			if parameter_name == "operation_id":
				parameter_name = "action_id" if String(node.get("category", "")) == "Action" else "query_id"
			values.append(parameter_name)
		if not values.is_empty():
			names[variant_id] = values
	return names


## The established result builder retains one exact expected projection while
## Day-1 execution evaluates the installed typed expected-facts record.
func _prepare_day1_typed_assertions(day1_case: Dictionary) -> bool:
	var initial_state: Variant = day1_case.get("initial_state", null)
	if typeof(initial_state) != TYPE_DICTIONARY:
		return false
	var assertions: Variant = day1_case.get("assertions", null)
	if typeof(assertions) != TYPE_ARRAY or Array(assertions).is_empty():
		return false
	for index: int in range(Array(assertions).size()):
		if typeof(Array(assertions)[index]) != TYPE_DICTIONARY:
			return false
		var assertion: Dictionary = Dictionary(Array(assertions)[index])
		var expected_facts: Variant = assertion.get("expected_facts", null)
		if typeof(expected_facts) != TYPE_ARRAY or Array(expected_facts).is_empty():
			return false
		assertion["expected"] = Array(expected_facts).duplicate(true)
		Array(assertions)[index] = assertion
	day1_case["assertions"] = assertions
	# The established executor and Task Sandbox port consume the historical
	# case-content envelope. Preserve the installed public-case fields while
	# deriving that envelope once at the Main composition boundary.
	day1_case["content"] = {
		"initial_state": Dictionary(initial_state).duplicate(true),
		"assertions": Array(assertions).duplicate(true),
	}
	return true


func _admit_contract_starting_graph(model: GraphModel, starting_graph: Dictionary) -> bool:
	var node_ids: Dictionary[StringName, StringName] = {}
	for index: int in range(Array(starting_graph.get("nodes", [])).size()):
		var source: Dictionary = Array(starting_graph["nodes"])[index]
		var admitted: DomainResult = model.admit_supplied_node(
			StringName(source["category"]), StringName(source["variant_id"]),
			{"x": index * 16, "y": 0}, false)
		if not admitted.is_success():
			return false
		node_ids[StringName(source["node_id"])] = StringName("node_%d" % (index + 1))
	for raw_node: Variant in Array(starting_graph["nodes"]):
		var source: Dictionary = raw_node
		var parameter_names: Array[String] = []
		for raw_name: Variant in Dictionary(source.get("parameters", {})).keys():
			parameter_names.append(String(raw_name))
		parameter_names.sort()
		for parameter_index: int in range(parameter_names.size()):
			var value: Variant = Dictionary(source["parameters"])[parameter_names[parameter_index]]
			if typeof(value) == TYPE_STRING:
				value = StringName(value)
			if not model.change_parameter(
				node_ids[StringName(source["node_id"])], parameter_index, value).is_success():
				return false
	for raw_connection: Variant in Array(starting_graph["connections"]):
		var connection: Dictionary = raw_connection
		var output_port: StringName = StringName(connection["source_port_id"])
		if not model.connect_ports(
			node_ids[StringName(connection["source_node_id"])], output_port,
			node_ids[StringName(connection["target_node_id"])],
			StringName(connection["target_port_id"])).is_success():
			return false
	return model.finalize_task_starting_snapshot().is_success()


func _admit_installed_task_catalog(catalog: CourseworkTaskCatalog) -> bool:
	var content: Array[Dictionary] = CourseworkTaskCatalogType.day1_day2_content()
	content.append(CourseworkTaskCatalogType.day3_content())
	content.append(CourseworkTaskCatalogType.day4_content())
	content.append(CourseworkTaskCatalogType.day5_content())
	var packages: Array[Variant] = []
	for index: int in range(content.size()):
		var task: Dictionary = content[index]
		var case_ids: Array[Variant] = []
		var assertion_ids: Array[Variant] = []
		var state_ids: Array[Variant] = []
		for case_index: int in range(Array(task["public_cases"]).size()):
			var public_case: Dictionary = Array(task["public_cases"])[case_index]
			var assertions: Array = Array(public_case.get("assertions", []))
			if assertions.is_empty() or typeof(assertions[0]) != TYPE_DICTIONARY:
				return false
			case_ids.append(String(public_case["case_id"]))
			assertion_ids.append(String(Dictionary(assertions[0])["assertion_id"]))
			state_ids.append(String(public_case["state_id"]))
		var prompt_ids: Array[Variant] = []
		for prompt_value: Variant in Array(task.get("prompts", [])):
			prompt_ids.append(String(Dictionary(prompt_value)["prompt_id"]))
		packages.append({
			"day_index": index + 1,
			"task_id": task["task_id"],
			"mode": task["mode"],
			"node_limit": task["limits"]["node_limit"],
			"public_case_ids": case_ids,
			"assertion_ids": assertion_ids,
			"state_ids": state_ids,
			"prompt_ids": prompt_ids,
		})
	var encoded: DomainResult = CanonicalCodecType.encode({"packages": packages})
	return encoded.is_success() and catalog.admit(encoded.value()).is_success()


func _compose_save_recovery_owners() -> bool:
	_workday_policy = WorkdayPolicyType.new()
	if not _workday_policy.admit(WorkdayPolicyType.approved_candidate()).is_success():
		return false
	_issuer_provider = IssuerProviderType.new()
	var issuer_result: DomainResult = _issuer_provider.create_fresh_issuer()
	if not issuer_result.is_success():
		return false
	var lifecycle_result: DomainResult = WorkdayLifecycleType.open(
		_workday_policy, issuer_result.value())
	if not lifecycle_result.is_success():
		return false
	_workday = lifecycle_result.value() as CourseworkWorkdayLifecycle
	_career = CareerProgressionType.new()
	_settings_tutorial = SettingsTutorialType.new()
	var owner_set_result: DomainResult = LiveOwnerSetType.create(
		_authoring, _task_catalog, _workday, _career, _settings_tutorial)
	if not owner_set_result.is_success():
		return false
	_live_owner_set = owner_set_result.value() as CourseworkLiveOwnerSet
	if not _workday.accept_authoring_revision_change(_authoring.live_revision()).is_success():
		return false
	_rework_career_handoff = ReworkCareerHandoffType.new()
	_delivery_transaction = AuthoritativeDeliveryTransactionType.new()
	_adapter.configure_workday_lifecycle(_workday)
	_adapter.configure_public_run_contract(_active_public_run_contract)
	_candidate_admission = CandidateAdmissionType.new(
		"coursework.save.v2", _typed_catalog_snapshot())
	var save_port: CourseworkWindowsGenerationSafeSavePort = WindowsSavePortType.new(
		ProjectSettings.globalize_path("user://coursework_save_recovery"))
	_save_service = CourseworkSaveServiceType.new(
		DomainResultType.success(true), _candidate_admission, save_port)
	var observed_slots: DomainResult = _save_service.refresh_persisted_slots()
	if not observed_slots.is_success():
		return false
	var recovery_result: DomainResult = WholeGenerationRecoveryType.create(
		_live_owner_set, _task_catalog, _run_port, _authoring.report_state(),
		_authoring.live_revision(), _workday_policy, _issuer_provider)
	if not recovery_result.is_success():
		return false
	_recovery_root = recovery_result.value() as CourseworkWholeGenerationRecovery
	_configure_career_presentation()
	_refresh_save_eligibility()
	return true


func _configure_career_presentation() -> void:
	if _career_panel == null or _career == null:
		return
	var career_port = CareerPresentationAdapterType.create_career_projection_port(
		Callable(_career, "stable_projection"), Callable(_career, "reset_career"))
	var route_port = CareerPresentationAdapterType.create_workstation_route_port(
		Callable(self, "_route_career_presentation"))
	_career_panel.configure_ports(career_port, route_port)


func _route_career_presentation(
	command: CareerPresentationAdapterType.PresentationCommand
) -> CareerPresentationAdapterType.PresentationResult:
	if command != null and command.name == &"continue":
		return CareerPresentationAdapterType.PresentationResult.accept({})
	return CareerPresentationAdapterType.PresentationResult.reject(
		"Use the explicit Reset action before starting a new career.")


func _present_final_career() -> void:
	_configure_career_presentation()
	var shell: WorkstationDesktopShell = get_node_or_null(
		"WorkstationDesktopShell") as WorkstationDesktopShell
	if shell != null:
		shell.hide()
	if _career_panel != null:
		_career_panel.show()
		if _legacy_configured_main_mode:
			_career_panel.show_legacy_mode()
			var heading: Control = _career_panel.get_node_or_null("Content/Heading") as Control
			if heading != null:
				heading.call_deferred("grab_focus")
			return
		var final_outcome: Dictionary[String, Variant] = _enriched_final_outcome(_typed_dictionary(
			_career.stable_projection().get("final_outcome", {})) if _career != null else {})
		_career_panel.show_final_outcome(final_outcome)
		if _presentation_audio != null:
			_presentation_audio.route_event(
				PresentationAudioType.FINAL_OUTCOME_EVENT,
				StringName(String(final_outcome.get("outcome_id", ""))))


func _enriched_final_outcome(final_outcome: Dictionary[String, Variant]) -> Dictionary[String, Variant]:
	var enriched: Dictionary[String, Variant] = final_outcome.duplicate(true)
	var rows: Array[Variant] = []
	for record_value: Variant in Array(final_outcome.get("records", [])):
		var row: Dictionary[String, Variant] = _typed_dictionary(record_value)
		var execution: DomainResult = _task_catalog.execution_contract(String(row.get("task_id", ""))) if _task_catalog != null else DomainResultType.failure(&"task_catalog_unavailable", "")
		if execution.is_success():
			var total: int = (execution.value() as CourseworkTaskExecutionContract).ordered_public_cases().size()
			row["total_public_cases"] = total
			row["passed_public_cases"] = maxi(0, total - int(row.get("failure_count", 0)))
		rows.append(row)
	enriched["records"] = rows
	return enriched


func _refresh_save_eligibility() -> void:
	if _save_service == null:
		return
	var authoring_gate: DomainResult = DomainResultType.success(true) \
		if _authoring != null and _authoring.state() == AuthoringSession.State.EDITABLE \
		else DomainResultType.failure(&"authoring_read_only", "Save is unavailable while Authoring is read-only.")
	_save_service.set_eligibility(authoring_gate, false, false)


func _build_stable_generation() -> DomainResult:
	if _authoring == null or _task_catalog == null or _workday == null \
		or _career == null or _settings_tutorial == null:
		return DomainResultType.failure(&"save_dependencies_unavailable", "Save owners are not configured.")
	var graph_snapshot: GraphSnapshot = _authoring.graph_snapshot()
	if graph_snapshot == null:
		return DomainResultType.failure(&"authoring_snapshot_unavailable", "Authoring has no accepted graph snapshot.")
	var workday_result: DomainResult = WorkdayRecoveryProjectionType.new().project_v2(_workday)
	if not workday_result.is_success():
		return workday_result
	var career_projection: Dictionary = _plain(_career.stable_projection())
	var workday_projection: Variant = null
	if String(career_projection.get("career_state", "")) != "finalized":
		workday_projection = _plain(workday_result.value())
	var content: Dictionary = _task_catalog.snapshot()
	var task_ids: Array[Variant] = []
	var case_ids: Array[Variant] = []
	for package_value: Variant in Array(content["packages"]):
		var package: Dictionary = package_value
		task_ids.append(package["task_id"])
		for case_id: Variant in Array(package["public_case_ids"]):
			case_ids.append(case_id)
	var sections: Array[Dictionary] = [
		{"task_id": _active_task_id, "graph_revision": _authoring.live_revision(), "graph": {
			"nodes": _plain(graph_snapshot.nodes()), "connections": _plain(graph_snapshot.connections())}},
		{"content_version": "coursework.v1", "task_ids": task_ids, "public_case_ids": case_ids},
		{"current_task_id": _active_task_id, "career_projection": career_projection, "workday_projection": workday_projection},
		_plain(_settings_tutorial.settings_projection()),
		_plain(_settings_tutorial.tutorial_projection()),
	]
	var encoded_sections: Array[PackedByteArray] = []
	for section: Dictionary in sections:
		var encoded: DomainResult = CanonicalCodecType.encode(section)
		if not encoded.is_success():
			return encoded
		encoded_sections.append(encoded.value())
	var preimage: DomainResult = CanonicalCodecType.encode([
		"coursework.save.v2", sections[0], sections[1], sections[2], sections[3], sections[4]])
	if not preimage.is_success():
		return preimage
	return DomainResultType.success({
		"save_version": "coursework.save.v2",
		"authoring_raw": encoded_sections[0],
		"content_raw": encoded_sections[1],
		"progression_raw": encoded_sections[2],
		"settings_raw": encoded_sections[3],
		"tutorial_raw": encoded_sections[4],
		"checksum": CanonicalCodecType.sha256_hex(preimage.value()),
	})


func _save_current_generation(slot_id: String, token: Dictionary[String, Variant]) -> DomainResult:
	var generation_result: DomainResult = _build_stable_generation()
	if not generation_result.is_success():
		return generation_result
	var candidate: Dictionary[String, Variant] = _typed_dictionary(generation_result.value())
	var result: DomainResult = _save_service.save(
		slot_id, candidate, "generation.%d" % _next_generation_sequence, token)
	if result.is_success() and String(result.value().get("result_code", "")) == "save_committed":
		_next_generation_sequence += 1
	return result


## Called by the stable terminal owner boundary after it has committed exactly once.
func commit_stable_terminal() -> DomainResult:
	_refresh_save_eligibility()
	var generation_result: DomainResult = _build_stable_generation()
	if not generation_result.is_success():
		return generation_result
	var generation: Dictionary[String, Variant] = _typed_dictionary(generation_result.value())
	var result: DomainResult = StableCommitAutosaveType.commit_v2(
		_candidate_admission, _save_service, PackedByteArray(generation["authoring_raw"]),
		PackedByteArray(generation["content_raw"]), PackedByteArray(generation["progression_raw"]),
		PackedByteArray(generation["settings_raw"]), PackedByteArray(generation["tutorial_raw"]),
		String(generation["checksum"]), "autosave.%d" % _next_generation_sequence)
	if result.is_success() and String(result.value().get("result_code", "")) == "save_committed":
		_next_generation_sequence += 1
		_autosave_commit_count += 1
	return result


## Exposes a detached owner snapshot for composition-level deterministic checks.
func save_recovery_slot_snapshot() -> Dictionary:
	return _save_service.slot_snapshot() if _save_service != null else {}


## Returns the active Task identity for configured-composition verification.
func active_task_id() -> String:
	return _active_task_id


## Returns the current Career-owned projection for configured-composition verification.
func career_projection() -> Dictionary[String, Variant]:
	return _career.stable_projection() if _career != null else {}


## Returns committed autosave count; rejected and unchanged attempts do not add one.
func autosave_commit_count() -> int:
	return _autosave_commit_count


## Returns the currently published Authoring owner after any synchronous recovery.
func current_authoring_owner() -> AuthoringSession:
	return _authoring


func _load_and_rebind(slot_id: String) -> DomainResult:
	var loaded: DomainResult = _save_service.load(slot_id)
	if not loaded.is_success():
		return loaded
	var slot: Dictionary[String, Variant] = _typed_dictionary(_save_service.slot_snapshot().get(slot_id, {}))
	var current: Dictionary[String, Variant] = _typed_dictionary(slot.get("current", {}))
	var previous: Dictionary[String, Variant] = _typed_dictionary(slot.get("previous", {}))
	var prepared_result: DomainResult = _recovery_root.prepare_restore(
		current.get("candidate", null), previous.get("candidate", null))
	if not prepared_result.is_success():
		return prepared_result
	var prepared: WholeGenerationRecoveryType.PreparedRestore = prepared_result.value() as WholeGenerationRecoveryType.PreparedRestore
	var accepted: CourseworkLiveOwnerSet = prepared.owner_set
	var restored_authoring: AuthoringSession = accepted.authoring_session()
	var restored_workday: CourseworkWorkdayLifecycle = accepted.workday_lifecycle()
	var restored_career: CourseworkCareerProgression = accepted.career()
	var restored_settings: CourseworkSettingsTutorialProjectionContracts = accepted.settings_tutorial()
	var prepared_handoff: CourseworkReworkCareerHandoff = ReworkCareerHandoffType.new()
	if restored_workday != null:
		prepared_handoff = ReworkCareerHandoffType.from_recovered_owners(
			restored_career.stable_projection(), restored_workday.snapshot(), restored_workday.rework_minutes())
	var restored_task_id: String = String(restored_career.stable_projection().get("eligible_task_id", ""))
	if restored_task_id.is_empty() \
			and String(restored_career.stable_projection().get("career_state", "")) == "finalized":
		_recovery_root.publish_prepared(prepared)
		_live_owner_set = accepted
		_authoring = restored_authoring
		_workday = restored_workday
		_career = restored_career
		_settings_tutorial = restored_settings
		_rework_career_handoff = prepared_handoff
		_delivery_transaction = AuthoritativeDeliveryTransactionType.new()
		_apply_startup_settings_projection()
		_configure_career_presentation()
		_present_final_career()
		return DomainResultType.success(prepared.result_code)
	if restored_task_id.is_empty():
		_recovery_root.discard_prepared(prepared)
		return DomainResultType.failure(&"recovery_task_binding_unavailable", "Recovery did not expose the active Task identity.")
	var execution_result: DomainResult = _task_catalog.execution_contract(restored_task_id)
	if not execution_result.is_success():
		_recovery_root.discard_prepared(prepared)
		return execution_result
	var execution: CourseworkTaskExecutionContract = execution_result.value()
	var public_result: DomainResult = execution.create_public_run_contract()
	if not public_result.is_success():
		_recovery_root.discard_prepared(prepared)
		return public_result
	var cases: Array[Dictionary] = execution.ordered_public_cases()
	if cases.is_empty():
		_recovery_root.discard_prepared(prepared)
		return DomainResultType.failure(&"recovery_task_cases_unavailable", "Recovery Task has no public cases.")
	var restored_case_id: StringName = StringName(String(cases[0].get("case_id", "")))
	if restored_case_id.is_empty():
		_recovery_root.discard_prepared(prepared)
		return DomainResultType.failure(&"recovery_task_case_binding_unavailable", "Recovery Task has no active public case.")
	var prepared_adapter: CourseworkLoopSessionAdapter = CourseworkLoopSessionAdapterType.new(restored_authoring, null,
		{"task_id": execution.task_id(), "day_index": execution.day_index()}, cases[0],
		execution.authoring_registry_projection(), String(execution.starting_graph().get("fixture_id", execution.task_id())),
		_parameter_names_from_starting_graph(execution.starting_graph()), restored_workday, cases,
		execution.graph_model_contract())
	if not _configure_auto_solve_witness(prepared_adapter, execution.task_id()):
		_recovery_root.discard_prepared(prepared)
		return DomainResultType.failure(
			&"recovery_auto_solve_witness_unavailable", "Recovery Task Auto Solve witness is unavailable.")
	prepared_adapter.configure_public_run_contract(public_result.value())
	prepared_adapter.connect(&"completed_report_available", _on_completed_report_available)
	_recovery_root.publish_prepared(prepared)
	_live_owner_set = accepted
	_authoring = restored_authoring
	_workday = restored_workday
	_career = restored_career
	_settings_tutorial = restored_settings
	_rework_career_handoff = prepared_handoff
	_apply_startup_settings_projection()
	_active_task_id = execution.task_id()
	_active_day_index = execution.day_index()
	_active_execution_contract = execution
	_active_public_run_contract = public_result.value()
	_adapter = prepared_adapter
	var panel: GraphAuthoringPanel = get_node_or_null("WorkstationDesktopShell/EditorApp/GraphPane/GraphAuthoringPanel") as GraphAuthoringPanel
	if panel != null:
		panel.configure_session(_adapter)
		panel._selected_case_id = restored_case_id
	var shell: WorkstationDesktopShell = get_node_or_null("WorkstationDesktopShell") as WorkstationDesktopShell
	if shell != null:
		_publish_current_task_identity(shell)
	_delivery_transaction = AuthoritativeDeliveryTransactionType.new()
	_publish_owner_report(_authoring.report_state().completed_report(), true)
	return DomainResultType.success(prepared.result_code)


func _typed_catalog_snapshot() -> Dictionary[String, Variant]:
	var typed: Dictionary[String, Variant] = {}
	for raw_key: Variant in _task_catalog.snapshot().keys():
		typed[String(raw_key)] = _task_catalog.snapshot()[raw_key]
	return typed


func _typed_dictionary(value: Variant) -> Dictionary[String, Variant]:
	var typed: Dictionary[String, Variant] = {}
	if typeof(value) != TYPE_DICTIONARY:
		return typed
	for raw_key: Variant in Dictionary(value).keys():
		typed[String(raw_key)] = Dictionary(value)[raw_key]
	return typed


func _plain(value: Variant) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		var copied: Dictionary = {}
		for key: Variant in Dictionary(value).keys():
			copied[key] = _plain(Dictionary(value)[key])
		return copied
	if typeof(value) == TYPE_ARRAY:
		var copied: Array = []
		for item: Variant in Array(value):
			copied.append(_plain(item))
		return copied
	return value


func _day1_registry() -> Dictionary:
	return {
		"registry_codec_version": "authoring_registry_v1",
		"resolved_locale_id": "en-GB",
		"categories": [
			_category("Start", 0), _category("Action", 1), _category("Query", 2),
			_category("Constant", 3), _category("Compare", 4), _category("Branch", 5),
			_category("Repeat", 6), _category("End", 7),
		],
		"variants": [
			_registry_variant("flow.start", "Start", 0, [_descriptor("next", 0, "output")]),
			_registry_variant("parcel.action.drop_front", "Action", 1, [
				_descriptor("in", 0, "input"), _descriptor("next", 1, "output")]),
			_registry_variant("parcel.action.pick_up_front", "Action", 2, [
				_descriptor("in", 0, "input"), _descriptor("next", 1, "output")]),
			_registry_variant("flow.end", "End", 3, [_descriptor("in", 0, "input")]),
		],
		"reasons": [], "trace_outcomes": [], "message_templates": [],
		"node_actions": [], "editor_controls": [],
	}


func _variant(id: StringName, category: StringName, creatable: bool, ports: Array, parameter_count: int) -> Dictionary:
	return {"id": id, "category": category, "creatable": creatable, "ports": ports, "parameter_count": parameter_count}


func _port(id: StringName, direction: StringName) -> Dictionary:
	return {"id": id, "direction": direction, "kind": &"execution"}


func _category(category_id: String, order: int) -> Dictionary:
	return {"category_id": category_id, "registry_order": order, "title": category_id}


func _registry_variant(variant_id: String, category_id: String, order: int, ports: Array[Dictionary]) -> Dictionary:
	return {"variant_id": variant_id, "category_id": category_id, "registry_order": order, "title": variant_id, "ports": ports, "parameters": [], "node_action_ids": [], "max_footprint_width": 1, "max_footprint_height": 1}


func _descriptor(port_id: String, order: int, direction: String) -> Dictionary:
	return {"port_id": port_id, "registry_order": order, "direction": direction, "kind": "execution", "maximum_connections": 1, "label": port_id}
