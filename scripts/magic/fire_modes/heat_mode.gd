class_name HeatMode
extends FireMode
## Pyrowning Arms (step 137, BRANDS_PLAN §3): no mana per cast; each cast adds heat. Heat
## decays after `vent_delay` without a cast; at 100 % the staff overheats and is locked
## for `overheat_seconds` (Q4: lockout only, no self-burn; Q3: no mana at all). R vents:
## dumps the heat over `vent_seconds` (no casting meanwhile). Holding repeats.
## Wands (Q46): the cooldown cut and heat per cast scale toward neutral by wand_scale.
## t69u crystal reload: casts and held fire never cost or need mana. Each overheat and each
## R vent is a "crystal reload" (the core is ejected and re-crystallizes over the lockout /
## vent time): it takes `reload_mana_frac` (0.5) of MAX mana, or whatever is left, and always
## finishes. Wands scale the fraction toward 0 by wand_scale. Emits &"crystal_reload"
## (value = its length in seconds); fx_progress() drives BrandFX's crystal animation.

var heat := 0.0  ## 0..1
var overheated := false
var venting := false
var lock_left := 0.0
var since_cast := 99.0
const HOT_HEAT := 0.7  ## step 146: Red Line threshold
const CRYSTAL_FLOOR := 0.35  ## step 146: Efficient Crystal floor (of max mana)
var reload_len := 0.0  ## t69u: seconds of the crystal reload in progress
var reload_left := 0.0
var crystal_reloads := 0
var mana_drained := 0.0  ## total taken by crystal reloads (tests)


func id() -> StringName:
	return &"heat"


func wants_cast(pressed: bool, held: bool, _released: bool) -> bool:
	return pressed or held


func is_locked() -> bool:
	return overheated or venting


func cost_mult() -> float:
	return 0.0


func cooldown_mult() -> float:
	return param("cooldown_mult", 1.0)


func damage_mult() -> float:
	var hot := skill_mult("hot_damage_pct") if heat >= HOT_HEAT else 1.0
	return param("damage_mult", 1.0) * hot


## Step 146 (Kindling Craft): lockout and vent times, heat per cast and decay with skills.
func _overheat_s() -> float:
	return raw("overheat_seconds", 2.0) * skill_mult("vent_pct", 0.3)


func _vent_s() -> float:
	return raw("vent_seconds", 1.0) * skill_mult("vent_pct", 0.3)


## Crystal reload fraction of max mana; skills lower it but never under CRYSTAL_FLOOR.
func crystal_fraction() -> float:
	var base := param("reload_mana_frac", 0.0)
	return maxf(minf(base, CRYSTAL_FLOOR), base * skill_mult("crystal_cost_pct"))


func after_cast() -> void:
	since_cast = 0.0
	heat = minf(1.0, heat + param("heat_per_cast", 0.0) * skill_mult("heat_pct", 0.3))
	emit(&"heat", heat)
	if heat >= 1.0 - 1e-9:
		overheated = true
		lock_left = _overheat_s()
		emit(&"overheated", 1.0)
		_crystal_reload(lock_left)


func tick(dt: float, _held: bool, _pressed: bool, _in_hand: bool) -> void:
	since_cast += dt
	reload_left = maxf(0.0, reload_left - dt)
	var before := heat
	if overheated:
		lock_left -= dt
		heat = maxf(0.0, lock_left / maxf(_overheat_s(), 1e-6))
		if lock_left <= 0.0:
			overheated = false
			heat = 0.0
			emit(&"vented", 0.0)
	elif venting:
		heat = maxf(0.0, heat - dt / maxf(_vent_s(), 1e-6))
		if heat <= 0.0:
			venting = false
			emit(&"vented", 0.0)
	elif since_cast >= raw("vent_delay", 0.4):
		heat = maxf(0.0, heat - raw("heat_decay", 0.6) * skill_mult("heat_decay_pct") * dt)
	if heat != before and not overheated:
		emit(&"heat", heat)


func reload(_out: Array) -> bool:
	if overheated or venting or heat <= 0.0:
		return false
	venting = true
	emit(&"vent", heat)
	_crystal_reload(heat * _vent_s())
	return true


func _crystal_reload(seconds: float) -> void:
	reload_len = maxf(seconds, 1e-3)
	reload_left = reload_len
	crystal_reloads += 1
	mana_drained += drain_mana(crystal_fraction())
	emit(&"crystal_reload", reload_len)


func reload_progress() -> float:
	return clampf(1.0 - reload_left / reload_len, 0.0, 1.0) if reload_left > 0.0 else -1.0


func fx_progress() -> float:
	return reload_progress() if overheated or venting else -1.0


func meter() -> float:
	return heat


func meter_kind() -> StringName:
	return &"heat"


func meter_text() -> String:
	return "OVERHEAT" if overheated else ("VENT" if venting else "")


func fx_bits() -> int:
	return (1 if heat >= 0.6 else 0) | (2 if overheated or venting else 0)
