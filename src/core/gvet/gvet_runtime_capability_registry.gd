## Process-local authority registry for runtime-owned GVET capabilities.
## Serialized correlations never resolve authority; authorization requires the exact
## live reference and a complete matching owner-local binding.
## Single-thread-only: the owning runtime mutation lane serializes every call.
class_name GvetRuntimeCapabilityRegistry
extends RefCounted

const CODEC = preload("res://src/foundation/canonical_codec.gd")

const ACTIVE_STATE: String = "active"
const SPECIALIZED_STATE: String = "specialized"
const REPLAY_ONLY_STATE: String = "replay_only"
const REVOKED_STATE: String = "revoked"
const TARGET_INGRESS_KIND: String = "runtime_ingress_adapter_capability_v1"

const AUTHORIZED: StringName = &"authorized"
const UNAUTHORIZED: StringName = &"unauthorized"
const INVALIDATED: StringName = &"invalidated"
const BINDING_MISMATCH: StringName = &"binding_mismatch"
const INVALID_REQUEST: StringName = &"invalid_request"
const COMMITTED: StringName = &"committed"
const ALREADY_REVOKED: StringName = &"already_revoked"
const ALREADY_ROTATED: StringName = &"already_rotated"
const REVOKED_THEN_CLEARED: StringName = &"revoked_then_cleared"
const REVOKED_CLEAR_FAILED: StringName = &"revoked_clear_failed"
const ILLEGAL_TRANSITION: StringName = &"illegal_transition"
const REENTRANT_REJECTED: StringName = &"reentrant_rejected"


## Opaque runtime-owned authority shell. Its projection is correlation only.
class RuntimeCapability extends RefCounted:
	var _sealed: bool = false:
		set(value):
			if not _sealed:
				_sealed = value
	var _valid: bool = false:
		set(value):
			if not _sealed:
				_valid = value
	var _handle_id: String = "":
		set(value):
			if not _sealed:
				_handle_id = value
	var _capability_kind: String = "":
		set(value):
			if not _sealed:
				_capability_kind = value
	var _issued_generation: int = -1:
		set(value):
			if not _sealed:
				_issued_generation = value

	func _init(handle_id: String = "", capability_kind: String = "", issued_generation: int = -1) -> void:
		_handle_id = handle_id
		_capability_kind = capability_kind
		_issued_generation = issued_generation
		_valid = not handle_id.is_empty() and not capability_kind.is_empty() and issued_generation >= 0
		_sealed = true

	func is_well_formed() -> bool:
		return _sealed and _valid

	func correlation() -> Dictionary:
		return {
			"capability_kind": _capability_kind,
			"handle_id": _handle_id,
			"issued_generation": _issued_generation,
		}


