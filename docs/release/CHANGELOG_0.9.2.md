# Changelog: 0.9.2-prealpha (2026-11-12)

Main quests and side quests. SaveGame stays on version 1.
The in-game build string is `0.9.2-prealpha`. The menu name is Pre-Alpha 0.9.2.

## 0.9.2

- One tracked quest. Starting a main quest tracks it. A side quest does not, unless Track is pressed.
- Joe's Marks and Joe's Seals are side quests. The rest of the current chain is main.
- The Sunken Ruins is a main quest: face the Drowned Choir. It starts once Forgemaw is known. No new dialogue.
- The HUD shows only the tracked quest. Main titles are gold. Side titles are blue.
- The Missions tab filters Main, Side, and Completed, and shows the reward and a recommended level.
- A short completion card names the quest and the XP and dust. It does not pause.
- A world mark follows the tracked step when a gate, waystone, or speaker is already there. A kill step marks that level's entrance. During the intro the existing gold mark stays the only one.
- The minimap draws that mark.
- An available quest with a giver shows ! for a main quest and ? for a side quest. No new givers were added, so the current chain does not grow new marks.
- Bounty counts are saved on the world save. A character file can carry side quests and bounty counts, and does not carry the host's story flags.
- The Abyss is still not a quest.

## Still not in

- An item-choice reward.
- A turn-in for the quests that already complete themselves.
- Live replication of the host's tracker onto a joiner's screen. The host save keeps the story. The joiner's file keeps their side quests and bounties.
