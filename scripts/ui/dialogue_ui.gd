class_name DialogueUI
extends Control
## Dialogue box (BUILD_PLAN step 62): speaker name, line text, choice buttons. Follows a
## DialogueRunner; Interact / click advances, a choice button chooses. Also the dialogue
## subtitle surface (step 76).

var runner: DialogueRunner
var speaker_label := Label.new()
var text_label := Label.new()
var choice_box := VBoxContainer.new()


func _init() -> void:
	name = "DialogueUI"
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -180
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	speaker_label.add_theme_color_override(&"font_color", Color(1.0, 0.8, 0.4))
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(speaker_label)
	v.add_child(text_label)
	v.add_child(choice_box)
	visible = false


func bind(r: DialogueRunner) -> void:
	runner = r
	r.line_shown.connect(_on_line)
	r.choices_shown.connect(_on_choices)
	r.ended.connect(func(_id: String) -> void: visible = false)


func _on_line(sp: String, t: String) -> void:
	visible = true
	speaker_label.text = sp
	text_label.text = t
	text_label.visible = Accessibility.subtitles  # step 76
	text_label.add_theme_font_size_override("font_size", Accessibility.font_size())
	speaker_label.add_theme_font_size_override("font_size", Accessibility.font_size())
	_clear_choices()


func _on_choices(texts: PackedStringArray) -> void:
	_clear_choices()
	for i in texts.size():
		var b := Button.new()
		b.text = texts[i]
		b.pressed.connect(runner.choose.bind(i))
		choice_box.add_child(b)
	if choice_box.get_child_count() > 0 and is_inside_tree() and is_visible_in_tree():
		(choice_box.get_child(0) as Button).grab_focus()


func _clear_choices() -> void:
	for c in choice_box.get_children():
		choice_box.remove_child(c)
		c.queue_free()


func button_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for c in choice_box.get_children():
		out.append((c as Button).text)
	return out


func _unhandled_input(e: InputEvent) -> void:
	if visible and runner and runner.active and not runner.awaiting_choice() and e.is_action_pressed(&"interact"):
		runner.advance()
		get_viewport().set_input_as_handled()
