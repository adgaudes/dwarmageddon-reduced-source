class_name LevelUpMenu
extends CanvasLayer
## Scelta fra tre upgrade a ogni livello (PROGRESSION_SPEC). Ferma il gioco,
## si usa con controller (croce o stick, A) e con mouse o tastiera. Le carte
## restano inattive per un attimo: chi sta premendo A non sceglie per sbaglio.

signal chosen(id: StringName)
## Il menu si e appena aperto con una nuova offerta.
signal opened

const INPUT_GRACE_SECONDS := 0.4

var is_open := false
var _overlay: ColorRect
var _title: Label
var _subtitle: Label
var _cards: HBoxContainer
var _buttons: Array[Button] = []
var _icons: Array[UiIcon] = []
var _ribbons: Array[Label] = []

const INK := Color("3b2718")
const INK_SOFT := Color("7a4a26")


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = ColorRect.new()
	_overlay.color = Color(UiPalette.BG, 0.82)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 24)
	center.add_child(column)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	_subtitle = Label.new()
	_subtitle.text = "scegli un pezzo"
	_subtitle.theme_type_variation = &"MutedLabel"
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_subtitle)
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override(&"separation", 20)
	column.add_child(_cards)
	column.add_child(ButtonPrompts.create([[&"ui_accept", "Scegli"]]))
	_overlay.hide()


## [param offer]: voci di UpgradeCatalog o carte arma (WeaponOffers); [param levels]: livello
## attuale per id (le carte arma lo portano in `shown_level`). Titolo e sottotitolo cambiano
## per la scelta della trasformazione di un'arma (D-092).
func open(offer: Array[Dictionary], levels: Dictionary, player_level: int, title := "", subtitle := "") -> void:
	for button in _buttons:
		# Tolte subito dall'albero: le carte vecchie non restano un frame accanto alle nuove (U-07).
		_cards.remove_child(button)
		button.queue_free()
	_buttons.clear()
	_icons.clear()
	_ribbons.clear()
	_title.text = title if not title.is_empty() else "LIVELLO %d" % player_level
	_subtitle.text = subtitle if not subtitle.is_empty() else "scegli un pezzo"
	for upgrade in offer:
		_buttons.append(_make_card(upgrade, int(upgrade.get(&"shown_level", levels.get(upgrade.id, 0)))))
	for i in _buttons.size():
		var left := _buttons[(i - 1 + _buttons.size()) % _buttons.size()]
		var right := _buttons[(i + 1) % _buttons.size()]
		_buttons[i].focus_neighbor_left = _buttons[i].get_path_to(left)
		_buttons[i].focus_neighbor_right = _buttons[i].get_path_to(right)
	# Le carte entrano sfalsate di 60 ms: il tween gira anche a gioco fermo.
	for i in _buttons.size():
		_buttons[i].modulate.a = 0.0
		var tween := create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_interval(0.06 * i)
		tween.tween_property(_buttons[i], "modulate:a", 1.0, 0.18)
	is_open = true
	get_tree().paused = true
	_overlay.show()
	var fx := get_node_or_null(^"/root/UiFx") as UiFxService
	if fx != null:
		fx.pop_in(_cards)
	_set_enabled(false)
	get_tree().create_timer(INPUT_GRACE_SECONDS, true).timeout.connect(_enable_after_grace)
	opened.emit()


func close() -> void:
	is_open = false
	_overlay.hide()
	get_viewport().gui_release_focus()
	get_tree().paused = false


func card_count() -> int:
	return _buttons.size()


func card(index: int) -> Button:
	return _buttons[index]


func card_icon(index: int) -> UiIcon:
	return _icons[index]


func card_ribbon(index: int) -> Label:
	return _ribbons[index]


## Testo della carta (rarita, nome, tipo, descrizione) su righe, per test e automazione.
func card_text(index: int) -> String:
	var parts: PackedStringArray = []
	for label in _labels_of(_buttons[index]):
		parts.append(label.text)
	return "\n".join(parts)


