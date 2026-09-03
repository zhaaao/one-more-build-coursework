class_name CourseworkRunInput
extends RefCounted

## Closed immutable input for the synchronous coursework GVET runner.
## Source collections are detached before their canonical identity is frozen.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CanonicalCodecType = preload("res://src/foundation/canonical_codec.gd")
const CanonicalJsonIRType = preload("res://src/foundation/canonical_json_ir.gd")

const CONTRACT_VERSION: String = "coursework_run_input_v1"
const MIN_DAY_INDEX: int = 1
const MAX_DAY_INDEX: int = 5
const MIN_CASE_COUNT: int = 1
const MAX_CASE_COUNT: int = 12

var _locked: bool = false:
	set(value):
		if _locked:
			return
		_locked = value
var _task_id: String = "":
	set(value):
		if not _locked:
			_task_id = value
var _day_index: int = -1:
	set(value):
		if not _locked:
			_day_index = value
var _request_id: String = "":
	set(value):
		if not _locked:
			_request_id = value
var _graph_revision: int = -1:
	set(value):
		if not _locked:
			_graph_revision = value
var _graph_snapshot: Dictionary = {}:
	get:
		return _clone_dictionary(_graph_snapshot)
	set(value):
		if not _locked:
			_graph_snapshot = _clone_dictionary(value)
var _case_roster: Array[Dictionary] = []:
	get:
		return _clone_case_roster(_case_roster)
	set(value):
		if not _locked:
			_case_roster = _clone_case_roster(value)
var _admitted_content_digest: String = "":
	set(value):
		if not _locked:
			_admitted_content_digest = value
var _identity_projection: Dictionary = {}:
	get:
		return _clone_dictionary(_identity_projection)
	set(value):
		if not _locked:
			_identity_projection = _clone_dictionary(value)
var _identity_canonical_bytes: PackedByteArray = PackedByteArray():
	get:
		return PackedByteArray(_identity_canonical_bytes)
	set(value):
		if not _locked:
			_identity_canonical_bytes = PackedByteArray(value)
var _identity_sha256: String = "":
	set(value):
		if not _locked:
			_identity_sha256 = value

## Validates, detaches, and freezes one coursework Run input.
## Example: `var result := CourseworkRunInput.create("task.1", 1,
## "request.1", 0, graph, cases)`.
static func create(
	task_id: Variant,
	day_index: Variant,
	request_id: Variant,
	graph_revision: Variant,
	graph_snapshot: Variant,
	case_roster: Variant,
	admitted_content: Variant = null
) -> DomainResult:
	var scalar_result: DomainResult = _validate_scalar_fields(task_id, day_index, request_id, graph_revision)
	if not scalar_result.is_success():
		return scalar_result
	var graph_result: DomainResult = _capture_graph(graph_snapshot)
	if not graph_result.is_success():
		return graph_result
	var roster_result: DomainResult = _capture_roster(case_roster)
	if not roster_result.is_success():
		return roster_result
	var roster: Array[Dictionary] = roster_result.value()
	var digest_result: DomainResult = _capture_admitted_digest(roster, admitted_content)
	if not digest_result.is_success():
		return digest_result
	var identity_result: DomainResult = _build_identity_packet(
		String(task_id), int(day_index), String(request_id), int(graph_revision),
		graph_result.value(), roster, String(digest_result.value()))
	if not identity_result.is_success():
		return identity_result
	var record: Dictionary = _build_record(
		String(task_id), int(day_index), String(request_id), int(graph_revision),
		graph_result.value(), roster, String(digest_result.value()), identity_result.value())
	var input: CourseworkRunInput = CourseworkRunInput.new(record)
	if not input.is_valid():
		return _invalid("coursework input construction did not commit")
	return DomainResultType.success(input)

