class_name CourseworkCanonicalCandidateAdmission
extends RefCounted

const CanonicalCodec = preload("res://src/foundation/canonical_codec.gd")
const Checkpoint = preload("res://src/core/save_recovery/coursework_five_section_stable_checkpoint.gd")
const ProgressionReplay = preload("res://src/core/save_recovery/coursework_progression_consistency_replay.gd")
const ProjectionOwner = preload("res://src/core/save_recovery/coursework_settings_tutorial_projection_contracts.gd")

## Admits one detached coursework checkpoint candidate only after every required boundary check passes.
##
## Example:
## [code]var result: DomainResult = admission.admit(version, authoring, content, progression, settings, tutorial, checksum)[/code]

const COURSEWORK_CONTENT_VERSION: String = "coursework.v1"
const SECTION_ORDER: Array[String] = ["authoring", "content", "progression", "settings", "tutorial"]
const _AUTHORING_FIELDS: Array[String] = ["task_id", "graph_revision", "graph"]
const _CONTENT_FIELDS: Array[String] = ["content_version", "task_ids", "public_case_ids"]

var _installed_task_ids: Array[String] = []
var _installed_case_ids: Array[String] = []
var _supported_save_version: String = ""
var _initialization_error: StringName = &""
var _initialization_message: String = ""
var _accepted_candidate: Dictionary[String, Variant] = {}

## Captures the Save-owner version and Task-owner projection for admission checks.
## Example: `CourseworkCanonicalCandidateAdmission.new(supported_version, task_catalog.snapshot())`.
func _init(supported_save_version: String, installed_catalog_snapshot: Dictionary[String, Variant]) -> void:
	if supported_save_version.is_empty():
		_initialization_error = &"invalid_supported_version"
		_initialization_message = "supported save version must be a non-empty string"
		return
	_supported_save_version = supported_save_version
	var identity_result: DomainResult = _extract_installed_identity(installed_catalog_snapshot)
	if identity_result.is_success():
		var identity: Dictionary[String, Variant] = _dictionary(identity_result.value())
		_installed_task_ids = _strings(identity["task_ids"])
		_installed_case_ids = _strings(identity["public_case_ids"])
	else:
		_initialization_error = identity_result.error_code()
		_initialization_message = "installed Task projection cannot supply the required five-Task/36-case identity"

## Validates five detached section byte values and atomically replaces this owner's candidate.
## Example: `admission.admit(version, authoring_bytes, content_bytes, progression_bytes, settings_bytes, tutorial_bytes, checksum)`.
func admit(save_version: String, authoring_raw: PackedByteArray, content_raw: PackedByteArray, progression_raw: PackedByteArray, settings_raw: PackedByteArray, tutorial_raw: PackedByteArray, checksum: String) -> DomainResult:
	if not _initialization_error.is_empty():
		return DomainResult.failure(_initialization_error, _initialization_message)
	if save_version != _supported_save_version:
		return DomainResult.failure(&"unsupported_version", "save version is not supported", "$.save_version")
	var raw_sections: Array[PackedByteArray] = [authoring_raw, content_raw, progression_raw, settings_raw, tutorial_raw]
	var decoded_sections: Array[Dictionary] = []
	for index: int in range(SECTION_ORDER.size()):
		var decoded_result: DomainResult = CanonicalCodec.decode_parts(raw_sections[index])
		if not decoded_result.is_success():
			return decoded_result
		var proof: Dictionary[String, Variant] = _dictionary(decoded_result.value())
		if typeof(proof.get("value", null)) != TYPE_DICTIONARY:
			return DomainResult.failure(&"invalid_section_payload", "each snapshot section must be an object", "$.%s" % SECTION_ORDER[index])
		decoded_sections.append(_dictionary(proof["value"]))
	var preimage_result: DomainResult = CanonicalCodec.encode([save_version, decoded_sections[0], decoded_sections[1], decoded_sections[2], decoded_sections[3], decoded_sections[4]])
	if not preimage_result.is_success():
		return preimage_result
	var preimage: PackedByteArray = preimage_result.value()
	if checksum != CanonicalCodec.sha256_hex(preimage):
		return DomainResult.failure(&"integrity_failed", "checksum does not match the canonical snapshot preimage", "$.checksum")
	var authoring: Dictionary[String, Variant] = decoded_sections[0]
	var content: Dictionary[String, Variant] = decoded_sections[1]
	var progression: Dictionary[String, Variant] = decoded_sections[2]
	var authoring_result: DomainResult = _validate_authoring_shape(authoring)
	if not authoring_result.is_success():
		return authoring_result
	var content_result: DomainResult = _validate_content_identity(content)
	if not content_result.is_success():
		return content_result
	var progression_identity_result: DomainResult = _validate_progression_content_identity(progression)
	if not progression_identity_result.is_success():
		return progression_identity_result
	var binding_result: DomainResult = _validate_authoring_binding(authoring, progression)
	if not binding_result.is_success():
		return binding_result
	var root_bytes_result: DomainResult = CanonicalCodec.encode({
		"authoring": authoring,
		"content": content,
		"progression": progression,
		"settings": decoded_sections[3],
		"tutorial": decoded_sections[4],
	})
	if not root_bytes_result.is_success():
		return root_bytes_result
	# Story 001 validates the frozen five-section/projection contracts only on a
	# temporary owner. It cannot mutate a live Settings or Tutorial owner here.
	var projections: ProjectionOwner = ProjectionOwner.new()
	var checkpoint: Checkpoint = Checkpoint.new(projections)
	var checkpoint_result: DomainResult = checkpoint.submit_raw_snapshot(root_bytes_result.value())
	if not checkpoint_result.is_success():
		return checkpoint_result
	# Story 002 replays Career/Workday consistency on an isolated validator.
	var replay: ProgressionReplay = ProgressionReplay.new()
	var replay_result: DomainResult = replay.submit(progression)
	if not replay_result.is_success():
		return replay_result
	var accepted_sections: Dictionary[String, Variant] = _dictionary(checkpoint_result.value())
	accepted_sections["progression"] = replay_result.value()
	_accepted_candidate = {
		"save_version": save_version,
		"checksum": checksum,
		"authoring": accepted_sections["authoring"],
		"content": accepted_sections["content"],
		"progression": accepted_sections["progression"],
		"settings": accepted_sections["settings"],
		"tutorial": accepted_sections["tutorial"],
	}
	return DomainResult.success(accepted_candidate())

