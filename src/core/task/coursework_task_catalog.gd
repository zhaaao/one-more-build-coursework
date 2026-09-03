class_name CourseworkTaskCatalog
extends RefCounted

const CanonicalCodec = preload("res://src/foundation/canonical_codec.gd")
const ContractShapeProfile = preload("res://src/foundation/contract_shape_profile.gd")
const TaskRecoveryContractType = preload("res://src/core/task/coursework_task_recovery_contract.gd")
const TaskExecutionContractType = preload("res://src/core/task/coursework_task_execution_contract.gd")

## Task/Public Test Content Story 001 admission owner.  Raw authored bytes are
## proven by Foundation before the private typed records below are constructed.

const _FROZEN_TASK_IDS: Array[String] = ["task.day1.delivery_order", "task.day2.color_sort", "task.day3.patrol_loop", "task.day4.low_battery", "task.day5.multi_package"]
const _FROZEN_MODES: Array[String] = ["repair", "repair", "completion", "completion", "independent construction"]
const _FROZEN_NODE_LIMITS: Array[int] = [6, 8, 8, 10, 15]
const _FROZEN_CASE_IDS: Array = [
	["case.d1.01.red", "case.d1.02.blue", "case.d1.03.yellow"],
	["case.d2.01.red_hold", "case.d2.02.blue_release", "case.d2.03.green_release", "case.d2.04.orange_release", "case.d2.05.yellow_release"],
	["case.d3.01.clear_east", "case.d3.02.obstacle_after_one", "case.d3.03.east_boundary", "case.d3.04.closed_door", "case.d3.05.crate_after_one", "case.d3.06.package_blocker", "case.d3.07.north_obstacle"],
	["case.d4.01.empty_0", "case.d4.02.low_1", "case.d4.03.boundary_2", "case.d4.04.above_3", "case.d4.05.above_4", "case.d4.06.mid_5", "case.d4.07.mid_6", "case.d4.08.high_9", "case.d4.09.full_10"],
	["case.d5.01.red_low_mixed", "case.d5.02.blue_low_mixed", "case.d5.03.red_high_mixed", "case.d5.04.green_high_three", "case.d5.05.red_low_three", "case.d5.06.yellow_low_distance2", "case.d5.07.blue_high_distance2", "case.d5.08.red_high_distance1", "case.d5.09.orange_low_all_far", "case.d5.10.red_high_all_far", "case.d5.11.purple_low_near", "case.d5.12.red_full_mixed"],
]
const _FROZEN_PROMPT_IDS: Array = [
	["prompt.d1.01.read_trace", "prompt.d1.02.pick_before_drop"],
	["prompt.d2.01.query_value", "prompt.d2.02.swap_arms"],
	["prompt.d3.01_continue"],
	["prompt.d4.01_boundary"],
	[],
]

var _admitted_recovery_records: Dictionary[String, Variant] = {}
var _admitted_execution_records: Dictionary[String, Variant] = {}

class TaskPackage extends RefCounted:
	var _locked := false:
		set(value):
			if not _locked:
				_locked = value
	var _day_index := 0:
		set(value):
			if not _locked:
				_day_index = value
	var _task_id := "":
		set(value):
			if not _locked:
				_task_id = value
	var _mode := "":
		set(value):
			if not _locked:
				_mode = value
	var _node_limit := 0:
		set(value):
			if not _locked:
				_node_limit = value
	var _public_case_ids: Array[String] = []:
		get:
			return _public_case_ids.duplicate()
		set(value):
			if not _locked:
				_public_case_ids = value.duplicate()
	var _assertion_ids: Array[String] = []:
		get:
			return _assertion_ids.duplicate()
		set(value):
			if not _locked:
				_assertion_ids = value.duplicate()
	var _state_ids: Array[String] = []:
		get:
			return _state_ids.duplicate()
		set(value):
			if not _locked:
				_state_ids = value.duplicate()
	var _prompt_ids: Array[String] = []:
		get:
			return _prompt_ids.duplicate()
		set(value):
			if not _locked:
				_prompt_ids = value.duplicate()

	func _init(day_index: int, task_id: String, mode: String, node_limit: int, public_case_ids: Array[String], assertion_ids: Array[String], state_ids: Array[String], prompt_ids: Array[String]) -> void:
		_day_index = day_index
		_task_id = task_id
		_mode = mode
		_node_limit = node_limit
		_public_case_ids = public_case_ids.duplicate()
		_assertion_ids = assertion_ids.duplicate()
		_state_ids = state_ids.duplicate()
		_prompt_ids = prompt_ids.duplicate()
		_locked = true

	func projection() -> Dictionary:
		return {
			"day_index": _day_index,
			"task_id": _task_id,
			"mode": _mode,
			"node_limit": _node_limit,
			"public_case_ids": _public_case_ids.duplicate(),
			"assertion_ids": _assertion_ids.duplicate(),
			"state_ids": _state_ids.duplicate(),
			"prompt_ids": _prompt_ids.duplicate(),
		}

class TaskCatalogSnapshot extends RefCounted:
	var _locked := false:
		set(value):
			if not _locked:
				_locked = value
	var _packages: Array[TaskPackage] = []:
		get:
			return _packages.duplicate()
		set(value):
			if not _locked:
				_packages = value.duplicate()
	var _catalog_digest := "":
		set(value):
			if not _locked:
				_catalog_digest = value

	func _init(packages: Array[TaskPackage], catalog_digest: String) -> void:
		_packages = packages.duplicate()
		_catalog_digest = catalog_digest
		_locked = true

	func projection() -> Dictionary:
		var packages: Array[Dictionary] = []
		for package: TaskPackage in _packages:
			packages.append(package.projection())
		return {"packages": packages, "catalog_digest": _catalog_digest}

var _operations_locked: bool = false:
	set(value):
		if not _operations_locked:
			_operations_locked = value
var _snapshot_operation: Callable:
	set(value):
		if not _operations_locked:
			_snapshot_operation = value
var _admit_operation: Callable:
	set(value):
		if not _operations_locked:
			_admit_operation = value

func _init() -> void:
	var snapshot_slot: Array[TaskCatalogSnapshot] = [TaskCatalogSnapshot.new([], "")]
	_snapshot_operation = func() -> Dictionary:
		return snapshot_slot[0].projection()
	_admit_operation = func(raw_bytes: PackedByteArray) -> DomainResult:
		var proof_result: DomainResult = CanonicalCodec.decode_parts(raw_bytes, _admission_profile())
		if not proof_result.is_success():
			return proof_result
		var proof: Dictionary = proof_result.value()
		var decoded: Dictionary = proof["value"]
		var packages_result := _validate_and_build_packages(decoded["packages"])
		if not packages_result.is_success():
			return packages_result
		var next_packages: Array[TaskPackage] = packages_result.value()
		var recovery_result: DomainResult = _build_admitted_recovery_records(Array(decoded["packages"]))
		if not recovery_result.is_success():
			return recovery_result
		var execution_result: DomainResult = _build_admitted_execution_records(Array(decoded["packages"]))
		if not execution_result.is_success():
			return execution_result
		snapshot_slot[0] = TaskCatalogSnapshot.new(next_packages, String(proof["sha256"]))
		_admitted_recovery_records = recovery_result.value()
		_admitted_execution_records = execution_result.value()
		return DomainResult.success(snapshot_slot[0].projection())
	_operations_locked = true

## Returns a detached projection; callers cannot mutate private owner records.
## Example: `var published := catalog.snapshot()`.
func snapshot() -> Dictionary:
	return _snapshot_operation.call()

## Admits one raw canonical package vector or returns the Foundation/domain
## diagnostic. A rejection never changes the previous private snapshot.
## Example: `var result := catalog.admit(raw_authored_json)`.
func admit(raw_bytes: PackedByteArray) -> DomainResult:
	return _admit_operation.call(PackedByteArray(raw_bytes))

## Returns a recursively detached recovery contract only for an admitted Task.
## The static coursework task definitions are the installed catalogue content;
## admission above proves the frozen task/case identity before this query is
## allowed to expose a Task's graph, starting graph, roster, or digest.
func recovery_contract(task_id: String) -> DomainResult:
	var projection: Dictionary = snapshot()
	var packages_value: Variant = projection.get("packages", [])
	if typeof(packages_value) != TYPE_ARRAY:
		return _reject(&"task_recovery_contract_unavailable", "the installed Task catalogue is not admitted", "$.packages")
	var package_found: bool = false
	for package_value: Variant in Array(packages_value):
		if typeof(package_value) == TYPE_DICTIONARY and String(Dictionary(package_value).get("task_id", "")) == task_id:
			package_found = true
			break
	if not package_found:
		return _reject(&"task_recovery_contract_unknown_task", "the requested Task is not admitted", "$.task_id")
	if not _admitted_recovery_records.has(task_id):
		return _reject(&"task_recovery_contract_unavailable", "the admitted Task has no retained recovery content", "$.task_id")
	var content: Dictionary = Dictionary(_admitted_recovery_records[task_id]).duplicate(true)
	if content.is_empty():
		return _reject(&"task_recovery_contract_unavailable", "the admitted Task has no installed recovery content", "$.task_id")
	if not _admitted_execution_records.has(task_id):
		return _reject(&"task_recovery_contract_unavailable", "the admitted Task has no retained execution contract", "$.task_id")
	var execution_record: Dictionary = Dictionary(_admitted_execution_records[task_id]).duplicate(true)
	var expected_day_index: int = 0
	for package_value: Variant in Array(packages_value):
		if typeof(package_value) == TYPE_DICTIONARY and String(Dictionary(package_value).get("task_id", "")) == task_id:
			expected_day_index = int(Dictionary(package_value).get("day_index", 0))
			break
	if expected_day_index == 0 or int(execution_record.get("day_index", 0)) != expected_day_index \
			or String(execution_record.get("task_id", "")) != task_id:
		return _reject(&"task_execution_contract_mismatch", "the admitted Task execution record identity does not match", "$.task_id")
	var graph_contract: Dictionary[String, Variant] = {}
	for raw_key: Variant in Dictionary(execution_record.get("graph_model_contract", {})).keys():
		if typeof(raw_key) != TYPE_STRING:
			return _reject(&"task_recovery_contract_unavailable", "execution graph contract has an invalid key", "$.graph_model_contract")
		graph_contract[String(raw_key)] = Dictionary(execution_record["graph_model_contract"])[raw_key]
	var starting_graph: Dictionary[String, Variant] = {}
	var raw_starting_graph: Dictionary = Dictionary(content.get("starting_graph", {}))
	for raw_key: Variant in raw_starting_graph.keys():
		if typeof(raw_key) != TYPE_STRING:
			return _reject(&"task_recovery_contract_unavailable", "installed starting graph has an invalid key", "$.starting_graph")
		starting_graph[String(raw_key)] = raw_starting_graph[raw_key]
	var public_cases: Array[Variant] = Array(content.get("public_cases", [])).duplicate(true)
	var witness_value: Variant = content.get("witness", null)
	if typeof(witness_value) != TYPE_DICTIONARY:
		return _reject(&"task_recovery_contract_unavailable", "installed Task witness is invalid", "$.witness")
	var witness_operations_value: Variant = Dictionary(witness_value).get("edits", null)
	if typeof(witness_operations_value) != TYPE_ARRAY:
		return _reject(&"task_recovery_contract_unavailable", "installed Task witness operations are invalid", "$.witness.edits")
	var witness_operations: Array[Variant] = Array(witness_operations_value).duplicate(true)
	return TaskRecoveryContractType.create(
		task_id, graph_contract, starting_graph, public_cases,
		String(content.get("content_digest", "")), witness_operations)

