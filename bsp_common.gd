class_name BSPCommon
extends RefCounted

const BSP_VERSION_QUAKE3: int = 46
const LUMP_ENTITIES: int = 0
const LUMP_SHADERS: int = 1
const LUMP_PLANES: int = 2
const LUMP_NODES: int = 3
const LUMP_LEAFS: int = 4
const LUMP_LEAFSURFACES: int = 5
const LUMP_LEAFBRUSHES: int = 6
const LUMP_MODELS: int = 7
const LUMP_BRUSHES: int = 8
const LUMP_BRUSHSIDES: int = 9
const LUMP_VERTICES: int = 10
const LUMP_MESHVERTS: int = 11
const LUMP_EFFECTS: int = 12
const LUMP_SURFACES: int = 13
const EXPECTED_LUMP_COUNT: int = 17

const MST_PLANAR: int = 1
const MST_PATCH: int = 2
const MST_TRIANGLE_SOUP: int = 3

const NON_RENDER_SHADERS: PackedStringArray = [
	"common/antiportal", "common/botclip", "common/caulk", "common/forcecaulk",
	"common/clip", "common/donotenter", "common/full_clip", "common/hint",
	"common/hintskip", "common/monsterclip", "common/nodraw", "common/nodrawnonsolid",
	"common/nodrop", "common/noimpact", "common/origin", "common/skip",
	"common/trigger", "common/lightgrid", "common/waternodraw", "common/slimenodraw",
	"common/lavanodraw"
]

const SOLID_SHADERS: PackedStringArray = [
	"common/clip", "common/weapclip", "common/full_clip", "common/invisible"
]

const TRIGGER_ENTITIES: Array[String] = [
	"trigger_push", "trigger_hurt", "trigger_teleport", "trigger_multiple",
	"trigger_once", "trigger_secret", "trigger_swamp", "trigger_heal",
	"trigger_gravity", "trigger_impulse", "trigger_keylock", "trigger_race_checkpoint",
	"trigger_race_penalty", "trigger_viewlocation", "trigger_warpzone",
	"trigger_music"
]

const GOAL_ENTITIES: Array[String] = [
	"nexball_redgoal", "nexball_bluegoal", "nexball_yellowgoal",
	"nexball_pinkgoal", "nexball_fault", "nexball_out"
]

const COLLIDABLE_FUNC_ENTITIES: Array[String] = [
	"func_door", "func_door_rotating", "func_rotating", "func_wall",
	"func_breakable", "func_ladder", "func_plat", "func_train"
]

const ITEM_ENTITIES: Array[String] = [
	"item_armor_mega", "item_armor_big", "item_armor_medium", "item_armor_small",
	"item_bullets", "item_cells", "item_flag_team1", "item_flag_team2",
	"item_flag_team3", "item_flag_team4", "item_health_big", "item_health_medium",
	"item_health_mega", "item_health_small", "item_shield", "item_speed",
	"item_invisibility", "item_key", "item_key1", "item_key2", "item_vaporizer_cells",
	"item_rockets", "item_shells", "item_strength", "item_fuel", "item_fuel_regen",
	"item_jetpack"
]

const WEAPON_ENTITIES: Array[String] = [
	"weapon_crylink", "weapon_electro", "weapon_mortar", "weapon_hagar",
	"weapon_blaster", "weapon_vortex", "weapon_devastator", "weapon_shotgun",
	"weapon_machinegun", "weapon_arc", "weapon_vaporizer", "weapon_porto",
	"weapon_hlac", "weapon_minelayer", "weapon_seeker", "weapon_hook",
	"weapon_fireball", "weapon_rifle"
]

const NON_COLLIDABLE_ENTITIES: Array[String] = [
	"light", "lightJunior", "target_position", "misc_teleporter_dest",
	"func_pointparticles", "info_autoscreenshot"
]
