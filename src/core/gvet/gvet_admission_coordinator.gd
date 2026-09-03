class_name GvetAdmissionCoordinator
extends RefCounted

## Sole production entry for ordered GVET admission.
##
## The coordinator performs reservation, read authorization, codec/bundle
## construction, contract, content, factory, semantic, and PreparedRun phases
## in one fixed order. It has no session/store/event/Sandbox mutation seam.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const PortsType = preload("res://src/core/gvet/gvet_admission_ports.gd")
const DiagnosticType = preload("res://src/core/gvet/gvet_admission_diagnostic.gd")
const ExecutionBundleType = preload("res://src/core/gvet/execution_bundle.gd")
const SemanticValidationReportType = preload("res://src/core/gvet/semantic_validation_report.gd")

var _ports: GvetAdmissionPorts

## Creates a coordinator with injectable typed pure-data ports.
## Example: `var coordinator := GvetAdmissionCoordinator.new(ports)`.
func _init(ports: GvetAdmissionPorts = null) -> void:
	_ports = ports if ports != null else PortsType.production_defaults()

## Admits one request through the fixed ordered contract.
## Example: `var result := coordinator.admit(request); if result.is_success(): use(result.prepared_run())`.
func admit(request: GvetAdmissionPorts.AdmissionRequest) -> GvetAdmissionDiagnostic.AdmissionResult:
	if request == null or not is_instance_valid(request):
		return _rejected(DiagnosticType.from_result(
			DiagnosticType.OUTCOME_EXECUTION_CONTRACT_MISMATCH,
			&"request",
			DomainResultType.failure(&"invalid_request", "admission requires a detached AdmissionRequest")
		))

	var reservation_result: DomainResult = _ports.reservation_port().reserve(request.trusted_identity())
	if not reservation_result.is_success():
		return _rejected(DiagnosticType.from_result(DiagnosticType.OUTCOME_REQUEST_RESOURCE_LIMIT, &"reservation", reservation_result))
	var reservation_value: Variant = reservation_result.value()
	if not reservation_value is PortsType.ReservationCapability:
		return _rejected(_invalid_phase_result(DiagnosticType.OUTCOME_REQUEST_RESOURCE_LIMIT, &"reservation", &"reservation port returned a non-record"))
	var reservation_capability: PortsType.ReservationCapability = reservation_value

	var read_result: DomainResult = _ports.read_port().authorize_read(
		request.adapter_capability(),
		reservation_capability,
		request.queue_epoch()
	)
	if not read_result.is_success():
		return _rejected(DiagnosticType.from_result(StringName(read_result.error_code()), &"read_authorization", read_result))
	var permit_value: Variant = read_result.value()
	if not permit_value is PortsType.IngressReadPermit:
		return _rejected(_invalid_phase_result(&"rejected_unauthorized", &"read_authorization", &"read port returned no typed permit"))
	var permit: PortsType.IngressReadPermit = permit_value
	var payload_result: DomainResult = _ports.read_port().read_payload(request.ingress_payload_source(), permit)
	if not payload_result.is_success():
		return _rejected(DiagnosticType.from_result(StringName(payload_result.error_code()), &"read_payload", payload_result))
	var payload_value: Variant = payload_result.value()
	if typeof(payload_value) != TYPE_PACKED_BYTE_ARRAY:
		return _rejected(_invalid_phase_result(&"rejected_unauthorized", &"read_payload", &"read port returned no bounded payload"))
	var raw_payload: PackedByteArray = payload_value

	var codec_result: DomainResult = _ports.codec_port().decode(raw_payload)
	if not codec_result.is_success():
		return _rejected(DiagnosticType.from_result(DiagnosticType.OUTCOME_EXECUTION_CONTRACT_MISMATCH, &"codec", codec_result))
	var bundle_value: Variant = codec_result.value()
	if not bundle_value is ExecutionBundleType:
		return _rejected(_invalid_phase_result(DiagnosticType.OUTCOME_EXECUTION_CONTRACT_MISMATCH, &"codec", &"codec port returned no ExecutionBundle"))
	var bundle: ExecutionBundle = bundle_value
	if not bundle.is_valid():
		return _rejected(_invalid_phase_result(DiagnosticType.OUTCOME_EXECUTION_CONTRACT_MISMATCH, &"codec", &"codec port returned an invalid ExecutionBundle"))

	var contract_result: DomainResult = _ports.contract_port().validate(bundle, request)
	if not contract_result.is_success():
		return _rejected(DiagnosticType.from_result(DiagnosticType.OUTCOME_EXECUTION_CONTRACT_MISMATCH, &"contract", contract_result))

	var content_result: DomainResult = _ports.content_port().resolve_and_validate(bundle, request)
	if not content_result.is_success():
		return _rejected(DiagnosticType.from_result(DiagnosticType.OUTCOME_CASE_CONTENT_INVALID, &"content", content_result))
	var content_receipt_value: Variant = content_result.value()
	if not content_receipt_value is PortsType.ContentAdmissionReceipt:
		return _rejected(_invalid_phase_result(DiagnosticType.OUTCOME_CASE_CONTENT_INVALID, &"content", &"content port returned no authoritative receipt"))
	var content_receipt: PortsType.ContentAdmissionReceipt = content_receipt_value
	if not content_receipt.is_valid():
		return _rejected(_invalid_phase_result(DiagnosticType.OUTCOME_CASE_CONTENT_INVALID, &"content", &"content port returned an invalid authoritative receipt"))

	var factory_result: DomainResult = _ports.factory_port().check(bundle, request.sandbox_factory_capability())
	if not factory_result.is_success():
		return _rejected(DiagnosticType.from_result(DiagnosticType.OUTCOME_SANDBOX_PREPARATION_FAILED, &"factory", factory_result))

	var semantic_result: DomainResult = _ports.semantic_port().validate(bundle, request.registry(), request.event_sequence())
	if not semantic_result.is_success():
		return _rejected(DiagnosticType.from_result(DiagnosticType.OUTCOME_EXECUTION_CONTRACT_MISMATCH, &"semantic", semantic_result))
	var report_value: Variant = semantic_result.value()
	if not report_value is SemanticValidationReportType:
		return _rejected(_invalid_phase_result(DiagnosticType.OUTCOME_EXECUTION_CONTRACT_MISMATCH, &"semantic", &"semantic port returned no validation report"))
	var report: SemanticValidationReport = report_value
	if not report.is_valid():
		return _rejected(_invalid_phase_result(DiagnosticType.OUTCOME_EXECUTION_CONTRACT_MISMATCH, &"semantic", &"semantic port returned an invalid validation report"))
	if report.execution_blocked():
		return _rejected(DiagnosticType.semantic_failure(report))

	return _rejected(_invalid_phase_result(
		DiagnosticType.OUTCOME_EXECUTION_CONTRACT_MISMATCH,
		&"prepared_run",
		&"legacy ExecutionBundle admission cannot construct the current coursework PreparedRun"
	))

func _rejected(diagnostic: GvetAdmissionDiagnostic) -> GvetAdmissionDiagnostic.AdmissionResult:
	return DiagnosticType.AdmissionResult.failure(diagnostic)

static func _invalid_phase_result(outcome_code: StringName, phase: StringName, message: String, witness: Dictionary = {}) -> GvetAdmissionDiagnostic:
	var result: DomainResult = DomainResultType.failure(&"invalid_port_result", message)
	return DiagnosticType.from_result(outcome_code, phase, result, witness)
