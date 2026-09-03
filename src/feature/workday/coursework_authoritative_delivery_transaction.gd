class_name CourseworkAuthoritativeDeliveryTransaction
extends RefCounted

## Story 004 owner for one charged, immutable authoritative delivery intent.
## It binds and reduces only deterministic Workday facts; GVET remains synchronous.

enum DeliveryTrigger { SUBMIT, LEAVE_AND_DELIVER, FORCED_DELIVERY }
enum RiskWarning { NONE, ZERO_VOLUNTARY_EVIDENCE, STALE_VOLUNTARY_EVIDENCE, FAILED_VOLUNTARY_EVIDENCE }
enum TransactionState { IDLE, RISK_WARNING_PENDING, ACTIVE, RECOVERABLE_INTERRUPTION, COMMITTED }

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CourseworkPublicRunContractType = preload("res://src/core/task/coursework_public_run_contract.gd")
const CourseworkRunInputType = preload("res://src/core/gvet/coursework_run_input.gd")
const CourseworkRunResultType = preload("res://src/core/gvet/coursework_run_result.gd")
const SemanticDiagnosticType = preload("res://src/core/gvet/semantic_diagnostic.gd")
const AuthoringSessionType = preload("res://src/core/authoring/authoring_session.gd")
const CourseworkWorkdayLifecycleType = preload("res://src/feature/workday/coursework_workday_lifecycle.gd")

var _state: int = TransactionState.IDLE
var _pending_warning: int = RiskWarning.NONE
var _pending_evidence_identity: String = ""
var _pending_graph_revision: int = -1
var _accepted_warning: int = RiskWarning.NONE
var _accepted_evidence_identity: String = ""
var _accepted_graph_revision: int = -1
var _binding: CourseworkRunInput = null
var _delivery_issuer: CourseworkWorkdayLifecycle.AcceptedOutcomeIssuer = null
var _committed_record: Dictionary[String, Variant] = {}
var _committed_result_sha256: String = ""

## Prepares the complete public roster, gates known voluntary-evidence risk,
## then charges and executes one authoritative delivery intent synchronously.
func admit_and_run(
	public_run_contract: CourseworkPublicRunContract,
	lifecycle: CourseworkWorkdayLifecycle,
	authoring_session: AuthoringSession,
	issuer: CourseworkWorkdayLifecycle.AcceptedOutcomeIssuer,
	trigger: int,
	task_id: String,
	day_index: int,
	request_id: String,
	graph_revision: int,
	graph_snapshot: Dictionary[String, Variant],
	complete_roster_ids: Array[String],
	voluntary_input: CourseworkRunInput = null,
	voluntary_result: CourseworkRunResult = null
) -> DomainResult:
	var command_result: DomainResult = _validate_command(
		public_run_contract, lifecycle, authoring_session, issuer, trigger)
	if not command_result.is_success():
		return command_result
	var prepared_result: DomainResult = _prepare_binding(public_run_contract, task_id, day_index,
		request_id, graph_revision, graph_snapshot, complete_roster_ids)
	if not prepared_result.is_success():
		return prepared_result
	var prepared_input: CourseworkRunInput = prepared_result.value()
	var warning_result: DomainResult = _admit_risk_warning(
		voluntary_input, voluntary_result, prepared_input, graph_revision)
	if not warning_result.is_success():
		return warning_result
	var warning_value: Variant = warning_result.value()
	if typeof(warning_value) == TYPE_DICTIONARY:
		return warning_result
	return _activate_bind_and_run(public_run_contract, lifecycle, authoring_session,
		trigger, prepared_input)

func _validate_command(
	public_run_contract: CourseworkPublicRunContract, lifecycle: CourseworkWorkdayLifecycle,
	authoring_session: AuthoringSession, issuer: CourseworkWorkdayLifecycle.AcceptedOutcomeIssuer,
	trigger: int
) -> DomainResult:
	var dependencies_result: DomainResult = _validate_dependencies(
		public_run_contract, lifecycle, authoring_session, issuer, trigger)
	if not dependencies_result.is_success():
		return dependencies_result
	if not _committed_record.is_empty():
		return _reject(&"authoritative_delivery_already_committed", "a committed delivery may only replay its exact outcome")
	if _state == TransactionState.ACTIVE or _state == TransactionState.RECOVERABLE_INTERRUPTION:
		return _reject(&"authoritative_delivery_locked", "the charged authoritative delivery intent must retry its exact binding")
	return DomainResultType.success(true)

