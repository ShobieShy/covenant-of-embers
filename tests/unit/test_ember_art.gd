extends TestCase
## Step 163 (W12) done check: every Ember Art slot has a placeholder until its file lands, the
## chest tiers and 4 waystone variants read apart, and dress() adds the Landfill's Filth decals
## and a skyline ring round a terrain zone.


func test_ember_art_slots() -> void:
	check(EmberArt.SLOTS.size() >= 15, "slots listed")
	for id in EmberArt.SLOTS:
		if String(EmberArt.SLOTS[id]["kind"]) == "texture":
			check(EmberArt.texture(id) != null, "placeholder " + id)
		check(EmberArt.has_art(id) or EmberArt.model(id) == null, "no art -> placeholder " + id)
	var tiers := ["normal", "hidden", "vault"].map(func(t: String) -> Color: return EmberArt.chest_colors(t)[1])
	check(tiers[0] != tiers[1] and tiers[1] != tiers[2] and tiers[0] != tiers[2], "3 chest tiers differ")
	var vs := {}
	for p in ["town_square", "landfill", "old_oak", "breach"]:
		vs[EmberArt.waystone_variant(p)] = true
	check(vs.size() == 4, "4 waystone variants: %s" % [vs.keys()])
	var c := VaultChest.new()
	c.set_meta(&"tier", "hidden")
	runner_tree.root.add_child(c)
	if EmberArt.has_art("chest_hidden"):
		check(c._art and c._lid != null and c._lid.name == &"Lid", "batch 06 chest has its Lid hinge")
	else:
		check(c._lid != null and c._lid.material_override.albedo_color == EmberArt.chest_colors("hidden")[1], "tinted")
	c.open_chest_quiet()
	check(is_equal_approx(c._lid.rotation_degrees.x, -70.0), "lid swings open on local X")
	c.free()


func test_ember_art_batch06() -> void:
	for id in EmberArt.SLOTS:
		check(EmberArt.has_art(id), "batch 06 file for " + id)
	var jm := EmberArt.model("junk_mountain")
	check(jm != null and is_equal_approx(jm.scale.x, 0.6), "junk mountain scaled")
	var lods := {}
	for g in jm.find_children("*", "GeometryInstance3D", true, false):
		var gi := g as GeometryInstance3D
		lods[[gi.visibility_range_begin, gi.visibility_range_end]] = true
	check(lods.size() == 3, "3 LOD bands: %s" % [lods.keys()])
	var hulls := jm.find_children("*", "StaticBody3D", true, false)
	check(hulls.size() == 9, "junk mountain: 9 convex hulls (batch 07), got %d" % hulls.size())
	var sp := EmberArt.model("association_spire")
	var walls := sp.find_children("*", "StaticBody3D", true, false)
	check(walls.size() == 6, "spire: 4 walls split round the back door + lintel")
	# The to_landfill exit (level z -13.5) sits inside the spire, reached through the door
	# gap at the spire's south wall (level z -9): a ray down the door line must hit nothing.
	var space_ok := true
	for w in walls:
		var cs := (w as StaticBody3D).get_child(0) as CollisionShape3D
		var b := cs.shape as BoxShape3D
		var c := (w as StaticBody3D).transform.origin
		var lo := c - b.size / 2
		var hi := c + b.size / 2
		if lo.x < 0.5 and hi.x > -0.5 and lo.y < 2.0 and hi.z > 1.5:  # between door (z 6) and exit (z 1.5)
			space_ok = false
	check(space_ok, "spire back door gap clear (x -0.5..0.5, below 2 m)")
	sp.free()
	var nav := EmberArt.nav_source("midden")
	check(nav.find_children("*", "StaticBody3D", true, false).size() == 9, "junk hulls join the midden nav bake")
	nav.free()
	for id in [] if not EmberArt.COLLIDE else ["oak_lod", "breach_crater_rim", "waystone_town", "chest_vault"]:
		var mm := EmberArt.model(id)
		check(mm.find_children("*", "StaticBody3D", true, false).size() >= 1, id + " collides")
		mm.free()
	jm.free()
	var oak := EmberArt.model("oak_lod")
	var imp := oak.find_child("oak_lod_Impostor", true, false)
	check(imp != null and imp.visible, "oak impostor kept as the far band")
	oak.free()
	var ws := EmberArt.model("waystone_breach")
	var dimmed := ws.find_children("*", "MeshInstance3D", true, false).any(
		func(m: Node) -> bool:
			for i in (m as MeshInstance3D).mesh.get_surface_count():
				var o := (m as MeshInstance3D).get_surface_override_material(i) as StandardMaterial3D
				if o and o.emission_enabled:
					return true
			return false
	)
	check(dimmed, "waystone glow dimmed")
	ws.free()
	for r in WorldMap.REGIONS:
		check(EmberArt.texture("map_" + String(r)) is CompressedTexture2D, "painting " + String(r))
	var g := ElementGem.new()
	check(ItemIcons.path_for(g).ends_with("icons/gear/gem.png"), "gem icon from batch 06")
	check(ItemIcons.junk_icon(g) != null, "junk icon")


func test_ember_art_dress() -> void:
	var lvl := (load("res://scenes/levels/midden.tscn") as PackedScene).instantiate() as Node3D
	var h := EmberArt.dress(lvl, "midden")
	var decals := h.get_children().filter(func(n: Node) -> bool: return n is Decal)
	check(decals.size() == 4, "4 Filth decals: %d" % decals.size())
	var sky := h.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with("Skyline"))
	check(sky.size() == EmberArt.SKYLINE_N, "skyline ring: %d" % sky.size())
	var n := h.get_child_count()
	check(EmberArt.dress(lvl, "midden").get_child_count() == n, "redress replaces")
	check(lvl.get_children().filter(func(x: Node) -> bool: return x.name == &"EmberArt").size() == 1, "one holder")
	lvl.free()
