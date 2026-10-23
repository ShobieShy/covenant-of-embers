class_name ElementDef
extends Resource
## One spell element's row in resources/magic/elements.tres (BUILD_PLAN step 6).
## Port of the archived C++ ElementInfo + one [[element]] of data/magic/elements.toml.

@export var id := ""                                  ## arcane | fire | water | earth | air | light | dark
@export var display_name := ""                        ## Magewar ELEMENT_NAMES
@export var color := Color.WHITE                      ## Magewar ELEMENT_COLORS (0..1 tint)
@export var strong_against := PackedStringArray()     ## element ids hit for ElementTable.strong
@export var weak_against := PackedStringArray()       ## element ids hit for ElementTable.weak
