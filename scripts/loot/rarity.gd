class_name Rarity
extends Resource
## One rarity tier (BUILD_PLAN step 15; PLAN §30.2). Follows Magewar's ItemRarity directly
## (weapon/loot system = Magewar design): the same six tiers in Magewar's enum order, its
## names, colours, stat multipliers and drop weights. Magewar keeps them in const
## Dictionaries; ours are data (resources/loot/rarities.tres, a RarityTable) so step 21's
## balance patches and step 28's Vigil weights can tune them.
## Items store the rarity as its id string ("basic" .. "unique"); look the tier up with
## Rarity.of(id) / RarityTable.load_default().

enum Tier { BASIC, UNCOMMON, RARE, MYTHIC, PRIMORDIAL, UNIQUE }   ## Magewar ItemRarity.Rarity order

const COUNT := 6
const IDS: PackedStringArray = ["basic", "uncommon", "rare", "mythic", "primordial", "unique"]

@export var id := ""                  ## IDS
@export var display_name := ""        ## Magewar RARITY_NAMES
@export var color := Color.WHITE      ## Magewar RARITY_COLORS (UI tint, pickup beam)
@export var multiplier := 1.0         ## Magewar RARITY_MULTIPLIERS: base damage (and step 16 rolls)
@export var drop_weight := 1.0        ## Magewar RARITY_DROP_WEIGHTS (higher = more common)

## Tier index for an id, or -1 when unknown.
static func parse(rarity_id: String) -> int:
	return IDS.find(rarity_id)

static func id_of(t: Tier) -> String:
	return IDS[t]

## The shared tier for an id (null when unknown).
static func of(rarity_id: String) -> Rarity:
	return RarityTable.load_default().find(rarity_id)

func tier() -> int:
	return IDS.find(id)

## Magewar luck rule (roll_rarity): Basic/Uncommon lose `common_step` weight per luck point
## (never below `floor_w`), Rare and above gain `rare_step` per point.
func weight_with_luck(luck: float, common_step := 5.0, rare_step := 2.0, floor_w := 1.0) -> float:
	if tier() <= Tier.UNCOMMON:
		return maxf(floor_w, drop_weight - luck * common_step)
	return maxf(0.0, drop_weight + luck * rare_step)
