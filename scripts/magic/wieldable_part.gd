class_name WieldablePart
extends Resource
## A staff/wand part (BUILD_PLAN step 7; Magewar StaffPartItem, followed directly). Only
## read by WieldableInstance's final stats so far; rolls (step 16), assembly rules (step 17)
## and the station (step 25) come later.

enum PartType { HEAD, EXTERIOR, INTERIOR, HANDLE, CHARM }   ## Magewar order

@export var id := ""
@export var display_name := ""
@export var part_type: PartType = PartType.HEAD
@export var rarity := "basic"                 ## WieldableDef.RARITY_IDS (Rarity resource in step 15)
@export var element: ElementTable.Element = ElementTable.Element.ARCANE   ## ARCANE = Magewar NONE = no override
@export var damage_bonus := 0.0               ## flat, every part type counts (Magewar)
@export var fire_rate_modifier := 1.0         ## Exterior and Charm multiply the cooldown
@export var accuracy_bonus := 0.0             ## Head, Handle and Charm count
@export var handling_bonus := 0.0             ## swap speed (step 10/17)
@export_range(0, 3) var gem_slots := 1        ## Head only (step 16)

static func make(p_type: PartType, p_damage_bonus := 0.0, p_fire_rate := 1.0,
		p_accuracy := 0.0, p_element: ElementTable.Element = ElementTable.Element.ARCANE) -> WieldablePart:
	var p := WieldablePart.new()
	p.part_type = p_type
	p.damage_bonus = p_damage_bonus
	p.fire_rate_modifier = p_fire_rate
	p.accuracy_bonus = p_accuracy
	p.element = p_element
	return p
