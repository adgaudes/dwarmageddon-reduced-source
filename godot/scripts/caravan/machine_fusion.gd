class_name MachineFusion
extends RefCounted
## Fusione delle macchine (D-093, piano B): taglia, vita, velocita, forza e scala in funzione
## dei moduli di una macchina, costi in rottami e anteprime di fusione e sgancio per il banco.
## Logica pura: i valori stanno in CaravanTuning, nessun nodo.

enum Size { SMALL, MEDIUM, LARGE, COLOSSUS }

const SIZE_NAMES: Array[String] = ["Piccola", "Media", "Grande", "Colosso"]


## Taglia (Size) di una macchina con [param module_count] moduli: l'indice piu alto con
## `size_min_modules[i] <= module_count`.
static func size_of(module_count: int, tuning: CaravanTuning) -> int:
	var n := maxi(module_count, 1)
	var size := 0
	for i in tuning.size_min_modules.size():
		if tuning.size_min_modules[i] <= n:
			size = i
	return size


## Vita massima: i telai dei moduli, piu `health_bonus_per_size` per taglia.
static func max_health_of(module_count: int, tuning: CaravanTuning) -> int:
	var size := size_of(module_count, tuning)
	return roundi(tuning.chassis_health * module_count * (1.0 + tuning.health_bonus_per_size * size))


## Fattore della velocita massima: meno `speed_malus_per_size` per taglia.
static func speed_factor_of(module_count: int, tuning: CaravanTuning) -> float:
	return 1.0 - tuning.speed_malus_per_size * size_of(module_count, tuning)


## Forza dei moduli (scelta 4 di D-093): +`power_per_extra_module` per modulo oltre il primo.
## Pilotata dal giocatore (piano C) vale `pilot_power_bonus` in piu.
static func power_of(module_count: int, tuning: CaravanTuning, piloted := false) -> float:
	var power := 1.0 + tuning.power_per_extra_module * (module_count - 1)
	if piloted:
		power *= 1.0 + tuning.pilot_power_bonus
	return power


## Velocita del giocatore a bordo: quella a piedi x `pilot_speed_factor`.
static func pilot_speed(player_walk_speed: float, tuning: CaravanTuning) -> float:
	return player_walk_speed * tuning.pilot_speed_factor


## Scala del modello, dei pezzi, dell'anello a terra e del raggio di contatto.
static func model_scale_of(module_count: int, tuning: CaravanTuning) -> float:
	return tuning.size_model_scale[size_of(module_count, tuning)]


## Vita dopo una fusione o uno sgancio: la stessa frazione del massimo, almeno 1 PV. Con un
## massimo di partenza nullo (telai senza vita) la macchina nasce piena.
static func carried_health(health_sum: int, max_sum: int, new_max: int) -> int:
	if max_sum <= 0:
		return maxi(new_max, 1)
	return clampi(roundi(new_max * health_sum / float(max_sum)), 1, new_max)


## Rottami per assorbire una macchina di [param absorbed_modules] moduli.
static func fuse_cost(absorbed_modules: int, tuning: CaravanTuning) -> int:
	return tuning.fuse_cost_per_module * absorbed_modules


## Rottami per sganciare un modulo.
static func detach_cost(tuning: CaravanTuning) -> int:
	return tuning.detach_cost_per_module


## Anteprima della fusione: la seconda macchina entra nella base, i suoi moduli in coda.
## `speed` in m/s; `new_combos` sono le combinazioni del risultato che nessuna delle due aveva.
static func preview_fuse(base_ids: Array[StringName], base_health: int, base_max: int,
		other_ids: Array[StringName], other_health: int, other_max: int, tuning: CaravanTuning) -> Dictionary:
	var modules: Array[StringName] = []
	modules.append_array(base_ids)
	modules.append_array(other_ids)
	var n := modules.size()
	var max_health := max_health_of(n, tuning)
	var combos := MachineCatalog.combos_of(modules)
	var base_combos := MachineCatalog.combos_of(base_ids)
	var other_combos := MachineCatalog.combos_of(other_ids)
	var new_combos: Array[StringName] = []
	for id in combos:
		if not base_combos.has(id) and not other_combos.has(id):
			new_combos.append(id)
	return {
		modules = modules,
		size = size_of(n, tuning),
		max_health = max_health,
		health = carried_health(base_health + other_health, base_max + other_max, max_health),
		speed = tuning.max_speed * speed_factor_of(n, tuning),
		power = power_of(n, tuning),
		combos = combos,
		new_combos = new_combos,
		cost = fuse_cost(other_ids.size(), tuning),
		allowed = n <= tuning.max_modules_per_machine,
	}


## Anteprima dello sgancio del modulo [param index]: sorgente e macchina sganciata conservano la
## frazione di vita. Con `index` fuori da [param ids] l'anteprima e vuota e `allowed` falso.
static func preview_detach(ids: Array[StringName], index: int, health: int, max_health: int, tuning: CaravanTuning) -> Dictionary:
	if index < 0 or index >= ids.size():
		return {source = {}, detached = {}, lost_combos = [] as Array[StringName], cost = detach_cost(tuning), allowed = false}
	var source_ids: Array[StringName] = []
	source_ids.append_array(ids)
	source_ids.remove_at(index)
	var detached_ids: Array[StringName] = [ids[index]]
	var source_max := max_health_of(source_ids.size(), tuning)
	var source_combos := MachineCatalog.combos_of(source_ids)
	var lost_combos: Array[StringName] = []
	for id in MachineCatalog.combos_of(ids):
		if not source_combos.has(id):
			lost_combos.append(id)
	var detached_max := max_health_of(1, tuning)
	return {
		source = {
			modules = source_ids,
			size = size_of(source_ids.size(), tuning),
			max_health = source_max,
			health = carried_health(health, max_health, source_max),
			speed = tuning.max_speed * speed_factor_of(source_ids.size(), tuning),
			combos = source_combos,
		},
		detached = {
			modules = detached_ids,
			size = size_of(1, tuning),
			max_health = detached_max,
			health = carried_health(health, max_health, detached_max),
			speed = tuning.max_speed * speed_factor_of(1, tuning),
		},
		lost_combos = lost_combos,
		cost = detach_cost(tuning),
		allowed = ids.size() >= 2,
	}