func _init(record: Dictionary = {}) -> void:
	if not _record_shape_is_valid(record):
		return
	_task_id = record["task_id"]
	_day_index = record["day_index"]
	_request_id = record["request_id"]
	_graph_revision = record["graph_revision"]
	_graph_snapshot = record["graph_snapshot"]
	_case_roster = record["case_roster"]
	_admitted_content_digest = record["admitted_content_digest"]
	_identity_projection = record["identity_projection"]
	_identity_canonical_bytes = record["identity_canonical_bytes"]
	_identity_sha256 = record["identity_sha256"]
	_locked = _state_matches_contract()

## Returns true only while every retained value still matches the frozen identity.
## Example: `if input.is_valid(): runner._prepare_run(input)`.
func is_valid() -> bool:
	return _locked and _state_matches_contract()

## Returns the stable Task identity captured for this Run.
## Example: `var task := input.task_id()`.
func task_id() -> String:
	return _task_id

## Returns the admitted coursework day in the inclusive range 1..5.
## Example: `var day := input.day_index()`.
func day_index() -> int:
	return _day_index

## Returns the stable request identity captured for this Run.
## Example: `var request := input.request_id()`.
func request_id() -> String:
	return _request_id

## Returns the non-negative captured graph revision.
## Example: `var revision := input.graph_revision()`.
func graph_revision() -> int:
	return _graph_revision

## Returns a detached copy of the exact admitted graph snapshot.
## Example: `var graph_copy := input.graph_snapshot()`.
func graph_snapshot() -> Dictionary:
	return _graph_snapshot

## Returns a detached copy of the authored case roster in roster order.
## Example: `var cases := input.case_roster()`.
func case_roster() -> Array[Dictionary]:
	return _case_roster

## Returns the lowercase SHA-256 of the admitted case content.
## Example: `var digest := input.admitted_content_digest()`.
func admitted_content_digest() -> String:
	return _admitted_content_digest

## Returns a detached copy of the complete stable identity projection.
## Example: `var projection := input.identity()`.
func identity() -> Dictionary:
	return _identity_projection

## Returns a detached copy of the canonical identity bytes.
## Example: `var bytes := input.identity_canonical_bytes()`.
func identity_canonical_bytes() -> PackedByteArray:
	return _identity_canonical_bytes

## Returns the lowercase SHA-256 of the canonical identity bytes.
## Example: `var digest := input.identity_sha256()`.
func identity_sha256() -> String:
	return _identity_sha256

static func _validate_scalar_fields(
	task_id: Variant, day_index: Variant, request_id: Variant, graph_revision: Variant
) -> DomainResult:
	if not _is_valid_stable_id(task_id):
		return _invalid("task_id must be a stable ASCII identifier")
	if typeof(day_index) != TYPE_INT or int(day_index) < MIN_DAY_INDEX or int(day_index) > MAX_DAY_INDEX:
		return _invalid("day_index must be an integer between 1 and 5")
	if not _is_valid_stable_id(request_id):
		return _invalid("request_id must be a stable ASCII identifier")
	if typeof(graph_revision) != TYPE_INT or int(graph_revision) < 0:
		return _invalid("graph_revision must be a non-negative integer")
	return DomainResultType.success(true)

static func _capture_graph(value: Variant) -> DomainResult:
	var validation: DomainResult = _validate_graph_snapshot(value)
	if not validation.is_success():
		return validation
	var copied: Variant = CanonicalJsonIRType.clone(value)
	if typeof(copied) != TYPE_DICTIONARY:
		return _invalid("graph snapshot could not be detached")
	return DomainResultType.success(copied)

static func _capture_roster(value: Variant) -> DomainResult:
	var validation: DomainResult = _validate_case_roster(value)
	if not validation.is_success():
		return validation
	var copied: Array[Dictionary] = _clone_case_roster(value)
	if copied.size() != Array(value).size():
		return _invalid("case roster could not be detached")
	return DomainResultType.success(copied)

