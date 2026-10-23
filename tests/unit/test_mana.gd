extends TestCase
## Step 8 done check (port of the archived test_mana.cpp, old step 18): the Mana pool and
## the Caster hook. Magewar ManaAttribute numbers (PLAN §30.1): 100 max, regen 3/s once
## 1.5 s have passed since the last successful cast, refusals don't restart the delay.
##  - the Apprentice Fire Staff (5 mana, 0.4 s) pressed every tick casts 20 times to 0
##    (ticks 0..456), the 21st press is refused (no bolt, no cooldown) and it casts again
##    on tick 646 +-1 (456 + 90 delay + 100 for 5 mana); also at 144 Hz and through Player;
##  - spend refuses when short (exactly enough is fine), counts/emits refusals; Magewar's
##    other bases empty the pool after 40 / 16 / 33 casts;
##  - regen starts exactly 1.5 s after the last cast at 30/60/144 Hz, +3/s; a cast in the
##    delay restarts it, a refusal doesn't; empty -> full in 1.5 + 100/3 = 34.83 s;
##  - regen bonus (Novice Grimoire +0.5 -> 3.5/s, negative total never drains), max bonus
##    (Magewar equip: raises max and value, removal clamps), refill, restore (potion 25),
##    auto_regenerate off;
##  - Player: caster.mana_spender = mana.spend, mana ticks before the cast, a refused
##    press emits hint("Not enough mana!") once per press.

const DT := 1.0 / 60.0
const PLAYER_SCENE := "res://scenes/player/player.tscn"

func _ticks(m: Mana, n: int, dt: float = DT) -> void:
	for i in n:
		m.tick(dt)

func test_defaults_spend_and_refuse() -> void:
	var m := Mana.new()
	check(m.value == 100.0 and m.max_value() == 100.0 and m.fraction() == 1.0, "starts full at 100")
	check(m.regen_per_sec == 3.0 and m.regen_delay == 1.5 and m.regen_rate() == 3.0, "3/s after 1.5 s")
	check(not m.regenerating(), "full: not regenerating")
	var got := []
	m.refused.connect(func(cost: float) -> void: got.append(cost))
	for i in 20:
		check(m.spend(5.0), "cast %d" % (i + 1))
	check(m.value == 0.0 and m.spends == 20, "20 x 5 = empty (%f)" % m.value)
	check(not m.spend(5.0) and m.value == 0.0 and m.refusals == 1, "21st refused")
	check(got == [5.0], "refused signal with the cost")
	# Exactly enough is fine (Magewar: value_current < amount refuses).
	var s := Mana.new()
	check(s.spend(96.0) and s.value == 4.0, "96")
	check(not s.spend(5.0) and s.value == 4.0 and s.has(4.0) and not s.has(4.5), "short by 1")
	check(s.spend(4.0) and s.value == 0.0, "exactly enough")
	# Magewar's other bases (mana from the .tres): casts until empty, mana left.
	for row in [["apprentice_fire_staff", 20, 0.0], ["swift_wind_wand", 40, 0.0],
			["earthward_battlestaff", 16, 4.0], ["novice_arcane_wand", 33, 1.0]]:
		var w := WieldableInstance.load_base(row[0])
		var pool := Mana.new()
		var n := 0
		while pool.spend(w.mana_cost()) and n < 1000:
			n += 1
		print("    mana: %s (%.1f/cast) -> %d casts, %.2f left" % [row[0], w.mana_cost(), n, pool.value])
		check(n == row[1] and absf(pool.value - row[2]) < 1e-6, "%s: %d casts, %f left" % [row[0], n, pool.value])

## Fire staff through the real Caster, Fire pressed every tick (mana ticks first, like
## Player.tick). Returns [last of the 20 casts, first refused tick, next cast tick, caster, mana].
func _twenty_casts(hz: int) -> Array:
	var dt := 1.0 / hz
	var m := Mana.new()
	var c := Caster.new(WieldableInstance.load_base("apprentice_fire_staff"))
	c.mana_spender = m.spend
	var last := -1
	var refused := -1
	var next := -1
	var tick := 0
	while tick < 100 * hz and next < 0:
		m.tick(dt)
		var cast := c.tick(true, true, dt, null, null)
		if cast and c.casts <= 20:
			last = tick
		elif cast:
			next = tick
		elif refused < 0 and c.mana_refused > 0:
			refused = tick
			check(c.cooldown_left <= 1e-9, "@%d Hz: refusal leaves no cooldown (%s)" % [hz, str(c.cooldown_left)])
		tick += 1
	return [last, refused, next, c, m]