func title_text() -> String:
	return _title.text


func _labels_of(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	if node is Label:
		out.append(node)
	for child in node.get_children():
		out.append_array(_labels_of(child))
	return out


## Sceglie la carta [param index] come se fosse premuta (test e automazione).
func press(index: int) -> void:
	if index >= 0 and index < _buttons.size() and not _buttons[index].disabled:
		_buttons[index].pressed.emit()


func _enable_after_grace() -> void:
	if not is_open:
		return
	_set_enabled(true)
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _set_enabled(enabled: bool) -> void:
	for button in _buttons:
		button.disabled = not enabled


func _make_card(upgrade: Dictionary, current_level: int) -> Button:
	var color: Color = UpgradeCatalog.RARITY_COLORS[upgrade.rarity].linear_to_srgb()
	var button := Button.new()
	button.theme_type_variation = &"CardButton"
	button.custom_minimum_size = Vector2(300, 320)
	button.focus_mode = Control.FOCUS_ALL
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 0
	column.offset_top = 6
	column.offset_right = 0
	column.offset_bottom = -6
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(&"separation", 6)
	button.add_child(column)
	# Nastro della rarita: texture bianca tinta del colore della rarita, testo scuro.
	var ribbon := Label.new()
	ribbon.text = UpgradeCatalog.RARITY_NAMES[upgrade.rarity]
	ribbon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ribbon.theme_type_variation = &"SectionLabel"
	ribbon.add_theme_font_size_override(&"font_size", 16)
	ribbon.add_theme_color_override(&"font_color", UiPalette.OUTLINE)
	var band := UiPalette.plate("ribbon", UiPalette.panel_box(true), 14.0, 10.0, Vector4(12, 5, 12, 7), color)
	ribbon.add_theme_stylebox_override(&"normal", band)
	column.add_child(ribbon)
	_ribbons.append(ribbon)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	var icon := UiIcon.make(upgrade.get(&"icon", UiIcon.for_category(upgrade.category)), 48.0, UiPalette.BORDER)
	icon.name = "Icon"
	icon.outline = INK
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(icon)
	_icons.append(icon)
	var body := MarginContainer.new()
	body.add_theme_constant_override(&"margin_left", 16)
	body.add_theme_constant_override(&"margin_right", 16)
	body.add_theme_constant_override(&"margin_bottom", 12)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(body)
	var text := VBoxContainer.new()
	text.add_theme_constant_override(&"separation", 6)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(text)
	var name_label := Label.new()
	name_label.text = upgrade.name
	name_label.theme_type_variation = &"SectionLabel"
	name_label.add_theme_color_override(&"font_color", INK)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(name_label)
	var level_text := "NUOVO" if current_level == 0 else "Liv. %d > %d" % [current_level, current_level + 1]
	var kind := Label.new()
	kind.text = "%s  -  %s" % [UpgradeCatalog.CATEGORY_NAMES.get(upgrade.category, ""), level_text]
	kind.theme_type_variation = &"MutedLabel"
	kind.add_theme_color_override(&"font_color", INK_SOFT)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_child(kind)
	var description := Label.new()
	description.text = UpgradeCatalog.describe(upgrade)
	description.add_theme_font_size_override(&"font_size", 17)
	description.add_theme_color_override(&"font_color", INK)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_child(description)
	for label: Label in [ribbon, name_label, kind, description]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# La carta con il focus si alza: scala 1,04 attorno al centro, 120 ms, anche in pausa.
	button.pivot_offset = button.custom_minimum_size * 0.5
	button.focus_entered.connect(func() -> void:
		create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(button, "scale", Vector2(1.04, 1.04), 0.12))
	button.focus_exited.connect(func() -> void:
		create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS).tween_property(button, "scale", Vector2.ONE, 0.12))
	var id: StringName = upgrade.id
	button.pressed.connect(func() -> void: _on_pressed(id))
	_cards.add_child(button)
	return button


func _on_pressed(id: StringName) -> void:
	if not is_open:
		return
	close()
	chosen.emit(id)
