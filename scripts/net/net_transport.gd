class_name NetTransport
extends RefCounted
## How co-op peers reach each other (BUILD_PLAN step 78). The session (NetSession) only
## sees a MultiplayerPeer; a transport makes one:
##  - EnetTransport: direct IP:port (LAN / dev / headless tests).
##  - SteamTransport: Steam P2P through GodotSteam (lobbies, invites: step 89).
## host()/join() return null and set last_error instead of throwing.

const DEFAULT_PORT := 24680
const MAX_CLIENTS := 3  ## 4-player co-op

var kind := "none"
var last_error := ""


static func make(which: String) -> NetTransport:
	match which:
		"enet":
			return EnetTransport.new()
		"steam":
			return SteamTransport.new()
	return null


func available() -> bool:
	return false


## `where`: a port (ENet) or a lobby id (Steam).
func host(_where: Variant = null) -> MultiplayerPeer:
	last_error = "transport %s cannot host" % kind
	return null


## `address`: "ip:port" (ENet) or a lobby id (Steam).
func join(_address: Variant) -> MultiplayerPeer:
	last_error = "transport %s cannot join" % kind
	return null


## Called each frame by the session (Steam needs run_callbacks()).
func poll() -> void:
	pass


func describe() -> String:
	return kind
