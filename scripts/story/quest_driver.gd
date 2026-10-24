class_name QuestDriver
extends Node
## The tutorial chain's glue (BUILD_PLAN step 67): feeds gameplay events into a QuestLog.
##   kill    <- EventBus.enemy_killed (the enemy's def id: gnawer, the_filth ...)
##   collect <- EventBus.quest_item_collected (joes_discards = Joe's Trash, step 57)
##   reach   <- entering a level (its waystone point id: midden -> "landfill", old_oak ...)
##   talk    <- a dialogue with that speaker ending (Bob)
## Chain: Bob (Old Oak) -> the Landfill -> Gnawers -> The Filth -> Joe's Trash
## (filth_defeated) -> back to Bob, who crafts the Fast Travel crystal (tutorial_done +
## fast_travel_crystal). Being a Node, its bus connections drop with the level.

var log: QuestLog


static func make(q: QuestLog) -> QuestDriver:
	var d := QuestDriver.new()
	d.name = "QuestDriver"
	d.log = q
	return d


func _ready() -> void:
	var bus := GameEvents.bus()
	bus.enemy_killed.connect(_on_killed)
	bus.quest_item_collected.connect(_on_item)


func _on_killed(e: Enemy, _el: ElementTable.Element) -> void:
	if e != null and e.def != null:
		log.notify("kill", e.def.id)


func _on_item(_p: Player, id: String) -> void:
	log.notify("collect", id)


static func reach_id(level_id: String) -> String:
	return String(FastTravel.LEVEL_POINT.get(level_id, level_id))


func reached(level_id: String) -> void:
	log.notify("reach", reach_id(level_id))


func talked(speaker: String) -> void:
	log.notify("talk", speaker)
