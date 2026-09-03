class_name ExecutionBundleProfileV2
extends RefCounted

## GVET-owned closed profile for `execution_bundle_v2`.
##
## Foundation remains generic: this profile supplies the fourteen field names,
## stable version values, identity/hash relationships, and task-day domain.

const CODEC_VERSION: String = "execution_bundle_v2"
const RUNTIME_CODEC_VERSION: String = "runtime_json_v1"
const VALID_TASK_DAY_MINIMUM: int = 1
const VALID_TASK_DAY_MAXIMUM: int = 5

## Returns the declarative root profile used by the Foundation codec.
## Example: `var profile := ExecutionBundleProfileV2.shape_profile()`.
static func shape_profile() -> ContractShapeProfile:
	var json_rule: Dictionary = {"kind": ContractShapeProfile.KIND_JSON}
	var hash_rule: Dictionary = {"kind": ContractShapeProfile.KIND_HASH}
	var public_case_item_rule: Dictionary = {
		"kind": ContractShapeProfile.KIND_OBJECT,
		"fields": {
			"test_case_id": {"kind": ContractShapeProfile.KIND_STRING},
			"case_definition_sha256": hash_rule,
		},
	}
	var public_case_manifest_rule: Dictionary = {
		"kind": ContractShapeProfile.KIND_ARRAY,
		"minimum": 1,
		"maximum": 16,
		"items": public_case_item_rule,
	}
	var parameter_value_rule: Dictionary = {
		"kind": ContractShapeProfile.KIND_OBJECT,
		"fields": {
			"parameter_id": {"kind": ContractShapeProfile.KIND_STRING},
			"value": json_rule,
		},
	}
	var graph_node_rule: Dictionary = {
		"kind": ContractShapeProfile.KIND_OBJECT,
		"fields": {
			"node_id": {"kind": ContractShapeProfile.KIND_STRING},
			"variant_id": {"kind": ContractShapeProfile.KIND_STRING},
			"anchor_x": {"kind": ContractShapeProfile.KIND_NUMBER},
			"anchor_y": {"kind": ContractShapeProfile.KIND_NUMBER},
			"parameter_values": {"kind": ContractShapeProfile.KIND_ARRAY, "items": parameter_value_rule},
		},
	}
	var graph_connection_rule: Dictionary = {
		"kind": ContractShapeProfile.KIND_OBJECT,
		"fields": {
			"connection_id": {"kind": ContractShapeProfile.KIND_STRING},
			"source_node_id": {"kind": ContractShapeProfile.KIND_STRING},
			"source_port_id": {"kind": ContractShapeProfile.KIND_STRING},
			"target_node_id": {"kind": ContractShapeProfile.KIND_STRING},
			"target_port_id": {"kind": ContractShapeProfile.KIND_STRING},
		},
	}
	var graph_rule: Dictionary = {
		"kind": ContractShapeProfile.KIND_OBJECT,
		"fields": {
			"graph_codec_version": {"kind": ContractShapeProfile.KIND_STRING},
			"fixture_id": {"kind": ContractShapeProfile.KIND_STRING},
			"nodes": {"kind": ContractShapeProfile.KIND_ARRAY, "items": graph_node_rule},
			"connections": {"kind": ContractShapeProfile.KIND_ARRAY, "items": graph_connection_rule},
		},
	}
	var request_rule: Dictionary = {
		"kind": ContractShapeProfile.KIND_OBJECT,
		"fields": {
			"request_codec_version": {"kind": ContractShapeProfile.KIND_STRING},
			"request_kind": {"kind": ContractShapeProfile.KIND_STRING},
			"session_id": {"kind": ContractShapeProfile.KIND_STRING},
			"task_id": {"kind": ContractShapeProfile.KIND_STRING},
			"request_id": {"kind": ContractShapeProfile.KIND_STRING},
			"live_revision": {"kind": ContractShapeProfile.KIND_U64},
			"case_suite_sha256": {"kind": ContractShapeProfile.KIND_HASH},
			"authoring_package_binding_sha256": {"kind": ContractShapeProfile.KIND_HASH},
			"case_roster": {"kind": ContractShapeProfile.KIND_ARRAY, "minimum": 1, "maximum": 16, "items": {"kind": ContractShapeProfile.KIND_STRING}},
			"request_progress_timeout": json_rule,
			"request_absolute_timeout": json_rule,
		},
	}
	var package_binding_rule: Dictionary = {
		"kind": ContractShapeProfile.KIND_OBJECT,
		"fields": {
			"binding_codec_version": {"kind": ContractShapeProfile.KIND_STRING},
			"task_fixture_sha256": {"kind": ContractShapeProfile.KIND_HASH},
			"registry_sha256": {"kind": ContractShapeProfile.KIND_HASH},
			"display_production_binding_sha256": {"kind": ContractShapeProfile.KIND_HASH},
			"authoring_viewport_profile_fixture_sha256": {"kind": ContractShapeProfile.KIND_HASH},
			"viewport_certificate_sha256": {"kind": ContractShapeProfile.KIND_HASH},
			"authoring_admission_sha256": {"kind": ContractShapeProfile.KIND_HASH},
			"authoring_display_source_manifest_sha256": {"kind": ContractShapeProfile.KIND_HASH},
			"authoring_package_source_projection_sha256": {"kind": ContractShapeProfile.KIND_HASH},
			"formatter_domain_coverage_manifest_sha256": {"kind": ContractShapeProfile.KIND_HASH},
		},
	}
	var argument_binding_rule: Dictionary = {
		"kind": ContractShapeProfile.KIND_OBJECT,
		"fields": {
			"argument_index": {"kind": ContractShapeProfile.KIND_INTEGER},
			"source_kind": {"kind": ContractShapeProfile.KIND_STRING},
			"source_id": {"kind": ContractShapeProfile.KIND_STRING},
			"sandbox_argument_fact_id": {"kind": ContractShapeProfile.KIND_STRING},
		},
	}
	var action_binding_rule: Dictionary = {
		"kind": ContractShapeProfile.KIND_OBJECT,
		"fields": {
			"authoring_variant_id": {"kind": ContractShapeProfile.KIND_STRING},
			"sandbox_action_variant_id": {"kind": ContractShapeProfile.KIND_STRING},
			"argument_bindings": {"kind": ContractShapeProfile.KIND_ARRAY, "items": argument_binding_rule},
		},
	}
	var query_binding_rule: Dictionary = {
		"kind": ContractShapeProfile.KIND_OBJECT,
		"fields": {
			"authoring_variant_id": {"kind": ContractShapeProfile.KIND_STRING},
			"sandbox_action_variant_id": {"kind": ContractShapeProfile.KIND_STRING},
			"argument_bindings": {"kind": ContractShapeProfile.KIND_ARRAY, "items": argument_binding_rule},
			"authoring_output_port_id": {"kind": ContractShapeProfile.KIND_STRING},
			"sandbox_produced_fact_id": {"kind": ContractShapeProfile.KIND_STRING},
		},
	}
	var compare_binding_rule: Dictionary = {
		"kind": ContractShapeProfile.KIND_OBJECT,
		"fields": {
			"authoring_variant_id": {"kind": ContractShapeProfile.KIND_STRING},
			"authoring_operator_id": {"kind": ContractShapeProfile.KIND_STRING},
			"comparison_operator_id": {"kind": ContractShapeProfile.KIND_STRING},
		},
	}
	var validator_binding_rule: Dictionary = {
		"kind": ContractShapeProfile.KIND_OBJECT,
		"fields": {
			"binding_codec_version": {"kind": ContractShapeProfile.KIND_STRING},
			"authoring_registry_sha256": hash_rule,
			"sandbox_catalog_sha256": hash_rule,
			"task_compare_operator_projection_sha256": hash_rule,
			"action_bindings": {"kind": ContractShapeProfile.KIND_ARRAY, "items": action_binding_rule},
			"query_bindings": {"kind": ContractShapeProfile.KIND_ARRAY, "items": query_binding_rule},
			"compare_bindings": {"kind": ContractShapeProfile.KIND_ARRAY, "items": compare_binding_rule},
		},
	}
	var resource_maxima_rule: Dictionary = {
		"kind": ContractShapeProfile.KIND_OBJECT,
		"fields": {
			"maximum_diagnostic_count": {"kind": ContractShapeProfile.KIND_INTEGER},
			"maximum_validation_report_bytes": {"kind": ContractShapeProfile.KIND_INTEGER},
			"maximum_case_count": {"kind": ContractShapeProfile.KIND_INTEGER},
			"maximum_steps_per_case": {"kind": ContractShapeProfile.KIND_INTEGER},
			"maximum_facts_per_array": {"kind": ContractShapeProfile.KIND_INTEGER},
			"maximum_observation_bytes": {"kind": ContractShapeProfile.KIND_INTEGER},
			"maximum_domain_detail_bytes": {"kind": ContractShapeProfile.KIND_INTEGER},
			"maximum_assertions_per_case": {"kind": ContractShapeProfile.KIND_INTEGER},
			"maximum_case_trace_bytes": {"kind": ContractShapeProfile.KIND_INTEGER},
			"maximum_case_result_bytes": {"kind": ContractShapeProfile.KIND_INTEGER},
			"maximum_request_summary_bytes": {"kind": ContractShapeProfile.KIND_INTEGER},
			"maximum_runtime_result_store_bytes": {"kind": ContractShapeProfile.KIND_INTEGER},
			"maximum_downstream_events": {"kind": ContractShapeProfile.KIND_INTEGER},
			"maximum_ingress_attempts": {"kind": ContractShapeProfile.KIND_INTEGER},
		},
	}
	var resource_core_rule: Dictionary = {
		"kind": ContractShapeProfile.KIND_OBJECT,
		"fields": {
			"core_codec_version": {"kind": ContractShapeProfile.KIND_STRING},
			"runtime_codec_version": {"kind": ContractShapeProfile.KIND_STRING},
			"runtime_ingress_limits_version": {"kind": ContractShapeProfile.KIND_STRING},
			"authoring_contract_version": {"kind": ContractShapeProfile.KIND_STRING},
			"registry_sha256": hash_rule,
			"task_content_contract_version": {"kind": ContractShapeProfile.KIND_STRING},
			"sandbox_catalog_sha256": hash_rule,
			"validator_executor_contract_version": {"kind": ContractShapeProfile.KIND_STRING},
			"display_production_binding_sha256": hash_rule,
			"declared_resource_maxima": resource_maxima_rule,
			"resource_requirement_catalog_sha256": hash_rule,
			"runtime_state_requirement_denominator_sha256": hash_rule,
			"runtime_state_requirement_catalog_sha256": hash_rule,
			"constraint_catalog_sha256": hash_rule,
			"resource_proof_pack_id": {"kind": ContractShapeProfile.KIND_STRING},
			"verifier_contract_version": {"kind": ContractShapeProfile.KIND_STRING},
		},
	}
	var resource_compatibility_rule: Dictionary = {
		"kind": ContractShapeProfile.KIND_OBJECT,
		"fields": {
			"compatibility_codec_version": {"kind": ContractShapeProfile.KIND_STRING},
			"resource_compatibility_core": resource_core_rule,
			"resource_compatibility_core_sha256": hash_rule,
		},
	}
	var rules: Dictionary = {
		&"execution_bundle_codec_version": {"kind": ContractShapeProfile.KIND_STRING},
		&"runtime_codec_version": {"kind": ContractShapeProfile.KIND_STRING},
		&"authoring_request": request_rule,
		&"graph": graph_rule,
		&"task_fixture_sha256": {"kind": ContractShapeProfile.KIND_HASH},
		&"registry_sha256": {"kind": ContractShapeProfile.KIND_HASH},
		&"authoring_package_binding": package_binding_rule,
		&"validator_executor_contract_version": {"kind": ContractShapeProfile.KIND_STRING},
		&"validator_executor_binding": validator_binding_rule,
		&"task_content_contract_version": {"kind": ContractShapeProfile.KIND_STRING},
		&"sandbox_catalog_sha256": {"kind": ContractShapeProfile.KIND_HASH},
		&"resource_compatibility": resource_compatibility_rule,
		&"task_day_index": {"kind": ContractShapeProfile.KIND_INTEGER},
		&"public_case_manifest": public_case_manifest_rule,
	}
	var profile_result := ContractShapeProfile.create(ExecutionBundle.FIELD_NAMES, rules)
	return profile_result.value() if profile_result.is_success() else null