## ADR-0011 v2 admission keeps every section detached and validates the whole
## canonical root before any live owner reconstruction begins.
func admit_v2(authoring_raw: PackedByteArray, content_raw: PackedByteArray, progression_raw: PackedByteArray, settings_raw: PackedByteArray, tutorial_raw: PackedByteArray, checksum: String) -> DomainResult:
	if not _initialization_error.is_empty():
		return DomainResult.failure(_initialization_error, _initialization_message)
	var raw_sections: Array[PackedByteArray] = [authoring_raw, content_raw, progression_raw, settings_raw, tutorial_raw]
	var sections: Array[Dictionary] = []
	for index: int in range(SECTION_ORDER.size()):
		var decoded: DomainResult = CanonicalCodec.decode_parts(raw_sections[index])
		if not decoded.is_success() or typeof(_dictionary(decoded.value()).get("value", null)) != TYPE_DICTIONARY:
			return decoded if not decoded.is_success() else DomainResult.failure(&"invalid_section_payload", "each v2 section must be an object", "$.%s" % SECTION_ORDER[index])
		sections.append(_dictionary(_dictionary(decoded.value())["value"]))
	var preimage: DomainResult = CanonicalCodec.encode(["coursework.save.v2", sections[0], sections[1], sections[2], sections[3], sections[4]])
	if not preimage.is_success():
		return preimage
	if checksum != CanonicalCodec.sha256_hex(preimage.value()):
		return DomainResult.failure(&"integrity_failed", "checksum does not match the canonical v2 snapshot preimage", "$.checksum")
	var authoring: Dictionary[String, Variant] = sections[0]
	var content: Dictionary[String, Variant] = sections[1]
	var progression: Dictionary[String, Variant] = sections[2]
	var authoring_result: DomainResult = _validate_authoring_shape(authoring)
	if not authoring_result.is_success(): return authoring_result
	var content_result: DomainResult = _validate_content_identity(content)
	if not content_result.is_success(): return content_result
	if not progression.has("career_projection") or not progression.has("workday_projection") \
			or typeof(progression["career_projection"]) != TYPE_DICTIONARY \
			or not (progression["workday_projection"] == null or typeof(progression["workday_projection"]) == TYPE_DICTIONARY):
		return DomainResult.failure(&"progression_v2_invalid", "v2 progression requires Career and active-only Workday projections", "$.progression")
	if not progression.has("current_task_id") or String(progression["current_task_id"]) != String(authoring["task_id"]):
		return DomainResult.failure(&"authoring_task_mismatch", "authoring task_id must match v2 progression current_task_id", "$.authoring.task_id")
	var v2_replay: ProgressionReplay = ProgressionReplay.new()
	var v2_replay_result: DomainResult = v2_replay.submit_v2(progression)
	if not v2_replay_result.is_success(): return v2_replay_result
	var projections: ProjectionOwner = ProjectionOwner.new()
	var settings_result: DomainResult = projections.submit_pair(sections[3], sections[4])
	if not settings_result.is_success(): return settings_result
	_accepted_candidate = {"save_version": "coursework.save.v2", "checksum": checksum, "authoring": authoring.duplicate(true), "content": content.duplicate(true), "progression": progression.duplicate(true), "settings": sections[3].duplicate(true), "tutorial": sections[4].duplicate(true)}
	return DomainResult.success(accepted_candidate())

