class_name MachineOffers
extends RefCounted
## Carte "Nuova macchina" del level-up (spec D-093, Sezione 5): una per modulo disponibile,
## finche la carovana ha posto; Rare nel mazzo comune, Non comuni nel mazzo del Meccanico.
## Le carte hanno la stessa forma delle voci di UpgradeCatalog, piu module_id e shown_level
## (0: la carta mostra "NUOVO"), come le carte arma di WeaponOffers. Identificatore:
## `m:new:<modulo>`. Al piu una entra in un'offerta (RunProgression.roll_offer). Le carte
## dei relitti sepolti (`wreck_cards`) hanno la stessa forma.

const PREFIX := "m:new:"
## Inizio del nome di ogni carta macchina (il menu espone i nomi, non gli id: test e bot la
## riconoscono da qui).
const NAME_PREFIX := "Nuova macchina: "


static func is_machine_card(id: StringName) -> bool:
	return String(id).begins_with(PREFIX)


## Modulo della carta, o &"" se [param id] non e una carta macchina.
static func module_of(id: StringName) -> StringName:
	if not is_machine_card(id):
		return &""
	return StringName(String(id).trim_prefix(PREFIX))


static func card(module_id: StringName, class_id: StringName) -> Dictionary:
	var entry := MachineCatalog.find(module_id)
	var mechanic := class_id == &"mechanic"
	return {id = StringName(PREFIX + String(module_id)), name = NAME_PREFIX + String(entry.name), category = &"companion",
		rarity = UpgradeCatalog.Rarity.UNCOMMON if mechanic else UpgradeCatalog.Rarity.RARE, max_level = 0, requires = "",
		deck = class_id if mechanic else &"common", text = entry.text, module_id = module_id, shown_level = 0,
		icon = entry.icon}


## Carte possibili adesso: una per modulo di [param available]; nessuna senza carovana o a
## carovana piena.
static func cards(caravan: Caravan, class_id: StringName, available: Array[StringName]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if caravan == null or not caravan.has_room():
		return out
	for module_id in available:
		out.append(card(module_id, class_id))
	return out


## Carte del relitto sepolto (D-093, Sezione 5): [param count] moduli distinti a caso fra
## [param available], con la forma delle carte "Nuova macchina" (al piu quanti sono i
## moduli). Il posto nella carovana lo controlla chi apre la scelta.
static func wreck_cards(available: Array[StringName], class_id: StringName, rng: RandomNumberGenerator, count := 2) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var pool := available.duplicate()
	while out.size() < count and not pool.is_empty():
		out.append(card(pool.pop_at(rng.randi_range(0, pool.size() - 1)), class_id))
	return out
