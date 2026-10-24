class_name DropPool
extends Resource
## A weighted drop pool (BUILD_PLAN step 18; PLAN §31.4 "one weight model": probability =
## weight / Σweights). Magewar's enemy `loot_table` + `drop_chance` (enemy_base.gd
## _drop_loot), reinterpreted: Magewar rolls every listed item independently (randf <=
## drop_chance each); ours rolls once per kill against `drop_chance` and then picks ONE
## entry, rarity first:
##   1. rarity = RarityTable.roll(rng, luck)            (one rng.randf(); Magewar luck rule)
##   2. entry  = weighted pick among entries of that tier (one rng.randf())
##      - none of that tier: fall back down a tier until one has entries;
##      - none at or below: the lowest tier above it (so an Uncommon-only pool still drops).
## A pool applies to `enemy_ids` (empty = any enemy) within [min_level, max_level];
## DropTable.pool_for() picks one.

@export var id := ""
@export var enemy_ids: PackedStringArray = []   ## EnemyDef ids; empty = generic
@export var min_level := 1                      ## Magewar enemy_level 1..50
@export var max_level := 50
@export_range(0.0, 1.0) var drop_chance := 0.3  ## Magewar enemy_base drop_chance default 0.3
@export var entries: Array[DropEntry] = []

const MAX_LEVEL := 50

func applies_to(enemy_id: String, level: int) -> bool:
	return level >= min_level and level <= max_level and (enemy_ids.is_empty() or enemy_ids.has(enemy_id))

## Entries whose rarity is tier `t`.
func entries_of_tier(t: int) -> Array[DropEntry]:
	var out: Array[DropEntry] = []
	for e in entries:
		if e != null and e.tier() == t:
			out.append(e)
	return out

## The tier a roll of `t` resolves to (fallback rule above); -1 for an empty pool.
func resolve_tier(t: int) -> int:
	for down in range(clampi(t, 0, Rarity.COUNT - 1), -1, -1):
		if not entries_of_tier(down).is_empty():
			return down
	for up in range(clampi(t, 0, Rarity.COUNT - 1) + 1, Rarity.COUNT):
		if not entries_of_tier(up).is_empty():
			return up
	return -1

## Weighted pick among the entries of resolve_tier(t): exactly one rng.randf() (none for an
## empty pool, which returns null).
func pick_entry(rng: RandomNumberGenerator, t: int) -> DropEntry:
	var rows := entries_of_tier(resolve_tier(t))
	if rows.is_empty():
		return null
	var total := 0.0
	for e in rows:
		total += e.weight
	var pick := rng.randf() * total
	var cum := 0.0
	for e in rows:
		cum += e.weight
		if pick < cum:
			return e
	return rows[rows.size() - 1]

## One pool drop (ignores drop_chance; DropRoller.roll_kill applies it): two rng.randf()
## draws (rarity, entry). Null for an empty pool.
func roll(rng: RandomNumberGenerator, luck := 0.0, table: RarityTable = null) -> LootDrop:
	var rt := table if table != null else RarityTable.load_default()
	var rolled := rt.roll(rng, luck)
	var e := pick_entry(rng, rolled.tier())
	if e == null:
		return null
	var d := LootDrop.new()
	d.kind = LootDrop.Kind.WIELDABLE
	d.item = e.make()
	d.rarity_id = e.rarity_id()
	d.rolled_rarity_id = rolled.id
	d.element = e.def().element
	d.pool_id = id
	d.entry = e
	return d

## Exact chance of each entry per pool roll (same order as `entries`): Σ over rolled tiers
## of P(tier) × weight / Σ weights of the tier it resolves to. The done check compares
## 10 000 rolls against this.
func expected_chances(luck := 0.0, table: RarityTable = null) -> PackedFloat64Array:
	var rt := table if table != null else RarityTable.load_default()
	var w := rt.weights(luck)
	var total := 0.0
	for x in w:
		total += x
	var out := PackedFloat64Array()
	out.resize(entries.size())
	for t in Rarity.COUNT:
		if w[t] <= 0.0 or total <= 0.0:
			continue
		var r := resolve_tier(t)
		if r < 0:
			continue
		var tier_sum := 0.0
		for e in entries_of_tier(r):
			tier_sum += e.weight
		for i in entries.size():
			if entries[i] != null and entries[i].tier() == r:
				out[i] += w[t] / total * entries[i].weight / tier_sum
	return out

## Empty when usable; else one message per problem.
func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	var tag := "pool '%s'" % id
	if RegEx.create_from_string("^[a-z0-9_]+$").search(id) == null:
		errs.append("%s: id must be lower_snake_case" % tag)
	if not (min_level >= 1 and min_level <= max_level and max_level <= MAX_LEVEL):
		errs.append("%s: levels must satisfy 1 <= min <= max <= %d (got %d..%d)" % [tag, MAX_LEVEL, min_level, max_level])
	if not (drop_chance >= 0.0 and drop_chance <= 1.0):
		errs.append("%s: drop_chance must be in 0..1" % tag)
	if entries.is_empty():
		errs.append("%s: no entries" % tag)
	for e in entries:
		if e == null:
			errs.append("%s: null entry" % tag)
			continue
		for m in e.validate():
			errs.append("%s: %s" % [tag, m])
	var seen := {}
	for e in entries:
		if e == null:
			continue
		var key := "%s@%s" % [e.wieldable_id, e.rarity_id()]
		if seen.has(key):
			errs.append("%s: duplicate entry %s" % [tag, key])
		seen[key] = true
	return errs
