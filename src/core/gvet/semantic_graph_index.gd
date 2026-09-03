class_name SemanticGraphIndex
extends RefCounted

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CanonicalJsonIRType = preload("res://src/foundation/canonical_json_ir.gd")

const CATEGORY_START: String = "Start"
const CATEGORY_ACTION: String = "Action"
const CATEGORY_QUERY: String = "Query"
const CATEGORY_CONSTANT: String = "Constant"
const CATEGORY_COMPARE: String = "Compare"
const CATEGORY_BRANCH: String = "Branch"
const CATEGORY_REPEAT: String = "Repeat"
const CATEGORY_END: String = "End"

var _locked: bool = false:
	set(value):
		if _locked:
			return
		_locked = value
var _nodes: Array = []:
	get:
		return CanonicalJsonIRType.clone(_nodes)
	set(value):
		if _locked:
			return
		_nodes = CanonicalJsonIRType.clone(value)
var _connections: Array = []:
	get:
		return CanonicalJsonIRType.clone(_connections)
	set(value):
		if _locked:
			return
		_connections = CanonicalJsonIRType.clone(value)
var _node_by_id: Dictionary = {}:
	get:
		return CanonicalJsonIRType.clone(_node_by_id)
	set(value):
		if _locked:
			return
		_node_by_id = CanonicalJsonIRType.clone(value)
var _connection_by_id: Dictionary = {}:
	get:
		return CanonicalJsonIRType.clone(_connection_by_id)
	set(value):
		if _locked:
			return
		_connection_by_id = CanonicalJsonIRType.clone(value)
var _valid: bool = false:
	set(value):
		if _locked:
			return
		_valid = value

## Normalizes one structurally admitted graph and its exact bound Authoring
## registry into an immutable pure-data index.
## Example: `SemanticGraphIndex.create(graph, authoring_registry)`.
static func create(graph: Dictionary, registry: Dictionary) -> DomainResult:
	var index := new(graph, registry)
	if not index.is_valid():
		return DomainResult.failure(&"construction_failed", "validated graph index could not be constructed")
	return DomainResult.success(index)

func _init(graph: Variant = null, registry: Variant = null) -> void:
	if graph == null or registry == null or typeof(graph) != TYPE_DICTIONARY or typeof(registry) != TYPE_DICTIONARY:
		_locked = true
		return
	var state_result := _build_state(graph, registry)
	if not state_result.is_success():
		_locked = true
		return
	var state: Dictionary = state_result.value()
	_nodes = state["nodes"]
	_connections = state["connections"]
	_node_by_id = state["node_by_id"]
	_connection_by_id = state["connection_by_id"]
	_valid = true
	_locked = true

static func _build_state(graph: Dictionary, registry: Dictionary) -> DomainResult:
	var pure_result := _validate_pure_inputs(graph, registry)
	if not pure_result.is_success():
		return pure_result
	var graph_shape := _validate_graph_shape(graph)
	if not graph_shape.is_success():
		return graph_shape
	var registry_shape := _validate_registry_shape(registry)
	if not registry_shape.is_success():
		return registry_shape
	var variants_result := _normalize_variants(registry)
	if not variants_result.is_success():
		return variants_result
	var variants: Dictionary = variants_result.value()
	var nodes_result := _build_nodes(graph["nodes"], variants)
	if not nodes_result.is_success():
		return nodes_result
	var node_state: Dictionary = nodes_result.value()
	var normalized_nodes: Array = node_state["nodes"]
	var connections_result := _build_connections(graph["connections"], normalized_nodes, node_state["node_ids"])
	if not connections_result.is_success():
		return connections_result
	var normalized_connections: Array = connections_result.value()
	return DomainResult.success({
		"nodes": normalized_nodes,
		"connections": normalized_connections,
		"node_by_id": _record_map(normalized_nodes, "node_id"),
		"connection_by_id": _record_map(normalized_connections, "connection_id"),
	})

static func _validate_pure_inputs(graph: Dictionary, registry: Dictionary) -> DomainResult:
	if not CanonicalJsonIRType.validate_pure_json(graph).is_success():
		return DomainResult.failure(&"invalid_graph", "graph input must be pure declarative data")
	if not CanonicalJsonIRType.validate_pure_json(registry).is_success():
		return DomainResult.failure(&"invalid_registry", "registry input must be pure declarative data")
	return DomainResult.success(true)

