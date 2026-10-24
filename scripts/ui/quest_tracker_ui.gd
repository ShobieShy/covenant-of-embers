class_name QuestTrackerUI
extends Control
## On-screen quest tracker + Clue Log screen (BUILD_PLAN step 63). The tracker (top right)
## follows QuestLog signals; toggle_clue_log() shows the clue panel.

var log: QuestLog
var tracker := Label.new()
var clue_panel := PanelContainer.new()
var clue_label := Label.new()


func _init() -> void:
	name = "QuestTracker"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tracker.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tracker.position = Vector2(-340, 120)
	tracker.size = Vector2(320, 200)
	tracker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(tracker)
	clue_panel.set_anchors_preset(Control.PRESET_CENTER)
	clue_panel.custom_minimum_size = Vector2(520, 320)
	clue_panel.position = Vector2(-260, -160)
	var v := VBoxContainer.new()
	var title := Label.new()
	title.text = "Clue Log"
	clue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clue_label.custom_minimum_size = Vector2(500, 0)
	v.add_child(title)
	v.add_child(clue_label)
	clue_panel.add_child(v)
	clue_panel.visible = false
	add_child(clue_panel)


func bind(q: QuestLog) -> void:
	log = q
	for s in [q.quest_started, q.quest_completed, q.clue_added]:
		s.connect(func(_id: String) -> void: refresh())
	q.objective_progressed.connect(func(_a: String, _b: int, _c: int, _d: int) -> void: refresh())
	refresh()


func refresh() -> void:
	if log == null:
		return
	tracker.text = log.tracker_text()
	clue_label.text = log.clue_log_text()


func toggle_clue_log() -> void:
	refresh()
	clue_panel.visible = not clue_panel.visible