## Immutable complete binding expected by one runtime capability operation.
class CapabilityExpectation extends RefCounted:
	var _sealed: bool = false:
		set(value):
			if not _sealed:
				_sealed = value
	var _valid: bool = false:
		set(value):
			if not _sealed:
				_valid = value
	var _owner_id: String = "":
		set(value):
			if not _sealed:
				_owner_id = value
	var _capability_kind: String = "":
		set(value):
			if not _sealed:
				_capability_kind = value
	var _identity: Dictionary = {}:
		get:
			return _identity.duplicate(true)
		set(value):
			if not _sealed:
				_identity = value.duplicate(true)
	var _identity_sha256: String = "":
		set(value):
			if not _sealed:
				_identity_sha256 = value
	var _operation: String = "":
		set(value):
			if not _sealed:
				_operation = value
	var _reservation_handle_id: String = "":
		set(value):
			if not _sealed:
				_reservation_handle_id = value
	var _queue_epoch: int = -1:
		set(value):
			if not _sealed:
				_queue_epoch = value
	var _generation: int = -1:
		set(value):
			if not _sealed:
				_generation = value

	static func create(
		owner_id: String,
		capability_kind: String,
		identity: Dictionary,
		operation: String,
		reservation_handle_id: String,
		queue_epoch: int,
		generation: int
	) -> CapabilityExpectation:
		return CapabilityExpectation.new(
			owner_id,
			capability_kind,
			identity,
			operation,
			reservation_handle_id,
			queue_epoch,
			generation
		)

	func _init(
		owner_id: String = "",
		capability_kind: String = "",
		identity: Dictionary = {},
		operation: String = "",
		reservation_handle_id: String = "",
		queue_epoch: int = -1,
		generation: int = -1
	) -> void:
		_owner_id = owner_id
		_capability_kind = capability_kind
		_identity = identity.duplicate(true)
		_identity_sha256 = _digest_identity(_identity)
		_operation = operation
		_reservation_handle_id = reservation_handle_id
		_queue_epoch = queue_epoch
		_generation = generation
		_valid = (
			not owner_id.is_empty()
			and not capability_kind.is_empty()
			and capability_kind != TARGET_INGRESS_KIND
			and not _identity_sha256.is_empty()
			and not operation.is_empty()
			and not reservation_handle_id.is_empty()
			and queue_epoch >= 0
			and generation >= 0
		)
		_sealed = true

	func is_valid() -> bool:
		return _sealed and _valid

	func owner_id() -> String:
		return _owner_id

	func capability_kind() -> String:
		return _capability_kind

	func identity() -> Dictionary:
		return _identity.duplicate(true)

	func identity_sha256() -> String:
		return _identity_sha256

	func operation() -> String:
		return _operation

	func reservation_handle_id() -> String:
		return _reservation_handle_id

	func queue_epoch() -> int:
		return _queue_epoch

	func generation() -> int:
		return _generation

	static func _digest_identity(value: Dictionary) -> String:
		if value.is_empty():
			return ""
		var encoded: RefCounted = CODEC.encode(value)
		if encoded == null or not encoded.is_success():
			return ""
		return CODEC.sha256_hex(PackedByteArray(encoded.value()))


## Immutable per-call target-owned binding returned only by the external broker.
class TargetCallBinding extends RefCounted:
	var _sealed: bool = false:
		set(value):
			if not _sealed:
				_sealed = value
	var _valid: bool = false:
		set(value):
			if not _sealed:
				_valid = value
	var _identity: Dictionary = {}:
		get:
			return _identity.duplicate(true)
		set(value):
			if not _sealed:
				_identity = value.duplicate(true)
	var _identity_sha256: String = "":
		set(value):
			if not _sealed:
				_identity_sha256 = value
	var _session_id: String = "":
		set(value):
			if not _sealed:
				_session_id = value
	var _adapter_id: String = "":
		set(value):
			if not _sealed:
				_adapter_id = value
	var _sandbox_id: String = "":
		set(value):
			if not _sealed:
				_sandbox_id = value
	var _queue_epoch: int = -1:
		set(value):
			if not _sealed:
				_queue_epoch = value
	var _operation: String = "":
		set(value):
			if not _sealed:
				_operation = value
	var _generation: int = -1:
		set(value):
			if not _sealed:
				_generation = value

	func _init(
		identity: Dictionary = {},
		session_id: String = "",
		adapter_id: String = "",
		sandbox_id: String = "",
		queue_epoch: int = -1,
		operation: String = "",
		generation: int = -1
	) -> void:
		_identity = identity.duplicate(true)
		_identity_sha256 = _digest_identity(_identity)
		_session_id = session_id
		_adapter_id = adapter_id
		_sandbox_id = sandbox_id
		_queue_epoch = queue_epoch
		_operation = operation
		_generation = generation
		_valid = (
			not _identity_sha256.is_empty()
			and not session_id.is_empty()
			and not adapter_id.is_empty()
			and not sandbox_id.is_empty()
			and queue_epoch >= 0
			and not operation.is_empty()
			and generation >= 0
		)
		_sealed = true

	func is_valid() -> bool:
		return _sealed and _valid

	func matches(request: TargetAuthenticationRequest) -> bool:
		return (
			is_valid()
			and request != null
			and request.is_valid()
			and _identity_sha256 == request.identity_sha256()
			and _identity == request.identity()
			and _session_id == request.session_id()
			and _adapter_id == request.adapter_id()
			and _sandbox_id == request.sandbox_id()
			and _queue_epoch == request.queue_epoch()
			and _operation == request.operation()
			and _generation == request.generation()
		)

	func projection() -> Dictionary:
		return {
			"capability_kind": TARGET_INGRESS_KIND,
			"identity": _identity.duplicate(true),
			"identity_sha256": _identity_sha256,
			"session_id": _session_id,
			"adapter_id": _adapter_id,
			"sandbox_id": _sandbox_id,
			"queue_epoch": _queue_epoch,
			"operation": _operation,
			"generation": _generation,
		}

	static func _digest_identity(value: Dictionary) -> String:
		if value.is_empty():
			return ""
		var encoded: RefCounted = CODEC.encode(value)
		if encoded == null or not encoded.is_success():
			return ""
		return CODEC.sha256_hex(PackedByteArray(encoded.value()))


