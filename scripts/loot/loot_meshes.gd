class_name LootMeshes
extends RefCounted
## Step 123 (Art A5): small low-poly ground props for drops and pickups (PROC, plus the
## CC0 KayKit staff/wand/spellbook and Quaternius trash bag already in assets/).
## prop_for() returns a Node3D sitting on y = 0, about 0.3-0.5 m across, trimmed in `c`
## (the rarity / pickup colour). Wieldables use the KayKit models laid on their side.

const KAYKIT := "res://assets/kaykit/props/"
const TRASH_BAG := "res://assets/quaternius/enemies/props/Trash_Bag.glb"
const CLOTH := Color(0.42, 0.3, 0.22)
const LEATHER := Color(0.3, 0.19, 0.11)
const GLASS := Color(0.85, 0.95, 1.0, 0.45)


static func _mat(c: Color, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = Color(c, 1.0)
		m.emission_energy_multiplier = glow
	return m


static func _cyl(rt: float, rb: float, h: float, segs := 8) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func _sph(r: float, segs := 8) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = segs / 2
	return s


static func _box(sz: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = sz
	return b


static func _part(root: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	root.add_child(mi)
	return mi


static func _scene(path: String, size: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var n := (load(path) as PackedScene).instantiate() as Node3D
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = CharacterModel._local_xform(n, mi as Node3D) * (mi as MeshInstance3D).get_aabb()
		box = a if first else box.merge(a)
		first = false
	if not first and box.get_longest_axis_size() > 0.0:
		var k := size / box.get_longest_axis_size()
		n.scale = Vector3.ONE * k
		n.position.y = -box.position.y * k
	return n


## The ground prop for a drop kind: "hat", "clothes", "belt", "shoes", "grimoire", "staff",
## "wand", "part", "gold", "mana", "dust", "potion", "trash".
static func prop_for(kind: String, c: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Prop"
	var trim := _mat(c, 0.6)
	match kind:
		"hat":
			_part(root, _cyl(0.2, 0.2, 0.02, 10), _mat(CLOTH), Vector3(0, 0.01, 0))
			_part(root, _cyl(0.02, 0.11, 0.3, 8), _mat(CLOTH), Vector3(0.0, 0.16, 0.0), Vector3(0, 0, 0.25))
			_part(root, _cyl(0.115, 0.115, 0.03, 8), trim, Vector3(0, 0.04, 0))
		"clothes":
			_part(root, _box(Vector3(0.36, 0.06, 0.28)), _mat(CLOTH), Vector3(0, 0.03, 0))
			_part(root, _box(Vector3(0.3, 0.05, 0.22)), _mat(CLOTH.lightened(0.15)), Vector3(0, 0.085, 0))
			_part(root, _box(Vector3(0.31, 0.012, 0.04)), trim, Vector3(0, 0.115, 0.06))
		"belt":
			var t := TorusMesh.new()
			t.inner_radius = 0.11
			t.outer_radius = 0.14
			t.rings = 12
			t.ring_segments = 4
			_part(root, t, _mat(LEATHER), Vector3(0, 0.015, 0))
			_part(root, _box(Vector3(0.07, 0.03, 0.06)), trim, Vector3(0.125, 0.02, 0))
		"shoes":
			for sx in [-0.07, 0.07]:
				_part(root, _box(Vector3(0.09, 0.08, 0.22)), _mat(LEATHER), Vector3(sx, 0.04, 0.02 * signf(sx)))
				_part(root, _box(Vector3(0.095, 0.02, 0.06)), trim, Vector3(sx, 0.085, -0.05 + 0.02 * signf(sx)))
		"grimoire", "staff", "wand":
			var path := (
				{"grimoire": "spellbook_closed.gltf", "staff": "staff.gltf", "wand": "wand.gltf"}[kind] as String
			)
			var n := _scene(KAYKIT + path, 0.55 if kind == "staff" else 0.32)
			if n:
				n.rotation = Vector3(0, 0.6, PI * 0.5) if kind != "grimoire" else Vector3(0, 0.4, 0)
				n.position.y += 0.04
				root.add_child(n)
			_part(root, _sph(0.035, 6), trim, Vector3(0, 0.05, 0))
		"part":
			_part(
				root,
				_cyl(0.045, 0.045, 0.26, 6),
				_mat(Color(0.36, 0.25, 0.15)),
				Vector3(0, 0.05, 0),
				Vector3(0, 0, PI * 0.5)
			)
			for x in [-0.08, 0.08]:
				_part(root, _cyl(0.06, 0.06, 0.03, 6), trim, Vector3(x, 0.05, 0), Vector3(0, 0, PI * 0.5))
			_part(root, _sph(0.05, 6), _mat(c, 1.5), Vector3(0.16, 0.05, 0))
		"gold":
			for i in 5:
				var a := TAU * i / 5.0
				_part(
					root,
					_cyl(0.05, 0.05, 0.015, 8),
					_mat(c, 0.3),
					Vector3(cos(a) * 0.05, 0.01 + 0.016 * (i % 3), sin(a) * 0.05)
				)
			_part(root, _cyl(0.05, 0.05, 0.015, 8), _mat(c, 0.3), Vector3(0, 0.055, 0), Vector3(0.6, 0, 0.3))
		"mana":
			_part(root, _sph(0.11, 10), _mat(Color(c, 0.75), 2.0), Vector3(0, 0.2, 0))
			_part(root, _sph(0.05, 6), _mat(Color.WHITE, 3.0), Vector3(0, 0.2, 0))
		"dust":
			_part(root, _sph(0.1, 8), _mat(LEATHER.lightened(0.2)), Vector3(0, 0.09, 0))
			_part(root, _cyl(0.035, 0.05, 0.06, 6), _mat(LEATHER.lightened(0.2)), Vector3(0, 0.2, 0))
			_part(root, _cyl(0.045, 0.045, 0.015, 6), trim, Vector3(0, 0.19, 0))
			_part(root, _sph(0.03, 6), _mat(c, 2.0), Vector3(0.07, 0.03, 0.06))
		"potion":
			_part(root, _sph(0.085, 8), _mat(GLASS), Vector3(0, 0.085, 0))
			_part(root, _sph(0.07, 8), _mat(c, 1.0), Vector3(0, 0.075, 0))
			_part(root, _cyl(0.025, 0.03, 0.08, 6), _mat(GLASS), Vector3(0, 0.19, 0))
			_part(root, _cyl(0.028, 0.028, 0.03, 6), _mat(LEATHER), Vector3(0, 0.24, 0))
		"trash":
			var bag := _scene(TRASH_BAG, 0.5)
			if bag:
				root.add_child(bag)
			else:
				_part(root, _sph(0.2, 8), _mat(Color(0.15, 0.15, 0.15)), Vector3(0, 0.2, 0))
		_:
			_part(root, _box(Vector3.ONE * 0.2), trim, Vector3(0, 0.1, 0))
	return root


## The prop kind for a LootDrop.
static func kind_for(d: LootDrop) -> String:
	match d.kind:
		LootDrop.Kind.WIELDABLE:
			var w := d.item as WieldableInstance
			return "wand" if w and w.type() == WieldableDef.Type.WAND else "staff"
		LootDrop.Kind.PART:
			return "part"
		_:
			var s := d.equip_slot_id()
			return s if not s.is_empty() else "clothes"
