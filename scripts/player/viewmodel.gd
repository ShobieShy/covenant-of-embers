class_name Viewmodel
extends Node3D
## First-person viewmodel (BUILD_PLAN step 10, port of the archived C++ viewmodel pass, old
## step 21). Child of the Player's Head, so it follows the eye and bobs with it.
##  * Poses = Magewar default_position (wieldable_staff.tscn (0.33, -0.26, -0.53),
##    wieldable_wand.tscn (0.3, -0.24, -0.5), metres in view space).
##  * Focus slide = Magewar action_secondary: position -> Vector3(0, default.y, default.z),
##    here lerped by Player.focus.amount() (the same 0.2 s linear tween as the FOV, no
##    separate Tween).
##  * Greybox model built in code (no asset): Magewar's CSG placeholders reinterpreted as a
##    shaft along -Z with an element-coloured gem at the tip and a CastPoint just past it
##    (staff shaft 0.55 x r 0.04, gem r 0.07; wand shaft 0.3 x r 0.025, gem r 0.04, as
##    Magewar). The gem is unshaded in the ElementTable colour (the wieldable's element()).
##  * Layer: every viewmodel mesh is on visual layer VISUAL_LAYER (20) only; the main
##    camera culls it, and a SubViewport camera at a fixed viewmodel_fov (75 deg, Cogito
##    ViewmodelSpace viewmodel_fov) that copies the main camera's transform renders only
##    that layer over the screen (transparent) - so the viewmodel never clips into walls
##    and doesn't zoom when focusing. enable_render() builds that overlay (game only:
##    headless has no renderer).
##  * Swap draw: the drawn wieldable rises from DRAW_DROP m below its pose as the 0.4 s
##    swap runs (Loadout.draw_progress()).
##  * Recoil (CameraFeel.recoil_offset(), zero under reduced motion) is added on top.

const VISUAL_LAYER := 20
const LAYER_MASK := 1 << (VISUAL_LAYER - 1)
const STAFF_POSE := Vector3(0.33, -0.26, -0.53)  ## Magewar wieldable_staff.tscn default_position
const WAND_POSE := Vector3(0.3, -0.24, -0.5)  ## Magewar wieldable_wand.tscn default_position
const DRAW_DROP := 0.35
const SHAFT_COLOR := Color(0.36, 0.25, 0.15)

## Greybox dimensions per type: [shaft length, shaft radius, gem radius].
const DIMS := {WieldableDef.Type.STAFF: [0.55, 0.04, 0.07], WieldableDef.Type.WAND: [0.3, 0.025, 0.04]}

var elements: ElementTable
var fov := 75.0
var shown: WieldableInstance  ## what the model shows (null = hidden)
var shown_type: int = -1
var shown_element: int = -1
var shown_key := ""  ## step 122: type/element/part ids/gems -> rebuild the StaffKit when it changes
var kit: Node3D
var pose := STAFF_POSE
var model: Node3D
var shaft: MeshInstance3D
var gem: MeshInstance3D
var cast_point: Marker3D
var brand_fx: BrandFX  ## step 141: heat/charge/spin look on the Head
var render_viewport: SubViewport  ## enable_render()
var render_camera: Camera3D
var _overlay: CanvasLayer
## 0.3.1 P5 (M5): a short element-coloured muzzle flare at the cast point.
const FLARE_SECONDS := 0.08
const FLARE_RADIUS := 0.06
var flare: MeshInstance3D
var flare_left := 0.0
var flares := 0
var _flare_mat: StandardMaterial3D
var _main_camera: Camera3D


func _init() -> void:
	name = "Viewmodel"
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	shaft = _mesh_instance("Shaft")
	gem = _mesh_instance("Gem")
	cast_point = Marker3D.new()
	cast_point.name = "CastPoint"
	model.add_child(cast_point)
	brand_fx = BrandFX.new(LAYER_MASK)
	cast_point.add_child(brand_fx)
	flare = MeshInstance3D.new()
	flare.name = "MuzzleFlare"
	flare.layers = LAYER_MASK
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sm := SphereMesh.new()
	sm.radius = FLARE_RADIUS
	sm.height = FLARE_RADIUS * 2.0
	sm.radial_segments = 8
	sm.rings = 4
	flare.mesh = sm
	_flare_mat = StandardMaterial3D.new()
	_flare_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flare_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flare_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flare.material_override = _flare_mat
	flare.visible = false
	cast_point.add_child(flare)
	visible = false


func _mesh_instance(n: String) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = n
	m.layers = LAYER_MASK
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(m)
	return m


static func pose_for(type: int) -> Vector3:
	return WAND_POSE if type == WieldableDef.Type.WAND else STAFF_POSE


## Magewar ADS pose: x to the centre, y/z kept.
static func focus_pose(p: Vector3) -> Vector3:
	return Vector3(0.0, p.y, p.z)


func element_color(e: int) -> Color:
	var t := elements if elements != null else ElementTable.load_default()
	return t.color(e) if t != null else Color.WHITE


func gem_color() -> Color:
	var m := gem.material_override as StandardMaterial3D
	return m.albedo_color if m != null else Color.BLACK


