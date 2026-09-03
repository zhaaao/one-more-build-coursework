class_name CourseworkWorkdayRecoveryProjection
extends RefCounted

## Feature-owned pure-data Workday projection and hydration seam for Story 006.
## It intentionally has no persistence, engine, GVET, Sandbox, report, or callback dependency.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CanonicalJsonIRType = preload("res://src/foundation/canonical_json_ir.gd")
const CanonicalCodec = preload("res://src/foundation/canonical_codec.gd")
const CourseworkRunInputType = preload("res://src/core/gvet/coursework_run_input.gd")
const CourseworkWorkdayLifecycleType = preload("res://src/feature/workday/coursework_workday_lifecycle.gd")

const CONTRACT_VERSION: String = "coursework_workday_recovery_projection_v1"
const V2_CONTRACT_VERSION: String = "coursework.workday.recovery.v2"

const RECOVERY_MODE_NONE: int = CourseworkWorkdayLifecycleType.RECOVERY_MODE_NONE
const RECOVERY_MODE_VOLUNTARY_LOCKED: int = CourseworkWorkdayLifecycleType.RECOVERY_MODE_VOLUNTARY_LOCKED
const RECOVERY_MODE_AUTHORITATIVE_LOCKED: int = CourseworkWorkdayLifecycleType.RECOVERY_MODE_AUTHORITATIVE_LOCKED

var _stable_lifecycle: Dictionary[String, Variant] = {}
var _recovery_mode: int = RECOVERY_MODE_NONE
var _voluntary_action: int = -1
var _locked_binding: CourseworkRunInput = null
var _charged_minutes: int = -1

## Creates an empty recovery seam. Call hydrate() only with a validated pure-data projection.
func _init() -> void:
	pass

## Captures the current stable Workday facts and, when charged, one immutable
## input record that can be reconstructed without retaining a live runner.
func project(lifecycle: CourseworkWorkdayLifecycle) -> DomainResult:
	if lifecycle == null:
		return _reject(&"workday_recovery_lifecycle_unavailable", "a Workday lifecycle is required")
	var stable_result: DomainResult = _capture_stable_lifecycle(lifecycle.snapshot())
	if not stable_result.is_success():
		return stable_result
	var recovery_result: DomainResult = _capture_recovery_intent(lifecycle)
	if not recovery_result.is_success():
		return recovery_result
	var projection: Dictionary[String, Variant] = {
		"contract_version": CONTRACT_VERSION,
		"stable_lifecycle": stable_result.value(),
		"recovery": recovery_result.value(),
	}
	if not CanonicalJsonIRType.validate_pure_json(projection).is_success():
		return _reject(&"workday_recovery_projection_not_pure", "the recovery projection contains unsupported live data")
	return DomainResultType.success(projection)

## Emits the ADR-0011 v2 projection. Charged intent carries semantic identity
## only; the graph is always reconstructed from selected authoring.graph.
func project_v2(lifecycle: CourseworkWorkdayLifecycle) -> DomainResult:
	if lifecycle == null:
		return _reject(&"workday_recovery_lifecycle_unavailable", "a Workday lifecycle is required")
	var stable_result: DomainResult = _capture_stable_lifecycle(lifecycle.snapshot())
	if not stable_result.is_success():
		return stable_result
	var intent_result: DomainResult = _capture_v2_charged_intent(lifecycle)
	if not intent_result.is_success():
		return intent_result
	var projection: Dictionary[String, Variant] = {
		"projection_version": V2_CONTRACT_VERSION,
		"stable_lifecycle": stable_result.value(),
		"charged_intent": intent_result.value(),
	}
	return DomainResultType.success(projection) if CanonicalJsonIRType.validate_pure_json(projection).is_success() \
		else _reject(&"workday_recovery_projection_not_pure", "the v2 recovery projection contains unsupported live data")

## Reconstructs v2 charged intent only from the supplied selected-generation
## authoring graph and admitted installed Task contract.
func hydrate_v2(
	projection: Variant,
	authoring_graph: Dictionary[String, Variant],
	task_contract: CourseworkTaskRecoveryContract
) -> DomainResult:
	if typeof(projection) != TYPE_DICTIONARY or task_contract == null:
		return _reject(&"workday_recovery_projection_invalid", "a v2 projection and admitted Task contract are required")
	var source: Dictionary = Dictionary(projection)
	if source.size() != 3 or String(source.get("projection_version", "")) != V2_CONTRACT_VERSION \
			or not source.has("stable_lifecycle") or not source.has("charged_intent"):
		return _reject(&"workday_recovery_projection_invalid", "the v2 recovery projection has an invalid shape")
	var stable_result: DomainResult = _capture_stable_lifecycle(source["stable_lifecycle"])
	if not stable_result.is_success():
		return stable_result
	var intent_result: DomainResult = _reconstruct_v2_charged_intent(source["charged_intent"], authoring_graph, task_contract)
	if not intent_result.is_success():
		return intent_result
	var parsed: Dictionary = Dictionary(intent_result.value())
	_stable_lifecycle = _typed_dictionary(stable_result.value())
	_recovery_mode = int(parsed["mode"])
	_voluntary_action = int(parsed["voluntary_action"])
	_locked_binding = parsed["binding"] as CourseworkRunInput
	_charged_minutes = int(parsed["charged_minutes"])
	return DomainResultType.success(status())

