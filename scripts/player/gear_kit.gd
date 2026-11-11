class_name GearKit
extends RefCounted
## 0.8.7 shield, flask, and relic. The shield replaces Health's capacity, delay, and
## effect. The flask is one charge and never touches the potion slot. The relic is a
## short list applied from scratch on every bonus pass, so taking it off clears it.

const FLASK_HEAL := 20.0
const SPIKE_DAMAGE := 4.0
const EMBER_DAMAGE := 3.0
const WARD_CAPACITY := 15.0
const SIP_HEAL := 4.0

var shield: ShieldDrop
var relic: RelicDrop
var flask := 1
var flasks_used := 0
var _sip_bound := false
var _player: WeakRef


func equip_shield(s: ShieldDrop) -> ShieldDrop:
	var old := shield
	shield = s
	return old


func clear_shield() -> ShieldDrop:
	var old := shield
	shield = null
	return old


func equip_relic(r: RelicDrop) -> RelicDrop:
	var old := relic
	relic = r if r != null and RelicDrop.IDS.has(r.relic_id) else null
	return old


func clear_relic() -> RelicDrop:
	var old := relic
	relic = null
	return old


func flat_damage() -> float:
	if relic != null and relic.relic_id == "ember_chip":
		return EMBER_DAMAGE
	return 0.0


## Writes the worn shield and relic onto `p`. A missing shield restores tuning.
func apply(p: Player) -> void:
	if p.health == null or p.tuning == null:
		return
	var cap := p.tuning.shield_max
	var delay := p.tuning.shield_regen_delay
	var regen := p.tuning.shield_regen_per_sec
	if shield != null:
		cap = shield.capacity
		delay = shield.delay
		if shield.effect == "ward":
			regen *= 1.5
		elif shield.effect == "calm":
			delay = maxf(0.4, delay * 0.5)
	if relic != null and relic.relic_id == "ward_bead":
		cap += WARD_CAPACITY
	var was_full := p.health.shield >= p.health.shield_max - 0.01
	p.health.shield_max = cap
	p.health.shield_regen_delay = delay
	p.health.shield_regen_per_sec = regen
	p.health.shield = cap if was_full else minf(p.health.shield, cap)


func tick(p: Player) -> void:
	if not _sip_bound:
		_sip_bound = true
		_player = weakref(p)
		GameEvents.bus().enemy_killed.connect(_on_kill)
	if shield != null and shield.effect == "spike" and p.health != null and p.health.shield > 0.0:
		for c in p.loadout.casters:
			c.conditional_bonus += SPIKE_DAMAGE


func use_flask(p: Player) -> bool:
	if flask <= 0 or p.health == null or p.health.dead:
		return false
	if p.health.value >= p.health.max_value() - 1e-6:
		return false
	p.health.heal(FLASK_HEAL)
	flask = 0
	flasks_used += 1
	return true


func refill() -> void:
	flask = 1


func to_dict() -> Dictionary:
	var d := {"flask": flask}
	if shield != null:
		d["shield"] = {"capacity": shield.capacity, "delay": shield.delay, "effect": shield.effect}
	if relic != null:
		d["relic"] = relic.relic_id
	return d


func from_dict(d: Dictionary) -> void:
	flask = clampi(int(d.get("flask", 1)), 0, 1)
	shield = null
	relic = null
	if d.has("shield") and d["shield"] is Dictionary:
		var s: Dictionary = d["shield"]
		shield = ShieldDrop.make(
			float(s.get("capacity", 40.0)), float(s.get("delay", 2.0)), String(s.get("effect", "ward"))
		)
	if d.has("relic"):
		relic = RelicDrop.make(String(d["relic"]))


func _on_kill(enemy: Enemy, _element: ElementTable.Element) -> void:
	var p: Player = _player.get_ref() as Player if _player != null else null
	if p == null or relic == null or relic.relic_id != "sip_stone" or p.health == null:
		return
	if enemy == null or not p.alive():
		return
	p.health.heal(SIP_HEAL)
