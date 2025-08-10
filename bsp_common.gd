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

## Special shader semantics (Xonotic/Quake3 style)
##
## - common/clip: Player-only clip. We build a separate ConcavePolygonShape3D on layer 8
##   so weapon traces can ignore it while the player collides with it.
## - common/weapclip (weaponclip): Weapon clip; acts like a normal solid wall for both
##   players and weapon traces. Merged into the main world collision.
## - common/full_clip: Legacy name for fully solid invisible walls. Treated as solid.
## - common/invisible: Invisible but solid. Treated as solid and rendered as transparent.
## - common/caulk, forcecaulk, nodraw: Helper, not rendered; if a brush has a majority of
##   these across its sides, the whole brush becomes non-collidable (majority-of-sides rule).
## - Liquids: surfaceparm water/slime/lava in shader files mark a brush as a pass-through
##   liquid volume. We create Area3D volumes (no solid collision) and attach metadata:
##   { liquid_type: water|slime|lava, damage_per_second } using LIQUID_DEFAULT_DPS.
##
## Majority-of-sides collidability:
## - For func_* brush models and worldspawn collision, a brush is classified by counting
##   the shader categories across its sides. The majority determines behavior:
##   clip -> PlayerClip; weapclip/weaponclip/full_clip -> Solid; caulk/nodraw -> Non-solid;
##   water/slime/lava -> Liquid volume. Otherwise falls back to Solid.
const NON_RENDER_SHADERS: PackedStringArray = [
	"common/antiportal",    # VIS blocker, not rendered or collidable
	"common/botclip",       # bot-only clip (ignored here)
	"common/caulk",         # invisible; used on hidden faces. Heuristic: tends to make brush non-solid if most sides are caulk (see is_brush_collidable)
	"common/forcecaulk",    # like caulk but structural
	"common/clip",          # Player-only clip volume (blocks players/physics, not weapons)
	"common/weapclip",      # Weapon clip (blocks projectiles/traces); acts solid
	"common/weaponclip",    # Alias in some maps: same as weapclip
	"common/donotenter",    # Bot nav (ignored)
	"common/full_clip",     # Old name; full solid clip (acts solid)
	"common/hint",          # VIS hint
	"common/hintskip",      # VIS helper
	"common/monsterclip",   # Monster/NPC clip (ignored)
	"common/nodraw",        # Not drawn; usually also non-collidable unless explicitly solid
	"common/nodrawnonsolid",# Explicit non-solid nodraw
	"common/nodrop",        # Items fall through; not drawn
	"common/noimpact",      # Prevents bullet/mark impact; decals/bullets pass
	"common/origin",        # Origin brush for rotating entities
	"common/skip",          # VIS helper
	"common/trigger",       # Trigger volumes; handled as Area3D elsewhere
	"common/lightgrid",     # Lightgrid bounds; not rendered
	"common/waternodraw",   # Water volume without draw (liquid)
	"common/slimenodraw",   # Slime volume without draw (liquid)
	"common/lavanodraw"     # Lava volume without draw (liquid)
]

const SOLID_SHADERS: PackedStringArray = [
	# Shaders that make a brush behave solid in practice.
	# This list feeds is_brush_collidable for func_* models and
	# complements face-based collision in worldspawn.
	# - common/clip: player-only solid (we put it on a separate layer)
	# - common/weapclip/weaponclip: solid for everyone (weapons + players)
	# - common/full_clip, common/invisible: fully solid invisible walls
	"common/clip",
	"common/weapclip",
	"common/weaponclip",
	"common/full_clip",
	"common/invisible"
]

# Collision classification helpers used by the importer when splitting
# collision into separate bodies. We create a dedicated PlayerClip body
# that contains ONLY player-clip brushes so weapons can ignore that layer.
const PLAYER_ONLY_CLIP_SHADERS: PackedStringArray = ["common/clip"]
const WEAPON_CLIP_SHADERS: PackedStringArray = ["common/weapclip", "common/weaponclip"]
const FULL_CLIP_SHADERS: PackedStringArray = ["common/full_clip", "common/invisible"]

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
