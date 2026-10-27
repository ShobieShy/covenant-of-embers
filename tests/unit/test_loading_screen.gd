extends TestCase
## Loading screen: real stages drive a monotonic bar, the region painting is the backdrop,
## tips rotate, and the readiness checks see Terrain3D and the navmesh.


func test_loading_screen_stages() -> void:
	LoadingScreen.dry_run = true
	var s := LoadingScreen.new()
	s.target = GameFlow.GAME
	s.level_id = "midden"
	runner_tree.root.add_child(s)
	check(s.bar != null and s.stage_label != null and s.tip_label != null and s.ember != null, "ui built")
	check(s.backdrop.texture == LoadingScreen.painting_for("midden"), "landfill painting backdrop")
	check(LoadingScreen.painting_for("old_oak") == EmberArt.texture("map_eldoria"), "old oak -> eldoria")
	s.advance(LoadingScreen.Stage.SCENE, 0.5)
	check(is_equal_approx(s.progress, 0.175), "half the scene stage: %s" % s.progress)
	s.advance(LoadingScreen.Stage.SCENE, 0.2)
	check(is_equal_approx(s.progress, 0.175), "never goes back")
	s.advance(LoadingScreen.Stage.NAV, 0.0)
	check(is_equal_approx(s.progress, 0.9) and s.stage_label.text.begins_with("Charting"), "nav stage label")
	var tip := s.tip_label.text
	s._process(LoadingScreen.TIP_SECONDS + 0.1)
	check(s.tip_label.text != tip, "tip rotates")
	s.free()
	LoadingScreen.dry_run = false


func test_loading_readiness() -> void:
	var n := Node3D.new()
	check(LoadingScreen.terrain_ready(n) and LoadingScreen.nav_ready(n), "empty scene is ready")
	var nav := LevelNavigation.new()
	nav.bake_on_ready = false
	n.add_child(nav)
	check(not LoadingScreen.nav_ready(n), "unbaked navmesh is not ready")
	var z := TerrainZone.new()
	z.build_on_ready = false
	n.add_child(z)
	check(LoadingScreen.terrain_ready(n) != TerrainZone.available(), "unbuilt terrain waits")
	n.free()


func test_flow_uses_loading_screen() -> void:
	check(
		FileAccess.get_file_as_string("res://scripts/core/game_flow.gd").contains("LoadingScreen.start("),
		"GameFlow routes through it"
	)
	var src := FileAccess.get_file_as_string("res://scripts/ui/loading_screen.gd")
	check(src.contains("load_threaded_request") and not src.contains("OS.delay"), "threaded, no stalls")
