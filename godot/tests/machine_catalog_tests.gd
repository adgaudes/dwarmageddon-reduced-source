extends SceneTree
## Catalogo dei moduli e tuning della carovana (spec D-093, Sezione 1 e "Valori di partenza";
## piano A, task 1). Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/machine_catalog_tests.gd

const TUNING_PATH := "res://resources/tuning/caravan_default.tres"
## Tarature delle run (arena e ferrovia): Torcia e Faro leggono da li il raggio per livello.
const RUN_TUNING_PATHS: Array[String] = ["res://resources/tuning/run_default.tres", "res://resources/tuning/run_railway.tres"]
## Distanza minima fra due colori (RGB 0..1): l'anello a terra e la striscia del HUD li
## devono far distinguere, anche dal rosso del guasto.
const MIN_COLOR_DISTANCE := 0.25

var _failures := 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_test_modules()
	_test_colors()
	_test_tuning()
	_test_card_texts()
	await _frames(2)
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


## Revisione finale (B8): i numeri nel testo di queste carte sono copie della taratura (gli
## effetti li calcolano i moduli e ArenaRun dalla taratura, non dai `values` della carta): una
## ritaratura che dimentica la carta fallisce qui. Le altre carte leggono i propri `values`.
func _test_card_texts() -> void:
	print("card texts")
	var tuning := load(TUNING_PATH) as CaravanTuning
	var rate := UpgradeCatalog.value(&"turret_rate", &"rate_percent")
	_check(is_equal_approx(rate, roundf((tuning.turret_rate_per_level - 1.0) * 100.0))
		and UpgradeCatalog.describe(_upgrade(&"turret_rate")).contains("%d%%" % int(rate)),
		"Torretta veloce: %d%% = turret_rate_per_level %.2f, e il testo lo dice" % [int(rate), tuning.turret_rate_per_level])
	var magnet := UpgradeCatalog.value(&"magnet_range", &"radius_per_level")
	_check(is_equal_approx(magnet, tuning.magnet_radius_per_level),
		"Calamita potente: %.1f m = magnet_radius_per_level %.1f" % [magnet, tuning.magnet_radius_per_level])
	var beacon := UpgradeCatalog.value(&"beacon_range", &"radius_per_level")
	var torch := UpgradeCatalog.value(&"torch_range", &"radius_per_level")
	for path in RUN_TUNING_PATHS:
		var run := load(path) as RunTuning
		_check(run != null and is_equal_approx(beacon, run.beacon_radius_per_level) and is_equal_approx(torch, run.torch_radius_per_level),
			"Faro %.1f m e Torcia %.1f m per livello = %s (%.1f, %.1f)" % [beacon, torch, path.get_file(),
				run.beacon_radius_per_level if run != null else -1.0, run.torch_radius_per_level if run != null else -1.0])


func _upgrade(id: StringName) -> Dictionary:
	for entry in UpgradeCatalog.all():
		if entry.id == id:
			return entry
	return {text = ""}


## Otto moduli nell'ordine della spec, coi nomi, le icone e gli sblocchi di serie.
func _test_modules() -> void:
	print("modules")
	var expected: Array[StringName] = [&"cargo", &"turret", &"magnet", &"beacon", &"drill", &"shovel", &"welder", &"siren"]
	var names: Array[String] = ["Cassone", "Torretta", "Calamita", "Faro", "Trivella", "Pala", "Saldatore", "Sirena"]
	var icons: Array[StringName] = [&"crate", &"turret", &"magnet", &"beacon", &"drill", &"scoop", &"solder", &"siren"]
	_check(MachineCatalog.MODULES == expected, "otto moduli in quell'ordine (%s)" % [MachineCatalog.MODULES])
	var entries := MachineCatalog.all()
	var ids: Array[StringName] = []
	for entry in entries:
		ids.append(entry.id)
	_check(ids == expected, "il catalogo segue l'ordine dei moduli (%s)" % [ids])
	for i in expected.size():
		var id := expected[i]
		var entry := MachineCatalog.find(id)
		_check(MachineCatalog.name_of(id) == names[i] and entry.get(&"name", "") == names[i], "%s si chiama %s (%s)" % [id, names[i], MachineCatalog.name_of(id)])
		_check(entry.get(&"icon", &"") == icons[i], "%s: icona %s (%s)" % [id, icons[i], entry.get(&"icon", &"")])
		_check(UiIcon.KINDS.has(entry.get(&"icon", &"")), "%s: icona fra quelle disegnate (UiIcon.KINDS)" % id)
		var text: String = entry.get(&"text", "")
		_check(not text.is_empty() and not text.contains("\n"), "%s: testo di una riga (%s)" % [id, text])
	var unlocked: Array[StringName] = []
	for entry in entries:
		if entry.get(&"unlocked_by_default", false):
			unlocked.append(entry.id)
	var by_default: Array[StringName] = [&"cargo", &"turret", &"magnet", &"beacon"]
	_check(unlocked == by_default, "sbloccati di serie esattamente Cassone, Torretta, Calamita e Faro (%s)" % [unlocked])
	_check(MachineCatalog.find(&"nope").is_empty(), "un modulo sconosciuto non c'e")
	_check(MachineCatalog.name_of(&"nope") == "", "un modulo sconosciuto non ha nome")
	_check(is_same(MachineCatalog.all(), MachineCatalog.all()) and is_same(MachineCatalog.find(&"cargo"), MachineCatalog.find(&"cargo")), "il catalogo e costruito una volta sola")


