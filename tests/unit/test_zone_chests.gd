extends TestCase
## Step 158 done check: [[chest]] markers become VaultChests with a tier floor; a looted
## chest (flag set) loads open; a vault-tier chest unlocks on its requires_flag.


func _level(tier: String, need := "") -> Node3D:
	var lvl := Node3D.new()
	var marks := Node3D.new()
	marks.name = "Chests"
	lvl.add_child(marks)
	var m := Marker3D.new()
	m.name = "c1"
	m.set_meta(&"tier", tier)
	if need:
		m.set_meta(&"requires_flag", need)
	marks.add_child(m)
	return lvl


func test_tiers_and_saved_open() -> void:
	var holder := Node3D.new()
	runner_tree.root.add_child(holder)
	var f := StoryFlags.new()
	f.set_flag("chest:town_square:c1")
	var lvl := _level("hidden")
	holder.add_child(lvl)
	var cs := ZoneChests.setup(holder, lvl, "town_square", null, f, null)
	check(cs.size() == 1 and cs[0].floor_rarity == "uncommon", "hidden tier floors at uncommon")
	check(cs[0].is_open, "a looted chest loads open")
	holder.queue_free()


func test_vault_unlocks_on_flag() -> void:
	var holder := Node3D.new()
	runner_tree.root.add_child(holder)
	var f := StoryFlags.new()
	var lvl := _level("vault", "lever_3")
	holder.add_child(lvl)
	var cs := ZoneChests.setup(holder, lvl, "midden", null, f, null)
	check(cs[0].locked and cs[0].floor_rarity == "rare", "vault chest starts locked at rare")
	f.set_flag("lever_3")
	check(not cs[0].locked, "lever flag unlocks it")
	holder.queue_free()
