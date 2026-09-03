class_name CourseworkWholeGenerationRecovery
extends RefCounted

## Coordinates isolated v2 generation reconstruction and atomic owner publication.
##
## The root deliberately exposes no member-owner setters. A successful restore
## replaces this one record only after its preparer has completed every fallible
## operation.

const SAVE_VERSION: String = "coursework.save.v2"

var _live_owner_set: CourseworkLiveOwnerSet = null
var _candidate_admission: CourseworkCanonicalCandidateAdmission = null
var _task_catalog: CourseworkTaskCatalog = null
var _run_port: AuthoringRunPort = null
var _report_state: AuthoringReportState = null
var _current_live_revision: int = 1
var _workday_policy: CourseworkWorkdayPolicy = null
var _issuer_provider: CourseworkAcceptedOutcomeIssuerProvider = null
var _restoring: bool = false

class PreparedRestore:
	extends RefCounted
	var owner_set: CourseworkLiveOwnerSet = null
	var result_code: StringName = &""

	func _init(next_owner_set: CourseworkLiveOwnerSet, next_result_code: StringName) -> void:
		owner_set = next_owner_set
		result_code = next_result_code

func _init(
	initial_owner_set: CourseworkLiveOwnerSet = null,
	candidate_admission: CourseworkCanonicalCandidateAdmission = null,
	task_catalog: CourseworkTaskCatalog = null,
	run_port: AuthoringRunPort = null,
	report_state: AuthoringReportState = null,
	current_live_revision: int = 1,
	workday_policy: CourseworkWorkdayPolicy = null,
	issuer_provider: CourseworkAcceptedOutcomeIssuerProvider = null
) -> void:
	_live_owner_set = initial_owner_set
	_candidate_admission = candidate_admission
	_task_catalog = task_catalog
	_run_port = run_port
	_report_state = report_state
	_current_live_revision = current_live_revision
	_workday_policy = workday_policy
	_issuer_provider = issuer_provider

## Validates retained process-local dependencies and returns the recovery root.
## Example: `var root_result: DomainResult = CourseworkWholeGenerationRecovery.create(...)`.
static func create(initial_owner_set: CourseworkLiveOwnerSet, task_catalog: CourseworkTaskCatalog, run_port: AuthoringRunPort, report_state: AuthoringReportState, current_live_revision: int, workday_policy: CourseworkWorkdayPolicy, issuer_provider: CourseworkAcceptedOutcomeIssuerProvider) -> DomainResult:
	if task_catalog == null or run_port == null or report_state == null or workday_policy == null or current_live_revision < 1 or issuer_provider == null:
		return DomainResult.failure(&"recovery_dependencies_unavailable", "typed recovery dependencies are incomplete")
	var catalog_snapshot: Dictionary[String, Variant] = {}
	var raw_snapshot: Dictionary = task_catalog.snapshot()
	for raw_key: Variant in raw_snapshot.keys():
		if typeof(raw_key) != TYPE_STRING:
			return DomainResult.failure(&"recovery_dependencies_unavailable", "Task catalogue snapshot contains an invalid key")
		catalog_snapshot[String(raw_key)] = raw_snapshot[raw_key]
	var admission: CourseworkCanonicalCandidateAdmission = CourseworkCanonicalCandidateAdmission.new(SAVE_VERSION, catalog_snapshot)
	return DomainResult.success(CourseworkWholeGenerationRecovery.new(initial_owner_set, admission, task_catalog, run_port, report_state, current_live_revision, workday_policy, issuer_provider))

## Returns the immutable owner membership currently published by this root.
## Example: `var owners: CourseworkLiveOwnerSet = root.current_owner_set()`.
func current_owner_set() -> CourseworkLiveOwnerSet:
	return _live_owner_set

## Validates current completely before previous and publishes only a fully
## prepared immutable owner set. The injected preparer receives one detached
## v2 generation. Candidate admission is typed and process-local; no callable
## or Save-decoded runtime owner is accepted as a preparation shortcut.
func restore(current_generation: Variant, previous_generation: Variant) -> DomainResult:
	var prepared_result: DomainResult = prepare_restore(current_generation, previous_generation)
	if not prepared_result.is_success():
		return prepared_result
	var prepared: PreparedRestore = prepared_result.value() as PreparedRestore
	publish_prepared(prepared)
	return DomainResult.success(prepared.result_code)

## Selects and prepares a complete owner set without changing live ownership.
## Example: `var prepared: DomainResult = root.prepare_restore(current, previous)`.
func prepare_restore(current_generation: Variant, previous_generation: Variant) -> DomainResult:
	if _restoring:
		return DomainResult.failure(&"recovery_reentrant", "recovery is already in progress")
	_restoring = true
	var result: DomainResult = _restore_current_first(current_generation, previous_generation)
	if not result.is_success():
		_restoring = false
	return result