## Shows `w` (null = empty hands); rebuilds the greybox when the type or element changes.
func show_wieldable(w: WieldableInstance) -> void:
	shown = w
	visible = w != null
	if w == null:
		return
	var t := int(w.type())
	var e := int(w.element())
	var key := _key(w)
	if t == shown_type and e == shown_element and key == shown_key:
		return
	shown_key = key
	shown_type = t
	shown_element = e
	pose = pose_for(t)
	var d: Array = DIMS[t]
	var length: float = d[0]
	var r: float = d[1]
	var gr: float = d[2]
	var cyl := CylinderMesh.new()
	cyl.height = length
	cyl.top_radius = r * 0.8
	cyl.bottom_radius = r
	cyl.radial_segments = 10
	cyl.rings = 1
	var sm := StandardMaterial3D.new()
	sm.albedo_color = SHAFT_COLOR
	sm.roughness = 0.8
	cyl.material = sm
	shaft.mesh = cyl
	# Cylinder axis (Y) turned onto -Z (top end forward), centred on the pose.
	shaft.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	shaft.position = Vector3.ZERO
	var sph := SphereMesh.new()
	sph.radius = gr
	sph.height = gr * 2.0
	sph.radial_segments = 12
	sph.rings = 6
	gem.mesh = sph
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = element_color(e)
	gem.material_override = gm
	gem.position = Vector3(0.0, 0.0, -0.5 * length - gr * 0.6)
	cast_point.position = Vector3(0.0, 0.0, gem.position.z - gr - 0.02)
	if kit != null:
		kit.free()
	kit = StaffKit.build(w, length, r, gr, element_color(e), LAYER_MASK)
	model.add_child(kit)


func _key(w: WieldableInstance) -> String:
	var k := "%d/%d/%s" % [int(w.type()), int(w.element()), w.rarity_id()]
	for p in w.parts:
		if p != null:
			k += "/" + p.id + ":" + str(p.gems.size())
	return k


## Local position for the current pose: focus slide (amount 0..1), swap draw (0..1 done)
## and recoil (view-space offset).
func pose_position(focus_amount: float, draw: float, recoil: Vector3) -> Vector3:
	var p := pose.lerp(focus_pose(pose), clampf(focus_amount, 0.0, 1.0))
	p.y -= DRAW_DROP * (1.0 - clampf(draw, 0.0, 1.0))
	return p + recoil


## One tick: what's in hand + where it sits.
func update_pose(w: WieldableInstance, focus_amount: float, draw: float, recoil: Vector3) -> void:
	show_wieldable(w)
	model.position = pose_position(focus_amount, draw, recoil)
	if render_camera != null and _main_camera != null:
		render_camera.global_transform = _main_camera.global_transform


## Step 141: the held brand's FX (heat glow/steam, charge glow, spin ring).
func update_brand(m: FireMode) -> void:
	brand_fx.show_mode(m)
	# t69u: the crystal reload rolls the staff over to the eject port and back.
	var p := brand_fx.progress
	model.rotation = Vector3(0.25, 0.0, 0.55) * sin(PI * p) if p >= 0.0 else Vector3.ZERO


## P5 (M5): a cast lights the flare in the gem's colour for FLARE_SECONDS.
func flash_muzzle() -> void:
	flare_left = FLARE_SECONDS
	flares += 1
	var c := gem_color()
	_flare_mat.albedo_color = Color(c.r, c.g, c.b, 1.0)
	flare.scale = Vector3.ONE
	flare.visible = true


func tick_flare(dt: float) -> void:
	if flare_left <= 0.0:
		return
	flare_left = maxf(0.0, flare_left - dt)
	var k := flare_left / FLARE_SECONDS
	flare.visible = k > 0.0
	flare.scale = Vector3.ONE * (1.6 - 0.6 * k)
	_flare_mat.albedo_color.a = k


## Cast point in world space (the visible tracer start).
func cast_point_position() -> Vector3:
	return cast_point.global_position


## Builds the overlay: a transparent SubViewport the size of the screen whose camera (fov,
## only VISUAL_LAYER) follows `main_camera`; the main camera stops drawing the layer.
## `size` 0 = follow the root viewport.
func enable_render(main_camera: Camera3D, size: Vector2i = Vector2i.ZERO) -> void:
	_main_camera = main_camera
	main_camera.cull_mask &= ~LAYER_MASK
	if render_viewport != null:
		return
	render_viewport = SubViewport.new()
	render_viewport.name = "ViewmodelViewport"
	render_viewport.transparent_bg = true
	render_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_viewport.size = size if size != Vector2i.ZERO else Vector2i(get_viewport().get_visible_rect().size)
	render_camera = Camera3D.new()
	render_camera.name = "ViewmodelCamera"
	render_camera.fov = fov
	render_camera.near = 0.01
	render_camera.far = 10.0
	render_camera.cull_mask = LAYER_MASK
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.6)
	render_camera.environment = env
	render_viewport.add_child(render_camera)
	_overlay = CanvasLayer.new()
	_overlay.name = "ViewmodelOverlay"
	_overlay.layer = 1
	_overlay.add_child(render_viewport)
	var rect := TextureRect.new()
	rect.name = "ViewmodelTexture"
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture = render_viewport.get_texture()
	_overlay.add_child(rect)
	add_child(_overlay)
	render_camera.current = true
	render_camera.global_transform = main_camera.global_transform
	if size == Vector2i.ZERO:
		get_viewport().size_changed.connect(_on_size_changed)


func _on_size_changed() -> void:
	if render_viewport != null:
		render_viewport.size = Vector2i(get_viewport().get_visible_rect().size)


## Render frames: keep the viewmodel camera on the (interpolated) main camera.
func _process(_delta: float) -> void:
	if render_camera != null and _main_camera != null:
		render_camera.global_transform = _main_camera.global_transform


## Where the gem's centre lands in the viewmodel image (pixels) and whether it's in view.
func gem_screen_position() -> Vector2:
	return render_camera.unproject_position(gem.global_position) if render_camera != null else Vector2(-1, -1)


func gem_in_view() -> bool:
	if render_camera == null or not visible:
		return false
	var g := gem.global_position
	if render_camera.is_position_behind(g) or not render_camera.is_position_in_frustum(g):
		return false
	var px := gem_screen_position()
	return Rect2(Vector2.ZERO, Vector2(render_viewport.size)).has_point(px)
