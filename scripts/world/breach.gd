class_name Breach
extends Node
## Breach room logic (BUILD_PLAN step 34/35): watches EventBus.enemy_killed for the boss
## (by def id, since the spawner frees dead wave enemies) and then opens the vault door
## (the level's "Boxes/vault_door": hidden, collision off). `vault_opened` fires once.

signal vault_opened()

const BOSS_ID := "breach_warden"
const DOOR := "Boxes/vault_door"

var level: Node3D
var open := false
var boss_kills := 0

func setup(lv: Node3D) -> void:
	level = lv
	GameEvents.bus().enemy_killed.connect(_on_killed)

func _exit_tree() -> void:
	if GameEvents.bus().enemy_killed.is_connected(_on_killed):
		GameEvents.bus().enemy_killed.disconnect(_on_killed)

func door() -> StaticBody3D:
	return level.get_node_or_null(DOOR) as StaticBody3D if level else null

func _on_killed(enemy: Enemy, _element: ElementTable.Element) -> void:
	if enemy == null or enemy.def == null or enemy.def.id != BOSS_ID:
		return
	boss_kills += 1
	open_vault()

func open_vault() -> void:
	if open:
		return
	open = true
	var d := door()
	if d:
		d.visible = false
		d.collision_layer = 0
		d.collision_mask = 0
		d.process_mode = Node.PROCESS_MODE_DISABLED
	vault_opened.emit()
