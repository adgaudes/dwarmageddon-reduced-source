class_name WorkshopPanel
extends CanvasLayer
## Officina (D-049): fra un livello e l'altro si spendono i rottami portati fuori
## in upgrade permanenti. Si apre dalla schermata di fine livello, a gioco fermo;
## controller (croce o stick, A compra, B torna) e mouse o tastiera. Schede per sezione
## (D-092, come le Impostazioni di D-091): Comune, una per classe e il Ricettario delle
## fusioni, che sotto le fusioni delle armi mostra le combinazioni delle macchine (D-093);
## LB/RB o PagSu/PagGiu cambiano scheda.

signal closed
signal purchased(id: StringName)
## Acquisto impossibile: rottami insufficienti o upgrade al massimo.
signal rejected(id: StringName)

## Titoli delle schede: le sezioni di PermanentCatalog.GROUPS nello stesso ordine, poi il ricettario.
const TAB_NAMES: Array[String] = ["Comune", "Ingegnere", "Guastatore", "Meccanico", "Erbacciaia", "Ricettario"]
const CARD_SIZE := Vector2(320, 66)
const CARD_GAP := 8

var is_open := false
var current_tab := 0
var _profile: PlayerProfileService
var _overlay: ColorRect
var _scrap_label: Label
var _buttons: Dictionary[StringName, Button] = {}
var _recipe_buttons: Dictionary[StringName, Button] = {}
var _combo_buttons: Dictionary[StringName, Button] = {}
## Sezione delle combinazioni sotto la griglia del Ricettario: visibile con quella.
var _combos_box: VBoxContainer
var _recipe_grid: GridContainer
var _tab_buttons: Array[Button] = []
## Una griglia di carte per scheda, nell'ordine di TAB_NAMES.
var _tab_grids: Array[GridContainer] = []

const INK := Color("3b2718")
const INK_GREEN := Color("3f7a2a")
const INK_RED := Color("a8321e")
const INK_MUTED := Color("3b271899")
var _back: Button
var _dots: Dictionary[StringName, LevelDots] = {}
var _detail_id: StringName = &""
var _detail_icon: UiIcon
var _detail_name: Label
var _detail_text: Label
var _detail_level: Label
var _detail_price: Label


func _ready() -> void:
	layer = 96
	process_mode = Node.PROCESS_MODE_ALWAYS
	_profile = get_node_or_null(^"/root/PlayerProfile") as PlayerProfileService
	# Fondo opaco (playtest O-13): prima la schermata di fine livello trapelava dietro.
	_overlay = ColorRect.new()
	_overlay.color = UiPalette.BG
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var column := VBoxContainer.new()
	# Larga quanto la carta di sblocco piu lunga a due colonne: cambiando scheda non si allarga.
	column.custom_minimum_size = Vector2(1200, 0)
	column.add_theme_constant_override(&"separation", 10)
	center.add_child(column)
	# Testata: titolo a sinistra, totale dei rottami a destra.
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 8)
	column.add_child(header)
	var title := Label.new()
	title.text = "OFFICINA"
	title.theme_type_variation = &"TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var scrap_icon := UiIcon.make(&"scrap", 28.0, UiPalette.SCRAP)
	scrap_icon.name = "ScrapIcon"
	scrap_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(scrap_icon)
	_scrap_label = Label.new()
	_scrap_label.theme_type_variation = &"ScrapLabel"
	_scrap_label.add_theme_font_size_override(&"font_size", 26)
	_scrap_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_scrap_label)
	var intro := Label.new()
	intro.theme_type_variation = &"MutedLabel"
	intro.text = "I rottami che porti fuori dai livelli restano qui: spendili in migliorie che valgono per tutte le run."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(intro)
	column.add_child(_make_tab_bar())
	# Corpo: a sinistra le carte della scheda, a destra il dettaglio della carta col fuoco.
	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 18)
	column.add_child(body)
	var cards := VBoxContainer.new()
	cards.name = "Cards"
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(cards)
	for group: Array in PermanentCatalog.GROUPS:
		var grid := _make_grid(cards, "Grid_%s" % group[0])
		for entry in PermanentCatalog.all():
			if entry.get("group", &"common") == group[0]:
				grid.add_child(_make_card(entry))
	_recipe_grid = _make_grid(cards, "Grid_recipes")
	for id in PermanentCatalog.RECIPES:
		_recipe_grid.add_child(_make_recipe_card(id))
	_make_combos(cards)
	# Altezza della scheda piu lunga: cambiando scheda il pannello non salta su e giu. Il
	# Ricettario conta anche la sezione delle combinazioni.
	var most := 0.0
	for grid in _tab_grids:
		var height := _grid_height(grid.get_child_count())
		if grid == _recipe_grid:
			height += cards.get_theme_constant(&"separation") + _combos_box.get_combined_minimum_size().y
		most = maxf(most, height)
	cards.custom_minimum_size = Vector2(0, most)
	body.add_child(_make_detail())
	_back = Button.new()
	_back.text = "Torna"
	_back.theme_type_variation = &"MainButton"
	_back.custom_minimum_size = Vector2(0, 50)
	_back.pressed.connect(close)
	column.add_child(_back)
	column.add_child(ButtonPrompts.create([[&"ui_accept", "Compra"], [&"ui_cancel", "Torna"]]))
	_overlay.hide()
	if _profile != null:
		# Una ricetta scoperta o un acquisto altrove si vedono subito anche a pannello aperto.
		_profile.changed.connect(_refresh)


