extends SceneTree
## Striscia delle armi nel HUD (spec D-092, par. 7): 3 slot automatici, 2 attivi con ricarica.
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/hud_weapon_tests.gd

var _failures := 0


func _initialize() -> void:
	var strip := WeaponStrip.new()
	get_root().add_child(strip)
	await process_frame
	print("striscia")
	strip.set_slots([{icon = &"nail", level = 3, branches = "A"}], [{icon = &"stake", level = 1, branches = "", cooldown = 0.5}])
	_check(strip.slot_count() == 5, "cinque slot: tre automatici e due attivi")
	_check(strip.slot_text(0).contains("3") and strip.slot_text(0).contains("A"), "chiodatrice: livello 3, trasformazione A (%s)" % strip.slot_text(0))
	_check(strip.slot_text(1).is_empty() and strip.slot_text(2).is_empty(), "slot automatici vuoti senza testo")
	_check(is_equal_approx(strip.cooldown_of(3), 0.5) and strip.slot_text(4).is_empty(), "attiva a meta ricarica, secondo slot attivo vuoto")
	_check(strip.prompt_action(3) == &"weapon_active_1" and strip.prompt_action(4) == &"weapon_active_2", "gli slot attivi mostrano il loro tasto")
	strip.set_cooldowns([0.0])
	_check(is_zero_approx(strip.cooldown_of(3)), "ricarica aggiornata senza ricostruire")
	strip.set_slots([], [])
	_check(strip.slot_text(0).is_empty() and is_zero_approx(strip.cooldown_of(3)), "senza armi tutti gli slot sono vuoti")

	print("HUD")
	var hud := RunHud.new()
	get_root().add_child(hud)
	await process_frame
	hud.set_weapons([{icon = &"nail", level = 2, branches = ""}], [])
	_check(hud.weapon_strip() != null and hud.weapon_strip().slot_text(0).contains("2"), "il HUD inoltra le armi alla striscia")
	_check(UiIcon.KINDS.has(&"stake"), "icona del picchetto")
	var missing := WeaponCatalog.all().filter(func(e: Dictionary) -> bool: return not UiIcon.KINDS.has(e.icon))
	_check(missing.is_empty(), "ogni arma e fusione del catalogo ha la sua icona (%s)" % [missing.map(func(e: Dictionary) -> StringName: return e.icon)])
	await process_frame
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)
