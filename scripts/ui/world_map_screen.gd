class_name WorldMapScreen
extends Control
## OW7: the open-world map (M). The world texture (world/map.png, tools/gen_world_map.py)
## with pan (drag) and zoom (wheel), fog of war (WorldFog), region names (Locked greyed),
## and markers: waystones (click an attuned one to fast travel), road exits, interior
## doors, custom pins (right click adds / removes, up to 32) and player arrows.

signal travel_requested(point: String)
signal closed

const TEX := "res://world/map.png"
const ZOOM_MIN := 0.5
const ZOOM_MAX := 6.0
const HIT := 10.0  ## px: how close a click must be to a marker
const FOG := Color(0.05, 0.05, 0.07, 0.92)
## 0.3.1 M7: the enemy levels a destination's zone holds (data/levels + data/labyrinth spawns).
const LEVEL_BAND := {
	"town_square": "Safe",
	"mage_association": "Safe",
	"old_oak": "Safe",
	"midden": "Lv 1-4",
	"breach": "Lv 1-5",
	"labyrinth": "Lv 5-12",
}

var tex: Texture2D
var fog: WorldFog
var pins: MapPins
var regions: WorldMap
var travel: WorldTravel
var players := Callable()  ## -> Array of [Vector3 position, float yaw, String name, Color]
var zoom := 1.0
var pan := Vector2.ZERO  ## screen offset of the map's top-left corner
var _fog_tex: ImageTexture
var _drag := false
var status := ""
var travel_mode := false  ## 0.3.1 M7: opened from a waystone; pins pick, a card confirms
var pending := ""  ## the waystone the confirm card is asking about
var card := PanelContainer.new()
var card_title := Label.new()
var card_info := Label.new()
var go_button := Button.new()
var list := VBoxContainer.new()  ## fallback: one button per attuned waystone
var list_buttons := {}


func _init() -> void:
	name = "WorldMapScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	if ResourceLoader.exists(TEX):
		tex = load(TEX)
	card.name = "TravelCard"
	card.set_anchors_preset(Control.PRESET_CENTER)
	var v := VBoxContainer.new()
	card.add_child(v)
	card_title.add_theme_font_size_override(&"font_size", 20)
	v.add_child(card_title)
	v.add_child(card_info)
	var h := HBoxContainer.new()
	v.add_child(h)
	go_button.text = "Travel"
	go_button.pressed.connect(confirm)
	h.add_child(go_button)
	var no := Button.new()
	no.text = "Cancel"
	no.pressed.connect(cancel)
	h.add_child(no)
	card.visible = false
	add_child(card)
	list.name = "TravelList"
	list.position = Vector2(16, 16)
	list.visible = false
	add_child(list)


## 0.3.1 M7: "Region" and "level band" lines for a destination's confirm card.
static func card_lines(point: String) -> PackedStringArray:
	var info := FastTravel.info(point)
	var level := String(info.get("level", ""))
	var reg := String(WorldMap.LEVEL_REGION.get(level, ""))
	var region := (
		String(WorldMap.REGIONS[reg]["name"])
		if WorldMap.REGIONS.has(reg)
		else ("The Warrens" if level == "labyrinth" else "Unknown")
	)
	return PackedStringArray(
		[
			String(info.get("name", point)),
			"Region: " + region,
			String(LEVEL_BAND.get(level, "Lv ?"))
		]
	)


## Open from a waystone: travel mode (pins pick a destination; the list is the fallback).
func open_travel() -> void:
	travel_mode = true
	open()
	_build_list()


func _build_list() -> void:
	for c in list.get_children():
		c.free()
	list_buttons.clear()
	var title := Label.new()
	title.text = "Travel to:"
	list.add_child(title)
	for p in travel.points() if travel else []:
		if not travel.fast_travel.attuned(p):
			continue
		var b := Button.new()
		b.text = String(FastTravel.info(p).get("name", p))
		b.pressed.connect(select.bind(p))
		list.add_child(b)
		list_buttons[p] = b
	list.visible = travel_mode and not list_buttons.is_empty()
	if list.visible:
		Gamepad.focus_first(list)


