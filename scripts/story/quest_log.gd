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
## Recommended level when the quest row has none. Filth stays the landfill band.
const LEVEL_OF := {
	"old_oak": 1,
	"landfill": 1,
	"midden": 1,
	"breach": 1,
	"labyrinth": 5,
	"gnawer": 1,
	"the_filth": 1,
	"bob": 1,
	"blightmaw_matriarch": 22,
	"forgemaw": 34,
	"drowned_choir": 46,
}

var quests := {}  ## id -> {id, title, objectives: [{kind, target, count, text}], rewards...}
var order: PackedStringArray = []
var clue_defs := {}  ## id -> {title, text}
var flags: StoryFlags
var player: Player  ## optional: gets xp / dust rewards
var active := {}  ## id -> {step: int, have: int}
var done: PackedStringArray = []
var clues: PackedStringArray = []
var known_bosses: Array = []  ## Labyrinth boss ids, for Act II quest seeding
var tracked := ""  ## 0.9.2: the one HUD quest. A main quest takes it. A side quest does not.


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
		var kind := String(q.get("kind", ""))
		if kind != "main" and kind != "side":
			kind = "side" if id in ["joes_marks", "joes_seals"] else "main"
		quests[id] = {
			"id": id,
			"title": String(q.get("title", id)),
			"kind": kind,
			"auto": Array(q.get("auto_start_when", [])),
			"xp": int(q.get("reward_xp", 0)),
			"dust": int(q.get("reward_dust", 0)),
			"gold": int(q.get("reward_gold", 0)),
			"level": int(q.get("level", 0)),
			"giver": String(q.get("giver", "")),
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
					"optional": bool(o.get("optional", false)),
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
	active[id] = {"step": 0, "have": 0, "opt": {}}
	_seed_act2(id)
	_seed_act3(id)
	_seed_sunken(id)
	if active.has(id):
		if kind_of(id) == "main":
			tracked = id
		_skip_optional(id)
	if active.has(id):
		quest_started.emit(id)
	return true


func _seed_act2(id: String) -> void:
	if id == "joes_marks":
		var n := 0
		for k in flags.values:
			if String(k).begins_with("mark:") and int(flags.values[k]) != 0:
				n += 1
		var need := int(quests[id]["objectives"][0]["count"])
		if n >= need:
			_complete(id)
		elif n > 0:
			active[id]["have"] = n
	elif id == "the_overgrown_deep" and known_bosses.has("blightmaw_matriarch"):
		_complete(id)


func _seed_act3(id: String) -> void:
	if id == "joes_seals":
		var n := 0
		for k in flags.values:
			if String(k).begins_with("seal:") and int(flags.values[k]) != 0:
				n += 1
		var need := int(quests[id]["objectives"][0]["count"])
		if n >= need:
			_complete(id)
		elif n > 0:
			active[id]["have"] = n
	elif id == "the_slagworks" and known_bosses.has("forgemaw"):
		_complete(id)


func _seed_sunken(id: String) -> void:
	if id == "the_sunken_ruins" and known_bosses.has("drowned_choir"):
		_complete(id)


func check_auto_start() -> void:
	for id in order:
		var a: Array = quests[id]["auto"]
		if not a.is_empty() and state(id) == "available" and flags.all_of(a):
			start(id)
	if known_bosses.has("forgemaw") and quests.has("the_sunken_ruins") and state("the_sunken_ruins") == "available":
		start("the_sunken_ruins")


func current_objective(id: String) -> Dictionary:
	if not active.has(id):
		return {}
	var steps: Array = quests[id]["objectives"]
	var i := int(active[id]["step"])
	if i < 0 or i >= steps.size():
		return {}
	return steps[i]


func notify(kind: String, target: String, n := 1) -> void:
	for id in active.keys():
		_note_optional(id, kind, target, n)
		_skip_optional(id)
		if not active.has(id):
			continue
		var o := current_objective(id)
		if o.is_empty() or bool(o.get("optional", false)) or o["kind"] != kind or o["target"] != target:
			continue
		var s: Dictionary = active[id]
		s["have"] = mini(int(o["count"]), int(s["have"]) + n)
		objective_progressed.emit(id, int(s["step"]), int(s["have"]), int(o["count"]))
		if int(s["have"]) >= int(o["count"]):
			s["step"] = int(s["step"]) + 1
			s["have"] = 0
			_skip_optional(id)
			if active.has(id) and int(active[id]["step"]) >= (quests[id]["objectives"] as Array).size():
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
		if int(q.get("gold", 0)) > 0:
			player.inventory.add_gold(int(q["gold"]))
	if q["clue"] != "":
		add_clue(q["clue"])
	quest_completed.emit(id)
	for f in q["flags"]:
		flags.set_flag(String(f))
	if tracked == id or not active.has(tracked):
		_follow_main()


func add_clue(id: String) -> void:
	if clue_defs.has(id) and not clues.has(id):
		clues.append(id)
		clue_added.emit(id)


## The HUD line: only the tracked quest, its current step, and any optional step.
func tracker_text() -> String:
	if not active.has(tracked):
		return ""
	var id := tracked
	var o := current_objective(id)
	if o.is_empty():
		return String(quests[id]["title"])
	var c := " (%d/%d)" % [active[id]["have"], o["count"]] if int(o["count"]) > 1 else ""
	var lines: PackedStringArray = ["%s\n  - %s%s" % [quests[id]["title"], o["text"], c]]
	var opt: Dictionary = active[id].get("opt", {})
	for step in quests[id]["objectives"]:
		if not bool(step.get("optional", false)):
			continue
		var have := int(opt.get(step["target"], 0))
		var oc := " (%d/%d)" % [have, step["count"]] if int(step["count"]) > 1 else ""
		lines.append("  optional: %s%s" % [step["text"], oc])
	return "\n".join(lines)


func clue_log_text() -> String:
	var out := PackedStringArray()
	for c in clues:
		out.append("%s: %s" % [clue_defs[c]["title"], clue_defs[c]["text"]])
	return "\n\n".join(out) if not out.is_empty() else "No clues yet."


func to_dict() -> Dictionary:
	return {
		"active": active.duplicate(true),
		"done": Array(done),
		"clues": Array(clues),
		"flags": flags.to_dict(),
		"tracked": tracked,
	}


func from_dict(d: Dictionary) -> void:
	active.clear()
	var a: Dictionary = d.get("active", {})
	for id in a:
		if quests.has(id):
			active[String(id)] = {
				"step": int(a[id].get("step", 0)),
				"have": int(a[id].get("have", 0)),
				"opt": a[id].get("opt", {}),
			}
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
	tracked = String(d.get("tracked", ""))
	if tracked == "" or not active.has(tracked):
		_follow_main()


func kind_of(id: String) -> String:
	return String(quests[id]["kind"]) if quests.has(id) else "main"


## Pressing Track may follow a side quest. Starting a main quest still replaces it.
func track(id: String) -> void:
	if active.has(id):
		tracked = id


func side_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in order:
		if kind_of(id) == "side" and (active.has(id) or done.has(id)):
			out.append(id)
	return out


## The side-quest slice a character file keeps. Main quests stay on the host save.
func side_dict() -> Dictionary:
	var act := {}
	var fin: PackedStringArray = []
	for id in order:
		if kind_of(id) != "side":
			continue
		if active.has(id):
			act[id] = active[id]
		elif done.has(id):
			fin.append(id)
	return {"active": act, "done": Array(fin)}


func apply_side(d: Dictionary) -> void:
	if d.is_empty():
		return
	var act: Dictionary = d.get("active", {})
	for id in act:
		if quests.has(id) and kind_of(id) == "side" and not done.has(id):
			active[id] = {
				"step": int(act[id].get("step", 0)),
				"have": int(act[id].get("have", 0)),
				"opt": act[id].get("opt", {}),
			}
	for id in d.get("done", []):
		var sid := String(id)
		if quests.has(sid) and kind_of(sid) == "side":
			active.erase(sid)
			if not done.has(sid):
				done.append(sid)


func recommended(id: String) -> int:
	if not quests.has(id):
		return 0
	if int(quests[id].get("level", 0)) > 0:
		return int(quests[id]["level"])
	var target := ""
	if active.has(id):
		var o := current_objective(id)
		target = String(o.get("target", "")) if not o.is_empty() else ""
	elif not (quests[id]["objectives"] as Array).is_empty():
		target = String(quests[id]["objectives"][0]["target"])
	return int(LEVEL_OF.get(target, 1))


func reward_line(id: String) -> String:
	if not quests.has(id):
		return ""
	var q: Dictionary = quests[id]
	return "%d XP, %d dust" % [int(q["xp"]), int(q["dust"])]


func _follow_main() -> void:
	for id in order:
		if active.has(id) and kind_of(id) == "main":
			tracked = id
			return
	tracked = ""


func _skip_optional(id: String) -> void:
	while active.has(id):
		var o := current_objective(id)
		if o.is_empty() or not bool(o.get("optional", false)):
			return
		var s: Dictionary = active[id]
		s["step"] = int(s["step"]) + 1
		s["have"] = 0
		if int(s["step"]) >= (quests[id]["objectives"] as Array).size():
			_complete(id)
			return


func _note_optional(id: String, kind: String, target: String, n: int) -> void:
	if not active.has(id):
		return
	var opt: Dictionary = active[id].get("opt", {})
	for step in quests[id]["objectives"]:
		if not bool(step.get("optional", false)) or step["kind"] != kind or step["target"] != target:
			continue
		opt[target] = mini(int(step["count"]), int(opt.get(target, 0)) + n)
	active[id]["opt"] = opt
