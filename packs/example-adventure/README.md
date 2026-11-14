# The Quiet Woods: an example game for MAGE

A tiny game that shows how content for MAGE (Modular Adventure Game Engine) is written. Every file covers one part of the content format, in small working pieces, with comments that explain the fields. Play it, read it, then copy it to start your own game.

## Playing it

Open the engine folder (the one with `project.godot`) in the Godot 4.7 editor and press Play. The engine loads every pack in its `packs/` folder; this one is the game. On the title screen choose **New game** and pick a start:

- **The cabin:** wake in your cabin at the edge of the woods.
- **The forager:** start in the clearing with a knife, a flask of tea and the Forager feat.

Things to try: meet Wren in the clearing and help her find her knife, trade at her barter shelf by day, explore the forest and the riverbank, cross the stepping stones, get caught in the brambles, open the tool shed, brave the deep woods past the trailhead (a wild boar and an old stag live there), find the hollow log past the bridge, stay out on a cold night, and, when you're done, follow the mist at the old bridge out of the woods. The game ends with an epilogue that tells what became of you.

## Starting your own game

1. Copy this folder inside `packs/` and give the copy a new folder name.
2. In `pack.fsc`, change the pack ID on the `== pack` line, the name, and the title.
3. Remove or rewrite the files you don't need. `template.fsc` has the common definitions with their fields, ready to copy; everything in it is commented out.
4. Remove or move the original `example-adventure` folder, so the two games don't load together.

## Checking your pack

The validator lists every problem with its file, line and a plain explanation. From the engine folder:

```
godot --headless --path . --script res://tests/validate_packs.gd
```

Add folders after `--` to check packs somewhere else. The game also refuses to start with errors and shows them instead.

## Where each feature lives

| File | Shows |
|---|---|
| `pack.fsc` | The pack manifest and the main menu's title, subtitle and footer |
| `scenarios/start.fsc` | Two ways to start a game, with setup (items, coins, feats, discovered places) and an intro with a page break |
| `world/world.fsc` | A region, three zones with ambient lines, places with exits and map positions, fast travel, a locked door, a dangerous door that explores a zone, an observe menu, a place's actions menu (with `~ use` from a scene), text that changes by time of day and by a content setting |
| `world/extensions.fsc` | Adding to content from outside its file with `== extend`: an option for another file's menu, and a new exit on another file's place |
| `characters/wren.fsc` | A character with body, stats and relationship values, a description, scent and presence line, a talk menu and an actions menu whose options depend on her values, `player has visited`, a quest with four stages, and a scene scheduled a few actions later |
| `shops/trading.fsc` | A shop run by a character: opening hours, stock with prices and conditions, items it buys, trading items for others, a bonus for a feat, and scenes after buying and selling |
| `items/items.fsc` | Food, drink (with a custom icon), a medical item usable in fights, clothing for two slots, melee and ranged weapons, an item that is not used up, a key, an item named in the plural, loot, and an item that can be traded |
| `creatures/forest_fox.fsc` | A creature with two variants (picked per meeting from the player's filters), loot, an encounter that counts meetings, attack lines, win and loss scenes, and a form whose infection changes head, skin and tail; a second, non-infectious creature |
| `creatures/deep_woods.fsc` | A built-in special attack (pounce) with its own text and a loot drop; a creature with its own scripted fight: attacks with conditions, a visible hit roll, a strike, a change to its numbers for the fight, and an `each round` script that reads its health and ends the fight |
| `events/exploring.fsc` | Exploration events: a one-off find that needs a quest stage, a random creature picked by tag, a fight with won, lost and fled branches and named outcomes, an event that starts a captivity, a scavenging find, and an event that counts with its resolution number |
| `events/arrivals.fsc` | An event when arriving at a place, one when leaving a place in a direction (with a cooldown and "continue moving"), a fast-travel trip replaced by an event, and the mist that ends the game (with a chance and a cooldown) |
| `events/brambles.fsc` | A captivity: rounds of Pull free, Hold still and Catch your breath, with an escape count and a custom status line |
| `rules/cold.fsc` | A meter with stages, conditions with lasting effects, a timed condition, an every-turn hook, and an ending at the meter's limit |
| `rules/endings.fsc` | Endings and the epilogue: an opening, one ending per way the game can end (leaving, freezing, the brambles), and endings that depend on what the player did (a friendship, a fox tail) |
| `rules/interface.fsc` | The top bar's meters and money, and a meter that adds the player's coins |
| `rules/scavenging.fsc` | The scavenging rules and their generic find |
| `scenes/scenes.fsc` | Pack-wide values, a text snippet, and scenes that play other scenes a random number of times |
| `settings/settings.fsc` | Content settings: filters (with genders, for creature variants), a tag, a level, and two feats |
| `template.fsc` | Copy-ready templates of the common definitions |

The full content format is described in the engine's documentation. When something in this pack doesn't do what you expect, the validator's message is the best place to start.
