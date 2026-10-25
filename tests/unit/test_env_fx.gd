extends TestCase
## Step 132 (FX F6): volumetric haze in the Landfill and Breach only, per-area colour grade,
## day/dusk/night presets (night never black).


func _env(path: String) -> Environment:
	var l: Node = (load(path) as PackedScene).instantiate()
	var e := (l.get_node("WorldEnvironment") as WorldEnvironment).environment
	l.free()
	return e


func test_volumetric_fog_areas() -> void:
	check(_env("res://scenes/levels/midden.tscn").volumetric_fog_enabled, "landfill haze")
	check(_env("res://scenes/levels/breach.tscn").volumetric_fog_enabled, "breach haze")
	check(not _env("res://scenes/levels/town_square.tscn").volumetric_fog_enabled, "town: depth fog only")


func test_grades_differ() -> void:
	var t := _env("res://scenes/levels/town_square.tscn")
	var b := _env("res://scenes/levels/breach.tscn")
	check(t.adjustment_enabled and b.adjustment_enabled, "grading on")
	check(t.adjustment_saturation > b.adjustment_saturation, "town warmer/more saturated than the Breach")


func test_presets() -> void:
	var l: Node = (load("res://scenes/levels/town_square.tscn") as PackedScene).instantiate()
	TimeOfDay.apply(l, TimeOfDay.Preset.DUSK)
	var sun := l.get_node("Sun") as DirectionalLight3D
	check(sun.light_color.r > sun.light_color.b, "dusk sun is warm")
	TimeOfDay.apply(l, TimeOfDay.Preset.NIGHT)
	var env := (l.get_node("WorldEnvironment") as WorldEnvironment).environment
	check(env.background_mode == Environment.BG_COLOR, "night drops the sky")
	check(env.ambient_light_energy >= 0.5 and sun.light_energy > 0.3, "night stays readable")
	TimeOfDay.apply(l, TimeOfDay.Preset.DAY)
	check(env.background_mode == Environment.BG_SKY and is_equal_approx(sun.light_energy, 1.0), "back to day")
	l.free()
