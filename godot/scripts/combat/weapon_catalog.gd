class_name WeaponCatalog
extends RefCounted
## Armi della spec D-092 (docs/superpowers/specs/2026-10-15-weapons-classes-design.md, par. 4).
## Dati in un solo posto, come UpgradeCatalog. Ogni voce: id, name, deck (&"common" o una
## classe), slot (&"auto"/&"active"), partner (l'arma compagna della fusione), fusion, unlock_cost
## (rottami in Officina, 0 = sempre disponibile), icon (UiIcon), text, base (valori al livello 1),
## levels (modifiche ai livelli 2 e 4), level_texts, branches (due opzioni ai livelli 3 e 5).
## Le modifiche usano chiavi `<valore>_mul`, `<valore>_add`, `<valore>_set` e si applicano in
## ordine di livello: 2, bivio del 3, 4, bivio del 5. Valori di partenza, non bilanciati.

const MAX_LEVEL := 5
const BRANCH_LEVELS: Array[int] = [3, 5]


## Costruito una volta sola (review I-2: `stat` gira a ogni passo). Le voci sono condivise:
## chi le legge non le modifica.
static var _entries: Array[Dictionary] = []
static var _by_id: Dictionary[StringName, Dictionary] = {}


static func all() -> Array[Dictionary]:
	if _entries.is_empty():
		_entries = _build()
		for entry in _entries:
			_by_id[entry.id] = entry
	return _entries