func _prepare_binding(
	public_run_contract: CourseworkPublicRunContract, task_id: String, day_index: int,
	request_id: String, graph_revision: int, graph_snapshot: Dictionary[String, Variant],
	complete_roster_ids: Array[String]
) -> DomainResult:
	var prepared_result: DomainResult = public_run_contract.prepare_run_input(
		task_id, day_index, request_id, graph_revision, graph_snapshot, complete_roster_ids)
	if not prepared_result.is_success():
		return prepared_result
	var prepared_input: CourseworkRunInput = prepared_result.value()
	if prepared_input == null or not prepared_input.is_valid():
		return _reject(&"authoritative_delivery_binding_invalid", "delivery requires the complete immutable current-day public roster")
	return DomainResultType.success(prepared_input)

func _admit_risk_warning(
	voluntary_input: CourseworkRunInput, voluntary_result: CourseworkRunResult,
	prepared_input: CourseworkRunInput, graph_revision: int
) -> DomainResult:
	var evidence_identity: String = "" if voluntary_input == null else voluntary_input.identity_sha256()
	var warning: int = risk_warning_for(voluntary_input, voluntary_result, prepared_input)
	if warning == RiskWarning.NONE or _has_accepted_warning(warning, evidence_identity, graph_revision):
		return DomainResultType.success(true)
	_state = TransactionState.RISK_WARNING_PENDING
	_pending_warning = warning
	_pending_evidence_identity = evidence_identity
	_pending_graph_revision = graph_revision
	return DomainResultType.success(status())

func _activate_bind_and_run(
	public_run_contract: CourseworkPublicRunContract, lifecycle: CourseworkWorkdayLifecycle,
	authoring_session: AuthoringSession, trigger: int, prepared_input: CourseworkRunInput
) -> DomainResult:
	if trigger == DeliveryTrigger.FORCED_DELIVERY:
		var activation: DomainResult = lifecycle.activate_forced_delivery()
		if not activation.is_success():
			return activation
	var endpoint_result: DomainResult = public_run_contract.validate_prepared_run(authoring_session, prepared_input)
	if not endpoint_result.is_success():
		return endpoint_result
	_delivery_issuer = CourseworkWorkdayLifecycleType.AcceptedOutcomeIssuer.new()
	var admission: DomainResult = lifecycle.begin_authoritative_delivery(prepared_input, _delivery_issuer)
	if not admission.is_success():
		return admission
	_binding = prepared_input
	_state = TransactionState.ACTIVE
	_clear_warning_gate()
	return _run_bound_input(public_run_contract, lifecycle, authoring_session)

## Accepts only the exact displayed risk warning for its immutable evidence
## identity and current authoring revision. A changed report requires re-warning.
func accept_pending_risk_warning(
	warning: int, evidence_identity: String, graph_revision: int
) -> DomainResult:
	if _state != TransactionState.RISK_WARNING_PENDING \
			or warning != _pending_warning \
			or evidence_identity != _pending_evidence_identity \
			or graph_revision != _pending_graph_revision:
		return _reject(&"authoritative_delivery_warning_mismatch", "risk acceptance must match the pending evidence and revision")
	_accepted_warning = warning
	_accepted_evidence_identity = evidence_identity
	_accepted_graph_revision = graph_revision
	return DomainResultType.success(status())

## Retries only the immutable charged delivery binding without another charge.
func retry_same_binding(
	public_run_contract: CourseworkPublicRunContract,
	lifecycle: CourseworkWorkdayLifecycle,
	authoring_session: AuthoringSession,
	candidate: CourseworkRunInput
) -> DomainResult:
	if public_run_contract == null or lifecycle == null or authoring_session == null:
		return _reject(&"authoritative_delivery_dependency_unavailable", "Task, Workday, and Authoring dependencies are required")
	if _state != TransactionState.RECOVERABLE_INTERRUPTION or _binding == null \
			or candidate == null or candidate.identity_sha256() != _binding.identity_sha256():
		return _reject(&"authoritative_delivery_retry_invalid", "retry requires the exact charged delivery binding")
	var endpoint_result: DomainResult = public_run_contract.validate_prepared_run(authoring_session, candidate)
	if not endpoint_result.is_success():
		return endpoint_result
	var retry_result: DomainResult = lifecycle.retry_authoritative_delivery(candidate)
	if not retry_result.is_success():
		return retry_result
	_state = TransactionState.ACTIVE
	return _run_bound_input(public_run_contract, lifecycle, authoring_session)

