class_name Hud
extends CanvasLayer
## In-game HUD (BUILD_PLAN step 29). Built in code (greybox Controls + Kenney Future font),
## CanvasLayer 2 so it sits above the viewmodel overlay (layer 1). `refresh(dt)` reads the
## player each frame (tests call it directly; _process does in game).
##  * bars: health (red), shield (cyan, pulses while regenerating), mana (Magewar mana_bar_hud
##    Color(0.2, 0.4, 1.0), flashes on Caster.out_of_mana), Breath (yellow, orange while exhausted)
##  * dash pips (charges / max_charges, next one fills with recharge_progress)
##  * crosshair: 4 ticks at gap = tan(cone) / tan(fov/2) x half-height; hidden while focused
##  * slot icons: staff/wand tinted rarity_color(), gem dot = element colour, active one
##    highlighted, draw filling from loadout.draw_progress()
##  * hint label (Player.hint, 1.5 s fade), hit / crit / kill marker (SpellBolts.bolt_hit),
##    wave banner + enemies left (EventBus), hurt edge flash, death overlay with countdown,
##    spawn-protection tint, level + XP line.

const LAYER := 2
const FONT_PATH := "res://assets/kenney/ui-pack/Font/Kenney Future.ttf"
const MANA_COLOR := Color(0.2, 0.4, 1.0)
const HEALTH_COLOR := Color(0.85, 0.2, 0.2)
const SHIELD_COLOR := Color(0.3, 0.85, 1.0)
const BREATH_COLOR := Color(0.95, 0.85, 0.3)
const BREATH_EXHAUSTED := Color(1.0, 0.45, 0.1)
const HINT_SECONDS := 1.5
const MARKER_SECONDS := 0.25
const FLASH_SECONDS := 0.3
const BANNER_SECONDS := 2.5
const BAR_SIZE := Vector2(260, 14)

var player: Player
var spawner: EnemySpawner
var root: Control
var health_bar: ProgressBar
var shield_bar: ProgressBar
var mana_bar: ProgressBar
var breath_bar: ProgressBar
var pips: Array[ProgressBar] = []
var pip_box: HBoxContainer
var crosshair: Crosshair
var slot_icons: Array[ColorRect] = []
var slot_gems: Array[ColorRect] = []
var slot_draw: Array[ProgressBar] = []
var hint_label: Label
var prompt_label: Label  ## step 46: the shared "[E] station" prompt
var marker: Label
var banner: Label
var level_label: Label
var hurt_flash: ColorRect
var death_overlay: ColorRect
var death_label: Label
var hint_left := 0.0
var marker_left := 0.0
var mana_flash_left := 0.0
var hurt_left := 0.0
var banner_left := 0.0
var markers := 0
var kill_markers := 0
var font: Font


## Tick marks around the screen centre.
class Crosshair:
	extends Control
	var gap := 4.0

	func _draw() -> void:
		var c := size * 0.5
		var col := Color(1, 1, 1, 0.9)
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * gap, c + d * (gap + 8.0), col, 2.0)
		draw_circle(c, 1.5, col)


