class_name CourseworkStableCommitAutosave
extends RefCounted

## Story 007's synchronous, stateless Feature coordinator for terminal stable
## owner commits. It admits the exact v2 stable-section boundary before
## delegating one detached recovery envelope to the fixed autosave slot.

const DomainResultType = preload("res://src/foundation/domain_result.gd")

## Admits one exact five-section v2 checkpoint then requests the existing
## service's fixed `autosave.1` write. Rejected admission leaves Save untouched;
## service eligibility rejections are returned unchanged.
## Example: `var result: DomainResult = CourseworkStableCommitAutosave.commit_v2(admission, service, authoring_raw, content_raw, progression_raw, settings_raw, tutorial_raw, checksum, generation_id)`.
static func commit_v2(
	candidate_admission: CourseworkCanonicalCandidateAdmission,
	autosave_service: CourseworkSaveService,
	authoring_raw: PackedByteArray,
	content_raw: PackedByteArray,
	progression_raw: PackedByteArray,
	settings_raw: PackedByteArray,
	tutorial_raw: PackedByteArray,
	checksum: String,
	generation_id: String
) -> DomainResult:
	if candidate_admission == null or not is_instance_valid(candidate_admission):
		return DomainResultType.failure(&"candidate_admission_unavailable", "autosave requires a valid v2 candidate admission owner")
	if autosave_service == null or not is_instance_valid(autosave_service):
		return DomainResultType.failure(&"autosave_service_unavailable", "autosave requires the existing save service")
	var admitted: DomainResult = candidate_admission.admit_v2(
		authoring_raw, content_raw, progression_raw, settings_raw, tutorial_raw, checksum)
	if not admitted.is_success():
		return admitted
	var envelope: Dictionary[String, Variant] = {
		"save_version": "coursework.save.v2",
		"authoring_raw": PackedByteArray(authoring_raw),
		"content_raw": PackedByteArray(content_raw),
		"progression_raw": PackedByteArray(progression_raw),
		"settings_raw": PackedByteArray(settings_raw),
		"tutorial_raw": PackedByteArray(tutorial_raw),
		"checksum": checksum,
	}
	return autosave_service.autosave(envelope, generation_id)
