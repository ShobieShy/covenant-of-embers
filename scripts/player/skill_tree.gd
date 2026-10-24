class_name SkillTree
extends RefCounted
## One skill tree read from data/skills/*.toml (BUILD_PLAN step 71). The layout follows
## the common looter-shooter pattern (design pattern only; names and text are ours):
## a tree has branches, each branch has tiers; a tier opens once POINTS_PER_TIER x tier
## points are spent in that branch; skills have ranks (max_rank) and each rank adds its
## effects; the last tier of a branch holds its capstone (one rank). Trees are data, not
## tied to archetypes (Q6 open), and every name in the data is a placeholder.
##
## TOML:
##   [tree]  id, name, tiers (default 6)
##   [[branch]]  id, name, consecrations = ["reaping", ...] (step 72 loot bias, optional)
##   [[skill]]  id, name, branch, tier (0-based), max_rank, desc, capstone (bool, optional),
##              effects = { stat = per_rank, ... }

const POINTS_PER_TIER := 5
const STATS: PackedStringArray = [
	"max_health",
	"max_mana",
	"mana_regen",
	"max_breath",
	"spell_damage",
	"speed_pct",
	"resist_all",
	"kill_mana",
	"kill_health",
	"kill_frenzy",
	"cast_refund",
]

const DEFAULT_PATH := "res://data/skills/ember_path.toml"

static var _default: SkillTree = null
static var _default_loaded := false

var id := ""
var name := ""
var tiers := 6
var branches: Array[Dictionary] = []  ## {id, name, consecrations}
var skills: Dictionary = {}  ## id -> {id, name, branch, tier, max_rank, desc, capstone, effects}
var order: PackedStringArray = []  ## skill ids in file order


## The tree every character uses until Q6 picks characters (null when the file is absent).
static func default_tree() -> SkillTree:
	if not _default_loaded:
		_default_loaded = true
		if FileAccess.file_exists(DEFAULT_PATH):
			var r := load_file(DEFAULT_PATH)
			if r.has("error"):
				push_error(r["error"])
			else:
				_default = r["tree"]
	return _default


static func load_file(path: String) -> Dictionary:
	var d := LevelToml.load_file(path)
	if d.has("error"):
		return d
	return from_dict(d, path)


## {"tree": SkillTree} or {"error": String}.
static func from_dict(d: Dictionary, source := "skills") -> Dictionary:
	var t := SkillTree.new()
	var head: Dictionary = d.get("tree", {})
	t.id = String(head.get("id", ""))
	t.name = String(head.get("name", t.id))
	t.tiers = int(head.get("tiers", 6))
	if t.id.is_empty() or t.tiers < 1:
		return {"error": "%s: [tree] needs an id and tiers >= 1" % source}
	var bids: PackedStringArray = []
	for b in d.get("branch", []):
		var bd: Dictionary = b
		var bid := String(bd.get("id", ""))
		if bid.is_empty() or bids.has(bid):
			return {"error": "%s: branch id missing or duplicate '%s'" % [source, bid]}
		bids.append(bid)
		var cons: Array = bd.get("consecrations", [])
		for c in cons:
			if not Consecrations.IDS.has(String(c)):
				return {"error": "%s: branch %s: unknown consecration '%s'" % [source, bid, c]}
		t.branches.append({"id": bid, "name": String(bd.get("name", bid)), "consecrations": cons})
	if bids.is_empty():
		return {"error": "%s: no [[branch]]" % source}
	for s in d.get("skill", []):
		var sd: Dictionary = s
		var sid := String(sd.get("id", ""))
		if sid.is_empty() or t.skills.has(sid):
			return {"error": "%s: skill id missing or duplicate '%s'" % [source, sid]}
		var br := String(sd.get("branch", ""))
		var tier := int(sd.get("tier", -1))
		var rank := int(sd.get("max_rank", 1))
		var cap := bool(sd.get("capstone", false))
		if not bids.has(br):
			return {"error": "%s: skill %s: unknown branch '%s'" % [source, sid, br]}
		if tier < 0 or tier >= t.tiers:
			return {"error": "%s: skill %s: tier %d outside 0..%d" % [source, sid, tier, t.tiers - 1]}
		if rank < 1 or (cap and (rank != 1 or tier != t.tiers - 1)):
			return {"error": "%s: skill %s: capstones are 1 rank on the last tier; ranks >= 1" % [source, sid]}
		var eff: Dictionary = sd.get("effects", {})
		for k in eff:
			if not STATS.has(String(k)):
				return {"error": "%s: skill %s: unknown effect '%s'" % [source, sid, k]}
		t.skills[sid] = {
			"id": sid,
			"name": String(sd.get("name", sid)),
			"branch": br,
			"tier": tier,
			"max_rank": rank,
			"desc": String(sd.get("desc", "")),
			"capstone": cap,
			"effects": eff,
		}
		t.order.append(sid)
	return {"tree": t}


func skill(sid: String) -> Dictionary:
	return skills.get(sid, {})


func branch(bid: String) -> Dictionary:
	for b in branches:
		if b["id"] == bid:
			return b
	return {}


func in_branch(bid: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for sid in order:
		if skills[sid]["branch"] == bid:
			out.append(sid)
	return out