## Performs the sole non-fallible publication after caller preparation succeeds.
## Example: `root.publish_prepared(prepared.value())`.
func publish_prepared(prepared: PreparedRestore) -> void:
	_current_live_revision = prepared.owner_set.authoring_session().live_revision()
	_live_owner_set = prepared.owner_set
	_restoring = false

## Releases a failed outer-composition preparation without altering live owners.
## Example: `root.discard_prepared(prepared.value())`.
func discard_prepared(_prepared: PreparedRestore) -> void:
	_restoring = false

## Holds the old aggregate strongly until the result has been constructed while
## the reentrancy guard remains active. Publication itself performs no callback.
func _finish_restore_retaining_prior(_prior_owner_guard: Array[CourseworkLiveOwnerSet], result: DomainResult) -> DomainResult:
	_restoring = false
	return result

func _prepare_current_first(current_generation: Variant, previous_generation: Variant) -> DomainResult:
	var current_result: DomainResult = _prepare_generation(current_generation)
	if current_result.is_success():
		return DomainResult.success(PreparedRestore.new(current_result.value() as CourseworkLiveOwnerSet, &"loaded_current"))
	var previous_result: DomainResult = _prepare_generation(previous_generation)
	if previous_result.is_success():
		return DomainResult.success(PreparedRestore.new(previous_result.value() as CourseworkLiveOwnerSet, &"recovered_previous"))
	if _is_preparation_rejection(current_result):
		return current_result
	if _is_preparation_rejection(previous_result):
		return previous_result
	return DomainResult.failure(&"no_valid_generation", "neither stored generation is wholly valid coursework.save.v2")

## Legacy protected seam retained for existing recovery-vector subclasses. It
## now returns a prepared owner set and never publishes by itself.
func _restore_current_first(current_generation: Variant, previous_generation: Variant) -> DomainResult:
	return _prepare_current_first(current_generation, previous_generation)

func _is_preparation_rejection(result: DomainResult) -> bool:
	if result == null or result.is_success():
		return false
	return not [
		&"generation_invalid", &"unsupported_version", &"integrity_failed",
		&"content_mismatch", &"invalid_section_payload", &"progression_v2_invalid",
		&"authoring_task_mismatch",
	].has(result.error_code())

func _prepare_generation(generation: Variant) -> DomainResult:
	var admission_result: DomainResult = _admit_generation(generation)
	if not admission_result.is_success():
		return admission_result
	return _prepare_admitted_owner_set(admission_result.value())

func _admit_generation(generation: Variant) -> DomainResult:
	if typeof(generation) != TYPE_DICTIONARY:
		return DomainResult.failure(&"generation_invalid", "a generation must be an object")
	var candidate: Dictionary = Dictionary(generation).duplicate(true)
	if String(candidate.get("save_version", "")) != SAVE_VERSION:
		return DomainResult.failure(&"unsupported_version", "only coursework.save.v2 is supported")
	if _candidate_admission == null:
		return DomainResult.failure(&"recovery_dependencies_unavailable", "typed candidate admission is required")
	var section_keys: Array[String] = ["authoring_raw", "content_raw", "progression_raw", "settings_raw", "tutorial_raw"]
	for section_key: String in section_keys:
		if not candidate.has(section_key) or not candidate[section_key] is PackedByteArray:
			return DomainResult.failure(&"generation_invalid", "a v2 generation requires detached canonical section bytes")
	if typeof(candidate.get("checksum", null)) != TYPE_STRING:
		return DomainResult.failure(&"generation_invalid", "a v2 generation requires its checksum")
	var admission_result: DomainResult = _candidate_admission.admit_v2(
		PackedByteArray(candidate["authoring_raw"]),
		PackedByteArray(candidate["content_raw"]),
		PackedByteArray(candidate["progression_raw"]),
		PackedByteArray(candidate["settings_raw"]),
		PackedByteArray(candidate["tutorial_raw"]),
		String(candidate["checksum"])
	)
	if not admission_result.is_success():
		return admission_result
	return admission_result

