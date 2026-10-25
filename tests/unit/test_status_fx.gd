extends TestCase
## Step 129 (FX F3): status children follow the enemy's statuses, Air chains draw an arc,
## deaths leave a dissolving shell that frees itself.


func test_status_children_toggle() -> void:
	var n := Node3D.new()
	Engine.get_main_loop().root.add_child(n)
	StatusFX.sync(n, Vector3.ONE, true, true, true)
	check(n.get_node_or_null(^"Burn") != null, "burn flames")
	check(n.get_node_or_null(^"Frost") != null, "frost flakes")
	check(n.get_node_or_null(^"Stars") != null, "stagger stars")
	StatusFX.sync(n, Vector3.ONE, false, false, false)
	for c in ["Burn", "Frost", "Stars"]:
		var k := n.get_node_or_null(NodePath(c))
		check(k == null or k.is_queued_for_deletion(), "%s off" % c)
	n.free()


func test_enemy_burn_shows_flames() -> void:
	var d := EnemyTable.load_default().find("gnawer")
	var e := Enemy.create(d)
	Engine.get_main_loop().root.add_child(e)
	e.burn_left = 2.0
	e.tick(0.01)
	check(e.get_node_or_null(^"Burn") != null, "burning enemy has flames")
	e.free()


func test_chain_arc_and_death() -> void:
	var root := Node3D.new()
	Engine.get_main_loop().root.add_child(root)
	check(StatusFX.chain_arc(root, Vector3.ZERO, Vector3(3, 0, 0)) != null, "arc drawn")
	var d := StatusFX.death(root, Vector3.ZERO, Vector3(0.7, 1.4, 0.7), Color.GRAY, Color.ORANGE)
	check(d != null and (d.get_child(0) as MeshInstance3D).material_override.shader == StatusFX.DISSOLVE, "dissolve")
	check(StatusFX.death(null, Vector3.ZERO, Vector3.ONE, Color.GRAY, Color.ORANGE) == null, "no parent, no fx")
	root.free()
