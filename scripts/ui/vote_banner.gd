class_name VoteBanner
extends CanvasLayer
## 0.3.1 P2: the Labyrinth stairs vote, on screen. "Waiting for party: N s", the players not
## yet at the stairs, and a chip per party member (Ember Art batch_09b ui/vote, CC0). It shows
## while LabyrinthSync.left() > 0 and goes when the party gathers or the floor changes.
## The last TICK_FROM seconds tick once a second (vote_tick on the UI bus).

const ART := "res://assets/original/ember_art/ui/vote/"
const TICK_FROM := 3
const CHIP_SCALE := 3

var sync: LabyrinthSync
var panel: PanelContainer
var label: Label
var chips: HBoxContainer
var ticks := 0
var _last_sec := -1
var _sig := ""


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.name = "VotePanel"
	panel.visible = false
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.position.y = 90
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.17, 0.12, 0.15, 0.85)
	sb.set_content_margin_all(8)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override(&"panel", sb)
	add_child(panel)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(label)
	var bar := PanelContainer.new()
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bt := load(ART + "chip_bar.png") as Texture2D
	if bt:
		var st := StyleBoxTexture.new()
		st.texture = bt
		st.set_texture_margin_all(4)
		st.set_content_margin_all(3 * CHIP_SCALE)
		bar.add_theme_stylebox_override(&"panel", st)
	bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	v.add_child(bar)
	chips = HBoxContainer.new()
	chips.add_theme_constant_override(&"separation", CHIP_SCALE)
	bar.add_child(chips)


func _process(_dt: float) -> void:
	refresh()


func refresh() -> void:
	var left := sync.left() if sync and is_instance_valid(sync) else -1.0
	if left <= 0.0:
		_last_sec = -1
		if panel.visible:
			UiAnim.close(panel)
		return
	if not panel.visible:
		UiAnim.open(panel)
	var sec := ceili(left)
	var away: Array[String] = sync.missing()
	label.text = "Waiting for party: %d s" % sec
	if not away.is_empty():
		label.text += "\nNot at the stairs: " + ", ".join(away)
	var total := maxi(sync.party_size(), 1)
	var sig := "%d/%d" % [total - away.size(), total]
	if sig != _sig:
		_sig = sig
		_chips(total - away.size(), total)
	if sec != _last_sec:
		_last_sec = sec
		if sec <= TICK_FROM:
			ticks += 1
			var a := get_tree().root.find_child("GameAudio", true, false)
			if a and a.has_method(&"play"):
				a.call(&"play", "vote_tick")


func _chips(here: int, total: int) -> void:
	for c in chips.get_children():
		c.queue_free()
	for i in total:
		var t := TextureRect.new()
		t.texture = load(ART + ("chip_yes.png" if i < here else "chip_waiting.png"))
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.custom_minimum_size = Vector2(8, 8) * CHIP_SCALE
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		chips.add_child(t)
