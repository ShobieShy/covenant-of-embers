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
	check(c._lid != null and c._lid.material_override.albedo_color == EmberArt.chest_colors("hidden")[1], "tinted")
	c.free()


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
