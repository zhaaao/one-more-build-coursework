class_name GvetJointReservation
extends RefCounted

const CANONICAL_CODEC = preload("res://src/foundation/canonical_codec.gd")
const IR_TYPE = preload("res://src/foundation/canonical_json_ir.gd")

const MAX_LEDGER_ENTRIES: int = 256
const MAX_LEDGER_BYTES: int = 524288
const MAX_COMPANION_SLOTS: int = 256
const MAX_TERMINAL_RECORD_BYTES: int = 524288
const TERMINAL_RECORD_BYTES: int = 2048
const SHA256_HEX_LENGTH: int = 64
const RESERVATION_CODEC_VERSION: String = "joint_ledger_reservation_v1"
const CURRENT_SLOT: String = "current"
const PENDING_SLOT: String = "pending"
const TOMBSTONE_SLOT: String = "tombstone"
const LIVE_STATE: String = "live"
const TOMBSTONE_STATE: String = "tombstone"
const HEX_DIGITS: String = "0123456789abcdef"


class QuantityManifest extends RefCounted:
	var _sealed: bool = false:
		set(value):
			if not _sealed:
				_sealed = value
	var _values: Dictionary = {}:
		get:
			return _values.duplicate(true)
		set(value):
			if not _sealed:
				_values = value.duplicate(true)

	func _init(values: Dictionary = {}) -> void:
		_values = values
		_sealed = _has_exact_schema(_values)

	func is_valid() -> bool:
		return _sealed

	func value(quantity_id: String) -> int:
		return int(_values.get(quantity_id, 0)) if _sealed else 0

	func to_dictionary() -> Dictionary:
		return _values.duplicate(true) if _sealed else {}

	static func _has_exact_schema(values: Dictionary) -> bool:
		var expected: Array[String] = [
			"ledger_count_units",
			"ledger_byte_delta",
			"terminal_record_bytes",
			"queue_drain_ticket_slots",
			"resolution_record_slots",
			"frontier_capability_slots",
			"cleanup_cell_slots",
			"delivery_capability_slots",
			"slot_kind",
		]
		if values.size() != expected.size():
			return false
		for key: String in expected:
			if not values.has(key):
				return false
		return true


class ReservationState extends RefCounted:
	var _sealed: bool = false:
		set(value):
			if not _sealed:
				_sealed = value
	var _handle_id: String = "":
		set(value):
			if not _sealed:
				_handle_id = value
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
	var _idempotency_key: String = "":
		set(value):
			if not _sealed:
				_idempotency_key = value
	var _slot_kind: String = "":
		set(value):
			if not _sealed:
				_slot_kind = value
	var _generation: int = -1:
		set(value):
			if not _sealed:
				_generation = value
	var _bundle_sha256: String = "":
		set(value):
			if not _sealed:
				_bundle_sha256 = value
	var _delivery_handle_id: String = "":
		set(value):
			if not _sealed:
				_delivery_handle_id = value
	var _cleanup_cell_id: String = "":
		set(value):
			if not _sealed:
				_cleanup_cell_id = value
	var _quantity_manifest: QuantityManifest:
		set(value):
			if not _sealed:
				_quantity_manifest = value
	var _reachable_arms: Array[Dictionary] = []:
		get:
			return _reachable_arms.duplicate(true)
		set(value):
			if not _sealed:
				_reachable_arms = value.duplicate(true)
	var _lifecycle_state: String = "":
		set(value):
			if not _sealed:
				_lifecycle_state = value
	var _consumed_count_units: int = 0:
		set(value):
			if not _sealed:
				_consumed_count_units = value
	var _consumed_byte_delta: int = 0:
		set(value):
			if not _sealed:
				_consumed_byte_delta = value

	func _init(
		handle_id: String,
		identity: Dictionary,
		identity_sha256: String,
		idempotency_key: String,
		slot_kind: String,
		generation: int,
		bundle_sha256: String,
		delivery_handle_id: String,
		cleanup_cell_id: String,
		quantity_manifest: QuantityManifest,
		reachable_arms: Array[Dictionary],
		lifecycle_state: String = LIVE_STATE,
		consumed_count_units: int = 0,
		consumed_byte_delta: int = 0
	) -> void:
		_handle_id = handle_id
		_identity = identity
		_identity_sha256 = identity_sha256
		_idempotency_key = idempotency_key
		_slot_kind = slot_kind
		_generation = generation
		_bundle_sha256 = bundle_sha256
		_delivery_handle_id = delivery_handle_id
		_cleanup_cell_id = cleanup_cell_id
		_quantity_manifest = quantity_manifest
		_reachable_arms = reachable_arms
		_lifecycle_state = lifecycle_state
		_consumed_count_units = consumed_count_units
		_consumed_byte_delta = consumed_byte_delta
		_sealed = _is_complete()

	func is_valid() -> bool:
		return _sealed

	func handle_id() -> String:
		return _handle_id if _sealed else ""

	func identity() -> Dictionary:
		return _identity.duplicate(true) if _sealed else {}

	func identity_sha256() -> String:
		return _identity_sha256 if _sealed else ""

	func idempotency_key() -> String:
		return _idempotency_key if _sealed else ""

	func slot_kind() -> String:
		return _slot_kind if _sealed else ""

	func generation() -> int:
		return _generation if _sealed else -1

	func bundle_sha256() -> String:
		return _bundle_sha256 if _sealed else ""

	func delivery_handle_id() -> String:
		return _delivery_handle_id if _sealed else ""

	func cleanup_cell_id() -> String:
		return _cleanup_cell_id if _sealed else ""

	func quantity_manifest() -> QuantityManifest:
		return _quantity_manifest if _sealed else null

	func reachable_arms() -> Array[Dictionary]:
		return _reachable_arms.duplicate(true) if _sealed else []

	func lifecycle_state() -> String:
		return _lifecycle_state if _sealed else ""

	func consumed_count_units() -> int:
		return _consumed_count_units if _sealed else 0

	func consumed_byte_delta() -> int:
		return _consumed_byte_delta if _sealed else 0

	func owner_entry() -> Dictionary:
		var entry: Dictionary = {
			"reservation_handle_id": handle_id(),
			"authoring_request_sha256": identity_sha256(),
			"reservation_slot_kind": slot_kind(),
			"owner_generation": generation(),
		}
		if not bundle_sha256().is_empty():
			entry["execution_bundle_sha256"] = bundle_sha256()
		return entry

	func snapshot() -> Dictionary:
		return {
			"reservation_handle_id": handle_id(),
			"authoring_request_sha256": identity_sha256(),
			"reservation_slot_kind": slot_kind(),
			"generation": generation(),
			"delivery_handle_id": delivery_handle_id(),
			"cleanup_cell_id": cleanup_cell_id(),
			"cleanup_cell_state": "reserved_empty",
			"cleanup_cell_generation": generation(),
			"bundle_sha256": bundle_sha256(),
			"quantity_manifest": quantity_manifest().to_dictionary(),
			"reachable_final_arm_entries": reachable_arms(),
			"lifecycle_state": lifecycle_state(),
			"consumed_ledger_count_units": consumed_count_units(),
			"consumed_ledger_byte_delta": consumed_byte_delta(),
			"public_success_type": "ReservationCapability",
		}

	func _is_complete() -> bool:
		if _handle_id.is_empty() or _identity.is_empty() or _identity_sha256.is_empty() or _idempotency_key.is_empty():
			return false
		if _slot_kind != CURRENT_SLOT and _slot_kind != PENDING_SLOT and _slot_kind != TOMBSTONE_SLOT:
			return false
		if _generation < 0 or _delivery_handle_id.is_empty() or _cleanup_cell_id.is_empty():
			return false
		if _quantity_manifest == null or not _quantity_manifest.is_valid():
			return false
		if _lifecycle_state != LIVE_STATE and _lifecycle_state != TOMBSTONE_STATE:
			return false
		return _consumed_count_units >= 0 and _consumed_byte_delta >= 0


