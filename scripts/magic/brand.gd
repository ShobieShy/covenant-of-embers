class_name Brand
extends Resource
## A staff/wand brand (Phase U, docs/BRANDS_PLAN.md, step 135). One per element except
## Arcane (unbranded). The brand is derived from the Head part's own element, never stored
## (old saves and Ember Marks gain brands automatically). `fire_mode` picks the Caster
## FireMode (step 136+); `params` holds its tunables (BalancePatch can override them, step 143).
## Wands use the same mode scaled toward the unbranded baseline by `wand_scale` (Q46).

enum FireMode { SEMI, HEAT, CHARGE, EXPLOSIVE, AUTO_SPINUP, SELECT_BURST, PRECISION }

const FIRE_MODE_NAMES: PackedStringArray = [
	"Semi", "Heat", "Charge", "Explosive", "Spin-up", "Select fire", "Precision"
]

@export var id := ""  ## lower_snake_case = the .tres stem
@export var display_name := ""  ## full maker name ("Pyrowning Arms")
@export var short_name := ""  ## in item names ("Rare Pyrowning Fire Staff")
@export var element: ElementTable.Element = ElementTable.Element.FIRE
@export var fire_mode: FireMode = FireMode.SEMI
@export var color := Color.WHITE
@export var tagline := ""  ## our own flavour line (Rare+ cards)
@export var mode_line := ""  ## one-line fire-mode summary for cards
@export var logo_path := ""  ## res:// 16 px logo (step 140), "" = none
@export var wand_scale := 0.6  ## wands: effects lerp this far from neutral toward the staff value
@export var params := {}


## A tunable, or `default` when the brand doesn't set it.
func p(key: String, default := 0.0) -> float:
	return float(params.get(key, default))


## `key` scaled for a wand: neutral + (value - neutral) x wand_scale. Staff = the value.
func scaled(key: String, neutral: float, is_wand: bool, default := NAN) -> float:
	var v := p(key, neutral if is_nan(default) else default)
	return neutral + (v - neutral) * wand_scale if is_wand else v


func fire_mode_name() -> String:
	return FIRE_MODE_NAMES[fire_mode]


func logo() -> Texture2D:
	return load(logo_path) as Texture2D if not logo_path.is_empty() and ResourceLoader.exists(logo_path) else null
