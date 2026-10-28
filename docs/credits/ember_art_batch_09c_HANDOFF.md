# stairs_warrens_4x4.glb (replaces stairs_warrens.glb, which was 8 m long)
Footprint 4 x 4 m (x/z -2..2) to fit WarrensKit.stair_hole. Drop 4.2 m (STAIR_DEPTH).
Pivot: hole centre at floor level (y=0). The top entry is at the -Z edge, like the original; your yaw PI puts it on the south edge.

## Layout: three-quarter-turn spiral around an open well
1.2 m bands inside 0.2 m shaft walls.
- Flight 1: 11 risers on the +X band, from the -Z edge going toward +Z.
- NE landing at -1.777.
- Flight 2: 5 risers along the +Z wall, going toward -X.
- NW landing at -2.585.
- Flight 3: 10 risers on the -X band, going back toward -Z. It ends on the floor at -4.2 in the SW corner.
26 risers of 0.1615 m. Going is about 0.24 m. Pitch is about 34°, and the collision ramps are under 45°.

## Nodes
stairs_warrens_4x4 (root) > _LOD0 (Glow child), _LOD1, _LOD2, stairs_warrens_4x4_col-colonly, PromptPoint (1.2, 1.2, -1.6), BottomExit (-0.6, -4.2, -1.0).
The collision has 3 flight ramps, 2 landings, the shaft floor, 4 shaft walls (to y+1) and a 1 m rail wall on the well side of flights 1 and 2.

## Notes for code
- The model ships its own collision, so the create_trimesh_collision() pass in stair_down isn't needed.
- labyrinth_floor's StairsDown trigger is at local (0, -3.8, +1.4), the "north end". That spot is now under flight 2 and the NE/NW landings. Move the trigger to BottomExit (the SW corner / well).
- StairLanding (top at -4.2) agrees with the shaft floor. The shaft floor has a slab of its own at -4.2 to -4.4.
- The arch post bases and the rune lintel stick out about 0.2 m past the hole on the -Z/+X rim. They sit on the floor slab.
