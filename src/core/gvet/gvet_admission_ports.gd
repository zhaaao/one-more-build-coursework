class_name GvetAdmissionPorts
extends RefCounted

## Typed, pure-data seams used by the single GVET admission coordinator.
##
## Ports are intentionally small contract-doubles: production adapters may
## provide a concrete implementation, while deterministic tests subclass these
## RefCounted ports without passing engine objects into Core.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CanonicalCodecType = preload("res://src/foundation/canonical_codec.gd")
const ExecutionBundleProfileType = preload("res://src/core/gvet/execution_bundle_profile_v2.gd")
const ExecutionBundleType = preload("res://src/core/gvet/execution_bundle.gd")
const PreparedRunType = preload("res://src/core/gvet/prepared_run.gd")
const SemanticDiagnosticValidatorType = preload("res://src/core/gvet/semantic_diagnostic_validator.gd")

class AdapterCapability extends RefCounted:
	var _locked: bool = false:
		set(value):
			if _locked:
				return
			_locked = value
	var _active: bool = false:
		set(value):
			if _locked:
				return
			_active = value
	var _token: String = "":
		set(value):
			if _locked:
				return
			_token = value

	## Creates a permanently inactive process-local adapter capability shell.
	## Example: `var capability := GvetAdmissionPorts.AdapterCapability.new()`.
	func _init() -> void:
		_locked = true

	## Creates a deterministic contract-double capability.
	## Example: `var capability := GvetAdmissionPorts.AdapterCapability.for_contract_test("adapter")`.
	static func for_contract_test(token: String) -> AdapterCapability:
		return ContractAdapterCapability.new(token)

	## Returns whether this process-local capability is authorized.
	## Example: `if capability.is_authorized(): proceed()`.
	func is_authorized() -> bool:
		return _active and not _token.is_empty()

class ContractAdapterCapability extends AdapterCapability:
	var _fixture_locked: bool = false:
		set(value):
			if _fixture_locked:
				return
			_fixture_locked = value
	var _fixture_active: bool = false:
		set(value):
			if _fixture_locked:
				return
			_fixture_active = value
	var _fixture_token: String = "":
		set(value):
			if _fixture_locked:
				return
			_fixture_token = value

	func _init(token: String) -> void:
		_fixture_active = not token.is_empty()
		_fixture_token = token if _fixture_active else ""
		_fixture_locked = true

	func is_authorized() -> bool:
		return _fixture_locked and _fixture_active and not _fixture_token.is_empty()

class ReservationCapability extends RefCounted:
	var _locked: bool = false:
		set(value):
			if _locked:
				return
			_locked = value
	var _active: bool = false:
		set(value):
			if _locked:
				return
			_active = value
	var _token: String = "":
		set(value):
			if _locked:
				return
			_token = value

	## Creates a permanently inactive process-local reservation capability shell.
	## Example: `var capability := GvetAdmissionPorts.ReservationCapability.new()`.
	func _init() -> void:
		_locked = true

	## Creates a deterministic contract-double capability.
	## Example: `var capability := GvetAdmissionPorts.ReservationCapability.for_contract_test("reservation")`.
	static func for_contract_test(token: String) -> ReservationCapability:
		return ContractReservationCapability.new(token)

	## Returns whether this process-local capability is authorized.
	## Example: `if capability.is_authorized(): proceed()`.
	func is_authorized() -> bool:
		return _active and not _token.is_empty()

	## Returns the stable owner handle when this is a runtime-issued capability.
	## Example: `var handle := capability.reservation_handle_id()`.
	func reservation_handle_id() -> String:
		return ""

	## Returns the stable handle alias used by process-local callers.
	## Example: `var handle := capability.handle_id()`.
	func handle_id() -> String:
		return reservation_handle_id()

	## Returns the observable joint-reservation generation.
	## Example: `var generation := capability.generation()`.
	func generation() -> int:
		return -1

	## Returns the owner-derived lane role.
	## Example: `var role := capability.reservation_slot_kind()`.
	func reservation_slot_kind() -> String:
		return ""

	## Returns the short lane-role alias.
	## Example: `var role := capability.slot_kind()`.
	func slot_kind() -> String:
		return reservation_slot_kind()

	## Returns the canonical trusted-identity digest bound by the owner.
	## Example: `var identity := capability.authoring_identity_sha256()`.
	func authoring_identity_sha256() -> String:
		return ""

	## Returns the immutable bundle binding carried by a contract fixture, when present.
	## Example: `var digest := capability.bundle_sha256()`.
	func bundle_sha256() -> String:
		return ""

	## Issues one process-local joint reservation capability for the owner.
	## Example: `var capability := ReservationCapability.issue_joint(handle, identity, "current", 1)`.
	static func issue_joint(
		handle_id: String,
		identity_sha256: String,
		slot_kind: String,
		generation: int
	) -> ReservationCapability:
		return IssuedReservationCapability.new(handle_id, identity_sha256, slot_kind, generation)