## Colori dell'anello a terra e della striscia: distinti a coppie e dal rosso del guasto,
## accesi e saturi per staccarsi dal terreno.
func _test_colors() -> void:
	print("colors")
	var colors: Array[Color] = []
	var labels: Array[String] = []
	for entry in MachineCatalog.all():
		colors.append(entry.get(&"color", Color.BLACK))
		labels.append(String(entry.id))
	colors.append(UiPalette.DANGER)
	labels.append("guasto")
	var closest := INF
	var closest_pair := ""
	for i in colors.size():
		for j in range(i + 1, colors.size()):
			var a := colors[i]
			var b := colors[j]
			var distance := Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
			if distance < closest:
				closest = distance
				closest_pair = "%s/%s" % [labels[i], labels[j]]
	_check(closest >= MIN_COLOR_DISTANCE, "colori a coppie distinti, anche dal rosso del guasto (piu vicini %s: %.2f)" % [closest_pair, closest])
	var dull: Array[String] = []
	for i in colors.size() - 1:
		if colors[i].v < 0.75 or colors[i].s < 0.4:
			dull.append(labels[i])
	_check(dull.is_empty(), "colori accesi e saturi, leggibili sul terreno (spenti: %s)" % [dull])


func _test_tuning() -> void:
	print("tuning")
	var tuning := load(TUNING_PATH) as CaravanTuning
	_check(tuning != null, "caravan_default.tres si carica come CaravanTuning")
	if tuning == null:
		return
	_check(tuning.chassis_health == 6 and tuning.module_limit == 6, "telaio da 6 PV, limite di 6 moduli")
	_check(is_equal_approx(tuning.hit_cooldown, 0.8), "immunita di 0,8 s dopo un colpo")
	_check(tuning.repair_cost == 2 and is_equal_approx(tuning.repair_seconds, 1.5), "riparazione: 2 rottami, 1,5 s")
	_check(is_equal_approx(tuning.regen_delay, 8.0) and is_equal_approx(tuning.regen_interval, 4.0), "rigenerazione dopo 8 s, 1 PV ogni 4 s")
	var slots := tuning.cluster_slots
	_check(slots.size() == 7, "sette posti nel grappolo (%d)" % slots.size())
	var radii_ok := true
	for slot in slots:
		if slot.y < 2.0 or slot.y > 4.0:
			radii_ok = false
	_check(radii_ok, "ogni posto fra 2 e 4 m dal giocatore (%s)" % [slots])
	# I primi sei posti (il limite dei moduli) non si sovrappongono: due macchine vicine
	# devono restare ad almeno 1,2 m (task 2).
	var nearest := INF
	for i in mini(slots.size(), 6):
		for j in range(i + 1, mini(slots.size(), 6)):
			var a := Vector2.from_angle(deg_to_rad(slots[i].x)) * slots[i].y
			var b := Vector2.from_angle(deg_to_rad(slots[j].x)) * slots[j].y
			nearest = minf(nearest, a.distance_to(b))
	_check(nearest > 1.2, "i primi sei posti sono distinti (piu vicini a %.2f m)" % nearest)
	# Movimento e Cassone uguali al compagno di oggi (companion_default.tres, che il task 3
	# toglie): la migrazione non cambia il gioco.
	_check(is_equal_approx(tuning.max_speed, 5.0) and is_equal_approx(tuning.acceleration, 25.0) and is_equal_approx(tuning.arrive_radius, 0.4), "movimento del compagno: 5 m/s, 25 m/s2, arrivo a 0,4 m")
	_check(slots[0].is_equal_approx(Vector2(0.0, 2.5)) and is_equal_approx(tuning.path_margin, 1.5), "primo posto a 2,5 m dietro al giocatore e margine del percorso di 1,5 m, come il compagno")
	_check(tuning.starting_scrap == 3 and tuning.cargo_capacity == 5, "Cassone del compagno: parte con 3 rottami, ne porta 5")
	_check(is_equal_approx(tuning.pickup_radius_from_player, 6.0) and is_equal_approx(tuning.collect_radius, 0.9) and is_equal_approx(tuning.supply_radius, 5.0), "raccolta entro 6 m dal giocatore, a 0,9 m, fornitura entro 5 m")