## Decodes raw bytes and constructs the immutable bundle in one pure operation.
## Example: `ExecutionBundleProfileV2.construct_from_bytes(raw_bytes)`.
static func construct_from_bytes(raw_bytes: PackedByteArray) -> DomainResult:
	return ExecutionBundle.create_from_raw(raw_bytes)

## Constructs a bundle from a validated canonical document.
## Example: `ExecutionBundleProfileV2.construct(document_result.value())`.
static func construct(document: ValidatedCanonicalDocument) -> DomainResult:
	if document == null or not is_instance_valid(document) or not document.is_valid():
		return DomainResult.failure(&"invalid_document", "bundle construction requires a validated canonical document")
	return ExecutionBundle.create_from_document(document, document.value(), document.canonical_bytes(), document.sha256_hex())

## Validates every bundle-specific predicate for callers that already hold a
## normalized closed root. No owner record is allocated by this helper.
## Example: `ExecutionBundleProfileV2.validate_normalized_fields(fields)`.
static func validate_normalized_fields(root: Dictionary) -> DomainResult:
	var version_result := _validate_versions(root)
	if not version_result.is_success():
		return version_result
	var day_result := _validate_task_day(root)
	if not day_result.is_success():
		return day_result
	var shape_relationship_result := _validate_nested_shapes(root)
	if not shape_relationship_result.is_success():
		return shape_relationship_result
	return _validate_identity_bindings(root)