## Returns one Task-owned immutable execution contract from the atomically
## admitted record. No static fixture is exposed after admission.
func execution_contract(task_id: String) -> DomainResult:
	var projection: Dictionary = snapshot()
	var packages_value: Variant = projection.get("packages", [])
	if typeof(packages_value) != TYPE_ARRAY:
		return _reject(&"task_execution_contract_unavailable", "the installed Task catalogue is not admitted", "$.packages")
	var expected_day_index := 0
	for raw_package: Variant in Array(packages_value):
		if typeof(raw_package) == TYPE_DICTIONARY and String(Dictionary(raw_package).get("task_id", "")) == task_id:
			expected_day_index = int(Dictionary(raw_package).get("day_index", 0))
			break
	if expected_day_index == 0 or not _admitted_execution_records.has(task_id):
		return _reject(&"task_execution_contract_unknown_task", "the requested Task is not admitted", "$.task_id")
	var record: Dictionary = Dictionary(_admitted_execution_records[task_id]).duplicate(true)
	if int(record.get("day_index", 0)) != expected_day_index or String(record.get("task_id", "")) != task_id:
		return _reject(&"task_execution_contract_mismatch", "the admitted Task execution record identity does not match", "$.task_id")
	return TaskExecutionContractType.create(
		task_id, expected_day_index, Dictionary(record.get("graph_model_contract", {})),
		Dictionary(record.get("starting_graph", {})), Dictionary(record.get("authoring_registry", {})),
		Array(record.get("public_cases", [])), String(record.get("content_digest", "")))

## Converts the fixed registered Visual Authoring descriptors into the smaller
## admitted per-Task GraphModel contract.  The source graph fixes each selected
## variant's parameter arity without exposing unrelated registry variants.
func _recovery_graph_variants(selected_variant_ids: Array, starting_graph: Dictionary) -> DomainResult:
	var registry: Dictionary[StringName, Dictionary] = _recovery_visual_registry()
	var nodes_value: Variant = starting_graph.get("nodes", null)
	if typeof(nodes_value) != TYPE_ARRAY:
		return _reject(&"task_recovery_contract_unavailable", "installed starting graph nodes are invalid", "$.starting_graph.nodes")
	for raw_node: Variant in Array(nodes_value):
		if typeof(raw_node) != TYPE_DICTIONARY:
			return _reject(&"task_recovery_contract_unavailable", "installed starting graph node is invalid", "$.starting_graph.nodes")
		var node: Dictionary = raw_node
		var raw_variant_id: Variant = node.get("variant_id", null)
		var raw_category: Variant = node.get("category", null)
		var raw_parameters: Variant = node.get("parameters", null)
		if (typeof(raw_variant_id) != TYPE_STRING and typeof(raw_variant_id) != TYPE_STRING_NAME) \
				or (typeof(raw_category) != TYPE_STRING and typeof(raw_category) != TYPE_STRING_NAME) \
				or typeof(raw_parameters) != TYPE_DICTIONARY:
			return _reject(&"task_recovery_contract_unavailable", "installed starting graph node fields are invalid", "$.starting_graph.nodes")
		var variant_id: StringName = StringName(raw_variant_id)
		var category: StringName = StringName(raw_category)
		if not registry.has(variant_id) or StringName(registry[variant_id]["category"]) != category:
			return _reject(&"task_recovery_contract_unavailable", "installed starting graph node is not registered", "$.starting_graph.nodes")
		if Dictionary(raw_parameters).size() != int(registry[variant_id]["parameter_count"]):
			return _reject(&"task_recovery_contract_unavailable", "installed starting graph parameter arity differs from its registered variant", "$.starting_graph.nodes")
	var variants: Array[Variant] = []
	for raw_variant_id: Variant in selected_variant_ids:
		if typeof(raw_variant_id) != TYPE_STRING and typeof(raw_variant_id) != TYPE_STRING_NAME:
			return _reject(&"task_recovery_contract_unavailable", "installed variant identity is invalid", "$.variant_ids")
		var variant_id: StringName = StringName(raw_variant_id)
		if not registry.has(variant_id):
			return _reject(&"task_recovery_contract_unavailable", "installed Task selects an unavailable Visual Authoring variant", "$.variant_ids")
		var descriptor: Dictionary = registry[variant_id]
		var parameter_ids: Array[StringName] = _execution_parameter_ids(String(variant_id))
		if parameter_ids.size() != int(descriptor["parameter_count"]):
			return _reject(&"task_recovery_contract_unavailable", "recovery variant parameter identities do not match its ABI arity", "$.variant_ids")
		variants.append({
			"id": variant_id,
			"category": StringName(descriptor["category"]),
			"creatable": true,
			"ports": Array(descriptor["ports"]).duplicate(true),
			"parameter_count": int(descriptor["parameter_count"]),
			"parameter_ids": parameter_ids,
			"default_parameters": _execution_default_parameters(String(variant_id)),
		})
	return DomainResult.success(variants)

## The fixed Visual Authoring registry is copied as a pure descriptor table so
## recovery can validate only the variants admitted by the installed Task.
static func _recovery_visual_registry() -> Dictionary[StringName, Dictionary]:
	return {
		&"flow.start": _recovery_variant(&"Start", 0, [_recovery_port(&"next", &"output")]),
		&"flow.end": _recovery_variant(&"End", 0, [_recovery_port(&"in", &"input")]),
		&"flow.branch.boolean": _recovery_variant(&"Branch", 0, [_recovery_port(&"in", &"input"), _recovery_port(&"condition", &"input", &"data", &"Boolean"), _recovery_port(&"true", &"output"), _recovery_port(&"false", &"output")]),
		&"flow.repeat.bounded": _recovery_variant(&"Repeat", 1, [_recovery_port(&"in", &"input"), _recovery_port(&"continue", &"input", &"execution", &"", true), _recovery_port(&"body", &"output"), _recovery_port(&"done", &"output")]),
		&"value.constant.numeric": _recovery_variant(&"Constant", 1, [_recovery_port(&"value", &"output", &"data", &"numeric")]),
		&"value.compare.numeric": _recovery_variant(&"Compare", 1, [_recovery_port(&"left", &"input", &"data", &"numeric"), _recovery_port(&"right", &"input", &"data", &"numeric"), _recovery_port(&"result", &"output", &"data", &"Boolean")]),
		&"parcel.query.front_sensor_matches_color": _recovery_variant(&"Query", 2, [_recovery_port(&"value", &"output", &"data", &"Boolean")]),
		&"parcel.query.path_is_clear": _recovery_variant(&"Query", 1, [_recovery_port(&"value", &"output", &"data", &"Boolean")]),
		&"parcel.query.battery_units": _recovery_variant(&"Query", 1, [_recovery_port(&"value", &"output", &"data", &"numeric")]),
		&"parcel.action.advance_conveyors": _recovery_variant(&"Action", 1, [_recovery_port(&"in", &"input"), _recovery_port(&"next", &"output")]),
		&"parcel.action.charge": _recovery_variant(&"Action", 1, [_recovery_port(&"in", &"input"), _recovery_port(&"next", &"output")]),
		&"parcel.action.drop_front": _recovery_variant(&"Action", 1, [_recovery_port(&"in", &"input"), _recovery_port(&"next", &"output")]),
		&"parcel.action.move_forward": _recovery_variant(&"Action", 1, [_recovery_port(&"in", &"input"), _recovery_port(&"next", &"output")]),
		&"parcel.action.pick_up_front": _recovery_variant(&"Action", 1, [_recovery_port(&"in", &"input"), _recovery_port(&"next", &"output")]),
		&"parcel.action.turn": _recovery_variant(&"Action", 2, [_recovery_port(&"in", &"input"), _recovery_port(&"next", &"output")]),
	}

static func _recovery_variant(category: StringName, parameter_count: int, ports: Array[Dictionary]) -> Dictionary:
	return {"category": category, "parameter_count": parameter_count, "ports": ports}

static func _recovery_port(port_id: StringName, direction: StringName, kind: StringName = &"execution", data_type: StringName = &"", multiple_execution_sources: bool = false) -> Dictionary:
	var port: Dictionary = {"id": port_id, "direction": direction, "kind": kind}
	if kind == &"data":
		port["data_type"] = data_type
	if multiple_execution_sources:
		port["multiple_execution_sources"] = true
	return port

