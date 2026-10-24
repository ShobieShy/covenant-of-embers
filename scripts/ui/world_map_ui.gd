class_name WorldMapUI
extends Control
## The Elyria map screen (BUILD_PLAN step 69): one row per region, coloured by state
## (locked grey, known white, visited ember) with its barrier / wild tag.

const COLORS := [Color(0.45, 0.45, 0.45), Color(0.9, 0.9, 0.9), Color(1.0, 0.6, 0.2)]

var map: WorldMap
var rows := VBoxContainer.new()
var labels := {}


func _init() -> void:
	name = "WorldMapUI"
	set_anchors_preset(Control.PRESET_CENTER_LEFT)
	var panel := PanelContainer.new()
	add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var title := Label.new()
	title.text = "Elyria"
	v.add_child(title)
	v.add_child(rows)
	visible = false


func show_map(m: WorldMap) -> void:
	map = m
	for c in rows.get_children():
		c.free()
	labels.clear()
	var texts := m.lines()
	var i := 0
	for id in WorldMap.REGIONS:
		var l := Label.new()
		l.text = texts[i]
		l.add_theme_color_override(&"font_color", COLORS[m.state(id)])
		rows.add_child(l)
		labels[id] = l
		i += 1
	visible = true


func toggle(m: WorldMap) -> void:
	if visible:
		visible = false
	else:
		show_map(m)
