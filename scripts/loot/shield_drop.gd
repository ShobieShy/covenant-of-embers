class_name ShieldDrop
extends Resource
## A dropped shield. Equipping it replaces Health's capacity, regen delay, and effect.
## Taking it off restores the tuning numbers. Not a second bar.

@export var capacity := 40.0
@export var delay := 2.0
@export var effect := "ward"  ## ward, spike, calm
@export var display_name := "Shield"


static func make(cap: float, p_delay: float, p_effect: String) -> ShieldDrop:
	var s := ShieldDrop.new()
	s.capacity = cap
	s.delay = p_delay
	s.effect = p_effect
	s.display_name = "%s Shield" % p_effect.capitalize()
	return s
