class_name FusionBench
extends CanvasLayer
## Banco di fusione (D-093, piano B): sulla pedana aperta Interagisci ferma il gioco e apre il
## banco. Due schede: Fondi (prima la macchina base, poi quella che entra: scelta 2) e Sgancia
## (prima la macchina, poi il modulo). L'anteprima segue la carta col focus: taglia, vita,
## velocita, combinazioni ("???" per quelle mai viste) e costo in rottami dei Cassoni.
## Controller prima (A sceglie, B indietro, croce o stick, LB/RB cambiano scheda), con Invio,
## Esc, frecce, PagSu/PagGiu e mouse come equivalenti. Si apre solo da `ArenaRun` a fine passo;
## per `INPUT_GRACE_SECONDS` non accetta A ne B: la pressione di X che lo apre non sceglie nulla.

signal opened
signal closed

enum Mode { FUSE, DETACH }
enum Step { PICK_FIRST, PICK_SECOND }

const INPUT_GRACE_SECONDS := 0.4
const MODE_NAMES: Array[String] = ["Fondi", "Sgancia"]
const COLUMNS := 3
const CARD_SIZE := Vector2(250, 78)
const PREVIEW_SIZE := Vector2(0, 150)
const SHORT_OF_SCRAP := "Rottami insufficienti nei Cassoni"
const INK_WARNING := Color("e0603f")
const INK_NOTICE := Color("3f7a2a")

var is_open := false
var caravan: Caravan
## StringName -> bool: la combinazione e gia stata scoperta (di serie nessuna; il profilo dal task 7).
var combo_known: Callable = func(_id: StringName) -> bool: return false
var mode := Mode.FUSE
var step := Step.PICK_FIRST

## Macchina scelta al primo passo (indice in `caravan.machines`), -1 al primo passo.
var _first := -1
var _grace_left := 0.0
var _overlay: ColorRect
var _panel: PanelContainer
var _title: Label
var _scrap_label: Label
var _tab_buttons: Array[Button] = []
var _hint: Label
var _grid: GridContainer
var _cards: Array[Button] = []
var _preview: Label
var _message: Label


func _ready() -> void:
	layer = 92
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_overlay = ColorRect.new()
	_overlay.color = Color(UiPalette.BG, 0.82)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	center.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	_panel.add_child(column)
	# Testata: titolo a sinistra, rottami dei Cassoni a destra.
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 8)
	column.add_child(header)
	_title = Label.new()
	_title.text = "BANCO DI FUSIONE"
	_title.theme_type_variation = &"TitleLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var scrap_icon := UiIcon.make(&"scrap", 28.0, UiPalette.SCRAP)
	scrap_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(scrap_icon)
	_scrap_label = Label.new()
	_scrap_label.theme_type_variation = &"ScrapLabel"
	_scrap_label.add_theme_font_size_override(&"font_size", 24)
	_scrap_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_scrap_label)
	column.add_child(_make_tab_bar())
	_hint = Label.new()
	_hint.theme_type_variation = &"MutedLabel"
	column.add_child(_hint)
	_grid = GridContainer.new()
	_grid.name = "Cards"
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override(&"h_separation", 8)
	_grid.add_theme_constant_override(&"v_separation", 8)
	column.add_child(_grid)
	_preview = Label.new()
	_preview.name = "Preview"
	_preview.custom_minimum_size = PREVIEW_SIZE
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_preview)
	_message = Label.new()
	_message.add_theme_color_override(&"font_color", INK_WARNING)
	column.add_child(_message)
	column.add_child(ButtonPrompts.create([[&"ui_accept", "Scegli"], [&"ui_cancel", "Indietro"]]))
	_overlay.hide()


## Schede a interruttore come nell'Officina: si cambiano con LB/RB, PagSu/PagGiu o col mouse.
## Niente focus: croce e stick restano sulle carte.
func _make_tab_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.name = "Tabs"
	bar.add_theme_constant_override(&"separation", 6)
	var group := ButtonGroup.new()
	for i in MODE_NAMES.size():
		var tab := Button.new()
		tab.name = "Tab%d" % i
		tab.text = MODE_NAMES[i]
		tab.theme_type_variation = &"MainButton"
		tab.toggle_mode = true
		tab.button_group = group
		tab.focus_mode = Control.FOCUS_NONE
		tab.custom_minimum_size = Vector2(0, 46)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(func() -> void: set_mode(i as Mode))
		bar.add_child(tab)
		_tab_buttons.append(tab)
	return bar