static func _build() -> Array[Dictionary]:
	return [
		{id = &"nailgun", name = "Chiodatrice", deck = &"engineer", slot = &"auto", partner = &"seismic_stake",
			fusion = &"fort", unlock_cost = 0, icon = &"nail",
			text = "Chiodi dritti al bersaglio. Gli argini li fermano.",
			base = {fire_interval = 0.5, damage = 1.0, weapon_range = 9.0, pierce = 0.0, projectiles = 1.0,
				spread_degrees = 12.0, projectile_speed = 24.0},
			levels = {2: {fire_interval_mul = 0.8}, 4: {pierce_add = 1.0}},
			level_texts = {2: "Spara il 25% piu spesso.", 4: "Ogni chiodo trapassa un nemico in piu."},
			branches = {
				3: [
					{id = &"burst", name = "Raffica", text = "Cadenza doppia, chiodi un po' sparpagliati.",
						mods = {fire_interval_mul = 0.5, spread_jitter_set = 8.0}},
					{id = &"bridge", name = "Chiodi da ponte", text = "Trapassano tutto e fanno 2 danni, ma un colpo ogni 0,7 s.",
						mods = {pierce_set = 99.0, damage_set = 2.0, fire_interval_set = 0.7}},
				],
				5: [
					{id = &"ricochet", name = "Rimbalzanti", text = "Un chiodo che colpisce un argine rimbalza una volta.",
						mods = {bounces_set = 1.0}},
					{id = &"incendiary", name = "Incandescenti", text = "Ogni chiodo lascia una macchia di fuoco per 2 s.",
						mods = {fire_patch_set = 1.0}},
				],
			}},
		{id = &"seismic_stake", name = "Picchetto sismico", deck = &"engineer", slot = &"active", partner = &"nailgun",
			fusion = &"fort", unlock_cost = 0, icon = &"stake",
			text = "Pianti un picchetto: si alza un anello di argine che chiude dentro chi c'e.",
			base = {cooldown = 15.0, aim_range = 6.0, ring_radius = 3.0, ring_height = 1.2, ring_width = 0.8,
				raise_delay = 0.6, hold_seconds = 12.0},
			levels = {2: {cooldown_mul = 0.85}, 4: {cooldown_mul = 0.85}},
			level_texts = {2: "Si ricarica il 15% prima.", 4: "Si ricarica il 15% prima."},
			branches = {
				3: [
					{id = &"wide", name = "Anello largo", text = "L'anello ha raggio 4,5 m.", mods = {ring_radius_set = 4.5}},
					{id = &"permanent", name = "Argine permanente", text = "L'anello non torna giu.", mods = {permanent_set = 1.0}},
				],
				5: [
					{id = &"spiked", name = "Argine chiodato", text = "Chi spinge contro l'anello prende 1 danno ogni 0,6 s.",
						mods = {spike_damage_set = 1.0}},
					{id = &"shock", name = "Scossa", text = "Quando si alza fa 3 danni a chi ci sta sopra e lo scaglia fuori.",
						mods = {shock_damage_set = 3.0}},
				],
			}},
		# --- Guastatore (spec par. 4.2): scavo esplosivo ---------------------------------------
		{id = &"scrap_launcher", name = "Lanciarottami", deck = &"sapper", slot = &"auto", partner = &"dig_charge",
			fusion = &"mortar", unlock_cost = 0, icon = &"scrap_launcher",
			text = "Rottami a parabola sul gruppo piu fitto: scavalcano gli argini.",
			base = {fire_interval = 1.6, weapon_range = 12.0, blast_radius = 1.8, damage = 2.0, flight_seconds = 0.7},
			levels = {2: {blast_radius_add = 0.4}, 4: {fire_interval_mul = 0.8}},
			level_texts = {2: "Scoppio piu largo di 0,4 m.", 4: "Lancia il 25% piu spesso."},
			branches = {
				3: [
					{id = &"cluster", name = "Grappolo", text = "Allo scoppio tre frammenti colpiscono attorno.", mods = {cluster_set = 1.0}},
					{id = &"heavy", name = "Rottame pesante", text = "4 danni e spinge via.", mods = {damage_set = 4.0, shove_set = 6.0}},
				],
				5: [
					{id = &"caltrops", name = "Bulloni sparsi", text = "Lascia quattro triboli per 4 s: rallentano e feriscono.", mods = {caltrops_set = 1.0}},
					{id = &"crater", name = "Cratere", text = "Lo scoppio scava una buca.", mods = {crater_set = 1.0}},
				],
			}},
		{id = &"dig_charge", name = "Carica da scavo", deck = &"sapper", slot = &"active", partner = &"scrap_launcher",
			fusion = &"mortar", unlock_cost = 0, icon = &"dig_charge",
			text = "Una carica che dopo un secondo esplode e apre un cratere.",
			base = {cooldown = 8.0, aim_range = 6.0, fuse_seconds = 1.0, damage = 4.0, blast_radius = 2.5,
				crater_radius = 2.0, crater_depth = 0.8, charges = 1.0, uses = 1.0},
			levels = {2: {damage_add = 1.0}, 4: {cooldown_mul = 0.85}},
			level_texts = {2: "Un danno in piu.", 4: "Si ricarica il 15% prima."},
			branches = {
				3: [
					{id = &"cluster", name = "Grappolo", text = "Tre cariche minori a ventaglio.",
						mods = {charges_set = 3.0, damage_set = 2.0, crater_depth_set = 0.4}},
					{id = &"pit", name = "Pozzo", text = "Un cratere profondo: chi ci cade resta dentro.",
						mods = {crater_depth_set = 1.6, pit_set = 1.0}},
				],
				5: [
					{id = &"double", name = "Doppia carica", text = "Due cariche per ricarica.", mods = {uses_set = 2.0}},
					{id = &"mine", name = "Mina", text = "Resta a terra finche un nemico la calpesta (fino a due).", mods = {mine_set = 1.0}},
				],
			}},
		# --- Meccanico (spec par. 4.3): compagno potenziato -------------------------------------
		{id = &"welder", name = "Saldatrice", deck = &"mechanic", slot = &"auto", partner = &"crane_magnet",
			fusion = &"tesla_coil", unlock_cost = 0, icon = &"welder",
			text = "Un arco elettrico salta da nemico a nemico; nei fossati salta piu lontano.",
			base = {fire_interval = 1.2, weapon_range = 6.0, jumps = 3.0, jump_range = 2.5, ditch_jump_range = 4.0,
				damage = 1.0, lead_range = 8.0, arcs = 1.0},
			levels = {2: {jumps_add = 1.0}, 4: {fire_interval_mul = 0.8}},
			level_texts = {2: "Un salto in piu.", 4: "Scarica il 25% piu spesso."},
			branches = {
				3: [
					{id = &"double_arc", name = "Arco doppio", text = "Due archi per colpo.", mods = {arcs_set = 2.0}},
					{id = &"fusion_point", name = "Punto di fusione", text = "3 danni al primo bersaglio, nessun salto.",
						mods = {damage_set = 3.0, jumps_set = 1.0}},
				],
				5: [
					{id = &"static", name = "Carica statica", text = "I colpiti restano elettrici 2 s e feriscono chi toccano.", mods = {static_set = 2.0}},
					{id = &"wire", name = "Filo teso", text = "Un filo fra te e il compagno ferisce chi lo attraversa.", mods = {wire_set = 1.0}},
				],
			}},
		{id = &"crane_magnet", name = "Calamita da gru", deck = &"mechanic", slot = &"active", partner = &"welder",
			fusion = &"tesla_coil", unlock_cost = 0, icon = &"crane_magnet",
			text = "Un elettromagnete tira i nemici verso il centro e l'esperienza verso di te.",
			base = {cooldown = 14.0, aim_range = 6.0, pull_radius = 6.0, pull_speed = 4.0, pull_seconds = 3.0, xp_radius = 10.0},
			levels = {2: {pull_radius_add = 1.0}, 4: {pull_seconds_add = 1.0}},
			level_texts = {2: "Raggio piu largo di 1 m.", 4: "Tira un secondo in piu."},
			branches = {
				3: [
					{id = &"crush", name = "Schiacciasassi", text = "Alla fine i nemici attratti si scontrano: 3 danni.", mods = {crush_set = 3.0}},
					{id = &"mobile", name = "Gru mobile", text = "La calamita si monta sul compagno e lo segue.", mods = {mobile_set = 1.0}},
				],
				5: [
					{id = &"repel", name = "Polarita inversa", text = "Alla fine respinge forte: contro un argine danno doppio.", mods = {repel_set = 1.0}},
					{id = &"salvage", name = "Raccolta", text = "Attira anche i rottami a terra e li porta al compagno.", mods = {salvage_set = 1.0}},
				],
			}},
		# --- Erbacciaia (spec par. 4.4): vegetazione come difesa --------------------------------
		{id = &"scythe", name = "Falce rotante", deck = &"weeder", slot = &"auto", partner = &"bramble",
			fusion = &"scythe_bramble", unlock_cost = 0, icon = &"scythe",
			text = "Falci che ti girano attorno; sul prato girano piu veloci.",
			base = {blades = 2.0, orbit_radius = 2.2, orbit_seconds = 1.5, damage = 1.0, hit_interval = 0.5, meadow_speed = 1.3},
			levels = {2: {blades_add = 1.0}, 4: {orbit_radius_add = 0.5}},
			level_texts = {2: "Una falce in piu.", 4: "Girano mezzo metro piu larghe."},
			branches = {
				3: [
					{id = &"long", name = "Falce lunga", text = "Girano a 3,2 m.", mods = {orbit_radius_set = 3.2}},
					{id = &"sharp", name = "Falce affilata", text = "2 danni.", mods = {damage_set = 2.0}},
				],
				5: [
					{id = &"haymaking", name = "Fienagione", text = "Dove muore un nemico cresce un ciuffo di prato.", mods = {haymaking_set = 1.0}},
					{id = &"furrow", name = "Pale da scavo", text = "Lasciano un anello di terra smossa che rallenta.", mods = {furrow_set = 1.0}},
				],
			}},
		{id = &"bramble", name = "Roveto", deck = &"weeder", slot = &"active", partner = &"scythe",
			fusion = &"scythe_bramble", unlock_cost = 0, icon = &"bramble",
			text = "Un seme fa crescere una siepe di rovi che rallenta e ferisce.",
			base = {cooldown = 12.0, aim_range = 5.0, hedge_length = 6.0, grow_seconds = 1.0, hedge_seconds = 15.0,
				slow = 0.5, damage = 1.0, damage_interval = 0.8, hedge_hp = 20.0},
			levels = {2: {hedge_seconds_add = 5.0}, 4: {cooldown_mul = 0.85}},
			level_texts = {2: "La siepe dura 5 s in piu.", 4: "Si ricarica il 15% prima."},
			branches = {
				3: [
					{id = &"ring", name = "Cerchio di rovi", text = "Un anello chiuso di rovi.", mods = {ring_set = 2.5}},
					{id = &"long_thorns", name = "Spine lunghe", text = "2 danni.", mods = {damage_set = 2.0}},
				],
				5: [
					{id = &"roots", name = "Radici", text = "Chi entra resta fermo 1,5 s.", mods = {roots_set = 1.5}},
					{id = &"advance", name = "Rovo che avanza", text = "La siepe cresce verso i nemici.", mods = {advance_set = 1.0}},
				],
			}},
		# --- Fusioni di classe (par. 4.1-4.4) ---------------------------------------------------
		{id = &"fort", name = "Fortino", deck = &"engineer", slot = &"fusion", parts = [&"nailgun", &"seismic_stake"],
			icon = &"fort", unlock_cost = 0,
			text = "Ogni 10 s alza un argine-torretta che spara chiodi per 8 s; al massimo due.",
			base = {every = 10.0, reach = 5.0, turret_seconds = 8.0, turret_height = 1.5, rate = 0.7, max_turrets = 2.0}},
		{id = &"mortar", name = "Mortaio a crateri", deck = &"sapper", slot = &"fusion", parts = [&"scrap_launcher", &"dig_charge"],
			icon = &"mortar", unlock_cost = 0,
			text = "Ogni rottame apre un cratere; ogni quarto colpo e una carica da scavo completa.",
			base = {crater_depth = 0.5, crater_radius = 1.0, charge_every = 4.0}},
		{id = &"tesla_coil", name = "Bobina di Tesla", deck = &"mechanic", slot = &"fusion", parts = [&"welder", &"crane_magnet"],
			icon = &"tesla_coil", unlock_cost = 0,
			text = "Un campo attorno a te e al compagno attira piano e scarica archi su chi c'e dentro.",
			base = {field_radius = 5.0, field_pull = 1.5, arc_interval = 0.6}},
		{id = &"scythe_bramble", name = "Falciarovi", deck = &"weeder", slot = &"fusion", parts = [&"scythe", &"bramble"],
			icon = &"scythe_bramble", unlock_cost = 0,
			text = "Le falci lasciano dietro una scia di rovi.",
			base = {trail_seconds = 4.0, trail_every = 0.3}},
		# --- Kit comune (spec par. 4.5): si sblocca in Officina -------------------------------
		{id = &"site_blade", name = "Lama da cantiere", deck = &"common", slot = &"auto", partner = &"ram",
			fusion = &"disc_dozer", unlock_cost = 15, icon = &"blade",
			text = "Lancia un disco che rotola: in discesa accelera, nei fossati gira sul fondo.",
			base = {fire_interval = 2.5, damage = 2.0, weapon_range = 10.0, projectile_speed = 8.0, travel = 10.0,
				disc_radius = 0.4, discs = 1.0, twin_angle = 15.0, ditch_seconds = 3.0},
			levels = {2: {damage_add = 1.0}, 4: {fire_interval_mul = 0.8}},
			level_texts = {2: "Un danno in piu.", 4: "Lancia il 25% piu spesso."},
			branches = {
				3: [
					{id = &"twin", name = "Due lame", text = "Due dischi per lancio, a ventaglio.", mods = {discs_set = 2.0}},
					{id = &"serrated", name = "Lama dentata", text = "Disco piu grande, ma piu lento.",
						mods = {disc_radius_mul = 1.6, projectile_speed_mul = 0.7}},
				],
				5: [
					{id = &"rebound", name = "Rimbalzo", text = "Rimbalza sugli argini fino a tre volte.", mods = {bounces_set = 3.0}},
					{id = &"groove", name = "Solco", text = "Dove passa scava un solco.", mods = {groove_set = 1.0}},
				],
			}},
		{id = &"jackhammer", name = "Martello pneumatico", deck = &"common", slot = &"auto", partner = &"cement_mixer",
			fusion = &"compactor", unlock_cost = 15, icon = &"hammer",
			text = "Un'onda attorno a te spinge via l'orda; chi sbatte contro un argine prende il doppio.",
			base = {fire_interval = 2.0, damage = 1.0, wave_radius = 3.0, shove_speed = 6.0},
			levels = {2: {wave_radius_add = 0.5}, 4: {damage_add = 1.0}},
			level_texts = {2: "Onda piu larga di mezzo metro.", 4: "Un danno in piu."},
			branches = {
				3: [
					{id = &"wide", name = "Onda larga", text = "L'onda arriva a 5 m.", mods = {wave_radius_set = 5.0}},
					{id = &"stunning", name = "Stordente", text = "Chi e colpito resta fermo 0,8 s.", mods = {stun_set = 0.8}},
				],
				5: [
					{id = &"cracks", name = "Crepe", text = "Ogni onda apre tre crateri attorno a te.", mods = {cracks_set = 1.0}},
					{id = &"echo", name = "Eco nei fossati", text = "L'onda colpisce anche chi sta in basso fino a 8 m.", mods = {echo_set = 1.0}},
				],
			}},
		{id = &"ram", name = "Ariete", deck = &"common", slot = &"active", partner = &"site_blade",
			fusion = &"disc_dozer", unlock_cost = 20, icon = &"ram",
			text = "Carichi in avanti, intoccabile: travolgi l'orda e spiani il terreno.",
			base = {cooldown = 10.0, aim_range = 8.0, charge_distance = 8.0, charge_seconds = 0.5, damage = 3.0,
				hit_radius = 1.2, shove_speed = 7.0},
			levels = {2: {damage_add = 1.0}, 4: {cooldown_mul = 0.85}},
			level_texts = {2: "Un danno in piu.", 4: "Si ricarica il 15% prima."},
			branches = {
				3: [
					{id = &"long", name = "Rincorsa", text = "La carica arriva a 12 m.", mods = {charge_distance_set = 12.0}},
					{id = &"shield", name = "Scudo", text = "All'arrivo resti intoccabile 1,5 s.", mods = {shield_set = 1.5}},
				],
				5: [
					{id = &"trench", name = "Trincea", text = "Invece di spianare scava un fossato lungo la carica.", mods = {trench_set = 1.0}},
					{id = &"blast", name = "Botto", text = "All'arrivo un'onda: 3 danni entro 3 m.", mods = {blast_set = 3.0}},
				],
			}},
		{id = &"cement_mixer", name = "Betoniera", deck = &"common", slot = &"active", partner = &"jackhammer",
			fusion = &"compactor", unlock_cost = 20, icon = &"mixer",
			text = "Una pozza di cemento blocca chi c'e dentro, poi indurisce in un dosso.",
			base = {cooldown = 12.0, aim_range = 6.0, pool_radius = 2.5, block_seconds = 3.0, bump_height = 0.4, pools = 1.0},
			levels = {2: {pool_radius_add = 0.5}, 4: {block_seconds_add = 1.0}},
			level_texts = {2: "Pozza piu larga di mezzo metro.", 4: "Blocca un secondo in piu."},
			branches = {
				3: [
					{id = &"double", name = "Doppia colata", text = "Due pozze affiancate.", mods = {pools_set = 2.0}},
					{id = &"wall", name = "Muro di getto", text = "Il dosso sale a 1,2 m: un argine.", mods = {bump_height_set = 1.2}},
				],
				5: [
					{id = &"quickset", name = "Presa rapida", text = "Quando indurisce fa 3 danni a chi e bloccato.", mods = {set_damage_set = 3.0}},
					{id = &"pavement", name = "Pavimento", text = "Invece del dosso spiana alla base: una piazzola liscia.", mods = {flatten_set = 1.0}},
				],
			}},
		# --- Fusioni comuni (par. 4.5): l'automatica resta e aggiunge questo effetto -----------
		{id = &"disc_dozer", name = "Ruspa a dischi", deck = &"common", slot = &"fusion", parts = [&"site_blade", &"ram"],
			icon = &"dozer", unlock_cost = 0,
			text = "Dischi grandi il doppio che spianano dove passano; ogni 10 s un disco enorme dritto per 20 m.",
			base = {radius_mul = 2.0, big_every = 10.0, big_travel = 20.0, big_radius = 1.6}},
		{id = &"compactor", name = "Costipatore", deck = &"common", slot = &"fusion", parts = [&"jackhammer", &"cement_mixer"],
			icon = &"compactor", unlock_cost = 0,
			text = "Ogni onda blocca per un attimo; ogni terza lascia un anello di cemento.",
			base = {stun = 0.6, ring_every = 3.0, ring_height = 0.3}},
	]


