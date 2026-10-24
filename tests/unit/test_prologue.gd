extends TestCase
## Step 64 done check: the prologue beats fire in order and end with the home unlocked.


func test_beats_in_order() -> void:
	var f := StoryFlags.new()
	var p := Prologue.new(f)
	var r := DialogueRunner.new(null, f)
	p.bind_dialogue(r)
	var titles := []
	p.beat_started.connect(func(_i: int, _id: String, t: String) -> void: titles.append(t))
	var ended := [false]
	p.finished.connect(func() -> void: ended[0] = true)
	p.begin()
	check(p.current()["id"] == "summoning", "starts at the summoning")
	p.on_reached("old_oak")
	p.advance()
	check(p.current()["id"] == "summoning", "later events do nothing")
	r.start("Crazy Joe")
	while r.active:
		r.advance()
	check(p.current()["id"] == "expulsion" and f.has("joe_met"), "Joe's dialogue -> expulsion")
	p.advance()
	check(f.has("joe_expelled"), "Joe expelled")
	check(not f.has("permit_given"), "no grant yet")
	p.advance()
	check(f.value("gold") == 50 and f.has("basic_clothes") and f.has("permit_given"), "50 gold, clothes, Old Oak")
	p.on_reached("old_oak")
	check(p.current()["id"] == "welcome_to_town", "must reach town first")
	p.on_reached("town_square")
	check(not f.has("home_unlocked"), "not home yet")
	p.on_reached("old_oak")
	check(ended[0] and p.done() and f.has("home_unlocked"), "ends with home unlocked")
	check(
		p.fired == PackedStringArray(["summoning", "expulsion", "grant", "welcome_to_town", "a_new_home"]),
		"order %s" % p.fired
	)
	check(
		titles.has("Prologue: The Summoning") and titles.has("Welcome to Town") and titles[-1] == "A New Home",
		"Magewar titles"
	)
	var again := Prologue.new(f)
	again.begin()
	check(again.current().is_empty(), "done prologue does not restart")


func test_feeds_quest_chain() -> void:
	var f := StoryFlags.new()
	var q := QuestLog.create(f)
	var p := Prologue.new(f)
	p.begin()
	p.on_talked("Crazy Joe")
	p.advance()
	p.advance()
	check(q.state("a_new_home") == "active", "grant starts the A New Home quest")
