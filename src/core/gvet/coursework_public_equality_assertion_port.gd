class_name CourseworkPublicEqualityAssertionPort
extends CourseworkCaseExecutor.AssertionEvaluationPort

## Evaluates the public Task typed-equality assertions owned by GVET.
## Example: `executor.create_node_semantics_program(registry, CourseworkPublicEqualityAssertionPort.new())`.

const DomainResultType = preload("res://src/foundation/domain_result.gd")
const CourseworkCaseExecutorType = preload("res://src/core/gvet/coursework_case_executor.gd")

## Evaluates every expected public fact against one observed Sandbox state.
## Example: `var result: DomainResult = port.evaluate_assertions(assertions, state, sandbox_port)`.
func evaluate_assertions(
	assertions: Array, state: Dictionary, sandbox_port: RefCounted
) -> DomainResult:
	var observed_result: DomainResult = sandbox_port.observe(state)
	if not observed_result.is_success():
		return observed_result
	var facts: Dictionary = observed_result.value()
	var outcomes: Array[Dictionary] = []
	for assertion: Dictionary in assertions:
		var expected: Dictionary = Dictionary(assertion.get("expected", {})).duplicate(true)
		if expected.is_empty():
			return DomainResultType.failure(&"invalid_assertion", "expected facts are required")
		var observed: Dictionary = {}
		for fact_id: String in expected:
			var value: Variant = facts.get(fact_id, null)
			observed[fact_id] = String(value) if typeof(value) == TYPE_STRING_NAME else value
		outcomes.append({
			"assertion_id": String(assertion.get("assertion_id", "")),
			"expected": expected, "observed": observed,
			"comparison": "equal", "pass": expected == observed,
		})
	return DomainResultType.success(outcomes)
