class_name CourseworkWorkdayLifecycle
extends RefCounted

## Typed Feature-domain owner for the Story 002 Workday lifecycle boundary.
## It records only time, state, report-staleness metadata, and minimal receipts.

enum LifecycleState { TASK_OPEN_REGULAR, REGULAR_DELIVERY_DECISION, TASK_OPEN_OVERTIME, FORCED_DELIVERY_PENDING, FORCED_DELIVERY_ACTIVATED, SUBMISSION_IN_PROGRESS, DAY_COMMITTED, CAREER_COMPLETE, REWORK_DUE }
enum OptionalAction { TARGETED_CASE, VOLUNTARY_SUITE }
enum OvertimeAuthorizationOrigin { PLAYER_EXPLICIT, AUTOMATIC }
enum VoluntaryTransactionState { NONE, ACTIVE, RECOVERABLE_INTERRUPTION, ABANDONED, COMPLETED }

const CourseworkRunInputType = preload("res://src/core/gvet/coursework_run_input.gd")
const CanonicalJsonIRType = preload("res://src/foundation/canonical_json_ir.gd")

## Single-use evidence that an external Story 004 owner accepted its outcome.
class AcceptedOutcomeCapability extends RefCounted:
	var _locked: bool = false:
		set(value):
			if not _locked:
				_locked = value
	var _delivery_identity: String = "":
		set(value):
			if not _locked:
				_delivery_identity = value
	var _issuer_identity: RefCounted = null:
		set(value):
			if not _locked:
				_issuer_identity = value
	var _day_index: int = 0:
		set(value):
			if not _locked:
				_day_index = value
	var _final_elapsed_minutes: int = 0:
		set(value):
			if not _locked:
				_final_elapsed_minutes = value
	var _consumed: bool = false:
		set(value):
			if value:
				_consumed = true

	func _init(issuer_identity: RefCounted, delivery_identity: String, day_index: int, final_elapsed_minutes: int) -> void:
		_issuer_identity = issuer_identity
		_delivery_identity = delivery_identity
		_day_index = day_index
		_final_elapsed_minutes = final_elapsed_minutes
		_locked = true

	func _consume() -> void:
		_consumed = true

## Minimal Story 004 issuer contract. Its opaque identity is bound at open;
## Story 004 owns deciding when an accepted outcome may be issued.
class AcceptedOutcomeIssuer extends RefCounted:
	var _locked: bool = false:
		set(value):
			if not _locked:
				_locked = value
	var _identity: RefCounted = null:
		set(value):
			if not _locked:
				_identity = value
	var _recovery_attempt_claimed: bool = false

	func _init() -> void:
		_identity = RefCounted.new()
		_locked = true

	## Reports whether this opaque issuer can participate in Story 006 recovery.
	## Example: `if issuer.is_recovery_valid(): prepare_workday_recovery()`.
	func is_recovery_valid() -> bool:
		return _identity != null and is_instance_valid(_identity)

	## Compares opaque recovery identities without exposing the identity token.
	## Example: `if first.has_same_recovery_identity(second): reject_reuse()`.
	func has_same_recovery_identity(other: AcceptedOutcomeIssuer) -> bool:
		return other != null and is_instance_valid(other) and is_recovery_valid() \
			and other.is_recovery_valid() and _identity == other._identity

	## Atomically claims this issuer for one Story 006 recovery attempt.
	## Example: `if not issuer.try_claim_recovery_attempt(): reject_reuse()`.
	## The claim remains consumed after any later recovery-preparation failure.
	func try_claim_recovery_attempt() -> bool:
		if not is_recovery_valid() or _recovery_attempt_claimed:
			return false
		_recovery_attempt_claimed = true
		return true

	func issue_lifecycle_receipt(delivery_identity: String, day_index: int, final_elapsed_minutes: int) -> DomainResult:
		var facts_result: DomainResult = CourseworkWorkdayLifecycle.receipt_facts_for_final_elapsed(day_index, final_elapsed_minutes)
		if not facts_result.is_success() or delivery_identity.is_empty():
			return CourseworkWorkdayLifecycle._reject(&"accepted_outcome_invalid", "accepted outcome identity and lifecycle facts are required")
		return DomainResult.success(AcceptedOutcomeCapability.new(_identity, delivery_identity, day_index, final_elapsed_minutes))

const _DELIVERY_BUFFER_MINUTES: int = 15
const _RECEIPT_COST_MINUTES: int = 15
const _REGULAR_CAPACITY_MINUTES: int = 480
const _MAX_FINAL_ELAPSED_MINUTES: int = 600
const _EXPECTED_DAY_COUNT: int = 5
const _FIRST_DAY_INDEX: int = 1
const _REPORT_REVISION_KEY: String = "revision"
const _REPORT_STALE_KEY: String = "stale"
const RECOVERY_MODE_NONE: int = 0
const RECOVERY_MODE_VOLUNTARY_LOCKED: int = 1
const RECOVERY_MODE_AUTHORITATIVE_LOCKED: int = 2

var _initialized: bool = false
var _regular_capacity_minutes: int = 0
var _overtime_additional_minutes: int = 0
var _optional_action_costs: Array[int] = []
var _rework_minutes: int = 0
var _day_count: int = 0
var _bound_issuer_identity: RefCounted = null
var _bound_issuer: AcceptedOutcomeIssuer = null
var _current_day_index: int = _FIRST_DAY_INDEX
var _elapsed_minutes: int = 0
var _authoring_revision: int = 0
var _operational_authoring_revision: int = 0
var _state: int = LifecycleState.TASK_OPEN_REGULAR
var _overtime_authorized: bool = false
var _committed_receipts: Array[Variant] = []
var _retained_voluntary_report: Dictionary[String, Variant] = {}
var _voluntary_transaction_state: int = VoluntaryTransactionState.NONE
var _voluntary_binding: CourseworkRunInput = null
var _voluntary_binding_identity: Dictionary[String, Variant] = {}
var _voluntary_binding_sha256: String = ""
var _voluntary_action: int = -1
var _voluntary_request_id: String = ""
var _voluntary_request_records: Dictionary[String, Variant] = {}
var _authoritative_delivery_binding: CourseworkRunInput = null
var _authoritative_delivery_issuer_identity: RefCounted = null
var _scheduled_rework_minutes: int = 0

## Creates an inert instance. Use open() with an admitted policy for commands.
func _init() -> void:
	pass

## Opens a lifecycle only from an already admitted Workday policy and issuer.
static func open(policy: CourseworkWorkdayPolicy, issuer: AcceptedOutcomeIssuer) -> DomainResult:
	if policy == null or issuer == null:
		return _reject(&"policy_snapshot_unavailable", "an admitted policy snapshot and bound issuer are required")
	var owner: CourseworkWorkdayLifecycle = CourseworkWorkdayLifecycle.new()
	var initialization_result: DomainResult = owner._initialize_from_admitted_policy(policy, issuer)
	if not initialization_result.is_success():
		return initialization_result
	return DomainResult.success(owner)

## Validates and constructs one fresh executable lifecycle from Story 006's
## pure recovery projection. Existing lifecycle owners are never mutated.
static func restore_from_recovery_projection(
	policy: CourseworkWorkdayPolicy,
	issuer: AcceptedOutcomeIssuer,
	stable_lifecycle: Variant,
	recovery_mode: int,
	voluntary_action: int,
	locked_binding: CourseworkRunInput,
	charged_minutes: int = -1,
	operational_authoring_revision: int = -1
) -> DomainResult:
	if policy == null or issuer == null:
		return _reject(&"workday_recovery_dependencies_unavailable", "an admitted policy and fresh issuer are required")
	var candidate: CourseworkWorkdayLifecycle = CourseworkWorkdayLifecycle.new()
	var initialization_result: DomainResult = candidate._initialize_from_admitted_policy(policy, issuer)
	if not initialization_result.is_success():
		return initialization_result
	var restoration_result: DomainResult = candidate._apply_recovery_projection(
		stable_lifecycle, recovery_mode, voluntary_action, locked_binding, issuer, charged_minutes,
		operational_authoring_revision)
	if not restoration_result.is_success():
		return restoration_result
	return DomainResult.success(candidate)