class State extends RefCounted:
	var _sealed: bool = false:
		set(value):
			if not _sealed:
				_sealed = value
	var _base_ledger_entry_count: int = 0:
		set(value):
			if not _sealed:
				_base_ledger_entry_count = value
	var _base_ledger_byte_count: int = 0:
		set(value):
			if not _sealed:
				_base_ledger_byte_count = value
	var _generation: int = -1:
		set(value):
			if not _sealed:
				_generation = value
	var _next_handle_sequence: int = 1:
		set(value):
			if not _sealed:
				_next_handle_sequence = value
	var _records_by_identity: Dictionary = {}:
		get:
			return _records_by_identity.duplicate()
		set(value):
			if not _sealed:
				_records_by_identity = value.duplicate()
	var _capacity_limits: Dictionary = {}:
		get:
			return _capacity_limits.duplicate(true)
		set(value):
			if not _sealed:
				_capacity_limits = value.duplicate(true)
	var _generation_projection: Dictionary = {}:
		get:
			return _generation_projection.duplicate(true)
		set(value):
			if not _sealed:
				_generation_projection = value.duplicate(true)
	var _ledger_root: String = "":
		set(value):
			if not _sealed:
				_ledger_root = value

	func _init(
		base_ledger_entry_count: int,
		base_ledger_byte_count: int,
		generation: int,
		next_handle_sequence: int,
		records_by_identity: Dictionary,
		capacity_limits: Dictionary,
		generation_projection: Dictionary,
		ledger_root: String
	) -> void:
		_base_ledger_entry_count = base_ledger_entry_count
		_base_ledger_byte_count = base_ledger_byte_count
		_generation = generation
		_next_handle_sequence = next_handle_sequence
		_records_by_identity = records_by_identity
		_capacity_limits = capacity_limits
		_generation_projection = generation_projection
		_ledger_root = ledger_root
		_sealed = generation >= 0 and next_handle_sequence > 0 and not generation_projection.is_empty() and not ledger_root.is_empty()

	func is_valid() -> bool:
		return _sealed

	func is_empty_seed() -> bool:
		return is_valid() and _generation == 0 and _next_handle_sequence == 1 and _records_by_identity.is_empty()

	func generation() -> int:
		return _generation if _sealed else -1

	func next_handle_sequence() -> int:
		return _next_handle_sequence if _sealed else 1

	func base_ledger_entry_count() -> int:
		return _base_ledger_entry_count if _sealed else 0

	func base_ledger_byte_count() -> int:
		return _base_ledger_byte_count if _sealed else 0

	func capacity_limits() -> Dictionary:
		return _capacity_limits.duplicate(true) if _sealed else {}

	func records_copy() -> Dictionary:
		return _records_by_identity.duplicate() if _sealed else {}

	func record_by_identity(identity_sha256: String) -> ReservationState:
		return _records_by_identity.get(identity_sha256) as ReservationState if _sealed else null

	func record_by_handle(handle_id: String) -> ReservationState:
		for identity_sha256: String in _records_by_identity.keys():
			var record: ReservationState = _records_by_identity[identity_sha256] as ReservationState
			if record != null and record.handle_id() == handle_id:
				return record
		return null

	func generation_record() -> Dictionary:
		return _generation_projection.duplicate(true) if _sealed else {}

	func ledger_root() -> String:
		return _ledger_root if _sealed else ""

	func reservation_count() -> int:
		return _records_by_identity.size() if _sealed else 0

	func effective_ledger_entry_count() -> int:
		return _base_ledger_entry_count + _total_consumed("ledger_count") if _sealed else 0

	func effective_ledger_byte_count() -> int:
		return _base_ledger_byte_count + _total_consumed("ledger_bytes") if _sealed else 0

	func reservation_snapshot(handle_id: String) -> Dictionary:
		var record: ReservationState = record_by_handle(handle_id)
		return record.snapshot() if record != null else {}

	func reservation_companions(handle_id: String) -> Dictionary:
		var record: ReservationState = record_by_handle(handle_id)
		if record == null:
			return {}
		return {
			"delivery_companion": {
				"resolution_delivery_handle_id": record.delivery_handle_id(),
				"reservation_handle_id": record.handle_id(),
				"generation": record.generation(),
			},
			"cleanup_cell": {
				"cleanup_cell_id": record.cleanup_cell_id(),
				"reservation_handle_id": record.handle_id(),
				"generation": record.generation(),
				"state": "reserved_empty",
			},
			"quantity_manifest": record.quantity_manifest().to_dictionary(),
		}

	func _total_consumed(kind: String) -> int:
		var total: int = 0
		for identity_sha256: String in _records_by_identity.keys():
			var record: ReservationState = _records_by_identity[identity_sha256] as ReservationState
			if record == null:
				continue
			total += record.consumed_count_units() if kind == "ledger_count" else record.consumed_byte_delta()
		return total

