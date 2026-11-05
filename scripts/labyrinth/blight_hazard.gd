class_name BlightHazard
extends Node
## Act II hazards (KTD4, KTD9). Mire and husk puffs take health only while a living
## body overlaps them. Spore fog is a height band with a linger. Vines refresh a slow
## and do not hurt or move anyone. A long landing hurts; a void fall returns to the
## last pad. None of this spends Breath or the shield.

const MIRE_DPS := 0.04
const FOG_DPS := 0.02
const FOG_LINGER := 3.0
const FALL_START := 4.0
const FALL_PER_M := 0.08
const VINE_SLOW := 0.5
const VINE_TIME := 0.2
const PUFF_TIME := 4.0

var cavern: Node3D
var fog_y := 12.0
var void_y := -8.0
var rest_exempt := 2.5
var rest_pad := Vector3.ZERO
var last_pad := Vector3.ZERO
var fog_cleared := false
var auto_tick := true
var _from_y := {}
var _air := {}
var _voided := {}


static func fall_fraction(drop_m: float) -> float:
	if drop_m <= FALL_START:
		return 0.0
	return FALL_PER_M * (drop_m - FALL_START)


static func in_fog_band(local_y: float, fog_line: float, on_rest: bool, cleared: bool) -> bool:
	if cleared or on_rest:
		return false
	return local_y >= fog_line - 0.05


func _physics_process(dt: float) -> void:
	if auto_tick:
		tick(dt)


func tick(dt: float) -> void:
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group(Player.GROUP):
		if n is Player:
			tick_player(n as Player, dt)


func tick_player(p: Player, dt: float) -> void:
	if p == null:
		return
	_expire_puffs(dt)
	if not p.alive() or p.downed:
		return
	var local_y := _local_y(p)
	if _overlaps(p, "mire") or _overlaps(p, "puff"):
		p.hurt_health(p.health.max_value() * MIRE_DPS * dt)
	var on_rest := rest_pad != Vector3.ZERO and _near_pad(p, rest_pad)
	if in_fog_band(local_y, fog_y, on_rest, fog_cleared):
		p.poison_dps = FOG_DPS
		p.poison_left = FOG_LINGER
	if _overlaps(p, "vine"):
		var before := p.global_position
		p.apply_slow(VINE_SLOW, VINE_TIME)
		p.global_position = before
	_falls(p, local_y)


func _falls(p: Player, local_y: float) -> void:
	var id := p.get_instance_id()
	if local_y < void_y:
		if not bool(_voided.get(id, false)):
			_voided[id] = true
			var from_y := float(_from_y.get(id, local_y))
			apply_fall(p, from_y - local_y)
			if last_pad != Vector3.ZERO and p.alive():
				p.global_position = last_pad + Vector3(0, 0.5, 0)
				p.velocity = Vector3.ZERO
		return
	_voided[id] = false
	var grounded := p.is_on_floor()
	if grounded:
		if bool(_air.get(id, false)):
			var drop := float(_from_y.get(id, local_y)) - local_y
			apply_fall(p, drop)
		_from_y[id] = local_y
		_air[id] = false
	else:
		if not _air.has(id):
			_from_y[id] = local_y
		_air[id] = true


static func apply_fall(p: Player, drop_m: float) -> void:
	var frac := fall_fraction(drop_m)
	if frac <= 0.0 or p == null:
		return
	p.hurt_health(p.health.max_value() * frac)


func _local_y(p: Player) -> float:
	if cavern == null:
		return p.global_position.y
	return p.global_position.y - cavern.global_position.y


func _near_pad(p: Player, pad: Vector3) -> bool:
	var d := p.global_position - pad
	return Vector2(d.x, d.z).length() <= rest_exempt and absf(d.y) < 2.0


func _overlaps(p: Player, kind: String) -> bool:
	var feet := p.global_position
	for n in get_tree().get_nodes_in_group(&"blight_volume"):
		if not (n is Node3D) or String(n.get_meta(&"kind", "")) != kind:
			continue
		if not (n as Node3D).visible and kind == "puff":
			continue
		var vol := n as Node3D
		var sz: Vector3 = vol.get_meta(&"size", Vector3(2, 2, 2))
		var half := sz * 0.5
		var c: Vector3 = vol.global_position
		if (
			absf(feet.x - c.x) <= half.x + 0.35
			and absf(feet.z - c.z) <= half.z + 0.35
			and feet.y >= c.y - half.y - 0.2
			and feet.y <= c.y + half.y + 1.6
		):
			return true
	return false


func _expire_puffs(dt: float) -> void:
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group(&"blight_volume"):
		if String(n.get_meta(&"kind", "")) != "puff":
			continue
		var left := float(n.get_meta(&"left", PUFF_TIME)) - dt
		n.set_meta(&"left", left)
		if left <= 0.0 and n is Node:
			(n as Node).queue_free()
