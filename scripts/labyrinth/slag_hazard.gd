class_name SlagHazard
extends Node
## Act III heat (KTD4). Lava, furnace shimmer, cart hits and long falls spend health
## only. Breath and the shield stay put. Volumes live in slag_volume, never blight_volume.

const LAVA_DPS := 0.08
const SHIMMER_DPS := 0.02
const SHIMMER_LINGER := 2.0
const CART_HIT := 0.12
const CART_IGNORE := 1.0
const CART_REACH := 0.9
const VOID_Y := -8.0

var host: Node3D
var cart_t := 0.0
var last_pad := Vector3.ZERO
var auto_tick := true
var _shimmer := {}
var _cart_cd := {}
var _from_y := {}
var _air := {}
var _voided := {}
var _watched := {}
var _rail_nodes: Array = []
var _cart_nodes: Array = []
var _rails_ready := false


func _ready() -> void:
	if host == null and get_parent() is Node3D:
		host = get_parent() as Node3D
	_ensure_carts.call_deferred()


func _physics_process(dt: float) -> void:
	if auto_tick:
		tick(dt)


func on_rest(_at: Vector3) -> void:
	for n in get_tree().get_nodes_in_group(Player.GROUP):
		if n is Player:
			clear_heat(n as Player)


func clear_heat(p: Player) -> void:
	if p == null:
		return
	var id := p.get_instance_id()
	_shimmer.erase(id)
	_cart_cd.erase(id)


static func clock_from(message: Dictionary) -> float:
	if not message.has("cart_t"):
		return 0.0
	return float(message["cart_t"])


func tick(dt: float) -> void:
	if host == null or dt < 0.0:
		return
	cart_t += dt
	_move_carts()
	if not is_inside_tree():
		return
	last_pad = host.call(&"pad_global")
	for n in get_tree().get_nodes_in_group(Player.GROUP):
		if n is Player:
			tick_player(n as Player, dt)


func tick_player(p: Player, dt: float) -> void:
	if p == null:
		return
	_watch(p)
	if not p.alive() or p.downed:
		return
	var id := p.get_instance_id()
	if _in_volume(p, "lava") and not bool(host.call(&"on_pad", p.global_position)):
		p.hurt_health(p.health.max_value() * LAVA_DPS * dt)
	var linger := float(_shimmer.get(id, 0.0))
	if _in_volume(p, "shimmer") and not _on_gantry(p):
		linger = SHIMMER_LINGER
	if linger > 0.0:
		var step := minf(dt, linger)
		p.hurt_health(p.health.max_value() * SHIMMER_DPS * step)
		linger -= dt
	_shimmer[id] = maxf(linger, 0.0)
	_carts(p, dt)
	_falls(p)


func _watch(p: Player) -> void:
	var id := p.get_instance_id()
	if bool(_watched.get(id, false)):
		return
	if p.respawned.is_connected(_on_respawn):
		_watched[id] = true
		return
	p.respawned.connect(_on_respawn)
	_watched[id] = true


func _on_respawn(p: Player) -> void:
	clear_heat(p)


func _in_volume(p: Player, kind: String) -> bool:
	var feet := p.global_position
	for n in get_tree().get_nodes_in_group(&"slag_volume"):
		if not (n is Node3D) or String(n.get_meta(&"kind", "")) != kind:
			continue
		if not _on_floor(n):
			continue
		var vol := n as Node3D
		var cs := vol.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var half: Vector3 = (cs.shape as BoxShape3D).size * 0.5
		var c := vol.global_position
		if (
			absf(feet.x - c.x) <= half.x + 0.3
			and absf(feet.z - c.z) <= half.z + 0.3
			and feet.y >= c.y - half.y - 0.2
			and feet.y <= c.y + half.y + 1.5
		):
			return true
	return false


func _on_floor(n: Node) -> bool:
	var p: Node = n
	while p:
		if p == host:
			return true
		p = p.get_parent()
	return false


func _on_gantry(p: Player) -> bool:
	if host == null:
		return false
	return p.global_position.y - host.global_position.y > 2.2


