# Changelog: 0.9.4-prealpha (2026-11-13)

Co-op protocol 6. A 0.9.3 build cannot join a 0.9.4 session.
The in-game build string is `0.9.4-prealpha`. The menu name is Pre-Alpha 0.9.4.
SaveGame stays on version 1.

## 0.9.4

- Enemy snapshots in co-op are smaller. A full fight fits in one packet. Protocol 6 refuses an older build instead of desyncing.
- Distant idle enemies think less often. Crowds separate with a spatial hash.
- The looked-at interact target is chosen once per physics frame.
- The kill line is stored on the level. A joiner who falls is checked against that line.
- The export ships only the terrain layers a level uses.
- The pause menu is the Auto-Scribe. The Clerk hands it over during the introduction.
- Greybox nav caches and the doubled UI art stay out of the download.
