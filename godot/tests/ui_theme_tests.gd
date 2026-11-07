extends SceneTree
## Test del tema dell'interfaccia (D-080). Eseguire con:
##   godot_console --headless --path godot --fixed-fps 60 --script res://tests/ui_theme_tests.gd

const MenuScene := preload("res://scenes/main/main_menu.tscn")

var _failures := 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	await _frames(1)
	_test_palette()
	_test_textures()
	_test_theme_on_root()
	await _test_icons_and_sounds()
	await _test_logo()
	await _test_screens_focus()
	await _test_pause_and_settings()
	await _test_cards_and_panels()
	await _test_game_over()
	await _test_hud()
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


func _test_palette() -> void:
	_check(UiPalette.title_font() != null and UiPalette.text_font() != null, "i due font si caricano")
	_check(UiPalette.title_font() != ThemeDB.fallback_font and UiPalette.text_font() != ThemeDB.fallback_font, "nessuno dei due e il font di riserva")
	_check(UiPalette.text_font(700) != UiPalette.text_font(400), "il peso 700 e una variazione distinta")
	var theme := UiPalette.build_theme()
	_check(theme.default_font == UiPalette.text_font(), "font di testo predefinito nel tema")
	_check(theme.default_font_size == 18, "testo a 18 px")
	for variation: StringName in [&"TitleLabel", &"SectionLabel", &"MutedLabel", &"HudLabel", &"ScrapLabel"]:
		_check(theme.get_type_variation_base(variation) == &"Label", "variante %s di Label" % variation)
	for variation: StringName in [&"MainButton", &"CardButton"]:
		_check(theme.get_type_variation_base(variation) == &"Button", "variante %s di Button" % variation)
	_check(theme.get_font_size(&"font_size", &"TitleLabel") == 40, "titolo a 40 px")
	var smallest := 999
	for type_name in theme.get_font_size_type_list():
		for size_name in theme.get_font_size_list(type_name):
			smallest = mini(smallest, theme.get_font_size(size_name, type_name))
	_check(smallest >= 14, "nessuna dimensione sotto 14 px (minima %d)" % smallest)
	var normal := UiPalette.button_box(&"normal")
	var focus := UiPalette.button_box(&"focus")
	var hover := UiPalette.button_box(&"hover")
	_check(focus.border_color == UiPalette.FOCUS and focus.border_color != hover.border_color, "stile di riserva: focus turchese, diverso dall'hover")
	_check(focus.shadow_size > 0 and normal.shadow_size == 0, "stile di riserva: bagliore solo sul focus")


