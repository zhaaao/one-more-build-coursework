class_name SemanticDiagnosticValidator
extends RefCounted

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CanonicalJsonIRType = preload("res://src/foundation/canonical_json_ir.gd")
const SemanticGraphIndexType = preload("res://src/core/gvet/semantic_graph_index.gd")
const SemanticDiagnosticType = preload("res://src/core/gvet/semantic_diagnostic.gd")
const SemanticValidationReportType = preload("res://src/core/gvet/semantic_validation_report.gd")
const CourseworkRunInputType = preload("res://src/core/gvet/coursework_run_input.gd")

## One configured, synchronous coursework semantic-validation port.
##
## The Authoring registry is a constructor dependency, not serialized runtime
## authority. One call reads only the immutable `CourseworkRunInput` snapshot.
## Example: `validator.validate_semantics(input)`.

var _registry: Dictionary = {}

func _init(registry: Dictionary = {}) -> void:
	_registry = CanonicalJsonIRType.clone(registry)

## Returns whether a structurally valid Authoring registry was supplied.
func is_configured() -> bool:
	return not _registry.is_empty()

## Runs all semantic rules exactly once and returns one frozen report.
func validate_semantics(input: CourseworkRunInput) -> DomainResult:
	return validate(input, _registry)

## Service-shaped alias for direct tests and later runner composition.
func run(input: CourseworkRunInput) -> DomainResult:
	return validate_semantics(input)

## Validates one admitted coursework input against one exact Authoring registry.
static func validate(input: Variant, registry: Dictionary) -> DomainResult:
	if not input is CourseworkRunInputType or not input.is_valid():
		return DomainResult.failure(&"run_input_error", "semantic validation requires a valid CourseworkRunInput")
	var index_result: DomainResult = SemanticGraphIndexType.create(input.graph_snapshot(), registry)
	if not index_result.is_success():
		return DomainResult.failure(
			&"semantic_validation_error",
			"graph snapshot and Authoring registry could not be indexed")
	var index: SemanticGraphIndex = index_result.value()
	var diagnostics: Array = []
	var add_result := _add_entry_diagnostics(index, diagnostics)
	if not add_result.is_success():
		return add_result
	add_result = _add_required_connection_diagnostics(index, diagnostics)
	if not add_result.is_success():
		return add_result
	var starts := _start_nodes(index)
	if starts.size() == 1:
		add_result = _add_reachability_diagnostics(index, starts[0], diagnostics)
		if not add_result.is_success():
			return add_result
	add_result = _add_cycle_diagnostics(
		index, "data", [], SemanticDiagnosticType.CODE_ILLEGAL_DATA_CYCLE, diagnostics)
	if not add_result.is_success():
		return add_result
	var repeat_result := _add_repeat_diagnostics(index, diagnostics)
	if not repeat_result.is_success():
		return repeat_result
	add_result = _add_cycle_diagnostics(
		index,
		"execution",
		repeat_result.value(),
		SemanticDiagnosticType.CODE_ILLEGAL_EXECUTION_CYCLE,
		diagnostics)
	if not add_result.is_success():
		return add_result
	return SemanticValidationReportType.create(input, diagnostics)

static func _start_nodes(index: SemanticGraphIndex) -> Array[String]:
	var starts: Array[String] = []
	for node_id: String in index.node_ids():
		if index.category_of(node_id) == SemanticGraphIndexType.CATEGORY_START:
			starts.append(node_id)
	return starts

static func _add_entry_diagnostics(index: SemanticGraphIndex, diagnostics: Array) -> DomainResult:
	var starts := _start_nodes(index)
	if starts.is_empty():
		return _append_diagnostic(
			diagnostics,
			SemanticDiagnosticType.CODE_MISSING_START,
			SemanticDiagnosticType.ENTITY_GRAPH)
	elif starts.size() > 1:
		return _append_diagnostic(
			diagnostics,
			SemanticDiagnosticType.CODE_MULTIPLE_START,
			SemanticDiagnosticType.ENTITY_NODE_SET,
			starts[0],
			starts.slice(1))
	return DomainResult.success(true)

static func _add_required_connection_diagnostics(
	index: SemanticGraphIndex,
	diagnostics: Array
) -> DomainResult:
	for node_id: String in index.node_ids():
		for port: Dictionary in index.required_ports(node_id):
			if _port_connection_count(index, node_id, port) < int(port["minimum_connections"]):
				var add_result := _append_diagnostic(
					diagnostics,
					SemanticDiagnosticType.CODE_MISSING_REQUIRED_CONNECTION,
					SemanticDiagnosticType.ENTITY_PORT,
					node_id,
					[String(port["port_id"])] )
				if not add_result.is_success():
					return add_result
	return DomainResult.success(true)

