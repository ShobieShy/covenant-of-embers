class_name DeepGear
extends RefCounted
## A story-run drop of gear from a deeper Covenant Escalation tier. The side stream
## does not draw on the kill rng. `chance` is unset (0). Tests pass an explicit chance.
## The part keeps its effect. `story_floor` is stamped on the drop so the numbers can
## be read as that floor's level.

const SALT := 0x0D3E900D
const PART := "cinder_of_the_heap"

static var chance := 0.0


static func roll(state: int, story_floor: int, p_chance := -1.0) -> LootDrop:
	var c := chance if p_chance < 0.0 else p_chance
	if c <= 0.0:
		return null
	var side := RandomNumberGenerator.new()
	side.seed = state ^ SALT
	if side.randf() >= c:
		return null
	var part := WieldablePart.load_part(PART)
	if part == null:
		return null
	var copy := part.duplicate()
	copy.set_meta(&"story_level", story_floor)
	copy.set_meta(&"source_tier", side.randi() % Vigil.MAX_TIER + 1)
	var d := LootDrop.new()
	d.kind = LootDrop.Kind.PART
	d.item = copy
	d.rarity_id = "unique"
	d.rolled_rarity_id = "unique"
	d.element = copy.element
	return d