static func _capture_admitted_digest(roster: Array[Dictionary], admitted_content: Variant) -> DomainResult:
	var admitted: Variant = roster if admitted_content == null else admitted_content
	if typeof(admitted) != TYPE_ARRAY or not CanonicalJsonIRType.validate_pure_json(admitted).is_success():
		return _invalid("admitted case content must be a pure array")
	var admitted_result: DomainResult = CanonicalCodecType.encode(admitted)
	var roster_result: DomainResult = CanonicalCodecType.encode(roster)
	if not admitted_result.is_success() or not roster_result.is_success():
		return _invalid("admitted case content is not canonically encodable")
	var admitted_bytes: PackedByteArray = admitted_result.value()
	if admitted_bytes != PackedByteArray(roster_result.value()):
		return _invalid("admitted case content must match the detached case roster")
	var digest: String = CanonicalCodecType.sha256_hex(admitted_bytes)
	if not _is_lower_sha256(digest):
		return _invalid("admitted case content did not produce a SHA-256 digest")
	return DomainResultType.success(digest)

static func _build_identity_packet(
	task_id: String, day_index: int, request_id: String, graph_revision: int,
	graph_snapshot: Dictionary, case_roster: Array[Dictionary], admitted_digest: String
) -> DomainResult:
	var projection: Dictionary = {
		"contract_version": CONTRACT_VERSION,
		"task_id": task_id,
		"day_index": day_index,
		"request_id": request_id,
		"graph_revision": graph_revision,
		"graph_snapshot": CanonicalJsonIRType.clone(graph_snapshot),
		"case_roster": CanonicalJsonIRType.clone(case_roster),
		"admitted_content_digest": admitted_digest,
	}
	var encoded: DomainResult = CanonicalCodecType.encode(projection)
	if not encoded.is_success():
		return _invalid("coursework input identity is not canonically encodable")
	var bytes: PackedByteArray = encoded.value()
	var digest: String = CanonicalCodecType.sha256_hex(bytes)
	if not _is_lower_sha256(digest):
		return _invalid("coursework input identity did not produce a SHA-256 digest")
	return DomainResultType.success({"projection": projection, "bytes": bytes, "sha256": digest})

static func _build_record(
	task_id: String, day_index: int, request_id: String, graph_revision: int,
	graph_snapshot: Dictionary, case_roster: Array[Dictionary], admitted_digest: String,
	identity_packet: Dictionary
) -> Dictionary:
	return {
		"task_id": task_id,
		"day_index": day_index,
		"request_id": request_id,
		"graph_revision": graph_revision,
		"graph_snapshot": graph_snapshot,
		"case_roster": case_roster,
		"admitted_content_digest": admitted_digest,
		"identity_projection": identity_packet["projection"],
		"identity_canonical_bytes": identity_packet["bytes"],
		"identity_sha256": identity_packet["sha256"],
	}

static func _record_shape_is_valid(record: Dictionary) -> bool:
	var fields: Array[String] = [
		"task_id", "day_index", "request_id", "graph_revision", "graph_snapshot",
		"case_roster", "admitted_content_digest", "identity_projection",
		"identity_canonical_bytes", "identity_sha256",
	]
	if not _has_exact_keys(record, fields):
		return false
	return typeof(record["task_id"]) == TYPE_STRING \
		and typeof(record["day_index"]) == TYPE_INT \
		and typeof(record["request_id"]) == TYPE_STRING \
		and typeof(record["graph_revision"]) == TYPE_INT \
		and typeof(record["graph_snapshot"]) == TYPE_DICTIONARY \
		and typeof(record["case_roster"]) == TYPE_ARRAY \
		and typeof(record["admitted_content_digest"]) == TYPE_STRING \
		and typeof(record["identity_projection"]) == TYPE_DICTIONARY \
		and typeof(record["identity_canonical_bytes"]) == TYPE_PACKED_BYTE_ARRAY \
		and typeof(record["identity_sha256"]) == TYPE_STRING