static func _build_nodes(raw_nodes: Array, variants: Dictionary) -> DomainResult:
	var normalized_nodes: Array = []
	var node_ids: Dictionary = {}
	for raw_node: Variant in raw_nodes:
		var node_result := _normalize_node(raw_node, variants)
		if not node_result.is_success():
			return node_result
		var node: Dictionary = node_result.value()
		var node_id: String = node["node_id"]
		if node_ids.has(node_id):
			return DomainResult.failure(&"duplicate_node", "node IDs must be unique", "$.nodes")
		node_ids[node_id] = true
		normalized_nodes.append(node)
	return DomainResult.success({"nodes": _sort_records_by_id(normalized_nodes, "node_id"), "node_ids": node_ids})

static func _build_connections(raw_connections: Array, normalized_nodes: Array, node_ids: Dictionary) -> DomainResult:
	var normalized_connections: Array = []
	var connection_ids: Dictionary = {}
	for raw_connection: Variant in raw_connections:
		var connection_result := _normalize_connection(raw_connection)
		if not connection_result.is_success():
			return connection_result
		var connection: Dictionary = connection_result.value()
		var connection_id: String = connection["connection_id"]
		if connection_ids.has(connection_id):
			return DomainResult.failure(&"duplicate_connection", "connection IDs must be unique", "$.connections")
		var endpoint_result := _validate_connection_endpoints(connection, normalized_nodes, node_ids)
		if not endpoint_result.is_success():
			return endpoint_result
		connection_ids[connection_id] = true
		normalized_connections.append(connection)
	return DomainResult.success(_sort_records_by_id(normalized_connections, "connection_id"))

static func _validate_connection_endpoints(connection: Dictionary, nodes: Array, node_ids: Dictionary) -> DomainResult:
	if not node_ids.has(connection["source_node_id"]) or not node_ids.has(connection["target_node_id"]):
		return DomainResult.failure(&"unknown_endpoint", "connection endpoint node is not registered", "$.connections")
	var source_port := _port_from_nodes(nodes, connection["source_node_id"], connection["source_port_id"])
	var target_port := _port_from_nodes(nodes, connection["target_node_id"], connection["target_port_id"])
	if source_port.is_empty() or target_port.is_empty():
		return DomainResult.failure(&"unknown_endpoint", "connection endpoint port is not registered", "$.connections")
	if source_port["direction"] != "output" or target_port["direction"] != "input" or source_port["kind"] != target_port["kind"]:
		return DomainResult.failure(&"invalid_endpoint", "connection direction or kind is not compatible", "$.connections")
	if source_port["kind"] == "data" and source_port["data_type"] != target_port["data_type"]:
		return DomainResult.failure(&"invalid_endpoint", "data connection types must match", "$.connections")
	return DomainResult.success(true)

static func _record_map(records: Array, key: String) -> Dictionary:
	var result: Dictionary = {}
	for record: Dictionary in records:
		result[record[key]] = record
	return result

## Returns whether the immutable index was constructed from pure data.
func is_valid() -> bool:
	return _valid

## Returns sorted node IDs.
func node_ids() -> Array[String]:
	var result: Array[String] = []
	for node: Dictionary in _nodes:
		result.append(node["node_id"])
	return result

## Returns defensive node records in canonical ID order.
func node_records() -> Array:
	return CanonicalJsonIRType.clone(_nodes)

## Returns defensive connection records in canonical ID order.
func connection_records() -> Array:
	return CanonicalJsonIRType.clone(_connections)

## Returns a detached node record, or an empty dictionary when absent.
func node_record(node_id: String) -> Dictionary:
	return CanonicalJsonIRType.clone(_node_by_id.get(node_id, {}))

## Returns a detached connection record, or an empty dictionary when absent.
func connection_record(connection_id: String) -> Dictionary:
	return CanonicalJsonIRType.clone(_connection_by_id.get(connection_id, {}))

## Returns all connections from a node, optionally filtered by semantic kind.
func outgoing(node_id: String, kind: String = "") -> Array:
	return _connections_for(node_id, true, kind)

