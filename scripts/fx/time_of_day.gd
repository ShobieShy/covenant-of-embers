class_name TimeOfDay
extends RefCounted
## FX F6 (step 132): day / dusk / night Environment presets with a tween between them.
## Each preset sets the sun (energy, colour), ambient (colour, energy), clear/fog colour and
## exposure; the level's procedural sky (step 124) is tinted for dusk and dropped for night
## (night keeps NightPreset's look: moonlight + sky-tinted ambient, never black).
## `apply(lvl, preset, seconds)`: seconds 0 = instant (tests, shots), > 0 = tween.

enum Preset { DAY, DUSK, NIGHT }

const PRESETS := {
	Preset.DAY:
	{
		"sun_energy": 1.0,
		"sun_color": Color(1.0, 0.96, 0.88),
		"ambient": Color(0.45, 0.45, 0.5),
		"ambient_energy": 0.45,
		"bg": Color(0.55, 0.65, 0.8),
		"exposure": 1.0,
	},
	Preset.DUSK:
	{
		"sun_energy": 0.7,
		"sun_color": Color(1.0, 0.62, 0.38),
		"ambient": Color(0.42, 0.32, 0.38),
		"ambient_energy": 0.55,
		"bg": Color(0.75, 0.45, 0.35),
		"exposure": 1.1,
	},
	Preset.NIGHT:
	{
		"sun_energy": NightPreset.MOON_ENERGY,
		"sun_color": NightPreset.MOON_COLOR,
		"ambient": NightPreset.NIGHT_AMBIENT,
		"ambient_energy": NightPreset.NIGHT_AMBIENT_ENERGY,
		"bg": NightPreset.NIGHT_SKY,
		"exposure": 1.25,
	},
}


## Returns the tween (null when instant or nothing to change).
static func apply(lvl: Node, preset: Preset, seconds := 0.0) -> Tween:
	var p: Dictionary = PRESETS[preset]
	var we := lvl.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	var sun := lvl.get_node_or_null(^"Sun") as DirectionalLight3D
	var env: Environment = null
	if we and we.environment:
		if not we.has_meta(&"tod_owned"):
			we.environment = we.environment.duplicate() as Environment
			we.set_meta(&"tod_owned", true)
		env = we.environment
		if preset == Preset.NIGHT:
			env.background_mode = Environment.BG_COLOR
		elif env.sky != null:
			env.background_mode = Environment.BG_SKY
			var sm := env.sky.sky_material as ProceduralSkyMaterial
			if sm:
				sm = sm.duplicate() as ProceduralSkyMaterial
				sm.sky_horizon_color = p["bg"]
				env.sky = env.sky.duplicate() as Sky
				env.sky.sky_material = sm
	var targets := []
	if sun:
		targets.append([sun, "light_energy", p["sun_energy"]])
		targets.append([sun, "light_color", p["sun_color"]])
	if env:
		targets.append([env, "ambient_light_color", p["ambient"]])
		targets.append([env, "ambient_light_energy", p["ambient_energy"]])
		targets.append([env, "background_color", p["bg"]])
		targets.append([env, "fog_light_color", p["bg"]])
		targets.append([env, "tonemap_exposure", p["exposure"]])
	if seconds <= 0.0 or not lvl.is_inside_tree():
		for t in targets:
			t[0].set(t[1], t[2])
		return null
	var tw := lvl.create_tween().set_parallel()
	for t in targets:
		tw.tween_property(t[0], t[1], t[2], seconds)
	return tw