func _build_admitted_recovery_records(candidate_packages: Array) -> DomainResult:
	var records: Dictionary[String, Variant] = {}
	for candidate_value: Variant in candidate_packages:
		if typeof(candidate_value) != TYPE_DICTIONARY:
			return _reject(&"task_recovery_contract_unavailable", "an admitted package is invalid", "$.packages")
		var candidate: Dictionary = Dictionary(candidate_value)
		var task_id: String = String(candidate["task_id"])
		var content: Dictionary = _installed_content_for_task(task_id)
		var public_cases: Array[Variant] = Array(content.get("public_cases", [])).duplicate(true)
		var expected_ids: Array = Array(candidate["public_case_ids"])
		if content.is_empty() or public_cases.size() != expected_ids.size():
			return _reject(&"task_recovery_contract_unavailable", "installed recovery content does not match the admitted package", "$.packages")
		for index: int in range(public_cases.size()):
			if typeof(public_cases[index]) != TYPE_DICTIONARY or String(Dictionary(public_cases[index]).get("case_id", "")) != String(expected_ids[index]):
				return _reject(&"task_recovery_contract_unavailable", "installed recovery roster differs from admitted case order", "$.packages")
		var encoded: DomainResult = CanonicalCodec.encode(public_cases)
		if not encoded.is_success():
			return encoded
		var record: Dictionary = content.duplicate(true)
		record["content_digest"] = CanonicalCodec.sha256_hex(encoded.value())
		records[task_id] = record
	return DomainResult.success(records)

func _build_admitted_execution_records(candidate_packages: Array) -> DomainResult:
	var records: Dictionary[String, Variant] = {}
	var registry: Dictionary = TaskExecutionContractType.production_authoring_registry()
	for candidate_value: Variant in candidate_packages:
		if typeof(candidate_value) != TYPE_DICTIONARY:
			return _reject(&"task_execution_contract_unavailable", "an admitted package is invalid", "$.packages")
		var candidate: Dictionary = Dictionary(candidate_value)
		var task_id: String = String(candidate.get("task_id", ""))
		var content: Dictionary = _installed_content_for_task(task_id)
		var public_cases: Array = Array(content.get("public_cases", []))
		var expected_ids: Array = Array(candidate.get("public_case_ids", []))
		if content.is_empty() or public_cases.size() != expected_ids.size():
			return _reject(&"task_execution_contract_unavailable", "installed execution content does not match the admitted package", "$.packages")
		for index: int in range(public_cases.size()):
			if typeof(public_cases[index]) != TYPE_DICTIONARY or String(Dictionary(public_cases[index]).get("case_id", "")) != String(expected_ids[index]):
				return _reject(&"task_execution_contract_unavailable", "installed execution roster differs from admitted case order", "$.packages")
		var encoded: DomainResult = CanonicalCodec.encode(public_cases)
		if not encoded.is_success():
			return encoded
		var graph_contract_result: DomainResult = _execution_graph_model_contract(content, registry)
		if not graph_contract_result.is_success():
			return graph_contract_result
		records[task_id] = {
			"task_id": task_id, "day_index": int(candidate.get("day_index", 0)),
			"graph_model_contract": graph_contract_result.value(),
			"starting_graph": Dictionary(content.get("starting_graph", {})).duplicate(true),
			"authoring_registry": registry.duplicate(true),
			"public_cases": public_cases.duplicate(true),
			"content_digest": CanonicalCodec.sha256_hex(encoded.value()),
		}
	return DomainResult.success(records)

func _execution_graph_model_contract(content: Dictionary, registry: Dictionary) -> DomainResult:
	var limits: Dictionary = Dictionary(content.get("limits", {}))
	var selected_variant_ids: Dictionary = {}
	for raw_variant_id: Variant in Array(content.get("variant_ids", [])):
		if typeof(raw_variant_id) != TYPE_STRING:
			return _reject(&"task_execution_contract_unavailable", "installed Task variant identity is invalid", "$.variant_ids")
		selected_variant_ids[String(raw_variant_id)] = true
	var variants: Array[Dictionary] = []
	for raw_variant: Variant in Array(registry.get("variants", [])):
		var variant: Dictionary = Dictionary(raw_variant)
		var variant_id: String = String(variant.get("variant_id", ""))
		if not selected_variant_ids.has(variant_id):
			continue
		var ports: Array[Dictionary] = []
		for raw_port: Variant in Array(variant.get("ports", [])):
			var port_source: Dictionary = Dictionary(raw_port)
			var port: Dictionary = {"id": StringName(port_source.get("port_id", "")), "direction": StringName(port_source.get("direction", "")), "kind": StringName(port_source.get("kind", ""))}
			if port_source.has("data_type"):
				port["data_type"] = StringName(port_source["data_type"])
			if String(variant.get("category_id", "")) == "Repeat" and String(port_source.get("port_id", "")) == "continue" and String(port_source.get("direction", "")) == "input" and String(port_source.get("kind", "")) == "execution":
				port["multiple_execution_sources"] = true
			ports.append(port)
		var parameter_count: int = _execution_parameter_arity(variant_id)
		var parameter_ids: Array[StringName] = _execution_parameter_ids(variant_id)
		if parameter_ids.size() != parameter_count:
			return _reject(&"task_execution_contract_unavailable", "production variant parameter identities do not match its ABI arity", "$.variants")
		variants.append({"id": StringName(variant_id), "category": StringName(variant.get("category_id", "")), "creatable": true, "ports": ports, "parameter_count": parameter_count, "parameter_ids": parameter_ids, "default_parameters": _execution_default_parameters(variant_id)})
	return DomainResult.success({"grid_size": 8, "grid_origin": {"x": 0, "y": 0}, "bounds": {"min_x": -128, "max_x": 128, "min_y": -32, "max_y": 32}, "node_limit": int(limits.get("node_limit", 0)), "connection_limit": int(limits.get("connection_budget", 0)), "variants": variants})

## The Task execution graph uses the completed GVET parameter ABI, rather than
## the partial starting-graph parameter sample.  This prevents Authoring from
## rejecting a permitted witness/player creation because it was absent at start.
static func _execution_parameter_arity(variant_id: String) -> int:
	match variant_id:
		"flow.repeat.bounded", "value.constant.numeric", "value.compare.numeric", \
		"parcel.query.path_is_clear", "parcel.query.battery_units", \
		"parcel.action.advance_conveyors", "parcel.action.charge", \
		"parcel.action.drop_front", "parcel.action.move_forward", \
		"parcel.action.pick_up_front":
			return 1
		"parcel.query.front_sensor_matches_color", "parcel.action.turn":
			return 2
		_:
			return 0

static func _execution_parameter_ids(variant_id: String) -> Array[StringName]:
	match variant_id:
		"flow.repeat.bounded":
			return [&"count"]
		"value.constant.numeric":
			return [&"value"]
		"value.compare.numeric":
			return [&"operator"]
		"parcel.query.front_sensor_matches_color":
			return [&"colour", &"query_id"]
		"parcel.query.path_is_clear", "parcel.query.battery_units":
			return [&"query_id"]
		"parcel.action.turn":
			return [&"direction", &"action_id"]
		"parcel.action.advance_conveyors", "parcel.action.charge", \
		"parcel.action.drop_front", "parcel.action.move_forward", \
		"parcel.action.pick_up_front":
			return [&"action_id"]
		_:
			return []

## Returns Task-owned initial values for one player-created node variant.
## Example: `var values := _execution_default_parameters("parcel.action.charge")`.
static func _execution_default_parameters(variant_id: String) -> Array:
	match variant_id:
		"flow.repeat.bounded": return [2]
		"value.constant.numeric": return [2]
		"value.compare.numeric": return [&"less_or_equal"]
		"parcel.query.front_sensor_matches_color": return [&"red", &"front_sensor_matches_color"]
		"parcel.query.path_is_clear": return [&"path_is_clear"]
		"parcel.query.battery_units": return [&"battery_units"]
		"parcel.action.turn": return [&"right", &"turn"]
		"parcel.action.advance_conveyors": return [&"advance_conveyors"]
		"parcel.action.charge": return [&"charge"]
		"parcel.action.drop_front": return [&"drop_front"]
		"parcel.action.move_forward": return [&"move_forward"]
		"parcel.action.pick_up_front": return [&"pick_up_front"]
		_: return []

static func _installed_content_for_task(task_id: String) -> Dictionary:
	for content: Dictionary in [_day1_content(), _day2_content(), _day3_content(), _day4_content(), _day5_content()]:
		if String(content.get("task_id", "")) == task_id:
			return content.duplicate(true)
	return {}

static func _admission_profile() -> ContractShapeProfile:
	return ContractShapeProfile.new([&"packages"], {
		"packages": {
			"kind": ContractShapeProfile.KIND_ARRAY,
			"minimum": 5,
			"maximum": 5,
			"items": {
				"kind": ContractShapeProfile.KIND_OBJECT,
				"fields": {
					"day_index": {"kind": ContractShapeProfile.KIND_INTEGER},
					"task_id": {"kind": ContractShapeProfile.KIND_STRING},
					"mode": {"kind": ContractShapeProfile.KIND_STRING},
					"node_limit": {"kind": ContractShapeProfile.KIND_INTEGER},
					"public_case_ids": {"kind": ContractShapeProfile.KIND_ARRAY, "items": {"kind": ContractShapeProfile.KIND_STRING}},
					"assertion_ids": {"kind": ContractShapeProfile.KIND_ARRAY, "items": {"kind": ContractShapeProfile.KIND_STRING}},
					"state_ids": {"kind": ContractShapeProfile.KIND_ARRAY, "items": {"kind": ContractShapeProfile.KIND_STRING}},
					"prompt_ids": {"kind": ContractShapeProfile.KIND_ARRAY, "items": {"kind": ContractShapeProfile.KIND_STRING}},
				},
			},
		},
	})