## Returns the lifecycle's detached stable projection, including inert instances.
func snapshot() -> Dictionary[String, Variant]:
	var receipt_copies: Array[Variant] = []
	for receipt_value: Variant in _committed_receipts:
		var receipt: Dictionary = Dictionary(receipt_value).duplicate(true)
		receipt_copies.append(receipt)
	return {"state": lifecycle_state_name(), "current_day_index": _current_day_index, "day_count": _day_count, "elapsed_minutes": _elapsed_minutes, "authorized_capacity_minutes": authorized_capacity_minutes(), "overtime_authorized": _overtime_authorized, "authoring_revision": _authoring_revision, "rework_due_minutes": _scheduled_rework_minutes, "retained_voluntary_report": _retained_voluntary_report.duplicate(true), "committed_receipts": receipt_copies}

## Reports whether this lifecycle is bound to the supplied opaque issuer.
## Example: `if workday.is_bound_to_issuer(issuer): reject_recovery_reuse()`.
func is_bound_to_issuer(issuer: AcceptedOutcomeIssuer) -> bool:
	return _bound_issuer != null and is_instance_valid(_bound_issuer) \
		and _bound_issuer.is_recovery_valid() and issuer != null and is_instance_valid(issuer) \
		and issuer.is_recovery_valid() and _bound_issuer.has_same_recovery_identity(issuer)

## Admits one paid optional action only when it preserves the delivery reserve.
func admit_optional_action(action: int) -> DomainResult:
	var initialized_result: DomainResult = _require_initialized()
	if not initialized_result.is_success():
		return initialized_result
	if _has_live_voluntary_transaction():
		return _reject(&"voluntary_transaction_locked", "another paid optional action is unavailable while a voluntary run is live")
	var action_result: DomainResult = _optional_action_cost(action)
	if not action_result.is_success() or not _is_task_open():
		return action_result if not action_result.is_success() else _reject(&"optional_action_unavailable", "optional actions require an open task")
	var action_cost: int = action_result.value()
	if not fits_delivery_buffer(_elapsed_minutes, action_cost, authorized_capacity_minutes()):
		return _reject(&"delivery_buffer_protected", "optional action would consume the delivery reserve")
	_elapsed_minutes += action_cost
	return DomainResult.success(snapshot())

## Commits one valid immutable voluntary binding and its optional-action charge.
## Same request key and identity replay owner truth without charging or dispatch.
func admit_voluntary_transaction(action: int, binding: CourseworkRunInput) -> DomainResult:
	var initialized_result: DomainResult = _require_initialized()
	if not initialized_result.is_success():
		return initialized_result
	var binding_result: DomainResult = _validate_voluntary_binding(action, binding)
	if not binding_result.is_success():
		return binding_result
	var request_id: String = binding.request_id()
	var replay: DomainResult = lookup_voluntary_request_replay(action, binding)
	if not replay.is_success():
		return replay
	var replay_value: Dictionary[String, Variant] = _typed_string_variant_dictionary(replay.value())
	if replay_value.is_empty() or not replay_value.has("found"):
		return _reject(&"voluntary_replay_record_invalid", "a voluntary replay lookup returned invalid owner state")
	if bool(replay_value["found"]):
		return DomainResult.success({"replayed": true, "status": replay_value["status"]})
	if _has_live_voluntary_transaction():
		return _reject(&"voluntary_transaction_locked", "a live voluntary run blocks another paid action")
	var charge_result: DomainResult = admit_optional_action(action)
	if not charge_result.is_success():
		return charge_result
	_authoring_revision = _operational_authoring_revision
	_voluntary_binding = binding
	_voluntary_binding_identity = _copy_binding_identity(binding)
	_voluntary_binding_sha256 = binding.identity_sha256()
	_voluntary_action = action
	_voluntary_request_id = request_id
	_voluntary_transaction_state = VoluntaryTransactionState.ACTIVE
	_record_current_voluntary_request()
	return DomainResult.success({"replayed": false, "status": voluntary_transaction_status()})

## Resolves an immutable prior request before a caller checks endpoint availability.
## It neither charges nor changes the current live voluntary transaction.
func lookup_voluntary_request_replay(action: int, binding: CourseworkRunInput) -> DomainResult:
	var initialized_result: DomainResult = _require_initialized()
	if not initialized_result.is_success():
		return initialized_result
	var binding_result: DomainResult = _validate_voluntary_binding(action, binding)
	if not binding_result.is_success():
		return binding_result
	var request_id: String = binding.request_id()
	if not _voluntary_request_records.has(request_id):
		return DomainResult.success({"found": false})
	var existing_value: Variant = _voluntary_request_records[request_id]
	if typeof(existing_value) != TYPE_DICTIONARY:
		return _reject(&"voluntary_request_key_invalid", "a recorded voluntary request key has invalid owner state")
	var existing: Dictionary = existing_value
	if String(existing.get("identity_sha256", "")) != binding.identity_sha256() \
			or int(existing.get("action_id", -1)) != action:
		return _reject(&"voluntary_request_key_conflict", "a request key cannot be rebound to another action or immutable input")
	return DomainResult.success({"found": true, "status": _copy_request_status(existing)})

## Returns the one immutable live binding for typed Task/Authoring dispatch.
func voluntary_binding() -> CourseworkRunInput:
	return _voluntary_binding

## Marks the active binding recoverable after an explicitly classified interruption.
func record_voluntary_recoverable_interruption() -> DomainResult:
	if _voluntary_transaction_state != VoluntaryTransactionState.ACTIVE:
		return _reject(&"voluntary_interruption_unavailable", "only an active voluntary run can become recoverable")
	_voluntary_transaction_state = VoluntaryTransactionState.RECOVERABLE_INTERRUPTION
	_record_current_voluntary_request()
	return DomainResult.success(voluntary_transaction_status())

## Restores only the exact stored binding for a zero-cost retry.
func retry_voluntary_transaction(candidate: CourseworkRunInput) -> DomainResult:
	if _voluntary_transaction_state != VoluntaryTransactionState.RECOVERABLE_INTERRUPTION \
			or candidate == null or _voluntary_binding == null:
		return _reject(&"voluntary_retry_unavailable", "only a recoverably interrupted binding can retry")
	if not candidate.is_valid() or candidate.identity_sha256() != _voluntary_binding.identity_sha256():
		return _reject(&"voluntary_retry_binding_mismatch", "retry must use the exact charged immutable binding")
	_voluntary_transaction_state = VoluntaryTransactionState.ACTIVE
	_record_current_voluntary_request()
	return DomainResult.success(voluntary_transaction_status())

## Closes a successful voluntary run without retaining its external terminal result.
func complete_voluntary_transaction() -> DomainResult:
	if _voluntary_transaction_state != VoluntaryTransactionState.ACTIVE:
		return _reject(&"voluntary_completion_unavailable", "only an active voluntary run can complete")
	_voluntary_transaction_state = VoluntaryTransactionState.COMPLETED
	_record_current_voluntary_request()
	_voluntary_binding = null
	return DomainResult.success(voluntary_transaction_status())

## Explicitly abandons a live/recoverable run while preserving the committed charge.
func abandon_voluntary_transaction() -> DomainResult:
	if not _has_live_voluntary_transaction():
		return _reject(&"voluntary_abandon_unavailable", "only a live voluntary run can be abandoned")
	_voluntary_transaction_state = VoluntaryTransactionState.ABANDONED
	_record_current_voluntary_request()
	_voluntary_binding = null
	return DomainResult.success(voluntary_transaction_status())

