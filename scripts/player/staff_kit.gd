class_name StaffKit
extends RefCounted
## Step 122 (Art A4): procedural low-poly modular staff/wand kit (PROC, no external asset).
## Builds the dressing around the Viewmodel's shaft + gem from the attached parts, on shared
## sockets along the shaft (local -Z = forward, shaft centred on 0):
##   HANDLE   -> grip wrap + pommel at the back end (3 variants by part id)
##   EXTERIOR -> shell bands along the shaft, trimmed in the rarity colour (3 variants)
##   INTERIOR -> an emissive element core visible through a slatted cage (2 variants)
##   HEAD     -> prongs/crescent around the gem + one socket gem per filled gem slot (3 variants)
##   CHARM    -> a small bauble hanging under the head
## Variants come from a stable hash of the part id, so a part always looks the same.
## Budget: a full staff stays far under the 4k-tri cap (low segment counts).

const WOOD := Color(0.36, 0.25, 0.15)
const LEATHER := Color(0.22, 0.14, 0.09)
const METAL := Color(0.55, 0.55, 0.58)


static func variant(p: WieldablePart, n: int) -> int:
	return absi(hash(p.id)) % n if p != null else 0


static func mat(c: Color, emissive := false, metal := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.35 if metal else 0.85
	m.metallic = 0.7 if metal else 0.0
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 2.0
	return m


static func cyl(r_top: float, r_bot: float, h: float, segs := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


## Adds a mesh along the shaft axis (cylinder Y -> -Z) at z.
static func _add(root: Node3D, mesh: Mesh, m: Material, z: float, layers: int, n: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = m
	mi.layers = layers
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	mi.position = Vector3(0, 0, z)
	root.add_child(mi)
	return mi


## A fresh "Kit" node for `w` (length / radius / gem radius of the shaft, element colour).
static func build(w: WieldableInstance, length: float, r: float, gr: float, elem: Color, layers: int) -> Node3D:
	var kit := Node3D.new()
	kit.name = "Kit"
	var trim := mat(w.rarity_color(), false, true)
	var back := 0.5 * length
	var front := -0.5 * length
	# Handle: grip + pommel
	var h := w.part(WieldablePart.PartType.HANDLE)
	var hv := variant(h, 3)
	_add(kit, cyl(r * 1.25, r * 1.25, length * 0.22), mat(LEATHER), back - length * 0.16, layers, "Grip")
	var pommel: Mesh = (
		[SphereMesh.new(), cyl(r * 0.6, r * 1.6, r * 2.5, 6), cyl(r * 1.7, r * 1.7, r * 1.0, 6)][hv] if h else null
	)
	if pommel is SphereMesh:
		(pommel as SphereMesh).radius = r * 1.6
		(pommel as SphereMesh).height = r * 3.2
		(pommel as SphereMesh).radial_segments = 8
		(pommel as SphereMesh).rings = 4
	if pommel:
		_add(kit, pommel, trim if hv != 1 else mat(METAL, false, true), back + r, layers, "Pommel")
	# Exterior: banded shell
	var ex := w.part(WieldablePart.PartType.EXTERIOR)
	if ex:
		var ev := variant(ex, 3)
		var n: int = [2, 3, 4][ev]
		for i in n:
			var z := lerpf(back - length * 0.35, front + length * 0.2, float(i) / maxf(1.0, n - 1))
			var band := cyl(r * 1.45, r * (1.2 if ev == 2 else 1.45), r * (1.2 if ev == 0 else 0.8), 8)
			_add(kit, band, trim, z, layers, "Band%d" % i)
	# Interior: glowing core in a cage
	var inn := w.part(WieldablePart.PartType.INTERIOR)
	if inn:
		var zc := front + length * 0.3
		_add(kit, cyl(r * 0.9, r * 0.9, length * 0.25, 6), mat(elem, true), zc, layers, "Core")
		var slats := 4 if variant(inn, 2) == 0 else 6
		for i in slats:
			var a := TAU * i / slats
			var s := _add(
				kit, cyl(r * 0.25, r * 0.25, length * 0.27, 4), mat(METAL, false, true), zc, layers, "Slat%d" % i
			)
			s.position += Vector3(cos(a), sin(a), 0) * r * 1.5
	# Head: prongs around the gem + socket gems
	var hd := w.part(WieldablePart.PartType.HEAD)
	var gz := front - gr * 0.6
	var hv2 := variant(hd, 3) if hd else 0
	var prongs: int = [3, 4, 2][hv2]
	for i in prongs:
		var a := TAU * i / prongs + 0.3
		var p := _add(
			kit, cyl(r * 0.15, r * 0.4, gr * 2.4, 4), trim if hd else mat(WOOD), gz + gr * 0.2, layers, "Prong%d" % i
		)
		var out := Vector3(cos(a), sin(a), 0)
		p.position += out * gr * (1.15 if hv2 != 2 else 1.4)
		p.rotation = Vector3(-PI * 0.5 + 0.35 * out.y, 0.0, 0.0)
	_add(kit, cyl(gr * 0.9, r * 1.3, gr * 0.8, 8), trim if hd else mat(WOOD), front + gr * 0.2, layers, "Collar")
	if hd:
		for i in hd.gems.size():
			var g := hd.gems[i]
			var sg := SphereMesh.new()
			sg.radius = r * 0.6
			sg.height = r * 1.2
			sg.radial_segments = 6
			sg.rings = 3
			var gc: Color = ElementTable.load_default().color(int(g.element)) if g != null else elem
			var gi := _add(kit, sg, mat(gc, true), front + length * 0.08, layers, "Socket%d" % i)
			var a: float = TAU * i / maxf(1, hd.gems.size())
			gi.position += Vector3(cos(a), sin(a), 0) * r * 1.4
	# Charm: bauble on a short cord under the head
	var ch := w.part(WieldablePart.PartType.CHARM)
	if ch:
		var cord := _add(kit, cyl(r * 0.08, r * 0.08, gr * 1.6, 3), mat(LEATHER), front + length * 0.12, layers, "Cord")
		cord.rotation = Vector3.ZERO
		cord.position.y = -gr * 0.8
		var b := SphereMesh.new()
		b.radius = r * 0.8
		b.height = r * 1.6
		b.radial_segments = 6
		b.rings = 3
		var bm := _add(
			kit,
			b,
			mat(ch.rarity_def().color if ch.rarity_def() else METAL, false, true),
			front + length * 0.12,
			layers,
			"Charm"
		)
		bm.position.y = -gr * 1.7
	return kit


## Triangle count of a kit (tests: the 4k budget).
static func tris(root: Node) -> int:
	var t := 0
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m:
			for s in m.get_surface_count():
				var a := m.surface_get_arrays(s)
				var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
				t += (idx.size() if idx.size() > 0 else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return t
