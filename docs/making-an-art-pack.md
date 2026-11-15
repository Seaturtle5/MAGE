# Making your own art pack

You can give places, characters, creatures and items pictures of your own choosing. There are two ways.

## The quick way: in the game

Under a place's picture, a character's or creature's picture, and an item's picture in the inventory, there is a small **Add image** link (**Change image** when a picture is already shown). Pick a PNG, JPG or WebP file and it is shown at once. The game copies it into a pack of your own, **My Images**, in your packs folder, so the file you picked can be moved or deleted afterwards. **Remove my image** takes your picture away again and shows the game's own.

To see the game's pictures again without removing yours, switch **My Images** off under **Settings › Content settings › Art packs**.

## By hand: a pack folder

An art pack is a folder in your packs folder. Where that is depends on your system; the game's own copy of the pictures you added in play is in a folder named `my-images` there, which you can use as an example.

- Windows: `%APPDATA%\Godot\app_userdata\MAGE\packs`
- Linux: `~/.local/share/godot/app_userdata/MAGE/packs`
- macOS: `~/Library/Application Support/Godot/app_userdata/MAGE/packs`

A `packs` folder next to the game's program works too.

```
my-art/
    pack.fsc
    art.fsc
    images/
        old_library.png
        wolf_hunter.png
        credits.fsc
```

**pack.fsc** names the pack and says it is an art pack:

```
== pack my-art
name: My Art
version: 1.0.0
authors: Your name
art: replaces
```

`art: replaces` means your pictures are shown instead of the game's own. With `art: fallback` they are only used where the game has no picture.

**art.fsc** says which picture belongs to what. Each block names the kind of thing and its ID, then the picture (the file name without its ending):

```
== extend location grey_abbey_library
image: old_library

== extend creature wolf
image: wolf_hunter
```

The kinds are `location`, `character`, `creature` and `item`. You find the IDs in the game's content files: every place, character, creature and item starts with a line such as `== location grey_abbey_library`; the ID is the last word. A picture you added in play is a good way to check: its block in `my-images/images.fsc` shows the right kind and ID.

A picture file with the same name as one of the game's own picture files (in a pack's `images/` folder) also replaces it, without an `art.fsc` line.

**images/credits.fsc** credits whoever made the pictures. The credit is shown with the picture:

```
== image old_library
artist: Your name
link: https://example.com/your-gallery
```

## Tips

- PNG, JPG and WebP all work. Wide pictures suit places; upright ones suit characters and creatures.
- Keep pictures below about 2000 pixels on the long side; larger ones load slowly.
- Start the game again after changing a pack by hand. A block that names something which does not exist is skipped; an art pack never stops the game from starting.
- Only share pictures you made yourself or are allowed to share, and credit the artist.
