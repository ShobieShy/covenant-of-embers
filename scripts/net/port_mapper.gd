class_name PortMapper
extends RefCounted
## UPnP fallback for direct-IP hosting (BUILD_PLAN step 88): asks the router to forward the
## host's UDP port so friends outside the LAN can join by IP. Optional and best effort: a
## router without UPnP just means "forward the port by hand" (the message says so). Steam
## co-op (step 89) needs none of this. map() blocks for up to ~2 s: run it in a Thread
## (map_async). `upnp` is injectable for tests (anything with UPNP's methods).

const DESCRIPTION := "Covenant of Embers co-op"

var upnp: Object
var mapped_port := 0
var external_ip := ""
var last_error := ""


func _init(u: Object = null) -> void:
	upnp = u


## {ok: true, ip} or {ok: false, error}.
func map(port: int) -> Dictionary:
	if upnp == null:
		upnp = UPNP.new()
	var err: int = upnp.call("discover", 2000, 2, "InternetGatewayDevice")
	if err != OK:
		return _fail("no UPnP router found (%d): forward UDP port %d by hand" % [err, port])
	var gw: Variant = upnp.call("get_gateway")
	if gw == null or not bool((gw as Object).call("is_valid_gateway")):
		return _fail("the router does not allow UPnP: forward UDP port %d by hand" % port)
	err = upnp.call("add_port_mapping", port, port, DESCRIPTION, "UDP", 0)
	if err != OK:
		return _fail("the router refused port %d (%d): forward it by hand" % [port, err])
	mapped_port = port
	external_ip = String(upnp.call("query_external_address"))
	last_error = ""
	return {"ok": true, "ip": external_ip}


func unmap() -> void:
	if upnp != null and mapped_port > 0:
		upnp.call("delete_port_mapping", mapped_port, "UDP")
		mapped_port = 0


## Runs map() on a thread and calls done(result) on the main thread.
func map_async(port: int, done: Callable) -> Thread:
	var t := Thread.new()
	t.start(
		func():
			var r := map(port)
			done.call_deferred(r)
	)
	return t


func _fail(msg: String) -> Dictionary:
	last_error = msg
	return {"ok": false, "error": msg}
