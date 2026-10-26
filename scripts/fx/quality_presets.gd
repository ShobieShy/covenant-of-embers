class_name QualityPresets
extends RefCounted
## FX F8 (step 134): Low / Medium / High graphics presets. Low is the Steam Deck target
## (60 fps at 1280x800, 40 fps floor): SSAO, glow, volumetric fog and all shadows off,
## particle counts halved, burst cap lowered, 60 fps cap. Medium keeps sun shadows + glow,
## drops SSAO and volumetric fog. High = everything the levels author (step 127/132).
## Settings.quality -1 = auto (Low on a Steam Deck, else High). Purely local: FX parity in
## co-op comes from replicated state, never from the preset.

enum Level { LOW, MEDIUM, HIGH }

const NAMES: PackedStringArray = ["Low (Steam Deck)", "Medium", "High"]
const PARTICLE_SCALE := [0.5, 0.75, 1.0]
const BURST_CAP := [12, 18, 24]

static var level: Level = Level.HIGH


static func is_steam_deck() -> bool:
	return OS.get_environment("SteamDeck") == "1" or OS.get_environment("SteamOS") == "1"


static func resolve(setting: int) -> Level:
	if setting < 0:
		return Level.LOW if is_steam_deck() else Level.HIGH
	return clampi(setting, 0, 2) as Level


static func particle_amount(n: int) -> int:
	return maxi(1, int(round(n * PARTICLE_SCALE[level])))


static func burst_cap() -> int:
	return BURST_CAP[level]


static func apply_env(env: Environment) -> void:
	if env == null:
		return
	if not env.has_meta(&"authored_ssao"):
		env.set_meta(&"authored_ssao", env.ssao_enabled)
		env.set_meta(&"authored_glow", env.glow_enabled)
		env.set_meta(&"authored_vfog", env.volumetric_fog_enabled)
	env.ssao_enabled = level == Level.HIGH and env.get_meta(&"authored_ssao")
	env.glow_enabled = level != Level.LOW and env.get_meta(&"authored_glow")
	env.volumetric_fog_enabled = level == Level.HIGH and env.get_meta(&"authored_vfog")


## Applies to a level: its Environment (duplicated once so the shared resource stays authored)
## and every light's shadows.
static func apply_level(lvl: Node) -> void:
	if lvl == null:
		return
	var we := lvl.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	if we and we.environment:
		if not we.has_meta(&"quality_owned"):
			we.environment = we.environment.duplicate() as Environment
			we.set_meta(&"quality_owned", true)
		apply_env(we.environment)
	for l in lvl.find_children("*", "Light3D", true, false):
		var light := l as Light3D
		if not light.has_meta(&"authored_shadow"):
			light.set_meta(&"authored_shadow", light.shadow_enabled)
		var keep := light is DirectionalLight3D and level != Level.LOW or level == Level.HIGH
		light.shadow_enabled = keep and light.get_meta(&"authored_shadow")
	ZoneStreamer.apply_ranges(lvl)  # step 153: prop visibility ranges per preset
	if lvl.is_inside_tree():
		lvl.get_viewport().use_occlusion_culling = level != Level.LOW


static func apply_engine() -> void:
	Engine.max_fps = 60 if level == Level.LOW else 0
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		tree.root.msaa_3d = Viewport.MSAA_DISABLED if level == Level.LOW else Viewport.MSAA_2X
		tree.root.positional_shadow_atlas_size = 1024 if level == Level.LOW else 4096
