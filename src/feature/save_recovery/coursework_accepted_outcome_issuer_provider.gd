class_name CourseworkAcceptedOutcomeIssuerProvider
extends RefCounted

## Supplies exactly one fresh process-local Workday issuer per preparation.

## Creates one fresh process-local issuer for a single recovery preparation.
## Example: `var result: DomainResult = provider.create_fresh_issuer()`.
func create_fresh_issuer() -> DomainResult:
	return DomainResult.success(CourseworkWorkdayLifecycle.AcceptedOutcomeIssuer.new())

## Compatibility alias for pre-ADR-0011 call sites. New recovery code uses
## create_fresh_issuer() to make the freshness boundary explicit.
func issue() -> DomainResult:
	return create_fresh_issuer()