func _capture_v2_charged_intent(lifecycle: CourseworkWorkdayLifecycle) -> DomainResult:
	var recovery: DomainResult = _capture_recovery_intent(lifecycle)
	if not recovery.is_success():
		return recovery
	var record: Dictionary = Dictionary(recovery.value())
	if int(record["mode"]) == RECOVERY_MODE_NONE:
		return DomainResultType.success(null)
	var charge_result: DomainResult = lifecycle.recovery_charged_minutes()
	if not charge_result.is_success() or typeof(charge_result.value()) != TYPE_INT or int(charge_result.value()) <= 0:
		return _reject(&"workday_recovery_charge_invalid", "a charged recovery intent must retain its actual positive charge")
	var binding: Dictionary = Dictionary(record["binding"])
	var selected_ids: Array[Variant] = []
	for case_value: Variant in Array(binding.get("case_roster", [])):
		if typeof(case_value) != TYPE_DICTIONARY or not Dictionary(case_value).has("case_id"):
			return _reject(&"workday_recovery_binding_invalid", "a charged binding must retain ordered public case identities")
		selected_ids.append(String(Dictionary(case_value)["case_id"]))
	return DomainResultType.success({
		"mode": "voluntary_locked" if int(record["mode"]) == RECOVERY_MODE_VOLUNTARY_LOCKED else "authoritative_locked",
		"action_kind": "voluntary_suite" if int(record["mode"]) == RECOVERY_MODE_VOLUNTARY_LOCKED and int(record["voluntary_action"]) == CourseworkWorkdayLifecycle.OptionalAction.VOLUNTARY_SUITE else "targeted_case" if int(record["mode"]) == RECOVERY_MODE_VOLUNTARY_LOCKED else "authoritative_suite",
		"charged_minutes": int(charge_result.value()),
		"task_id": binding["task_id"],
		"day_index": binding["day_index"],
		"request_id": binding["request_id"],
		"graph_revision": binding["graph_revision"],
		"selected_public_case_ids": selected_ids,
		"admitted_content_digest": binding["admitted_content_digest"],
		"binding_identity_sha256": binding["identity_sha256"],
	})

func _reconstruct_v2_charged_intent(intent_value: Variant, authoring_graph: Dictionary[String, Variant], task_contract: CourseworkTaskRecoveryContract) -> DomainResult:
	if intent_value == null:
		return DomainResultType.success({"mode": RECOVERY_MODE_NONE, "voluntary_action": -1, "binding": null, "charged_minutes": 0})
	if typeof(intent_value) != TYPE_DICTIONARY or not authoring_graph.has("nodes") or not authoring_graph.has("connections"):
		return _reject(&"workday_recovery_binding_invalid", "v2 charged intent requires the sole authoring graph")
	var intent: Dictionary = Dictionary(intent_value)
	var shape_result: DomainResult = _validate_v2_intent_shape(intent, task_contract)
	if not shape_result.is_success(): return shape_result
	var selection_result: DomainResult = _selected_v2_cases(intent, task_contract)
	if not selection_result.is_success(): return selection_result
	return _reconstruct_v2_intent_binding(intent, authoring_graph, Array(selection_result.value()), task_contract)

func _validate_v2_intent_shape(intent: Dictionary, task_contract: CourseworkTaskRecoveryContract) -> DomainResult:
	var fields: Array[String] = ["mode", "action_kind", "charged_minutes", "task_id", "day_index", "request_id", "graph_revision", "selected_public_case_ids", "admitted_content_digest", "binding_identity_sha256"]
	if intent.size() != fields.size():
		return _reject(&"workday_recovery_binding_invalid", "v2 charged intent has an invalid shape")
	for field: String in fields:
		if not intent.has(field):
			return _reject(&"workday_recovery_binding_invalid", "v2 charged intent is incomplete")
	if typeof(intent["mode"]) != TYPE_STRING or typeof(intent["action_kind"]) != TYPE_STRING \
			or typeof(intent["charged_minutes"]) != TYPE_INT or int(intent["charged_minutes"]) <= 0 \
			or String(intent["task_id"]) != task_contract.task_id() \
			or typeof(intent["selected_public_case_ids"]) != TYPE_ARRAY:
		return _reject(&"workday_recovery_binding_invalid", "v2 charged intent does not match admitted Task content")
	var mode_name: String = String(intent["mode"])
	var action_kind: String = String(intent["action_kind"])
	if (mode_name == "voluntary_locked" and action_kind != "targeted_case" and action_kind != "voluntary_suite") \
			or (mode_name == "authoritative_locked" and action_kind != "authoritative_suite") \
			or (mode_name != "voluntary_locked" and mode_name != "authoritative_locked"):
		return _reject(&"workday_recovery_binding_invalid", "v2 charged intent has an invalid mode and action combination")
	return DomainResultType.success(null)

func _selected_v2_cases(intent: Dictionary, task_contract: CourseworkTaskRecoveryContract) -> DomainResult:
	var action_kind: String = String(intent["action_kind"])
	var selected_ids: Array[Variant] = Array(intent["selected_public_case_ids"])
	var contract_cases: Array[Variant] = task_contract.ordered_public_cases()
	if (action_kind == "targeted_case" and selected_ids.size() != 1) \
			or (action_kind != "targeted_case" and selected_ids.size() != contract_cases.size()):
		return _reject(&"workday_recovery_binding_invalid", "v2 charged intent has an invalid selected-case count")
	if action_kind != "targeted_case":
		for index: int in range(contract_cases.size()):
			if String(selected_ids[index]) != String(Dictionary(contract_cases[index]).get("case_id", "")):
				return _reject(&"workday_recovery_binding_invalid", "suite recovery must retain the complete installed case order")
	var selected_cases: Array[Variant] = []
	for selected_id_value: Variant in selected_ids:
		var found: bool = false
		for case_value: Variant in task_contract.ordered_public_cases():
			if typeof(case_value) == TYPE_DICTIONARY and String(Dictionary(case_value).get("case_id", "")) == String(selected_id_value):
				selected_cases.append(Dictionary(case_value).duplicate(true))
				found = true
				break
		if not found:
			return _reject(&"workday_recovery_binding_invalid", "v2 charged intent contains an unknown public case")
	return DomainResultType.success(selected_cases)