## Ferma il gioco sulla scheda Fondi; il focus arriva sulla prima carta sceglibile dopo la grazia.
func open(target: Caravan) -> void:
	if is_open or target == null:
		return
	caravan = target
	is_open = true
	mode = Mode.FUSE
	_reset_step()
	_message.text = ""
	_rebuild()
	get_viewport().gui_release_focus()
	_overlay.show()
	get_tree().paused = true
	_grace_left = INPUT_GRACE_SECONDS
	set_process(true)
	var fx := get_node_or_null(^"/root/UiFx") as UiFxService
	if fx != null:
		fx.pop_in(_panel)
	print("PROTOTYPE01_FUSION_BENCH_OPENED machines=%d" % caravan.machines.size())
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	set_process(false)
	_overlay.hide()
	get_viewport().gui_release_focus()
	get_tree().paused = false
	print("PROTOTYPE01_FUSION_BENCH_CLOSED")
	closed.emit()


## Cambia scheda e torna al primo passo, col focus sulla prima carta sceglibile.
func set_mode(next: Mode) -> void:
	if not is_open:
		return
	mode = next
	_reset_step()
	_message.text = ""
	_rebuild()
	_focus_default()


## Come premere la carta [param index]: al primo passo la sceglie, al secondo conferma.
func select(index: int) -> void:
	if not is_open or index < 0 or index >= _cards.size() or _cards[index].disabled:
		return
	if step == Step.PICK_FIRST:
		_first = index
		step = Step.PICK_SECOND
		_message.text = ""
		_rebuild()
		# Fondi: il focus resta sulla base (la croce va sulle altre); Sgancia: sul primo modulo.
		_focus_card(index if mode == Mode.FUSE else 0)
	elif mode == Mode.FUSE:
		fuse(_first, index)
	else:
		detach(_first, index)


## Dal secondo passo al primo (focus sulla macchina scelta); dal primo chiude.
func back() -> void:
	if not is_open:
		return
	if step == Step.PICK_FIRST:
		close()
		return
	var chosen := _first
	_reset_step()
	_message.text = ""
	_rebuild()
	_focus_card(chosen)


## Fonde la macchina [param other_index] nella [param base_index] (stessa via della conferma).
## Falso, senza effetti, se la carovana non lo permette; coi soli rottami mancanti lo dice.
func fuse(base_index: int, other_index: int) -> bool:
	if not is_open or not _is_machine(base_index) or not _is_machine(other_index):
		return false
	var base := caravan.machines[base_index]
	var other := caravan.machines[other_index]
	if not caravan.fuse(base, other):
		var fits := base != other and not base.is_broken() and not other.is_broken() \
			and base.modules.size() + other.modules.size() <= caravan.tuning.max_modules_per_machine
		_set_message(SHORT_OF_SCRAP if fits else "", INK_WARNING)
		return false
	_after_change("Fusione fatta: %s" % _machine_title(base))
	return true


## Sgancia il modulo [param module_index] della macchina [param machine_index] (stessa via della
## conferma). Falso, senza effetti, se la carovana non lo permette.
func detach(machine_index: int, module_index: int) -> bool:
	if not is_open or not _is_machine(machine_index):
		return false
	var machine := caravan.machines[machine_index]
	var fits := not machine.is_broken() and machine.modules.size() >= 2 \
		and module_index >= 0 and module_index < machine.modules.size()
	var module_name := MachineCatalog.name_of(machine.modules[module_index].module_id) if fits else ""
	if caravan.detach(machine, module_index) == null:
		_set_message(SHORT_OF_SCRAP if fits else "", INK_WARNING)
		return false
	_after_change("Sganciato: %s" % module_name)
	return true


func card_count() -> int:
	return _cards.size()


func card(index: int) -> Button:
	return _cards[index]


func card_text(index: int) -> String:
	return _cards[index].text


func preview_text() -> String:
	return _preview.text


func message_text() -> String:
	return _message.text


func title_text() -> String:
	return _title.text


func scrap_text() -> String:
	return _scrap_label.text


func _process(delta: float) -> void:
	if _grace_left <= 0.0:
		set_process(false)
		return
	_grace_left -= delta
	if _grace_left <= 0.0:
		set_process(false)
		var focus := get_viewport().gui_get_focus_owner()
		if focus == null or not _cards.has(focus):
			_focus_default()


func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _grace_left <= 0.0:
			back()


