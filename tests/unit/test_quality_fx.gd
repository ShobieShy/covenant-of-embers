extends TestCase
## Step 134 (FX F8): quality presets (Low = Steam Deck) and co-op FX parity (the host's
## statuses and Dark ally aura reach a client puppet through the snapshot).


func test_low_strips_costly_features() -> void:
	var l: Node = (load("res://scenes/levels/midden.tscn") as PackedScene).instantiate()
	QualityPresets.level = QualityPresets.Level.LOW
	QualityPresets.apply_level(l)
	var env := (l.get_node("WorldEnvironment") as WorldEnvironment).environment
	check(not env.ssao_enabled and not env.volumetric_fog_enabled and not env.glow_enabled, "low: no ssao/vfog/glow")
	check(not (l.get_node("Sun") as Light3D).shadow_enabled, "low: no sun shadow")
	check(QualityPresets.particle_amount(40) == 20 and QualityPresets.burst_cap() == 12, "low: particle caps")
	QualityPresets.level = QualityPresets.Level.HIGH
	QualityPresets.apply_level(l)
	check(env.ssao_enabled and env.volumetric_fog_enabled, "high restores the authored env")
	var shared := (load("res://scenes/levels/midden.tscn") as PackedScene).instantiate() as Node
	check((shared.get_node("WorldEnvironment") as WorldEnvironment).environment.ssao_enabled, "resource untouched")
	shared.free()
	l.free()
	QualityPresets.level = QualityPresets.Level.HIGH


func test_auto_resolve_and_setting() -> void:
	check(
		(
			QualityPresets.resolve(0) == QualityPresets.Level.LOW
			and QualityPresets.resolve(5) == QualityPresets.Level.HIGH
		),
		"clamp"
	)
	var s := Settings.new()
	check(s.quality == -1, "auto by default")
	check(s._options().has("quality"), "saved")


func test_coop_status_and_aura_parity() -> void:
	var table := EnemyTable.load_default()
	var host_cw := CoopWorld.new()
	var real := Enemy.new()
	real.setup(table.find("gnawer"))
	runner_tree.root.add_child(real)
	real.burn_left = 2.0
	real.stagger_left = 1.0
	real.corrupted_left = 5.0
	var row := host_cw.snap_row(real)
	var cw := CoopWorld.new()
	cw.table = table
	runner_tree.root.add_child(cw)
	cw._apply_snapshot([row])
	var pup: Enemy = cw.puppets.values()[0]
	pup.tick(0.01)
	real.tick(0.01)
	for n in ["Burn", "Stars"]:
		check(real.get_node_or_null(NodePath(n)) != null and pup.get_node_or_null(NodePath(n)) != null, n + " on both")
	check(pup.get_node_or_null(^"Frost") == null, "no frost on either")
	check(pup.corrupted_left > 0.0, "dark ally aura state reaches the client")
	real.free()
	cw.free()
	host_cw.free()