## Alias for the first-decision construction path used by admission callers.
## Example: `var decision := ExecutionBundleProfileV2.first_decision(document)`.
static func first_decision(document: ValidatedCanonicalDocument) -> DomainResult:
	return construct(document)

## Alias for profile validation without construction.
## Example: `var checked := ExecutionBundleProfileV2.validate(document)`.
static func validate(document: ValidatedCanonicalDocument) -> DomainResult:
	return construct(document)

static func _validate_versions(root: Dictionary) -> DomainResult:
	if String(root.get("execution_bundle_codec_version", "")) != CODEC_VERSION:
		return DomainResult.failure(&"version_mismatch", "execution bundle codec version is not execution_bundle_v2", "$.execution_bundle_codec_version")
	if String(root.get("runtime_codec_version", "")) != RUNTIME_CODEC_VERSION:
		return DomainResult.failure(&"version_mismatch", "runtime codec version is not runtime_json_v1", "$.runtime_codec_version")
	if String(root.get("validator_executor_contract_version", "")) != "validator_executor_v1":
		return DomainResult.failure(&"version_mismatch", "validator executor contract version is not validator_executor_v1", "$.validator_executor_contract_version")
	if String(root.get("task_content_contract_version", "")) != "task_content_v1":
		return DomainResult.failure(&"version_mismatch", "task content contract version is not task_content_v1", "$.task_content_contract_version")
	return DomainResult.success(true)

