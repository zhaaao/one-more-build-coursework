class_name CourseworkGvetPanel
extends Control

## Coursework-only Presentation adapter. Authoring, Task, Sandbox, assertion,
## and GVET truth arrive through SessionPort; this Control renders projections.

const EXECUTION_PORT: int = 0
const BOOLEAN_PORT: int = 1
const EXECUTION_COLOR: Color = Color("8db7ff")
const BOOLEAN_COLOR: Color = Color("f4c95d")
const DEFAULT_NODE_COLOR: Color = Color("d7e3f4")
const HIGHLIGHT_NODE_COLOR: Color = Color("9af0b3")
const EXPECTED_NODE_IDS: Array[String] = [
	"action", "branch", "decision", "end_fail", "end_pass", "start"]
const OUTPUT_PORTS: Dictionary = {
	"action.next": 0,
	"branch.false": 0,
	"branch.true": 1,
	"decision.value": 0,
	"start.next": 0,
}
const INPUT_PORTS: Dictionary = {
	"action.in": 0,
	"branch.condition": 1,
	"branch.in": 0,
	"end_fail.in": 0,
	"end_pass.in": 0,
}


class SessionPort extends RefCounted:
	## Accepts a fresh bounded graph and returns whether it committed.
	func load_minimal_graph() -> bool:
		return false

	## Accepts the sole Boolean authoring command and returns whether it committed.
	func set_corrective_decision(_enabled: bool) -> bool:
		return false

	## Returns the accepted Boolean parameter.
	func corrective_decision() -> bool:
		return false

	## Returns the accepted Authoring revision.
	func graph_revision() -> int:
		return -1

	## Returns a defensive copy of accepted Authoring truth.
	func graph_snapshot() -> Dictionary:
		return {}

	## Runs the captured graph and Task cases synchronously.
	func run_public_case() -> CourseworkRunResult:
		return null

	## Returns the single completed frozen report.
	func completed_report() -> CourseworkRunResult:
		return null

	## Returns whether the completed report predates accepted Authoring truth.
	func report_is_out_of_date() -> bool:
		return false

	## Returns detached counters for integration evidence.
	func execution_counts() -> Dictionary:
		return {}


@onready var title_label: Label = %TitleLabel
@onready var instruction_label: Label = %InstructionLabel
@onready var load_button: Button = %LoadButton
@onready var decision_toggle: CheckButton = %DecisionToggle
@onready var run_button: Button = %RunButton
@onready var stale_badge: Label = %StaleBadge
@onready var graph_edit: GraphEdit = %GraphEdit
@onready var outcome_label: Label = %OutcomeLabel
@onready var reason_label: Label = %ReasonLabel
@onready var trace_title: Label = %TraceTitle
@onready var trace_list: ItemList = %TraceList
@onready var trace_detail: RichTextLabel = %TraceDetail
@onready var footer_label: Label = %FooterLabel

var _session: SessionPort = null
var _run_in_progress: bool = false
var _selected_trace: Dictionary = {}
var _highlighted_node_id: String = ""
var _graph_nodes: Dictionary = {}


## Injects the non-UI session owner before this adapter enters the scene tree.
func configure_session(session: SessionPort) -> void:
	_session = session
	if is_node_ready():
		load_minimal_graph()


func _ready() -> void:
	_configure_copy()
	_connect_controls()
	if _session == null:
		_set_interaction_locked(true)
		_render_internal_error(tr("Coursework session is unavailable."))
		return
	load_minimal_graph()
	run_button.grab_focus()


## Requests the one bounded Day-1 graph in its deliberately incorrect state.
func load_minimal_graph() -> bool:
	if _run_in_progress or _session == null or not _session.load_minimal_graph():
		return false
	decision_toggle.set_pressed_no_signal(_session.corrective_decision())
	if not _build_graph_projection(_session.graph_snapshot()):
		_render_internal_error(tr("The accepted graph could not be projected."))
		return false
	_render_visible_report()
	return true


## Requests the sole authored edit. The previous frozen report remains visible.
func set_corrective_decision(enabled: bool) -> bool:
	if _run_in_progress or _session == null:
		return false
	var accepted: bool = _session.set_corrective_decision(enabled)
	decision_toggle.set_pressed_no_signal(_session.corrective_decision())
	if not accepted:
		return false
	_update_decision_projection()
	_render_staleness()
	return true


## Runs synchronously through the injected owner, then renders only its report.
func run_public_case() -> CourseworkRunResult:
	if _run_in_progress or _session == null:
		return null
	_set_interaction_locked(true)
	var report: CourseworkRunResult = _session.run_public_case()
	_set_interaction_locked(false)
	if report == null or not is_instance_valid(report) or not report.is_valid():
		_render_internal_error(tr("The run did not produce a complete report."))
		return null
	_render_visible_report()
	return report


