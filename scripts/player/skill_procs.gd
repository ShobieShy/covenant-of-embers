class_name SkillProcs
extends RefCounted
## Kill-driven skill effects (BUILD_PLAN step 72), read from Skills.totals() at each kill:
##  - kill_mana   restore that much mana;
##  - kill_health heal that much;
##  - kill_frenzy (capstone) +that much spell damage for FRENZY_SECONDS after a kill.
## Like Consecrations, the frenzy bonus is pushed into every caster each tick (after
## Consecrations.tick, so both stack on conditional_bonus).

const FRENZY_SECONDS := 6.0

var frenzy_left := 0.0
var procs := 0
var _player: WeakRef
var _bound := false


func bind(p: Player) -> void:
	_player = weakref(p)
	if not _bound:
		_bound = true
		GameEvents.bus().enemy_killed.connect(_on_killed)


func on_kill(p: Player, element := -1) -> void:
	if p == null or not p.alive():
		return
	var t := p.skills.totals()
	var el := ElementSkillMods.of(p.skills, element)  # step 145: the killing element's tree
	for k in ["kill_mana", "kill_health"]:
		if el.has(k):
			t[k] = float(t.get(k, 0.0)) + float(el[k])
	var any := false
	if float(t.get("kill_mana", 0.0)) > 0.0 and p.mana != null:
		p.mana.restore(float(t["kill_mana"]))
		any = true
	if float(t.get("kill_health", 0.0)) > 0.0 and p.health != null:
		p.health.heal(float(t["kill_health"]))
		any = true
	if float(t.get("kill_frenzy", 0.0)) > 0.0:
		frenzy_left = FRENZY_SECONDS
		any = true
	if any:
		procs += 1


func tick(p: Player, dt: float) -> void:
	var bonus := 0.0
	if frenzy_left > 0.0:
		frenzy_left = maxf(0.0, frenzy_left - dt)
		bonus = p.skills.total("kill_frenzy")
	if bonus > 0.0:
		for c in p.loadout.casters:
			c.conditional_bonus += bonus


func _on_killed(_enemy: Enemy, element: ElementTable.Element) -> void:
	var p: Player = _player.get_ref() if _player else null
	on_kill(p, element)
