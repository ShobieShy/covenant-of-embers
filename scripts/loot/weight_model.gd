class_name WeightModel
extends RefCounted
## One weight model everywhere (BUILD_PLAN step 28; PLAN §31.4): weight = base x prod(modifiers).
## A modifier is {"mul": k} (constant) or {"attr": name, "per": k} -> 1 + k x context[name]
## (a live attribute: Vigil tier, player count, health %, luck ...); {"attr", "pow": k} ->
## k ^ context[name]. Weights are relative: probability = weight / sum. Never negative.

const TIERS := {"staple": 100.0, "common": 50.0, "uncommon": 12.0, "scarce": 3.0,
	"rare": 0.6, "precious": 0.12}   ## named weight tiers (§31.4), our own scale

static func named(tier_name: String) -> float:
	return TIERS.get(tier_name, 0.0)

static func modifier(mod: Dictionary, context: Dictionary) -> float:
	if mod.has("mul"):
		return float(mod["mul"])
	var v := float(context.get(mod.get("attr", ""), 0.0))
	if mod.has("per"):
		return 1.0 + float(mod["per"]) * v
	if mod.has("pow"):
		return pow(float(mod["pow"]), v)
	return 1.0

static func weight(base: float, mods: Array, context := {}) -> float:
	var w := base
	for m in mods:
		w *= modifier(m, context)
	return maxf(0.0, w)

static func probabilities(weights: PackedFloat64Array) -> PackedFloat64Array:
	var total := 0.0
	for w in weights:
		total += w
	var out := PackedFloat64Array()
	for w in weights:
		out.append(w / total if total > 0.0 else 0.0)
	return out
