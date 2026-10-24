class_name DialogueRunner
extends RefCounted
## One conversation (BUILD_PLAN step 62; Magewar npc_dialogue start/advance/end):
## start(speaker) -> text() / advance() through the lines -> choices() (if any) -> choose(i)
## plays the reply -> ended. Flags are set when the lines finish (entry `sets`, the seen
## flag) and when a choice is taken.

signal line_shown(speaker: String, text: String)
signal choices_shown(texts: PackedStringArray)
signal ended(id: String)

var db: DialogueDB
var flags: StoryFlags
var entry := {}
var lines: Array = []
var index := -1
var active := false
var in_reply := false
var _repeat_at := {}  ## dialogue id -> next repeat line


func _init(d: DialogueDB = null, f: StoryFlags = null) -> void:
	db = d if d else DialogueDB.load_default()
	flags = f if f else StoryFlags.new()


func can_talk(speaker: String) -> bool:
	return not db.pick(speaker, flags).is_empty()


func start(speaker: String) -> bool:
	entry = db.pick(speaker, flags)
	if entry.is_empty():
		return false
	var id: String = entry["id"]
	in_reply = false
	if flags.has(DialogueDB.SEEN + id) and not (entry["repeats"] as Array).is_empty():
		var r: Array = entry["repeats"]
		var k := int(_repeat_at.get(id, 0))
		lines = [r[k % r.size()]]
		_repeat_at[id] = k + 1
	else:
		lines = entry["lines"]
	index = 0
	active = true
	_show()
	return true


func speaker() -> String:
	return String(entry.get("speaker", ""))


func text() -> String:
	return String(lines[index]) if active and index >= 0 and index < lines.size() else ""


func awaiting_choice() -> bool:
	return active and index >= lines.size()


func choices() -> Array:
	return db.choices_for(entry["id"], flags) if awaiting_choice() else []


## Next line; false once the conversation is over (or waiting on a choice).
func advance() -> bool:
	if not active or awaiting_choice():
		return false
	index += 1
	if index < lines.size():
		_show()
		return true
	if not in_reply:
		_finish_lines()
		var cs := db.choices_for(entry["id"], flags)
		if not cs.is_empty() and not _is_repeat():
			choices_shown.emit(PackedStringArray(cs.map(func(c: Dictionary) -> String: return c["text"])))
			return true
	end()
	return false


func choose(i: int) -> bool:
	var cs := choices()
	if i < 0 or i >= cs.size():
		return false
	var c: Dictionary = cs[i]
	for f in c["sets"]:
		flags.set_flag(String(f))
	in_reply = true
	lines = c["reply"]
	index = 0
	if lines.is_empty():
		end()
		return false
	_show()
	return true


func end() -> void:
	if not active:
		return
	active = false
	ended.emit(String(entry.get("id", "")))


func _is_repeat() -> bool:
	return lines != entry["lines"]


func _finish_lines() -> void:
	if _is_repeat():
		return
	flags.set_flag(DialogueDB.SEEN + String(entry["id"]))
	for f in entry["sets"]:
		flags.set_flag(String(f))


func _show() -> void:
	line_shown.emit(speaker(), text())
