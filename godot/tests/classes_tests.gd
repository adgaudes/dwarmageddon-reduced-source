extends SceneTree
## Classi (spec D-092, par. 5 e 10): mazzi separati per classe e carte dei mazzi (ClassPerks).
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/classes_tests.gd

const SmokeTestScene := preload("res://scenes/main/smoke_test.tscn")
const CLASSES: Array[StringName] = [&"engineer", &"sapper", &"mechanic", &"weeder"]
const CARAVAN_TUNING := preload("res://resources/tuning/caravan_default.tres")

var _failures := 0
var _root: Node3D
var _director: EnemyDirector
var _field: TerrainField


## Giocatore finto: vita e scala del costo di alzata, quanto basta a ClassPerks.
class PlayerStub extends Node3D:
	var health := 5
	var raise_cost_scale := 1.0

	func heal(amount: int) -> void:
		health += amount


func _initialize() -> void:
	_root = Node3D.new()
	get_root().add_child(_root)
	_director = EnemyDirector.new()
	_director.spawning = false
	_root.add_child(_director)
	_field = TerrainField.new()
	_field.render = false
	_field.size_m = Vector2(40.0, 40.0)
	get_root().add_child(_field)
	_director.terrain_field = _field
	await process_frame
	_test_catalog()
	for class_id in CLASSES:
		await _test_decks(class_id)
	await _test_banks_fuse_grass()
	await _test_chain_reaction()
	await _test_weld_and_bush()
	await _test_engine()
	await _test_pocket_seeds()
	await _test_quick_cast_in_scene()
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _test_catalog() -> void:
	print("catalogo dei mazzi")
	for class_id in CLASSES:
		var own := UpgradeCatalog.all().filter(func(u: Dictionary) -> bool: return u.deck == class_id)
		_check(own.size() >= 2, "%s: almeno due carte proprie (%d)" % [class_id, own.size()])
	_check(ClassCatalog.start_cards(&"weeder") == ([&"tall_grass"] as Array[StringName]), "l'Erbacciaia parte con Erba alta")
	_check(ClassCatalog.start_cards(&"engineer").is_empty(), "l'Ingegnere senza carte iniziali")
	for id in ClassPerks.IDS:
		var found := UpgradeCatalog.all().filter(func(u: Dictionary) -> bool: return u.id == id)
		_check(found.size() == 1, "%s nel catalogo" % id)


## Loadout con la chiodatrice "di scena" adottata e il kit della classe, come fa ArenaRun.
func _loadout(class_id: StringName) -> WeaponLoadout:
	var shooter := Node3D.new()
	_root.add_child(shooter)
	var scene_weapon := AutoWeapon.new()
	scene_weapon.shooter = shooter
	scene_weapon.director = _director
	_root.add_child(scene_weapon)
	var loadout := WeaponLoadout.new()
	loadout.player = shooter
	loadout.director = _director
	loadout.terrain_field = _field
	_root.add_child(loadout)
	loadout.adopt(scene_weapon)
	loadout.setup_class(class_id)
	return loadout


func _clear() -> void:
	for child in _root.get_children():
		if child != _director:
			child.queue_free()
	await process_frame


## 500 offerte con seme fisso, scegliendo sempre la prima carta: nessuna carta (arma o no) di
## un'altra classe.
func _test_decks(class_id: StringName) -> void:
	print("mazzo %s" % class_id)
	var loadout := _loadout(class_id)
	await process_frame
	var unlocked: Array[StringName] = []
	for entry in WeaponCatalog.all():
		if int(entry.get(&"unlock_cost", 0)) > 0:
			unlocked.append(entry.id)
	var progression := RunProgression.new()
	progression.setup(17)
	progression.class_id = class_id
	progression.has_caravan = true
	progression.weapon_cards = func() -> Array[Dictionary]: return WeaponOffers.cards(loadout, class_id, unlocked)
	for card in ClassCatalog.start_cards(class_id):
		progression.choose(card)
	var foreign: Array[String] = []
	var weapon_seen := 0
	for i in 500:
		var offer := progression.roll_offer()
		for card in offer:
			var deck: StringName = card.get(&"deck", &"common")
			if deck != &"common" and deck != class_id:
				foreign.append(String(card.id))
		if offer.is_empty():
			continue
		var pick: Dictionary = offer[0]
		if WeaponOffers.is_weapon_card(pick.id):
			weapon_seen += 1
			var parsed := WeaponOffers.parse(pick.id)
			match parsed.kind:
				&"new":
					loadout.add(parsed.weapon_id)
				&"level":
					loadout.level_up(parsed.weapon_id)
				&"branch":
					loadout.choose_branch(parsed.weapon_id, &"a")
				&"fusion":
					loadout.fuse(parsed.weapon_id)
		else:
			progression.choose(pick.id)
	_check(foreign.is_empty(), "%s: nessuna carta di un'altra classe in 500 offerte %s" % [class_id, foreign.slice(0, 5)])
	_check(weapon_seen > 0, "%s: compaiono carte arma (%d)" % [class_id, weapon_seen])
	_check(progression.level_of(&"tall_grass") >= (1 if class_id == &"weeder" else 0), "%s: carte iniziali tenute" % class_id)
	await _clear()


