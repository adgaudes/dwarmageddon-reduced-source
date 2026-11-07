extends SceneTree
## Test dei lampioni (D-058, tappa 2; `docs/DAY_NIGHT_SPEC.md` sezione 7) sul rilievo
## continuo (D-085): posa su terreno piano, distanza minima, costo, luce, caduta quando il
## suolo si muove, Demolitore che li abbatte. Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/lamp_tests.gd

const RunScene := preload("res://scenes/main/arena_run.tscn")

var _failures := 0
var _scene: Node3D
var _run: ArenaRun
var _field: TerrainField
var _player: PlayerCharacter
var _caravan: Caravan
var _director: EnemyDirector
var _lamps: LampField
var _hud: RunHud


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_scene = RunScene.instantiate()
	root.add_child(_scene)
	_run = _scene.get_node(^"Run")
	_field = _scene.get_node(^"TerrainField")
	_player = _scene.get_node(^"Player")
	_caravan = _scene.get_node(^"Caravan")
	_director = _scene.get_node(^"EnemyDirector")
	_lamps = _scene.get_node(^"LampField")
	_hud = _scene.get_node(^"RunHud")
	_director.spawning = false
	(_scene.get_node(^"PlayerWeapon") as AutoWeapon).set_physics_process(false)
	await _frames(5)
	await _test_mode_cycle()
	_test_lamp_rules_on_relief()
	await _test_lamp_falls_when_ground_moves()
	await _test_cost()
	_test_light_and_loss()
	await _test_boss_knocks_down()
	# T-12: i nodi messi in coda con queue_free vanno liberati prima di uscire, o
	# il motore segnala istanze ObjectDB perse all'uscita.
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


func _send(action: StringName) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
	await _frames(2)


func _place_player_facing(target: Vector3) -> void:
	# Il giocatore sta a sud del bersaglio, alla distanza del tool, e guarda a nord (-Z).
	var reach: float = _field.tuning.tool_range_m + _player.tool_range_bonus_m
	var at := target + Vector3(0.0, 0.0, reach)
	_player.global_position = Vector3(at.x, _field.height_at(at) + 0.88, at.z)
	_player.velocity = Vector3.ZERO
	_player.look_at(target + Vector3(0.0, _player.global_position.y, 0.0), Vector3.UP)
	_player._update_terrain_target()


## Il Cassone capofila accanto a [param near], con [param scrap] rottami a bordo.
func _supply(near: Vector3, scrap: int) -> void:
	_caravan.lead().global_position = near + Vector3(0.0, 0.3, 2.0)
	_caravan.carried = scrap


func _test_mode_cycle() -> void:
	print("mode cycle")
	_place_player_facing(Vector3(0.0, 0.0, -4.8))
	_player.terrain_tool_mode = TerrainField.ToolMode.DIG
	await _send(&"terrain_mode")
	var second := _player.terrain_tool_mode
	await _send(&"terrain_mode")
	var third := _player.terrain_tool_mode
	await _send(&"terrain_mode")
	var fourth := _player.terrain_tool_mode
	var lamp_preview: Color = _player._preview.last_color
	await _send(&"terrain_mode")
	_check(second == TerrainField.ToolMode.RAISE and third == TerrainField.ToolMode.LEVEL and fourth == TerrainField.ToolMode.LAMP
		and _player.terrain_tool_mode == TerrainField.ToolMode.DIG,
		"il tasto del modo cicla scava -> alza -> livella -> lampione -> scava")
	_check(lamp_preview.is_equal_approx(BrushPreview.LAMP_COLOR) or lamp_preview.is_equal_approx(BrushPreview.INVALID_COLOR),
		"in modo lampione l'anello e bianco caldo o rosso")
	_check(_hud._tool_label.visible == false, "indicatore del tool nascosto fuori dal modo lampione")
	_player.terrain_tool_mode = TerrainField.ToolMode.LAMP
	_player.terrain_mode_changed.emit(_player.terrain_tool_mode)
	_check(_hud._tool_label.visible and _hud._tool_label.text.contains("0/%d" % _lamps.max_count) and _hud._tool_label.text.contains("%d rottami" % _lamps.scrap_cost),
		"in modo lampione l'HUD mostra costo e contatore: %s" % _hud._tool_label.text)
	_player.terrain_tool_mode = TerrainField.ToolMode.DIG
	_player.terrain_mode_changed.emit(_player.terrain_tool_mode)


func _test_lamp_rules_on_relief() -> void:
	print("lamp rules")
	_caravan.add_cargo_capacity(20)
	_caravan.add_scrap(20)
	# Fuori dal cortile di partenza: nei primi 10 s il suo disco (6 m) e protetto.
	var flat := Vector3(0.0, 0.0, -14.0)
	_check(_lamps.can_place(flat), "si pianta su terreno piano")
	_field.sculpt(flat, 1.5, 0.6)
	_check(not _lamps.can_place(flat), "non si pianta su un fianco (dislivello > 0,3 m entro 1 m)")
	_field.level(flat, 2.0, _field.base_height_at(flat), 1.0)
	_field.level(flat, 2.0, _field.base_height_at(flat), 1.0)
	_check(_lamps.can_place(flat), "spianato, si pianta di nuovo")
	_check(not _lamps.can_place(Vector3(200.0, 0.0, 0.0)), "non fuori dal rilievo")
	_supply(flat, 20)
	_check(_lamps.place_at(flat) and _lamps.count() == 1 and _lamps.positions().size() == 1, "piantato")
	_check(not _lamps.can_place(flat + Vector3(1.5, 0.0, 0.0)), "un altro entro 2 m e rifiutato")
	_check(_lamps.can_place(flat + Vector3(3.0, 0.0, 0.0)), "a 3 m si")
	var lamp_y: float = (_lamps.positions()[0] as Vector3).y
	_check(absf(lamp_y - _field.height_at(flat)) < 0.05, "il palo poggia sulla quota del rilievo (%.2f)" % lamp_y)
	# Limite: fino a max_count.
	var x := 1
	while _lamps.count() < _lamps.max_count:
		var at := Vector3(x * 3.0, 0.0, -14.0)
		_supply(at, 20)
		_lamps.place_at(at)
		x += 1
	var extra := Vector3(-6.0, 0.0, -14.0)
	_supply(extra, 20)
	_check(_lamps.count() == _lamps.max_count and not _lamps.can_place(extra) and not _lamps.place_at(extra),
		"al massimo (%d) il settimo e rifiutato" % _lamps.max_count)
	_lamps.remove_all(&"test")
	_check(_lamps.count() == 0 and _lamps.positions().is_empty(), "pulizia")


