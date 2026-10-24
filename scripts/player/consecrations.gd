class_name Consecrations
extends RefCounted
## Consecrations (BUILD_PLAN step 36; PLAN §31.4, our anointment analogue): a conditional
## bonus tied to a game verb, carried by an EquipmentItem's `consecration` id. The worn set
## is re-read by apply() from Player.apply_bonuses() (never one-off +=/-=), so removing the
## piece removes the effect. tick() runs each player tick for the verb-driven ones.
##  - fleetfoot  "Sandals": +1 dash charge (Dash.set_bonus_charges; PLAN §30.8).
##  - kindling   after a dash, the next cast deals +KINDLING_BONUS.
##  - bulwark    while the shield is full, each cast deals +BULWARK_BONUS.
##  - reaping    each kill restores REAPING_MANA mana.
## Numbers are plan design (Magewar has no anointments). Rolled onto Rare+ vault/boss
## equipment (VaultChest, CONSECRATE_CHANCE); unlocks per PLAN after the first Breach warden.

const KINDLING_BONUS := 10.0
const BULWARK_BONUS := 5.0
const REAPING_MANA := 10.0
const DEFS := {
	"fleetfoot": "+1 dash charge",
	"kindling": "After a dash, your next spell deals +10 damage",
	"bulwark": "While your shield is full, spells deal +5 damage",
	"reaping": "Kills restore 10 mana",
}
const IDS: PackedStringArray = ["fleetfoot", "kindling", "bulwark", "reaping"]

var active: PackedStringArray = []
var kindling_armed := false
var kindling_procs := 0
var reaping_procs := 0
var _last_dashes := -1
var _player: WeakRef
var _bound := false


static func describe(id: String) -> String:
	return DEFS.get(id, "")


static func roll(rng: RandomNumberGenerator) -> String:
	return IDS[rng.randi_range(0, IDS.size() - 1)]


func has(id: String) -> bool:
	return active.has(id)


## Recomputed from the worn set (Player.apply_bonuses).
func apply(p: Player) -> void:
	_player = weakref(p)
	active = PackedStringArray()
	for it in p.equipment.worn():
		if it != null and DEFS.has(it.consecration) and not active.has(it.consecration):
			active.append(it.consecration)
	if p.dash != null:
		p.dash.set_bonus_charges(1 if has("fleetfoot") else 0)
	if not has("kindling"):
		kindling_armed = false
	if not _bound:
		_bound = true
		GameEvents.bus().enemy_killed.connect(_on_killed)
	_push(p)


func tick(p: Player) -> void:
	if p.dash != null:
		if _last_dashes >= 0 and p.dash.dashes > _last_dashes and has("kindling"):
			kindling_armed = true
			kindling_procs += 1
		_last_dashes = p.dash.dashes
	_push(p)


func _push(p: Player) -> void:
	var cond := (
		BULWARK_BONUS if has("bulwark") and p.health != null and p.health.shield >= p.health.shield_max - 1e-6 else 0.0
	)
	for c in p.loadout.casters:
		c.conditional_bonus = cond
		if kindling_armed:
			c.next_cast_bonus = KINDLING_BONUS
	if kindling_armed:
		kindling_armed = false


func _on_killed(_enemy: Enemy, _element: ElementTable.Element) -> void:
	var p: Player = _player.get_ref() if _player else null
	if p == null or not has("reaping") or not p.alive() or p.mana == null:
		return
	p.mana.restore(REAPING_MANA)
	reaping_procs += 1