## Il tema di progetto (`gui/theme/custom`, generato da build_theme.gd) deve essere
## identico a `UiPalette.build_theme()`: i CanvasLayer lo ricevono solo da li. Confronto
## campo per campo di colori, costanti, dimensioni, varianti e StyleBoxFlat.
## Texture generate da build_ui_textures.gd e montate nel tema come StyleBoxTexture.
func _test_textures() -> void:
	var expected := {
		"plate_panel": Vector2i(96, 96), "plate_button": Vector2i(96, 96), "plate_button_hover": Vector2i(96, 96),
		"plate_button_pressed": Vector2i(96, 96), "plate_button_focus": Vector2i(96, 96), "plate_card": Vector2i(96, 96),
		"plate_card_focus": Vector2i(96, 96), "ribbon": Vector2i(96, 32), "rule": Vector2i(256, 12),
		"gauge": Vector2i(64, 24), "gauge_fill": Vector2i(64, 24), "strip": Vector2i(96, 48), "knob": Vector2i(24, 24),
	}
	var all_present := true
	for name in expected:
		var texture := load(UiPalette.TEXTURE_DIR + name + ".png") as Texture2D
		if texture == null or texture.get_size() != Vector2(expected[name]):
			all_present = false
			print("    manca o misura sbagliata: %s" % name)
	_check(all_present, "tredici texture dell'interfaccia presenti con le misure attese")
	_check(UiPalette.has_textures(), "UiPalette trova le texture")
	var theme := UiPalette.build_theme()
	var checks := [
		[&"normal", &"Button", "plate_button.png"], [&"hover", &"Button", "plate_button_hover.png"],
		[&"pressed", &"Button", "plate_button_pressed.png"], [&"focus", &"Button", "plate_button_focus.png"],
		[&"panel", &"PanelContainer", "plate_panel.png"], [&"normal", &"CardButton", "plate_card.png"],
		[&"focus", &"CardButton", "plate_card_focus.png"], [&"fill", &"ProgressBar", "gauge_fill.png"],
		[&"slider", &"HSlider", "gauge.png"],
	]
	for entry in checks:
		var box := theme.get_stylebox(entry[0], entry[1]) as StyleBoxTexture
		_check(box != null and box.texture != null and box.texture.resource_path.ends_with(entry[2]), "%s/%s su %s" % [entry[1], entry[0], entry[2]])
	var focus := theme.get_stylebox(&"focus", &"Button") as StyleBoxTexture
	_check(focus != null and focus.expand_margin_left > 0.0, "il focus sborda con l'alone")
	_check(theme.get_icon(&"grabber", &"HSlider").resource_path.ends_with("knob.png"), "pomello dello slider a rivetto")
	var slider := theme.get_stylebox(&"slider", &"HSlider") as StyleBoxTexture
	_check(slider != null and slider.content_margin_top + slider.content_margin_bottom >= slider.texture_margin_top * 2.0, "lo slider e alto quanto il tubo")


## Pittogrammi a poligoni (UiIcon) e suoni di interfaccia sintetizzati.
func _test_icons_and_sounds() -> void:
	var holder := Control.new()
	root.add_child(holder)
	for kind in UiIcon.KINDS:
		var icon := UiIcon.make(kind, 32.0)
		holder.add_child(icon)
	await _frames(2)
	_check(holder.get_child_count() == UiIcon.KINDS.size() and UiIcon.KINDS.size() >= 12, "%d icone disegnate senza errori" % holder.get_child_count())
	_check(UiIcon.for_category(&"weapon") == &"nail" and UiIcon.for_category(&"terrain") == &"shovel" and UiIcon.for_category(&"character") == &"boot" and UiIcon.for_category(&"companion") == &"wrench", "icona per categoria di upgrade")
	_check(UiIcon.for_permanent(&"base_health") == &"bolt" and UiIcon.for_permanent(&"fixed_turret") == &"nail", "icona per upgrade permanente")
	holder.queue_free()
	var all_short := true
	for id: StringName in [&"ui_move", &"ui_confirm", &"ui_back", &"ui_open"]:
		var stream := SfxLibrary.build(id)
		if stream == null or SfxLibrary.duration_of(stream) > 0.25:
			all_short = false
		if not SfxLibrary.IDS.has(id):
			all_short = false
	_check(all_short, "quattro suoni di interfaccia brevi, negli IDS")
	await _frames(1)


func _test_theme_on_root() -> void:
	var project := ThemeDB.get_project_theme()
	_check(project != null, "tema di progetto registrato")
	if project == null:
		return
	var expected := UiPalette.build_theme()
	var differences := _theme_differences(expected, project)
	_check(differences.is_empty(), "theme.tres allineato a UiPalette (rigenerare con build_theme.gd): %s" % ", ".join(differences.slice(0, 5)))