func _test_lamp_falls_when_ground_moves() -> void:
	print("lamp falls")
	var p := Vector3(0.0, 0.0, -14.0)
	_supply(p, 20)
	_check(_lamps.place_at(p), "lampione piantato per la prova")
	var lost: Array = []
	var handler := func(_point: Vector3, reason: StringName) -> void: lost.append(reason)
	_lamps.lamp_lost.connect(handler)
	_field.sculpt(p + Vector3(2.0, 0.0, 0.0), 2.4, 0.2)
	await _frames(1)
	_check(lost.is_empty() and _lamps.count() == 1, "uno spostamento sotto 0,4 m non lo abbatte")
	_field.sculpt(p, 2.4, 0.8)
	await _frames(1)
	_check(lost.size() == 1 and lost[0] == &"terrain" and _lamps.count() == 0, "oltre 0,4 m il lampione cade")
	_lamps.lamp_lost.disconnect(handler)
	_field.level(p, 4.0, _field.base_height_at(p), 1.0)
	_field.level(p, 4.0, _field.base_height_at(p), 1.0)


func _test_cost() -> void:
	print("cost")
	var target := Vector3(0.0, 0.0, -14.0)
	_supply(target, _lamps.scrap_cost - 1)
	var rejected := [0]
	var handler := func() -> void: rejected[0] += 1
	_player.terrain_tool_rejected.connect(handler)
	_place_player_facing(target)
	_player.terrain_tool_mode = TerrainField.ToolMode.LAMP
	_player._update_terrain_target()
	await _frames(1)
	_check(not _lamps.can_afford(target) and _player._preview.last_color == BrushPreview.INVALID_COLOR,
		"con %d rottami l'anello e rosso" % _caravan.carried)
	_player.tool_held = true
	await _frames(2)
	_player.tool_held = false
	_check(rejected[0] >= 1 and _lamps.count() == 0, "senza rottami il comando e rifiutato")
	_supply(target, _lamps.scrap_cost + 1)
	_player._update_terrain_target()
	await _frames(1)
	_player.tool_held = true
	await _frames(2)
	_player.tool_held = false
	_check(_lamps.count() == 1 and _caravan.carried == 1, "col tool: lampione piazzato e %d rottami spesi (%d, %d)" % [_lamps.scrap_cost, _lamps.count(), _caravan.carried])
	_player.terrain_tool_rejected.disconnect(handler)
	_player.terrain_tool_mode = TerrainField.ToolMode.DIG
	_lamps.remove_all(&"test")


func _test_light_and_loss() -> void:
	print("light and loss")
	var world := Vector3(9.6, 0.0, -14.0)
	_caravan.add_scrap(6)
	_supply(world, 6)
	_check(_lamps.place_at(world), "lampione piantato a %s" % world)
	# Via il faro del capofila e la torcia: conta solo il lampione.
	_caravan.lead().global_position = world + Vector3(60.0, 0.3, 0.0)
	_player.global_position = world + Vector3(-60.0, 0.88, 0.0)
	var field := _run.light_field
	_check(field.is_lit(world + Vector3(_lamps.light_radius - 0.1, 0.0, 0.0)) and not field.is_lit(world + Vector3(_lamps.light_radius + 0.3, 0.0, 0.0)),
		"il lampione illumina entro %.0f m nel campo logico" % _lamps.light_radius)
	var lost := [0]
	_lamps.lamp_lost.connect(func(_point: Vector3, _reason: StringName) -> void: lost[0] += 1)
	_field.sculpt(world, 2.4, -0.8)
	_check(lost[0] == 1 and _lamps.count() == 0 and not field.is_lit(world), "scavare sotto il lampione lo perde e spegne la luce")
	_field.level(world, 4.0, _field.base_height_at(world), 1.0)
	_field.level(world, 4.0, _field.base_height_at(world), 1.0)


func _test_boss_knocks_down() -> void:
	print("boss knocks down")
	_player.global_position = Vector3(0.0, 0.88, 0.0)
	_player._invulnerable_left = 600.0
	var world := Vector3(0.0, 0.0, -14.4)
	_supply(world, 6)
	_check(_lamps.place_at(world), "lampione piantato davanti al cortile")
	_run.boss_call_at = _run.elapsed + 0.05
	await _frames(6)
	_run._boss_warning_left = 0.05
	await _frames(6)
	var boss := _run.boss as Demolisher
	_check(boss != null and boss.lamp_field == _lamps, "il Demolitore conosce i lampioni")
	if boss != null:
		boss.global_position = world + Vector3(0.5, _field.height_at(world) + Demolisher.boss_spawn_height(), 0.0)
		await _frames(3)
		_check(_lamps.count() == 0, "entrando nel raggio di contatto lo abbatte")
	_caravan.lead().global_position = Vector3(-3.0, 0.3, 0.0)