## Immutable request passed to the target-owned authentication port.
class TargetAuthenticationRequest extends RefCounted:
	var _sealed: bool = false:
		set(value):
			if not _sealed:
				_sealed = value
	var _binding: TargetCallBinding:
		set(value):
			if not _sealed:
				_binding = value

	func _init(
		identity: Dictionary = {},
		session_id: String = "",
		adapter_id: String = "",
		sandbox_id: String = "",
		queue_epoch: int = -1,
		operation: String = "",
		generation: int = -1
	) -> void:
		_binding = TargetCallBinding.new(
			identity, session_id, adapter_id, sandbox_id, queue_epoch, operation, generation
		)
		_sealed = true

	func is_valid() -> bool:
		return _sealed and _binding != null and _binding.is_valid()

	func identity() -> Dictionary:
		return _binding.projection().get("identity", {}).duplicate(true) if is_valid() else {}

	func identity_sha256() -> String:
		return String(_binding.projection().get("identity_sha256", "")) if is_valid() else ""

	func session_id() -> String:
		return String(_binding.projection().get("session_id", "")) if is_valid() else ""

	func adapter_id() -> String:
		return String(_binding.projection().get("adapter_id", "")) if is_valid() else ""

	func sandbox_id() -> String:
		return String(_binding.projection().get("sandbox_id", "")) if is_valid() else ""

	func queue_epoch() -> int:
		return int(_binding.projection().get("queue_epoch", -1)) if is_valid() else -1

	func operation() -> String:
		return String(_binding.projection().get("operation", "")) if is_valid() else ""

	func generation() -> int:
		return int(_binding.projection().get("generation", -1)) if is_valid() else -1


## Target-owned port. Runtime can request authentication but owns no issuer methods.
class TargetIngressCapabilityBrokerPort extends RefCounted:
	func authenticate(
		_capability: RefCounted,
		_request: TargetAuthenticationRequest
	) -> TargetCallBinding:
		return null


## Typed cleanup port invoked only after every requested runtime authority is revoked.
class OwnedStateClearPort extends RefCounted:
	func clear_owned_state() -> bool:
		return false