class Transition extends RefCounted:
	var _sealed: bool = false:
		set(value):
			if not _sealed:
				_sealed = value
	var _success: bool = false:
		set(value):
			if not _sealed:
				_success = value
	var _error_code: StringName = &"reservation_invalid":
		set(value):
			if not _sealed:
				_error_code = value
	var _message: String = "":
		set(value):
			if not _sealed:
				_message = value
	var _next_state: State:
		set(value):
			if not _sealed:
				_next_state = value
	var _handle_id: String = "":
		set(value):
			if not _sealed:
				_handle_id = value
	var _value: Dictionary = {}:
		get:
			return _value.duplicate(true)
		set(value):
			if not _sealed:
				_value = value.duplicate(true)

	func _init(
		success: bool,
		error_code: StringName,
		message: String,
		next_state: State,
		handle_id: String = "",
		value: Dictionary = {}
	) -> void:
		_success = success
		_error_code = error_code
		_message = message
		_next_state = next_state
		_handle_id = handle_id
		_value = value.duplicate(true)
		_sealed = true

	func is_success() -> bool:
		return _success

	func error_code() -> StringName:
		return _error_code

	func message() -> String:
		return _message

	func next_state() -> State:
		return _next_state

	func handle_id() -> String:
		return _handle_id

	func value() -> Dictionary:
		return _value.duplicate(true)


## Creates an immutable empty reservation state for one owner session.
## Example: `var state := GvetJointReservation.create(254, 12000)`.
static func create(
	ledger_entry_count: int = 0,
	ledger_byte_count: int = 0,
	capacity_limits: Dictionary = {}
) -> State:
	if ledger_entry_count < 0 or ledger_entry_count > MAX_LEDGER_ENTRIES:
		return null
	if ledger_byte_count < 0 or ledger_byte_count > MAX_LEDGER_BYTES:
		return null
	var limits: Dictionary = _make_capacity_limits(capacity_limits)
	if limits.is_empty():
		return null
	return _build_state(null, ledger_entry_count, ledger_byte_count, 1, {}, limits, "initial", "", [], [])


## Calculates one pre-live reservation generation without mutating the supplied state.
## Example: `var transition := GvetJointReservation.reserve(state, identity)`.
static func reserve(
	state: State,
	trusted_identity: Dictionary,
	current_occupied: bool = false,
	pending_occupied: bool = false
) -> Transition:
	if state == null or not state.is_valid() or not _identity_is_valid(trusted_identity):
		return _failure(state, &"request_resource_limit", "trusted pre-live identity is invalid")
	var identity_sha256: String = _canonical_digest(trusted_identity)
	var idempotency_key: String = _identity_idempotency_key(trusted_identity, identity_sha256)
	var existing: ReservationState = state.record_by_identity(identity_sha256)
	if existing != null:
		if existing.idempotency_key() == idempotency_key:
			return _success(state, existing.handle_id(), existing.snapshot())
		return _failure(state, &"identity_conflict", "the complete identity has another idempotency binding")
	if _idempotency_belongs_to_other(state, idempotency_key, identity_sha256):
		return _failure(state, &"identity_conflict", "the idempotency key belongs to another identity")
	var slot_kind: String = _derive_slot_kind(state, current_occupied, pending_occupied)
	if slot_kind.is_empty():
		return _failure(state, &"request_resource_limit", "no current or pending reservation slot is available")
	return _reserve_new_identity(state, trusted_identity, identity_sha256, idempotency_key, slot_kind)


## Calculates a bundle specialization using an exact lowercase SHA-256 identity.
## Example: `var transition := GvetJointReservation.specialize(state, handle, digest)`.
static func specialize(state: State, handle_id: String, bundle_sha256: String) -> Transition:
	var record: ReservationState = _live_record(state, handle_id)
	if record == null:
		return _failure(state, &"reservation_invalid", "reservation handle is not live")
	if not is_lowercase_sha256(bundle_sha256):
		return _failure(state, &"identity_conflict", "bundle specialization requires exactly 64 lowercase hexadecimal characters")
	if not record.bundle_sha256().is_empty():
		if record.bundle_sha256() == bundle_sha256:
			return _success(state, handle_id, _transition_value(state, record, "specialization"))
		return _failure(state, &"identity_conflict", "reservation is already specialized to another bundle")
	var candidate: ReservationState = _copy_record(state, record, record.slot_kind(), bundle_sha256, LIVE_STATE, 0, 0)
	if candidate == null or not _specialization_fits(candidate):
		return _failure(state, &"request_resource_limit", "bundle specialization exceeds reserved candidate headroom")
	return _replace_record(state, record, candidate, "bundle_specialization", "specialization")


