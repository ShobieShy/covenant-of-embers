class_name InteriorFade
extends CanvasLayer
## OW5: the UI side of Interiors. `fade` dips a black ColorRect in and out over the
## transition (Interiors.FADE), and `slow_load` (a load over Interiors.SLOW_MS) shows a
## LoadingScreen overlay that closes when the interior is entered or left.
## 0.3.1 P1: the same black also covers the other party moves. A fast-travel arrival (after
## OpenWorld.ground_now() has built the ground) and a respawn after death fade in from black.
## Like UiAnim, those fade-ins are instant (it stays clear) under reduced motion and headless.

const ARRIVE_S := 0.35

var interiors: Interiors
var travel: WorldTravel
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
	if travel:
		travel.arrived.connect(func(_p: String) -> void: from_black(ARRIVE_S))
	for p in get_tree().get_nodes_in_group(Player.GROUP):
		_watch(p)
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n is Player:
		_watch(n)


func _watch(p: Node) -> void:
	var pl := p as Player
	if pl and not pl.respawned.is_connected(_on_respawned):
		pl.respawned.connect(_on_respawned)


func _on_respawned(_p: Player) -> void:
	from_black(ARRIVE_S)


## Start black and fade to clear over `seconds`.
func from_black(seconds: float) -> void:
	if UiAnim.instant():
		rect.color.a = 0.0
		return
	rect.color.a = 1.0
	var tw := create_tween()
	tw.tween_property(rect, "color:a", 0.0, seconds)


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
