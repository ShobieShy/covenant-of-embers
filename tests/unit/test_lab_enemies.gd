extends TestCase
## L3: main.gd's floor wiring (_lab_enemies / _on_lab_kill) on a main whose _ready is
## stubbed out: entering a floor spawns its goblins (and the King) under one
## "LabyrinthEnemies" spawner, a re-entry replaces it, a cleared elite pack and the King's
## kill are saved to main.labyrinth.


class StubMain:
	extends "res://scripts/core/main.gd"

	func _ready() -> void:
		set_process(false)
		set_physics_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)


func _setup(n: int, seed: int) -> Array:
	var m := StubMain.new()
	m.labyrinth = LabyrinthState.fresh(seed)
	m.position = Vector3(0, 900, -4200)
	runner_tree.root.add_child(m)
	var fl := LabyrinthFloor.build(FloorGen.load_kit(), n, m.labyrinth)
	m.add_child(fl)
	return [m, fl]


func _count(fl: Node, meta: StringName) -> int:
	var c := 0
	for mk in fl.get_node("EnemySpawns").get_children():
		if mk.has_meta(meta):
			c += 1
	return c


func test_entering_floor_spawns_its_goblins() -> void:
	var s := _setup(1, 42)
	var m: Node = s[0]
	var fl: LabyrinthFloor = s[1]
	var marks := fl.get_node("EnemySpawns").get_child_count()
	m._lab_enemies(fl, null)
	var sp := m.get_node_or_null("LabyrinthEnemies") as EnemySpawner
	check(sp != null, "a LabyrinthEnemies spawner under main")
	var all := runner_tree.root.find_children("*", "Enemy", true, false)
	check(
		marks > 0 and all.size() >= marks,
		"one enemy per floor marker (%d / %d)" % [all.size(), marks]
	)
	m._lab_enemies(fl, null)
	check(m.get_node_or_null("LabyrinthEnemies_old") != null, "re-entry retires the old spawner")
	m.free()


func test_elite_pack_and_king_saved() -> void:
	var s := _setup(1, 42)
	var m: Node = s[0]
	var fl: LabyrinthFloor = s[1]
	check(_count(fl, &"lab_elite") > 0, "floor 1 has an elite pack")
	var id := ""
	for mk in fl.get_node("EnemySpawns").get_children():
		if mk.has_meta(&"lab_elite"):
			id = String(mk.get_meta(&"lab_elite"))
	var packs := {id: 2}
	m._on_lab_kill(null, ElementTable.Element.EARTH, fl, id, "", packs)
	check(not m.labyrinth.elite_dead(1, id), "pack alive with one left")
	m._on_lab_kill(null, ElementTable.Element.EARTH, fl, id, "", packs)
	check(m.labyrinth.elite_dead(1, id), "whole pack down: saved dead")
	m.free()
	var s5 := _setup(5, 7)
	var m5: Node = s5[0]
	var f5: LabyrinthFloor = s5[1]
	check(_count(f5, &"lab_boss") == 1, "floor 5 has the King marker")
	m5._lab_enemies(f5, null)
	m5._on_lab_kill(null, ElementTable.Element.EARTH, f5, "", f5.boss_id(), {})
	check(m5.labyrinth.bosses.has(f5.boss_id()), "the King's kill is saved")
	m5.free()
