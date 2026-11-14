class_name CharacterSystem
extends RefCounted
## Characters' bodies, numbers and relationship with the player, after the
## original's NPC template (the "ScaleValue of X is 3. Cock Length of X is 8.
## PlayerMet of X is false." lines every character file starts with).
##
##   == character francois
##   body:
##       form: mutt                 (the strain the body is, for species words)
##       cocks: 1
##       cock length: 8
##       ball size: 3
##       ass depth: 12
##       sterile: yes
##   stats:
##       level: 5
##       strength: 14
##   relationship:
##       virgin: yes
##       anal virgin: no
##
## Every key becomes a value of the character that scenes read and change like
## any other (`francois.cock.length`, `francois.met`, `francois.virgin`), with the
## definition's number as its starting value. Conditions such as `francois is
## male` and descriptors such as `[cock_size_desc of francois]` read them as they
## read the player's body. The relationship values exist for every character:
## met, romanced, friended, controlled and had_sex start as no, the virginities
## as yes.

## body key -> [value name, kind]
const BODY := {
	"form": ["form", "text"], "scale": ["scale", "number"], "weight": ["weight", "number"],
	"definition": ["definition", "number"], "androgyny": ["androgyny", "number"],
	"cocks": ["cocks", "number"], "cock length": ["cock.length", "number"], "cock girth": ["cock.girth", "number"],
	"balls": ["balls.count", "number"], "ball size": ["balls.size", "number"],
	"cunts": ["cunts", "number"], "cunt depth": ["cunt.depth", "number"], "cunt tightness": ["cunt.tightness", "number"],
	"clit size": ["clit.size", "number"], "nipples": ["nipples", "number"], "breast size": ["breasts.size", "number"],
	"ass depth": ["ass.depth", "number"], "ass tightness": ["ass.tightness", "number"],
	"mouth length": ["mouth.length", "number"], "mouth circumference": ["mouth.circumference", "number"],
	"tongue length": ["tongue.length", "number"],
	"sterile": ["sterile", "flag"], "twisted capacity": ["twisted_capacity", "flag"],
}
## stats key -> value name (all numbers). `hp` is left to stories: the original
## used "HP of X" for a character's story stage; fighting health is `max hp`.
const STATS := {
	"level": "level", "max hp": "maxhp", "xp": "xp", "armor": "armor", "damage": "damage",
	"strength": "strength", "dexterity": "dexterity", "stamina": "stamina", "charisma": "charisma",
	"intelligence": "intelligence", "perception": "perception", "libido": "libido", "lust": "lust",
	"loyalty": "loyalty", "humanity": "humanity", "morale": "morale",
}
## relationship key -> [value name, default]
const RELATIONSHIP := {
	"met": ["met", false], "romanced": ["romanced", false], "friended": ["friended", false],
	"controlled": ["controlled", false], "had sex": ["had_sex", false], "experienced": ["experienced", false],
	"virgin": ["virgin", true], "oral virgin": ["oral_virgin", true], "anal virgin": ["anal_virgin", true],
	"penile virgin": ["penile_virgin", true],
}


## Pairs "key: value" of one of a definition's nested fields, with line numbers.
static func pairs(d: FscParser.Definition, field: String) -> Array:
	var out: Array = []
	if not d.fields.has(field):
		return out
	for l: FscParser.Line in d.fields[field].children:
		if l.is_blank() or not ":" in l.text:
			continue
		var p := l.text.split(":", true, 1)
		out.append({"key": p[0].strip_edges().to_lower(), "value": p[1].strip_edges(), "line": l.number})
	return out


## The values a character definition declares, as ContentDB value declarations.
## Keys it does not know are left out here and reported by the validator.
static func declarations(d: FscParser.Definition) -> Dictionary:
	var out := {}
	for key in RELATIONSHIP:
		out[RELATIONSHIP[key][0]] = {"kind": "flag", "default": RELATIONSHIP[key][1], "path": d.path, "line": d.line}
	for p in pairs(d, "relationship"):
		if RELATIONSHIP.has(p.key):
			out[RELATIONSHIP[p.key][0]] = {"kind": "flag", "default": p.value == "yes", "path": d.path, "line": p.line}
	for p in pairs(d, "body"):
		if BODY.has(p.key):
			var spec: Array = BODY[p.key]
			var v: Variant = p.value
			match spec[1]:
				"number":
					v = int(p.value)
				"flag":
					v = p.value == "yes"
			out[spec[0]] = {"kind": spec[1], "default": v, "path": d.path, "line": p.line}
	for p in pairs(d, "stats"):
		if STATS.has(p.key):
			out[STATS[p.key]] = {"kind": "number", "default": int(p.value), "path": d.path, "line": p.line}
	if d.fields.has("companion"):
		# A possible companion (CompanionSystem): its fighting numbers, whether it is
		# tamed (can be summoned) and when it last fought.
		for key in CompanionSystem.DEFAULTS:
			var name: String = STATS.get(key, key)
			if not out.has(name):
				out[name] = {"kind": "number", "default": CompanionSystem.DEFAULTS[key], "path": d.path, "line": d.fields.companion.line}
		var tamed := false
		for p in pairs(d, "companion"):
			if p.key == "tamed":
				tamed = p.value == "yes"
		out["tamed"] = {"kind": "flag", "default": tamed, "path": d.path, "line": d.fields.companion.line}
		out["last_fight"] = {"kind": "time", "default": null, "path": d.path, "line": d.fields.companion.line}
	# When the character last had sex (SexSystem stamps it): `since x.last_sex > 8 turns`.
	if not out.has("last_sex"):
		out["last_sex"] = {"kind": "time", "default": null, "path": d.path, "line": d.line}
	return out
