class_name UiTheme
extends RefCounted
## 0.15.1: parchment-and-brass Auto-Scribe theme, drawn to match the painted maps.
## Applied once to the root Window (main_menu._ready) so every Control inherits it.
## 9-slice margins sit outside the corner knots so a stretched panel keeps them.

const DIR := "res://assets/original/ui_scribe/"
const FONT_PATH := "res://assets/original/libre-baskerville/LibreBaskerville-Regular.ttf"
const GOLD := Color(0.72, 0.55, 0.28)
const PARCHMENT := Color(0.92, 0.85, 0.7)  ## light paper; loading tips still use this
const INK := Color(0.20, 0.11, 0.06)
const INK_SOFT := Color(0.33, 0.20, 0.10)
const SLOT := &"SlotButton"
const SLOT_MARGIN := 16
const BODY := 22  ## Libre Baskerville, drawn for small text on screen


static func tex(rel: String) -> Texture2D:
	return load(DIR + rel) as Texture2D


static func body_font() -> Font:
	var f := load(FONT_PATH) as Font
	return f if f != null else ThemeDB.fallback_font


static func box(rel: String, margin: int, modulate := Color.WHITE, pad := 8) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex(rel)
	# Content sits inside the brass, not under the corner knots.
	var inset := margin + pad
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_texture_margin(side, margin)
		sb.set_content_margin(side, inset)
	sb.modulate_color = modulate
	return sb


static func get_theme() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = BODY
	t.set_stylebox(&"normal", &"Button", box("button.png", 26, Color.WHITE, 6))
	t.set_stylebox(&"hover", &"Button", box("button_hover.png", 26, Color.WHITE, 6))
	var pressed := box("button_pressed.png", 26, Color.WHITE, 6)
	pressed.content_margin_top += 1
	t.set_stylebox(&"pressed", &"Button", pressed)
	t.set_stylebox(&"disabled", &"Button", box("button_disabled.png", 26, Color(1, 1, 1, 0.85), 6))
	var focus := box("focus.png", 16, GOLD, 8)
	focus.draw_center = false
	t.set_stylebox(&"focus", &"Button", focus)
	t.set_color(&"font_color", &"Button", INK)
	t.set_color(&"font_hover_color", &"Button", INK)
	t.set_color(&"font_pressed_color", &"Button", INK_SOFT)
	t.set_color(&"font_disabled_color", &"Button", Color(INK, 0.45))
	t.set_color(&"font_outline_color", &"Button", Color(0, 0, 0, 0))
	t.set_constant(&"outline_size", &"Button", 0)
	var panel := box("panel.png", 48, Color.WHITE, 10)
	t.set_stylebox(&"panel", &"Panel", panel)
	t.set_stylebox(&"panel", &"PanelContainer", panel)
	t.set_stylebox(&"panel", &"PopupPanel", panel)
	var inlay := box("inlay.png", 14, Color.WHITE, 8)
	t.set_stylebox(&"normal", &"LineEdit", inlay)
	t.set_stylebox(&"focus", &"LineEdit", inlay)
	t.set_stylebox(&"read_only", &"LineEdit", inlay)
	t.set_color(&"font_color", &"LineEdit", INK)
	t.set_color(&"font_placeholder_color", &"LineEdit", INK_SOFT)
	t.set_stylebox(&"panel", &"ItemList", inlay)
	t.set_color(&"font_color", &"ItemList", INK)
	t.set_color(&"font_hovered_color", &"ItemList", INK)
	t.set_color(&"font_selected_color", &"ItemList", INK)
	t.set_stylebox(&"selected", &"ItemList", box("slot_selected.png", SLOT_MARGIN, Color(1, 1, 1, 0.35), 4))
	t.set_stylebox(&"slider", &"HSlider", box("inlay.png", 10, Color.WHITE, 2))
	t.set_icon(&"grabber", &"HSlider", tex("grabber.png"))
	t.set_icon(&"grabber_highlight", &"HSlider", tex("grabber.png"))
	t.set_type_variation(SLOT, &"Button")
	t.set_stylebox(&"normal", SLOT, box("slot.png", SLOT_MARGIN, Color.WHITE, 4))
	t.set_stylebox(&"hover", SLOT, box("slot_selected.png", SLOT_MARGIN, Color.WHITE, 4))
	t.set_stylebox(&"pressed", SLOT, box("slot_selected.png", SLOT_MARGIN, Color.WHITE, 4))
	t.set_stylebox(&"focus", SLOT, box("slot_selected.png", SLOT_MARGIN, GOLD, 4))
	t.set_stylebox(&"disabled", SLOT, box("slot.png", SLOT_MARGIN, Color(1, 1, 1, 0.55), 4))
	t.set_stylebox(&"normal", &"RichTextLabel", StyleBoxEmpty.new())
	t.set_color(&"default_color", &"RichTextLabel", INK)
	for f in [&"normal_font", &"bold_font", &"italics_font", &"bold_italics_font"]:
		t.set_font(f, &"RichTextLabel", t.default_font)
	t.set_font_size(&"normal_font_size", &"RichTextLabel", BODY)
	t.set_font_size(&"bold_font_size", &"RichTextLabel", BODY)
	t.set_color(&"font_color", &"Label", INK)
	t.set_color(&"font_outline_color", &"Label", Color(0, 0, 0, 0))
	t.set_constant(&"outline_size", &"Label", 0)
	return t


## Whole UI. CanvasLayer screens do not inherit the Window theme, so this also merges
## into ThemeDB's default theme, the fallback for all of them.
static func apply(win: Window) -> void:
	if win.theme == null:  # no static cache: a static Theme leaks RIDs at exit
		win.theme = get_theme()
	var d := ThemeDB.get_default_theme()
	if not d.has_meta(&"scribe"):
		d.set_meta(&"scribe", true)
		d.merge_with(win.theme)
		d.default_font = win.theme.default_font
		d.default_font_size = win.theme.default_font_size
	# Painted paper and the map plates, not the old pixel pack.
	win.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	if DisplayServer.get_name() != "headless":
		var arrow := tex("cursor.png")
		Input.set_custom_mouse_cursor(arrow, Input.CURSOR_ARROW, Vector2(1, 1))
		Input.set_custom_mouse_cursor(arrow, Input.CURSOR_POINTING_HAND, Vector2(1, 1))


## Brass rule laid over a HUD ProgressBar. The centre of the texture is clear.
static func frame_bar(b: ProgressBar) -> void:
	_frame(b, "bar_frame.png", 12, 5)
	RitualFX.bar_shine(b)


## Brass rule over a carry slot. Centre stays clear so the icon and rarity tint show.
static func frame_slot(node: Control) -> void:
	_frame(node, "slot_frame.png", 16, 4)


static func _frame(node: Control, rel: String, margin: int, outset: int) -> void:
	var f := NinePatchRect.new()
	f.texture = tex(rel)
	f.patch_margin_left = margin
	f.patch_margin_top = margin
	f.patch_margin_right = margin
	f.patch_margin_bottom = margin
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.offset_left = -outset
	f.offset_top = -outset
	f.offset_right = outset
	f.offset_bottom = outset
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(f)