func _init() -> void:
	layer = LAYER
	name = "Hud"
	font = load(FONT_PATH) as Font
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	hurt_flash = _rect(Color(0.8, 0, 0, 0), Control.PRESET_FULL_RECT)
	var bars := VBoxContainer.new()
	bars.position = Vector2(24, 24)
	root.add_child(bars)
	shield_bar = _bar(SHIELD_COLOR, bars)
	health_bar = _bar(HEALTH_COLOR, bars)
	mana_bar = _bar(MANA_COLOR, bars)
	breath_bar = _bar(BREATH_COLOR, bars)
	pip_box = HBoxContainer.new()
	bars.add_child(pip_box)
	level_label = _label(14, bars)
	crosshair = Crosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	marker = _label(28, root)
	marker.set_anchors_preset(Control.PRESET_CENTER)
	marker.text = "x"
	marker.visible = false
	var slots := HBoxContainer.new()
	slots.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	slots.position = Vector2(-200, -90)
	root.add_child(slots)
	for i in 2:
		var icon := ColorRect.new()
		icon.custom_minimum_size = Vector2(80, 56)
		slots.add_child(icon)
		var gem := ColorRect.new()
		gem.size = Vector2(12, 12)
		gem.position = Vector2(34, 8)
		icon.add_child(gem)
		var dr := ProgressBar.new()
		dr.show_percentage = false
		dr.max_value = 1.0
		dr.position = Vector2(4, 44)
		dr.size = Vector2(72, 8)
		icon.add_child(dr)
		slot_icons.append(icon)
		slot_gems.append(gem)
		slot_draw.append(dr)
	prompt_label = _label(18, root)
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.position = Vector2(-200, -200)
	prompt_label.size = Vector2(400, 30)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label = _label(20, root)
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.position = Vector2(-200, -160)
	hint_label.size = Vector2(400, 30)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner = _label(32, root)
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.position = Vector2(-300, 60)
	banner.size = Vector2(600, 40)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_overlay = _rect(Color(0, 0, 0, 0.6), Control.PRESET_FULL_RECT)
	death_overlay.visible = false
	death_label = _label(36, death_overlay)
	death_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _rect(c: Color, preset: int) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(preset)
	root.add_child(r)
	return r