func _validate_and_build_packages(candidate_packages: Array) -> DomainResult:
	var identifier_sets := {
		"task": {}, "public_case": {}, "assertion": {}, "state": {}, "prompt": {},
	}
	for index: int in candidate_packages.size():
		var candidate: Dictionary = candidate_packages[index]
		var package_result := _validate_package(index, candidate, identifier_sets)
		if not package_result.is_success():
			return package_result

	var packages: Array[TaskPackage] = []
	for candidate: Dictionary in candidate_packages:
		packages.append(TaskPackage.new(
			int(candidate["day_index"]), String(candidate["task_id"]), String(candidate["mode"]), int(candidate["node_limit"]),
			_to_string_array(candidate["public_case_ids"]), _to_string_array(candidate["assertion_ids"]),
			_to_string_array(candidate["state_ids"]), _to_string_array(candidate["prompt_ids"])
		))
	return DomainResult.success(packages)

func _validate_package(index: int, candidate: Dictionary, identifier_sets: Dictionary) -> DomainResult:
	if int(candidate["day_index"]) != index + 1:
		return _reject(&"day_order_mismatch", "day index is not in frozen order", "$.packages[%d].day_index" % index)
	var task_ids: Dictionary = identifier_sets["task"]
	if task_ids.has(candidate["task_id"]):
		return _reject(&"duplicate_task_id", "task ID appears more than once", "$.packages[%d].task_id" % index)
	task_ids[candidate["task_id"]] = true
	if String(candidate["task_id"]) != _FROZEN_TASK_IDS[index]:
		return _reject(&"task_id_mismatch", "task ID is not the frozen Day task", "$.packages[%d].task_id" % index)
	if String(candidate["mode"]) != _FROZEN_MODES[index]:
		return _reject(&"mode_mismatch", "task mode is not the frozen Day mode", "$.packages[%d].mode" % index)
	if int(candidate["node_limit"]) != _FROZEN_NODE_LIMITS[index]:
		return _reject(&"node_limit_mismatch", "node limit is not the frozen Day limit", "$.packages[%d].node_limit" % index)
	var public_case_result := _validate_exact_ids(candidate["public_case_ids"], _FROZEN_CASE_IDS[index], identifier_sets["public_case"], &"public_case", index)
	if not public_case_result.is_success():
		return public_case_result
	# Assertion/state IDs are structural-only until later Stories introduce registries.
	var assertion_result := _validate_structural_ids(candidate["assertion_ids"], int(_FROZEN_CASE_IDS[index].size()), identifier_sets["assertion"], &"assertion", index)
	if not assertion_result.is_success():
		return assertion_result
	var state_result := _validate_structural_ids(candidate["state_ids"], int(_FROZEN_CASE_IDS[index].size()), identifier_sets["state"], &"state", index)
	if not state_result.is_success():
		return state_result
	return _validate_exact_ids(candidate["prompt_ids"], _FROZEN_PROMPT_IDS[index], identifier_sets["prompt"], &"prompt", index)

func _validate_exact_ids(candidate: Array, expected: Array, all_ids: Dictionary, kind: StringName, package_index: int) -> DomainResult:
	if candidate.size() != expected.size():
		return _reject(&"%s_count_mismatch" % kind, "%s ID count is not frozen" % kind, "$.packages[%d]" % package_index)
	for index: int in candidate.size():
		var identifier := String(candidate[index])
		if not _is_stable_identifier(identifier):
			return _reject(&"malformed_%s_id" % kind, "%s ID is not a stable ASCII identifier" % kind, "$.packages[%d][%d]" % [package_index, index])
		if all_ids.has(identifier):
			return _reject(&"duplicate_%s_id" % kind, "%s ID appears more than once" % kind, "$.packages[%d][%d]" % [package_index, index])
		all_ids[identifier] = true
	for index: int in candidate.size():
		if String(candidate[index]) != String(expected[index]):
			return _reject(&"%s_order_mismatch" % kind, "%s ID is not in frozen order" % kind, "$.packages[%d][%d]" % [package_index, index])
	return DomainResult.success(true)

func _validate_structural_ids(candidate: Array, expected_count: int, all_ids: Dictionary, kind: StringName, package_index: int) -> DomainResult:
	if candidate.size() != expected_count:
		return _reject(&"%s_count_mismatch" % kind, "%s ID count must equal the public roster" % kind, "$.packages[%d]" % package_index)
	for index: int in candidate.size():
		var identifier := String(candidate[index])
		if not _is_stable_identifier(identifier):
			return _reject(&"malformed_%s_id" % kind, "%s ID is not a stable ASCII identifier" % kind, "$.packages[%d][%d]" % [package_index, index])
		if all_ids.has(identifier):
			return _reject(&"duplicate_%s_id" % kind, "%s ID appears more than once" % kind, "$.packages[%d][%d]" % [package_index, index])
		all_ids[identifier] = true
	return DomainResult.success(true)

func _to_string_array(source: Array) -> Array[String]:
	var values: Array[String] = []
	for value: Variant in source:
		values.append(String(value))
	return values

func _is_stable_identifier(identifier: String) -> bool:
	if identifier.is_empty():
		return false
	for byte: int in identifier.to_utf8_buffer():
		if not ((byte >= 97 and byte <= 122) or (byte >= 48 and byte <= 57) or byte == 46 or byte == 95):
			return false
	return true

func _reject(error_code: StringName, message: String, path: String) -> DomainResult:
	return DomainResult.failure(error_code, message, path)

## Returns detached Task-owned Day 1-2 authored content in declared day and
## public-case order. Every call constructs a fresh projection, so consumers
## cannot mutate later reads.
## Example: `var day_one := CourseworkTaskCatalog.day1_day2_content()[0]`.
static func day1_day2_content() -> Array[Dictionary]:
	return [_day1_content(), _day2_content()]

## Returns detached Task-owned Day 3 authored content in declared public-case
## order. Every call constructs a fresh projection for deterministic consumers.
## Example: `var patrol := CourseworkTaskCatalog.day3_content()`.
static func day3_content() -> Dictionary:
	return _day3_content()

## Returns detached Task-owned Day 4 authored content in declared public-case
## order. Every call constructs a fresh projection for deterministic consumers.
## Example: `var battery_boundary := CourseworkTaskCatalog.day4_content()`.
static func day4_content() -> Dictionary:
	return _day4_content()

## Returns detached Task-owned Day 5 authored content in declared public-case
## order. Every call constructs a fresh projection for deterministic consumers.
## Example: `var independent_shift := CourseworkTaskCatalog.day5_content()`.
static func day5_content() -> Dictionary:
	return _day5_content()

static func _day1_content() -> Dictionary:
	var cases: Array[Dictionary] = []
	for row: Dictionary in [
		{"case_id": "case.d1.01.red", "state_id": "state.d1.01", "assertion_id": "assert.d1.01", "colour": "red"},
		{"case_id": "case.d1.02.blue", "state_id": "state.d1.02", "assertion_id": "assert.d1.02", "colour": "blue"},
		{"case_id": "case.d1.03.yellow", "state_id": "state.d1.03", "assertion_id": "assert.d1.03", "colour": "yellow"},
	]:
		cases.append(_day1_case(row))
	return {
		"day_index": 1,
		"task_id": "task.day1.delivery_order",
		"mode": "repair",
		"categories": ["Start", "Action", "End"],
		"variant_ids": ["flow.start", "parcel.action.drop_front", "parcel.action.pick_up_front", "flow.end"],
		"sandbox_operation_ids": ["drop_front", "pick_up_front"],
		"limits": {
			"starting_node_count": 5, "node_limit": 6,
			"connection_budget": 6, "grid_interval": 16,
			"finite_canvas": true, "prompt_max": 2,
		},
		"starting_node_capabilities": {"movable": true, "editable": true, "deletable": true},
		"starting_graph": {
			"nodes": [
				_node("node.d1.start", "Start", "flow.start"),
				_action_node("node.d1.drop_bad", "parcel.action.drop_front", "drop_front"),
				_action_node("node.d1.pick_up", "parcel.action.pick_up_front", "pick_up_front"),
				_action_node("node.d1.drop_good", "parcel.action.drop_front", "drop_front"),
				_node("node.d1.end", "End", "flow.end"),
			],
			"connections": [
				_connection("connection.d1.start_drop_bad", "node.d1.start", "next", "node.d1.drop_bad", "in"),
				_connection("connection.d1.drop_bad_pick", "node.d1.drop_bad", "next", "node.d1.pick_up", "in"),
				_connection("connection.d1.pick_drop_good", "node.d1.pick_up", "next", "node.d1.drop_good", "in"),
				_connection("connection.d1.drop_good_end", "node.d1.drop_good", "next", "node.d1.end", "in"),
			],
		},
		"public_cases": cases,
		"witness": {
			"final_node_count": 4, "final_connection_count": 3,
			"accepted_edit_count": 2, "max_steps": 4, "step_cap": 40,
			"passing_edit_range": {"minimum": 1, "maximum": 3},
			"expected_diagnostic_runs": {"minimum": 1, "maximum": 2},
			"edits": [
				{"kind": "delete_node", "node_id": "node.d1.drop_bad"},
				_connection("connection.d1.start_pick", "node.d1.start", "next", "node.d1.pick_up", "in").merged({"kind": "connect"}),
			],
		},
		"prompts": [
			_prompt("prompt.d1.01.read_trace", "first_same_case_failure", "Read the first failing Action and its reason before changing a wire."),
			_prompt("prompt.d1.02.pick_before_drop", "same_case_two_failures_without_graph_change", "The package must enter inventory before `drop_front` can deliver it."),
		],
	}

