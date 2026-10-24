class_name Skills
extends RefCounted
## Per-character skill state (BUILD_PLAN step 71): ranks spent in one SkillTree.
## Points: one per level from FIRST_POINT_LEVEL (level 2 -> 1 point, level 10 -> 9).
## A skill can take a rank when a point is free, it is below max_rank and its tier is
## open: tier t needs t x SkillTree.POINTS_PER_TIER points already spent in its branch.
## respec() refunds everything (free at the Old Oak; a gold cost waits for Q4).
## totals() sums every rank's effects; Player.apply_bonuses() reads it (never +=/-=).
## Ranks travel with the character save (portable between hosts, step 91).

signal changed

const FIRST_POINT_LEVEL := 2

var tree: SkillTree
var ranks: Dictionary = {}  ## skill id -> rank
var respecs := 0


static func points_for_level(level: int) -> int:
	return maxi(0, level - FIRST_POINT_LEVEL + 1)


func spent() -> int:
	var n := 0
	for k in ranks:
		n += int(ranks[k])
	return n


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
	return {"tree": tree.id if tree else "", "ranks": ranks.duplicate(), "respecs": respecs}


## Loads saved ranks; unknown skills are dropped, ranks clamped, and an over-spent set
## (fewer points than ranks, e.g. an edited save) is refunded entirely. Returns warnings.
func from_dict(d: Dictionary, level: int) -> PackedStringArray:
	var warn := PackedStringArray()
	ranks.clear()
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
	changed.emit()
	return warn