## Returns transient owner truth; this is deliberately excluded from save state.
func voluntary_transaction_status() -> Dictionary[String, Variant]:
	return {
		"state": StringName(VoluntaryTransactionState.keys()[_voluntary_transaction_state].to_lower()),
		"action": StringName(OptionalAction.keys()[_voluntary_action].to_lower()) if _voluntary_action >= 0 else &"",
		"binding_identity": _voluntary_binding_identity.duplicate(true),
		"is_live": _has_live_voluntary_transaction(),
	}

## Reports the exact already-committed charge for the presently locked intent.
func recovery_charged_minutes() -> DomainResult:
	var initialized_result: DomainResult = _require_initialized()
	if not initialized_result.is_success():
		return initialized_result
	if _voluntary_binding != null:
		return _optional_action_cost(_voluntary_action)
	if _authoritative_delivery_binding != null:
		return DomainResult.success(_RECEIPT_COST_MINUTES)
	return DomainResult.success(0)

## Preflight gate for Presentation composition before any Core graph mutation.
func preflight_authoring_graph_mutation() -> DomainResult:
	var initialized_result: DomainResult = _require_initialized()
	if not initialized_result.is_success():
		return initialized_result
	if _has_live_voluntary_transaction():
		return _reject(&"voluntary_transaction_locked", "graph mutation is unavailable while a voluntary run is live")
	if not _is_task_open():
		return _reject(&"edit_locked", "editing requires an open task")
	return DomainResult.success(true)

## Returns the process-local revision that must match Authoring before an edit.
func operational_authoring_revision() -> int:
	return _operational_authoring_revision

## Evaluates the explicit delivery boundary without charging or dispatching.
func evaluate_optional_action_availability() -> DomainResult:
	var initialized_result: DomainResult = _require_initialized()
	if not initialized_result.is_success():
		return initialized_result
	if _has_live_voluntary_transaction():
		return _reject(&"voluntary_transaction_locked", "optional-action availability is unavailable while a voluntary run is live")
	if not _is_task_open():
		return _reject(&"delivery_boundary_unavailable", "delivery boundary requires an open task")
	if _has_fitting_optional_action():
		return DomainResult.success(snapshot())
	_state = LifecycleState.FORCED_DELIVERY_PENDING if _overtime_authorized else LifecycleState.REGULAR_DELIVERY_DECISION
	return DomainResult.success(snapshot())

## Authorizes overtime only from an explicit player command that no longer fits.
func authorize_overtime(desired_action: int, origin: int) -> DomainResult:
	var initialized_result: DomainResult = _require_initialized()
	if not initialized_result.is_success():
		return initialized_result
	if _has_live_voluntary_transaction():
		return _reject(&"voluntary_transaction_locked", "overtime authorization is unavailable while a voluntary run is live")
	if origin != OvertimeAuthorizationOrigin.PLAYER_EXPLICIT:
		return _reject(&"overtime_must_be_explicit", "automatic overtime authorization is forbidden")
	if _overtime_authorized or not _is_regular_open_state():
		return _reject(&"overtime_unavailable", "overtime may be authorized once from a regular open task")
	var action_result: DomainResult = _optional_action_cost(desired_action)
	if not action_result.is_success():
		return action_result
	if fits_delivery_buffer(_elapsed_minutes, action_result.value(), _regular_capacity_minutes):
		return _reject(&"overtime_not_needed", "the requested action still fits the regular delivery reserve")
	_overtime_authorized = true
	_state = LifecycleState.TASK_OPEN_OVERTIME
	return DomainResult.success(snapshot())

## Retains accepted voluntary-report metadata without binding, running, or refresh.
func retain_voluntary_report_metadata(report_revision: int) -> DomainResult:
	var initialized_result: DomainResult = _require_initialized()
	if not initialized_result.is_success():
		return initialized_result
	if not _is_task_open() or report_revision != _operational_authoring_revision:
		return _reject(&"report_metadata_unavailable", "report metadata requires the current revision of an open task")
	_retained_voluntary_report = {_REPORT_REVISION_KEY: report_revision, _REPORT_STALE_KEY: false}
	return DomainResult.success(snapshot())

## Accepts one Authoring revision change without changing elapsed minutes.
func accept_authoring_revision_change(next_revision: int) -> DomainResult:
	var preflight_result: DomainResult = preflight_authoring_graph_mutation()
	if not preflight_result.is_success():
		return preflight_result
	if next_revision <= _operational_authoring_revision:
		return _reject(&"edit_locked", "editing requires an open task and an advanced revision")
	_authoring_revision = next_revision
	_operational_authoring_revision = next_revision
	if not _retained_voluntary_report.is_empty():
		_retained_voluntary_report[_REPORT_STALE_KEY] = true
	return DomainResult.success(snapshot())

## Activates only the locked forced-delivery boundary without a charge or run.
func activate_forced_delivery() -> DomainResult:
	var initialized_result: DomainResult = _require_initialized()
	if not initialized_result.is_success():
		return initialized_result
	if _has_live_voluntary_transaction():
		return _reject(&"voluntary_transaction_locked", "delivery is unavailable while a voluntary run is live")
	if _state != LifecycleState.FORCED_DELIVERY_PENDING:
		return _reject(&"forced_delivery_not_pending", "forced delivery must be pending before activation")
	_state = LifecycleState.FORCED_DELIVERY_ACTIVATED
	return DomainResult.success(snapshot())

## Binds and charges the one authoritative delivery intent before synchronous
## Task/GVET dispatch. Story 004 keeps the transient binding out of save state.
func begin_authoritative_delivery(
	binding: CourseworkRunInput, issuer: AcceptedOutcomeIssuer
) -> DomainResult:
	var initialized_result: DomainResult = _require_initialized()
	if not initialized_result.is_success():
		return initialized_result
	if _has_live_voluntary_transaction():
		return _reject(&"voluntary_transaction_locked", "delivery is unavailable while a voluntary run is live")
	if _authoritative_delivery_binding != null or not _can_begin_authoritative_delivery():
		return _reject(&"authoritative_delivery_unavailable", "an open task or activated forced delivery is required")
	if binding == null or issuer == null or issuer._identity == null or not binding.is_valid() \
			or binding.day_index() != _current_day_index \
			or binding.graph_revision() != _operational_authoring_revision:
		return _reject(&"authoritative_delivery_binding_invalid", "delivery requires the current valid immutable public Run input")
	if _elapsed_minutes > authorized_capacity_minutes() - _RECEIPT_COST_MINUTES:
		return _reject(&"authoritative_delivery_capacity_exceeded", "delivery does not fit the authorized capacity")
	_authoritative_delivery_binding = binding
	_authoritative_delivery_issuer_identity = issuer._identity
	_authoring_revision = _operational_authoring_revision
	_elapsed_minutes += _RECEIPT_COST_MINUTES
	_state = LifecycleState.SUBMISSION_IN_PROGRESS
	return DomainResult.success(snapshot())

## Returns the exact charged delivery binding for one zero-cost retry.
func authoritative_delivery_binding() -> CourseworkRunInput:
	return _authoritative_delivery_binding

## Returns whether the current admitted Workday is its final playable day.
func is_final_day() -> bool:
	return _initialized and _current_day_index == _day_count

## Validates one zero-cost retry against the exact charged immutable binding.
func retry_authoritative_delivery(candidate: CourseworkRunInput) -> DomainResult:
	if _state != LifecycleState.SUBMISSION_IN_PROGRESS \
			or _authoritative_delivery_binding == null or candidate == null \
			or not candidate.is_valid() \
			or candidate.identity_sha256() != _authoritative_delivery_binding.identity_sha256():
		return _reject(&"authoritative_delivery_retry_invalid", "retry requires the exact charged delivery binding")
	return DomainResult.success(snapshot())