static func _day2_content() -> Dictionary:
	var cases: Array[Dictionary] = []
	for row: Dictionary in [
		{"case_id": "case.d2.01.red_hold", "state_id": "state.d2.01", "assertion_id": "assert.d2.01", "colour": "red", "delivered": 0, "front": "none", "inventory": 1, "inventory_front": "red", "remaining": 2},
		{"case_id": "case.d2.02.blue_release", "state_id": "state.d2.02", "assertion_id": "assert.d2.02", "colour": "blue", "delivered": 1, "front": "blue", "inventory": 0, "inventory_front": "none", "remaining": 1},
		{"case_id": "case.d2.03.green_release", "state_id": "state.d2.03", "assertion_id": "assert.d2.03", "colour": "green", "delivered": 1, "front": "green", "inventory": 0, "inventory_front": "none", "remaining": 1},
		{"case_id": "case.d2.04.orange_release", "state_id": "state.d2.04", "assertion_id": "assert.d2.04", "colour": "orange", "delivered": 1, "front": "orange", "inventory": 0, "inventory_front": "none", "remaining": 1},
		{"case_id": "case.d2.05.yellow_release", "state_id": "state.d2.05", "assertion_id": "assert.d2.05", "colour": "yellow", "delivered": 1, "front": "yellow", "inventory": 0, "inventory_front": "none", "remaining": 1},
	]:
		cases.append(_day2_case(row))
	return {
		"day_index": 2,
		"task_id": "task.day2.color_sort",
		"mode": "repair",
		"categories": ["Start", "Query", "Branch", "Action", "End"],
		"variant_ids": ["flow.start", "parcel.query.front_sensor_matches_color", "flow.branch.boolean", "parcel.action.advance_conveyors", "parcel.action.pick_up_front", "flow.end"],
		"sandbox_operation_ids": ["front_sensor_matches_color", "advance_conveyors", "pick_up_front"],
		"limits": {
			"starting_node_count": 7, "node_limit": 8,
			"connection_budget": 12, "grid_interval": 16,
			"finite_canvas": true, "prompt_max": 2,
		},
		"starting_node_capabilities": {"movable": true, "editable": true, "deletable": true},
		"starting_graph": {
			"nodes": [
				_node("node.d2.start", "Start", "flow.start"),
				{"node_id": "node.d2.red_query", "category": "Query", "variant_id": "parcel.query.front_sensor_matches_color", "parameters": {"operation_id": "front_sensor_matches_color", "colour": "red"}},
				_node("node.d2.branch", "Branch", "flow.branch.boolean"),
				_action_node("node.d2.advance", "parcel.action.advance_conveyors", "advance_conveyors"),
				_action_node("node.d2.pick_up", "parcel.action.pick_up_front", "pick_up_front"),
				_node("node.d2.end_red", "End", "flow.end"),
				_node("node.d2.end_non_red", "End", "flow.end"),
			],
			"connections": [
				_connection("connection.d2.start_branch", "node.d2.start", "next", "node.d2.branch", "in"),
				_connection("connection.d2.query_condition", "node.d2.red_query", "value", "node.d2.branch", "condition"),
				_connection("connection.d2.true_advance_swapped", "node.d2.branch", "true", "node.d2.advance", "in"),
				_connection("connection.d2.false_pick_swapped", "node.d2.branch", "false", "node.d2.pick_up", "in"),
				_connection("connection.d2.advance_end", "node.d2.advance", "next", "node.d2.end_non_red", "in"),
				_connection("connection.d2.pick_end", "node.d2.pick_up", "next", "node.d2.end_red", "in"),
			],
		},
		"public_cases": cases,
		"witness": {
			"final_node_count": 7, "final_connection_count": 6,
			"accepted_edit_count": 4, "max_steps": 5, "step_cap": 48,
			"passing_edit_range": {"minimum": 3, "maximum": 6},
			"expected_diagnostic_runs": {"minimum": 2, "maximum": 3},
			"edits": [
				{"kind": "disconnect", "connection_id": "connection.d2.true_advance_swapped"},
				{"kind": "disconnect", "connection_id": "connection.d2.false_pick_swapped"},
				_connection("connection.d2.true_pick", "node.d2.branch", "true", "node.d2.pick_up", "in").merged({"kind": "connect"}),
				_connection("connection.d2.false_advance", "node.d2.branch", "false", "node.d2.advance", "in").merged({"kind": "connect"}),
			],
		},
		"prompts": [
			_prompt("prompt.d2.01.query_value", "first_wrong_arm_result", "Compare the sensor Boolean result with the Branch arm selected in the trace."),
			_prompt("prompt.d2.02.swap_arms", "red_and_non_red_disagree", "Red belongs in hold inventory; another colour releases the conveyor batch."),
		],
	}

static func _day3_content() -> Dictionary:
	var cases: Array[Dictionary] = []
	for row: Dictionary in [
		{"case_id": "case.d3.01.clear_east", "state_id": "state.d3.01", "assertion_id": "assert.d3.01", "bot_x": 1, "bot_y": 2, "orientation": "east", "colour": "blue", "package_x": 0, "package_y": 4, "dock_x": 0, "dock_y": 3, "blocker_kind": "", "blocker_x": -1, "blocker_y": -1, "battery": 7, "final_orientation": "east", "final_x": 4, "final_y": 2},
		{"case_id": "case.d3.02.obstacle_after_one", "state_id": "state.d3.02", "assertion_id": "assert.d3.02", "bot_x": 1, "bot_y": 2, "orientation": "east", "colour": "blue", "package_x": 0, "package_y": 4, "dock_x": 0, "dock_y": 3, "blocker_kind": "obstacle", "blocker_x": 3, "blocker_y": 2, "battery": 8, "final_orientation": "south", "final_x": 2, "final_y": 3},
		{"case_id": "case.d3.03.east_boundary", "state_id": "state.d3.03", "assertion_id": "assert.d3.03", "bot_x": 4, "bot_y": 1, "orientation": "east", "colour": "green", "package_x": 0, "package_y": 4, "dock_x": 0, "dock_y": 3, "blocker_kind": "", "blocker_x": -1, "blocker_y": -1, "battery": 8, "final_orientation": "south", "final_x": 4, "final_y": 3},
		{"case_id": "case.d3.04.closed_door", "state_id": "state.d3.04", "assertion_id": "assert.d3.04", "bot_x": 1, "bot_y": 1, "orientation": "east", "colour": "orange", "package_x": 4, "package_y": 4, "dock_x": 4, "dock_y": 3, "blocker_kind": "door", "blocker_x": 2, "blocker_y": 1, "battery": 8, "final_orientation": "south", "final_x": 1, "final_y": 3},
		{"case_id": "case.d3.05.crate_after_one", "state_id": "state.d3.05", "assertion_id": "assert.d3.05", "bot_x": 1, "bot_y": 3, "orientation": "east", "colour": "purple", "package_x": 0, "package_y": 0, "dock_x": 0, "dock_y": 1, "blocker_kind": "crate", "blocker_x": 3, "blocker_y": 3, "battery": 8, "final_orientation": "south", "final_x": 2, "final_y": 4},
		{"case_id": "case.d3.06.package_blocker", "state_id": "state.d3.06", "assertion_id": "assert.d3.06", "bot_x": 1, "bot_y": 1, "orientation": "east", "colour": "red", "package_x": 2, "package_y": 1, "dock_x": 4, "dock_y": 4, "blocker_kind": "", "blocker_x": -1, "blocker_y": -1, "battery": 8, "final_orientation": "south", "final_x": 1, "final_y": 3},
		{"case_id": "case.d3.07.north_obstacle", "state_id": "state.d3.07", "assertion_id": "assert.d3.07", "bot_x": 2, "bot_y": 3, "orientation": "north", "colour": "yellow", "package_x": 0, "package_y": 0, "dock_x": 0, "dock_y": 1, "blocker_kind": "obstacle", "blocker_x": 2, "blocker_y": 2, "battery": 8, "final_orientation": "east", "final_x": 4, "final_y": 3},
	]:
		cases.append(_day3_case(row))
	return {
		"day_index": 3,
		"task_id": "task.day3.patrol_loop",
		"mode": "completion",
		"categories": ["Start", "Query", "Branch", "Action", "Repeat", "End"],
		"variant_ids": ["flow.start", "parcel.query.path_is_clear", "flow.branch.boolean", "parcel.action.move_forward", "parcel.action.turn", "flow.repeat.bounded", "flow.end"],
		"sandbox_operation_ids": ["path_is_clear", "move_forward", "turn"],
		"limits": {
			"starting_node_count": 7, "node_limit": 8,
			"connection_budget": 16, "grid_interval": 16,
			"finite_canvas": true, "prompt_max": 1,
		},
		"starting_node_capabilities": {"movable": true, "editable": true, "deletable": true},
		"starting_graph": {
			"nodes": [
				_node("node.d3.start", "Start", "flow.start"),
				{"node_id": "node.d3.path_query", "category": "Query", "variant_id": "parcel.query.path_is_clear", "parameters": {"operation_id": "path_is_clear"}},
				_node("node.d3.branch", "Branch", "flow.branch.boolean"),
				_action_node("node.d3.move", "parcel.action.move_forward", "move_forward"),
				{"node_id": "node.d3.turn_right", "category": "Action", "variant_id": "parcel.action.turn", "parameters": {"operation_id": "turn", "direction": "right"}},
				{"node_id": "node.d3.repeat", "category": "Repeat", "variant_id": "flow.repeat.bounded", "parameters": {"count": 3}},
				_node("node.d3.end", "End", "flow.end"),
			],
			"connections": [],
		},
		"public_cases": cases,
		"witness": {
			"final_node_count": 7, "final_connection_count": 8,
			"accepted_edit_count": 8, "max_steps": 15, "step_cap": 56,
			"passing_edit_range": {"minimum": 5, "maximum": 9},
			"expected_diagnostic_runs": {"minimum": 2, "maximum": 4},
			"edits": [
				_connection("connection.d3.start_repeat", "node.d3.start", "next", "node.d3.repeat", "in").merged({"kind": "connect"}),
				_connection("connection.d3.repeat_body_branch", "node.d3.repeat", "body", "node.d3.branch", "in").merged({"kind": "connect"}),
				_connection("connection.d3.query_condition", "node.d3.path_query", "value", "node.d3.branch", "condition").merged({"kind": "connect"}),
				_connection("connection.d3.true_move", "node.d3.branch", "true", "node.d3.move", "in").merged({"kind": "connect"}),
				_connection("connection.d3.false_turn", "node.d3.branch", "false", "node.d3.turn_right", "in").merged({"kind": "connect"}),
				_connection("connection.d3.move_continue", "node.d3.move", "next", "node.d3.repeat", "continue").merged({"kind": "connect"}),
				_connection("connection.d3.turn_continue", "node.d3.turn_right", "next", "node.d3.repeat", "continue").merged({"kind": "connect"}),
				_connection("connection.d3.repeat_done_end", "node.d3.repeat", "done", "node.d3.end", "in").merged({"kind": "connect"}),
			],
		},
		"prompts": [
			_prompt("prompt.d3.01_continue", "repeat_region_validation_fault", "Both normal body paths must return to this Repeat's `continue` input."),
		],
	}

