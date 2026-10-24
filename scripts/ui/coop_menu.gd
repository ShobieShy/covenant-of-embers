class_name CoopMenu
extends PanelContainer
## Co-op from the main menu (BUILD_PLAN step 88): host or join by direct IP (ENet, LAN /
## dev fallback, optional UPnP port opening) or through Steam (step 89), then a lobby
## with the roster, Ready and (host) Start. Every failure lands in `status` in words the
## player can act on (bad address, no answer, version mismatch, full, host left).
## Scripted: auto(opts) with Coop.parse_args (--host / --join / --name / --coop-players).

signal closed

var name_edit: LineEdit
var port_edit: LineEdit
var address_edit: LineEdit
var upnp_check: CheckBox
var status: Label
var roster_label: Label
var ready_button: Button
var start_button: Button
var buttons := {}
var session: NetSession
var mapper: PortMapper
var auto_opts := {}
var _upnp_thread: Thread


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(460, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var title := Label.new()
	title.text = "Co-op"
	title.add_theme_font_size_override("font_size", 28)
	v.add_child(title)
	name_edit = _field(v, "Name", Coop.default_name())
	port_edit = _field(v, "Host port", str(NetTransport.DEFAULT_PORT))
	upnp_check = CheckBox.new()
	upnp_check.text = "Open the port on my router (UPnP)"
	v.add_child(upnp_check)
	address_edit = _field(v, "Join address", "127.0.0.1:%d" % NetTransport.DEFAULT_PORT)
	var row := HBoxContainer.new()
	v.add_child(row)
	for id in ["host_ip", "join_ip", "host_steam", "invite_steam", "leave", "back"]:
		var b := Button.new()
		b.text = {
			"host_ip": "Host (IP)",
			"join_ip": "Join (IP)",
			"host_steam": "Host (Steam)",
			"invite_steam": "Invite",
			"leave": "Leave",
			"back": "Back"
		}[id]
		b.pressed.connect(press.bind(id))
		row.add_child(b)
		buttons[id] = b
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(status)
	roster_label = Label.new()
	v.add_child(roster_label)
	var lobby := HBoxContainer.new()
	v.add_child(lobby)
	ready_button = Button.new()
	ready_button.text = "Ready"
	ready_button.toggle_mode = true
	ready_button.toggled.connect(_on_ready_toggled)
	lobby.add_child(ready_button)
	start_button = Button.new()
	start_button.text = "Start"
	start_button.pressed.connect(press.bind("start"))
	lobby.add_child(start_button)
	_refresh()


func _on_ready_toggled(on: bool) -> void:
	if session:
		session.set_ready(on)


func _field(parent: Control, label: String, value: String) -> LineEdit:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(110, 0)
	h.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(e)
	return e


func _session() -> NetSession:
	if session == null or not is_instance_valid(session):
		session = Coop.ensure_session(get_tree())
		session.roster_changed.connect(_on_roster)
		session.failed.connect(_on_failed)
		session.ended.connect(_on_ended)
		session.started.connect(_on_started)
	return session


func info() -> Dictionary:
	var n := name_edit.text.strip_edges()
	return {"name": n if not n.is_empty() else Coop.default_name(), "level": Coop.host_level()}


func press(id: String) -> void:
	match id:
		"host_ip":
			if not port_edit.text.strip_edges().is_valid_int():
				return set_status("The port must be a number (1024-65535).")
			var port := int(port_edit.text)
			if port < 1024 or port > 65535:
				return set_status("The port must be between 1024 and 65535.")
			if _session().host(NetTransport.make("enet"), port, info()):
				set_status("Hosting on UDP port %d. Friends join with your IP:%d." % [port, port])
				if upnp_check.button_pressed:
					_map_port(port)
		"join_ip":
			var a := NetAddress.parse(address_edit.text)
			if a.has("error"):
				return set_status(String(a["error"]))
			if _session().join(NetTransport.make("enet"), address_edit.text, info()):
				set_status("Connecting to %s:%d ..." % [a["host"], a["port"]])
		"host_steam":
			var t := NetTransport.make("steam") as SteamTransport
			if not t.init():
				return set_status(t.last_error + ". Direct IP still works.")
			if _session().host(t, null, info()):
				set_status("Steam lobby open. Use Invite or the Steam overlay to bring friends.")
		"invite_steam":
			if session and session.transport is SteamTransport:
				(session.transport as SteamTransport).invite_dialog()
			else:
				set_status("Invites need a Steam lobby: press Host (Steam) first.")
		"start":
			if session == null or not session.start_game():
				set_status("Everyone must be ready before the host starts.")
		"leave":
			Coop.end("left")
			session = null
			set_status("Left the session.")
		"back":
			if session and session.state != NetSession.State.IN_GAME:
				Coop.end("left")
				session = null
			hide()
			closed.emit()
	_refresh()


func set_status(text: String) -> void:
	status.text = text
	print("[coop] " + text)


func _map_port(port: int) -> void:
	mapper = PortMapper.new()
	set_status(status.text + " Asking the router to open it ...")
	_upnp_thread = mapper.map_async(port, _on_mapped)


func _on_mapped(r: Dictionary) -> void:
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if bool(r.get("ok", false)):
		set_status("Port open. Your address: %s:%d" % [r["ip"], int(port_edit.text)])
	else:
		set_status(String(r.get("error", "UPnP failed")))


func _on_roster() -> void:
	_refresh()
	if auto_opts.get("mode", "") == "join" and session.state == NetSession.State.LOBBY:
		if not bool(session.roster.get(session.my_id(), {}).get("ready", false)):
			session.set_ready(true)
	if auto_opts.get("mode", "") == "host" and session.is_host():
		if session.roster.size() >= int(auto_opts.get("players", 2)) and session.all_ready():
			session.start_game()


func _on_failed(reason: String) -> void:
	set_status("Could not connect: " + reason)
	_refresh()


func _on_ended(reason: String) -> void:
	set_status("Session ended: " + reason)
	_refresh()


func _on_started() -> void:
	set_status("Starting ...")
	Coop.begin(get_tree())


## Scripted host/join (Coop.parse_args); the host readies itself at once.
func auto(opts: Dictionary) -> void:
	auto_opts = opts
	show()
	name_edit.text = String(opts.get("name", name_edit.text))
	if opts["mode"] == "host":
		port_edit.text = str(opts["port"])
		press("host_ip")
		if session and session.is_host():
			session.set_ready(true)
	elif opts["mode"] == "join":
		address_edit.text = String(opts["address"])
		press("join_ip")


func _refresh() -> void:
	var s := session if session and is_instance_valid(session) else null
	var in_lobby := s != null and s.state == NetSession.State.LOBBY
	var busy := s != null and (s.state == NetSession.State.CONNECTING or in_lobby)
	for id in ["host_ip", "join_ip", "host_steam"]:
		(buttons[id] as Button).disabled = busy
	(buttons["leave"] as Button).disabled = not busy
	(buttons["invite_steam"] as Button).disabled = not (in_lobby and s.transport is SteamTransport)
	ready_button.disabled = not in_lobby
	start_button.visible = in_lobby and s.is_host()
	start_button.disabled = not (in_lobby and s.all_ready())
	var lines: Array[String] = []
	if s:
		var ids := s.roster.keys()
		ids.sort()
		for id in ids:
			var r: Dictionary = s.roster[id]
			lines.append(
				(
					"%s %s%s"
					% ["[x]" if r.get("ready", false) else "[ ]", r.get("name", "?"), " (host)" if id == 1 else ""]
				)
			)
	roster_label.text = "\n".join(lines)


func _exit_tree() -> void:
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
