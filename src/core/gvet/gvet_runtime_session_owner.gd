## Session-scoped sole writer for serialized GVET runtime and reservation transitions.
## Commands run synchronously on the creating thread; published snapshots are immutable.
class_name GvetRuntimeSessionOwner
extends RefCounted

const OCCUPANCY_STATE = preload("res://src/core/gvet/runtime_occupancy_state.gd")
const SESSION_SNAPSHOT = preload("res://src/core/gvet/runtime_session_snapshot.gd")
const MUTATION_COMMAND = preload("res://src/core/gvet/runtime_mutation_command.gd")
const MUTATION_RECEIPT = preload("res://src/core/gvet/runtime_mutation_receipt.gd")
const JOINT_RESERVATION = preload("res://src/core/gvet/gvet_joint_reservation.gd")
const ADMISSION_PORTS = preload("res://src/core/gvet/gvet_admission_ports.gd")
const DOMAIN_RESULT = preload("res://src/foundation/domain_result.gd")


## Immutable post-commit value passed to the injected synchronous port.
class RuntimePostCommitNotification:
	extends RefCounted
	var _sealed: bool = false:
		set(value):
			if not _sealed:
				_sealed = value
	var _snapshot_value: RuntimeSessionSnapshot:
		set(value):
			if not _sealed:
				_snapshot_value = value
	var _receipt_value: RuntimeMutationReceipt:
		set(value):
			if not _sealed:
				_receipt_value = value
	var _valid: bool = false:
		set(value):
			if not _sealed:
				_valid = value

	func _init(snapshot_value: RuntimeSessionSnapshot = null, receipt_value: RuntimeMutationReceipt = null) -> void:
		if _corresponds(snapshot_value, receipt_value):
			_snapshot_value = snapshot_value.duplicate_snapshot()
			_receipt_value = receipt_value
			_valid = true
		_sealed = true

	func snapshot() -> RuntimeSessionSnapshot:
		return _snapshot_value.duplicate_snapshot() if _valid else null

	func receipt() -> RuntimeMutationReceipt:
		return _receipt_value if _valid else null

	func is_valid() -> bool:
		return _valid and _sealed

	static func _corresponds(snapshot_value: RuntimeSessionSnapshot, receipt_value: RuntimeMutationReceipt) -> bool:
		if snapshot_value == null or not snapshot_value.is_valid() or receipt_value == null or not receipt_value.is_exact_commit():
			return false
		if receipt_value.state_root() != snapshot_value.state_root() or receipt_value.generation() != snapshot_value.generation():
			return false
		if receipt_value.commit_id() != snapshot_value.last_commit_id():
			return false
		var correlations: PackedStringArray = snapshot_value.correlation_ids()
		return correlations.size() == 2 and correlations[0] == receipt_value.command_id() and correlations[1] == receipt_value.idempotency_key()


## Pure production port; tests may inject a typed subclass.
class RuntimeNotificationPort:
	extends RefCounted

	## Publishes one immutable value. Example: `GvetRuntimeSessionOwner.create(vector, test_port)`.
	func publish(_notification: RuntimePostCommitNotification) -> void:
		return


class RuntimeJournalEntry:
	extends RefCounted
	var _fingerprint: String = ""
	var _receipt: RuntimeMutationReceipt
	var _valid: bool = false

	func _init(fingerprint: String = "", receipt: RuntimeMutationReceipt = null) -> void:
		if fingerprint.is_empty() or receipt == null or not receipt.is_closed():
			return
		_fingerprint = fingerprint
		_receipt = receipt
		_valid = true

	func fingerprint() -> String:
		return _fingerprint

	func receipt() -> RuntimeMutationReceipt:
		return _receipt if _valid else null

	func is_valid() -> bool:
		return _valid


class RuntimeConflictJournal:
	extends RefCounted
	var _entries: Array[RuntimeJournalEntry] = []

	func find(fingerprint: String) -> RuntimeJournalEntry:
		for entry: RuntimeJournalEntry in _entries:
			if entry.fingerprint() == fingerprint:
				return entry
		return null

	func add(entry: RuntimeJournalEntry) -> void:
		if entry != null and entry.is_valid() and find(entry.fingerprint()) == null:
			_entries.append(entry)

	func size() -> int:
		return _entries.size()


## Owner-internal accepted-resolution delivery authority created with a grant.
class AcceptedResolutionDeliveryCapability extends RefCounted:
	var _sealed: bool = false:
		set(value):
			if not _sealed:
				_sealed = value
	var _handle_id: String = "":
		set(value):
			if not _sealed:
				_handle_id = value
	var _reservation_handle_id: String = "":
		set(value):
			if not _sealed:
				_reservation_handle_id = value
	var _identity_sha256: String = "":
		set(value):
			if not _sealed:
				_identity_sha256 = value
	var _issued_generation: int = -1:
		set(value):
			if not _sealed:
				_issued_generation = value

	func _init(handle_id: String = "", reservation_handle_id: String = "", identity_sha256: String = "", issued_generation: int = -1) -> void:
		_handle_id = handle_id
		_reservation_handle_id = reservation_handle_id
		_identity_sha256 = identity_sha256
		_issued_generation = issued_generation
		_sealed = not handle_id.is_empty() and not reservation_handle_id.is_empty() and not identity_sha256.is_empty() and issued_generation >= 0

	func is_valid() -> bool:
		return _sealed

	func projection() -> Dictionary:
		return {
			"capability_kind": "accepted_resolution_delivery",
			"resolution_delivery_handle_id": _handle_id,
			"reservation_handle_id": _reservation_handle_id,
			"authoring_request_sha256": _identity_sha256,
			"issued_generation": _issued_generation,
			"registered": is_valid(),
		}


## Owner-internal immutable cleanup-cell generation record.
class CleanupIntentCell extends RefCounted:
	var _sealed: bool = false:
		set(value):
			if not _sealed:
				_sealed = value
	var _cell_id: String = "":
		set(value):
			if not _sealed:
				_cell_id = value
	var _reservation_handle_id: String = "":
		set(value):
			if not _sealed:
				_reservation_handle_id = value
	var _identity_sha256: String = "":
		set(value):
			if not _sealed:
				_identity_sha256 = value
	var _generation: int = -1:
		set(value):
			if not _sealed:
				_generation = value
	var _state: String = "":
		set(value):
			if not _sealed:
				_state = value

	func _init(cell_id: String = "", reservation_handle_id: String = "", identity_sha256: String = "", generation: int = -1, state: String = "") -> void:
		_cell_id = cell_id
		_reservation_handle_id = reservation_handle_id
		_identity_sha256 = identity_sha256
		_generation = generation
		_state = state
		_sealed = not cell_id.is_empty() and not reservation_handle_id.is_empty() and not identity_sha256.is_empty() and generation >= 0 and state == "reserved_empty"

	func is_valid() -> bool:
		return _sealed

	func projection() -> Dictionary:
		return {
			"cleanup_cell_id": _cell_id,
			"reservation_handle_id": _reservation_handle_id,
			"authoring_request_sha256": _identity_sha256,
			"generation": _generation,
			"state": _state,
			"registered": is_valid(),
		}