func test_fire_staff_20_casts_21st_refused_casts_again_at_646() -> void:
	var r := _twenty_casts(60)
	var c: Caster = r[3]
	var m: Mana = r[4]
	print("    mana: 20 fire-staff casts by tick %d, 21st refused at tick %d, casts again at tick %d (646 +-1), %d refusals" % [r[0], r[1], r[2], c.mana_refused])
	check(r[0] == 19 * 24, "20th cast at tick 456 (got %d)" % r[0])
	check(r[1] == 480, "21st press (tick 480, cooldown over) refused for mana (got %d)" % r[1])
	check(absi(r[2] - 646) <= 1, "casts again at tick 646 +-1 (got %d)" % r[2])
	check(c.casts == 21 and c.mana_refused == r[2] - 480, "every press 480..%d refused (%d)" % [r[2] - 1, c.mana_refused])
	check(m.spends == 21 and absf(m.value) < 0.06, "spent the 5 it regained (%f)" % m.value)
	# 144 Hz: a cast every 58 ticks (0.4028 s), regen from 1.5 s, 5 mana after 5/3 s.
	var h := _twenty_casts(144)
	var expect_next := 19 * 58 + 216 + 240
	print("    mana @144 Hz: 20th cast tick %d, next cast tick %d (expect %d +-1)" % [h[0], h[2], expect_next])
	check(h[0] == 19 * 58 and absi(h[2] - expect_next) <= 1, "144 Hz timing (%d, %d)" % [h[0], h[2]])

func _regen_timing(hz: int) -> void:
	var dt := 1.0 / hz
	var delay_ticks := hz * 3 / 2
	var m := Mana.new()
	check(m.spend(50.0), "spend 50")
	_ticks(m, delay_ticks - 1, dt)
	check(m.value == 50.0 and not m.regenerating(), "@%d Hz: still in the delay one tick before 1.5 s" % hz)
	_ticks(m, 1, dt)
	check_near(m.value, 50.0, 1e-4, "@%d Hz: exactly 1.5 s (a rounding sliver at most)" % hz)
	check(m.regenerating(), "@%d Hz: regenerating at 1.5 s" % hz)
	_ticks(m, 1, dt)
	check_near(m.value, 50.0 + 3.0 * dt, 1e-6, "@%d Hz: first regen tick" % hz)
	_ticks(m, hz - 1, dt)
	print("    mana @%d Hz: %.5f after 1.5 s delay + 1 s regen (53)" % [hz, m.value])
	check_near(m.value, 53.0, 1e-6, "@%d Hz: +3 after 1 s of regen" % hz)
	_ticks(m, 10 * hz, dt)
	check_near(m.value, 83.0, 1e-6, "@%d Hz: +30 after 10 s more" % hz)
	# A cast inside the delay restarts it: casts at 0 and 1.4 s, regen only from 2.9 s.
	var r := Mana.new()
	check(r.spend(10.0), "spend 10")
	_ticks(r, int(1.4 * hz + 0.5), dt)
	check(r.value == 90.0 and r.spend(10.0) and r.value == 80.0, "@%d Hz: no regen within 1.4 s" % hz)
	_ticks(r, delay_ticks, dt)
	check_near(r.value, 80.0, 1e-4, "@%d Hz: delay restarted by the second cast" % hz)
	_ticks(r, hz, dt)
	check_near(r.value, 83.0, 1e-4, "@%d Hz: then +3/s" % hz)

func test_regen_delay_and_rate_30_60_144_hz() -> void:
	for hz: int in [30, 60, 144]:
		_regen_timing(hz)

func test_refusal_does_not_reset_delay() -> void:
	for hz: int in [60, 144]:
		var dt := 1.0 / hz
		var q := Mana.new()
		check(q.spend(99.0), "spend 99")
		_ticks(q, hz, dt)   # 1 s after the cast
		check(not q.spend(5.0) and q.value == 1.0 and q.refusals == 1, "@%d Hz: refused at 1 s" % hz)
		check_near(q.seconds_since_spend, 1.0, 1e-9, "@%d Hz: refusal kept the timer" % hz)
		_ticks(q, hz * 3 / 2, dt)   # 2.5 s after the cast: 1 s of regen
		check_near(q.value, 4.0, 1e-6, "@%d Hz: regen 1.5 s after the *successful* cast" % hz)
		# Refusing every tick (Fire held with hold_to_repeat) doesn't hold regen back either.
		var h := Mana.new()
		check(h.spend(100.0), "empty")
		var n := 0
		while not h.spend(5.0) and n < 100 * hz:
			h.tick(dt)
			n += 1
		var expect := int(ceil((1.5 + 5.0 / 3.0) * hz - 1e-6))
		check(absi(n - expect) <= 1, "@%d Hz: refused every tick, still affords 5 after %d ticks (got %d)" % [hz, expect, n])