static func _day4_content() -> Dictionary:
	var cases: Array[Dictionary] = []
	for row: Dictionary in [
		{"case_id": "case.d4.01.empty_0", "state_id": "state.d4.01", "assertion_id": "assert.d4.01", "initial_battery": 0, "final_battery": 10, "final_dock": "charging", "final_x": 1},
		{"case_id": "case.d4.02.low_1", "state_id": "state.d4.02", "assertion_id": "assert.d4.02", "initial_battery": 1, "final_battery": 10, "final_dock": "charging", "final_x": 1},
		{"case_id": "case.d4.03.boundary_2", "state_id": "state.d4.03", "assertion_id": "assert.d4.03", "initial_battery": 2, "final_battery": 10, "final_dock": "charging", "final_x": 1},
		{"case_id": "case.d4.04.above_3", "state_id": "state.d4.04", "assertion_id": "assert.d4.04", "initial_battery": 3, "final_battery": 2, "final_dock": "none", "final_x": 2},
		{"case_id": "case.d4.05.above_4", "state_id": "state.d4.05", "assertion_id": "assert.d4.05", "initial_battery": 4, "final_battery": 3, "final_dock": "none", "final_x": 2},
		{"case_id": "case.d4.06.mid_5", "state_id": "state.d4.06", "assertion_id": "assert.d4.06", "initial_battery": 5, "final_battery": 4, "final_dock": "none", "final_x": 2},
		{"case_id": "case.d4.07.mid_6", "state_id": "state.d4.07", "assertion_id": "assert.d4.07", "initial_battery": 6, "final_battery": 5, "final_dock": "none", "final_x": 2},
		{"case_id": "case.d4.08.high_9", "state_id": "state.d4.08", "assertion_id": "assert.d4.08", "initial_battery": 9, "final_battery": 8, "final_dock": "none", "final_x": 2},
		{"case_id": "case.d4.09.full_10", "state_id": "state.d4.09", "assertion_id": "assert.d4.09", "initial_battery": 10, "final_battery": 9, "final_dock": "none", "final_x": 2},
	]:
		cases.append(_day4_case(row))
	return {
		"day_index": 4,
		"task_id": "task.day4.low_battery",
		"mode": "completion",
		"categories": ["Start", "Action", "Query", "Constant", "Compare", "Branch", "End"],
		"variant_ids": ["flow.start", "parcel.query.battery_units", "value.constant.numeric", "value.compare.numeric", "flow.branch.boolean", "parcel.action.charge", "parcel.action.move_forward", "flow.end"],
		"sandbox_operation_ids": ["battery_units", "charge", "move_forward"],
		"limits": {
			"starting_node_count": 7, "node_limit": 10,
			"connection_budget": 16, "grid_interval": 16,
			"finite_canvas": true, "prompt_max": 1,
		},
		"starting_node_capabilities": {"movable": true, "editable": true, "deletable": true},
		"starting_graph": {
			"nodes": [
				_node("node.d4.start", "Start", "flow.start"),
				{"node_id": "node.d4.battery_query", "category": "Query", "variant_id": "parcel.query.battery_units", "parameters": {"operation_id": "battery_units"}},
				{"node_id": "node.d4.constant_2", "category": "Constant", "variant_id": "value.constant.numeric", "parameters": {"value": 2}},
				{"node_id": "node.d4.compare", "category": "Compare", "variant_id": "value.compare.numeric", "parameters": {"operator": "less_or_equal"}},
				_node("node.d4.branch", "Branch", "flow.branch.boolean"),
				_action_node("node.d4.move", "parcel.action.move_forward", "move_forward"),
				_node("node.d4.end_high", "End", "flow.end"),
			],
			"connections": [],
		},
		"public_cases": cases,
		"witness": {
			"final_node_count": 9, "final_connection_count": 8,
			"accepted_edit_count": 10, "max_steps": 7, "step_cap": 64,
			"passing_edit_range": {"minimum": 8, "maximum": 13},
			"expected_diagnostic_runs": {"minimum": 3, "maximum": 5},
			"edits": [
				_action_node("node.d4.charge", "parcel.action.charge", "charge").merged({"kind": "create_node"}),
				_node("node.d4.end_low", "End", "flow.end").merged({"kind": "create_node"}),
				_connection("connection.d4.start_branch", "node.d4.start", "next", "node.d4.branch", "in").merged({"kind": "connect"}),
				_connection("connection.d4.battery_left", "node.d4.battery_query", "value", "node.d4.compare", "left").merged({"kind": "connect"}),
				_connection("connection.d4.constant_right", "node.d4.constant_2", "value", "node.d4.compare", "right").merged({"kind": "connect"}),
				_connection("connection.d4.compare_condition", "node.d4.compare", "value", "node.d4.branch", "condition").merged({"kind": "connect"}),
				_connection("connection.d4.true_charge", "node.d4.branch", "true", "node.d4.charge", "in").merged({"kind": "connect"}),
				_connection("connection.d4.charge_end_low", "node.d4.charge", "next", "node.d4.end_low", "in").merged({"kind": "connect"}),
				_connection("connection.d4.false_move", "node.d4.branch", "false", "node.d4.move", "in").merged({"kind": "connect"}),
				_connection("connection.d4.move_end_high", "node.d4.move", "next", "node.d4.end_high", "in").merged({"kind": "connect"}),
			],
		},
		"prompts": [
			_prompt("prompt.d4.01_boundary", "case.d4.03.boundary_2_failure", "The public rule includes battery `2`; use an inclusive comparison."),
		],
	}

