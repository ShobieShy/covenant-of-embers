extends TestCase
## OW4: open-world enemies beyond 96 m of every viewer stop processing and wake inside 80 m.


func test_sleep_and_wake() -> void:
	var w := Node3D.new()
	runner_tree.root.add_child(w)
	var d := EnemyTable.load_default().find("gnawer")
	var near := Enemy.create(d, Transform3D(Basis.IDENTITY, Vector3(20, 0, 0)))
	var far := Enemy.create(d, Transform3D(Basis.IDENTITY, Vector3(150, 0, 0)))
	w.add_child(near)
	w.add_child(far)
	var s := EnemySleep.new()
	w.add_child(s)
	s.update_now([Vector3.ZERO])
	check(near.process_mode != Node.PROCESS_MODE_DISABLED, "near enemy awake")
	check(far.process_mode == Node.PROCESS_MODE_DISABLED, "far enemy asleep")
	s.update_now([Vector3(60, 0, 0)])  # 90 m: inside the hysteresis band, stays asleep
	check(far.process_mode == Node.PROCESS_MODE_DISABLED, "no wake in the 80-96 m band")
	s.update_now([Vector3(80, 0, 0)])  # 70 m
	check(far.process_mode == Node.PROCESS_MODE_INHERIT, "wakes inside 80 m")
	w.free()
