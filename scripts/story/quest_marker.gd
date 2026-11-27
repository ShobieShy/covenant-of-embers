class_name QuestMarker
extends Node3D
## 0.9.2: one world mark for the tracked quest. While the intro has its own mark,
## this one stays hidden so the playtest still walks to a single point.
## 0.11.5: QuestWaypoint picks the spot. A finished step and a missing exit leave no mark.

var main: Node
var mark: Label3D
var _cached_id := ""
var _cached_step := -1
var _cached_here := ""
var _cached_floor := -999
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
		var lead: Variant = intro.call("target_point")
		if lead is Vector3:
			var p := lead as Vector3
			_minimap(Vector2(p.x, p.z))
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
	var here := ""
	if main.has_method(&"here_id"):
		here = String(main.call(&"here_id"))
	var floor := -999
	var lin := main.get_node_or_null("LinearInteriors")
	if lin:
		floor = int(lin.get("floor_no"))
	# The floor changes under one kill step (stairs, then the boss). The spot has to move with it.
	if log.tracked != _cached_id or step != _cached_step or here != _cached_here or floor != _cached_floor:
		_cached_id = log.tracked
		_cached_step = step
		_cached_here = here
		_cached_floor = floor
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
	var survey := QuestWaypoint.survey(main)
	var here := ""
	if main.has_method(&"here_id"):
		here = String(main.call(&"here_id"))
	var at: Variant = QuestWaypoint.resolve(
		String(o["kind"]), String(o["target"]), here, int(survey.get("floor", 0)), survey
	)
	if at is Vector3:
		return _feet(at)
	return at


## A spawn or a dais origin can sit inside its floor. The mark stands on the surface.
func _feet(at: Vector3) -> Vector3:
	var w: World3D = main.get_world_3d()
	if w == null:
		return at
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 2.0, 0), at + Vector3(0, -3.0, 0), 1)
	var hit: Dictionary = w.direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return at
	return (hit.position as Vector3) + Vector3(0, 0.2, 0)


func _minimap(at: Vector2) -> void:
	var mini := main.find_child("Minimap", true, false)
	if mini:
		mini.set("quest_at", at)
