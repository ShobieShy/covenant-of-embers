class_name QuestToast
extends CanvasLayer
## 0.9.2: a short completion card. It does not pause. Reduced motion shows it with no slide.

var label := Label.new()


func _init() -> void:
	layer = 5
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.position = Vector2(-220, 72)
	panel.custom_minimum_size = Vector2(440, 0)
	add_child(panel)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420, 0)
	panel.add_child(label)


func bind(log: QuestLog) -> void:
	if not log.quest_completed.is_connected(_on_done):
		log.quest_completed.connect(_on_done.bind(log))


func _on_done(id: String, log: QuestLog) -> void:
	if not log.quests.has(id):
		return
	var q: Dictionary = log.quests[id]
	label.text = "%s\n%s" % [q["title"], log.reward_line(id)]
	UiAnim.open(self)
	if UiAnim.instant():
		visible = true
		return
	var t := create_tween()
	t.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	t.set_ignore_time_scale(true)
	t.tween_interval(2.2)
	t.tween_callback(func() -> void: UiAnim.close(self))