func _state_matches_contract() -> bool:
	if not _validate_scalar_fields(_task_id, _day_index, _request_id, _graph_revision).is_success():
		return false
	if not _validate_graph_snapshot(_graph_snapshot).is_success() or not _validate_case_roster(_case_roster).is_success():
		return false
	var roster_encoded: DomainResult = CanonicalCodecType.encode(_case_roster)
	if not roster_encoded.is_success():
		return false
	if CanonicalCodecType.sha256_hex(roster_encoded.value()) != _admitted_content_digest:
		return false
	var packet_result: DomainResult = _build_identity_packet(
		_task_id, _day_index, _request_id, _graph_revision,
		_graph_snapshot, _case_roster, _admitted_content_digest)
	if not packet_result.is_success():
		return false
	var packet: Dictionary = packet_result.value()
	return CanonicalJsonIRType.equal(packet["projection"], _identity_projection) \
		and PackedByteArray(packet["bytes"]) == _identity_canonical_bytes \
		and String(packet["sha256"]) == _identity_sha256

static func _validate_graph_snapshot(value: Variant) -> DomainResult:
	if typeof(value) != TYPE_DICTIONARY:
		return _invalid("graph snapshot must be a Dictionary")
	if not CanonicalJsonIRType.validate_pure_json(value).is_success():
		return _invalid("graph snapshot contains a non-canonical value")
	var graph: Dictionary = value
	if not _has_exact_keys(graph, ["graph_codec_version", "fixture_id", "nodes", "connections"]):
		return _invalid("authoring_graph_v1 fields are not exact")
	if graph["graph_codec_version"] != "authoring_graph_v1" or not _is_valid_stable_id(graph["fixture_id"]):
		return _invalid("graph version or fixture identity is invalid")
	if typeof(graph["nodes"]) != TYPE_ARRAY or typeof(graph["connections"]) != TYPE_ARRAY:
		return _invalid("graph nodes and connections must be arrays")
	var nodes_result: DomainResult = _validate_graph_nodes(graph["nodes"])
	if not nodes_result.is_success():
		return nodes_result
	return _validate_graph_connections(graph["connections"], nodes_result.value())

static func _validate_graph_nodes(nodes: Array) -> DomainResult:
	var node_ids: Dictionary = {}
	var previous_node_id: String = ""
	for raw_node: Variant in nodes:
		var node_result: DomainResult = _validate_graph_node(raw_node)
		if not node_result.is_success():
			return node_result
		var node_id: String = node_result.value()
		if node_ids.has(node_id):
			return _invalid("graph node identities must be unique")
		if not previous_node_id.is_empty() and not _stable_id_is_after(node_id, previous_node_id):
			return _invalid("graph nodes must use canonical stable-ID order")
		node_ids[node_id] = true
		previous_node_id = node_id
	return DomainResultType.success(node_ids)

static func _validate_graph_node(value: Variant) -> DomainResult:
	if typeof(value) != TYPE_DICTIONARY:
		return _invalid("graph nodes must be dictionaries")
	var node: Dictionary = value
	var fields: Array[String] = ["node_id", "variant_id", "anchor_x", "anchor_y", "parameter_values"]
	if not _has_exact_keys(node, fields):
		return _invalid("graph node fields are not exact")
	if not _is_valid_stable_id(node["node_id"]) or not _is_valid_stable_id(node["variant_id"]):
		return _invalid("graph node and variant identities must be stable ASCII IDs")
	if typeof(node["anchor_x"]) != TYPE_INT or typeof(node["anchor_y"]) != TYPE_INT:
		return _invalid("graph node anchors must be integers")
	if typeof(node["parameter_values"]) != TYPE_ARRAY:
		return _invalid("graph node parameter_values must be an array")
	var parameters_result: DomainResult = _validate_parameter_values(node["parameter_values"])
	if not parameters_result.is_success():
		return parameters_result
	return DomainResultType.success(String(node["node_id"]))

