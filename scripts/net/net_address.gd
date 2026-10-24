class_name NetAddress
extends RefCounted
## "host[:port]" parsing for direct-IP join (BUILD_PLAN steps 78/88): IPv4, a host name,
## or [IPv6]:port. Returns {host, port} or {error} with a message a player can act on.


static func parse(text: String, default_port := NetTransport.DEFAULT_PORT) -> Dictionary:
	var t := text.strip_edges()
	if t.is_empty():
		return {"error": "Enter the host's address, e.g. 192.168.1.20:%d" % default_port}
	var host := t
	var port := default_port
	if t.begins_with("["):
		var close := t.find("]")
		if close < 0:
			return {"error": "Missing ] in IPv6 address"}
		host = t.substr(1, close - 1)
		var rest := t.substr(close + 1)
		if rest.begins_with(":"):
			if not rest.substr(1).is_valid_int():
				return {"error": "Port must be a number"}
			port = int(rest.substr(1))
		elif not rest.is_empty():
			return {"error": "Unexpected text after ]"}
	elif t.count(":") == 1:
		host = t.get_slice(":", 0)
		var ps := t.get_slice(":", 1)
		if not ps.is_valid_int():
			return {"error": "Port must be a number"}
		port = int(ps)
	if host.is_empty() or host.contains(" "):
		return {"error": "Bad host name '%s'" % host}
	if port < 1 or port > 65535:
		return {"error": "Port must be 1-65535"}
	return {"host": host, "port": port}
