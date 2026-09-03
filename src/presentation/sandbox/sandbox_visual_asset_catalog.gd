## Implements Story 007's approved, non-authoritative Sandbox visual asset catalog.
## This presentation-only catalog has no accepted state, result, Node, or Resource ownership.
class_name SandboxVisualAssetCatalog
extends RefCounted


const ENVIRONMENT_FAR_TEXTURE_ID: StringName = &"environment_far"
const ENVIRONMENT_MID_TEXTURE_ID: StringName = &"environment_mid"
const ENVIRONMENT_NEAR_TEXTURE_ID: StringName = &"environment_near"
const BOT_ATLAS_ID: StringName = &"parcel_bot"
const PLAYFIELD_ATLAS_ID: StringName = &"playfield"
const FIXTURES_ATLAS_ID: StringName = &"fixtures"
const DOCKS_ATLAS_ID: StringName = &"docks"
const PACKAGES_ATLAS_ID: StringName = &"packages"

const _TEXTURE_PATHS_BY_ID: Dictionary = {

	ENVIRONMENT_FAR_TEXTURE_ID: "res://assets/art/env_company_far_1024.png",
	ENVIRONMENT_MID_TEXTURE_ID: "res://assets/art/env_company_mid_1024.png",
	ENVIRONMENT_NEAR_TEXTURE_ID: "res://assets/art/env_workstation_near_1024.png",
	BOT_ATLAS_ID: "res://assets/art/obj_parcel_bot_directional_32.png",
	PLAYFIELD_ATLAS_ID: "res://assets/art/env_sandbox_playfield_grid_boundary_256.png",
	FIXTURES_ATLAS_ID: "res://assets/art/obj_sandbox_fixtures_set_256.png",
	DOCKS_ATLAS_ID: "res://assets/art/obj_sandbox_docks_set_256.png",
	PACKAGES_ATLAS_ID: "res://assets/art/obj_sandbox_packages_markers_256.png",
}

const _ENVIRONMENT_COMPOSITING_ORDER: Array[String] = [
	"res://assets/art/env_company_far_1024.png",
	"res://assets/art/env_company_mid_1024.png",
	"res://assets/art/env_workstation_near_1024.png",
]

const _REGION_MAPS_BY_ATLAS_ID: Dictionary = {
	BOT_ATLAS_ID: {
		&"east": Rect2(2, 2, 32, 32),
		&"north": Rect2(38, 2, 32, 32),
		&"south": Rect2(2, 38, 32, 32),
		&"west": Rect2(38, 38, 32, 32),
	},
	PLAYFIELD_ATLAS_ID: {
		&"none": Rect2(2, 2, 32, 32),
		&"north": Rect2(38, 2, 32, 32),
		&"east": Rect2(74, 2, 32, 32),
		&"north_east": Rect2(110, 2, 32, 32),
		&"south": Rect2(2, 38, 32, 32),
		&"north_south": Rect2(38, 38, 32, 32),
		&"east_south": Rect2(74, 38, 32, 32),
		&"north_east_south": Rect2(110, 38, 32, 32),
		&"west": Rect2(2, 74, 32, 32),
		&"north_west": Rect2(38, 74, 32, 32),
		&"east_west": Rect2(74, 74, 32, 32),
		&"north_east_west": Rect2(110, 74, 32, 32),
		&"south_west": Rect2(2, 110, 32, 32),
		&"north_south_west": Rect2(38, 110, 32, 32),
		&"east_south_west": Rect2(74, 110, 32, 32),
		&"north_east_south_west": Rect2(110, 110, 32, 32),
	},
	FIXTURES_ATLAS_ID: {
		&"sensor": Rect2(2, 2, 32, 32),
		&"conveyor_east": Rect2(38, 2, 32, 32),
		&"conveyor_north": Rect2(74, 2, 32, 32),
		&"conveyor_south": Rect2(110, 2, 32, 32),
		&"conveyor_west": Rect2(2, 38, 32, 32),
		&"closed_door": Rect2(38, 38, 32, 32),
		&"obstacle": Rect2(74, 38, 32, 32),
		&"crate": Rect2(110, 38, 32, 32),
	},
	DOCKS_ATLAS_ID: {
		&"delivery_dock": Rect2(2, 2, 32, 32),
		&"charging_dock": Rect2(38, 2, 32, 32),
	},
	PACKAGES_ATLAS_ID: {
		&"red": Rect2(2, 2, 32, 32),
		&"blue": Rect2(38, 2, 32, 32),
		&"green": Rect2(74, 2, 32, 32),
		&"orange": Rect2(110, 2, 32, 32),
		&"yellow": Rect2(2, 38, 32, 32),
		&"purple": Rect2(38, 38, 32, 32),
	},
}


static func get_texture_paths() -> Dictionary:
	return _TEXTURE_PATHS_BY_ID.duplicate(true)


static func get_texture_path(texture_id: StringName) -> String:
	return String(_TEXTURE_PATHS_BY_ID.get(texture_id, ""))


static func get_environment_compositing_order() -> PackedStringArray:
	return PackedStringArray(_ENVIRONMENT_COMPOSITING_ORDER)


static func get_region_map(atlas_id: StringName) -> Dictionary:
	var region_map: Dictionary = _REGION_MAPS_BY_ATLAS_ID.get(atlas_id, {})
	return region_map.duplicate(true)
