class_name EnemyModels
extends RefCounted
## Step 121 (Art A3, Ember Art batch_04, CC0 Quaternius): rigged enemy bodies by enemy id.
## The greybox box stays as the collision shape; the box mesh hides when a model loads, and
## the hit-flash / Dark-convert tint shows as a translucent overlay on the model.

const DIR := "res://assets/quaternius/enemies/"
const REGULAR := "res://assets/original/ember_art/regular_enemies/"
## "heap" is retired (The Filth replaces it) but keeps a body for old saves/tests.
## Boss ids stay on their own meshes. This pass is the regular roster only.
const MODELS := {
	"gnawer": REGULAR + "gnawer_mangy.glb",
	"ooze": REGULAR + "ooze.glb",
	"heap": REGULAR + "heap.glb",
	"breach_warden": "garbage_golems/GarbageGolem_Bin.glb",
	"the_filth": "filth/Filth_Brute.glb",
	"goblin_grunt": REGULAR + "goblin_grunt.glb",
	"goblin_archer": REGULAR + "goblin_archer.glb",
	"goblin_shaman": REGULAR + "goblin_shaman.glb",
	"goblin_king": "res://assets/original/ember_art/goblin_king.glb",
	"spore_husk": REGULAR + "spore_husk.glb",
	"mossbound_treant": REGULAR + "mossbound_treant.glb",
	"spore_beast": REGULAR + "spore_beast.glb",
	"blightmaw_matriarch": "res://assets/original/ember_art/enemies/blightmaw_matriarch.glb",
	"earth_training_dummy": REGULAR + "dummy_earth.glb",
	"water_training_dummy": REGULAR + "dummy_tidal.glb",
	"branded_troll": REGULAR + "branded_troll.glb",
	"forge_construct": REGULAR + "forge_construct.glb",
	"drowned_cultist": REGULAR + "drowned_cultist.glb",
	"harpy": REGULAR + "harpy.glb",
	"storm_elemental": REGULAR + "storm_elemental.glb",
}
## Mesh height in metres (feet on y = 0). Collision stays def.size. The face, seam
## or core was sculpted onto the weak point, so this is not the hitbox height.
const VISUAL_HEIGHT := {
	"goblin_grunt": 1.22,
	"goblin_archer": 1.46,
	"goblin_shaman": 1.68,
	"gnawer": 0.45,
	"heap": 2.25,
	"ooze": 0.94,
	"scorchling": 1.05,
	"earth_training_dummy": 1.80,
	"water_training_dummy": 1.80,
	"spore_husk": 1.70,
	"mossbound_treant": 3.21,
	"spore_beast": 2.28,
	"branded_troll": 2.47,
	"forge_construct": 2.76,
	"drowned_cultist": 2.05,
	"harpy": 2.15,
	"storm_elemental": 2.75,
}
## Batch 08b: nodes freed when the body dies (the King's Crown becomes his drop).
const DEATH_HIDE := {"goblin_king": ["Crown"]}
## Batch 08b: Throw reuses Punch and has no release marker; the rock leaves at 40%.
const THROW_RELEASE := 0.4
## Step 125 (Art A7): extra bodies picked at random per spawn (visual only).
const VARIANTS := {"gnawer": [REGULAR + "gnawer_mangy.glb", REGULAR + "gnawer_plague.glb"]}
## Step 125: procedural bodies for types with no CC0 model.
const PROCEDURAL := ["scorchling"]
const WARDEN_EYES := Color(0.75, 0.3, 1.0)


static func path_for(id: String) -> String:
	if not MODELS.has(id):
		return ""
	var p := String(MODELS[id])
	return p if p.begins_with("res://") else DIR + p


static func height_for(id: String, box_h: float) -> float:
	return float(VISUAL_HEIGHT.get(id, box_h))


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
		var pick := String(vs[randi() % vs.size()])
		path = pick if pick.begins_with("res://") else DIR + pick
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


## Batch 08b: hides the model parts that drop on death (the Goblin King's Crown); returns
## how many were hidden.
static func on_death(id: String, m: Node3D) -> int:
	var n := 0
	if m == null:
		return 0
	for part: String in DEATH_HIDE.get(id, []):
		for c in m.find_children(part, "Node3D", true, false):
			(c as Node3D).visible = false
			n += 1
	return n


## Seconds into the model's Throw clip at which the King's rock spawns (0 with no clip).
static func throw_release(m: Node) -> float:
	var ap := m.find_child("AnimationPlayer", true, false) as AnimationPlayer if m else null
	if ap == null or not ap.has_animation(&"Throw"):
		return 0.0
	return ap.get_animation(&"Throw").length * THROW_RELEASE


## L3: a loose copy of the King's Crown mesh (a static prop, ground at y = 0), or null.
static func crown_drop(m: Node) -> Node3D:
	var c := m.find_child("Crown", true, false) as MeshInstance3D if m else null
	if c == null or c.mesh == null:
		return null
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = c.mesh
	var ab := c.mesh.get_aabb()
	var s := c.global_transform.basis.get_scale() if c.is_inside_tree() else Vector3.ONE
	mi.scale = s
	mi.position = -Vector3(ab.get_center().x, ab.position.y, ab.get_center().z) * s
	root.add_child(mi)
	return root
