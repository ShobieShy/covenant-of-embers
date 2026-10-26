class_name RemotePlayer
extends Node3D
## Another player in a co-op session (BUILD_PLAN step 79): a greybox capsule with a name
## tag, moved toward the last pose that player sent (20 Hz, smoothed). On the host,
## enemies can hunt it like the local player (alive / invulnerable / eye_position); its
## hits are sent to its owner ("hurt"). Not in Player.GROUP: kill XP stays local.

const SMOOTH := 12.0  ## 1/s, how fast the shown pose catches up
const EYE := 1.5
const GROUP := &"remote_players"
const HITBOX_LAYER := 2  ## step 108: bolts hit it (Light heals); players/enemies don't collide

## Step 108: a local Light bolt hit this player; CoopWorld sends "heal" to its owner.
signal light_healed(amount: float)

var peer := 0
var display_name := "Player"
var target_pos := Vector3.ZERO
var target_yaw := 0.0
var is_alive := true
var is_invulnerable := false
var downed := false  ## step 80
var hp := 0.0
var hp_max := 1.0
var level := 1
var poses := 0
var _tag: Label3D
var color := Color(0.35, 0.6, 1.0)  ## step 73: the character colour (pose "c")
var _mat: StandardMaterial3D
var _placed := false
var archetype := ""  ## pose "k": batch_02 player model for gal / buff
var _body: Node3D
var _model: CharacterModel
var brand_fx: BrandFX  ## step 142: the other player's staff-brand FX (pose "bf")


func _ready() -> void:
	add_to_group(GROUP)
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.8
	mi.mesh = cap
	mi.position = Vector3(0, 0.9, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	_mat = m
	mi.material_override = m
	add_child(mi)
	_body = mi
	var hb := StaticBody3D.new()
	hb.name = "Hitbox"
	hb.collision_layer = HITBOX_LAYER
	hb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.8
	cs.shape = shape
	cs.position = Vector3(0, 0.9, 0)
	hb.add_child(cs)
	add_child(hb)
	_tag = Label3D.new()
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.position = Vector3(0, 2.1, 0)
	_tag.text = display_name
	add_child(_tag)


func apply_pose(d: Dictionary) -> void:
	target_pos = d.get("p", target_pos)
	target_yaw = float(d.get("y", target_yaw))
	is_alive = bool(d.get("a", true))
	is_invulnerable = bool(d.get("i", false))
	downed = bool(d.get("d", false))
	hp = float(d.get("h", hp))
	hp_max = maxf(1.0, float(d.get("m", hp_max)))
	level = int(d.get("l", level))
	display_name = String(d.get("n", display_name))
	if d.has("c"):
		color = Color.from_string(String(d["c"]), color)
		if _mat:
			_mat.albedo_color = color
	_apply_brand(d.get("bf", []))
	if d.has("k") and String(d["k"]) != archetype:
		_set_archetype(String(d["k"]))
	if _tag:
		_tag.text = "%s%s" % [display_name, " (down)" if downed else ""]
	poses += 1
	if not _placed:
		_placed = true
		global_position = target_pos
		rotation.y = target_yaw


## Step 142: [bits, meter, colour html] -> BrandFX at the staff hand ([] = nothing branded).
func _apply_brand(bf: Variant) -> void:
	if brand_fx == null:
		brand_fx = BrandFX.new()
		brand_fx.position = Vector3(0.35, 1.35, -0.35)
		add_child(brand_fx)
	if bf is Array and (bf as Array).size() >= 3:
		var a := bf as Array
		brand_fx.apply(int(a[0]), float(a[1]), Color.from_string(String(a[2]), Color.WHITE))
	else:
		brand_fx.apply(0, 0.0, Color.WHITE)


func _set_archetype(id: String) -> void:
	archetype = id
	if _model:
		_model.queue_free()
		_model = null
	_model = CharacterModel.make(CharacterModel.for_archetype(id))
	if _model:
		add_child(_model)
	if _body:
		_body.visible = _model == null


func smooth(dt: float) -> void:
	var k := 1.0 - exp(-SMOOTH * dt)
	global_position = global_position.lerp(target_pos, k)
	rotation.y = lerp_angle(rotation.y, target_yaw, k)


func alive() -> bool:
	return is_alive and not downed


func invulnerable() -> bool:
	return is_invulnerable


func eye_position() -> Vector3:
	return global_position + Vector3(0, EYE, 0)
