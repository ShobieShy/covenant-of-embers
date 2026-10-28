class_name PartyFrames
extends CanvasLayer
## Co-op party frames (BUILD_PLAN step 80): one row per other player (top left): name,
## level, a health bar and DOWN when they need a revive.
## 0.3.1 P6 (L2): a damage chip (the lost part lingers, then drains) and, on a joiner, a
## "host is loading" overlay while the host's player is not in the world yet.

const CHIP_HOLD := 0.4  ## s before the chip starts draining
const CHIP_RATE := 0.6  ## of max health per s
const WAIT_GRACE := 0.5  ## s without the host before the overlay shows
var waiting: Label
var _no_host := 0.0

var coop: CoopWorld
var box: VBoxContainer
var rows := {}  ## peer -> {label, bar}


func _ready() -> void:
	layer = 3
	box = VBoxContainer.new()
	box.position = Vector2(16, 96)
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	waiting = Label.new()
	waiting.text = "The host is loading ..."
	waiting.visible = false
	waiting.add_theme_font_size_override(&"font_size", 28)
	waiting.add_theme_color_override(&"font_color", Color(1.0, 0.8, 0.4))
	waiting.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	waiting.position.y = 140
	add_child(waiting)


func bind(c: CoopWorld) -> void:
	coop = c


func _process(dt: float) -> void:
	refresh(dt)


## Next [chip, hold] for a chip at `chip` over health `hp` after `dt`.
static func chip_step(chip: float, hp: float, hold: float, dt: float, hp_max: float) -> Array:
	if hp >= chip:
		return [hp, 0.0]
	hold += dt
	if hold < CHIP_HOLD:
		return [chip, hold]
	return [maxf(hp, chip - CHIP_RATE * maxf(hp_max, 1.0) * dt), hold]


func refresh(dt := 0.0) -> void:
	if coop == null or not is_instance_valid(coop):
		return
	var client := (
		coop.session != null and is_instance_valid(coop.session) and not coop.session.is_host()
	)
	_no_host = _no_host + dt if client and not coop.proxies.has(1) else 0.0
	var show_wait := _no_host >= WAIT_GRACE
	if show_wait and not waiting.visible:
		UiAnim.fade_in(waiting, 0.3)
	waiting.visible = show_wait
	for peer in rows.keys():
		if not coop.proxies.has(peer):
			(rows[peer]["root"] as Node).queue_free()
			rows.erase(peer)
	for peer in coop.proxies:
		var pr: RemotePlayer = coop.proxies[peer]
		if not rows.has(peer):
			var root := VBoxContainer.new()
			var l := Label.new()
			root.add_child(l)
			var stack := Control.new()
			stack.custom_minimum_size = Vector2(160, 8)
			root.add_child(stack)
			var chip := ProgressBar.new()
			chip.show_percentage = false
			chip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			chip.modulate = Color(1.0, 0.85, 0.3)
			stack.add_child(chip)
			var b := ProgressBar.new()
			b.show_percentage = false
			b.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var clear := StyleBoxEmpty.new()
			b.add_theme_stylebox_override(&"background", clear)
			stack.add_child(b)
			box.add_child(root)
			rows[peer] = {
				"root": root, "label": l, "bar": b, "chip": chip, "chip_v": pr.hp, "hold": 0.0
			}
		var row: Dictionary = rows[peer]
		var state := "  DOWN" if pr.downed else ("  dead" if not pr.is_alive else "")
		(row["label"] as Label).text = "%s  Lv %d%s" % [pr.display_name, pr.level, state]
		var bar := row["bar"] as ProgressBar
		bar.max_value = pr.hp_max
		bar.value = pr.hp
		var c := chip_step(float(row["chip_v"]), pr.hp, float(row["hold"]), dt, pr.hp_max)
		row["chip_v"] = c[0]
		row["hold"] = c[1]
		var cb := row["chip"] as ProgressBar
		cb.max_value = pr.hp_max
		cb.value = c[0]


func row_text(peer: int) -> String:
	return (rows[peer]["label"] as Label).text if rows.has(peer) else ""


func chip_value(peer: int) -> float:
	return float(rows[peer]["chip_v"]) if rows.has(peer) else -1.0