## Show the confirm card for `point` (from a pin or the list).
func select(point: String) -> bool:
	if travel == null or not travel.fast_travel.attuned(point):
		return false
	pending = point
	var l := card_lines(point)
	card_title.text = l[0]
	card_info.text = l[1] + "\n" + l[2]
	var ok := travel.can_travel(point)
	go_button.disabled = not ok
	if not ok:
		card_info.text += "\n" + travel.last_error
	card.visible = true
	UiAnim.fade_in(card)
	if ok and is_inside_tree():
		go_button.grab_focus.call_deferred()
	queue_redraw()
	return true


func cancel() -> void:
	pending = ""
	card.visible = false
	queue_redraw()


## Travel to the card's destination.
func confirm() -> bool:
	var p := pending
	if p.is_empty() or not travel.can_travel(p):
		status = travel.last_error if travel else ""
		queue_redraw()
		return false
	cancel()
	travel_requested.emit(p)
	close()
	travel.travel_to(p)
	return true


func open() -> void:
	if fog == null:
		fog = WorldFog.new()
	if pins == null:
		pins = MapPins.new()
	_rebuild_fog()
	if size.x > 0.0 and tex:  # fit the world to the screen
		zoom = clampf(minf(size.x / tex.get_width(), size.y / tex.get_height()), ZOOM_MIN, ZOOM_MAX)
		pan = (size - Vector2(tex.get_size()) * zoom) * 0.5
	UiAnim.open(self)  # 0.3.1 P1
	queue_redraw()


func close() -> void:
	cancel()
	travel_mode = false
	list.visible = false
	UiAnim.close(self)  # 0.3.1 P1
	closed.emit()


## Metres -> map texture pixels.
func _px_per_m() -> Vector2:
	if tex == null or fog == null or fog.size.x <= 0.0:
		return Vector2.ONE
	return Vector2(tex.get_size()) / fog.size


func world_to_screen(p: Vector3) -> Vector2:
	return pan + (Vector2(p.x, p.z) - fog.origin) * _px_per_m() * zoom


func screen_to_world(s: Vector2) -> Vector3:
	var m := (s - pan) / (_px_per_m() * zoom) + fog.origin
	return Vector3(m.x, 0.0, m.y)


func zoom_at(s: Vector2, factor: float) -> void:
	var w := screen_to_world(s)
	zoom = clampf(zoom * factor, ZOOM_MIN, ZOOM_MAX)
	pan += s - world_to_screen(w)
	queue_redraw()


## The attuned waystone under screen point `s`, or "".
func waystone_at(s: Vector2) -> String:
	if travel == null:
		return ""
	for p in travel.points():
		if (
			travel.fast_travel.attuned(p)
			and world_to_screen(travel.point_world(p)).distance_to(s) <= HIT
		):
			return p
	return ""


func click(s: Vector2) -> bool:
	var p := waystone_at(s)
	if p.is_empty():
		return false
	return select(p)  # 0.3.1 M7: a confirm card, not an instant jump


func right_click(s: Vector2) -> void:
	var w := screen_to_world(s)
	if _remove_px(s):
		status = "Pin removed."
	elif pins.add(w.x, w.z):
		status = "Pin placed."
	else:
		status = "No more pins (%d)." % MapPins.MAX
	queue_redraw()


func _remove_px(s: Vector2) -> bool:
	for i in pins.pins.size():
		var p: Array = pins.pins[i]
		if world_to_screen(Vector3(p[0], 0, p[1])).distance_to(s) <= HIT:
			pins.pins.remove_at(i)
			return true
	return false


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		var b := e as InputEventMouseButton
		match b.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom_at(b.position, 1.15)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom_at(b.position, 1.0 / 1.15)
			MOUSE_BUTTON_LEFT:
				_drag = not click(b.position)
			MOUSE_BUTTON_RIGHT:
				right_click(b.position)
	elif e is InputEventMouseButton and not e.pressed:
		_drag = false
	elif e is InputEventMouseMotion and _drag:
		pan += (e as InputEventMouseMotion).relative
		queue_redraw()
	accept_event()