## Returns all connections into a node, optionally filtered by semantic kind.
func incoming(node_id: String, kind: String = "") -> Array:
	return _connections_for(node_id, false, kind)

## Returns the registered port descriptor for one endpoint.
func port_descriptor(node_id: String, port_id: String) -> Dictionary:
	var node: Dictionary = _node_by_id.get(node_id, {})
	for port: Dictionary in node.get("ports", []):
		if port["port_id"] == port_id:
			return CanonicalJsonIRType.clone(port)
	return {}

## Returns a node's category ID.
func category_of(node_id: String) -> String:
	return String(_node_by_id.get(node_id, {}).get("category_id", ""))

## Returns whether a node category is a control-flow category.
func is_control_node(node_id: String) -> bool:
	return _is_control_category(category_of(node_id))

## Returns whether a connection is a data edge.
func is_data_connection(connection: Dictionary) -> bool:
	return _connection_kind(connection) == "data"

## Returns whether a connection is an execution edge.
func is_execution_connection(connection: Dictionary) -> bool:
	return _connection_kind(connection) == "execution"

## Returns the effective semantic kind for an endpoint connection.
func connection_kind(connection: Dictionary) -> String:
	return _connection_kind(connection)

## Returns the minimum required cardinality for a port.
func required_minimum(node_id: String, port_id: String) -> int:
	var port := port_descriptor(node_id, port_id)
	return int(port.get("minimum_connections", 0))

## Returns the registered order used by port diagnostics.
func registered_port_order(node_id: String, port_id: String) -> int:
	var port := port_descriptor(node_id, port_id)
	return int(port.get("registry_order", -1))

## Returns required ports in registered order then ordinal ID order.
func required_ports(node_id: String) -> Array:
	var result: Array = []
	var node: Dictionary = _node_by_id.get(node_id, {})
	for port: Dictionary in node.get("ports", []):
		if int(port.get("minimum_connections", 0)) > 0:
			result.append(CanonicalJsonIRType.clone(port))
	return _sort_ports(result)

## Returns port descriptors in registry order.
func ports(node_id: String) -> Array:
	var node: Dictionary = _node_by_id.get(node_id, {})
	return CanonicalJsonIRType.clone(node.get("ports", []))

static func _validate_graph_shape(graph: Dictionary) -> DomainResult:
	if not _has_exact_string_keys(graph, ["graph_codec_version", "fixture_id", "nodes", "connections"]):
		return DomainResult.failure(&"invalid_graph", "authoring_graph_v1 fields are not exact")
	if graph["graph_codec_version"] != "authoring_graph_v1":
		return DomainResult.failure(&"invalid_graph", "graph codec version is not authoring_graph_v1")
	if typeof(graph["fixture_id"]) != TYPE_STRING or not _valid_ascii_id(graph["fixture_id"]):
		return DomainResult.failure(&"invalid_graph", "graph fixture_id must be a non-empty ASCII ID")
	if typeof(graph["nodes"]) != TYPE_ARRAY or typeof(graph["connections"]) != TYPE_ARRAY:
		return DomainResult.failure(&"invalid_graph", "graph nodes and connections must be arrays")
	return DomainResult.success(true)

static func _validate_registry_shape(registry: Dictionary) -> DomainResult:
	var fields := ["registry_codec_version", "resolved_locale_id", "categories", "variants", "reasons", "trace_outcomes", "message_templates", "node_actions", "editor_controls"]
	if not _has_exact_string_keys(registry, fields):
		return DomainResult.failure(&"invalid_registry", "authoring_registry_v1 fields are not exact")
	if registry["registry_codec_version"] != "authoring_registry_v1":
		return DomainResult.failure(&"invalid_registry", "registry codec version is not authoring_registry_v1")
	if typeof(registry["resolved_locale_id"]) != TYPE_STRING or String(registry["resolved_locale_id"]).is_empty():
		return DomainResult.failure(&"invalid_registry", "registry resolved_locale_id must be a string")
	for field: String in fields.slice(2):
		if typeof(registry[field]) != TYPE_ARRAY:
			return DomainResult.failure(&"invalid_registry", "%s must be an array" % field)
	return _validate_categories(registry["categories"])

