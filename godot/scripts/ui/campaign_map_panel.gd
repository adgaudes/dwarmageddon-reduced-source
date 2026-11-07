class_name CampaignMapPanel
extends CanvasLayer
## Mappa di campagna (D-040, D-066): i livelli in fila, da sinistra a destra, con il
## loro stato (completato, sbloccato, bloccato, in costruzione). Si apre dal menu
## iniziale con "Gioca": si sceglie un livello sbloccato, A conferma e B torna.
## Dopo il livello si sceglie la classe (D-092, spec par. 6.1): quattro carte col colore
## di classe sul bordo, fuoco sull'ultima scelta del profilo; B torna ai livelli.
## `level_chosen` parte solo dopo la classe. Controller (croce o stick), tastiera e mouse.

signal closed
signal level_chosen(id: StringName)


var is_open := false
## Vero mentre al posto dei livelli ci sono le quattro classi.
var choosing_class := false
var _profile: PlayerProfileService
var _overlay: ColorRect
var _title: Label
var _row: HBoxContainer
var _buttons: Dictionary[StringName, Button] = {}
var _detail: Label
var _back: Button
var _marks: Dictionary[StringName, UiIcon] = {}
var _badges: Dictionary[StringName, Label] = {}
var _class_row: HBoxContainer
var _class_buttons: Dictionary[StringName, Button] = {}
var _level_prompts: ButtonPrompts
var _class_prompts: ButtonPrompts
var _chosen_level: StringName = &""

const INK := Color("3b2718")
const INK_GREEN := Color("3f7a2a")
const INK_LOCKED := Color("8a7a66")


func _ready() -> void:
	layer = 96
	process_mode = Node.PROCESS_MODE_ALWAYS
	_profile = get_node_or_null(^"/root/PlayerProfile") as PlayerProfileService
	_overlay = ColorRect.new()
	_overlay.color = Color(UiPalette.BG, 0.94)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(900, 0)
	column.add_theme_constant_override(&"separation", 18)
	center.add_child(column)
	_title = Label.new()
	_title.text = "PRIMA CAMPAGNA"
	_title.theme_type_variation = &"TitleLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override(&"separation", 24)
	column.add_child(_row)
	for i in LevelCatalog.count():
		var entry: Dictionary = LevelCatalog.all()[i]
		var id: StringName = entry.id
		if i > 0:
			# Linea rame che collega le carte, centrata in verticale.
			var link := ColorRect.new()
			link.color = UiPalette.BORDER
			link.custom_minimum_size = Vector2(40, 3)
			link.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_row.add_child(link)
		var button := Button.new()
		button.theme_type_variation = &"CardButton"
		button.custom_minimum_size = Vector2(220, 140)
		button.add_theme_font_size_override(&"font_size", 18)
		button.pressed.connect(func() -> void: _on_pressed(id))
		button.focus_entered.connect(func() -> void: _show_detail(id))
		button.mouse_entered.connect(func() -> void: _show_detail(id))
		_row.add_child(button)
		_buttons[id] = button
		var mark := UiIcon.make(&"check", 26.0, UiPalette.BORDER)
		mark.name = "Mark"
		mark.outline = INK
		mark.visible = false
		button.add_child(mark)
		mark.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 8)
		mark.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_marks[id] = mark
		# Numero del livello in un cerchio di rame, in alto a sinistra.
		var badge := Label.new()
		badge.name = "Badge"
		badge.text = str(i + 1)
		badge.theme_type_variation = &"SectionLabel"
		badge.add_theme_font_size_override(&"font_size", 16)
		badge.add_theme_color_override(&"font_color", INK)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.custom_minimum_size = Vector2(28, 28)
		var circle := StyleBoxFlat.new()
		circle.bg_color = UiPalette.BORDER
		circle.border_color = INK
		circle.set_border_width_all(2)
		circle.set_corner_radius_all(14)
		badge.add_theme_stylebox_override(&"normal", circle)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(badge)
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 8)
		_badges[id] = badge
	# Le classi prendono il posto della riga dei livelli dopo la scelta del livello.
	_class_row = HBoxContainer.new()
	_class_row.name = "ClassRow"
	_class_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_class_row.add_theme_constant_override(&"separation", 20)
	_class_row.visible = false
	column.add_child(_class_row)
	for entry in ClassCatalog.all():
		_class_row.add_child(_make_class_card(entry))
	_detail = Label.new()
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(0, 60)
	_detail.theme_type_variation = &"MutedLabel"
	_detail.add_theme_font_size_override(&"font_size", 18)
	column.add_child(_detail)
	_back = Button.new()
	_back.text = "Torna"
	_back.theme_type_variation = &"MainButton"
	_back.custom_minimum_size = Vector2(0, 50)
	_back.pressed.connect(_go_back)
	column.add_child(_back)
	_level_prompts = ButtonPrompts.create([[&"ui_accept", "Scegli"], [&"ui_cancel", "Torna"]])
	column.add_child(_level_prompts)
	_class_prompts = ButtonPrompts.create([[&"ui_accept", "Parti"], [&"ui_cancel", "Livelli"]])
	_class_prompts.visible = false
	column.add_child(_class_prompts)
	_overlay.hide()