## Closed immutable authorization result. It exposes a detached binding only.
class AuthorizationResult extends RefCounted:
	var _sealed: bool = false:
		set(value):
			if not _sealed:
				_sealed = value
	var _authorized: bool = false:
		set(value):
			if not _sealed:
				_authorized = value
	var _disposition: StringName = INVALID_REQUEST:
		set(value):
			if not _sealed:
				_disposition = value
	var _binding: Dictionary = {}:
		get:
			return _binding.duplicate(true)
		set(value):
			if not _sealed:
				_binding = value.duplicate(true)

	func _init(authorized: bool = false, disposition: StringName = INVALID_REQUEST, binding: Dictionary = {}) -> void:
		_authorized = authorized
		_disposition = disposition
		_binding = binding.duplicate(true)
		_sealed = true

	func is_authorized() -> bool:
		return _sealed and _authorized

	func is_closed() -> bool:
		return _sealed and _disposition != &""

	func disposition() -> StringName:
		return _disposition

	func binding() -> Dictionary:
		return _binding.duplicate(true) if _authorized else {}


## Closed result for registry lifecycle operations.
class MutationResult extends RefCounted:
	var _sealed: bool = false:
		set(value):
			if not _sealed:
				_sealed = value
	var _accepted: bool = false:
		set(value):
			if not _sealed:
				_accepted = value
	var _mutated: bool = false:
		set(value):
			if not _sealed:
				_mutated = value
	var _clear_succeeded: bool = false:
		set(value):
			if not _sealed:
				_clear_succeeded = value
	var _disposition: StringName = INVALID_REQUEST:
		set(value):
			if not _sealed:
				_disposition = value
	var _capability: RuntimeCapability:
		set(value):
			if not _sealed:
				_capability = value

	func _init(
		accepted: bool = false,
		mutated: bool = false,
		disposition: StringName = INVALID_REQUEST,
		capability: RuntimeCapability = null,
		clear_succeeded: bool = false
	) -> void:
		_accepted = accepted
		_mutated = mutated
		_disposition = disposition
		_capability = capability
		_clear_succeeded = clear_succeeded
		_sealed = true

	func is_accepted() -> bool:
		return _sealed and _accepted

	func is_closed() -> bool:
		return _sealed and _disposition != &""

	func did_mutate() -> bool:
		return _sealed and _mutated

	func disposition() -> StringName:
		return _disposition

	func capability() -> RuntimeCapability:
		return _capability if _accepted else null

	func clear_succeeded() -> bool:
		return _clear_succeeded


var _sealed: bool = false:
	set(value):
		if not _sealed:
			_sealed = value
var _store_dispatch: Callable:
	set(value):
		if not _sealed:
			_store_dispatch = value


## Creates one owner-local registry.
## Example: `var registry := GvetRuntimeCapabilityRegistry.create("session-owner")`.
static func create(owner_id: String):
	if owner_id.is_empty():
		return null
	var registry = new()
	var store_state: Dictionary = {
		"owner_id": owner_id,
		"records": [],
		"next_handle_sequence": 1,
		"revision": 0,
		"mutation_active": false,
	}
	registry._store_dispatch = func(action: String, arguments: Array) -> Variant:
		return _dispatch_store(store_state, action, arguments)
	registry._sealed = true
	return registry


## Issues one runtime-owned capability. The target ingress kind is always rejected.
## Example: `var capability := registry.issue_runtime(expectation)`.
func issue_runtime(expectation: CapabilityExpectation) -> RuntimeCapability:
	if not _has_store():
		return null
	return _store_dispatch.call("issue", [expectation]) as RuntimeCapability


## Authenticates only an exact live runtime-owned reference and complete binding.
## Example: `var result := registry.authorize_runtime(capability, expectation)`.
func authorize_runtime(
	capability: RuntimeCapability,
	expectation: CapabilityExpectation
) -> AuthorizationResult:
	if not _has_store():
		return AuthorizationResult.new(false, INVALID_REQUEST)
	var result := _store_dispatch.call("authorize", [capability, expectation]) as AuthorizationResult
	return result if result != null else AuthorizationResult.new(false, INVALID_REQUEST)