func _label(px: int, parent: Control) -> Label:
	var l := Label.new()
	if font:
		l.add_theme_font_override(&"font", font)
	l.add_theme_font_size_override(&"font_size", px)
	l.add_theme_color_override(&"font_outline_color", Color.BLACK)
	l.add_theme_constant_override(&"outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(c: Color, parent: Control) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = BAR_SIZE
	b.max_value = 1.0
	b.step = 0.0
	b.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	var fg := StyleBoxFlat.new()
	fg.bg_color = c
	b.add_theme_stylebox_override(&"background", bg)
	b.add_theme_stylebox_override(&"fill", fg)
	parent.add_child(b)
	return b


static func bar_color(b: ProgressBar) -> Color:
	return (b.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color


func _set_bar_color(b: ProgressBar, c: Color) -> void:
	(b.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color = c


## Hooks the player (and optionally the spawner for the wave counter).
func bind(p: Player, sp: EnemySpawner = null) -> void:
	player = p
	spawner = sp
	p.hint.connect(show_hint)
	p.hurt.connect(func(_p: Player, _r: Damage.Result) -> void: hurt_left = FLASH_SECONDS)
	for c in p.loadout.casters:
		c.out_of_mana.connect(func(_c: float) -> void: mana_flash_left = FLASH_SECONDS)
	if p.bolts:
		p.bolts.bolt_hit.connect(_on_bolt_hit)
	var bus := GameEvents.bus()
	bus.wave_started.connect(func(i: int, id: String) -> void: show_banner("Wave %d: %s" % [i + 1, id.capitalize()]))
	bus.wave_cleared.connect(func(i: int, _id: String) -> void: show_banner("Wave %d cleared" % (i + 1)))
	bus.waves_completed.connect(func() -> void: show_banner("The Midden is quiet"))
	refresh(0.0)


func _exit_tree() -> void:
	# lambdas on the bus outlive the HUD otherwise
	var bus := GameEvents.bus()
	for s in [bus.wave_started, bus.wave_cleared, bus.waves_completed]:
		for c in s.get_connections():
			if c["callable"].get_object() == self:
				s.disconnect(c["callable"])


func show_hint(text: String) -> void:
	hint_label.text = text
	hint_left = HINT_SECONDS
	hint_label.modulate.a = 1.0


func show_banner(text: String) -> void:
	banner.text = text
	banner_left = BANNER_SECONDS


func _on_bolt_hit(h: SpellBolts.Hit) -> void:
	if not (h.collider is Enemy):
		return
	var e := h.collider as Enemy
	markers += 1
	marker_left = MARKER_SECONDS
	marker.visible = true
	if e.dead:
		kill_markers += 1
		marker.text = "X"
		marker.add_theme_color_override(&"font_color", Color(1, 0.3, 0.2))
	elif h.result != null and h.result.crit > 1.0:
		marker.text = "x"
		marker.add_theme_color_override(&"font_color", Color(1, 0.85, 0.2))
	else:
		marker.text = "x"
		marker.add_theme_color_override(&"font_color", Color.WHITE)


func _process(delta: float) -> void:
	refresh(delta)


## Crosshair gap in px for the current spread cone (0 at 100 % accuracy).
func crosshair_gap() -> float:
	var cone := player.spread.cone_deg(player.accuracy(), player.spread_stance())
	var half_h := root.get_viewport_rect().size.y * 0.5 if root.is_inside_tree() else 450.0
	return tan(deg_to_rad(cone)) / tan(deg_to_rad(player.camera.fov * 0.5)) * half_h


func refresh(dt: float) -> void:
	if player == null:
		return
	var h := player.health
	health_bar.value = h.fraction()
	shield_bar.value = h.shield_fraction()
	shield_bar.modulate.a = 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.006)) if h.regenerating() else 1.0
	mana_bar.value = player.mana.fraction()
	mana_flash_left = maxf(0.0, mana_flash_left - dt)
	_set_bar_color(mana_bar, MANA_COLOR.lerp(Color.WHITE, 0.7) if mana_flash_left > 0.0 else MANA_COLOR)
	breath_bar.value = player.breath.fraction()
	prompt_label.text = AssemblyStation.prompt_for(player)
	_set_bar_color(breath_bar, BREATH_EXHAUSTED if player.breath.exhausted else BREATH_COLOR)
	_refresh_pips()
	crosshair.visible = not player.focus.focused and player.alive()
	crosshair.gap = crosshair_gap() + 3.0
	crosshair.queue_redraw()
	var et := ElementTable.load_default()
	for i in 2:
		var w := player.loadout.wieldable(i)
		slot_icons[i].color = w.rarity_color() if w else Color(0.2, 0.2, 0.2, 0.5)
		slot_gems[i].visible = w != null
		if w:
			slot_gems[i].color = et.color(w.element())
		var on := player.loadout.active == i
		slot_icons[i].modulate = Color.WHITE if on else Color(1, 1, 1, 0.45)
		slot_draw[i].visible = on and player.loadout.swapping()
		slot_draw[i].value = player.loadout.draw_progress()
	hint_left = maxf(0.0, hint_left - dt)
	hint_label.modulate.a = clampf(hint_left / 0.5, 0.0, 1.0)
	hint_label.visible = hint_left > 0.0
	marker_left = maxf(0.0, marker_left - dt)
	marker.visible = marker_left > 0.0
	hurt_left = maxf(0.0, hurt_left - dt)
	hurt_flash.color.a = 0.35 * hurt_left / FLASH_SECONDS
	if player.protection_left > 0.0:
		hurt_flash.color = Color(0.3, 0.6, 1.0, 0.12)
	elif hurt_left <= 0.0:
		hurt_flash.color = Color(0.8, 0, 0, 0)
	else:
		hurt_flash.color = Color(0.8, 0, 0, hurt_flash.color.a)
	banner_left = maxf(0.0, banner_left - dt)
	var left := ""
	if spawner and spawner.wave_state == EnemySpawner.WaveState.ACTIVE:
		left = "  (%d left)" % spawner.wave_alive.size()
	banner.visible = banner_left > 0.0 or left != ""
	if banner_left <= 0.0 and left != "":
		banner.text = "Wave %d/%d%s" % [spawner.wave_index + 1, spawner.waves.size(), left]
	var pr := player.progression
	level_label.text = "Level %d   %d / %d XP" % [pr.level, pr.xp, pr.xp_to_next]
	death_overlay.visible = not player.alive()
	if death_overlay.visible:
		death_label.text = "You fell.\nRising in %.1f" % player.respawn_left


func _refresh_pips() -> void:
	var n := player.dash.max_charges()
	while pips.size() < n:
		var p := ProgressBar.new()
		p.custom_minimum_size = Vector2(30, 8)
		p.max_value = 1.0
		p.step = 0.0
		p.show_percentage = false
		pip_box.add_child(p)
		pips.append(p)
	while pips.size() > n:
		pips.pop_back().queue_free()
	for i in n:
		if i < player.dash.charges:
			pips[i].value = 1.0
		elif i == player.dash.charges:
			pips[i].value = player.dash.recharge_progress()
		else:
			pips[i].value = 0.0