## Carta di una classe: bordo nel colore di classe, ritratto con le due armi del kit,
## nome, riga del ruolo e nomi delle armi.
func _make_class_card(entry: Dictionary) -> Button:
	var id: StringName = entry.id
	var color: Color = entry.color
	var button := Button.new()
	button.name = "Class_%s" % id
	button.theme_type_variation = &"CardButton"
	button.custom_minimum_size = Vector2(205, 250)
	button.pressed.connect(func() -> void: _on_class_pressed(id))
	button.focus_entered.connect(func() -> void: _show_class_detail(id))
	button.mouse_entered.connect(func() -> void: _show_class_detail(id))
	_class_buttons[id] = button
	# Cornice nel colore di classe, piu spessa in alto come una fascia.
	var frame := Panel.new()
	frame.name = "ClassFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border := StyleBoxFlat.new()
	border.draw_center = false
	border.border_color = color
	border.set_border_width_all(4)
	border.border_width_top = 12
	border.set_corner_radius_all(6)
	frame.add_theme_stylebox_override(&"panel", border)
	button.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 5)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 6)
	button.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	box.offset_top = 22
	var portrait := HBoxContainer.new()
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.alignment = BoxContainer.ALIGNMENT_CENTER
	portrait.add_theme_constant_override(&"separation", 10)
	box.add_child(portrait)
	var names: PackedStringArray = []
	for weapon_id: StringName in entry.kit:
		var weapon := WeaponCatalog.find(weapon_id)
		var icon := UiIcon.make(weapon.get(&"icon", &"lock"), 52.0, color)
		icon.outline = INK
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.add_child(icon)
		names.append(weapon.get(&"name", String(weapon_id)))
	var name_label := _card_label(entry.name, 20, INK)
	name_label.theme_type_variation = &"SectionLabel"
	box.add_child(name_label)
	box.add_child(_card_label(entry.text, 15, INK))
	box.add_child(_card_label("\n".join(names), 14, INK_LOCKED))
	return button


func _card_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(170, 0)
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	return label


func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()


## B o "Torna": dalle classi si torna ai livelli, dai livelli si chiude.
func _go_back() -> void:
	if not is_open:
		return
	if not choosing_class:
		close()
		return
	_show_levels()
	var fx := get_node_or_null(^"/root/UiFx") as UiFxService
	if fx != null:
		fx.play(&"ui_back")


func open() -> void:
	is_open = true
	_refresh()
	_set_choosing_class(false)
	_overlay.show()
	var fx := get_node_or_null(^"/root/UiFx") as UiFxService
	if fx != null:
		fx.pop_in(_overlay.get_child(0))
	_buttons[default_level()].grab_focus()
	_show_detail(default_level())


func close() -> void:
	if not is_open:
		return
	is_open = false
	_set_choosing_class(false)
	_overlay.hide()
	var fx := get_node_or_null(^"/root/UiFx") as UiFxService
	if fx != null:
		fx.play(&"ui_back")
	closed.emit()


## Il livello proposto: l'ultimo sbloccato e giocabile.
func default_level() -> StringName:
	var chosen := LevelCatalog.first()
	for i in LevelCatalog.count():
		var id: StringName = LevelCatalog.all()[i].id
		if is_unlocked(id) and LevelCatalog.is_playable(id):
			chosen = id
	return chosen


func is_unlocked(id: StringName) -> bool:
	var index := LevelCatalog.index_of(id)
	var unlocked := _profile.levels_unlocked if _profile != null else 1
	return index >= 0 and index < unlocked


func is_completed(id: StringName) -> bool:
	return _profile != null and _profile.has_completed(id)


func can_play(id: StringName) -> bool:
	return is_unlocked(id) and LevelCatalog.is_playable(id)


## Sceglie come se il pulsante fosse premuto (test e automazione).
func press(id: StringName) -> void:
	if is_open and _buttons.has(id):
		_buttons[id].pressed.emit()