## Moves a live runtime capability to a narrower lifecycle state.
## Example: `registry.transition_runtime(capability, expectation, "specialized")`.
func transition_runtime(
	capability: RuntimeCapability,
	expectation: CapabilityExpectation,
	next_state: String
) -> MutationResult:
	if not _has_store():
		return MutationResult.new(false, false, INVALID_REQUEST)
	var result := _store_dispatch.call(
		"transition", [capability, expectation, next_state]
	) as MutationResult
	return result if result != null else MutationResult.new(false, false, INVALID_REQUEST)


## Revokes one exact runtime authority. Exact duplicate revocation is idempotent.
## Example: `registry.revoke_runtime(capability, expectation)`.
func revoke_runtime(
	capability: RuntimeCapability,
	expectation: CapabilityExpectation
) -> MutationResult:
	if not _has_store():
		return MutationResult.new(false, false, INVALID_REQUEST)
	var result := _store_dispatch.call("revoke", [capability, expectation]) as MutationResult
	return result if result != null else MutationResult.new(false, false, INVALID_REQUEST)


## Atomically revokes an old runtime authority and issues its next generation.
## Example: `var rotated := registry.rotate_runtime(capability, expectation, next)`.
func rotate_runtime(
	capability: RuntimeCapability,
	expectation: CapabilityExpectation,
	next_expectation: CapabilityExpectation
) -> MutationResult:
	if not _has_store():
		return MutationResult.new(false, false, INVALID_REQUEST)
	var result := _store_dispatch.call(
		"rotate", [capability, expectation, next_expectation]
	) as MutationResult
	return result if result != null else MutationResult.new(false, false, INVALID_REQUEST)


## Revokes the complete validated set before invoking the owned-state clear port.
## A clear failure is a committed quarantined lifecycle outcome, not an auth reject.
## Example: `registry.revoke_before_clear(capabilities, bindings, clear_port)`.
func revoke_before_clear(
	capabilities: Array[RuntimeCapability],
	expectations: Array[CapabilityExpectation],
	clear_port: OwnedStateClearPort
) -> MutationResult:
	if not _has_store():
		return MutationResult.new(false, false, INVALID_REQUEST)
	var result := _store_dispatch.call(
		"revoke_before_clear", [capabilities, expectations, clear_port]
	) as MutationResult
	return result if result != null else MutationResult.new(false, false, INVALID_REQUEST)


## Authenticates target-owned ingress for this call through its broker only.
## The returned detached binding cannot authorize a later call.
## Example: `registry.authenticate_target_for_call(broker, target_ref, request)`.
func authenticate_target_for_call(
	broker: TargetIngressCapabilityBrokerPort,
	target_capability: RefCounted,
	request: TargetAuthenticationRequest
) -> AuthorizationResult:
	if broker == null or target_capability == null or request == null or not request.is_valid():
		return AuthorizationResult.new(false, INVALID_REQUEST)
	var binding := broker.authenticate(target_capability, request)
	if binding == null:
		return AuthorizationResult.new(false, UNAUTHORIZED)
	if not binding.matches(request):
		return AuthorizationResult.new(false, BINDING_MISMATCH)
	return AuthorizationResult.new(true, AUTHORIZED, binding.projection())


## Returns a non-authorizing mutation counter for deterministic no-mutation tests.
## Example: `var before := registry.revision()`.
func revision() -> int:
	return int(_store_dispatch.call("revision", [])) if _has_store() else -1


## Returns registry cardinalities without exposing authority references.
## Example: `var count := registry.active_capability_count()`.
func active_capability_count() -> int:
	return int(_store_dispatch.call("active_count", [])) if _has_store() else 0


func _has_store() -> bool:
	return _sealed and _store_dispatch.is_valid()