func _prepare_admitted_owner_set(admitted_value: Variant) -> DomainResult:
	if typeof(admitted_value) != TYPE_DICTIONARY:
		return DomainResult.failure(&"generation_invalid", "admitted v2 generation has an invalid shape")
	var admitted: Dictionary[String, Variant] = admitted_value
	var authoring: Dictionary[String, Variant] = admitted["authoring"]
	var contract_result: DomainResult = _task_catalog.recovery_contract(String(authoring["task_id"]))
	if not contract_result.is_success(): return contract_result
	if not contract_result.value() is CourseworkTaskRecoveryContract:
		return DomainResult.failure(&"task_recovery_contract_invalid", "Task recovery resolution returned an invalid contract")
	var contract: CourseworkTaskRecoveryContract = contract_result.value() as CourseworkTaskRecoveryContract
	var model_result: DomainResult = GraphModel.restore_from_recovery_projection(contract.graph_model_contract(), contract.starting_graph(), Dictionary(authoring["graph"]), int(authoring["graph_revision"]), _current_live_revision)
	if not model_result.is_success(): return model_result
	var session_result: DomainResult = AuthoringSession.restore_from_recovery(model_result.value(), _run_port, _report_state)
	if not session_result.is_success(): return session_result
	var prepared_authoring: AuthoringSession = session_result.value() as AuthoringSession
	if prepared_authoring == null:
		return DomainResult.failure(&"authoring_recovery_session_invalid", "Authoring recovery returned no prepared session")
	var progression: Dictionary[String, Variant] = admitted["progression"]
	var career: CourseworkCareerProgression = CourseworkCareerProgression.new()
	var career_result: DomainResult = career.restore_stable_projection(progression["career_projection"])
	if not career_result.is_success(): return career_result
	var settings_tutorial: CourseworkSettingsTutorialProjectionContracts = CourseworkSettingsTutorialProjectionContracts.new()
	var settings_result: DomainResult = settings_tutorial.submit_pair(admitted["settings"], admitted["tutorial"])
	if not settings_result.is_success(): return settings_result
	var workday_result: DomainResult = _prepare_workday(
		progression["workday_projection"], authoring, contract, prepared_authoring.live_revision())
	if not workday_result.is_success(): return workday_result
	var workday: CourseworkWorkdayLifecycle = workday_result.value() as CourseworkWorkdayLifecycle
	var owner_set_result: DomainResult = CourseworkLiveOwnerSet.create(prepared_authoring, _task_catalog, workday, career, settings_tutorial)
	if not owner_set_result.is_success(): return owner_set_result
	var prepared_owner_set: CourseworkLiveOwnerSet = owner_set_result.value() as CourseworkLiveOwnerSet
	return DomainResult.success(prepared_owner_set)

func _prepare_workday(
	projection: Variant,
	authoring: Dictionary[String, Variant],
	contract: CourseworkTaskRecoveryContract,
	operational_authoring_revision: int
) -> DomainResult:
	if projection == null:
		return DomainResult.success(null)
	if _workday_policy == null:
		return DomainResult.failure(&"recovery_dependencies_unavailable", "active Workday requires its admitted policy")
	var issuer_result: DomainResult = _fresh_recovery_issuer()
	if not issuer_result.is_success(): return issuer_result
	var graph_result: DomainResult = _authoring_graph_from_admitted(authoring)
	if not graph_result.is_success(): return graph_result
	var workday_projection: CourseworkWorkdayRecoveryProjection = CourseworkWorkdayRecoveryProjection.new()
	var hydration: DomainResult = workday_projection.hydrate_v2(projection, graph_result.value(), contract)
	if not hydration.is_success(): return hydration
	return workday_projection.restore_lifecycle(
		_workday_policy, issuer_result.value(), operational_authoring_revision)

func _fresh_recovery_issuer() -> DomainResult:
	var issuer_result: DomainResult = _issuer_provider.create_fresh_issuer()
	if not issuer_result.is_success() or not issuer_result.value() is CourseworkWorkdayLifecycle.AcceptedOutcomeIssuer:
		return issuer_result if not issuer_result.is_success() else DomainResult.failure(&"issuer_provider_invalid", "issuer provider returned no valid fresh issuer")
	var issuer: CourseworkWorkdayLifecycle.AcceptedOutcomeIssuer = issuer_result.value() as CourseworkWorkdayLifecycle.AcceptedOutcomeIssuer
	if issuer == null or not is_instance_valid(issuer) or not issuer.is_recovery_valid():
		return DomainResult.failure(&"issuer_provider_invalid", "issuer provider returned an invalid recovery issuer")
	if not issuer.try_claim_recovery_attempt():
		return DomainResult.failure(&"issuer_provider_reused", "issuer provider returned an already consumed recovery issuer")
	return DomainResult.success(issuer)

func _authoring_graph_from_admitted(authoring: Dictionary[String, Variant]) -> DomainResult:
	var authoring_graph: Dictionary[String, Variant] = {}
	for graph_key: Variant in Dictionary(authoring["graph"]).keys():
		if typeof(graph_key) != TYPE_STRING:
			return DomainResult.failure(&"invalid_authoring_graph", "authoring graph keys must be strings")
		authoring_graph[String(graph_key)] = Dictionary(authoring["graph"])[graph_key]
	return DomainResult.success(authoring_graph)