static func _validate_parameter_values(values: Array) -> DomainResult:
	var parameter_ids: Dictionary = {}
	var previous_parameter_id: String = ""
	for raw_parameter: Variant in values:
		if typeof(raw_parameter) != TYPE_DICTIONARY:
			return _invalid("parameter values must be dictionaries")
		var parameter: Dictionary = raw_parameter
		if not _has_exact_keys(parameter, ["parameter_id", "value"]):
			return _invalid("parameter value fields are not exact")
		if not _is_valid_stable_id(parameter["parameter_id"]):
			return _invalid("parameter identity must be a stable ASCII ID")
		var parameter_id: String = parameter["parameter_id"]
		if parameter_ids.has(parameter_id):
			return _invalid("parameter identities must be unique within a node")
		if not previous_parameter_id.is_empty() \
			and not _stable_id_is_after(parameter_id, previous_parameter_id):
			return _invalid("parameter values must use canonical stable-ID order")
		parameter_ids[parameter_id] = true
		previous_parameter_id = parameter_id
	return DomainResultType.success(true)

static func _validate_graph_connections(connections: Array, node_ids: Dictionary) -> DomainResult:
	var connection_ids: Dictionary = {}
	var previous_connection_id: String = ""
	for raw_connection: Variant in connections:
		var result: DomainResult = _validate_graph_connection(raw_connection, node_ids)
		if not result.is_success():
			return result
		var connection_id: String = result.value()
		if connection_ids.has(connection_id):
			return _invalid("graph connection identities must be unique")
		if not previous_connection_id.is_empty() \
			and not _stable_id_is_after(connection_id, previous_connection_id):
			return _invalid("graph connections must use canonical stable-ID order")
		connection_ids[connection_id] = true
		previous_connection_id = connection_id
	return DomainResultType.success(true)

static func _validate_graph_connection(value: Variant, node_ids: Dictionary) -> DomainResult:
	if typeof(value) != TYPE_DICTIONARY:
		return _invalid("graph connections must be dictionaries")
	var connection: Dictionary = value
	var fields: Array[String] = [
		"connection_id", "source_node_id", "source_port_id",
		"target_node_id", "target_port_id",
	]
	if not _has_exact_keys(connection, fields):
		return _invalid("graph connection fields are not exact")
	for field: String in fields:
		if not _is_valid_stable_id(connection[field]):
			return _invalid("graph connection identities must be stable ASCII IDs")
	if not node_ids.has(connection["source_node_id"]) or not node_ids.has(connection["target_node_id"]):
		return _invalid("graph connection endpoint references an unknown node")
	return DomainResultType.success(String(connection["connection_id"]))

static func _validate_case_roster(value: Variant) -> DomainResult:
	if typeof(value) != TYPE_ARRAY or not CanonicalJsonIRType.validate_pure_json(value).is_success():
		return _invalid("case roster must be a pure Array")
	var roster: Array = value
	if roster.size() < MIN_CASE_COUNT or roster.size() > MAX_CASE_COUNT:
		return _invalid("case roster must contain between 1 and 12 cases")
	var case_ids: Dictionary = {}
	for raw_case: Variant in roster:
		var case_result: DomainResult = _validate_case(raw_case)
		if not case_result.is_success():
			return case_result
		var case_id: String = case_result.value()
		if case_ids.has(case_id):
			return _invalid("case identities must be unique")
		case_ids[case_id] = true
	return DomainResultType.success(true)

static func _validate_case(value: Variant) -> DomainResult:
	if typeof(value) != TYPE_DICTIONARY:
		return _invalid("case roster entries must be dictionaries")
	var case_definition: Dictionary = value
	var case_id_result: DomainResult = _stable_alias_id(case_definition, ["case_id", "test_case_id"])
	if not case_id_result.is_success():
		return _invalid("case identity must be one stable ASCII ID")
	var content_result: DomainResult = _validate_case_content(case_definition)
	if not content_result.is_success():
		return content_result
	return case_id_result