func test_empty_to_full_in_34_83_s() -> void:
	for hz: int in [30, 60, 144]:
		var dt := 1.0 / hz
		var e := Mana.new()
		check(e.spend(100.0) and e.value == 0.0, "empty")
		var n := 0
		while e.value < e.max_value() and n < 100 * hz:
			e.tick(dt)
			n += 1
		var expect := int(ceil((1.5 + 100.0 / 3.0) * hz - 1e-6))
		print("    mana @%d Hz: empty -> full in %d ticks = %.4f s (expect %d = 34.833 s)" % [hz, n, float(n) / hz, expect])
		check(absi(n - expect) <= 1 and e.value == 100.0, "@%d Hz: full after %d ticks (got %d)" % [hz, expect, n])
		check_near(float(n) / hz, 34.8333, 1.0 / hz + 1e-4, "@%d Hz: 34.83 s" % hz)
		_ticks(e, hz, dt)
		check(e.value == 100.0 and not e.regenerating(), "@%d Hz: never above the max" % hz)

func test_regen_and_max_bonus_hooks() -> void:
	# Equipment regen (step 19): Novice Grimoire mana_regen_bonus 0.5 -> 3.5/s.
	var m := Mana.new()
	m.set_regen_bonus(0.5)
	check(m.regen_rate() == 3.5 and m.regen_bonus == 0.5, "3.5/s")
	check(m.spend(50.0), "spend 50")
	_ticks(m, 90 + 60)
	print("    mana: regen bonus +0.5 -> %.4f after 1.5 s + 1 s (53.5)" % m.value)
	check_near(m.value, 53.5, 1e-6, "+3.5 in 1 s")
	m.set_regen_bonus(2.0)
	_ticks(m, 60)
	check_near(m.value, 58.5, 1e-6, "+5 at 5/s")
	m.set_regen_bonus(-10.0)
	check(m.regen_rate() == 0.0, "never negative")
	_ticks(m, 60)
	check_near(m.value, 58.5, 1e-6, "never drains")
	# Max bonus = Magewar equip: max and current both +bonus (clamped); removal clamps.
	var x := Mana.new()
	check(x.spend(20.0), "spend 20")
	x.set_max_bonus(5.0)   # Novice Grimoire mana_bonus 5
	check(x.max_value() == 105.0 and x.value == 85.0, "equip +5: 105 max, 85 now (%f)" % x.value)
	x.set_max_bonus(0.0)
	check(x.max_value() == 100.0 and x.value == 85.0, "unequip: 100 max, 85 kept")
	var f := Mana.new()
	f.set_max_bonus(25.0)
	check(f.max_value() == 125.0 and f.value == 125.0 and f.fraction() == 1.0, "full + 25 = 125/125")
	f.set_max_bonus(10.0)
	check(f.max_value() == 110.0 and f.value == 110.0, "lowered: clamped to 110")
	# Level-up (step 27): +5 max and a full refill (Magewar _level_up).
	check(f.spend(60.0), "spend 60")
	f.set_max_bonus(15.0)
	check(f.value == 55.0, "raising adds the difference only")
	f.refill()
	check(f.max_value() == 115.0 and f.value == 115.0, "refill")
	# Mana Potion (Magewar +25, step 19/23): capped, doesn't touch the delay.
	var p := Mana.new()
	check(p.spend(90.0), "spend 90")
	_ticks(p, 30)
	p.restore(25.0)
	check(p.value == 35.0 and is_equal_approx(p.seconds_since_spend, 0.5), "potion +25, delay kept")
	p.restore(500.0)
	check(p.value == 100.0, "potion capped at max")
	p.restore(-5.0)
	check(p.value == 100.0, "negative restore ignored")
	# auto_regenerate off: never regenerates.
	var o := Mana.new()
	o.auto_regenerate = false
	check(o.spend(10.0), "spend 10")
	_ticks(o, 600)
	check(o.value == 90.0 and not o.regenerating(), "auto_regenerate off")

