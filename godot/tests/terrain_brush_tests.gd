extends SceneTree
## Tool del giocatore sul rilievo continuo (spec sezione 3): pennello continuo, modi,
## zainetto, anteprima a decal, aree protette.
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/terrain_brush_tests.gd

const PlayerScene := preload("res://scenes/player/player.tscn")

var _failures := 0
var _field: TerrainField
var _player: PlayerCharacter


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	_field = TerrainField.new()
	_field.size_m = Vector2(64.0, 64.0)
	_field.tuning = TerrainTuning.new()
	root.add_child(_field)
	_player = PlayerScene.instantiate()
	_player.terrain_field = _field
	root.add_child(_player)
	_player.position = Vector3(0, 0.9, 0)
	await _frames(3)
	await _test_mode_cycle()
	await _test_continuous_dig_fills_pack()
	await _test_raise_with_empty_pack()
	await _test_dig_with_full_pack()
	await _test_level_mode()
	await _test_level_with_empty_pack()
	await _test_protected_is_red()
	await _test_dig_animation_rhythm()
	_test_mouse_ray_on_relief()
	await _frames(2)
	print("PROTOTYPE01_TESTS %s failures=%d" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


## Audit G-03: tenendo premuto il tool l'affondo riparte a fine animazione, non a ogni passo.
func _test_dig_animation_rhythm() -> void:
	print("dig animation rhythm")
	var animator: CharacterAnimator = _player._animator
	if animator == null:
		_check(false, "il giocatore ha l'animatore")
		return
	if _player.terrain_tool_mode != TerrainField.ToolMode.DIG:
		_player.terrain_tool_mode = TerrainField.ToolMode.DIG
	_player.pack.take(999.0)
	var before := animator.fired_count(&"dig")
	await _hold(1.0)
	var fired := animator.fired_count(&"dig") - before
	_check(fired >= 2 and fired <= 3, "un secondo di scavo: %d affondi (non 60)" % fired)


## Audit G-02: il punto sotto il cursore sta sul rilievo, non sul piano alla quota del giocatore.
func _test_mouse_ray_on_relief() -> void:
	print("mouse ray on relief")
	var mound := Vector3(14.0, 0.0, 6.0)
	_field.sculpt(mound, 4.0, 2.5)
	var target := mound + Vector3(1.0, 0.0, 0.5)
	target.y = _field.height_at(target)
	var ray := Vector3(0.0, -sin(deg_to_rad(55.0)), -cos(deg_to_rad(55.0)))
	var origin := target - ray * 20.0
	var hit: Variant = PlayerCharacter.ray_ground_point(_field, origin, ray, 0.0)
	var error := Vector2(hit.x - target.x, hit.z - target.z).length() if hit != null else INF
	_check(error < 0.2, "il cursore su un cumulo da 2,5 m cade sul cumulo (errore %.2f m; col piano a quota 0 sarebbe %.2f m)"
		% [error, target.y / tan(deg_to_rad(55.0))])
	_field.sculpt(mound, 4.0, -2.5)


func _hold(seconds: float) -> void:
	_player.tool_held = true
	for i in int(seconds * 60.0):
		await physics_frame
	_player.tool_held = false
	await physics_frame


func _test_mode_cycle() -> void:
	print("mode cycle")
	_check(_player.terrain_tool_mode == TerrainField.ToolMode.DIG, "parte in Scava")
	_player._toggle_terrain_mode()
	_check(_player.terrain_tool_mode == TerrainField.ToolMode.RAISE, "poi Alza")
	_player._toggle_terrain_mode()
	_check(_player.terrain_tool_mode == TerrainField.ToolMode.LEVEL, "poi Livella")
	_player._toggle_terrain_mode()
	_check(_player.terrain_tool_mode == TerrainField.ToolMode.DIG, "senza LampField torna a Scava")
	await _frames(1)


func _test_continuous_dig_fills_pack() -> void:
	print("continuous dig")
	var target := _player.terrain_target
	var before := _player.pack.amount
	await _hold(0.5)
	_check(_field.height_at(target) < -0.3, "mezzo secondo di scavo abbassa il centro (%.2f)" % _field.height_at(target))
	_check(_player.pack.amount > before + 1.0, "lo zaino si riempie con la terra scavata (%.1f -> %.1f)" % [before, _player.pack.amount])
	_check(_player._preview.last_color == BrushPreview.DIG_COLOR, "anello ciano in Scava")


func _test_raise_with_empty_pack() -> void:
	print("raise with empty pack")
	_player.pack.take(999.0)
	_player._toggle_terrain_mode()  # RAISE
	var target := _player.terrain_target
	var h0 := _field.height_at(target)
	var rejected := [0]
	var handler := func() -> void: rejected[0] += 1
	_player.terrain_tool_rejected.connect(handler)
	await _hold(0.3)
	_player.terrain_tool_rejected.disconnect(handler)
	_check(absf(_field.height_at(target) - h0) < 0.001, "a zaino vuoto alzare non cambia il terreno")
	_check(_player._preview.last_color == BrushPreview.INVALID_COLOR, "anello rosso a zaino vuoto")
	_check(rejected[0] > 0, "emesso terrain_tool_rejected")
	_player.pack.give(10.0)
	await _hold(0.3)
	_check(_field.height_at(target) > h0 + 0.2, "con terra nello zaino alza")
	_check(_player.pack.amount < 10.0, "alzare consuma lo zaino (%.1f)" % _player.pack.amount)
	# Audit G-01: con parte del disco protetta (centro libero) lo zaino paga solo la terra
	# posata davvero, non quella della pennellata intera.
	var heights_before := _field.height_at(target)
	var guard := target + Vector3(1.6, 0.0, 0.0)
	_field.set_protected(guard, 1.6, true)
	var placed := [0.0]
	var counter := func(_c: Vector3, _r: float, volume: float, _m: int) -> void: placed[0] += volume
	_field.player_sculpted.connect(counter)
	var before := _player.pack.amount
	await _hold(0.3)
	_field.player_sculpted.disconnect(counter)
	_field.set_protected(guard, 1.6, false)
	var paid := before - _player.pack.amount
	_check(placed[0] > 0.01 and absf(paid - placed[0]) < 0.001, "zaino scalato quanto la terra posata (%.3f pagati, %.3f posati)" % [paid, placed[0]])
	# Torna il rilievo di prima per le prove successive.
	_field.level(target, 3.0, heights_before, 1.0)


func _test_dig_with_full_pack() -> void:
	print("dig with full pack")
	_player._toggle_terrain_mode()  # LEVEL
	_player._toggle_terrain_mode()  # DIG
	_player.pack.give(999.0)
	var target := _player.terrain_target
	var h0 := _field.height_at(target)
	await _hold(0.3)
	_check(_field.height_at(target) < h0 - 0.1, "a zaino pieno si scava lo stesso")
	_check(absf(_player.pack.fill_ratio() - 1.0) < 0.001, "lo zaino resta pieno: la terra in eccesso si perde")


func _test_level_mode() -> void:
	print("level mode")
	_player._toggle_terrain_mode()  # RAISE
	_player._toggle_terrain_mode()  # LEVEL
	var target := _player.terrain_target
	_field.sculpt(target + Vector3(1.0, 0, 0), 1.5, 0.8)
	var bump := _field.height_at(target + Vector3(1.0, 0, 0))
	await _hold(0.6)
	_check(_field.height_at(target + Vector3(1.0, 0, 0)) < bump - 0.3, "livella abbassa il cumulo accanto al centro")
	_check(_player._preview.last_color == BrushPreview.LEVEL_COLOR, "anello bianco in Livella")


## Review finale: Livella scambia terra nei due versi (spec sezione 3): a zaino vuoto non
## puo alzare i dintorni verso una cima.
func _test_level_with_empty_pack() -> void:
	print("level with empty pack")
	var target := _player.terrain_target
	_field.sculpt(target, 1.2, 1.0)
	var side := target + Vector3(1.6, 0.0, 0.0)
	var before := _field.height_at(side)
	_player.pack.take(_player.pack.capacity)
	await _hold(0.4)
	_check(_field.height_at(side) <= before + 0.01, "a zaino vuoto Livella non alza i dintorni (%.2f -> %.2f)" % [before, _field.height_at(side)])
	_check(_player.pack.amount < 0.01, "lo zaino resta vuoto (%.2f m3)" % _player.pack.amount)
	_player.pack.give(20.0)
	_field.level(target, 3.0, _field.base_height_at(target), 1.0)


func _test_protected_is_red() -> void:
	print("protected")
	_player._toggle_terrain_mode()  # DIG
	_field.set_protected(_player.terrain_target, 3.0, true)
	await _frames(2)
	_check(_player._preview.last_color == BrushPreview.INVALID_COLOR, "anello rosso su area protetta")
	var h0 := _field.height_at(_player.terrain_target)
	await _hold(0.2)
	_check(absf(_field.height_at(_player.terrain_target) - h0) < 0.001, "non scava sull'area protetta")
	_field.set_protected(_player.terrain_target, 3.0, false)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		_failures += 1
		print("  FAIL %s" % label)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame
