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
	"common/antiportal",    # VIS blocker, not rendered or collidable
	"common/botclip",       # bot-only clip (ignored here)
	"common/caulk",         # invisible, typically on hidden faces of solid brushes
	"common/forcecaulk",    # same as caulk but structural
	"common/clip",          # player clip volume (blocks players, lets weapons pass)
	"common/weapclip",      # weapon clip (blocks projectiles/trace)
	"common/donotenter",    # bot nav (ignored)
	"common/full_clip",     # legacy; full solid clip (treated as solid)
	"common/hint",          # VIS hint
	"common/hintskip",      # VIS helper
	"common/monsterclip",   # monster/NPC clip (ignored)
	"common/nodraw",        # not drawn; usually also non-collidable
	"common/nodrawnonsolid",# explicitly non-solid
	"common/nodrop",        # items fall through; not drawn
	"common/noimpact",      # prevents bullet/mark impact; visual only for us
	"common/origin",        # origin brush for rotating entities
	"common/skip",          # VIS helper
	"common/trigger",       # trigger volumes; handled as Area3D elsewhere
	"common/lightgrid",     # lightgrid bounds; not rendered
	"common/waternodraw",   # water volume without draw (liquid)
	"common/slimenodraw",   # slime volume without draw (liquid)
	"common/lavanodraw"     # lava volume without draw (liquid)
]

const SOLID_SHADERS: PackedStringArray = [
	# Shaders that make a brush behave solid in practice.
	# Note: semantics differ in Q3/Xonotic; our importer uses these
	# to judge func_* model collidability and to build collision shapes.
	"common/clip",        # player-only clip (added to player collision only)
	"common/weapclip",    # weapon clip (added to weapon collision; see notes)
	"common/full_clip",   # full solid, blocks everything
	"common/invisible"    # solid invisible surface
]

# Collision classification helpers used by the importer when splitting
# collision into separate bodies for players vs weapons.
const PLAYER_ONLY_CLIP_SHADERS: PackedStringArray = [
	"common/clip"
]
const WEAPON_CLIP_SHADERS: PackedStringArray = [
	"common/weapclip", "common/weaponclip"
]
const FULL_CLIP_SHADERS: PackedStringArray = [
	"common/full_clip", "common/invisible"
]

# Liquids (parsed from surfaceparms in .shader files). We attach a metadata
# damage_per_second on the generated Area3D for these; values are approximate
# Quake 3 defaults and can be tuned by the game code.
const LIQUID_DEFAULT_DPS := {
	"water": 0,
	"slime": 10,
	"lava": 30
}

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
