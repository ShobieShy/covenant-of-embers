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
## Phase V step 144 (docs/ELEMENT_TREES_PLAN.md): an element tree sets [tree] element = "<id>"
## and gate = "tree" (tiers open on points spent in the whole tree, not one branch); its
## effects use ELEMENT_STATS (read by ElementSkillMods for casts of that element), and its
## capstone carries exclusive_group = "element_capstone" (one capstone across all trees).

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

## Per-element modifier keys (ElementSkillMods); values are per rank.
const ELEMENT_STATS: PackedStringArray = [
	"damage_pct",
	"cost_pct",
	"accuracy",
	"cooldown_pct",
	"bloom_pct",
	"range_pct",
	"status_seconds",
	"status_pct",
	"status_damage_pct",
	"vs_status_pct",
	"vs_mark_status_pct",
	"mark_seconds",
	"mark_pct",
	"crit_chance",
	"crit_damage_pct",
	"weakpoint_pct",
	"chain_range",
	"chain_jumps",
	"heal_pct",
	"turn_chance",
	"kill_mana",
	"kill_health",
	"resist_pct",
	"move_pct",
	"heat_pct",
	"heat_decay_pct",
	"hot_damage_pct",
	"vent_pct",
	"crystal_cost_pct",
	"charge_pct",
	"splash_pct",
	"splash_damage_pct",
	"speed_pct",
	"spin_pct",
	"ramp_pct",
	"echo",
	"capstone",
]
const ELEMENT_DIR := "res://data/skills/%s.toml"

const DEFAULT_PATH := "res://data/skills/ember_path.toml"

static var _default: SkillTree = null
static var _default_loaded := false

var id := ""
var name := ""
var tiers := 6
var element := ""  ## step 144: "" = Core tree, else an ElementTable id
var gate := "branch"  ## "branch" (Core) or "tree" (element trees)
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


static var _elements: Dictionary = {}


## Step 144: the element tree for `el` (ElementTable id), null when its file is absent.
static func element_tree(el: String) -> SkillTree:
	if not _elements.has(el):
		_elements[el] = null
		var path := ELEMENT_DIR % el
		if FileAccess.file_exists(path):
			var r := load_file(path)
			if r.has("error"):
				push_error(r["error"])
			else:
				_elements[el] = r["tree"]
	return _elements[el]


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
	t.element = String(head.get("element", ""))
	t.gate = String(head.get("gate", "branch"))
	if not t.element.is_empty() and ElementTable.parse(t.element) < 0:
		return {"error": "%s: unknown element '%s'" % [source, t.element]}
	if t.gate != "branch" and t.gate != "tree":
		return {"error": "%s: gate must be branch or tree" % source}
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
		var vocab := STATS if t.element.is_empty() else ELEMENT_STATS
		for k in eff:
			if not vocab.has(String(k)):
				return {"error": "%s: skill %s: unknown effect '%s'" % [source, sid, k]}
		t.skills[sid] = {
			"id": sid,
			"name": String(sd.get("name", sid)),
			"branch": br,
			"tier": tier,
			"max_rank": rank,
			"desc": String(sd.get("desc", "")),
			"capstone": cap,
			"exclusive_group": String(sd.get("exclusive_group", "")),
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