static func _validate_case_content(case_definition: Dictionary) -> DomainResult:
	var content: Variant = case_definition.get("content", case_definition.get("case_content", null))
	if content == null:
		content = case_definition
	if typeof(content) != TYPE_DICTIONARY:
		return _invalid("case content must be a Dictionary")
	var content_dictionary: Dictionary = content
	if not content_dictionary.has("initial_state") or not content_dictionary.has("assertions"):
		return _invalid("case content requires initial_state and assertions")
	if typeof(content_dictionary["initial_state"]) != TYPE_DICTIONARY:
		return _invalid("case initial_state must be a Dictionary")
	return _validate_assertions(content_dictionary["assertions"])

static func _validate_assertions(value: Variant) -> DomainResult:
	if typeof(value) != TYPE_ARRAY or Array(value).is_empty():
		return _invalid("case assertions must contain at least one item")
	var assertion_ids: Dictionary = {}
	for raw_assertion: Variant in Array(value):
		if typeof(raw_assertion) != TYPE_DICTIONARY or Dictionary(raw_assertion).is_empty():
			return _invalid("assertions must be non-empty dictionaries")
		var id_result: DomainResult = _stable_alias_id(raw_assertion, ["id", "assertion_id"])
		if not id_result.is_success() or assertion_ids.has(id_result.value()):
			return _invalid("assertion identities must be unique stable ASCII IDs")
		assertion_ids[id_result.value()] = true
	return DomainResultType.success(true)

static func _stable_alias_id(dictionary: Dictionary, aliases: Array[String]) -> DomainResult:
	var found: String = ""
	for alias: String in aliases:
		if not dictionary.has(alias):
			continue
		if not found.is_empty() or not _is_valid_stable_id(dictionary[alias]):
			return _invalid("identity alias is missing or ambiguous")
		found = String(dictionary[alias])
	if found.is_empty():
		return _invalid("stable identity is missing")
	return DomainResultType.success(found)

static func _has_exact_keys(dictionary: Dictionary, fields: Array[String]) -> bool:
	if dictionary.size() != fields.size():
		return false
	for raw_key: Variant in dictionary.keys():
		if typeof(raw_key) != TYPE_STRING or not fields.has(String(raw_key)):
			return false
	return true

static func _is_valid_stable_id(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var bytes: PackedByteArray = String(value).to_utf8_buffer()
	if bytes.is_empty() or bytes.size() > 64 or not _is_ascii_letter(bytes[0]):
		return false
	for index: int in range(1, bytes.size()):
		var byte: int = bytes[index]
		if not _is_ascii_letter(byte) and not _is_ascii_digit(byte) and not [45, 46, 95].has(byte):
			return false
	return true

static func _is_ascii_letter(byte: int) -> bool:
	return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)

static func _is_ascii_digit(byte: int) -> bool:
	return byte >= 48 and byte <= 57

static func _stable_id_is_after(candidate: String, previous: String) -> bool:
	var candidate_bytes: PackedByteArray = candidate.to_utf8_buffer()
	var previous_bytes: PackedByteArray = previous.to_utf8_buffer()
	var shared_size: int = mini(candidate_bytes.size(), previous_bytes.size())
	for index: int in range(shared_size):
		if candidate_bytes[index] == previous_bytes[index]:
			continue
		return candidate_bytes[index] > previous_bytes[index]
	return candidate_bytes.size() > previous_bytes.size()

static func _is_lower_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index: int in range(value.length()):
		var code: int = value.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true

static func _clone_dictionary(value: Variant) -> Dictionary:
	var copied: Variant = CanonicalJsonIRType.clone(value)
	return copied if typeof(copied) == TYPE_DICTIONARY else {}

static func _clone_case_roster(value: Variant) -> Array[Dictionary]:
	var copied: Variant = CanonicalJsonIRType.clone(value)
	var result: Array[Dictionary] = []
	if typeof(copied) != TYPE_ARRAY:
		return result
	for raw_case: Variant in copied:
		if typeof(raw_case) != TYPE_DICTIONARY:
			return []
		result.append(raw_case)
	return result

static func _invalid(message: String) -> DomainResult:
	return DomainResultType.failure(&"run_input_error", message)
