class_name CourseworkSettingsTutorialProjectionContracts
extends RefCounted

## Foundation owner for the Settings and Tutorial stable Save projections.
##
## Example:
## `var result: DomainResult = owner.submit_settings(owner.default_settings_candidate())`

const _SETTINGS_FIELDS: Array[String] = ["ui_scale", "reduced_motion", "base_bindings"]
const _TUTORIAL_FIELDS: Array[String] = ["onboarding_state", "next_step_index", "revealed_prompt_ids"]
const _BINDING_FIELDS: Array[String] = ["action", "required_binding"]
const _BASE_BINDINGS: Array[Dictionary] = [
	{"action": "Next focus", "required_binding": "Tab"},
	{"action": "Previous focus", "required_binding": "Shift+Tab"},
	{"action": "Activate focused control", "required_binding": "Enter or Space"},
	{"action": "Cancel/close/back", "required_binding": "Escape"},
	{"action": "Open Help", "required_binding": "F1 plus a visible Help control"},
]
const _PROMPT_ROSTER: Array[StringName] = [
	&"prompt.d1.01.read_trace",
	&"prompt.d1.02.pick_before_drop",
	&"prompt.d2.01.query_value",
	&"prompt.d2.02.swap_arms",
	&"prompt.d3.01_continue",
	&"prompt.d4.01_boundary",
]
const _PROMPT_DAY_BY_ID: Dictionary = {
	&"prompt.d1.01.read_trace": 1,
	&"prompt.d1.02.pick_before_drop": 1,
	&"prompt.d2.01.query_value": 2,
	&"prompt.d2.02.swap_arms": 2,
	&"prompt.d3.01_continue": 3,
	&"prompt.d4.01_boundary": 4,
}
const _DAILY_MAXIMA: Array[int] = [2, 2, 1, 1, 0]
const _ONBOARDING_STATES: Array[StringName] = [&"not_started", &"active", &"completed", &"skipped"]

var _settings: SettingsStableProjection
var _tutorial: TutorialStableProjection

## Creates one owner with the deterministic accepted defaults.
## Example: `var owner: CourseworkSettingsTutorialProjectionContracts = CourseworkSettingsTutorialProjectionContracts.new()`.
func _init() -> void:
	_settings = SettingsStableProjection.new(1.0, false, _copy_bindings(_BASE_BINDINGS))
	_tutorial = TutorialStableProjection.new(&"not_started", 1, [])

## Returns a mutable candidate matching the deterministic Settings default.
## Example: `var candidate: Dictionary = owner.default_settings_candidate()`.
func default_settings_candidate() -> Dictionary:
	return _settings.to_dictionary()

## Returns a mutable candidate matching the deterministic Tutorial default.
## Example: `var candidate: Dictionary = owner.default_tutorial_candidate()`.
func default_tutorial_candidate() -> Dictionary:
	return _tutorial.to_dictionary()

## Validates and atomically replaces only the Settings projection.
## Example: `var result: DomainResult = owner.submit_settings(candidate)`.
func submit_settings(candidate: Dictionary) -> DomainResult:
	var validated: DomainResult = _validate_settings(candidate)
	if not validated.is_success():
		return validated
	var projection: SettingsStableProjection = validated.value() as SettingsStableProjection
	_settings = projection
	return DomainResult.success(_settings.to_dictionary())

## Validates and atomically replaces only the Tutorial projection.
## Example: `var result: DomainResult = owner.submit_tutorial(candidate)`.
func submit_tutorial(candidate: Dictionary) -> DomainResult:
	var validated: DomainResult = _validate_tutorial(candidate)
	if not validated.is_success():
		return validated
	var projection: TutorialStableProjection = validated.value() as TutorialStableProjection
	_tutorial = projection
	return DomainResult.success(_tutorial.to_dictionary())

