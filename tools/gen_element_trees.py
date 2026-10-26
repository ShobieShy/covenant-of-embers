#!/usr/bin/env python3
"""Writes data/skills/<element>.toml, the 7 element trees (Phase V step 144,
docs/ELEMENT_TREES_PLAN.md section 4). Each tree: 20 ranked skills on tiers 0-4
(2 Attunement + 2 Craft per tier) + 1 exclusive capstone on tier 5. Names follow the plan;
effects use the ElementSkillMods vocabulary (scripts/player/element_skill_mods.gd), with
placeholder numbers per rank. `--check` fails when the files are out of date."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# (tier, branch, id, name, ranks, effects-per-rank, desc)
A, C = "attunement", "craft"
T = {
 "arcane": ("Pure Focus", [
  (0,A,"clean_lines","Clean Lines",5,{"damage_pct":3},"+3% Arcane damage per rank"),
  (0,A,"measured_breath","Measured Breath",3,{"cost_pct":-4},"Arcane casts cost -4% mana per rank"),
  (0,C,"steady_hand","Steady Hand",3,{"accuracy":4},"+4 accuracy per rank"),
  (0,C,"trigger_discipline","Trigger Discipline",2,{"cooldown_pct":-4},"Cooldown -4% per rank"),
  (1,A,"resonant_gem","Resonant Gem",3,{"status_seconds":0.1},"Status from Arcane bolts lasts +0.1 s per rank"),
  (1,A,"thin_veil","Thin Veil",2,{"vs_status_pct":3},"+3% damage to enemies under any of your statuses"),
  (1,C,"quick_study","Quick Study",2,{"accuracy":2},"+2 accuracy per rank"),
  (1,C,"bloom_control","Bloom Control",3,{"bloom_pct":-10},"Spread bloom per cast -10% per rank"),
  (2,A,"echo","Echo",3,{"echo":1},"Every 8th Arcane bolt fires a free copy at 40% (+1 copy chance per rank)"),
  (2,A,"mana_lens","Mana Lens",3,{"damage_pct":2},"+2% Arcane damage per rank"),
  (2,C,"gem_socket_sense","Gem Socket Sense",2,{"damage_pct":3},"+3% Arcane damage per rank"),
  (2,C,"long_sight","Long Sight",2,{"range_pct":8},"Range +8% per rank"),
  (3,A,"overflow","Overflow",2,{"kill_mana":3},"Arcane kills refund 3 mana per rank"),
  (3,A,"prism","Prism",1,{"mark_seconds":3},"Arcane hits mark the target (Hex) for 3 s"),
  (3,C,"focused_fire","Focused Fire",3,{"damage_pct":2},"+2% Arcane damage per rank"),
  (3,C,"weak_point_study","Weak Point Study",2,{"weakpoint_pct":8},"Weak-point damage +8% per rank"),
  (4,A,"attuned_pool","Attuned Pool",2,{"kill_mana":2},"Arcane kills refund 2 mana per rank"),
  (4,A,"refraction","Refraction",2,{"mark_pct":4},"+4% damage to marked enemies per rank"),
  (4,C,"clockwork","Clockwork",2,{"cooldown_pct":-3},"Cooldown -3% per rank"),
  (4,C,"gem_harmony","Gem Harmony",1,{"damage_pct":4},"+4% Arcane damage"),
  (5,A,"convergence","Convergence",1,{"capstone":1},"Every 5th Arcane hit on one target triggers the statuses of every element tree you have points in"),
 ]),
 "fire": ("Kindling", [
  (0,A,"hot_coals","Hot Coals",5,{"damage_pct":3},"+3% Fire damage per rank"),
  (0,A,"long_burn","Long Burn",3,{"status_seconds":0.5},"Burn lasts +0.5 s per rank"),
  (0,C,"heat_sink","Heat Sink",3,{"heat_pct":-6},"Pyrowning heat per shot -6% per rank"),
  (0,C,"cool_hands","Cool Hands",2,{"heat_decay_pct":10},"Heat decay +10% per rank"),
  (1,A,"searing","Searing",3,{"status_pct":10},"Burn deals +10% of the hit per rank (max 60%)"),
  (1,A,"tinder","Tinder",2,{"damage_pct":2},"+2% Fire damage per rank"),
  (1,C,"quick_vent","Quick Vent",3,{"vent_pct":-10},"Vent time -10% per rank"),
  (1,C,"efficient_crystal","Efficient Crystal",2,{"crystal_cost_pct":-5},"Crystal reload costs -5% of max mana per rank (floor 35%)"),
  (2,A,"flashpoint","Flashpoint",3,{"vs_status_pct":5},"+5% damage to burning enemies per rank"),
  (2,A,"spread_fire","Spread Fire",2,{"status_seconds":0.25},"Burn lasts +0.25 s per rank"),
  (2,C,"red_line","Red Line",2,{"hot_damage_pct":6},"While heat >= 70%: +6% Fire damage per rank"),
  (2,C,"short_fuse","Short Fuse",2,{"vent_pct":-5},"Overheat lockout -5% per rank"),
  (3,A,"wildfire_kin","Wildfire Kin",2,{"status_damage_pct":5},"Burn damage +5% per rank"),
  (3,A,"ember_ward","Ember Ward",2,{"resist_pct":2},"-2% damage taken with a Fire staff out per rank"),
  (3,C,"hot_swap","Hot Swap",2,{"heat_pct":-3},"Heat per shot -3% per rank"),
  (3,C,"overclock","Overclock",3,{"cooldown_pct":-3},"Cooldown -3% per rank"),
  (4,A,"inferno_heart","Inferno Heart",2,{"status_damage_pct":10},"Burn damage +10% per rank"),
  (4,A,"kindred_flame","Kindred Flame",1,{"status_seconds":0.5},"Burn lasts +0.5 s"),
  (4,C,"fresh_crystal","Fresh Crystal",2,{"heat_pct":-4},"Heat per shot -4% per rank"),
  (4,C,"thermal_bank","Thermal Bank",1,{"crystal_cost_pct":-5},"Crystal reload costs -5% of max mana"),
  (5,A,"backdraft","Backdraft",1,{"capstone":1},"Venting at >= 80% heat releases a 4 m fire burst for 120% of one shot and resets burns"),
 ]),
 "water": ("Tidecaller", [
  (0,A,"cold_current","Cold Current",5,{"damage_pct":3},"+3% Water damage per rank"),
  (0,A,"undertow","Undertow",3,{"status_seconds":0.4},"Slow lasts +0.4 s per rank"),
  (0,C,"patient_draw","Patient Draw",3,{"charge_pct":-6},"Sigil charge time -6% per rank"),
  (0,C,"steady_pour","Steady Pour",2,{"charge_pct":-3},"Sigil charge time -3% per rank"),
  (1,A,"heavy_water","Heavy Water",3,{"status_pct":4},"Slow factor -0.04 per rank (floor 0.45)"),
  (1,A,"riptide","Riptide",3,{"vs_status_pct":6},"+6% damage to slowed enemies per rank"),
  (1,C,"overflowing_charge","Overflowing Charge",2,{"chain_jumps":1},"A full charge chains to +1 target per rank"),
  (1,C,"pressure","Pressure",2,{"damage_pct":2},"+2% Water damage per rank"),
  (2,A,"drench","Drench",2,{"status_seconds":0.3},"Slow lasts +0.3 s per rank"),
  (2,A,"calm_pool","Calm Pool",3,{"cost_pct":-3},"Water casts cost -3% mana per rank"),
  (2,C,"brimming","Brimming",2,{"charge_pct":-3},"Charge time -3% per rank"),
  (2,C,"ripple","Ripple",2,{"chain_range":1},"Chain range +1 m per rank"),
  (3,A,"soak","Soak",2,{"mark_seconds":2},"Water hits apply Soaked for 2 s per rank"),
  (3,A,"deep_cold","Deep Cold",2,{"resist_pct":2},"-2% damage taken with a Water staff out per rank"),
  (3,C,"tide_turn","Tide Turn",2,{"mark_pct":3},"+3% damage to Soaked enemies per rank"),
  (3,C,"wave_crest","Wave Crest",2,{"damage_pct":3},"+3% Water damage per rank"),
  (4,A,"saturation","Saturation",2,{"mark_seconds":1},"Soaked lasts +1 s per rank"),
  (4,A,"still_water","Still Water",1,{"damage_pct":4},"+4% Water damage"),
  (4,C,"riverbed","Riverbed",2,{"chain_range":1},"Chain range +1 m per rank"),
  (4,C,"hydraulic","Hydraulic",2,{"kill_mana":2},"Water kills refund 2 mana per rank"),
  (5,A,"tidal_hold","Tidal Hold",1,{"capstone":1},"A full Sigil charge freezes its first target for 1.2 s (bosses are slowed x0.4 instead)"),
 ]),
 "earth": ("Bedrock", [
  (0,A,"stoneskin","Stoneskin",5,{"damage_pct":3},"+3% Earth damage per rank"),
  (0,A,"bulk","Bulk",3,{"resist_pct":2},"-2% damage taken with an Earth staff out per rank"),
  (0,C,"wide_blast","Wide Blast",3,{"splash_pct":8},"Splash radius +8% per rank"),
  (0,C,"heavy_shot","Heavy Shot",2,{"speed_pct":10},"Boulder speed +10% per rank"),
  (1,A,"quake","Quake",3,{"status_seconds":0.1},"Stagger +0.1 s per rank"),
  (1,A,"crumble","Crumble",3,{"vs_status_pct":6},"+6% damage to staggered enemies per rank"),
  (1,C,"rubble","Rubble",2,{"splash_pct":4},"Splash radius +4% per rank"),
  (1,C,"packed_load","Packed Load",2,{"splash_damage_pct":10},"Blast damage +10% per rank"),
  (2,A,"grounded","Grounded",2,{"resist_pct":2},"-2% damage taken with an Earth staff out per rank"),
  (2,A,"bedrock_pulse","Bedrock Pulse",2,{"status_seconds":0.05},"Stagger +0.05 s per rank"),
  (2,C,"aftershock","Aftershock",2,{"splash_damage_pct":5},"Blast damage +5% per rank"),
  (2,C,"shrapnel","Shrapnel",3,{"splash_damage_pct":4},"Blast damage +4% per rank"),
  (3,A,"tremor","Tremor",2,{"vs_mark_status_pct":50},"Staggering a Soaked enemy: stagger +50% per rank"),
  (3,A,"stone_will","Stone Will",2,{"resist_pct":2},"-2% damage taken with an Earth staff out per rank"),
  (3,C,"cluster","Cluster",2,{"splash_pct":3},"Splash radius +3% per rank"),
  (3,C,"seismic_charge","Seismic Charge",2,{"damage_pct":4},"+4% Earth damage per rank"),
  (4,A,"landslide","Landslide",2,{"status_seconds":0.05},"Stagger +0.05 s per rank"),
  (4,A,"mountain","Mountain",1,{"resist_pct":3},"-3% damage taken with an Earth staff out"),
  (4,C,"detonator","Detonator",2,{"splash_damage_pct":5},"Blast damage +5% per rank"),
  (4,C,"bigger_rocks","Bigger Rocks",2,{"splash_pct":5},"Splash radius +5% per rank"),
  (5,A,"fault_line","Fault Line",1,{"capstone":1},"Every 4th boulder splits into 3 on impact (each 40%), each able to stagger"),
 ]),
 "air": ("Gale", [
  (0,A,"tailwind","Tailwind",5,{"damage_pct":3},"+3% Air damage per rank"),
  (0,A,"light_feet","Light Feet",3,{"move_pct":2},"+2% move speed with an Air staff out per rank"),
  (0,C,"spool","Spool",3,{"spin_pct":-8},"Spin-up time -8% per rank"),
  (0,C,"momentum","Momentum",2,{"spin_pct":-4},"Spin-up time -4% per rank"),
  (1,A,"long_arc","Long Arc",3,{"chain_range":1},"Chain range +1 m per rank"),
  (1,A,"gust","Gust",2,{"status_pct":5},"Chain hits +5% per rank"),
  (1,C,"keep_spinning","Keep Spinning",3,{"spin_pct":-3},"Spin-up time -3% per rank"),
  (1,C,"whirl_guard","Whirl Guard",2,{"resist_pct":2},"-2% damage taken with an Air staff out per rank"),
  (2,A,"forked","Forked",2,{"chain_jumps":1},"The chain jumps to +1 enemy per rank"),
  (2,A,"conductive","Conductive",2,{"vs_mark_status_pct":25},"Chains on Soaked enemies +25% per rank"),
  (2,C,"static","Static",3,{"damage_pct":2},"+2% Air damage per rank"),
  (2,C,"overspin","Overspin",2,{"cooldown_pct":-3},"Cooldown -3% per rank"),
  (3,A,"updraft","Updraft",2,{"status_pct":3},"Chain hits +3% per rank"),
  (3,A,"slipstream","Slipstream",2,{"move_pct":2},"+2% move speed with an Air staff out per rank"),
  (3,C,"feathered","Feathered",2,{"bloom_pct":-15},"Spread bloom -15% per rank"),
  (3,C,"cyclic","Cyclic",2,{"kill_mana":2},"Air kills refund 2 mana per rank"),
  (4,A,"storm_eye","Storm Eye",2,{"status_pct":4},"Chain hits +4% per rank"),
  (4,A,"jetstream","Jetstream",1,{"move_pct":3},"+3% move speed with an Air staff out"),
  (4,C,"gyro","Gyro",2,{"spin_pct":-3},"Spin-up time -3% per rank"),
  (4,C,"thunderhead","Thunderhead",2,{"damage_pct":3},"+3% Air damage per rank"),
  (5,A,"cyclone","Cyclone",1,{"capstone":1},"At full spin for 2 s, bolts chain to every enemy within 6 m (35% each), 6 s cooldown"),
 ]),
 "light": ("Dawnward", [
  (0,A,"bright_hands","Bright Hands",5,{"heal_pct":5},"Heals +5% per rank"),
  (0,A,"clear_sight","Clear Sight",3,{"damage_pct":3},"+3% Light damage per rank (the 0.9x rule stays)"),
  (0,C,"choir","Choir",3,{"ramp_pct":15},"Burst accuracy ramp +15% per rank"),
  (0,C,"quick_toggle","Quick Toggle",2,{"accuracy":2},"+2 accuracy per rank"),
  (1,A,"lasting_glow","Lasting Glow",3,{"status_seconds":5},"The Light summon lasts +5 s per rank"),
  (1,A,"mend_bond","Mend Bond",3,{"heal_pct":4},"Heals +4% per rank"),
  (1,C,"halo_step","Halo Step",2,{"move_pct":3},"+3% move speed with a Light staff out per rank"),
  (1,C,"tight_burst","Tight Burst",2,{"bloom_pct":-10},"Burst spread -10% per rank"),
  (2,A,"sanctuary","Sanctuary",2,{"heal_pct":5},"Heals +5% per rank"),
  (2,A,"radiance","Radiance",2,{"mark_seconds":1.5},"Light hits weaken (Hex mark) for 1.5 s per rank"),
  (2,C,"ramp_memory","Ramp Memory",2,{"ramp_pct":10},"Accuracy ramp +10% per rank"),
  (2,C,"fourth_note","Fourth Note",2,{"damage_pct":3},"+3% Light damage per rank"),
  (3,A,"beacon","Beacon",2,{"status_seconds":3},"The Light summon lasts +3 s per rank"),
  (3,A,"gentle","Gentle",2,{"heal_pct":4},"Heals +4% per rank"),
  (3,C,"measured_semi","Measured Semi",2,{"damage_pct":4},"+4% Light damage per rank"),
  (3,C,"halo_recall","Halo Recall",2,{"kill_mana":3},"Light kills refund 3 mana per rank"),
  (4,A,"martyr","Martyr",2,{"heal_pct":5},"Heals +5% per rank"),
  (4,A,"purify","Purify",1,{"kill_health":3},"Light kills heal 3"),
  (4,C,"chorus_line","Chorus Line",2,{"cooldown_pct":-3},"Cooldown -3% per rank"),
  (4,C,"hallowed","Hallowed",2,{"mark_seconds":1},"Light marks last +1 s per rank"),
  (5,A,"dawnchorus","Dawnchorus",1,{"capstone":1},"A full 3-shot burst that lands heals every ally within 6 m for 15% of max health (8 s cooldown)"),
 ]),
 "dark": ("Gloam", [
  (0,A,"shadow_touch","Shadow Touch",5,{"damage_pct":3},"+3% Dark damage per rank"),
  (0,A,"whisper","Whisper",3,{"turn_chance":0.5},"Turn chance +0.5% per rank (cap 15%)"),
  (0,C,"weak_spots","Weak Spots",3,{"crit_damage_pct":8},"Crit damage +8% per rank"),
  (0,C,"keen_eye","Keen Eye",2,{"crit_chance":2},"Crit chance +2% per rank"),
  (1,A,"long_night","Long Night",3,{"status_seconds":5},"Corrupted allies last +5 s per rank"),
  (1,A,"thrall_bond","Thrall Bond",2,{"kill_health":2},"Dark kills heal 2 per rank"),
  (1,C,"cursed_load","Cursed Load",2,{"splash_damage_pct":15},"Cursed orb damage +15% per rank"),
  (1,C,"misfortune","Misfortune",2,{"accuracy":2},"+2 accuracy per rank"),
  (2,A,"hex","Hex",3,{"mark_seconds":5,"mark_pct":3},"Dark hits apply Hex (5 s); your hits on it +3% per rank"),
  (2,A,"dread","Dread",2,{"turn_chance":0.25},"Turn chance +0.25% per rank"),
  (2,C,"orb_radius","Orb Radius",2,{"splash_pct":10},"Orb blast radius +10% per rank"),
  (2,C,"lucky_streak","Lucky Streak",2,{"crit_chance":1},"Crit chance +1% per rank"),
  (3,A,"contagion","Contagion",2,{"mark_seconds":1},"Hex lasts +1 s per rank"),
  (3,A,"dark_pact","Dark Pact",2,{"damage_pct":3},"+3% Dark damage per rank"),
  (3,C,"deadeye","Deadeye",2,{"weakpoint_pct":10},"Weak-point damage +10% per rank"),
  (3,C,"quick_curse","Quick Curse",2,{"cooldown_pct":-3},"Cooldown -3% per rank"),
  (4,A,"soul_tithe","Soul Tithe",2,{"kill_health":3},"Dark kills heal 3 per rank"),
  (4,A,"legion","Legion",1,{"status_seconds":5},"Corrupted allies last +5 s"),
  (4,C,"executioner","Executioner",2,{"crit_damage_pct":10},"Crit damage +10% per rank"),
  (4,C,"black_orb","Black Orb",2,{"mark_pct":2},"+2% damage to Hexed enemies per rank"),
  (5,A,"eclipse","Eclipse",1,{"capstone":1},"A crit on a Hexed enemy below 30% health turns it (not bosses; may ignore the 15% cap once every 20 s)"),
 ]),
}

def fmt(v):
    return repr(v) if isinstance(v, float) else str(v)

def render(el, title, rows):
    out = [f"# Element tree: {el} (Phase V step 144, generated by tools/gen_element_trees.py; placeholder numbers).",
           "", "[tree]", f'id = "{el}"', f'name = "{title}"', f'element = "{el}"', "tiers = 6", "gate = \"tree\"",
           "", "[[branch]]", 'id = "attunement"', 'name = "Attunement"', "", "[[branch]]", 'id = "craft"', 'name = "Craft"', ""]
    for tier, br, sid, name, ranks, eff, desc in rows:
        e = ", ".join(f"{k} = {fmt(v)}" for k, v in eff.items())
        out += ["[[skill]]", f'id = "{sid}"', f'name = "{name}"', f'branch = "{br}"', f"tier = {tier}", f"max_rank = {ranks}", f'desc = "{desc}"']
        if tier == 5:
            out += ["capstone = true", 'exclusive_group = "element_capstone"']
        out += [f"effects = {{ {e} }}", ""]
    return "\n".join(out)

def main():
    check = "--check" in sys.argv
    bad = 0
    for el, (title, rows) in T.items():
        assert len(rows) == 21 and sum(1 for r in rows if r[0] == 5) == 1, el
        p = ROOT / "data/skills" / f"{el}.toml"
        text = render(el, title, rows)
        if check:
            if not p.exists() or p.read_text() != text:
                print(f"[gen_element_trees] {p} out of date"); bad = 1
        else:
            p.write_text(text)
    return bad

if __name__ == "__main__":
    sys.exit(main())