## Reduces a terminal outcome for the charged intent and replays only exact
## committed results. Conflicts leave the authoritative record unchanged.
func reduce_authoritative_outcome(
	lifecycle: CourseworkWorkdayLifecycle, candidate: CourseworkRunResult
) -> DomainResult:
	if lifecycle == null or candidate == null or not candidate.is_valid():
		return _mark_recoverable(&"authoritative_delivery_outcome_invalid", "delivery requires one valid complete terminal outcome")
	if not _committed_record.is_empty():
		if candidate.sha256_hex() == _committed_result_sha256:
			return DomainResultType.success(_committed_record.duplicate(true))
		return _reject(&"authoritative_delivery_identity_conflict", "a different outcome cannot replace the committed delivery")
	if _binding == null or _delivery_issuer == null \
			or (_state != TransactionState.ACTIVE and _state != TransactionState.RECOVERABLE_INTERRUPTION):
		return _reject(&"authoritative_delivery_outcome_unavailable", "no charged authoritative delivery intent is active")
	var failed_ids_result: DomainResult = _validate_settling_outcome(candidate)
	if not failed_ids_result.is_success():
		return _mark_recoverable(failed_ids_result.error_code(), failed_ids_result.error_message())
	var final_elapsed: int = int(lifecycle.snapshot().get("elapsed_minutes", -1))
	var receipt_facts_result: DomainResult = CourseworkWorkdayLifecycleType.receipt_facts_for_final_elapsed(
		_binding.day_index(), final_elapsed)
	if not receipt_facts_result.is_success():
		return _mark_recoverable(receipt_facts_result.error_code(), receipt_facts_result.error_message())
	var receipt_facts: Dictionary[String, Variant] = _typed_dictionary_copy(receipt_facts_result.value())
	var failed_ids: Array[String] = failed_ids_result.value()
	var pending_record: Dictionary[String, Variant] = _build_committed_record(
		receipt_facts, failed_ids, lifecycle.is_final_day())
	var capability_result: DomainResult = _delivery_issuer.issue_lifecycle_receipt(
		_binding.identity_sha256(), _binding.day_index(), final_elapsed)
	if not capability_result.is_success():
		return _mark_recoverable(capability_result.error_code(), capability_result.error_message())
	var receipt_result: DomainResult = lifecycle.commit_authoritative_receipt(capability_result.value())
	if not receipt_result.is_success():
		return _mark_recoverable(receipt_result.error_code(), receipt_result.error_message())
	_committed_record = pending_record
	_committed_result_sha256 = candidate.sha256_hex()
	_state = TransactionState.COMMITTED
	_clear_warning_gate()
	_binding = null
	return DomainResultType.success(_committed_record.duplicate(true))

## Returns the exact risk warning after verifying evidence against the current
## prepared full delivery roster. Targeted/subset reports cannot grant credit.
func risk_warning_for(
	voluntary_input: CourseworkRunInput, voluntary_result: CourseworkRunResult,
	current_delivery_input: CourseworkRunInput
) -> int:
	if voluntary_input == null or voluntary_result == null \
			or not voluntary_input.is_valid() or not voluntary_result.is_valid() \
			or current_delivery_input == null or not current_delivery_input.is_valid() \
			or not _rosters_match(voluntary_input.case_roster(), current_delivery_input.case_roster()):
		return RiskWarning.ZERO_VOLUNTARY_EVIDENCE
	if not _evidence_matches_current_delivery(voluntary_input, current_delivery_input):
		return RiskWarning.STALE_VOLUNTARY_EVIDENCE
	if not _result_matches_input(voluntary_result, voluntary_input) or not voluntary_result.suite_pass():
		return RiskWarning.FAILED_VOLUNTARY_EVIDENCE
	return RiskWarning.NONE

