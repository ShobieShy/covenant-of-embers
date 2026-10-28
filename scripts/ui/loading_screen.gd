class_name LoadingScreen
extends CanvasLayer
## Loading screen (after batch 07): covers scene changes (initial load, waystone travel,
## instanced interiors). Pixel UI theme, an ember spinner, a stage label, a rotating tip
## and the region's map painting behind it. The bar follows real stages, never a timer:
##   1. threaded ResourceLoader for the target scene (main.tscn)     0 .. 0.35
##   2. threaded ResourceLoader for the level scene main swaps in    0.35 .. 0.70
##   3. scene change (main._ready instantiates the cached level)     0.70 .. 0.80
##   4. Terrain3D ready (every TerrainZone has its terrain)          0.80 .. 0.90
##   5. navmesh ready (LevelNavigation.map_ready())                  0.90 .. 1.00
## Nothing here blocks: loads are polled once a frame. It lives on the root (not the
## current scene) so it survives the change. A stage that cannot finish (missing GDExtension,
## no navigation) gives up after STAGE_TIMEOUT and the screen still closes.

enum Stage { SCENE, LEVEL, SWAP, TERRAIN, NAV, DONE }
const STAGE_TEXT := [
	"Loading", "Loading the region", "Entering", "Raising the land", "Charting paths", "Ready"
]
const STAGE_RANGE := [[0.0, 0.35], [0.35, 0.7], [0.7, 0.8], [0.8, 0.9], [0.9, 1.0], [1.0, 1.0]]
const STAGE_TIMEOUT := 20.0
const TIP_SECONDS := 4.0
const TIPS := [
	"Waystones you have touched can take you back from the world map.",
	"Crystal reloads restore mana, but only the Pyrowning ones refill half of it.",
	"Hidden chests glow faintly blue; vaults need a key from the region boss.",
	"Your partner's arrow on the HUD points to where they are.",
	"Brands stack with gem slots. Check the compare card before you swap.",
	"Filth slows you. Burn it away with fire spells.",
	"Press M for the world map.",
	# 0.3.1 P6 (L3): Labyrinth, brands and co-op.
	"Labyrinth stairs need every player on them: hold Interact to vote to go down.",
	"Each Labyrinth Act ends in a boss; its first kill drops a unique.",
	"Each save has its own Labyrinth layout; cleared floors can be re-rolled for farming.",
	"A Moss & Berg brand bursts on impact; Sigil Sauer chains when fully charged.",
	"Hexler & Koch brands hit weak points harder. Aim for the glow.",
	"In co-op, Light bolts heal your partner instead of hurting them.",
	"In co-op, a downed partner bleeds out slowly. Get to them and revive them.",
]
const SMOOTH_RATE := 1.5  ## P6: bar fill per second at most, so a jump eases in
const SMOOTH_EASE := 8.0  ## and an exponential catch-up on top

var target := ""
var level_id := ""
var stage := Stage.SCENE
var progress := 0.0  ## 0..1, monotonic
var shown := 0.0  ## P6 (L3): the bar's smoothed value, never ahead of progress
var tip_index := 0
var _t_stage := 0.0
var _t_tip := 0.0
var _tree: SceneTree
var _swapped := false
var bar: ProgressBar
var stage_label: Label
var tip_label: Label
var backdrop: TextureRect
var ember: Control

static var active: LoadingScreen = null
static var dry_run := false  ## tests: build the screen but never change scenes
## OW5: an overlay screen driven by its caller (advance / done), never changing scenes:
## instanced interiors show it over the world when a load runs long.
var manual := false


## An overlay for a load the caller runs itself (Interiors); close it with done().
static func overlay(tree: SceneTree, level := "") -> LoadingScreen:
	if active and is_instance_valid(active):
		active.queue_free()
	var s := LoadingScreen.new()
	s.manual = true
	s.level_id = level
	s._tree = tree
	tree.root.add_child(s)
	active = s
	return s


func done() -> void:
	advance(Stage.DONE, 1.0)
	_finish()


## Starts a load of `path` (and `level` for the game scene); returns the screen.
static func start(tree: SceneTree, path: String, level := "") -> LoadingScreen:
	if active and is_instance_valid(active):
		active.queue_free()
	var s := LoadingScreen.new()
	s.target = path
	s.level_id = level
	s._tree = tree
	tree.root.add_child.call_deferred(s)
	active = s
	return s