static func _validate_task_day(root: Dictionary) -> DomainResult:
	var value: Variant = root.get("task_day_index", null)
	if typeof(value) != TYPE_INT:
		return DomainResult.failure(&"invalid_task_day", "task_day_index must be an integer", "$.task_day_index")
	if int(value) < VALID_TASK_DAY_MINIMUM or int(value) > VALID_TASK_DAY_MAXIMUM:
		return DomainResult.failure(&"invalid_task_day", "task_day_index is outside the content-valid domain", "$.task_day_index")
	return DomainResult.success(true)

static func _validate_nested_shapes(root: Dictionary) -> DomainResult:
	var required_objects := ["authoring_request", "graph", "authoring_package_binding", "validator_executor_binding", "resource_compatibility"]
	for field_name: String in required_objects:
		if typeof(root.get(field_name, null)) != TYPE_DICTIONARY:
			return DomainResult.failure(&"closed_shape", "bundle member must be a closed object record", "$." + field_name)
	return DomainResult.success(true)

static func _validate_identity_bindings(root: Dictionary) -> DomainResult:
	var request: Dictionary = root["authoring_request"]
	var graph: Dictionary = root["graph"]
	var package_binding: Dictionary = root["authoring_package_binding"]
	var validator_binding: Dictionary = root["validator_executor_binding"]
	var resource_compatibility: Dictionary = root["resource_compatibility"]
	var resource_core: Dictionary = resource_compatibility["resource_compatibility_core"]
	var version_result := _validate_identity_versions(request, graph, package_binding, validator_binding, resource_compatibility, resource_core)
	if not version_result.is_success():
		return version_result
	var core_result := _validate_core_identity(root, resource_compatibility, resource_core)
	if not core_result.is_success():
		return core_result
	var package_result := _validate_package_identity(root, request, package_binding, resource_core)
	if not package_result.is_success():
		return package_result
	var validator_result := _validate_validator_identity(root, validator_binding)
	if not validator_result.is_success():
		return validator_result
	return _validate_case_roster(root, request)

static func _validate_identity_versions(request: Dictionary, graph: Dictionary, package_binding: Dictionary, validator_binding: Dictionary, resource_compatibility: Dictionary, resource_core: Dictionary) -> DomainResult:
	var request_result := _validate_request_versions(request)
	if not request_result.is_success():
		return request_result
	var binding_result := _validate_binding_versions(graph, package_binding, validator_binding, resource_compatibility)
	if not binding_result.is_success():
		return binding_result
	return _validate_resource_versions(resource_core)