## Returns transient delivery state and any committed immutable delivery record.
func status() -> Dictionary[String, Variant]:
	return {
		"state": StringName(TransactionState.keys()[_state].to_lower()),
		"pending_warning": StringName(RiskWarning.keys()[_pending_warning].to_lower()),
		"pending_evidence_identity": _pending_evidence_identity,
		"pending_graph_revision": _pending_graph_revision,
		"binding_identity_sha256": "" if _binding == null else _binding.identity_sha256(),
		"committed_record": _committed_record.duplicate(true),
	}

func _run_bound_input(
	public_run_contract: CourseworkPublicRunContract,
	lifecycle: CourseworkWorkdayLifecycle,
	authoring_session: AuthoringSession
) -> DomainResult:
	var execution: DomainResult = public_run_contract.run_prepared(authoring_session, _binding)
	if not execution.is_success():
		return _mark_recoverable(execution.error_code(), execution.error_message())
	var terminal_value: Variant = execution.value()
	if not terminal_value is CourseworkRunResultType:
		return _mark_recoverable(&"authoritative_delivery_terminal_invalid", "Task did not return a CourseworkRunResult")
	return reduce_authoritative_outcome(lifecycle, terminal_value)

func _validate_complete_matching_outcome(candidate: CourseworkRunResult) -> DomainResult:
	if not _result_matches_input(candidate, _binding) or not candidate.validation_pass() \
			or not candidate.run_error().is_empty():
		return _reject(&"authoritative_delivery_outcome_incomplete", "outcome must be a complete validation-passing result for the charged binding")
	var roster: Array[Dictionary] = _binding.case_roster()
	var cases: Array[CourseworkCaseResult] = candidate.case_results()
	if cases.size() != roster.size():
		return _reject(&"authoritative_delivery_outcome_incomplete", "outcome must contain every public roster case")
	var failed_ids: Array[String] = []
	var seen: Dictionary[String, bool] = {}
	for index: int in roster.size():
		var expected_id: String = String(roster[index].get("case_id", ""))
		var actual: CourseworkCaseResult = cases[index]
		if expected_id.is_empty() or actual == null or actual.case_id() != expected_id \
			or actual.status() == CourseworkCaseResult.STATUS_SYSTEM_ERROR \
			or actual.status() == CourseworkCaseResult.STATUS_NOT_RUN_SYSTEM_ERROR:
			return _reject(&"authoritative_delivery_outcome_incomplete", "outcome cases must match roster order and complete execution")
		if not actual.case_pass() and not seen.has(expected_id):
			seen[expected_id] = true
			failed_ids.append(expected_id)
	return DomainResultType.success(failed_ids)

## A confirmed authoritative delivery settles a valid semantic rejection as a
## full-roster failure. GVET keeps the rejection report unchanged: it ran no
## cases and retains its ordered diagnostics. Input and system failures remain
## retryable.
func _validate_settling_outcome(candidate: CourseworkRunResult) -> DomainResult:
	if _is_settling_semantic_rejection(candidate):
		return DomainResultType.success(_binding_case_ids())
	return _validate_complete_matching_outcome(candidate)

func _is_settling_semantic_rejection(candidate: CourseworkRunResult) -> bool:
	return _result_matches_input(candidate, _binding) \
		and not candidate.validation_pass() \
		and _has_only_semantic_diagnostics(candidate.diagnostics()) \
		and candidate.case_results().is_empty() \
		and candidate.run_error().is_empty()

func _has_only_semantic_diagnostics(diagnostics: Array[Dictionary]) -> bool:
	if diagnostics.is_empty():
		return false
	for diagnostic: Dictionary in diagnostics:
		var reason_code: Variant = diagnostic.get("reason_code", null)
		if typeof(reason_code) != TYPE_STRING \
				or SemanticDiagnosticType.priority_for(String(reason_code)) < 0:
			return false
	return true

func _binding_case_ids() -> Array[String]:
	var failed_ids: Array[String] = []
	if _binding == null:
		return failed_ids
	for row: Dictionary in _binding.case_roster():
		failed_ids.append(String(row.get("case_id", "")))
	return failed_ids

func _result_matches_input(result: CourseworkRunResult, input: CourseworkRunInput) -> bool:
	if result == null or input == null:
		return false
	var identity: Dictionary[String, Variant] = _typed_dictionary_copy(result.identity())
	return String(identity.get("task_id", "")) == input.task_id() \
		and int(identity.get("day_index", -1)) == input.day_index() \
		and String(identity.get("request_id", "")) == input.request_id() \
		and int(identity.get("graph_revision", -1)) == input.graph_revision() \
		and String(identity.get("input_identity_sha256", "")) == input.identity_sha256() \
		and String(identity.get("admitted_content_digest", "")) == input.admitted_content_digest()

