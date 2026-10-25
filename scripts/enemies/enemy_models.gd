class_name EnemyModels
extends RefCounted
## Step 121 (Art A3, Ember Art batch_04, CC0 Quaternius): rigged enemy bodies by enemy id.
## The greybox box stays as the collision shape; the box mesh hides when a model loads, and
## the hit-flash / Dark-convert tint shows as a translucent overlay on the model.

const DIR := "res://assets/quaternius/enemies/"
## "heap" is retired (The Filth replaces it) but keeps a golem body for old saves/tests.
const MODELS := {
	"gnawer": "rats/Rat_Mutated_Sickly.glb",
	"ooze": "filth/Filth_Sludge.glb",
	"heap": "garbage_golems/GarbageGolem_Bags.glb",
	"breach_warden": "garbage_golems/GarbageGolem_Bin.glb",
	"the_filth": "filth/Filth_Brute.glb",
}


static func path_for(id: String) -> String:
	return DIR + String(MODELS[id]) if MODELS.has(id) else ""


## Fit the model to the enemy's box height; null when there is none (caller keeps the box).
static func make(id: String, height: float) -> CharacterModel:
	var m := CharacterModel.make_sized(path_for(id), height)
	if m != null and String(MODELS[id]).begins_with("garbage_golems/"):
		(m.get_child(0) as Node3D).rotation.y = 0.0  # Ember Art's kitbash rig already faces -Z
	return m