## Selects one frozen trace entry. No runner, Sandbox, or assertion work occurs.
func select_trace_step(index: int) -> bool:
	var trace: Array[Dictionary] = _visible_trace()
	if index < 0 or index >= trace.size() or index >= trace_list.item_count:
		return false
	_selected_trace = trace[index].duplicate(true)
	trace_list.select(index)
	_highlight_node(String(_selected_trace["node_id"]))
	_render_trace_detail(_selected_trace)
	return true


## Returns the exact currently visible completed report.
func visible_report() -> CourseworkRunResult:
	return _session.completed_report() if _session != null else null


## Returns whether the visible report belongs to older Authoring truth.
func visible_report_is_out_of_date() -> bool:
	return _session != null and _session.report_is_out_of_date()


## Returns a detached selected trace projection for integration evidence.
func selected_trace_projection() -> Dictionary:
	return _selected_trace.duplicate(true)


## Returns the authored node highlighted from the frozen trace.
func highlighted_node_id() -> String:
	return _highlighted_node_id


## Returns the number of trace rows actually rendered in the ItemList.
func visible_trace_count() -> int:
	return trace_list.item_count


## Returns one trace row actually rendered in the ItemList.
func visible_trace_row(index: int) -> String:
	return trace_list.get_item_text(index) \
		if index >= 0 and index < trace_list.item_count else ""


## Returns the player-readable outcome copy currently on screen.
func visible_outcome_text() -> String:
	return outcome_label.text


## Returns the player-readable reason copy currently on screen.
func visible_reason_text() -> String:
	return reason_label.text


## Returns the selected trace detail copy currently on screen.
func visible_trace_detail_text() -> String:
	return trace_detail.text


## Returns the visible report freshness badge.
func visible_staleness_text() -> String:
	return stale_badge.text


## Returns the accepted Authoring revision number.
func graph_revision() -> int:
	return _session.graph_revision() if _session != null else -1


func _execution_counts_for_test() -> Dictionary:
	return _session.execution_counts() if _session != null else {}


func _interactions_are_locked_for_test() -> bool:
	return _run_in_progress and load_button.disabled \
		and decision_toggle.disabled and run_button.disabled


func _graph_node_ids_for_test() -> Array[String]:
	var ids: Array[String] = []
	for raw_id: Variant in _graph_nodes.keys():
		ids.append(String(raw_id))
	ids.sort()
	return ids


func _configure_copy() -> void:
	title_label.text = tr("One More Build — Coursework Graph")
	instruction_label.text = tr(
		"Run the incorrect graph, inspect the failed trace, enable the corrective Action, then rerun.")
	load_button.text = tr("Load minimal graph")
	decision_toggle.text = tr("Use corrective Action")
	run_button.text = tr("Run public case")
	trace_title.text = tr("Executed trace — select any step")
	footer_label.text = tr(
		"Presentation reads the frozen report only; selection never reruns execution.")
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _connect_controls() -> void:
	load_button.pressed.connect(load_minimal_graph)
	decision_toggle.toggled.connect(set_corrective_decision)
	run_button.pressed.connect(run_public_case)
	trace_list.item_selected.connect(select_trace_step)
	load_button.focus_neighbor_right = decision_toggle.get_path()
	decision_toggle.focus_neighbor_left = load_button.get_path()
	decision_toggle.focus_neighbor_right = run_button.get_path()
	run_button.focus_neighbor_left = decision_toggle.get_path()


func _set_interaction_locked(locked: bool) -> void:
	_run_in_progress = locked
	load_button.disabled = locked
	decision_toggle.disabled = locked
	run_button.disabled = locked


func _build_graph_projection(snapshot: Dictionary) -> bool:
	var accepted_ids: Array[String] = []
	for raw_node: Variant in snapshot.get("nodes", []):
		var node: Dictionary = raw_node
		accepted_ids.append(String(node.get("node_id", "")))
	accepted_ids.sort()
	if accepted_ids != EXPECTED_NODE_IDS:
		return false
	_reset_graph_nodes()
	_add_graph_node("start", tr("Start"), Vector2(40, 210), [
		_slot(tr("Begin"), false, EXECUTION_PORT, true, EXECUTION_PORT)])
	_add_graph_node("decision", tr("Decision"), Vector2(40, 40), [
		_slot(_decision_copy(), false, BOOLEAN_PORT, true, BOOLEAN_PORT)])
	_add_graph_node("branch", tr("Branch"), Vector2(290, 170), [
		_slot(tr("Flow / false"), true, EXECUTION_PORT, true, EXECUTION_PORT),
		_slot(tr("Condition / true"), true, BOOLEAN_PORT, true, EXECUTION_PORT),
	])
	_add_graph_node("action", tr("Action"), Vector2(540, 80), [
		_slot(tr("Deliver parcel"), true, EXECUTION_PORT, true, EXECUTION_PORT)])
	_add_graph_node("end_fail", tr("End — unmet"), Vector2(540, 290), [
		_slot(tr("Public assertion"), true, EXECUTION_PORT, false, EXECUTION_PORT)])
	_add_graph_node("end_pass", tr("End — corrected"), Vector2(790, 80), [
		_slot(tr("Public assertion"), true, EXECUTION_PORT, false, EXECUTION_PORT)])
	if not _project_connections(snapshot.get("connections", [])):
		return false
	_highlight_node("")
	_reset_graph_view.call_deferred()
	return true