func _falls(p: Player) -> void:
	var id := p.get_instance_id()
	var local_y := p.global_position.y - host.global_position.y
	if local_y < VOID_Y:
		if not bool(_voided.get(id, false)):
			_voided[id] = true
			var from_y := float(_from_y.get(id, local_y))
			BlightHazard.apply_fall(p, from_y - local_y)
			if p.alive():
				p.global_position = last_pad + Vector3(0, 0.5, 0)
				p.velocity = Vector3.ZERO
				clear_heat(p)
		return
	_voided[id] = false
	var grounded := p.is_on_floor()
	if grounded:
		if bool(_air.get(id, false)):
			BlightHazard.apply_fall(p, float(_from_y.get(id, local_y)) - local_y)
		_from_y[id] = local_y
		_air[id] = false
	else:
		if not _air.has(id):
			_from_y[id] = local_y
		_air[id] = true


func _rails() -> Array:
	if _rails_ready:
		return _rail_nodes
	if host == null or not host.is_inside_tree():
		return []
	_rail_nodes = []
	if int(host.get(&"floor_no")) >= 9 and int(host.get(&"floor_no")) <= 12:
		for n in host.find_children("*", "Node3D", true, false):
			if String(n.name) == "Rail" and n.has_meta(&"loop"):
				_rail_nodes.append(n)
	_rails_ready = true
	return _rail_nodes


func _remember_carts() -> void:
	_cart_nodes.clear()
	for n in _rails():
		if not n.has_meta(&"cart"):
			continue
		var cart: Variant = n.get_meta(&"cart")
		if cart is Node3D and is_instance_valid(cart):
			_cart_nodes.append(cart)


func _ensure_carts() -> void:
	if host == null or not host.is_inside_tree():
		return
	for n in _rails():
		if n.has_meta(&"cart"):
			var existing: Variant = n.get_meta(&"cart")
			if existing is Node and is_instance_valid(existing) and (existing as Node).is_inside_tree():
				continue
		var cart := Node3D.new()
		cart.name = "Cart"
		cart.set_meta(&"mover", true)
		host.add_child(cart)
		n.set_meta(&"cart", cart)
	_remember_carts()


func _move_carts() -> void:
	_ensure_carts()
	for n in _rails():
		if not n.has_meta(&"cart"):
			continue
		var cart := n.get_meta(&"cart") as Node3D
		if cart == null:
			continue
		var pts: Array = n.get_meta(&"loop")
		if pts.size() < 2:
			continue
		var period := maxf(float(n.get_meta(&"period", 8.0)), 0.1)
		var u := fposmod(cart_t, period) / period
		var at := _sample(pts, u)
		cart.position = at
		cart.set_meta(&"ahead", _sample(pts, u + 0.02))


func _sample(pts: Array, u: float) -> Vector3:
	var n := pts.size()
	var f := fposmod(u, 1.0) * float(n)
	var i := int(f) % n
	var j := (i + 1) % n
	var a: Vector3 = pts[i]
	var b: Vector3 = pts[j]
	return a.lerp(b, f - float(int(f)))


func _carts(p: Player, dt: float) -> void:
	var id := p.get_instance_id()
	var cd := float(_cart_cd.get(id, 0.0)) - dt
	_cart_cd[id] = maxf(cd, 0.0)
	if cd > 0.0:
		return
	if host == null:
		return
	for n in _cart_nodes:
		var cart := n as Node3D
		if cart == null or not is_instance_valid(cart):
			continue
		if cart.global_position.distance_to(p.global_position) > CART_REACH:
			continue
		p.hurt_health(p.health.max_value() * CART_HIT)
		_cart_cd[id] = CART_IGNORE
		var ahead: Vector3 = cart.get_meta(&"ahead", cart.global_position + Vector3(1, 0, 0))
		var push := ahead - cart.global_position
		push.y = 0.0
		if push.length() > 0.05:
			p.global_position += push.normalized() * 1.2
			p.velocity = push.normalized() * 4.0
		return
