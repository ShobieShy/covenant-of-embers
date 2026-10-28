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
const CHIP_COLOR := Color(1.0, 0.93, 0.72, 0.85)  ## 0.3.1 P4 (M3): trailing damage chip
const TOAST_S := 3.0  ## M2: pickup toast life
const TOAST_FADE_S := 0.5
const TOAST_MAX := 5
const LEVEL_BANNER_S := 2.8  ## M4
const BADGE_COLOR := Color(1.0, 0.82, 0.25)
const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float strength = 0.0;
uniform vec4 tint : source_color = vec4(0.75, 0.0, 0.05, 1.0);
void fragment() {
	float d = distance(UV, vec2(0.5));
	COLOR = vec4(tint.rgb, strength * smoothstep(0.32, 0.72, d));
}
"""

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
var stats_box: VBoxContainer  ## the top-left bars + level line (QA r14: party frames sit below it)
var hurt_flash: ColorRect
var death_overlay: ColorRect
var death_label: Label
var boss_label: Label  ## step 56: boss name + phase pips
var boss_bar: ProgressBar
var brand_meter: BrandMeter  ## step 140: heat/charge/spin/burst/pool under the crosshair
var hint_left := 0.0
var marker_left := 0.0
var mana_flash_left := 0.0
var hurt_left := 0.0
var banner_left := 0.0
var markers := 0
var kill_markers := 0
var font: Font
var chips := {}  ## M3: ProgressBar -> HudFx.Chip
var chip_rects := {}  ## M3: ProgressBar -> ColorRect (the trailing segment)
var chip_boss: Object  ## M3: the boss the boss chip belongs to
var vignette: ColorRect  ## M3: low-health heartbeat
var beat_t := 0.0
var toast_box: VBoxContainer  ## M2: pickup toast stack
var toasts: Array[Dictionary] = []  ## {label, text, count, age}
var level_banner: Label  ## M4
var level_burst: CPUParticles2D  ## M4
var level_left := 0.0
var level_ups := 0
var skill_badge: Label  ## M4: unspent skill points


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


## Step 140 (Brands B6): the held brand's logo, a 96x6 meter and its short text, centred
## under the crosshair; hidden for unbranded wieldables and empty hands.
class BrandMeter:
	extends Control
	const COLORS := {
		&"heat": Color(1.0, 0.45, 0.1),
		&"charge": Color(0.35, 0.65, 1.0),
		&"spin": Color(0.9, 0.97, 1.0),
		&"burst": Color(1.0, 0.85, 0.35),
		&"pool": Color(0.7, 0.4, 1.0),
	}
	var logo: Texture2D
	var value := 0.0
	var kind := &""
	var text := ""
	var font: Font
	var hot := false  ## overheated / venting: the bar flashes

	func show_mode(m: FireMode) -> void:
		visible = m != null and m.brand != null
		if not visible:
			return
		logo = m.brand.logo()
		value = clampf(m.meter(), 0.0, 1.0)
		kind = m.meter_kind()
		text = m.meter_text()
		hot = (m.fx_bits() & 2) != 0
		queue_redraw()

	func meter_color() -> Color:
		var c: Color = COLORS.get(kind, Color.WHITE)
		if kind == &"heat":
			c = Color(1.0, 0.75, 0.3).lerp(Color(1.0, 0.15, 0.05), value)
		if hot and int(Time.get_ticks_msec() / 120) % 2 == 0:
			c = Color.WHITE
		return c

	func _draw() -> void:
		var c := size * 0.5 + Vector2(0, 46)
		var bar := Rect2(c + Vector2(-40, 0), Vector2(96, 6))
		if logo != null:
			draw_texture_rect(logo, Rect2(c + Vector2(-62, -5), Vector2(16, 16)), false)
		draw_rect(bar.grow(1.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * value, bar.size.y)), meter_color())
		if font != null and not text.is_empty():
			draw_string(font, c + Vector2(-40, 22), text, HORIZONTAL_ALIGNMENT_LEFT, 120, 12, meter_color())


func _init() -> void:
	layer = LAYER
	name = "Hud"
	add_to_group(&"hud")  # step 112: IntroDirector.refuse finds it
	font = load(FONT_PATH) as Font
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	hurt_flash = _rect(Color(0.8, 0, 0, 0), Control.PRESET_FULL_RECT)
	vignette = _rect(Color.WHITE, Control.PRESET_FULL_RECT)
	vignette.name = "HeartbeatVignette"
	var vm := ShaderMaterial.new()
	var vs := Shader.new()
	vs.code = VIGNETTE_SHADER
	vm.shader = vs
	vignette.material = vm
	vignette.visible = false
	var bars := VBoxContainer.new()
	bars.position = Vector2(24, 24)
	root.add_child(bars)
	stats_box = bars
	shield_bar = _bar(SHIELD_COLOR, bars)
	health_bar = _bar(HEALTH_COLOR, bars)
	mana_bar = _bar(MANA_COLOR, bars)
	breath_bar = _bar(BREATH_COLOR, bars)
	pip_box = HBoxContainer.new()
	bars.add_child(pip_box)
	level_label = _label(14, bars)
	skill_badge = _label(14, bars)
	skill_badge.name = "SkillBadge"
	skill_badge.add_theme_color_override(&"font_color", BADGE_COLOR)
	skill_badge.visible = false
	crosshair = Crosshair.new()
	crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(crosshair)
	brand_meter = BrandMeter.new()
	brand_meter.set_anchors_preset(Control.PRESET_FULL_RECT)
	brand_meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand_meter.font = font
	brand_meter.visible = false
	root.add_child(brand_meter)
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
	var boss_box := VBoxContainer.new()
	boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_box.position = Vector2(-220, 16)
	boss_box.custom_minimum_size = Vector2(440, 0)
	root.add_child(boss_box)
	boss_label = _label(18, boss_box)
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_bar = _bar(Color(0.55, 0.75, 0.2), boss_box)
	boss_bar.custom_minimum_size = Vector2(440, 14)
	boss_box.visible = false
	for b in [health_bar, shield_bar, boss_bar]:
		_add_chip(b)
	toast_box = VBoxContainer.new()
	toast_box.name = "Toasts"
	toast_box.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	toast_box.position = Vector2(-340, 40)
	toast_box.custom_minimum_size = Vector2(320, 0)
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)
	level_banner = _label(40, root)
	level_banner.name = "LevelBanner"
	level_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	level_banner.position = Vector2(-300, 120)
	level_banner.size = Vector2(600, 56)
	level_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_banner.add_theme_color_override(&"font_color", BADGE_COLOR)
	level_banner.visible = false
	level_burst = CPUParticles2D.new()
	level_burst.name = "LevelBurst"
	level_burst.emitting = false
	level_burst.one_shot = true
	level_burst.amount = 48
	level_burst.lifetime = 0.9
	level_burst.explosiveness = 1.0
	level_burst.direction = Vector2(0, -1)
	level_burst.spread = 180.0
	level_burst.initial_velocity_min = 120.0
	level_burst.initial_velocity_max = 320.0
	level_burst.gravity = Vector2(0, 260)
	level_burst.scale_amount_min = 3.0
	level_burst.scale_amount_max = 6.0
	level_burst.color = BADGE_COLOR
	level_burst.position = Vector2(300, 28)
	level_banner.add_child(level_burst)
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
	UiTheme.frame_bar(b)  # step 126
	return b


static func bar_color(b: ProgressBar) -> Color:
	return (b.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color


func _set_bar_color(b: ProgressBar, c: Color) -> void:
	(b.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color = c


## M3: a trailing chip segment drawn over the empty part of `b`.
func _add_chip(b: ProgressBar) -> void:
	var r := ColorRect.new()
	r.name = "Chip"
	r.color = CHIP_COLOR
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.visible = false
	b.add_child(r)
	chips[b] = HudFx.Chip.new()
	chip_rects[b] = r


## M3: step `b`'s chip toward `target` and draw the bar from it.
func _set_chip(b: ProgressBar, target: float, dt: float) -> void:
	var c: HudFx.Chip = chips[b]
	c.step(target, dt)
	b.value = c.shown
	var r: ColorRect = chip_rects[b]
	var w := b.size.x if b.size.x > 0.0 else b.custom_minimum_size.x
	var hgt := b.size.y if b.size.y > 0.0 else b.custom_minimum_size.y
	r.visible = c.chip > c.shown + 1e-3
	r.position = Vector2(c.shown * w, 0)
	r.size = Vector2(maxf(0.0, c.chip - c.shown) * w, hgt)


## M2: a pickup toast; a repeat of the newest live toast counts up instead ("x3").
func add_toast(text: String, color := Color.WHITE) -> void:
	if not toasts.is_empty():
		var last: Dictionary = toasts[-1]
		if last["text"] == text and last["age"] < TOAST_S - TOAST_FADE_S:
			last["count"] += 1
			last["age"] = 0.0
			(last["label"] as Label).text = "%s  x%d" % [text, last["count"]]
			UiAnim.pulse(last["label"], 0.1)
			return
	var l := _label(16, toast_box)
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_color_override(&"font_color", color)
	toasts.append({"label": l, "text": text, "count": 1, "age": 0.0})
	while toasts.size() > TOAST_MAX:
		(toasts.pop_front()["label"] as Label).queue_free()


func _tick_toasts(dt: float) -> void:
	for i in range(toasts.size() - 1, -1, -1):
		var t: Dictionary = toasts[i]
		t["age"] += dt
		var l: Label = t["label"]
		if t["age"] >= TOAST_S:
			l.queue_free()
			toasts.remove_at(i)
		else:
			l.modulate.a = clampf((TOAST_S - t["age"]) / TOAST_FADE_S, 0.0, 1.0)


static func toast_text(lp: LootPickup, what: String) -> String:
	match what:
		"item":
			return lp.drop.describe() if lp != null and lp.drop != null else "Item"
		"gold":
			return "+%d Gold" % lp.amount
		"dust":
			return "+%d Arcane Dust" % lp.amount
		"potion":
			return lp.potion.display_name if lp != null and lp.potion != null else "Potion"
	return ""  # mana orbs: the bar says it


func _on_collected(lp: LootPickup, what: String) -> void:
	var t := toast_text(lp, what)
	if t != "":
		add_toast(t, lp.color if lp != null else Color.WHITE)


## M4: the level-up moment (GameAudio plays level_up).
func _on_level_up(lv: int) -> void:
	level_ups += 1
	level_banner.text = "Level %d!" % lv
	level_left = LEVEL_BANNER_S
	level_banner.visible = true
	level_banner.modulate.a = 1.0
	UiAnim.pulse(level_banner, 0.25)
	if not UiAnim.instant():
		level_burst.restart()


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
	p.pickups.collected.connect(_on_collected)  # 0.3.1 P4
	p.progression.leveled_up.connect(_on_level_up)
	var bus := GameEvents.bus()
	bus.wave_started.connect(func(i: int, id: String) -> void: show_banner("Wave %d: %s" % [i + 1, id.capitalize()]))
	bus.wave_cleared.connect(func(i: int, _id: String) -> void: show_banner("Wave %d cleared" % (i + 1)))
	bus.waves_completed.connect(func() -> void: show_banner("The Landfill is quiet"))
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
	root.visible = Cinematic.playing == null  # cinematics own the screen (no 0-HP bar mid-summoning)
	if player == null:
		return
	var h := player.health
	_set_chip(health_bar, h.fraction(), dt)  # 0.3.1 P4 (M3)
	_set_chip(shield_bar, h.shield_fraction(), dt)
	beat_t += dt
	var va := HudFx.heartbeat(h.fraction(), beat_t, UiAnim.reduced_motion) if player.alive() else 0.0
	vignette.visible = va > 0.0
	(vignette.material as ShaderMaterial).set_shader_parameter(&"strength", va)
	_tick_toasts(dt)
	level_left = maxf(0.0, level_left - dt)
	level_banner.visible = level_left > 0.0
	level_banner.modulate.a = clampf(level_left / 0.6, 0.0, 1.0)
	shield_bar.modulate.a = 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() * 0.006)) if h.regenerating() else 1.0
	mana_bar.value = player.mana.fraction()
	mana_flash_left = maxf(0.0, mana_flash_left - dt)
	_set_bar_color(mana_bar, MANA_COLOR.lerp(Color.WHITE, 0.7) if mana_flash_left > 0.0 else MANA_COLOR)
	breath_bar.value = player.breath.fraction()
	prompt_label.text = Interaction.prompt(player)
	_set_bar_color(breath_bar, BREATH_EXHAUSTED if player.breath.exhausted else BREATH_COLOR)
	_refresh_pips()
	crosshair.visible = not player.focus.focused and player.alive()
	crosshair.gap = crosshair_gap() + 3.0
	crosshair.queue_redraw()
	var cst := player.caster
	brand_meter.show_mode(cst.fire_mode() if cst != null and player.alive() else null)
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
	_refresh_boss()
	var pr := player.progression
	level_label.text = "Level %d   %d / %d XP   %d Gold" % [pr.level, pr.xp, pr.xp_to_next, player.inventory.gold]
	var sp := player.skills.available(pr.level)
	skill_badge.visible = sp > 0
	if sp > 0:
		skill_badge.text = skill_badge_text(sp)
	death_overlay.visible = not player.alive()
	if death_overlay.visible:
		if player.downed:
			death_label.text = "Down! %.0f s\nA friend standing beside you revives you." % player.downed_left
		else:
			death_label.text = "You fell.\nRising in %.1f" % player.respawn_left


## Step 56: the boss bar shows the nearest living Filth that has a target (pips = phases).
func _refresh_boss() -> void:
	var boss: Filth = null
	if player.is_inside_tree():
		for n in player.get_tree().get_nodes_in_group(Enemy.GROUP):
			var f := n as Filth
			if f != null and f.alive() and f.target != null:
				boss = f
				break
	boss_bar.get_parent().visible = boss != null
	if boss == null:
		return
	if chip_boss != boss:
		chip_boss = boss
		(chips[boss_bar] as HudFx.Chip).started = false  # a new boss starts full, no chip
	_set_chip(boss_bar, boss.health / boss.max_health(), get_process_delta_time())
	boss_label.text = "%s  %s" % [boss.def.display_name, "◆".repeat(boss.phase) + "◇".repeat(3 - boss.phase)]


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


## M4: "◆ 2 skill points  [K]" (the same text on the pause menu's Skills entry count).
static func skill_badge_text(n: int) -> String:
	return "◆ %d skill point%s  [K]" % [n, "" if n == 1 else "s"]
