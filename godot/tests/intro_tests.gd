extends SceneTree
## Test dell'intro all'avvio (D-080). Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/intro_tests.gd

const IntroScene := preload("res://scenes/main/boot_intro.tscn")

var _failures := 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	await _frames(1)
	_test_skip_rules()
	await _test_sequence_completes()
	await _test_skip_on_input()
	await _test_handoff_keeps_pause_disabled()
	await _test_fade_and_sounds()
	await _test_skip_by_key()
	await _test_vignette_hook()
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


func _test_skip_rules() -> void:
	_check(BootIntro.should_skip(PackedStringArray(["--autostart"]), false), "--autostart salta l'intro")
	_check(BootIntro.should_skip(PackedStringArray(["--level=railway"]), false), "--level= salta l'intro")
	_check(BootIntro.should_skip(PackedStringArray([]), true), "headless salta l'intro")
	_check(not BootIntro.should_skip(PackedStringArray([]), false), "avvio normale: intro")
	_check(not BootIntro.should_skip(PackedStringArray(["--intro-test"]), true), "--intro-test la forza anche in headless")
	_check(RunLaunchOptions.wants_intro_test(PackedStringArray(["--intro-test"])), "RunLaunchOptions legge --intro-test")


## Con force_play la sequenza gira in headless e finisce da sola entro 5 s.
func _test_sequence_completes() -> void:
	var intro := IntroScene.instantiate() as BootIntro
	intro.force_play = true
	intro.change_scene_on_finish = false
	root.add_child(intro)
	await _frames(2)
	var pause := root.get_node("PauseMenu")
	_check(intro.is_playing and pause.get(&"enabled") == false, "intro in corso, pausa disattivata")
	var done := [false]
	intro.finished.connect(func() -> void: done[0] = true)
	await _frames(60 * 5)
	_check(done[0] and not intro.is_playing, "finita entro 5 s")
	_check(pause.get(&"enabled") == true, "pausa riattivata alla fine")
	_check(intro.logo().is_complete(), "logo completo alla fine")
	intro.queue_free()
	await _frames(1)


## Un tasto a meta la chiude prima; un secondo tasto non la chiude due volte.
func _test_skip_on_input() -> void:
	var intro := IntroScene.instantiate() as BootIntro
	intro.force_play = true
	intro.change_scene_on_finish = false
	root.add_child(intro)
	await _frames(30)
	var count := [0]
	intro.finished.connect(func() -> void: count[0] += 1)
	intro.skip()
	intro.skip()
	await _frames(60)
	_check(count[0] == 1 and not intro.is_playing, "salto: una sola fine (%d)" % count[0])
	_check(intro.logo().is_complete(), "il salto mostra il logo completo")
	intro.queue_free()
	await _frames(1)


## Quando l'intro passa la mano al menu, la pausa resta disattivata finche il menu non
## la gestisce da solo: altrimenti un Esc nel frame del cambio scena apre il pannello
## di pausa sopra il menu.
func _test_handoff_keeps_pause_disabled() -> void:
	var intro := IntroScene.instantiate() as BootIntro
	intro.force_play = true
	intro.change_scene_on_finish = true
	root.add_child(intro)
	await _frames(5)
	var pause := root.get_node("PauseMenu")
	var enabled_at_finish := [true]
	intro.finished.connect(func() -> void: enabled_at_finish[0] = pause.get(&"enabled"))
	intro.skip()
	await _frames(60)
	_check(not enabled_at_finish[0], "alla fine dell'intro con cambio scena la pausa e ancora disattivata")
	await _frames(3)
	_check(root.get_node_or_null("PauseMenu/%Overlay") != null and not (root.get_node("PauseMenu/%Overlay") as Control).visible, "nessun pannello di pausa aperto dopo il cambio scena")
	if is_instance_valid(intro):
		intro.queue_free()
	await _frames(1)


## La dissolvenza finale arriva al colore di fondo del tema (non a BG moltiplicato per
## se stesso) e i suoni sono sintetizzati prima che parta l'animazione.
func _test_fade_and_sounds() -> void:
	var intro := IntroScene.instantiate() as BootIntro
	intro.force_play = true
	intro.change_scene_on_finish = false
	root.add_child(intro)
	await _frames(2)
	_check(intro.prebuilt_sound_count() == 4, "quattro suoni pronti prima del tween (%d)" % intro.prebuilt_sound_count())
	_check(intro.fade_alpha() == 0.0, "all'inizio nessuna dissolvenza")
	intro.skip()
	await _frames(60)
	_check(intro.fade_alpha() >= 0.999 and intro.modulate == Color.WHITE, "alla fine il velo BG e opaco e la modulazione e intatta (alpha %.2f)" % intro.fade_alpha())
	intro.queue_free()
	await _frames(1)


## Un tasto vero (Esc) a meta intro la chiude: passa dalla pausa disattivata fino a
## `_unhandled_input`.
func _test_skip_by_key() -> void:
	var intro := IntroScene.instantiate() as BootIntro
	intro.force_play = true
	intro.change_scene_on_finish = false
	root.add_child(intro)
	await _frames(30)
	var done := [false]
	intro.finished.connect(func() -> void: done[0] = true)
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_ESCAPE
		event.keycode = KEY_ESCAPE
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)
	await _frames(60)
	_check(done[0] and not intro.is_playing, "Esc salta l'intro")
	_check(not root.get_node("PauseMenu").call(&"is_open"), "Esc durante l'intro non apre la pausa")
	intro.queue_free()
	await _frames(1)


## Aggancio della vignetta: una scena che emette `finished` gia nel proprio _ready non
## blocca l'intro; una scena senza il segnale viene saltata con un avviso.
func _test_vignette_hook() -> void:
	var instant := GDScript.new()
	instant.source_code = "extends Node\nsignal finished\nfunc _ready() -> void:\n\tfinished.emit()\n"
	instant.reload()
	for variant in ["instant", "no_signal"]:
		var node := Node.new()
		if variant == "instant":
			node.set_script(instant)
		var scene := PackedScene.new()
		scene.pack(node)
		node.free()
		var intro := IntroScene.instantiate() as BootIntro
		intro.force_play = true
		intro.change_scene_on_finish = false
		intro.vignette = scene
		root.add_child(intro)
		var done := [false]
		intro.finished.connect(func() -> void: done[0] = true)
		await _frames(60 * 5)
		_check(done[0] and intro.logo().is_complete(), "vignetta %s: l'intro arriva alla fine" % variant)
		intro.queue_free()
		await _frames(1)