class ContractReservationCapability extends ReservationCapability:
	var _fixture_locked: bool = false:
		set(value):
			if _fixture_locked:
				return
			_fixture_locked = value
	var _fixture_active: bool = false:
		set(value):
			if _fixture_locked:
				return
			_fixture_active = value
	var _fixture_token: String = "":
		set(value):
			if _fixture_locked:
				return
			_fixture_token = value

	func _init(token: String) -> void:
		_fixture_active = not token.is_empty()
		_fixture_token = token if _fixture_active else ""
		_fixture_locked = true

	func is_authorized() -> bool:
		return _fixture_locked and _fixture_active and not _fixture_token.is_empty()


class IssuedReservationCapability extends ReservationCapability:
	var _fixture_locked: bool = false:
		set(value):
			if not _fixture_locked:
				_fixture_locked = value
	var _fixture_active: bool = false:
		set(value):
			if not _fixture_locked:
				_fixture_active = value
	var _fixture_handle_id: String = "":
		set(value):
			if not _fixture_locked:
				_fixture_handle_id = value
	var _fixture_identity_sha256: String = "":
		set(value):
			if not _fixture_locked:
				_fixture_identity_sha256 = value
	var _fixture_slot_kind: String = "":
		set(value):
			if not _fixture_locked:
				_fixture_slot_kind = value
	var _fixture_generation: int = -1:
		set(value):
			if not _fixture_locked:
				_fixture_generation = value
	var _fixture_bundle_sha256: String = "":
		set(value):
			if not _fixture_locked:
				_fixture_bundle_sha256 = value

	func _init(
		handle_id: String,
		identity_sha256: String,
		slot_kind: String,
		generation: int
	) -> void:
		_fixture_handle_id = handle_id
		_fixture_identity_sha256 = identity_sha256
		_fixture_slot_kind = slot_kind
		_fixture_generation = generation
		_fixture_active = not handle_id.is_empty() and not identity_sha256.is_empty() and (slot_kind == "current" or slot_kind == "pending") and generation >= 0
		_fixture_locked = true

	func is_authorized() -> bool:
		return _fixture_locked and _fixture_active and not _fixture_handle_id.is_empty()

	func reservation_handle_id() -> String:
		return _fixture_handle_id if _fixture_locked else ""

	func generation() -> int:
		return _fixture_generation if is_authorized() else -1

	func reservation_slot_kind() -> String:
		return _fixture_slot_kind if is_authorized() else ""

	func authoring_identity_sha256() -> String:
		return _fixture_identity_sha256 if is_authorized() else ""

	func bundle_sha256() -> String:
		return _fixture_bundle_sha256 if is_authorized() else ""

class SandboxFactoryCapability extends RefCounted:
	var _locked: bool = false:
		set(value):
			if _locked:
				return
			_locked = value
	var _active: bool = false:
		set(value):
			if _locked:
				return
			_active = value
	var _available: bool = false:
		set(value):
			if _locked:
				return
			_available = value
	var _token: String = "":
		set(value):
			if _locked:
				return
			_token = value

	## Creates a permanently unavailable process-local Sandbox factory capability shell.
	## Example: `var capability := GvetAdmissionPorts.SandboxFactoryCapability.new()`.
	func _init() -> void:
		_locked = true

	## Creates a deterministic contract-double capability.
	## Example: `var capability := GvetAdmissionPorts.SandboxFactoryCapability.for_contract_test("factory")`.
	static func for_contract_test(token: String, available: bool = true) -> SandboxFactoryCapability:
		return ContractSandboxFactoryCapability.new(token, available)

	## Returns whether a factory check may succeed.
	## Example: `if capability.is_available(): check_only()`.
	func is_available() -> bool:
		return _active and _available and not _token.is_empty()

class ContractSandboxFactoryCapability extends SandboxFactoryCapability:
	var _fixture_locked: bool = false:
		set(value):
			if _fixture_locked:
				return
			_fixture_locked = value
	var _fixture_active: bool = false:
		set(value):
			if _fixture_locked:
				return
			_fixture_active = value
	var _fixture_available: bool = false:
		set(value):
			if _fixture_locked:
				return
			_fixture_available = value
	var _fixture_token: String = "":
		set(value):
			if _fixture_locked:
				return
			_fixture_token = value

	func _init(token: String, available: bool) -> void:
		_fixture_active = not token.is_empty()
		_fixture_available = _fixture_active and available
		_fixture_token = token if _fixture_active else ""
		_fixture_locked = true

	func is_available() -> bool:
		return _fixture_locked and _fixture_active and _fixture_available and not _fixture_token.is_empty()

class IngressReadPermit extends RefCounted:
	var _locked: bool = false:
		set(value):
			if _locked:
				return
			_locked = value
	var _active: bool = false:
		set(value):
			if _locked:
				return
			_active = value
	var _adapter_capability: AdapterCapability = null:
		set(value):
			if _locked:
				return
			_adapter_capability = value
	var _reservation_capability: ReservationCapability = null:
		set(value):
			if _locked:
				return
			_reservation_capability = value
	var _queue_epoch: String = "":
		set(value):
			if _locked:
				return
			_queue_epoch = value

	## Creates an inactive read-permit shell; only authorization may issue an active permit.
	## Example: `var permit := GvetAdmissionPorts.IngressReadPermit.new()`.
	func _init() -> void:
		_locked = true

	static func issue(adapter_capability: AdapterCapability, reservation_capability: ReservationCapability, queue_epoch: String) -> IngressReadPermit:
		if adapter_capability == null or reservation_capability == null:
			return IssuedIngressReadPermit.new(null, null, "")
		if not adapter_capability.is_authorized() or not reservation_capability.is_authorized() or queue_epoch.is_empty():
			return IssuedIngressReadPermit.new(null, null, "")
		return IssuedIngressReadPermit.new(adapter_capability, reservation_capability, queue_epoch)

	## Returns whether this permit was issued by the typed authorization port.
	## Example: `if permit.is_valid(): read_payload()`.
	func is_valid() -> bool:
		return _active and _adapter_capability != null and _reservation_capability != null and _queue_epoch != "" and _adapter_capability.is_authorized() and _reservation_capability.is_authorized()

	## Returns the queue epoch bound by authorization.
	## Example: `var epoch := permit.queue_epoch()`.
	func queue_epoch() -> String:
		return _queue_epoch