## Calculates one pending-to-current generation replacement.
## Example: `var transition := GvetJointReservation.reclassify_pending_to_current(state, handle)`.
static func reclassify_pending_to_current(
	state: State,
	handle_id: String,
	current_occupied: bool = false
) -> Transition:
	var record: ReservationState = _live_record(state, handle_id)
	if record == null:
		return _failure(state, &"reservation_invalid", "reservation handle is not live")
	if record.slot_kind() == CURRENT_SLOT:
		return _success(state, handle_id, _transition_value(state, record, "reclassification"))
	if record.slot_kind() != PENDING_SLOT:
		return _failure(state, &"reservation_invalid", "only a pending reservation can reclassify")
	if current_occupied or _count_slot(state, CURRENT_SLOT, record.identity_sha256()) > 0:
		return _failure(state, &"request_resource_limit", "current slot is still occupied")
	var candidate: ReservationState = _copy_record(state, record, CURRENT_SLOT, record.bundle_sha256(), LIVE_STATE, 0, 0)
	return _replace_record(state, record, candidate, "reservation_reclassification_commit", "reclassification")


## Calculates pending retirement into the one awaiting-drain tombstone position.
## Example: `var transition := GvetJointReservation.pending_to_tombstone(state, handle)`.
static func pending_to_tombstone(state: State, handle_id: String) -> Transition:
	var record: ReservationState = state.record_by_handle(handle_id) if state != null else null
	if record == null:
		return _failure(state, &"reservation_invalid", "reservation handle is unknown")
	if record.lifecycle_state() == TOMBSTONE_STATE:
		return _success(state, handle_id, _transition_value(state, record, "pending_to_tombstone"))
	if record.slot_kind() != PENDING_SLOT or _count_slot(state, TOMBSTONE_SLOT) > 0:
		return _failure(state, &"request_resource_limit", "pending retirement cannot occupy the tombstone position")
	var retired_entry: Dictionary = _candidate_quantity_preimage(record, TOMBSTONE_SLOT, record.bundle_sha256(), "ordinary", "awaiting_queue_drain")
	var consumed_bytes: int = _canonical_bytes(retired_entry).size()
	if consumed_bytes <= 0 or consumed_bytes > record.quantity_manifest().value("ledger_byte_delta"):
		return _failure(state, &"request_resource_limit", "retired entry exceeds reserved ledger headroom")
	var candidate: ReservationState = _copy_record(state, record, TOMBSTONE_SLOT, record.bundle_sha256(), TOMBSTONE_STATE, 1, consumed_bytes)
	return _replace_record(state, record, candidate, "pending_to_tombstone_conversion", "pending_to_tombstone")


## Reports whether a value is exactly one canonical lowercase SHA-256 digest.
## Example: `GvetJointReservation.is_lowercase_sha256(digest)`.
static func is_lowercase_sha256(value: String) -> bool:
	if value.length() != SHA256_HEX_LENGTH:
		return false
	for index: int in range(SHA256_HEX_LENGTH):
		if HEX_DIGITS.find(value.substr(index, 1)) < 0:
			return false
	return true


## Recomputes one reservation-generation root from its pure projection.
## Example: `GvetJointReservation.recompute_canonical_root(projection)`.
static func recompute_canonical_root(payload: Dictionary) -> String:
	var copy: Dictionary = _clone_dictionary(payload)
	copy.erase("reservation_root_id")
	return _canonical_digest(copy)


## Recomputes a canonical retired-ledger scalar root.
## Example: `GvetJointReservation.recompute_ledger_root(254, 1, 1, 0, 12000)`.
static func recompute_ledger_root(
	ledger_entry_count: int,
	current_reservations: int,
	pending_reservations: int,
	tombstones: int,
	ledger_byte_count: int
) -> String:
	return _compute_ledger_root(ledger_entry_count, current_reservations, pending_reservations, tombstones, ledger_byte_count)


static func _reserve_new_identity(
	state: State,
	identity: Dictionary,
	identity_sha256: String,
	idempotency_key: String,
	slot_kind: String
) -> Transition:
	var handle_id: String = _make_handle_id(identity_sha256, state.next_handle_sequence())
	var manifest: QuantityManifest = _make_quantity_manifest(identity_sha256, handle_id, slot_kind)
	if manifest == null or not manifest.is_valid() or not _has_joint_capacity(state, manifest):
		return _failure(state, &"request_resource_limit", "joint ledger or bounded companion capacity is exhausted")
	var record: ReservationState = _new_record(identity, identity_sha256, idempotency_key, handle_id, slot_kind, state.generation() + 1, "", manifest)
	if record == null:
		return _failure(state, &"request_resource_limit", "reservation record construction failed")
	var records: Dictionary = state.records_copy()
	records[identity_sha256] = record
	var next: State = _build_state(
		state,
		state.base_ledger_entry_count(),
		state.base_ledger_byte_count(),
		state.next_handle_sequence() + 1,
		records,
		state.capacity_limits(),
		"pre_live_grant",
		handle_id,
		[],
		[record.owner_entry()]
	)
	return _success(next, handle_id, record.snapshot()) if next != null else _failure(state, &"request_resource_limit", "joint generation could not be constructed")