## Testo della carta piu il segno di stato ("V" completato, "X" bloccato), per test e automazione.
func button_text(id: StringName) -> String:
	if not _buttons.has(id):
		return ""
	var mark := "V" if is_completed(id) else ("" if is_unlocked(id) else "X")
	return "%d  %s\n%s" % [LevelCatalog.index_of(id) + 1, _buttons[id].text, mark]


## Icona sulla carta: `check` completato, `lock` bloccato o in costruzione, vuoto se giocabile.
func card_badge(id: StringName) -> Label:
	return _badges.get(id)


func card_mark(id: StringName) -> StringName:
	if not _marks.has(id) or not _marks[id].visible:
		return &""
	return _marks[id].kind


## Sceglie la classe come se la carta fosse premuta (test e automazione).
func press_class(id: StringName) -> void:
	if is_open and choosing_class and _class_buttons.has(id):
		_class_buttons[id].pressed.emit()


func class_card(id: StringName) -> Button:
	return _class_buttons.get(id)


## Il livello scelto prima della classe (vuoto finche non se ne sceglie uno).
func chosen_level() -> StringName:
	return _chosen_level


## Classe proposta: l'ultima del profilo, l'Ingegnere senza profilo.
func default_class() -> StringName:
	var id := _profile.last_class if _profile != null else ClassCatalog.DEFAULT
	return id if _class_buttons.has(id) else ClassCatalog.DEFAULT


func _on_pressed(id: StringName) -> void:
	if not is_open or choosing_class or not can_play(id):
		return
	_chosen_level = id
	print("PROTOTYPE01_LEVEL_CHOSEN id=%s" % id)
	_set_choosing_class(true)
	var start := default_class()
	_class_buttons[start].grab_focus()
	_show_class_detail(start)


func _on_class_pressed(id: StringName) -> void:
	if not is_open or not choosing_class or _chosen_level == &"":
		return
	if _profile != null:
		_profile.set_last_class(id)
	print("PROTOTYPE01_CLASS_CHOSEN id=%s" % id)
	is_open = false
	_set_choosing_class(false)
	_overlay.hide()
	level_chosen.emit(_chosen_level)


## Torna alla riga dei livelli col fuoco sul livello scelto prima.
func _show_levels() -> void:
	_set_choosing_class(false)
	var id := _chosen_level if _buttons.has(_chosen_level) else default_level()
	_buttons[id].grab_focus()
	_show_detail(id)


func _set_choosing_class(value: bool) -> void:
	choosing_class = value
	_row.visible = not value
	_class_row.visible = value
	_level_prompts.visible = not value
	_class_prompts.visible = value
	_back.text = "Torna ai livelli" if value else "Torna"
	if value:
		_title.text = "LIVELLO %d: %s" % [LevelCatalog.index_of(_chosen_level) + 1, LevelCatalog.title_of(_chosen_level).to_upper()]
	else:
		_title.text = "PRIMA CAMPAGNA"


func _show_class_detail(id: StringName) -> void:
	var entry := ClassCatalog.find(id)
	if entry.is_empty():
		return
	_detail.text = "Scegli la classe per %s.\n%s: %s" % [LevelCatalog.title_of(_chosen_level), entry.name, entry.text]


func _show_detail(id: StringName) -> void:
	var entry := LevelCatalog.find(id)
	if entry.is_empty():
		return
	var state := "In costruzione" if not LevelCatalog.is_playable(id) else \
		("Completato" if is_completed(id) else ("Sbloccato" if is_unlocked(id) else "Bloccato: completa il livello precedente"))
	_detail.text = "%s\n%s  -  Boss: %s" % [entry.text, state, entry.boss]


func _refresh() -> void:
	for i in LevelCatalog.count():
		var entry: Dictionary = LevelCatalog.all()[i]
		var id: StringName = entry.id
		var button: Button = _buttons[id]
		button.text = (entry.title as String).to_upper()
		var color := INK_LOCKED
		if is_completed(id):
			color = INK_GREEN
		elif can_play(id):
			color = INK
		var mark_icon: UiIcon = _marks[id]
		mark_icon.visible = is_completed(id) or not can_play(id)
		mark_icon.kind = &"check" if is_completed(id) else &"lock"
		mark_icon.tint = UiPalette.SUCCESS if is_completed(id) else UiPalette.BORDER
		button.add_theme_color_override(&"font_color", color)
		button.add_theme_color_override(&"font_focus_color", color)
		button.add_theme_color_override(&"font_hover_color", color)
		# I livelli bloccati o in costruzione si vedono e si leggono, ma il fuoco li salta.
		button.focus_mode = Control.FOCUS_ALL if can_play(id) else Control.FOCUS_NONE
		button.disabled = not can_play(id)