static func _validate_request_versions(request: Dictionary) -> DomainResult:
	if String(request.get("request_codec_version", "")) != "authoring_request_v1":
		return DomainResult.failure(&"version_mismatch", "authoring request codec version is not authoring_request_v1", "$.authoring_request.request_codec_version")
	if not ["targeted", "suite"].has(String(request.get("request_kind", ""))):
		return DomainResult.failure(&"version_mismatch", "authoring request kind is not registered", "$.authoring_request.request_kind")
	return DomainResult.success(true)

static func _validate_binding_versions(graph: Dictionary, package_binding: Dictionary, validator_binding: Dictionary, resource_compatibility: Dictionary) -> DomainResult:
	if String(graph.get("graph_codec_version", "")) != "authoring_graph_v1":
		return DomainResult.failure(&"version_mismatch", "authoring graph codec version is not authoring_graph_v1", "$.graph.graph_codec_version")
	if String(package_binding.get("binding_codec_version", "")) != "authoring_package_binding_v2":
		return DomainResult.failure(&"version_mismatch", "authoring package binding codec version is not authoring_package_binding_v2", "$.authoring_package_binding.binding_codec_version")
	if String(validator_binding.get("binding_codec_version", "")) != "validator_executor_binding_v1":
		return DomainResult.failure(&"version_mismatch", "validator executor binding codec version is not validator_executor_binding_v1", "$.validator_executor_binding.binding_codec_version")
	if String(resource_compatibility.get("compatibility_codec_version", "")) != "resource_compatibility_v2":
		return DomainResult.failure(&"version_mismatch", "resource compatibility codec version is not resource_compatibility_v2", "$.resource_compatibility.compatibility_codec_version")
	return DomainResult.success(true)

static func _validate_resource_versions(resource_core: Dictionary) -> DomainResult:
	if String(resource_core.get("core_codec_version", "")) != "resource_compatibility_core_v2":
		return DomainResult.failure(&"version_mismatch", "resource compatibility core codec version is not resource_compatibility_core_v2", "$.resource_compatibility.resource_compatibility_core.core_codec_version")
	if String(resource_core.get("runtime_codec_version", "")) != RUNTIME_CODEC_VERSION:
		return DomainResult.failure(&"version_mismatch", "resource compatibility runtime codec version is not runtime_json_v1", "$.resource_compatibility.resource_compatibility_core.runtime_codec_version")
	if String(resource_core.get("runtime_ingress_limits_version", "")) != "runtime_ingress_limits_v2":
		return DomainResult.failure(&"version_mismatch", "resource compatibility limits version is not runtime_ingress_limits_v2", "$.resource_compatibility.resource_compatibility_core.runtime_ingress_limits_version")
	if String(resource_core.get("authoring_contract_version", "")) != "authoring_contract_v1":
		return DomainResult.failure(&"version_mismatch", "resource authoring contract version is not authoring_contract_v1", "$.resource_compatibility.resource_compatibility_core.authoring_contract_version")
	if String(resource_core.get("task_content_contract_version", "")) != "task_content_v1":
		return DomainResult.failure(&"version_mismatch", "resource task content contract version is not task_content_v1", "$.resource_compatibility.resource_compatibility_core.task_content_contract_version")
	if String(resource_core.get("validator_executor_contract_version", "")) != "validator_executor_v1":
		return DomainResult.failure(&"version_mismatch", "resource validator executor contract version is not validator_executor_v1", "$.resource_compatibility.resource_compatibility_core.validator_executor_contract_version")
	if String(resource_core.get("verifier_contract_version", "")) != "verifier_v1":
		return DomainResult.failure(&"version_mismatch", "resource verifier contract version is not verifier_v1", "$.resource_compatibility.resource_compatibility_core.verifier_contract_version")
	return DomainResult.success(true)