## Rejects abandoning a charged authoritative delivery because finality requires
## its exact locked intent to remain available for retry until receipt commit.
func abandon_authoritative_delivery() -> DomainResult:
	if _state != LifecycleState.SUBMISSION_IN_PROGRESS or _authoritative_delivery_binding == null:
		return _reject(&"authoritative_delivery_abandon_unavailable", "no charged authoritative delivery is active")
	return _reject(&"authoritative_delivery_abandon_forbidden", "authoritative delivery must retry its exact charged intent")

## Atomically records only the authorized lifecycle receipt facts and consumes
## the external accepted-outcome capability; it never runs or interprets tests.
func commit_authoritative_receipt(capability: AcceptedOutcomeCapability) -> DomainResult:
	if _has_live_voluntary_transaction():
		return _reject(&"voluntary_transaction_locked", "delivery is unavailable while a voluntary run is live")
	var validation_result: DomainResult = _validate_receipt_capability(capability)
	if not validation_result.is_success():
		return validation_result
	var facts_result: DomainResult = receipt_facts_for_final_elapsed(capability._day_index, capability._final_elapsed_minutes)
	if not facts_result.is_success():
		return facts_result
	if _authoritative_delivery_binding == null \
			or _state != LifecycleState.SUBMISSION_IN_PROGRESS \
			or capability._delivery_identity != _authoritative_delivery_binding.identity_sha256():
		return _reject(&"authoritative_delivery_identity_mismatch", "receipt does not match the charged delivery intent")
	capability._consume()
	_elapsed_minutes = capability._final_elapsed_minutes
	_committed_receipts.append(_receipt_facts(capability._day_index, capability._final_elapsed_minutes))
	_authoritative_delivery_binding = null
	_authoritative_delivery_issuer_identity = null
	_state = LifecycleState.DAY_COMMITTED
	return DomainResult.success(snapshot())

## Advances only from a committed day and never opens a sixth task day.
func advance_day() -> DomainResult:
	var initialized_result: DomainResult = _require_initialized()
	if not initialized_result.is_success():
		return initialized_result
	if _has_live_voluntary_transaction():
		return _reject(&"voluntary_transaction_locked", "day advance is unavailable while a voluntary run is live")
	if _state != LifecycleState.DAY_COMMITTED:
		return _reject(&"day_advance_unavailable", "only a committed day may advance")
	if _current_day_index == _day_count:
		_state = LifecycleState.CAREER_COMPLETE
		return DomainResult.success(snapshot())
	_current_day_index += 1
	_elapsed_minutes = 0
	_authoring_revision = 0
	_operational_authoring_revision = 0
	_overtime_authorized = false
	_retained_voluntary_report = {}
	_state = LifecycleState.REWORK_DUE if _scheduled_rework_minutes > 0 else LifecycleState.TASK_OPEN_REGULAR
	return DomainResult.success(snapshot())

## Schedules one policy-priced abstract block for the next playable day.
func schedule_next_day_rework(rework_minutes: int) -> DomainResult:
	var initialized_result: DomainResult = _require_initialized()
	if not initialized_result.is_success():
		return initialized_result
	if _state != LifecycleState.DAY_COMMITTED or _current_day_index >= _day_count:
		return _reject(&"rework_schedule_unavailable", "only a non-final committed day may schedule rework")
	if rework_minutes != _rework_minutes or _scheduled_rework_minutes != 0:
		return _reject(&"rework_schedule_invalid", "rework must be scheduled once at the admitted policy cost")
	_scheduled_rework_minutes = rework_minutes
	return DomainResult.success(snapshot())

## Completes the scheduled abstract block before the next task opens.
func complete_scheduled_rework() -> DomainResult:
	var initialized_result: DomainResult = _require_initialized()
	if not initialized_result.is_success():
		return initialized_result
	if _state != LifecycleState.REWORK_DUE or _scheduled_rework_minutes <= 0:
		return _reject(&"rework_completion_unavailable", "only one scheduled rework block may complete")
	if _elapsed_minutes > _regular_capacity_minutes - _scheduled_rework_minutes:
		return _reject(&"rework_capacity_invalid", "scheduled rework must fit the regular workday")
	_elapsed_minutes += _scheduled_rework_minutes
	_scheduled_rework_minutes = 0
	_state = LifecycleState.TASK_OPEN_REGULAR
	return DomainResult.success(snapshot())

## Returns the current authorized capacity or zero for an inert instance.
func authorized_capacity_minutes() -> int:
	if not _initialized:
		return 0
	return _regular_capacity_minutes + _overtime_additional_minutes if _overtime_authorized else _regular_capacity_minutes

## Returns the admitted fixed cost of one abstract rework block.
func rework_minutes() -> int:
	return _rework_minutes if _initialized else 0

## Returns a stable lifecycle state name, including the inert construction state.
func lifecycle_state_name() -> StringName:
	return &"uninitialized" if not _initialized else StringName(LifecycleState.keys()[_state].to_lower())

## Returns whether an optional action leaves the required delivery buffer.
## Validation occurs before subtraction, so no candidate addition can overflow.
static func fits_delivery_buffer(elapsed_minutes: int, action_cost_minutes: int, capacity_minutes: int) -> bool:
	if elapsed_minutes < 0 or action_cost_minutes <= 0 or capacity_minutes < _DELIVERY_BUFFER_MINUTES:
		return false
	if elapsed_minutes > _MAX_FINAL_ELAPSED_MINUTES or action_cost_minutes > _MAX_FINAL_ELAPSED_MINUTES or capacity_minutes > _MAX_FINAL_ELAPSED_MINUTES:
		return false
	var actionable_minutes: int = capacity_minutes - _DELIVERY_BUFFER_MINUTES
	if elapsed_minutes > actionable_minutes:
		return false
	return action_cost_minutes <= actionable_minutes - elapsed_minutes

## Returns validated minimal receipt facts for day 1..5 and final minutes 15..600.
static func receipt_facts_for_final_elapsed(day_index: int, final_elapsed_minutes: int) -> DomainResult:
	if day_index < _FIRST_DAY_INDEX or day_index > _EXPECTED_DAY_COUNT:
		return _reject(&"receipt_day_invalid", "receipt day index is outside the five-day lifecycle")
	if final_elapsed_minutes < _RECEIPT_COST_MINUTES or final_elapsed_minutes > _MAX_FINAL_ELAPSED_MINUTES:
		return _reject(&"receipt_elapsed_invalid", "receipt elapsed minutes are outside the authorized range")
	return DomainResult.success(_receipt_facts(day_index, final_elapsed_minutes))

func _initialize_from_admitted_policy(policy: CourseworkWorkdayPolicy, issuer: AcceptedOutcomeIssuer) -> DomainResult:
	if _initialized:
		return _reject(&"lifecycle_already_initialized", "lifecycle initialization occurs once")
	if policy == null or issuer == null:
		return _reject(&"policy_snapshot_unavailable", "an admitted policy snapshot and bound issuer are required")
	var policy_result: DomainResult = _extract_policy_values(policy.snapshot())
	if not policy_result.is_success():
		return policy_result
	var values: Dictionary[String, Variant] = policy_result.value()
	_regular_capacity_minutes = values["regular_capacity_minutes"]
	_overtime_additional_minutes = values["overtime_additional_minutes"]
	_optional_action_costs = values["optional_action_costs"].duplicate()
	_rework_minutes = values["rework_minutes"]
	_day_count = values["day_count"]
	_bound_issuer_identity = issuer._identity
	_bound_issuer = issuer
	_initialized = true
	return DomainResult.success(true)

