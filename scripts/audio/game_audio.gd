class_name GameAudio
extends Node
## Game sounds (BUILD_PLAN step 37): Kenney CC0 packs (assets/kenney/impact-sounds,
## interface-sounds, ui-pack) on the SFX / UI buses (default_bus_layout.tres: Master, SFX,
## UI, Music; Music has no track yet). bind(player) hooks the player's verbs; enemies are
## hooked as EventBus.enemy_spawned announces them (3D sounds at the enemy). Player-side
## counters (landings, dash.dashes, casters' casts) are polled each physics frame so no
## gameplay code needs to know about audio. `played` counts each key (tests).

const IMPACT := "res://assets/kenney/impact-sounds/Audio/"
const IFACE := "res://assets/kenney/interface-sounds/Audio/"
const UIPACK := "res://assets/kenney/ui-pack/Sounds/"
const EMBER_SFX := "res://assets/original/ember_art/sfx/"
const BUSES: PackedStringArray = ["Master", "SFX", "UI", "Music"]
const SOUNDS := {
	"cast": IFACE + "glass_002.ogg",
	# 0.3.1 P5 (M5): one cast sound per element (batch 09, CC0); "cast" is the fallback.
	"cast_arcane": EMBER_SFX + "cast_arcane.ogg",
	"cast_fire": EMBER_SFX + "cast_fire.ogg",
	"cast_water": EMBER_SFX + "cast_water.ogg",
	"cast_earth": EMBER_SFX + "cast_earth.ogg",
	"cast_air": EMBER_SFX + "cast_air.ogg",
	"cast_light": EMBER_SFX + "cast_light.ogg",
	"cast_dark": EMBER_SFX + "cast_dark.ogg",
	"cast_fail": IFACE + "error_004.ogg",
	"focus": IFACE + "maximize_003.ogg",
	"equip": UIPACK + "switch-a.ogg",
	"dash": IFACE + "minimize_006.ogg",
	"land": IMPACT + "footstep_concrete_000.ogg",
	"footstep": IMPACT + "footstep_concrete_001.ogg",
	"hit": IMPACT + "impactGeneric_light_000.ogg",
	"enemy_death": IMPACT + "impactMetal_heavy_000.ogg",
	"kill": IFACE + "confirmation_001.ogg",
	"hurt": IMPACT + "impactPunch_medium_000.ogg",
	"shield_break": IMPACT + "impactGlass_heavy_000.ogg",
	"player_death": IMPACT + "impactBell_heavy_000.ogg",
	"respawn": IFACE + "confirmation_003.ogg",
	"wave_start": IFACE + "bong_001.ogg",
	"wave_clear": IFACE + "confirmation_002.ogg",
	"slam_windup": IMPACT + "impactMining_000.ogg",
	"slam": IMPACT + "impactPlate_heavy_000.ogg",
	"ui_click": UIPACK + "click-a.ogg",
	"pickup": IFACE + "drop_002.ogg",
	"vote_tick": IFACE + "tick_001.ogg",  # 0.3.1 P2: the stairs vote's last 3 s
	# 0.3.1 P4 (M2/M4): Ember Art batch_09_polish, original CC0 synth
	"level_up": EMBER_SFX + "level_up.ogg",
	"pickup_basic": EMBER_SFX + "pickup_basic.ogg",
	"pickup_uncommon": EMBER_SFX + "pickup_uncommon.ogg",
	"pickup_rare": EMBER_SFX + "pickup_rare.ogg",
	"pickup_mythic": EMBER_SFX + "pickup_mythic.ogg",
	"pickup_primordial": EMBER_SFX + "pickup_primordial.ogg",
	"pickup_unique": EMBER_SFX + "pickup_unique.ogg",
	# step 141 (Brands B7): brand fire-mode sounds, same Kenney CC0 packs
	"brand_overheat": IFACE + "error_006.ogg",
	"brand_vent": IFACE + "scratch_004.ogg",
	"brand_crystal_eject": IMPACT + "impactGlass_light_000.ogg",  # t69u
	"brand_crystal_set": IFACE + "glass_002.ogg",
	"brand_charge_full": IFACE + "maximize_005.ogg",
	"brand_charge_release": IFACE + "glass_005.ogg",
	"brand_blast": IMPACT + "impactMining_002.ogg",
	"brand_spin_full": IFACE + "tick_002.ogg",
	"brand_burst": IFACE + "click_003.ogg",
	"brand_toggle": IFACE + "switch_004.ogg",
	"brand_orb": IFACE + "maximize_008.ogg",
	"brand_crit": IMPACT + "impactGlass_light_002.ogg",
}
const UI_KEYS: PackedStringArray = [
	"ui_click", "kill", "wave_start", "wave_clear", "cast_fail", "equip", "pickup", "vote_tick"
]
const LAND_MIN := 2.0  ## m/s: Cogito's min landing velocity (quiet)
const LAND_MAX := 8.0  ## m/s: loudest
const STEP_DIST := 2.2  ## m of grounded travel per footstep
const POOL := 12

