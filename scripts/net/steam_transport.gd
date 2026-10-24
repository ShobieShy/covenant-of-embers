class_name SteamTransport
extends NetTransport
## Steam P2P co-op through the GodotSteam GDExtension (BUILD_PLAN steps 78/89).
## Steam is optional: the game runs without the extension, without the Steam client, and
## headless tests never start it. The API is reached through Engine.get_singleton() so the
## scripts parse even when the extension is missing. init() is only called when the
## player picks Steam co-op (it shows "playing" to friends). App id: steam_appid.txt
## (480, Valve's public test app, until we have our own).

const APP_ID := 480

static var initialised := false
static var init_error := ""

var singleton_name := "Steam"  ## tests point this at a missing name


func _init() -> void:
	kind = "steam"


func has_extension() -> bool:
	return Engine.has_singleton(singleton_name) and ClassDB.class_exists("SteamMultiplayerPeer")


func api() -> Object:
	return Engine.get_singleton(singleton_name) if Engine.has_singleton(singleton_name) else null


## Starts Steam once; false (with last_error) when the extension or the client is missing.
func init() -> bool:
	if not has_extension():
		last_error = "Steam support is not installed in this build"
		return false
	if initialised and singleton_name == "Steam":
		return true
	if DisplayServer.get_name() == "headless" and not OS.has_environment("COE_STEAM_HEADLESS"):
		last_error = "Steam is not started in headless runs"
		return false
	var r: Variant = api().call("steamInitEx", APP_ID, false)
	var status := int((r as Dictionary).get("status", -1)) if r is Dictionary else -1
	if status != 0:
		init_error = String((r as Dictionary).get("verbal", "unknown")) if r is Dictionary else "no reply"
		last_error = "Steam is not running or not logged in (%s)" % init_error
		return false
	initialised = true
	return true


func available() -> bool:
	return has_extension() and initialised and singleton_name == "Steam"


func poll() -> void:
	if available():
		api().call("run_callbacks")


func _peer() -> MultiplayerPeer:
	if not available():
		if last_error.is_empty():
			last_error = "Steam is not available (start Steam, or use Direct IP)"
		return null
	return ClassDB.instantiate("SteamMultiplayerPeer") as MultiplayerPeer


## where: the lobby id (step 89 creates it).
func host(where: Variant = null) -> MultiplayerPeer:
	var p := _peer()
	if p == null:
		return null
	var err: int = p.call("host_with_lobby", int(where)) if where != null else p.call("create_host", 0)
	if err != OK:
		last_error = "Steam host failed (%s)" % error_string(err)
		return null
	last_error = ""
	return p


## address: the lobby id to join.
func join(address: Variant) -> MultiplayerPeer:
	var p := _peer()
	if p == null:
		return null
	var err: int = p.call("connect_to_lobby", int(address))
	if err != OK:
		last_error = "Steam join failed (%s)" % error_string(err)
		return null
	last_error = ""
	return p


func describe() -> String:
	if not has_extension():
		return "steam (not installed)"
	return "steam (ready)" if available() else "steam (not started)"
