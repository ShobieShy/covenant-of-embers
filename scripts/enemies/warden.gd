class_name Warden
extends Heap
## The Breach Warden (BUILD_PLAN step 34): a two-phase mini-boss on the Heap's brain.
## Phase 1 = the Heap (slam with a 0.6 s wind-up, seam weak point). When a hit takes it to
## <= PHASE_2_AT of max health it enrages once: phase 2, speeds x ENRAGE_SPEED, slam
## cooldown and wind-up x ENRAGE_TEMPO, a red glow; `phase_changed` fires. reset() returns
## it to phase 1. Its death is announced like any enemy (EventBus.enemy_killed); the Breach
## listens for that, not for the node (the spawner frees dead wave enemies).

signal phase_changed(warden: Warden, phase: int)

const PHASE_2_AT := 0.5
const ENRAGE_SPEED := 1.5
const ENRAGE_TEMPO := 0.6
const ENRAGE_GLOW := Color(1.0, 0.15, 0.1)

var phase := 1
var phase_2_tick := -1


func apply_damage(amount: float, element: ElementTable.Element, announce := true) -> bool:
	var killed := super.apply_damage(amount, element, announce)
	if not dead and phase == 1 and health <= max_health() * PHASE_2_AT:
		_enrage()
	return killed


func _enrage() -> void:
	phase = 2
	phase_2_tick = ticks
	rusher.walk_speed *= ENRAGE_SPEED
	rusher.sprint_speed *= ENRAGE_SPEED
	rusher.attack_cooldown *= ENRAGE_TEMPO
	rusher.attack_windup *= ENRAGE_TEMPO
	if _head_mat != null:
		_head_mat.emission = ENRAGE_GLOW
		_head_mat.emission_energy_multiplier = 3.0
	phase_changed.emit(self, phase)


func reset(xform: Variant = null) -> void:
	super.reset(xform)
	if phase != 1:
		phase = 1
		phase_2_tick = -1
		rusher = def.rusher()
		if _head_mat != null:
			_head_mat.emission = SEAM_GLOW
			_head_mat.emission_energy_multiplier = 1.5