## Barra delle schede: pulsanti a interruttore come nelle Impostazioni (D-091).
func _make_tab_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.name = "Tabs"
	bar.add_theme_constant_override(&"separation", 6)
	var group := ButtonGroup.new()
	for i in TAB_NAMES.size():
		var tab := Button.new()
		tab.name = "Tab%d" % i
		tab.text = TAB_NAMES[i]
		tab.theme_type_variation = &"MainButton"
		tab.toggle_mode = true
		tab.button_group = group
		tab.custom_minimum_size = Vector2(0, 46)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(show_tab.bind(i))
		bar.add_child(tab)
		_tab_buttons.append(tab)
	return bar


## Griglia di una scheda: entra in `_tab_grids`.
func _make_grid(parent: Control, grid_name: String) -> GridContainer:
	var grid := _new_grid(grid_name)
	parent.add_child(grid)
	_tab_grids.append(grid)
	return grid


func _new_grid(grid_name: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = grid_name
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", CARD_GAP)
	grid.add_theme_constant_override(&"v_separation", CARD_GAP)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return grid


## Altezza di [param count] carte su due colonne.
func _grid_height(count: int) -> float:
	var rows := ceili(count / 2.0)
	return rows * CARD_SIZE.y + maxi(rows - 1, 0) * CARD_GAP


## Sezione "Combinazioni delle macchine" sotto le fusioni: un'etichetta e una carta per
## combinazione. La croce in giu dall'ultima fusione porta alla prima combinazione.
func _make_combos(parent: Control) -> void:
	_combos_box = VBoxContainer.new()
	_combos_box.name = "Combos"
	_combos_box.add_theme_constant_override(&"separation", CARD_GAP)
	parent.add_child(_combos_box)
	var title := Label.new()
	title.name = "Title"
	title.text = "Combinazioni delle macchine"
	title.theme_type_variation = &"SectionLabel"
	_combos_box.add_child(title)
	var grid := _new_grid("Grid_combos")
	_combos_box.add_child(grid)
	for id in MachineCatalog.COMBOS:
		grid.add_child(_make_combo_card(id))
	var last_recipe := _recipe_grid.get_child(_recipe_grid.get_child_count() - 1) as Control
	last_recipe.focus_neighbor_bottom = last_recipe.get_path_to(grid.get_child(0))


## Carta vuota nello stile dell'Officina, con l'icona a sinistra; il dettaglio la segue.
func _card_button(id: StringName, icon_kind: StringName) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"CardButton"
	button.custom_minimum_size = CARD_SIZE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.set_meta(&"card_id", id)
	button.focus_entered.connect(func() -> void: _show_detail(id))
	button.mouse_entered.connect(func() -> void: _show_detail(id))
	# Il testo lascia lo spazio all'icona col margine dello stile, non con spazi iniziali.
	var theme := ThemeDB.get_project_theme()
	if theme != null:
		for state: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
			var box := theme.get_stylebox(state, &"CardButton")
			if box != null:
				box = box.duplicate()
				box.content_margin_left = 64.0
				box.content_margin_right = 52.0
				button.add_theme_stylebox_override(state, box)
	var icon := UiIcon.make(icon_kind, 36.0, UiPalette.BORDER)
	icon.name = "Icon"
	icon.outline = INK
	button.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 14)
	icon.grow_vertical = Control.GROW_DIRECTION_BOTH
	return button