var player: Player
var played := {}
var muted_output := false  ## tests: count without playing
var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _last := {}
var _step_acc := 0.0
var _last_pos := Vector3.INF
var _charge_full := false
var _spin_full := false


static func load_stream(key: String) -> AudioStream:
	return load(SOUNDS[key]) as AudioStream if SOUNDS.has(key) else null


## Volumes (0..1 linear) on Master / SFX(+UI) / Music.
static func apply_volumes(master: float, sfx: float, music: float) -> void:
	_set_bus("Master", master)
	_set_bus("SFX", sfx)
	_set_bus("UI", sfx)
	_set_bus("Music", music)


static func _set_bus(n: String, v: float) -> void:
	var i := AudioServer.get_bus_index(n)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		muted_output = true  # headless runs: no audio device, and a sound alive at quit leaks (0.3.1: tests too)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	var bus := GameEvents.bus()
	bus.enemy_spawned.connect(_on_enemy_spawned)
	bus.enemy_killed.connect(func(_e, _el): play("kill"))
	bus.wave_started.connect(func(_i, _id): play("wave_start"))
	bus.wave_cleared.connect(func(_i, _id): play("wave_clear"))


func _exit_tree() -> void:
	for c in get_children():  # a sound still playing at quit would leak its playback
		if c is AudioStreamPlayer or c is AudioStreamPlayer3D:
			c.stop()
			c.stream = null
	var bus := GameEvents.bus()
	if bus.enemy_spawned.is_connected(_on_enemy_spawned):
		bus.enemy_spawned.disconnect(_on_enemy_spawned)
	for s in ["enemy_killed", "wave_started", "wave_cleared"]:
		for c in bus.get_signal_connection_list(s):
			if c["callable"].get_object() == self:
				bus.disconnect(s, c["callable"])


func bind(p: Player) -> void:
	player = p
	p.hurt.connect(_on_hurt)
	p.died.connect(func(_p): play("player_death"))
	p.respawned.connect(func(_p): play("respawn"))
	p.loadout.swap_started.connect(func(_s): play("equip"))
	for c in p.loadout.casters:
		c.out_of_mana.connect(func(_c): play("cast_fail"))
		c.brand_event.connect(_on_brand_event)
	p.pickups.collected.connect(func(lp, what): play(pickup_key(lp, what)))
	p.progression.leveled_up.connect(func(_lv): play("level_up"))
	_last = _snapshot()


## 0.3.1 P5 (M5): the cast sound key for an element ("cast" when it has none).
static func cast_key_for(element: int) -> String:
	if element < 0 or element >= ElementTable.IDS.size():
		return "cast"
	var k := "cast_" + ElementTable.IDS[element]
	return k if SOUNDS.has(k) else "cast"


func _snapshot() -> Dictionary:
	var casts := 0
	var cast_key := "cast"
	for c in player.loadout.casters:
		casts += c.casts
		if c.casts > int(_last.get("casts_by", {}).get(c.get_instance_id(), c.casts)):
			cast_key = cast_key_for(c.wieldable.element() if c.wieldable else -1)
	var by := {}
	for c in player.loadout.casters:
		by[c.get_instance_id()] = c.casts
	return {
		"cast_key": cast_key,
		"casts_by": by,
		"landings": player.landings,
		"dashes": player.dash.dashes if player.dash else 0,
		"casts": casts,
		"focus": player.focus.amount() > 0.5 if player.focus else false,
		"blasts": MagicEffects.blasts,
		"crits": MagicEffects.crits,
	}


