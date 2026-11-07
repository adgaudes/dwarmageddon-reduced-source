class_name GameOverPanel
extends CanvasLayer
## Fine livello: sconfitta (D-038) o vittoria sul boss (D-043), riepilogo e ripartenza.
## Da qui si entra nell'Officina (D-049) per spendere i rottami portati fuori.

signal restart_requested
signal workshop_requested
signal menu_requested
## Vittoria con un livello successivo giocabile (D-066).
signal next_level_requested

const MAP_SIZE := 340.0
const MAP_LEGEND := "giallo: terrapieni tuoi   azzurro: fossati tuoi   crema: lampioni\nrosso: brecce   viola: barricate del boss   grigio: rovine"

const INPUT_GRACE_SECONDS := 0.8
const SAVE_FAILED_TEXT := "Attenzione: profilo non salvato su disco"

var is_open := false
var is_victory := false
var _overlay: ColorRect
var _title: Label
var _summary: Label
var _workshop: Button
var _next: Button
var _restart: Button
var _menu: Button
var _quit: Button
var _map_box: VBoxContainer
var _map_rect: TextureRect
var _map_caption: Label
var _save_map: Button
var _map_image: Image
var _map_name := ""


func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay = ColorRect.new()
	_overlay.color = Color("2a0f0c", 0.9)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 48)
	center.add_child(row)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(460, 0)
	row.add_child(frame)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	frame.add_child(column)
	_build_map_box(row)
	_title = Label.new()
	_title.text = "ROTTAMATO"
	_title.theme_type_variation = &"TitleLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	# Tabella a due colonne: etichetta, tab, valore (il testo resta leggibile dai test).
	var table := PanelContainer.new()
	table.add_theme_stylebox_override(&"panel", UiPalette.plate("plate_card", UiPalette.panel_box(true), 28.0, 0.0, Vector4(18, 12, 18, 12)))
	column.add_child(table)
	_summary = Label.new()
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_summary.add_theme_font_size_override(&"font_size", 20)
	_summary.add_theme_color_override(&"font_color", UiPalette.OUTLINE)
	_summary.tab_stops = PackedFloat32Array([280.0])
	table.add_child(_summary)
	_workshop = _button(column, "Officina")
	_workshop.pressed.connect(func() -> void: workshop_requested.emit())
	_next = _button(column, "Prossimo livello")
	_next.pressed.connect(func() -> void: next_level_requested.emit())
	_next.hide()
	_restart = _button(column, "Ricomincia")
	_restart.pressed.connect(func() -> void: restart_requested.emit())
	_menu = _button(column, "Menu")
	_menu.pressed.connect(func() -> void: menu_requested.emit())
	_quit = _button(column, "Esci")
	_quit.pressed.connect(func() -> void: get_tree().quit())
	column.add_child(ButtonPrompts.create([[&"ui_accept", "Conferma"]]))
	_overlay.hide()


## Mappa del campo scolpito (D-052), a destra del riepilogo; nascosta finche manca.
func _build_map_box(parent: Control) -> void:
	_map_box = VBoxContainer.new()
	_map_box.add_theme_constant_override(&"separation", 8)
	_map_box.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(_map_box)
	var heading := Label.new()
	heading.text = "IL TUO CAMPO"
	heading.theme_type_variation = &"SectionLabel"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_box.add_child(heading)
	_map_rect = TextureRect.new()
	_map_rect.custom_minimum_size = Vector2(MAP_SIZE, MAP_SIZE)
	_map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var map_frame := PanelContainer.new()
	map_frame.add_theme_stylebox_override(&"panel", UiPalette.panel_box(true))
	map_frame.add_child(_map_rect)
	_map_box.add_child(map_frame)
	_map_caption = Label.new()
	_map_caption.theme_type_variation = &"MutedLabel"
	_map_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_caption.add_theme_font_size_override(&"font_size", 14)
	_map_box.add_child(_map_caption)
	_save_map = Button.new()
	_save_map.text = "Salva mappa"
	_save_map.custom_minimum_size = Vector2(0, 40)
	# Il nome del file non allarga mai il pulsante oltre la mappa (U-08).
	_save_map.clip_text = true
	_save_map.pressed.connect(save_map)
	_map_box.add_child(_save_map)
	_map_box.hide()


