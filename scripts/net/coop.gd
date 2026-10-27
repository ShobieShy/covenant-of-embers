class_name Coop
extends RefCounted
## The running co-op session, kept across scene changes (BUILD_PLAN steps 78/88/91).
## The NetSession lives directly under the SceneTree root ("CoopSession") so menu ->
## game -> travel keeps the connection. Command line (after `--`), for scripted runs:
##   --host [port]        host a direct-IP session (ENet) and start when everyone is ready
##   --join host[:port]   join a direct-IP session
##   --name NAME          player name in the lobby (default: the OS user)
##   --coop-players N     host: start once N players are in and ready (default 2)

const NODE_NAME := "CoopSession"

static var session: NetSession = null
static var character := ""  ## step 91: the client's character file name


static func ensure_session(tree: SceneTree) -> NetSession:
	if session != null and is_instance_valid(session) and session.is_inside_tree():
		return session
	session = NetSession.new()
	session.name = NODE_NAME
	tree.root.add_child(session)
	return session


static func active() -> bool:
	return (
		session != null and is_instance_valid(session) and session.state == NetSession.State.IN_GAME
	)


static func is_host() -> bool:
	return active() and session.is_host()


static func is_client() -> bool:
	return active() and not session.is_host()


static func end(reason := "left") -> void:
	var s := session
	session = null  # OW11c-6: leave() emits ended, whose handlers call end() again
	if s != null and is_instance_valid(s):
		s.leave(reason)
		s.queue_free()


static func default_name() -> String:
	var n := OS.get_environment("USER")
	if n.is_empty():
		n = OS.get_environment("USERNAME")
	return n if not n.is_empty() else "Player"


## {mode: "host"|"join"|"", port, address, name, players} from the user args.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var out := {
		"mode": "",
		"port": NetTransport.DEFAULT_PORT,
		"address": "",
		"name": default_name(),
		"players": 2
	}
	var i := 0
	while i < args.size():
		var a := args[i]
		var nxt := args[i + 1] if i + 1 < args.size() else ""
		match a:
			"--host":
				out["mode"] = "host"
				if nxt.is_valid_int():
					out["port"] = int(nxt)
					i += 1
			"--join":
				out["mode"] = "join"
				out["address"] = nxt
				i += 1
			"--name":
				out["name"] = nxt
				i += 1
			"--coop-players":
				out["players"] = maxi(1, int(nxt))
				i += 1
		i += 1
	return out


## The host's level for the lobby info: its save's level, else where a new run starts
## (0.1.4: was the Midden, so a fresh host's clients loaded the wrong map).
static func host_level() -> String:
	var r := SaveGame.read(GameFlow.save_path)
	if r.has("error"):
		return (
			"old_oak"
			if GameFlow.intro_mode_from_args(OS.get_cmdline_user_args()) == GameFlow.INTRO_SKIP
			else "mage_association"
		)
	var id := String((r["data"] as Dictionary).get("progress", {}).get("level_id", "midden"))
	return id if GameFlow.LEVELS.has(id) else "midden"


## Step 155: the anchor/waystone the host's save stands at; joining clients spawn there.
static func host_anchor() -> String:
	var r := SaveGame.read(GameFlow.save_path)
	return (
		""
		if r.has("error")
		else String((r["data"] as Dictionary).get("progress", {}).get("anchor", ""))
	)


## session.started: everyone loads the game scene in the host's level. The host plays
## from its own save (world + quests); clients bring their character (step 91).
static func begin(tree: SceneTree) -> void:
	if session == null:
		return
	if session.is_host():
		if not GameFlow.continue_run(tree):
			GameFlow.new_run(tree, GameFlow.intro_mode_from_args(OS.get_cmdline_user_args()))
		return
	character = CharacterSave.path_for(String(session.local_info.get("name", default_name())))
	var host_info: Dictionary = session.roster.get(1, {})
	var lvl := String(host_info.get("level", "midden"))
	GameFlow.level_id = lvl if GameFlow.LEVELS.has(lvl) else "midden"
	GameFlow.spawn_anchor = String(host_info.get("anchor", ""))
	GameFlow.load_save = false
	GameFlow._change(tree, GameFlow.GAME)
