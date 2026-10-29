class_name ShaderWarmup
extends RefCounted
## OW11e: compiles the open world's shaders and pipelines behind the first-load screen. A cold
## cache stalled 380 to 890 ms on the first frame and when the Landfill cells first came into view
## (docs/perf_ow11.md). One tiny copy of every geometry node in the world cells is drawn just in front of
## the camera for a few frames, so the drivers compile every material and vertex-format variant
## (with shadows) while the loading screen is still up. On headless (dummy renderer) this does nothing.

const FRAMES := 4
const SCALE := 0.002

## First Labyrinth floor only. Later floors reuse the pipelines compiled here.
static var _lab_warmed := false


## Glbs whose materials and skinning show up on the first Labyrinth floor (warrens kit
## plus the Act I goblins). Open-world cells do not include these, so the first floor
## used to compile them in view (about 60 ms).
static func labyrinth_mesh_paths() -> PackedStringArray:
	var out: PackedStringArray = []
	for f in DirAccess.get_files_at(WarrensKit.DIR):
		if f.ends_with(".glb"):
			out.append(WarrensKit.DIR + f)
	for id in EnemyModels.MODELS:
		var p := String(EnemyModels.MODELS[id])
		if p.begins_with("res://") and p.ends_with(".glb") and not out.has(p):
			out.append(p)
	out.sort()
	return out


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
	await _present(tree, cam, holder)
	return n


## Awaitable. Draws the Labyrinth kit once, while the loading screen is up, before the
## floor is parented. Headless (dummy renderer) returns 0. Whole scenes stay intact so
## skinned goblins compile the skinning variant, not a static stand-in.
static func warm_labyrinth(tree: SceneTree, cam: Camera3D = null) -> int:
	if _lab_warmed or DisplayServer.get_name() == "headless" or tree == null:
		return 0
	if cam == null:
		cam = tree.root.get_camera_3d()
	if cam == null:
		return 0
	var holder := Node3D.new()
	holder.name = "ShaderWarmupLab"
	var n := 0
	for path in labyrinth_mesh_paths():
		var ps := ResourceLoader.load(path) as PackedScene
		if ps == null:
			continue
		holder.add_child(ps.instantiate())
		n += 1
	n += _lab_standins(holder)
	await _present(tree, cam, holder)
	_lab_warmed = true
	return n


## Plain albedo, emissive (stairs and the rest shrine), and one torch omni.
static func _lab_standins(holder: Node3D) -> int:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	for emit in [false, true]:
		var mi := MeshInstance3D.new()
		mi.mesh = box
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.9, 0.6, 0.2)
		if emit:
			m.emission_enabled = true
			m.emission = m.albedo_color * 0.5
		mi.material_override = m
		holder.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = WarrensKit.LIGHT
	light.light_energy = 1.6
	light.omni_range = 9.0
	holder.add_child(light)
	return 2


static func _present(tree: SceneTree, cam: Camera3D, holder: Node3D) -> void:
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