func _apply_recovery_projection(
	stable_lifecycle: Variant,
	recovery_mode: int,
	voluntary_action: int,
	locked_binding: CourseworkRunInput,
	issuer: AcceptedOutcomeIssuer,
	charged_minutes: int,
	operational_authoring_revision: int
) -> DomainResult:
	if typeof(stable_lifecycle) != TYPE_DICTIONARY \
			or not CanonicalJsonIRType.validate_pure_json(stable_lifecycle).is_success():
		return _reject(&"workday_recovery_stable_state_invalid", "the stable recovery state must be pure data")
	var stable: Dictionary = stable_lifecycle
	var validation_result: DomainResult = _validate_recovery_stable_lifecycle(stable)
	if not validation_result.is_success():
		return validation_result
	var state_index: int = _lifecycle_state_from_recovery_name(String(stable["state"]))
	if state_index < 0:
		return _reject(&"workday_recovery_state_invalid", "the recovered lifecycle state is unsupported")
	var mode_validation: DomainResult = _validate_recovery_mode(
		state_index, recovery_mode, voluntary_action, locked_binding,
		int(stable["current_day_index"]), int(stable["authoring_revision"]),
		int(stable["elapsed_minutes"]), int(stable["authorized_capacity_minutes"]), charged_minutes)
	if not mode_validation.is_success():
		return mode_validation
	_current_day_index = int(stable["current_day_index"])
	_elapsed_minutes = int(stable["elapsed_minutes"])
	_authoring_revision = int(stable["authoring_revision"])
	_operational_authoring_revision = operational_authoring_revision \
		if recovery_mode == RECOVERY_MODE_NONE and operational_authoring_revision >= 0 \
		else _authoring_revision
	_overtime_authorized = bool(stable["overtime_authorized"])
	_scheduled_rework_minutes = int(stable["rework_due_minutes"])
	var restored_receipts: Array[Variant] = []
	for raw_receipt: Variant in Array(stable["committed_receipts"]):
		restored_receipts.append(Dictionary(raw_receipt).duplicate(true))
	_committed_receipts = restored_receipts
	_retained_voluntary_report = {}
	_state = state_index
	if recovery_mode == RECOVERY_MODE_VOLUNTARY_LOCKED:
		_voluntary_transaction_state = VoluntaryTransactionState.RECOVERABLE_INTERRUPTION
		_voluntary_binding = locked_binding
		_voluntary_binding_identity = _copy_binding_identity(locked_binding)
		_voluntary_binding_sha256 = locked_binding.identity_sha256()
		_voluntary_action = voluntary_action
		_voluntary_request_id = locked_binding.request_id()
		_record_current_voluntary_request()
	elif recovery_mode == RECOVERY_MODE_AUTHORITATIVE_LOCKED:
		_authoritative_delivery_binding = locked_binding
		_authoritative_delivery_issuer_identity = issuer._identity
	return DomainResult.success(snapshot())

func _validate_recovery_stable_lifecycle(stable: Dictionary) -> DomainResult:
	var shape_validation: DomainResult = _validate_recovery_stable_shape(stable)
	if not shape_validation.is_success():
		return shape_validation
	var type_validation: DomainResult = _validate_recovery_stable_types(stable)
	if not type_validation.is_success():
		return type_validation
	var policy_validation: DomainResult = _validate_recovery_stable_policy(stable)
	if not policy_validation.is_success():
		return policy_validation
	var receipt_validation: DomainResult = _validate_recovery_receipts(Array(stable["committed_receipts"]))
	if not receipt_validation.is_success():
		return receipt_validation
	var state_index: int = _lifecycle_state_from_recovery_name(String(stable["state"]))
	if state_index < 0:
		return _reject(&"workday_recovery_state_invalid", "the recovered lifecycle state is unsupported")
	var current_day_index: int = int(stable["current_day_index"])
	var elapsed_minutes: int = int(stable["elapsed_minutes"])
	var overtime_authorized: bool = bool(stable["overtime_authorized"])
	var receipt_state_validation: DomainResult = _validate_recovery_receipt_state(
		state_index, current_day_index, elapsed_minutes, Array(stable["committed_receipts"]))
	if not receipt_state_validation.is_success():
		return receipt_state_validation
	var rework_validation: DomainResult = _validate_recovery_rework(
		state_index, current_day_index, elapsed_minutes, overtime_authorized, int(stable["rework_due_minutes"]))
	if not rework_validation.is_success():
		return rework_validation
	if not _recovery_state_has_reachable_elapsed(
			state_index, elapsed_minutes, overtime_authorized, int(stable["rework_due_minutes"]), current_day_index):
		return _reject(&"workday_recovery_elapsed_invalid", "the recovered elapsed time is not reachable by fixed lifecycle mutations")
	if elapsed_minutes > _regular_capacity_minutes and not overtime_authorized:
		return _reject(&"workday_recovery_overtime_invalid", "elapsed overtime requires prior authorization")
	return DomainResult.success(true)

func _validate_recovery_stable_shape(stable: Dictionary) -> DomainResult:
	var fields: Array[String] = [
		"state", "current_day_index", "day_count", "elapsed_minutes",
		"authorized_capacity_minutes", "overtime_authorized", "authoring_revision",
		"rework_due_minutes", "committed_receipts",
	]
	if stable.size() != fields.size():
		return _reject(&"workday_recovery_stable_state_invalid", "the stable recovery state has an invalid shape")
	for field: String in fields:
		if not stable.has(field):
			return _reject(&"workday_recovery_stable_state_invalid", "the stable recovery state is incomplete")
	return DomainResult.success(true)

func _validate_recovery_stable_types(stable: Dictionary) -> DomainResult:
	if typeof(stable["state"]) != TYPE_STRING or typeof(stable["current_day_index"]) != TYPE_INT \
			or typeof(stable["day_count"]) != TYPE_INT or typeof(stable["elapsed_minutes"]) != TYPE_INT \
			or typeof(stable["authorized_capacity_minutes"]) != TYPE_INT:
		return _reject(&"workday_recovery_stable_state_invalid", "the stable recovery state has invalid field types")
	if typeof(stable["overtime_authorized"]) != TYPE_BOOL \
			or typeof(stable["authoring_revision"]) != TYPE_INT \
			or typeof(stable["rework_due_minutes"]) != TYPE_INT \
			or typeof(stable["committed_receipts"]) != TYPE_ARRAY:
		return _reject(&"workday_recovery_stable_state_invalid", "the stable recovery state has invalid field types")
	return DomainResult.success(true)

func _validate_recovery_stable_policy(stable: Dictionary) -> DomainResult:
	var expected_capacity: int = _regular_capacity_minutes + _overtime_additional_minutes \
		if bool(stable["overtime_authorized"]) else _regular_capacity_minutes
	if int(stable["current_day_index"]) < _FIRST_DAY_INDEX \
			or int(stable["current_day_index"]) > _day_count \
			or int(stable["day_count"]) != _day_count:
		return _reject(&"workday_recovery_stable_state_invalid", "the stable recovery facts violate the admitted policy")
	if int(stable["elapsed_minutes"]) < 0 \
			or int(stable["elapsed_minutes"]) > expected_capacity \
			or int(stable["authorized_capacity_minutes"]) != expected_capacity:
		return _reject(&"workday_recovery_stable_state_invalid", "the stable recovery facts violate the admitted policy")
	if int(stable["authoring_revision"]) < 0 or int(stable["rework_due_minutes"]) < 0:
		return _reject(&"workday_recovery_stable_state_invalid", "the stable recovery facts violate the admitted policy")
	return DomainResult.success(true)

func _validate_recovery_receipt_state(
	state_index: int,
	current_day_index: int,
	elapsed_minutes: int,
	receipts: Array[Variant]
) -> DomainResult:
	if not _recovery_receipt_state_matches(
			state_index, receipts.size(), current_day_index, elapsed_minutes, receipts):
		return _reject(&"workday_recovery_state_invalid", "the recovered receipt facts do not match lifecycle finality")
	return DomainResult.success(true)