## Da chiamare prima di `open()`. [param stats]: riga sotto la mappa (celle
## scavate e rialzate); [param file_name]: nome del PNG salvato, senza estensione.
func set_map(image: Image, stats: String, file_name: String) -> void:
	_map_image = image
	_map_name = file_name
	_map_rect.texture = ImageTexture.create_from_image(image)
	_map_caption.text = "%s\n%s" % [stats, MAP_LEGEND]
	_save_map.text = "Salva mappa"
	_map_box.show()


func has_map() -> bool:
	return _map_image != null


## Salva la mappa in `user://maps/`; restituisce il percorso, vuoto se fallisce.
func save_map() -> String:
	if _map_image == null:
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://maps"))
	var path := "user://maps/%s.png" % _map_name
	if _map_image.save_png(path) != OK:
		_save_map.text = "Salvataggio non riuscito"
		return ""
	# Solo il nome: il percorso assoluto (su Deck `/home/deck/.local/share/...`) non ci sta.
	_save_map.text = "Salvata: %s" % path.get_file()
	return path


## [param banked]: rottami in Officina dopo questo livello; negativo = non mostrato.
## [param save_failed]: il profilo non e stato scritto su disco (F-03): il giocatore lo
## deve sapere, perche rottami e sblocchi spariranno al riavvio.
func open(seconds: float, level: int, kills: int, victory := false, scrap := 0, banked := -1,
		save_failed := false) -> void:
	is_open = true
	is_victory = victory
	_title.text = "LIVELLO COMPLETATO" if victory else "ROTTAMATO"
	_title.add_theme_color_override(&"font_color", UiPalette.SUCCESS if victory else UiPalette.DANGER)
	_overlay.color = Color("0f2416", 0.9) if victory else Color("2a0f0c", 0.9)
	_summary.text = "Tempo\t%s\nLivello\t%d\nRottamatori abbattuti\t%d\nRottami portati fuori\t%d" \
		% [RunHud.format_time(seconds), level, kills, scrap]
	if banked >= 0:
		_summary.text += "\nRottami in Officina\t%d" % banked
	if save_failed:
		_summary.text += "\n" + SAVE_FAILED_TEXT
	get_tree().paused = true
	_overlay.show()
	var fx := get_node_or_null(^"/root/UiFx") as UiFxService
	if fx != null:
		fx.pop_in(_overlay.get_child(0))
	if not victory:
		_next.hide()
	for button: Button in [_workshop, _next, _restart, _menu, _quit]:
		button.disabled = true
	get_tree().create_timer(INPUT_GRACE_SECONDS, true).timeout.connect(func() -> void:
		for button: Button in [_workshop, _next, _restart, _menu, _quit]:
			button.disabled = false
		focus_default())


## Mostra "Prossimo livello" con il titolo del livello sbloccato; vuoto = nascosto.
func shows_save_warning() -> bool:
	return _summary.text.contains(SAVE_FAILED_TEXT)


func set_next_level(title: String) -> void:
	_next.text = "Prossimo livello: %s" % title if not title.is_empty() else ""
	_next.visible = not title.is_empty()


func has_next_level() -> bool:
	return _next.visible


## Fuoco sul pulsante da cui ripartire: l'Officina se c'e qualcosa da spendere.
func focus_default(prefer_workshop := true) -> void:
	if not is_open:
		return
	# Un pannello aperto sopra (Officina) ha gia il focus: non glielo si ruba.
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null and not is_ancestor_of(owner):
		return
	if prefer_workshop:
		_workshop.grab_focus()
	elif _next.visible:
		_next.grab_focus()
	else:
		_restart.grab_focus()


func _button(parent: Control, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = &"MainButton"
	button.custom_minimum_size = Vector2(0, 52)
	parent.add_child(button)
	return button
