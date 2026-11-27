class_name WarrensDress
extends RefCounted
## Act I burrow dress. The generator's rooms, doors, stairs and markers stay where they
## are. This replaces the flat kit shell with a rounded earthen burrow, floor by floor,
## and builds the throne hall as the painting's round bone chamber.
## Roofs are named CaveRoof so a top-down shot can hide them and see the plan.

const PROP := "res://assets/original/ember_art/warrens/pbr/"
const GREEN := Color(0.45, 1.0, 0.38)
const ORANGE := Color(1.0, 0.58, 0.28)

static var _props := {}
static var _mesh_cache := {}


static func room(
	r: Node3D, floor_no: int, kind: String, size: Vector2, open: Array, slot: float, stairs: bool, stair_row: int
) -> void:
	var dress := r.get_node_or_null("Dress") as Node3D
	if dress:
		_hide_flat_shell(dress)
		WarrensTheme.retint_kit(dress)
	var phase := float(hash(r.name) % 7)
	var hole := Vector3(999.0, 0, 0)
	if stairs:
		hole = WarrensKit.stair_hole(size, stair_row)
	var burrow := Node3D.new()
	burrow.name = "Burrow"
	r.add_child(burrow)
	r.set_meta(&"foot", size)
	var roofed := floor_no != 1
	_shell(burrow, size, open, hole, phase, roofed)
	_tunnels(burrow, size, open, slot, phase, roofed)
	_seal_corners(r, size, _radius(size), hole, open)
	_fill_light(burrow, size, floor_no)
	_theme(burrow, floor_no, kind, size, open, phase)
	if floor_no == 1:
		_timber(burrow, size, open)


static func finish(f: Node3D) -> void:
	var floor_no := int(f.get("floor_no"))
	var rooms: Array = f.get("rooms")
	if floor_no == 4:
		var west := _westmost(rooms)
		if west:
			var foot: Vector2 = west.get_meta(&"foot", Vector2(12, 12))
			var plaque := _put(west.get_node("Burrow"), "joe_plaque", Vector3(0, 0, -foot.y * 0.5 + 1.15), PI)
			if plaque:
				plaque.name = "joe_plaque"
	elif floor_no == 3:
		var mid := 0.0
		for room in rooms:
			mid += room.position.x
		mid /= maxf(float(rooms.size()), 1.0)
		for room in rooms:
			if room.position.x <= mid or String(room.get_meta(&"kind", "")) == "exit":
				continue
			var nest := room.get_node_or_null("Burrow") as Node3D
			if nest == null:
				continue
			var foot: Vector2 = room.get_meta(&"foot", Vector2(12, 12))
			_kit(nest, "bone_pile", Vector3(foot.x * 0.5 - 1.6, 0, 0.4), 0.4)
			_kit(nest, "bone_pile", Vector3(foot.x * 0.5 - 2.2, 0, -1.4), 1.2)
			_put(nest, "root_cluster", Vector3(foot.x * 0.5 - 1.8, 0, 1.2), 0.6, 0.7)