func _reconstruct_v2_intent_binding(intent: Dictionary, authoring_graph: Dictionary[String, Variant], selected_cases: Array[Variant], task_contract: CourseworkTaskRecoveryContract) -> DomainResult:
	var execution_cases_result: DomainResult = _execution_cases_from_authored(selected_cases)
	if not execution_cases_result.is_success():
		return execution_cases_result
	var execution_cases: Array[Variant] = Array(execution_cases_result.value())
	var execution_graph_result: DomainResult = _execution_graph_from_authoring(authoring_graph, task_contract.task_id())
	if not execution_graph_result.is_success():
		return execution_graph_result
	var execution_graph: Dictionary[String, Variant] = _typed_dictionary(execution_graph_result.value())
	var binding_result: DomainResult = CourseworkRunInputType.create(String(intent["task_id"]), int(intent["day_index"]), String(intent["request_id"]), int(intent["graph_revision"]), execution_graph, execution_cases)
	if not binding_result.is_success():
		return binding_result
	if not binding_result.value() is CourseworkRunInputType:
		return _reject(&"workday_recovery_binding_invalid", "v2 charged intent cannot reconstruct a Run input")
	var binding: CourseworkRunInput = binding_result.value() as CourseworkRunInput
	if binding.admitted_content_digest() != String(intent["admitted_content_digest"]) \
			or binding.identity_sha256() != String(intent["binding_identity_sha256"]):
		return _reject(&"workday_recovery_binding_identity_mismatch", "v2 charged intent does not match the sole authoring graph")
	var action_kind: String = String(intent["action_kind"])
	var mode_name: String = String(intent["mode"])
	var voluntary_action: int = CourseworkWorkdayLifecycle.OptionalAction.VOLUNTARY_SUITE if action_kind == "voluntary_suite" else CourseworkWorkdayLifecycle.OptionalAction.TARGETED_CASE
	var mode: int = RECOVERY_MODE_VOLUNTARY_LOCKED if mode_name == "voluntary_locked" else RECOVERY_MODE_AUTHORITATIVE_LOCKED
	return DomainResultType.success({"mode": mode, "voluntary_action": voluntary_action if mode == RECOVERY_MODE_VOLUNTARY_LOCKED else -1, "binding": binding, "charged_minutes": int(intent["charged_minutes"])})

## Builds the immutable GVET case ABI from the selected Task-authored cases.
## This derived value is never retained by the Save projection.
func _execution_cases_from_authored(selected_cases: Array[Variant]) -> DomainResult:
	var execution_cases: Array[Variant] = []
	for raw_case: Variant in selected_cases:
		if typeof(raw_case) != TYPE_DICTIONARY:
			return _reject(&"workday_recovery_binding_invalid", "selected Task content contains an invalid public case")
		var authored_case: Dictionary = Dictionary(raw_case)
		var case_id: Variant = authored_case.get("case_id", null)
		var initial_state: Variant = authored_case.get("initial_state", null)
		var authored_assertions: Variant = authored_case.get("assertions", null)
		if typeof(case_id) != TYPE_STRING or String(case_id).is_empty() \
				or typeof(initial_state) != TYPE_DICTIONARY or typeof(authored_assertions) != TYPE_ARRAY:
			return _reject(&"workday_recovery_binding_invalid", "selected Task content lacks the public execution case fields")
		var assertions_result: DomainResult = _execution_assertions_from_authored(Array(authored_assertions))
		if not assertions_result.is_success():
			return assertions_result
		execution_cases.append({
			"case_id": String(case_id),
			"content": {
				"initial_state": Dictionary(initial_state).duplicate(true),
				"assertions": assertions_result.value(),
			},
		})
	return DomainResultType.success(execution_cases)

func _execution_assertions_from_authored(authored_assertions: Array) -> DomainResult:
	if authored_assertions.is_empty():
		return _reject(&"workday_recovery_binding_invalid", "a selected public case requires at least one assertion")
	var execution_assertions: Array[Variant] = []
	for raw_assertion: Variant in authored_assertions:
		if typeof(raw_assertion) != TYPE_DICTIONARY:
			return _reject(&"workday_recovery_binding_invalid", "a selected public assertion is invalid")
		var assertion: Dictionary = Dictionary(raw_assertion)
		var assertion_id: Variant = assertion.get("assertion_id", null)
		var expected_facts: Variant = assertion.get("expected_facts", null)
		if typeof(assertion_id) != TYPE_STRING or String(assertion_id).is_empty() \
				or typeof(expected_facts) != TYPE_ARRAY or Array(expected_facts).is_empty():
			return _reject(&"workday_recovery_binding_invalid", "a selected public assertion lacks expected facts")
		var expected: Dictionary[String, Variant] = {}
		for raw_fact: Variant in Array(expected_facts):
			if typeof(raw_fact) != TYPE_DICTIONARY:
				return _reject(&"workday_recovery_binding_invalid", "a selected expected fact is invalid")
			var fact: Dictionary = Dictionary(raw_fact)
			var fact_id: Variant = fact.get("fact_id", null)
			if typeof(fact_id) != TYPE_STRING or String(fact_id).is_empty() \
					or not fact.has("value") or expected.has(String(fact_id)):
				return _reject(&"workday_recovery_binding_invalid", "selected expected facts require unique identities and values")
			expected[String(fact_id)] = fact["value"]
		execution_assertions.append({"assertion_id": String(assertion_id), "expected": expected})
	return DomainResultType.success(execution_assertions)

