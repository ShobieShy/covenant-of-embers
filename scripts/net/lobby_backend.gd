class_name LobbyBackend
extends RefCounted
## Lobbies + invites behind one interface (BUILD_PLAN step 89), so the menu and tests do
## not care whether Steam is there:
##  - SteamLobbyBackend: GodotSteam matchmaking (createLobby, overlay invites,
##    join-on-launch "+connect_lobby <id>", Steam's relay does NAT traversal);
##  - FakeLobbyBackend: in-memory lobbies for headless tests.
## Flow: host create_lobby() -> lobby_created(id) -> SteamTransport.host(id);
## friend gets join_requested(id) (overlay / invite / launch arg) -> join_lobby(id) ->
## lobby_joined(id) -> SteamTransport.join(id).

signal lobby_created(lobby_id: int)
signal lobby_joined(lobby_id: int)
signal join_requested(lobby_id: int, from_friend: String)
signal failed(reason: String)

const MAX_MEMBERS := NetTransport.MAX_CLIENTS + 1

var lobby_id := 0
var last_error := ""


func available() -> bool:
	return false


func create_lobby() -> bool:
	return _fail("lobbies are not available")


func join_lobby(_id: int) -> bool:
	return _fail("lobbies are not available")


func invite(_friend: String) -> bool:
	return _fail("invites are not available")


func leave_lobby() -> void:
	lobby_id = 0


func members() -> PackedStringArray:
	return PackedStringArray()


func poll() -> void:
	pass


## What the transport hosts / joins for a lobby (Steam: the lobby id itself).
func host_target(id: int) -> Variant:
	return id


func join_target(id: int) -> Variant:
	return id


## The transport that carries this backend's sessions.
func make_transport() -> NetTransport:
	return NetTransport.make("steam")


func _fail(reason: String) -> bool:
	last_error = reason
	failed.emit(reason)
	return false


## "+connect_lobby <id>" (Steam's join-on-launch) from the command line; 0 when absent.
static func launch_lobby(args: PackedStringArray) -> int:
	var i := args.find("+connect_lobby")
	if i >= 0 and i + 1 < args.size() and args[i + 1].is_valid_int():
		return int(args[i + 1])
	return 0
