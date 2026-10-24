class_name DialogueDB
extends RefCounted
## Data-driven dialogue (BUILD_PLAN step 62), read from data/story/dialogue.toml:
##   [[dialogue]] id, speaker, lines = [...], repeats = [...] (optional), requires = [flags],
##   forbids = [flags], sets = [flags set when the lines finish];
##   [[choice]] dialogue = id, text, reply = [...], sets = [...], requires = [...].
## For a speaker the first entry (file order) whose requires/forbids pass is used. Its first
## run plays `lines` (then its choices) and sets "dlg_seen:<id>"; later runs play one
## `repeats` line each, cycling (Magewar npc_dialogue repeat_dialogue_lines), or `lines`
## again when it has no repeats.

const DEFAULT_PATH := "res://data/story/dialogue.toml"
const SEEN := "dlg_seen:"

var entries: Array[Dictionary] = []
var choices := {}  ## dialogue id -> Array[Dictionary]

static var _default: DialogueDB


static func load_default() -> DialogueDB:
	if _default == null:
		var r := from_file(DEFAULT_PATH)
		assert(not r.has("error"), str(r.get("error", "")))
		_default = r.get("db")
	return _default


static func from_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"error": "can't open " + path}
	return from_text(f.get_as_text(), path)


static func from_text(text: String, source := "dialogue") -> Dictionary:
	var t := LevelToml.parse(text, source)
	if t.has("error"):
		return t
	var db := DialogueDB.new()
	var ids := {}
	for d in t.get("dialogue", []):
		var e := {
			"id": String(d.get("id", "")),
			"speaker": String(d.get("speaker", "")),
			"lines": Array(d.get("lines", [])),
			"repeats": Array(d.get("repeats", [])),
			"requires": Array(d.get("requires", [])),
			"forbids": Array(d.get("forbids", [])),
			"sets": Array(d.get("sets", [])),
		}
		if e["id"] == "" or e["speaker"] == "" or (e["lines"] as Array).is_empty():
			return {"error": "%s: dialogue needs id, speaker and lines (%s)" % [source, e["id"]]}
		if ids.has(e["id"]):
			return {"error": "%s: duplicate dialogue id '%s'" % [source, e["id"]]}
		ids[e["id"]] = true
		db.entries.append(e)
	for c in t.get("choice", []):
		var did := String(c.get("dialogue", ""))
		if not ids.has(did) or String(c.get("text", "")) == "":
			return {"error": "%s: choice needs a known dialogue and text (%s)" % [source, did]}
		if not db.choices.has(did):
			db.choices[did] = []
		(
			(db.choices[did] as Array)
			. append(
				{
					"text": String(c["text"]),
					"reply": Array(c.get("reply", [])),
					"sets": Array(c.get("sets", [])),
					"requires": Array(c.get("requires", [])),
				}
			)
		)
	return {"db": db}


func speakers() -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries:
		if not out.has(e["speaker"]):
			out.append(e["speaker"])
	return out


## The entry `speaker` would say now, or {}.
func pick(speaker: String, flags: StoryFlags) -> Dictionary:
	for e in entries:
		if e["speaker"] == speaker and flags.all_of(e["requires"]) and flags.none_of(e["forbids"]):
			return e
	return {}


func choices_for(id: String, flags: StoryFlags) -> Array:
	return (choices.get(id, []) as Array).filter(func(c: Dictionary) -> bool: return flags.all_of(c["requires"]))
