class_name ScorchlingBody
extends Node3D
## Step 125 (Art A7): the Breach's fire imp, built from primitives (no CC0 imp in the batches).
## Charred body, ember belly, horns, glowing eyes and a head flame; the flame and its light
## flicker and the body bobs. ~600 tris, one OmniLight (no shadows) so Steam Deck stays cheap.

const CHAR := Color(0.16, 0.07, 0.05)
const EMBER := Color(1.0, 0.42, 0.08)
const FLAME := Color(1.0, 0.45, 0.08)

var flame: MeshInstance3D
var light: OmniLight3D
var _t := 0.0
var _base_y := 0.0


static func build(height: float) -> ScorchlingBody:
	var b := ScorchlingBody.new()
	b.name = "Scorchling"
	var k := height / 0.8
	var rig := Node3D.new()
	rig.name = "Rig"
	rig.scale = Vector3.ONE * k
	b.add_child(rig)
	var char_m := _mat(CHAR, 0.0)
	var ember_m := _mat(EMBER, 2.5)
	var flame_m := _mat(FLAME, 1.8)
	flame_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_m.albedo_color.a = 0.85
	_part(rig, _sphere(0.2, 0.36), char_m, Vector3(0, 0.3, 0))
	_part(rig, _sphere(0.13, 0.2), ember_m, Vector3(0, 0.3, -0.1))
	_part(rig, _sphere(0.15, 0.28), char_m, Vector3(0, 0.57, 0))
	for sx: float in [-1.0, 1.0]:
		_part(rig, _sphere(0.035, 0.05), ember_m, Vector3(0.06 * sx, 0.6, -0.13))
		var horn := _part(rig, _cone(0.04, 0.16), char_m, Vector3(0.09 * sx, 0.72, 0))
		horn.rotation_degrees = Vector3(0, 0, -25.0 * sx)
		var arm := _part(rig, _cone(0.05, 0.26), char_m, Vector3(0.22 * sx, 0.3, -0.02))
		arm.rotation_degrees = Vector3(-30, 0, 155.0 * sx)
		_part(rig, _sphere(0.05, 0.08), ember_m, Vector3(0.32 * sx, 0.2, -0.08))
		_part(rig, _cone(0.06, 0.18), char_m, Vector3(0.08 * sx, 0.08, 0)).rotation_degrees = Vector3(180, 0, 0)
	b.flame = _part(rig, _cone(0.1, 0.3), flame_m, Vector3(0, 0.82, 0.02))
	b.light = OmniLight3D.new()
	b.light.light_color = EMBER
	b.light.light_energy = 1.2
	b.light.omni_range = 3.0
	b.light.shadow_enabled = false
	b.light.position = Vector3(0, 0.5 * k, 0)
	b.add_child(b.light)
	return b


static func tris(n: Node) -> int:
	var t := 0
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var a := m.surface_get_arrays(s)
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			t += (idx.size() if idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t


static func _mat(c: Color, glow: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


static func _sphere(r: float, h: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h
	s.radial_segments = 10
	s.rings = 5
	return s


static func _cone(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	c.rings = 1
	return c


static func _part(parent: Node3D, mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = at
	parent.add_child(mi)
	return mi


func _ready() -> void:
	_base_y = position.y


func _process(dt: float) -> void:
	_t += dt
	position.y = _base_y + sin(_t * 3.0) * 0.03
	if flame:
		flame.scale = Vector3(1.0, 0.85 + 0.25 * absf(sin(_t * 11.0) * cos(_t * 7.0)), 1.0)
	if light:
		light.light_energy = 1.0 + 0.4 * absf(sin(_t * 9.0))