func test_from_tuning() -> void:
	var t := PlayerTuning.new()
	check(t.mana_max == 100.0 and t.mana_regen_per_sec == 3.0 and t.mana_regen_delay == 1.5 and t.mana_auto_regenerate,
		"PlayerTuning mana = PLAN §30.1")
	var tres := load("res://resources/player/player_tuning.tres") as PlayerTuning
	check(tres != null and tres.mana_max == 100.0 and tres.mana_regen_per_sec == 3.0 and tres.mana_regen_delay == 1.5,
		"player_tuning.tres mana")
	t.mana_max = 80.0
	t.mana_regen_per_sec = 4.0
	t.mana_regen_delay = 2.0
	var m := Mana.from_tuning(t)
	check(m.value == 80.0 and m.max_value() == 80.0 and m.regen_rate() == 4.0 and m.regen_delay == 2.0, "from_tuning")
	check(m.seconds_since_spend == 2.0, "a fresh pool is past its delay")

func test_caster_cue_once_per_press() -> void:
	var c := Caster.new(WieldableInstance.load_base("swift_wind_wand"))
	var m := Mana.new()
	c.mana_spender = m.spend
	check(m.spend(99.0), "1 left")
	var cues := []
	c.out_of_mana.connect(func(cost: float) -> void: cues.append(cost))
	check(not c.tick(true, true, DT, null, null), "press refused")
	for i in 10:
		c.tick(false, true, DT, null, null)   # held, semi-auto: no re-try, no cue
	check(cues == [2.5] and c.mana_refused == 1 and m.refusals == 1, "one cue per press (%s)" % [cues])
	c.hold_to_repeat = true
	for i in 10:
		c.tick(false, true, DT, null, null)   # held with repeat: tries, but no press cue
	check(cues.size() == 1 and m.refusals == 11, "repeat retries without a cue (%d refusals)" % m.refusals)

func test_player_spends_mana_and_shows_not_enough_mana() -> void:
	var w := Node3D.new()
	runner_tree.root.add_child(w)
	w.global_position = Vector3(-1100, 0, 1100)
	var floor := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	cs.shape = box
	floor.add_child(cs)
	floor.position = Vector3(0, -0.5, 0)
	w.add_child(floor)
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position, 0.0)
	check(p.mana != null and p.mana.value == 100.0 and p.mana.max_value() == 100.0, "player mana 100/100")
	check(p.caster.mana_spender.is_valid() and p.caster.mana_spender.get_object() == p.mana, "caster spends player.mana")
	var hints := []
	p.hint.connect(func(t: String) -> void: hints.append(t))
	p.caster.equip(WieldableInstance.load_base("apprentice_fire_staff"))
	var fire := PlayerInput.hold([], ["action_primary"])
	var next := -1
	for tick in 1200:
		p.tick(fire, DT)
		if tick == 456:
			check(p.caster.casts == 20 and p.mana.value == 0.0, "20 casts by tick 456 (%d, %f)" % [p.caster.casts, p.mana.value])
		if tick == 480:
			check(p.caster.casts == 20 and hints == [Player.HINT_NOT_ENOUGH_MANA], "21st press: one 'Not enough mana!' (%s)" % [hints])
		if p.caster.casts == 21:
			next = tick
			break
	print("    mana: player casts again at tick %d (646 +-1) after %d 'Not enough mana!' cue(s)" % [next, p.not_enough_mana_cues])
	check(absi(next - 646) <= 1, "player casts again at tick 646 +-1 (got %d)" % next)
	check(p.not_enough_mana_cues == next - 480 and p.not_enough_mana_cues == p.caster.mana_refused and p.last_hint == "Not enough mana!",
		"a cue per refused press")
	# Idle regen through Player.tick: spend 10, 1.5 s + 1 s later 93.
	p.mana.refill()
	check(p.mana.spend(10.0), "spend 10")
	var idle := PlayerInput.hold()
	for i in 150:
		p.tick(idle, DT)
	check_near(p.mana.value, 93.0, 1e-6, "player regenerates once per tick")
	# set_mana() rebinds the caster.
	var bigger := Mana.new()
	bigger.base_max = 150.0
	bigger.value = 150.0
	p.set_mana(bigger)
	check(p.caster.mana_spender.get_object() == bigger, "set_mana rebinds the caster")
	w.free()
