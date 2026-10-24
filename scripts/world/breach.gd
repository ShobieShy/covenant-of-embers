class_name Breach
extends Node
## Breach room logic (BUILD_PLAN step 34/35): watches EventBus.enemy_killed for the boss
## (by def id, since the spawner frees dead wave enemies) and then opens the vault door
## (the level's "Boxes/vault_door": hidden, collision off) and unlocks the VaultChest
## (step 35) it placed at WaveSpawns/vault_chest. `vault_opened` fires once.

signal vault_opened
signal gate_opened  ## step 47: every lever pulled, the switch gate is open

const CHEST_SPAWN := "WaveSpawns/vault_chest"  ## step 35: the VaultChest stands here

const BOSS_ID := "breach_warden"
const DOOR := "Boxes/vault_door"

var level: Node3D
var open := false
var boss_kills := 0
var chest: VaultChest
## Step 47: room encounters (Encounter spawners, children of this node) and the levers.
var encounters: Array[Encounter] = []
var switches: Array[BreachSwitch] = []
var gate_open := false
var player: Player
var _removed: Array[StaticBody3D] = []


func setup(lv: Node3D, p: Player = null, auto_tick := true) -> void:
	level = lv
	player = p
	_setup_rooms(auto_tick)
	chest = VaultChest.new()
	chest.player = p
	chest.name = "VaultChest"
	var at := level.get_node_or_null(CHEST_SPAWN) as Node3D
	level.add_child(chest)
	if at:
		chest.global_transform = at.global_transform
	GameEvents.bus().enemy_killed.connect(_on_killed)


func _exit_tree() -> void:
	if GameEvents.bus().enemy_killed.is_connected(_on_killed):
		GameEvents.bus().enemy_killed.disconnect(_on_killed)


func _setup_rooms(auto_tick: bool) -> void:
	var en := level.get_node_or_null("Encounters")
	if en:
		for n in en.get_children():
			var e := Encounter.new()
			e.name = "Encounter_" + String(n.name)
			e.auto_tick = auto_tick
			add_child(e)
			e.setup_encounter(level, player, n)
			e.waves_completed.connect(_check_rooms)
			encounters.append(e)
	var sw := level.get_node_or_null("Switches")
	if sw:
		for m in sw.get_children():
			var s := BreachSwitch.new()
			s.name = String(m.name)
			s.opens = String(m.get_meta("opens", ""))
			s.player = player
			level.add_child(s)
			s.global_transform = (m as Node3D).global_transform
			s.pressed.connect(_on_switch)
			switches.append(s)
	_check_rooms()


func rooms_cleared() -> bool:
	for e in encounters:
		if not e.cleared():
			return false
	return true


## The first room encounter not yet cleared (null when all are).
func next_encounter() -> Encounter:
	for e in encounters:
		if not e.cleared():
			return e
	return null


func _check_rooms() -> void:
	if rooms_cleared():
		for s in switches:
			s.arm()


func _on_switch(_s: BreachSwitch) -> void:
	for s in switches:
		if not s.is_pressed:
			return
	open_gate()


func open_gate() -> void:
	if gate_open:
		return
	gate_open = true
	var names := {}
	for s in switches:
		names[s.opens] = true
	for n in names:
		_remove_box(String(n))
	gate_opened.emit()


## A save made after the vault opened: rooms cleared, levers pulled, gate + vault open.
func restore_open() -> void:
	for e in encounters:
		e.mark_cleared()
	for s in switches:
		s.arm()
		s.press()
	open_gate()
	open_vault()


func door() -> StaticBody3D:
	return level.get_node_or_null(DOOR) as StaticBody3D if level else null


func _on_killed(enemy: Enemy, _element: ElementTable.Element) -> void:
	if enemy == null or enemy.def == null or enemy.def.id != BOSS_ID:
		return
	boss_kills += 1
	if chest:
		chest.element = enemy.def.affinity
	open_vault()


func open_vault() -> void:
	if open:
		return
	open = true
	_remove_box(DOOR.get_file())
	if chest:
		chest.unlock()
	vault_opened.emit()


## Hides a level box and turns its collision off, then re-bakes the navmesh without it.
func _remove_box(box_name: String) -> void:
	var d := level.get_node_or_null("Boxes/" + box_name) as StaticBody3D if level else null
	if d:
		d.visible = false
		d.collision_layer = 0
		d.collision_mask = 0
		d.process_mode = Node.PROCESS_MODE_DISABLED
		for c in d.get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).set_deferred(&"disabled", true)
		_removed.append(d)
		# Step 48: re-bake the navmesh without the door (and every box opened before it:
		# the bake parses colliders even when disabled) so paths go through.
		var nav := level.get_node_or_null("Navigation") as LevelNavigation
		if nav:
			var back: Array = []
			for b: StaticBody3D in _removed:
				back.append([b, b.get_parent(), b.get_index()])
			for x in back:
				(x[1] as Node).remove_child(x[0])
			nav.bake_now()
			back.reverse()
			for x in back:
				(x[1] as Node).add_child(x[0])
				(x[1] as Node).move_child(x[0], x[2])
