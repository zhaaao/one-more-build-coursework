class_name CourseworkTaskRecoveryContract
extends RefCounted

## Immutable, detached installed-Task data used only during Save recovery.

var _task_id: String = ""
var _graph_model_contract: Dictionary[String, Variant] = {}
var _starting_graph: Dictionary[String, Variant] = {}
var _ordered_public_cases: Array[Variant] = []
var _witness_operations: Array[Variant] = []
var _content_digest: String = ""

## Creates a detached recovery contract from admitted installed Task data.
## Example: `var result: DomainResult = CourseworkTaskRecoveryContract.create(task_id, contract, starting_graph, cases, digest, witness_edits)`.
static func create(
	task_id: String,
	graph_model_contract: Dictionary[String, Variant],
	starting_graph: Dictionary[String, Variant],
	ordered_public_cases: Array[Variant],
	content_digest: String,
	witness_operations: Array[Variant] = []
) -> DomainResult:
	if task_id.is_empty() or graph_model_contract.is_empty() or starting_graph.is_empty() \
			or ordered_public_cases.is_empty() or content_digest.is_empty():
		return DomainResult.failure(&"task_recovery_contract_invalid", "installed Task recovery data is incomplete")
	var contract: CourseworkTaskRecoveryContract = CourseworkTaskRecoveryContract.new()
	contract._task_id = task_id
	contract._graph_model_contract = graph_model_contract.duplicate(true)
	contract._starting_graph = starting_graph.duplicate(true)
	contract._ordered_public_cases = ordered_public_cases.duplicate(true)
	contract._witness_operations = witness_operations.duplicate(true)
	contract._content_digest = content_digest
	return DomainResult.success(contract)

## Returns the admitted installed Task identity.
## Example: `var task_id: String = contract.task_id()`.
func task_id() -> String:
	return _task_id

## Returns a deep-detached GraphModel contract.
## Example: `var graph_contract: Dictionary[String, Variant] = contract.graph_model_contract()`.
func graph_model_contract() -> Dictionary[String, Variant]:
	return _graph_model_contract.duplicate(true)

## Returns the deep-detached Task Reset graph.
## Example: `var starting: Dictionary[String, Variant] = contract.starting_graph()`.
func starting_graph() -> Dictionary[String, Variant]:
	return _starting_graph.duplicate(true)

## Returns the installed public-case roster in stable order.
## Example: `var cases: Array[Variant] = contract.ordered_public_cases()`.
func ordered_public_cases() -> Array[Variant]:
	return _ordered_public_cases.duplicate(true)

## Returns the admitted Auto Solve witness edits in authored order.
## Example: `var operations: Array[Variant] = contract.witness_operations()`.
func witness_operations() -> Array[Variant]:
	return _witness_operations.duplicate(true)

## Returns the admitted installed content digest.
## Example: `var digest: String = contract.content_digest()`.
func content_digest() -> String:
	return _content_digest
