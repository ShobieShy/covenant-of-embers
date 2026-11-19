class_name XpRewarder
extends Node
## Kill XP (BUILD_PLAN step 27; Magewar MagewarKillRewardService): on EventBus.enemy_killed
## every Player within RANGE m of the corpse gets the enemy's xp_reward (x xp_multiplier,
## Magewar get_xp_multiplier; 1.0 here). Training dummies give nothing (they respawn).
## Gold (Magewar gold_drop) isn't granted: our currency arrives with vendors (PLAN Tallies).

const RANGE := 80.0

var xp_multiplier := 1.0
var granted := 0  ## XP handed out (all players)
var kills_seen := 0
var resolve_bonus := 0  ## step 70: extra XP from Resolve catch-up
var _paid := {}  ## corpse key -> true once this peer was granted the kill's XP


func _ready() -> void:
	GameEvents.bus().enemy_killed.connect(_on_killed)


func _exit_tree() -> void:
	if GameEvents.bus().enemy_killed.is_connected(_on_killed):
		GameEvents.bus().enemy_killed.disconnect(_on_killed)


func _key(e: Enemy) -> int:
	return int(e.get_meta(&"net_id", e.get_instance_id()))


func _on_killed(e: Enemy, _element: ElementTable.Element) -> void:
	kills_seen += 1
	if e == null or e.def == null or e.def.id.ends_with("training_dummy") or not is_inside_tree():
		return
	var key := _key(e)
	if _paid.has(key):
		return
	var near: Array[Player] = []
	var expected := 1
	for n in get_tree().get_nodes_in_group(Player.GROUP):
		var p := n as Player
		if p != null and p.is_inside_tree() and p.global_position.distance_to(e.global_position) <= RANGE:
			near.append(p)
			expected = maxi(expected, p.progression.level)
	if near.is_empty():
		return
	_paid[key] = true
	_give(near, e.def, e.combat_dl(LevelScale.player_level) if LevelScale.player_level > 0 else 0, expected)


## The shooter of a hit that arrived after death. Once per corpse. No-op if the
## kill already paid someone in range.
func pay_corpse(key: int, def: EnemyDef) -> bool:
	if def == null or def.id.ends_with("training_dummy") or _paid.has(key) or not is_inside_tree():
		return false
	var near: Array[Player] = []
	var expected := 1
	for n in get_tree().get_nodes_in_group(Player.GROUP):
		var p := n as Player
		if p != null and p.is_inside_tree():
			near.append(p)
			expected = maxi(expected, p.progression.level)
	if near.is_empty():
		return false
	_paid[key] = true
	_give(near, def, 0, expected)
	return true


func _give(near: Array[Player], def: EnemyDef, d_l: int, expected: int) -> void:
	var xp_scale := LevelScale.mult("xp", d_l) if LevelScale.player_level > 0 else 1.0
	var amount := int(round(def.xp_reward * xp_scale * xp_multiplier))
	if amount <= 0:
		return
	for p in near:
		var got := int(amount * Progression.resolve_multiplier(p.progression.level, expected))
		p.add_xp(got)
		granted += got
		resolve_bonus += got - amount
