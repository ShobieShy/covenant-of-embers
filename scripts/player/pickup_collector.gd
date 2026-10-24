class_name PickupCollector
extends RefCounted
## Picking loot up (BUILD_PLAN step 23). Two paths, both run from Player.tick():
##  * Walk-over auto-collect (PLAN §4 "ammo and tallies auto-collect" -> Magewar: mana orbs,
##    potions, Arcane Dust): any auto LootPickup within AUTO_RADIUS of the feet (XZ, plus a
##    1.8 m height band). Mana orbs wait while mana is full; potions fill the quick-slot and
##    the rest stays on the ground; dust always goes in.
##  * Interact (F) on an item pickup: the one closest to the look ray within REACH of the eye
##    and inside LOOK_CONE goes into the Inventory; a full backpack refuses with a hint.
## `focused` is the item pickup the player is looking at (the HUD compare card, step 31).
## Distance checks over the loot_pickups group, no physics query: deterministic in tests.

signal collected(pickup: LootPickup, what: String)

const AUTO_RADIUS := 1.2
const REACH := 3.0
const LOOK_CONE_DEG := 12.0
const HINT_FULL := "Inventory full."

var focused: LootPickup
var auto_collected := 0
var items_picked := 0
var refused_full := 0

func tick(p: Player, interact_pressed: bool) -> void:
	if not p.is_inside_tree():
		return
	var all := p.get_tree().get_nodes_in_group(LootPickup.GROUP)
	var feet := p.global_position
	for n in all:
		var lp := n as LootPickup
		if lp == null or lp.is_queued_for_deletion() or not lp.is_auto():
			continue
		var d := lp.global_position - feet
		if Vector2(d.x, d.z).length() <= AUTO_RADIUS and d.y > -0.5 and d.y < 1.8:
			_auto(p, lp)
	focused = look_target(p, all)
	if interact_pressed and focused != null:
		pick(p, focused)

func look_target(p: Player, all: Array = []) -> LootPickup:
	if all.is_empty() and p.is_inside_tree():
		all = p.get_tree().get_nodes_in_group(LootPickup.GROUP)
	var eye := p.eye_position()
	var dir := p.look_direction().normalized()
	var best: LootPickup = null
	var best_cos := cos(deg_to_rad(LOOK_CONE_DEG))
	for n in all:
		var lp := n as LootPickup
		if lp == null or lp.is_queued_for_deletion() or lp.drop == null:
			continue
		var to := lp.global_position + Vector3(0, LootPickup.GEM_SIZE * 0.5, 0) - eye
		var dist := to.length()
		if dist > REACH or dist < 1e-4:
			continue
		var c := dir.dot(to / dist)
		if c >= best_cos:
			best_cos = c
			best = lp
	return best

## Puts an item pickup in the backpack. False (pickup stays) when the backpack is full.
func pick(p: Player, lp: LootPickup) -> bool:
	if lp == null or lp.drop == null or lp.is_queued_for_deletion():
		return false
	if not p.inventory.add(lp.drop.item):
		refused_full += 1
		p.show_hint(HINT_FULL)
		return false
	items_picked += 1
	collected.emit(lp, "item")
	_consume(lp)
	return true

func _auto(p: Player, lp: LootPickup) -> void:
	match lp.auto:
		LootPickup.Auto.MANA:
			if p.mana.value >= p.mana.max_value():
				return
			p.mana.restore(lp.amount)
			_done(lp, "mana")
		LootPickup.Auto.DUST:
			p.inventory.add_dust(lp.amount)
			_done(lp, "dust")
		LootPickup.Auto.POTION:
			var took := p.equipment.add_potions(lp.potion, lp.amount)
			if took <= 0:
				return
			lp.amount -= took
			auto_collected += 1
			collected.emit(lp, "potion")
			if lp.amount <= 0:
				_consume(lp)
			elif lp.label:
				lp.label.text = "%s x%d" % [lp.potion.display_name, lp.amount]

func _done(lp: LootPickup, what: String) -> void:
	auto_collected += 1
	collected.emit(lp, what)
	_consume(lp)

func _consume(lp: LootPickup) -> void:
	lp.remove_from_group(LootPickup.GROUP)
	if lp.get_parent():
		lp.get_parent().remove_child(lp)
	lp.queue_free()