static func _validate_core_identity(root: Dictionary, resource_compatibility: Dictionary, resource_core: Dictionary) -> DomainResult:
	var core_bytes_result := CanonicalCodec.encode(resource_core)
	if not core_bytes_result.is_success():
		return core_bytes_result
	var core_digest := CanonicalCodec.sha256_hex(core_bytes_result.value())
	if core_digest.is_empty() or core_digest != String(resource_compatibility.get("resource_compatibility_core_sha256", "")):
		return DomainResult.failure(&"identity_mismatch", "resource compatibility core digest does not match its complete record", "$.resource_compatibility.resource_compatibility_core_sha256")
	if String(resource_core.get("registry_sha256", "")) != String(root.get("registry_sha256", "")):
		return DomainResult.failure(&"identity_mismatch", "resource compatibility registry digest does not match the bundle registry", "$.resource_compatibility.resource_compatibility_core.registry_sha256")
	if String(resource_core.get("task_content_contract_version", "")) != String(root.get("task_content_contract_version", "")):
		return DomainResult.failure(&"identity_mismatch", "resource compatibility task-content contract does not match the bundle", "$.resource_compatibility.resource_compatibility_core.task_content_contract_version")
	if String(resource_core.get("sandbox_catalog_sha256", "")) != String(root.get("sandbox_catalog_sha256", "")):
		return DomainResult.failure(&"identity_mismatch", "resource compatibility Sandbox catalog digest does not match the bundle", "$.resource_compatibility.resource_compatibility_core.sandbox_catalog_sha256")
	if String(resource_core.get("validator_executor_contract_version", "")) != String(root.get("validator_executor_contract_version", "")):
		return DomainResult.failure(&"identity_mismatch", "resource compatibility validator contract does not match the bundle", "$.resource_compatibility.resource_compatibility_core.validator_executor_contract_version")
	return DomainResult.success(true)

static func _validate_package_identity(root: Dictionary, request: Dictionary, package_binding: Dictionary, resource_core: Dictionary) -> DomainResult:
	var binding_bytes_result := CanonicalCodec.encode(package_binding)
	if not binding_bytes_result.is_success():
		return binding_bytes_result
	var binding_digest := CanonicalCodec.sha256_hex(binding_bytes_result.value())
	var request_digest := String(request.get("authoring_package_binding_sha256", ""))
	if not _is_lower_sha256(request_digest):
		return DomainResult.failure(&"invalid_hash", "authoring package binding digest must be lowercase SHA-256", "$.authoring_request.authoring_package_binding_sha256")
	if binding_digest.is_empty() or binding_digest != request_digest:
		return DomainResult.failure(&"identity_mismatch", "authoring package binding digest does not match its complete canonical record", "$.authoring_package_binding")
	if String(root.get("task_fixture_sha256", "")) != String(package_binding.get("task_fixture_sha256", "")):
		return DomainResult.failure(&"identity_mismatch", "task fixture digest does not match the package binding", "$.task_fixture_sha256")
	if String(root.get("registry_sha256", "")) != String(package_binding.get("registry_sha256", "")):
		return DomainResult.failure(&"identity_mismatch", "registry digest does not match the package binding", "$.registry_sha256")
	if String(package_binding.get("display_production_binding_sha256", "")) != String(resource_core.get("display_production_binding_sha256", "")):
		return DomainResult.failure(&"identity_mismatch", "display production binding digest does not match the resource compatibility core", "$.authoring_package_binding.display_production_binding_sha256")
	return DomainResult.success(true)

static func _validate_validator_identity(root: Dictionary, validator_binding: Dictionary) -> DomainResult:
	if String(validator_binding.get("authoring_registry_sha256", "")) != String(root.get("registry_sha256", "")):
		return DomainResult.failure(&"identity_mismatch", "validator binding registry digest does not match the bundle registry", "$.validator_executor_binding.authoring_registry_sha256")
	if String(validator_binding.get("sandbox_catalog_sha256", "")) != String(root.get("sandbox_catalog_sha256", "")):
		return DomainResult.failure(&"identity_mismatch", "validator binding sandbox digest does not match the bundle catalog", "$.validator_executor_binding.sandbox_catalog_sha256")
	return DomainResult.success(true)

static func _validate_case_roster(root: Dictionary, request: Dictionary) -> DomainResult:
	var manifest: Array = root["public_case_manifest"]
	var roster: Array = request["case_roster"]
	if roster.size() != manifest.size():
		return DomainResult.failure(&"identity_mismatch", "request case roster does not project the public case manifest", "$.authoring_request.case_roster")
	for index: int in range(manifest.size()):
		var manifest_item: Dictionary = manifest[index]
		if String(roster[index]) != String(manifest_item["test_case_id"]):
			return DomainResult.failure(&"identity_mismatch", "request case roster does not project the public case manifest", "$.authoring_request.case_roster[%d]" % index)
	return DomainResult.success(true)

static func _is_lower_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character: String in value:
		if (character < "0" or character > "9") and (character < "a" or character > "f"):
			return false
	return true
