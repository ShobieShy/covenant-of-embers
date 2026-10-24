class_name NetSession
extends Node
## A co-op session (BUILD_PLAN step 78): the host is authoritative (it owns the world and
## its save, step 91); clients join with their own character. This node owns its own
## SceneMultiplayer rooted at itself, so two sessions can live in one process (tests,
## the 2-instance smoke run uses two processes). Flow:
##   host()/join() -> client sends _hello(info) -> host checks the version gate and room,
##   answers _welcome(roster) or _reject(reason) -> lobby: players toggle ready ->
##   host start_game() when everyone is ready -> _start() on every peer -> IN_GAME.
## The host leaving ends the session for everyone (no migration, Q16): clients get
## `ended("host left")` and save their character locally.

signal roster_changed
signal started
signal failed(reason: String)
signal ended(reason: String)
signal message(from: int, kind: String, data: Dictionary)  ## step 79+: game traffic

enum State { IDLE, CONNECTING, LOBBY, IN_GAME, ENDED }

const PROTOCOL := 1
const CONNECT_TIMEOUT := 8.0

var state := State.IDLE
var transport: NetTransport
var api: SceneMultiplayer
var roster := {}  ## peer id -> {name, ready, version}
var local_info := {}
var last_reason := ""
var _connect_left := 0.0


static func version() -> String:
	return "%s/p%d" % [String(ProjectSettings.get_setting("application/config/version", "0")), PROTOCOL]


func _ready() -> void:
	_ensure_api()


func _ensure_api() -> void:
	if api != null:
		return
	api = SceneMultiplayer.new()
	api.server_relay = true
	get_tree().set_multiplayer(api, get_path())
	api.peer_connected.connect(_on_peer_connected)
	api.peer_disconnected.connect(_on_peer_disconnected)
	api.connected_to_server.connect(_on_connected)
	api.connection_failed.connect(func(): _fail("could not connect to the host"))
	api.server_disconnected.connect(func(): _end("host left"))


func is_host() -> bool:
	return api != null and api.has_multiplayer_peer() and api.is_server() and state != State.IDLE


func my_id() -> int:
	return api.get_unique_id() if api and api.has_multiplayer_peer() else 0


func host(t: NetTransport, where: Variant, info: Dictionary) -> bool:
	_ensure_api()
	transport = t
	var p := t.host(where)
	if p == null:
		return _fail(t.last_error)
	api.multiplayer_peer = p
	local_info = _info(info)
	roster = {1: local_info.duplicate()}
	state = State.LOBBY
	roster_changed.emit()
	return true


func join(t: NetTransport, address: Variant, info: Dictionary) -> bool:
	_ensure_api()
	transport = t
	var p := t.join(address)
	if p == null:
		return _fail(t.last_error)
	api.multiplayer_peer = p
	local_info = _info(info)
	state = State.CONNECTING
	_connect_left = CONNECT_TIMEOUT
	return true


func _info(info: Dictionary) -> Dictionary:
	var d := info.duplicate()
	d["name"] = String(d.get("name", "Player"))
	d["ready"] = false
	d["version"] = version()
	d["data"] = Compat.fingerprint()  # step 90
	return d


func set_ready(flag: bool) -> void:
	if state != State.LOBBY:
		return
	if is_host():
		_apply_ready(1, flag)
	else:
		_ready_rpc.rpc_id(1, flag)


func all_ready() -> bool:
	if roster.is_empty():
		return false
	for id in roster:
		if not bool(roster[id].get("ready", false)):
			return false
	return true


func start_game() -> bool:
	if not is_host() or state != State.LOBBY or not all_ready():
		return false
	_start.rpc()
	return true


## Game traffic (steps 79+): reliable dictionary messages; to = 0 sends to everyone else.
func send(kind: String, data: Dictionary, to := 0, reliable := true) -> void:
	if state == State.IDLE or state == State.ENDED or not api.has_multiplayer_peer():
		return
	var f: Callable = _msg if reliable else _msg_fast
	if to != 0:
		f.rpc_id(to, kind, data)
	else:
		f.rpc(kind, data)


func leave(reason := "left") -> void:
	_close_peer()
	_end(reason)


func _close_peer() -> void:
	if api and api.has_multiplayer_peer():
		api.multiplayer_peer.close()
		api.multiplayer_peer = null


func _process(delta: float) -> void:
	if transport:
		transport.poll()
	if state == State.CONNECTING:
		_connect_left -= delta
		if _connect_left <= 0.0:
			_close_peer()
			_fail("the host did not answer (check the address, port and firewall)")


func _fail(reason: String) -> bool:
	last_reason = reason
	state = State.IDLE
	failed.emit(reason)
	return false


func _end(reason: String) -> void:
	if state == State.ENDED or state == State.IDLE:
		return
	last_reason = reason
	state = State.ENDED
	roster.clear()
	ended.emit(reason)


func _on_peer_connected(_id: int) -> void:
	pass  # the client introduces itself with _hello


func _on_peer_disconnected(id: int) -> void:
	if roster.erase(id):
		if is_host():
			_roster.rpc(roster)
		roster_changed.emit()


func _on_connected() -> void:
	_hello.rpc_id(1, local_info)


func _apply_ready(id: int, flag: bool) -> void:
	if roster.has(id):
		roster[id]["ready"] = flag
		_roster.rpc(roster)
		roster_changed.emit()


@rpc("any_peer", "reliable")
func _hello(info: Dictionary) -> void:
	if not is_host():
		return
	var id := api.get_remote_sender_id()
	var why := ""
	if String(info.get("version", "")) != version():
		why = "version mismatch: host %s, you %s" % [version(), info.get("version", "?")]
	elif String(info.get("data", "")) != Compat.fingerprint():
		why = (
			"game data mismatch (host %s, you %s): both players need the same build"
			% [Compat.fingerprint(), info.get("data", "?")]
		)
	elif state != State.LOBBY:
		why = "the game has already started"
	elif roster.size() > NetTransport.MAX_CLIENTS:
		why = "the session is full"
	if not why.is_empty():
		_reject.rpc_id(id, why)
		return
	var d := info.duplicate()
	d["ready"] = false
	roster[id] = d
	_roster.rpc(roster)
	roster_changed.emit()


@rpc("authority", "reliable")
func _reject(reason: String) -> void:
	_close_peer()
	_fail(reason)


@rpc("authority", "reliable")
func _roster(r: Dictionary) -> void:
	roster = r
	if state == State.CONNECTING:
		state = State.LOBBY
	roster_changed.emit()


@rpc("any_peer", "reliable")
func _ready_rpc(flag: bool) -> void:
	if is_host():
		_apply_ready(api.get_remote_sender_id(), flag)


@rpc("authority", "call_local", "reliable")
func _start() -> void:
	state = State.IN_GAME
	started.emit()


@rpc("any_peer", "reliable")
func _msg(kind: String, data: Dictionary) -> void:
	message.emit(api.get_remote_sender_id(), kind, data)


@rpc("any_peer", "unreliable_ordered")
func _msg_fast(kind: String, data: Dictionary) -> void:
	message.emit(api.get_remote_sender_id(), kind, data)
