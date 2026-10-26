class_name Skills
extends RefCounted
## Per-character skill state (BUILD_PLAN step 71): ranks spent in one SkillTree.
## Points: one per level from FIRST_POINT_LEVEL (level 2 -> 1 point, level 10 -> 9).
## A skill can take a rank when a point is free, it is below max_rank and its tier is
## open: tier t needs t x SkillTree.POINTS_PER_TIER points already spent in its branch.
## respec() refunds everything (at the Old Oak; Player.respec_price() gold, step 59).
## totals() sums every rank's effects; Player.apply_bonuses() reads it (never +=/-=).
## Ranks travel with the character save (portable between hosts, step 91).
## Phase V step 144: plus 7 element trees (SkillTree.element_tree) drawing on the same point
## pool. Element tiers open on points spent in that tree (tier t needs 5t); a capstone needs
## 25 points and a tier-4 skill, and only one element capstone may be owned at a time
## (CAPSTONE_LOCKED; respec unlocks). Saves: "elements" {tree: {sid: rank}}, skills_version 2.

signal changed

const FIRST_POINT_LEVEL := 2
const VERSION := 2
const CAPSTONE_LOCKED := "capstone_locked"
const CAPSTONE_POINTS := 25

var tree: SkillTree
var ranks: Dictionary = {}  ## skill id -> rank
var respecs := 0
var el_ranks: Dictionary = {}  ## step 144: element tree id -> {skill id -> rank}


static func points_for_level(level: int) -> int:
	return maxi(0, level - FIRST_POINT_LEVEL + 1)


func spent() -> int:
	var n := 0
	for k in ranks:
		n += int(ranks[k])
	for el in el_ranks:
		n += el_spent(el)
	return n


func core_spent() -> int:
	var n := 0
	for k in ranks:
		n += int(ranks[k])
	return n


func el_rank(el: String, sid: String) -> int:
	return int(el_ranks.get(el, {}).get(sid, 0))


func el_spent(el: String) -> int:
	var n := 0
	var d: Dictionary = el_ranks.get(el, {})
	for k in d:
		n += int(d[k])
	return n


## The element tree that owns the exclusive capstone, "" when none.
func capstone_owner() -> String:
	for el in ElementTable.IDS:
		var t := SkillTree.element_tree(el)
		if t == null:
			continue
		for sid in el_ranks.get(el, {}):
			if bool(t.skill(sid).get("capstone", false)):
				return el
	return ""


func _has_tier(el: String, tier: int) -> bool:
	var t := SkillTree.element_tree(el)
	for sid in el_ranks.get(el, {}):
		if int(t.skill(sid).get("tier", -1)) == tier:
			return true
	return false


## "" when a rank of element skill `sid` in tree `el` can be taken, else why not
## (CAPSTONE_LOCKED when another tree owns the element capstone).
func el_why_not(el: String, sid: String, level: int) -> String:
	var t := SkillTree.element_tree(el)
	if t == null:
		return "no skill tree"
	var s := t.skill(sid)
	if s.is_empty():
		return "unknown skill"
	if el_rank(el, sid) >= int(s["max_rank"]):
		return "max rank"
	if bool(s["capstone"]):
		var own := capstone_owner()
		if not own.is_empty() and own != el:
			return CAPSTONE_LOCKED
	if available(level) <= 0:
		return "no skill points"
	var tier := int(s["tier"])
	if bool(s["capstone"]):
		if el_spent(el) < CAPSTONE_POINTS or not _has_tier(el, tier - 1):
			return "needs %d points in %s and a tier %d skill" % [CAPSTONE_POINTS, t.name, tier]
	elif el_spent(el) < tier * SkillTree.POINTS_PER_TIER:
		return "needs %d points in %s" % [tier * SkillTree.POINTS_PER_TIER, t.name]
	return ""


func el_spend(el: String, sid: String, level: int) -> bool:
	if not el_why_not(el, sid, level).is_empty():
		return false
	if not el_ranks.has(el):
		el_ranks[el] = {}
	el_ranks[el][sid] = el_rank(el, sid) + 1
	changed.emit()
	return true


## Sum of tree `el`'s effects over its spent ranks: stat -> value.
func el_totals(el: String) -> Dictionary:
	var out := {}
	var t := SkillTree.element_tree(el)
	if t == null:
		return out
	var d: Dictionary = el_ranks.get(el, {})
	for sid in d:
		var eff: Dictionary = t.skill(sid).get("effects", {})
		for k in eff:
			out[k] = float(out.get(k, 0.0)) + float(eff[k]) * int(d[sid])
	return out