static func _replace_record(
	state: State,
	prior: ReservationState,
	candidate: ReservationState,
	commit_kind: String,
	transition_kind: String
) -> Transition:
	if candidate == null or not candidate.is_valid():
		return _failure(state, &"reservation_invalid", "replacement record is invalid")
	var records: Dictionary = state.records_copy()
	records[prior.identity_sha256()] = candidate
	var next: State = _build_state(
		state,
		state.base_ledger_entry_count(),
		state.base_ledger_byte_count(),
		state.next_handle_sequence(),
		records,
		state.capacity_limits(),
		commit_kind,
		prior.handle_id(),
		[prior.handle_id()],
		[candidate.owner_entry()]
	)
	if next == null:
		return _failure(state, &"reservation_invalid", "replacement generation could not be constructed")
	return _success(next, candidate.handle_id(), _transition_value(next, candidate, transition_kind))


static func _new_record(
	identity: Dictionary,
	identity_sha256: String,
	idempotency_key: String,
	handle_id: String,
	slot_kind: String,
	generation: int,
	bundle_sha256: String,
	manifest: QuantityManifest
) -> ReservationState:
	var delivery_id: String = _make_companion_id(handle_id, "delivery")
	var cleanup_id: String = _make_companion_id(handle_id, "cleanup")
	var prototype: ReservationState = ReservationState.new(
		handle_id,
		identity,
		identity_sha256,
		idempotency_key,
		slot_kind,
		generation,
		bundle_sha256,
		delivery_id,
		cleanup_id,
		manifest,
		[],
		LIVE_STATE,
		0,
		0
	)
	if not prototype.is_valid():
		return null
	return ReservationState.new(
		handle_id,
		identity,
		identity_sha256,
		idempotency_key,
		slot_kind,
		generation,
		bundle_sha256,
		delivery_id,
		cleanup_id,
		manifest,
		_make_reachable_arms(prototype),
		LIVE_STATE,
		0,
		0
	)


static func _copy_record(
	state: State,
	source: ReservationState,
	slot_kind: String,
	bundle_sha256: String,
	lifecycle_state: String,
	consumed_count_units: int,
	consumed_byte_delta: int
) -> ReservationState:
	var prototype: ReservationState = ReservationState.new(
		source.handle_id(),
		source.identity(),
		source.identity_sha256(),
		source.idempotency_key(),
		slot_kind,
		state.generation() + 1,
		bundle_sha256,
		source.delivery_handle_id(),
		source.cleanup_cell_id(),
		source.quantity_manifest(),
		[],
		lifecycle_state,
		consumed_count_units,
		consumed_byte_delta
	)
	if not prototype.is_valid():
		return null
	var arms: Array[Dictionary] = []
	if lifecycle_state != TOMBSTONE_STATE:
		arms = _make_reachable_arms(prototype)
	return ReservationState.new(
		prototype.handle_id(),
		prototype.identity(),
		prototype.identity_sha256(),
		prototype.idempotency_key(),
		prototype.slot_kind(),
		prototype.generation(),
		prototype.bundle_sha256(),
		prototype.delivery_handle_id(),
		prototype.cleanup_cell_id(),
		prototype.quantity_manifest(),
		arms,
		prototype.lifecycle_state(),
		prototype.consumed_count_units(),
		prototype.consumed_byte_delta()
	)


static func _build_state(
	prior: State,
	base_ledger_entry_count: int,
	base_ledger_byte_count: int,
	next_handle_sequence: int,
	records: Dictionary,
	capacity_limits: Dictionary,
	commit_kind: String,
	changed_handle_id: String,
	removed_owner_handle_ids: Array,
	added_owner_entries: Array
) -> State:
	var generation: int = 0 if prior == null else prior.generation() + 1
	var metrics: Dictionary = _collect_metrics(records)
	if metrics.is_empty() or not _state_constraints_hold(base_ledger_entry_count, base_ledger_byte_count, metrics):
		return null
	var replacement_entries: Array[Dictionary] = _prior_replacements(prior)
	if prior != null:
		var replacement: Dictionary = _make_replacement_entry(prior, generation, commit_kind, changed_handle_id, removed_owner_handle_ids, added_owner_entries, metrics)
		if replacement.is_empty():
			return null
		replacement_entries.append(replacement)
	var ledger_entries: int = base_ledger_entry_count + int(metrics["consumed_count"])
	var ledger_bytes: int = base_ledger_byte_count + int(metrics["consumed_bytes"])
	var ledger_root: String = _compute_ledger_root(ledger_entries, int(metrics["current_count"]), int(metrics["pending_count"]), int(metrics["tombstone_count"]), ledger_bytes)
	var payload: Dictionary = _generation_payload(generation, ledger_root, ledger_bytes, metrics, replacement_entries)
	var root_id: String = recompute_canonical_root(payload)
	if root_id.is_empty():
		return null
	payload["reservation_root_id"] = root_id
	return State.new(base_ledger_entry_count, base_ledger_byte_count, generation, next_handle_sequence, records, capacity_limits, payload, ledger_root)