## Canonicalizes the selected generation's sole authoring graph for RunInput.
## The source graph remains owner data; this GVET shape exists only while hydrating.
func _execution_graph_from_authoring(authoring_graph: Dictionary[String, Variant], task_id: String) -> DomainResult:
	var raw_nodes: Variant = authoring_graph.get("nodes", null)
	var raw_connections: Variant = authoring_graph.get("connections", null)
	if typeof(raw_nodes) != TYPE_ARRAY or typeof(raw_connections) != TYPE_ARRAY:
		return _reject(&"workday_recovery_binding_invalid", "the sole authoring graph lacks nodes or connections")
	var nodes: Array[Dictionary] = []
	var categories: Dictionary[String, String] = {}
	for raw_node: Variant in Array(raw_nodes):
		if typeof(raw_node) != TYPE_DICTIONARY:
			return _reject(&"workday_recovery_binding_invalid", "the sole authoring graph contains an invalid node")
		var node_result: DomainResult = _execution_node_from_authoring(Dictionary(raw_node))
		if not node_result.is_success():
			return node_result
		var node: Dictionary[String, Variant] = _typed_dictionary(node_result.value())
		var node_id: String = String(node["node_id"])
		if categories.has(node_id):
			return _reject(&"workday_recovery_binding_invalid", "the sole authoring graph repeats a node identity")
		categories[node_id] = String(node.get("_recovery_category", ""))
		node.erase("_recovery_category")
		nodes.append(node)
	nodes.sort_custom(_stable_record_id_less)
	var connections: Array[Dictionary] = []
	for raw_connection: Variant in Array(raw_connections):
		if typeof(raw_connection) != TYPE_DICTIONARY:
			return _reject(&"workday_recovery_binding_invalid", "the sole authoring graph contains an invalid connection")
		var connection_result: DomainResult = _execution_connection_from_authoring(Dictionary(raw_connection), categories)
		if not connection_result.is_success():
			return connection_result
		connections.append(_typed_dictionary(connection_result.value()))
	connections.sort_custom(_stable_record_id_less)
	var fixture_id: String = "coursework.%s" % task_id.trim_prefix("task.")
	return DomainResultType.success({
		"graph_codec_version": "authoring_graph_v1",
		"fixture_id": fixture_id,
		"nodes": nodes,
		"connections": connections,
	})

func _execution_node_from_authoring(authored_node: Dictionary) -> DomainResult:
	var node_id: Variant = authored_node.get("node_id", null)
	var variant_id: Variant = authored_node.get("variant_id", null)
	var category: Variant = authored_node.get("category", "")
	if typeof(node_id) != TYPE_STRING or String(node_id).is_empty() \
			or typeof(variant_id) != TYPE_STRING or String(variant_id).is_empty() \
			or typeof(category) != TYPE_STRING:
		return _reject(&"workday_recovery_binding_invalid", "an authoring node lacks stable identity or category fields")
	var parameters_result: DomainResult = _execution_parameters_from_authoring(authored_node, String(variant_id), String(category))
	if not parameters_result.is_success():
		return parameters_result
	var anchor: Variant = authored_node.get("anchor", {})
	var anchor_x: Variant = authored_node.get("anchor_x", Dictionary(anchor).get("x", 0)) if typeof(anchor) == TYPE_DICTIONARY else authored_node.get("anchor_x", 0)
	var anchor_y: Variant = authored_node.get("anchor_y", Dictionary(anchor).get("y", 0)) if typeof(anchor) == TYPE_DICTIONARY else authored_node.get("anchor_y", 0)
	if typeof(anchor_x) != TYPE_INT or typeof(anchor_y) != TYPE_INT:
		return _reject(&"workday_recovery_binding_invalid", "authoring node anchors must be integers")
	return DomainResultType.success({
		"node_id": String(node_id),
		"variant_id": String(variant_id),
		"anchor_x": int(anchor_x),
		"anchor_y": int(anchor_y),
		"parameter_values": parameters_result.value(),
		"_recovery_category": String(category),
	})

func _execution_parameters_from_authoring(authored_node: Dictionary, variant_id: String, category: String) -> DomainResult:
	var map_result: DomainResult = _parameter_map_from_authoring(authored_node, variant_id)
	if not map_result.is_success(): return map_result
	var parameter_map: Dictionary[String, Variant] = _typed_dictionary(map_result.value())
	var category_result: DomainResult = _map_execution_operation(parameter_map, category)
	if not category_result.is_success(): return category_result
	return _ordered_execution_parameters(parameter_map)

func _parameter_map_from_authoring(authored_node: Dictionary, variant_id: String) -> DomainResult:
	var parameter_map: Dictionary[String, Variant] = {}
	if authored_node.has("parameters") and authored_node.has("parameter_values"):
		return _reject(&"workday_recovery_binding_invalid", "an authoring node has ambiguous parameter fields")
	var source: Variant = authored_node.get("parameters", authored_node.get("parameter_values", {}))
	if typeof(source) == TYPE_DICTIONARY:
		for raw_key: Variant in Dictionary(source).keys():
			if typeof(raw_key) != TYPE_STRING or String(raw_key).is_empty():
				return _reject(&"workday_recovery_binding_invalid", "an authoring parameter has an invalid identity")
			parameter_map[String(raw_key)] = Dictionary(source)[raw_key]
	elif typeof(source) == TYPE_ARRAY:
		var values: Array = Array(source)
		var records: bool = not values.is_empty() and typeof(values[0]) == TYPE_DICTIONARY
		if records:
			for raw_parameter: Variant in values:
				if typeof(raw_parameter) != TYPE_DICTIONARY:
					return _reject(&"workday_recovery_binding_invalid", "an authoring parameter record is invalid")
				var parameter: Dictionary = Dictionary(raw_parameter)
				var parameter_id: Variant = parameter.get("parameter_id", null)
				if parameter.size() != 2 or typeof(parameter_id) != TYPE_STRING or String(parameter_id).is_empty() \
						or not parameter.has("value") or parameter_map.has(String(parameter_id)):
					return _reject(&"workday_recovery_binding_invalid", "an authoring parameter record is incomplete")
				parameter_map[String(parameter_id)] = parameter["value"]
		else:
			var canonical_result: DomainResult = _canonical_parameter_map(variant_id, values)
			if not canonical_result.is_success():
				return canonical_result
			parameter_map = _typed_dictionary(canonical_result.value())
	else:
		return _reject(&"workday_recovery_binding_invalid", "authoring parameters must be a Dictionary or array")
	return DomainResult.success(parameter_map)

