extends SceneTree
## Carte arma (spec D-092, par. 6.3): nuova, livello, bivio, per classe e slot.
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/weapon_offers_tests.gd

var _failures := 0
var _root: Node3D


func _initialize() -> void:
	_root = Node3D.new()
	get_root().add_child(_root)
	await process_frame
	_test_fresh_engineer()
	_test_branch_card()
	_test_maxed_weapon()
	_test_branch_cards_and_parse()
	_test_sapper_sees_nothing_of_engineer()
	_test_fusion_card()
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _loadout(class_id: StringName) -> WeaponLoadout:
	var shooter := Node3D.new()
	_root.add_child(shooter)
	var loadout := WeaponLoadout.new()
	loadout.player = shooter
	_root.add_child(loadout)
	loadout.setup_class(class_id)
	return loadout


func _ids(cards: Array[Dictionary]) -> Array:
	return cards.map(func(c: Dictionary) -> StringName: return c.id)


func _test_fresh_engineer() -> void:
	print("Ingegnere appena partito")
	var cards := WeaponOffers.cards(_loadout(&"engineer"), &"engineer", [])
	var ids := _ids(cards)
	_check(ids.has(&"w:level:nailgun") and ids.has(&"w:level:seismic_stake"), "carte livello per chiodatrice e picchetto (%s)" % [ids])
	_check(not cards.any(func(c: Dictionary) -> bool: return c.kind == &"new"), "nessuna arma nuova: niente altro di sbloccato")
	var level: Dictionary = cards.filter(func(c: Dictionary) -> bool: return c.id == &"w:level:nailgun")[0]
	_check(level.rarity == UpgradeCatalog.Rarity.COMMON and level.category == &"weapon", "livello: Comune, categoria arma")
	_check(level.shown_level == 1 and level.text == "Spara il 25% piu spesso.", "mostra il livello attuale e il testo del 2")


func _test_branch_card() -> void:
	print("carta bivio")
	var loadout := _loadout(&"engineer")
	loadout.level_up(&"nailgun")
	var cards := WeaponOffers.cards(loadout, &"engineer", [])
	var branch := cards.filter(func(c: Dictionary) -> bool: return c.weapon_id == &"nailgun")
	_check(branch.size() == 1 and branch[0].id == &"w:branch:nailgun", "al livello 2 la carta della chiodatrice e il bivio")
	_check(branch[0].rarity == UpgradeCatalog.Rarity.RARE, "il bivio e Raro")


func _test_maxed_weapon() -> void:
	print("arma al massimo")
	var loadout := _loadout(&"engineer")
	loadout.level_up(&"nailgun")
	loadout.choose_branch(&"nailgun", &"a")
	loadout.level_up(&"nailgun")
	loadout.choose_branch(&"nailgun", &"a")
	var cards := WeaponOffers.cards(loadout, &"engineer", [])
	_check(not cards.any(func(c: Dictionary) -> bool: return c.weapon_id == &"nailgun"), "nessuna carta per la chiodatrice al 5")


func _test_branch_cards_and_parse() -> void:
	print("trasformazioni")
	var cards := WeaponOffers.branch_cards(&"nailgun", 3)
	_check(_ids(cards) == [&"wb:nailgun:3:a", &"wb:nailgun:3:b"], "due carte a e b")
	_check(cards[0].name == "Raffica" and cards[1].name == "Chiodi da ponte", "coi nomi del catalogo")
	var parsed := WeaponOffers.parse(&"wb:nailgun:3:b")
	_check(parsed.kind == &"choose" and parsed.weapon_id == &"nailgun" and parsed.at == 3 and parsed.pick == &"b", "parse della trasformazione")
	_check(WeaponOffers.parse(&"w:new:nailgun").kind == &"new", "parse di una carta arma")
	_check(WeaponOffers.is_weapon_card(&"w:level:nailgun") and not WeaponOffers.is_weapon_card(&"boots"), "riconosce le carte arma")


func _test_fusion_card() -> void:
	print("carta fusione")
	var loadout := _loadout(&"sapper")
	loadout.add(&"site_blade")
	loadout.add(&"ram")
	for id in [&"site_blade", &"ram"]:
		while loadout.level_of(id) < 5:
			if loadout.needs_branch(id):
				loadout.choose_branch(id, &"b")
			else:
				loadout.level_up(id)
	var cards := WeaponOffers.cards(loadout, &"sapper", [&"site_blade", &"ram"])
	var fusion := cards.filter(func(c: Dictionary) -> bool: return c.kind == &"fusion")
	_check(fusion.size() == 1 and fusion[0].id == &"w:fusion:site_blade", "carta della fusione dalla Lama")
	_check(fusion[0].rarity == UpgradeCatalog.Rarity.LEGENDARY and fusion[0].name == "Ruspa a dischi", "Leggendaria, col nome della fusione")
	_check(WeaponOffers.parse(&"w:fusion:site_blade").kind == &"fusion", "parse della fusione")


func _test_sapper_sees_nothing_of_engineer() -> void:
	print("classi")
	var cards := WeaponOffers.cards(_loadout(&"sapper"), &"sapper", [])
	var foreign := cards.filter(func(c: Dictionary) -> bool:
		return WeaponCatalog.find(WeaponOffers.parse(c.id).get(&"weapon_id", &"")).get(&"deck", &"") == &"engineer")
	_check(foreign.is_empty(), "il Guastatore non vede le armi dell'Ingegnere (%s)" % [_ids(cards)])
