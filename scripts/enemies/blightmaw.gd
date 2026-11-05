class_name Blightmaw
extends Heap
## Blightmaw Matriarch (Act II). Three phases by health fraction, so a viewer's combat
## level does not move the thresholds. No phase regenerates and the arena does not lock.
## She stays quiet while the player's feet are more than CROWN_REACH below the Crown.
## Clients do not run this brain (`drives_brain` stays false on a puppet).

signal phase_changed(boss: Blightmaw, phase: int)
signal husk_called(boss: Blightmaw)
signal spore_fired(boss: Blightmaw)

const PHASE_2_AT := 0.66
const PHASE_3_AT := 0.33
const CROWN_REACH := 4.0
const HUSK_PERIOD := 8.0
const SPORE_PERIOD := 3.0

var phase := 1
var drives_brain := true
var arena_locked := false
var regenerated := 0.0
var crown_global_y := 0.0
var husks_called := 0
var spores_fired := 0
var _husk_left := 2.0
var _spore_left := 1.0
var weak_open := false


func is_boss() -> bool:
	return true


func _target_valid() -> bool:
	if _below_crown():
		return false
	return super._target_valid()


func _below_crown() -> bool:
	if crown_global_y == 0.0 or target == null or not is_instance_valid(target):
		return false
	return target.global_position.y < crown_global_y - CROWN_REACH


func think(dt: float) -> void:
	if not drives_brain:
		return
	sync_phase()
	if not _below_crown() and _target_valid():
		_spore_left -= dt
		_husk_left -= dt
		if _spore_left <= 0.0:
			_spore_left = SPORE_PERIOD
			spores_fired += 1
			_play_clip("SporeSpray")
			spore_fired.emit(self)
		if phase >= 1 and _husk_left <= 0.0 and husks_called < 3:
			_husk_left = HUSK_PERIOD
			husks_called += 1
			husk_called.emit(self)
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
	if want > phase:
		phase = want
		if phase == 3:
			_open_weak_point()
		phase_changed.emit(self, phase)
	_apply_phase_meshes()


func _enter_tree() -> void:
	_apply_phase_meshes()


## Phase2_Spines from phase 2. Phase3_Heart from phase 3. Both start hidden.
func _apply_phase_meshes() -> void:
	if model == null:
		return
	for n in model.find_children("*", "Node3D", true, false):
		var nm := String(n.name)
		if nm.contains("Phase2_Spines"):
			(n as Node3D).visible = phase >= 2
		elif nm.contains("Phase3_Heart"):
			(n as Node3D).visible = phase >= 3


func _open_weak_point() -> void:
	weak_open = true
	if head_shape and head_shape.shape is BoxShape3D:
		var grown := (head_shape.shape as BoxShape3D).size * 1.8
		(head_shape.shape as BoxShape3D).size = grown
		if _head_mesh and _head_mesh.mesh is BoxMesh:
			(_head_mesh.mesh as BoxMesh).size = grown