static func _validate_categories(categories: Array) -> DomainResult:
	var seen: Dictionary = {}
	for raw_category: Variant in categories:
		var category_result := _validate_category(raw_category, seen)
		if not category_result.is_success():
			return category_result
		var category: Dictionary = category_result.value()
		if seen.has(category["category_id"]):
			return DomainResult.failure(&"invalid_registry", "category IDs must be unique")
		seen[category["category_id"]] = true
	if seen.size() != 8:
		return DomainResult.failure(&"invalid_registry", "registry must contain the exact eight categories")
	return DomainResult.success(true)

static func _validate_category(raw_category: Variant, seen: Dictionary) -> DomainResult:
	if typeof(raw_category) != TYPE_DICTIONARY:
		return DomainResult.failure(&"invalid_registry", "category descriptors must be dictionaries")
	var category: Dictionary = raw_category
	if not _has_exact_string_keys(category, ["category_id", "registry_order", "title"]):
		return DomainResult.failure(&"invalid_registry", "category descriptor fields are not exact")
	if typeof(category["category_id"]) != TYPE_STRING or not _is_known_category(category["category_id"]):
		return DomainResult.failure(&"invalid_registry", "category ID is not registered")
	if seen.has(category["category_id"]):
		return DomainResult.failure(&"invalid_registry", "category IDs must be unique")
	if typeof(category["registry_order"]) != TYPE_INT or int(category["registry_order"]) < 0:
		return DomainResult.failure(&"invalid_registry", "category registry order is invalid")
	if typeof(category["title"]) != TYPE_STRING:
		return DomainResult.failure(&"invalid_registry", "category title must be a string")
	return DomainResult.success(category)

static func _normalize_variants(registry: Dictionary) -> DomainResult:
	if not registry.has("variants") or typeof(registry["variants"]) != TYPE_ARRAY:
		return DomainResult.failure(&"invalid_registry", "authoring_registry_v1 requires a variants array")
	var entries: Array = registry["variants"]
	var result: Dictionary = {}
	var category_ids: Dictionary = {}
	for category: Dictionary in registry["categories"]:
		category_ids[category["category_id"]] = true
	for raw_entry: Variant in entries:
		var variant_result := _normalize_variant(raw_entry, category_ids)
		if not variant_result.is_success():
			return variant_result
		var variant: Dictionary = variant_result.value()
		var variant_id: String = variant["variant_id"]
		if result.has(variant_id):
			return DomainResult.failure(&"duplicate_variant", "variant IDs must be unique")
		result[variant_id] = variant
	return DomainResult.success(result)

static func _normalize_variant(raw_entry: Variant, category_ids: Dictionary) -> DomainResult:
	if typeof(raw_entry) != TYPE_DICTIONARY:
		return DomainResult.failure(&"invalid_variant", "variant descriptors must be dictionaries")
	var entry: Dictionary = CanonicalJsonIRType.clone(raw_entry)
	var shape_result := _validate_variant_shape(entry, category_ids)
	if not shape_result.is_success():
		return shape_result
	var ports_result := _normalize_ports(entry["ports"], entry["category_id"])
	if not ports_result.is_success():
		return ports_result
	return DomainResult.success({"variant_id": entry["variant_id"], "category_id": entry["category_id"], "ports": ports_result.value()})

static func _validate_variant_shape(entry: Dictionary, category_ids: Dictionary) -> DomainResult:
	var fields := ["variant_id", "category_id", "registry_order", "title", "ports", "parameters", "node_action_ids", "max_footprint_width", "max_footprint_height"]
	if not _has_exact_string_keys(entry, fields):
		return DomainResult.failure(&"invalid_variant", "variant descriptor fields are not exact")
	if typeof(entry["variant_id"]) != TYPE_STRING or not _valid_ascii_id(entry["variant_id"]):
		return DomainResult.failure(&"invalid_variant", "variant descriptors require variant_id")
	if typeof(entry["category_id"]) != TYPE_STRING or not category_ids.has(entry["category_id"]):
		return DomainResult.failure(&"invalid_variant", "variant category is not registered")
	if typeof(entry["registry_order"]) != TYPE_INT or int(entry["registry_order"]) < 0 or typeof(entry["title"]) != TYPE_STRING:
		return DomainResult.failure(&"invalid_variant", "variant registry order or title is invalid")
	if typeof(entry["ports"]) != TYPE_ARRAY or typeof(entry["parameters"]) != TYPE_ARRAY or typeof(entry["node_action_ids"]) != TYPE_ARRAY:
		return DomainResult.failure(&"invalid_variant", "variant collection fields must be arrays")
	if not _finite_number(entry["max_footprint_width"]) or not _finite_number(entry["max_footprint_height"]):
		return DomainResult.failure(&"invalid_variant", "variant footprint must be finite numeric data")
	return DomainResult.success(true)

