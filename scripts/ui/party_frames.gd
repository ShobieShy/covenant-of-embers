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
var note: Label
var hud: Hud  ## QA r14: found beside us when unset; the frames stack below its stats
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
	note = Label.new()
	note.add_theme_color_override(&"font_color", Color(0.95, 0.75, 0.45))
	box.add_child(note)


func bind(c: CoopWorld) -> void:
	coop = c


func player_of() -> Node3D:
	return coop.player if coop != null else null


func _arrow(pr: RemotePlayer) -> String:
	var p := player_of()
	if p == null:
		return ""
	var d := pr.global_position - p.global_position
	if Vector2(d.x, d.z).length() < 1.5:
		return ""
	var a := atan2(d.x, d.z)
	var steps := int(round(a / (TAU / 8.0)))
	return " " + ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][posmod(steps, 8)]


func _down_ring(row: Dictionary, pr: RemotePlayer) -> void:
	var ring: Control = row.get("ring")
	if ring == null:
		return
	ring.visible = pr.downed
	if pr.downed and ring.has_method(&"set_frac"):
		var frac := clampf(pr.downed_left / CoopWorld.LAST_STAND, 0.0, 1.0)
		ring.call(&"set_frac", frac)


func _ping(row: Dictionary, pr: RemotePlayer) -> void:
	if pr.ping_left <= 0.0 or player_of() == null:
		return
	(row["label"] as Label).text += "  •"


class _Ring:
	extends Control
	var frac := 1.0

	func set_frac(v: float) -> void:
		frac = v
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		draw_arc(c, 7.0, -TAU / 4.0, -TAU / 4.0 + TAU * frac, 20, Color(0.9, 0.25, 0.2), 2.0)


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


## The frames' top: below the HUD's stats column (`hud_bottom` px), never above 96.
static func frames_y(hud_bottom: float) -> float:
	return maxf(96.0, hud_bottom + 12.0)


func _place() -> void:
	if hud == null and get_parent():
		for c in get_parent().get_children():
			if c is Hud:
				hud = c
	if hud and is_instance_valid(hud) and hud.stats_box and hud.stats_box.is_inside_tree():
		box.position.y = frames_y(hud.stats_box.get_global_rect().end.y)


func refresh(dt := 0.0) -> void:
	_place()
	if coop == null or not is_instance_valid(coop):
		return
	if note and coop.session and is_instance_valid(coop.session):
		note.text = CoopFlow.party_line(coop.session.roster.size())
	var client := false
	if coop.session != null and is_instance_valid(coop.session) and coop.session.state != NetSession.State.ENDED:
		client = not coop.session.is_host()
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
			var shield := ProgressBar.new()
			shield.show_percentage = false
			shield.custom_minimum_size = Vector2(160, 4)
			shield.modulate = Color(0.4, 0.7, 1.0)
			root.add_child(shield)
			var ring := _Ring.new()
			ring.custom_minimum_size = Vector2(18, 18)
			root.add_child(ring)
			rows[peer] = {
				"root": root, "label": l, "bar": b, "chip": chip, "chip_v": pr.hp, "hold": 0.0,
				"shield": shield, "ring": ring,
			}
		var row: Dictionary = rows[peer]
		var state := ""
		if pr.reconnecting:
			state = "  reconnecting"
		elif pr.downed:
			state = "  DOWN %ds" % int(ceil(pr.downed_left))
		elif not pr.is_alive:
			state = "  dead"
		var dist := ""
		if player_of() != null:
			dist = "  " + CoopFlow.distance_text(pr.global_position.distance_to(player_of().global_position))
		var arrow := _arrow(pr)
		(row["label"] as Label).text = "%s  Lv %d%s%s%s" % [pr.display_name, pr.level, dist, arrow, state]
		_down_ring(row, pr)
		_ping(row, pr)
		var bar := row["bar"] as ProgressBar
		bar.max_value = pr.hp_max
		bar.value = pr.hp
		var c := chip_step(float(row["chip_v"]), pr.hp, float(row["hold"]), dt, pr.hp_max)
		row["chip_v"] = c[0]
		row["hold"] = c[1]
		var cb := row["chip"] as ProgressBar
		cb.max_value = pr.hp_max
		cb.value = c[0]
		var sh: ProgressBar = row.get("shield")
		if sh:
			sh.max_value = maxf(1.0, pr.hp_max)
			sh.value = pr.shield
			sh.visible = pr.shield > 0.0


func row_text(peer: int) -> String:
	return (rows[peer]["label"] as Label).text if rows.has(peer) else ""


func chip_value(peer: int) -> float:
	return float(rows[peer]["chip_v"]) if rows.has(peer) else -1.0