func _rosters_match(left: Array[Dictionary], right: Array[Dictionary]) -> bool:
	if left.size() != right.size():
		return false
	for index: int in left.size():
		if String(left[index].get("case_id", "")) != String(right[index].get("case_id", "")):
			return false
	return true

func _evidence_matches_current_delivery(
	evidence_input: CourseworkRunInput, current_delivery_input: CourseworkRunInput
) -> bool:
	return evidence_input.task_id() == current_delivery_input.task_id() \
		and evidence_input.day_index() == current_delivery_input.day_index() \
		and evidence_input.graph_revision() == current_delivery_input.graph_revision() \
		and evidence_input.graph_snapshot() == current_delivery_input.graph_snapshot() \
		and evidence_input.admitted_content_digest() == current_delivery_input.admitted_content_digest() \
		and _rosters_match(evidence_input.case_roster(), current_delivery_input.case_roster())

func _build_committed_record(
	receipt: Dictionary[String, Variant], failed_ids: Array[String], is_final_day: bool
) -> Dictionary[String, Variant]:
	var defect_count: int = failed_ids.size()
	var rework_decision: StringName = &"none"
	if defect_count > 0:
		rework_decision = &"final_review_outstanding_60" if is_final_day else &"next_day_rework_60"
	var failed_copy: Array[String] = failed_ids.duplicate()
	return {
		"delivery_identity": _binding.identity_sha256(),
		"failed_case_ids": failed_copy,
		"defect_count": defect_count,
		"receipt": receipt.duplicate(true),
		"overtime_fact": {
			"overtime_minutes": int(receipt["overtime_minutes"]),
			"overtime_used": bool(receipt["overtime_used"]),
		},
		"rework_decision": rework_decision,
		"day_closed": true,
		"career_fact": {
			"day_index": int(receipt["day_index"]),
			"failed_case_ids": failed_copy.duplicate(),
			"defect_count": defect_count,
			"overtime_minutes": int(receipt["overtime_minutes"]),
		},
	}

func _validate_dependencies(
	public_run_contract: CourseworkPublicRunContract,
	lifecycle: CourseworkWorkdayLifecycle,
	authoring_session: AuthoringSession,
	issuer: CourseworkWorkdayLifecycle.AcceptedOutcomeIssuer,
	trigger: int
) -> DomainResult:
	if public_run_contract == null or lifecycle == null or authoring_session == null or issuer == null:
		return _reject(&"authoritative_delivery_dependency_unavailable", "Task, Workday, Authoring, and receipt issuer dependencies are required")
	if trigger < DeliveryTrigger.SUBMIT or trigger > DeliveryTrigger.FORCED_DELIVERY:
		return _reject(&"authoritative_delivery_trigger_invalid", "delivery trigger is not supported")
	return DomainResultType.success(true)

func _mark_recoverable(error_code: StringName, message: String) -> DomainResult:
	if _binding != null:
		_state = TransactionState.RECOVERABLE_INTERRUPTION
	return _reject(error_code, message)

func _reject(error_code: StringName, message: String) -> DomainResult:
	return DomainResultType.failure(error_code, message, "workday.authoritative_delivery_transaction")

func _has_accepted_warning(warning: int, evidence_identity: String, graph_revision: int) -> bool:
	return _accepted_warning == warning \
		and _accepted_evidence_identity == evidence_identity \
		and _accepted_graph_revision == graph_revision

func _clear_warning_gate() -> void:
	_pending_warning = RiskWarning.NONE
	_pending_evidence_identity = ""
	_pending_graph_revision = -1
	_accepted_warning = RiskWarning.NONE
	_accepted_evidence_identity = ""
	_accepted_graph_revision = -1

func _typed_dictionary_copy(value: Variant) -> Dictionary[String, Variant]:
	var copy: Dictionary[String, Variant] = {}
	if typeof(value) != TYPE_DICTIONARY:
		return copy
	for raw_key: Variant in value.keys():
		if typeof(raw_key) != TYPE_STRING:
			return {}
		copy[String(raw_key)] = value[raw_key]
	return copy