## Carta di un upgrade: icona a sinistra (per gli sblocchi quella dell'arma), nome e
## livello, prezzo sotto, pallini in alto a destra.
func _make_card(entry: Dictionary) -> Button:
	var id: StringName = entry.id
	var button := _card_button(id, UiIcon.for_permanent(id))
	button.name = "Card_%s" % id
	button.pressed.connect(func() -> void: _on_pressed(id))
	_buttons[id] = button
	var dots := LevelDots.new()
	dots.name = "Dots"
	dots.total = (entry.costs as Array).size()
	button.add_child(dots)
	dots.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	dots.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_dots[id] = dots
	return button


## Carta del ricettario: si guarda, non si compra (premerla non fa nulla).
func _make_recipe_card(id: StringName) -> Button:
	var button := _card_button(id, &"lock")
	button.name = "Recipe_%s" % id
	_recipe_buttons[id] = button
	return button


## Nome della parte [param index] della fusione [param id].
func _part_name(id: StringName, index: int) -> String:
	var parts: Array = WeaponCatalog.find(id).get(&"parts", [])
	return WeaponCatalog.find(parts[index]).get(&"name", "?") if index < parts.size() else "?"


## "Chiodatrice + Picchetto sismico" se scoperta, "Chiodatrice + ?" se no.
func _recipe_parts(id: StringName, known: bool) -> String:
	return "%s + %s" % [_part_name(id, 0), _part_name(id, 1) if known else "?"]


func _recipe_known(id: StringName) -> bool:
	return _profile != null and _profile.has_recipe(id)


## Carta di una combinazione delle macchine: si guarda come le fusioni.
func _make_combo_card(id: StringName) -> Button:
	var button := _card_button(id, &"lock")
	button.name = "Combo_%s" % id
	_combo_buttons[id] = button
	return button


func _combo_known(id: StringName) -> bool:
	return _profile != null and _profile.has_combo(id)


## "Trivella + Calamita" se scoperta, "Trivella + ?" se no.
func _combo_parts(combo: Dictionary, known: bool) -> String:
	var parts: Array = combo.get(&"parts", [])
	if parts.size() < 2:
		return "?"
	return "%s + %s" % [MachineCatalog.name_of(parts[0]), MachineCatalog.name_of(parts[1]) if known else "?"]


## Icona del primo modulo se scoperta, il lucchetto se no.
func _combo_icon(combo: Dictionary, known: bool) -> StringName:
	var parts: Array = combo.get(&"parts", [])
	if not known or parts.is_empty():
		return &"lock"
	return MachineCatalog.find(parts[0]).get(&"icon", &"lock")


## Testo della carta della combinazione [param id]: "???\nTrivella + ?" da scoprire,
## "Estrattore\nTrivella + Calamita" scoperta.
func combo_text(id: StringName) -> String:
	var combo := MachineCatalog.find_combo(id)
	if combo.is_empty():
		return ""
	var known := _combo_known(id)
	return "%s\n%s" % [combo.name if known else "???", _combo_parts(combo, known)]


## Dettaglio: cosa fa l'upgrade, a che livello sei, quanto costa il prossimo.
func _make_detail() -> Control:
	var panel := PanelContainer.new()
	panel.name = "Detail"
	panel.custom_minimum_size = Vector2(360, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	panel.add_child(box)
	_detail_icon = UiIcon.make(&"scrap", 72.0, UiPalette.BORDER)
	_detail_icon.outline = INK
	_detail_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_detail_icon)
	_detail_name = Label.new()
	_detail_name.theme_type_variation = &"SectionLabel"
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_detail_name)
	_detail_text = Label.new()
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.custom_minimum_size = Vector2(320, 0)
	box.add_child(_detail_text)
	_detail_level = Label.new()
	_detail_level.theme_type_variation = &"MutedLabel"
	box.add_child(_detail_level)
	_detail_price = Label.new()
	_detail_price.theme_type_variation = &"ScrapLabel"
	_detail_price.add_theme_font_size_override(&"font_size", 22)
	_detail_price.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_detail_price)
	return panel


