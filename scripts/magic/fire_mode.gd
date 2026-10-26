class_name FireMode
extends RefCounted
## How a Caster turns input into casts (step 136, Phase U B2, docs/BRANDS_PLAN.md §2-3).
## This base class IS the unbranded SemiMode: a press casts (hold repeats only with
## hold_to_repeat), full mana, base cooldown, no modifiers, so an unbranded wieldable casts
## exactly as before (test_fire_modes pins it). Brand modes (fire_modes/*.gd) override:
##   wants_cast()   which input edge asks for a cast (press, hold, release)
##   is_locked()    refuses casts for a while (overheat, empty pool)
##   cost_mult()    x WieldableInstance.mana_cost() (0 = no mana)
##   cooldown_mult() x WieldableInstance.cooldown() (result still >= 0.1 s, Q45)
##   damage_mult()  x WieldableInstance.damage() before the flat gear bonus (§4)
##   modify(spawn)  speed / blast / chain / crit fields on the bolt
##   after_cast()   heat, charge reset, ramp, burst queue
##   tick()         per-tick state (heat decay, charge build, spin)
##   reload()       the R vent action; may return an extra Spawn (cursed orb)
##   take_due()     follow-up bolts due this tick (burst), cast without a new press
## State lives on the mode (one per Caster = per loadout slot). Events go out through
## Caster.brand_event(kind, value) for HUD/VFX/SFX.

var brand: Brand  ## null = unbranded
var is_wand := false
var _caster: WeakRef  ## the owning Caster (weak: Caster holds the mode)


## The mode for `w`'s brand (null wieldable or unbranded -> plain FireMode = semi).
static func for_wieldable(w: WieldableInstance) -> FireMode:
	var b := w.brand() if w != null else null
	var m: FireMode
	match b.fire_mode if b != null else Brand.Mode.SEMI:
		Brand.Mode.HEAT:
			m = HeatMode.new()
		Brand.Mode.AUTO_SPINUP:
			m = SpinMode.new()
		Brand.Mode.CHARGE:
			m = ChargeMode.new()
		Brand.Mode.EXPLOSIVE:
			m = ExplosiveMode.new()
		_:
			m = FireMode.new()
	m.brand = b
	m.is_wand = w != null and w.is_wand()
	return m


func attach(c: Caster) -> void:
	_caster = weakref(c)


## The owning Caster (reads hold_to_repeat, emits brand_event), or null.
func caster() -> Caster:
	return _caster.get_ref() as Caster if _caster != null else null


func id() -> StringName:
	return &"semi"


## Brand tunable scaled for a wand (Brand.scaled); `neutral` = the unbranded value.
func param(key: String, neutral: float) -> float:
	return brand.scaled(key, neutral, is_wand) if brand != null else neutral


## Raw (unscaled) brand tunable.
func raw(key: String, default: float) -> float:
	return brand.p(key, default) if brand != null else default


func wants_cast(pressed: bool, held: bool, _released: bool) -> bool:
	var c := caster()
	return pressed or (c != null and c.hold_to_repeat and held)


func is_locked() -> bool:
	return false


func cost_mult() -> float:
	return 1.0


func cooldown_mult() -> float:
	return 1.0


func damage_mult() -> float:
	return 1.0


func accuracy_bonus() -> float:
	return 0.0


func bloom_mult() -> float:
	return 1.0


func modify(_s: SpellBolts.Spawn) -> void:
	pass


func after_cast() -> void:
	pass


## Every tick, holstered or not (`in_hand` false = only cooling down).
func tick(_dt: float, _held: bool, _pressed: bool, _in_hand: bool) -> void:
	pass


## Bolts due this tick without a new press (burst follow-ups); consumes them.
func take_due() -> int:
	return 0


func pending() -> bool:
	return false


## The R action. Returns true when it did something; `out` may get an extra bolt.
func reload(_out: Array) -> bool:
	return false


## HUD meter 0..1 (-1 = hidden) and its kind ("heat", "charge", "spin", "burst", "pool").
func meter() -> float:
	return -1.0


func meter_kind() -> StringName:
	return &""


## Short HUD text beside the meter ("VENT", "BURST"...), "" = none.
func meter_text() -> String:
	return ""


## Co-op brand_fx bits (step 142): 1 hot, 2 overheated/venting, 4 charging, 8 spinning.
func fx_bits() -> int:
	return 0


func emit(kind: StringName, value := 0.0) -> void:
	var c := caster()
	if c != null:
		c.brand_event.emit(kind, value)