## P6 (L3): the Act art for the level (loading_<level>, then loading_<region>), else the
## region's map painting.
static func painting_for(level: String) -> Texture2D:
	var region := String(WorldMap.LEVEL_REGION.get(level, "eldoria"))
	var keys := ["loading/loading_" + level, "loading/loading_" + region]
	if level.contains("warrens") or level.contains("labyrinth"):
		keys.push_front("loading/loading_warrens")
	for k in keys:
		if EmberArt.has_art(k):
			return EmberArt.texture(k)
	return EmberArt.texture("map_" + region)


## QA r14 (L2): the co-op join phase lives here, since the co-op menu is gone by now:
## "Co-op: loading the world - " while a session is live, else "".
static func coop_phase() -> String:
	var ss: NetSession = Coop.session
	if ss == null or not is_instance_valid(ss):
		return ""
	if ss.state == NetSession.State.LOBBY or ss.state == NetSession.State.IN_GAME:
		return "Co-op: loading the world - "
	return ""


static func level_path(level: String) -> String:
	return GameFlow.level_scene(level) if level != "" else ""


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	tip_index = randi() % TIPS.size()
	_build_ui()
	if dry_run or manual:
		return
	SafeLoad.request(target, "PackedScene")
	_requests.append(target)
	if level_id != "":
		SafeLoad.request(level_path(level_id), "PackedScene")
		_requests.append(level_path(level_id))


## Threaded requests not yet collected. A screen freed mid-load (a test, a quit) collects
## them, so the loader never hands a stale half-finished request to the next load.
var _requests: Array[String] = []


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for r in _requests:
			SafeLoad.take(r)
		_requests.clear()


func _build_ui() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.06)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	backdrop = TextureRect.new()
	backdrop.name = "Painting"
	backdrop.texture = painting_for(level_id)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	backdrop.modulate = Color(0.55, 0.5, 0.5)
	root.add_child(backdrop)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override(
		&"panel", UiTheme.box("panels_9slice/pixel_ui/Ancient/brown.png", 16)
	)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.custom_minimum_size = Vector2(900, 170)
	panel.offset_left = -450
	panel.offset_right = 450
	panel.offset_top = -230
	panel.offset_bottom = -60
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", 10)
	panel.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	ember = _Ember.new()
	ember.name = "Ember"
	ember.custom_minimum_size = Vector2(40, 40)
	h.add_child(ember)
	stage_label = Label.new()
	stage_label.name = "Stage"
	stage_label.add_theme_color_override(&"font_color", UiTheme.GOLD)
	h.add_child(stage_label)
	bar = ProgressBar.new()
	bar.name = "Bar"
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.001
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 22)
	var fill := UiTheme.box("bars_sliders/bar_fill_xp.png", 3, Color.WHITE, 0)
	var under := UiTheme.box("bars_sliders/bar_under.png", 3, Color.WHITE, 0)
	bar.add_theme_stylebox_override(&"fill", fill)
	bar.add_theme_stylebox_override(&"background", under)
	v.add_child(bar)
	UiTheme.frame_bar(bar)
	tip_label = Label.new()
	tip_label.name = "Tip"
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.add_theme_font_size_override(&"font_size", 24)
	tip_label.add_theme_color_override(&"font_color", UiTheme.PARCHMENT)
	v.add_child(tip_label)
	_refresh()


func _refresh() -> void:
	if stage_label == null:
		return  # before _ready
	stage_label.text = coop_phase() + "%s... %d%%" % [STAGE_TEXT[stage], int(progress * 100.0)]
	var tip := "Tip: " + String(TIPS[tip_index])
	if tip_label.text != tip:
		tip_label.text = tip
		UiAnim.fade_in(tip_label, 0.3)
	if UiAnim.instant() or not is_inside_tree():
		shown = progress
	bar.value = shown


## Moves to stage `s` at sub-progress `f` (0..1). Progress never goes back.
func advance(s: int, f := 0.0) -> void:
	if s > stage:
		stage = s as Stage
		_t_stage = 0.0
	var r: Array = STAGE_RANGE[stage]
	progress = maxf(progress, lerpf(r[0], r[1], clampf(f, 0.0, 1.0)))
	_refresh()


