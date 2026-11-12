class_name QuestMarker
extends Node3D
## 0.9.2: one world mark for the tracked quest. While the intro has its own mark,
## this one stays hidden so the playtest still walks to a single point.
## A kill step marks the level entrance, not every enemy. A collect step is text only.

const KILL_LEVEL := {
	"the_filth": "midden",
	"gnawer": "midden",
	"blightmaw_matriarch": "labyrinth",
	"forgemaw": "labyrinth",
	"drowned_choir": "labyrinth",
}

var main: Node
var mark: Label3D
var _cached_id := ""
var _cached_step := -1
var _cached_at: Variant = null


func _ready() -> void:
	mark = Label3D.new()
	mark.text = "v"
	mark.font_size = 96
	mark.outline_size = 16
	mark.modulate = Color(1.0, 0.8, 0.2)
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.fixed_size = true
	mark.pixel_size = 0.0006
	mark.visible = false
	add_child(mark)
	_giver_marks()


func _process(_dt: float) -> void:
	if main == null or mark == null:
		return
	var intro := main.get_node_or_null("IntroDirector")
	if intro and intro.has_method("target_point") and intro.call("target_point") != null:
		mark.visible = false
		_minimap(Vector2(INF, INF))
		return
	var at: Variant = _cached()
	mark.visible = at is Vector3 and Cinematic.playing == null
	if at is Vector3:
		var pos := at as Vector3
		mark.global_position = pos + Vector3(0, 3.0, 0)
		mark.modulate = Color(0.55, 0.75, 1.0) if _side() else Color(1.0, 0.8, 0.2)
		_minimap(Vector2(pos.x, pos.z))
	else:
		_minimap(Vector2(INF, INF))


func _cached() -> Variant:
	var log: QuestLog = main.get("quests")
	if log == null or not log.active.has(log.tracked):
		_cached_id = ""
		_cached_step = -1
		_cached_at = null
		return null
	var step := int(log.active[log.tracked]["step"])
	if log.tracked != _cached_id or step != _cached_step:
		_cached_id = log.tracked
		_cached_step = step
		_cached_at = _resolve()
	return _cached_at


func _giver_marks() -> void:
	if main == null:
		return
	var log: QuestLog = main.get("quests")
	if log == null:
		return
	for n in main.find_children("*", "Node3D", true, false):
		if not (n is Npc):
			continue
		var glyph := _glyph(log, String(n.get("speaker")))
		if glyph == "":
			continue
		var label := Label3D.new()
		label.text = glyph
		label.font_size = 64
		label.modulate = Color(1.0, 0.85, 0.3) if glyph == "!" else Color(0.55, 0.75, 1.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0, 2.4, 0)
		(n as Node3D).add_child(label)


func _glyph(log: QuestLog, speaker: String) -> String:
	if speaker == "":
		return ""
	for id in log.order:
		if String(log.quests[id].get("giver", "")) != speaker or log.state(id) != "available":
			continue
		return "!" if log.kind_of(id) == "main" else "?"
	return ""


func _side() -> bool:
	var log: QuestLog = main.get("quests")
	return log != null and log.kind_of(log.tracked) == "side"


func _resolve() -> Variant:
	var log: QuestLog = main.get("quests")
	if log == null or not log.active.has(log.tracked):
		return null
	var o := log.current_objective(log.tracked)
	if o.is_empty():
		return null
	var kind := String(o["kind"])
	var target := String(o["target"])
	if kind == "collect":
		return null
	if kind == "talk":
		return _speaker(target)
	if kind == "kill":
		target = String(KILL_LEVEL.get(target, ""))
		if target == "":
			return null
	return _gate(target)


func _speaker(name: String) -> Variant:
	for n in main.find_children("*", "Node3D", true, false):
		if n is Npc and String(n.get("speaker")) == name:
			return (n as Node3D).global_position
	return null


func _gate(level_id: String) -> Variant:
	for n in main.find_children("*", "Node3D", true, false):
		if n is LevelGate and String(n.get("target")) == level_id:
			return (n as Node3D).global_position
	for n in main.find_children("*", "Node3D", true, false):
		if n is Waystone:
			return (n as Node3D).global_position
	return null


func _minimap(at: Vector2) -> void:
	var mini := main.find_child("Minimap", true, false)
	if mini:
		mini.set("quest_at", at)
