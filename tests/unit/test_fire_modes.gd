extends TestCase
## Step 136 (Brands B2): Caster runs on a FireMode. An unbranded wieldable (no Head or an
## Arcane Head) must cast exactly as the pre-brand Caster did: OldCaster below is a verbatim
## copy of that tick(); random press/hold sequences, hold_to_repeat on/off, a draining mana
## pool and the gear bonuses must give identical casts, refusals, cooldowns and bolts.
## Also: the reload (R) action exists and is rebindable; the potion moved to H.

const DT := 1.0 / 60.0
const BASES := ["apprentice_fire_staff", "swift_wind_wand", "earthward_battlestaff"]


## The Caster.tick of 0.1.2 (step 7/8/19/36/108), kept for the parity check.
class OldCaster:
	extends RefCounted
	var wieldable: WieldableInstance
	var hold_to_repeat := false
	var mana_spender := Callable()
	var cooldown_left := 0.0
	var casts := 0
	var blocked := 0
	var mana_refused := 0
	var damage_bonus := 0.0
	var conditional_bonus := 0.0
	var next_cast_bonus := 0.0

	func tick(pressed: bool, held: bool, dt: float, aim: Caster.Aim, bolts: SpellBolts) -> bool:
		cooldown_left = maxf(0.0, cooldown_left - dt)
		var want := pressed or (hold_to_repeat and held)
		if not want or wieldable == null:
			return false
		if cooldown_left > 1e-9:
			if pressed:
				blocked += 1
			return false
		if mana_spender.is_valid() and not bool(mana_spender.call(wieldable.mana_cost())):
			if pressed:
				blocked += 1
				mana_refused += 1
			return false
		cooldown_left = wieldable.cooldown()
		if bolts != null and aim != null:
			var s := SpellBolts.Spawn.new()
			s.origin = aim.origin
			s.direction = aim.direction
			s.speed = wieldable.projectile_speed()
			s.range_m = wieldable.range_m()
			s.element = wieldable.element()
			s.damage = wieldable.damage() + damage_bonus + conditional_bonus + next_cast_bonus
			next_cast_bonus = 0.0
			if s.element == ElementTable.Element.LIGHT:
				s.damage *= MagicEffects.LIGHT_DAMAGE_SCALE
			s.dark_bonus = wieldable.dark_chance_bonus()
			bolts.spawn(s)
		casts += 1
		return true


class Pool:
	extends RefCounted
	var mana := 60.0

	func spend(c: float) -> bool:
		if mana + 1e-9 < c:
			return false
		mana -= c
		return true


func _unbranded(base: String, arcane_head: bool) -> WieldableInstance:
	var w := WieldableInstance.load_base(base)
	if arcane_head:
		var parts: Array[WieldablePart] = [PartRoller.from_seed(7, WieldablePart.PartType.HEAD, "rare", 0)]
		var ids := (
			["basic_exterior", "basic_interior", "basic_handle"]
			if w.type() == WieldableDef.Type.STAFF
			else ["basic_exterior"]
		)
		for id in ids:
			parts.append(WieldablePart.load_part(id))
		w = Assembly.assemble(w.def, parts)
	return w


func test_semi_parity() -> void:
	var aim := Caster.Aim.make(Vector3(1, 2, 3), Vector3(0, 0, -1))
	var runs := 0
	for base in BASES:
		for arcane in [false, true]:
			for repeat in [false, true]:
				for seed in 4:
					var w := _unbranded(base, arcane)
					check(w.brand() == null, "%s unbranded" % base)
					var rng := RandomNumberGenerator.new()
					rng.seed = seed * 31 + 5
					var a := OldCaster.new()
					var b := Caster.new(w)
					a.wieldable = w
					var pa := Pool.new()
					var pb := Pool.new()
					a.mana_spender = pa.spend
					b.mana_spender = pb.spend
					a.hold_to_repeat = repeat
					b.hold_to_repeat = repeat
					a.damage_bonus = 2.5
					b.damage_bonus = 2.5
					var ba := SpellBolts.new()
					var bb := SpellBolts.new()
					var held := false
					var same := true
					for t in 900:
						var pressed := false
						if rng.randf() < 0.08:
							held = not held
							pressed = held
						if t % 200 == 0:
							a.next_cast_bonus = 4.0
							b.next_cast_bonus = 4.0
						if t % 60 == 0:
							pa.mana += 3.0
							pb.mana += 3.0
						var ra := a.tick(pressed, held, DT, aim, ba)
						var rb := b.tick(pressed, held, DT, aim, bb)
						if ra != rb or a.cooldown_left != b.cooldown_left:
							same = false
							break
					same = same and a.casts == b.casts and a.blocked == b.blocked
					same = same and a.mana_refused == b.mana_refused and pa.mana == pb.mana
					same = same and ba.spawned == bb.spawned
					for i in mini(ba.live.size(), bb.live.size()):
						var x := ba.live[i].spawn
						var y := bb.live[i].spawn
						same = (
							same
							and x.damage == y.damage
							and x.element == y.element
							and x.speed == y.speed
							and x.range_m == y.range_m
							and x.dark_bonus == y.dark_bonus
							and x.origin == y.origin
						)
					check(same, "%s arcane=%s repeat=%s seed %d identical" % [base, arcane, repeat, seed])
					check(b.wants_aim(true, true) and b.fire_mode().id() == &"semi", "semi mode")
					check(not b.reload(aim, bb), "R does nothing unbranded")
					ba.free()
					bb.free()
					runs += 1
	check(runs == 48, "48 parity runs")


func test_reload_binding() -> void:
	check(InputMap.has_action(&"reload"), "reload action")
	check(PlayerInput.ACTIONS.has(&"reload") and Settings.rebindable().has(&"reload"), "rebindable")
	var keys := {}
	for a in [&"reload", &"use_potion"]:
		for e in InputMap.action_get_events(a):
			if e is InputEventKey:
				keys[a] = (e as InputEventKey).physical_keycode
	check(keys.get(&"reload") == KEY_R and keys.get(&"use_potion") == KEY_H, "R vents, H drinks: %s" % keys)
	check(Gamepad.DEFAULTS.has(&"reload"), "pad default")


func test_bloom_mult() -> void:
	var s := Spread.new()
	s.on_cast(0.5)
	check(is_equal_approx(s.bloom, s.bloom_per_cast_deg * 0.5), "bloom x mult")
	s.on_cast()
	check(is_equal_approx(s.bloom, s.bloom_per_cast_deg * 1.5), "default x1")
