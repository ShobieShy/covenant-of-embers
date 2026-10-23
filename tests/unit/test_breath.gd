extends TestCase
## Step 4 done check (port of the archived test_breath.cpp, old step 15): the Breath pool.
##  - 100 base; sprinting drains 20/s: 1 s -> 80, empty after exactly 300 ticks (5 s);
##  - regen waits 1 s after the last drain (none on tick 60, +0.5 on tick 61), then +30/s;
##  - an emptied pool is exhausted until 20 is back (100 ticks = 1 + 20/30 s) and full
##    after 260 ticks (1 + 100/30 s); resume_at 0 = Magewar's "sprint whenever > 0";
##  - a drain or spend restarts the delay; spend(25) refuses when short;
##  - set_max_bonus raises/lowers the max without refilling.

const DT := 1.0 / 60.0

func _ticks(b: Breath, draining: bool, n: int, dt: float = DT) -> void:
	for i in n:
		b.tick(draining, dt)

func test_drain_empty_after_300_ticks() -> void:
	var b := Breath.new()
	check(b.value == 100.0 and b.max_value() == 100.0 and b.can_sprint() and not b.exhausted, "starts full")
	_ticks(b, true, 60)
	check_near(b.value, 80.0, 1e-6, "1 s of sprint")
	_ticks(b, true, 239)
	check(b.value > 0.0 and b.can_sprint(), "299 ticks: not yet empty (%f)" % b.value)
	_ticks(b, true, 1)
	print("    breath: after 300 ticks %.6f, exhausted %s" % [b.value, b.exhausted])
	check(b.value == 0.0 and b.empty() and b.exhausted and not b.can_sprint(), "empty + exhausted at tick 300")
	_ticks(b, true, 30)
	check(b.value == 0.0, "floored at 0")

func _regen_timing(hz: int) -> void:
	var dt := 1.0 / hz
	var b := Breath.new()
	_ticks(b, true, 2 * hz, dt)
	var base := b.value
	check_near(base, 60.0, 1e-6, "2 s sprint @%d Hz" % hz)
	_ticks(b, false, hz - 1, dt)
	check(b.value == base and not b.regenerating(), "still waiting 1 tick before 1 s @%d Hz" % hz)
	_ticks(b, false, 1, dt)
	check_near(b.value, base, 1e-3, "exactly 1 s: regen starts @%d Hz" % hz)
	_ticks(b, false, 1, dt)
	check_near(b.value, base + 30.0 * dt, 1e-3, "first regen tick @%d Hz" % hz)
	_ticks(b, false, hz - 1, dt)
	print("    breath @%d Hz: %.4f after 1 s delay + 1 s regen (%.1f)" % [hz, b.value, base + 30.0])
	check_near(b.value, base + 30.0, 1e-3, "+30 after 1 s of regen @%d Hz" % hz)
	_ticks(b, false, 2 * hz, dt)
	check(b.value == b.max_value() and not b.regenerating(), "capped at max @%d Hz" % hz)

func test_regen_delay_and_rate_60_and_144_hz() -> void:
	_regen_timing(60)
	_regen_timing(144)

func test_empty_resume_after_100_full_after_260() -> void:
	var b := Breath.new()
	_ticks(b, true, 300)
	check(b.exhausted, "exhausted")
	var resume_tick := -1
	var full_tick := -1
	for i in range(1, 401):
		b.tick(false, DT)
		if resume_tick < 0 and b.can_sprint():
			resume_tick = i
		if full_tick < 0 and b.value >= b.max_value():
			full_tick = i
	print("    breath: empty -> sprint again after %d ticks (100), full after %d ticks (260)" % [resume_tick, full_tick])
	check(absi(resume_tick - 100) <= 1, "resume after 100 ticks (got %d)" % resume_tick)
	check(absi(full_tick - 260) <= 1, "full after 260 ticks (got %d)" % full_tick)
	var m := Breath.new()
	m.resume_at = 0.0   # Magewar behaviour
	_ticks(m, true, 300)
	check(not m.can_sprint(), "empty: no sprint")
	_ticks(m, false, 61)
	check(m.can_sprint() and m.value < 1.0, "resume_at 0 sprints on a sliver (Magewar)")

func test_interrupt_and_spend() -> void:
	var b := Breath.new()
	_ticks(b, true, 60)
	_ticks(b, false, 90)   # 1 s delay + 0.5 s regen
	check_near(b.value, 95.0, 1e-3, "80 + 0.5 s regen")
	_ticks(b, true, 1)     # one sprint tick restarts the delay
	var v := b.value
	_ticks(b, false, 60)
	check_near(b.value, v, 1e-3, "delay restarted by a 1-tick drain")
	var d := Breath.new()
	check(d.spend(25.0) and d.value == 75.0, "dash cost 25")
	_ticks(d, false, 59)
	check(d.value == 75.0, "spend restarts the delay")
	check(d.spend(25.0) and d.spend(25.0) and absf(d.value - 25.0) < 1e-9, "two more spends")
	_ticks(d, true, 60)
	check(not d.spend(25.0) and absf(d.value - 5.0) < 1e-6, "spend refused when short (5 left)")
	var s := Breath.new()
	_ticks(s, true, 30)   # 90
	_ticks(s, false, 30)
	var since := s.seconds_since_use
	check(not s.spend(95.0) and s.seconds_since_use == since and since > 0.4, "a refused spend doesn't restart the delay")
	var e := Breath.new()
	check(e.spend(100.0) and e.exhausted and not e.can_sprint(), "spending to 0 exhausts")

func test_max_bonus_and_refill() -> void:
	var b := Breath.new()
	b.set_max_bonus(15.0)   # Magewar Leather Belt stamina_bonus 15 (step 19)
	check(b.max_value() == 115.0 and b.value == 100.0, "no free refill")
	_ticks(b, false, 60)
	check_near(b.value, 115.0, 1e-6, "never drained: regens to the new max")
	b.set_max_bonus(0.0)
	check(b.value == 100.0 and b.max_value() == 100.0, "clamped back")
	b.spend(50.0)
	b.refill()
	check(b.value == 100.0 and not b.exhausted, "refill")
	check_near(b.fraction(), 1.0, 1e-9, "fraction")

func test_from_tuning() -> void:
	var t: PlayerTuning = load("res://resources/player/player_tuning.tres")
	var b := Breath.from_tuning(t)
	check(b.base_max == 100.0 and b.drain_per_sec == 20.0 and b.regen_per_sec == 30.0
		and b.regen_delay == 1.0 and b.resume_at == 20.0 and b.value == 100.0, "PLAN §30.8 numbers")