func _unhandled_input(e: InputEvent) -> void:
	if visible and card.visible and e.is_action_pressed(&"ui_cancel"):
		cancel()
		get_viewport().set_input_as_handled()
	elif (
		visible
		and (
			e.is_action_pressed(&"ui_cancel")
			or (InputMap.has_action(&"map") and e.is_action_pressed(&"map"))
		)
	):
		close()
		get_viewport().set_input_as_handled()


func _rebuild_fog() -> void:
	var img := Image.create(maxi(1, fog.cols), maxi(1, fog.rows), false, Image.FORMAT_RGBA8)
	for y in fog.rows:
		for x in fog.cols:
			var c := fog.origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * WorldFog.CELL
			img.set_pixel(x, y, Color(0, 0, 0, 0) if fog.is_revealed(c.x, c.y) else FOG)
	_fog_tex = ImageTexture.create_from_image(img)


func _draw() -> void:
	if fog == null:
		return
	var r := Rect2(pan, (tex.get_size() if tex else fog.size) * zoom)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.03))
	if tex:
		draw_texture_rect(tex, r, false)
	if _fog_tex:
		draw_texture_rect(_fog_tex, r, false)  # linear filtering softens the cell edges
	var font := get_theme_default_font()
	var info := OpenWorld.load_info()
	for z in info.get("zones", {}):
		var reg := String(WorldMap.LEVEL_REGION.get(z, ""))
		if reg.is_empty() or regions == null:
			continue
		var wo: Array = info["zones"][z]["world_offset"]
		var locked := regions.state(reg) == WorldMap.State.LOCKED
		var at := world_to_screen(Vector3(wo[0], 0, wo[1])) + Vector2(0, -24)
		draw_string(
			font,
			at,
			String(WorldMap.REGIONS[reg]["name"]),
			HORIZONTAL_ALIGNMENT_CENTER,
			-1,
			18,
			Color(0.5, 0.5, 0.5) if locked else Color(1, 0.95, 0.85)
		)
	if travel:
		for e in travel.exit_markers():
			var c := Color(0.9, 0.8, 0.5) if e["kind"] == "road" else Color(0.6, 0.8, 1.0)
			draw_circle(world_to_screen(e["pos"]), 4.0, c)
		for p in travel.points():
			var on := travel.fast_travel.attuned(p)
			var s := world_to_screen(travel.point_world(p))
			draw_circle(s, 7.0, Color(1.0, 0.55, 0.15) if on else Color(0.4, 0.4, 0.4))
			if on and (travel_mode or p == pending):  # M7: clickable pins get a ring
				draw_arc(
					s,
					11.0,
					0.0,
					TAU,
					24,
					Color(1, 0.9, 0.6) if p == pending else Color(1, 0.7, 0.3, 0.7),
					2.0
				)
			if on:
				draw_string(
					font,
					s + Vector2(9, 5),
					String(FastTravel.info(p).get("name", p)),
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					14
				)
	for p in pins.pins if pins else []:
		var s := world_to_screen(Vector3(p[0], 0, p[1]))
		draw_colored_polygon(
			PackedVector2Array([s, s + Vector2(-5, -12), s + Vector2(5, -12)]), Color(0.9, 0.2, 0.3)
		)
	for pl in players.call() if players.is_valid() else []:
		var s := world_to_screen(pl[0])
		var d := Vector2(0, -1).rotated(-float(pl[1]))
		var c: Color = pl[3] if pl.size() > 3 else Color.WHITE
		draw_colored_polygon(
			PackedVector2Array([s + d * 10, s + d.rotated(2.5) * 7, s + d.rotated(-2.5) * 7]), c
		)
		if pl.size() > 2 and String(pl[2]) != "":
			draw_string(
				font, s + Vector2(10, -6), String(pl[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c
			)
	if status != "":
		draw_string(font, Vector2(20, size.y - 20), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
