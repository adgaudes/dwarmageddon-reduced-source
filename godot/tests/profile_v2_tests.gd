extends SceneTree
## Profilo versione 2 e catalogo dell'Officina per sezioni (spec D-092, par. 6.2 e 8; piano 4).
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/profile_v2_tests.gd

const ProfileScript := preload("res://scripts/services/player_profile.gd")
const PATH := "user://profile_v2_test.cfg"

var _failures := 0


func _initialize() -> void:
	_test_catalog()
	_test_v1_loads()
	_test_v2_round_trip()
	_test_bad_class()
	_remove(PATH)
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _remove(path: String) -> void:
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _new_profile() -> PlayerProfileService:
	var profile: PlayerProfileService = ProfileScript.new()
	profile.profile_path = ""
	return profile


func _test_catalog() -> void:
	print("catalogo")
	var groups := PermanentCatalog.GROUPS.map(func(g: Array) -> StringName: return g[0])
	_check(groups == [&"common", &"engineer", &"sapper", &"mechanic", &"weeder"], "cinque sezioni: comune e classi")
	for group: StringName in groups:
		var count := PermanentCatalog.all().filter(func(e: Dictionary) -> bool: return e.group == group).size()
		_check(count >= 2, "%s: almeno due voci (%d)" % [group, count])
	_check(PermanentCatalog.find(&"tool_reach").group == &"common" and PermanentCatalog.find(&"cargo").group == &"common", "le voci di oggi diventano comuni")
	_check(PermanentCatalog.find(&"fixed_turret").group == &"mechanic", "la Torretta fissa passa al Meccanico")
	_check(PermanentCatalog.find(&"unlock_ram").costs == [20] and PermanentCatalog.find(&"unlock_site_blade").costs == [15], "sblocchi coi costi del catalogo delle armi")
	_check(PermanentCatalog.weapon_of(&"unlock_jackhammer") == &"jackhammer" and PermanentCatalog.weapon_of(&"tool_reach") == &"", "arma di uno sblocco")
	_check(PermanentCatalog.unlock_id(&"cement_mixer") == &"unlock_cement_mixer", "id dello sblocco di un'arma")
	_check(PermanentCatalog.find(&"unlock_nailgun").is_empty(), "le armi di classe non si sbloccano")
	_check(PermanentCatalog.RECIPES.size() == 6, "sei fusioni nel ricettario")
	for id: StringName in PermanentCatalog.RECIPES:
		_check(WeaponCatalog.find(id).get(&"slot", &"") == &"fusion", "%s e una fusione" % id)
	_check(is_same(PermanentCatalog.all(), PermanentCatalog.all()), "catalogo costruito una volta")


## Un profilo di versione 1 scritto a mano: tutto quello che c'era resta, le novita prendono il default.
func _test_v1_loads() -> void:
	print("profilo versione 1")
	_remove(PATH)
	var config := ConfigFile.new()
	config.set_value("profile", "version", 1)
	config.set_value("profile", "scrap", 17)
	config.set_value("profile", "levels_unlocked", 2)
	config.set_value("upgrades", "tool_reach", 2)
	config.set_value("upgrades", "fixed_turret", 1)
	config.set_value("mystery", "answer", 42)
	config.save(PATH)
	var profile := _new_profile()
	_check(profile.load_profile(PATH) == OK, "si carica")
	_check(profile.scrap == 17 and profile.levels_unlocked == 2, "rottami e livelli sbloccati intatti")
	_check(profile.level_of(&"tool_reach") == 2 and profile.level_of(&"fixed_turret") == 1, "upgrade intatti, Torretta compresa")
	_check(profile.last_class == &"engineer" and profile.recipes.is_empty() and profile.unlocked_weapons().is_empty(), "default: Ingegnere, nessuna ricetta, nessuna arma")
	_check(profile.save_profile() == OK, "si salva")
	var reread := ConfigFile.new()
	reread.load(PATH)
	_check(reread.get_value("profile", "version", 0) == PlayerProfileService.VERSION, "salvato nella versione corrente (%d)" % PlayerProfileService.VERSION)
	_check(reread.get_value("mystery", "answer", 0) == 42, "la sezione sconosciuta resta")
	profile.free()


func _test_v2_round_trip() -> void:
	print("versione 2 avanti e indietro")
	_remove(PATH)
	var profile := _new_profile()
	profile.profile_path = PATH
	profile.scrap = 20
	profile.set_last_class(&"weeder")
	_check(profile.discover_recipe(&"mortar"), "prima scoperta di una ricetta: vero")
	_check(not profile.discover_recipe(&"mortar"), "seconda volta: falso")
	_check(profile.buy(&"unlock_site_blade") and profile.scrap == 5, "sblocco della Lama comprato per 15")
	_check(profile.unlocked_weapons() == ([&"site_blade"] as Array[StringName]), "armi sbloccate")
	var loaded := _new_profile()
	loaded.load_profile(PATH)
	_check(loaded.last_class == &"weeder", "ultima classe ricordata")
	_check(loaded.has_recipe(&"mortar") and not loaded.has_recipe(&"fort"), "ricette ricordate")
	_check(loaded.unlocked_weapons() == ([&"site_blade"] as Array[StringName]), "sblocchi ricordati")
	var reread := ConfigFile.new()
	reread.load(PATH)
	_check(not reread.has_section("unknown") and reread.get_value("recipes", "mortar", false) == true, "ricette nella loro sezione")
	loaded.save_profile()
	reread.load(PATH)
	_check(reread.get_section_keys("recipes").size() == 1, "nessuna ricetta duplicata fra le sezioni sconosciute")
	profile.free()
	loaded.free()


func _test_bad_class() -> void:
	print("classe sconosciuta")
	_remove(PATH)
	var config := ConfigFile.new()
	config.set_value("profile", "version", 2)
	config.set_value("profile", "last_class", "pirate")
	config.save(PATH)
	var profile := _new_profile()
	profile.load_profile(PATH)
	_check(profile.last_class == &"engineer", "una classe sconosciuta torna all'Ingegnere")
	profile.set_last_class(&"pirate")
	_check(profile.last_class == &"engineer", "set_last_class ignora le classi sconosciute")
	profile.free()
