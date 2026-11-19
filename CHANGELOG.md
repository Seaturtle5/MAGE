# MAGE changelog

Changes to MAGE, the Modular Adventure Game Engine, for people who make games with it. The newest version is at the top; changes since the last version are listed under "Next version" until that version is built, one short line each. The content format is described in the engine's documentation and the example game in `packs/example-adventure`.

## Next version (not built yet)

**New**
- Debug window: a Debug button on the bottom bar (F3) while Debug tools are switched on in Settings.
- Debug window, left: a line for a command or an action (`~ give rope 2`, `play <scene>`, `fight <creature>`, `event <id>`), with suggestions while typing, Tab to complete and every command listed.
- Debug window, right: every value and each event's resolved and active flags, looked up by name and changed by hand; changed ones are marked.
- Debug commands: `== command` with `debug: yes` runs from the Debug window only.
- What is done in the Debug window is noted among the steps a bug report sends.
- Hunting by name: `by name: yes` in `hunt_rules` gives the Hunt window a box to type a place, an event or a creature.
- Hunting by name: a search roll (`search bonus`, `search target`, `search certain when`), texts for it, and an answer for each way the hunt finds nothing.
- `events listed when:` in `hunt_rules` lists the area's events in the Hunt window.
- `tracks:` in `hunt_rules`: a line said before a hunted creature is met.
- `player.milk_item` and `player.cum_item`: the milk and cum item of the player's strain.
- A scene's picture is always shown whole, and a click shows it large.
- A page longer than its window shows "More below"; Space reads on before it continues.
- A level gained shows a notice of its own.
- The feats offered when a new game is made follow the answers given (a main stat opens up its feats).
- A feat can be bedding for a rest anywhere: `rest: rough` and `rest text:` on a feat.
- `kindred when:` and `kindred parts:` in `combat_rules`: creatures of the player's own strain are met more often.
- `kindred when:` and `kindred chance:` in `hunt_rules`: the same for hunts.
- Hooks `on: hunting` and `~ hunt may meet <creature> [N times]`: content puts creatures into a hunt.
- `here.zone` reads the zone the player explores and hunts in.
- The Debug button is shown by the Settings switch only; `--debug` no longer shows it.
- `before aftermath:` in `combat_rules` plays after a won fight's trophies; `~ no aftermath` leaves the beaten creature's scene out.

**Fixed**
- A creature of any level can be hunted for; the level limit is for random meetings only.
- A tall picture no longer pushes the fight buttons and choices off the bottom of the screen.
- A long list of choices scrolls instead of being cut off, and is set tighter.
- A feat picked at the start that the answers no longer open up gives way to the default.
- At the start each free feat is checked after the one before it is taken, so a first feat can close off a second.
- Scavenging's special find is drawn from all of the area's scavenging events, the generic find among them.

**Internal**
- New tests: hunting by name, the Debug window's rules, the feats offered at creation, a feat as bedding, the after-fight question.
- The scenario player prints choices that have no description.

**For tools that load content**
- `ContentDB.layer()`: a copy of loaded content to load more packs onto.
- `protect_definitions`: an extension changes a copy, the parsed definition stays as written.
- `Validator.run(content, [pack folders])` checks the scripts of those packs only.
- `Validator.check_program(content, program)` checks one compiled script.
- Actions, conditions and text compile from several threads at once.
- `ContentDB.forget_compiled()` frees the compiled actions, conditions and texts.
- The map layout of layered content reads each definition once.

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