## Immutable typed command for every reservation-generation mutation.
class ReservationMutationCommand extends RefCounted:
	const RESERVE_KIND: String = "reservation_grant"
	const SPECIALIZE_KIND: String = "reservation_specialization"
	const RECLASSIFY_KIND: String = "reservation_reclassification"
	const TOMBSTONE_KIND: String = "pending_to_tombstone"
	const CODEC = preload("res://src/foundation/canonical_codec.gd")

	var _sealed: bool = false:
		set(value):
			if not _sealed:
				_sealed = value
	var _operation_kind: String = "":
		set(value):
			if not _sealed:
				_operation_kind = value
	var _trusted_identity: Dictionary = {}:
		get:
			return _trusted_identity.duplicate(true)
		set(value):
			if not _sealed:
				_trusted_identity = value.duplicate(true)
	var _capability: GvetAdmissionPorts.ReservationCapability:
		set(value):
			if not _sealed:
				_capability = value
	var _expected_identity_sha256: String = "":
		set(value):
			if not _sealed:
				_expected_identity_sha256 = value
	var _expected_generation: int = -1:
		set(value):
			if not _sealed:
				_expected_generation = value
	var _expected_slot_kind: String = "":
		set(value):
			if not _sealed:
				_expected_slot_kind = value
	var _expected_bundle_sha256: String = "":
		set(value):
			if not _sealed:
				_expected_bundle_sha256 = value
	var _expected_runtime_generation: int = -1:
		set(value):
			if not _sealed:
				_expected_runtime_generation = value
	var _target_bundle_sha256: String = "":
		set(value):
			if not _sealed:
				_target_bundle_sha256 = value
	var _idempotency_key: String = "":
		set(value):
			if not _sealed:
				_idempotency_key = value
	var _fingerprint: String = "":
		set(value):
			if not _sealed:
				_fingerprint = value

	static func for_reserve(trusted_identity: Dictionary, expected_generation: int) -> ReservationMutationCommand:
		return ReservationMutationCommand.new(RESERVE_KIND, trusted_identity, null, "", expected_generation, "", "", "", -1)

	static func for_specialize(
		capability: GvetAdmissionPorts.ReservationCapability,
		identity_sha256: String,
		expected_generation: int,
		expected_slot_kind: String,
		expected_bundle_sha256: String,
		target_bundle_sha256: String
	) -> ReservationMutationCommand:
		return ReservationMutationCommand.new(SPECIALIZE_KIND, {}, capability, identity_sha256, expected_generation, expected_slot_kind, expected_bundle_sha256, target_bundle_sha256, -1)

	static func for_reclassify(
		capability: GvetAdmissionPorts.ReservationCapability,
		identity_sha256: String,
		expected_generation: int,
		expected_slot_kind: String,
		expected_bundle_sha256: String,
		expected_runtime_generation: int
	) -> ReservationMutationCommand:
		return ReservationMutationCommand.new(RECLASSIFY_KIND, {}, capability, identity_sha256, expected_generation, expected_slot_kind, expected_bundle_sha256, "", expected_runtime_generation)

	static func for_tombstone(
		capability: GvetAdmissionPorts.ReservationCapability,
		identity_sha256: String,
		expected_generation: int,
		expected_slot_kind: String,
		expected_bundle_sha256: String
	) -> ReservationMutationCommand:
		return ReservationMutationCommand.new(TOMBSTONE_KIND, {}, capability, identity_sha256, expected_generation, expected_slot_kind, expected_bundle_sha256, "", -1)

	func _init(
		operation_kind: String = "",
		trusted_identity: Dictionary = {},
		capability: GvetAdmissionPorts.ReservationCapability = null,
		expected_identity_sha256: String = "",
		expected_generation: int = -1,
		expected_slot_kind: String = "",
		expected_bundle_sha256: String = "",
		target_bundle_sha256: String = "",
		expected_runtime_generation: int = -1
	) -> void:
		_operation_kind = operation_kind
		_trusted_identity = trusted_identity
		_capability = capability
		_expected_identity_sha256 = expected_identity_sha256
		_expected_generation = expected_generation
		_expected_slot_kind = expected_slot_kind
		_expected_bundle_sha256 = expected_bundle_sha256
		_target_bundle_sha256 = target_bundle_sha256
		_expected_runtime_generation = expected_runtime_generation
		_idempotency_key = _make_idempotency_key()
		_fingerprint = _make_fingerprint()
		_sealed = true

	func is_valid() -> bool:
		if not _sealed or _expected_generation < 0 or _idempotency_key.is_empty() or _fingerprint.is_empty():
			return false
		if _operation_kind == RESERVE_KIND:
			return not _trusted_identity.is_empty()
		if _capability == null or not _capability.is_authorized() or _expected_identity_sha256.is_empty():
			return false
		var live_slot: bool = _expected_slot_kind == "current" or _expected_slot_kind == "pending"
		if not live_slot and not (_operation_kind == TOMBSTONE_KIND and _expected_slot_kind == "tombstone"):
			return false
		if _operation_kind == SPECIALIZE_KIND:
			return not _target_bundle_sha256.is_empty()
		if _operation_kind == RECLASSIFY_KIND:
			return _expected_runtime_generation >= 0
		return _operation_kind == TOMBSTONE_KIND

	func operation_kind() -> String:
		return _operation_kind

	func trusted_identity() -> Dictionary:
		return _trusted_identity.duplicate(true)

	func capability() -> GvetAdmissionPorts.ReservationCapability:
		return _capability

	func reservation_handle_id() -> String:
		return _capability.reservation_handle_id() if _capability != null else ""

	func expected_identity_sha256() -> String:
		return _expected_identity_sha256

	func expected_generation() -> int:
		return _expected_generation

	func expected_slot_kind() -> String:
		return _expected_slot_kind

	func expected_bundle_sha256() -> String:
		return _expected_bundle_sha256

	func expected_runtime_generation() -> int:
		return _expected_runtime_generation

	func target_bundle_sha256() -> String:
		return _target_bundle_sha256

	func idempotency_key() -> String:
		return _idempotency_key

	func fingerprint() -> String:
		return _fingerprint

	func _make_idempotency_key() -> String:
		if _operation_kind == RESERVE_KIND:
			for key: String in ["idempotency_key", "request_id", "authoring_request_sha256"]:
				if _trusted_identity.has(key) and not String(_trusted_identity[key]).is_empty():
					return String(_trusted_identity[key])
			return _canonical_digest(_trusted_identity)
		return _canonical_digest({
			"operation_kind": _operation_kind,
			"reservation_handle_id": reservation_handle_id(),
			"expected_generation": _expected_generation,
			"expected_runtime_generation": _expected_runtime_generation,
			"target_bundle_sha256": _target_bundle_sha256,
		})

	func _make_fingerprint() -> String:
		return _canonical_digest({
			"operation_kind": _operation_kind,
			"trusted_identity": _trusted_identity,
			"reservation_handle_id": reservation_handle_id(),
			"expected_identity_sha256": _expected_identity_sha256,
			"expected_generation": _expected_generation,
			"expected_slot_kind": _expected_slot_kind,
			"expected_bundle_sha256": _expected_bundle_sha256,
			"expected_runtime_generation": _expected_runtime_generation,
			"target_bundle_sha256": _target_bundle_sha256,
		})

	static func _canonical_digest(value: Dictionary) -> String:
		var encoded: RefCounted = CODEC.encode(value)
		if encoded == null or not encoded.is_success():
			return ""
		return CODEC.sha256_hex(PackedByteArray(encoded.value()))