## Carovana vera senza giocatore: la sua macchina sta ferma dove la mette il test.
func _caravan() -> Caravan:
	var caravan := Caravan.new()
	caravan.tuning = CARAVAN_TUNING
	_root.add_child(caravan)
	return caravan


func _perks() -> ClassPerks:
	var perks := ClassPerks.new()
	perks.director = _director
	perks.terrain_field = _field
	_root.add_child(perks)
	return perks


func _test_banks_fuse_grass() -> void:
	print("argini, miccia, erba")
	var perks := _perks()
	var player := PlayerStub.new()
	_root.add_child(player)
	perks.player = player
	perks.loadout = _loadout(&"engineer")
	await process_frame
	perks.apply(&"reinforced_banks", 1)
	_check(is_equal_approx(_director.gnaw_scale, 1.0 / 0.7), "Argini rinforzati liv. 1: morsi il 30%% piu radi (%.2f)" % _director.gnaw_scale)
	perks.apply(&"reinforced_banks", 2)
	_check(is_equal_approx(_director.gnaw_scale, 1.0 / 0.4), "liv. 2: piu radi ancora")
	perks.apply(&"quick_cast", 1)
	_check(is_equal_approx(player.raise_cost_scale, 0.8), "Getto rapido liv. 1: alzare costa l'80%")
	perks.apply(&"short_fuse", 2)
	var stake := perks.loadout.weapon(&"seismic_stake") as ActiveWeapon
	_check(is_equal_approx(stake.cooldown_total(), 15.0 * 0.8), "Miccia corta liv. 2: ricarica all'80%% (%.1f s)" % stake.cooldown_total())
	perks.apply(&"tall_grass", 2)
	_check(is_equal_approx(_director.meadow_slow, 0.4), "Erba alta liv. 2: -40% sul prato")
	_director.gnaw_scale = 1.0
	_director.meadow_slow = 0.0
	await _clear()


func _test_chain_reaction() -> void:
	print("reazione a catena")
	var perks := _perks()
	perks.apply(&"chain_reaction", 1)
	var hole := Vector3(4.0, 0.0, 4.0)
	_field.dig_to_base_offset(hole, 1.6, 0.8)
	var dying := _director.spawn_at(hole)
	dying.global_position = hole
	dying.health = 1
	var neighbour := _director.spawn_at(hole + Vector3(1.0, 0.0, 0.0))
	neighbour.global_position = hole + Vector3(1.0, 0.0, 0.0)
	neighbour.health = 5
	dying.take_damage(1)
	_check(neighbour.health == 4, "ucciso in un cratere: il vicino perde 1 PV (%d)" % neighbour.health)
	var flat := Vector3(-8.0, 0.0, -8.0)
	var dying_flat := _director.spawn_at(flat)
	dying_flat.global_position = flat
	dying_flat.health = 1
	var neighbour_flat := _director.spawn_at(flat + Vector3(1.0, 0.0, 0.0))
	neighbour_flat.global_position = flat + Vector3(1.0, 0.0, 0.0)
	neighbour_flat.health = 5
	dying_flat.take_damage(1)
	_check(neighbour_flat.health == 5, "ucciso in piano: niente esplosione")
	# Una fila in una trincea, a 1,2 m: ogni esplosione uccide il successivo; al massimo
	# CHAIN_PER_STEP esplosioni nello stesso passo.
	_director.clear_horde()
	var trench := Vector3(-6.0, 0.0, 8.0)
	for k in 9:
		_field.dig_to_base_offset(trench + Vector3(k, 0.0, 0.0), 1.2, 0.8)
	perks._chain_left = ClassPerks.CHAIN_PER_STEP
	var row: Array[Enemy] = []
	for k in 6:
		var enemy := _director.spawn_at(trench + Vector3(1.2 * k, 0.0, 0.0))
		enemy.global_position = trench + Vector3(1.2 * k, 0.0, 0.0)
		enemy.health = 1
		row.append(enemy)
	var kills := _director.kills
	row[0].take_damage(1)
	_check(_director.kills - kills == 1 + ClassPerks.CHAIN_PER_STEP, "la catena si propaga e si ferma a %d esplosioni (%d morti)" % [ClassPerks.CHAIN_PER_STEP, _director.kills - kills])
	_field.reset_to_base(trench + Vector3(4.0, 0.0, 0.0), Vector2(7.0, 2.0))
	_director.clear_horde()
	_field.reset_to_base(hole, Vector2(3.0, 3.0))
	await _clear()