class IssuedIngressReadPermit extends IngressReadPermit:
	var _fixture_locked: bool = false:
		set(value):
			if _fixture_locked:
				return
			_fixture_locked = value
	var _fixture_active: bool = false:
		set(value):
			if _fixture_locked:
				return
			_fixture_active = value
	var _fixture_adapter_capability: AdapterCapability = null:
		set(value):
			if _fixture_locked:
				return
			_fixture_adapter_capability = value
	var _fixture_reservation_capability: ReservationCapability = null:
		set(value):
			if _fixture_locked:
				return
			_fixture_reservation_capability = value
	var _fixture_queue_epoch: String = "":
		set(value):
			if _fixture_locked:
				return
			_fixture_queue_epoch = value

	func _init(adapter_capability: AdapterCapability, reservation_capability: ReservationCapability, queue_epoch: String) -> void:
		_fixture_adapter_capability = adapter_capability
		_fixture_reservation_capability = reservation_capability
		_fixture_queue_epoch = queue_epoch
		_fixture_active = adapter_capability != null and reservation_capability != null and not queue_epoch.is_empty()
		_fixture_locked = true

	func is_valid() -> bool:
		return _fixture_locked and _fixture_active and _fixture_adapter_capability != null and _fixture_reservation_capability != null and not _fixture_queue_epoch.is_empty() and _fixture_adapter_capability.is_authorized() and _fixture_reservation_capability.is_authorized()

	func queue_epoch() -> String:
		return _fixture_queue_epoch

class IngressPayloadSource extends RefCounted:
	## Process-local source handle. Core stores no transport bytes before authority.
	## Runtime adapters and contract-test doubles override read_for after authorization.
	func read_for(permit: IngressReadPermit) -> DomainResult:
		return DomainResultType.failure(&"rejected_unauthorized", "no authorized ingress payload adapter is bound")

	## Base handles expose zero reads; instrumented adapter doubles override this.
	func read_count() -> int:
		return 0

class AdmissionRequest extends RefCounted:
	const IRType = preload("res://src/foundation/canonical_json_ir.gd")

	var _trusted_identity: Dictionary = {}
	var _adapter_capability: AdapterCapability = null
	var _queue_epoch: String = ""
	var _ingress_payload_source: IngressPayloadSource = null
	var _sandbox_factory_capability: SandboxFactoryCapability = null
	var _registry: Dictionary = {}
	var _event_sequence: String = "0"
	var _resolved_registry_projection: Dictionary = {}
	var _task_content_projection: Dictionary = {}
	var _sandbox_projection: Dictionary = {}

	## Creates a detached request containing only trusted identity and pure data.
	## Example: `var request := GvetAdmissionPorts.AdmissionRequest.new(...)`.
	func _init(
		trusted_identity: Dictionary = {},
		adapter_capability: AdapterCapability = null,
		queue_epoch: String = "",
		ingress_payload_source: IngressPayloadSource = null,
		sandbox_factory_capability: SandboxFactoryCapability = null,
		registry: Dictionary = {},
		event_sequence: String = "0",
		resolved_registry_projection: Dictionary = {},
		task_content_projection: Dictionary = {},
		sandbox_projection: Dictionary = {}
	) -> void:
		_trusted_identity = IRType.clone(trusted_identity)
		_adapter_capability = adapter_capability if adapter_capability != null else AdapterCapability.new()
		_queue_epoch = queue_epoch
		_ingress_payload_source = ingress_payload_source if ingress_payload_source != null else IngressPayloadSource.new()
		_sandbox_factory_capability = sandbox_factory_capability if sandbox_factory_capability != null else SandboxFactoryCapability.new()
		_registry = IRType.clone(registry)
		_event_sequence = event_sequence
		_resolved_registry_projection = IRType.clone(resolved_registry_projection)
		_task_content_projection = IRType.clone(task_content_projection)
		_sandbox_projection = IRType.clone(sandbox_projection)

	## Returns the trusted identity before any untrusted payload is inspected.
	## Example: `var identity := request.trusted_identity()`.
	func trusted_identity() -> Dictionary:
		return IRType.clone(_trusted_identity)

	## Returns the process-local adapter capability shell.
	## Example: `var capability := request.adapter_capability()`.
	func adapter_capability() -> AdapterCapability:
		return _adapter_capability

	## Returns the explicit queue epoch bound to the read attempt.
	## Example: `var epoch := request.queue_epoch()`.
	func queue_epoch() -> String:
		return _queue_epoch

	## Returns the opaque ingress payload source; bytes are readable only with an authorized permit.
	## Example: `var source := request.ingress_payload_source()`.
	func ingress_payload_source() -> IngressPayloadSource:
		return _ingress_payload_source

	## Returns the process-local capability that the non-allocating factory check authenticates.
	## Example: `var factory := request.sandbox_factory_capability()`.
	func sandbox_factory_capability() -> SandboxFactoryCapability:
		return _sandbox_factory_capability

	## Returns the immutable semantic registry projection used by validation.
	## Example: `var registry := request.registry()`.
	func registry() -> Dictionary:
		return IRType.clone(_registry)

	## Returns the canonical decimal event sequence for the report identity.
	## Example: `var sequence := request.event_sequence()`.
	func event_sequence() -> String:
		return _event_sequence

	## Returns the existing resolved-registry/proof projection without aliases.
	## Example: `var resolved := request.resolved_registry_projection()`.
	func resolved_registry_projection() -> Dictionary:
		return IRType.clone(_resolved_registry_projection)

	## Returns the immutable Task/content preimage projection.
	## Example: `var content := request.task_content_projection()`.
	func task_content_projection() -> Dictionary:
		return IRType.clone(_task_content_projection)

	## Returns the immutable Sandbox catalog/preimage projection.
	## Example: `var sandbox := request.sandbox_projection()`.
	func sandbox_projection() -> Dictionary:
		return IRType.clone(_sandbox_projection)