## Immutable receipt journaled for one reservation command outcome.
class ReservationMutationReceipt extends RefCounted:
	const COMMITTED: StringName = &"committed"
	const REENTRANT_REJECTED: StringName = &"reentrant_rejected"
	const STALE_GENERATION: StringName = &"stale_generation"

	var _sealed: bool = false:
		set(value):
			if not _sealed:
				_sealed = value
	var _success: bool = false:
		set(value):
			if not _sealed:
				_success = value
	var _disposition: StringName = &"reservation_invalid":
		set(value):
			if not _sealed:
				_disposition = value
	var _message: String = "":
		set(value):
			if not _sealed:
				_message = value
	var _command_key: String = "":
		set(value):
			if not _sealed:
				_command_key = value
	var _command_fingerprint: String = "":
		set(value):
			if not _sealed:
				_command_fingerprint = value
	var _generation: int = -1:
		set(value):
			if not _sealed:
				_generation = value
	var _reservation_root: String = "":
		set(value):
			if not _sealed:
				_reservation_root = value
	var _handle_id: String = "":
		set(value):
			if not _sealed:
				_handle_id = value
	var _capability: GvetAdmissionPorts.ReservationCapability:
		set(value):
			if not _sealed:
				_capability = value
	var _transition_value: Dictionary = {}:
		get:
			return _transition_value.duplicate(true)
		set(value):
			if not _sealed:
				_transition_value = value.duplicate(true)

	static func committed_for(command: ReservationMutationCommand, transition: JOINT_RESERVATION.Transition, capability: GvetAdmissionPorts.ReservationCapability) -> ReservationMutationReceipt:
		var transition_value: Dictionary = transition.value()
		if command.operation_kind() == ReservationMutationCommand.RESERVE_KIND:
			transition_value = {}
		return ReservationMutationReceipt.new(true, COMMITTED, "", command, transition.next_state(), transition.handle_id(), capability, transition_value)

	static func rejected_for(command: ReservationMutationCommand, code: StringName, message: String, state: JOINT_RESERVATION.State) -> ReservationMutationReceipt:
		return ReservationMutationReceipt.new(false, code, message, command, state)

	func _init(
		success: bool = false,
		disposition: StringName = &"reservation_invalid",
		message: String = "",
		command: ReservationMutationCommand = null,
		state: JOINT_RESERVATION.State = null,
		handle_id: String = "",
		capability: GvetAdmissionPorts.ReservationCapability = null,
		transition_value: Dictionary = {}
	) -> void:
		_success = success
		_disposition = disposition
		_message = message
		_command_key = command.idempotency_key() if command != null else ""
		_command_fingerprint = command.fingerprint() if command != null else ""
		_generation = state.generation() if state != null else -1
		_reservation_root = String(state.generation_record().get("reservation_root_id", "")) if state != null else ""
		_handle_id = handle_id
		_capability = capability
		_transition_value = transition_value
		_sealed = true

	func is_success() -> bool:
		return _sealed and _success

	func is_closed() -> bool:
		return _sealed and not _command_key.is_empty() and not _command_fingerprint.is_empty() and _generation >= 0 and not _reservation_root.is_empty()

	func disposition() -> StringName:
		return _disposition

	func error_code() -> StringName:
		return &"" if _success else _disposition

	func error_message() -> String:
		return "" if _success else _message

	func command_key() -> String:
		return _command_key

	func command_fingerprint() -> String:
		return _command_fingerprint

	func generation() -> int:
		return _generation

	func reservation_root_id() -> String:
		return _reservation_root

	func reservation_handle_id() -> String:
		return _handle_id

	func capability() -> GvetAdmissionPorts.ReservationCapability:
		return _capability if _success else null

	func value() -> Variant:
		if not _success:
			return null
		if _capability != null and _transition_value.get("transition_kind", "") == "":
			return _capability
		return _transition_value.duplicate(true)

	func transition_value() -> Dictionary:
		return _transition_value.duplicate(true)

	func diagnostic() -> Dictionary:
		return {} if _success else {"discriminant": &"rejected", "cause": _disposition, "message": _message}

	func to_domain_result() -> DomainResult:
		return DOMAIN_RESULT.success(value()) if _success else DOMAIN_RESULT.failure(_disposition, _message)


class ReservationJournalEntry extends RefCounted:
	var _command: ReservationMutationCommand
	var _receipt: ReservationMutationReceipt

	func _init(command: ReservationMutationCommand, receipt: ReservationMutationReceipt) -> void:
		_command = command
		_receipt = receipt

	func is_valid() -> bool:
		return _command != null and _command.is_valid() and _receipt != null and _receipt.is_closed()

	func receipt() -> ReservationMutationReceipt:
		return _receipt if is_valid() else null

	func matches_semantic(command: ReservationMutationCommand) -> bool:
		if not is_valid() or command == null or not command.is_valid():
			return false
		if _command.operation_kind() != command.operation_kind():
			return false
		if command.operation_kind() == ReservationMutationCommand.RESERVE_KIND:
			return _command.trusted_identity() == command.trusted_identity()
		return _command.capability() == command.capability() and _command.reservation_handle_id() == command.reservation_handle_id() and _command.target_bundle_sha256() == command.target_bundle_sha256()

	func matches_fingerprint(command: ReservationMutationCommand) -> bool:
		return is_valid() and command != null and command.is_valid() and _command.capability() == command.capability() and _command.fingerprint() == command.fingerprint()

	func matches_exact_retry(command: ReservationMutationCommand) -> bool:
		if not is_valid() or command == null or not command.is_valid() or _command.operation_kind() != command.operation_kind():
			return false
		if command.operation_kind() == ReservationMutationCommand.RESERVE_KIND:
			return _command.trusted_identity() == command.trusted_identity()
		return matches_fingerprint(command)

	func matches_applied_retry(command: ReservationMutationCommand) -> bool:
		if not is_valid() or command == null or not command.is_valid() or not _receipt.is_success():
			return false
		if _command.operation_kind() != command.operation_kind() or _command.capability() != command.capability():
			return false
		return _command.reservation_handle_id() == command.reservation_handle_id() and _command.target_bundle_sha256() == command.target_bundle_sha256()


## Typed wrapper used by the one owner mailbox for both mutation families.
class OwnerMutationCommand extends RefCounted:
	const RUNTIME_KIND: String = "runtime"
	const RESERVATION_KIND: String = "reservation"
	var _kind: String = ""
	var _runtime_command: RuntimeMutationCommand
	var _reservation_command: ReservationMutationCommand

	static func for_runtime(command: RuntimeMutationCommand) -> OwnerMutationCommand:
		return OwnerMutationCommand.new(RUNTIME_KIND, command, null)

	static func for_reservation(command: ReservationMutationCommand) -> OwnerMutationCommand:
		return OwnerMutationCommand.new(RESERVATION_KIND, null, command)

	func _init(kind: String = "", runtime_command: RuntimeMutationCommand = null, reservation_command: ReservationMutationCommand = null) -> void:
		_kind = kind
		_runtime_command = runtime_command.duplicate_command() if runtime_command != null else null
		_reservation_command = reservation_command

	func is_valid() -> bool:
		if _kind == RUNTIME_KIND:
			return _runtime_command != null and _runtime_command.is_valid()
		return _kind == RESERVATION_KIND and _reservation_command != null and _reservation_command.is_valid()

	func kind() -> String:
		return _kind

	func runtime_command() -> RuntimeMutationCommand:
		return _runtime_command.duplicate_command() if _runtime_command != null else null

	func reservation_command() -> ReservationMutationCommand:
		return _reservation_command


