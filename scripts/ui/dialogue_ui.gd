class_name DialogueUI
extends Control
## Dialogue box (BUILD_PLAN step 62): speaker name, line text, choice buttons. Follows a
## DialogueRunner; Interact / click advances, a choice button chooses. Also the dialogue
## subtitle surface (step 76).
## 0.3.1 P3: lines type out at CPS chars/s (instant under Settings.instant_text, reduced
## motion or headless). Interact while typing completes the line; the next press advances.
## Choices wait for the line to finish. A "continue" arrow (Ember Art batch_09b, CC0) bobs
## at 8 fps once a line is done; each speaker gets a stable name colour.

const CPS := 45.0
const ARROW := "res://assets/original/ember_art/ui/typewriter/continue_arrow_strip.png"
const ARROW_FPS := 8.0
const SPEAKER_COLORS: Array[Color] = [
	Color(1.0, 0.8, 0.4),
	Color(0.55, 0.85, 1.0),
	Color(0.7, 1.0, 0.6),
	Color(1.0, 0.6, 0.55),
	Color(0.85, 0.7, 1.0),
	Color(1.0, 0.95, 0.65),
]

static var instant_text := false  ## Settings.apply_to() keeps this in sync

var runner: DialogueRunner
var speaker_label := Label.new()
var text_label := Label.new()
var choice_box := VBoxContainer.new()
var arrow := TextureRect.new()
var typed := 0.0  ## characters shown so far (float: CPS * time)
var _arrow_t := 0.0
var _pending_choices := PackedStringArray()
var _has_pending := false


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
	var strip := load(ARROW) as Texture2D
	if strip:
		var at := AtlasTexture.new()
		at.atlas = strip
		at.region = Rect2(0, 0, 8, 8)
		arrow.texture = at
	arrow.name = "ContinueArrow"
	arrow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	arrow.stretch_mode = TextureRect.STRETCH_SCALE
	arrow.custom_minimum_size = Vector2(24, 24)
	arrow.size = Vector2(24, 24)
	arrow.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	arrow.position -= Vector2(36, 36)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.visible = false
	add_child(arrow)
	visible = false


static func speaker_color(sp: String) -> Color:
	if sp.is_empty():
		return SPEAKER_COLORS[0]
	return SPEAKER_COLORS[absi(sp.hash()) % SPEAKER_COLORS.size()]


func typing() -> bool:
	return text_label.visible_characters >= 0


## Show the whole line now (the first Interact while typing).
func complete() -> void:
	text_label.visible_characters = -1
	typed = 0.0
	if _has_pending:
		_has_pending = false
		_show_choices(_pending_choices)
	_update_arrow()


func _process(dt: float) -> void:
	if typing():
		typed += CPS * dt
		var n := int(typed)
		if n >= text_label.get_total_character_count():
			complete()
		else:
			text_label.visible_characters = n
	if arrow.visible and arrow.texture is AtlasTexture:
		_arrow_t += dt
		var f := int(_arrow_t * ARROW_FPS) % 6
		(arrow.texture as AtlasTexture).region = Rect2(f * 8, 0, 8, 8)


func _update_arrow() -> void:
	arrow.visible = (
		visible
		and not typing()
		and choice_box.get_child_count() == 0
		and runner != null
		and runner.active
		and not runner.awaiting_choice()
	)


func bind(r: DialogueRunner) -> void:
	runner = r
	r.line_shown.connect(_on_line)
	r.choices_shown.connect(_on_choices)
	r.ended.connect(func(_id: String) -> void: UiAnim.close(self))  # 0.3.1 P1


func _on_line(sp: String, t: String) -> void:
	if not UiAnim.is_shown(self):
		UiAnim.open(self)  # 0.3.1 P1
	speaker_label.text = sp
	speaker_label.add_theme_color_override(&"font_color", speaker_color(sp))  # 0.3.1 P3
	text_label.text = t
	_has_pending = false
	typed = 0.0
	var instant := instant_text or UiAnim.instant() or not Accessibility.subtitles
	text_label.visible_characters = -1 if instant else 0
	text_label.visible = Accessibility.subtitles  # step 76
	text_label.add_theme_font_size_override("font_size", Accessibility.font_size())
	speaker_label.add_theme_font_size_override("font_size", Accessibility.font_size())
	_clear_choices()
	_update_arrow()


func _on_choices(texts: PackedStringArray) -> void:
	_clear_choices()
	if typing():  # choices wait for the line
		_pending_choices = texts
		_has_pending = true
		return
	_show_choices(texts)


func _show_choices(texts: PackedStringArray) -> void:
	for i in texts.size():
		var b := Button.new()
		b.text = texts[i]
		b.pressed.connect(runner.choose.bind(i))
		choice_box.add_child(b)
	if choice_box.get_child_count() > 0 and is_inside_tree() and is_visible_in_tree():
		(choice_box.get_child(0) as Button).grab_focus()
	_update_arrow()


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
	if visible and runner and runner.active and e.is_action_pressed(&"interact"):
		if press_interact():
			get_viewport().set_input_as_handled()


## Interact: complete a typing line, else advance (not while a choice is up).
func press_interact() -> bool:
	if typing():
		complete()
		return true
	if runner.awaiting_choice():
		return false
	runner.advance()
	return true
