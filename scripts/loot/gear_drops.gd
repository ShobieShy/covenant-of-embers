class_name GearDrops
extends RefCounted
## 0.8.7 extra drops. One side stream seeded from the kill rng's state, so the kill
## rng's own draws stay in order. `chance` is unset (0): tests pass an explicit chance.
## Tune it later. Shields, relics, the new bases, and the new parts share the roll.

const SALT := 0x0F1A57

static var chance := 0.0


static func roll(state: int, p_chance := -1.0) -> LootDrop:
	var c := chance if p_chance < 0.0 else p_chance
	if c <= 0.0:
		return null
	var side := RandomNumberGenerator.new()
	side.seed = state ^ SALT
	if side.randf() >= c:
		return null
	var d := LootDrop.new()
	match side.randi() % 4:
		0:
			d.kind = LootDrop.Kind.EQUIPMENT
			d.item = ShieldDrop.make(40.0 + float(side.randi() % 40), 1.0 + float(side.randi() % 3), _effect(side))
			d.rarity_id = "rare"
		1:
			d.kind = LootDrop.Kind.EQUIPMENT
			d.item = RelicDrop.make(RelicDrop.IDS[side.randi() % RelicDrop.IDS.size()])
			d.rarity_id = "rare"
		2:
			d.kind = LootDrop.Kind.WIELDABLE
			var bases := EquipmentRoller.extra_bases()
			d.item = WieldableInstance.load_base(bases[side.randi() % bases.size()])
			d.rarity_id = "uncommon"
		_:
			d.kind = LootDrop.Kind.PART
			var parts := PartRoller.extra_ids()
			var part := WieldablePart.load_part(parts[side.randi() % parts.size()])
			d.item = part.duplicate() if part != null else null
			d.rarity_id = "uncommon"
	if d.item == null:
		return null
	d.rolled_rarity_id = d.rarity_id
	return d


static func _effect(side: RandomNumberGenerator) -> String:
	return ["ward", "spike", "calm"][side.randi() % 3]