class OwnerKernel extends GvetAdmissionPorts.PreliveReservationOwner:
	var _runtime_snapshot: RuntimeSessionSnapshot
	var _owner_mailbox: Array[OwnerMutationCommand] = []
	var _runtime_primary_journal: Dictionary = {}
	var _runtime_conflict_journal: Dictionary = {}
	var _reservation_primary_journal: Dictionary = {}
	var _reservation_conflict_journal: Dictionary = {}
	var _reservation_state: JOINT_RESERVATION.State
	var _reservation_registry: Dictionary = {}
	var _delivery_capability_registry: Dictionary = {}
	var _cleanup_cell_registry: Dictionary = {}
	var _commit_sequence: int = 0
	var _active_transition: bool = false
	var _last_notification: RuntimePostCommitNotification
	var _notification_port: RuntimeNotificationPort
	var _ready: bool = false

	func _init(initial_vector: PackedInt32Array = PackedInt32Array([0, 0, 0, 0]), notification_port: RuntimeNotificationPort = null, reservation_state: JOINT_RESERVATION.State = null) -> void:
		_notification_port = notification_port if notification_port != null else RuntimeNotificationPort.new()
		if reservation_state == null:
			_reservation_state = JOINT_RESERVATION.create()
		elif reservation_state.is_empty_seed():
			_reservation_state = JOINT_RESERVATION.create(
				reservation_state.base_ledger_entry_count(),
				reservation_state.base_ledger_byte_count(),
				reservation_state.capacity_limits()
			)
		else:
			return
		var initial_state: RuntimeOccupancyState = OCCUPANCY_STATE.from_vector(initial_vector)
		if initial_state == null or _reservation_state == null or not _reservation_state.is_valid():
			return
		_runtime_snapshot = SESSION_SNAPSHOT.create(initial_state, 0, "", PackedStringArray())
		_ready = _runtime_snapshot != null and _runtime_snapshot.is_valid()

	func is_ready() -> bool:
		return _ready

	func enqueue_runtime(command: RuntimeMutationCommand) -> bool:
		if not _ready or command == null or not command.is_valid() or _active_transition:
			return false
		var wrapped: OwnerMutationCommand = OwnerMutationCommand.for_runtime(command)
		if not wrapped.is_valid():
			return false
		_owner_mailbox.append(wrapped)
		return true

	func dequeue_and_reduce() -> RuntimeMutationReceipt:
		if not _ready or _active_transition or _owner_mailbox.is_empty():
			return null
		var wrapped: OwnerMutationCommand = _owner_mailbox.pop_front()
		if wrapped.kind() != OwnerMutationCommand.RUNTIME_KIND:
			return null
		_active_transition = true
		var receipt: RuntimeMutationReceipt = _reduce_runtime(wrapped.runtime_command())
		_active_transition = false
		return receipt

	func submit_runtime(command: RuntimeMutationCommand) -> RuntimeMutationReceipt:
		if command == null or not command.is_valid() or not _ready:
			return MUTATION_RECEIPT.invalid_command()
		var exact_retry: RuntimeMutationReceipt = _lookup_exact_runtime(command)
		if exact_retry != null:
			return exact_retry
		if _active_transition:
			return _reentrant_runtime_receipt(command)
		var known: RuntimeMutationReceipt = _lookup_runtime(command)
		if known != null:
			return known
		var wrapped: OwnerMutationCommand = OwnerMutationCommand.for_runtime(command)
		if not wrapped.is_valid():
			return MUTATION_RECEIPT.invalid_command()
		_owner_mailbox.append(wrapped)
		return _drain_until(wrapped) as RuntimeMutationReceipt

	func snapshot() -> RuntimeSessionSnapshot:
		return _runtime_snapshot.duplicate_snapshot() if _ready else null

	func generation() -> int:
		return _runtime_snapshot.generation() if _ready else -1

	func commit_count() -> int:
		return _commit_sequence

	func mailbox_size() -> int:
		return _owner_mailbox.size()

	func journal_size() -> int:
		var total: int = _runtime_primary_journal.size() + _reservation_primary_journal.size()
		for key: String in _runtime_conflict_journal.keys():
			var runtime_conflicts: RuntimeConflictJournal = _runtime_conflict_journal[key] as RuntimeConflictJournal
			if runtime_conflicts != null:
				total += runtime_conflicts.size()
		for key: String in _reservation_conflict_journal.keys():
			total += _reservation_conflicts_for_key(key).size()
		return total

	func reservation_journal_size() -> int:
		var total: int = _reservation_primary_journal.size()
		for key: String in _reservation_conflict_journal.keys():
			total += _reservation_conflicts_for_key(key).size()
		return total

	func is_transition_active() -> bool:
		return _active_transition

	func last_post_commit_notification() -> RuntimePostCommitNotification:
		return _last_notification

	func state_root() -> String:
		return _runtime_snapshot.state_root() if _ready else ""

	func runtime_mailbox_copy() -> Array[RuntimeMutationCommand]:
		var result: Array[RuntimeMutationCommand] = []
		for wrapped: OwnerMutationCommand in _owner_mailbox:
			if wrapped.kind() == OwnerMutationCommand.RUNTIME_KIND:
				var command: RuntimeMutationCommand = wrapped.runtime_command()
				if command != null:
					result.append(command)
		return result

	func runtime_journal_copy() -> Dictionary:
		var result: Dictionary = {}
		for key: String in _runtime_primary_journal.keys():
			var entry: RuntimeJournalEntry = _runtime_primary_journal[key] as RuntimeJournalEntry
			if entry != null and entry.is_valid():
				result[key] = entry.receipt()
		return result

	func reserve(trusted_identity: Dictionary) -> DomainResult:
		return reserve_receipt(trusted_identity).to_domain_result()

	func reserve_receipt(trusted_identity: Dictionary) -> ReservationMutationReceipt:
		var command: ReservationMutationCommand = ReservationMutationCommand.for_reserve(trusted_identity, _reservation_state.generation())
		return submit_reservation(command)

	func make_specialize_command(capability: GvetAdmissionPorts.ReservationCapability, bundle_sha256: String) -> ReservationMutationCommand:
		var entry: Dictionary = _registry_entry(capability)
		if entry.is_empty():
			return ReservationMutationCommand.new()
		return ReservationMutationCommand.for_specialize(capability, String(entry["identity_sha256"]), int(entry["generation"]), String(entry["slot_kind"]), String(entry["bundle_sha256"]), bundle_sha256)

	func make_reclassify_command(capability: GvetAdmissionPorts.ReservationCapability) -> ReservationMutationCommand:
		var entry: Dictionary = _registry_entry(capability)
		if entry.is_empty():
			return ReservationMutationCommand.new()
		return ReservationMutationCommand.for_reclassify(capability, String(entry["identity_sha256"]), int(entry["generation"]), String(entry["slot_kind"]), String(entry["bundle_sha256"]), _runtime_snapshot.generation())

	func make_tombstone_command(capability: GvetAdmissionPorts.ReservationCapability) -> ReservationMutationCommand:
		var entry: Dictionary = _registry_entry(capability)
		if entry.is_empty():
			return ReservationMutationCommand.new()
		return ReservationMutationCommand.for_tombstone(capability, String(entry["identity_sha256"]), int(entry["generation"]), String(entry["slot_kind"]), String(entry["bundle_sha256"]))

	func submit_reservation(command: ReservationMutationCommand) -> ReservationMutationReceipt:
		if command == null or not command.is_valid() or not _ready:
			return ReservationMutationReceipt.rejected_for(command, &"reservation_invalid", "reservation mutation command is invalid", _reservation_state)
		var exact: ReservationMutationReceipt = _lookup_exact_reservation(command)
		if exact != null:
			return exact
		var applied: ReservationMutationReceipt = _lookup_applied_reservation(command)
		if applied != null:
			return applied
		if _active_transition:
			return ReservationMutationReceipt.rejected_for(command, ReservationMutationReceipt.REENTRANT_REJECTED, "reservation mutation is already fenced", _reservation_state)
		var known: ReservationMutationReceipt = _lookup_reservation(command)
		if known != null:
			return known
		var wrapped: OwnerMutationCommand = OwnerMutationCommand.for_reservation(command)
		if not wrapped.is_valid():
			return ReservationMutationReceipt.rejected_for(command, &"reservation_invalid", "reservation mutation command is invalid", _reservation_state)
		_owner_mailbox.append(wrapped)
		return _drain_until(wrapped) as ReservationMutationReceipt

	func reservation_snapshot(capability: GvetAdmissionPorts.ReservationCapability) -> Dictionary:
		var entry: Dictionary = _registry_entry(capability)
		return _reservation_state.reservation_snapshot(String(entry.get("handle_id", ""))) if not entry.is_empty() else {}

	func reservation_companions(capability: GvetAdmissionPorts.ReservationCapability) -> Dictionary:
		var entry: Dictionary = _registry_entry(capability)
		if entry.is_empty():
			return {}
		var handle_id: String = String(entry["handle_id"])
		var delivery_entry: Dictionary = _delivery_capability_registry.get(handle_id, {}) as Dictionary
		var cell_entry: Dictionary = _cleanup_cell_registry.get(handle_id, {}) as Dictionary
		var delivery: AcceptedResolutionDeliveryCapability = delivery_entry.get("capability") as AcceptedResolutionDeliveryCapability
		var cell: CleanupIntentCell = cell_entry.get("cell") as CleanupIntentCell
		var record: JOINT_RESERVATION.ReservationState = _reservation_state.record_by_handle(handle_id)
		if delivery == null or not delivery.is_valid() or cell == null or not cell.is_valid() or record == null:
			return {}
		var delivery_projection: Dictionary = delivery.projection()
		delivery_projection["owner_generation"] = delivery_entry.get("generation", -1)
		var cell_projection: Dictionary = cell.projection()
		cell_projection["owner_generation"] = cell_entry.get("generation", -1)
		return {
			"delivery_companion": delivery_projection,
			"cleanup_cell": cell_projection,
			"quantity_manifest": record.quantity_manifest().to_dictionary(),
		}

	func reservation_registry_counts() -> Dictionary:
		return {
			"reservation_capabilities": _reservation_registry.size(),
			"delivery_capabilities": _delivery_capability_registry.size(),
			"cleanup_cells": _cleanup_cell_registry.size(),
		}

	func reservation_registry_record(capability: GvetAdmissionPorts.ReservationCapability) -> Dictionary:
		var entry: Dictionary = _registry_entry(capability)
		if entry.is_empty():
			return {}
		return {
			"reservation_handle_id": entry["handle_id"],
			"authoring_request_sha256": entry["identity_sha256"],
			"issued_generation": entry["issued_generation"],
			"issued_slot_kind": entry["issued_slot_kind"],
			"generation": entry["generation"],
			"slot_kind": entry["slot_kind"],
			"bundle_sha256": entry["bundle_sha256"],
			"active": entry["active"],
		}

	func reservation_generation_record() -> Dictionary:
		return _reservation_state.generation_record() if _ready else {}

	func reservation_ledger_root() -> String:
		return _reservation_state.ledger_root() if _ready else ""

	func _drain_until(target: OwnerMutationCommand) -> Variant:
		var target_result: Variant = null
		while not _owner_mailbox.is_empty():
			var wrapped: OwnerMutationCommand = _owner_mailbox.pop_front()
			_active_transition = true
			var outcome: Variant = _reduce_owner_command(wrapped)
			_active_transition = false
			if wrapped == target:
				target_result = outcome
				break
		return target_result

	func _reduce_owner_command(wrapped: OwnerMutationCommand) -> Variant:
		if wrapped.kind() == OwnerMutationCommand.RUNTIME_KIND:
			return _reduce_runtime(wrapped.runtime_command())
		return _reduce_reservation(wrapped.reservation_command())

	func _reduce_reservation(command: ReservationMutationCommand) -> ReservationMutationReceipt:
		if command.expected_generation() != _reservation_state.generation():
			return _record_stale_reservation(command, "reservation command targets a prior generation")
		var transition: JOINT_RESERVATION.Transition
		var capability: GvetAdmissionPorts.ReservationCapability
		if command.operation_kind() == ReservationMutationCommand.RESERVE_KIND:
			var occupancy: PackedInt32Array = _runtime_snapshot.get_occupancy_vector()
			transition = JOINT_RESERVATION.reserve(_reservation_state, command.trusted_identity(), occupancy[0] == 1, occupancy[1] == 1)
			if transition.is_success():
				capability = _capability_for_transition(transition)
		else:
			var authority_error: StringName = _validate_reservation_authority(command)
			if not authority_error.is_empty():
				if authority_error == ReservationMutationReceipt.STALE_GENERATION:
					return _record_stale_reservation(command, "reservation capability binding targets a prior generation")
				return _record_reservation(command, ReservationMutationReceipt.rejected_for(command, authority_error, "reservation capability binding is not current", _reservation_state))
			if command.operation_kind() == ReservationMutationCommand.SPECIALIZE_KIND:
				transition = JOINT_RESERVATION.specialize(_reservation_state, command.reservation_handle_id(), command.target_bundle_sha256())
			elif command.operation_kind() == ReservationMutationCommand.RECLASSIFY_KIND:
				if command.expected_runtime_generation() != _runtime_snapshot.generation():
					return _record_stale_reservation(command, "reservation command targets a prior runtime occupancy generation")
				transition = JOINT_RESERVATION.reclassify_pending_to_current(_reservation_state, command.reservation_handle_id(), _runtime_snapshot.get_occupancy_vector()[0] == 1)
			elif command.operation_kind() == ReservationMutationCommand.TOMBSTONE_KIND:
				transition = JOINT_RESERVATION.pending_to_tombstone(_reservation_state, command.reservation_handle_id())
			else:
				return _record_reservation(command, ReservationMutationReceipt.rejected_for(command, &"reservation_invalid", "unknown reservation mutation command", _reservation_state))
			capability = command.capability()
		if transition == null or not transition.is_success():
			var code: StringName = transition.error_code() if transition != null else &"reservation_invalid"
			var message: String = transition.message() if transition != null else "reservation transition is invalid"
			return _record_reservation(command, ReservationMutationReceipt.rejected_for(command, code, message, _reservation_state))
		var grant_bundle: Dictionary = {}
		if command.operation_kind() == ReservationMutationCommand.RESERVE_KIND:
			grant_bundle = _make_grant_registry_bundle(transition, capability)
			if grant_bundle.is_empty():
				return _record_reservation(command, ReservationMutationReceipt.rejected_for(command, &"reservation_invalid", "owner companion registration failed", _reservation_state))
		_reservation_state = transition.next_state()
		if command.operation_kind() == ReservationMutationCommand.RESERVE_KIND:
			_commit_grant_registry_bundle(grant_bundle)
		else:
			_update_registry_after_transition(transition, capability)
			_update_cleanup_cell_after_transition(transition)
		return _record_reservation(command, ReservationMutationReceipt.committed_for(command, transition, capability))

	func _make_grant_registry_bundle(transition: JOINT_RESERVATION.Transition, capability: GvetAdmissionPorts.ReservationCapability) -> Dictionary:
		var record: JOINT_RESERVATION.ReservationState = transition.next_state().record_by_handle(transition.handle_id())
		if record == null or capability == null or not capability.is_authorized() or _reservation_registry.has(record.handle_id()) or _delivery_capability_registry.has(record.handle_id()) or _cleanup_cell_registry.has(record.handle_id()):
			return {}
		var delivery := AcceptedResolutionDeliveryCapability.new(record.delivery_handle_id(), record.handle_id(), record.identity_sha256(), record.generation())
		var cell := CleanupIntentCell.new(record.cleanup_cell_id(), record.handle_id(), record.identity_sha256(), record.generation(), "reserved_empty")
		if not delivery.is_valid() or not cell.is_valid():
			return {}
		return {
			"handle_id": record.handle_id(),
			"reservation_entry": _reservation_registry_entry(record, capability),
			"delivery_entry": {"capability": delivery, "generation": record.generation(), "active": true},
			"cleanup_entry": {"cell": cell, "generation": record.generation(), "state": "reserved_empty"},
		}

	func _commit_grant_registry_bundle(bundle: Dictionary) -> void:
		var handle_id: String = String(bundle["handle_id"])
		_reservation_registry[handle_id] = bundle["reservation_entry"]
		_delivery_capability_registry[handle_id] = bundle["delivery_entry"]
		_cleanup_cell_registry[handle_id] = bundle["cleanup_entry"]

	func _reservation_registry_entry(record: JOINT_RESERVATION.ReservationState, capability: GvetAdmissionPorts.ReservationCapability) -> Dictionary:
		return {
			"capability": capability,
			"handle_id": record.handle_id(),
			"identity_sha256": record.identity_sha256(),
			"issued_generation": record.generation(),
			"issued_slot_kind": record.slot_kind(),
			"generation": record.generation(),
			"slot_kind": record.slot_kind(),
			"bundle_sha256": record.bundle_sha256(),
			"active": true,
		}

	func _update_cleanup_cell_after_transition(transition: JOINT_RESERVATION.Transition) -> void:
		var handle_id: String = transition.handle_id()
		var record: JOINT_RESERVATION.ReservationState = transition.next_state().record_by_handle(handle_id)
		var delivery_entry: Dictionary = _delivery_capability_registry.get(handle_id, {}) as Dictionary
		var cell_entry: Dictionary = _cleanup_cell_registry.get(handle_id, {}) as Dictionary
		var delivery: AcceptedResolutionDeliveryCapability = delivery_entry.get("capability") as AcceptedResolutionDeliveryCapability
		var cell: CleanupIntentCell = cell_entry.get("cell") as CleanupIntentCell
		if delivery == null or not delivery.is_valid() or cell == null or not cell.is_valid() or record == null:
			return
		_delivery_capability_registry[handle_id] = {"capability": delivery, "generation": record.generation(), "active": record.lifecycle_state() == JOINT_RESERVATION.LIVE_STATE}
		_cleanup_cell_registry[handle_id] = {"cell": cell, "generation": record.generation(), "state": "reserved_empty"}

	func _capability_for_transition(transition: JOINT_RESERVATION.Transition) -> GvetAdmissionPorts.ReservationCapability:
		var record: JOINT_RESERVATION.ReservationState = transition.next_state().record_by_handle(transition.handle_id())
		if record == null:
			return null
		var capability: GvetAdmissionPorts.ReservationCapability = ADMISSION_PORTS.ReservationCapability.issue_joint(record.handle_id(), record.identity_sha256(), record.slot_kind(), record.generation())
		return capability if capability != null and capability.is_authorized() else null

	func _update_registry_after_transition(transition: JOINT_RESERVATION.Transition, capability: GvetAdmissionPorts.ReservationCapability) -> void:
		if capability == null:
			return
		var handle_id: String = transition.handle_id()
		var entry: Dictionary = _reservation_registry.get(handle_id, {}) as Dictionary
		var record: JOINT_RESERVATION.ReservationState = transition.next_state().record_by_handle(handle_id)
		if entry.is_empty() or record == null or entry.get("capability") != capability:
			return
		var replacement: Dictionary = entry.duplicate(true)
		replacement["capability"] = capability
		replacement["generation"] = record.generation()
		replacement["slot_kind"] = record.slot_kind()
		replacement["bundle_sha256"] = record.bundle_sha256()
		replacement["active"] = record.lifecycle_state() == JOINT_RESERVATION.LIVE_STATE
		_reservation_registry[handle_id] = replacement

	func _validate_reservation_authority(command: ReservationMutationCommand) -> StringName:
		var entry: Dictionary = _registry_entry(command.capability())
		if entry.is_empty() or entry.get("active", false) != true:
			return &"reservation_invalid"
		var record: JOINT_RESERVATION.ReservationState = _reservation_state.record_by_handle(command.reservation_handle_id())
		if record == null or record.lifecycle_state() != JOINT_RESERVATION.LIVE_STATE:
			return &"reservation_invalid"
		if command.expected_generation() != int(entry["generation"]) or command.expected_generation() != record.generation():
			return ReservationMutationReceipt.STALE_GENERATION
		if command.expected_identity_sha256() != String(entry["identity_sha256"]) or command.expected_identity_sha256() != record.identity_sha256():
			return &"reservation_invalid"
		if command.expected_slot_kind() != String(entry["slot_kind"]) or command.expected_slot_kind() != record.slot_kind():
			return ReservationMutationReceipt.STALE_GENERATION
		if command.expected_bundle_sha256() != String(entry["bundle_sha256"]) or command.expected_bundle_sha256() != record.bundle_sha256():
			return ReservationMutationReceipt.STALE_GENERATION
		return &""

	func _registry_entry(capability: GvetAdmissionPorts.ReservationCapability) -> Dictionary:
		if capability == null or not capability.is_authorized():
			return {}
		var handle_id: String = capability.reservation_handle_id()
		var entry: Dictionary = _reservation_registry.get(handle_id, {}) as Dictionary
		if entry.is_empty() or entry.get("capability") != capability:
			return {}
		if capability.authoring_identity_sha256() != String(entry.get("identity_sha256", "")):
			return {}
		if capability.generation() != int(entry.get("issued_generation", -1)) or capability.reservation_slot_kind() != String(entry.get("issued_slot_kind", "")):
			return {}
		return entry

	func _lookup_exact_reservation(command: ReservationMutationCommand) -> ReservationMutationReceipt:
		var primary: ReservationJournalEntry = _reservation_primary_journal.get(command.idempotency_key()) as ReservationJournalEntry
		if primary != null and primary.matches_exact_retry(command):
			return primary.receipt()
		for entry: ReservationJournalEntry in _reservation_conflicts_for_key(command.idempotency_key()):
			if entry.matches_fingerprint(command):
				return entry.receipt()
		return null

	func _lookup_applied_reservation(command: ReservationMutationCommand) -> ReservationMutationReceipt:
		if command.expected_generation() != _reservation_state.generation() or not _reservation_postcondition_holds(command):
			return null
		for key: String in _reservation_primary_journal.keys():
			var entry: ReservationJournalEntry = _reservation_primary_journal[key] as ReservationJournalEntry
			if entry != null and entry.matches_applied_retry(command):
				return entry.receipt()
		return null

	func _reservation_postcondition_holds(command: ReservationMutationCommand) -> bool:
		if command.operation_kind() == ReservationMutationCommand.RESERVE_KIND:
			return false
		var record: JOINT_RESERVATION.ReservationState = _reservation_state.record_by_handle(command.reservation_handle_id())
		if record == null:
			return false
		if command.operation_kind() == ReservationMutationCommand.SPECIALIZE_KIND:
			return record.lifecycle_state() == JOINT_RESERVATION.LIVE_STATE and record.bundle_sha256() == command.target_bundle_sha256()
		if command.operation_kind() == ReservationMutationCommand.RECLASSIFY_KIND:
			return record.lifecycle_state() == JOINT_RESERVATION.LIVE_STATE and record.slot_kind() == JOINT_RESERVATION.CURRENT_SLOT
		return command.operation_kind() == ReservationMutationCommand.TOMBSTONE_KIND and record.lifecycle_state() == JOINT_RESERVATION.TOMBSTONE_STATE

	func _lookup_reservation(command: ReservationMutationCommand) -> ReservationMutationReceipt:
		var primary: ReservationJournalEntry = _reservation_primary_journal.get(command.idempotency_key()) as ReservationJournalEntry
		if primary == null:
			return null
		return _record_reservation_conflict(command, ReservationMutationReceipt.rejected_for(command, &"identity_conflict", "reservation mutation idempotency key conflicts", _reservation_state))

	func _record_reservation(command: ReservationMutationCommand, receipt: ReservationMutationReceipt) -> ReservationMutationReceipt:
		if receipt == null or not receipt.is_closed():
			return receipt
		if not _reservation_primary_journal.has(command.idempotency_key()):
			_reservation_primary_journal[command.idempotency_key()] = ReservationJournalEntry.new(command, receipt)
		return receipt

	func _record_stale_reservation(command: ReservationMutationCommand, message: String) -> ReservationMutationReceipt:
		var receipt: ReservationMutationReceipt = ReservationMutationReceipt.rejected_for(command, ReservationMutationReceipt.STALE_GENERATION, message, _reservation_state)
		var conflicts: Array[ReservationJournalEntry] = _reservation_conflicts_for_key(command.idempotency_key())
		for entry: ReservationJournalEntry in conflicts:
			if entry.matches_fingerprint(command):
				return entry.receipt()
		conflicts.append(ReservationJournalEntry.new(command, receipt))
		_reservation_conflict_journal[command.idempotency_key()] = conflicts
		return receipt

	func _record_reservation_conflict(command: ReservationMutationCommand, receipt: ReservationMutationReceipt) -> ReservationMutationReceipt:
		var conflicts: Array[ReservationJournalEntry] = _reservation_conflicts_for_key(command.idempotency_key())
		for entry: ReservationJournalEntry in conflicts:
			if entry.matches_fingerprint(command):
				return entry.receipt()
		conflicts.append(ReservationJournalEntry.new(command, receipt))
		_reservation_conflict_journal[command.idempotency_key()] = conflicts
		return receipt

	func _reservation_conflicts_for_key(key: String) -> Array[ReservationJournalEntry]:
		var result: Array[ReservationJournalEntry] = []
		var raw: Variant = _reservation_conflict_journal.get(key, [])
		if typeof(raw) != TYPE_ARRAY:
			return result
		for value: Variant in raw:
			var entry: ReservationJournalEntry = value as ReservationJournalEntry
			if entry != null:
				result.append(entry)
		return result

	func _reduce_runtime(command: RuntimeMutationCommand) -> RuntimeMutationReceipt:
		var known: RuntimeMutationReceipt = _lookup_runtime(command)
		if known != null:
			return known
		if command.expected_generation() != _runtime_snapshot.generation():
			return _record_runtime_rejection(MUTATION_RECEIPT.STALE_GENERATION, command)
		var candidate: RuntimeOccupancyState = OCCUPANCY_STATE.from_vector(command.target_vector())
		if candidate == null:
			return _record_runtime_rejection(MUTATION_RECEIPT.ILLEGAL_OCCUPANCY, command)
		return _commit_runtime_candidate(command, candidate)

	func _commit_runtime_candidate(command: RuntimeMutationCommand, candidate: RuntimeOccupancyState) -> RuntimeMutationReceipt:
		var next_generation: int = _runtime_snapshot.generation() + 1
		var next_sequence: int = _commit_sequence + 1
		var commit_id: String = "gvet-commit-%06d" % next_sequence
		var correlations: PackedStringArray = PackedStringArray([command.command_id(), command.idempotency_key()])
		var next_snapshot: RuntimeSessionSnapshot = SESSION_SNAPSHOT.create(candidate, next_generation, commit_id, correlations)
		if next_snapshot == null:
			return _record_runtime_rejection(MUTATION_RECEIPT.INVALID_COMMAND, command)
		var receipt: RuntimeMutationReceipt = MUTATION_RECEIPT.committed_for(command, commit_id, next_snapshot)
		if receipt == null:
			return _record_runtime_rejection(MUTATION_RECEIPT.INVALID_COMMAND, command)
		var notification: RuntimePostCommitNotification = RuntimePostCommitNotification.new(next_snapshot, receipt)
		var entry: RuntimeJournalEntry = RuntimeJournalEntry.new(command.fingerprint(), receipt)
		if not notification.is_valid() or not entry.is_valid():
			return _record_runtime_rejection(MUTATION_RECEIPT.INVALID_COMMAND, command)
		_runtime_snapshot = next_snapshot
		_commit_sequence = next_sequence
		_runtime_primary_journal[command.idempotency_key()] = entry
		_last_notification = notification
		_notification_port.publish(notification)
		return receipt

	func _lookup_runtime(command: RuntimeMutationCommand) -> RuntimeMutationReceipt:
		var key: String = command.idempotency_key()
		var fingerprint: String = command.fingerprint()
		var primary: RuntimeJournalEntry = _runtime_primary_journal.get(key) as RuntimeJournalEntry
		if primary != null:
			if primary.fingerprint() == fingerprint:
				return primary.receipt()
			return _record_runtime_conflict(command)
		var conflicts: RuntimeConflictJournal = _runtime_conflict_journal.get(key) as RuntimeConflictJournal
		if conflicts != null:
			var conflict: RuntimeJournalEntry = conflicts.find(fingerprint)
			if conflict != null:
				return conflict.receipt()
		return null

	func _lookup_exact_runtime(command: RuntimeMutationCommand) -> RuntimeMutationReceipt:
		var key: String = command.idempotency_key()
		var fingerprint: String = command.fingerprint()
		var primary: RuntimeJournalEntry = _runtime_primary_journal.get(key) as RuntimeJournalEntry
		if primary != null and primary.fingerprint() == fingerprint:
			return primary.receipt()
		var conflicts: RuntimeConflictJournal = _runtime_conflict_journal.get(key) as RuntimeConflictJournal
		if conflicts != null:
			var conflict: RuntimeJournalEntry = conflicts.find(fingerprint)
			if conflict != null:
				return conflict.receipt()
		return null

	func _record_runtime_rejection(disposition: String, command: RuntimeMutationCommand) -> RuntimeMutationReceipt:
		var receipt: RuntimeMutationReceipt = MUTATION_RECEIPT.rejected_for(disposition, command, _runtime_snapshot)
		if receipt == null:
			return MUTATION_RECEIPT.invalid_command()
		var entry: RuntimeJournalEntry = RuntimeJournalEntry.new(command.fingerprint(), receipt)
		if not entry.is_valid():
			return MUTATION_RECEIPT.invalid_command()
		_runtime_primary_journal[command.idempotency_key()] = entry
		return receipt

	func _record_runtime_conflict(command: RuntimeMutationCommand) -> RuntimeMutationReceipt:
		var conflicts: RuntimeConflictJournal = _runtime_conflict_journal.get(command.idempotency_key()) as RuntimeConflictJournal
		if conflicts == null:
			conflicts = RuntimeConflictJournal.new()
			_runtime_conflict_journal[command.idempotency_key()] = conflicts
		var known: RuntimeJournalEntry = conflicts.find(command.fingerprint())
		if known != null:
			return known.receipt()
		var receipt: RuntimeMutationReceipt = MUTATION_RECEIPT.rejected_for(MUTATION_RECEIPT.IDEMPOTENCY_CONFLICT, command, _runtime_snapshot)
		if receipt == null:
			return MUTATION_RECEIPT.invalid_command()
		var entry: RuntimeJournalEntry = RuntimeJournalEntry.new(command.fingerprint(), receipt)
		if entry.is_valid():
			conflicts.add(entry)
		return receipt

	func _reentrant_runtime_receipt(command: RuntimeMutationCommand) -> RuntimeMutationReceipt:
		var receipt: RuntimeMutationReceipt = MUTATION_RECEIPT.rejected_for(MUTATION_RECEIPT.REENTRANT_REJECTED, command, _runtime_snapshot)
		return receipt if receipt != null else MUTATION_RECEIPT.invalid_command()