func _reset_graph_nodes() -> void:
	graph_edit.clear_connections()
	for child: Node in graph_edit.get_children():
		if child is GraphNode:
			graph_edit.remove_child(child)
			child.queue_free()
	_graph_nodes.clear()
	graph_edit.add_valid_connection_type(EXECUTION_PORT, EXECUTION_PORT)
	graph_edit.add_valid_connection_type(BOOLEAN_PORT, BOOLEAN_PORT)


func _project_connections(raw_connections: Array) -> bool:
	var connections: Array[Dictionary] = []
	for raw_connection: Variant in raw_connections:
		if typeof(raw_connection) != TYPE_DICTIONARY:
			return false
		connections.append(Dictionary(raw_connection))
	connections.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return String(left.get("connection_id", "")) \
			< String(right.get("connection_id", "")))
	for connection: Dictionary in connections:
		var source_key: String = "%s.%s" % [
			connection.get("source_node_id", ""), connection.get("source_port_id", "")]
		var target_key: String = "%s.%s" % [
			connection.get("target_node_id", ""), connection.get("target_port_id", "")]
		if not OUTPUT_PORTS.has(source_key) or not INPUT_PORTS.has(target_key):
			return false
		graph_edit.connect_node(
			StringName(connection["source_node_id"]), int(OUTPUT_PORTS[source_key]),
			StringName(connection["target_node_id"]), int(INPUT_PORTS[target_key]))
	return true


func _reset_graph_view() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	graph_edit.zoom = 0.8
	graph_edit.scroll_offset = Vector2.ZERO


func _add_graph_node(
	node_id: String, node_title: String, graph_position: Vector2,
	slots: Array[Dictionary]
) -> void:
	var node: GraphNode = GraphNode.new()
	node.name = StringName(node_id)
	node.title = node_title
	node.position_offset = graph_position
	node.custom_minimum_size = Vector2(185, 88)
	for slot_index: int in range(slots.size()):
		var descriptor: Dictionary = slots[slot_index]
		var label: Label = Label.new()
		label.text = descriptor["label"]
		label.custom_minimum_size = Vector2(155, 28)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		node.add_child(label)
		node.set_slot(
			slot_index,
			descriptor["left_enabled"], descriptor["left_type"],
			_port_color(descriptor["left_type"]),
			descriptor["right_enabled"], descriptor["right_type"],
			_port_color(descriptor["right_type"]))
	graph_edit.add_child(node)
	_graph_nodes[node_id] = node


func _slot(
	label: String, left_enabled: bool, left_type: int,
	right_enabled: bool, right_type: int
) -> Dictionary:
	return {
		"label": label,
		"left_enabled": left_enabled,
		"left_type": left_type,
		"right_enabled": right_enabled,
		"right_type": right_type,
	}


func _port_color(port_type: int) -> Color:
	return BOOLEAN_COLOR if port_type == BOOLEAN_PORT else EXECUTION_COLOR


func _decision_copy() -> String:
	return tr("Corrective path: ON") if _session.corrective_decision() \
		else tr("Corrective path: OFF")


func _update_decision_projection() -> void:
	var node: GraphNode = _graph_nodes.get("decision")
	if node != null and node.get_child_count() > 0:
		var label: Label = node.get_child(0)
		label.text = _decision_copy()


func _render_visible_report() -> void:
	var report: CourseworkRunResult = visible_report()
	if report == null:
		outcome_label.text = tr("No report yet — run the public case.")
		reason_label.text = tr("The loaded graph currently bypasses the corrective Action.")
		trace_list.clear()
		trace_detail.text = tr("Select a trace step after a run to inspect frozen values and path.")
		_selected_trace.clear()
		_highlight_node("")
		_render_staleness()
		return
	if not report.validation_pass():
		_render_diagnostics(report)
		return
	var cases: Array[CourseworkCaseResult] = report.case_results()
	if cases.is_empty():
		_render_internal_error(tr("The completed report contains no public case."))
		return
	var case_result: CourseworkCaseResult = cases[0]
	var case_word: String = tr("PASS") if case_result.case_pass() else tr("FAIL")
	var suite_word: String = tr("PASS") if report.suite_pass() else tr("FAIL")
	outcome_label.text = "%s: %s    %s: %s" % [
		tr("Public case"), case_word, tr("Suite"), suite_word]
	reason_label.text = _case_reason(case_result)
	_render_trace(case_result.trace())
	_render_staleness()


