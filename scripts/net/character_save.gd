class_name CharacterSave
extends RefCounted
## Portable co-op characters (BUILD_PLAN step 91, Borderlands-style ownership):
## the host's save slot holds the world (level, quests, story flags, vault); a client
## brings its own character file user://character_<name>.json (level, XP, gear, skills,
## dust) into any host's game and keeps it. A client never writes the host's slot and
## its quest/story progress is never written into the host's world: the character file
## has an empty `progress`. Same format as SaveGame (version-gated), so a character loads
## into any game with SaveGame.apply().

const PREFIX := "user://character_"


static func slug(player_name: String) -> String:
	var s := ""
	for ch in player_name.to_lower():
		s += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	s = s.strip_edges().trim_prefix("_").trim_suffix("_")
	return s.left(32) if not s.is_empty() else "player"


static func path_for(player_name: String) -> String:
	return PREFIX + slug(player_name) + ".json"


## The character only: SaveGame.capture with no world progress.
static func capture(p: Player) -> Dictionary:
	var d := SaveGame.capture(p, {})
	d["kind"] = "character"
	d["progress"] = {}
	return d


static func write(p: Player, path: String) -> Error:
	if not path.begins_with(PREFIX):
		push_warning("[character] refusing to write %s (not a character file)" % path)
		return ERR_FILE_NO_PERMISSION
	return SaveGame.write(capture(p), path)


## Loads the character into `p` (gear, level, skills; world progress ignored).
## {"warnings": PackedStringArray} or {"error": String} (no file = fresh character).
static func load_into(p: Player, path: String) -> Dictionary:
	var r := SaveGame.read(path)
	if r.has("error"):
		return r
	var d: Dictionary = (r["data"] as Dictionary).duplicate(true)
	d["progress"] = {}
	return {"warnings": SaveGame.apply(p, d)}
