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


func test_out_of_order_sample_resets() -> void:
	var b := NetInterp.new()
	b.push(500.0, Vector3(3, 0, 0), 0.0)
	b.push(100.0, Vector3(0, 0, 0), 0.0)
	check(b.samples.size() == 1, "older timestamp drops the buffer")