static func _day5_content() -> Dictionary:
	var cases: Array[Dictionary] = []
	for row: Dictionary in [
		{"case_id": "case.d5.01.red_low_mixed", "state_id": "state.d5.01", "assertion_id": "assert.d5.01", "initial_battery": 0, "control_colour": "red", "batch": [{"colour": "blue", "distance": 1}, {"colour": "green", "distance": 2}], "final_battery": 10, "delivered": 1, "inventory": 1, "remaining": 2, "slots": ["blue", "none", "none"]},
		{"case_id": "case.d5.02.blue_low_mixed", "state_id": "state.d5.02", "assertion_id": "assert.d5.02", "initial_battery": 2, "control_colour": "blue", "batch": [{"colour": "red", "distance": 1}, {"colour": "yellow", "distance": 2}], "final_battery": 10, "delivered": 1, "inventory": 0, "remaining": 2, "slots": ["red", "none", "none"]},
		{"case_id": "case.d5.03.red_high_mixed", "state_id": "state.d5.03", "assertion_id": "assert.d5.03", "initial_battery": 4, "control_colour": "red", "batch": [{"colour": "blue", "distance": 1}, {"colour": "green", "distance": 2}], "final_battery": 4, "delivered": 2, "inventory": 1, "remaining": 1, "slots": ["blue", "green", "none"]},
		{"case_id": "case.d5.04.green_high_three", "state_id": "state.d5.04", "assertion_id": "assert.d5.04", "initial_battery": 10, "control_colour": "green", "batch": [{"colour": "orange", "distance": 1}, {"colour": "purple", "distance": 2}, {"colour": "yellow", "distance": 2}], "final_battery": 10, "delivered": 3, "inventory": 0, "remaining": 1, "slots": ["orange", "purple", "yellow"]},
		{"case_id": "case.d5.05.red_low_three", "state_id": "state.d5.05", "assertion_id": "assert.d5.05", "initial_battery": 1, "control_colour": "red", "batch": [{"colour": "red", "distance": 1}, {"colour": "blue", "distance": 1}, {"colour": "green", "distance": 2}], "final_battery": 10, "delivered": 2, "inventory": 1, "remaining": 2, "slots": ["red", "blue", "none"]},
		{"case_id": "case.d5.06.yellow_low_distance2", "state_id": "state.d5.06", "assertion_id": "assert.d5.06", "initial_battery": 2, "control_colour": "yellow", "batch": [{"colour": "orange", "distance": 2}], "final_battery": 10, "delivered": 0, "inventory": 0, "remaining": 2, "slots": ["none", "none", "none"]},
		{"case_id": "case.d5.07.blue_high_distance2", "state_id": "state.d5.07", "assertion_id": "assert.d5.07", "initial_battery": 3, "control_colour": "blue", "batch": [{"colour": "purple", "distance": 2}], "final_battery": 3, "delivered": 1, "inventory": 0, "remaining": 1, "slots": ["purple", "none", "none"]},
		{"case_id": "case.d5.08.red_high_distance1", "state_id": "state.d5.08", "assertion_id": "assert.d5.08", "initial_battery": 6, "control_colour": "red", "batch": [{"colour": "yellow", "distance": 1}], "final_battery": 6, "delivered": 1, "inventory": 1, "remaining": 1, "slots": ["yellow", "none", "none"]},
		{"case_id": "case.d5.09.orange_low_all_far", "state_id": "state.d5.09", "assertion_id": "assert.d5.09", "initial_battery": 0, "control_colour": "orange", "batch": [{"colour": "blue", "distance": 2}, {"colour": "green", "distance": 2}, {"colour": "purple", "distance": 2}], "final_battery": 10, "delivered": 0, "inventory": 0, "remaining": 4, "slots": ["none", "none", "none"]},
		{"case_id": "case.d5.10.red_high_all_far", "state_id": "state.d5.10", "assertion_id": "assert.d5.10", "initial_battery": 9, "control_colour": "red", "batch": [{"colour": "blue", "distance": 2}, {"colour": "green", "distance": 2}, {"colour": "purple", "distance": 2}], "final_battery": 9, "delivered": 3, "inventory": 1, "remaining": 1, "slots": ["blue", "green", "purple"]},
		{"case_id": "case.d5.11.purple_low_near", "state_id": "state.d5.11", "assertion_id": "assert.d5.11", "initial_battery": 2, "control_colour": "purple", "batch": [{"colour": "orange", "distance": 1}, {"colour": "yellow", "distance": 1}], "final_battery": 10, "delivered": 2, "inventory": 0, "remaining": 1, "slots": ["orange", "yellow", "none"]},
		{"case_id": "case.d5.12.red_full_mixed", "state_id": "state.d5.12", "assertion_id": "assert.d5.12", "initial_battery": 10, "control_colour": "red", "batch": [{"colour": "red", "distance": 1}, {"colour": "yellow", "distance": 2}], "final_battery": 10, "delivered": 2, "inventory": 1, "remaining": 1, "slots": ["red", "yellow", "none"]},
	]:
		cases.append(_day5_case(row))
	return {
		"day_index": 5,
		"task_id": "task.day5.multi_package",
		"mode": "independent construction",
		"categories": ["Start", "Action", "Query", "Constant", "Compare", "Branch", "Repeat", "End"],
		"variant_ids": ["flow.start", "flow.repeat.bounded", "flow.end", "parcel.query.battery_units", "value.constant.numeric", "value.compare.numeric", "flow.branch.boolean", "parcel.action.charge", "parcel.action.advance_conveyors", "parcel.query.front_sensor_matches_color", "parcel.action.pick_up_front"],
		"sandbox_operation_ids": ["battery_units", "charge", "advance_conveyors", "front_sensor_matches_color", "pick_up_front"],
		"limits": {
			"starting_node_count": 3, "node_limit": 15,
			"connection_budget": 24, "grid_interval": 16,
			"finite_canvas": true, "prompt_max": 0,
		},
		"starting_node_capabilities": {"movable": true, "editable": true, "deletable": true},
		"starting_graph": {
			"nodes": [
				_node("node.d5.start", "Start", "flow.start"),
				{"node_id": "node.d5.repeat", "category": "Repeat", "variant_id": "flow.repeat.bounded", "parameters": {"count": 2}},
				_node("node.d5.end_non_red", "End", "flow.end"),
			],
			"connections": [
				_connection("connection.d5.start_repeat", "node.d5.start", "next", "node.d5.repeat", "in"),
				_connection("connection.d5.repeat_done_end", "node.d5.repeat", "done", "node.d5.end_non_red", "in"),
			],
		},
		"public_cases": cases,
		"witness": {
			"final_node_count": 13, "final_connection_count": 14,
			"accepted_edit_count": 23, "max_steps": 18, "step_cap": 72,
			"passing_edit_range": {"minimum": 14, "maximum": 24},
			"expected_diagnostic_runs": {"minimum": 4, "maximum": 6},
			"edits": [
				{"node_id": "node.d5.battery_query", "category": "Query", "variant_id": "parcel.query.battery_units", "parameters": {"operation_id": "battery_units"}, "kind": "create_node"},
				{"node_id": "node.d5.constant_2", "category": "Constant", "variant_id": "value.constant.numeric", "parameters": {"value": 2}, "kind": "create_node"},
				{"node_id": "node.d5.battery_compare", "category": "Compare", "variant_id": "value.compare.numeric", "parameters": {"operator": "less_or_equal"}, "kind": "create_node"},
				_node("node.d5.battery_branch", "Branch", "flow.branch.boolean").merged({"kind": "create_node"}),
				_action_node("node.d5.charge", "parcel.action.charge", "charge").merged({"kind": "create_node"}),
				_action_node("node.d5.advance", "parcel.action.advance_conveyors", "advance_conveyors").merged({"kind": "create_node"}),
				{"node_id": "node.d5.red_query", "category": "Query", "variant_id": "parcel.query.front_sensor_matches_color", "parameters": {"operation_id": "front_sensor_matches_color", "colour": "red"}, "kind": "create_node"},
				_node("node.d5.colour_branch", "Branch", "flow.branch.boolean").merged({"kind": "create_node"}),
				_action_node("node.d5.hold_red", "parcel.action.pick_up_front", "pick_up_front").merged({"kind": "create_node"}),
				_node("node.d5.end_red", "End", "flow.end").merged({"kind": "create_node"}),
				_connection("connection.d5.non_red_end", "node.d5.colour_branch", "false", "node.d5.end_non_red", "in").merged({"kind": "replace_connection", "replaces_connection_id": "connection.d5.repeat_done_end"}),
				_connection("connection.d5.repeat_body_battery_branch", "node.d5.repeat", "body", "node.d5.battery_branch", "in").merged({"kind": "connect"}),
				_connection("connection.d5.battery_left", "node.d5.battery_query", "value", "node.d5.battery_compare", "left").merged({"kind": "connect"}),
				_connection("connection.d5.constant_right", "node.d5.constant_2", "value", "node.d5.battery_compare", "right").merged({"kind": "connect"}),
				_connection("connection.d5.battery_condition", "node.d5.battery_compare", "value", "node.d5.battery_branch", "condition").merged({"kind": "connect"}),
				_connection("connection.d5.low_charge", "node.d5.battery_branch", "true", "node.d5.charge", "in").merged({"kind": "connect"}),
				_connection("connection.d5.charge_continue", "node.d5.charge", "next", "node.d5.repeat", "continue").merged({"kind": "connect"}),
				_connection("connection.d5.high_advance", "node.d5.battery_branch", "false", "node.d5.advance", "in").merged({"kind": "connect"}),
				_connection("connection.d5.advance_continue", "node.d5.advance", "next", "node.d5.repeat", "continue").merged({"kind": "connect"}),
				_connection("connection.d5.done_colour_branch", "node.d5.repeat", "done", "node.d5.colour_branch", "in").merged({"kind": "connect"}),
				_connection("connection.d5.red_condition", "node.d5.red_query", "value", "node.d5.colour_branch", "condition").merged({"kind": "connect"}),
				_connection("connection.d5.red_hold", "node.d5.colour_branch", "true", "node.d5.hold_red", "in").merged({"kind": "connect"}),
				_connection("connection.d5.hold_end", "node.d5.hold_red", "next", "node.d5.end_red", "in").merged({"kind": "connect"}),
			],
		},
		"prompts": [],
	}

static func _day1_case(row: Dictionary) -> Dictionary:
	var colour := String(row["colour"])
	var state := _empty_case_state(String(row["case_id"]), 3, 2, 0, 0)
	state["packages"] = [{"id": "pkg.01", "color": colour}]
	state["world_packages"] = [{"package_id": "pkg.01", "x": 1, "y": 0}]
	state["docks"] = [{"id": "dock.delivery", "kind": "delivery", "x": 1, "y": 0, "accepted_color": colour, "capacity": 1}]
	return _public_case(row, state, [
		_fact("battery_units", "integer", 10),
		_fact("inventory_count", "integer", 0),
		_fact("delivered_count", "integer", 1),
		_fact("remaining_package_count", "integer", 0),
		_label_fact("delivery_slot_1", colour),
		_label_fact("delivery_slot_2", "none"),
	])

static func _day2_case(row: Dictionary) -> Dictionary:
	var colour := String(row["colour"])
	var state := _empty_case_state(String(row["case_id"]), 4, 3, 0, 1)
	state["packages"] = [{"id": "pkg.control", "color": colour}, {"id": "pkg.batch", "color": "orange"}]
	state["world_packages"] = [{"package_id": "pkg.control", "x": 1, "y": 1}, {"package_id": "pkg.batch", "x": 2, "y": 0}]
	state["docks"] = [{"id": "dock.delivery", "kind": "delivery", "x": 3, "y": 0, "accepted_color": "orange", "capacity": 1}]
	state["conveyors"] = [{"id": "conveyor.batch", "x": 2, "y": 0, "direction": "east"}]
	state["sensors"] = [{"id": "sensor.control", "x": 1, "y": 1, "color": "red"}]
	return _public_case(row, state, [
		_label_fact("front_package_colour", String(row["front"])),
		_fact("inventory_count", "integer", int(row["inventory"])),
		_label_fact("inventory_front_package_colour", String(row["inventory_front"])),
		_fact("delivered_count", "integer", int(row["delivered"])),
		_fact("remaining_package_count", "integer", int(row["remaining"])),
	])

static func _day3_case(row: Dictionary) -> Dictionary:
	var state: Dictionary = _empty_case_state(String(row["case_id"]), 5, 5, int(row["bot_x"]), int(row["bot_y"]))
	state["bot"]["orientation"] = String(row["orientation"])
	state["packages"] = [{"id": "pkg.01", "color": String(row["colour"])}]
	state["world_packages"] = [{"package_id": "pkg.01", "x": int(row["package_x"]), "y": int(row["package_y"])}]
	state["docks"] = [{"id": "dock.delivery", "kind": "delivery", "x": int(row["dock_x"]), "y": int(row["dock_y"]), "accepted_color": String(row["colour"]), "capacity": 1}]
	match String(row["blocker_kind"]):
		"crate":
			state["crates"] = [{"id": "crate.block", "x": int(row["blocker_x"]), "y": int(row["blocker_y"])}]
		"obstacle":
			state["obstacles"] = [{"id": "obstacle.block", "x": int(row["blocker_x"]), "y": int(row["blocker_y"])}]
		"door":
			state["doors"] = [{"id": "door.block", "x": int(row["blocker_x"]), "y": int(row["blocker_y"]), "is_open": false}]
	return _public_case(row, state, [
		_fact("bot_x", "integer", int(row["final_x"])),
		_fact("bot_y", "integer", int(row["final_y"])),
		_domain_label_fact("bot_orientation", "cardinal_orientation", String(row["final_orientation"])),
		_fact("battery_units", "integer", int(row["battery"])),
	])

