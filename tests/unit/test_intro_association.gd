extends TestCase
## Step 111 done check: beats 1-4 in the Association - the summoning cinematic, the
## appraisal creator setting the identity, Joe's explanation + expulsion, and the Clerk's
## grant (50 gold, permit) unlocking the front door.

const FILE := "user://test_intro_assoc.json"


func _game() -> Node:
	GameFlow.dry_run = true
	GameFlow.save_path = FILE
	GameFlow.level_id = "mage_association"
	GameFlow.load_save = false
	GameFlow.intro_mode = GameFlow.INTRO_PLAY
	var g: Node = (load(GameFlow.GAME) as PackedScene).instantiate()
	runner_tree.root.add_child(g)
	return g


func _finish_dialogue(g: Node) -> void:
	var d: DialogueRunner = g.dialogue
	for i in 40:
		if not d.active:
			return
		if not d.advance() and d.awaiting_choice():
			d.choose(0)


func test_beats_one_to_four() -> void:
	var g := _game()
	var p := g.get_node("Player") as Player
	var it: IntroDirector = g.intro
	check(p.inventory.gold == 0, "no gold before the grant")
	check(it.cast.has("Elder") and it.cast.has("Clerk"), "Elder + Clerk")
	var others := it.cast.keys().filter(func(k: String) -> bool: return k.begins_with("Summoned "))
	check(others.size() == 3 and not others.has("Summoned " + Archetype.label(p.archetype)), "3 other Summoned")
	check(Cinematic.playing != null and it.cinematic != null, "summoning cinematic")
	var town: LevelGate = null
	for gt in g.gates:
		if gt.target == "town_square":
			town = gt
	check(town != null and not town.use(), "front door locked before the permit")
	it.cinematic.skip()
	check(it.current() == "appraisal" and it.creator != null, "creator opens after the summoning")
	CharacterCreator.of(it.creator).set_identity({"archetype": "buff", "name": "Tess"})
	CharacterCreator.of(it.creator).confirm()
	check(p.archetype == "buff" and p.character_name == "Tess", "identity applied from the creator")
	check(it.current() == "expulsion" and g.dialogue.active and g.dialogue.speaker() == "Crazy Joe", "Joe explains")
	_finish_dialogue(g)
	check(it.cinematic != null and Cinematic.playing == it.cinematic, "expulsion cinematic")
	it.cinematic.skip()
	check(g.story_flags.has("joe_expelled") and not it.joe().visible, "Joe expelled")
	check(it.current() == "grant", "grant beat")
	check(g.talk_to("Clerk") and g.dialogue.entry["id"] == "clerk_grant", "Clerk gives the grant")
	_finish_dialogue(g)
	check(p.inventory.gold == IntroDirector.GRANT_GOLD and g.story_flags.has("permit_given"), "50 gold + permit")
	check(it.current() == "welcome", "on to the town")
	check(not town.locked(), "front door opens after the permit")
	g.free()
	GameFlow.dry_run = false
	GameFlow.level_id = "midden"
	GameFlow.intro_mode = ""
	GameFlow.save_path = SaveGame.PATH
	GameFlow.select_slot(1)


func test_menu_creator() -> void:
	var c := CharacterCreator.new(true, {"archetype": "gal", "name": "Ana"})
	check(c.identity()["archetype"] == "gal" and c.identity()["name"] == "Ana", "prefill")
	var got := []
	c.confirmed.connect(func(i: Dictionary): got.append(i))
	c.confirm()
	check(got.size() == 1, "confirm emits")
	c.free()