static func _collect_metrics(records: Dictionary) -> Dictionary:
	var owner_entries: Array[Dictionary] = []
	var reachable_entries: Array[Dictionary] = []
	var total_count: int = 0
	var total_bytes: int = 0
	var consumed_count: int = 0
	var consumed_bytes: int = 0
	var current_count: int = 0
	var pending_count: int = 0
	var tombstone_count: int = 0
	var identities: Array[String] = []
	for key: Variant in records.keys():
		identities.append(String(key))
	identities.sort()
	for identity_sha256: String in identities:
		var record: ReservationState = records[identity_sha256] as ReservationState
		if record == null or not record.is_valid():
			return {}
		owner_entries.append(record.owner_entry())
		reachable_entries.append_array(record.reachable_arms())
		total_count += record.quantity_manifest().value("ledger_count_units")
		total_bytes += record.quantity_manifest().value("ledger_byte_delta")
		consumed_count += record.consumed_count_units()
		consumed_bytes += record.consumed_byte_delta()
		current_count += int(record.slot_kind() == CURRENT_SLOT)
		pending_count += int(record.slot_kind() == PENDING_SLOT)
		tombstone_count += int(record.slot_kind() == TOMBSTONE_SLOT)
	owner_entries.sort_custom(_owner_entry_less)
	reachable_entries.sort_custom(_arm_less)
	return {
		"owner_entries": owner_entries,
		"reachable_entries": reachable_entries,
		"total_count": total_count,
		"total_bytes": total_bytes,
		"consumed_count": consumed_count,
		"consumed_bytes": consumed_bytes,
		"residual_count": total_count - consumed_count,
		"residual_bytes": total_bytes - consumed_bytes,
		"current_count": current_count,
		"pending_count": pending_count,
		"tombstone_count": tombstone_count,
	}


static func _generation_payload(
	generation: int,
	ledger_root: String,
	ledger_bytes: int,
	metrics: Dictionary,
	replacement_entries: Array[Dictionary]
) -> Dictionary:
	return {
		"reservation_codec_version": RESERVATION_CODEC_VERSION,
		"reservation_root_id": "",
		"generation": generation,
		"base_runtime_retired_ledger_sha256": ledger_root,
		"base_runtime_retired_ledger_bytes": ledger_bytes,
		"owner_handle_entries": metrics["owner_entries"],
		"reachable_final_arm_entries": metrics["reachable_entries"],
		"total_reserved_ledger_count_units": metrics["total_count"],
		"total_reserved_ledger_byte_delta": metrics["total_bytes"],
		"consumed_ledger_count_units": metrics["consumed_count"],
		"consumed_ledger_byte_delta": metrics["consumed_bytes"],
		"residual_reserved_ledger_count_units": metrics["residual_count"],
		"residual_reserved_ledger_byte_delta": metrics["residual_bytes"],
		"atomic_replacement_entries": replacement_entries,
	}


static func _make_replacement_entry(
	prior: State,
	next_generation: int,
	commit_kind: String,
	changed_handle_id: String,
	removed_owner_handle_ids: Array,
	added_owner_entries: Array,
	next_metrics: Dictionary
) -> Dictionary:
	if changed_handle_id.is_empty():
		return {}
	var removed: Array[String] = []
	for value: Variant in removed_owner_handle_ids:
		removed.append(String(value))
	removed.sort()
	var added: Array[Dictionary] = []
	for value: Variant in added_owner_entries:
		if typeof(value) == TYPE_DICTIONARY:
			added.append(_clone_dictionary(value))
	added.sort_custom(_owner_entry_less)
	if added.size() != 1 or String(added[0].get("reservation_handle_id", "")) != changed_handle_id:
		return {}
	var prior_projection: Dictionary = prior.generation_record()
	return {
		"commit_kind": commit_kind,
		"commit_id": "reservation-commit-%06d" % next_generation,
		"prior_generation": prior.generation(),
		"next_generation": next_generation,
		"removed_owner_handle_ids": removed,
		"added_owner_handle_entries": added,
		"consumed_count_delta": int(next_metrics["consumed_count"]) - int(prior_projection.get("consumed_ledger_count_units", 0)),
		"consumed_byte_delta": int(next_metrics["consumed_bytes"]) - int(prior_projection.get("consumed_ledger_byte_delta", 0)),
		"residual_count_delta": int(next_metrics["residual_count"]) - int(prior_projection.get("residual_reserved_ledger_count_units", 0)),
		"residual_byte_delta": int(next_metrics["residual_bytes"]) - int(prior_projection.get("residual_reserved_ledger_byte_delta", 0)),
	}


static func _prior_replacements(prior: State) -> Array[Dictionary]:
	if prior == null:
		return []
	var raw: Variant = prior.generation_record().get("atomic_replacement_entries", [])
	return _clone_dictionary_array(raw) if typeof(raw) == TYPE_ARRAY else []


static func _state_constraints_hold(base_entries: int, base_bytes: int, metrics: Dictionary) -> bool:
	var effective_entries: int = base_entries + int(metrics["consumed_count"])
	var effective_bytes: int = base_bytes + int(metrics["consumed_bytes"])
	if effective_entries + int(metrics["current_count"]) + int(metrics["pending_count"]) > MAX_LEDGER_ENTRIES:
		return false
	if effective_bytes + int(metrics["residual_bytes"]) > MAX_LEDGER_BYTES:
		return false
	if int(metrics["current_count"]) > 1 or int(metrics["pending_count"]) > 1 or int(metrics["tombstone_count"]) > 1:
		return false
	return int(metrics["pending_count"]) + int(metrics["tombstone_count"]) <= 1


static func _has_joint_capacity(state: State, manifest: QuantityManifest) -> bool:
	if state.base_ledger_entry_count() + state.reservation_count() + 1 > MAX_LEDGER_ENTRIES:
		return false
	var projection: Dictionary = state.generation_record()
	var reserved_bytes: int = int(projection.get("total_reserved_ledger_byte_delta", 0))
	if state.base_ledger_byte_count() + reserved_bytes + manifest.value("ledger_byte_delta") > MAX_LEDGER_BYTES:
		return false
	var next_owner_count: int = state.reservation_count() + 1
	var limits: Dictionary = state.capacity_limits()
	for quantity_id: String in ["queue_drain_ticket_slots", "resolution_record_slots", "frontier_capability_slots", "cleanup_cell_slots", "delivery_capability_slots"]:
		if next_owner_count > int(limits.get(quantity_id, 0)):
			return false
	var terminal_bytes: int = _used_quantity(state, "terminal_record_bytes") + manifest.value("terminal_record_bytes")
	return terminal_bytes <= int(limits.get("terminal_record_bytes", 0))