func available(level: int) -> int:
	return points_for_level(level) - spent()


func rank(sid: String) -> int:
	return int(ranks.get(sid, 0))


func spent_in(bid: String) -> int:
	var n := 0
	if tree == null:
		return 0
	for sid in ranks:
		var s := tree.skill(sid)
		if not s.is_empty() and s["branch"] == bid:
			n += int(ranks[sid])
	return n


func tier_open(bid: String, tier: int) -> bool:
	return spent_in(bid) >= tier * SkillTree.POINTS_PER_TIER


## "" when the rank can be taken, else why not.
func why_not(sid: String, level: int) -> String:
	if tree == null:
		return "no skill tree"
	var s := tree.skill(sid)
	if s.is_empty():
		return "unknown skill"
	if rank(sid) >= int(s["max_rank"]):
		return "max rank"
	if available(level) <= 0:
		return "no skill points"
	if not tier_open(s["branch"], int(s["tier"])):
		return "needs %d points in %s" % [int(s["tier"]) * SkillTree.POINTS_PER_TIER, s["branch"]]
	return ""


func spend(sid: String, level: int) -> bool:
	if not why_not(sid, level).is_empty():
		return false
	ranks[sid] = rank(sid) + 1
	changed.emit()
	return true


## Refunds every point; returns how many came back.
func respec() -> int:
	var n := spent()
	ranks.clear()
	el_ranks.clear()
	if n > 0:
		respecs += 1
		changed.emit()
	return n


## Sum of every effect over the spent ranks: stat -> value.
func totals() -> Dictionary:
	var out := {}
	if tree == null:
		return out
	for sid in ranks:
		var s := tree.skill(sid)
		if s.is_empty():
			continue
		var eff: Dictionary = s["effects"]
		for k in eff:
			out[k] = float(out.get(k, 0.0)) + float(eff[k]) * int(ranks[sid])
	return out


func total(stat: String) -> float:
	return float(totals().get(stat, 0.0))


## The branch with the most points (ties: first in the file); "" when nothing is spent.
func main_branch() -> String:
	if tree == null:
		return ""
	var best := ""
	var most := 0
	for b in tree.branches:
		var n := spent_in(b["id"])
		if n > most:
			most = n
			best = b["id"]
	return best


func to_dict() -> Dictionary:
	return {
		"tree": tree.id if tree else "",
		"ranks": ranks.duplicate(),
		"respecs": respecs,
		"elements": el_ranks.duplicate(true),
		"skills_version": VERSION,
	}


## Loads saved ranks; unknown skills are dropped, ranks clamped, and an over-spent set
## (fewer points than ranks, e.g. an edited save) is refunded entirely. Returns warnings.
## A version-1 save (no "elements") loads with empty element trees; with two element
## capstones the first in ElementTable.IDS order is kept and the other refunded.
func from_dict(d: Dictionary, level: int) -> PackedStringArray:
	var warn := PackedStringArray()
	ranks.clear()
	el_ranks.clear()
	var els: Dictionary = d.get("elements", {}) if d.get("elements", {}) is Dictionary else {}
	var cap_kept := ""
	for el in ElementTable.IDS:
		if not els.has(el) or not (els[el] is Dictionary):
			continue
		var t := SkillTree.element_tree(el)
		var out := {}
		for sid in els[el]:
			var s := t.skill(String(sid)) if t else {}
			if s.is_empty():
				warn.append("skills: dropped unknown %s skill '%s'" % [el, sid])
				continue
			if bool(s["capstone"]):
				if not cap_kept.is_empty():
					warn.append("skills: second capstone %s refunded (kept %s)" % [sid, cap_kept])
					continue
				cap_kept = String(sid)
			var r := clampi(int(els[el][sid]), 0, int(s["max_rank"]))
			if r > 0:
				out[String(sid)] = r
		if not out.is_empty():
			el_ranks[el] = out
	for k in els:
		if not ElementTable.IDS.has(String(k)):
			warn.append("skills: dropped unknown tree '%s'" % k)
	respecs = int(d.get("respecs", 0))
	var saved: Dictionary = d.get("ranks", {})
	for sid in saved:
		var s := tree.skill(String(sid)) if tree else {}
		if s.is_empty():
			warn.append("skills: dropped unknown skill '%s'" % sid)
			continue
		var r := clampi(int(saved[sid]), 0, int(s["max_rank"]))
		if r > 0:
			ranks[String(sid)] = r
	if available(level) < 0:
		warn.append("skills: %d ranks for %d points; refunded" % [spent(), points_for_level(level)])
		ranks.clear()
		el_ranks.clear()
	changed.emit()
	return warn