static func _port_connection_count(
	index: SemanticGraphIndex,
	node_id: String,
	port: Dictionary
) -> int:
	var connections: Array = (
		index.incoming(node_id, port["kind"])
		if port["direction"] == "input"
		else index.outgoing(node_id, port["kind"]))
	var count := 0
	for connection: Dictionary in connections:
		var endpoint: String = (
			connection["target_port_id"]
			if port["direction"] == "input"
			else connection["source_port_id"])
		if endpoint == port["port_id"]:
			count += 1
	return count

static func _add_reachability_diagnostics(
	index: SemanticGraphIndex,
	start_id: String,
	diagnostics: Array
) -> DomainResult:
	var reachable := _reachable_closure(index, start_id)
	for node_id: String in index.node_ids():
		if not reachable.has(node_id):
			var add_result := _append_diagnostic(
				diagnostics,
				SemanticDiagnosticType.CODE_UNREACHABLE_NODE,
				SemanticDiagnosticType.ENTITY_NODE,
				node_id)
			if not add_result.is_success():
				return add_result
	return DomainResult.success(true)

static func _reachable_closure(index: SemanticGraphIndex, start_id: String) -> Dictionary:
	var reachable: Dictionary = {start_id: true}
	var pending: Array[String] = [start_id]
	while not pending.is_empty():
		var current: String = pending.pop_front()
		for connection: Dictionary in index.outgoing(current, "execution"):
			_add_reachable(reachable, pending, connection["target_node_id"])
		for connection: Dictionary in index.incoming(current, "data"):
			_add_reachable(reachable, pending, connection["source_node_id"])
	return reachable

static func _add_reachable(
	reachable: Dictionary,
	pending: Array[String],
	node_id: String
) -> void:
	if not reachable.has(node_id):
		reachable[node_id] = true
		pending.append(node_id)

static func _add_cycle_diagnostics(
	index: SemanticGraphIndex,
	kind: String,
	excluded_connection_ids: Array,
	reason_code: String,
	diagnostics: Array
) -> DomainResult:
	for component: Array in _strong_components(index, kind, excluded_connection_ids):
		if not _is_cyclic_component(index, component, kind, excluded_connection_ids):
			continue
		var ids: Array[String] = []
		for raw_id: Variant in component:
			ids.append(String(raw_id))
		var add_result := _append_diagnostic(
			diagnostics,
			reason_code,
			SemanticDiagnosticType.ENTITY_COMPONENT,
			ids[0],
			ids.slice(1))
		if not add_result.is_success():
			return add_result
	return DomainResult.success(true)

static func _is_cyclic_component(
	index: SemanticGraphIndex,
	component: Array,
	kind: String,
	excluded_connection_ids: Array
) -> bool:
	return component.size() > 1 or _has_self_loop(
		index, component[0], kind, excluded_connection_ids)

static func _strong_components(
	index: SemanticGraphIndex,
	kind: String,
	excluded_connection_ids: Array
) -> Array:
	var components: Array = []
	var seen_components: Dictionary = {}
	var nodes: Array[String] = index.node_ids()
	for origin: String in nodes:
		var forward := _walk_kind(index, origin, kind, excluded_connection_ids)
		var component: Array[String] = []
		for candidate: String in nodes:
			if forward.has(candidate) and _walk_kind(
				index, candidate, kind, excluded_connection_ids).has(origin):
				component.append(candidate)
		if component.is_empty():
			continue
		var key := _component_key(component)
		if not seen_components.has(key):
			seen_components[key] = true
			components.append(component)
	return components

static func _walk_kind(
	index: SemanticGraphIndex,
	origin: String,
	kind: String,
	excluded_connection_ids: Array
) -> Dictionary:
	var visited: Dictionary = {origin: true}
	var pending: Array[String] = [origin]
	while not pending.is_empty():
		var current: String = pending.pop_front()
		for connection: Dictionary in index.outgoing(current, kind):
			if excluded_connection_ids.has(connection["connection_id"]):
				continue
			_add_reachable(visited, pending, connection["target_node_id"])
	return visited

static func _has_self_loop(
	index: SemanticGraphIndex,
	node_id: String,
	kind: String,
	excluded_connection_ids: Array
) -> bool:
	for connection: Dictionary in index.outgoing(node_id, kind):
		if (
			connection["target_node_id"] == node_id
			and not excluded_connection_ids.has(connection["connection_id"])
		):
			return true
	return false

