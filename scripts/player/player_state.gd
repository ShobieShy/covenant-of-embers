class_name PlayerState
extends RefCounted
## Helpers extracted from scripts/player/player.gd so that file stays under the line limit.
## Behavior is unchanged; the original type keeps the same methods.


static func _on_died(h: Player) -> void:
	h.deaths += 1
	h.respawn_left = h.tuning.respawn_delay
	h.slide_left = 0.0
	h.sprinting = false
	h.velocity = Vector3.ZERO
	h.direction = Vector3.ZERO
	h.downed = true
	h.downed_left = h.last_stand if h.last_stand > 0.0 else h.SECOND_WIND_S
	h.downed_changed.emit(h, true)
	h.died.emit(h)


## Back at the last spawn point, full health/shield, mana and Breath refilled (equipment
## and level bonuses kept), focus and slide dropped. (Jolt: ray queries see the moved
## body only after the next physics step.)
static func respawn(h: Player) -> void:
	h.clear_blight_status()
	h.health.refill()
	h.mana.refill()
	h.breath.refill()
	h.respawn_left = 0.0
	h.slide_left = 0.0
	h.sprinting = false
	h._air_tuck = false
	h._tuck_rise = 0.0
	h._crouched_jump = false
	h._set_crouched(false)
	h.spawn(h.spawn_feet, h.spawn_yaw)
	h.respawns += 1
	h.protection_left = h.tuning.respawn_protection
	h.respawned.emit(h)


## Step 80: back up where you fell with `fraction` of max health (no shield), briefly
## protected. False unless downed.
static func revive(h: Player, fraction := 0.3) -> bool:
	if not h.downed:
		return false
	h.downed = false
	h.downed_left = 0.0
	h.health.refill()
	h.health.value = maxf(1.0, h.health.max_value() * clampf(fraction, 0.01, 1.0))
	h.health.shield = 0.0
	h.respawn_left = 0.0
	h.protection_left = h.tuning.respawn_protection
	h.revives += 1
	h.downed_changed.emit(h, false)
	h.respawned.emit(h)
	return true


## Step 80: the last stand ran out; the normal respawn countdown starts.
static func bleed_out(h: Player) -> void:
	if not h.downed:
		return
	h.downed = false
	h.downed_left = 0.0
	h.bleed_outs += 1
	h.respawn_left = h.tuning.respawn_delay
	h.downed_changed.emit(h, false)


## Step 24: equips a backpack item (staff/wand into its loadout slot, gear into its
## equipment slot); whatever it replaces goes back into the backpack in its place.
## Parts can't be equipped (they go to the Assembly Station). False = refused.
static func equip_from_inventory(h: Player, item: Resource) -> bool:
	if item == null or not h.inventory.has(item):
		return false
	var old: Resource = null
	if item is WieldableInstance:
		var slot := h.loadout.slot_for_incoming(item)
		old = h.loadout.wieldable(slot)
		h.inventory.remove(item)
		h.equip_in(slot, item)
	elif item is EquipmentItem:
		h.inventory.remove(item)
		old = h.equip_item(item)
	else:
		return false
	if old != null:
		h.inventory.add(old)
	return true


## Step 24: moves the staff/wand in loadout `slot` to the backpack; false when empty/full.
static func unequip_wieldable_to_inventory(h: Player, slot: int) -> bool:
	var w := h.loadout.wieldable(slot)
	if w == null or h.inventory.is_full():
		if w != null:
			h.show_hint(PickupCollector.HINT_FULL)
		return false
	h.loadout.unequip(slot)
	if h.viewmodel != null:
		h.viewmodel.show_wieldable(h.caster.wieldable)
	return h.inventory.add(w)


## Step 24: moves the worn piece in equipment `slot` to the backpack; false when empty/full.
## t74u: see ItemTrash (quest items refused, worn gear must be unequipped first).
static func trash_item(h: Player, item: Variant, count: int = 1) -> String:
	return ItemTrash.trash(h, item, count)


static func unequip_item_to_inventory(h: Player, slot: int) -> bool:
	var it := h.equipment.item(slot)
	if it == null or h.inventory.is_full():
		if it != null:
			h.show_hint(PickupCollector.HINT_FULL)
		return false
	h.unequip_item(slot)
	return h.inventory.add(it)


