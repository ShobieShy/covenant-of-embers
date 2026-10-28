class_name GameEvents
extends Node
## Game-wide event bus (BUILD_PLAN step 14), registered as the `EventBus` autoload.
## Systems that shouldn't know each other (loot drops step 22, XP step 27, HUD step 29,
## audio step 37, quests) listen here instead of wiring every enemy/player by hand:
##   enemy_killed(enemy, element)   once per death (Enemy announces it with `died`);
##   player_damaged(player, result) a hit that landed on a player (Player.hurt);
##   enemy_spawned(enemy)           the spawner placed (or respawned) an enemy;
##   wave_started / wave_cleared    the level's [[wave]] table (EnemySpawner);
##   waves_completed                the last wave was cleared.
## Emitters call `GameEvents.bus()`: the autoload when it exists (the game, the headless
## test runner), else one lazily made stand-in so scripts never depend on the tree.
##
## Magewar reference (enemy_base.gd _finalize_death, read-only): Magewar has no event bus;
## a death calls the reward service (XP/gold to every player within 80 m), the loot drop
## and the quest bridge directly from the enemy. Reinterpreted: the enemy only announces
## the kill; rewards/loot subscribe (steps 22/27), so the enemy stays system-agnostic.

signal enemy_killed(enemy: Enemy, element: ElementTable.Element)
signal player_damaged(player: Player, result: Damage.Result)
signal enemy_spawned(enemy: Enemy)
signal wave_started(index: int, wave_id: String)
signal wave_cleared(index: int, wave_id: String)
signal waves_completed
signal quest_item_collected(player: Player, item_id: String)  ## step 57
signal player_healed(player: Player, amount: float)  ## step 50: Light heal etc.
## 0.3.1 P7 (L6): a one-shot sound cue (GameAudio plays it; `at` INF = 2D).
signal sfx(key: String, at: Vector3)
signal crafting_completed(player: Player, item: WieldableInstance)  ## step 25 (Magewar station signal)

const AUTOLOAD := ^"/root/EventBus"

var kills := 0  ## enemy_killed emitted (all time; tests use deltas)
var player_hits := 0  ## player_damaged emitted

static var _fallback: GameEvents


## The bus: the EventBus autoload, else a stand-in (not in the tree; signals still work).
static func bus() -> GameEvents:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		var n := tree.root.get_node_or_null(AUTOLOAD) as GameEvents
		if n != null:
			return n
	if _fallback == null:
		_fallback = GameEvents.new()
	return _fallback


func announce_kill(enemy: Enemy, element: ElementTable.Element) -> void:
	kills += 1
	enemy_killed.emit(enemy, element)


func announce_player_damaged(player: Player, result: Damage.Result) -> void:
	player_hits += 1
	player_damaged.emit(player, result)


func _ready() -> void:
	Gamepad.install()  # step 77: default pad bindings on every action