static func _dispatch_store(state: Dictionary, action: String, arguments: Array) -> Variant:
	match action:
		"issue":
			return _store_issue(state, arguments[0] as CapabilityExpectation) if arguments.size() == 1 else null
		"authorize":
			return _store_authorize(state, arguments[0] as RuntimeCapability, arguments[1] as CapabilityExpectation) if arguments.size() == 2 else AuthorizationResult.new(false, INVALID_REQUEST)
		"transition":
			return _store_transition(state, arguments[0] as RuntimeCapability, arguments[1] as CapabilityExpectation, String(arguments[2])) if arguments.size() == 3 else MutationResult.new(false, false, INVALID_REQUEST)
		"revoke":
			return _store_revoke(state, arguments[0] as RuntimeCapability, arguments[1] as CapabilityExpectation) if arguments.size() == 2 else MutationResult.new(false, false, INVALID_REQUEST)
		"rotate":
			return _store_rotate(state, arguments[0] as RuntimeCapability, arguments[1] as CapabilityExpectation, arguments[2] as CapabilityExpectation) if arguments.size() == 3 else MutationResult.new(false, false, INVALID_REQUEST)
		"revoke_before_clear":
			return _store_revoke_before_clear(state, arguments) if arguments.size() == 3 else MutationResult.new(false, false, INVALID_REQUEST)
		"revision":
			return int(state["revision"])
		"active_count":
			return _active_record_count(state)
	return null


static func _store_issue(state: Dictionary, expectation: CapabilityExpectation) -> RuntimeCapability:
	if bool(state["mutation_active"]) or not _valid_owner_expectation(state, expectation):
		return null
	var records: Array = state["records"]
	var exact_record := _find_record_by_binding(records, expectation)
	if not exact_record.is_empty():
		return exact_record["capability"] as RuntimeCapability if _record_authorizes(exact_record) else null
	if not _find_lineage_record(records, expectation).is_empty():
		return null
	return _append_record(state, expectation)


static func _store_authorize(
	state: Dictionary,
	capability: RuntimeCapability,
	expectation: CapabilityExpectation
) -> AuthorizationResult:
	if capability == null or expectation == null or not expectation.is_valid():
		return AuthorizationResult.new(false, INVALID_REQUEST)
	var record := _find_record_by_capability(state["records"], capability)
	if record.is_empty():
		return AuthorizationResult.new(false, UNAUTHORIZED)
	if String(record["state"]) == REVOKED_STATE:
		return AuthorizationResult.new(false, INVALIDATED)
	if not _record_matches(record, expectation):
		return AuthorizationResult.new(false, BINDING_MISMATCH)
	if not _record_authorizes(record):
		return AuthorizationResult.new(false, INVALIDATED)
	return AuthorizationResult.new(true, AUTHORIZED, _binding_projection(record))


static func _store_transition(
	state: Dictionary,
	capability: RuntimeCapability,
	expectation: CapabilityExpectation,
	next_state: String
) -> MutationResult:
	if bool(state["mutation_active"]):
		return MutationResult.new(false, false, REENTRANT_REJECTED)
	var authorization := _store_authorize(state, capability, expectation)
	if not authorization.is_authorized():
		return MutationResult.new(false, false, authorization.disposition())
	var record := _find_record_by_capability(state["records"], capability)
	if not _is_legal_transition(String(record["state"]), next_state):
		return MutationResult.new(false, false, ILLEGAL_TRANSITION)
	record["state"] = next_state
	state["revision"] = int(state["revision"]) + 1
	return MutationResult.new(true, true, COMMITTED, capability)


static func _store_revoke(
	state: Dictionary,
	capability: RuntimeCapability,
	expectation: CapabilityExpectation
) -> MutationResult:
	if bool(state["mutation_active"]):
		return MutationResult.new(false, false, REENTRANT_REJECTED)
	var record := _find_record_by_capability(state["records"], capability)
	if not record.is_empty() and String(record["state"]) == REVOKED_STATE and _record_matches(record, expectation):
		return MutationResult.new(true, false, ALREADY_REVOKED)
	var authorization := _store_authorize(state, capability, expectation)
	if not authorization.is_authorized():
		return MutationResult.new(false, false, authorization.disposition())
	record["state"] = REVOKED_STATE
	state["revision"] = int(state["revision"]) + 1
	return MutationResult.new(true, true, COMMITTED)


