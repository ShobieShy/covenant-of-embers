class_name MainMenu
extends Control
## Main menu (step 39): New Run (the Midden), Continue (the saved level + state; greyed
## without a save), Settings, Quit. User args (after `--`):
##  --start      begin a new run at once (scripted launches, CI smoke);
##  --continue   continue the save at once (falls back to a new run without one);
##  --seconds N  quit after N s if still on the menu (never hangs a headless run).

var buttons := {}
var version_label: Label
var slot_buttons: Array[Button] = []
## Step 49: New Run over an existing save asks first.
var confirm: ConfirmationDialog
## Step 118: an old save that may predate the intro asks once; New Game can skip the prologue.
var intro_ask: ConfirmationDialog
var _new_mode := ""
var settings_ui: SettingsUi
var coop_menu: CoopMenu  ## step 88
var menu_column: Control  ## QA r14: hidden while the co-op panel is up (no overlap)
var _seconds := -1.0
var _elapsed := 0.0
var creator: CharacterCreator  ## step 73 / 111
var credits_ui: CreditsUi  ## batch_01/02 art credits
## 0.3.1 P6 (L1): title fade-in, a hover tick and nudge on buttons, save-slot cards.
const LOCATION_NAMES := {
	"midden": "The Midden",
	"breach": "The Breach",
	"town_square": "Town Square",
	"mage_association": "Mage Association",
	"old_oak": "The Old Oak",
}
var title_label: Label
var hover_player: AudioStreamPlayer
var hovers := 0


## "v0.1.0" from application/config/version (step 84; also stamped into the Windows exe).
static func version_string() -> String:
	return "v" + String(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## "Pre-Alpha 0.1.1" for 0.1.1-prealpha (the menu's release name; VersionInfo parses the suffix).
static func release_name() -> String:
	return VersionInfo.release_name(VersionInfo.current())


func _ready() -> void:
	UiTheme.apply(get_tree().root)  # step 126: pixel fantasy UI
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.05, 0.04)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	menu_column = c
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(320, 0)
	v.add_theme_constant_override("separation", 10)
	c.add_child(v)
	var title := Label.new()
	title_label = title
	title.text = "Covenant of Embers"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1.0, 0.55, 0.2))
	v.add_child(title)
	UiAnim.fade_in(title, 0.8)
	hover_player = AudioStreamPlayer.new()
	hover_player.stream = GameAudio.load_stream("ui_hover")  # 0.3.1 P7
	hover_player.volume_db = -10.0
	hover_player.bus = &"UI" if AudioServer.get_bus_index(&"UI") >= 0 else &"Master"
	add_child(hover_player)
	version_label = Label.new()  # step 84
	version_label.text = "%s  (%s)" % [release_name(), version_string()]
	version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version_label.modulate = Color(1, 1, 1, 0.6)
	v.add_child(version_label)
	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(slots)
	for n in range(1, SaveGame.SLOTS + 1):
		var sb := Button.new()
		sb.toggle_mode = true
		sb.custom_minimum_size = Vector2(150, 114)
		sb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sb.pressed.connect(select_slot.bind(n))
		_hoverable(sb)
		slots.add_child(sb)
		slot_buttons.append(sb)
	_build_identity(v)  # step 73
	for id in ["new_run", "skip_prologue", "continue", "coop", "settings", "credits", "quit"]:
		var b := Button.new()
		b.text = "Co-op" if id == "coop" else id.capitalize()
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(press.bind(id))
		_hoverable(b)
		v.add_child(b)
		buttons[id] = b
	for f in UserDir.migrate_legacy():  # step 83
		print("[menu] migrated %s from the old user dir" % f)
	UiDriver.attach(get_tree())  # step 41: --ui-test <dir>
	confirm = ConfirmationDialog.new()
	confirm.dialog_text = "This slot already has a save. Start a new run and overwrite it?"
	confirm.ok_button_text = "Overwrite"
	confirm.confirmed.connect(_start_new)
	add_child(confirm)
	intro_ask = ConfirmationDialog.new()
	intro_ask.title = "New intro"
	intro_ask.dialog_text = "This save is from before the prologue was added.\nPlay the new intro?"
	intro_ask.ok_button_text = "Play intro"
	intro_ask.cancel_button_text = "Keep playing"
	intro_ask.confirmed.connect(_answer_intro.bind(true))
	intro_ask.canceled.connect(_answer_intro.bind(false))
	add_child(intro_ask)
	select_slot(GameFlow.slot)
	settings_ui = SettingsUi.new()
	add_child(settings_ui)
	settings_ui.setup(Settings.load_from())
	credits_ui = CreditsUi.new()
	add_child(credits_ui)
	coop_menu = CoopMenu.new()
	coop_menu.visible = false
	add_child(coop_menu)
	coop_menu.visibility_changed.connect(
		func() -> void: menu_column.visible = not coop_menu.visible
	)
	var coop_opts := Coop.parse_args(OS.get_cmdline_user_args())
	if Coop.last_end_reason != "":
		var why := CoopFlow.error_text(Coop.last_end_reason)
		Coop.last_end_reason = ""
		coop_menu.show()
		coop_menu.set_status(why)
	if coop_opts["mode"] != "" and not PlaytestBot.finished:  # step 88: --host / --join
		coop_menu.auto.call_deferred(coop_opts)
	var launch_lobby := LobbyBackend.launch_lobby(OS.get_cmdline_args())  # step 89: Steam join-on-launch
	if launch_lobby != 0:
		coop_menu.join_lobby_id.call_deferred(launch_lobby)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(buttons["new_run"] as Button).grab_focus.call_deferred()
	var args := Array(OS.get_cmdline_user_args())
	var i := args.find("--seconds")
	if i >= 0 and i + 1 < args.size():
		_seconds = float(args[i + 1])
	if args.has("--autoplay"):  # step 40: the bot never touches the real save
		GameFlow.save_path = "user://playtest_save.json"
		PlaytestBot.reset_run()
		if not PlaytestBot.save_cleared:  # QA: each bot run starts without a stale save
			PlaytestBot.save_cleared = true
			for f in [GameFlow.save_path, GameFlow.save_path + ".bak"]:
				if FileAccess.file_exists(f):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		var cargs := Coop.parse_args(OS.get_cmdline_user_args())
		if cargs["mode"] != "" and not PlaytestBot.coop_started:  # step 93: bots start fresh
			PlaytestBot.coop_started = true
			for f in [GameFlow.save_path, CharacterSave.path_for(String(cargs["name"]))]:
				if FileAccess.file_exists(f):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		if not args.has("--start"):
			args.append("--start")
	Screenshots.attach(self, "menu")
	print("[menu] main menu, save %s" % ("found" if GameFlow.has_save() else "none"))
	if Coop.parse_args(OS.get_cmdline_user_args())["mode"] != "":
		pass
	elif args.has("--continue"):
		press.call_deferred("continue")
	elif args.has("--start"):  # scripted: no overwrite prompt
		_start_new.call_deferred()


