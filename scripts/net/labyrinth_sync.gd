class_name LabyrinthSync
extends Node
## Labyrinth L4: co-op floor sync (LABYRINTH_PLAN section 8). Host authority:
##  - the host sends "lab" {n, st} (its floor and its LabyrinthState) on every floor it
##    enters and whenever the roster changes; a joiner plays on a copy of that state (its
##    own save's block is left alone and restored at the end), and if it is on another
##    floor it moves to the host's;
##  - a joiner's stairs do nothing (Interiors.follow_only): the host's decide;
##  - the host's stairs down need the whole party within STAIR_RANGE, else a VOTE_S
##    countdown starts ("lab_vote") and the party descends when it ends (vote default
##    yes) or as soon as everyone has gathered.

const STAIR_RANGE := 10.0
const VOTE_S := 10.0

var session: Object  ## NetSession (or a test double: is_host(), send(), signal message)
var interiors: Interiors
var host := false
var own: LabyrinthState  ## the joiner's own block, back in place when the sync ends
var host_state: LabyrinthState
var vote_left := -1.0  ## s; < 0 = no countdown
var follows := 0  ## joiner: floor moves made for the host
var pushes := 0


func setup(s: Object, ints: Interiors, is_host: bool) -> void:
	session = s
	interiors = ints
	host = is_host
	s.connect(&"message", _on_message)
	if host:
		ints.floor_entered.connect(func(_n: int) -> void: push())
		ints.stair_gate = gate
		if s.has_signal(&"roster_changed"):
			s.connect(&"roster_changed", push)
	else:
		own = ints.labyrinth
		ints.follow_only = true


func _exit_tree() -> void:
	if interiors and is_instance_valid(interiors) and not host:
		interiors.follow_only = false
		if own:
			interiors.labyrinth = own


## Host: the floor being played and the state that built it.
func push() -> void:
	if not host or interiors.current != "labyrinth" or interiors.labyrinth == null:
		return
	pushes += 1
	session.call(&"send", "lab", {"n": interiors.floor_no, "st": interiors.labyrinth.to_dict()})


## Host: may the party take the stairs down now? Else the vote countdown runs.
func gate() -> bool:
	if all_near():
		vote_left = -1.0
		return true
	if vote_left < 0.0:
		vote_left = VOTE_S
		session.call(&"send", "lab_vote", {"t": VOTE_S})
		print("[labyrinth] waiting for the party at the stairs (%.0f s)" % VOTE_S)
	return false


func all_near() -> bool:
	var sd := stairs_pos()
	if sd == Vector3.INF:
		return true
	var who: Array = interiors.party()
	# L5b: the joiners are RemotePlayer proxies on the host (not in the local party), so
	# before this the vote never ran and the host went down without them
	who.append_array(interiors.get_tree().get_nodes_in_group(RemotePlayer.GROUP))
	for p: Node3D in who:
		var d := Vector2(p.global_position.x - sd.x, p.global_position.z - sd.z)
		if d.length() > STAIR_RANGE:
			return false
	return true


func stairs_pos() -> Vector3:
	var f := interiors.lab_floor
	var sd := f.get_node_or_null("StairsDown") as Node3D if f and is_instance_valid(f) else null
	return sd.global_position if sd else Vector3.INF


func _process(dt: float) -> void:
	tick(dt)


func tick(dt: float) -> void:
	if not host or vote_left < 0.0:
		return
	if interiors.current != "labyrinth":
		vote_left = -1.0
		return
	vote_left -= dt
	if vote_left <= 0.0 or all_near():
		vote_left = -1.0
		interiors.descend()


func _on_message(from: int, kind: String, data: Dictionary) -> void:
	if host or from != 1:
		return
	match kind:
		"lab":
			follow(int(data.get("n", 1)), data.get("st", {}))
		"lab_vote":
			print("[labyrinth] the host is at the stairs: %.0f s" % float(data.get("t", VOTE_S)))


## Joiner: play the host's floor `n` from its state `st`.
func follow(n: int, st: Variant) -> void:
	if not (st is Dictionary) or n < 1:
		return
	host_state = LabyrinthState.from_dict(st)
	host_state.current = n
	interiors.labyrinth = host_state
	if interiors.current == "labyrinth" and interiors.floor_no != n and not interiors.busy:
		follows += 1
		print("[coop] following the host to floor %d" % n)
		await interiors.enter_floor(n)
	elif interiors.current != "labyrinth":
		interiors.floor_no = n
