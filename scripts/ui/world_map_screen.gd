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


func _init() -> void:
	name = "WorldMapScreen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	if ResourceLoader.exists(TEX):
		tex = load(TEX)


func open() -> void:
	if fog == null:
		fog = WorldFog.new()
	if pins == null:
		pins = MapPins.new()
	_rebuild_fog()
	if size.x > 0.0 and tex:  # fit the world to the screen
		zoom = clampf(minf(size.x / tex.get_width(), size.y / tex.get_height()), ZOOM_MIN, ZOOM_MAX)
		pan = (size - Vector2(tex.get_size()) * zoom) * 0.5
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
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
	if not travel.can_travel(p):
		status = travel.last_error
		queue_redraw()
		return false
	travel_requested.emit(p)
	close()
	travel.travel_to(p)
	return true


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
	if (
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
