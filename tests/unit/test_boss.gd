extends TestCase
## Step 34 done check: the Breach Warden (two-phase mini-boss).
##  - breach_warden.tres = data/enemies/breach_warden.toml; ai kind "boss" spawns a Warden
##    (a Heap); the Breach's last wave is the Warden alone at the dais;
##  - phase 1 above 50 % health; the hit that takes it to <= 50 % switches to phase 2 once
##    (phase_changed), faster and with a shorter slam wind-up / cooldown;
##  - its death (EventBus.enemy_killed) opens the vault door: hidden, no collision; a Heap
##    kill does not.

const SCENE := "res://scenes/levels/breach.tscn"
const TOML := "res://data/enemies/breach_warden.toml"
const E := ElementTable.Element


func _spawn(w: Node3D, id: String, feet: Vector3) -> Enemy:
	var e := Enemy.create(EnemyTable.load_default().find(id), Transform3D(Basis.IDENTITY, feet))
	e.auto_tick = false
	w.add_child(e)
	return e


func test_tres_matches_toml() -> void:
	var r := EnemyTable.from_toml_files([TOML])
	check(not r.has("error"), "toml loads (%s)" % r.get("error", ""))
	if r.has("error"):
		return
	var want := (r["table"] as EnemyTable).find("breach_warden")
	var got := EnemyTable.load_default().find("breach_warden")
	check(got != null, "shipped")
	if got == null:
		return
	for k in [
		"display_name",
		"affinity",
		"max_health",
		"level",
		"xp_reward",
		"size",
		"color",
		"weak_point_offset",
		"weak_point_size",
		"ai"
	]:
		check(
			got.get(k) == want.get(k) if k == "ai" else str(got.get(k)) == str(want.get(k)),
			"%s: %s vs %s" % [k, got.get(k), want.get(k)]
		)


func test_phase_switch_at_half() -> void:
	var w := Node3D.new()
	w.position = Vector3(0, 500, 2400)
	runner_tree.root.add_child(w)
	var b := _spawn(w, "breach_warden", Vector3.ZERO) as Warden
	check(b != null, "boss kind spawns a Warden")
	if b == null:
		w.free()
		return
	var seen: Array = []
	b.phase_changed.connect(func(_x, p): seen.append(p))
	var walk := b.rusher.walk_speed
	var windup := b.rusher.attack_windup
	var cd := b.rusher.attack_cooldown
	b.apply_damage(199.0, E.FIRE)
	check(b.phase == 1, "phase 1 at 201/400")
	b.apply_damage(1.0, E.FIRE)
	check(b.phase == 2 and seen == [2], "phase 2 at exactly 50 %% (%s)" % [seen])
	check_near(b.rusher.walk_speed, walk * 1.5, 0.001, "faster")
	check(b.rusher.attack_windup < windup and b.rusher.attack_cooldown < cd, "shorter slam")
	b.apply_damage(50.0, E.FIRE)
	check(seen.size() == 1, "switches once")
	b.reset()
	check(b.phase == 1 and is_equal_approx(b.rusher.walk_speed, walk), "reset -> phase 1")
	w.free()


func test_death_opens_vault() -> void:
	var w := Node3D.new()
	w.position = Vector3(0, 600, 2700)
	runner_tree.root.add_child(w)
	var level: Node3D = (load(SCENE) as PackedScene).instantiate()
	w.add_child(level)
	var waves := level.get_node("Waves")
	var last := waves.get_child(waves.get_child_count() - 1)
	check(str(last.name) == "warden", "the boss is the last wave (%s)" % last.name)
	var br := Breach.new()
	w.add_child(br)
	br.setup(level)
	var opened := [0]
	br.vault_opened.connect(func(): opened[0] += 1)
	var door := br.door()
	check(door != null and door.visible and door.collision_layer != 0, "door shut")
	var h := _spawn(w, "heap", Vector3(5, 0, 5))
	h.apply_damage(1000.0, E.FIRE)
	check(not br.open, "a heap kill keeps it shut")
	var b := _spawn(w, "breach_warden", Vector3(0, 0, 0))
	b.apply_damage(1000.0, E.FIRE)
	check(br.open and opened[0] == 1, "boss death opens the vault")
	check(not door.visible and door.collision_layer == 0, "door gone")
	w.free()
