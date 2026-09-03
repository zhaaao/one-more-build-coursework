class_name U64Value
extends RefCounted

## Decimal-only u64 boundary from the shared canonical wire schemas.
## Values stay strings to avoid signed-int overflow.

const MAX_DECIMAL: String = "18446744073709551615"

## Validates and normalizes a decimal u64 without converting it to an int.
static func normalize(decimal: String) -> DomainResult:
	if decimal.is_empty():
		return DomainResult.failure(&"invalid_u64", "u64 must contain at least one digit")
	if decimal.length() > 1 and decimal.begins_with("0"):
		return DomainResult.failure(&"invalid_u64", "leading zeroes are not canonical")
	for character: String in decimal:
		if character < "0" or character > "9":
			return DomainResult.failure(&"invalid_u64", "u64 must contain decimal digits only")
	if decimal.length() > MAX_DECIMAL.length():
		return DomainResult.failure(&"u64_out_of_range", "u64 exceeds its maximum value")
	if decimal.length() == MAX_DECIMAL.length() and _compare_decimal(decimal, MAX_DECIMAL) > 0:
		return DomainResult.failure(&"u64_out_of_range", "u64 exceeds its maximum value")
	return DomainResult.success(decimal)

## Compares two equal-length ASCII decimal strings without integer conversion.
static func _compare_decimal(left: String, right: String) -> int:
	for index: int in range(left.length()):
		var left_digit: int = left.unicode_at(index)
		var right_digit: int = right.unicode_at(index)
		if left_digit < right_digit:
			return -1
		if left_digit > right_digit:
			return 1
	return 0
