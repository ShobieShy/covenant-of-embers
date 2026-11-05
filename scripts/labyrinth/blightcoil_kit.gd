class_name BlightcoilKit
extends RefCounted
## Act II Blightcoil art (Ember Art batch_12). Collision for the walk stays on the
## cavern's own boxes. A mesh is shown when its file exists. Music cues stay silent
## until a file is there. `-colonly` bodies on a mesh are switched off so a vine
## cannot block or hurt anyone.

const DIR := "res://assets/original/ember_art/blightcoil/"
const ENEMY_DIR := "res://assets/original/ember_art/enemies/"
const CUES := {
	"sump": DIR + "music/sump.ogg",
	"canopy": DIR + "music/canopy.ogg",
	"crown": DIR + "music/crown.ogg",
	"matriarch": DIR + "music/matriarch.ogg",
	"fog_clear": DIR + "music/fog_clear.ogg",
}
## HANDOFF batch_12. Props live under blightcoil/; creatures under enemies/.
const BLIGHTCOIL := {
	"moss_wall": DIR + "moss_wall.glb",
	"root_bridge_ramp": DIR + "root_bridge_ramp.glb",
	"mire_surface": DIR + "mire_surface.glb",
	"spore_pod": DIR + "spore_pod.glb",
	"trunk_column": DIR + "trunk_column.glb",
	"torn_cocoon": DIR + "torn_cocoon.glb",
	"forge_door": DIR + "forge_door.glb",
	"ritual_mark_decal": DIR + "ritual_mark_decal.png",
	"verdant_mother": DIR + "verdant_mother.glb",
	"grabbing_vine": DIR + "grabbing_vine.glb",
}
const BLIGHTCOIL_ENEMIES := {
	"spore_cap_husk": ENEMY_DIR + "spore_cap_husk.glb",
	"mossbound_treant": ENEMY_DIR + "mossbound_treant.glb",
	"spore_beast": ENEMY_DIR + "spore_beast.glb",
	"blightmaw_matriarch": ENEMY_DIR + "blightmaw_matriarch.glb",
}
const SLOTS := {
	"moss_wall": BLIGHTCOIL["moss_wall"],
	"root_bridge_ramp": BLIGHTCOIL["root_bridge_ramp"],
	"mire_surface": BLIGHTCOIL["mire_surface"],
	"spore_pod": BLIGHTCOIL["spore_pod"],
	"trunk_column": BLIGHTCOIL["trunk_column"],
	"torn_cocoon": BLIGHTCOIL["torn_cocoon"],
	"forge_door": BLIGHTCOIL["forge_door"],
	"ritual_mark_decal": BLIGHTCOIL["ritual_mark_decal"],
	"verdant_mother": BLIGHTCOIL["verdant_mother"],
	"grabbing_vine": BLIGHTCOIL["grabbing_vine"],
	"spore_cap_husk": BLIGHTCOIL_ENEMIES["spore_cap_husk"],
	"mossbound_treant": BLIGHTCOIL_ENEMIES["mossbound_treant"],
	"spore_beast": BLIGHTCOIL_ENEMIES["spore_beast"],
	"blightmaw_matriarch": BLIGHTCOIL_ENEMIES["blightmaw_matriarch"],
}


static func mesh_for(slot: String) -> Node3D:
	var path := String(SLOTS.get(slot, ""))
	if path == "" or not path.ends_with(".glb") or not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	return ps.instantiate() as Node3D if ps else null


## The mesh with its imported collision switched off. Walk collision stays on the cavern.
static func visual(slot: String) -> Node3D:
	var n := mesh_for(slot)
	if n == null:
		return null
	for b in n.find_children("*", "CollisionObject3D", true, false):
		var body := b as CollisionObject3D
		body.collision_layer = 0
		body.collision_mask = 0
	return n


static func texture(slot: String) -> Texture2D:
	var path := String(SLOTS.get(slot, ""))
	if path == "" or not path.ends_with(".png") or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## Silence until the cue file exists. Returns true only when a file actually played.
static func play_cue(id: String) -> bool:
	var path := String(CUES.get(id, ""))
	if path == "" or not ResourceLoader.exists(path):
		return false
	return false