var _locked: bool = false:
	set(value):
		if not _locked:
			_locked = value
var _kernel: OwnerKernel:
	set(value):
		if not _locked:
			_kernel = value

var _snapshot: RuntimeSessionSnapshot:
	get:
		return snapshot()
	set(_value):
		return
var _mailbox: Array[RuntimeMutationCommand]:
	get:
		return _kernel.runtime_mailbox_copy() if _kernel != null else []
	set(_value):
		return
var _journal: Dictionary:
	get:
		return _kernel.runtime_journal_copy() if _kernel != null else {}
	set(_value):
		return
var _commit_sequence: int:
	get:
		return commit_count()
	set(_value):
		return
var _active_transition: bool:
	get:
		return is_transition_active()
	set(_value):
		return


## Creates a legal owner; commands are synchronous and thread-affine to this owner.
## Example: `var owner = GvetRuntimeSessionOwner.create(); owner.submit(command)`.
static func create(initial_vector: PackedInt32Array = PackedInt32Array([0, 0, 0, 0]), notification_port: RuntimeNotificationPort = null, reservation_state: JOINT_RESERVATION.State = null) -> GvetRuntimeSessionOwner:
	var owner: GvetRuntimeSessionOwner = new(initial_vector, notification_port, reservation_state)
	return owner if owner.is_ready() else null


