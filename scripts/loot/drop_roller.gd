class_name DropRoller
extends RefCounted
## Kill drops (BUILD_PLAN step 18; step 22 calls roll_kill from EventBus.enemy_killed).
## Follows Magewar's enemy_base._drop_loot order: the enemy's loot table first (ours: a
## weighted DropPool, rolled once against its drop_chance), then the procedural drops of
## MagewarInstancedLootService.roll_procedural_drops, with the same draw order:
##   for each of part_count(level) parts (1, +1 when enemy level >= 3):
##     part type uniform over the 5 (rng.randi_range), rarity = RarityTable.roll(rng, luck),
##     element = the enemy's (else PartRoller.roll_element(rng)), PartRoller.roll(rng, ...)
##   then randf() < EQUIP_CHANCE (25 %): one equipment piece: slot uniform over
##     Hat/Clothes/Belt/Shoes, rarity = RarityTable.roll(rng, luck × 0.5), seed = rng.randi()
##     -> item = EquipmentRoller.from_seed(seed, slot, rarity, element) (step 19; no extra
##     draws from rng, so the replay contract of test_pools holds).
## Reinterpreted (flagged): Magewar's roll_rarity_seeded uses fixed thresholds
## 45/25/15/8/5/2 % (+ luck × 0.05 on the roll) that disagree with its own ItemRarity drop
## weights 50/25/15/7/2/1; ours uses RarityTable (PLAN §30.2) for every drop. Everything is
## drawn from the caller's rng (Magewar solo kills use rng.randomize(); co-op uses
## LootDropper.make_peer_rng(seed_base, peer_id) per player, step 22).

const EQUIP_CHANCE := 0.25  ## Magewar roll_procedural_drops
const EQUIP_LUCK_SCALE := 0.5  ## Magewar: equipment rarity rolls with luck × 0.5
const EXTRA_PART_LEVEL := 3  ## Magewar: +1 part when enemy_level >= 3

static var _pools: DropTable


## The shared pools (resources/loot/drop_pools.tres), loaded and validated once.
static func default_pools() -> DropTable:
	if _pools == null:
		_pools = load(DropTable.PATH) as DropTable
		var errs := _pools.validate()
		if not errs.is_empty():
			push_error("%s: %s" % [DropTable.PATH, "; ".join(errs)])
	return _pools


static func part_count(enemy_level: int) -> int:
	return 1 + (1 if enemy_level >= EXTRA_PART_LEVEL else 0)


## Magewar roll_procedural_drops. `element` < 0 = no enemy element (roll one per drop).
static func roll_procedural(
	rng: RandomNumberGenerator,
	enemy_level: int,
	element: int = -1,
	luck := 0.0,
	table: RarityTable = null
) -> Array[LootDrop]:
	var rt := table if table != null else RarityTable.load_default()
	var out: Array[LootDrop] = []
	for i in part_count(enemy_level):
		var part_type := (
			rng.randi_range(0, WieldablePart.PART_TYPE_NAMES.size() - 1) as WieldablePart.PartType
		)
		var rarity := rt.roll(rng, luck)
		var el := _element(rng, element)
		var part := PartRoller.roll(rng, part_type, rarity.id, el)
		if part == null:
			continue
		var d := LootDrop.new()
		d.kind = LootDrop.Kind.PART
		d.item = part
		d.rarity_id = rarity.id
		d.rolled_rarity_id = rarity.id
		d.element = part.element
		d.roll_seed = part.roll_seed
		out.append(d)
	if rng.randf() < EQUIP_CHANCE:
		var e := LootDrop.new()
		e.kind = LootDrop.Kind.EQUIPMENT
		e.equip_slot = rng.randi_range(0, LootDrop.DROP_EQUIP_SLOTS - 1)
		var r := rt.roll(rng, luck * EQUIP_LUCK_SCALE)
		e.rarity_id = r.id
		e.rolled_rarity_id = r.id
		e.element = _element(rng, element)
		e.roll_seed = rng.randi()
		e.item = EquipmentRoller.from_seed(e.roll_seed, e.equip_slot, r.id, e.element)
		out.append(e)
	return out


## Everything one kill drops for one player: the enemy's pool (when one applies and
## randf() < drop_chance), then roll_procedural. `pools` defaults to default_pools().
static func roll_kill(
	rng: RandomNumberGenerator,
	enemy_id: String,
	enemy_level: int,
	element: int = -1,
	luck := 0.0,
	pools: DropTable = null,
	table: RarityTable = null,
	players := 1
) -> Array[LootDrop]:
	var dt := pools if pools != null else default_pools()
	var out: Array[LootDrop] = []
	var pool := dt.pool_for(enemy_id, enemy_level)
	if pool != null and rng.randf() < ActLoot.party_chance(pool.drop_chance, players):
		var d := pool.roll(rng, luck, table)
		if d != null:
			out.append(d)
	out.append_array(roll_procedural(rng, enemy_level, element, luck, table))
	return out


## roll_kill for an EnemyDef (its id, level and affinity as the drop element).
static func roll_enemy(
	rng: RandomNumberGenerator,
	def: EnemyDef,
	luck := 0.0,
	pools: DropTable = null,
	table: RarityTable = null
) -> Array[LootDrop]:
	return roll_kill(rng, def.id, def.level, def.affinity, luck, pools, table)


static func _element(rng: RandomNumberGenerator, element: int) -> ElementTable.Element:
	if element >= 0 and element < ElementTable.COUNT:
		return element as ElementTable.Element
	return PartRoller.roll_element(rng)
