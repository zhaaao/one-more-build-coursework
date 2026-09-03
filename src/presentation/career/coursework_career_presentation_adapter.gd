class_name CourseworkCareerPresentationAdapter
extends RefCounted

## Read-only Presentation adapter for Career owner projections.
## Implements career-progression-and-evaluation.md Sections 1, 5, and 8.

class PresentationCommand extends RefCounted:
	var name: StringName
	var reset_confirmed: bool

	func _init(command_name: StringName, confirmed: bool = false) -> void:
		name = command_name
		reset_confirmed = confirmed


class PresentationResult extends RefCounted:
	var accepted: bool
	var reason: String
	var projection: Dictionary[String, Variant]

	static func accept(owner_projection: Dictionary[String, Variant]) -> PresentationResult:
		var result: PresentationResult = PresentationResult.new()
		result.accepted = true
		result.reason = ""
		result.projection = owner_projection.duplicate(true)
		return result

	static func reject(rejection_reason: String) -> PresentationResult:
		var result: PresentationResult = PresentationResult.new()
		result.accepted = false
		result.reason = rejection_reason
		result.projection = {}
		return result


class CareerProjectionPort extends RefCounted:
	var _projection_reader: Callable
	var _reset_command: Callable

	func _init(projection_reader: Callable, reset_command: Callable) -> void:
		_projection_reader = projection_reader
		_reset_command = reset_command

	func read_projection() -> PresentationResult:
		if not _projection_reader.is_valid():
			return PresentationResult.reject("Career projection is unavailable.")
		var owner_projection: Variant = _projection_reader.call()
		if typeof(owner_projection) != TYPE_DICTIONARY:
			return PresentationResult.reject("Career projection is unavailable.")
		var projection: Dictionary[String, Variant] = owner_projection
		return PresentationResult.accept(projection)

	func reset(confirmed: bool) -> PresentationResult:
		if not _reset_command.is_valid():
			return PresentationResult.reject("Career reset is unavailable.")
		var owner_result: Variant = _reset_command.call(confirmed)
		if owner_result == null or not owner_result.has_method("is_success") or not owner_result.is_success():
			return PresentationResult.reject("Career reset was not accepted.")
		return read_projection()


class WorkstationRoutePort extends RefCounted:
	var _route_command: Callable

	func _init(route_command: Callable) -> void:
		_route_command = route_command

	func route(command: PresentationCommand) -> PresentationResult:
		if not _route_command.is_valid():
			return PresentationResult.reject("Career route is unavailable.")
		var route_result: Variant = _route_command.call(command)
		if route_result is PresentationResult:
			return route_result
		return PresentationResult.reject("Career route returned no availability result.")


signal projection_presented(projection: Dictionary[String, Variant])
signal command_accepted(command: PresentationCommand, result: PresentationResult)
signal command_rejected(command: PresentationCommand, result: PresentationResult)

var _career_port: CareerProjectionPort
var _workstation_route_port: WorkstationRoutePort


## Creates the narrow Career projection/reset port without coupling the adapter to its owner class.
static func create_career_projection_port(projection_reader: Callable, reset_command: Callable) -> CareerProjectionPort:
	return CareerProjectionPort.new(projection_reader, reset_command)


## Creates the narrow Workstation start/continue route port with availability feedback.
static func create_workstation_route_port(route_command: Callable) -> WorkstationRoutePort:
	return WorkstationRoutePort.new(route_command)


## Injects the only ports this presentation seam may use.
func configure(career_port: CareerProjectionPort, workstation_route_port: WorkstationRoutePort) -> void:
	_career_port = career_port
	_workstation_route_port = workstation_route_port


## Routes one typed command and emits an accepted notification only after its port succeeds.
func route(command: PresentationCommand) -> PresentationResult:
	var result: PresentationResult = _route_command(command)
	if result.accepted:
		if not result.projection.is_empty():
			projection_presented.emit(result.projection.duplicate(true))
		command_accepted.emit(command, result)
	else:
		command_rejected.emit(command, result)
	return result


func _route_command(command: PresentationCommand) -> PresentationResult:
	if command == null:
		return PresentationResult.reject("Career command is unavailable.")
	match command.name:
		&"start", &"continue":
			if _workstation_route_port == null:
				return PresentationResult.reject("Career route is unavailable.")
			var route_result: PresentationResult = _workstation_route_port.route(command)
			if not route_result.accepted:
				return route_result
			return _read_owner_projection()
		&"reset_confirm", &"reset_cancel":
			if _career_port == null:
				return PresentationResult.reject("Career reset is unavailable.")
			return _career_port.reset(command.reset_confirmed)
		&"inspect_history", &"inspect_feedback", &"request_reset", &"dismiss":
			return _read_owner_projection()
	return PresentationResult.reject("Career command is unavailable.")


func _read_owner_projection() -> PresentationResult:
	if _career_port == null:
		return PresentationResult.reject("Career projection is unavailable.")
	return _career_port.read_projection()
