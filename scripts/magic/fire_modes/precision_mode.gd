class_name PrecisionMode
extends FireMode
## Hexler & Koch (step 139, BRANDS_PLAN §3): precise semi-auto. Accuracy +`accuracy_add`,
## damage x`damage_mult`; a weak-point hit deals an extra x`crit_mult`, any other hit crits
## for x`crit_mult` on a `crit_chance` roll (Q41; MagicEffects.apply_crit). A pool of
## `pool_casts` casts: R, or emptying the pool, throws the spent charge as a cursed orb (a
## Dark bolt bursting for `orb_damage_per_charge` x casts spent x the wieldable damage over
## `orb_radius`, Dark roll once per enemy), then the pool refills over refill_time()
## (no casts meanwhile). Casts still cost mana. Wands (Q46): smaller bonuses and orb.

const ORB_RANGE := 30.0

var spent := 0
var refill_left := 0.0


func id() -> StringName:
	return &"precision"


func pool() -> int:
	return maxi(1, roundi(raw("pool_casts", 6.0)))


func is_locked() -> bool:
	return refill_left > 0.0


func damage_mult() -> float:
	return param("damage_mult", 1.0)


func accuracy_bonus() -> float:
	return param("accuracy_add", 0.0)


func modify(s: SpellBolts.Spawn) -> void:
	s.crit_mult = param("crit_mult", 1.0)
	s.crit_chance = raw("crit_chance", 0.0)


## Step 143: `refill_cooldowns` x the wieldable cooldown, else the flat `refill_seconds`.
func refill_time() -> float:
	if brand != null and brand.params.has("refill_cooldowns"):
		return raw("refill_cooldowns", 3.5) * base_cooldown()
	return raw("refill_seconds", 1.5)


func after_cast() -> void:
	spent += 1
	emit(&"pool", float(pool() - spent))


func auto_reload() -> bool:
	return spent >= pool()


func tick(dt: float, _held: bool, _pressed: bool, _in_hand: bool) -> void:
	if refill_left > 0.0:
		refill_left = maxf(0.0, refill_left - dt)
		if refill_left <= 0.0:
			emit(&"pool", float(pool()))


func reload(out: Array) -> bool:
	if spent <= 0 or refill_left > 0.0:
		return false
	var c := caster()
	var w := c.wieldable if c != null else null
	var s := SpellBolts.Spawn.new()
	s.element = ElementTable.Element.DARK
	s.is_orb = true
	s.damage = param("orb_damage_per_charge", 0.0) * spent * (w.damage() if w != null else 0.0)
	s.damage *= skill_mult("splash_damage_pct")
	s.speed = raw("orb_speed", 18.0)
	s.range_m = ORB_RANGE
	s.blast_radius = param("orb_radius", 0.0) * skill_mult("splash_pct")
	s.blast_falloff = 0.5
	s.blast_fraction = 1.0
	s.dark_bonus = w.dark_chance_bonus() if w != null else 0.0
	out.append(s)
	emit(&"orb_thrown", float(spent))
	spent = 0
	refill_left = refill_time()
	return true


func meter() -> float:
	return 1.0 - refill_left / maxf(refill_time(), 1e-6) if refill_left > 0.0 else float(pool() - spent) / pool()


func meter_kind() -> StringName:
	return &"pool"


func meter_text() -> String:
	return "REFILL" if refill_left > 0.0 else "%d" % (pool() - spent)
