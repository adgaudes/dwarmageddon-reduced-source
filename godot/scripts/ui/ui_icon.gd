class_name UiIcon
extends Control
## Pittogrammi dell'interfaccia (D-081) disegnati con poligoni, in due toni (riempimento
## e outline scuro), scalabili con `custom_minimum_size`. Nessuna immagine: lo stile
## resta quello della pipeline nostra. `kind` fra KINDS; `tint` colora il riempimento.

const KINDS: Array[StringName] = [
	&"nail", &"shovel", &"boot", &"wrench", &"scrap", &"bolt", &"skull", &"clock",
	&"lamp", &"arrow_right", &"check", &"lock", &"stake",
	&"blade", &"hammer", &"ram", &"mixer", &"dozer", &"compactor",
	&"scrap_launcher", &"dig_charge", &"welder", &"crane_magnet", &"scythe", &"bramble",
	&"fort", &"mortar", &"tesla_coil", &"scythe_bramble",
	&"crate", &"turret", &"magnet", &"beacon", &"drill", &"scoop", &"solder", &"siren",
]

@export var kind: StringName = &"nail":
	set(value):
		kind = value
		queue_redraw()
@export var tint: Color = Color("f2e6cf"):
	set(value):
		tint = value
		queue_redraw()
@export var outline: Color = Color("130d0a")


static func make(icon_kind: StringName, size: float, icon_tint := Color("f2e6cf")) -> UiIcon:
	var icon := UiIcon.new()
	icon.kind = icon_kind
	icon.tint = icon_tint
	icon.custom_minimum_size = Vector2(size, size)
	return icon


static func for_category(category: StringName) -> StringName:
	match category:
		&"weapon":
			return &"nail"
		&"terrain":
			return &"shovel"
		&"character":
			return &"boot"
		&"companion":
			return &"wrench"
	return &"scrap"


static func for_permanent(id: StringName) -> StringName:
	match id:
		&"tool_reach":
			return &"shovel"
		&"pack_size":
			return &"sack"
		&"base_health":
			return &"bolt"
		&"reflexes":
			return &"boot"
		&"cargo":
			return &"crate"
		&"stock":
			return &"scrap"
		&"fixed_turret":
			return &"nail"
		&"salvage":
			return &"parachute"
		&"toolbox":
			return &"wrench"
		&"spare_stakes":
			return &"stake"
		&"dry_powder", &"charge_pack":
			return &"dig_charge"
		&"good_oil":
			return &"crane_magnet"
		&"good_seeds":
			return &"bramble"
		&"green_thumb":
			return &"scythe"
	# Sblocco di un'arma: l'icona dell'arma.
	var weapon := PermanentCatalog.weapon_of(id)
	if weapon != &"":
		return WeaponCatalog.find(weapon).get(&"icon", &"scrap")
	return &"scrap"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Converte punti in unita (0..1) nel rettangolo del Control.
func _pts(units: Array) -> PackedVector2Array:
	var s := minf(size.x, size.y)
	var offset := (size - Vector2(s, s)) * 0.5
	var out := PackedVector2Array()
	for u in units:
		out.append(offset + Vector2(u[0], u[1]) * s)
	return out


func _shape(units: Array, fill: Color) -> void:
	var points := _pts(units)
	draw_colored_polygon(points, fill)
	var closed := PackedVector2Array(points)
	closed.append(points[0])
	draw_polyline(closed, outline, maxf(minf(size.x, size.y) * 0.06, 1.5), true)


func _stroke(units: Array, color: Color, width_units: float) -> void:
	draw_polyline(_pts(units), color, maxf(minf(size.x, size.y) * width_units, 1.5), true)


func _dot(center: Array, radius_units: float, color: Color) -> void:
	var s := minf(size.x, size.y)
	var p := _pts([center])[0]
	draw_circle(p, s * radius_units, color)


## Profilo dentato attorno a (cx, cy) in unita: denti fra raggio esterno e interno.
func _saw(cx: float, cy: float, outer: float, inner: float, teeth: int) -> Array:
	var points := []
	for k in teeth * 2:
		var angle := TAU * k / (teeth * 2)
		var r := outer if k % 2 == 0 else inner
		points.append([cx + cos(angle) * r, cy + sin(angle) * r])
	return points


