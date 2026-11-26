class_name WarrensTheme
extends RefCounted
## Act I PBR palette. Packed earth, cave rock, timber, iron, bone, violet crystal.
## Textures are ambientCG (CC0) plus the project's crystal set. Albedo tints pull the
## neutral scans toward the warrens painting: warm brown stone and torch-lit dirt.

const DIRT := "res://assets/ambientcg/Ground080/"
const ROCK := "res://assets/ambientcg/Rock030/"
const WOOD := "res://assets/ambientcg/Wood049/"
const METAL := "res://assets/ambientcg/Metal032/"
const CRYSTAL := "res://assets/original/ember_art/terrain/crystal_albedo_height.png"
const CRYSTAL_N := "res://assets/original/ember_art/terrain/crystal_normal_roughness.png"
const PLAQUE := "res://assets/original/ember_art/warrens/pbr/joe_plaque.png"
const SIGIL := "res://assets/original/ember_art/warrens/pbr/crate_sigil.png"

static var _mats := {}


static func mat(kind: String) -> StandardMaterial3D:
	if not _mats.has(kind):
		_mats[kind] = _make(kind)
	return _mats[kind]


static func paint(mi: MeshInstance3D, kind: String, double_sided := false) -> void:
	if mi.mesh == null:
		return
	var use := mat(kind)
	if double_sided:
		use = use.duplicate()
		use.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in mi.mesh.get_surface_count():
		var existing := mi.mesh.surface_get_material(i) as StandardMaterial3D
		var forced := kind == "flame" or kind == "sigil" or kind == "plaque" or kind == "crystal"
		if not forced and existing and existing.emission_enabled and existing.emission_energy_multiplier > 0.05:
			var glow := existing.duplicate() as StandardMaterial3D
			glow.emission_energy_multiplier = maxf(glow.emission_energy_multiplier, 2.2)
			mi.set_surface_override_material(i, glow)
		else:
			mi.set_surface_override_material(i, use)


static func paint_tree(root: Node) -> void:
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for n in nodes:
		if n is MeshInstance3D:
			var node_name := String(n.name)
			var kind := _kind_for(node_name, root.name)
			paint(n as MeshInstance3D, kind, kind == "sigil" or "crate" in node_name.to_lower())


static func retint_kit(dress: Node3D) -> void:
	for mi in dress.find_children("*", "MeshInstance3D", true, false):
		var id := _kit_id(mi)
		if id == "":
			continue
		var kind := "rock"
		if id.begins_with("stair") or id.begins_with("torch") or id.begins_with("crate") or id.begins_with("barricade"):
			kind = "wood"
		elif id.begins_with("bone") or id.begins_with("spike"):
			kind = "bone"
		elif id.begins_with("mushroom"):
			kind = "fungus"
		elif id.begins_with("banner") or id.begins_with("bedroll"):
			kind = "wood"
		elif id.begins_with("cook") or id.begins_with("craft"):
			kind = "wood"
		paint(mi as MeshInstance3D, kind)


static func _kind_for(node_name: String, root_name: String) -> String:
	var n := node_name.to_lower()
	var r := String(root_name).to_lower()
	if n == "flame" or n.begins_with("flame"):
		return "flame"
	if n == "sigil":
		return "sigil"
	if "crystal" in n or "crystal" in r:
		return "crystal"
	if "hoop" in n or "pot" in n:
		return "metal"
	if "plaque" in n or "joe" in n or "plaque" in r:
		return "plaque"
	if "throne" in n or "throne" in r:
		return "bone"
	if "rock" in n or "rock" in r:
		return "rock"
	if "root" in n or "root" in r or "spike" in n or "timber" in n or "barrel" in n or "crate" in r:
		return "wood"
	return "wood"


static func _kit_id(n: Node) -> String:
	var p := n
	while p:
		var nm := String(p.name)
		if nm == "Dress":
			return ""
		if (
			nm.begins_with("stair")
			or nm.begins_with("torch")
			or nm.begins_with("crate")
			or nm.begins_with("bone")
			or nm.begins_with("barricade")
			or nm.begins_with("spike")
			or nm.begins_with("mushroom")
			or nm.begins_with("banner")
			or nm.begins_with("bedroll")
			or nm.begins_with("cook")
			or nm.begins_with("craft")
			or nm.begins_with("goblin")
		):
			return nm
		p = p.get_parent()
	return ""


static func _make(kind: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	match kind:
		"dirt":
			_pbr(m, DIRT, Color(0.42, 0.32, 0.22), Vector3(0.45, 0.45, 0.45))
		"rock":
			_pbr(m, ROCK, Color(0.62, 0.48, 0.36), Vector3(0.28, 0.28, 0.28))
		"wood":
			_pbr(m, WOOD, Color(0.55, 0.38, 0.22), Vector3(0.5, 0.5, 0.5))
		"metal":
			_pbr(m, METAL, Color(0.42, 0.38, 0.32), Vector3(1.1, 1.1, 1.1))
			m.metallic = 0.45
			m.roughness = 0.55
		"bone":
			_pbr(m, ROCK, Color(0.78, 0.68, 0.52), Vector3(0.85, 0.85, 0.85))
		"fungus":
			_pbr(m, DIRT, Color(0.4, 0.62, 0.32), Vector3(0.7, 0.7, 0.7))
			m.emission_enabled = true
			m.emission = Color(0.15, 0.45, 0.18)
			m.emission_energy_multiplier = 0.35
		"crystal":
			m.albedo_texture = load(CRYSTAL)
			m.albedo_color = Color(0.75, 0.6, 1.0)
			m.normal_enabled = true
			m.normal_texture = load(CRYSTAL_N)
			m.roughness = 0.28
			m.emission_enabled = true
			m.emission = Color(0.35, 0.12, 0.7)
			m.emission_energy_multiplier = 0.45
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(0.9, 0.9, 0.9)
		"flame":
			m.albedo_color = Color(0.6, 1.0, 0.45)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.emission_enabled = true
			m.emission = Color(0.35, 1.0, 0.32)
			m.emission_energy_multiplier = 4.0
		"sigil":
			m.albedo_texture = load(SIGIL)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.emission_enabled = true
			m.emission_texture = load(SIGIL)
			m.emission = Color(0.4, 0.62, 1.0)
			m.emission_energy_multiplier = 2.2
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"plaque":
			m.albedo_texture = load(PLAQUE)
			m.albedo_color = Color(0.95, 0.9, 0.85)
			m.roughness = 0.82
		_:
			_pbr(m, ROCK, Color(0.6, 0.5, 0.4), Vector3(0.4, 0.4, 0.4))
	return m


static func _pbr(m: StandardMaterial3D, dir: String, tint: Color, scale: Vector3) -> void:
	m.albedo_texture = load(dir + "color.jpg") as Texture2D
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(dir + "normal.jpg") as Texture2D
	m.roughness_texture = load(dir + "roughness.jpg") as Texture2D
	m.uv1_triplanar = true
	m.uv1_scale = scale
