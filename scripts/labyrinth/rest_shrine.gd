class_name RestShrine
extends Node3D
## Labyrinth L2 (plan section 7): the rest room's shrine. Interact to rest: health, mana
## and Breath refill, deaths on this floor respawn here, and `rested` asks main.gd to save.
## The craft station stands beside it (LabyrinthFloor's WaveSpawns/station).

signal rested(at: Vector3)

var player: Player


func _ready() -> void:
	Interaction.register(self, 1.0, 0.5)
	var c := CSGCylinder3D.new()
	c.radius = 0.6
	c.height = 1.0
	c.position.y = 0.5
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.4, 0.9, 0.5)
	m.emission_enabled = true
	m.emission = Color(0.2, 0.7, 0.3)
	c.material = m
	add_child(c)
	var l := Label3D.new()
	l.text = "Rest shrine  [F]"
	l.position.y = 1.8
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)


func interact_prompt() -> String:
	return "[F] Rest"


func rest(p: Player) -> void:
	if p:
		p.health.refill()
		p.mana.refill()
		p.breath.refill()
		p.spawn_feet = global_position + Vector3(0, 0, 1.5)
	GameEvents.bus().sfx.emit("shrine_use", global_position)  # 0.3.1 P7
	rested.emit(global_position)


func _unhandled_input(event: InputEvent) -> void:
	if (
		player
		and not player.ui_open
		and event.is_action_pressed(&"interact")
		and Interaction.is_target(player, self)
	):
		rest(player)
		get_viewport().set_input_as_handled()