func _draw() -> void:
	var dark := tint.darkened(0.35)
	match kind:
		&"nail":
			# Chiodo inclinato: gambo, punta e testa piatta.
			_shape([[0.62, 0.12], [0.74, 0.22], [0.34, 0.74], [0.24, 0.88], [0.2, 0.84], [0.26, 0.64]], tint)
			_shape([[0.56, 0.06], [0.84, 0.3], [0.78, 0.36], [0.5, 0.12]], dark)
		&"shovel":
			# Badile: manico con impugnatura a T e lama.
			_shape([[0.28, 0.1], [0.52, 0.1], [0.44, 0.18], [0.44, 0.5], [0.36, 0.5], [0.36, 0.18]], dark)
			_shape([[0.22, 0.48], [0.58, 0.48], [0.6, 0.72], [0.4, 0.94], [0.2, 0.72]], tint)
		&"boot":
			# Scarpone: gambale, collo del piede e suola.
			_shape([[0.3, 0.1], [0.56, 0.1], [0.56, 0.5], [0.84, 0.66], [0.84, 0.86], [0.22, 0.86], [0.22, 0.6], [0.3, 0.5]], tint)
			_shape([[0.2, 0.78], [0.86, 0.78], [0.86, 0.9], [0.2, 0.9]], dark)
		&"wrench":
			# Chiave inglese in diagonale.
			_shape([[0.2, 0.68], [0.32, 0.56], [0.62, 0.26], [0.56, 0.14], [0.68, 0.08], [0.84, 0.24], [0.78, 0.36], [0.66, 0.3], [0.36, 0.6], [0.3, 0.72], [0.24, 0.84], [0.12, 0.84], [0.12, 0.74]], tint)
		&"scrap":
			# Tre frammenti di metallo.
			_shape([[0.1, 0.62], [0.36, 0.5], [0.44, 0.74], [0.18, 0.86]], tint)
			_shape([[0.42, 0.14], [0.7, 0.24], [0.62, 0.52], [0.36, 0.42]], dark)
			_shape([[0.6, 0.58], [0.9, 0.56], [0.84, 0.86], [0.56, 0.82]], tint)
		&"bolt":
			# Bullone esagonale con il foro.
			var hexagon := []
			for k in 6:
				var angle := PI / 6.0 + k * PI / 3.0
				hexagon.append([0.5 + cos(angle) * 0.42, 0.5 + sin(angle) * 0.42])
			_shape(hexagon, tint)
			_dot([0.5, 0.5], 0.14, outline)
		&"skull":
			# Teschio tondo con due occhi e i denti.
			_shape([[0.24, 0.14], [0.76, 0.14], [0.88, 0.4], [0.8, 0.66], [0.66, 0.7], [0.66, 0.86], [0.34, 0.86], [0.34, 0.7], [0.2, 0.66], [0.12, 0.4]], tint)
			_dot([0.36, 0.42], 0.09, outline)
			_dot([0.64, 0.42], 0.09, outline)
			_stroke([[0.42, 0.72], [0.42, 0.84]], outline, 0.05)
			_stroke([[0.5, 0.72], [0.5, 0.84]], outline, 0.05)
			_stroke([[0.58, 0.72], [0.58, 0.84]], outline, 0.05)
		&"clock":
			# Orologio da taschino: quadrante, anello in alto, lancette.
			_shape([[0.44, 0.04], [0.56, 0.04], [0.56, 0.14], [0.44, 0.14]], dark)
			var circle := []
			for k in 20:
				var angle := k * TAU / 20.0
				circle.append([0.5 + cos(angle) * 0.4, 0.56 + sin(angle) * 0.4])
			_shape(circle, tint)
			_stroke([[0.5, 0.56], [0.5, 0.3]], outline, 0.06)
			_stroke([[0.5, 0.56], [0.68, 0.64]], outline, 0.06)
		&"lamp":
			# Lampione: palo, testa a campana e luce.
			_shape([[0.46, 0.38], [0.54, 0.38], [0.54, 0.9], [0.46, 0.9]], dark)
			_shape([[0.3, 0.9], [0.7, 0.9], [0.7, 0.96], [0.3, 0.96]], dark)
			_shape([[0.28, 0.36], [0.72, 0.36], [0.6, 0.12], [0.4, 0.12]], tint)
			_dot([0.5, 0.3], 0.1, Color("ffd45a"))
		&"arrow_right":
			# Chiodo orizzontale con la punta a destra: il cursore del focus.
			_shape([[0.06, 0.4], [0.62, 0.4], [0.62, 0.3], [0.94, 0.5], [0.62, 0.7], [0.62, 0.6], [0.06, 0.6]], tint)
			_shape([[0.04, 0.3], [0.14, 0.3], [0.14, 0.7], [0.04, 0.7]], dark)
		&"sack":
			# Zainetto di terra: sacca tonda con la patta e la cinghia.
			_shape([[0.22, 0.34], [0.78, 0.34], [0.86, 0.6], [0.78, 0.88], [0.22, 0.88], [0.14, 0.6]], tint)
			_shape([[0.26, 0.2], [0.74, 0.2], [0.8, 0.42], [0.2, 0.42]], dark)
			_stroke([[0.38, 0.2], [0.42, 0.08], [0.58, 0.08], [0.62, 0.2]], outline, 0.07)
		&"crate":
			# Cassone del compagno: cassa a doghe con le traverse.
			_shape([[0.12, 0.28], [0.88, 0.28], [0.88, 0.86], [0.12, 0.86]], tint)
			_stroke([[0.12, 0.47], [0.88, 0.47]], dark, 0.05)
			_stroke([[0.12, 0.67], [0.88, 0.67]], dark, 0.05)
			_stroke([[0.16, 0.32], [0.84, 0.82]], dark, 0.07)
		&"parachute":
			# Paracadute: calotta a spicchi, funi e un rottame appeso.
			_shape([[0.1, 0.42], [0.2, 0.22], [0.38, 0.1], [0.62, 0.1], [0.8, 0.22], [0.9, 0.42]], tint)
			_stroke([[0.1, 0.42], [0.46, 0.74]], outline, 0.04)
			_stroke([[0.9, 0.42], [0.54, 0.74]], outline, 0.04)
			_stroke([[0.5, 0.42], [0.5, 0.74]], outline, 0.04)
			_shape([[0.4, 0.72], [0.6, 0.72], [0.62, 0.9], [0.38, 0.9]], dark)
		&"stake":
			# Picchetto piantato con l'anello di terra che sale attorno.
			_stroke([[0.1, 0.78], [0.22, 0.66], [0.5, 0.6], [0.78, 0.66], [0.9, 0.78]], outline, 0.16)
			_stroke([[0.1, 0.78], [0.22, 0.66], [0.5, 0.6], [0.78, 0.66], [0.9, 0.78]], dark, 0.08)
			_shape([[0.42, 0.08], [0.58, 0.08], [0.58, 0.62], [0.5, 0.86], [0.42, 0.62]], tint)
			_shape([[0.36, 0.08], [0.64, 0.08], [0.64, 0.18], [0.36, 0.18]], dark)
		&"blade":
			# Lama circolare dentata col mozzo.
			_shape(_saw(0.5, 0.5, 0.42, 0.32, 12), tint)
			_dot([0.5, 0.5], 0.1, dark)
		&"hammer":
			# Martello pneumatico: maniglie, corpo e punta.
			_shape([[0.18, 0.12], [0.82, 0.12], [0.82, 0.24], [0.18, 0.24]], dark)
			_shape([[0.36, 0.22], [0.64, 0.22], [0.64, 0.66], [0.36, 0.66]], tint)
			_shape([[0.44, 0.64], [0.56, 0.64], [0.56, 0.84], [0.5, 0.94], [0.44, 0.84]], dark)
		&"ram":
			# Ariete: trave con la testa a cuneo e le linee della corsa.
			_stroke([[0.08, 0.36], [0.26, 0.36]], dark, 0.06)
			_stroke([[0.08, 0.64], [0.26, 0.64]], dark, 0.06)
			_shape([[0.24, 0.38], [0.66, 0.38], [0.66, 0.62], [0.24, 0.62]], tint)
			_shape([[0.64, 0.26], [0.92, 0.5], [0.64, 0.74]], dark)
		&"mixer":
			# Betoniera: tamburo inclinato sul telaio.
			_shape([[0.18, 0.3], [0.62, 0.14], [0.86, 0.46], [0.42, 0.66]], tint)
			_shape([[0.2, 0.66], [0.82, 0.66], [0.82, 0.76], [0.2, 0.76]], dark)
			_dot([0.3, 0.86], 0.08, dark)
			_dot([0.72, 0.86], 0.08, dark)
		&"dozer":
			# Ruspa a dischi: pala e due lame che spianano.
			_shape([[0.1, 0.22], [0.3, 0.22], [0.34, 0.78], [0.1, 0.78]], dark)
			_shape(_saw(0.6, 0.34, 0.2, 0.15, 10), tint)
			_shape(_saw(0.66, 0.72, 0.2, 0.15, 10), tint)
		&"compactor":
			# Costipatore: piastra che batte con le frecce verso il basso.
			_shape([[0.2, 0.62], [0.8, 0.62], [0.8, 0.8], [0.2, 0.8]], tint)
			_shape([[0.42, 0.14], [0.58, 0.14], [0.58, 0.62], [0.42, 0.62]], dark)
			_stroke([[0.1, 0.9], [0.9, 0.9]], dark, 0.06)
		&"scrap_launcher":
			# Lanciarottami: tubo inclinato e un rottame in parabola.
			_stroke([[0.36, 0.6], [0.5, 0.3], [0.7, 0.16], [0.86, 0.22]], dark, 0.05)
			_shape([[0.1, 0.72], [0.38, 0.5], [0.46, 0.62], [0.18, 0.86]], tint)
			_shape([[0.78, 0.12], [0.92, 0.18], [0.88, 0.32], [0.74, 0.26]], tint)
			_shape([[0.12, 0.86], [0.42, 0.86], [0.42, 0.94], [0.12, 0.94]], dark)
		&"dig_charge":
			# Carica da scavo: candelotto con la miccia e la scintilla.
			_shape([[0.3, 0.38], [0.7, 0.38], [0.7, 0.9], [0.3, 0.9]], tint)
			_stroke([[0.3, 0.52], [0.7, 0.52]], dark, 0.06)
			_stroke([[0.5, 0.38], [0.56, 0.22], [0.66, 0.14]], outline, 0.05)
			_dot([0.7, 0.12], 0.08, Color("ffd45a"))
		&"welder":
			# Saldatrice: pinza e arco spezzato.
			_shape([[0.1, 0.62], [0.34, 0.5], [0.42, 0.62], [0.18, 0.8]], dark)
			_stroke([[0.4, 0.52], [0.56, 0.4], [0.5, 0.3], [0.7, 0.2], [0.64, 0.12], [0.9, 0.06]], outline, 0.12)
			_stroke([[0.4, 0.52], [0.56, 0.4], [0.5, 0.3], [0.7, 0.2], [0.64, 0.12], [0.9, 0.06]], tint, 0.06)
		&"crane_magnet":
			# Calamita da gru: cavo e ferro di cavallo.
			_stroke([[0.5, 0.04], [0.5, 0.26]], dark, 0.06)
			_shape([[0.16, 0.26], [0.84, 0.26], [0.84, 0.86], [0.64, 0.86], [0.64, 0.46], [0.36, 0.46], [0.36, 0.86], [0.16, 0.86]], tint)
			_shape([[0.16, 0.76], [0.36, 0.76], [0.36, 0.86], [0.16, 0.86]], dark)
			_shape([[0.64, 0.76], [0.84, 0.76], [0.84, 0.86], [0.64, 0.86]], dark)
		&"scythe":
			# Falce: manico e lama ricurva.
			_stroke([[0.22, 0.92], [0.62, 0.12]], dark, 0.08)
			_shape([[0.6, 0.12], [0.9, 0.24], [0.94, 0.46], [0.8, 0.32], [0.56, 0.24]], tint)
		&"bramble":
			# Roveto: tre cespugli con le spine.
			_dot([0.3, 0.62], 0.2, tint)
			_dot([0.68, 0.6], 0.22, tint)
			_dot([0.5, 0.38], 0.2, dark)
			_stroke([[0.12, 0.5], [0.04, 0.44]], outline, 0.05)
			_stroke([[0.88, 0.46], [0.96, 0.38]], outline, 0.05)
			_stroke([[0.5, 0.18], [0.5, 0.08]], outline, 0.05)
		&"fort":
			# Fortino: cono di terra con la canna in cima.
			_shape([[0.08, 0.9], [0.4, 0.34], [0.6, 0.34], [0.92, 0.9]], tint)
			_shape([[0.44, 0.18], [0.84, 0.18], [0.84, 0.3], [0.44, 0.3]], dark)
		&"mortar":
			# Mortaio a crateri: buca e rottame che ci cade dentro.
			_shape([[0.06, 0.66], [0.3, 0.66], [0.38, 0.84], [0.62, 0.84], [0.7, 0.66], [0.94, 0.66], [0.94, 0.92], [0.06, 0.92]], dark)
			_shape(_saw(0.5, 0.32, 0.2, 0.14, 7), tint)
		&"tesla_coil":
			# Bobina di Tesla: colonna, sfera e scariche.
			_shape([[0.4, 0.4], [0.6, 0.4], [0.66, 0.92], [0.34, 0.92]], dark)
			_dot([0.5, 0.3], 0.18, tint)
			_stroke([[0.28, 0.24], [0.14, 0.14], [0.2, 0.06]], tint, 0.05)
			_stroke([[0.72, 0.24], [0.86, 0.14], [0.8, 0.06]], tint, 0.05)
		&"scythe_bramble":
			# Falciarovi: falce sopra un cespuglio di rovi.
			_dot([0.34, 0.74], 0.18, dark)
			_dot([0.64, 0.76], 0.16, dark)
			_stroke([[0.16, 0.6], [0.58, 0.08]], outline, 0.08)
			_shape([[0.56, 0.08], [0.88, 0.2], [0.92, 0.42], [0.78, 0.28], [0.52, 0.2]], tint)
		&"turret":
			# Torretta della carovana: zoccolo, testa con l'oblo e canna con la bocca.
			_shape([[0.16, 0.9], [0.84, 0.9], [0.72, 0.7], [0.28, 0.7]], dark)
			_shape([[0.2, 0.72], [0.2, 0.46], [0.32, 0.3], [0.58, 0.3], [0.7, 0.46], [0.7, 0.72]], tint)
			_shape([[0.62, 0.4], [0.88, 0.4], [0.88, 0.54], [0.62, 0.54]], dark)
			_shape([[0.84, 0.36], [0.94, 0.36], [0.94, 0.58], [0.84, 0.58]], tint)
			_dot([0.4, 0.52], 0.07, outline)
		&"magnet":
			# Calamita a ferro di cavallo inclinata, coi poli scuri e un frammento attirato.
			var horseshoe := [[0.74, 0.56]]
			for k in 9:
				var angle := PI * 0.25 + k * PI / 8.0
				horseshoe.append([0.42 + cos(angle) * 0.215, 0.58 + sin(angle) * 0.215])
			horseshoe.append([0.44, 0.26])
			_stroke(horseshoe, outline, 0.27)
			_stroke(horseshoe, tint, 0.17)
			_shape([[0.62, 0.56], [0.68, 0.5], [0.8, 0.62], [0.74, 0.68]], dark)
			_shape([[0.32, 0.26], [0.38, 0.2], [0.5, 0.32], [0.44, 0.38]], dark)
			_shape([[0.76, 0.12], [0.86, 0.24], [0.76, 0.36], [0.66, 0.24]], tint)
		&"beacon":
			# Faro: lanterna accesa sul palo, tetto a punta e due fasci di luce.
			var light := Color("ffd45a")
			_shape([[0.4, 0.36], [0.06, 0.22], [0.06, 0.58], [0.4, 0.48]], light)
			_shape([[0.6, 0.36], [0.94, 0.22], [0.94, 0.58], [0.6, 0.48]], light)
			_shape([[0.44, 0.52], [0.56, 0.52], [0.56, 0.86], [0.44, 0.86]], dark)
			_shape([[0.28, 0.84], [0.72, 0.84], [0.72, 0.94], [0.28, 0.94]], dark)
			_shape([[0.34, 0.28], [0.66, 0.28], [0.66, 0.56], [0.34, 0.56]], tint)
			_shape([[0.28, 0.3], [0.5, 0.08], [0.72, 0.3]], dark)
			_dot([0.5, 0.42], 0.08, light)
		&"drill":
			# Trivella: motore con le feritoie, mandrino e punta a spirale.
			_shape([[0.24, 0.06], [0.76, 0.06], [0.76, 0.32], [0.24, 0.32]], tint)
			_stroke([[0.36, 0.13], [0.36, 0.25]], dark, 0.05)
			_stroke([[0.5, 0.13], [0.5, 0.25]], dark, 0.05)
			_stroke([[0.64, 0.13], [0.64, 0.25]], dark, 0.05)
			_shape([[0.36, 0.32], [0.64, 0.32], [0.6, 0.44], [0.4, 0.44]], dark)
			_shape([[0.34, 0.44], [0.66, 0.44], [0.5, 0.96]], tint)
			_stroke([[0.37, 0.52], [0.6, 0.6]], dark, 0.05)
			_stroke([[0.42, 0.66], [0.56, 0.72]], dark, 0.05)
			_stroke([[0.46, 0.8], [0.53, 0.83]], dark, 0.05)
		&"scoop":
			# Pala meccanica: braccio, benna colma di terra e l'argine che alza.
			_shape([[0.06, 0.18], [0.14, 0.1], [0.46, 0.4], [0.38, 0.48]], dark)
			_shape([[0.42, 0.3], [0.5, 0.2], [0.62, 0.16], [0.72, 0.3]], dark)
			_shape([[0.4, 0.3], [0.74, 0.3], [0.9, 0.7], [0.5, 0.7], [0.4, 0.6], [0.36, 0.44]], tint)
			_shape([[0.08, 0.94], [0.2, 0.8], [0.38, 0.8], [0.5, 0.94]], dark)
		&"solder":
			# Cannello del Saldatore: impugnatura, ugello, fiamma e la croce della riparazione.
			_shape([[0.08, 0.8], [0.36, 0.52], [0.48, 0.64], [0.2, 0.92]], dark)
			_shape([[0.4, 0.5], [0.66, 0.24], [0.72, 0.3], [0.46, 0.56]], tint)
			_shape([[0.66, 0.2], [0.94, 0.06], [0.8, 0.34]], Color("ffd45a"))
			_stroke([[0.78, 0.58], [0.78, 0.9]], outline, 0.16)
			_stroke([[0.62, 0.74], [0.94, 0.74]], outline, 0.16)
			_stroke([[0.78, 0.58], [0.78, 0.9]], tint, 0.08)
			_stroke([[0.62, 0.74], [0.94, 0.74]], tint, 0.08)
		&"siren":
			# Sirena: lampeggiante a cupola sulla base, con le onde del richiamo ai lati.
			var dome := []
			for k in 9:
				var angle := PI + k * PI / 8.0
				dome.append([0.5 + cos(angle) * 0.24, 0.62 + sin(angle) * 0.24])
			_shape(dome, tint)
			_stroke([[0.3, 0.54], [0.7, 0.54]], dark, 0.06)
			_shape([[0.26, 0.62], [0.74, 0.62], [0.8, 0.8], [0.2, 0.8]], dark)
			for wave in [[[0.2, 0.34], [0.13, 0.46], [0.2, 0.58]], [[0.12, 0.24], [0.05, 0.46], [0.12, 0.68]],
					[[0.8, 0.34], [0.87, 0.46], [0.8, 0.58]], [[0.88, 0.24], [0.95, 0.46], [0.88, 0.68]]]:
				_stroke(wave, outline, 0.1)
				_stroke(wave, tint, 0.05)
		&"check":
			_stroke([[0.16, 0.52], [0.4, 0.78], [0.86, 0.26]], outline, 0.2)
			_stroke([[0.16, 0.52], [0.4, 0.78], [0.86, 0.26]], tint, 0.1)
		&"lock":
			# Lucchetto: arco e corpo.
			_stroke([[0.32, 0.46], [0.32, 0.26], [0.4, 0.14], [0.6, 0.14], [0.68, 0.26], [0.68, 0.46]], outline, 0.16)
			_stroke([[0.32, 0.46], [0.32, 0.26], [0.4, 0.14], [0.6, 0.14], [0.68, 0.26], [0.68, 0.46]], dark, 0.08)
			_shape([[0.2, 0.44], [0.8, 0.44], [0.8, 0.9], [0.2, 0.9]], tint)
			_dot([0.5, 0.64], 0.07, outline)
		_:
			_shape([[0.2, 0.2], [0.8, 0.2], [0.8, 0.8], [0.2, 0.8]], tint)