static func _store_rotate(
	state: Dictionary,
	capability: RuntimeCapability,
	expectation: CapabilityExpectation,
	next_expectation: CapabilityExpectation
) -> MutationResult:
	if bool(state["mutation_active"]):
		return MutationResult.new(false, false, REENTRANT_REJECTED)
	if expectation == null or next_expectation == null or not next_expectation.is_valid():
		return MutationResult.new(false, false, INVALID_REQUEST)
	var records: Array = state["records"]
	var current_record := _find_record_by_capability(records, capability)
	if not current_record.is_empty() and String(current_record["state"]) == REVOKED_STATE:
		var existing_next := _find_record_by_binding(records, next_expectation)
		if _record_matches(current_record, expectation) and not existing_next.is_empty() and _valid_successor(expectation, next_expectation):
			return MutationResult.new(true, false, ALREADY_ROTATED, existing_next["capability"] as RuntimeCapability)
	var authorization := _store_authorize(state, capability, expectation)
	if not authorization.is_authorized():
		return MutationResult.new(false, false, authorization.disposition())
	if not _valid_successor(expectation, next_expectation):
		return MutationResult.new(false, false, BINDING_MISMATCH)
	if not _find_record_by_binding(records, next_expectation).is_empty():
		return MutationResult.new(false, false, BINDING_MISMATCH)
	state["mutation_active"] = true
	current_record["state"] = REVOKED_STATE
	var replacement := _append_record(state, next_expectation, false)
	state["revision"] = int(state["revision"]) + 1
	state["mutation_active"] = false
	return MutationResult.new(true, true, COMMITTED, replacement)


static func _store_revoke_before_clear(state: Dictionary, arguments: Array) -> MutationResult:
	if bool(state["mutation_active"]):
		return MutationResult.new(false, false, REENTRANT_REJECTED)
	var capabilities: Array = arguments[0]
	var expectations: Array = arguments[1]
	var clear_port := arguments[2] as OwnedStateClearPort
	if capabilities.is_empty() or capabilities.size() != expectations.size() or clear_port == null:
		return MutationResult.new(false, false, INVALID_REQUEST)
	var records_to_revoke: Array[Dictionary] = []
	for index in capabilities.size():
		var capability := capabilities[index] as RuntimeCapability
		var expectation := expectations[index] as CapabilityExpectation
		var authorization := _store_authorize(state, capability, expectation)
		if not authorization.is_authorized():
			return MutationResult.new(false, false, authorization.disposition())
		var record := _find_record_by_capability(state["records"], capability)
		if records_to_revoke.has(record):
			return MutationResult.new(false, false, INVALID_REQUEST)
		records_to_revoke.append(record)
	state["mutation_active"] = true
	for record in records_to_revoke:
		record["state"] = REVOKED_STATE
	state["revision"] = int(state["revision"]) + 1
	var cleared := clear_port.clear_owned_state()
	state["mutation_active"] = false
	return MutationResult.new(true, true, REVOKED_THEN_CLEARED if cleared else REVOKED_CLEAR_FAILED, null, cleared)


static func _valid_owner_expectation(state: Dictionary, expectation: CapabilityExpectation) -> bool:
	return (
		expectation != null
		and expectation.is_valid()
		and expectation.owner_id() == String(state["owner_id"])
		and expectation.capability_kind() != TARGET_INGRESS_KIND
	)


static func _append_record(
	state: Dictionary,
	expectation: CapabilityExpectation,
	advance_revision: bool = true
) -> RuntimeCapability:
	var sequence := int(state["next_handle_sequence"])
	var capability := RuntimeCapability.new(
		"%s-runtime-capability-%d" % [String(state["owner_id"]), sequence],
		expectation.capability_kind(),
		expectation.generation()
	)
	var records: Array = state["records"]
	records.append({
		"capability": capability,
		"binding": _snapshot_expectation(expectation),
		"state": ACTIVE_STATE,
	})
	state["next_handle_sequence"] = sequence + 1
	if advance_revision:
		state["revision"] = int(state["revision"]) + 1
	return capability


