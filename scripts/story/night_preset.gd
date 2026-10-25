class_name NightPreset
extends RefCounted
## Step 127 (FX F1): the night Environment preset used by the intro and tools/level_shots.gd.

# Step 127 (FX F1): moonlit, readable night. A preset swap (moon light + sky-tinted ambient +
# warm lantern fill), not a multiplied-down sun, so the cinematic frames are never black.
const NIGHT_AMBIENT := Color(0.22, 0.27, 0.48)
const NIGHT_AMBIENT_ENERGY := 0.75
const NIGHT_SKY := Color(0.05, 0.07, 0.16)
const MOON_COLOR := Color(0.62, 0.72, 1.0)
const MOON_ENERGY := 0.45
const LANTERN_COLOR := Color(1.0, 0.7, 0.4)


## Swap a level to the night preset. Static so tools/level_shots.gd and tests can use it.
static func apply(lvl: Node, anchor: Vector3) -> void:
	var we := lvl.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		var env := we.environment.duplicate() as Environment
		env.ambient_light_color = NIGHT_AMBIENT
		env.ambient_light_energy = NIGHT_AMBIENT_ENERGY
		env.background_color = NIGHT_SKY
		env.fog_light_color = NIGHT_SKY
		env.tonemap_exposure = 1.25
		we.environment = env
	var sun := lvl.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.light_energy = MOON_ENERGY
		sun.light_color = MOON_COLOR
	if lvl.get_node_or_null("NightLantern") == null:
		var lamp := OmniLight3D.new()
		lamp.name = "NightLantern"
		lamp.light_color = LANTERN_COLOR
		lamp.light_energy = 2.0
		lamp.omni_range = 9.0
		lvl.add_child(lamp)
		lamp.position = anchor + Vector3(0.8, 2.2, -1.2)