func _render_diagnostics(report: CourseworkRunResult) -> void:
	outcome_label.text = tr("Semantic validation failed — no case executed.")
	var rows: Array[String] = []
	for diagnostic: Dictionary in report.diagnostics():
		rows.append("%s · %s" % [
			diagnostic.get("reason_code", ""),
			diagnostic.get("primary_entity_id", "")])
	reason_label.text = "\n".join(rows)
	trace_list.clear()
	trace_detail.text = tr("Fix the located graph diagnostic before running cases.")
	_highlight_node("")
	_render_staleness()


func _case_reason(case_result: CourseworkCaseResult) -> String:
	if case_result.case_pass():
		return tr("The parcel was delivered; the authored public assertion passed.")
	for assertion: CourseworkAssertionResult in case_result.assertion_results():
		if not assertion.passed():
			return "%s %s: %s=%s, %s=%s." % [
				tr("Assertion"), assertion.assertion_id(), tr("expected"),
				_value_text(assertion.expected()), tr("observed"),
				_value_text(assertion.observed())]
	var record: Dictionary = case_result.to_dictionary()
	var ordinary_reason: String = String(record.get("ordinary_failure_reason", ""))
	return ordinary_reason if not ordinary_reason.is_empty() \
		else tr("The case failed before its public assertion passed.")


func _render_trace(trace: Array[Dictionary]) -> void:
	trace_list.clear()
	for entry: Dictionary in trace:
		trace_list.add_item("%02d  %-12s  %s" % [
			entry["step_number"], entry["node_id"], entry["outcome"]])
	if trace.is_empty():
		trace_detail.text = tr("No executed trace is available.")
		_selected_trace.clear()
		_highlight_node("")
		return
	select_trace_step(0)


func _render_trace_detail(entry: Dictionary) -> void:
	var produced: String = tr("not produced")
	if entry.get("produced_value_present", false):
		produced = _value_text(entry.get("produced_value"))
	var path: String = String(entry.get("selected_connection_id", ""))
	if path.is_empty():
		path = tr("none")
	var reason: String = String(entry.get("reason", ""))
	trace_detail.text = "%s %s — %s\n%s: %s\n%s: %s\n%s: %s\n%s:\n%s\n%s: %s" % [
		tr("Step"), entry.get("step_number", 0), entry.get("node_id", ""),
		tr("Consumed"), _value_text(entry.get("consumed_values", {})),
		tr("Produced"), produced,
		tr("Selected path"), path,
		tr("Sandbox observation"), _observation_text(entry.get("observation", {})),
		tr("Reason"), reason]


func _render_staleness() -> void:
	if visible_report() == null:
		stale_badge.text = tr("Report: none")
		stale_badge.modulate = Color("b8c5d6")
	elif visible_report_is_out_of_date():
		stale_badge.text = tr("Report: OUT OF DATE — still readable")
		stale_badge.modulate = Color("f4c95d")
	else:
		stale_badge.text = tr("Report: current")
		stale_badge.modulate = Color("9af0b3")


func _render_internal_error(message: String) -> void:
	outcome_label.text = tr("Run unavailable")
	reason_label.text = message
	_render_staleness()


func _highlight_node(node_id: String) -> void:
	_highlighted_node_id = node_id
	for raw_id: Variant in _graph_nodes.keys():
		var node: GraphNode = _graph_nodes[raw_id]
		var selected: bool = String(raw_id) == node_id
		node.selected = selected
		node.self_modulate = HIGHLIGHT_NODE_COLOR if selected else DEFAULT_NODE_COLOR


func _visible_trace() -> Array[Dictionary]:
	var report: CourseworkRunResult = visible_report()
	if report == null or not report.validation_pass():
		return []
	var cases: Array[CourseworkCaseResult] = report.case_results()
	return cases[0].trace() if not cases.is_empty() else []


func _value_text(value: Variant) -> String:
	if typeof(value) == TYPE_STRING:
		return String(value)
	return JSON.stringify(value)


func _observation_text(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY or Dictionary(value).is_empty():
		return _value_text(value)
	var keys: Array = Dictionary(value).keys()
	keys.sort()
	var rows: Array[String] = []
	for raw_key: Variant in keys:
		rows.append("%s=%s" % [String(raw_key), _value_text(value[raw_key])])
	return "\n".join(rows)
