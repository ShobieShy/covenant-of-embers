extends TestCase
## U7: greybox until Ember Art files exist. No new asset files in this milestone.


func test_missing_files_stay_greybox() -> void:
	for slot in SlagworksKit.SLOTS:
		check(not ResourceLoader.exists(String(SlagworksKit.SLOTS[slot])), "%s has no file yet" % slot)
		if String(slot) != "slag_seal_decal":
			check(SlagworksKit.mesh_for(slot) == null, "%s leaves the box" % slot)
	check(not SlagworksKit.play_cue("railhead"), "Railhead music is silent")
	check(not SlagworksKit.play_cue("vein"), "Vein uses the Railhead bed, still missing")
	check(not SlagworksKit.play_cue("forgemaw"), "Forgemaw music is silent")
	var floor := SlagworksFloor.make(9, LabyrinthState.fresh(3))
	runner_tree.root.add_child(floor)
	check(
		floor.find_child("Slab", true, false) != null or floor.find_child("SlabN", true, false) != null,
		"the floor still has collision"
	)
	floor.free()
