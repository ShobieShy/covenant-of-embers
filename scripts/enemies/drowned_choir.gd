class_name DrownedChoir
extends Heap
## The Drowned Choir (Act IV). Two phases by health. Surfaced, then submerged.
## The submerged phase is the water rising. No new attack script: the Heap brain stays.

signal phase_changed(boss: DrownedChoir, phase: int)

const PHASE_2_AT := 0.5

var phase := 1
var submerged := false


func is_boss() -> bool:
	return true


func think(dt: float) -> void:
	sync_phase()
	super.think(dt)


func apply_damage(amount: float, element: ElementTable.Element, announce := true, normalised := false) -> bool:
	var killed := super.apply_damage(amount, element, announce, normalised)
	if not dead:
		sync_phase()
	return killed


func sync_phase() -> void:
	var max_hp := max_health()
	var fraction := health / max_hp if max_hp > 0.0 else 1.0
	var next := 2 if fraction <= PHASE_2_AT else 1
	if next == phase:
		return
	phase = next
	submerged = phase == 2
	set_meta(&"submerged", submerged)
	phase_changed.emit(self, phase)
