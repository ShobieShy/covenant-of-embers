extends TestCase
## 0.12.0: the Town slice uses the painting lock in
## docs/specs/TOWN_GOLDEN_SLICE_0.12.0.md. World +X is east, -Z is north.


func test_painting_landmarks_match_the_spec() -> void:
	check(_near(_world(0.50, 0.80), Vector2(-6.4, 89.6)), "Main Gate")
	check(_near(_world(0.50, 0.55), Vector2(-6.4, 9.6)), "fountain")
	check(_near(_world(0.50, 0.22), Vector2(-6.4, -96.0)), "Association doors")
	check(_near(_world(0.82, 0.38), Vector2(96.0, -44.8)), "Old Oak")
	check(_near(_world(0.71, 0.66), Vector2(60.8, 44.8)), "East Gate")
	check(_near(_world(0.24, 0.53), Vector2(-89.6, 3.2)), "The Flagon")
	var gate := _world(0.50, 0.80)
	var fountain := _world(0.50, 0.55)
	check(absf(gate.y - fountain.y) > 60.0, "the gate sits outside the 60 m square")


func _world(paint_x: float, paint_y: float) -> Vector2:
	return Vector2((paint_x - 0.52) * 320.0, (paint_y - 0.52) * 320.0)


func _near(got: Vector2, want: Vector2) -> bool:
	return got.distance_to(want) < 1.0
