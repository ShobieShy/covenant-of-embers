extends TestCase
## 0.8.6: one cooldown, the verb follows the element tree, downed refuses it,
## and a joiner's cast is applied by the host (no private roll).

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const DT := 1.0 / 60.0

var _port := 27100 + randi_range(0, 200) * 2


func test_highest_tree_and_tie_break() -> void:
	var s := Skills.new()
	check(ActionSkill.verb_for(s) == "chain", "nothing spent is Arcane's chain")
	_ranks(s, "fire", 2)
	_ranks(s, "arcane", 1)
	check(ActionSkill.verb_for(s) == "stagger", "fire ahead of arcane staggers")
	_ranks(s, "arcane", 1)
	check(ActionSkill.verb_for(s) == "chain", "a tie breaks toward Arcane")
	_ranks(s, "light", 3)
	check(ActionSkill.verb_for(s) == "summon", "light ahead summons")
	_ranks(s, "dark", 4)
	check(ActionSkill.verb_for(s) == "convert", "dark ahead converts")
	var earth := Skills.new()
	_ranks(earth, "earth", 2)
	_ranks(earth, "water", 2)
	check(ActionSkill.verb_for(earth) == "chain", "water beats earth on a tie, and water chains")


func test_cooldown_downed_and_each_verb() -> void:
	var w := _world()
	var p := _player(w)
	var far := Enemy.create(EnemyTable.load_default().find("earth_training_dummy"))
	var near := Enemy.create(EnemyTable.load_default().find("earth_training_dummy"))
	w.add_child(far)
	w.add_child(near)
	near.global_position = p.global_position + Vector3(0, 0, -3)
	far.global_position = p.global_position + Vector3(0, 0, -6)
	var before_near := near.global_position
	var before_far := far.global_position
	_press(p)
	check(p.action_skill.casts == 1 and p.action_skill.last_verb == "chain", "default verb chains")
	check(near.hits >= 1 and far.hits >= 1, "chain hits the nearest and jumps")
	check(near.global_position == before_near and far.global_position == before_far, "chain does not shove")
	var refused := p.action_skill.refused_cooldown
	_press(p)
	check(
		p.action_skill.casts == 1 and p.action_skill.refused_cooldown == refused + 1, "cooldown blocks a second press"
	)
	p.action_skill.tick(p, PlayerInput.new(), ActionSkill.COOLDOWN)
	p.downed = true
	_press(p)
	check(p.action_skill.casts == 1 and p.action_skill.refused_downed == 1, "downed refuses it")
	p.downed = false
	_ranks(p.skills, "earth", 3)
	_press(p)
	check(p.action_skill.last_verb == "stagger" and near.stagger_left > 0.0, "earth staggers")
	check(near.global_position == before_near, "stagger does not shove")
	p.action_skill.tick(p, PlayerInput.new(), ActionSkill.COOLDOWN)
	var gnawer := Enemy.create(EnemyTable.load_default().find("gnawer"))
	w.add_child(gnawer)
	gnawer.global_position = p.global_position + Vector3(2, 0, 0)
	var gnawer_at := gnawer.global_position
	_ranks(p.skills, "dark", 4)
	_press(p)
	check(p.action_skill.last_verb == "convert" and gnawer.is_ally(), "dark converts the nearest gnawer")
	check(not MagicEffects.force_convert, "the forced convert does not leak")
	check(gnawer.global_position == gnawer_at, "convert does not shove")
	p.action_skill.tick(p, PlayerInput.new(), ActionSkill.COOLDOWN)
	_ranks(p.skills, "light", 5)
	_press(p)
	check(p.action_skill.last_verb == "summon" and LightSummon.of(p) != null, "light summons")
	check(near.global_position == before_near and gnawer.global_position == gnawer_at, "summon does not shove")
	var hud := Hud.new()
	w.add_child(hud)
	hud.player = p
	hud.refresh(DT)
	check(hud.skill_cd.text.begins_with("Skill"), "cooldown readout (%s)" % hud.skill_cd.text)
	w.free()


func test_joiner_cast_is_applied_by_the_host() -> void:
	_port += 1
	var w := Node3D.new()
	runner_tree.root.add_child(w)
	var h := NetSession.new()
	var c := NetSession.new()
	w.add_child(h)
	w.add_child(c)
	check(h.host(NetTransport.make("enet"), _port, {"name": "H"}), "host")
	check(c.join(NetTransport.make("enet"), "127.0.0.1:%d" % _port, {"name": "C"}), "join")
	check(await _wait(func(): return h.roster.size() == 2 and c.state == NetSession.State.LOBBY), "lobby")
	h.set_ready(true)
	c.set_ready(true)
	await _wait(func(): return h.all_ready())
	check(h.start_game(), "start")
	check(await _wait(func(): return c.state == NetSession.State.IN_GAME), "client in game")
	var table := EnemyTable.load_default()
	var hen := Node3D.new()
	var cen := Node3D.new()
	w.add_child(hen)
	w.add_child(cen)
	var dummy := Enemy.create(table.find("earth_training_dummy"))
	hen.add_child(dummy)
	dummy.global_position = Vector3(4, 0, 0)
	var hp := FakeCaster.new()
	var cp: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	cp.input_enabled = false
	w.add_child(hp)
	w.add_child(cp)
	cp.spawn(Vector3(4, 0, 2), 0.0)
	_ranks(cp.skills, "earth", 2)
	var hw := CoopWorld.new()
	var cw := CoopWorld.new()
	hw.auto_tick = false
	cw.auto_tick = false
	w.add_child(hw)
	w.add_child(cw)
	hw.setup(h, hp, hen, table)
	cw.setup(c, cp, cen, table)
	_press(cp)
	check(cp.action_skill.casts == 1 and cp.action_skill.last_verb == "stagger", "the joiner chose stagger")
	check(cw.asks_sent == 1, "the joiner forwards the cast")
	check(await _wait(func(): return hw.asks_applied >= 1 and dummy.stagger_left > 0.0), "the host staggers")
	for i in 8:
		hw.tick(DT)
		cw.tick(DT)
		await runner_tree.process_frame
	var puppet: Enemy = cw.puppets.values()[0] if cw.puppets.size() > 0 else null
	check(puppet != null and (puppet.net_fx & Enemy.FX_STAGGER) != 0, "the joiner sees the stagger")
	w.free()


func _ranks(s: Skills, el: String, n: int) -> void:
	var sid := String(SkillTree.element_tree(el).order[0])
	for _i in n:
		s.el_spend(el, sid, 40)


func _world() -> Node3D:
	var w := Node3D.new()
	w.position = Vector3(8000, 0, 8000)
	runner_tree.root.add_child(w)
	return w


func _player(w: Node3D) -> Player:
	var p: Player = (load(PLAYER_SCENE) as PackedScene).instantiate()
	p.input_enabled = false
	w.add_child(p)
	p.spawn(w.global_position, 0.0)
	return p


func _press(p: Player) -> void:
	p.tick(PlayerInput.hold([], ["action_skill"]), DT)


func _wait(cond: Callable, frames := 300) -> bool:
	for _i in frames:
		if cond.call():
			return true
		await runner_tree.process_frame
	return bool(cond.call())


class FakeCaster:
	extends Node3D

	var downed := false

	func alive() -> bool:
		return true

	func invulnerable() -> bool:
		return false