static func throne(arena: Node3D, hall: Node3D) -> void:
	for mi in hall.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visible = false
	var burrow := Node3D.new()
	burrow.name = "Burrow"
	arena.add_child(burrow)
	var radius := 15.1
	_circle(burrow, radius, 0.17)
	_scatter_ring(burrow, radius - 1.4)
	# Bone pyramid on the north side. The king stays on the floor just in front of it.
	var pyramid := _put(burrow, "throne_pyramid", Vector3(0, 0, -11.6))
	if pyramid:
		pyramid.name = "throne_pyramid"
	for spot in [Vector3(-8.4, 0, 7.2), Vector3(8.6, 0, 6.6), Vector3(-7.4, 0, 3.0), Vector3(7.6, 0, 2.2)]:
		var crates := _put(burrow, "sigil_crates", spot, randf_from_hash(spot) * 0.6, 1.45)
		if crates:
			crates.name = "sigil_crates"
			_omni(crates, Vector3(0, 1.3, 0.4), Color(0.4, 0.58, 1.0), 1.6, 5.5)
	for spot in [Vector3(-11.2, 0, 8.2), Vector3(11.4, 0, 7.4), Vector3(-10.6, 0, -7.2), Vector3(10.8, 0, -6.4)]:
		var gem := _put(burrow, "crystal_cluster", spot, spot.x * 0.1, 1.8)
		if gem:
			gem.name = "crystal_cluster"
			_omni(gem, Vector3(0, 1.2, 0), Color(0.55, 0.28, 1.0), 1.5, 6.5)
	for spot in [Vector3(-5.2, 0, 11.4), Vector3(5.4, 0, 11.2), Vector3(-3.4, 0, -8.2), Vector3(3.6, 0, -8.6)]:
		_put(burrow, "root_cluster", spot, spot.x, 1.15)
	for i in 8:
		var ang := float(i) / 8.0 * TAU
		if absf(wrapf(ang - PI * 0.5, -PI, PI)) < 0.28:
			continue
		var at := Vector3(cos(ang) * (radius - 0.7), 0, sin(ang) * (radius - 0.7))
		_torch(burrow, at, ang + PI)
	_omni(burrow, Vector3(0, 4.2, -2.0), ORANGE, 0.85, 22.0)
	_omni(burrow, Vector3(0, 2.4, -10.5), Color(1.0, 0.46, 0.18), 1.4, 9.0)


static func _theme(burrow: Node3D, floor_no: int, kind: String, size: Vector2, open: Array, phase: float) -> void:
	_torch(burrow, Vector3(-size.x * 0.28, 0, -size.y * 0.5 + 0.55), PI)
	_torch(burrow, Vector3(size.x * 0.28, 0, size.y * 0.5 - 0.55), 0.0)
	match floor_no:
		1:
			_put(burrow, "barrel", Vector3(-size.x * 0.5 + 1.7, 0, -size.y * 0.5 + 1.7), 0.4)
			_put(burrow, "barrel", Vector3(-size.x * 0.5 + 2.3, 0, -size.y * 0.5 + 2.5), 1.1, 0.85)
			_kit(burrow, "crate_stack", Vector3(size.x * 0.5 - 1.8, 0, -size.y * 0.5 + 1.8), 0.5)
			_put(burrow, "rock_chunk", Vector3(size.x * 0.32, 0, size.y * 0.22), phase, 0.8)
		2:
			_spikes_by_door(burrow, size, open)
			_kit(burrow, "bone_pile", Vector3(-size.x * 0.28, 0, size.y * 0.22), 0.8)
			_put(burrow, "rock_chunk", Vector3(size.x * 0.3, 0, -size.y * 0.2), phase, 1.1)
		3:
			_put(burrow, "ward_pot", Vector3(-1.6, 0, 1.2), 0.2)
			_put(burrow, "ward_pot", Vector3(2.0, 0, -0.8), 1.4)
			_green(burrow, Vector3(0, 1.2, 0))
			if kind != "exit":
				_kit(burrow, "spike_trap", Vector3(1.7, 0, 0.2), 0.3)
			_put(burrow, "rock_chunk", Vector3(-size.x * 0.22, 0, -size.y * 0.18), phase, 0.9)
		4:
			_put(burrow, "ward_pot", Vector3(-size.x * 0.28, 0, 0.4), 0.5)
			_put(burrow, "ward_pot", Vector3(size.x * 0.28, 0, -0.6), 2.0)
			_put(burrow, "ward_pot", Vector3(0.4, 0, size.y * 0.28), 1.0)
			_green(burrow, Vector3(0, 1.6, 0))
		5:
			_put(burrow, "root_cluster", Vector3(size.x * 0.25, 0, -1.2), 0.4, 0.8)
	if kind == "exit":
		_put(burrow, "root_cluster", Vector3(-1.2, 0, 1.4), 0.8, 0.85)


