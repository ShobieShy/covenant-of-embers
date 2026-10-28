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
var _shown_at := -1.0
var _last_left := 0.0


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.name = "VotePanel"
	panel.visible = false
	# QA round 10: a preset set before the panel has a size left it ~113 px right of centre.
	# Anchor at the top centre and grow both ways so it stays centred as the text changes.
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = 0.0
	panel.offset_right = 0.0
	panel.offset_top = 90.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
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
		# QA round 11: the panel stays visible through the close fade; log the end once.
		if panel.visible and not UiAnim.closing(panel):
			UiAnim.close(panel, Callable(), false)
			_log_end()
		return
	_last_left = left
	var sec := ceili(left)
	var away: Array[String] = sync.missing()
	label.text = "Waiting for party: %d s" % sec
	if not away.is_empty():
		label.text += "\nNot at the stairs: " + ", ".join(away)
	if not panel.visible or UiAnim.closing(panel):
		# QA round 11: size to the text before open() reads the rest position, or the slide
		# home is the narrow width and the banner sits ~112 px off-centre.
		var w := panel.get_combined_minimum_size().x
		panel.offset_left = -ceilf(w / 2.0)
		panel.offset_right = ceilf(w / 2.0)
		UiAnim.open(panel, false)
		_shown_at = Time.get_ticks_msec() / 1000.0
		print("[vote] start: %.1f s left" % left)
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


## QA round 10: log how the vote ended and how long the banner was up.
func _log_end() -> void:
	var up := Time.get_ticks_msec() / 1000.0 - _shown_at if _shown_at >= 0.0 else 0.0
	var why := (
		"ended (timer ran out)" if _last_left < 1.0 else "cleared (party gathered or floor changed)"
	)
	print("[vote] %s after %.1f s" % [why, up])
	_shown_at = -1.0
