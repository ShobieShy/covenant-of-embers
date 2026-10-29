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


func _ready() -> void:
	GameEvents.bus().enemy_killed.connect(_on_killed)


func _exit_tree() -> void:
	if GameEvents.bus().enemy_killed.is_connected(_on_killed):
		GameEvents.bus().enemy_killed.disconnect(_on_killed)


func _on_killed(e: Enemy, _element: ElementTable.Element) -> void:
	kills_seen += 1
	if e == null or e.def == null or e.def.id.ends_with("training_dummy") or not is_inside_tree():
		return
	var viewer := LevelScale.player_level
	var xp_scale := 1.0
	if viewer > 0 and e.def != null:
		xp_scale = LevelScale.mult("xp", e.combat_dl(viewer))
	var amount := int(round(e.def.xp_reward * xp_scale * xp_multiplier))
	if amount <= 0:
		return
	var near: Array[Player] = []
	var expected := 1
	for n in get_tree().get_nodes_in_group(Player.GROUP):
		var p := n as Player
		if p != null and p.is_inside_tree() and p.global_position.distance_to(e.global_position) <= RANGE:
			near.append(p)
			expected = maxi(expected, p.progression.level)
	for p in near:
		# Step 70: Resolve catch-up against the highest level in range (the co-op party).
		var got := int(amount * Progression.resolve_multiplier(p.progression.level, expected))
		p.add_xp(got)
		granted += got
		resolve_bonus += got - amount
