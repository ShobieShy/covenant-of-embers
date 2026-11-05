extends TestCase
## U6: three phases, no regen, no lock, the Slagworks door does not travel.


func _boss() -> Blightmaw:
	var b := Enemy.create(EnemyTable.load_default().find("blightmaw_matriarch")) as Blightmaw
	b.auto_tick = false
	b.drives_brain = true
	return b


func test_phases_do_not_rewind_or_regen() -> void:
	var b := _boss()
	runner_tree.root.add_child(b)
	check(b.phase == 1, "full health is phase 1")
	b.health = b.max_health() * 0.50
	b.sync_phase()
	check(b.phase == 2, "50 percent is phase 2")
	b.health = b.max_health() * 0.20
	b.sync_phase()
	check(b.phase == 3 and b.weak_open, "20 percent is phase 3")
	b.health = b.max_health() * 0.90
	b.sync_phase()
	check(b.phase == 3, "raising the fraction does not rewind")
	var held := b.health
	b.think(2.0)
	check_near(b.health, held, 0.01, "no phase regenerates")
	check(not b.arena_locked, "the arena does not lock")
	var level := LevelScale.player_level
	LevelScale.player_level = 20
	b.health_scale = 2.0
	b.health = b.max_health() * 0.50
	b.phase = 1
	b.sync_phase()
	check(b.phase == 2, "the fraction holds when the pool changes")
	LevelScale.player_level = level
	b.drives_brain = false
	var phase := b.phase
	b.think(1.0)
	check(b.phase == phase and b.ticks == 0 or b.drives_brain == false, "a client does not run the brain")
	b.free()


func test_phase_meshes_follow_the_phase() -> void:
	var b := _boss()
	runner_tree.root.add_child(b)
	await runner_tree.process_frame
	var spines := b.model.find_child("Phase2_Spines", true, false) as Node3D
	var heart := b.model.find_child("Phase3_Heart", true, false) as Node3D
	check(spines != null and heart != null, "phase meshes on the rig")
	check(spines != null and not spines.visible, "spines hidden in phase 1")
	check(heart != null and not heart.visible, "heart hidden in phase 1")
	b.health = b.max_health() * 0.5
	b.sync_phase()
	check(b.phase == 2 and spines.visible and not heart.visible, "phase 2 shows the spines")
	b.health = b.max_health() * 0.2
	b.sync_phase()
	check(b.phase == 3 and heart.visible, "phase 3 shows the heart")
	b.free()


func test_sump_does_not_pull_her_and_the_door_stays() -> void:
	var b := _boss()
	runner_tree.root.add_child(b)
	var p := (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as Player
	runner_tree.root.add_child(p)
	b.crown_global_y = 24.0
	b.global_position = Vector3(0, 24, 0)
	p.global_position = Vector3(0, 0, 0)
	b.target = p
	b.think(0.1)
	check(b.state == Gnawer.State.IDLE, "a player at the Sump does not pull her")
	var state := LabyrinthState.fresh(1)
	var cav := BlightcoilCavern.make(8, state)
	runner_tree.root.add_child(cav)
	check(not cav.forge.calls_travel, "the door does not call travel")
	var before := GameFlow.level_id
	cav.forge.interact()
	check(GameFlow.level_id == before, "the door adds no level id")
	check(cav.get_node_or_null("ForgeDoor") is BlightForge, "it is not a LevelGate")
	state.defeat_boss(LabGate.BOSS)
	state.defeat_boss(LabGate.BOSS)
	check(state.bosses.size() == 1, "a second death does not append the id")
	cav.note_boss_dead()
	check(cav.fog_cleared and cav.cocoon.visible, "fog off and the cocoon is shown")
	check(cav.forge.opened and cav.forge.line().contains("way down has opened"), "the opened line")
	check(not cav.forge.line().contains("travel"), "the line does not offer travel")
	b.free()
	p.free()
	cav.free()