static func _timber(burrow: Node3D, size: Vector2, open: Array) -> void:
	var x := -size.x * 0.5 + 1.5
	while x < size.x * 0.5 - 0.4:
		var blocked_n := open.has(0) and absf(x) < 2.3
		var blocked_s := open.has(2) and absf(x) < 2.3
		if not blocked_n:
			var post := _put(burrow, "timber_post", Vector3(x, 0, -size.y * 0.5 + 0.7))
			if post:
				post.name = "TimberBeam"
		if not blocked_s:
			var post_s := _put(burrow, "timber_post", Vector3(x, 0, size.y * 0.5 - 0.7), PI)
			if post_s:
				post_s.name = "TimberBeam"
		x += 3.6
	var z := -size.y * 0.5 + 2.2
	while z < size.y * 0.5 - 1.0:
		var beam := _put(burrow, "timber_beam", Vector3(0, 3.25, z))
		if beam:
			beam.name = "TimberBeam"
			beam.scale = Vector3((size.x - 1.4) / 4.0, 1, 1)
		z += 3.3


static func _spikes_by_door(burrow: Node3D, size: Vector2, open: Array) -> void:
	for side in open:
		var horiz := int(side) == 0 or int(side) == 2
		var sgn := -1.0 if int(side) == 0 or int(side) == 3 else 1.0
		var along := size.x if horiz else size.y
		if along < 8.0:
			continue
		var at := (
			Vector3(2.35, 0, sgn * (size.y * 0.5 - 1.35)) if horiz else Vector3(sgn * (size.x * 0.5 - 1.35), 0, 2.35)
		)
		var yaw := 0.0 if int(side) == 2 else PI if int(side) == 0 else -PI * 0.5 if int(side) == 1 else PI * 0.5
		_put(burrow, "spike_row", at, yaw, 0.85)
		return


static func _shell(parent: Node3D, size: Vector2, open: Array, hole: Vector3, phase: float, roofed: bool) -> void:
	var key := "s%s|%s|%s|%d|%s" % [size, _open_key(open), hole, int(phase), roofed]
	var built: Array = _mesh_cache.get(key, [])
	if built.is_empty():
		var radius := _radius(size)
		var floor_m := _floor_mesh(size, radius, hole, phase)
		var wall_m := _wall_mesh(size, radius, open, phase)
		built = [floor_m, wall_m]
		if roofed:
			built.append(_roof_mesh(size, radius, phase))
		_mesh_cache[key] = built
	_instance(parent, built[0], "BurrowFloor", "dirt")
	_instance(parent, built[1], "BurrowWall", "rock")
	if roofed and built.size() > 2:
		var roof := _instance(parent, built[2], "CaveRoof", "rock")
		if roof:
			roof.name = "CaveRoof"


static func _tunnels(parent: Node3D, size: Vector2, open: Array, slot: float, phase: float, roofed: bool) -> void:
	for side in open:
		var horiz := int(side) == 0 or int(side) == 2
		var span := size.y if horiz else size.x
		var run := slot * 0.5 - span * 0.5
		if run <= 0.05:
			continue
		var sgn := -1.0 if int(side) == 0 or int(side) == 3 else 1.0
		var mid := span * 0.5 + run * 0.5
		var centre := Vector3(0, 0, sgn * mid) if horiz else Vector3(sgn * mid, 0, 0)
		var key := "t%.2f|%s|%d" % [run, horiz, int(phase)]
		var pair: Array = _mesh_cache.get(key, [])
		if pair.is_empty():
			pair = _tunnel_meshes(run, phase, roofed)
			_mesh_cache[key] = pair
		var tunnel := Node3D.new()
		tunnel.name = "Tunnel"
		tunnel.position = centre
		if not horiz:
			tunnel.rotation.y = PI * 0.5
		parent.add_child(tunnel)
		_instance(tunnel, pair[0], "TunnelFloor", "dirt")
		_instance(tunnel, pair[1], "TunnelWall", "rock")
		if roofed and pair.size() > 2:
			var roof := _instance(tunnel, pair[2], "CaveRoof", "rock")
			if roof:
				roof.name = "CaveRoof"