class ContentAdmissionReceipt extends RefCounted:
	const IRType = preload("res://src/foundation/canonical_json_ir.gd")

	var _locked: bool = false:
		set(value):
			if _locked:
				return
			_locked = value
	var _resolved_registry_projection: Dictionary = {}:
		get:
			var copied: Variant = IRType.clone(_resolved_registry_projection)
			return copied if typeof(copied) == TYPE_DICTIONARY else {}
		set(value):
			if _locked:
				return
			var copied: Variant = IRType.clone(value)
			_resolved_registry_projection = copied if typeof(copied) == TYPE_DICTIONARY else {}
	var _task_content_projection: Dictionary = {}:
		get:
			var copied: Variant = IRType.clone(_task_content_projection)
			return copied if typeof(copied) == TYPE_DICTIONARY else {}
		set(value):
			if _locked:
				return
			var copied: Variant = IRType.clone(value)
			_task_content_projection = copied if typeof(copied) == TYPE_DICTIONARY else {}
	var _sandbox_projection: Dictionary = {}:
		get:
			var copied: Variant = IRType.clone(_sandbox_projection)
			return copied if typeof(copied) == TYPE_DICTIONARY else {}
		set(value):
			if _locked:
				return
			var copied: Variant = IRType.clone(value)
			_sandbox_projection = copied if typeof(copied) == TYPE_DICTIONARY else {}
	var _binding_sha256: String = "":
		set(value):
			if _locked:
				return
			_binding_sha256 = value

	## Issues a detached content-authority receipt after exact pure validation.
	## Example: `var result := ContentAdmissionReceipt.issue(resolved, content, sandbox)`.
	static func issue(
		resolved_registry_projection: Dictionary,
		task_content_projection: Dictionary,
		sandbox_projection: Dictionary
	) -> DomainResult:
		var catalog_result: DomainResult = _validate_resolved_registry_projection(resolved_registry_projection)
		if not catalog_result.is_success():
			return catalog_result
		var binding: Dictionary = {
			"resolved_registry_projection": IRType.clone(resolved_registry_projection),
			"task_content_projection": IRType.clone(task_content_projection),
			"sandbox_projection": IRType.clone(sandbox_projection),
		}
		var pure_result: DomainResult = _validate_pure_projection(binding)
		if not pure_result.is_success():
			return pure_result
		var encoded_result: DomainResult = CanonicalCodecType.encode(binding)
		if not encoded_result.is_success():
			return DomainResultType.failure(&"content_binding_invalid", "content projections are not canonicalizable")
		var binding_bytes: PackedByteArray = PackedByteArray(encoded_result.value())
		var binding_sha256: String = CanonicalCodecType.sha256_hex(binding_bytes)
		var receipt: ContentAdmissionReceipt = ContentAdmissionReceipt.new(
			resolved_registry_projection,
			task_content_projection,
			sandbox_projection,
			binding_sha256
		)
		if not receipt.is_valid():
			return DomainResultType.failure(&"content_binding_invalid", "content authority receipt did not commit")
		return DomainResultType.success(receipt)

	func _init(
		resolved_registry_projection: Dictionary = {},
		task_content_projection: Dictionary = {},
		sandbox_projection: Dictionary = {},
		binding_sha256: String = ""
	) -> void:
		var catalog_result: DomainResult = _validate_resolved_registry_projection(resolved_registry_projection)
		if not catalog_result.is_success():
			_locked = true
			return
		var binding: Dictionary = {
			"resolved_registry_projection": IRType.clone(resolved_registry_projection),
			"task_content_projection": IRType.clone(task_content_projection),
			"sandbox_projection": IRType.clone(sandbox_projection),
		}
		var pure_result: DomainResult = _validate_pure_projection(binding)
		if not pure_result.is_success():
			_locked = true
			return
		var encoded_result: DomainResult = CanonicalCodecType.encode(binding)
		if not encoded_result.is_success():
			_locked = true
			return
		var binding_bytes: PackedByteArray = PackedByteArray(encoded_result.value())
		if CanonicalCodecType.sha256_hex(binding_bytes) != binding_sha256:
			_locked = true
			return
		_resolved_registry_projection = IRType.clone(resolved_registry_projection)
		_task_content_projection = IRType.clone(task_content_projection)
		_sandbox_projection = IRType.clone(sandbox_projection)
		_binding_sha256 = binding_sha256
		_locked = true

	## Returns whether this receipt was issued from a canonical content binding.
	## Example: `if receipt.is_valid(): build_prepared_run(receipt)`.
	func is_valid() -> bool:
		return _locked and not _binding_sha256.is_empty()

	static func _validate_resolved_registry_projection(projection: Dictionary) -> DomainResult:
		if projection.is_empty():
			return DomainResultType.failure(
				&"catalog_missing", "resolved-registry projection is required")
		return _validate_pure_projection(projection)

	static func _validate_pure_projection(projection: Variant) -> DomainResult:
		var pure_result: DomainResult = IRType.validate_pure_json(projection)
		if not pure_result.is_success():
			return DomainResultType.failure(
				&"content_binding_invalid", "content projections must be pure JSON")
		return DomainResultType.success(true)

	## Returns the detached resolved-registry/proof projection authorized by content.
	## Example: `var resolved := receipt.resolved_registry_projection()`.
	func resolved_registry_projection() -> Dictionary:
		return IRType.clone(_resolved_registry_projection)

	## Returns the detached Task/content projection authorized by content.
	## Example: `var content := receipt.task_content_projection()`.
	func task_content_projection() -> Dictionary:
		return IRType.clone(_task_content_projection)

	## Returns the detached Sandbox projection authorized by content.
	## Example: `var sandbox := receipt.sandbox_projection()`.
	func sandbox_projection() -> Dictionary:
		return IRType.clone(_sandbox_projection)

	## Returns the lowercase digest binding all three authorized projections.
	## Example: `var digest := receipt.binding_sha256()`.
	func binding_sha256() -> String:
		return _binding_sha256

