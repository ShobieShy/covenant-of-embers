class_name CharacterCreator
extends VBoxContainer
## Step 111: the archetype / colour / name picker (lifted out of the step 73 main menu).
## The menu embeds it as-is (used by --skip-intro / Skip prologue runs); the intro shows it
## as the appraisal crystal's readout via `overlay()`, with a Confirm button.

signal confirmed(identity: Dictionary)

var archetype_pick: OptionButton
var color_pick: ColorPickerButton
var name_edit: LineEdit
var confirm_button: Button


func _init(with_confirm := false, prefill := {}) -> void:
	add_theme_constant_override(&"separation", 8)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(row)
	archetype_pick = OptionButton.new()
	for id in Archetype.IDS:
		archetype_pick.add_item("%s (%s)" % [Archetype.label(id), Archetype.blurb(id)])
	archetype_pick.item_selected.connect(_on_archetype)
	row.add_child(archetype_pick)
	color_pick = ColorPickerButton.new()
	color_pick.custom_minimum_size = Vector2(40, 0)
	color_pick.edit_alpha = false
	row.add_child(color_pick)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Character name"
	name_edit.max_length = Archetype.NAME_MAX
	add_child(name_edit)
	set_identity(prefill)
	if with_confirm:
		confirm_button = Button.new()
		confirm_button.text = "This is me"
		confirm_button.custom_minimum_size = Vector2(0, 36)
		confirm_button.pressed.connect(confirm)
		add_child(confirm_button)


## The intro's appraisal readout: a centred panel on its own layer (caller adds it).
static func overlay(prefill := {}) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "CharacterCreator"
	layer.layer = 40
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(c)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	c.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var t := Label.new()
	t.text = "Appraisal crystal - readout"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override(&"font_size", 24)
	v.add_child(t)
	var cc := CharacterCreator.new(true, prefill)
	cc.name = "Creator"
	v.add_child(cc)
	layer.set_meta(&"creator", cc)
	return layer


static func of(layer: CanvasLayer) -> CharacterCreator:
	return layer.get_meta(&"creator") as CharacterCreator


func set_identity(idn: Dictionary) -> void:
	var arch := Archetype.valid(String(idn.get("archetype", Archetype.DEFAULT)))
	archetype_pick.select(maxi(0, Archetype.IDS.find(arch)))
	color_pick.color = (
		idn.get("color", Archetype.default_color(arch)) if idn.get("color") is Color else Archetype.default_color(arch)
	)
	name_edit.text = String(idn.get("name", "Ember"))
	if name_edit.text.is_empty():
		name_edit.text = "Ember"


func _on_archetype(i: int) -> void:
	color_pick.color = Archetype.default_color(Archetype.IDS[i])


func identity() -> Dictionary:
	return {
		"archetype": Archetype.IDS[maxi(0, archetype_pick.selected)],
		"name": name_edit.text,
		"color": color_pick.color,
	}


func confirm() -> void:
	confirmed.emit(identity())
