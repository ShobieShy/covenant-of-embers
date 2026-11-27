class_name SunkenMeshes
extends RefCounted
## Array meshes for the flooded plan: paved ribbons, water, the spire, coral,
## bells, the sarcophagus. None of these are PrimitiveMesh nodes.


static func ribbon(points: PackedVector3Array, width: float, y: float, drop: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := width * 0.5
	var along := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var dir := Vector3(b.x - a.x, 0, b.z - a.z)
		var len := dir.length()
		if len < 0.05:
			continue
		dir /= len
		var side := Vector3(-dir.z, 0, dir.x) * half
		var a0 := Vector3(a.x, y, a.z)
		var b0 := Vector3(b.x, y, b.z)
		var a1 := a0 - Vector3(0, drop, 0)
		var b1 := b0 - Vector3(0, drop, 0)
		_quad(st, a0 - side, a0 + side, b0 + side, b0 - side, along, along + len, 0.0, 1.0)
		_quad(st, a1 - side, a0 - side, b0 - side, b1 - side, along, along + len, 0.0, 0.2)
		_quad(st, a0 + side, a1 + side, b1 + side, b0 + side, along, along + len, 0.0, 0.2)
		along += len
	st.generate_normals()
	return st.commit()


static func slab(size: Vector2, y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	_quad(
		st,
		Vector3(-hx, y, -hz),
		Vector3(hx, y, -hz),
		Vector3(hx, y, hz),
		Vector3(-hx, y, hz),
		0.0,
		size.x / 4.0,
		0.0,
		size.y / 4.0,
	)
	st.generate_normals()
	return st.commit()


static func disc(radius_x: float, radius_z: float, y: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(0, y, 0)
	for i in segs:
		var t0 := TAU * float(i) / float(segs)
		var t1 := TAU * float(i + 1) / float(segs)
		var p0 := Vector3(cos(t0) * radius_x, y, sin(t0) * radius_z)
		var p1 := Vector3(cos(t1) * radius_x, y, sin(t1) * radius_z)
		_tri(st, centre, p0, p1)
	st.generate_normals()
	return st.commit()


static func spire() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 8
	_ring_wall(st, sides, 5.6, 5.2, 0.0, 2.2)
	_ring_wall(st, sides, 3.4, 3.1, 2.2, 11.0)
	_roof(st, sides, 3.8, 11.0, 22.0)
	for i in 4:
		var ang := TAU * float(i) / 4.0 + 0.2
		_buttress(st, ang)
	st.generate_normals()
	return st.commit()


static func doorway_glow() -> ArrayMesh:
	return _panel(2.2, 4.4)


static func coral(seed: int, tint_slot: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := _Rng.new(seed + tint_slot * 17)
	var tip := Vector3(0, 0.2 + rng.f() * 0.4, 0)
	var top := Vector3(rng.signed() * 0.3, 1.6 + rng.f() * 0.8, rng.signed() * 0.3)
	_tube(st, tip, top, 0.22, 0.08, 5)
	var arms := 3 + (seed % 3)
	for i in arms:
		var dir := Vector3(rng.signed(), 0.45 + rng.f() * 0.6, rng.signed()).normalized()
		var end := top + dir * (0.7 + rng.f() * 0.8)
		_tube(st, top, end, 0.09, 0.03, 4)
		if rng.f() > 0.4:
			var fork := end + Vector3(rng.signed(), 0.4, rng.signed()).normalized() * 0.55
			_tube(st, end, fork, 0.05, 0.015, 4)
	st.generate_normals()
	return st.commit()


static func bell() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile := PackedVector2Array(
		[
			Vector2(0.05, 0.0),
			Vector2(0.12, 0.15),
			Vector2(0.28, 0.55),
			Vector2(0.42, 0.9),
			Vector2(0.36, 1.05),
			Vector2(0.08, 1.15),
		]
	)
	var segs := 12
	for i in profile.size() - 1:
		for s in segs:
			var a0 := TAU * float(s) / float(segs)
			var a1 := TAU * float(s + 1) / float(segs)
			var r0: Vector2 = profile[i]
			var r1: Vector2 = profile[i + 1]
			_tri(st, _lathe(r0, a0), _lathe(r1, a0), _lathe(r1, a1))
			_tri(st, _lathe(r0, a0), _lathe(r1, a1), _lathe(r0, a1))
	st.generate_normals()
	return st.commit()


static func sarcophagus() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box_chamfer(st, Vector3(0, 0.45, 0), Vector3(1.5, 0.9, 3.2), 0.12)
	_box_chamfer(st, Vector3(0, 1.05, -0.05), Vector3(1.25, 0.28, 2.9), 0.08)
	st.generate_normals()
	var mesh := st.commit()
	return mesh


static func crack() -> ArrayMesh:
	return _panel(0.18, 2.4)


static func tablet() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_box_chamfer(st, Vector3(0, 0.9, 0), Vector3(1.1, 1.6, 0.16), 0.04)
	st.generate_normals()
	return st.commit()


static func waterfall(height: float, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-width * 0.5, height, 0)
	var b := Vector3(width * 0.5, height, 0)
	var c := Vector3(width * 0.5, 0.2, 0.4)
	var d := Vector3(-width * 0.5, 0.2, 0.4)
	_quad(st, a, b, c, d, 0.0, height, 0.0, 1.0)
	st.generate_normals()
	return st.commit()


static func _panel(w: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-w * 0.5, 0, 0)
	var b := Vector3(w * 0.5, 0, 0)
	var c := Vector3(w * 0.5, h, 0)
	var d := Vector3(-w * 0.5, h, 0)
	_quad(st, a, b, c, d, 0.0, 1.0, 0.0, 1.0)
	st.generate_normals()
	return st.commit()


static func _lathe(p: Vector2, ang: float) -> Vector3:
	return Vector3(cos(ang) * p.x, p.y, sin(ang) * p.x)


static func _ring_wall(st: SurfaceTool, sides: int, r0: float, r1: float, y0: float, y1: float) -> void:
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var p10 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var p01 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		_quad(st, p00, p10, p11, p01, 0.0, 1.0, 0.0, 1.0)
	# Cap the base.
	var c0 := Vector3(0, y0, 0)
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		_tri(st, c0, Vector3(cos(a1) * r0, y0, sin(a1) * r0), Vector3(cos(a0) * r0, y0, sin(a0) * r0))


static func _roof(st: SurfaceTool, sides: int, radius: float, y0: float, y1: float) -> void:
	var tip := Vector3(0, y1, 0)
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var p0 := Vector3(cos(a0) * radius, y0, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, y0, sin(a1) * radius)
		_tri(st, p0, p1, tip)


static func _buttress(st: SurfaceTool, ang: float) -> void:
	var out := Vector3(cos(ang), 0, sin(ang))
	var side := Vector3(-out.z, 0, out.x) * 0.35
	var base := out * 5.4
	var top := out * 3.3 + Vector3(0, 8.5, 0)
	var foot := out * 7.2
	_quad(st, base - side, base + side, top + side, top - side, 0, 1, 0, 1)
	_quad(st, foot - side, foot + side, base + side, base - side, 0, 1, 0, 1)


static func _box_chamfer(st: SurfaceTool, centre: Vector3, size: Vector3, chamfer: float) -> void:
	var h := size * 0.5
	var c := minf(chamfer, minf(h.x, minf(h.y, h.z)) * 0.45)
	var xs: Array[float] = [-h.x + c, h.x - c]
	var ys: Array[float] = [-h.y + c, h.y - c]
	# Six faces, inset so the edges read as cut stone.
	_face(st, centre, Vector3(0, h.y, 0), Vector3(h.x - c, 0, 0), Vector3(0, 0, h.z - c))
	_face(st, centre, Vector3(0, -h.y, 0), Vector3(0, 0, h.z - c), Vector3(h.x - c, 0, 0))
	_face(st, centre, Vector3(h.x, 0, 0), Vector3(0, 0, h.z - c), Vector3(0, h.y - c, 0))
	_face(st, centre, Vector3(-h.x, 0, 0), Vector3(0, h.y - c, 0), Vector3(0, 0, h.z - c))
	_face(st, centre, Vector3(0, 0, h.z), Vector3(h.x - c, 0, 0), Vector3(0, h.y - c, 0))
	_face(st, centre, Vector3(0, 0, -h.z), Vector3(0, h.y - c, 0), Vector3(h.x - c, 0, 0))
	# Edge bevels. xs/ys/zs keep the chamfer from collapsing on a thin slab.
	if xs[1] > xs[0] and ys[1] > ys[0]:
		_bevel_ring(st, centre, h, c)


static func _face(st: SurfaceTool, centre: Vector3, n: Vector3, u: Vector3, v: Vector3) -> void:
	var p := centre + n
	_quad(st, p - u - v, p + u - v, p + u + v, p - u + v, 0, 1, 0, 1)


static func _bevel_ring(st: SurfaceTool, centre: Vector3, h: Vector3, c: float) -> void:
	# Vertical edges only. Enough to stop the coffin reading as a crate.
	var corners: Array[Vector3] = [
		Vector3(h.x, 0, h.z),
		Vector3(-h.x, 0, h.z),
		Vector3(-h.x, 0, -h.z),
		Vector3(h.x, 0, -h.z),
	]
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var inward := Vector3(signf(a.x) * c, 0, signf(a.z) * c)
		var inward_b := Vector3(signf(b.x) * c, 0, signf(b.z) * c)
		var y0 := -h.y + c
		var y1 := h.y - c
		var p0 := centre + Vector3(a.x, y0, a.z) - inward
		var p1 := centre + Vector3(b.x, y0, b.z) - inward_b
		var p2 := centre + Vector3(b.x, y1, b.z) - inward_b
		var p3 := centre + Vector3(a.x, y1, a.z) - inward
		_quad(st, p0, p1, p2, p3, 0, 1, 0, 1)


static func _tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, sides: int) -> void:
	var dir := b - a
	if dir.length() < 0.02:
		return
	var up := Vector3.UP
	if absf(dir.normalized().dot(up)) > 0.9:
		up = Vector3.RIGHT
	var side := dir.cross(up).normalized()
	var bin := dir.cross(side).normalized()
	for i in sides:
		var t0 := TAU * float(i) / float(sides)
		var t1 := TAU * float(i + 1) / float(sides)
		var o0 := side * cos(t0) + bin * sin(t0)
		var o1 := side * cos(t1) + bin * sin(t1)
		_quad(st, a + o0 * ra, a + o1 * ra, b + o1 * rb, b + o0 * rb, 0, 1, 0, 1)


static func _quad(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, u0: float, u1: float, v0: float, v1: float
) -> void:
	st.set_uv(Vector2(u0, v0))
	st.add_vertex(a)
	st.set_uv(Vector2(u1, v0))
	st.add_vertex(b)
	st.set_uv(Vector2(u1, v1))
	st.add_vertex(c)
	st.set_uv(Vector2(u0, v0))
	st.add_vertex(a)
	st.set_uv(Vector2(u1, v1))
	st.add_vertex(c)
	st.set_uv(Vector2(u0, v1))
	st.add_vertex(d)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_uv(Vector2(0, 0))
	st.add_vertex(a)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(b)
	st.set_uv(Vector2(0.5, 1))
	st.add_vertex(c)


class _Rng:
	var s: int

	func _init(seed_value: int) -> void:
		s = seed_value if seed_value != 0 else 1

	func f() -> float:
		s = (s * 1103515245 + 12345) & 0x7FFFFFFF
		return float(s % 10000) / 10000.0

	func signed() -> float:
		return f() * 2.0 - 1.0