## Enqueues a defensive runtime command. Example: `owner.enqueue(command); owner.dequeue_and_reduce()`.
func enqueue(command: RuntimeMutationCommand) -> bool:
	return _kernel.enqueue_runtime(command) if _kernel != null else false


## Dequeues and reduces exactly one queued runtime command in FIFO order.
func dequeue_and_reduce() -> RuntimeMutationReceipt:
	return _kernel.dequeue_and_reduce() if _kernel != null else null


## Submits one runtime command through the shared owner fence.
## Example: `var receipt := owner.submit(command)`.
func submit(command: RuntimeMutationCommand) -> RuntimeMutationReceipt:
	return _kernel.submit_runtime(command) if _kernel != null else MUTATION_RECEIPT.invalid_command()


## Delegates to submit for reducer-oriented callers. Example: `owner.reduce(command)`.
func reduce(command: RuntimeMutationCommand) -> RuntimeMutationReceipt:
	return submit(command)


## Returns a defensive immutable snapshot copy. Example: `var copy := owner.snapshot()`.
func snapshot() -> RuntimeSessionSnapshot:
	return _kernel.snapshot() if _kernel != null else null


## Returns the snapshot alias. Example: `var copy := owner.get_snapshot()`.
func get_snapshot() -> RuntimeSessionSnapshot:
	return snapshot()