## LB/RB e PagSu/PagGiu passano all'altra scheda (dopo la grazia, come le carte).
func _unhandled_input(event: InputEvent) -> void:
	if not is_open or _grace_left > 0.0:
		return
	var step_by := 0
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			step_by = -1
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			step_by = 1
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_PAGEUP:
			step_by = -1
		elif event.keycode == KEY_PAGEDOWN:
			step_by = 1
	if step_by != 0:
		get_viewport().set_input_as_handled()
		set_mode(posmod(mode + step_by, MODE_NAMES.size()) as Mode)


func _reset_step() -> void:
	step = Step.PICK_FIRST
	_first = -1


func _is_machine(index: int) -> bool:
	return caravan != null and index >= 0 and index < caravan.machines.size()


## Dopo una conferma: primo passo della stessa scheda, carte rifatte, focus sulla prima sceglibile.
## L'esito riuscito e in verde, non nel rosso degli avvisi.
func _after_change(message: String) -> void:
	_reset_step()
	_rebuild()
	_set_message(message, INK_NOTICE)
	_focus_default()


func _set_message(text: String, ink: Color) -> void:
	_message.text = text
	_message.add_theme_color_override(&"font_color", ink)


## Rifà schede, rottami, suggerimento e carte del passo; l'anteprima va alla carta predefinita.
func _rebuild() -> void:
	for i in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(i == mode)
	_scrap_label.text = "Nei Cassoni: %d" % caravan.working_carried()
	for button in _cards:
		# Tolte subito dall'albero: le carte vecchie non restano un frame accanto alle nuove.
		_grid.remove_child(button)
		button.queue_free()
	_cards.clear()
	if step == Step.PICK_FIRST:
		_hint.text = "Scegli la macchina base: tiene posto e nome" if mode == Mode.FUSE else "Scegli la macchina da cui sganciare un modulo"
		for i in caravan.machines.size():
			var machine := caravan.machines[i]
			var reason := ""
			if machine.is_broken():
				reason = "GUASTA"
			elif mode == Mode.DETACH and machine.modules.size() < 2:
				reason = "Un modulo solo"
			_add_card(_machine_card_text(machine, reason), not reason.is_empty())
	elif mode == Mode.FUSE:
		_hint.text = "Scegli la macchina che entra nella base"
		var base := caravan.machines[_first]
		for i in caravan.machines.size():
			var machine := caravan.machines[i]
			var reason := ""
			if i == _first:
				reason = "BASE"
			elif machine.is_broken():
				reason = "GUASTA"
			elif base.modules.size() + machine.modules.size() > caravan.tuning.max_modules_per_machine:
				reason = "Troppi moduli"
			_add_card(_machine_card_text(machine, reason), not reason.is_empty())
	else:
		_hint.text = "Scegli il modulo da sganciare"
		var ids := caravan.machines[_first].module_ids()
		for i in ids.size():
			_add_card("%s\nModulo %d di %d" % [MachineCatalog.name_of(ids[i]), i + 1, ids.size()], false)
	# Croce e frecce a sinistra e a destra scorrono le carte in fila e girano in fondo.
	for i in _cards.size():
		var left := _cards[(i - 1 + _cards.size()) % _cards.size()]
		var right := _cards[(i + 1) % _cards.size()]
		_cards[i].focus_neighbor_left = _cards[i].get_path_to(left)
		_cards[i].focus_neighbor_right = _cards[i].get_path_to(right)
	_show_preview(_default_card())


func _add_card(text: String, disabled: bool) -> void:
	var button := Button.new()
	button.theme_type_variation = &"CardButton"
	button.custom_minimum_size = CARD_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.text = text
	button.disabled = disabled
	var index := _cards.size()
	button.pressed.connect(func() -> void: _on_card_pressed(index))
	button.focus_entered.connect(func() -> void: _show_preview(index))
	# Il mouse porta il focus: l'anteprima segue sempre la carta col focus.
	button.mouse_entered.connect(func() -> void:
		if is_open and _grace_left <= 0.0:
			button.grab_focus())
	_grid.add_child(button)
	_cards.append(button)


func _on_card_pressed(index: int) -> void:
	if _grace_left > 0.0:
		return
	select(index)


## La prima carta sceglibile, altrimenti la prima; -1 senza carte.
func _default_card() -> int:
	for i in _cards.size():
		if not _cards[i].disabled:
			return i
	return 0 if not _cards.is_empty() else -1


func _focus_default() -> void:
	_focus_card(_default_card())


func _focus_card(index: int) -> void:
	if index >= 0 and index < _cards.size():
		_cards[index].grab_focus()
		_show_preview(index)