func _validate_recovery_rework(
	state_index: int,
	current_day_index: int,
	elapsed_minutes: int,
	overtime_authorized: bool,
	rework_due_minutes: int
) -> DomainResult:
	var cost_validation: DomainResult = _validate_recovery_rework_cost(rework_due_minutes)
	if not cost_validation.is_success():
		return cost_validation
	var due_state_validation: DomainResult = _validate_recovery_rework_due_state(
		state_index, current_day_index, elapsed_minutes, overtime_authorized, rework_due_minutes)
	if not due_state_validation.is_success():
		return due_state_validation
	return _validate_recovery_rework_finality(state_index, current_day_index, rework_due_minutes)

func _validate_recovery_rework_cost(rework_due_minutes: int) -> DomainResult:
	if rework_due_minutes != 0 and rework_due_minutes != _rework_minutes:
		return _reject(&"workday_recovery_rework_invalid", "recovery rework must use the admitted policy cost")
	return DomainResult.success(true)

func _validate_recovery_rework_due_state(
	state_index: int,
	current_day_index: int,
	elapsed_minutes: int,
	overtime_authorized: bool,
	rework_due_minutes: int
) -> DomainResult:
	if state_index != LifecycleState.REWORK_DUE:
		return DomainResult.success(true)
	if current_day_index <= _FIRST_DAY_INDEX or rework_due_minutes != _rework_minutes \
			or elapsed_minutes != 0 or overtime_authorized:
		return _reject(&"workday_recovery_rework_invalid", "rework due must follow a committed day before its one regular-time block")
	return DomainResult.success(true)

func _validate_recovery_rework_finality(
	state_index: int, current_day_index: int, rework_due_minutes: int
) -> DomainResult:
	if state_index == LifecycleState.REWORK_DUE:
		return DomainResult.success(true)
	if rework_due_minutes != 0 and state_index != LifecycleState.DAY_COMMITTED:
		return _reject(&"workday_recovery_rework_invalid", "scheduled rework is only stable after receipt commit or before rework completion")
	if state_index == LifecycleState.DAY_COMMITTED and current_day_index >= _day_count \
			and rework_due_minutes != 0:
		return _reject(&"workday_recovery_rework_invalid", "a fifth-day receipt cannot schedule rework")
	if state_index == LifecycleState.CAREER_COMPLETE and rework_due_minutes != 0:
		return _reject(&"workday_recovery_rework_invalid", "career completion cannot schedule playable rework")
	return DomainResult.success(true)

func _validate_recovery_mode(
	state_index: int,
	recovery_mode: int,
	voluntary_action: int,
	locked_binding: CourseworkRunInput,
	current_day_index: int,
	authoring_revision: int,
	elapsed_minutes: int,
	authorized_capacity_minutes: int,
	charged_minutes: int
) -> DomainResult:
	if charged_minutes < -1:
		return _reject(&"workday_recovery_charge_invalid", "charged minutes cannot be negative")
	if recovery_mode == RECOVERY_MODE_NONE:
		if locked_binding != null or state_index == LifecycleState.SUBMISSION_IN_PROGRESS or charged_minutes > 0:
			return _reject(&"workday_recovery_mode_invalid", "unlocked restoration cannot retain a charged delivery")
		return DomainResult.success(true)
	if locked_binding == null or not locked_binding.is_valid() \
			or locked_binding.day_index() != current_day_index \
			or locked_binding.graph_revision() != authoring_revision:
		return _reject(&"workday_recovery_binding_invalid", "the recovered binding must match current Workday identity")
	if recovery_mode == RECOVERY_MODE_VOLUNTARY_LOCKED:
		if state_index != LifecycleState.TASK_OPEN_REGULAR \
			and state_index != LifecycleState.TASK_OPEN_OVERTIME:
			return _reject(&"workday_recovery_mode_invalid", "a voluntary recovery requires an open task state")
		var voluntary_validation: DomainResult = _validate_voluntary_binding(voluntary_action, locked_binding)
		if not voluntary_validation.is_success():
			return voluntary_validation
		var action_cost: int = _optional_action_costs[voluntary_action]
		if charged_minutes >= 0 and charged_minutes != action_cost:
			return _reject(&"workday_recovery_charge_invalid", "the voluntary recovery charge differs from the admitted policy")
		if elapsed_minutes < action_cost \
			or not _recovery_voluntary_charge_is_reachable(
				state_index, elapsed_minutes - action_cost, action_cost, authorized_capacity_minutes, current_day_index):
			return _reject(&"workday_recovery_charge_invalid", "the voluntary recovery elapsed time omits or exceeds its committed charge")
		return DomainResult.success(true)
	if recovery_mode == RECOVERY_MODE_AUTHORITATIVE_LOCKED:
		if state_index != LifecycleState.SUBMISSION_IN_PROGRESS or voluntary_action != -1:
			return _reject(&"workday_recovery_mode_invalid", "authoritative recovery requires the charged submission state")
		if charged_minutes >= 0 and charged_minutes != _RECEIPT_COST_MINUTES:
			return _reject(&"workday_recovery_charge_invalid", "the authoritative recovery charge differs from the admitted policy")
		return DomainResult.success(true) if _recovery_authoritative_charge_is_reachable(
			elapsed_minutes, authorized_capacity_minutes, current_day_index > _FIRST_DAY_INDEX) else _reject(
			&"workday_recovery_charge_invalid", "the authoritative recovery elapsed time omits its committed charge")
	return _reject(&"workday_recovery_mode_invalid", "the recovery mode is unsupported")

func _recovery_state_has_reachable_elapsed(
	state_index: int,
	elapsed_minutes: int,
	overtime_authorized: bool,
	rework_due_minutes: int,
	current_day_index: int
) -> bool:
	var recovery_capacity: int = _regular_capacity_minutes + _overtime_additional_minutes \
		if overtime_authorized else _regular_capacity_minutes
	var completed_rework_may_be_reflected: bool = current_day_index > _FIRST_DAY_INDEX \
		and state_index != LifecycleState.REWORK_DUE
	if state_index == LifecycleState.REWORK_DUE:
		return elapsed_minutes == 0 and not overtime_authorized and rework_due_minutes == _rework_minutes
	if state_index == LifecycleState.TASK_OPEN_REGULAR:
		return not overtime_authorized and rework_due_minutes == 0 \
			and _is_reachable_regular_open_elapsed(elapsed_minutes, completed_rework_may_be_reflected)
	if state_index == LifecycleState.REGULAR_DELIVERY_DECISION:
		return not overtime_authorized and rework_due_minutes == 0 \
			and _is_reachable_regular_open_elapsed(elapsed_minutes, completed_rework_may_be_reflected) \
			and not _has_fitting_optional_action_at(elapsed_minutes, _regular_capacity_minutes)
	if state_index == LifecycleState.TASK_OPEN_OVERTIME:
		return overtime_authorized and rework_due_minutes == 0 \
			and _is_reachable_overtime_open_elapsed(elapsed_minutes, completed_rework_may_be_reflected)
	if state_index == LifecycleState.FORCED_DELIVERY_PENDING \
			or state_index == LifecycleState.FORCED_DELIVERY_ACTIVATED:
		return overtime_authorized and rework_due_minutes == 0 \
			and _is_reachable_overtime_open_elapsed(elapsed_minutes, completed_rework_may_be_reflected) \
			and not _has_fitting_optional_action_at(
				elapsed_minutes, _regular_capacity_minutes + _overtime_additional_minutes)
	if state_index == LifecycleState.SUBMISSION_IN_PROGRESS:
		return rework_due_minutes == 0 and _recovery_authoritative_charge_is_reachable(
			elapsed_minutes, recovery_capacity, completed_rework_may_be_reflected)
	if state_index == LifecycleState.DAY_COMMITTED \
			or state_index == LifecycleState.CAREER_COMPLETE:
		return _is_reachable_authoritative_elapsed(
			elapsed_minutes, overtime_authorized, completed_rework_may_be_reflected)
	return false