static func _add_repeat_diagnostics(
	index: SemanticGraphIndex,
	diagnostics: Array
) -> DomainResult:
	var region_result := _repeat_regions(index)
	if not region_result.is_success():
		return region_result
	var regions: Dictionary = region_result.value()
	var valid_returns: Array[String] = []
	for repeat_id: String in _repeat_ids(index):
		var region: Dictionary = regions[repeat_id]
		for connection_id: String in region["valid_return_ids"]:
			valid_returns.append(connection_id)
		for event: Dictionary in region["events"]:
			var add_result := _append_diagnostic(
				diagnostics,
				event["reason_code"],
				event["entity_kind"],
				event["primary_entity_id"],
				event.get("related_entity_ids", []))
			if not add_result.is_success():
				return add_result
	var add_result := _add_crossed_region_diagnostics(index, regions, diagnostics)
	if not add_result.is_success():
		return add_result
	add_result = _add_outside_continue_diagnostics(index, regions, diagnostics)
	if not add_result.is_success():
		return add_result
	return DomainResult.success(valid_returns)

static func _repeat_ids(index: SemanticGraphIndex) -> Array[String]:
	var result: Array[String] = []
	for node_id: String in index.node_ids():
		if index.category_of(node_id) == SemanticGraphIndexType.CATEGORY_REPEAT:
			result.append(node_id)
	return result

static func _repeat_regions(index: SemanticGraphIndex) -> DomainResult:
	var regions: Dictionary = {}
	for repeat_id: String in _repeat_ids(index):
		var walk := _walk_repeat(index, repeat_id)
		if not walk.is_success():
			return walk
		regions[repeat_id] = walk.value()
	_expand_inclusive_regions(index, regions)
	return DomainResult.success(regions)

static func _walk_repeat(index: SemanticGraphIndex, repeat_id: String) -> DomainResult:
	var body_edges := _port_connections(index, repeat_id, "body", true)
	var events: Array = []
	var valid_returns: Array[String] = []
	var direct_members: Dictionary = {}
	if body_edges.is_empty():
		return DomainResult.success({
			"direct_members": direct_members,
			"inclusive_members": {},
			"valid_return_ids": valid_returns,
			"events": events,
		})
	var pending: Array[String] = []
	for edge: Dictionary in body_edges:
		_process_direct_repeat_edge(
			index, repeat_id, edge, pending, valid_returns, events)
	var visited: Dictionary = {}
	while not pending.is_empty():
		var node_id: String = pending.pop_front()
		if visited.has(node_id):
			continue
		visited[node_id] = true
		direct_members[node_id] = true
		if (
			node_id != repeat_id
			and index.category_of(node_id) == SemanticGraphIndexType.CATEGORY_REPEAT
		):
			for connection: Dictionary in _port_connections(index, node_id, "done", true):
				_process_direct_repeat_edge(
					index, repeat_id, connection, pending, valid_returns, events)
			continue
		for connection: Dictionary in index.outgoing(node_id, "execution"):
			_process_direct_repeat_edge(
				index, repeat_id, connection, pending, valid_returns, events)
	return DomainResult.success({
		"direct_members": direct_members,
		"inclusive_members": direct_members.duplicate(),
		"valid_return_ids": valid_returns,
		"events": events,
	})

static func _process_direct_repeat_edge(
	index: SemanticGraphIndex,
	repeat_id: String,
	connection: Dictionary,
	pending: Array[String],
	valid_returns: Array[String],
	events: Array
) -> void:
	var target: String = connection["target_node_id"]
	var target_port: String = connection["target_port_id"]
	if target == repeat_id:
		if target_port == "continue":
			valid_returns.append(connection["connection_id"])
		elif target_port == "in":
			events.append(_repeat_connection_event(
				SemanticDiagnosticType.CODE_REPEAT_BODY_TO_IN,
			connection["connection_id"]))
		return
	if index.category_of(target) == SemanticGraphIndexType.CATEGORY_END:
		events.append(_repeat_connection_event(
			SemanticDiagnosticType.CODE_REPEAT_BODY_EXIT,
			connection["connection_id"]))
		return
	if (
		index.category_of(target) == SemanticGraphIndexType.CATEGORY_REPEAT
		and target_port == "continue"
	):
		events.append(_repeat_connection_event(
			SemanticDiagnosticType.CODE_REPEAT_BODY_EXIT,
			connection["connection_id"]))
		return
	pending.append(target)

static func _expand_inclusive_regions(
	index: SemanticGraphIndex,
	regions: Dictionary
) -> void:
	for _pass: int in range(regions.size() + 1):
		var changed := false
		for repeat_id: String in _sorted_dictionary_keys(regions):
			var region: Dictionary = regions[repeat_id]
			var inclusive: Dictionary = region["inclusive_members"]
			for member_id: String in _sorted_dictionary_keys(region["direct_members"]):
				if (
					index.category_of(member_id) != SemanticGraphIndexType.CATEGORY_REPEAT
					or not regions.has(member_id)
				):
					continue
				for nested_id: String in _sorted_dictionary_keys(
					regions[member_id]["inclusive_members"]):
					if not inclusive.has(nested_id):
						inclusive[nested_id] = true
						changed = true
			region["inclusive_members"] = inclusive
			regions[repeat_id] = region
		if not changed:
			return

