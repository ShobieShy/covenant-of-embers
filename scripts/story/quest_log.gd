class_name QuestLog
extends RefCounted
## Quests + clue log (BUILD_PLAN step 63; Magewar magewar_quest_tracker): quest data from
## data/story/quests.toml, objectives kill / collect / talk / reach with counts, rewards
## (xp, Arcane Dust, flags, a clue), auto-start on flags, saved via to_dict()/from_dict()
## (SaveGame progress["quests"]). notify(kind, target) advances every active quest's
## *current* objective (objectives are done in order).

signal quest_started(id: String)
signal objective_progressed(id: String, index: int, have: int, need: int)
signal quest_completed(id: String)
signal clue_added(id: String)

const DEFAULT_PATH := "res://data/story/quests.toml"
const KINDS: PackedStringArray = ["kill", "collect", "talk", "reach"]

var quests := {}  ## id -> {id, title, objectives: [{kind, target, count, text}], rewards...}
var order: PackedStringArray = []
var clue_defs := {}  ## id -> {title, text}
var flags: StoryFlags
var player: Player  ## optional: gets xp / dust rewards
var active := {}  ## id -> {step: int, have: int}
var done: PackedStringArray = []
var clues: PackedStringArray = []


static func create(f: StoryFlags = null, path := DEFAULT_PATH) -> QuestLog:
	var q := QuestLog.new()
	q.flags = f if f else StoryFlags.new()
	var r := q.load_file(path)
	assert(r == "", r)
	q.flags.changed.connect(q.check_auto_start.unbind(2))
	return q


## "" or an error.
func load_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "can't open " + path
	return load_text(f.get_as_text(), path)


func load_text(text: String, source := "quests") -> String:
	var t := LevelToml.parse(text, source)
	if t.has("error"):
		return t["error"]
	quests.clear()
	order.clear()
	clue_defs.clear()
	for c in t.get("clue", []):
		clue_defs[String(c.get("id", ""))] = {"title": String(c.get("title", "")), "text": String(c.get("text", ""))}
	for q in t.get("quest", []):
		var id := String(q.get("id", ""))
		if id == "" or quests.has(id):
			return "%s: quest needs a unique id (%s)" % [source, id]
		var clue := String(q.get("reward_clue", ""))
		if clue != "" and not clue_defs.has(clue):
			return "%s: quest %s: unknown clue %s" % [source, id, clue]
		quests[id] = {
			"id": id,
			"title": String(q.get("title", id)),
			"auto": Array(q.get("auto_start_when", [])),
			"xp": int(q.get("reward_xp", 0)),
			"dust": int(q.get("reward_dust", 0)),
			"flags": Array(q.get("reward_flags", [])),
			"clue": clue,
			"objectives": [],
		}
		order.append(id)
	for o in t.get("objective", []):
		var qid := String(o.get("quest", ""))
		var kind := String(o.get("kind", ""))
		if not quests.has(qid) or not KINDS.has(kind) or String(o.get("target", "")) == "":
			return "%s: bad objective (%s, %s)" % [source, qid, kind]
		(
			(quests[qid]["objectives"] as Array)
			. append(
				{
					"kind": kind,
					"target": String(o["target"]),
					"count": maxi(1, int(o.get("count", 1))),
					"text": String(o.get("text", "")),
				}
			)
		)
	for id in order:
		if (quests[id]["objectives"] as Array).is_empty():
			return "%s: quest %s has no objectives" % [source, id]
	return ""


func state(id: String) -> String:
	return "done" if done.has(id) else ("active" if active.has(id) else "available")


func start(id: String) -> bool:
	if not quests.has(id) or active.has(id) or done.has(id):
		return false
	active[id] = {"step": 0, "have": 0}
	quest_started.emit(id)
	return true


func check_auto_start() -> void:
	for id in order:
		var a: Array = quests[id]["auto"]
		if not a.is_empty() and state(id) == "available" and flags.all_of(a):
			start(id)


func current_objective(id: String) -> Dictionary:
	if not active.has(id):
		return {}
	return quests[id]["objectives"][int(active[id]["step"])]


func notify(kind: String, target: String, n := 1) -> void:
	for id in active.keys():
		var o := current_objective(id)
		if o.is_empty() or o["kind"] != kind or o["target"] != target:
			continue
		var s: Dictionary = active[id]
		s["have"] = mini(int(o["count"]), int(s["have"]) + n)
		objective_progressed.emit(id, int(s["step"]), int(s["have"]), int(o["count"]))
		if int(s["have"]) >= int(o["count"]):
			s["step"] = int(s["step"]) + 1
			s["have"] = 0
			if int(s["step"]) >= (quests[id]["objectives"] as Array).size():
				_complete(id)


func _complete(id: String) -> void:
	active.erase(id)
	done.append(id)
	var q: Dictionary = quests[id]
	if player:
		if int(q["xp"]) > 0:
			player.progression.add_xp(int(q["xp"]))
		if int(q["dust"]) > 0:
			player.inventory.add_dust(int(q["dust"]))
	if q["clue"] != "":
		add_clue(q["clue"])
	quest_completed.emit(id)
	for f in q["flags"]:
		flags.set_flag(String(f))


func add_clue(id: String) -> void:
	if clue_defs.has(id) and not clues.has(id):
		clues.append(id)
		clue_added.emit(id)


## The on-screen tracker text: each active quest and its current objective.
func tracker_text() -> String:
	var out := PackedStringArray()
	for id in order:
		if active.has(id):
			var o := current_objective(id)
			var c := " (%d/%d)" % [active[id]["have"], o["count"]] if int(o["count"]) > 1 else ""
			out.append("%s\n  - %s%s" % [quests[id]["title"], o["text"], c])
	return "\n".join(out)


func clue_log_text() -> String:
	var out := PackedStringArray()
	for c in clues:
		out.append("%s: %s" % [clue_defs[c]["title"], clue_defs[c]["text"]])
	return "\n\n".join(out) if not out.is_empty() else "No clues yet."


func to_dict() -> Dictionary:
	return {"active": active.duplicate(true), "done": Array(done), "clues": Array(clues), "flags": flags.to_dict()}


func from_dict(d: Dictionary) -> void:
	active.clear()
	var a: Dictionary = d.get("active", {})
	for id in a:
		if quests.has(id):
			active[String(id)] = {"step": int(a[id].get("step", 0)), "have": int(a[id].get("have", 0))}
	done = PackedStringArray(Array(d.get("done", [])).filter(func(x: Variant) -> bool: return quests.has(String(x))))
	clues = PackedStringArray(
		Array(d.get("clues", [])).filter(func(x: Variant) -> bool: return clue_defs.has(String(x)))
	)
	# Step 118: the save's progress flags (often the same StoryFlags) are already live and may
	# have moved on (the intro advances on level load); only fill in flags that are missing.
	var fd: Dictionary = d.get("flags", {})
	for k in fd:
		if int(fd[k]) != 0 and not flags.values.has(String(k)):
			flags.values[String(k)] = int(fd[k])