func _theme_differences(expected: Theme, actual: Theme) -> PackedStringArray:
	var out: PackedStringArray = []
	if expected.default_font_size != actual.default_font_size:
		out.append("default_font_size")
	for type_name in expected.get_type_list():
		if expected.get_type_variation_base(type_name) != actual.get_type_variation_base(type_name):
			out.append("variation %s" % type_name)
		for name in expected.get_color_list(type_name):
			if not expected.get_color(name, type_name).is_equal_approx(actual.get_color(name, type_name)):
				out.append("%s/%s" % [type_name, name])
		for name in expected.get_constant_list(type_name):
			if expected.get_constant(name, type_name) != actual.get_constant(name, type_name):
				out.append("%s/%s" % [type_name, name])
		for name in expected.get_font_size_list(type_name):
			if expected.get_font_size(name, type_name) != actual.get_font_size(name, type_name):
				out.append("%s/%s" % [type_name, name])
		for name in expected.get_stylebox_list(type_name):
			var ta := expected.get_stylebox(name, type_name) as StyleBoxTexture
			var tb := actual.get_stylebox(name, type_name) as StyleBoxTexture
			if ta != null or tb != null:
				if ta == null or tb == null or ta.texture == null or tb.texture == null 						or ta.texture.resource_path != tb.texture.resource_path 						or ta.texture_margin_left != tb.texture_margin_left or ta.expand_margin_left != tb.expand_margin_left 						or not ta.modulate_color.is_equal_approx(tb.modulate_color):
					out.append("%s/%s" % [type_name, name])
				continue
			var a := expected.get_stylebox(name, type_name) as StyleBoxFlat
			var b := actual.get_stylebox(name, type_name) as StyleBoxFlat
			if a == null or b == null:
				if (a == null) != (b == null):
					out.append("%s/%s" % [type_name, name])
				continue
			var same := a.bg_color.is_equal_approx(b.bg_color) and a.border_color.is_equal_approx(b.border_color) 				and a.border_width_top == b.border_width_top and a.border_width_left == b.border_width_left 				and a.corner_radius_top_left == b.corner_radius_top_left and a.shadow_size == b.shadow_size 				and a.shadow_color.is_equal_approx(b.shadow_color) and a.content_margin_left == b.content_margin_left 				and a.content_margin_top == b.content_margin_top
			if not same:
				out.append("%s/%s" % [type_name, name])
	return out


func _test_logo() -> void:
	for layout in ["wide", "stacked"]:
		var logo := GameLogo.new()
		logo.layout = layout
		root.add_child(logo)
		await _frames(1)
		_check(logo.letter_count() == GameLogo.TITLE.length(), "%s: una Label per lettera" % layout)
		_check(logo.custom_minimum_size.x > 300 and logo.custom_minimum_size.y > 80, "%s: dimensione calcolata" % layout)
		for p in [0.0, 0.5, 1.0]:
			logo.set_letter_progress(p)
			logo.set_nail_progress(p)
			logo.set_subtitle_progress(p)
			logo.set_grass_progress(p)
		logo.set_all(1.0)
		_check(logo.is_complete(), "%s: set_all(1) completa il logo" % layout)
		_check(logo.shadow_count() == logo.letter_count(), "%s: ogni lettera ha la sua ombra portata" % layout)
		var material := logo.letter_material()
		_check(material != null and material.get_shader_parameter(&"bevel_px") != null and float(material.get_shader_parameter(&"bevel_px")) > 0.0, "%s: bisello nello shader delle lettere" % layout)
		logo.queue_free()
	await _frames(1)


