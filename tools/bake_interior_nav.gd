extends SceneTree
## OW5b: bakes each instanced interior's navmesh (the scene as Interiors.prepare leaves
## it, at the origin, so the mesh is interior-local) into Interiors.nav_cache(id).
## godot --headless --path . -s res://tools/bake_interior_nav.gd


func _initialize() -> void:
	_run.call_deferred()  # bake once the root is in the tree


func _run() -> void:
	for id in Interiors.LINKS:
		var n := (
			(load(GameFlow.level_scene(Interiors.LINKS[id]["scene"])) as PackedScene).instantiate()
			as Node3D
		)
		Interiors.prepare(n, id, false)
		var nav := n.get_node_or_null("Navigation") as LevelNavigation
		if nav == null:
			continue
		nav.bake_on_ready = false
		root.add_child(n)
		var polys := nav.bake_now()
		ResourceSaver.save(
			nav.navigation_mesh, Interiors.nav_cache(id), ResourceSaver.FLAG_COMPRESS
		)
		print("[interior_nav] %s %d polys" % [id, polys])
		n.free()
	quit(0)