func _map_execution_operation(parameter_map: Dictionary[String, Variant], category: String) -> DomainResult:
	if category == "Action":
		var action_id: Variant = parameter_map.get("operation_id", parameter_map.get("action_id", null))
		if typeof(action_id) != TYPE_STRING or String(action_id).is_empty():
			return _reject(&"workday_recovery_binding_invalid", "an Action node lacks its operation identity")
		parameter_map.erase("operation_id")
		parameter_map["action_id"] = String(action_id)
	elif category == "Query":
		var query_id: Variant = parameter_map.get("operation_id", parameter_map.get("query_id", null))
		if typeof(query_id) != TYPE_STRING or String(query_id).is_empty():
			return _reject(&"workday_recovery_binding_invalid", "a Query node lacks its operation identity")
		parameter_map.erase("operation_id")
		parameter_map["query_id"] = String(query_id)
	return DomainResult.success(null)

func _ordered_execution_parameters(parameter_map: Dictionary[String, Variant]) -> DomainResult:
	var parameter_ids: Array[String] = []
	for parameter_id: String in parameter_map.keys():
		parameter_ids.append(parameter_id)
	parameter_ids.sort()
	var values: Array[Dictionary] = []
	for parameter_id: String in parameter_ids:
		values.append({"parameter_id": parameter_id, "value": parameter_map[parameter_id]})
	return DomainResultType.success(values)

## Maps GraphModel's ordered scalar parameter ABI back to the fixed registered
## coursework semantics.  The order is contract data, never inferred from a
## value, and does not enter the persisted Workday projection.
func _canonical_parameter_map(variant_id: String, values: Array) -> DomainResult:
	var parameter_ids: Array[String] = []
	match variant_id:
		"flow.start", "flow.end", "flow.branch.boolean": parameter_ids = []
		"flow.repeat.bounded": parameter_ids = ["count"]
		"value.constant.numeric": parameter_ids = ["value"]
		"value.compare.numeric": parameter_ids = ["operator"]
		"parcel.query.battery_units", "parcel.query.path_is_clear": parameter_ids = ["operation_id"]
		"parcel.query.front_sensor_matches_color": parameter_ids = ["colour", "operation_id"]
		"parcel.action.turn": parameter_ids = ["direction", "operation_id"]
		"parcel.action.advance_conveyors", "parcel.action.charge", "parcel.action.drop_front", "parcel.action.move_forward", "parcel.action.pick_up_front": parameter_ids = ["operation_id"]
		_:
			return _reject(&"workday_recovery_binding_invalid", "a canonical authoring node uses an unregistered Task variant")
	if values.size() != parameter_ids.size():
		return _reject(&"workday_recovery_binding_invalid", "canonical authoring parameter cardinality differs from its fixed variant contract")
	var result: Dictionary[String, Variant] = {}
	for index: int in range(values.size()):
		var value: Variant = values[index]
		if not _is_canonical_parameter_scalar(value):
			return _reject(&"workday_recovery_binding_invalid", "canonical authoring parameters must use admitted scalar values")
		result[parameter_ids[index]] = value
	return DomainResultType.success(result)

static func _is_canonical_parameter_scalar(value: Variant) -> bool:
	return typeof(value) == TYPE_BOOL or typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT \
		or typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME

func _execution_connection_from_authoring(authored_connection: Dictionary, categories: Dictionary[String, String]) -> DomainResult:
	var connection_id: Variant = authored_connection.get("connection_id", null)
	var source_node_id: Variant = authored_connection.get("source_node_id", authored_connection.get("output_node_id", null))
	var source_port_id: Variant = authored_connection.get("source_port_id", authored_connection.get("output_port_id", null))
	var target_node_id: Variant = authored_connection.get("target_node_id", authored_connection.get("input_node_id", null))
	var target_port_id: Variant = authored_connection.get("target_port_id", authored_connection.get("input_port_id", null))
	if typeof(connection_id) != TYPE_STRING or String(connection_id).is_empty() \
			or typeof(source_node_id) != TYPE_STRING or String(source_node_id).is_empty() \
			or typeof(source_port_id) != TYPE_STRING or String(source_port_id).is_empty() \
			or typeof(target_node_id) != TYPE_STRING or String(target_node_id).is_empty() \
			or typeof(target_port_id) != TYPE_STRING or String(target_port_id).is_empty() \
			or not categories.has(String(source_node_id)) or not categories.has(String(target_node_id)):
		return _reject(&"workday_recovery_binding_invalid", "an authoring connection lacks valid endpoint identities")
	var projected_port: String = String(source_port_id)
	if projected_port == "value" and categories[String(source_node_id)] == "Compare":
		projected_port = "result"
	return DomainResultType.success({
		"connection_id": String(connection_id),
		"source_node_id": String(source_node_id),
		"source_port_id": projected_port,
		"target_node_id": String(target_node_id),
		"target_port_id": String(target_port_id),
	})

