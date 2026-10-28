class_name FastTravelUI
extends Control
## The fast-travel map screen (BUILD_PLAN step 68; Magewar fast_travel_ui.tscn): one button
## per attuned point (greyed: here / crystal locked), plus a status line and Close.

signal closed

var travel: FastTravel
var here := ""
var list := VBoxContainer.new()
var status := Label.new()
var buttons := {}


func _init() -> void:
	name = "FastTravelUI"
	set_anchors_preset(Control.PRESET_CENTER)
	var panel := PanelContainer.new()
	add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var title := Label.new()
	title.text = "Teleportation Crystal"
	v.add_child(title)
	v.add_child(list)
	v.add_child(status)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(hide_map)
	v.add_child(close)
	visible = false


func show_map(ft: FastTravel, here_point: String) -> void:
	travel = ft
	here = here_point
	for c in list.get_children():
		c.queue_free()
	buttons.clear()
	var ok := ft.unlocked()
	status.text = (
		""
		if ok
		else ("No crystal." if not ft.has_crystal() else "The crystal hasn't been activated yet.")
	)
	for p in ft.destinations():
		var b := Button.new()
		b.text = String(FastTravel.info(p)["name"]) + ("  (here)" if p == here else "")
		b.disabled = not ok or p == here
		b.pressed.connect(press.bind(p))
		list.add_child(b)
		buttons[p] = b
	UiAnim.open(self)  # 0.3.1 P1
	Gamepad.focus_first(self)  # step 77


func press(point: String) -> bool:
	if travel == null or point == here or not travel.travel(point):
		status.text = travel.last_error if travel else ""
		return false
	hide_map()
	return true


func hide_map() -> void:
	UiAnim.close(self)  # 0.3.1 P1
	closed.emit()
