class_name DropTable
extends Resource
## Every drop pool (BUILD_PLAN step 18): resources/loot/drop_pools.tres, loaded and
## validated once by DropRoller.default_pools(). pool_for(enemy, level) prefers a pool
## naming the enemy over a generic one (empty enemy_ids); two pools of the same kind may not overlap for an
## enemy/level (validate), so the choice is never ambiguous. Step 21's patches tune it on a
## duplicate(true) + validate(), like RarityTable.
## No static func returning DropTable here: in Godot 4.7.2 that (a self-typed static method,
## godotengine/godot#86540) made the test run leak every cached script/resource at exit
## ("resources still in use" ERROR lines) depending on load order; the shared copy lives
## in DropRoller.default_pools() instead.

const PATH := "res://resources/loot/drop_pools.tres"

@export var pools: Array[DropPool] = []


func find(pool_id: String) -> DropPool:
	for p in pools:
		if p != null and p.id == pool_id:
			return p
	return null


## The pool for an enemy at a level (specific before generic), or null (no pool drop).
func pool_for(enemy_id: String, level: int) -> DropPool:
	var generic: DropPool = null
	for p in pools:
		if p == null or not p.applies_to(enemy_id, level):
			continue
		if not p.enemy_ids.is_empty():
			return p
		if generic == null:
			generic = p
	return generic


func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	var seen := {}
	for p in pools:
		if p == null:
			errs.append("null pool")
			continue
		if seen.has(p.id):
			errs.append("pool '%s': duplicate id" % p.id)
		seen[p.id] = true
		errs.append_array(p.validate())
	# No ambiguous overlap: same enemy (or both generic) and intersecting level bands.
	for i in pools.size():
		for j in range(i + 1, pools.size()):
			var a := pools[i]
			var b := pools[j]
			if a == null or b == null:
				continue
			if a.max_level < b.min_level or b.max_level < a.min_level:
				continue
			var clash := a.enemy_ids.is_empty() and b.enemy_ids.is_empty()
			for e in a.enemy_ids:
				clash = clash or b.enemy_ids.has(e)
			if clash:
				errs.append("pools '%s' and '%s' overlap (same enemy, levels intersect)" % [a.id, b.id])
	return errs