func _recovery_voluntary_charge_is_reachable(
	state_index: int,
	elapsed_before_charge: int,
	action_cost: int,
	authorized_capacity_minutes: int,
	current_day_index: int
) -> bool:
	if not fits_delivery_buffer(elapsed_before_charge, action_cost, authorized_capacity_minutes):
		return false
	if state_index == LifecycleState.TASK_OPEN_REGULAR:
		return _is_reachable_regular_open_elapsed(elapsed_before_charge, current_day_index > _FIRST_DAY_INDEX)
	if state_index == LifecycleState.TASK_OPEN_OVERTIME:
		return _is_reachable_overtime_open_elapsed(elapsed_before_charge, current_day_index > _FIRST_DAY_INDEX)
	return false

func _recovery_authoritative_charge_is_reachable(
	elapsed_minutes: int, authorized_capacity_minutes: int, completed_rework_may_be_reflected: bool
) -> bool:
	if elapsed_minutes < _RECEIPT_COST_MINUTES or elapsed_minutes > authorized_capacity_minutes:
		return false
	return _is_reachable_authoritative_elapsed(
		elapsed_minutes,
		authorized_capacity_minutes > _regular_capacity_minutes,
		completed_rework_may_be_reflected)

func _is_reachable_authoritative_elapsed(
	elapsed_minutes: int, overtime_authorized: bool, completed_rework_may_be_reflected: bool
) -> bool:
	var elapsed_before_charge: int = elapsed_minutes - _RECEIPT_COST_MINUTES
	if overtime_authorized:
		return _is_reachable_overtime_open_elapsed(elapsed_before_charge, completed_rework_may_be_reflected)
	return _is_reachable_regular_open_elapsed(elapsed_before_charge, completed_rework_may_be_reflected)

func _is_reachable_regular_open_elapsed(elapsed_minutes: int, completed_rework_may_be_reflected: bool) -> bool:
	var optional_capacity: int = _regular_capacity_minutes - _DELIVERY_BUFFER_MINUTES
	if _is_reachable_optional_elapsed(elapsed_minutes, 0, optional_capacity):
		return true
	return completed_rework_may_be_reflected \
		and _is_reachable_optional_elapsed(
			elapsed_minutes - _rework_minutes, 0, optional_capacity - _rework_minutes)

func _is_reachable_overtime_open_elapsed(elapsed_minutes: int, completed_rework_may_be_reflected: bool) -> bool:
	for boundary_elapsed: int in range(_regular_capacity_minutes + 1):
		if _is_reachable_regular_open_elapsed(boundary_elapsed, completed_rework_may_be_reflected) \
				and not _has_fitting_optional_action_at(boundary_elapsed, _regular_capacity_minutes) \
				and _is_reachable_optional_elapsed(elapsed_minutes - boundary_elapsed, 0,
					_regular_capacity_minutes + _overtime_additional_minutes - _DELIVERY_BUFFER_MINUTES):
			return true
	return false

func _is_reachable_optional_elapsed(elapsed_minutes: int, minimum_minutes: int, maximum_minutes: int) -> bool:
	if elapsed_minutes < minimum_minutes or elapsed_minutes > maximum_minutes:
		return false
	for suite_count: int in range(int(elapsed_minutes / _optional_action_costs[OptionalAction.VOLUNTARY_SUITE]) + 1):
		var remaining_minutes: int = elapsed_minutes - suite_count * _optional_action_costs[OptionalAction.VOLUNTARY_SUITE]
		if remaining_minutes >= 0 and remaining_minutes % _optional_action_costs[OptionalAction.TARGETED_CASE] == 0:
			return true
	return false

func _has_fitting_optional_action_at(elapsed_minutes: int, capacity_minutes: int) -> bool:
	for action_cost: int in _optional_action_costs:
		if fits_delivery_buffer(elapsed_minutes, action_cost, capacity_minutes):
			return true
	return false

func _validate_recovery_receipts(receipts: Array) -> DomainResult:
	var expected_day_index: int = _FIRST_DAY_INDEX
	for raw_receipt: Variant in receipts:
		if typeof(raw_receipt) != TYPE_DICTIONARY \
			or not CanonicalJsonIRType.validate_pure_json(raw_receipt).is_success():
			return _reject(&"workday_recovery_receipt_invalid", "a recovered receipt is not pure data")
		var receipt: Dictionary = raw_receipt
		var fields: Array[String] = ["day_index", "final_elapsed_minutes", "overtime_minutes", "overtime_used"]
		if receipt.size() != fields.size():
			return _reject(&"workday_recovery_receipt_invalid", "a recovered receipt has an invalid shape")
		for field: String in fields:
			if not receipt.has(field):
				return _reject(&"workday_recovery_receipt_invalid", "a recovered receipt is incomplete")
		if typeof(receipt["day_index"]) != TYPE_INT \
			or typeof(receipt["final_elapsed_minutes"]) != TYPE_INT \
			or typeof(receipt["overtime_minutes"]) != TYPE_INT \
			or typeof(receipt["overtime_used"]) != TYPE_BOOL:
			return _reject(&"workday_recovery_receipt_invalid", "a recovered receipt has invalid field types")
		var day_index: int = int(receipt["day_index"])
		var final_elapsed: int = int(receipt["final_elapsed_minutes"])
		var overtime_minutes: int = int(receipt["overtime_minutes"])
		var expected_overtime: int = maxi(0, final_elapsed - _REGULAR_CAPACITY_MINUTES)
		if day_index != expected_day_index or day_index < _FIRST_DAY_INDEX or day_index > _EXPECTED_DAY_COUNT \
			or final_elapsed < _RECEIPT_COST_MINUTES or final_elapsed > _MAX_FINAL_ELAPSED_MINUTES \
			or not _is_reachable_authoritative_elapsed(
				final_elapsed, final_elapsed > _regular_capacity_minutes, day_index > _FIRST_DAY_INDEX) \
			or overtime_minutes != expected_overtime or bool(receipt["overtime_used"]) != (expected_overtime > 0):
			return _reject(&"workday_recovery_receipt_invalid", "a recovered receipt violates Workday finality facts")
		expected_day_index += 1
	return DomainResult.success(true)

func _recovery_receipt_state_matches(
	state_index: int,
	receipt_count: int,
	current_day_index: int,
	elapsed_minutes: int,
	receipts: Array
) -> bool:
	if state_index == LifecycleState.DAY_COMMITTED:
		if receipt_count != current_day_index or receipts.is_empty():
			return false
		var final_receipt: Dictionary = receipts[receipt_count - 1]
		return int(final_receipt["day_index"]) == current_day_index \
			and int(final_receipt["final_elapsed_minutes"]) == elapsed_minutes
	if state_index == LifecycleState.CAREER_COMPLETE:
		if receipt_count != _EXPECTED_DAY_COUNT or current_day_index != _EXPECTED_DAY_COUNT:
			return false
		var final_receipt: Dictionary = receipts[receipt_count - 1]
		return int(final_receipt["day_index"]) == _EXPECTED_DAY_COUNT \
			and int(final_receipt["final_elapsed_minutes"]) == elapsed_minutes
	return receipt_count == current_day_index - 1

static func _lifecycle_state_from_recovery_name(value: String) -> int:
	var names: Array = LifecycleState.keys()
	for index: int in names.size():
		if value == String(names[index]).to_lower():
			return index
	return -1

func _validate_receipt_capability(capability: AcceptedOutcomeCapability) -> DomainResult:
	if not _initialized:
		return _reject(&"lifecycle_uninitialized", "open an admitted policy before issuing commands")
	if capability == null or capability._consumed:
		return _reject(&"accepted_outcome_consumed", "accepted outcome capability must be unused")
	if _authoritative_delivery_binding == null \
			or _state != LifecycleState.SUBMISSION_IN_PROGRESS:
		return _reject(&"authoritative_delivery_commit_unavailable", "a charged authoritative delivery intent is required")
	if capability._issuer_identity != _authoritative_delivery_issuer_identity:
		return _reject(&"accepted_outcome_issuer_mismatch", "accepted outcome issuer is not bound to this delivery intent")
	if not _can_commit_receipt() or capability._day_index != _current_day_index:
		return _reject(&"receipt_commit_unavailable", "receipt capability does not match the active delivery boundary")
	if capability._final_elapsed_minutes < _RECEIPT_COST_MINUTES or capability._final_elapsed_minutes > authorized_capacity_minutes():
		return _reject(&"receipt_capacity_exceeded", "receipt elapsed minutes exceed authorized capacity")
	if capability._final_elapsed_minutes != _elapsed_minutes:
		return _reject(&"receipt_elapsed_mismatch", "receipt elapsed minutes must equal the current charge")
	return DomainResult.success(true)