static func _stable_record_id_less(left: Dictionary, right: Dictionary) -> bool:
	return String(left.get("node_id", left.get("connection_id", ""))) < String(right.get("node_id", right.get("connection_id", "")))

## Validates a detached pure-data projection before replacing this seam's
## recovered truth. A rejected candidate leaves the existing recovered truth unchanged.
func hydrate(projection: Variant) -> DomainResult:
	var parsed_result: DomainResult = _parse_projection(projection)
	if not parsed_result.is_success():
		return parsed_result
	var parsed_value: Variant = parsed_result.value()
	if typeof(parsed_value) != TYPE_DICTIONARY:
		return _reject(&"workday_recovery_projection_invalid", "the parsed recovery projection is invalid")
	var parsed: Dictionary = parsed_value
	var reconstructed_value: Variant = parsed["binding"]
	var reconstructed: CourseworkRunInput = null
	if reconstructed_value != null:
		if not reconstructed_value is CourseworkRunInputType:
			return _reject(&"workday_recovery_binding_invalid", "the parsed recovered binding has an invalid type")
		reconstructed = reconstructed_value
	_stable_lifecycle = _typed_dictionary(parsed["stable_lifecycle"])
	if _stable_lifecycle.is_empty():
		return _reject(&"workday_recovery_stable_state_invalid", "the parsed stable lifecycle cannot be copied")
	var recovery_mode_value: Variant = parsed.get("recovery_mode", null)
	var voluntary_action_value: Variant = parsed.get("voluntary_action", null)
	if typeof(recovery_mode_value) != TYPE_INT or typeof(voluntary_action_value) != TYPE_INT:
		return _reject(&"workday_recovery_record_invalid", "the parsed recovery mode or action has an invalid type")
	var parsed_recovery_mode: int = int(recovery_mode_value)
	var parsed_voluntary_action: int = int(voluntary_action_value)
	_recovery_mode = parsed_recovery_mode
	_voluntary_action = parsed_voluntary_action
	_locked_binding = reconstructed
	return DomainResultType.success(status())

## Reconstructs the charged input only for a locked recovered intent.
func reconstruct_retry_input() -> DomainResult:
	if _recovery_mode != RECOVERY_MODE_VOLUNTARY_LOCKED \
			and _recovery_mode != RECOVERY_MODE_AUTHORITATIVE_LOCKED:
		return _reject(&"workday_recovery_retry_unavailable", "no locked recovered intent is available for retry")
	if _locked_binding == null or not _locked_binding.is_valid():
		return _reject(&"workday_recovery_binding_unavailable", "the recovered binding is not valid")
	return DomainResultType.success(_locked_binding)

## Builds a fresh executable Workday owner from this validated projection.
## Existing lifecycle instances are never mutated when restoration is rejected.
func restore_lifecycle(
	policy: CourseworkWorkdayPolicy,
	issuer: CourseworkWorkdayLifecycle.AcceptedOutcomeIssuer,
	operational_authoring_revision: int = -1
) -> DomainResult:
	return CourseworkWorkdayLifecycleType.restore_from_recovery_projection(
		policy, issuer, _stable_lifecycle, _recovery_mode, _voluntary_action, _locked_binding,
		_charged_minutes, operational_authoring_revision)

## Accepts only the exact recovered input identity and never applies another charge.
func retry_same_intent(candidate: CourseworkRunInput) -> DomainResult:
	var binding_result: DomainResult = reconstruct_retry_input()
	if not binding_result.is_success():
		return binding_result
	if candidate == null or not candidate.is_valid() \
			or candidate.identity_sha256() != _locked_binding.identity_sha256():
		return _reject(&"workday_recovery_retry_identity_mismatch", "retry must use the exact recovered charged input")
	return DomainResultType.success(status())

## Ends only a recovered voluntary intent while preserving its already charged stable facts.
## Authoritative delivery remains locked because abandoning it would violate delivery finality.
func abandon_locked_intent() -> DomainResult:
	if _recovery_mode == RECOVERY_MODE_AUTHORITATIVE_LOCKED:
		return _reject(&"workday_recovery_authoritative_abandon_forbidden", "authoritative delivery must retry its exact charged intent")
	if _recovery_mode != RECOVERY_MODE_VOLUNTARY_LOCKED:
		return _reject(&"workday_recovery_abandon_unavailable", "only a locked voluntary intent may be abandoned")
	_recovery_mode = RECOVERY_MODE_NONE
	_voluntary_action = -1
	_locked_binding = null
	return DomainResultType.success(status())

## Returns detached stable facts and the current pure-data recovery disposition.
func status() -> Dictionary[String, Variant]:
	return {
		"stable_lifecycle": _stable_lifecycle.duplicate(true),
		"recovery_mode": _recovery_mode_name(),
		"voluntary_action": _voluntary_action,
		"binding_identity_sha256": "" if _locked_binding == null else _locked_binding.identity_sha256(),
	}

