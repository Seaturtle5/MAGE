class_name StorageSystem
extends RefCounted
## Storage: a place where the player can stash carried items and take them
## back later, such as a locker in a shelter. Stored items are not carried
## (they weigh nothing and `player has` does not see them); they stay in the
## storage, saved with the game.
##
##   == storage bunker_locker
##   name: Storage locker
##   at: bunker                      (the places it is in)
##   open when: <condition>          (optional)
##   description: text shown above the two lists when it is opened
##   stash: / stash all: / retrieve: / retrieve all:
##       texts for one item or all of one item; [storage.item_name] names the
##       item and [storage.count] says how many
##   stash everything: / retrieve everything:
##       texts after moving everything; [storage.count] items of
##       [storage.kinds] different kinds (0 when there was nothing to move)
##   empty: / pack empty:  what the lists say when the storage or the pack is empty
##   kept:    refusal for an item that must stay with the player (`keep: yes`)
##   in use:  refusal for gear worn or wielded now
##
## Items with `keep: yes` and gear in use are never stashed; "stash everything"
## leaves them out.

const TEXTS := ["stash", "stash all", "retrieve", "retrieve all", "stash everything", "retrieve everything", "kept", "in use",
	"empty", "pack empty"]
## Plain wording for a storage without its own texts.
const DEFAULTS := {
	"stash": "You put the [storage.item_name] into storage.",
	"stash all": "You put [storage.count] x [storage.item_name] into storage.",
	"retrieve": "You take the [storage.item_name] from storage.",
	"retrieve all": "You take [storage.count] x [storage.item_name] from storage.",
	"stash everything": "[if storage.count = 0]You have nothing you can store.[else]You store [storage.count] items.[end if]",
	"retrieve everything": "[if storage.count = 0]The storage is empty.[else]You take out [storage.count] items.[end if]",
	"kept": "You'd better keep that with you.",
	"in use": "You're using that right now.",
	"empty": "Nothing is stored here.",
	"pack empty": "Your pack is empty.",
}
const ACTIONS := ["stash", "stash_all", "retrieve", "retrieve_all", "stash_everything", "retrieve_everything"]


static func field(game, id: String, name: String, fallback: String = "") -> String:
	return game.content.typed_value("storage", id, name, fallback)


## The storages at the player's place that are open now, sorted by ID.
static func here(game) -> Array:
	var out: Array = []
	for id in game.content.all_of("storage"):
		if game.state.location in game.content.list_field(id, "at") and is_open(game, id):
			out.append(id)
	out.sort()
	return out


static func is_open(game, id: String) -> bool:
	var when := field(game, id, "open when")
	return when == "" or Condition.evaluate(Condition.compile(when), game)


## What a storage holds: {item id: count}.
static func contents(game, id: String) -> Dictionary:
	if not game.state.storage.has(id):
		game.state.storage[id] = {}
	return game.state.storage[id]


static func stored(game, id: String, item: String) -> int:
	return int(contents(game, id).get(item, 0))


## The stored items as rows for the interface, sorted by name.
static func list(game, id: String) -> Array:
	var out: Array = []
	var held := contents(game, id)
	for item: String in held:
		out.append({"id": item, "name": ItemSystem.item_name(game, item), "count": int(held[item])})
	out.sort_custom(func(a, b): return str(a.name) < str(b.name))
	return out


## Why an item can't be stashed now, or "" (Storage Locker.i7x:112-117).
static func refusal(game, id: String, item: String) -> String:
	if game.content.typed_value("item", item, "keep", "no") == "yes":
		return _text(game, id, "kept")
	if item in game.state.equipped or game.state.wielded == item:
		return _text(game, id, "in use")
	return ""


## Runs a storage action: "stash", "stash_all", "retrieve", "retrieve_all" with
## `arg` "storage:item", or "stash_everything", "retrieve_everything" with the
## storage's ID. The storage must be here and open. Returns whether anything moved.
static func act(game, action: String, arg: String) -> bool:
	var id := arg.get_slice(":", 0)
	var item := arg.get_slice(":", 1) if ":" in arg else ""
	if action not in ACTIONS or id not in here(game):
		return false
	match action:
		"stash", "stash_all":
			var have := ItemSystem.count(game, item)
			if have <= 0:
				return false
			var why := refusal(game, id, item)
			if why != "":
				game.notice(TextTemplate.plain(game.render(TextTemplate.compile(why))), false)
				return false
			var n := have if action == "stash_all" else 1
			ItemSystem.lose(game, item, n)
			_add(game, id, item, n)
			_tell(game, id, action.replace("_", " "), item, n)
			return true
		"retrieve", "retrieve_all":
			var held := stored(game, id, item)
			if held <= 0:
				return false
			var n := held if action == "retrieve_all" else 1
			_add(game, id, item, -n)
			ItemSystem.gain(game, item, n)
			_tell(game, id, action.replace("_", " "), item, n)
			return true
		"stash_everything":
			var total := 0
			var kinds := 0
			for it: String in game.state.inventory.keys():
				if refusal(game, id, it) != "":
					continue
				var n := ItemSystem.count(game, it)
				if n <= 0:
					continue
				ItemSystem.lose(game, it, n)
				_add(game, id, it, n)
				total += n
				kinds += 1
			_tell_all(game, id, "stash everything", total, kinds)
			return total > 0
		"retrieve_everything":
			var total := 0
			var kinds := 0
			var held := contents(game, id)
			for it: String in held.keys():
				var n := int(held[it])
				ItemSystem.gain(game, it, n)
				total += n
				kinds += 1
			held.clear()
			_tell_all(game, id, "retrieve everything", total, kinds)
			return total > 0
	return false


static func _add(game, id: String, item: String, n: int) -> void:
	var held := contents(game, id)
	held[item] = int(held.get(item, 0)) + n
	if int(held[item]) <= 0:
		held.erase(item)


static func text(game, id: String, name: String) -> String:
	return TextTemplate.plain(game.render(TextTemplate.compile(_text(game, id, name))))


static func _text(game, id: String, name: String) -> String:
	return field(game, id, name, DEFAULTS[name])


static func _tell(game, id: String, name: String, item: String, n: int) -> void:
	game.state.values["storage.item"] = item
	game.state.values["storage.item_name"] = ItemSystem.item_name(game, item)
	game.state.values["storage.count"] = n
	_say(game, _text(game, id, name))


static func _tell_all(game, id: String, name: String, total: int, kinds: int) -> void:
	game.state.values["storage.count"] = total
	game.state.values["storage.kinds"] = kinds
	_say(game, _text(game, id, name))


static func _say(game, text: String) -> void:
	game.emit({"type": "paragraph", "spans": game.render(TextTemplate.compile(text))})


## Validation: places, the open condition and the texts.
static func check(v) -> void:
	for id in v.db.all_of("storage"):
		var d: FscParser.Definition = v.db.get_def("storage", id)
		v._path = d.path
		if not d.fields.has("at"):
			v._err(d.line, "A storage needs 'at:' with the places it is in.")
		else:
			for place in v.db.list_field(id, "at"):
				v._need(place, "location", d.fields["at"].line)
		if d.fields.has("open when"):
			v._check_condition_text(d.fields["open when"].value, d.fields["open when"].line, id)
		for name: String in TEXTS:
			if d.fields.has(name):
				v._check_text_field(d.fields[name].value, d.fields[name].line, id)