## P6 (L3): eases `shown` toward `progress` (capped rate plus exponential catch-up).
func smooth(delta: float) -> void:
	if UiAnim.instant():
		shown = progress
	else:
		var step := maxf(
			SMOOTH_RATE * delta, (progress - shown) * (1.0 - exp(-SMOOTH_EASE * delta))
		)
		shown = minf(progress, shown + minf(step, SMOOTH_RATE * delta * 4.0))
	if bar:
		bar.value = shown


func _process(delta: float) -> void:
	smooth(delta)
	_t_tip += delta
	if _t_tip >= TIP_SECONDS:
		_t_tip = 0.0
		tip_index = (tip_index + 1) % TIPS.size()
		_refresh()
	if dry_run or manual:
		return
	_t_stage += delta
	var timed_out := _t_stage > STAGE_TIMEOUT
	match stage:
		Stage.SCENE:
			var f := _poll(target)
			if f >= 1.0 or timed_out:
				advance(Stage.LEVEL if level_id != "" else Stage.SWAP)
			else:
				advance(Stage.SCENE, f)
		Stage.LEVEL:
			var f := _poll(level_path(level_id))
			if f >= 1.0 or timed_out:
				advance(Stage.SWAP)
			else:
				advance(Stage.LEVEL, f)
		Stage.SWAP:
			if not _swapped:
				_swapped = true
				var ps := SafeLoad.take(target) as PackedScene
				_requests.erase(target)
				_tree.paused = false
				if ps:
					_tree.change_scene_to_packed(ps)
				else:
					_tree.change_scene_to_file(target)
			elif _tree.current_scene and _tree.current_scene.is_node_ready():
				if level_id != "":
					SafeLoad.take(level_path(level_id))  # drop the request
					_requests.erase(level_path(level_id))
				advance(Stage.TERRAIN)
		Stage.TERRAIN:
			if terrain_ready(_tree.current_scene) or timed_out:
				advance(Stage.NAV)
		Stage.NAV:
			if nav_ready(_tree.current_scene) or timed_out:
				advance(Stage.DONE, 1.0)
				_finish()


func _poll(path: String) -> float:
	var p := []
	var st := SafeLoad.status(path, p)
	match st:
		ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			return 1.0
	return float(p[0]) if p.size() > 0 else 0.0


static func _collect(n: Node, out: Array, want: Script) -> void:
	if n == null:
		return
	if n.get_script() == want:
		out.append(n)
	for c in n.get_children():
		_collect(c, out, want)


## True when every TerrainZone under `scene` has built its Terrain3D (or the extension is missing).
static func terrain_ready(scene: Node) -> bool:
	var zones := []
	_collect(scene, zones, TerrainZone)
	for z: TerrainZone in zones:
		if TerrainZone.available() and z.terrain == null:
			return false
	return true


## True when every LevelNavigation under `scene` reports map_ready (none: ready).
static func nav_ready(scene: Node) -> bool:
	var navs := []
	_collect(scene, navs, LevelNavigation)
	for n: LevelNavigation in navs:
		if not n.map_ready():
			return false
	return true


func _finish() -> void:
	var tw := create_tween()
	tw.tween_property(get_node("Root"), "modulate:a", 0.0, 0.35)
	tw.tween_callback(queue_free)
	if active == self:
		active = null


## A pulsing ember: 8 pixel squares orbiting a glowing core.
class _Ember:
	extends Control
	var t := 0.0

	func _process(d: float) -> void:
		t += d
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var glow := 0.75 + 0.25 * sin(t * 6.0)
		draw_rect(Rect2(c - Vector2(5, 5), Vector2(10, 10)), Color(1.0, 0.55, 0.15) * glow)
		for i in 8:
			var a := t * 3.0 + i * TAU / 8.0
			var p := c + Vector2(cos(a), sin(a)) * 14.0
			var k := float(i) / 8.0
			draw_rect(
				Rect2((p - Vector2(2, 2)).floor(), Vector2(4, 4)),
				Color(1.0, 0.35 + 0.4 * k, 0.1, 0.3 + 0.7 * k)
			)