func press(id: String) -> void:
	match id:
		"new_run", "skip_prologue":
			_new_mode = GameFlow.INTRO_SKIP if id == "skip_prologue" else ""
			if GameFlow.has_save():
				confirm.popup_centered()
			else:
				_start_new()
		"continue":
			if SaveGame.migrate_intro(GameFlow.save_path) == SaveGame.INTRO_ASK:
				intro_ask.popup_centered()
				return
			if not GameFlow.continue_run(get_tree()):
				GameFlow.new_run(get_tree())
		"coop":
			UiAnim.open(coop_menu)  # 0.3.1 P1
		"settings":
			settings_ui.open()
		"credits":
			credits_ui.open()
		"quit":
			get_tree().quit(0)


func _start_new() -> void:
	GameFlow.new_identity = identity()
	var mode := (
		_new_mode if _new_mode != "" else GameFlow.intro_mode_from_args(OS.get_cmdline_user_args())
	)
	GameFlow.new_run(get_tree(), mode)


func _answer_intro(play: bool) -> void:
	SaveGame.answer_intro(GameFlow.save_path, play)
	press("continue")


## Step 73 / 111: the picker lives in CharacterCreator (the intro shows it again in-game).
func _build_identity(v: VBoxContainer) -> void:
	creator = CharacterCreator.new()
	v.add_child(creator)


func identity() -> Dictionary:
	return creator.identity() if creator else {}


func select_slot(n: int) -> void:
	GameFlow.select_slot(n)
	for i in slot_buttons.size():
		var b := slot_buttons[i]
		b.button_pressed = i + 1 == GameFlow.slot
		b.text = slot_card(i + 1)
	(buttons["continue"] as Button).disabled = not GameFlow.has_save()
	(buttons["skip_prologue"] as Button).visible = SaveGame.any_intro_done()


func _process(delta: float) -> void:
	_elapsed += delta
	if _seconds > 0.0 and _elapsed >= _seconds:
		print("[menu] quit after %.2f s on the menu" % _elapsed)
		get_tree().quit(0)


func _hoverable(b: Button) -> void:
	b.mouse_entered.connect(hover.bind(b))
	b.focus_entered.connect(hover.bind(b))


## P6 (L1): a quiet tick and a small pop when a button is hovered or focused.
func hover(b: Button) -> void:
	hovers += 1
	UiAnim.pulse(b, 0.04)
	if (
		hover_player
		and hover_player.stream
		and hover_player.is_inside_tree()
		and not UiAnim.instant()
	):
		hover_player.play()


## "Slot N" plus the character, level, location, playtime and last save time.
## playtime_s is optional (0.3.4, still save version 1). Missing or under a minute stays off
## the card so an old slot looks the same.
static func slot_card(n: int) -> String:
	var r := SaveGame.read(SaveGame.slot_path(n))
	if r.has("error"):
		return "Slot %d\n(empty)" % n
	var d: Dictionary = r["data"]
	var pl: Dictionary = d.get("player", {})
	var pr: Dictionary = d.get("progress", {})
	var who := String(pl.get("name", ""))
	var lines := ["Slot %d" % n]
	lines.append(
		(
			("%s, Lv %d" % [who, int(pl.get("level", 1))])
			if who != ""
			else "Lv %d" % int(pl.get("level", 1))
		)
	)
	var lid := String(pr.get("level_id", ""))
	if lid != "":
		lines.append(String(LOCATION_NAMES.get(lid, lid.capitalize())))
	var played := float(d.get("playtime_s", 0.0))
	if played >= 60.0:
		lines.append(SaveGame.format_playtime(played))
	var at := String(d.get("saved_at", ""))
	if at.length() >= 16:  # saved_at is UTC; show it in local time
		var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		var loc := Time.get_datetime_string_from_unix_time(
			Time.get_unix_time_from_datetime_string(at) + bias, true
		)
		lines.append("Saved " + loc.substr(0, 16))
	return "\n".join(lines)
