# The Quiet Woods: an example game for MAGE

A tiny game that shows how content for MAGE (Modular Adventure Game Engine) is written. Every file covers one part of the content format, in small working pieces, with comments that explain the fields. Play it, read it, then copy it to start your own game.

## Playing it

Open the engine folder (the one with `project.godot`) in the Godot 4.7 editor and press Play. The engine loads every pack in its `packs/` folder; this one is the game. On the title screen choose **New game** and pick a start:

- **The cabin:** wake in your cabin at the edge of the woods.
- **The forager:** start in the clearing with a knife, a flask of tea and the Forager feat.

Things to try: meet Wren in the clearing and help her find her knife, explore the forest and the riverbank, cross the stepping stones, get caught in the brambles, open the tool shed, stay out on a cold night, and, when you're done, follow the mist at the old bridge out of the woods.

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
| `scenarios/start.fsc` | Two ways to start a game, with setup (items, feats, discovered places) and an intro with a page break |
| `world/world.fsc` | A region, two zones with ambient lines, five places with exits and map positions, fast travel, a locked door, an observe menu, text that changes by time of day and by a content setting |
| `world/extensions.fsc` | Adding an option to another file's menu with `== extend` |
| `characters/wren.fsc` | A character with values, a description and presence line, a talk menu whose options depend on those values, a quest with four stages, and a scene scheduled a few actions later |
| `items/items.fsc` | Food, drink (with a custom icon), a medical item usable in fights, clothing for two slots, melee and ranged weapons, an item that is not used up, a key |
| `creatures/forest_fox.fsc` | A creature with two variants (picked per meeting from the player's filters), loot, an encounter that counts meetings, attack lines, win and loss scenes, and a form whose infection changes head, skin and tail; a second, non-infectious creature |
| `events/exploring.fsc` | Exploration events: a one-off find that needs a quest stage, a random creature picked by tag, a fight with won, lost and fled branches and named outcomes, an event that starts a captivity, and a scavenging find |
| `events/arrivals.fsc` | An event when arriving at a place, one when leaving a place in a direction (with a cooldown and "continue moving"), and an ending the player can choose (with a chance and a cooldown) |
| `events/brambles.fsc` | A captivity: rounds of Pull free, Hold still and Catch your breath, with an escape count and a custom status line |
| `rules/cold.fsc` | A meter with stages, conditions with lasting effects, a timed condition, an every-turn hook, and an ending |
| `rules/scavenging.fsc` | The scavenging rules and their generic find |
| `scenes/scenes.fsc` | Pack-wide values, a text snippet, and scenes that play other scenes a random number of times |
| `settings/settings.fsc` | Content settings: filters (with genders, for creature variants), a tag, a level, and two feats |
| `template.fsc` | Copy-ready templates of the common definitions |

The full content format is described in the engine's documentation. When something in this pack doesn't do what you expect, the validator's message is the best place to start.