## Pushes the worn totals (+ level parts) into the pools, speed, resists and casters.
## Max raises add the difference (Health/Mana; Breath doesn't refill), removals clamp.
static func apply_bonuses(h: Player) -> void:
	var sk := h.skills.totals()  # step 71: skill ranks stack on top of gear + levels
	var arch := Archetype.perks(h.archetype)  # step 73: the archetype perk stacks the same way
	for k in arch:
		sk[k] = float(sk.get(k, 0.0)) + float(arch[k])
	if h.health != null:
		h.health.set_max_bonus(h.equipment.health_bonus() + h.level_health_bonus + float(sk.get("max_health", 0.0)))
	if h.mana != null:
		h.mana.set_max_bonus(h.equipment.mana_bonus() + h.level_mana_bonus + float(sk.get("max_mana", 0.0)))
		h.mana.set_regen_bonus(h.equipment.mana_regen_bonus() + float(sk.get("mana_regen", 0.0)))
	if h.breath != null:
		h.breath.set_max_bonus(h.equipment.stamina_bonus() + h.level_breath_bonus + float(sk.get("max_breath", 0.0)))
	h.set_speed_multiplier(h.equipment.speed_multiplier() * (1.0 + float(sk.get("speed_pct", 0.0)) / 100.0))
	var res := h.equipment.resistances()
	for e in ElementTable.COUNT:
		h.damage_target.resist[e] = res[e] + float(sk.get("resist_all", 0.0)) / 100.0  # capped in Damage
	var dmg := h.equipment.spell_damage_bonus() + float(sk.get("spell_damage", 0.0))
	for c in h.loadout.casters:
		c.damage_bonus = dmg
		c.skills = h.skills  # step 145: element-tree mods
		c.owner_node = h
	h.consecrations.apply(h)
	h.skill_procs.bind(h)


## Second Wind: a slow crawl. No jump, sprint, slide, or dash.
static func _tick_crawl(h: Player, input: PlayerInput) -> void:
	var wish := h.forward_for(h.yaw) * input.move_forward() + h.right_for(h.yaw) * input.move_right()
	if wish.length_squared() < 1e-12:
		return
	h.velocity = wish.normalized() * h.CRAWL_SPEED
	h.move_and_slide()


static func _bind_second_wind(h: Player) -> void:
	if h._second_wind_bound:
		return
	h._second_wind_bound = true
	GameEvents.bus().enemy_killed.connect(h._on_second_wind_kill)


static func _on_second_wind_kill(h: Player, _enemy: Enemy, _element: ElementTable.Element) -> void:
	if not h.downed:
		return
	if revive(h, h.SECOND_WIND_HEALTH):
		h.second_wind_revives += 1
		h.show_hint("Second Wind!")


## Weapons, mana, focus, and the cast. `allow_potion` is false while downed: a drink
## would be spent on a pool that refuses heals until you are up.
static func _tick_combat(h: Player, input: PlayerInput, dt: float, allow_potion: bool) -> void:
	# Loadout: slot_1..slot_4 and the wheel start a 0.4 s draw; holstered slots keep cooling.
	var started := false
	var slot_keys: Array[StringName] = [&"slot_1", &"slot_2", &"slot_3", &"slot_4"]
	var picked := false
	for i in slot_keys.size():
		if input.was_pressed(slot_keys[i]):
			started = h.loadout.select(i)
			picked = true
			break
	if not picked and input.was_pressed(&"quickslot_next_wieldable"):
		started = h.loadout.cycle(1)
	elif not picked and input.was_pressed(&"quickslot_prev_wieldable"):
		started = h.loadout.cycle(-1)
	h.loadout.tick(dt, started)
	if allow_potion and input.was_pressed(&"use_potion"):  # step 24 (H since step 136)
		h.use_potion()
	# Pickups (step 23): walk-over auto-collect, then Interact on the looked-at item.
	h.pickups.tick(h, input.was_pressed(&"interact"), dt)
	# Mana regen (step 8) before the cast, so a pool back at the cost casts this tick.
	h.mana.tick(dt)
	# Focus (step 9): action_secondary held with a wieldable; costs no mana. A swap while
	# focused retargets to the drawn slot's type FOV.
	h.focus.tick(input.down(&"action_secondary"), h.caster.wieldable, dt)
	h.camera.fov = h.focus.fov + h.feel.fov_kick
	# Casting (step 7): semi-auto on the press, from where the eye is after this tick.
	# Spread (step 9): bloom decays, a press that wants to cast is spread inside the cone;
	# bloom grows only on a real cast (not on a cooldown/mana refusal).
	h.spread.tick(dt)
	var fire_pressed := input.was_pressed(&"action_primary")
	var fire_held := input.down(&"action_primary")
	var w := h.caster.wieldable
	if h.loadout.swapping():  # drawing: no cast attempt at all (Cogito is_changing_wieldables)
		h.loadout.tick_swap(fire_pressed, dt)
	else:
		var a := h.aim()
		if w != null and h.caster.wants_aim(fire_pressed, fire_held):
			a = h.spread.apply(a, minf(100.0, w.accuracy() + h.caster.accuracy_bonus()), h.spread_stance())
		if h.viewmodel != null and w != null and h.viewmodel.is_inside_tree():
			h.viewmodel.update_pose(w, h.focus.amount(), h.loadout.draw_progress(), h.feel.recoil_offset())
			a.with_visual_origin(h.viewmodel.cast_point_position())
		if input.was_pressed(&"reload") and w != null:  # step 136: R = the brand's vent action
			h.caster.reload(a, h.bolts)
		if h.caster.tick(fire_pressed, fire_held, dt, a, h.bolts):
			h.spread.on_cast(h.caster.bloom_mult())
			var is_wand := w.type() == WieldableDef.Type.WAND
			h.feel.add_recoil(h.tuning.recoil_wand if is_wand else h.tuning.recoil_staff)
			h.feel.add_shake(h.tuning.shake_wand if is_wand else h.tuning.shake_staff)
			if h.viewmodel != null:
				h.viewmodel.flash_muzzle()  # P5 (M5)
	if h.viewmodel != null:
		h.viewmodel.tick_flare(dt)
		h.viewmodel.update_pose(h.caster.wieldable, h.focus.amount(), h.loadout.draw_progress(), h.feel.recoil_offset())
		h.viewmodel.update_brand(h.caster.fire_mode())


