class_name ShaderWarmup
extends RefCounted
## OW11e: compiles the open world's shaders and pipelines behind the first-load screen. A cold
## cache stalled 380 to 890 ms on the first frame and when the Landfill cells first came into view
## (docs/perf_ow11.md). One tiny copy of every geometry node in the world cells is drawn just in front of
## the camera for a few frames, so the drivers compile every material and vertex-format variant
## (with shadows) while the loading screen is still up. On headless (dummy renderer) this does nothing.

const FRAMES := 4
const SCALE := 0.002


## Awaitable. `cam` defaults to the viewport's camera; without one there is nothing to warm.
static func run(tree: SceneTree, cam: Camera3D = null) -> int:
	if DisplayServer.get_name() == "headless" or tree == null:
		return 0
	if cam == null:
		cam = tree.root.get_camera_3d()
	if cam == null:
		return 0
	var holder := Node3D.new()
	holder.name = "ShaderWarmup"
	var n := 0
	var seen := {}
	for f in DirAccess.get_files_at(WorldStreamer.DIR):
		if not f.ends_with(".tscn"):
			continue
		var ps := ResourceLoader.load(WorldStreamer.DIR + f) as PackedScene  # sync: cells are small
		if ps == null:
			continue
		var cell := ps.instantiate()
		n += _collect(cell, holder, seen)
		cell.free()
	tree.root.add_child(holder)
	for _f in FRAMES:
		if not is_instance_valid(cam) or not cam.is_inside_tree():
			break
		var fwd := -cam.global_transform.basis.z
		holder.global_transform = Transform3D(
			Basis().scaled(Vector3.ONE * SCALE), cam.global_position + fwd * (cam.near + 0.3)
		)
		await RenderingServer.frame_post_draw
	holder.queue_free()
	return n


## Adds one script-free copy per distinct (class, mesh, materials) found under `node`.
static func _collect(node: Node, holder: Node3D, seen: Dictionary) -> int:
	var n := 0
	if node is GeometryInstance3D:
		var key := _key(node as GeometryInstance3D)
		if not seen.has(key):
			seen[key] = true
			var g := node.duplicate(0) as GeometryInstance3D  # no scripts, groups or signals
			for c in g.get_children():
				g.remove_child(c)
				c.free()
			g.transform = Transform3D(g.transform.basis, Vector3.ZERO)
			g.visible = true
			g.visibility_range_begin = 0.0
			g.visibility_range_end = 0.0
			holder.add_child(g)
			n += 1
	for c in node.get_children():
		n += _collect(c, holder, seen)
	return n


static func _key(g: GeometryInstance3D) -> String:
	var parts: Array = [g.get_class(), g.material_override, g.cast_shadow]
	if g is MeshInstance3D:
		var m := g as MeshInstance3D
		parts.append(m.mesh)
		for i in m.get_surface_override_material_count():
			parts.append(m.get_surface_override_material(i))
	elif g is MultiMeshInstance3D:
		var mm := (g as MultiMeshInstance3D).multimesh
		parts.append(mm.mesh if mm else null)
	elif g.has_method(&"get_draw_pass_mesh"):
		parts.append(g.call(&"get_draw_pass_mesh", 0))
	return str(parts)
