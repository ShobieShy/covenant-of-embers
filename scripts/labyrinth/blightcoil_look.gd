class_name BlightcoilLook
extends RefCounted
## Act II cavern dressing. The walk collision stays on the cavern boxes.
## This scene is the shell, the Rotheart, the shelves and the props.

const LOOK := "res://assets/original/ember_art/blightcoil_look/cavern_look.glb"


static func dress(cav: Node3D) -> void:
	if ResourceLoader.exists(LOOK):
		var ps := load(LOOK) as PackedScene
		if ps:
			var n := ps.instantiate()
			n.name = "CavernLook"
			cav.add_child(n)
			for b in n.find_children("*", "CollisionObject3D", true, false):
				var body := b as CollisionObject3D
				body.collision_layer = 0
				body.collision_mask = 0
	_lights(cav)
	var env := _environment()
	var we := WorldEnvironment.new()
	we.name = "CaveEnvironment"
	we.environment = env
	cav.add_child(we)
	cav.set_meta(&"cave_env", env)
	var trunk := cav.get_node_or_null("TrunkArt")
	if trunk is Node3D:
		(trunk as Node3D).visible = false
	for id in ["to_canopy", "to_crown"]:
		var ramp := cav.get_node_or_null("RampArt_" + id)
		if ramp is Node3D:
			(ramp as Node3D).visible = false


static func _environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.045, 0.035)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.56, 0.42)
	e.ambient_light_energy = 0.72
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_exposure = 1.05
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_density = 0.012
	e.fog_light_color = Color(0.16, 0.22, 0.14)
	e.fog_aerial_perspective = 0.35
	e.glow_enabled = true
	e.glow_intensity = 0.45
	e.glow_bloom = 0.12
	e.glow_hdr_threshold = 0.85
	return e


static func _lights(cav: Node3D) -> void:
	var fill := DirectionalLight3D.new()
	fill.name = "CaveFill"
	fill.rotation_degrees = Vector3(-48, 24, 0)
	fill.light_color = Color(0.64, 0.76, 0.55)
	fill.light_energy = 0.42
	fill.shadow_enabled = false
	cav.add_child(fill)
	_omni(cav, "HeartLight", Vector3(0, 15.4, 6.2), Color(1.0, 0.46, 0.14), 6.0, 18.0)
	_omni(cav, "CrystalWest", Vector3(-28, 26.5, -6), Color(0.55, 0.28, 1.0), 3.2, 14.0)
	_omni(cav, "CrystalEast", Vector3(20, 26.5, 2), Color(0.5, 0.24, 1.0), 2.8, 12.0)
	_omni(cav, "PoolWest", Vector3(-16, 2.0, 6), Color(0.4, 0.9, 0.32), 1.8, 11.0)
	_omni(cav, "PoolEast", Vector3(16, 2.0, 4), Color(0.45, 0.95, 0.34), 1.8, 11.0)
	_omni(cav, "ShrineLight", Vector3(0.6, 14.4, 14.0), Color(0.75, 0.9, 0.5), 1.6, 9.0)
	_omni(cav, "CrownLight", Vector3(-16, 28.0, -8), Color(0.55, 0.7, 0.45), 1.4, 14.0)


static func _omni(cav: Node3D, nm: String, at: Vector3, color: Color, energy: float, radius: float) -> void:
	var l := OmniLight3D.new()
	l.name = nm
	l.position = at
	l.light_color = color
	l.light_energy = energy
	l.omni_range = radius
	l.shadow_enabled = false
	cav.add_child(l)
