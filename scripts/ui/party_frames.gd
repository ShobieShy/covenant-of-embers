class_name PartyFrames
extends CanvasLayer
## Co-op party frames (BUILD_PLAN step 80): one row per other player (top left): name,
## level, a health bar and DOWN when they need a revive.

var coop: CoopWorld
var box: VBoxContainer
var rows := {}  ## peer -> {label, bar}


func _ready() -> void:
	layer = 3
	box = VBoxContainer.new()
	box.position = Vector2(16, 96)
	box.add_theme_constant_override("separation", 4)
	add_child(box)


func bind(c: CoopWorld) -> void:
	coop = c


func _process(_dt: float) -> void:
	refresh()


func refresh() -> void:
	if coop == null or not is_instance_valid(coop):
		return
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
			var b := ProgressBar.new()
			b.custom_minimum_size = Vector2(160, 8)
			b.show_percentage = false
			root.add_child(b)
			box.add_child(root)
			rows[peer] = {"root": root, "label": l, "bar": b}
		var row: Dictionary = rows[peer]
		var state := "  DOWN" if pr.downed else ("  dead" if not pr.is_alive else "")
		(row["label"] as Label).text = "%s  Lv %d%s" % [pr.display_name, pr.level, state]
		var bar := row["bar"] as ProgressBar
		bar.max_value = pr.hp_max
		bar.value = pr.hp


func row_text(peer: int) -> String:
	return (rows[peer]["label"] as Label).text if rows.has(peer) else ""