class PreliveReservationOwner extends RefCounted:
	const ResultType = preload("res://src/foundation/domain_result.gd")

	## Requests one pre-live grant from a typed owner boundary.
	## Example: `var result := owner.reserve(trusted_identity)`.
	func reserve(_trusted_identity: Dictionary) -> DomainResult:
		return ResultType.failure(&"request_resource_limit", "pre-live reservation authority is unavailable")


class PreliveReservationPort extends RefCounted:
	const ResultType = preload("res://src/foundation/domain_result.gd")
	var _reservation_owner: PreliveReservationOwner = null

	func _init(reservation_owner: PreliveReservationOwner = null) -> void:
		_reservation_owner = reservation_owner

	## Binds the owner used by this process-local port.
	## Example: `port.bind_owner(runtime_owner)`.
	func bind_owner(reservation_owner: PreliveReservationOwner) -> void:
		_reservation_owner = reservation_owner

	## Reserves bounded pre-live capacity through the runtime-owned capability seam.
	## Example: `var result := reservation_port.reserve(request.trusted_identity())`.
	func reserve(trusted_identity: Dictionary) -> DomainResult:
		if _reservation_owner != null:
			return _reservation_owner.reserve(trusted_identity)
		return ResultType.failure(&"request_resource_limit", "pre-live reservation authority is unavailable in the pure default port")