## Validates both projections before atomically replacing either one.
## Example: `var result: DomainResult = owner.submit_pair(settings_candidate, tutorial_candidate)`.
func submit_pair(settings_candidate: Dictionary, tutorial_candidate: Dictionary) -> DomainResult:
	var settings_result: DomainResult = _validate_settings(settings_candidate)
	if not settings_result.is_success():
		return settings_result
	var tutorial_result: DomainResult = _validate_tutorial(tutorial_candidate)
	if not tutorial_result.is_success():
		return tutorial_result
	var new_settings: SettingsStableProjection = settings_result.value() as SettingsStableProjection
	var new_tutorial: TutorialStableProjection = tutorial_result.value() as TutorialStableProjection
	_settings = new_settings
	_tutorial = new_tutorial
	return DomainResult.success({"settings": _settings.to_dictionary(), "tutorial": _tutorial.to_dictionary()})

## Returns a detached Settings projection directly consumable by Save.
## Example: `var settings: Dictionary = owner.settings_projection()`.
func settings_projection() -> Dictionary:
	return _settings.to_dictionary()

## Returns a detached Tutorial projection directly consumable by Save.
## Example: `var tutorial: Dictionary = owner.tutorial_projection()`.
func tutorial_projection() -> Dictionary:
	return _tutorial.to_dictionary()

func _validate_settings(candidate: Dictionary) -> DomainResult:
	var shape_error: DomainResult = _validate_exact_fields(candidate, _SETTINGS_FIELDS, "$.settings")
	if not shape_error.is_success():
		return shape_error
	var scale: Variant = candidate["ui_scale"]
	if not (scale is float or scale is int) or not _is_legal_scale(float(scale)):
		return DomainResult.failure(&"invalid_ui_scale", "ui_scale must be one approved scale", "$.settings.ui_scale")
	var reduced_motion: Variant = candidate["reduced_motion"]
	if typeof(reduced_motion) != TYPE_BOOL:
		return DomainResult.failure(&"invalid_reduced_motion", "reduced_motion must be Boolean", "$.settings.reduced_motion")
	var bindings_value: Variant = candidate["base_bindings"]
	if typeof(bindings_value) != TYPE_ARRAY:
		return DomainResult.failure(&"invalid_base_bindings", "base_bindings must be an Array", "$.settings.base_bindings")
	var bindings: Array = bindings_value
	if bindings.size() != _BASE_BINDINGS.size():
		return DomainResult.failure(&"invalid_base_bindings", "base_bindings has the wrong row count", "$.settings.base_bindings")
	for index: int in range(_BASE_BINDINGS.size()):
		var row_value: Variant = bindings[index]
		if typeof(row_value) != TYPE_DICTIONARY:
			return DomainResult.failure(&"invalid_base_binding", "each base binding must be a Dictionary", "$.settings.base_bindings[%d]" % index)
		var row: Dictionary = row_value
		var row_shape_error: DomainResult = _validate_exact_fields(row, _BINDING_FIELDS, "$.settings.base_bindings[%d]" % index)
		if not row_shape_error.is_success():
			return row_shape_error
		if row != _BASE_BINDINGS[index]:
			return DomainResult.failure(&"invalid_base_binding", "base binding does not match the required ordered table", "$.settings.base_bindings[%d]" % index)
	return DomainResult.success(SettingsStableProjection.new(float(scale), bool(reduced_motion), _copy_bindings(bindings)))