static func _snapshot_expectation(expectation: CapabilityExpectation) -> Dictionary:
	return {
		"owner_id": expectation.owner_id(),
		"capability_kind": expectation.capability_kind(),
		"identity": expectation.identity(),
		"identity_sha256": expectation.identity_sha256(),
		"operation": expectation.operation(),
		"reservation_handle_id": expectation.reservation_handle_id(),
		"queue_epoch": expectation.queue_epoch(),
		"generation": expectation.generation(),
	}


static func _find_record_by_capability(records: Array, capability: RuntimeCapability) -> Dictionary:
	for record_value in records:
		var record: Dictionary = record_value
		if record["capability"] == capability:
			return record
	return {}


static func _find_record_by_binding(records: Array, expectation: CapabilityExpectation) -> Dictionary:
	for record_value in records:
		var record: Dictionary = record_value
		if _record_matches(record, expectation):
			return record
	return {}


static func _find_lineage_record(records: Array, expectation: CapabilityExpectation) -> Dictionary:
	for record_value in records:
		var record: Dictionary = record_value
		if _binding_same_lineage(record["binding"], expectation):
			return record
	return {}


static func _record_matches(record: Dictionary, expectation: CapabilityExpectation) -> bool:
	if record.is_empty() or expectation == null or not expectation.is_valid():
		return false
	var binding: Dictionary = record["binding"]
	return _binding_same_lineage(binding, expectation) and int(binding["generation"]) == expectation.generation()


static func _binding_same_lineage(binding: Dictionary, expectation: CapabilityExpectation) -> bool:
	return (
		String(binding["owner_id"]) == expectation.owner_id()
		and String(binding["capability_kind"]) == expectation.capability_kind()
		and String(binding["identity_sha256"]) == expectation.identity_sha256()
		and binding["identity"] == expectation.identity()
		and String(binding["operation"]) == expectation.operation()
		and String(binding["reservation_handle_id"]) == expectation.reservation_handle_id()
		and int(binding["queue_epoch"]) == expectation.queue_epoch()
	)


static func _record_authorizes(record: Dictionary) -> bool:
	return String(record["state"]) in [ACTIVE_STATE, SPECIALIZED_STATE, REPLAY_ONLY_STATE]


static func _binding_projection(record: Dictionary) -> Dictionary:
	var projection: Dictionary = (record["binding"] as Dictionary).duplicate(true)
	projection["lifecycle_state"] = String(record["state"])
	return projection


static func _active_record_count(state: Dictionary) -> int:
	var count: int = 0
	for record_value in state["records"]:
		if _record_authorizes(record_value):
			count += 1
	return count


static func _valid_successor(
	current: CapabilityExpectation,
	next: CapabilityExpectation
) -> bool:
	return _is_same_binding_except_generation(current, next) and next.generation() == current.generation() + 1


static func _is_legal_transition(current_state: String, next_state: String) -> bool:
	if current_state == ACTIVE_STATE:
		return next_state == SPECIALIZED_STATE or next_state == REPLAY_ONLY_STATE
	if current_state == SPECIALIZED_STATE:
		return next_state == REPLAY_ONLY_STATE
	return false


static func _is_same_binding_except_generation(
	current: CapabilityExpectation,
	next: CapabilityExpectation
) -> bool:
	return (
		current.owner_id() == next.owner_id()
		and current.capability_kind() == next.capability_kind()
		and current.identity_sha256() == next.identity_sha256()
		and current.identity() == next.identity()
		and current.operation() == next.operation()
		and current.reservation_handle_id() == next.reservation_handle_id()
		and current.queue_epoch() == next.queue_epoch()
	)