static func _circle(parent: Node3D, radius: float, gap: float) -> void:
	var floor_st := SurfaceTool.new()
	floor_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 18
	for iz in n:
		for ix in n:
			var a := _cell(ix, iz, n, radius)
			var b := _cell(ix + 1, iz, n, radius)
			var c := _cell(ix + 1, iz + 1, n, radius)
			var d := _cell(ix, iz + 1, n, radius)
			if a.y > 50.0 or b.y > 50.0 or c.y > 50.0 or d.y > 50.0:
				continue
			_quad(floor_st, a, b, c, d)
	_instance(parent, _commit(floor_st), "ThroneFloor", "dirt")
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var samples := 80
	var bands := 7
	for i in samples:
		var t0 := float(i) / samples
		var t1 := float(i + 1) / samples
		var p0 := Vector2(cos(t0 * TAU) * radius, sin(t0 * TAU) * radius)
		var p1 := Vector2(cos(t1 * TAU) * radius, sin(t1 * TAU) * radius)
		var door := _arc_gap(t0, gap) or _arc_gap(t1, gap)
		var o0 := p0.normalized()
		var o1 := p1.normalized()
		for j in bands:
			var y0 := 4.6 * float(j) / bands
			var y1 := 4.6 * float(j + 1) / bands
			if door and y1 < 3.15:
				continue
			var bump0 := 0.18 * _noise(Vector3(p0.x, y0, p0.y), 1.0)
			var bump1 := 0.18 * _noise(Vector3(p1.x, y0, p1.y), 1.0)
			var outer0 := Vector3(p0.x, y0, p0.y) + Vector3(o0.x, 0, o0.y) * (0.45 + bump0)
			var outer1 := Vector3(p1.x, y0, p1.y) + Vector3(o1.x, 0, o1.y) * (0.45 + bump1)
			var inner0 := Vector3(p0.x, y0, p0.y) - Vector3(o0.x, 0, o0.y) * 0.05
			var inner1 := Vector3(p1.x, y0, p1.y) - Vector3(o1.x, 0, o1.y) * 0.05
			var outer0b := Vector3(outer0.x, y1, outer0.z)
			var outer1b := Vector3(outer1.x, y1, outer1.z)
			var inner0b := Vector3(inner0.x, y1, inner0.z)
			var inner1b := Vector3(inner1.x, y1, inner1.z)
			_quad(wall, outer0, outer1, outer1b, outer0b)
			_quad(wall, inner1, inner0, inner0b, inner1b)
			_quad(wall, outer0b, outer1b, inner1b, inner0b)
	var wall_mi := _instance(parent, _commit(wall), "ThroneWall", "rock")
	if wall_mi:
		wall_mi.create_trimesh_collision()
	var roof := SurfaceTool.new()
	roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in n:
		for ix in n:
			var a := _cell(ix, iz, n, radius - 0.4)
			var b := _cell(ix + 1, iz, n, radius - 0.4)
			var c := _cell(ix + 1, iz + 1, n, radius - 0.4)
			var d := _cell(ix, iz + 1, n, radius - 0.4)
			if a.y > 50.0:
				continue
			a.y = 4.35
			b.y = 4.35
			c.y = 4.35
			d.y = 4.35
			_quad(roof, d, c, b, a)
	var roof_mi := _instance(parent, _commit(roof), "CaveRoof", "rock")
	if roof_mi:
		roof_mi.name = "CaveRoof"


static func _cell(ix: int, iz: int, n: int, radius: float) -> Vector3:
	var x := -radius + radius * 2.0 * float(ix) / n
	var z := -radius + radius * 2.0 * float(iz) / n
	if x * x + z * z > radius * radius:
		return Vector3(0, 99, 0)
	return Vector3(x, 0.04 + 0.05 * _noise(Vector3(x, 0, z), 2.0), z)