## Returns whether an entire candidate has been accepted by this isolated owner.
## Example: `if admission.has_accepted_candidate(): restore(admission.accepted_candidate())`.
func has_accepted_candidate() -> bool:
	return not _accepted_candidate.is_empty()

## Returns a detached accepted candidate, or an empty dictionary before admission.
## Example: `var candidate: Dictionary[String, Variant] = admission.accepted_candidate()`.
func accepted_candidate() -> Dictionary[String, Variant]:
	return _accepted_candidate.duplicate(true)

func _extract_installed_identity(snapshot_value: Dictionary[String, Variant]) -> DomainResult:
	if snapshot_value.size() != 2 or not snapshot_value.has("packages") or not snapshot_value.has("catalog_digest") or typeof(snapshot_value["packages"]) != TYPE_ARRAY:
		return DomainResult.failure(&"invalid_installed_content", "installed Task projection has an invalid shape", "$.packages")
	var packages: Array[Variant] = _variants(snapshot_value["packages"])
	if packages.size() != 5:
		return DomainResult.failure(&"invalid_installed_content", "installed Task projection must contain five packages", "$.packages")
	var task_ids: Array[String] = []
	var case_ids: Array[String] = []
	var seen_tasks: Dictionary[String, bool] = {}
	var seen_cases: Dictionary[String, bool] = {}
	for package_index: int in range(packages.size()):
		if typeof(packages[package_index]) != TYPE_DICTIONARY:
			return DomainResult.failure(&"invalid_installed_content", "installed package must be an object", "$.packages[%d]" % package_index)
		var package: Dictionary[String, Variant] = _dictionary(packages[package_index])
		if not package.has("task_id") or typeof(package["task_id"]) != TYPE_STRING or String(package["task_id"]).is_empty() or seen_tasks.has(String(package["task_id"])):
			return DomainResult.failure(&"invalid_installed_content", "installed task IDs must be unique non-empty strings", "$.packages[%d].task_id" % package_index)
		if not package.has("public_case_ids") or typeof(package["public_case_ids"]) != TYPE_ARRAY:
			return DomainResult.failure(&"invalid_installed_content", "installed packages must declare public case IDs", "$.packages[%d].public_case_ids" % package_index)
		var task_id: String = String(package["task_id"])
		seen_tasks[task_id] = true
		task_ids.append(task_id)
		for case_value: Variant in _variants(package["public_case_ids"]):
			if typeof(case_value) != TYPE_STRING or String(case_value).is_empty() or seen_cases.has(String(case_value)):
				return DomainResult.failure(&"invalid_installed_content", "installed public case IDs must be unique non-empty strings", "$.packages[%d].public_case_ids" % package_index)
			var case_id: String = String(case_value)
			seen_cases[case_id] = true
			case_ids.append(case_id)
	if case_ids.size() != 36:
		return DomainResult.failure(&"invalid_installed_content", "installed Task projection must contain 36 public cases", "$.packages")
	return DomainResult.success({"task_ids": task_ids, "public_case_ids": case_ids})

func _validate_authoring_shape(authoring: Dictionary[String, Variant]) -> DomainResult:
	var shape_result: DomainResult = _validate_exact_fields(authoring, _AUTHORING_FIELDS, "$.authoring")
	if not shape_result.is_success():
		return shape_result
	if typeof(authoring["task_id"]) != TYPE_STRING or String(authoring["task_id"]).is_empty():
		return DomainResult.failure(&"invalid_authoring_task", "authoring task_id must be a non-empty string", "$.authoring.task_id")
	var revision: Variant = authoring["graph_revision"]
	if not ((typeof(revision) == TYPE_INT and int(revision) >= 0) or (typeof(revision) == TYPE_STRING and not String(revision).is_empty())):
		return DomainResult.failure(&"invalid_graph_revision", "authoring graph_revision must be a non-negative integer or non-empty string", "$.authoring.graph_revision")
	if typeof(authoring["graph"]) != TYPE_DICTIONARY:
		return DomainResult.failure(&"invalid_authoring_graph", "authoring graph must be an object", "$.authoring.graph")
	return DomainResult.success(true)

