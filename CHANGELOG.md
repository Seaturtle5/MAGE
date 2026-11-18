# MAGE changelog

Changes to MAGE, the Modular Adventure Game Engine, for people who make games with it. The newest version is at the top; changes since the last version are under "Unreleased" until the next one. The content format is described in the engine's documentation and the example game in `packs/example-adventure`.

## Unreleased

**For players and authors**
- **Debug window.** With debug mode on (the start option `--debug`, or **Debug tools** in Settings) the bottom bar has a **Debug** button (F3). On the left a line to type a command or an action on, with what it could become listed as it is typed (Tab completes, Enter runs, Up and Down bring back earlier lines) and every command listed when nothing is typed. A line is a command's ID or name, an action as content writes it (`~ give rope 2`, `~ go to great_hall`, `~ unresolve old_debt`, `~ wolf.met = 3`), `play <scene>`, `fight <creature>` or `event <id>`; it is checked like content before it runs. On the right every declared value and each event's resolved and active flags, looked up by parts of the name and changed by hand; values that differ from their start are marked. What is done there is noted among the last steps a bug report sends.
- **Debug commands.** `== command` with `debug: yes` is an author's test or skip command: never among a place's actions, run from the Debug window.
- **Hunting by name.** `by name: yes` in `hunt_rules` gives the Hunt window a box to type what is hunted for: a place, an event or a creature. A place or an event is found with a visible roll (`search bonus`, `search bonus modifiers`, `search target`, `search label`, `search certain when`); a place is then travelled to and known, an event plays. Texts: `tracks`, `searching`, `place found`, `event found`, `place not found`, `event not found`, `search fight`, and an answer for each way such a hunt ends with nothing met. `events listed when:` lists the zone's events in the window.
- `player.milk_item` and `player.cum_item` read the item the strain of the player's torso gives as milk and the strain of their cock as cum (the forms' `milk item` and `cum item`), for `~ give player.milk_item 2`.

**Fixed**
- A creature of any level can be hunted for: the combat rules' `level limit` kept creatures above it out of the Hunt list, although it is meant for random meetings.

**For tools that load content** (an editor, a checker)
- Loaded content can be layered: `ContentDB.layer()` gives a copy to load more packs onto, sharing everything already loaded. A tool keeps the packs that do not change and loads only the pack being worked on again after each change. The content below is never altered and can be layered again, also from another thread.
- `protect_definitions` on a `ContentDB` makes an extension change a copy of the definition it extends, so a tool's own parsed definitions stay as written.
- `Validator.run(content, [pack folders])` compiles and checks the scripts of those packs only.
- Actions, conditions and text can be compiled from several threads at once.
- `ContentDB.forget_compiled()` drops the compiled actions, conditions and texts kept for reuse; a tool that has checked a whole game gets several hundred megabytes back.
- The map layout of layered content is worked out faster: each definition is read once for the exits its stories make in play (`~ change north exit of A to B`) and remembers them, so after a change only the pack that was loaded again is read.

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