static func _make_quantity_manifest(identity_sha256: String, handle_id: String, slot_kind: String) -> QuantityManifest:
	var worst_case_bytes: int = 0
	var maximum_digest: String = "f".repeat(SHA256_HEX_LENGTH)
	var slot_kinds: Array[String] = [slot_kind]
	if slot_kind == PENDING_SLOT:
		slot_kinds.append(TOMBSTONE_SLOT)
	for candidate_slot: String in slot_kinds:
		for bundle_sha256: String in ["", maximum_digest]:
			for retirement_class: String in ["ordinary", "born_invalidated"]:
				for drain_state: String in ["not_required", "awaiting_queue_drain"]:
					var candidate: Dictionary = _candidate_quantity_fields(identity_sha256, handle_id, candidate_slot, bundle_sha256, retirement_class, drain_state)
					worst_case_bytes = maxi(worst_case_bytes, _canonical_bytes(candidate).size())
	if worst_case_bytes <= 0:
		return null
	return QuantityManifest.new({
		"ledger_count_units": 1,
		"ledger_byte_delta": worst_case_bytes,
		"terminal_record_bytes": TERMINAL_RECORD_BYTES,
		"queue_drain_ticket_slots": 1,
		"resolution_record_slots": 1,
		"frontier_capability_slots": 1,
		"cleanup_cell_slots": 1,
		"delivery_capability_slots": 1,
		"slot_kind": slot_kind,
	})


static func _make_reachable_arms(record: ReservationState) -> Array[Dictionary]:
	var arms: Array[Dictionary] = []
	var retirement_classes: Array[String] = ["ordinary"]
	if record.bundle_sha256().is_empty():
		retirement_classes.append("born_invalidated")
	for retirement_class: String in retirement_classes:
		for drain_state: String in ["not_required", "awaiting_queue_drain"]:
			var candidate: Dictionary = _candidate_quantity_preimage(record, record.slot_kind(), record.bundle_sha256(), retirement_class, drain_state)
			var candidate_sha256: String = _canonical_digest(candidate)
			arms.append({
				"reservation_handle_id": record.handle_id(),
				"retirement_class": retirement_class,
				"drain_state": drain_state,
				"candidate_entry_sha256": candidate_sha256,
				"candidate_root_sha256": _canonical_digest({"candidate_entry_sha256": candidate_sha256}),
				"candidate_root_byte_delta": _canonical_bytes(candidate).size(),
			})
	arms.sort_custom(_arm_less)
	return arms


static func _candidate_quantity_preimage(
	record: ReservationState,
	slot_kind: String,
	bundle_sha256: String,
	retirement_class: String,
	drain_state: String
) -> Dictionary:
	return _candidate_quantity_fields(record.identity_sha256(), record.handle_id(), slot_kind, bundle_sha256, retirement_class, drain_state)


static func _candidate_quantity_fields(
	identity_sha256: String,
	handle_id: String,
	slot_kind: String,
	bundle_sha256: String,
	retirement_class: String,
	drain_state: String
) -> Dictionary:
	var candidate: Dictionary = {
		"reservation_codec_version": RESERVATION_CODEC_VERSION,
		"reservation_handle_id": handle_id,
		"authoring_request_sha256": identity_sha256,
		"reservation_slot_kind": slot_kind,
		"retirement_class": retirement_class,
		"drain_state": drain_state,
		"terminal_record_bytes": TERMINAL_RECORD_BYTES,
		"queue_drain_ticket_slots": 1,
		"resolution_record_slots": 1,
		"frontier_capability_slots": 1,
		"cleanup_cell_slots": 1,
		"delivery_capability_slots": 1,
	}
	if not bundle_sha256.is_empty():
		candidate["execution_bundle_sha256"] = bundle_sha256
	return candidate


static func _specialization_fits(record: ReservationState) -> bool:
	for arm: Dictionary in record.reachable_arms():
		if int(arm.get("candidate_root_byte_delta", 0)) > record.quantity_manifest().value("ledger_byte_delta"):
			return false
	return true


static func _transition_value(state: State, record: ReservationState, transition_kind: String) -> Dictionary:
	return {
		"transition_kind": transition_kind,
		"reservation_handle_id": record.handle_id(),
		"generation": state.generation(),
		"reservation_root_id": String(state.generation_record().get("reservation_root_id", "")),
		"ledger_root": state.ledger_root(),
		"delivery_handle_id": record.delivery_handle_id(),
		"cleanup_cell_id": record.cleanup_cell_id(),
		"cleanup_cell_generation": record.generation(),
		"slot_kind": record.slot_kind(),
		"bundle_specialized": not record.bundle_sha256().is_empty(),
		"charged_headroom": record.quantity_manifest().value("ledger_byte_delta"),
		"lifecycle_state": record.lifecycle_state(),
	}


static func _live_record(state: State, handle_id: String) -> ReservationState:
	var record: ReservationState = state.record_by_handle(handle_id) if state != null else null
	return record if record != null and record.lifecycle_state() == LIVE_STATE else null


