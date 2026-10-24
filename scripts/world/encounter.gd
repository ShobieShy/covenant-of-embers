class_name Encounter
extends EnemySpawner
## A room encounter (BUILD_PLAN step 47): one level Encounters/<id> node (generated from a
## TOML [[encounter]]) run as a one-wave EnemySpawner: when the player steps within its
## trigger radius it spawns its enemies delay_s later; `waves_completed` = cleared.
## No marker enemies (those belong to the level's main spawner).

var node: Node


func setup_encounter(lvl: Node, p: Player, n: Node, t: EnemyTable = null) -> void:
	level = lvl
	player = p
	node = n
	table = t if t != null else EnemyTable.load_default()
	nav = level.get_node_or_null("Navigation") as LevelNavigation
	_read_waves()


func _read_waves() -> void:
	waves.clear()
	if node == null:
		return
	var origin := (
		(level as Node3D).global_transform
		if level is Node3D and (level as Node3D).is_inside_tree()
		else Transform3D.IDENTITY
	)
	trigger_center = origin * (node.get_meta(&"trigger_center", Vector3.ZERO) as Vector3)
	trigger_radius = float(node.get_meta(&"trigger_radius", 0.0))
	waves.append(
		{
			"id": String(node.name),
			"delay_s": float(node.get_meta(&"delay_s", 0.0)),
			"enemies": node.get_meta(&"enemies", [])
		}
	)


func cleared() -> bool:
	return wave_state == WaveState.DONE


## Restoring a save past this room: never fires.
func mark_cleared() -> void:
	wave_state = WaveState.DONE