func _validate_tutorial(candidate: Dictionary) -> DomainResult:
	var shape_error: DomainResult = _validate_exact_fields(candidate, _TUTORIAL_FIELDS, "$.tutorial")
	if not shape_error.is_success():
		return shape_error
	var state_value: Variant = candidate["onboarding_state"]
	if not (state_value is String or state_value is StringName) or not _ONBOARDING_STATES.has(StringName(state_value)):
		return DomainResult.failure(&"invalid_onboarding_state", "onboarding_state is not legal", "$.tutorial.onboarding_state")
	var index_value: Variant = candidate["next_step_index"]
	if typeof(index_value) != TYPE_INT or int(index_value) < 1 or int(index_value) > 8:
		return DomainResult.failure(&"invalid_next_step_index", "next_step_index must be an integer in 1..8", "$.tutorial.next_step_index")
	var prompts_value: Variant = candidate["revealed_prompt_ids"]
	if typeof(prompts_value) != TYPE_ARRAY:
		return DomainResult.failure(&"invalid_revealed_prompt_ids", "revealed_prompt_ids must be an Array", "$.tutorial.revealed_prompt_ids")
	var prompt_values: Array = prompts_value
	var accepted_ids: Array[StringName] = []
	var previous_roster_index: int = -1
	var day_counts: Array[int] = [0, 0, 0, 0, 0]
	for prompt_index: int in range(prompt_values.size()):
		var prompt_value: Variant = prompt_values[prompt_index]
		if not (prompt_value is String or prompt_value is StringName) or not _PROMPT_DAY_BY_ID.has(StringName(prompt_value)):
			return DomainResult.failure(&"unknown_prompt_id", "revealed_prompt_ids contains an unknown prompt", "$.tutorial.revealed_prompt_ids[%d]" % prompt_index)
		var prompt_id: StringName = StringName(prompt_value)
		var day: int = int(_PROMPT_DAY_BY_ID[prompt_id])
		day_counts[day - 1] += 1
		if day_counts[day - 1] > _DAILY_MAXIMA[day - 1]:
			return DomainResult.failure(&"prompt_day_excess", "revealed_prompt_ids exceeds its daily maximum", "$.tutorial.revealed_prompt_ids[%d]" % prompt_index)
		var roster_index: int = _PROMPT_ROSTER.find(prompt_id)
		if roster_index <= previous_roster_index:
			return DomainResult.failure(&"invalid_prompt_order", "revealed_prompt_ids must be duplicate-free roster order", "$.tutorial.revealed_prompt_ids[%d]" % prompt_index)
		previous_roster_index = roster_index
		accepted_ids.append(prompt_id)
	return DomainResult.success(TutorialStableProjection.new(StringName(state_value), int(index_value), accepted_ids))

func _validate_exact_fields(candidate: Dictionary, required_fields: Array[String], path: String) -> DomainResult:
	var keys: Array = candidate.keys()
	if keys.size() != required_fields.size():
		return DomainResult.failure(&"invalid_record_shape", "record has an unexpected field count", path)
	for key: Variant in keys:
		if not (key is String or key is StringName):
			return DomainResult.failure(&"invalid_record_shape", "record field names must be strings", path)
	for required_field: String in required_fields:
		if not candidate.has(required_field):
			return DomainResult.failure(&"invalid_record_shape", "record fields must match the required roster", path)
	return DomainResult.success(true)

func _is_legal_scale(scale: float) -> bool:
	return scale == 1.0 or scale == 1.25 or scale == 1.5 or scale == 2.0

func _copy_bindings(bindings: Array) -> Array[Dictionary]:
	var copied: Array[Dictionary] = []
	for binding_value: Variant in bindings:
		var binding: Dictionary = binding_value
		copied.append(binding.duplicate(true))
	return copied

class SettingsStableProjection extends RefCounted:
	var _ui_scale: float
	var _reduced_motion: bool
	var _base_bindings: Array[Dictionary]

	func _init(ui_scale: float, reduced_motion: bool, base_bindings: Array[Dictionary]) -> void:
		_ui_scale = ui_scale
		_reduced_motion = reduced_motion
		_base_bindings = _copy_bindings(base_bindings)

	func to_dictionary() -> Dictionary:
		return {"ui_scale": _ui_scale, "reduced_motion": _reduced_motion, "base_bindings": _copy_bindings(_base_bindings)}

	func _copy_bindings(bindings: Array[Dictionary]) -> Array[Dictionary]:
		var copied: Array[Dictionary] = []
		for binding: Dictionary in bindings:
			copied.append(binding.duplicate(true))
		return copied

class TutorialStableProjection extends RefCounted:
	var _onboarding_state: StringName
	var _next_step_index: int
	var _revealed_prompt_ids: Array[StringName]

	func _init(onboarding_state: StringName, next_step_index: int, revealed_prompt_ids: Array[StringName]) -> void:
		_onboarding_state = onboarding_state
		_next_step_index = next_step_index
		_revealed_prompt_ids = revealed_prompt_ids.duplicate()

	func to_dictionary() -> Dictionary:
		return {"onboarding_state": _onboarding_state, "next_step_index": _next_step_index, "revealed_prompt_ids": _revealed_prompt_ids.duplicate()}
