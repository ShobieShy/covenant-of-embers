class_name DaggerGlow
extends CanvasLayer
## Step 113 (Q18): Bob's rusty dagger is a keepsake key item, not a weapon. It glows when a
## hostile is near: a HUD tag that brightens and pulses faster as the nearest one closes in.

const RANGE := 14.0

var player: Player
var label: Label
var level := 0.0  ## 0 = nothing near, 1 = right on top of you


static func make(p: Player) -> DaggerGlow:
	var d := DaggerGlow.new()
	d.name = "DaggerGlow"
	d.player = p
	return d


func _ready() -> void:
	layer = 3
	label = Label.new()
	label.text = "Rusty dagger: glowing"
	label.anchor_left = 0.02
	label.anchor_top = 0.62
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_color", Color(1.0, 0.5, 0.15))
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 5)
	label.visible = false
	add_child(label)


## Nearest live hostile distance (INF when none).
func nearest() -> float:
	var best := INF
	if player == null or not player.is_inside_tree():
		return best
	for n in get_tree().get_nodes_in_group(Enemy.GROUP):
		var e := n as Enemy
		if e and e.alive() and not e.def.ai.is_empty():
			best = minf(best, e.global_position.distance_to(player.global_position))
	return best


func _process(_dt: float) -> void:
	var d := nearest()
	level = clampf(1.0 - d / RANGE, 0.0, 1.0) if d < RANGE else 0.0
	label.visible = level > 0.0
	if label.visible:
		var speed := 0.004 + 0.012 * level
		label.modulate.a = 0.35 + 0.65 * level * (0.6 + 0.4 * sin(Time.get_ticks_msec() * speed))
