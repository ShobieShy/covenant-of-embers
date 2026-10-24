class_name SteamLobbyBackend
extends LobbyBackend
## Steam lobbies through GodotSteam (BUILD_PLAN step 89). Needs SteamTransport.init()
## first (the Steam client running + logged in). Lobbies are friends-only; Steam's relay
## (SteamMultiplayerPeer over Steam Networking Sockets) handles NAT traversal, so no port
## forwarding. Overlay "Join game" and invite accepts arrive as join_requested.

const LOBBY_FRIENDS_ONLY := 1

var transport: SteamTransport


func _init(t: SteamTransport) -> void:
	transport = t


func available() -> bool:
	return transport != null and transport.available()


func _steam() -> Object:
	return transport.api() if available() else null


func _connect(sig: String, f: Callable) -> void:
	var s := _steam()
	if s and s.has_signal(sig) and not s.is_connected(sig, f):
		s.connect(sig, f)


func _wire() -> void:
	_connect("lobby_created", _on_created)
	_connect("lobby_joined", _on_joined)
	_connect("join_requested", _on_join_requested)


func create_lobby() -> bool:
	if not available():
		return _fail("Steam is not running (Direct IP still works)")
	_wire()
	_steam().call("createLobby", LOBBY_FRIENDS_ONLY, MAX_MEMBERS)
	return true


func join_lobby(id: int) -> bool:
	if not available():
		return _fail("Steam is not running (Direct IP still works)")
	_wire()
	_steam().call("joinLobby", id)
	return true


func invite(_friend := "") -> bool:
	transport.lobby_id = lobby_id
	if not transport.invite_dialog():
		return _fail(transport.last_error)
	return true


func leave_lobby() -> void:
	if available() and lobby_id != 0:
		_steam().call("leaveLobby", lobby_id)
	lobby_id = 0


func poll() -> void:
	transport.poll()


func _on_created(connect: int, id: int) -> void:
	if connect != 1:
		_fail("Steam could not create a lobby (code %d)" % connect)
		return
	lobby_id = id
	transport.lobby_id = id
	_steam().call("setLobbyJoinable", id, true)
	lobby_created.emit(id)


func _on_joined(id: int, _perms: int, _locked: bool, response: int) -> void:
	if response != 1:
		_fail("could not join the Steam lobby (code %d)" % response)
		return
	lobby_id = id
	transport.lobby_id = id
	lobby_joined.emit(id)


func _on_join_requested(id: int, friend_id: int) -> void:
	join_requested.emit(id, str(friend_id))


func make_transport() -> NetTransport:
	return transport
