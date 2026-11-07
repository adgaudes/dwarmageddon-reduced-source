class_name WeaponOffers
extends RefCounted
## Carte arma (spec D-092, par. 6.3), costruite dallo stato degli slot: arma nuova (Non comune,
## se c'e uno slot libero e l'arma e del mazzo comune o della classe, sbloccata e implementata),
## livello 2 o 4 (Comune), bivio 3 o 5 (Raro: sceglierla apre le due trasformazioni), fusione
## (Leggendaria: automatica e compagna al livello 5). Le carte
## hanno la stessa forma delle voci di UpgradeCatalog, piu weapon_id, kind e shown_level.
## Identificatori: `w:<new|level|branch>:<arma>` e `wb:<arma>:<livello>:<a|b>`.

const KIND_TEXT := {&"auto": "Automatica", &"active": "Attiva"}


static func is_weapon_card(id: StringName) -> bool:
	var text := String(id)
	return text.begins_with("w:") or text.begins_with("wb:")


## {kind, weapon_id} per `w:`; {kind = &"choose", weapon_id, at, pick} per `wb:`; vuoto altrimenti.
static func parse(id: StringName) -> Dictionary:
	var parts := String(id).split(":")
	if parts.size() == 3 and parts[0] == "w":
		return {kind = StringName(parts[1]), weapon_id = StringName(parts[2])}
	if parts.size() == 4 and parts[0] == "wb":
		return {kind = &"choose", weapon_id = StringName(parts[1]), at = parts[2].to_int(), pick = StringName(parts[3])}
	return {}


## Carte arma possibili adesso. [param unlocked]: armi comprate in Officina.
static func cards(loadout: WeaponLoadout, class_id: StringName, unlocked: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for auto in loadout.autos():
		if loadout.can_fuse(auto.weapon_id):
			var fusion := WeaponCatalog.find(WeaponCatalog.fusion_of(auto.weapon_id))
			out.append({id = StringName("w:fusion:%s" % auto.weapon_id), name = fusion.name, category = &"weapon",
				rarity = UpgradeCatalog.Rarity.LEGENDARY, max_level = 0, requires = "", deck = fusion.deck,
				text = "Fusione. %s" % fusion.text, weapon_id = auto.weapon_id, kind = &"fusion",
				shown_level = WeaponCatalog.MAX_LEVEL, icon = fusion.icon})
	for entry in WeaponCatalog.all():
		var id: StringName = entry.id
		if entry.slot == &"fusion" or (entry.deck != &"common" and entry.deck != class_id):
			continue
		var level := loadout.level_of(id)
		if level > 0:
			if level >= WeaponCatalog.MAX_LEVEL:
				continue
			if loadout.needs_branch(id):
				out.append(_card(entry, &"branch", UpgradeCatalog.Rarity.RARE, level, "Scegli una trasformazione."))
			else:
				out.append(_card(entry, &"level", UpgradeCatalog.Rarity.COMMON, level, (entry.level_texts as Dictionary).get(level + 1, "")))
			continue
		var available := int(entry.unlock_cost) == 0 or unlocked.has(id)
		if available and loadout.free_slots(entry.slot) > 0 and WeaponLoadout.script_for(id) != null:
			out.append(_card(entry, &"new", UpgradeCatalog.Rarity.UNCOMMON, 0, "%s. %s" % [KIND_TEXT[entry.slot], entry.text]))
	return out


## Le due trasformazioni dell'arma al livello [param at_level].
static func branch_cards(weapon_id: StringName, at_level: int) -> Array[Dictionary]:
	var entry := WeaponCatalog.find(weapon_id)
	var out: Array[Dictionary] = []
	var picks: Array[StringName] = [&"a", &"b"]
	var options := WeaponCatalog.branch_options(weapon_id, at_level)
	for i in options.size():
		var option := options[i]
		out.append({id = StringName("wb:%s:%d:%s" % [weapon_id, at_level, picks[i]]), name = option.name,
			category = &"weapon", rarity = UpgradeCatalog.Rarity.RARE, max_level = 0, requires = "", deck = entry.deck,
			text = option.text, weapon_id = weapon_id, kind = &"choose", shown_level = at_level - 1, icon = entry.icon})
	return out


static func _card(entry: Dictionary, kind: StringName, rarity: int, level: int, text: String) -> Dictionary:
	return {id = StringName("w:%s:%s" % [kind, entry.id]), name = entry.name, category = &"weapon", rarity = rarity,
		max_level = 0, requires = "", deck = entry.deck, text = text, weapon_id = entry.id, kind = kind,
		shown_level = level, icon = entry.icon}