## "<Taglia> - Cassone + Torretta", "PV a/b" e il motivo per cui non si sceglie.
func _machine_card_text(machine: Machine, reason: String) -> String:
	var text := "%s\nPV %d/%d" % [_machine_title(machine), machine.health, machine.max_health]
	return text if reason.is_empty() else "%s\n%s" % [text, reason]


func _machine_title(machine: Machine) -> String:
	return "%s - %s" % [MachineFusion.SIZE_NAMES[machine.size], _module_names(machine.module_ids())]


func _module_names(ids: Array[StringName]) -> String:
	var names: PackedStringArray = []
	for id in ids:
		names.append(MachineCatalog.name_of(id))
	return " + ".join(names)


# --- Anteprima ----------------------------------------------------------------------------------

func _show_preview(index: int) -> void:
	if not is_open or index < 0 or index >= _cards.size():
		_preview.text = ""
		return
	var lines: PackedStringArray = []
	if step == Step.PICK_FIRST:
		var machine := caravan.machines[index]
		if machine.is_broken():
			lines.append("GUASTA: riparala prima di usarla al banco")
		elif mode == Mode.DETACH and machine.modules.size() < 2:
			lines.append("Un modulo solo: niente da sganciare")
		lines.append(_stats_line(machine.health, machine.max_health, machine.modules.size()))
		lines.append("Combinazioni: %s" % _combo_names(machine.combos(), []))
	elif mode == Mode.FUSE:
		var base := caravan.machines[_first]
		var other := caravan.machines[index]
		if index == _first:
			lines.append("Base: %s" % _machine_title(base))
			lines.append("Scegli la macchina che entra")
		elif other.is_broken():
			lines.append("GUASTA: riparala prima di fonderla")
		else:
			var result := MachineFusion.preview_fuse(base.module_ids(), base.health, base.max_health,
				other.module_ids(), other.health, other.max_health, caravan.tuning)
			if not result.allowed:
				lines.append("Troppi moduli: al massimo %d per macchina" % caravan.tuning.max_modules_per_machine)
			else:
				var n: int = (result.modules as Array).size()
				lines.append(_becomes_line(result.size, n))
				lines.append(_stats_line(result.health, result.max_health, n))
				lines.append("Combinazioni: %s" % _combo_names(result.combos, result.new_combos))
				lines.append(_cost_line(result.cost))
	else:
		var machine := caravan.machines[_first]
		var result := MachineFusion.preview_detach(machine.module_ids(), index, machine.health, machine.max_health, caravan.tuning)
		var source: Dictionary = result.source
		var detached: Dictionary = result.detached
		var n: int = (source.modules as Array).size()
		lines.append(_becomes_line(source.size, n))
		lines.append(_stats_line(source.health, source.max_health, n))
		lines.append("Si stacca: %s - %s, PV %d/%d" % [MachineFusion.SIZE_NAMES[detached.size],
			_module_names(detached.modules), detached.health, detached.max_health])
		if not (result.lost_combos as Array).is_empty():
			lines.append("Combinazioni perse: %s" % _combo_names(result.lost_combos, []))
		lines.append(_cost_line(result.cost))
	_preview.text = "\n".join(lines)


func _becomes_line(size: int, modules: int) -> String:
	return "Diventa: %s (%d %s)" % [MachineFusion.SIZE_NAMES[size], modules, "modulo" if modules == 1 else "moduli"]


## "PV 11/15  Velocita 4,5 m/s" (virgola decimale).
func _stats_line(health: int, max_health: int, modules: int) -> String:
	var speed := caravan.tuning.max_speed * MachineFusion.speed_factor_of(modules, caravan.tuning)
	return "PV %d/%d  Velocita %s m/s" % [health, max_health, ("%.1f" % speed).replace(".", ",")]


func _cost_line(cost: int) -> String:
	return "Costo: %d %s (nei Cassoni: %d)" % [cost, "rottame" if cost == 1 else "rottami", caravan.working_carried()]


## Nomi delle combinazioni: "???" per quelle mai viste, "(nuova)" per quelle che nascono qui.
func _combo_names(combos: Array, new_combos: Array) -> String:
	if combos.is_empty():
		return "nessuna"
	var names: PackedStringArray = []
	for id: StringName in combos:
		if not combo_known.call(id):
			names.append("???")
		elif new_combos.has(id):
			names.append("%s (nuova)" % MachineCatalog.find_combo(id).get(&"name", ""))
		else:
			names.append(String(MachineCatalog.find_combo(id).get(&"name", "")))
	return ", ".join(names)