static func _floor_mesh(size: Vector2, radius: float, hole: Vector3, phase: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := maxi(int(size.x / 0.75), 2)
	var nz := maxi(int(size.y / 0.75), 2)
	for iz in nz:
		for ix in nx:
			var pts: Array[Vector3] = []
			var keep := true
			for corner in [Vector2i(ix, iz), Vector2i(ix + 1, iz), Vector2i(ix + 1, iz + 1), Vector2i(ix, iz + 1)]:
				var p := Vector2(
					-size.x * 0.5 + size.x * float(corner.x) / nx, -size.y * 0.5 + size.y * float(corner.y) / nz
				)
				if not _inside(size, radius, p) or _in_hole(p, hole):
					keep = false
					break
				var y := 0.03 + 0.045 * _noise(Vector3(p.x, 0, p.y), phase)
				pts.append(Vector3(p.x, y, p.y))
			if keep:
				_quad(st, pts[0], pts[1], pts[2], pts[3])
	return _commit(st)


static func _wall_mesh(size: Vector2, radius: float, open: Array, phase: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var perim := 4.0 * (size.x * 0.5 - radius + size.y * 0.5 - radius) + TAU * radius
	var samples := maxi(int(perim / 0.62), 16)
	var bands := 6
	for i in samples:
		var t0 := float(i) / samples
		var t1 := float(i + 1) / samples
		var p0 := _rim(size, radius, t0)
		var p1 := _rim(size, radius, t1)
		var door := _gap(size, radius, p0, open) and _gap(size, radius, p1, open)
		var o0 := _outward(size, radius, p0)
		var o1 := _outward(size, radius, p1)
		for j in bands:
			var y0 := 4.15 * float(j) / bands
			var y1 := 4.15 * float(j + 1) / bands
			if door and y1 < 3.05:
				continue
			var b0 := 0.14 * _noise(Vector3(p0.x, y0, p0.y), phase)
			var b1 := 0.14 * _noise(Vector3(p1.x, y0, p1.y), phase)
			var e0 := Vector3(p0.x, y0, p0.y) + Vector3(o0.x, 0, o0.y) * (0.34 + b0)
			var e1 := Vector3(p1.x, y0, p1.y) + Vector3(o1.x, 0, o1.y) * (0.34 + b1)
			var n0 := Vector3(p0.x, y0, p0.y) - Vector3(o0.x, 0, o0.y) * 0.06
			var n1 := Vector3(p1.x, y0, p1.y) - Vector3(o1.x, 0, o1.y) * 0.06
			_quad(st, e0, e1, Vector3(e1.x, y1, e1.z), Vector3(e0.x, y1, e0.z))
			_quad(st, n1, n0, Vector3(n0.x, y1, n0.z), Vector3(n1.x, y1, n1.z))
			if j == bands - 1:
				_quad(
					st,
					Vector3(e0.x, y1, e0.z),
					Vector3(e1.x, y1, e1.z),
					Vector3(n1.x, y1, n1.z),
					Vector3(n0.x, y1, n0.z)
				)
	return _commit(st)


static func _roof_mesh(size: Vector2, radius: float, phase: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := maxi(int(size.x / 0.9), 2)
	var nz := maxi(int(size.y / 0.9), 2)
	for iz in nz:
		for ix in nx:
			var pts: Array[Vector3] = []
			var keep := true
			for corner in [Vector2i(ix, iz), Vector2i(ix + 1, iz), Vector2i(ix + 1, iz + 1), Vector2i(ix, iz + 1)]:
				var p := Vector2(
					-size.x * 0.5 + size.x * float(corner.x) / nx, -size.y * 0.5 + size.y * float(corner.y) / nz
				)
				if not _inside(size, radius * 0.92, p):
					keep = false
					break
				pts.append(Vector3(p.x, 3.85 + 0.05 * _noise(Vector3(p.x, 2, p.y), phase), p.y))
			if keep:
				_quad(st, pts[3], pts[2], pts[1], pts[0])
	return _commit(st)


static func _tunnel_meshes(length: float, phase: float, roofed: bool) -> Array:
	var floor_st := SurfaceTool.new()
	floor_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := maxi(int(length / 0.7), 1)
	var half := 1.85
	for i in steps:
		var z0 := -length * 0.5 + length * float(i) / steps
		var z1 := -length * 0.5 + length * float(i + 1) / steps
		_quad(
			floor_st,
			Vector3(-half, 0.03, z0),
			Vector3(half, 0.03, z0),
			Vector3(half, 0.03, z1),
			Vector3(-half, 0.03, z1)
		)
	var wall := SurfaceTool.new()
	wall.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bands := 5
	for i in steps:
		var z0 := -length * 0.5 + length * float(i) / steps
		var z1 := -length * 0.5 + length * float(i + 1) / steps
		for j in bands:
			var y0 := 4.05 * float(j) / bands
			var y1 := 4.05 * float(j + 1) / bands
			var b0 := 0.1 * _noise(Vector3(z0, y0, phase), phase)
			var b1 := 0.1 * _noise(Vector3(z1, y0, phase), phase)
			for side_sign in [-1.0, 1.0]:
				var sgn := float(side_sign)
				var x0 := sgn * (half + 0.2 + b0)
				var x1 := sgn * (half + 0.2 + b1)
				var o0 := Vector3(x0, y0, z0)
				var o1 := Vector3(x1, y0, z1)
				var i0 := Vector3(sgn * (half - 0.05), y0, z0)
				var i1 := Vector3(sgn * (half - 0.05), y0, z1)
				if sgn > 0.0:
					_quad(wall, o0, o1, Vector3(o1.x, y1, o1.z), Vector3(o0.x, y1, o0.z))
					_quad(wall, i1, i0, Vector3(i0.x, y1, i0.z), Vector3(i1.x, y1, i1.z))
				else:
					_quad(wall, o1, o0, Vector3(o0.x, y1, o0.z), Vector3(o1.x, y1, o1.z))
					_quad(wall, i0, i1, Vector3(i1.x, y1, i1.z), Vector3(i0.x, y1, i0.z))
	var out := [_commit(floor_st), _commit(wall)]
	if roofed:
		var roof := SurfaceTool.new()
		roof.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in steps:
			var z0 := -length * 0.5 + length * float(i) / steps
			var z1 := -length * 0.5 + length * float(i + 1) / steps
			_quad(
				roof, Vector3(-half, 3.8, z1), Vector3(half, 3.8, z1), Vector3(half, 3.8, z0), Vector3(-half, 3.8, z0)
			)
		out.append(_commit(roof))
	return out


static func _radius(size: Vector2) -> float:
	return clampf(minf(size.x, size.y) * 0.32, 1.8, minf(size.x, size.y) * 0.38)


static func _inside(size: Vector2, radius: float, p: Vector2) -> bool:
	var hx := size.x * 0.5 - radius
	var hz := size.y * 0.5 - radius
	var q := Vector2(absf(p.x) - hx, absf(p.y) - hz)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() <= radius - 0.08


static func _in_hole(p: Vector2, hole: Vector3) -> bool:
	return hole.x < 100.0 and absf(p.x - hole.x) < 2.15 and absf(p.y - hole.z) < 2.15


static func _rim(size: Vector2, radius: float, t: float) -> Vector2:
	var hx := size.x * 0.5 - radius
	var hz := size.y * 0.5 - radius
	var sx := hx * 2.0
	var sz := hz * 2.0
	var arc := PI * radius * 0.5
	var d := fposmod(t, 1.0) * (2.0 * (sx + sz) + TAU * radius)
	if d <= sx:
		return Vector2(-hx + d, size.y * 0.5)
	d -= sx
	if d <= arc:
		var a := PI * 0.5 * (1.0 - d / arc)
		return Vector2(hx, hz) + Vector2(cos(a), sin(a)) * radius
	d -= arc
	if d <= sz:
		return Vector2(size.x * 0.5, hz - d)
	d -= sz
	if d <= arc:
		var a2 := -PI * 0.5 * (d / arc)
		return Vector2(hx, -hz) + Vector2(cos(a2), sin(a2)) * radius
	d -= arc
	if d <= sx:
		return Vector2(hx - d, -size.y * 0.5)
	d -= sx
	if d <= arc:
		var a3 := -PI * 0.5 - PI * 0.5 * (d / arc)
		return Vector2(-hx, -hz) + Vector2(cos(a3), sin(a3)) * radius
	d -= arc
	if d <= sz:
		return Vector2(-size.x * 0.5, -hz + d)
	d -= sz
	var a4 := PI - PI * 0.5 * clampf(d / arc, 0.0, 1.0)
	return Vector2(-hx, hz) + Vector2(cos(a4), sin(a4)) * radius


static func _outward(size: Vector2, radius: float, p: Vector2) -> Vector2:
	var hx := size.x * 0.5 - radius
	var hz := size.y * 0.5 - radius
	var q := Vector2(absf(p.x) - hx, absf(p.y) - hz)
	if q.x > 0.05 and q.y > 0.05:
		return Vector2(signf(p.x) * q.x, signf(p.y) * q.y).normalized()
	if absf(p.x) > absf(p.y):
		return Vector2(signf(p.x), 0)
	return Vector2(0, signf(p.y))


static func _gap(size: Vector2, radius: float, p: Vector2, open: Array) -> bool:
	var hx := size.x * 0.5 - radius
	var hz := size.y * 0.5 - radius
	if open.has(2) and p.y > hz and absf(p.x) < 2.2:
		return true
	if open.has(0) and p.y < -hz and absf(p.x) < 2.2:
		return true
	if open.has(1) and p.x > hx and absf(p.y) < 2.2:
		return true
	if open.has(3) and p.x < -hx and absf(p.y) < 2.2:
		return true
	return false


static func _arc_gap(t: float, gap: float) -> bool:
	return absf(wrapf(t * TAU - PI * 0.5, -PI, PI)) < gap


static func _seal_corners(r: Node3D, size: Vector2, radius: float, hole: Vector3, open: Array) -> void:
	var inset := radius * 0.62
	var half := inset * 1.05 * 0.5
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(sx * (size.x * 0.5 - inset), 1.5, sz * (size.y * 0.5 - inset))
			if _in_hole(Vector2(p.x, p.z), hole):
				continue
			var blocks_door := false
			if (open.has(0) or open.has(2)) and absf(p.x) - half < 2.45:
				blocks_door = true
			if (open.has(1) or open.has(3)) and absf(p.z) - half < 2.45:
				blocks_door = true
			if blocks_door:
				continue
			var body := StaticBody3D.new()
			body.name = "BurrowFill"
			body.position = p
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(inset * 1.05, 3.0, inset * 1.05)
			shape.shape = box
			body.add_child(shape)
			r.add_child(body)


static func _hide_flat_shell(dress: Node3D) -> void:
	for mi in dress.find_children("*", "MeshInstance3D", true, false):
		var id := _flat_id(mi)
		if id.begins_with("wall") or id.begins_with("floor") or id.begins_with("pillar") or id.begins_with("ceiling"):
			(mi as MeshInstance3D).visible = false


static func _flat_id(n: Node) -> String:
	var p := n
	while p:
		var nm := String(p.name)
		if nm == "Dress":
			return ""
		if nm.begins_with("wall") or nm.begins_with("floor") or nm == "pillar" or nm.begins_with("ceiling"):
			return nm
		p = p.get_parent()
	return ""


static func _scatter_ring(parent: Node3D, radius: float) -> void:
	for i in 10:
		var ang := float(i) / 10.0 * TAU + 0.2
		if absf(wrapf(ang - PI * 0.5, -PI, PI)) < 0.35:
			continue
		_put(parent, "rock_chunk", Vector3(cos(ang) * radius, 0, sin(ang) * radius), ang, 0.7 + float(i % 3) * 0.25)


static func _fill_light(parent: Node3D, size: Vector2, floor_no: int) -> void:
	var color := ORANGE
	var energy := 0.34
	if floor_no == 3 or floor_no == 4:
		color = Color(0.7, 0.85, 0.45)
		energy = 0.28
	_omni(parent, Vector3(0, 2.3, 0), color, energy, maxf(size.x, size.y) * 0.72)


static func _green(parent: Node3D, at: Vector3) -> void:
	_omni(parent, at, GREEN, 1.15, 7.5)


static func _omni(parent: Node3D, at: Vector3, color: Color, energy: float, reach: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = reach
	l.shadow_enabled = false
	l.position = at
	parent.add_child(l)


static func _torch(parent: Node3D, at: Vector3, yaw: float) -> void:
	var t := WarrensKit.piece("torch_sconce")
	if t == null:
		return
	parent.add_child(t)
	t.position = at
	t.rotation.y = yaw
	var light := OmniLight3D.new()
	light.light_color = ORANGE
	light.light_energy = 2.1
	light.omni_range = 8.0
	light.position = Vector3(0, 2.45, -0.5)
	t.add_child(light)
	WarrensTheme.paint_tree(t)


static func _kit(parent: Node3D, id: String, at: Vector3, yaw: float) -> void:
	var n := WarrensKit.piece(id)
	if n == null:
		return
	parent.add_child(n)
	n.position = at
	n.rotation.y = yaw
	WarrensTheme.paint_tree(n)


static func _put(parent: Node3D, id: String, at: Vector3, yaw := 0.0, scale := 1.0) -> Node3D:
	if not _props.has(id):
		var path := PROP + id + ".glb"
		_props[id] = load(path) as PackedScene if ResourceLoader.exists(path) else null
	var ps: PackedScene = _props[id]
	if ps == null:
		return null
	var n := ps.instantiate() as Node3D
	n.name = id
	parent.add_child(n)
	n.position = at
	n.rotation.y = yaw
	n.scale = Vector3.ONE * scale
	WarrensTheme.paint_tree(n)
	if id == "ward_pot":
		_omni(n, Vector3(0, 0.95, 0), GREEN, 1.7, 6.5)
	return n


static func _westmost(rooms: Array) -> Node3D:
	var best: Node3D
	var x := INF
	for room in rooms:
		if room.position.x < x and room.has_node("Burrow"):
			x = room.position.x
			best = room
	return best


static func _instance(parent: Node3D, mesh: ArrayMesh, node_name: String, kind: String) -> MeshInstance3D:
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	WarrensTheme.paint(mi, kind)
	parent.add_child(mi)
	return mi


static func _commit(st: SurfaceTool) -> ArrayMesh:
	st.generate_normals()
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_vert(st, a)
	_vert(st, b)
	_vert(st, c)
	_vert(st, a)
	_vert(st, c)
	_vert(st, d)


static func _vert(st: SurfaceTool, p: Vector3) -> void:
	st.set_uv(Vector2(p.x * 0.22 + p.z * 0.05, p.y * 0.22 + p.z * 0.08))
	st.add_vertex(p)


static func _noise(p: Vector3, phase: float) -> float:
	return sin(p.x * 1.7 + phase) * cos(p.z * 2.15 + phase * 0.37) * sin(p.y * 2.4 + p.x * 0.5)


static func _open_key(open: Array) -> String:
	var s := ""
	for side in open:
		s += str(int(side))
	return s


static func randf_from_hash(p: Vector3) -> float:
	return float(absi(hash(p) % 1000)) / 1000.0
