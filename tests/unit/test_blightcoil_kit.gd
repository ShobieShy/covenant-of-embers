extends TestCase
## U7: greybox with no new asset files. A listed file would replace its box.


func test_greybox_without_files() -> void:
	for slot in BlightcoilKit.SLOTS:
		check(BlightcoilKit.mesh_for(slot) == null, "%s has no file yet" % slot)
	for cue in BlightcoilKit.CUES:
		check(not BlightcoilKit.play_cue(cue), "%s stays silent" % cue)
	var cav := BlightcoilCavern.make(6, LabyrinthState.fresh(1))
	runner_tree.root.add_child(cav)
	check(cav.find_children("*", "CollisionShape3D", true, false).size() > 3, "greybox still collides")
	check(WarrensKit.available() == ResourceLoader.exists("res://assets/original/ember_art/warrens/wall_4m.glb"), "the Warrens kit is unchanged")
	cav.free()
