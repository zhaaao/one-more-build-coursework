class_name CourseworkLiveOwnerSet
extends RefCounted

## Immutable membership record published by CourseworkWholeGenerationRecovery.

var _authoring_session: AuthoringSession = null
var _task_catalog: CourseworkTaskCatalog = null
var _workday_lifecycle: CourseworkWorkdayLifecycle = null
var _career: CourseworkCareerProgression = null
var _settings_tutorial: CourseworkSettingsTutorialProjectionContracts = null

## Creates one immutable owner root after every owner has prepared successfully.
## Example: `var result: DomainResult = CourseworkLiveOwnerSet.create(session, catalog, workday, career, settings_tutorial)`.
static func create(
	authoring_session: AuthoringSession,
	task_catalog: CourseworkTaskCatalog,
	workday_lifecycle: CourseworkWorkdayLifecycle,
	career: CourseworkCareerProgression,
	settings_tutorial: CourseworkSettingsTutorialProjectionContracts
) -> DomainResult:
	if authoring_session == null or task_catalog == null or career == null or settings_tutorial == null:
		return DomainResult.failure(&"owner_set_invalid", "every required recovered owner must be present")
	var result: CourseworkLiveOwnerSet = CourseworkLiveOwnerSet.new()
	result._authoring_session = authoring_session
	result._task_catalog = task_catalog
	result._workday_lifecycle = workday_lifecycle
	result._career = career
	result._settings_tutorial = settings_tutorial
	return DomainResult.success(result)

## Returns the prepared Authoring owner. Example: `var session: AuthoringSession = owners.authoring_session()`.
func authoring_session() -> AuthoringSession: return _authoring_session
## Returns the admitted installed Task catalogue. Example: `var catalog: CourseworkTaskCatalog = owners.task_catalog()`.
func task_catalog() -> CourseworkTaskCatalog: return _task_catalog
## Returns active Workday or null for finalized Career. Example: `var workday: CourseworkWorkdayLifecycle = owners.workday_lifecycle()`.
func workday_lifecycle() -> CourseworkWorkdayLifecycle: return _workday_lifecycle
## Returns the reconstructed Career owner. Example: `var career: CourseworkCareerProgression = owners.career()`.
func career() -> CourseworkCareerProgression: return _career
## Returns the paired Settings/Tutorial owner. Example: `var settings: CourseworkSettingsTutorialProjectionContracts = owners.settings_tutorial()`.
func settings_tutorial() -> CourseworkSettingsTutorialProjectionContracts: return _settings_tutorial
