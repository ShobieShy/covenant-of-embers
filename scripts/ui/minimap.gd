class_name Minimap
extends Control
## OW8: the top-right minimap. Drawn from the world map texture (no second camera), centred on
## the local player, rotating with the camera unless Settings.minimap_north. Shows fog,
## waystones, exits, pins and co-op partners; partners off the edge clamp to the rim.

const SIZE := 160.0
const MARGIN := 16.0
const PX_PER_M := 0.8  ## 160 px covers 200 m
const FOG := Color(0.05, 0.05, 0.07, 0.92)

var tex: Texture2D
var fog: WorldFog
var pins: MapPins
var travel: WorldTravel
var players := Callable()  ## same rows as WorldMapScreen: [pos, yaw, name, colour, is_local]
var lock_north := false
var center := Vector2.ZERO  ## world x/z under the middle of the minimap
var yaw := 0.0  ## camera yaw; up on the minimap is where the camera looks
var _fog_tex: ImageTexture
var _fog_count := -1


func _init() -> void:
	name = "Minimap"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -SIZE - MARGIN
	offset_right = -MARGIN
	offset_top = MARGIN
	offset_bottom = MARGIN + SIZE

	if ResourceLoader.exists(WorldMapScreen.TEX):
		tex = load(WorldMapScreen.TEX)


func _process(_dt: float) -> void:
	if not visible:
		return
	_follow()
	queue_redraw()


## Centre and rotation from the local player row and the active camera.
func _follow() -> void:
	for p in rows():
		if p.size() > 4 and p[4]:
			center = Vector2(p[0].x, p[0].z)
			yaw = float(p[1])
			break
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		yaw = cam.global_rotation.y


func rows() -> Array:
	return players.call() if players.is_valid() else []


func _angle() -> float:
	return 0.0 if lock_north else yaw


## World point -> minimap pixel (unclamped). Camera forward (-z rotated by yaw) maps to up.
func world_to_mini(p: Vector3) -> Vector2:
	var d := (Vector2(p.x, p.z) - center) * PX_PER_M
	return size * 0.5 + d.rotated(_angle())


## Pulls a point outside the round minimap back onto its rim.
func clamp_rim(s: Vector2) -> Vector2:
	var c := size * 0.5
	var r := minf(c.x, c.y) - 6.0
	var d := s - c
	return c + d.limit_length(r)


func _rebuild_fog() -> void:
	if fog == null:
		return
	var n := fog.revealed_count()
	if n == _fog_count and _fog_tex:
		return
	_fog_count = n
	var img := Image.create(maxi(1, fog.cols), maxi(1, fog.rows), false, Image.FORMAT_RGBA8)
	for y in fog.rows:
		for x in fog.cols:
			var c := fog.origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * WorldFog.CELL
			img.set_pixel(x, y, Color(0, 0, 0, 0) if fog.is_revealed(c.x, c.y) else FOG)
	_fog_tex = ImageTexture.create_from_image(img)


func _draw() -> void:
	var mid := size * 0.5
	draw_circle(mid, mid.x, Color(0.02, 0.02, 0.03, 0.85))
	if fog:
		_rebuild_fog()
		# texture space: metre m sits at (m - origin) * tex_ppm; draw scaled to PX_PER_M
		var origin_px := (fog.origin - center) * PX_PER_M
		draw_set_transform(mid, _angle(), Vector2.ONE)
		var r := Rect2(origin_px, fog.size * PX_PER_M)
		if tex:
			draw_texture_rect(tex, r, false)
		if _fog_tex:
			draw_texture_rect(_fog_tex, r, false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if travel:
		for e in travel.exit_markers():
			var s := world_to_mini(e["pos"])
			if s.distance_to(mid) < mid.x:
				draw_circle(
					s, 3.0, Color(0.9, 0.8, 0.5) if e["kind"] == "road" else Color(0.6, 0.8, 1.0)
				)
		for p in travel.waystones:
			var on := travel.fast_travel.attuned(p) if travel.fast_travel else false
			var s := clamp_rim(world_to_mini(travel.point_world(p)))
			draw_circle(s, 5.0, Color(1.0, 0.55, 0.15) if on else Color(0.4, 0.4, 0.4))
	for p in pins.pins if pins else []:
		var s := clamp_rim(world_to_mini(Vector3(p[0], 0, p[1])))
		draw_colored_polygon(
			PackedVector2Array([s, s + Vector2(-4, -9), s + Vector2(4, -9)]), Color(0.9, 0.2, 0.3)
		)
	for pl in rows():
		var local: bool = pl.size() > 4 and pl[4]
		var s := mid if local else clamp_rim(world_to_mini(pl[0]))
		var d := Vector2(0, -1).rotated(_angle() - float(pl[1]))
		var c: Color = pl[3] if pl.size() > 3 else Color.WHITE
		draw_colored_polygon(
			PackedVector2Array([s + d * 8, s + d.rotated(2.5) * 6, s + d.rotated(-2.5) * 6]), c
		)
	draw_arc(mid, mid.x - 1.0, 0.0, TAU, 48, Color(0.8, 0.7, 0.5, 0.9), 2.0)
	if not lock_north:  # the N tick rides the rim
		draw_string(
			get_theme_default_font(),
			mid + Vector2(0, -(mid.x - 12)).rotated(_angle()) + Vector2(-4, 5),
			"N",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			12
		)
