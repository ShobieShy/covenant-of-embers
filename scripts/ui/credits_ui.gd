class_name CreditsUi
extends CanvasLayer
## In-game Credits (main menu): every third-party asset, read from data/credits.toml
## (generated from ASSETS.toml by tools/gen_credits.py), including the CC BY attributions.

const PATH := "res://data/credits.toml"

var lines: Array[String] = []
var root: PanelContainer


func _init() -> void:
	layer = 4
	visible = false
	root = PanelContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var v := VBoxContainer.new()
	root.add_child(v)
	var title := Label.new()
	title.text = "Credits"
	title.add_theme_font_size_override("font_size", 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	lines = load_lines()
	for t in ["Covenant of Embers - made with the Godot Engine (godotengine.org, MIT)", ""] + lines:
		var l := Label.new()
		l.text = t
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		list.add_child(l)
	var close := Button.new()
	close.text = "Back"
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(hide)
	v.add_child(close)


static func load_lines() -> Array[String]:
	var out: Array[String] = []
	var d := LevelToml.load_file(PATH)
	for c in d.get("credit", []):
		var cd := c as Dictionary
		# LevelToml keeps TOML escapes raw (\" stays \"), so unescape here
		out.append(("%s  -  %s" % [String(cd.get("line", "")), String(cd.get("source", ""))]).c_unescape())
	return out


func open() -> void:
	show()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		hide()
		get_viewport().set_input_as_handled()
