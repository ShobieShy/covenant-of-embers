extends TestCase
## Steps 119-121 + 120 (A2): every speaker / archetype / enemy model loads and fits to a sane
## scale (guards the skinned-armature fit: batch_02 humanoids once came out 400x too big).


func _scale_ok(path: String, cm: CharacterModel) -> void:
	check(cm != null, "loads " + path)
	if cm:
		var s := (cm.get_child(0) as Node3D).scale.y
		check(s > 0.01 and s < 10.0, "%s fit scale %f" % [path, s])
		cm.free()


func test_speakers_and_archetypes() -> void:
	for sp: String in CharacterModel.SPEAKERS:
		_scale_ok(sp, CharacterModel.make_for_speaker(sp))
	for id: String in CharacterModel.ARCHETYPES:
		_scale_ok(id, CharacterModel.make(CharacterModel.for_archetype(id)))


## Bob's farmer mesh is retired. The placeholder is the ash wizard (robe, hat, staff)
## with a worn tint, unless Ember Art's bob_wizard.glb is present.
func test_bob_is_a_wizard() -> void:
	var path := CharacterModel.for_speaker("Bob")
	check(not path.ends_with("Farmer.glb"), "not the farmer (%s)" % path)
	var dropped := ResourceLoader.exists(CharacterModel.BOB_ART)
	if dropped:
		check(path == CharacterModel.BOB_ART, "dedicated Bob art")
	else:
		check(path.ends_with("Elder_ash.glb"), "ash wizard placeholder (%s)" % path)
	var cm := CharacterModel.make_for_speaker("Bob")
	check(cm != null and cm.anim != null, "Bob's rig plays")
	var staff := false
	var worn := dropped
	for mi in cm.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		var n := String(mi.name) + " " + (mesh.resource_name if mesh else "")
		if n.to_lower().contains("staff"):
			staff = true
		var ov := (mi as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
		if ov and ov.albedo_color.is_equal_approx(CharacterModel.BOB_WEAR):
			worn = true
	check(staff, "staff in the silhouette")
	check(worn, "placeholder wears the haggard tint, or the dedicated model is in")
	cm.free()


func test_scavenger_holds_a_fallen_pose() -> void:
	var cm := CharacterModel.make_for_speaker("Wounded scavenger")
	runner_tree.root.add_child(cm)
	await runner_tree.process_frame
	check(
		cm.holding() == "" and String(cm.anim.current_animation).contains("Idle"),
		"starts in an idle, not the bind pose"
	)
	var idle_h := _chest_height(cm)
	check(cm.hold("Death"), "Death clip")
	await runner_tree.process_frame
	var fallen := _chest_height(cm)
	check(fallen < idle_h - 0.4, "fallen chest is near the ground (%.2f vs idle %.2f)" % [fallen, idle_h])
	cm.release()
	for _i in 20:
		await runner_tree.process_frame
	check(cm.holding() == "", "stands")
	check(_chest_height(cm) > fallen + 0.4, "idle lifts the chest again")
	cm.free()


func _bone_world(cm: CharacterModel, bone: String) -> Vector3:
	var sk := cm.find_child("Skeleton3D", true, false) as Skeleton3D
	return (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone))).origin


func _chest_height(cm: CharacterModel) -> float:
	return _bone_world(cm, "Chest").y - cm.global_position.y


func test_intro_cast_has_models() -> void:
	for sp in ["Elder", "Clerk", "Wounded scavenger", "Bored Guard", "Potion Merchant", "Runesmith", "Tailor"]:
		check(CharacterModel.for_speaker(sp) != "", "model for " + sp)


func test_enemy_models() -> void:
	for id: String in EnemyModels.MODELS:
		_scale_ok(id, EnemyModels.make(id, 1.0))