## Ogni pulsante delle schermate eredita dal tema un focus diverso dal normale.
func _test_screens_focus() -> void:
	var menu := MenuScene.instantiate()
	root.add_child(menu)
	await _frames(3)
	_check_focus_distinct(menu, "menu", 4)
	_check((menu.get_node_or_null(^"Background") as Control) != null, "menu con sfondo dipinto")
	_check((menu.get_node_or_null(^"Background") as ColorRect).material is ShaderMaterial, "sfondo con il cielo dipinto")
	_check(menu.get_node_or_null(^"Logo") is GameLogo, "logo nel menu")
	_check(menu.get_node_or_null(^"ProfilePlate") is PanelContainer, "targhetta del profilo")
	_check(menu.get_node_or_null(^"ProfilePlate/Row/ScrapIcon") is UiIcon, "targhetta con l'icona dei rottami")
	_check(menu.get_node_or_null(^"ProfilePlate/Row/RunsIcon") is UiIcon and menu.get_node_or_null(^"ProfilePlate/Row/LevelsIcon") is UiIcon, "targhetta con le icone di run e livelli")
	_check(menu._runs_label.text.begins_with("Run giocate: ") and menu._levels_label.text.begins_with("Livelli completati: "), "run e livelli su etichette proprie")
	var backdrop := menu.get_node_or_null(^"Backdrop") as MenuBackdrop
	_check(backdrop != null and backdrop.layer_count() == 3, "sfondo a tre strati dietro il menu")
	var before_x := backdrop.layer_offset(2) if backdrop != null else 0.0
	await _frames(30)
	_check(backdrop != null and not is_equal_approx(backdrop.layer_offset(2), before_x), "gli strati scorrono in parallasse")
	_check(backdrop != null and backdrop.get_index() < menu.get_node(^"Column").get_index() and backdrop.mouse_filter == Control.MOUSE_FILTER_IGNORE, "lo sfondo sta dietro la colonna e non prende il mouse")
	var dust: CPUParticles2D = menu.get_node(^"Dust")
	_check(is_equal_approx(dust.position.x, menu.size.x * 0.5) and is_equal_approx(dust.emission_rect_extents.x, menu.size.x * 0.55), "polvere centrata sulla larghezza del menu (%.0f su %.0f)" % [dust.position.x, menu.size.x])
	menu.queue_free()
	await _frames(2)


## Pausa e Impostazioni usano le varianti del tema, non dimensioni scritte a mano.
func _test_pause_and_settings() -> void:
	var pause := root.get_node("PauseMenu")
	var pause_title: Label = pause.get_node("%PausePanel/Margin/Buttons/Title")
	_check(pause_title.theme_type_variation == &"TitleLabel", "titolo della pausa in TitleLabel")
	var settings: Control = pause.get_node("%SettingsPanel")
	var header: Label = settings.get_node("%Content/GraphicsHeader")
	_check(header.theme_type_variation == &"SectionLabel", "intestazione Grafica in SectionLabel")
	_check(settings.get_node_or_null("%Content/GraphicsRule") is TextureRect and (settings.get_node("%Content/GraphicsRule") as TextureRect).texture.resource_path.ends_with("rule.png"), "linea di rame disegnata (rule.png) sotto Grafica")
	var hand_sized := 0
	for node in _descendants(pause):
		if node is Control and (node as Control).has_theme_font_size_override(&"font_size"):
			hand_sized += 1
	_check(hand_sized == 0, "nessuna dimensione di font scritta a mano nella pausa (%d)" % hand_sized)
	var buttons: Array[Button] = []
	_collect_buttons(pause, buttons)
	var main_buttons := 0
	for button in buttons:
		if button.theme_type_variation == &"MainButton":
			main_buttons += 1
	_check(main_buttons >= 5, "Riprendi, Impostazioni, Torna al menu, Esci e Indietro in MainButton (%d)" % main_buttons)
	_check(settings.custom_minimum_size.x == 760.0, "pannello Impostazioni largo 760")
	_check_focus_distinct(pause, "pausa e Impostazioni", 5)


