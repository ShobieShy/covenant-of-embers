class_name ScorchlingBody
extends Node3D
## Ember Scorchling. The body is the sculpt in regular_enemies/scorchling.glb.
## The flame node flickers and the imp bobs. One OmniLight, no shadows.

const MESH := "res://assets/original/ember_art/regular_enemies/scorchling.glb"
const EMBER := Color(1.0, 0.42, 0.08)

var flame: MeshInstance3D
var light: OmniLight3D
var _t := 0.0
var _base_y := 0.0


static func build(height: float) -> ScorchlingBody:
	var b := ScorchlingBody.new()
	b.name = "Scorchling"
	var inst := (load(MESH) as PackedScene).instantiate() as Node3D
	b.add_child(inst)
	var box := AABB()
	var first := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = _local(inst, mi) * (mi as MeshInstance3D).get_aabb()
		box = a if first else box.merge(a)
		first = false
	if not first and box.size.y > 0.001:
		var s := height / box.size.y
		inst.scale = Vector3.ONE * s
		inst.position.y = -box.position.y * s
	inst.rotation.y = PI  # the sculpt faces +Z; the fight faces -Z
	b.flame = inst.find_child("Flame", true, false) as MeshInstance3D
	b.light = OmniLight3D.new()
	b.light.light_color = EMBER
	b.light.light_energy = 1.2
	b.light.omni_range = 3.0
	b.light.shadow_enabled = false
	b.light.position = Vector3(0, height * 0.7, 0)
	b.add_child(b.light)
	return b


static func _local(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


static func tris(n: Node) -> int:
	var t := 0
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var a := m.surface_get_arrays(s)
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			t += (idx.size() if idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t


func _ready() -> void:
	_base_y = position.y


func _process(dt: float) -> void:
	_t += dt
	position.y = _base_y + sin(_t * 3.0) * 0.03
	if flame:
		flame.scale = Vector3(1.0, 0.85 + 0.25 * absf(sin(_t * 11.0) * cos(_t * 7.0)), 1.0)
	if light:
		light.light_energy = 1.0 + 0.4 * absf(sin(_t * 9.0))
