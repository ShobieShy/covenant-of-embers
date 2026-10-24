class_name EnetTransport
extends NetTransport
## Direct IP co-op over ENet (BUILD_PLAN steps 78/88). Works without Steam.

var bind_ip := "*"


func _init() -> void:
	kind = "enet"


func available() -> bool:
	return true


func host(where: Variant = null) -> MultiplayerPeer:
	var port := int(where) if where != null else DEFAULT_PORT
	var p := ENetMultiplayerPeer.new()
	p.set_bind_ip(bind_ip)
	var err := p.create_server(port, MAX_CLIENTS)
	if err != OK:
		last_error = "could not open port %d (%s): is another game already hosting?" % [port, error_string(err)]
		return null
	last_error = ""
	return p


func join(address: Variant) -> MultiplayerPeer:
	var a := NetAddress.parse(String(address))
	if a.has("error"):
		last_error = a["error"]
		return null
	var p := ENetMultiplayerPeer.new()
	var err := p.create_client(a["host"], a["port"])
	if err != OK:
		last_error = "could not reach %s:%d (%s)" % [a["host"], a["port"], error_string(err)]
		return null
	last_error = ""
	return p
