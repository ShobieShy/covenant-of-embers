class_name BossLooks
extends Node
## Shows the phase meshes on a 0.14.0 boss rig. Phase2_* from phase 2, Phase3_* from
## phase 3. The Storm Warden has no phase field; the extra gale follows half health
## and does not change the fight.

var _nodes: Array[Node3D] = []


func _ready() -> void:
	var host := get_parent()
	if host == null:
		return
	for n in host.find_children("*", "Node3D", true, false):
		var nm := String(n.name)
		if "Phase2" in nm or "Phase3" in nm:
			_nodes.append(n)
	_apply()


func _process(_dt: float) -> void:
	_apply()


func _apply() -> void:
	var phase := _phase()
	for n in _nodes:
		var nm := String(n.name)
		if "Phase3" in nm:
			n.visible = phase >= 3
		elif "Phase2" in nm:
			n.visible = phase >= 2


func _phase() -> int:
	var host := _enemy()
	if host == null:
		return 1
	if host.get("phase") != null:
		return int(host.phase)
	if host.def != null and host.def.id == "storm_warden":
		var max_hp := host.max_health()
		if max_hp > 0.0 and host.health <= max_hp * 0.5:
			return 2
	return 1


func _enemy() -> Enemy:
	var n: Node = self
	while n:
		if n is Enemy:
			return n as Enemy
		n = n.get_parent()
	return null