## Returns the current serialized runtime generation.
## Example: `var generation_value := owner.generation()`.
func generation() -> int:
	return _kernel.generation() if _kernel != null else -1


## Returns committed runtime transition count. Example: `var commits := owner.commit_count()`.
func commit_count() -> int:
	return _kernel.commit_count() if _kernel != null else 0


## Returns the shared typed FIFO mailbox size. Example: `var queued := owner.mailbox_size()`.
func mailbox_size() -> int:
	return _kernel.mailbox_size() if _kernel != null else 0


## Returns runtime and reservation journal outcome count.
## Example: `var outcomes := owner.journal_size()`.
func journal_size() -> int:
	return _kernel.journal_size() if _kernel != null else 0


## Returns reservation-only journal outcome count.
## Example: `var outcomes := owner.reservation_journal_size()`.
func reservation_journal_size() -> int:
	return _kernel.reservation_journal_size() if _kernel != null else 0


## Returns whether initialization succeeded. Example: `if owner.is_ready(): owner.submit(command)`.
func is_ready() -> bool:
	return _kernel != null and _kernel.is_ready()


## Returns whether the shared owner transition fence is active.
## Example: `if owner.is_transition_active(): return`.
func is_transition_active() -> bool:
	return _kernel.is_transition_active() if _kernel != null else false


