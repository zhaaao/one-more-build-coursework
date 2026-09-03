class_name PreparedRun
extends RefCounted

## Transient immutable preparation value. It has no serialization, persistence,
## public identity, or independent address. Admission consumes the runner's
## one-shot claim for the exact input and semantic result object.

const CanonicalJsonIRType = preload("res://src/foundation/canonical_json_ir.gd")
const RUNNER_SCRIPT_PATH: String = "res://src/core/gvet/coursework_gvet_runner.gd"

var _locked: bool = false:
	set(value):
		if _locked:
			return
		_locked = value
var _graph_snapshot: Dictionary = {}:
	get:
		return _clone_dictionary(_graph_snapshot)
	set(value):
		if not _locked:
			_graph_snapshot = _clone_dictionary(value)
var _day_index: int = -1:
	set(value):
		if not _locked:
			_day_index = value
var _case_roster: Array[Dictionary] = []:
	get:
		return _clone_case_roster(_case_roster)
	set(value):
		if not _locked:
			_case_roster = _clone_case_roster(value)

func _init(
	owner: CourseworkGvetRunner = null,
	input: CourseworkRunInput = null,
	semantic_validation: DomainResult = null
) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	var owner_script: Script = owner.get_script()
	if owner_script == null or owner_script.resource_path.get_slice("::", 0) != RUNNER_SCRIPT_PATH:
		return
	if not owner._claim_prepared_run(input, semantic_validation):
		return
	if not _semantic_receipt_matches(input, semantic_validation):
		return
	_graph_snapshot = input.graph_snapshot()
	_day_index = input.day_index()
	_case_roster = input.case_roster()
	_locked = _state_is_complete()

## Returns true only for a complete value claimed by the active runner call.
## Example: `assert(prepared.is_valid())`.
func is_valid() -> bool:
	return _locked and _state_is_complete()

## Returns a detached copy of the validated graph snapshot.
## Example: `var graph := prepared.graph_snapshot()`.
func graph_snapshot() -> Dictionary:
	return _graph_snapshot

## Returns the admitted coursework day.
## Example: `var day := prepared.day_index()`.
func day_index() -> int:
	return _day_index

## Returns a detached copy of the authored case roster.
## Example: `var cases := prepared.case_roster()`.
func case_roster() -> Array[Dictionary]:
	return _case_roster

## Returns the number of rostered cases in this transient preparation.
## Example: `assert(prepared.case_count() >= 1)`.
func case_count() -> int:
	return _case_roster.size()

func _state_is_complete() -> bool:
	return not _graph_snapshot.is_empty() \
		and _day_index >= CourseworkRunInput.MIN_DAY_INDEX \
		and _day_index <= CourseworkRunInput.MAX_DAY_INDEX \
		and _case_roster.size() >= CourseworkRunInput.MIN_CASE_COUNT \
		and _case_roster.size() <= CourseworkRunInput.MAX_CASE_COUNT

static func _semantic_receipt_matches(
	input: CourseworkRunInput,
	semantic_validation: DomainResult
) -> bool:
	if input == null or not is_instance_valid(input) or not input.is_valid():
		return false
	if semantic_validation == null or not is_instance_valid(semantic_validation) or not semantic_validation.is_success():
		return false
	var raw_receipt: Variant = semantic_validation.value()
	if typeof(raw_receipt) != TYPE_DICTIONARY:
		return false
	var receipt: Dictionary = raw_receipt
	if not _has_exact_keys(receipt, ["validation_pass", "input_identity_sha256", "diagnostics"]):
		return false
	if typeof(receipt["validation_pass"]) != TYPE_BOOL or not receipt["validation_pass"]:
		return false
	if typeof(receipt["input_identity_sha256"]) != TYPE_STRING or receipt["input_identity_sha256"] != input.identity_sha256():
		return false
	return typeof(receipt["diagnostics"]) == TYPE_ARRAY and Array(receipt["diagnostics"]).is_empty()

static func _has_exact_keys(dictionary: Dictionary, fields: Array[String]) -> bool:
	if dictionary.size() != fields.size():
		return false
	for raw_key: Variant in dictionary.keys():
		if typeof(raw_key) != TYPE_STRING or not fields.has(String(raw_key)):
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