func _test_weld_and_bush() -> void:
	print("saldatura al volo e cespuglio")
	var perks := _perks()
	var player := PlayerStub.new()
	_root.add_child(player)
	var caravan := _caravan()
	var machine := caravan.lead()
	perks.player = player
	perks.caravan = caravan
	machine.global_position = Vector3(2.0, 0.0, 0.0)
	perks.apply(&"field_weld", 1)
	for i in 46:
		perks._physics_process(1.0)
	_check(player.health == 6, "macchina vicina: 1 PV dopo 45 s (%d)" % player.health)
	machine.global_position = Vector3(12.0, 0.0, 0.0)
	for i in 50:
		perks._physics_process(1.0)
	_check(player.health == 6, "macchina lontana: niente")
	machine.global_position = Vector3(2.0, 0.0, 0.0)
	machine.state = Machine.State.BROKEN
	for i in 50:
		perks._physics_process(1.0)
	_check(player.health == 6, "macchina vicina ma guasta: niente")
	machine.state = Machine.State.OK
	perks.levels.erase(&"field_weld")
	var map := MeadowMap.new()
	map.setup(_field)
	perks.meadow = map
	perks.apply(&"healing_bush", 1)
	for i in 61:
		perks._physics_process(1.0)
	_check(player.health == 6, "fuori dal prato il cespuglio non cura")
	map.mark(player.global_position, 2.0)
	for i in 61:
		perks._physics_process(1.0)
	_check(player.health == 7, "sul prato 1 PV ogni 60 s")
	perks.apply(&"healing_bush", 2)
	for i in 41:
		perks._physics_process(1.0)
	_check(player.health == 8, "al liv. 2 ogni 40 s")
	await _clear()


func _test_engine() -> void:
	print("motore truccato")
	var perks := _perks()
	var caravan := _caravan()
	var machine := caravan.lead()
	var shared := caravan.tuning
	var base_speed := shared.max_speed
	perks.caravan = caravan
	perks.apply(&"tuned_engine", 1)
	var top_speed := caravan.tuning.max_speed * caravan.speed_scale
	_check(is_equal_approx(top_speed, base_speed * 1.2), "velocita +20%% (%.1f)" % top_speed)
	perks.apply(&"tuned_engine", 2)
	_check(is_equal_approx(caravan.tuning.max_speed * caravan.speed_scale, base_speed * 1.4), "liv. 2: +40%")
	_check(caravan.tuning == shared and is_equal_approx(shared.max_speed, base_speed), "la taratura condivisa non si tocca")
	var enemy := _director.spawn_at(Vector3(6.0, 0.0, 6.0))
	enemy.global_position = Vector3(6.0, 0.0, 6.0)
	enemy.health = 5
	machine.global_position = Vector3(6.3, 0.0, 6.0)
	machine.velocity = Vector3.ZERO
	perks._physics_process(0.6)
	_check(enemy.health == 5, "fermo non travolge")
	machine.velocity = Vector3(4.0, 0.0, 0.0)
	perks._physics_process(0.6)
	_check(enemy.health == 4, "in corsa travolge: 1 danno")
	machine.state = Machine.State.BROKEN
	perks._physics_process(0.6)
	_check(enemy.health == 4, "guasta non travolge")
	machine.state = Machine.State.OK
	_director.clear_horde()
	await _clear()


func _test_pocket_seeds() -> void:
	print("semi in tasca")
	var perks := _perks()
	var map := MeadowMap.new()
	map.setup(_field)
	perks.meadow = map
	perks.apply(&"pocket_seeds", 1)
	var bank := Vector3(-4.0, 0.0, 6.0)
	_field.level(bank, 1.5, 1.2, 1.0)
	_check(not map.is_meadow(bank), "prima l'argine non e prato")
	_field.player_sculpted.emit(bank, 1.5, 0.4, TerrainField.ToolMode.RAISE)
	_check(map.is_meadow(bank), "un rialzo diventa prato, anche sopra la base")
	var dug := Vector3(8.0, 0.0, -6.0)
	perks._seed_left = 0.0
	_field.player_sculpted.emit(dug, 1.5, -0.4, TerrainField.ToolMode.DIG)
	_check(not map.is_meadow(dug), "scavare non semina")
	_field.reset_to_base(bank, Vector2(2.0, 2.0))
	await _clear()


## Getto rapido sul giocatore vero: a parita di pennellata lo zaino perde meno terra.
func _test_quick_cast_in_scene() -> void:
	print("getto rapido nel giocatore")
	var spent: Array[float] = []
	for scale: float in [1.0, 0.8]:
		var scene := SmokeTestScene.instantiate()
		root.add_child(scene)
		var player: PlayerCharacter = scene.get_node(^"Player")
		await _frames(10)
		player.raise_cost_scale = scale
		player.pack.give(player.pack.capacity)
		var before := player.pack.amount
		player.terrain_tool_mode = TerrainField.ToolMode.RAISE
		player._update_terrain_target()
		player.tool_held = true
		await _frames(20)
		player.tool_held = false
		spent.append(before - player.pack.amount)
		scene.queue_free()
		await _frames(2)
	_check(spent[0] > 0.0, "alzare consuma terra (%.3f)" % spent[0])
	_check(spent[1] < spent[0] * 0.9 and spent[1] > spent[0] * 0.6, "con scala 0,8 ne consuma circa l'80%% (%.3f contro %.3f)" % [spent[1], spent[0]])


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
