# batch_08b_goblins — handoff

Files: `assets/original/ember_art/goblin_{king,grunt,archer,shaman}.glb` (rigged, skinned, Y-up, faces +Z).

| id | height (idle, body) | tris | anims | special nodes |
|---|---|---|---|---|
| goblin_grunt | 1.31–1.34 m | 2952 | Idle, Walk, Run, Attack, HitReact (+HitRecieve original), Death, Jump | `Club` (child of bone Arm.R) |
| goblin_archer | 1.31–1.34 m (hood tip 1.53) | 2982 | same | `Bow` (Arm.R), `Quiver` (Body), `Hood` (Head) |
| goblin_shaman | 1.31–1.34 m (hood tip 1.66) | 3052 | same | `Staff` with a glowing orb (Arm.R; emissive 3), `Hood` (Head), `Beads` (Body) |
| goblin_king | 2.37–2.42 m body, 2.63 crown top | 7440 | Idle, Walk, Run, Attack(=Weapon), **Slam**(=Weapon), **Throw**(=Punch), **Roar**, Death, HitReact, + Duck, Jump*, No, Yes, Wave, Punch, Weapon | `Crown`: a separate MeshInstance, skinned 100% to bone Head. Hide or free it on death and spawn the drop. `Orc_Weapon` is the spiked club. |

- Animation names are plain (no `Armature|` prefix), so character_model.gd's IDLE/WALK lists match `Idle`/`Walk` directly.
- Scale lives on the scene-root node (`goblin_<id>`); the feet sit at y=0.
- The goblin trio share one mesh and rig; they differ by texture recolour and props.
- **Luna needs to** add the ids to enemy_models.gd. I have not edited any code.
- Roar is procedural (arms out, head and torso back, frames 0–50 at 24 fps, about 2 s). Throw reuses Punch and has no projectile release marker; spawn the rock at about 40% of the clip.
- Verified by computing the skinned vertices straight from the GLB data (_src/sk.py): heights, the feet on the ground, and the Crown tracking the head in every clip.
