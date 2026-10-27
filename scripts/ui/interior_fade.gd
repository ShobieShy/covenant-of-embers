class_name InteriorFade
extends CanvasLayer
## OW5: the UI side of Interiors. `fade` dips a black ColorRect in and out over the
## transition (Interiors.FADE), and `slow_load` (a load over Interiors.SLOW_MS) shows a
## LoadingScreen overlay that closes when the interior is entered or left.

var interiors: Interiors
var rect: ColorRect
var screen: LoadingScreen


func _ready() -> void:
	layer = 90
	rect = ColorRect.new()
	rect.name = "Black"
	rect.color = Color(0, 0, 0, 0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(rect)
	if interiors:
		interiors.fade.connect(_on_fade)
		interiors.slow_load.connect(_on_slow)
		interiors.entered.connect(_close)
		interiors.left.connect(_close)


func _on_fade(seconds: float) -> void:
	var tw := create_tween()
	tw.tween_property(rect, "color:a", 1.0, seconds * 0.5)
	tw.tween_property(rect, "color:a", 0.0, seconds * 0.5)


func _on_slow(id: String) -> void:
	screen = LoadingScreen.overlay(get_tree(), id)


func _close(_id: String) -> void:
	if screen and is_instance_valid(screen):
		screen.done()
	screen = null
