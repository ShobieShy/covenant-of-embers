extends TestCase
## 0.3.2 C3: jitter in, a smooth sample out; snap only past the threshold.


func test_buffer_interpolates_and_snaps() -> void:
	var b := NetInterp.new()
	b.push(0.0, Vector3.ZERO, 0.0)
	b.push(100.0, Vector3(1, 0, 0), 0.2)
	b.push(200.0, Vector3(2, 0, 0), 0.4)
	var mid := b.sample(200.0, Vector3(1, 0, 0))
	check_near((mid["pos"] as Vector3).x, 1.0, 0.05, "100 ms behind lands on the middle sample")
	check(not bool(mid["snap"]), "a metre of error does not snap")
	var late := b.sample(300.0 + NetInterp.EXTRAP_MS, Vector3(2, 0, 0))
	check((late["pos"] as Vector3).x >= 2.0, "short extrapolation moves forward")
	var far := b.sample(200.0, Vector3(20, 0, 0))
	check(bool(far["snap"]), "past %s m snaps" % NetInterp.SNAP_M)


## 0.3.4: the live conditioner hook (150 ms, 5% loss) driven into the buffer.
## A 6 m/s walk at 20 Hz should not snap and should not jump more than a metre
## between 60 Hz samples. Headless stand-in for the co-op playtest pass.
func test_walk_stays_smooth_at_150ms_5pct() -> void:
	var lc := LinkConditioner.new(150.0, 0.05, 11)
	var buf := NetInterp.new()
	var speed := 6.0
	var send_t := 0.0
	var now := 0.0
	var drawn := Vector3.ZERO
	var stats := {}
	var guard := 0
	while now < 8000.0 and guard < 2000:
		guard += 1
		while send_t <= now:
			var pos := Vector3(speed * send_t / 1000.0, 0.0, 0.0)
			lc.push(false, 1, "pose", {"t": send_t, "p": pos, "y": 0.0}, send_t)
			send_t += 50.0
		for row in lc.pop_due(now):
			var data: Dictionary = row[4]
			buf.push_remote(float(data["t"]), now, data["p"], float(data["y"]))
		if buf.samples.size() >= 2:
			var before := drawn
			var sm := buf.sample_sender(now, drawn)
			drawn = sm["pos"]
			NetInterp.watch(stats, before, drawn, bool(sm["snap"]))
		now += 1000.0 / 60.0
	var steps := int(stats.get("steps", 0))
	var snaps := int(stats.get("snaps", 0))
	var big := int(stats.get("big", 0))
	print("[s8] interp 150ms 5%% loss steps %d snaps %d big %d dropped %d" % [steps, snaps, big, lc.dropped])
	check(steps > 200, "sampled the walk (%d)" % steps)
	check(lc.dropped > 0, "loss actually dropped poses")
	check(snaps == 0, "a walk does not snap")
	check(big == 0, "no unsmoothed jump over 1 m")


func test_out_of_order_sample_resets() -> void:
	var b := NetInterp.new()
	b.push(500.0, Vector3(3, 0, 0), 0.0)
	b.push(100.0, Vector3(0, 0, 0), 0.0)
	check(b.samples.size() == 1, "older timestamp drops the buffer")
