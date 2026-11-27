class_name StaffKit
extends RefCounted
## Modular staff and wand (0.15.0). One project-made mesh per part type and tier,
## shared by both forms. Sockets, cores and veins use the sheet palette. The viewmodel
## focus gem stays the element-table colour (see Viewmodel).

const DIR := "res://assets/original/weapons/staff_kit/"
const MAT_DIR := "res://resources/weapons/"
const ELEM_IDS: PackedStringArray = ["arcane", "fire", "water", "earth", "air", "light", "dark"]

const WOOD := {
	"basic": Color(0.36, 0.24, 0.14),
	"uncommon": Color(0.66, 0.54, 0.36),
	"rare": Color(0.30, 0.18, 0.11),
	"mythic": Color(0.14, 0.09, 0.08),
	"primordial": Color(0.40, 0.30, 0.20),
	"unique": Color(0.26, 0.16, 0.11),
}
const METAL_MIX := {
	"basic": 0.12,
	"uncommon": 0.22,
	"rare": 0.38,
	"mythic": 0.58,
	"primordial": 0.30,
	"unique": 0.42,
}

static var _layout: Dictionary = {}


static func variant(p: WieldablePart, n: int) -> int:
	return absi(hash(p.id)) % n if p != null else 0


static func layout() -> Dictionary:
	if _layout.is_empty():
		var f := FileAccess.open(DIR + "layout.json", FileAccess.READ)
		_layout = JSON.parse_string(f.get_as_text())
	return _layout


static func sheet_color(element: int) -> Color:
	var i := clampi(element, 0, ELEM_IDS.size() - 1)
	var mat := load("%selement_%s.tres" % [MAT_DIR, ELEM_IDS[i]]) as StandardMaterial3D
	return mat.albedo_color if mat != null else Color.WHITE


static func _scale_for(length: float, explicit: float) -> float:
	if explicit > 0.0:
		return explicit
	var lay := layout()
	var view := float(lay["view_staff"]) if length >= 0.45 else float(lay["view_wand"])
	return view / float(lay["staff_length"])


static func mesh_id(part_name: String, tier: String) -> String:
	var t := tier if WOOD.has(tier) else "basic"
	return "%s_%s" % [part_name, t]


static func instantiate(id: String) -> Node3D:
	var ps := load(DIR + id + ".glb") as PackedScene
	var inst := ps.instantiate() as Node3D
	var mi := _mesh_of(inst)
	if mi != null and mi != inst:
		inst.remove_child(mi)
		inst.free()
		return mi
	return inst


## `length` is the legacy shaft length (viewmodel). Pass `scale` > 0 for a world
## scale (1.0 is the 1.82 m staff, 0.40/1.82 is the wand). `lay_flat` aims the
## tip down -Z for the viewmodel; the contact sheets leave it upright.
static func build(
	w: WieldableInstance,
	length: float,
	_r: float,
	_gr: float,
	_elem: Color,
	layers: int,
	scale := -1.0,
	lay_flat := true
) -> Node3D:
	var lay := layout()
	var sc := _scale_for(length, scale)
	var kit := Node3D.new()
	kit.name = "Kit"
	var weapon := Node3D.new()
	weapon.name = "Weapon"
	kit.add_child(weapon)
	var staff_len := float(lay["staff_length"])
	var names := ["handle", "exterior", "interior", "head", "charm"]
	var types := [
		WieldablePart.PartType.HANDLE,
		WieldablePart.PartType.EXTERIOR,
		WieldablePart.PartType.INTERIOR,
		WieldablePart.PartType.HEAD,
		WieldablePart.PartType.CHARM,
	]
	for i in names.size():
		var part := w.part(types[i])
		if part == null:
			continue
		var inst := instantiate(mesh_id(names[i], part.rarity))
		inst.name = names[i].capitalize()
		_paint(inst, part)
		_dress(inst, layers)
		if names[i] == "charm":
			var hook: Array = lay["charm_hook"]
			inst.position = Vector3(float(hook[0]), float(hook[1]), float(hook[2]))
			if lay_flat:
				inst.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		else:
			var span: Array = lay[names[i]]
			inst.position = Vector3(0.0, float(span[0]), 0.0)
		weapon.add_child(inst)
	weapon.scale = Vector3.ONE * sc
	if lay_flat:
		weapon.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		weapon.position = Vector3(0.0, 0.0, staff_len * 0.5 * sc)
	_store_markers(kit, weapon)
	return kit


