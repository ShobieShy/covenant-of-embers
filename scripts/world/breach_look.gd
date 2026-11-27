extends Node3D
## Breach crater lighting. The shell mesh and the colliders come from the level;
## these lamps are the violet rift, the ember gallery and the cistern. No gameplay.


func _ready() -> void:
	_lamp(Vector3(0, 7, 125), Color(0.62, 0.22, 1.0), 4.5, 22.0)
	_lamp(Vector3(0, 4, 72), Color(0.48, 0.22, 0.85), 2.4, 16.0)
	_lamp(Vector3(-44, 2.2, 128), Color(1.0, 0.32, 0.06), 2.6, 14.0)
	_lamp(Vector3(-36, 1.6, 136), Color(1.0, 0.45, 0.1), 1.2, 7.0)
	_lamp(Vector3(32, 1.4, 164), Color(0.25, 0.85, 0.4), 3.2, 14.0)
	_lamp(Vector3(-38, 2.0, 154), Color(0.45, 0.28, 0.7), 1.6, 10.0)
	_lamp(Vector3(-34, 2.2, 102), Color(0.5, 0.3, 0.85), 1.8, 10.0)
	_lamp(Vector3(46, 2.0, 144), Color(0.55, 0.35, 0.8), 1.6, 9.0)
	_lamp(Vector3(50, 2.4, 118), Color(0.6, 0.28, 0.95), 2.2, 11.0)
	_lamp(Vector3(42, 2.4, 98), Color(0.5, 0.25, 0.9), 2.0, 10.0)
	_lamp(Vector3(0, 3.2, 170), Color(0.95, 0.62, 0.35), 2.2, 12.0)
	_lamp(Vector3(0, 3.0, 186), Color(0.95, 0.6, 0.32), 1.8, 10.0)
	_lamp(Vector3(-4, 2.4, 184), Color(0.9, 0.55, 0.3), 1.2, 7.0)
	for spot in [Vector3(-52, 3, 150), Vector3(54, 3, 150), Vector3(-48, 3, 90), Vector3(52, 3, 88), Vector3(0, 3, 48)]:
		_lamp(spot, Color(0.55, 0.25, 1.0), 2.4, 11.0)


func _lamp(at: Vector3, color: Color, energy: float, reach: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.position = at
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = reach
	lamp.shadow_enabled = false
	add_child(lamp)