static func find(id: StringName) -> Dictionary:
	if _entries.is_empty():
		all()
	return _by_id.get(id, {})


## Valore [param key] dell'arma al livello dato, coi bivi presi ({3: &"a"|&"b", 5: ...}).
## Un valore assente dalla base vale 0 (i flag dei bivi: bounces, fire_patch, permanent...).
static func stat(id: StringName, key: StringName, level: int, branches: Dictionary) -> float:
	var entry := find(id)
	if entry.is_empty():
		return 0.0
	var value := float((entry.base as Dictionary).get(key, 0.0))
	for at in range(2, mini(level, MAX_LEVEL) + 1):
		var mods: Dictionary = {}
		if BRANCH_LEVELS.has(at):
			var options: Array = (entry.branches as Dictionary).get(at, [])
			var pick: StringName = branches.get(at, &"")
			if pick == &"a" and options.size() > 0:
				mods = options[0].mods
			elif pick == &"b" and options.size() > 1:
				mods = options[1].mods
		else:
			mods = (entry.levels as Dictionary).get(at, {})
		value = _apply(value, key, mods)
	return value


## Applica a [param value] le modifiche di [param mods] per [param key] (`_set`, `_mul`, `_add`):
## le stesse dei bivi, usate anche per gli upgrade permanenti dell'Officina.
static func apply_mods(value: float, key: StringName, mods: Dictionary) -> float:
	return _apply(value, key, mods) if not mods.is_empty() else value


