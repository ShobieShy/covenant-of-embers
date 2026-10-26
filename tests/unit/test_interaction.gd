extends TestCase
## t60u: interaction goes by where the camera looks, not where the feet stand.

const PLAYER_SCENE := "res://scenes/player/player.tscn"


func _player(at: Vector3) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	runner_tree.root.add_child(p)
	p.spawn(at, 0.0)
	return p


func _add(n: Node3D, at: Vector3) -> Node3D:
	runner_tree.root.add_child(n)
	n.global_position = at
	return n


func test_looked_at_wins_over_nearest() -> void:
	var base := Vector3(40, 400, -700)
	var p := _player(base)
	var near_npc: Npc = _add(Npc.new("Alder"), base + Vector3(1.2, 0, 0))  # right beside the feet
	var far_npc: Npc = _add(Npc.new("Elder Wren"), base + Vector3(0, 0, -3.0))  # 3 m ahead
	Interaction.face(p, far_npc)
	check(Interaction.target(p) == far_npc, "looked-at NPC is the target, not the nearest")
	check(far_npc.in_reach(p) and not near_npc.in_reach(p), "only the looked-at one is in reach")
	check(Interaction.prompt(p) == "[F] Talk to Elder Wren", "prompt: %s" % Interaction.prompt(p))
	Interaction.face(p, near_npc)
	check(Interaction.target(p) == near_npc, "turning switches target")
	p.set_look(PI, 0.0)  # look away from both
	check(Interaction.target(p) == null and Interaction.prompt(p) == "", "looking away: no target, no prompt")
	for n in [p, near_npc, far_npc]:
		n.free()


func test_range_and_ui_open() -> void:
	var base := Vector3(80, 400, -700)
	var p := _player(base)
	var gate: LevelGate = _add(LevelGate.new("breach"), base + Vector3(0, 0, -9.0))
	Interaction.face(p, gate)
	check(Interaction.target(p) == null, "out of range (9 m) is not targetable")
	gate.global_position = base + Vector3(0, 0, -3.5)
	Interaction.face(p, gate)
	check(Interaction.target(p) == gate, "gate 3.5 m ahead targetable")
	p.ui_open = true
	check(Interaction.prompt(p) == "", "no prompt while a UI is open")
	p.ui_open = false
	gate.free()
	p.free()


func test_forgiving_aim_on_big_targets() -> void:
	var base := Vector3(120, 400, -700)
	var p := _player(base)
	var st: AssemblyStation = _add(AssemblyStation.new(), base + Vector3(0, 0, -2.0))
	Interaction.face(p, st)
	var aim := Interaction.aim_point(st) + Vector3(0.7, 0, 0)  # off-centre but on the station
	var d := aim - p.eye_position()
	p.set_look(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))
	check(Interaction.target(p) == st, "aiming at the station's edge still targets it")
	check(AssemblyStation.prompt_for(p) == "[F] Magic Assembly Station", "station prompt")
	st.free()
	p.free()


func test_every_interactable_registers() -> void:
	var nodes: Array[Node3D] = [Npc.new("A"), LevelGate.new("breach"), AssemblyStation.new(), VaultChest.new(), BreachSwitch.new(), Waystone.new("old_oak")]
	for n in nodes:
		runner_tree.root.add_child(n)
		check(n.is_in_group(Interaction.GROUP) and n.has_method("interact_prompt"), "%s is an interactable" % n.get_class())
	for n in nodes:
		n.free()
