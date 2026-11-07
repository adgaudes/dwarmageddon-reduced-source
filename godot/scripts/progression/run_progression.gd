class_name RunProgression
extends RefCounted
## Esperienza, livelli ed estrazione delle carte (PROGRESSION_SPEC, regole 1-4).
## Logica pura e deterministica dato il seed: nessun nodo, testabile da sola.

## Regola 1: pesi di rarita. I leggendari non sono nel catalogo del prototipo.
const RARITY_WEIGHTS: Array[float] = [60.0, 27.0, 10.0, 3.0]
const CARDS := 3

var rng := RandomNumberGenerator.new()
var catalog: Array[Dictionary] = []
## Livello di ogni upgrade posseduto.
var levels: Dictionary[StringName, int] = {}
var xp := 0
var level := 1
var xp_first_level := 5
var xp_growth := 3
## Regola 4.
var pity_level_ups := 4
var level_ups_without_rare := 0
## Con la carovana in scena compaiono le carte che la richiedono (`requires = "caravan"`) e,
## se c'e il modulo, quelle di un modulo (`requires = "module:<id>"`).
var has_caravan := true
## Quante macchine della carovana hanno il modulo: `func(id: StringName) -> int` (ArenaRun la
## collega a `Caravan.count_of`). Non impostata vale 0: le carte dei moduli non compaiono.
var module_count: Callable
var seed_value := 0
## Classe del giocatore (D-092): con un valore compaiono solo le carte comuni e quelle del suo
## mazzo; vuota, tutte (test e simulazioni vecchie).
var class_id: StringName = &""
## Carte arma possibili (WeaponOffers.cards), chiamata a ogni offerta; se ne restituisce, la
## prima carta dell'offerta e un'arma (spec D-092, par. 6.3).
var weapon_cards: Callable
## Carte "Nuova macchina" possibili (MachineOffers.cards), chiamata a ogni offerta; al piu una
## entra nell'offerta (spec D-093, Sezione 5).
var machine_cards: Callable


func setup(run_seed: int, upgrades: Array[Dictionary] = []) -> void:
	seed_value = run_seed
	rng.seed = run_seed
	catalog = upgrades if not upgrades.is_empty() else UpgradeCatalog.all()


func xp_to_next() -> int:
	return xp_first_level + xp_growth * (level - 1)


## Aggiunge esperienza; restituisce quanti livelli ha guadagnato.
func add_xp(amount: int) -> int:
	xp += amount
	var gained := 0
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		gained += 1
	return gained


func level_of(id: StringName) -> int:
	return levels.get(id, 0)


## Regola 2: niente upgrade al massimo ne carte per moduli che la carovana non ha.
## Le carte ripetibili (`filler`) non sono qui: vedi `fillers()`.
func eligible() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for upgrade in catalog:
		if upgrade.get(&"filler", false) or level_of(upgrade.id) >= upgrade.max_level:
			continue
		if not _requirement_met(upgrade) or not _in_deck(upgrade):
			continue
		result.append(upgrade)
	return result


## `requires`: "" sempre; "caravan" con la carovana; "module:<id>" con almeno una macchina col
## modulo. Un valore sconosciuto non passa.
func _requirement_met(upgrade: Dictionary) -> bool:
	var requires: String = upgrade.get(&"requires", "")
	if requires.is_empty():
		return true
	if requires == "caravan":
		return has_caravan
	if requires.begins_with("module:"):
		var module_id := StringName(requires.trim_prefix("module:"))
		return has_caravan and module_count.is_valid() and int(module_count.call(module_id)) > 0
	return false


## Carte comuni e della classe; piu quelle gia possedute (una carta di un altro mazzo avuta in
## altro modo resta potenziabile).
func _in_deck(upgrade: Dictionary) -> bool:
	var deck: StringName = upgrade.get(&"deck", &"common")
	return class_id == &"" or deck == &"common" or deck == class_id or level_of(upgrade.id) > 0


## Carte ripetibili: riempiono l'offerta quando gli upgrade veri stanno finendo,
## cosi un level-up non resta mai senza scelta.
func fillers() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for upgrade in catalog:
		if not upgrade.get(&"filler", false):
			continue
		if not _requirement_met(upgrade) or not _in_deck(upgrade):
			continue
		result.append(upgrade)
	return result