static func _apply(value: float, key: StringName, mods: Dictionary) -> float:
	var set_key := StringName("%s_set" % key)
	if mods.has(set_key):
		value = float(mods[set_key])
	var mul_key := StringName("%s_mul" % key)
	if mods.has(mul_key):
		value *= float(mods[mul_key])
	var add_key := StringName("%s_add" % key)
	if mods.has(add_key):
		value += float(mods[add_key])
	return value


## Fusione dell'automatica [param auto_id] (voce con `slot == &"fusion"` che la contiene), o &"".
static func fusion_of(auto_id: StringName) -> StringName:
	var entry := find(auto_id)
	if entry.is_empty() or entry.slot != &"auto":
		return &""
	for candidate in all():
		if candidate.slot == &"fusion" and (candidate.parts as Array).has(auto_id):
			return candidate.id
	return &""


## Le due trasformazioni al livello [param at_level] (3 o 5), vuoto altrove.
static func branch_options(id: StringName, at_level: int) -> Array[Dictionary]:
	var entry := find(id)
	var out: Array[Dictionary] = []
	if entry.is_empty():
		return out
	# Le fusioni non hanno bivi.
	for option: Dictionary in (entry.get(&"branches", {}) as Dictionary).get(at_level, []):
		out.append(option)
	return out
