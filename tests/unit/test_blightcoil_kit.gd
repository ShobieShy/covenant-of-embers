extends TestCase
## U7: batch_12 meshes replace the greybox where a file exists. Cues stay silent.
## Walk collision stays on the cavern boxes.


func test_kit_files_and_silent_cues() -> void:
	var glbs := 0
	for slot in BlightcoilKit.SLOTS:
		var path := String(BlightcoilKit.SLOTS[slot])
		check(ResourceLoader.exists(path), "%s is in the tree" % slot)
		if path.ends_with(".glb"):
			var mesh := BlightcoilKit.mesh_for(slot)
			check(mesh != null, "%s instantiates" % slot)
			if mesh:
				glbs += 1
				mesh.free()
		else:
			check(BlightcoilKit.texture(slot) != null, "%s decal" % slot)
	check(glbs == 13, "13 glb slots (%d)" % glbs)
	for cue in BlightcoilKit.CUES:
		check(not BlightcoilKit.play_cue(cue), "%s stays silent" % cue)
	var cav := BlightcoilCavern.make(6, LabyrinthState.fresh(1))
	runner_tree.root.add_child(cav)
	check(cav.find_children("*", "CollisionShape3D", true, false).size() > 3, "greybox still collides")
	check(cav.get_node_or_null("TrunkArt") != null, "trunk art")
	check(cav.get_node_or_null("RampArt_to_canopy") != null, "ramp art")
	check(
		WarrensKit.available() == ResourceLoader.exists("res://assets/original/ember_art/warrens/wall_4m.glb"),
		"the Warrens kit is unchanged"
	)
	cav.free()
