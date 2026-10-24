class_name LinkConditioner
extends RefCounted
## Step 92: simulated bad link for NetSession's outgoing game traffic. Every message waits
## delay_ms (+ up to jitter_ms) before it is really sent; unreliable ones are dropped with
## probability `loss`. Seeded, so a test run drops the same packets every time.
## Command line (after --): --net-lag=150 --net-loss=0.02

var delay_ms := 150.0
var jitter_ms := 0.0
var loss := 0.02
var dropped := 0
var delayed := 0
var _rng := RandomNumberGenerator.new()
var _queue: Array = []  ## [due_ms, reliable, to, kind, data], due order kept per send order


func _init(delay := 150.0, drop := 0.02, seed_value := 92) -> void:
	delay_ms = delay
	loss = drop
	_rng.seed = seed_value


static func from_args(args: PackedStringArray) -> LinkConditioner:
	var lag := -1.0
	var drop := 0.0
	for a in args:
		if a.begins_with("--net-lag="):
			lag = a.get_slice("=", 1).to_float()
		elif a.begins_with("--net-loss="):
			drop = a.get_slice("=", 1).to_float()
	if lag < 0.0 and drop <= 0.0:
		return null
	return LinkConditioner.new(maxf(lag, 0.0), drop)


## False when the packet is lost.
func push(reliable: bool, to: int, kind: String, data: Dictionary, now_ms: float) -> bool:
	if not reliable and _rng.randf() < loss:
		dropped += 1
		return false
	var due := now_ms + delay_ms + (_rng.randf() * jitter_ms if jitter_ms > 0.0 else 0.0)
	if not _queue.is_empty():
		due = maxf(due, float(_queue[-1][0]))  # never reorder
	_queue.append([due, reliable, to, kind, data.duplicate(true)])
	delayed += 1
	return true


## Messages whose time has come, oldest first.
func pop_due(now_ms: float) -> Array:
	var out: Array = []
	while not _queue.is_empty() and float(_queue[0][0]) <= now_ms:
		out.append(_queue.pop_front())
	return out


func pending() -> int:
	return _queue.size()


func clear() -> void:
	_queue.clear()