## Returns the latest immutable runtime notification.
## Example: `var note := owner.last_post_commit_notification()`.
func last_post_commit_notification() -> RuntimePostCommitNotification:
	return _kernel.last_post_commit_notification() if _kernel != null else null


## Returns the current canonical runtime state root. Example: `var root := owner.state_root()`.
func state_root() -> String:
	return _kernel.state_root() if _kernel != null else ""


## Returns the typed pre-live port boundary backed by this owner.
## Example: `GvetAdmissionPorts.for_runtime_owner(owner.prelive_reservation_owner())`.
func prelive_reservation_owner() -> GvetAdmissionPorts.PreliveReservationOwner:
	return _kernel


## Grants pre-live capacity through the shared owner command fence.
## Example: `var receipt := owner.reserve(trusted_identity)`.
func reserve(trusted_identity: Dictionary) -> ReservationMutationReceipt:
	return _kernel.reserve_receipt(trusted_identity) if _kernel != null else null


## Captures one typed specialization command at the current owner generation.
## Example: `var command := owner.reservation_command_for_specialization(capability, digest)`.
func reservation_command_for_specialization(capability: GvetAdmissionPorts.ReservationCapability, bundle_sha256: String) -> ReservationMutationCommand:
	return _kernel.make_specialize_command(capability, bundle_sha256) if _kernel != null else ReservationMutationCommand.new()


## Captures one typed reclassification command at the current owner generation.
## Example: `var command := owner.reservation_command_for_reclassification(capability)`.
func reservation_command_for_reclassification(capability: GvetAdmissionPorts.ReservationCapability) -> ReservationMutationCommand:
	return _kernel.make_reclassify_command(capability) if _kernel != null else ReservationMutationCommand.new()


## Captures one typed tombstone command at the current owner generation.
## Example: `var command := owner.reservation_command_for_tombstone(capability)`.
func reservation_command_for_tombstone(capability: GvetAdmissionPorts.ReservationCapability) -> ReservationMutationCommand:
	return _kernel.make_tombstone_command(capability) if _kernel != null else ReservationMutationCommand.new()


## Submits a previously captured reservation command through the shared owner fence.
## Example: `var receipt := owner.submit_reservation_command(command)`.
func submit_reservation_command(command: ReservationMutationCommand) -> ReservationMutationReceipt:
	return _kernel.submit_reservation(command) if _kernel != null else null


## Specializes an existing reservation without releasing its charged headroom.
## Example: `owner.specialize_reservation(capability, bundle_sha256)`.
func specialize_reservation(capability: GvetAdmissionPorts.ReservationCapability, bundle_sha256: String) -> ReservationMutationReceipt:
	return submit_reservation_command(reservation_command_for_specialization(capability, bundle_sha256))


## Reclassifies a pending reservation to current without minting authority.
## Example: `owner.reclassify_pending_to_current(capability)`.
func reclassify_pending_to_current(capability: GvetAdmissionPorts.ReservationCapability) -> ReservationMutationReceipt:
	return submit_reservation_command(reservation_command_for_reclassification(capability))


## Converts one pending reservation into its awaiting-drain tombstone generation.
## Example: `owner.pending_to_tombstone(capability)`.
func pending_to_tombstone(capability: GvetAdmissionPorts.ReservationCapability) -> ReservationMutationReceipt:
	return submit_reservation_command(reservation_command_for_tombstone(capability))


## Returns private companion evidence for deterministic contract tests.
## Example: `var evidence := owner.reservation_snapshot(capability)`.
func reservation_snapshot(capability: GvetAdmissionPorts.ReservationCapability) -> Dictionary:
	return _kernel.reservation_snapshot(capability) if _kernel != null else {}


## Returns owner-held typed companion evidence for deterministic tests.
## Example: `var companions := owner.reservation_companions(capability)`.
func reservation_companions(capability: GvetAdmissionPorts.ReservationCapability) -> Dictionary:
	return _kernel.reservation_companions(capability) if _kernel != null else {}


## Returns the current owner-registry binding without exposing authority references.
## Example: `var record := owner.reservation_registry_record(capability)`.
func reservation_registry_record(capability: GvetAdmissionPorts.ReservationCapability) -> Dictionary:
	return _kernel.reservation_registry_record(capability) if _kernel != null else {}


## Returns owner registry cardinalities without exposing opaque references.
## Example: `var counts := owner.reservation_registry_counts()`.
func reservation_registry_counts() -> Dictionary:
	return _kernel.reservation_registry_counts() if _kernel != null else {}


## Returns a detached projection of the current reservation generation.
## Example: `var record := owner.reservation_generation_record()`.
func reservation_generation_record() -> Dictionary:
	return _kernel.reservation_generation_record() if _kernel != null else {}


## Returns the independently recomputable canonical ledger root.
## Example: `var root := owner.reservation_ledger_root()`.
func reservation_ledger_root() -> String:
	return _kernel.reservation_ledger_root() if _kernel != null else ""


func _init(initial_vector: PackedInt32Array = PackedInt32Array([0, 0, 0, 0]), notification_port: RuntimeNotificationPort = null, reservation_state: JOINT_RESERVATION.State = null) -> void:
	_kernel = OwnerKernel.new(initial_vector, notification_port, reservation_state)
	_locked = true
