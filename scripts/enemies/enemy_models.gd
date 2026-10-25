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
## Step 125 (Art A7): extra bodies picked at random per spawn (visual only).
const VARIANTS := {"gnawer": ["rats/Rat_Mutated_Sickly.glb", "rats/Rat_Mutated_Plague.glb"]}
## Step 125: procedural bodies for types with no CC0 model.
const PROCEDURAL := ["scorchling"]
const WARDEN_EYES := Color(0.75, 0.3, 1.0)


static func path_for(id: String) -> String:
	return DIR + String(MODELS[id]) if MODELS.has(id) else ""


## Fit the model to the enemy's box height; null when there is none (caller keeps the box).
static func make(id: String, height: float) -> CharacterModel:
	if id in PROCEDURAL:
		var holder := CharacterModel.new()
		holder.name = "Model"
		holder.add_child(ScorchlingBody.build(height))
		return holder
	var path := path_for(id)
	if VARIANTS.has(id):
		var vs: Array = VARIANTS[id]
		path = DIR + String(vs[randi() % vs.size()])
	var m := CharacterModel.make_sized(path, height)
	if m != null and id == "breach_warden":
		_warden_eyes(m, height)
	if m != null and String(MODELS[id]).begins_with("garbage_golems/"):
		(m.get_child(0) as Node3D).rotation.y = 0.0  # Ember Art's kitbash rig already faces -Z
	return m


## Step 125: the Breach Warden reads as the Breach's keeper, not a Landfill golem: violet
## rune eyes and a soft violet glow on the bin golem body.
static func _warden_eyes(m: CharacterModel, height: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WARDEN_EYES
	mat.emission_enabled = true
	mat.emission = WARDEN_EYES
	mat.emission_energy_multiplier = 4.0
	for sx: float in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		e.name = "WardenEye"
		var s := SphereMesh.new()
		s.radius = height * 0.03
		s.height = height * 0.06
		e.mesh = s
		e.material_override = mat
		e.position = Vector3(height * 0.08 * sx, height * 0.78, -height * 0.2)
		m.add_child(e)
	var l := OmniLight3D.new()
	l.name = "WardenGlow"
	l.light_color = WARDEN_EYES
	l.light_energy = 1.5
	l.omni_range = height * 1.6
	l.position = Vector3(0, height * 0.8, -height * 0.3)
	m.add_child(l)