static func _normalize_node(raw_node: Variant, variants: Dictionary) -> DomainResult:
	if typeof(raw_node) != TYPE_DICTIONARY:
		return DomainResult.failure(&"invalid_node", "node records must be dictionaries")
	var source: Dictionary = CanonicalJsonIRType.clone(raw_node)
	var source_result := _validate_node_source(source)
	if not source_result.is_success():
		return source_result
	var node_id: String = source["node_id"]
	var variant_id: String = source["variant_id"]
	var variant: Dictionary = variants.get(variant_id, {})
	if variant.is_empty():
		return DomainResult.failure(&"unknown_variant", "node variant is not registered")
	var category: String = variant["category_id"]
	return DomainResult.success({
		"node_id": node_id,
		"variant_id": variant_id,
		"category_id": category,
		"ports": CanonicalJsonIRType.clone(variant["ports"]),
	})

static func _validate_node_source(source: Dictionary) -> DomainResult:
	if not _has_exact_string_keys(source, ["node_id", "variant_id", "anchor_x", "anchor_y", "parameter_values"]):
		return DomainResult.failure(&"invalid_node", "graph node fields are not exact")
	if typeof(source["node_id"]) != TYPE_STRING or not _valid_ascii_id(source["node_id"]):
		return DomainResult.failure(&"invalid_node", "node records require node_id")
	if typeof(source["variant_id"]) != TYPE_STRING or not _valid_ascii_id(source["variant_id"]):
		return DomainResult.failure(&"invalid_node", "node records require variant_id")
	if not _finite_number(source["anchor_x"]) or not _finite_number(source["anchor_y"]):
		return DomainResult.failure(&"invalid_node", "node anchors must be finite")
	if typeof(source["parameter_values"]) != TYPE_ARRAY:
		return DomainResult.failure(&"invalid_node", "node parameter_values must be an array")
	return _validate_parameter_values(source["parameter_values"])

static func _normalize_connection(raw_connection: Variant) -> DomainResult:
	if typeof(raw_connection) != TYPE_DICTIONARY:
		return DomainResult.failure(&"invalid_connection", "connection records must be dictionaries")
	var source: Dictionary = CanonicalJsonIRType.clone(raw_connection)
	var required_fields := ["connection_id", "source_node_id", "source_port_id", "target_node_id", "target_port_id"]
	if not _has_exact_string_keys(source, required_fields):
		return DomainResult.failure(&"invalid_connection", "graph connection fields are not exact")
	for field: String in required_fields:
		if typeof(source[field]) != TYPE_STRING or not _valid_ascii_id(source[field]):
			return DomainResult.failure(&"invalid_connection", "connections require %s" % field)
	var connection_id: String = source["connection_id"]
	if connection_id.is_empty():
		return DomainResult.failure(&"invalid_connection", "connection records require connection_id")
	return DomainResult.success({
		"connection_id": connection_id,
		"source_node_id": source["source_node_id"],
		"source_port_id": source["source_port_id"],
		"target_node_id": source["target_node_id"],
		"target_port_id": source["target_port_id"],
	})

static func _normalize_ports(raw_ports: Variant, category: String) -> DomainResult:
	if typeof(raw_ports) != TYPE_ARRAY:
		return DomainResult.failure(&"invalid_port", "ports must be an array or dictionary")
	var entries: Array = raw_ports
	var normalized: Array = []
	var seen: Dictionary = {}
	for index: int in range(entries.size()):
		var port_result := _normalize_port(entries[index], category, seen)
		if not port_result.is_success():
			return port_result
		normalized.append(port_result.value())
	return DomainResult.success(_sort_ports(normalized))

