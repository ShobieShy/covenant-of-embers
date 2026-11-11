class_name Loadout
extends RefCounted
## Staff + wand slots (BUILD_PLAN step 10, port of the archived C++ game/magic/loadout.*,
## old step 21; PLAN §30.1). Weapon system = Magewar design: a staff and a wand are both
## wieldables (StaffWieldableItem.StaffType STAFF/WAND) put into quickslots and drawn with
## quickslot_1/2 or cycled with quickslot_prev/next_wieldable (mouse wheel); only the drawn
## one casts (Cogito PlayerInteractionComponent blocks action_primary/secondary while
## is_changing_wieldables).
##  * Four slots. Slot.STAFF holds the staff, Slot.WAND the wand (equip() still picks that
##    slot by type). Slot.CARRY_3 and Slot.CARRY_4 hold any extra staff or wand (keys 3
##    and 4). equip() does not fill those; slot_for_incoming() does, from the backpack.
##  * Each slot owns a Caster, so each keeps its own cooldown (Caster.cooldown_left), which
##    keeps counting while holstered (cool()): swapping never resets or pauses it.
##    Reinterpreted: Magewar frees the wieldable node on a swap, so its _fire_timer
##    restarts at 0 and swap-cancel skips the cooldown; ours can't be exploited that way.
##  * select(slot) starts a swap_seconds (0.4 s) draw: the tick of the press and the next
##    23 ticks (60 Hz) cast nothing; the first cast can happen 24 ticks after the press
##    (counts down before the press check, like Caster's cooldown). Magewar's equip/unequip
##    animations are 0.001 s placeholders (Cogito waits for their length), so its swap is
##    effectively instant; 0.4 s is our (PLAN) number. Selecting during a swap retargets
##    and restarts the draw; selecting the slot in hand, or an empty slot, does nothing.
##    Step 17: the draw is shortened by the drawn wieldable's handling
##    (WieldableInstance.draw_seconds: 0.4 x 100 / (100 + handling), >= 0.2 s).
##  * Mana, focus and spread are the player's (shared by both slots; Player wires every
##    slot's mana_spender/out_of_mana). A press during a swap is not a cast attempt: no
##    mana check, no "Not enough mana!" cue, no spread draw, no bloom (counted in
##    swap_blocked).

enum Slot { STAFF, WAND, CARRY_3, CARRY_4 }

const SLOT_COUNT := 4

signal swap_started(slot: int)

var casters: Array[Caster] = [Caster.new(), Caster.new(), Caster.new(), Caster.new()]
var active: int = Slot.STAFF
var swap_seconds := 0.4
var swap_left := 0.0  ## seconds left on the current draw (0 = ready)
var draw_seconds := 0.4  ## length of the current/last draw (handling-adjusted, step 17)
var swaps := 0
var swap_blocked := 0  ## fire presses refused because a swap was running


static func from_tuning(t: PlayerTuning) -> Loadout:
	var l := Loadout.new()
	l.swap_seconds = t.swap_seconds
	return l


static func slot_for(w: WieldableInstance) -> int:
	return Slot.WAND if w != null and w.type() == WieldableDef.Type.WAND else Slot.STAFF


## The caster of the slot in hand.
func caster() -> Caster:
	return casters[active]


## The wieldable in `slot` (default: in hand); null = empty.
func wieldable(slot: int = -1) -> WieldableInstance:
	return casters[active if slot < 0 else slot].wieldable


## Puts `w` into the slot of its type (its cooldown is kept). With empty hands the new
## slot is drawn at once (no swap). Returns the slot.
## Replacing the weapon in hand starts a draw of the new one (step 24: inventory
## swaps can't skip the draw).
func equip(w: WieldableInstance) -> int:
	return equip_slot(slot_for(w), w)


## Staff or wand slot when it is empty, otherwise the first empty carry slot, otherwise
## the typed slot (the caller replaces what is there).
func slot_for_incoming(w: WieldableInstance) -> int:
	var typed := slot_for(w)
	if w == null or casters[typed].wieldable == null:
		return typed
	for s in range(Slot.CARRY_3, casters.size()):
		if casters[s].wieldable == null:
			return s
	return typed


## Puts `w` in `slot` whatever its type is. Same draw rules as equip().
func equip_slot(slot: int, w: WieldableInstance) -> int:
	if slot < 0 or slot >= casters.size():
		return -1
	var replacing_in_hand := (
		slot == active and casters[slot].wieldable != null and w != null and casters[slot].wieldable != w
	)
	casters[slot].equip(w)
	if replacing_in_hand:
		draw_seconds = w.draw_seconds(swap_seconds)
		swap_left = draw_seconds
		swaps += 1
		swap_started.emit(slot)
	if casters[active].wieldable == null and w != null:
		active = slot
		swap_left = 0.0
	return slot


## Empties `slot`.
func unequip(slot: int) -> void:
	casters[slot].equip(null)


func swapping() -> bool:
	return swap_left > 0.0


## Draws `slot`: false if it is already in hand (or being drawn) or empty.
func select(slot: int) -> bool:
	if slot < 0 or slot >= casters.size() or slot == active or casters[slot].wieldable == null:
		return false
	active = slot
	draw_seconds = casters[slot].wieldable.draw_seconds(swap_seconds)
	swap_left = draw_seconds
	swaps += 1
	swap_started.emit(slot)
	return true


## Mouse wheel (Magewar quickslot_prev/next_wieldable): the next non-empty slot in `dir`.
func cycle(dir: int) -> bool:
	var n := casters.size()
	for i in range(1, n):
		var s := posmod(active + dir * i, n)
		if casters[s].wieldable != null:
			return select(s)
	return false


## 0 at the start of a draw .. 1 when ready (viewmodel raise).
func draw_progress() -> float:
	return 1.0 - swap_left / draw_seconds if draw_seconds > 0.0 else 1.0


## One tick for everything but the cast: holstered slots cool down; a running swap counts
## down unless it started this tick (`started_now`). The slot in hand is cooled by its
## Caster.tick (ready) or by cool() inside tick_swap (swapping).
func tick(dt: float, started_now: bool) -> void:
	for i in casters.size():
		if i != active:
			casters[i].cool(dt)
	if swapping() and not started_now:
		swap_left = maxf(0.0, swap_left - dt)
		if swap_left < 1e-9:
			swap_left = 0.0


## The drawn slot during a swap: its cooldown keeps running, a press is refused.
func tick_swap(pressed: bool, dt: float) -> void:
	casters[active].cool(dt)
	if pressed:
		swap_blocked += 1
