class_name GateVote
extends Node
## 0.4.0: a co-op level change waits for the party (LINEAR_LEVELS_PLAN section 5).
## The host opens the vote; it travels when everyone is at the gate or the 15 s
## timeout ends (the vote defaults to yes). One player travels at once. Walking
## away cancels. Joiners see the same VoteBanner the Labyrinth stairs use.

const VOTE_S := 15.0
const RANGE := 8.0

var session: Object
var host := false
var vote_left := -1.0
var banner_left := -1.0
var target := ""
var anchor := ""
var spot := Vector3.ZERO
var banner: VoteBanner
## Joiner-facing outcome of the last gate_vote: "waiting", "ready", or "cancelled".
var result := ""
signal decided(to: String, anchor: String)


func setup(s: Object, is_host: bool) -> void:
	session = s
	host = is_host
	if s and not s.is_connected(&"message", _on_message):
		s.connect(&"message", _on_message)
	if banner == null and is_inside_tree():
		banner = VoteBanner.new()
		banner.name = "GateVoteBanner"
		banner.sync = self
		add_child(banner)


func _exit_tree() -> void:
	if session and session.is_connected(&"message", _on_message):
		session.disconnect(&"message", _on_message)


func party_size() -> int:
	if session == null:
		return 1
	var roster: Variant = session.get(&"roster")
	if roster is Dictionary:
		return maxi(1, (roster as Dictionary).size())
	return 1


func left() -> float:
	return vote_left if host else banner_left


func missing() -> Array[String]:
	var out: Array[String] = []
	var here := {}
	for n in _voters():
		if n.is_in_group(Player.GROUP):
			continue
		var nm := _name_of(n)
		if (n as Node3D).global_position.distance_to(spot) > RANGE:
			if not out.has(nm):
				out.append(nm)
		else:
			here[nm] = true
	# A reconnecting peer stays missing after their body is freed. Erasing them
	# from the roster (the reconnect window ended) drops them from this list.
	if session != null:
		var roster: Variant = session.get(&"roster")
		if roster is Dictionary:
			for id in roster:
				var row: Variant = (roster as Dictionary)[id]
				if not (row is Dictionary) or not bool((row as Dictionary).get("reconnecting", false)):
					continue
				var nm := String((row as Dictionary).get("name", ""))
				if nm.is_empty():
					nm = "peer%s" % str(id)
				if here.has(nm) or out.has(nm):
					continue
				out.append(nm)
	return out


## True when the party must wait. A solo host (or no session) travels immediately.
func begin(to: String, at_anchor: String, at: Vector3) -> bool:
	if party_size() <= 1:
		return false
	if vote_left >= 0.0:
		return true
	target = to
	anchor = at_anchor
	spot = at
	vote_left = VOTE_S
	if session:
		session.call(&"send", "gate_vote", {"t": VOTE_S, "to": to})
	print("[gate] waiting for the party to enter %s (%.0f s)" % [to, VOTE_S])
	return true


func cancel() -> void:
	if vote_left < 0.0 and banner_left < 0.0:
		return
	vote_left = -1.0
	banner_left = -1.0
	if host and session:
		session.call(&"send", "gate_vote", {"t": -1.0, "to": target, "ready": false})
	print("[gate] vote cancelled")


func tick(dt: float) -> void:
	if not host or vote_left < 0.0:
		return
	if _host_left():
		cancel()
		return
	vote_left -= dt
	if vote_left <= 0.0 or missing().is_empty():
		var to := target
		var at := anchor
		vote_left = -1.0
		if session:
			session.call(&"send", "gate_vote", {"t": -1.0, "to": to, "ready": true})
		print("[gate] party ready for %s" % to)
		decided.emit(to, at)


func _process(dt: float) -> void:
	tick(dt)


func _host_left() -> bool:
	for n in _voters():
		if n.is_in_group(Player.GROUP):
			return (n as Node3D).global_position.distance_to(spot) > RANGE
	return false


func _voters() -> Array:
	var out: Array = []
	if not is_inside_tree():
		return out
	for g in [Player.GROUP, &"coop_avatars"]:
		for n in get_tree().get_nodes_in_group(g):
			if n is Node3D and not out.has(n):
				out.append(n)
	return out


func _name_of(n: Node) -> String:
	var named := String(n.get_meta(&"player_name", ""))
	return named if not named.is_empty() else n.name


func _on_message(_from: int, kind: String, data: Dictionary) -> void:
	if kind != "gate_vote" or host:
		return
	var t := float(data.get("t", -1.0))
	target = String(data.get("to", target))
	if t < 0.0:
		banner_left = -1.0
		if bool(data.get("ready", false)):
			result = "ready"
			print("[gate] party ready for %s" % target)
		else:
			result = "cancelled"
			print("[gate] the level-change vote was cancelled")
	else:
		banner_left = t
		result = "waiting"
		print("[gate] the host is at a gate: %.0f s" % t)