static func _extract_policy_values(snapshot: Dictionary[String, Variant]) -> DomainResult:
	if snapshot.is_empty() or not snapshot.has("action_cost_minutes") or not snapshot.has("career_days"):
		return _reject(&"policy_snapshot_unavailable", "an admitted policy snapshot is required")
	if typeof(snapshot["action_cost_minutes"]) != TYPE_DICTIONARY or typeof(snapshot["career_days"]) != TYPE_ARRAY:
		return _reject(&"policy_snapshot_invalid", "admitted policy snapshot has an invalid shape")
	var actions: Dictionary[String, Variant] = snapshot["action_cost_minutes"]
	var days: Array[Variant] = snapshot["career_days"]
	if not _has_valid_policy_values(snapshot, actions, days):
		return _reject(&"policy_snapshot_invalid", "admitted policy does not contain lifecycle values")
	var costs: Array[int] = [actions["targeted_case"], actions["voluntary_suite"]]
	var values: Dictionary[String, Variant] = {
		"regular_capacity_minutes": snapshot["regular_capacity_minutes"],
		"overtime_additional_minutes": snapshot["overtime_capacity_minutes"],
		"optional_action_costs": costs,
		"rework_minutes": actions["rework"],
		"day_count": days.size(),
	}
	return DomainResult.success(values)

static func _has_valid_policy_values(snapshot: Dictionary[String, Variant], actions: Dictionary[String, Variant], days: Array[Variant]) -> bool:
	if typeof(snapshot.get("regular_capacity_minutes")) != TYPE_INT or typeof(snapshot.get("overtime_capacity_minutes")) != TYPE_INT:
		return false
	if not actions.has("targeted_case") or not actions.has("voluntary_suite") or not actions.has("rework"):
		return false
	if typeof(actions["targeted_case"]) != TYPE_INT or typeof(actions["voluntary_suite"]) != TYPE_INT or typeof(actions["rework"]) != TYPE_INT:
		return false
	return snapshot["regular_capacity_minutes"] == _REGULAR_CAPACITY_MINUTES and snapshot["overtime_capacity_minutes"] == 120 and actions["targeted_case"] == 20 and actions["voluntary_suite"] == 45 and actions["rework"] == 60 and days.size() == _EXPECTED_DAY_COUNT

func _optional_action_cost(action: int) -> DomainResult:
	if action < OptionalAction.TARGETED_CASE or action > OptionalAction.VOLUNTARY_SUITE:
		return _reject(&"optional_action_unknown", "optional action is not supported by the lifecycle")
	return DomainResult.success(_optional_action_costs[action])

func _has_fitting_optional_action() -> bool:
	for action_cost: int in _optional_action_costs:
		if fits_delivery_buffer(_elapsed_minutes, action_cost, authorized_capacity_minutes()):
			return true
	return false

func _has_live_voluntary_transaction() -> bool:
	return _voluntary_transaction_state == VoluntaryTransactionState.ACTIVE \
		or _voluntary_transaction_state == VoluntaryTransactionState.RECOVERABLE_INTERRUPTION

func _validate_voluntary_binding(action: int, binding: CourseworkRunInput) -> DomainResult:
	if action < OptionalAction.TARGETED_CASE or action > OptionalAction.VOLUNTARY_SUITE:
		return _reject(&"voluntary_action_invalid", "voluntary action is not supported")
	if binding == null or not binding.is_valid():
		return _reject(&"voluntary_binding_invalid", "a valid immutable public Run input is required")
	var case_count: int = binding.case_roster().size()
	if action == OptionalAction.TARGETED_CASE and case_count != 1:
		return _reject(&"voluntary_targeted_binding_invalid", "a targeted run binds exactly one public case")
	if action == OptionalAction.VOLUNTARY_SUITE and case_count < 2:
		return _reject(&"voluntary_suite_binding_invalid", "a voluntary suite binds the complete ordered public roster")
	return DomainResult.success(true)

func _copy_binding_identity(binding: CourseworkRunInput) -> Dictionary[String, Variant]:
	var source: Dictionary = binding.identity()
	var copy: Dictionary[String, Variant] = {}
	for raw_key: Variant in source.keys():
		if typeof(raw_key) != TYPE_STRING:
			return {}
		copy[String(raw_key)] = source[raw_key]
	return copy

func _record_current_voluntary_request() -> void:
	if _voluntary_request_id.is_empty() or _voluntary_binding_identity.is_empty() \
			or _voluntary_action < OptionalAction.TARGETED_CASE:
		return
	var action_cost: DomainResult = _optional_action_cost(_voluntary_action)
	if not action_cost.is_success():
		return
	_voluntary_request_records[_voluntary_request_id] = {
		"request_id": _voluntary_request_id,
		"identity_sha256": _voluntary_binding_sha256,
		"binding_identity": _voluntary_binding_identity.duplicate(true),
		"action_id": _voluntary_action,
		"action": StringName(OptionalAction.keys()[_voluntary_action].to_lower()),
		"charged": {
			"action_cost_minutes": int(action_cost.value()),
			"elapsed_minutes_after_charge": _elapsed_minutes,
		},
		"state": StringName(VoluntaryTransactionState.keys()[_voluntary_transaction_state].to_lower()),
		"is_live": _has_live_voluntary_transaction(),
	}

func _copy_request_status(record: Dictionary) -> Dictionary[String, Variant]:
	var copy: Dictionary[String, Variant] = {}
	for raw_key: Variant in record.keys():
		if typeof(raw_key) != TYPE_STRING:
			return {}
		copy[String(raw_key)] = record[raw_key]
	return copy.duplicate(true)

func _typed_string_variant_dictionary(value: Variant) -> Dictionary[String, Variant]:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	return _copy_request_status(Dictionary(value))

func _is_task_open() -> bool:
	return _state == LifecycleState.TASK_OPEN_REGULAR or _state == LifecycleState.REGULAR_DELIVERY_DECISION or _state == LifecycleState.TASK_OPEN_OVERTIME

func _is_regular_open_state() -> bool:
	return _state == LifecycleState.TASK_OPEN_REGULAR or _state == LifecycleState.REGULAR_DELIVERY_DECISION

func _can_commit_receipt() -> bool:
	return _is_task_open() or _state == LifecycleState.FORCED_DELIVERY_ACTIVATED \
		or _state == LifecycleState.SUBMISSION_IN_PROGRESS

func _can_begin_authoritative_delivery() -> bool:
	return _is_task_open() or _state == LifecycleState.FORCED_DELIVERY_ACTIVATED

func _require_initialized() -> DomainResult:
	return DomainResult.success(true) if _initialized else _reject(&"lifecycle_uninitialized", "open an admitted policy before issuing commands")

static func _receipt_facts(day_index: int, final_elapsed_minutes: int) -> Dictionary[String, Variant]:
	var overtime_minutes: int = maxi(0, final_elapsed_minutes - _REGULAR_CAPACITY_MINUTES)
	return {"day_index": day_index, "final_elapsed_minutes": final_elapsed_minutes, "overtime_minutes": overtime_minutes, "overtime_used": overtime_minutes > 0}

static func _reject(error_code: StringName, message: String) -> DomainResult:
	return DomainResult.failure(error_code, message, "workday.lifecycle")