func _show_detail(id: StringName) -> void:
	_detail_id = id
	if _combo_buttons.has(id):
		_show_combo_detail(id)
		return
	if _recipe_buttons.has(id):
		_show_recipe_detail(id)
		return
	var entry := PermanentCatalog.find(id)
	if entry.is_empty() or _profile == null:
		return
	_detail_icon.kind = UiIcon.for_permanent(id)
	_detail_name.text = entry.name
	_detail_text.text = entry.text
	var level := _profile.level_of(id)
	_detail_level.text = "Livello %d di %d" % [level, (entry.costs as Array).size()]
	var cost := _profile.cost_of(id)
	if cost < 0:
		_detail_price.text = "Al massimo"
		_detail_price.add_theme_color_override(&"font_color", Color("8fcf5f"))
	elif _profile.scrap >= cost:
		_detail_price.text = "Prossimo livello: %d rottami" % cost
		_detail_price.remove_theme_color_override(&"font_color")
	else:
		_detail_price.text = "Prossimo livello: %d rottami\nNe mancano %d" % [cost, cost - _profile.scrap]
		_detail_price.add_theme_color_override(&"font_color", Color("e0603f"))


## Dettaglio di una fusione: le stesse cose della carta, piu il testo se e scoperta.
func _show_recipe_detail(id: StringName) -> void:
	var known := _recipe_known(id)
	var fusion := WeaponCatalog.find(id)
	_detail_icon.kind = fusion.get(&"icon", &"scrap") if known else &"lock"
	_detail_name.text = fusion.get(&"name", "") if known else "???"
	if known:
		_detail_text.text = "%s\n\n%s" % [_recipe_parts(id, true), fusion.get(&"text", "")]
	else:
		_detail_text.text = "%s\n\nSi scopre la prima volta che fai questa fusione in partita." % _recipe_parts(id, false)
	_detail_level.text = "Fusione scoperta" if known else "Fusione da scoprire"
	_detail_price.text = ""
	_detail_price.remove_theme_color_override(&"font_color")


## Dettaglio di una combinazione delle macchine: come quello delle fusioni.
func _show_combo_detail(id: StringName) -> void:
	var combo := MachineCatalog.find_combo(id)
	var known := _combo_known(id)
	_detail_icon.kind = _combo_icon(combo, known)
	_detail_name.text = combo.get(&"name", "") if known else "???"
	if known:
		_detail_text.text = "%s\n\n%s" % [_combo_parts(combo, true), combo.get(&"text", "")]
	else:
		_detail_text.text = "%s\n\nSi scopre la prima volta che fondi queste due macchine in partita." % _combo_parts(combo, false)
	_detail_level.text = "Combinazione scoperta" if known else "Combinazione da scoprire"
	_detail_price.text = ""
	_detail_price.remove_theme_color_override(&"font_color")


func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## LB/RB e PagSu/PagGiu cambiano scheda e portano il fuoco sulla sua prima carta.
func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	var step := 0
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			step = -1
		elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			step = 1
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_PAGEUP:
			step = -1
		elif event.keycode == KEY_PAGEDOWN:
			step = 1
	if step != 0:
		get_viewport().set_input_as_handled()
		show_tab(posmod(current_tab + step, TAB_NAMES.size()))
		_focus_first_card()


## Mostra le carte della scheda [param index] e nasconde le altre; il dettaglio passa
## alla prima carta. Se il fuoco era su una carta ora nascosta, va sulla prima.
func show_tab(index: int) -> void:
	current_tab = clampi(index, 0, TAB_NAMES.size() - 1)
	for i in _tab_grids.size():
		_tab_grids[i].visible = i == current_tab
	_combos_box.visible = _recipe_grid.visible
	# Senza segnale il ButtonGroup non spegne le altre schede: si spengono qui.
	for i in _tab_buttons.size():
		_tab_buttons[i].set_pressed_no_signal(i == current_tab)
	var first := _first_card()
	if first != null:
		_show_detail(first.get_meta(&"card_id"))
	if is_open:
		var focus := get_viewport().gui_get_focus_owner()
		if focus == null or not focus.is_visible_in_tree():
			_focus_first_card()


func _first_card() -> Button:
	var grid := _tab_grids[current_tab]
	return grid.get_child(0) as Button if grid.get_child_count() > 0 else null