static func _add_crossed_region_diagnostics(
	index: SemanticGraphIndex,
	regions: Dictionary,
	diagnostics: Array
) -> DomainResult:
	for repeat_id: String in _sorted_dictionary_keys(regions):
		var inclusive: Dictionary = regions[repeat_id]["inclusive_members"]
		for connection: Dictionary in index.connection_records():
			if index.connection_kind(connection) != "execution":
				continue
			var source_inside: bool = inclusive.has(connection["source_node_id"])
			var target_inside: bool = inclusive.has(connection["target_node_id"])
			var body_entry: bool = (
				connection["source_node_id"] == repeat_id
				and connection["source_port_id"] == "body"
				and target_inside)
			if target_inside and not source_inside and not body_entry:
				var add_result := _append_diagnostic(
					diagnostics,
					SemanticDiagnosticType.CODE_REPEAT_CROSSED_REGION,
					SemanticDiagnosticType.ENTITY_CONNECTION,
					connection["connection_id"])
				if not add_result.is_success():
					return add_result
	return DomainResult.success(true)

static func _add_outside_continue_diagnostics(
	index: SemanticGraphIndex,
	regions: Dictionary,
	diagnostics: Array
) -> DomainResult:
	for connection: Dictionary in index.connection_records():
		if (
			index.connection_kind(connection) != "execution"
			or connection["target_port_id"] != "continue"
		):
			continue
		var target: String = connection["target_node_id"]
		if index.category_of(target) != SemanticGraphIndexType.CATEGORY_REPEAT:
			continue
		var direct_member: bool = (
			regions.has(target)
			and regions[target]["direct_members"].has(connection["source_node_id"]))
		if not direct_member:
			var add_result := _append_diagnostic(
				diagnostics,
				SemanticDiagnosticType.CODE_REPEAT_OUTSIDE_CONTINUE,
				SemanticDiagnosticType.ENTITY_CONNECTION,
				connection["connection_id"])
			if not add_result.is_success():
				return add_result
	return DomainResult.success(true)

static func _port_connections(
	index: SemanticGraphIndex,
	node_id: String,
	port_id: String,
	outgoing: bool
) -> Array:
	var connections: Array = (
		index.outgoing(node_id, "execution")
		if outgoing
		else index.incoming(node_id, "execution"))
	var filtered: Array = []
	for connection: Dictionary in connections:
		var endpoint: String = (
			connection["source_port_id"]
			if outgoing
			else connection["target_port_id"])
		if endpoint == port_id:
			filtered.append(connection)
	return filtered

static func _repeat_connection_event(
	reason_code: String,
	connection_id: String
) -> Dictionary:
	return {
		"reason_code": reason_code,
		"entity_kind": SemanticDiagnosticType.ENTITY_CONNECTION,
		"primary_entity_id": connection_id,
		"related_entity_ids": [],
	}

static func _append_diagnostic(
	diagnostics: Array,
	reason_code: String,
	entity_kind: String,
	primary_entity_id: String = "",
	related_entity_ids: Array = []
) -> DomainResult:
	var created: DomainResult = SemanticDiagnosticType.create(
		reason_code, entity_kind, primary_entity_id, related_entity_ids)
	if not created.is_success():
		return DomainResult.failure(
			&"semantic_validation_error",
			"semantic diagnostic construction failed closed")
	var candidate: SemanticDiagnostic = created.value()
	for existing: SemanticDiagnostic in diagnostics:
		if existing.equals(candidate):
			return DomainResult.success(false)
	diagnostics.append(candidate)
	return DomainResult.success(true)

static func _sorted_dictionary_keys(value: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for raw_key: Variant in value.keys():
		keys.append(String(raw_key))
	keys.sort_custom(_ordinal_less)
	return keys

static func _component_key(component: Array[String]) -> String:
	var key := ""
	for node_id: String in component:
		key += "%d:%s" % [node_id.length(), node_id]
	return key

static func _ordinal_less(left: String, right: String) -> bool:
	var left_bytes := left.to_utf8_buffer()
	var right_bytes := right.to_utf8_buffer()
	var shared: int = mini(left_bytes.size(), right_bytes.size())
	for index: int in range(shared):
		if left_bytes[index] != right_bytes[index]:
			return left_bytes[index] < right_bytes[index]
	return left_bytes.size() < right_bytes.size()