static func _normalize_port(raw_entry: Variant, category: String, seen: Dictionary) -> DomainResult:
	if typeof(raw_entry) != TYPE_DICTIONARY:
		return DomainResult.failure(&"invalid_port", "port descriptors must be dictionaries")
	var entry: Dictionary = CanonicalJsonIRType.clone(raw_entry)
	var shape_result := _validate_port_shape(entry, seen)
	if not shape_result.is_success():
		return shape_result
	var data_type_result := _normalized_port_data_type(entry)
	if not data_type_result.is_success():
		return data_type_result
	var port_id: String = entry["port_id"]
	seen[port_id] = true
	return DomainResult.success({
		"port_id": port_id, "registry_order": entry["registry_order"],
		"direction": entry["direction"], "kind": entry["kind"],
		"data_type": data_type_result.value(),
		"minimum_connections": _required_minimum(category, port_id, entry["direction"], entry["kind"]),
		"maximum_connections": entry["maximum_connections"],
	})

static func _validate_port_shape(entry: Dictionary, seen: Dictionary) -> DomainResult:
	var fields := ["port_id", "registry_order", "direction", "kind", "maximum_connections", "label"]
	if entry.get("kind", null) == "data":
		fields.append("data_type")
	if not _has_exact_string_keys(entry, fields):
		return DomainResult.failure(&"invalid_port", "port descriptor fields are not exact")
	if typeof(entry["port_id"]) != TYPE_STRING or not _valid_ascii_id(entry["port_id"]) or seen.has(entry["port_id"]):
		return DomainResult.failure(&"duplicate_port", "port IDs must be unique non-empty ASCII IDs")
	if typeof(entry["direction"]) != TYPE_STRING or not ["input", "output"].has(entry["direction"]):
		return DomainResult.failure(&"invalid_port", "port direction is not registered")
	if typeof(entry["kind"]) != TYPE_STRING or not ["execution", "data"].has(entry["kind"]):
		return DomainResult.failure(&"invalid_port", "port kind is not registered")
	if typeof(entry["registry_order"]) != TYPE_INT or int(entry["registry_order"]) < 0:
		return DomainResult.failure(&"invalid_port", "port registry order must be non-negative")
	if typeof(entry["maximum_connections"]) != TYPE_INT or int(entry["maximum_connections"]) < 1 or typeof(entry["label"]) != TYPE_STRING:
		return DomainResult.failure(&"invalid_port", "port maximum connections or label is invalid")
	return DomainResult.success(true)

static func _normalized_port_data_type(entry: Dictionary) -> DomainResult:
	if entry["kind"] == "execution":
		return DomainResult.success("")
	if typeof(entry.get("data_type", null)) != TYPE_STRING or String(entry["data_type"]).is_empty():
		return DomainResult.failure(&"invalid_port", "data ports require data_type")
	if not ["Boolean", "numeric", "label"].has(entry["data_type"]):
		return DomainResult.failure(&"invalid_port", "data port type is not registered")
	return DomainResult.success(entry["data_type"])

static func _validate_parameter_values(values: Array) -> DomainResult:
	var seen: Dictionary = {}
	for raw_value: Variant in values:
		if typeof(raw_value) != TYPE_DICTIONARY:
			return DomainResult.failure(&"invalid_node", "parameter values must be dictionaries")
		var value: Dictionary = raw_value
		if not _has_exact_string_keys(value, ["parameter_id", "value"]):
			return DomainResult.failure(&"invalid_node", "parameter value fields are not exact")
		if typeof(value["parameter_id"]) != TYPE_STRING or not _valid_ascii_id(value["parameter_id"]) or seen.has(value["parameter_id"]):
			return DomainResult.failure(&"invalid_node", "parameter IDs must be unique ASCII IDs")
		seen[value["parameter_id"]] = true
	return DomainResult.success(true)

static func _port_from_nodes(nodes: Array, node_id: String, port_id: String) -> Dictionary:
	for node: Dictionary in nodes:
		if node["node_id"] != node_id:
			continue
		for port: Dictionary in node["ports"]:
			if port["port_id"] == port_id:
				return port
	return {}

