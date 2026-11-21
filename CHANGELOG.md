# MAGE changelog

Changes to MAGE, the Modular Adventure Game Engine, for people who make games with it. The newest version is at the top; changes since the last version are listed under "Next version" until that version is built, one short line each. The content format is described in the engine's documentation and the example game in `packs/example-adventure`.

## Next version (not built yet)

**New**
- `picked.feat`: after `~ choose feat`, the feat the player took, empty after Skip or when nothing was offered.
- `[not yet implemented]` on a choice or menu option: shown greyed out with "Not yet implemented" under it, and it cannot be picked.
- `fight picked.creature:` (or any value holding a creature ID) fights that creature; with none held, the scene goes on.
- `hunt_rules`: `explored nothing:`, what exploring says when it finds nothing in a zone without `ambient:` lines.
- `[name of here]`: the name of the player's location.
- Hooks `on: instead of birth`, `on: instead of child` and `on: after birth`, for a story's own births; a birth's litter follows `pregnancy.litter` when a hook changes it.
- Feats: `bonuses when:`, a condition for the feat's bonus fields to count.
- `~ pick random creature ... as a meeting`: the pick is weighted as a random meeting is (the combat rules' kindred).
- `survival_rules`: `morale limit:`, `morale limit modifiers:` and `morale reset modifiers:` (the top of morale was fixed in the engine as charisma plus perception).

**Fixed**
- `== extend text X` and `== extend scene X` add their lines after the original's (they were ignored).
- A scenario's `setup` and `intro` play even when another definition shares the scenario's ID; either may be left out.

## 1.0.1 (2026-11-19)

**New**
- Report window: the player says whether it is a bug, a suggestion or other feedback; each report has its own number.
- `feedback receiver:` in the game's pack: an address of your own that gets every report as JSON (a POST; any 2xx answer is success).
- With a receiver, a report holds the state of the game unless the player switches it off, and a save when the player attaches one.
- Reports never hold the player's name, the journal's notes or a text the player typed (`~ ask`); "Show exactly what is sent" shows the whole report.
- The Discord message stays short: the kind of report, the operating system and the report's number, never the state or the save.
- Debug window (the Debug button or F3, while Debug tools are switched on in Settings): commands and actions with suggestions, and every value and event flag looked up and changed by hand.
- `== command` with `debug: yes` runs from the Debug window only.
- Hunting by name: `by name: yes` in `hunt_rules`, with a search roll (`search bonus`, `search target`, `search certain when`) and an answer for each way a hunt finds nothing.
- `hunt_rules`: `events listed when:`, `tracks:`, `kindred when:` and `kindred chance:`.
- `combat_rules`: `kindred when:`, `kindred parts:` and `before aftermath:`; `~ no aftermath` leaves the beaten creature's scene out.
- Hooks `on: hunting` with `~ hunt may meet <creature> [N times]`.
- New values: `here.zone`, `player.milk_item`, `player.cum_item`.
- A feat can be bedding for a rest anywhere: `rest: rough` and `rest text:`.
- The feats offered when a new game is made follow the answers given.
- A scene's picture is shown whole, and a click shows it large.
- A long page shows "More below", and a level gained has a notice of its own.

**Fixed**
- A creature of any level can be hunted for; the level limit is for random meetings only.
- Tall pictures and long lists of choices no longer push buttons off the screen.
- Starting feats are checked one after the other, and one the answers no longer open up gives way to the default.
- Scavenging's special find is drawn from all of the area's scavenging events.

**For tools that load content**
- `ContentDB.layer()` and `protect_definitions`: load more packs onto a copy of loaded content.
- `Validator.run(content, [pack folders])` and `Validator.check_program(content, program)` check part of a game.
- Scripts compile from several threads at once; `ContentDB.forget_compiled()` frees them.

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
