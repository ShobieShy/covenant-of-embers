# Changelog: 0.11.3-prealpha

The in-game build string is `0.11.3-prealpha`. The menu name is Pre-Alpha 0.11.3.

## 0.11.3

The art gate and the capture fixes. No level was remade in this version, so the primitive check reports and does not fail the build. A scene listed in `tools/art_gate_remade.txt` fails CI if it still contains a primitive mesh or CSG node. Collision and debug nodes stay allowed.

The capture harness (`tools/art_capture.gd`) uses a fixed exposure and an orthographic top-down. Creatures and NPCs are shot from the front, with their feet on the ground. An empty frame fails the harness.

Bob's lab is its own interior. The Old Oak crown no longer runs through the room. The combat HUD hides while the Auto-Scribe menu is open. Staff and wand parts meet at their sockets.

The Core stays closed. Music stays silent.