func _focus_first_card() -> void:
	var first := _first_card()
	if first != null:
		first.grab_focus()
		_show_detail(first.get_meta(&"card_id"))


## Scheda della classe [param class_id], o quella Comune.
func _tab_of_class(class_id: StringName) -> int:
	for i in PermanentCatalog.GROUPS.size():
		if PermanentCatalog.GROUPS[i][0] == class_id:
			return i
	return 0


func open() -> void:
	if _profile == null:
		return
	is_open = true
	_refresh()
	_overlay.show()
	var fx := get_node_or_null(^"/root/UiFx") as UiFxService
	if fx != null:
		fx.pop_in(_overlay.get_child(0))
	# Si parte dalla scheda della classe giocata per ultima.
	show_tab(_tab_of_class(_profile.last_class))
	_focus_first_card()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_overlay.hide()
	var fx := get_node_or_null(^"/root/UiFx") as UiFxService
	if fx != null:
		fx.play(&"ui_back")
	closed.emit()


## Compra come se la riga fosse premuta (test e automazione).
func press(id: StringName) -> void:
	if is_open and _buttons.has(id):
		_buttons[id].pressed.emit()


func row_text(id: StringName) -> String:
	return _buttons[id].text if _buttons.has(id) else ""


func row_dots(id: StringName) -> LevelDots:
	return _dots.get(id)


## Testo della carta del ricettario [param id] (test e automazione).
func recipe_text(id: StringName) -> String:
	return _recipe_buttons[id].text if _recipe_buttons.has(id) else ""


func _on_pressed(id: StringName) -> void:
	if not is_open:
		return
	if _profile.buy(id):
		purchased.emit(id)
	else:
		rejected.emit(id)
	_refresh()


func _refresh() -> void:
	_scrap_label.text = "Rottami: %d" % _profile.scrap
	for entry in PermanentCatalog.all():
		var id: StringName = entry.id
		var level := _profile.level_of(id)
		var cost := _profile.cost_of(id)
		var price := "Al massimo"
		var color := INK_GREEN
		if cost >= 0 and _profile.scrap >= cost:
			price = "%d rottami" % cost
			color = INK
		elif cost >= 0:
			price = "%d rottami, ne mancano %d" % [cost, cost - _profile.scrap]
			color = INK_RED
		var button := _buttons[id]
		button.text = "%s  %d/%d\n%s" % [entry.name, level, (entry.costs as Array).size(), price]
		_dots[id].filled = level
		_set_ink(button, color)
	for id in PermanentCatalog.RECIPES:
		var known := _recipe_known(id)
		var fusion := WeaponCatalog.find(id)
		var button := _recipe_buttons[id]
		button.text = "%s\n%s" % [fusion.get(&"name", "") if known else "???", _recipe_parts(id, known)]
		(button.get_node(^"Icon") as UiIcon).kind = fusion.get(&"icon", &"scrap") if known else &"lock"
		_set_ink(button, INK if known else INK_MUTED)
	for id in MachineCatalog.COMBOS:
		var known := _combo_known(id)
		var button := _combo_buttons[id]
		button.text = combo_text(id)
		(button.get_node(^"Icon") as UiIcon).kind = _combo_icon(MachineCatalog.find_combo(id), known)
		_set_ink(button, INK if known else INK_MUTED)
	if _detail_id != &"":
		_show_detail(_detail_id)


func _set_ink(button: Button, color: Color) -> void:
	for state: StringName in [&"font_color", &"font_focus_color", &"font_hover_color", &"font_pressed_color"]:
		button.add_theme_color_override(state, color)


## Pallini del livello di un upgrade permanente: pieni di rame quelli comprati.
class LevelDots extends Control:
	const RADIUS := 5.0
	const GAP := 6.0
	var total := 1:
		set(value):
			total = value
			custom_minimum_size = Vector2(total * (RADIUS * 2.0 + GAP), RADIUS * 2.0)
			queue_redraw()
	var filled := 0:
		set(value):
			filled = value
			queue_redraw()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in total:
			var center := Vector2(i * (RADIUS * 2.0 + GAP) + RADIUS, size.y * 0.5)
			draw_circle(center, RADIUS, UiPalette.BORDER if i < filled else Color(UiPalette.BORDER, 0.25))
			draw_arc(center, RADIUS, 0.0, TAU, 16, Color("3b2718"), 1.5)