static func _day4_case(row: Dictionary) -> Dictionary:
	var state: Dictionary = _empty_case_state(String(row["case_id"]), 4, 3, 1, 1)
	state["charge_enabled"] = true
	state["bot"]["battery_units"] = int(row["initial_battery"])
	state["packages"] = [{"id": "pkg.01", "color": "blue"}]
	state["world_packages"] = [{"package_id": "pkg.01", "x": 3, "y": 2}]
	state["docks"] = [
		{"id": "dock.charge", "kind": "charging", "x": 1, "y": 1, "accepted_color": "none", "capacity": 1},
		{"id": "dock.delivery", "kind": "delivery", "x": 2, "y": 2, "accepted_color": "blue", "capacity": 1},
	]
	return _public_case(row, state, [
		_fact("bot_x", "integer", int(row["final_x"])),
		_fact("bot_y", "integer", 1),
		_fact("battery_units", "integer", int(row["final_battery"])),
		_domain_label_fact("current_dock_kind", "dock_kind_or_none", String(row["final_dock"])),
	])

static func _day5_case(row: Dictionary) -> Dictionary:
	var state: Dictionary = _empty_case_state(String(row["case_id"]), 6, 5, 0, 0)
	state["charge_enabled"] = true
	state["bot"]["battery_units"] = int(row["initial_battery"])
	var packages: Array[Dictionary] = [{"id": "pkg.control", "color": String(row["control_colour"])}]
	var world_packages: Array[Dictionary] = [{"package_id": "pkg.control", "x": 1, "y": 0}]
	var docks: Array[Dictionary] = [{"id": "dock.charge", "kind": "charging", "x": 0, "y": 0, "accepted_color": "none", "capacity": 1}]
	var conveyors: Array[Dictionary] = []
	var batch: Array[Dictionary] = []
	batch.assign(row["batch"])
	for index: int in batch.size():
		var package_number: int = index + 1
		var package_id: String = "pkg.%02d" % package_number
		var colour: String = String(batch[index]["colour"])
		var distance: int = int(batch[index]["distance"])
		var y: int = package_number + 1
		packages.append({"id": package_id, "color": colour})
		world_packages.append({"package_id": package_id, "x": 5 - distance, "y": y})
		docks.append({"id": "dock.delivery.%02d" % package_number, "kind": "delivery", "x": 5, "y": y, "accepted_color": colour, "capacity": 1})
		for conveyor_x: int in range(5 - distance, 5):
			conveyors.append({"id": "conveyor.%02d.%02d" % [package_number, conveyor_x], "x": conveyor_x, "y": y, "direction": "east"})
	state["packages"] = packages
	state["world_packages"] = world_packages
	state["docks"] = docks
	state["conveyors"] = conveyors
	state["sensors"] = [{"id": "sensor.control", "x": 1, "y": 0, "color": "red"}]
	var slots: Array[String] = []
	slots.assign(row["slots"])
	return _public_case(row, state, [
		_fact("battery_units", "integer", int(row["final_battery"])),
		_fact("inventory_count", "integer", int(row["inventory"])),
		_fact("delivered_count", "integer", int(row["delivered"])),
		_fact("remaining_package_count", "integer", int(row["remaining"])),
		_label_fact("delivery_slot_1", slots[0]),
		_label_fact("delivery_slot_2", slots[1]),
		_label_fact("delivery_slot_3", slots[2]),
	])

static func _empty_case_state(state_id: String, width: int, height: int, bot_x: int, bot_y: int) -> Dictionary:
	return {
		"case_id": state_id, "assignment_floor": true, "charge_enabled": false,
		"grid": {"width": width, "height": height},
		"bot": {"id": "bot.01", "x": bot_x, "y": bot_y, "orientation": "east", "battery_units": 10, "battery_capacity": 10, "inventory_capacity": 1},
		"packages": [], "world_packages": [], "inventory": [], "deliveries": [],
		"docks": [], "conveyors": [], "crates": [], "obstacles": [], "doors": [], "sensors": [],
	}

static func _public_case(row: Dictionary, initial_state: Dictionary, facts: Array[Dictionary]) -> Dictionary:
	return {
		"case_id": String(row["case_id"]),
		"state_id": String(row["state_id"]),
		"initial_state": initial_state,
		"assertions": [{"assertion_id": String(row["assertion_id"]), "kind": "typed_equality", "expected_facts": facts}],
	}

static func _fact(fact_id: String, value_type: String, value: Variant) -> Dictionary:
	return {"fact_id": fact_id, "value_type": value_type, "value": value}

static func _label_fact(fact_id: String, value: String) -> Dictionary:
	return _domain_label_fact(fact_id, "parcel_colour_or_none", value)

static func _domain_label_fact(fact_id: String, label_domain: String, value: String) -> Dictionary:
	return {"fact_id": fact_id, "value_type": "label", "label_domain": label_domain, "value": value}

static func _node(node_id: String, category: String, variant_id: String) -> Dictionary:
	return {"node_id": node_id, "category": category, "variant_id": variant_id, "parameters": {}}

static func _action_node(node_id: String, variant_id: String, operation_id: String) -> Dictionary:
	return {"node_id": node_id, "category": "Action", "variant_id": variant_id, "parameters": {"operation_id": operation_id}}

static func _connection(connection_id: String, source_node_id: String, source_port_id: String, target_node_id: String, target_port_id: String) -> Dictionary:
	return {
		"connection_id": connection_id,
		"source_node_id": source_node_id, "source_port_id": source_port_id,
		"target_node_id": target_node_id, "target_port_id": target_port_id,
	}

static func _prompt(prompt_id: String, trigger_id: String, message: String) -> Dictionary:
	return {
		"prompt_id": prompt_id, "trigger_id": trigger_id, "message": message,
		"read_only": true,
		"effects": {"edit": false, "run": false, "submit": false, "spend_time": false, "reveal_witness": false},
	}

## Immutable Task-owned bindings for Story 006's Assignment-Floor witness.
##
## Example: `var bindings := CourseworkTaskCatalog.bindings()` returns detached
## day-ordered dictionaries, so a caller cannot mutate later catalog reads.

const DAY_BINDINGS: Array[Dictionary] = [
	{
		"day_index": 1,
		"task_id": "task.day1.delivery_order",
		"mode": "repair",
		"public_case_count": 3,
		"operation_ids": ["advance_conveyors", "pick_up_front", "drop_front"],
	},
	{
		"day_index": 2,
		"task_id": "task.day2.color_sort",
		"mode": "repair",
		"public_case_count": 5,
		"operation_ids": ["advance_conveyors", "pick_up_front", "drop_front", "front_sensor_active", "front_sensor_matches_color"],
	},
	{
		"day_index": 3,
		"task_id": "task.day3.patrol_loop",
		"mode": "completion",
		"public_case_count": 7,
		"operation_ids": ["advance_conveyors", "pick_up_front", "drop_front", "front_sensor_active", "front_sensor_matches_color", "move_forward", "turn", "path_is_clear"],
	},
	{
		"day_index": 4,
		"task_id": "task.day4.low_battery",
		"mode": "completion",
		"public_case_count": 9,
		"operation_ids": ["advance_conveyors", "pick_up_front", "drop_front", "front_sensor_active", "front_sensor_matches_color", "move_forward", "turn", "path_is_clear", "battery_units", "charge"],
	},
	{
		"day_index": 5,
		"task_id": "task.day5.multi_package",
		"mode": "independent construction",
		"public_case_count": 12,
		"operation_ids": ["advance_conveyors", "pick_up_front", "drop_front", "front_sensor_active", "front_sensor_matches_color", "move_forward", "turn", "path_is_clear", "battery_units", "charge", "front_door_open", "inventory_count", "inventory_has_package", "packages_remaining", "remaining_package_count"],
	},
]

## Returns the five design-contract bindings in stable day order.
static func bindings() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for binding: Dictionary in DAY_BINDINGS:
		result.append(binding.duplicate(true))
	return result

## Returns the sole Day-1 repair witness authorized for Story 006 integration.
## Example: `var case := CourseworkTaskCatalog.day1_delivery_witness()`.
static func day1_delivery_witness() -> Dictionary:
	return {
		"case_id": "case.d1.01.red",
		"content": {
			"initial_state": {
				"case_id": "case.d1.01.red",
				"assignment_floor": true,
				"charge_enabled": false,
				"grid": {"width": 3, "height": 2},
				"bot": {
					"id": "bot.01", "x": 0, "y": 0, "orientation": "east",
					"battery_units": 10, "battery_capacity": 10,
					"inventory_capacity": 1,
				},
				"packages": [{"id": "pkg.01", "color": "red"}],
				"world_packages": [{"package_id": "pkg.01", "x": 1, "y": 0}],
				"inventory": [],
				"deliveries": [],
				"docks": [{
					"id": "dock.delivery", "kind": "delivery", "x": 1, "y": 0,
					"accepted_color": "red", "capacity": 1,
				}],
				"conveyors": [], "crates": [], "obstacles": [], "doors": [], "sensors": [],
			},
			"assertions": [{
				"assertion_id": "assert.d1.01.delivery",
				"expected": {
					"delivered_count": 1, "inventory_count": 0,
					"remaining_package_count": 0, "delivery_slot_1": "red",
				},
			}],
		},
	}.duplicate(true)