func _capture_stable_lifecycle(snapshot: Variant) -> DomainResult:
	if typeof(snapshot) != TYPE_DICTIONARY:
		return _reject(&"workday_recovery_stable_state_invalid", "the lifecycle stable projection must be a Dictionary")
	var source: Dictionary = snapshot
	var field_result: DomainResult = _validate_stable_lifecycle_fields(source)
	if not field_result.is_success():
		return field_result
	var receipts: Array[Variant] = []
	for raw_receipt: Variant in source["committed_receipts"]:
		if typeof(raw_receipt) != TYPE_DICTIONARY:
			return _reject(&"workday_recovery_receipt_invalid", "stable receipts must be pure dictionaries")
		if not CanonicalJsonIRType.validate_pure_json(raw_receipt).is_success():
			return _reject(&"workday_recovery_receipt_invalid", "stable receipts must not contain live data")
		receipts.append(Dictionary(raw_receipt).duplicate(true))
	var stable: Dictionary[String, Variant] = {
		"state": String(source["state"]),
		"current_day_index": source["current_day_index"],
		"day_count": source["day_count"],
		"elapsed_minutes": source["elapsed_minutes"],
		"authorized_capacity_minutes": source["authorized_capacity_minutes"],
		"overtime_authorized": source["overtime_authorized"],
		"authoring_revision": source["authoring_revision"],
		"rework_due_minutes": source["rework_due_minutes"],
		"committed_receipts": receipts,
	}
	if not CanonicalJsonIRType.validate_pure_json(stable).is_success():
		return _reject(&"workday_recovery_stable_state_invalid", "stable lifecycle state must be pure data")
	return DomainResultType.success(stable)

func _validate_stable_lifecycle_fields(source: Dictionary) -> DomainResult:
	var required_fields: Array[String] = [
		"state", "current_day_index", "day_count", "elapsed_minutes",
		"authorized_capacity_minutes", "overtime_authorized", "authoring_revision",
		"rework_due_minutes", "committed_receipts",
	]
	for field: String in required_fields:
		if not source.has(field):
			return _reject(&"workday_recovery_stable_state_invalid", "the lifecycle stable projection is incomplete")
	if typeof(source["state"]) != TYPE_STRING_NAME and typeof(source["state"]) != TYPE_STRING \
			or typeof(source["current_day_index"]) != TYPE_INT \
			or typeof(source["day_count"]) != TYPE_INT \
			or typeof(source["elapsed_minutes"]) != TYPE_INT \
			or typeof(source["authorized_capacity_minutes"]) != TYPE_INT \
			or typeof(source["overtime_authorized"]) != TYPE_BOOL \
			or typeof(source["authoring_revision"]) != TYPE_INT \
			or typeof(source["rework_due_minutes"]) != TYPE_INT \
			or typeof(source["committed_receipts"]) != TYPE_ARRAY:
		return _reject(&"workday_recovery_stable_state_invalid", "the lifecycle stable projection has invalid field types")
	return DomainResultType.success(null)

func _capture_recovery_intent(lifecycle: CourseworkWorkdayLifecycle) -> DomainResult:
	var voluntary_binding: CourseworkRunInput = lifecycle.voluntary_binding()
	if voluntary_binding != null:
		var voluntary_status: Dictionary[String, Variant] = lifecycle.voluntary_transaction_status()
		var action: int = _voluntary_action_from_status(voluntary_status)
		if action < CourseworkWorkdayLifecycle.OptionalAction.TARGETED_CASE:
			return _reject(&"workday_recovery_voluntary_action_invalid", "the charged voluntary action is not recoverable")
		return _recovery_record(RECOVERY_MODE_VOLUNTARY_LOCKED, action, voluntary_binding)
	var authoritative_binding: CourseworkRunInput = lifecycle.authoritative_delivery_binding()
	if authoritative_binding != null:
		return _recovery_record(RECOVERY_MODE_AUTHORITATIVE_LOCKED, -1, authoritative_binding)
	return DomainResultType.success({"mode": RECOVERY_MODE_NONE, "voluntary_action": -1, "binding": {}})

func _recovery_record(mode: int, voluntary_action: int, binding: CourseworkRunInput) -> DomainResult:
	if binding == null or not binding.is_valid():
		return _reject(&"workday_recovery_binding_invalid", "the charged recovery binding must be valid")
	var binding_record: Dictionary[String, Variant] = {
		"task_id": binding.task_id(),
		"day_index": binding.day_index(),
		"request_id": binding.request_id(),
		"graph_revision": binding.graph_revision(),
		"graph_snapshot": binding.graph_snapshot().duplicate(true),
		"case_roster": binding.case_roster().duplicate(true),
		"admitted_content_digest": binding.admitted_content_digest(),
		"identity_sha256": binding.identity_sha256(),
	}
	if not CanonicalJsonIRType.validate_pure_json(binding_record).is_success():
		return _reject(&"workday_recovery_binding_invalid", "the immutable input record contains unsupported live data")
	return DomainResultType.success({"mode": mode, "voluntary_action": voluntary_action, "binding": binding_record})

func _parse_projection(projection: Variant) -> DomainResult:
	if typeof(projection) != TYPE_DICTIONARY:
		return _reject(&"workday_recovery_projection_invalid", "the recovery projection must be a Dictionary")
	var source: Dictionary = projection
	if not CanonicalJsonIRType.validate_pure_json(source).is_success():
		return _reject(&"workday_recovery_projection_not_pure", "the recovery projection contains unsupported live data")
	if source.size() != 3 or source.get("contract_version", "") != CONTRACT_VERSION \
			or not source.has("stable_lifecycle") or not source.has("recovery"):
		return _reject(&"workday_recovery_projection_invalid", "the recovery projection has an invalid contract shape")
	var stable_result: DomainResult = _capture_stable_lifecycle(source["stable_lifecycle"])
	if not stable_result.is_success():
		return stable_result
	var recovery_result: DomainResult = _parse_recovery_record(source["recovery"])
	if not recovery_result.is_success():
		return recovery_result
	var recovery_value: Variant = recovery_result.value()
	if typeof(recovery_value) != TYPE_DICTIONARY:
		return _reject(&"workday_recovery_record_invalid", "the parsed recovery disposition is invalid")
	var recovery: Dictionary = recovery_value
	return DomainResultType.success({
		"stable_lifecycle": stable_result.value(),
		"recovery_mode": recovery["mode"],
		"voluntary_action": recovery["voluntary_action"],
		"binding": recovery["binding"],
	})

