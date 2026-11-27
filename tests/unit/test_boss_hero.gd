extends TestCase
## 0.14.0 boss hero meshes: the seven bosses keep their hitboxes, and each rig
## loads with an idle clip. The King's crown and the Matriarch's phase nodes stay.

const HITS := {
	"the_filth": Vector3(2.2, 2.0, 2.2),
	"breach_warden": Vector3(1.8, 2.8, 1.8),
	"goblin_king": Vector3(1.6, 2.4, 1.6),
	"blightmaw_matriarch": Vector3(2.2, 3.4, 2.2),
	"forgemaw": Vector3(2.4, 3.2, 2.4),
	"drowned_choir": Vector3(2.2, 2.8, 2.2),
	"storm_warden": Vector3(2.0, 2.6, 2.0),
}


func test_hitboxes_and_rigs() -> void:
	var table := EnemyTable.load_default()
	for id in HITS:
		var d := table.find(id)
		check(d != null and d.size.is_equal_approx(HITS[id]), "hitbox %s" % id)
		check(ResourceLoader.exists(EnemyModels.path_for(id)), "mesh %s" % id)
		var m := EnemyModels.make(id, d.size.y)
		check(m != null, "loads %s" % id)
		if m == null:
			continue
		check(m.find_child("Skeleton3D", true, false) != null, "rig %s" % id)
		check(m.anim != null and m.anim.has_animation(&"Idle"), "idle %s" % id)
		check(m.anim.has_animation(&"Attack") and m.anim.has_animation(&"Death"), "clips %s" % id)
		var feet := 0
		var sk := m.find_child("Skeleton3D", true, false) as Skeleton3D
		if sk:
			for i in sk.get_bone_count():
				if "foot" in String(sk.get_bone_name(i)).to_lower():
					feet += 1
		check(feet >= 2, "feet %s" % id)
		var depth := _depth_over_height(m)
		check(depth > 0.28, "%s has volume, depth/height %.2f" % [id, depth])
		m.free()


func _depth_over_height(root: Node) -> float:
	var best_h := 0.0
	var depth := 0.0
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var a := mi.get_aabb().size
		var s := mi.global_transform.basis.get_scale().abs()
		var h := a.y * s.y
		if h > best_h:
			best_h = h
			depth = a.z * s.z
	if best_h <= 0.001:
		return 0.0
	return depth / best_h


func test_named_phase_parts() -> void:
	var table := EnemyTable.load_default()
	var king := Enemy.create(table.find("goblin_king"))
	runner_tree.root.add_child(king)
	await runner_tree.process_frame
	var crown := king.model.find_child("Crown", true, false) as Node3D
	check(crown != null and crown.visible, "crown on")
	check(EnemyModels.throw_release(king.model) > 0.1, "throw clip")
	var warden := Enemy.create(table.find("breach_warden"))
	runner_tree.root.add_child(warden)
	check(warden.model.find_child("WardenEye", true, false) != null, "seam")
	var filth := Enemy.create(table.find("the_filth")) as Filth
	runner_tree.root.add_child(filth)
	await runner_tree.process_frame
	var core := filth.model.find_child("Phase3_Core", true, false) as Node3D
	check(core != null and not core.visible, "filth core hidden in phase 1")
	filth.phase = 3
	await runner_tree.process_frame
	check(core.visible, "filth core in phase 3")
	var choir := Enemy.create(table.find("drowned_choir"))
	runner_tree.root.add_child(choir)
	check(choir.model.find_child("Phase2_Water", true, false) != null, "one choir body, water is a phase")
	king.free()
	warden.free()
	filth.free()
	choir.free()