func _physics_process(_dt: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var now := _snapshot()
	if now["landings"] > _last["landings"]:
		var t := clampf(inverse_lerp(LAND_MIN, LAND_MAX, player.last_landing_speed), 0.0, 1.0)
		play("land", lerpf(-12.0, 0.0, t), lerpf(1.1, 0.85, t))
	if now["dashes"] > _last["dashes"]:
		play("dash")
	if now["casts"] > _last["casts"]:
		play_at(now["cast_key"], player.viewmodel.cast_point_position() if player.viewmodel else player.global_position)
	if now["focus"] and not _last["focus"]:
		play("focus", -6.0)
	if now["blasts"] > _last.get("blasts", now["blasts"]):
		play("brand_blast", -4.0)
	if now["crits"] > _last.get("crits", now["crits"]):
		play("brand_crit", -2.0)
	_last = now
	var pos := player.global_position
	if player.is_on_floor() and _last_pos != Vector3.INF:
		_step_acc += Vector2(pos.x - _last_pos.x, pos.z - _last_pos.z).length()
		if _step_acc >= STEP_DIST:
			_step_acc = 0.0
			play("footstep", -8.0, randf_range(0.9, 1.1))
	_last_pos = pos


## Step 141: brand fire-mode events (FireMode.emit -> Caster.brand_event).
func _on_brand_event(kind: StringName, value: float) -> void:
	match kind:
		&"overheated":
			play("brand_overheat")
		&"vent":
			play("brand_vent", -2.0)
		&"crystal_reload":  # t69u: the core pops out; the click when it re-forms is "vented"
			play("brand_crystal_eject", -4.0, 1.3)
		&"vented":
			play("brand_crystal_set", -6.0, 1.6)
		&"charge":
			if value >= 0.95 and not _charge_full:
				play("brand_charge_full", -6.0)
			_charge_full = value >= 0.95
		&"charge_released":
			_charge_full = false
			play("brand_charge_release", 0.0, lerpf(1.2, 0.8, clampf(value, 0.0, 1.0)))
		&"spin":
			if value >= 0.99 and not _spin_full:
				play("brand_spin_full", -8.0, 1.5)
			_spin_full = value >= 0.99
		&"burst":
			play("brand_burst", -6.0)
		&"mode_toggled":
			play("brand_toggle")
		&"orb_thrown":
			play("brand_orb")


func _on_hurt(p: Player, _r: Damage.Result) -> void:
	play(
		"shield_break" if p.health.shield <= 0.0 and p.health.value > 0.0 and p.health.shield_absorbed > 0.0 else "hurt"
	)


func _on_enemy_spawned(e: Enemy) -> void:
	if e == null:
		return
	e.damaged.connect(func(en: Enemy, _h): play_at("hit", en.global_position, 0.0, 1.4 if en.last_weak_point else 1.0))
	e.died.connect(func(en: Enemy, _el): play_at("enemy_death", en.global_position))
	if e is Gnawer:
		e.attacked.connect(_on_gnawer_attacked)
		e.state_changed.connect(_on_gnawer_state)


func _stream(key: String) -> AudioStream:
	if not _streams.has(key):
		_streams[key] = load_stream(key)
	return _streams[key]


func _count(key: String) -> bool:
	played[key] = int(played.get(key, 0)) + 1
	return not muted_output and _stream(key) != null


## A 2D (non-positional) sound.
func play(key: String, db := 0.0, pitch := 1.0) -> void:
	if not _count(key):
		return
	var p: AudioStreamPlayer = null
	for q in _pool:
		if not q.playing:
			p = q
			break
	if p == null:
		p = _pool[0]
	p.stream = _stream(key)
	p.bus = &"UI" if UI_KEYS.has(key) else &"SFX"
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


## A 3D sound at `at` (freed when done).
func play_at(key: String, at: Vector3, db := 0.0, pitch := 1.0) -> void:
	if not _count(key) or not is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _stream(key)
	p.bus = &"SFX"
	p.volume_db = db
	p.pitch_scale = pitch
	p.unit_size = 6.0
	add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()


func _on_gnawer_attacked(g: Gnawer, _b) -> void:
	if g is Heap:
		play_at("slam", g.global_position)


func _on_gnawer_state(g: Gnawer, _from, to) -> void:
	if g is Heap and to == Gnawer.State.ATTACK:
		play_at("slam_windup", g.global_position, -4.0)


## 0.3.1 P4 (M2): items play their rarity's pickup sound (each tier longer, more notes);
## walk-over gold, dust, mana and potions keep the light Kenney blip.
static func pickup_key(lp: LootPickup, what: String) -> String:
	if what == "item" and lp != null and lp.drop != null and Rarity.parse(lp.drop.rarity_id) >= 0:
		return "pickup_" + lp.drop.rarity_id
	return "pickup"