class IngressReadAuthorizationPort extends RefCounted:
	const ResultType = preload("res://src/foundation/domain_result.gd")

	## Authenticates the three-input read gate without reading payload bytes.
	## Example: `var result := read_port.authorize_read(capability, reservation, epoch)`.
	func authorize_read(adapter_capability: AdapterCapability, request_reservation: ReservationCapability, queue_epoch: String) -> DomainResult:
		return ResultType.failure(&"rejected_unauthorized", "read permit authority is unavailable in the pure default port")

	## Reads the opaque payload only after the typed permit has been issued.
	## Example: `var bytes := read_port.read_payload(source, permit)`.
	func read_payload(source: IngressPayloadSource, permit: IngressReadPermit) -> DomainResult:
		return ResultType.failure(&"rejected_unauthorized", "payload read authority is unavailable in the pure default port")

class BundleCodecPort extends RefCounted:
	const ResultType = preload("res://src/foundation/domain_result.gd")
	const ProfileType = preload("res://src/core/gvet/execution_bundle_profile_v2.gd")

	## Decodes and constructs exactly one immutable ExecutionBundle.
	## Example: `var result := codec_port.decode(read_result.value())`.
	func decode(raw_payload: PackedByteArray) -> DomainResult:
		return ProfileType.construct_from_bytes(raw_payload)

class ContractAdmissionPort extends RefCounted:
	const ResultType = preload("res://src/foundation/domain_result.gd")
	const ProfileType = preload("res://src/core/gvet/execution_bundle_profile_v2.gd")

	## Checks immutable bundle identity and cross-system contract bindings.
	## Example: `var result := contract_port.validate(bundle, request)`.
	func validate(bundle: ExecutionBundle, request: AdmissionRequest) -> DomainResult:
		if bundle == null or not is_instance_valid(bundle) or not bundle.is_valid():
			return ResultType.failure(&"invalid_bundle", "contract admission requires a valid ExecutionBundle")
		var result: DomainResult = ProfileType.validate_normalized_fields(bundle.to_dictionary())
		if not result.is_success():
			return result
		var projection: Dictionary = request.resolved_registry_projection()
		if projection.has("contract_valid") and projection["contract_valid"] == false:
			return ResultType.failure(&"contract_binding_mismatch", "resolved contract projection is invalid", "$.resolved_registry_projection")
		return ResultType.success(true)

class ContentAdmissionPort extends RefCounted:
	const ResultType = preload("res://src/foundation/domain_result.gd")

	## Resolves and validates authoritative content projections without runtime state.
	## Example: `var result := content_port.resolve_and_validate(bundle, request)`.
	func resolve_and_validate(bundle: ExecutionBundle, request: AdmissionRequest) -> DomainResult:
		return ResultType.failure(&"content_invalid", "content admission authority is unavailable in the pure default port")

class SandboxFactoryAvailabilityPort extends RefCounted:
	const ResultType = preload("res://src/foundation/domain_result.gd")

	## Checks factory capability without creating, resetting, or mutating a Sandbox.
	## Example: `var result := factory_port.check(bundle, request.sandbox_factory_capability())`.
	func check(bundle: ExecutionBundle, capability: SandboxFactoryCapability) -> DomainResult:
		return ResultType.failure(&"factory_unavailable", "Sandbox factory authority is unavailable in the pure default port", "$.sandbox_factory_capability")