func _validate_content_identity(content: Dictionary[String, Variant]) -> DomainResult:
	var shape_result: DomainResult = _validate_exact_fields(content, _CONTENT_FIELDS, "$.content")
	if not shape_result.is_success():
		return shape_result
	if content["content_version"] != COURSEWORK_CONTENT_VERSION:
		return DomainResult.failure(&"content_mismatch", "content version does not match the installed coursework content", "$.content.content_version")
	if typeof(content["task_ids"]) != TYPE_ARRAY or typeof(content["public_case_ids"]) != TYPE_ARRAY:
		return DomainResult.failure(&"content_mismatch", "content identities must be ordered arrays", "$.content")
	if _strings(content["task_ids"]) != _installed_task_ids or _strings(content["public_case_ids"]) != _installed_case_ids:
		return DomainResult.failure(&"content_mismatch", "content Task or public-case identities do not match the installed projection", "$.content")
	return DomainResult.success(true)

func _validate_progression_content_identity(progression: Dictionary[String, Variant]) -> DomainResult:
	if not progression.has("task_states") or typeof(progression["task_states"]) != TYPE_ARRAY:
		return DomainResult.failure(&"content_mismatch", "progression must retain the installed Task roster", "$.progression.task_states")
	var task_states: Array[Variant] = _variants(progression["task_states"])
	if task_states.size() != _installed_task_ids.size():
		return DomainResult.failure(&"content_mismatch", "progression task roster does not match installed content", "$.progression.task_states")
	for index: int in range(task_states.size()):
		if typeof(task_states[index]) != TYPE_DICTIONARY:
			return DomainResult.failure(&"content_mismatch", "progression task roster does not match installed content", "$.progression.task_states[%d]" % index)
		var state: Dictionary[String, Variant] = _dictionary(task_states[index])
		if String(state.get("task_id", "")) != _installed_task_ids[index]:
			return DomainResult.failure(&"content_mismatch", "progression task roster does not match installed content", "$.progression.task_states[%d].task_id" % index)
	return DomainResult.success(true)

func _validate_authoring_binding(authoring: Dictionary[String, Variant], progression: Dictionary[String, Variant]) -> DomainResult:
	if not progression.has("current_task_id") or typeof(progression["current_task_id"]) != TYPE_STRING:
		return DomainResult.failure(&"invalid_current_task", "progression current_task_id must be a string", "$.progression.current_task_id")
	var authoring_task: String = String(authoring["task_id"])
	if authoring_task != String(progression["current_task_id"]):
		return DomainResult.failure(&"authoring_task_mismatch", "authoring task_id must match progression current_task_id", "$.authoring.task_id")
	if not _installed_task_ids.has(authoring_task):
		return DomainResult.failure(&"content_mismatch", "authoring task_id is absent from installed content", "$.authoring.task_id")
	return DomainResult.success(true)

func _validate_exact_fields(candidate: Dictionary[String, Variant], expected_fields: Array[String], path: String) -> DomainResult:
	if candidate.size() != expected_fields.size():
		return DomainResult.failure(&"invalid_record_shape", "record contains an unknown or missing field", path)
	for field_name: String in expected_fields:
		if not candidate.has(field_name):
			return DomainResult.failure(&"invalid_record_shape", "record contains an unknown or missing field", path)
	return DomainResult.success(true)

func _dictionary(value: Variant) -> Dictionary[String, Variant]:
	var copy: Dictionary[String, Variant] = {}
	if typeof(value) != TYPE_DICTIONARY:
		return copy
	for key: Variant in value.keys():
		if typeof(key) != TYPE_STRING:
			return {}
		copy[String(key)] = value[key]
	return copy.duplicate(true)

func _variants(value: Variant) -> Array[Variant]:
	var copy: Array[Variant] = []
	if typeof(value) != TYPE_ARRAY:
		return copy
	for item: Variant in value:
		copy.append(item)
	return copy.duplicate(true)

func _strings(value: Variant) -> Array[String]:
	var strings: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return strings
	for item: Variant in value:
		if typeof(item) != TYPE_STRING:
			return []
		strings.append(String(item))
	return strings
