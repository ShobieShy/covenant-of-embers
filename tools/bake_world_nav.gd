extends SceneTree
## OW4b: offline whole-world navmesh bake. One NavigationMesh per 128 m streaming cell
## (WorldStreamer.CELL) over the zones' bounding box (+64 m), from the stitched world
## heights (build/world/world_height.f32, 2 m quads) plus the cell's StaticBody3D
## colliders (world/cells/<cx>_<cz>.tscn). Writes world/nav/<cx>_<cz>.res + nav.json.
## Run after tools/build_world.sh: godot --headless --path . -s res://tools/bake_world_nav.gd
## Optional args after --: <cx>_<cz> ... to bake only those cells (timing / debugging).

const SRC := "res://build/world/"
const DST := "res://world/nav/"
const STEP := 2.0
const PAD := 64.0

var hw := PackedFloat32Array()
var origin := Vector2.ZERO
var grid := Vector2i.ZERO
var spacing := 1.0


func _initialize() -> void:
	_run.call_deferred()  # root is not in the tree yet: parsed colliders would be empty


func _run() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SRC + "world.json"))
	origin = Vector2(meta.origin[0], meta.origin[1])
	grid = Vector2i(int(meta.grid[0]), int(meta.grid[1]))
	spacing = float(meta.spacing)
	hw = FileAccess.get_file_as_bytes(SRC + "world_height.f32").to_float32_array()
	var keys := cell_keys(meta.zones)
	var only := OS.get_cmdline_user_args()
	var t0 := Time.get_ticks_msec()
	var info := {}
	for k in keys:
		var id := "%d_%d" % [k.x, k.y]
		if not only.is_empty() and not only.has(id):
			continue
		var t1 := Time.get_ticks_msec()
		var obstacles := [0, 0]
		var nm := bake_cell(k, obstacles)
		ResourceSaver.save(nm, DST + id + ".res", ResourceSaver.FLAG_COMPRESS)
		info[id] = {
			"polys": nm.get_polygon_count(), "obstacle_verts": obstacles[0], "shapes": obstacles[1]
		}
		print("[nav] %s %d polys %d ms" % [id, nm.get_polygon_count(), Time.get_ticks_msec() - t1])
	if only.is_empty():
		var f := FileAccess.open(DST + "nav.json", FileAccess.WRITE)
		f.store_string(JSON.stringify({"cell_size": WorldStreamer.CELL, "cells": info}, "  ", true))
	print("[nav] %d cells in %d s" % [info.size(), (Time.get_ticks_msec() - t0) / 1000])
	quit(0)


static func cell_keys(zones: Dictionary) -> Array[Vector2i]:
	var lo := Vector2(INF, INF)
	var hi := -lo
	for z in zones.values():
		var fp: Array = z.footprint
		lo = lo.min(Vector2(fp[0], fp[1]))
		hi = hi.max(Vector2(fp[2], fp[3]))
	var a := WorldStreamer.cell_of(lo - Vector2(PAD, PAD))
	var b := WorldStreamer.cell_of(hi + Vector2(PAD, PAD))
	var out: Array[Vector2i] = []
	for cz in range(a.y, b.y + 1):
		for cx in range(a.x, b.x + 1):
			out.append(Vector2i(cx, cz))
	return out


func h(x: float, z: float) -> float:
	var i := clampi(roundi((x - origin.x) / spacing), 0, grid.x - 1)
	var j := clampi(roundi((z - origin.y) / spacing), 0, grid.y - 1)
	return hw[j * grid.x + i]


func bake_cell(k: Vector2i, obstacles: Array) -> NavigationMesh:
	var c := WorldStreamer.CELL
	var lo := Vector2(k.x * c, k.y * c)
	var nm := LevelNavigation.make_mesh()
	nm.filter_baking_aabb = AABB(Vector3(lo.x - 1, -200, lo.y - 1), Vector3(c + 2, 600, c + 2))
	nm.border_size = 1.0
	var d := NavigationMeshSourceGeometryData3D.new()
	var path := "res://world/cells/%d_%d.tscn" % [k.x, k.y]
	if ResourceLoader.exists(path):
		var n := (load(path) as PackedScene).instantiate()
		root.add_child(n)
		NavigationServer3D.parse_source_geometry_data(nm, d, n)
		obstacles[0] = d.get_vertices().size() / 3
		# decor-only cells (rocks, trash glbs) have no physics, so nothing to carve
		obstacles[1] = n.find_children("*", "CollisionShape3D", true, false).size()
		if obstacles[1] > 0 and obstacles[0] == 0:
			push_error("bake_world_nav: cell %s parsed no colliders" % path)
		n.free()
	var faces := PackedVector3Array()
	var x0 := lo.x - 4.0
	while x0 < lo.x + c + 4.0:
		var z0 := lo.y - 4.0
		while z0 < lo.y + c + 4.0:
			var x1 := x0 + STEP
			var z1 := z0 + STEP
			var a := Vector3(x0, h(x0, z0), z0)
			var b := Vector3(x1, h(x1, z0), z0)
			var cc := Vector3(x0, h(x0, z1), z1)
			var dd := Vector3(x1, h(x1, z1), z1)
			faces.append_array([a, b, cc, b, dd, cc])
			z0 = z1
		x0 += STEP
	d.add_faces(faces, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(nm, d)
	return nm