static func _store_markers(kit: Node3D, weapon: Node3D) -> void:
	var focus := weapon.find_child("Focus", true, false) as Node3D
	var tip := weapon.find_child("Tip", true, false) as Node3D
	if focus != null:
		kit.set_meta("focus", weapon.transform * (focus.get_parent().position + focus.position))
	if tip != null:
		kit.set_meta("tip", weapon.transform * (tip.get_parent().position + tip.position))


static func _paint(inst: Node, part: WieldablePart) -> void:
	var mi := _mesh_of(inst)
	if mi == null or mi.mesh == null:
		return
	var elem := sheet_color(int(part.element))
	if not part.gems.is_empty() and part.gems[0] != null:
		elem = sheet_color(int(part.gems[0].element))
	var tier := part.rarity if WOOD.has(part.rarity) else "basic"
	var wood: Color = WOOD[tier]
	if tier == "mythic":
		wood = wood.lerp(elem, 0.62)
	var mix := float(METAL_MIX[tier])
	var metal := Color(0.55, 0.52, 0.46).lerp(elem, mix).lerp(part.rarity_color(), 0.14)
	var wrap := Color(0.28, 0.16, 0.10).lerp(elem, 0.45 if tier != "basic" else 0.28)
	var mesh := mi.mesh
	for s in mesh.get_surface_count():
		var base := mesh.surface_get_material(s)
		var n := (base.resource_name if base != null else "").to_lower()
		var m := StandardMaterial3D.new()
		m.resource_name = n
		if n.contains("gem") or n.contains("core"):
			var src := load("%selement_%s.tres" % [MAT_DIR, ELEM_IDS[clampi(int(part.element), 0, 6)]]) as StandardMaterial3D
			if not part.gems.is_empty() and part.gems[0] != null and n.contains("gem"):
				src = load(
					"%selement_%s.tres" % [MAT_DIR, ELEM_IDS[clampi(int(part.gems[0].element), 0, 6)]]
				) as StandardMaterial3D
			if src != null:
				m = src.duplicate() as StandardMaterial3D
			else:
				m.albedo_color = elem
				m.emission_enabled = true
				m.emission = elem
				m.emission_energy_multiplier = 1.7
		elif n.contains("metal"):
			m.albedo_color = metal
			m.metallic = 0.85
			m.roughness = 0.32
		elif n.contains("wrap"):
			m.albedo_color = wrap
			m.metallic = 0.08
			m.roughness = 0.68
		else:
			m.albedo_color = wood
			m.roughness = 0.84
		mi.set_surface_override_material(s, m)


static func _mesh_of(inst: Node) -> MeshInstance3D:
	if inst is MeshInstance3D:
		return inst
	var found := inst.find_children("*", "MeshInstance3D", true, false)
	return found[0] as MeshInstance3D if not found.is_empty() else null


static func _dress(inst: Node, layers: int) -> void:
	var nodes: Array[Node] = []
	if inst is MeshInstance3D:
		nodes.append(inst)
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		nodes.append(n)
	for n in nodes:
		var mi := n as MeshInstance3D
		mi.layers = layers
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func tris(root: Node) -> int:
	var t := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m:
			for s in m.get_surface_count():
				var a := m.surface_get_arrays(s)
				var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
				t += (idx.size() if idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	if root is MeshInstance3D and (root as MeshInstance3D).mesh:
		var m2 := (root as MeshInstance3D).mesh
		for s in m2.get_surface_count():
			var a2 := m2.surface_get_arrays(s)
			var idx2: PackedInt32Array = a2[Mesh.ARRAY_INDEX]
			t += (idx2.size() if idx2.size() > 0 else (a2[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t