static func _derive_slot_kind(state: State, current_occupied: bool, pending_occupied: bool) -> String:
	var current_busy: bool = current_occupied or _count_slot(state, CURRENT_SLOT) > 0
	var pending_busy: bool = pending_occupied or _count_slot(state, PENDING_SLOT) > 0 or _count_slot(state, TOMBSTONE_SLOT) > 0
	if not current_busy:
		return CURRENT_SLOT
	if not pending_busy:
		return PENDING_SLOT
	return ""


static func _count_slot(state: State, slot_kind: String, excluded_identity: String = "") -> int:
	var count: int = 0
	if state == null:
		return count
	for identity_sha256: String in state.records_copy().keys():
		if identity_sha256 == excluded_identity:
			continue
		var record: ReservationState = state.record_by_identity(identity_sha256)
		if record != null and record.slot_kind() == slot_kind:
			count += 1
	return count


static func _idempotency_belongs_to_other(state: State, key: String, identity_sha256: String) -> bool:
	for candidate_identity: String in state.records_copy().keys():
		var record: ReservationState = state.record_by_identity(candidate_identity)
		if record != null and record.idempotency_key() == key and candidate_identity != identity_sha256:
			return true
	return false


static func _used_quantity(state: State, quantity_id: String) -> int:
	var total: int = 0
	for identity_sha256: String in state.records_copy().keys():
		var record: ReservationState = state.record_by_identity(identity_sha256)
		if record != null:
			total += record.quantity_manifest().value(quantity_id)
	return total


static func _make_capacity_limits(overrides: Dictionary) -> Dictionary:
	var limits: Dictionary = {
		"terminal_record_bytes": MAX_TERMINAL_RECORD_BYTES,
		"queue_drain_ticket_slots": MAX_COMPANION_SLOTS,
		"resolution_record_slots": MAX_COMPANION_SLOTS,
		"frontier_capability_slots": MAX_COMPANION_SLOTS,
		"cleanup_cell_slots": MAX_COMPANION_SLOTS,
		"delivery_capability_slots": MAX_COMPANION_SLOTS,
	}
	for key: Variant in overrides.keys():
		if not limits.has(key) or typeof(overrides[key]) != TYPE_INT or int(overrides[key]) < 0:
			return {}
		limits[key] = int(overrides[key])
	return limits


static func _state_metrics(state: State) -> Dictionary:
	return {
		"consumed_count": int(state.generation_record().get("consumed_ledger_count_units", 0)),
		"consumed_bytes": int(state.generation_record().get("consumed_ledger_byte_delta", 0)),
		"residual_count": int(state.generation_record().get("residual_reserved_ledger_count_units", 0)),
		"residual_bytes": int(state.generation_record().get("residual_reserved_ledger_byte_delta", 0)),
	}


static func _make_handle_id(identity_sha256: String, sequence: int) -> String:
	return "reservation-%s" % _canonical_digest({"identity_sha256": identity_sha256, "kind": "request_retirement_reservation", "sequence": sequence}).substr(0, 24)


static func _make_companion_id(handle_id: String, kind: String) -> String:
	return "%s-%s" % [kind, _canonical_digest({"handle": handle_id, "kind": kind}).substr(0, 24)]


static func _identity_is_valid(identity: Dictionary) -> bool:
	return not identity.is_empty() and not _canonical_digest(identity).is_empty()


static func _identity_idempotency_key(identity: Dictionary, identity_sha256: String) -> String:
	for key: String in ["idempotency_key", "request_id", "authoring_request_sha256"]:
		if identity.has(key) and not String(identity[key]).is_empty():
			return String(identity[key])
	return identity_sha256


static func _success(state: State, handle_id: String, value: Dictionary) -> Transition:
	return Transition.new(true, &"", "", state, handle_id, value)


static func _failure(state: State, code: StringName, message: String) -> Transition:
	return Transition.new(false, code, message, state)


static func _owner_entry_less(left: Dictionary, right: Dictionary) -> bool:
	return String(left.get("reservation_handle_id", "")) < String(right.get("reservation_handle_id", ""))


static func _arm_less(left: Dictionary, right: Dictionary) -> bool:
	return _arm_sort_key(left) < _arm_sort_key(right)


static func _arm_sort_key(arm: Dictionary) -> String:
	return "%s|%s|%s|%s" % [arm.get("reservation_handle_id", ""), arm.get("retirement_class", ""), arm.get("drain_state", ""), arm.get("candidate_entry_sha256", "")]


static func _canonical_bytes(value: Dictionary) -> PackedByteArray:
	var result: RefCounted = CANONICAL_CODEC.encode(value)
	return PackedByteArray(result.value()) if result != null and result.is_success() else PackedByteArray()


static func _canonical_digest(value: Dictionary) -> String:
	var bytes: PackedByteArray = _canonical_bytes(value)
	return CANONICAL_CODEC.sha256_hex(bytes) if not bytes.is_empty() else ""


static func _compute_ledger_root(
	ledger_entry_count: int,
	current_reservations: int,
	pending_reservations: int,
	tombstones: int,
	ledger_byte_count: int
) -> String:
	return _canonical_digest({
		"ledger_codec_version": "runtime_retired_ledger_v3",
		"ledger_entry_count": ledger_entry_count,
		"current_reservations": current_reservations,
		"pending_reservations": pending_reservations,
		"tombstones": tombstones,
		"ledger_byte_count": ledger_byte_count,
	})


static func _clone_dictionary(value: Dictionary) -> Dictionary:
	var copied: Variant = IR_TYPE.clone(value)
	return copied if typeof(copied) == TYPE_DICTIONARY else {}


static func _clone_dictionary_array(value: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: Variant in value:
		if typeof(item) == TYPE_DICTIONARY:
			result.append(_clone_dictionary(item))
	return result