class SemanticValidationPort extends RefCounted:
	const ResultType = preload("res://src/foundation/domain_result.gd")

	## Performs the one semantic validation pass after all earlier phases pass.
	## Example: `var result := semantic_port.validate(bundle, registry, "0")`.
	func validate(_bundle: ExecutionBundle, _registry: Dictionary, _event_sequence: String) -> DomainResult:
		return ResultType.failure(
			&"legacy_semantic_admission_unavailable",
			"legacy ExecutionBundle semantic admission is superseded by CourseworkRunInput validation")

var _reservation_port: PreliveReservationPort
var _read_port: IngressReadAuthorizationPort
var _codec_port: BundleCodecPort
var _contract_port: ContractAdmissionPort
var _content_port: ContentAdmissionPort
var _factory_port: SandboxFactoryAvailabilityPort
var _semantic_port: SemanticValidationPort

## Creates one production port set with pure default implementations.
## Example: `var ports := GvetAdmissionPorts.production_defaults()`.
static func production_defaults() -> GvetAdmissionPorts:
	return GvetAdmissionPorts.new()


## Creates ports backed by one runtime session owner.
## Example: `var ports := GvetAdmissionPorts.for_runtime_owner(owner)`.
static func for_runtime_owner(reservation_owner: PreliveReservationOwner) -> GvetAdmissionPorts:
	return GvetAdmissionPorts.new(null, null, null, null, null, null, null, reservation_owner)

## Injects all typed admission seams; omitted ports use pure defaults.
## Example: `var ports := GvetAdmissionPorts.new(my_reservation, my_read)`.
func _init(
	reservation_port: PreliveReservationPort = null,
	read_port: IngressReadAuthorizationPort = null,
	codec_port: BundleCodecPort = null,
	contract_port: ContractAdmissionPort = null,
	content_port: ContentAdmissionPort = null,
	factory_port: SandboxFactoryAvailabilityPort = null,
	semantic_port: SemanticValidationPort = null,
	reservation_owner: PreliveReservationOwner = null
) -> void:
	_reservation_port = reservation_port if reservation_port != null else PreliveReservationPort.new(reservation_owner)
	_read_port = read_port if read_port != null else IngressReadAuthorizationPort.new()
	_codec_port = codec_port if codec_port != null else BundleCodecPort.new()
	_contract_port = contract_port if contract_port != null else ContractAdmissionPort.new()
	_content_port = content_port if content_port != null else ContentAdmissionPort.new()
	_factory_port = factory_port if factory_port != null else SandboxFactoryAvailabilityPort.new()
	_semantic_port = semantic_port if semantic_port != null else SemanticValidationPort.new()

## Returns the pre-live reservation seam.
## Example: `ports.reservation_port().reserve(identity)`.
func reservation_port() -> PreliveReservationPort:
	return _reservation_port

## Returns the ingress read authorization seam.
## Example: `ports.read_port().authorize_read(capability, reservation, epoch)`.
func read_port() -> IngressReadAuthorizationPort:
	return _read_port

## Returns the Foundation/GVET bundle codec seam.
## Example: `ports.codec_port().decode(payload)`.
func codec_port() -> BundleCodecPort:
	return _codec_port

## Returns the ordered contract/binding seam.
## Example: `ports.contract_port().validate(bundle, request)`.
func contract_port() -> ContractAdmissionPort:
	return _contract_port

## Returns the ordered content/resource seam.
## Example: `ports.content_port().resolve_and_validate(bundle, request)`.
func content_port() -> ContentAdmissionPort:
	return _content_port

## Returns the non-allocating Sandbox factory seam.
## Example: `ports.factory_port().check(bundle, capability)`.
func factory_port() -> SandboxFactoryAvailabilityPort:
	return _factory_port

## Returns the exactly-once semantic validation seam.
## Example: `ports.semantic_port().validate(bundle, registry, "0")`.
func semantic_port() -> SemanticValidationPort:
	return _semantic_port
