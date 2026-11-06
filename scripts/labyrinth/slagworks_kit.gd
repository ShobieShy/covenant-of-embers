class_name SlagworksKit
extends RefCounted
## Act III greybox slots. Collision stays on the floor boxes. A mesh replaces a
## slot only when the file exists. Music cues stay silent until a file is there.

const DIR := "res://assets/original/ember_art/slagworks/"
const ENEMY_DIR := "res://assets/original/ember_art/enemies/"
const CUES := {
	"railhead": DIR + "music/railhead.ogg",
	"overlook": DIR + "music/overlook.ogg",
	"crucible": DIR + "music/crucible.ogg",
	"forgemaw": DIR + "music/forgemaw.ogg",
	"lift_unlock": DIR + "music/lift_unlock.ogg",
}
const SLOTS := {
	"furnace_anvil": DIR + "furnace_anvil.glb",
	"gantry_deck": DIR + "gantry_deck.glb",
	"gantry_ramp": DIR + "gantry_ramp.glb",
	"lava_channel": DIR + "lava_channel.glb",
	"rail": DIR + "rail.glb",
	"mine_cart": DIR + "mine_cart.glb",
	"slag_seal_decal": DIR + "slag_seal_decal.png",
	"scrap_spirit": DIR + "scrap_spirit.glb",
	"branded_troll": ENEMY_DIR + "branded_troll.glb",
	"forge_construct": ENEMY_DIR + "forge_construct.glb",
	"forgemaw": ENEMY_DIR + "forgemaw.glb",
	"slag_cast": DIR + "slag_cast.glb",
	"main_lift": DIR + "main_lift.glb",
	"sunken_door": DIR + "sunken_door.glb",
	"ore_vein": DIR + "ore_vein.glb",
}


static func mesh_for(slot: String) -> Node3D:
	var path := String(SLOTS.get(slot, ""))
	if path == "" or not path.ends_with(".glb") or not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	return ps.instantiate() as Node3D if ps else null


static func play_cue(slot: String) -> bool:
	var path := String(CUES.get(slot, ""))
	if slot == "vein" or slot == "furnace":
		path = String(CUES["railhead"])
	return path != "" and ResourceLoader.exists(path)