## Level-up a carte con fascia di rarita, Officina e campagna con le varianti del tema.
func _test_cards_and_panels() -> void:
	var level_up := LevelUpMenu.new()
	root.add_child(level_up)
	await _frames(1)
	var offer: Array[Dictionary] = UpgradeCatalog.all().slice(0, 3)
	level_up.open(offer, {}, 2)
	await _frames(2)
	_check(level_up.card_count() == 3, "tre carte")
	var text := level_up.card_text(0)
	_check(text.contains(UpgradeCatalog.RARITY_NAMES[offer[0].rarity]) and text.contains(offer[0].name), "la carta mostra rarita e nome: %s" % text.replace("\n", " | "))
	_check(level_up.title_text() == "LIVELLO 2", "titolo del level-up: %s" % level_up.title_text())
	var card := level_up.card(0)
	_check(card.theme_type_variation == &"CardButton" and card.custom_minimum_size == Vector2(300, 320), "carta CardButton 300x320")
	var focus_box := card.get_theme_stylebox(&"focus") as StyleBoxTexture
	_check(focus_box != null and focus_box.texture.resource_path.ends_with("plate_card_focus.png"), "carta con la pergamena del focus (alone)")
	_check(level_up.card_icon(0) != null and level_up.card_icon(0).kind == UiIcon.for_category(offer[0].category), "icona della categoria sulla carta")
	var ribbon := level_up.card_ribbon(0)
	var ribbon_box := ribbon.get_theme_stylebox(&"normal") as StyleBoxTexture
	_check(ribbon_box != null and ribbon_box.texture.resource_path.ends_with("ribbon.png") and ribbon_box.modulate_color.is_equal_approx(UpgradeCatalog.RARITY_COLORS[offer[0].rarity].linear_to_srgb()), "nastro della rarita tinto")
	_check_focus_distinct(level_up, "level-up", 3)
	level_up.close()
	level_up.queue_free()
	var workshop := WorkshopPanel.new()
	root.add_child(workshop)
	await _frames(1)
	workshop.open()
	await _frames(1)
	var rows: Array[Button] = []
	_collect_buttons(workshop, rows)
	var card_rows := 0
	for row in rows:
		if row.theme_type_variation == &"CardButton":
			card_rows += 1
	# Le carte dell'Officina: gli upgrade, le sei fusioni del ricettario (D-092) e le sei
	# combinazioni delle macchine (D-093).
	var workshop_cards := PermanentCatalog.all().size() + PermanentCatalog.RECIPES.size() + MachineCatalog.COMBOS.size()
	_check(card_rows == workshop_cards, "righe dell'Officina in CardButton (%d)" % card_rows)
	_check(workshop._scrap_label.theme_type_variation == &"ScrapLabel", "contatore rottami in ScrapLabel")
	var rows_with_icon := 0
	for row in rows:
		if row.theme_type_variation == &"CardButton" and row.get_node_or_null(^"Icon") is UiIcon:
			rows_with_icon += 1
	_check(rows_with_icon == workshop_cards, "ogni riga dell'Officina ha la sua icona (%d)" % rows_with_icon)
	var dots := workshop.row_dots(&"base_health")
	_check(dots != null and dots.total == 3 and dots.filled == 0, "pallini del livello sulla riga (%s)" % ("%d/%d" % [dots.filled, dots.total] if dots != null else "nessuno"))
	_check(workshop._scrap_label.get_parent().get_node_or_null(^"ScrapIcon") is UiIcon, "icona dei rottami accanto al totale dell'Officina")
	_check_focus_distinct(workshop, "Officina", 2)
	workshop.close()
	workshop.queue_free()
	var campaign := CampaignMapPanel.new()
	root.add_child(campaign)
	await _frames(1)
	campaign.open()
	await _frames(1)
	var level_cards: Array[Button] = []
	_collect_buttons(campaign._row, level_cards)
	_check(level_cards.size() == LevelCatalog.count() and level_cards[0].theme_type_variation == &"CardButton", "livelli della campagna come carte")
	var links := 0
	for child in campaign._row.get_children():
		if child is ColorRect:
			links += 1
	_check(links == LevelCatalog.count() - 1, "una linea rame fra una carta e l'altra (%d)" % links)
	var marks_ok := true
	for i in LevelCatalog.count():
		var id: StringName = LevelCatalog.all()[i].id
		var mark := campaign.card_mark(id)
		var expected_mark: StringName = &"check" if campaign.is_completed(id) else (&"lock" if not campaign.can_play(id) else &"")
		if mark != expected_mark:
			marks_ok = false
	_check(marks_ok, "icona check/lock sulle carte della campagna")
	var first_id: StringName = LevelCatalog.all()[0].id
	var badge := campaign.card_badge(first_id)
	_check(badge != null and badge.text == "1" and badge.get_theme_stylebox(&"normal") is StyleBoxFlat and (badge.get_theme_stylebox(&"normal") as StyleBoxFlat).corner_radius_top_left >= 12, "numero del livello in un cerchio di rame")
	var first: StringName = LevelCatalog.all()[0].id
	_check(not campaign._buttons[first].text.contains("
") and campaign.button_text(first).contains("
"), "sulle carte niente riga con la lettera V/X (resta solo in button_text)")
	_check_focus_distinct(campaign, "campagna", 2)
	campaign.close()
	campaign.queue_free()
	await _frames(2)


## Fine livello: pannello, titolo colorato per esito, tabella allineata con i tab.
func _test_game_over() -> void:
	var panel := GameOverPanel.new()
	root.add_child(panel)
	await _frames(1)
	panel.open(61.0, 3, 12, false, 5, 20)
	await _frames(1)
	_check(panel._title.theme_type_variation == &"TitleLabel", "titolo in TitleLabel")
	_check(panel._title.get_theme_color(&"font_color").is_equal_approx(UiPalette.DANGER), "sconfitta in corallo")
	_check(panel._summary.get_parent() is PanelContainer, "riepilogo in un pannello")
	var note := (panel._summary.get_parent() as PanelContainer).get_theme_stylebox(&"panel") as StyleBoxTexture
	_check(note != null and note.texture.resource_path.ends_with("plate_card.png") and panel._summary.get_theme_color(&"font_color").is_equal_approx(UiPalette.OUTLINE), "riepilogo su pergamena con testo scuro")
	_check(panel._summary.tab_stops.size() == 1 and panel._summary.text.contains("Tempo\t01:01") and panel._summary.text.contains("Rottami in Officina\t20"), "righe allineate con i tab: %s" % panel._summary.text.replace("\n", " | "))
	panel.open(61.0, 3, 12, true, 5, 20)
	await _frames(1)
	_check(panel._title.get_theme_color(&"font_color").is_equal_approx(UiPalette.SUCCESS), "vittoria in verde")
	var buttons: Array[Button] = []
	_collect_buttons(panel, buttons)
	var main := 0
	for button in buttons:
		if button.theme_type_variation == &"MainButton":
			main += 1
	_check(main >= 5, "pulsanti di fine livello in MainButton (%d)" % main)
	# Un pannello aperto sopra (Officina) tiene il focus: la grazia di fine livello non lo ruba.
	var other := Button.new()
	other.text = "Sopra"
	root.add_child(other)
	panel.open(10.0, 1, 0, false, 0, 0)
	await _frames(3)
	other.grab_focus()
	await _frames(70)
	_check(root.get_viewport().gui_get_focus_owner() == other, "la fine livello non ruba il focus a chi sta sopra")
	other.queue_free()
	_check_focus_distinct(panel, "fine livello", 5)
	paused = false
	panel.queue_free()
	await _frames(2)


## HUD: bulloni di vita senza nodi figli, quadrante accanto al testo del giorno, slab.
func _test_hud() -> void:
	var hud := RunHud.new()
	root.add_child(hud)
	await _frames(2)
	hud.set_health(3, 5)
	_check(hud._health_row is HealthBolts and hud._health_row.bolt_count() == 5 and hud._health_row.lit_count() == 3, "cinque bulloni, tre accesi")
	hud.set_health(2, 7)
	_check(hud._health_row.bolt_count() == 7 and hud._health_row.get_child_count() == 0, "al cambio di massimo si ridisegna senza figli")
	hud.set_day_phase(0, 125.0)
	_check(hud._day_label.visible and hud._day_label.text.contains("02:05"), "testo del giorno conservato: %s" % hud._day_label.text)
	_check(hud._day_dial is DayDial and hud._day_dial.visible and hud._day_dial.phase() == 0, "quadrante del giorno visibile")
	hud.set_day_phase(0, INF)
	_check(not hud._day_dial.visible, "ciclo spento: quadrante nascosto")
	_check(hud._level_label.get_theme_font(&"font") == UiPalette.title_font(), "numeri dell'HUD in slab")
	_check(hud._xp_bar.anchor_top == 1.0, "barra esperienza in basso")
	var xp_fill := hud._xp_bar.get_theme_stylebox(&"fill") as StyleBoxTexture
	_check(xp_fill != null and xp_fill.texture.resource_path.ends_with("gauge_fill.png"), "barra esperienza come tubo (gauge_fill)")
	_check(xp_fill != null and xp_fill.texture_margin_top * 2.0 <= hud._xp_bar.custom_minimum_size.y, "il tubo non viene tagliato in altezza (margini %.0f su %.0f)" % [xp_fill.texture_margin_top, hud._xp_bar.custom_minimum_size.y])
	_check(hud.strip_of(hud._health_row) != null and (hud.strip_of(hud._health_row).get_theme_stylebox(&"panel") as StyleBoxTexture).texture.resource_path.ends_with("strip.png"), "vita su una striscia di lamiera")
	_check(hud.icon_before(hud._kills_label) != null and hud.icon_before(hud._kills_label).kind == &"skull", "teschio prima dei rottamati")
	_check(hud.icon_before(hud._time_label) != null and hud.icon_before(hud._time_label).kind == &"clock", "orologio prima del tempo")
	_check(hud.icon_before(hud._health_row) != null and hud.icon_before(hud._health_row).kind == &"bolt", "bullone prima della vita")
	hud.set_tool_mode(TerrainField.ToolMode.LAMP, 1, 4, 3)
	_check(hud._tool_label.visible and hud.icon_before(hud._tool_label) != null and hud.icon_before(hud._tool_label).kind == &"lamp" and hud.icon_before(hud._tool_label).visible, "modo lampione con l'icona")
	hud.set_tool_mode(TerrainField.ToolMode.DIG, 0, 4, 3)
	_check(not hud._tool_label.visible and not hud.icon_before(hud._tool_label).visible, "fuori dal modo lampione icona e testo spariscono")
	_check(not hud._warning_plate.has_theme_stylebox_override(&"panel"), "targa degli avvisi dal tema (cuoio e rivetti)")
	var boss_fill := hud._boss_bar.get_theme_stylebox(&"fill") as StyleBoxTexture
	_check(boss_fill != null and boss_fill.modulate_color.is_equal_approx(RunHud.BOSS_COLOR), "barra del boss come tubo arancione")
	hud.show_notice("PROVA DI UN AVVISO MOLTO PIU LUNGO DEL PRECEDENTE", 1.0, UiPalette.TEXT)
	_check(hud._warning_plate.visible and hud._boss_warning.visible, "avviso su targa")
	await _frames(2)
	_check(hud._warning_plate.pivot_offset.is_equal_approx(hud._warning_plate.size * 0.5), "la targa ruota attorno al centro della sua dimensione attuale")
	_check(not ("HEALTH_ON" in (load("res://scripts/ui/run_hud.gd") as GDScript).get_script_constant_map()), "costanti HEALTH_* tolte dall'HUD")
	hud.clear_event_warning()
	_check(not hud._warning_plate.visible, "targa nascosta con l'avviso")
	hud.queue_free()
	await _frames(1)


func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_descendants(child))
	return out


## Ogni pulsante della schermata ha un focus diverso dal normale e testo di almeno 14 px.
func _check_focus_distinct(screen: Node, label: String, at_least: int) -> void:
	var buttons: Array[Button] = []
	_collect_buttons(screen, buttons)
	_check(buttons.size() >= at_least, "%s: almeno %d pulsanti (%d)" % [label, at_least, buttons.size()])
	var all_distinct := true
	var all_big := true
	for button in buttons:
		if button.get_theme_stylebox(&"focus") == button.get_theme_stylebox(&"normal"):
			all_distinct = false
		if button.get_theme_font_size(&"font_size") < 14:
			all_big = false
	_check(all_distinct, "%s: ogni pulsante ha un focus distinto" % label)
	_check(all_big, "%s: nessun pulsante sotto 14 px" % label)


func _collect_buttons(node: Node, out: Array[Button]) -> void:
	if node is Button:
		out.append(node)
	for child in node.get_children():
		_collect_buttons(child, out)