static func _required_minimum(category: String, port_id: String, direction: String, kind: String) -> int:
	var key: String = "%s|%s|%s|%s" % [category, kind, direction, port_id]
	match key:
		"Start|execution|output|next", \
		"Action|execution|input|in", \
		"Action|execution|output|next", \
		"Query|data|output|value", \
		"Constant|data|output|value", \
		"Compare|data|input|left", \
		"Compare|data|input|right", \
		"Compare|data|output|result", \
		"Branch|execution|input|in", \
		"Branch|execution|output|true", \
		"Branch|execution|output|false", \
		"Branch|data|input|condition", \
		"Repeat|execution|input|in", \
		"Repeat|execution|input|continue", \
		"Repeat|execution|output|body", \
		"Repeat|execution|output|done", \
		"End|execution|input|in":
			return 1
		_:
			return 0

static func _is_known_category(category: String) -> bool:
	return category in [CATEGORY_START, CATEGORY_ACTION, CATEGORY_QUERY, CATEGORY_CONSTANT, CATEGORY_COMPARE, CATEGORY_BRANCH, CATEGORY_REPEAT, CATEGORY_END]

static func _is_control_category(category: String) -> bool:
	return category in [CATEGORY_START, CATEGORY_ACTION, CATEGORY_BRANCH, CATEGORY_REPEAT, CATEGORY_END]

func _connection_kind(connection: Dictionary) -> String:
	var source_port := port_descriptor(connection["source_node_id"], connection["source_port_id"])
	var target_port := port_descriptor(connection["target_node_id"], connection["target_port_id"])
	var source_kind := String(source_port.get("kind", ""))
	var target_kind := String(target_port.get("kind", ""))
	if source_kind == target_kind and not source_kind.is_empty():
		return source_kind
	return String(connection.get("kind", ""))

func _connections_for(node_id: String, source_side: bool, kind: String) -> Array:
	var result: Array = []
	for connection: Dictionary in _connections:
		var matches: bool = connection["source_node_id"] == node_id if source_side else connection["target_node_id"] == node_id
		if matches and (kind.is_empty() or _connection_kind(connection) == kind):
			result.append(CanonicalJsonIRType.clone(connection))
	return result

static func _sort_records_by_id(records: Array, key: String) -> Array:
	var sorted: Array = []
	for record: Dictionary in records:
		var insert_at := sorted.size()
		for index: int in range(sorted.size()):
			if _ordinal_less(String(record[key]), String(sorted[index][key])):
				insert_at = index
				break
		sorted.insert(insert_at, CanonicalJsonIRType.clone(record))
	return sorted

static func _sort_ports(ports: Array) -> Array:
	var sorted: Array = []
	for port: Dictionary in ports:
		var insert_at := sorted.size()
		for index: int in range(sorted.size()):
			var current: Dictionary = sorted[index]
			if int(port.get("registry_order", 0)) < int(current.get("registry_order", 0)) or (int(port.get("registry_order", 0)) == int(current.get("registry_order", 0)) and _ordinal_less(String(port.get("port_id", "")), String(current.get("port_id", "")))):
				insert_at = index
				break
		sorted.insert(insert_at, CanonicalJsonIRType.clone(port))
	return sorted

static func _ordinal_less(left: String, right: String) -> bool:
	var left_bytes := left.to_utf8_buffer()
	var right_bytes := right.to_utf8_buffer()
	var shared_length: int = mini(left_bytes.size(), right_bytes.size())
	for index: int in range(shared_length):
		if left_bytes[index] != right_bytes[index]:
			return left_bytes[index] < right_bytes[index]
	return left_bytes.size() < right_bytes.size()

static func _has_exact_string_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for raw_key: Variant in value.keys():
		if typeof(raw_key) != TYPE_STRING or not expected.has(String(raw_key)):
			return false
	return true

static func _finite_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(float(value))

static func _valid_ascii_id(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	var bytes := value.to_utf8_buffer()
	var first: int = bytes[0]
	if not ((first >= 0x41 and first <= 0x5a) or (first >= 0x61 and first <= 0x7a)):
		return false
	for byte: int in bytes:
		var alpha := (byte >= 0x41 and byte <= 0x5a) or (byte >= 0x61 and byte <= 0x7a)
		var digit := byte >= 0x30 and byte <= 0x39
		if not alpha and not digit and byte not in [0x2e, 0x5f, 0x2d]:
			return false
	return true