## Source-style crouch jump: shrink from the bottom. The crouched capsule moves up
## so its top stays where the standing head was and the feet rise by the difference
## (1.0 m with the shipped tuning). A low ceiling stops the rise early.
static func _begin_air_tuck(h: Player) -> void:
	var rise := h.tuning.standing_height - h.tuning.crouching_height
	h._set_crouched(true)
	var motion := Vector3(0.0, rise, 0.0)
	var col := KinematicCollision3D.new()
	if h.test_move(h.global_transform, motion, col):
		motion = col.get_travel()
	if motion.y < 0.02:
		h._set_crouched(false)
		return
	h.global_position.y += motion.y
	h.eye_height = maxf(h.tuning.crouching_eye, h.eye_height - motion.y)
	h._tuck_rise = motion.y
	h._air_tuck = true


## Drop the tucked feet and stand. Refuses when the standing capsule would intersect
## the world (a ledge under the feet, or a ceiling the head would grow into).
static func _try_release_tuck(h: Player) -> void:
	if not h._air_tuck:
		return
	var drop := h._tuck_rise
	if drop <= 0.01:
		h._air_tuck = false
		h._tuck_rise = 0.0
		return
	if not _stand_fits(h, h.global_position + Vector3(0.0, -drop, 0.0)):
		return
	h.global_position.y -= drop
	h.eye_height += drop
	h._tuck_rise = 0.0
	h._air_tuck = false
	h._set_crouched(false)


## The full standing capsule at `feet` is clear of the world.
static func _stand_fits(h: Player, feet: Vector3) -> bool:
	var probe := CapsuleShape3D.new()
	probe.radius = h.tuning.radius - 0.02
	probe.height = h.tuning.standing_height
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3(0.0, h.tuning.standing_height * 0.5, 0.0))
	q.collision_mask = h.collision_mask
	q.exclude = [h.get_rid()]
	return h.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## The part of the standing capsule above the crouched one (slightly thinner so touching
## walls don't count) must be free.
static func _can_stand(h: Player) -> bool:
	var probe := CapsuleShape3D.new()
	probe.radius = h.tuning.radius - 0.01
	var lo := h.tuning.crouching_height - h.tuning.radius  # bottom of the extra part (sphere centre)
	probe.height = h.tuning.standing_height - lo
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.transform = Transform3D(Basis.IDENTITY, h.global_position + Vector3(0.0, lo + probe.height * 0.5, 0.0))
	q.collision_mask = h.collision_mask
	q.exclude = [h.get_rid()]
	return h.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## Step climbing (reinterprets Cogito's step_check): if this tick's horizontal motion hits
## a wall, probe up by step_height (+2 cm), forward until the capsule's bottom sphere is
## past the edge (contact travel + radius + 5 cm), then down; a walkable top at most
## step_height above the feet places the body on it (true = moved this tick).
## The lift goes to last_step_rise; tick() hands it to the camera feel (step 5).
static func _try_step_up(h: Player, motion: Vector3) -> bool:
	if motion.length_squared() < 1e-10:
		return false
	var col := KinematicCollision3D.new()
	if not h.test_move(h.global_transform, motion, col):
		return false
	var min_floor_y := cos(h.floor_max_angle) - 1e-4
	if col.get_normal().y >= min_floor_y:
		return false  # a walkable slope: move_and_slide handles it
	var t := h.global_transform
	var up := Vector3(0.0, h.tuning.step_height + 0.02, 0.0)
	var c := KinematicCollision3D.new()
	if h.test_move(t, up, c):
		up = c.get_travel()
	t.origin += up
	var fwd := motion.normalized() * maxf(motion.length(), col.get_travel().length() + h.tuning.radius + 0.05)
	if h.test_move(t, fwd, c):
		return false  # still blocked when raised: a wall, not a step
	t.origin += fwd
	if not h.test_move(t, Vector3(0.0, -(up.y + 0.05), 0.0), c):
		return false  # nothing below: an edge, not a step
	if c.get_normal().y < min_floor_y:
		return false
	t.origin += c.get_travel()
	var rise := t.origin.y - h.global_position.y
	if rise <= 0.01 or rise > h.tuning.step_height + 0.005:
		return false
	h.global_transform = t
	h.last_step_rise = rise
	h.steps_climbed += 1
	return true
