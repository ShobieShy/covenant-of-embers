class_name UiTheme
extends RefCounted
## Step 126 (Art A8, Ember Art batch_05, CC0 Kenney + original): pixel fantasy UI theme.
## Applied once to the root Window (main_menu._ready) so every Control inherits it.
## 9-slice margins from batch_05 HANDOFF.md: 48 px panels/buttons 16, inlays 14, bar frame 3, slots 4.

const DIR := "res://assets/kenney/pixel-ui/"
const SCALE := 2  # whole-number pixel scale for 9-slice corners
const GOLD := Color(0.95, 0.8, 0.45)
const PARCHMENT := Color(0.92, 0.85, 0.7)


static func tex(rel: String) -> Texture2D:
	return load(DIR + rel) as Texture2D


static func box(rel: String, margin: int, modulate := Color.WHITE, pad := 10) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex(rel)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_texture_margin(side, margin)
		sb.set_content_margin(side, pad)
	sb.modulate_color = modulate
	return sb


static func pixel_font(file: String) -> FontFile:
	var f := (load(DIR + "fonts/" + file) as FontFile).duplicate() as FontFile
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NONE
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f


static func get_theme() -> Theme:
	var t := Theme.new()
	t.default_font = pixel_font("Kenney Pixel.ttf")
	t.default_font_size = 32  # base 16 x2
	# Buttons: Ancient brown stone/wood, pressed art sits 1 px lower.
	t.set_stylebox(&"normal", &"Button", box("panels_9slice/pixel_ui/Ancient/brown.png", 16))
	t.set_stylebox(&"hover", &"Button", box("panels_9slice/pixel_ui/Ancient/tan.png", 16))
	var pressed := box("panels_9slice/pixel_ui/Ancient/brown_pressed.png", 16)
	pressed.content_margin_top += 1
	t.set_stylebox(&"pressed", &"Button", pressed)
	t.set_stylebox(&"disabled", &"Button", box("panels_9slice/pixel_ui/Ancient/grey.png", 16, Color(1, 1, 1, 0.6)))
	t.set_stylebox(&"focus", &"Button", box("panels_9slice/fantasy_borders/Border/panel-border-000.png", 16, GOLD))
	(t.get_stylebox(&"focus", &"Button") as StyleBoxTexture).draw_center = false
	t.set_color(&"font_color", &"Button", PARCHMENT)
	t.set_color(&"font_hover_color", &"Button", Color.WHITE)
	t.set_color(&"font_pressed_color", &"Button", GOLD)
	t.set_color(&"font_outline_color", &"Button", Color(0.1, 0.06, 0.04))
	t.set_constant(&"outline_size", &"Button", 4)
	# Panels: dark filled fantasy panel tinted parchment-brown; inlay for recessed areas.
	var panel := box("panels_9slice/fantasy_borders/Panel/panel-000.png", 16, Color(0.35, 0.27, 0.2, 0.95), 16)
	t.set_stylebox(&"panel", &"Panel", panel)
	t.set_stylebox(&"panel", &"PanelContainer", panel)
	t.set_stylebox(&"panel", &"PopupPanel", panel)
	t.set_stylebox(&"normal", &"LineEdit", box("panels_9slice/pixel_ui/Ancient/brown_inlay.png", 14, Color.WHITE, 8))
	t.set_stylebox(&"panel", &"ItemList", box("panels_9slice/pixel_ui/Ancient/brown_inlay.png", 14, Color.WHITE, 8))
	# Slider
	t.set_stylebox(&"slider", &"HSlider", box("bars_sliders/slider_track.png", 2, Color.WHITE, 3))
	t.set_icon(&"grabber", &"HSlider", tex("bars_sliders/slider_grabber.png"))
	t.set_icon(&"grabber_highlight", &"HSlider", tex("bars_sliders/slider_grabber_hover.png"))
	t.set_color(&"font_color", &"Label", PARCHMENT)
	t.set_color(&"font_outline_color", &"Label", Color(0.08, 0.05, 0.03))
	return t


## Whole UI: theme, Nearest filtering for 2D, pixel cursors (hotspots per HANDOFF.md).
static func apply(win: Window) -> void:
	if win.theme == null:  # no static cache: a static Theme leaks RIDs at exit
		win.theme = get_theme()
	win.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	if DisplayServer.get_name() != "headless":
		Input.set_custom_mouse_cursor(tex("cursors/cursor_pointer.png"), Input.CURSOR_ARROW, Vector2(0, 0))
		Input.set_custom_mouse_cursor(tex("cursors/cursor_hand_point.png"), Input.CURSOR_POINTING_HAND, Vector2(5, 1))
		Input.set_custom_mouse_cursor(tex("cursors/cursor_busy_hourglass.png"), Input.CURSOR_BUSY, Vector2(8, 8))


## Pixel bar frame (bar_frame.png, margins 3) laid over a HUD ProgressBar; gameplay colours unchanged.
static func frame_bar(b: ProgressBar) -> void:
	var f := NinePatchRect.new()
	f.texture = tex("bars_sliders/bar_frame.png")
	f.patch_margin_left = 3
	f.patch_margin_top = 3
	f.patch_margin_right = 3
	f.patch_margin_bottom = 3
	f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	f.offset_left = -4
	f.offset_top = -4
	f.offset_right = 4
	f.offset_bottom = 4
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.add_child(f)
