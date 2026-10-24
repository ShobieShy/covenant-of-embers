class_name Progression
extends RefCounted
## XP and levels (BUILD_PLAN step 27; Magewar magewar_player.gd add_xp / _level_up):
## level 1, 0 XP, 100 XP to the next level; add_xp loops (one kill can give several
## levels), each level-up keeps the overflow and sets the next threshold to
## int(threshold x 1.5): 100, 150, 225, 337, 505, ...
## Per level (Magewar): +5 max mana and +5 max Breath (stamina), both refilled. Magewar
## gives no health on level-up, so HEALTH_PER_LEVEL is 0 (flagged for ShobieShy).
## Player.on_level_up() applies the gains; this class is pure numbers.

signal leveled_up(new_level: int)

const START_XP_TO_NEXT := 100
const GROWTH := 1.5
const MANA_PER_LEVEL := 5.0
const BREATH_PER_LEVEL := 5.0
const HEALTH_PER_LEVEL := 0.0
const MAX_LEVEL := 50          ## enemies are 1..50 (EnemyDef.MAX_LEVEL)

var level := 1
var xp := 0                    ## toward the next level
var xp_to_next := START_XP_TO_NEXT
var total_xp := 0

## Threshold to leave `lv` (level 1 -> 100).
static func threshold(lv: int) -> int:
	var t := START_XP_TO_NEXT
	for i in range(1, lv):
		t = int(t * GROWTH)
	return t

## Adds XP; returns how many levels were gained.
func add_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	total_xp += amount
	if level >= MAX_LEVEL:
		return 0
	xp += amount
	var gained := 0
	while xp >= xp_to_next and level < MAX_LEVEL:
		xp -= xp_to_next
		level += 1
		xp_to_next = int(xp_to_next * GROWTH)
		gained += 1
		leveled_up.emit(level)
	if level >= MAX_LEVEL:
		xp = 0
	return gained
