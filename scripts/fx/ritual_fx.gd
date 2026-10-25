class_name RitualFX
extends RefCounted
## FX F7 (step 133): story set-piece FX - the summoning circle (beat 1), Bob's vortex (beat 6)
## and the crystal Bob makes from Joe's trash (beat 13). Static builders returning a Node3D;
## CPU particles with modest counts so the Steam Deck Low preset can keep them.

const CIRCLE_SHADER := preload("res://shaders/fx/rune_circle.gdshader")
const SUMMON_COLOR := Color(0.55, 0.35, 1.0)
const VORTEX_COLOR := Color(0.6, 0.3, 1.0)
const CRYSTAL_COLOR := Color(0.45, 0.9, 1.0)


static func disc(radius: float, c: Color, swirl := 0.0, spin := 0.4) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "RuneDisc"
	var q := QuadMesh.new()
	q.size = Vector2.ONE * radius * 2.0
	q.orientation = PlaneMesh.FACE_Y
	var m := ShaderMaterial.new()
	m.shader = CIRCLE_SHADER
	m.set_shader_parameter(&"tint", c)
	m.set_shader_parameter(&"swirl", swirl)
	m.set_shader_parameter(&"spin", spin)
	q.material = m
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _light(c: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.name = "Glow"
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng
	return l


## Beat 1: a 2.2 m rune circle on the dais with rising motes and smoke-coloured light.
static func summoning_circle(at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = "SummoningCircle"
	n.position = at + Vector3(0, 0.03, 0)
	n.add_child(disc(2.2, SUMMON_COLOR, 0.0, 0.3))
	var motes := StatusFX._particles(48, 1.8, SUMMON_COLOR, 0.12)
	motes.name = "Motes"
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	motes.emission_ring_axis = Vector3.UP
	motes.emission_ring_radius = 2.0
	motes.emission_ring_inner_radius = 1.6
	motes.emission_ring_height = 0.05
	motes.direction = Vector3.UP
	motes.spread = 10.0
	motes.gravity = Vector3.ZERO
	motes.initial_velocity_min = 1.0
	motes.initial_velocity_max = 2.0
	n.add_child(motes)
	var l := _light(SUMMON_COLOR, 3.0, 7.0)
	l.position.y = 1.0
	n.add_child(l)
	return n


## Beat 6: dresses Bob's vortex (MentorArrival.vortex keeps the torus) with a swirl disc,
## inward-spiralling motes and a pulsing light.
static func dress_vortex(v: Node3D) -> void:
	var d := disc(1.3, VORTEX_COLOR, 1.0, 1.5)
	d.rotation_degrees.x = 0.0  # torus is already turned upright; the disc follows its plane
	v.add_child(d)
	var p := StatusFX._particles(40, 1.2, VORTEX_COLOR, 0.1)
	p.name = "Swirl"
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 1.2
	p.emission_ring_inner_radius = 0.9
	p.emission_ring_height = 0.02
	p.gravity = Vector3.ZERO
	p.radial_accel_min = -2.5
	p.radial_accel_max = -1.5
	p.tangential_accel_min = 3.0
	p.tangential_accel_max = 4.0
	v.add_child(p)
	v.add_child(_light(VORTEX_COLOR, 4.0, 8.0))


## Beat 13: a floating, slowly turning crystal with sparkles.
static func crystal(at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = "TrashCrystal"
	n.position = at
	var mi := MeshInstance3D.new()
	mi.name = "Gem"
	var cm := CylinderMesh.new()  # 6-sided bipyramid-ish prism, low-poly
	cm.top_radius = 0.0
	cm.bottom_radius = 0.18
	cm.height = 0.5
	cm.radial_segments = 6
	cm.rings = 0
	var m := StandardMaterial3D.new()
	m.albedo_color = CRYSTAL_COLOR
	m.emission_enabled = true
	m.emission = CRYSTAL_COLOR
	m.emission_energy_multiplier = 2.5
	m.metallic = 0.3
	m.roughness = 0.15
	cm.material = m
	mi.mesh = cm
	var bottom := mi.duplicate() as MeshInstance3D
	bottom.rotation_degrees.x = 180.0
	bottom.position.y = -0.25
	mi.position.y = 0.25
	n.add_child(mi)
	n.add_child(bottom)
	var s := StatusFX._particles(24, 1.0, CRYSTAL_COLOR, 0.07)
	s.name = "Sparkles"
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	s.emission_sphere_radius = 0.45
	s.gravity = Vector3(0, 0.3, 0)
	n.add_child(s)
	n.add_child(_light(CRYSTAL_COLOR, 2.0, 4.0))
	n.ready.connect(func(): n.create_tween().set_loops().tween_property(n, ^"rotation:y", TAU, 6.0).from(0.0))
	return n


## HUD (step 133): a sweeping shine over a ProgressBar (UiTheme.frame_bar calls this).
static func bar_shine(b: Control) -> ColorRect:
	var r := ColorRect.new()
	r.name = "Shine"
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/ui/bar_shine.gdshader")
	m.set_shader_parameter(&"period", 3.0 + randf())
	r.material = m
	b.add_child(r)
	return r