func _parse_recovery_record(value: Variant) -> DomainResult:
	if typeof(value) != TYPE_DICTIONARY:
		return _reject(&"workday_recovery_record_invalid", "the recovery disposition must be a Dictionary")
	var record: Dictionary = value
	if record.size() != 3 or not record.has("mode") or not record.has("voluntary_action") or not record.has("binding") \
			or typeof(record["mode"]) != TYPE_INT or typeof(record["voluntary_action"]) != TYPE_INT \
			or typeof(record["binding"]) != TYPE_DICTIONARY:
		return _reject(&"workday_recovery_record_invalid", "the recovery disposition has an invalid shape")
	var mode_value: Variant = record["mode"]
	var action_value: Variant = record["voluntary_action"]
	if typeof(mode_value) != TYPE_INT or typeof(action_value) != TYPE_INT:
		return _reject(&"workday_recovery_record_invalid", "the recovery mode or action has an invalid type")
	var mode: int = int(mode_value)
	if mode == RECOVERY_MODE_NONE:
		if not Dictionary(record["binding"]).is_empty() or int(action_value) != -1:
			return _reject(&"workday_recovery_record_invalid", "an unlocked recovery disposition must not retain an intent")
		return DomainResultType.success({"mode": mode, "voluntary_action": -1, "binding": null})
	if mode != RECOVERY_MODE_VOLUNTARY_LOCKED and mode != RECOVERY_MODE_AUTHORITATIVE_LOCKED:
		return _reject(&"workday_recovery_record_invalid", "the recovery mode is not supported by stable hydration")
	var action: int = int(action_value)
	if (mode == RECOVERY_MODE_VOLUNTARY_LOCKED \
			and (action < CourseworkWorkdayLifecycle.OptionalAction.TARGETED_CASE \
			or action > CourseworkWorkdayLifecycle.OptionalAction.VOLUNTARY_SUITE)) \
		or (mode == RECOVERY_MODE_AUTHORITATIVE_LOCKED and action != -1):
		return _reject(&"workday_recovery_record_invalid", "the recovered action does not match its recovery mode")
	var input_result: DomainResult = _reconstruct_input(Dictionary(record["binding"]))
	if not input_result.is_success():
		return input_result
	return DomainResultType.success({"mode": mode, "voluntary_action": action, "binding": input_result.value()})

func _reconstruct_input(record: Dictionary) -> DomainResult:
	var fields: Array[String] = [
		"task_id", "day_index", "request_id", "graph_revision", "graph_snapshot",
		"case_roster", "admitted_content_digest", "identity_sha256",
	]
	if record.size() != fields.size():
		return _reject(&"workday_recovery_binding_invalid", "the immutable input record has an invalid shape")
	for field: String in fields:
		if not record.has(field):
			return _reject(&"workday_recovery_binding_invalid", "the immutable input record is incomplete")
	if typeof(record["task_id"]) != TYPE_STRING or typeof(record["day_index"]) != TYPE_INT \
			or typeof(record["request_id"]) != TYPE_STRING or typeof(record["graph_revision"]) != TYPE_INT \
			or typeof(record["graph_snapshot"]) != TYPE_DICTIONARY or typeof(record["case_roster"]) != TYPE_ARRAY \
			or typeof(record["admitted_content_digest"]) != TYPE_STRING or typeof(record["identity_sha256"]) != TYPE_STRING:
		return _reject(&"workday_recovery_binding_invalid", "the immutable input record has invalid field types")
	var input_result: DomainResult = CourseworkRunInputType.create(
		record["task_id"], record["day_index"], record["request_id"], record["graph_revision"],
		record["graph_snapshot"], record["case_roster"], record["case_roster"])
	if not input_result.is_success():
		return _reject(&"workday_recovery_binding_invalid", "the immutable input record cannot be reconstructed")
	var input_value: Variant = input_result.value()
	if not input_value is CourseworkRunInputType:
		return _reject(&"workday_recovery_binding_invalid", "the reconstructed input has an invalid type")
	var input: CourseworkRunInput = input_value
	if input.admitted_content_digest() != record["admitted_content_digest"] \
			or input.identity_sha256() != record["identity_sha256"]:
		return _reject(&"workday_recovery_binding_identity_mismatch", "the reconstructed input identity does not match the locked intent")
	return DomainResultType.success(input)

func _voluntary_action_from_status(status: Dictionary[String, Variant]) -> int:
	var action_name: StringName = StringName(status.get("action", &""))
	if action_name == &"targeted_case":
		return CourseworkWorkdayLifecycle.OptionalAction.TARGETED_CASE
	if action_name == &"voluntary_suite":
		return CourseworkWorkdayLifecycle.OptionalAction.VOLUNTARY_SUITE
	return -1

func _recovery_mode_name() -> StringName:
	if _recovery_mode == RECOVERY_MODE_NONE:
		return &"none"
	if _recovery_mode == RECOVERY_MODE_VOLUNTARY_LOCKED:
		return &"voluntary_locked"
	if _recovery_mode == RECOVERY_MODE_AUTHORITATIVE_LOCKED:
		return &"authoritative_locked"
	return &"invalid"

func _typed_dictionary(value: Variant) -> Dictionary[String, Variant]:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var result: Dictionary[String, Variant] = {}
	for raw_key: Variant in Dictionary(value).keys():
		if typeof(raw_key) != TYPE_STRING:
			return {}
		result[String(raw_key)] = Dictionary(value)[raw_key]
	return result

func _reject(error_code: StringName, message: String) -> DomainResult:
	return DomainResultType.failure(error_code, message, "workday.recovery_projection")
