class_name Forgemaw
extends Heap
## Forgemaw (Act III). Three phases by health fraction. No phase regenerates and
## the arena does not lock. Clients still advance the phase from health, and they
## do not run the attack brain.

signal phase_changed(boss: Forgemaw, phase: int)

const PHASE_2_AT := 0.66
const PHASE_3_AT := 0.33

var phase := 1
var drives_brain := true
var arena_locked := false
var regenerated := 0.0
var weak_open := false


func is_boss() -> bool:
	return true


func think(dt: float) -> void:
	sync_phase()
	if not drives_brain:
		return
	super.think(dt)


func apply_damage(amount: float, element: ElementTable.Element, announce := true, normalised := false) -> bool:
	var killed := super.apply_damage(amount, element, announce, normalised)
	if not dead:
		sync_phase()
	return killed


## Phases only advance. Raising the fraction does not return to an earlier phase.
func sync_phase() -> void:
	var max_hp := max_health()
	var fraction := health / max_hp if max_hp > 0.0 else 1.0
	var want := 1
	if fraction <= PHASE_3_AT:
		want = 3
	elif fraction <= PHASE_2_AT:
		want = 2
	if want <= phase:
		return
	phase = want
	if phase >= 3:
		weak_open = true
	phase_changed.emit(self, phase)