## Tre carte distinte. Regola 3: categorie diverse finche il pool lo permette.
## Regola 4: dopo pity_level_ups scelte senza Rari, la prima carta e Rara o superiore.
## D-092: con carte arma la prima e un'arma, la seconda preferisce il mazzo della classe.
## D-093: al piu una carta "Nuova macchina" per offerta.
func roll_offer() -> Array[Dictionary]:
	var offer: Array[Dictionary] = []
	var used_categories: Array[StringName] = []
	var force_rare := level_ups_without_rare >= pity_level_ups
	var weapons: Array[Dictionary] = []
	if weapon_cards.is_valid():
		weapons.assign(weapon_cards.call())
	if not weapons.is_empty():
		var weapon_pool: Array = weapons
		# La fusione, quando c'e, e sempre la carta arma (spec par. 6.3).
		var fusions := weapons.filter(func(u: Dictionary) -> bool: return u.rarity >= UpgradeCatalog.Rarity.LEGENDARY)
		if not fusions.is_empty():
			weapon_pool = fusions
			force_rare = false
		elif force_rare:
			var rare := weapons.filter(func(u: Dictionary) -> bool: return u.rarity >= UpgradeCatalog.Rarity.RARE)
			if not rare.is_empty():
				weapon_pool = rare
				force_rare = false
		var pick := _weighted_pick(weapon_pool)
		offer.append(pick)
		used_categories.append(pick.category)
	var machines: Array[Dictionary] = []
	if machine_cards.is_valid():
		machines.assign(machine_cards.call())
	var pool := eligible()
	# Le carte macchina contano come una sola per le ripetibili: ne entra al piu una (D-056).
	if pool.size() + mini(machines.size(), 1) < CARDS - offer.size():
		pool.append_array(fillers())
	pool.append_array(machines)
	for i in CARDS - offer.size():
		var candidates := pool.filter(func(u: Dictionary) -> bool: return not offer.has(u))
		if candidates.is_empty():
			break
		var fresh := candidates.filter(func(u: Dictionary) -> bool: return not used_categories.has(u.category))
		if not fresh.is_empty():
			candidates = fresh
		if class_id != &"" and offer.size() == 1:
			var own := candidates.filter(func(u: Dictionary) -> bool: return u.get(&"deck", &"common") == class_id)
			if not own.is_empty():
				candidates = own
		if force_rare:
			var rare := candidates.filter(func(u: Dictionary) -> bool: return u.rarity >= UpgradeCatalog.Rarity.RARE)
			if rare.is_empty():
				rare = pool.filter(func(u: Dictionary) -> bool:
					return u.rarity >= UpgradeCatalog.Rarity.RARE and not offer.has(u))
			if not rare.is_empty():
				candidates = rare
				force_rare = false
		var pick := _weighted_pick(candidates)
		offer.append(pick)
		used_categories.append(pick.category)
		# Una carta macchina nell'offerta: le altre escono dal pool (anche dal recupero del Raro).
		if MachineOffers.is_machine_card(pick.id):
			pool.assign(pool.filter(func(u: Dictionary) -> bool: return not MachineOffers.is_machine_card(u.id)))
	var has_rare := offer.any(func(u: Dictionary) -> bool: return u.rarity >= UpgradeCatalog.Rarity.RARE)
	level_ups_without_rare = 0 if has_rare else level_ups_without_rare + 1
	return offer


## Carte di una cassa sepolta (spec D-092, par. 6.3): fino a [param count] carte arma distinte,
## pesate per rarita come il level-up; una fusione (Leggendaria), se c'e, sempre per prima.
func roll_weapon_offer(cards: Array[Dictionary], count := CARDS) -> Array[Dictionary]:
	var offer: Array[Dictionary] = []
	var pool: Array = cards.duplicate()
	var fusions := pool.filter(func(u: Dictionary) -> bool: return u.rarity >= UpgradeCatalog.Rarity.LEGENDARY)
	if not fusions.is_empty() and count > 0:
		offer.append(_weighted_pick(fusions))
		pool.erase(offer[0])
	while offer.size() < count and not pool.is_empty():
		var pick := _weighted_pick(pool)
		offer.append(pick)
		pool.erase(pick)
	return offer


## Restituisce il nuovo livello dell'upgrade.
func choose(id: StringName) -> int:
	levels[id] = level_of(id) + 1
	return levels[id]


## Ogni rarita pesa come da regola 1 indipendentemente da quante carte contiene;
## le rarita assenti dal gruppo sono ignorate e i pesi rinormalizzati.
func _weighted_pick(candidates: Array) -> Dictionary:
	var per_rarity := {}
	for upgrade in candidates:
		per_rarity[upgrade.rarity] = per_rarity.get(upgrade.rarity, 0) + 1
	var total := 0.0
	var weights: Array[float] = []
	for upgrade in candidates:
		var w: float = RARITY_WEIGHTS[upgrade.rarity] / per_rarity[upgrade.rarity]
		weights.append(w)
		total += w
	var roll := rng.randf() * total
	for i in candidates.size():
		roll -= weights[i]
		if roll <= 0.0:
			return candidates[i]
	return candidates[candidates.size() - 1]
