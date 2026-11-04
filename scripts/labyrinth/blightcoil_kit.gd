class_name BlightcoilKit
extends RefCounted
## Greybox dressing for the Blightcoil. Collision stays on the boxes. A mesh is shown
## only when its file exists. Music cues are slots: silence until a file is there.

const DIR := "res://assets/original/ember_art/blightcoil/"
const ENEMY_DIR := "res://assets/original/ember_art/enemies/"
const CUES := {
	"sump": DIR + "music/sump.ogg",
	"canopy": DIR + "music/canopy.ogg",
	"crown": DIR + "music/crown.ogg",
	"matriarch": DIR + "music/matriarch.ogg",
	"fog_clear": DIR + "music/fog_clear.ogg",
}
const SLOTS := {
	"moss_wall": DIR + "moss_wall.glb",
	"root_bridge_ramp": DIR + "root_bridge_ramp.glb",
	"mire_surface": DIR + "mire_surface.glb",
	"spore_pod": DIR + "spore_pod.glb",
	"trunk_column": DIR + "trunk_column.glb",
	"torn_cocoon": DIR + "torn_cocoon.glb",
	"forge_door": DIR + "forge_door.glb",
	"ritual_mark": DIR + "ritual_mark_decal.png",
	"verdant_mother": DIR + "verdant_mother.glb",
	"grabbing_vine": DIR + "grabbing_vine.glb",
	"spore_cap_husk": ENEMY_DIR + "spore_cap_husk.glb",
	"mossbound_treant": ENEMY_DIR + "mossbound_treant.glb",
	"spore_beast": ENEMY_DIR + "spore_beast.glb",
	"blightmaw_matriarch": ENEMY_DIR + "blightmaw_matriarch.glb",
}


static func mesh_for(slot: String) -> Node3D:
	var path := String(SLOTS.get(slot, ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	return ps.instantiate() as Node3D if ps else null


## Silence until the cue file exists. Returns true only when a file actually played.
static func play_cue(id: String) -> bool:
	var path := String(CUES.get(id, ""))
	if path == "" or not ResourceLoader.exists(path):
		return false
	return false
