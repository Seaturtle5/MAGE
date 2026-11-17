# MAGE changelog

Changes to MAGE, the Modular Adventure Game Engine, for people who make games with it. The newest version is at the top; changes since the last version are under "Unreleased" until the next one. The content format is described in the engine's documentation and the example game in `packs/example-adventure`.

## Unreleased

Nothing yet.

## 1.0.0 (2026-11-17): first public version

The first public version, used for Flexible Survival's first public test build.

**Player-facing**
- A **Report a bug / Feedback** button in the bottom bar and on the main menu. A game sets `feedback webhook:` (a Discord webhook) in its pack; the report holds the player's text, an optional Discord username, the place and scene, the last ten steps and the game's and engine's versions, and nothing else.
- A game's `start notice:` is shown each time the game has loaded.
- The title screen's lower right corner shows the engine's card: MAGE, its Discord and GitHub, version.
- On macOS the game reads its packs from inside the app bundle (`Contents/Resources/packs`).

**For content authors** (all with validator checks and documented in the content format)
- Fights: `fight actions:` (extra player buttons from creatures, items, feats, companions and the combat rules), hooks on the player's turn and below a share of the enemy's health, `~ enemy becomes X` (second stages), `~ end fight` and `~ no second fight`, `fight random in <zones>:`, `fight X away from home:`, `player is hunting`, creature and form tags, attack texts and loot changed in play, `~ cancel blow`, fight scripts that give items and break the page.
- Story: `~ moment <name>` for other packs' hooks, hooks `after picking up`, `before picking up` (with `~ cancel pick up`), `instead of using`, `arriving`, `after import`; `~ rest`; random events by tag; area arrivals; `given:` items; discovering places by flag; level options with `when:`; events moved to other zones or levels in play; renamed characters and companions' own names; `no rescue when:` (extended play).
- Systems: smelling (`smell_rules`, door and scenery scents), the player's notes (`notes_rules`), help topics (`== help`), storage (`== storage`), collections (`== collection`), importing a player's progress from another game's export files (`== save_import`).
- Body and text: `player is looking at themself`, a form's body numbers (`form.<id>.cock.length`), the unborn child's looks, weapons and armor in scenes, `strain of x`, `level of x`, `zones of x`, `[traits of x]`, `player.heat_name`, `~ for each creature by level play X`.
- A character counts as met once its first talk is over, so first-meeting branches play.
- Text values and choice descriptions that hold markup are rendered when shown.
- An action's leading `command:` line is kept as its command words, not shown as text.
- The validator checks feat names, the form in `transform … into X`, fight values changed in an encounter, and choices in scenes played for each companion.
- Faster loading: all packs of Flexible Survival load in about 18 seconds instead of 41.
