class_name FakeLobbyBackend
extends LobbyBackend
## In-memory lobby backend for tests (BUILD_PLAN step 89). Every FakeLobbyBackend made
## with the same `hub` sees the same lobbies and friends, like one Steam network.


class Hub:
	extends RefCounted
	var next_id := 109775240000000001
	var lobbies := {}  ## id -> PackedStringArray of member names
	var users := {}  ## name -> FakeLobbyBackend
	var port := 0  ## tests: lobbies ride a local ENet session on this port

	## Breaks the hub <-> backend reference cycle (tests call it when done).
	func close() -> void:
		for u in users.values():
			u.hub = null
		users.clear()
		lobbies.clear()


var hub: Hub
var user := ""


func _init(h: Hub, user_name: String) -> void:
	hub = h
	user = user_name
	hub.users[user] = self


func available() -> bool:
	return true


func create_lobby() -> bool:
	lobby_id = hub.next_id
	hub.next_id += 1
	hub.lobbies[lobby_id] = PackedStringArray([user])
	lobby_created.emit(lobby_id)
	return true


func join_lobby(id: int) -> bool:
	if not hub.lobbies.has(id):
		return _fail("that lobby no longer exists")
	var m: PackedStringArray = hub.lobbies[id]
	if m.size() >= MAX_MEMBERS:
		return _fail("the lobby is full")
	if not m.has(user):
		m.append(user)
	hub.lobbies[id] = m
	lobby_id = id
	lobby_joined.emit(id)
	return true


func invite(friend: String) -> bool:
	if lobby_id == 0:
		return _fail("no lobby to invite to")
	# Typed as the base class on purpose: naming its own class_name here made a script self-reference that,
	# once the game scene had loaded, kept ~190 scripts alive at exit (the rt34 exit leak).
	var f: LobbyBackend = hub.users.get(friend)
	if f == null:
		return _fail("%s is not online" % friend)
	f.join_requested.emit(lobby_id, user)
	return true


func leave_lobby() -> void:
	if hub.lobbies.has(lobby_id):
		var m: PackedStringArray = hub.lobbies[lobby_id]
		m.remove_at(m.find(user))
		if m.is_empty():
			hub.lobbies.erase(lobby_id)
		else:
			hub.lobbies[lobby_id] = m
	lobby_id = 0


func members() -> PackedStringArray:
	return hub.lobbies.get(lobby_id, PackedStringArray())


func host_target(_id: int) -> Variant:
	return hub.port


func join_target(_id: int) -> Variant:
	return "127.0.0.1:%d" % hub.port


func make_transport() -> NetTransport:
	return NetTransport.make("enet")
