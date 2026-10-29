class_name CoopFlow
extends RefCounted
## 0.3.2 join / leave / reconnect / revive helpers. Pure, so the fast tier can
## walk every failure without opening a socket.

const CONNECT_TIMEOUT := 8.0
const HANDSHAKE_TIMEOUT := 8.0
const WORLD_TIMEOUT := 45.0
const RECONNECT_S := 30.0

const PHASE_CONNECTING := "connecting"
const PHASE_HANDSHAKE := "handshake"
const PHASE_HOST_LOADING := "host_loading"
const PHASE_WORLD := "world"
const PHASE_IN_WORLD := "in_world"
const PHASE_FAILED := "failed"
const PHASE_ENDED := "ended"
const PHASE_IDLE := "idle"


static func phase(state: int, started: bool, failed: bool, ended: bool) -> String:
	if failed:
		return PHASE_FAILED
	if ended:
		return PHASE_ENDED
	match state:
		NetSession.State.CONNECTING:
			return PHASE_CONNECTING
		NetSession.State.LOBBY:
			return PHASE_WORLD if started else PHASE_HANDSHAKE
		NetSession.State.IN_GAME:
			return PHASE_IN_WORLD if started else PHASE_HOST_LOADING
		_:
			return PHASE_IDLE


static func phase_timeout(which: String) -> float:
	match which:
		PHASE_CONNECTING:
			return CONNECT_TIMEOUT
		PHASE_HANDSHAKE:
			return HANDSHAKE_TIMEOUT
		PHASE_HOST_LOADING, PHASE_WORLD:
			return WORLD_TIMEOUT
		_:
			return 0.0


## A sentence a player can act on. Unknown reasons pass through.
static func error_text(reason: String) -> String:
	var r := reason.strip_edges()
	if r.is_empty():
		return "Could not join."
	if r.begins_with("version mismatch"):
		return "Version mismatch. You and the host need the same game version."
	if "full" in r:
		return "The host is full."
	if "did not answer" in r or "timed out" in r or "timeout" in r:
		return "Timed out waiting for the host."
	if r == "host left":
		return "The host left the session."
	if "game data mismatch" in r or "map data mismatch" in r:
		return r
	return r


static func reconnect_left(left: float, dt: float) -> float:
	return maxf(0.0, left - dt)


static func reconnect_open(left: float) -> bool:
	return left > 0.0


## Hold Interact to revive. Releasing drains the bar. `done` when the hold completes.
static func revive_step(progress: float, holding: bool, dt: float, need: float) -> Dictionary:
	var p := progress + dt if holding else maxf(0.0, progress - dt)
	return {"p": p, "done": holding and p >= need}


static func party_line(players: int) -> String:
	var n := maxi(1, players)
	if n <= 1:
		return ""
	var bonus := int(round(100.0 * CoopWorld.HP_PER_EXTRA_PLAYER * (n - 1)))
	return "Party x%d: enemies +%d%% health" % [n, bonus]


static func edge_marker(screen: Vector2, viewport: Vector2, margin: float) -> Dictionary:
	var inside := (
		screen.x >= margin
		and screen.y >= margin
		and screen.x <= viewport.x - margin
		and screen.y <= viewport.y - margin
	)
	if inside:
		return {"show": false, "at": screen}
	var c := viewport * 0.5
	var d := screen - c
	if d.length() < 0.001:
		d = Vector2.RIGHT
	var max_x := viewport.x * 0.5 - margin
	var max_y := viewport.y * 0.5 - margin
	var s := minf(max_x / absf(d.x), max_y / absf(d.y))
	return {"show": true, "at": c + d * s}


static func distance_text(metres: float) -> String:
	return "%d m" % int(round(maxf(0.0, metres)))
