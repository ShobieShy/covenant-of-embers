class_name OldOakLandmark
extends RefCounted
## 0.11.4: Ember Art's Old Oak v4, placed on the Town's east lobe.
## ShobieShy shipped this mesh as it is. The 4/5 painting score is waived for
## this asset only. The primitive-mesh gate still applies to every other scene.

## Painting (0.82, 0.38) on a 320 m town whose centre is (0.52, 0.52).
## -Z is north, +X is east.
const PLACE := Vector3(96.0, 0.0, -44.8)
const YAW_DEG := 135.0
## LOD0 (30,998 tris) through 60 m, then LOD1 (9,350). A 40 m shot stays on LOD0.
const LOD0_END := 60.0
const SCISSOR := 0.35


## Configures the instanced glTF: visibility ranges, foliage cards, the hidden
## collision mesh (194 tris, including the root ramp), and a plain door gate.
static func prepare(level: Node3D, player: Player = null, on_used: Callable = Callable()) -> Node3D:
	var oak := level.get_node_or_null(^"Props/east_oak") as Node3D
	if oak == null or oak.has_meta(&"oak_ready"):
		return oak
	var lod0 := oak.find_child("LOD0", true, false) as Node3D
	var lod1 := oak.find_child("LOD1", true, false) as Node3D
	_range(lod0, 0.0, LOD0_END)
	_range(lod1, LOD0_END, 0.0)
	for n in oak.find_children("FoliageCards*", "MeshInstance3D", true, false):
		_foliage(n as MeshInstance3D)
	_collision(oak)
	_door(oak, player, on_used)
	oak.set_meta(&"oak_ready", true)
	return oak


static func _range(root: Node3D, begin: float, end: float) -> void:
	if root == null:
		return
	for n in root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		g.visibility_range_begin = begin
		g.visibility_range_end = end
		g.visibility_range_begin_margin = 6.0
		g.visibility_range_end_margin = 6.0
		g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


static func _foliage(mi: MeshInstance3D) -> void:
	var base := mi.get_active_material(0) as StandardMaterial3D
	if base == null:
		return
	var m := base.duplicate() as StandardMaterial3D
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = SCISSOR
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m


## Godot imports the `old_oak-colonly` mesh as a concave StaticBody (the -col suffix).
## That hull is the root ramp. Keep it on the world layer and do not draw it.
static func _collision(oak: Node3D) -> void:
	for n in oak.find_children("*", "StaticBody3D", true, false):
		var body := n as StaticBody3D
		body.collision_layer = 1
		body.collision_mask = 0
		for c in body.get_children():
			if c is MeshInstance3D:
				(c as MeshInstance3D).visible = false


static func _door(oak: Node3D, player: Player, on_used: Callable) -> void:
	var door := oak.find_child("Door", true, false) as Node3D
	if door == null or not on_used.is_valid():
		return
	var gate := LevelGate.new("bobs_lab")
	gate.name = "LabDoor"
	gate.set_meta(&"plain", true)
	gate.player = player
	door.add_child(gate)
	gate.used.connect(on_used)
