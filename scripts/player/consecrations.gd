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
## Numbers are plan design (Magewar has no anointments). Vault and boss chests roll one
## onto Rare+ equipment (VaultChest.CONSECRATE_CHANCE). Ordinary kill drops use
## WORLD_CHANCE, also Rare+ only. IDS is append-only: item codes store the index in 3
## bits (ItemCodes.CONSECRATION_BITS), so there can be at most 7.

const BIAS_CHANCE := 0.5
const WORLD_CHANCE := 0.2  ## tunable: Rare+ equipment from ordinary kill drops
const KINDLING_BONUS := 10.0
const BULWARK_BONUS := 5.0
const REAPING_MANA := 10.0
const STEADY_BONUS := 8.0
const KEEN_CRIT := 0.08
const SIPHON_HEALTH := 8.0
const DEFS := {
	"fleetfoot": "+1 dash charge",
	"kindling": "After a dash, your next spell deals +10 damage",
	"bulwark": "While your shield is full, spells deal +5 damage",
	"reaping": "Kills restore 10 mana",
	"steady": "While focused, spells deal +8 damage",
	"keen": "Spells have +8% crit chance",
	"siphon": "Kills restore 8 health",
}
const IDS: PackedStringArray = ["fleetfoot", "kindling", "bulwark", "reaping", "steady", "keen", "siphon"]

var active: PackedStringArray = []
var kindling_armed := false
var kindling_procs := 0
var reaping_procs := 0
var _last_dashes := -1
var _player: WeakRef
var _bound := false


static func describe(id: String) -> String:
	return DEFS.get(id, "")


## Step 72: `bias` (the wearer's main skill branch consecrations) wins BIAS_CHANCE of rolls.
static func roll(rng: RandomNumberGenerator, bias: PackedStringArray = []) -> String:
	if not bias.is_empty() and rng.randf() < BIAS_CHANCE:
		return bias[rng.randi_range(0, bias.size() - 1)]
	return IDS[rng.randi_range(0, IDS.size() - 1)]


## Rare+ kill drops. Uses a side stream from the item seed, so the kill rng's draw order
## stays the Magewar one. `bias` is the wearer's branch list (empty = uniform).
static func roll_onto(item: EquipmentItem, rarity_id: String, bias: PackedStringArray = []) -> void:
	if item == null or item.roll_seed < 0 or not item.consecration.is_empty():
		return
	if Rarity.parse(rarity_id) < Rarity.Tier.RARE:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = item.roll_seed ^ 0x5EEDC0DE
	if rng.randf() >= WORLD_CHANCE:
		return
	item.consecration = roll(rng, bias)


## The consecrations of p's most-invested skill branch (empty when nothing is spent).
static func bias_for(p: Player) -> PackedStringArray:
	var out := PackedStringArray()
	if p == null or p.skills.tree == null:
		return out
	var b := p.skills.tree.branch(p.skills.main_branch())
	for c in b.get("consecrations", []):
		out.append(String(c))
	return out


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
	var cond := 0.0
	if has("bulwark") and p.health != null and p.health.shield >= p.health.shield_max - 1e-6:
		cond += BULWARK_BONUS
	if has("steady") and p.focus != null and p.focus.focused:
		cond += STEADY_BONUS
	var crit := KEEN_CRIT if has("keen") else 0.0
	for c in p.loadout.casters:
		c.conditional_bonus = cond
		c.crit_chance_bonus = crit
		if kindling_armed:
			c.next_cast_bonus = KINDLING_BONUS
	if kindling_armed:
		kindling_armed = false


func _on_killed(_enemy: Enemy, _element: ElementTable.Element) -> void:
	var p: Player = _player.get_ref() if _player else null
	if p == null or not p.alive():
		return
	if has("reaping") and p.mana != null:
		p.mana.restore(REAPING_MANA)
		reaping_procs += 1
	if has("siphon") and p.health != null:
		p.health.heal(SIPHON_HEALTH)
