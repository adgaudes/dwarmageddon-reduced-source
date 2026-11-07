class_name PlayerCharacter
extends CharacterBody3D
## Personaggio graybox: porta di APrototype01Character.
##
## Movimento planare analogico, orientamento indipendente (stick destro o mouse
## deproiettato sul piano del personaggio), commutazione automatica del
## dispositivo di mira, dash con cooldown e feedback solo visivo, tool terreno
## con bersaglio fisso davanti al personaggio.
## L'origine e al centro della capsula, come la location dell'attore Unreal.

signal dash_started
signal dash_ready
signal aim_device_changed(device: AimDevice)
signal health_changed(health: int, max_health: int)
## Colpo andato a segno (dopo il calcolo della vita): spinta dei nemici e lampo del HUD.
signal damaged(amount: int)
signal died
## Lo strumento terreno non ha potuto agire: cella non valida o niente rottami.
signal terrain_tool_rejected
signal terrain_mode_changed(mode: int)
## Rampa d'uscita ritagliata nella parete di una buca (playtest O-03).
signal escape_ramp_carved
## Mira della chiodatrice cambiata (D-089): AimMode.AUTO o AimMode.MANUAL.
signal aim_mode_changed(mode: int)
## Fine della carica dell'Ariete (D-092).
signal charge_finished
## Tasto di un'arma attiva premuto (D-092): slot 0 (E, grilletto sinistro) o 1 (F, dorsale destro).
signal active_weapon_pressed(slot: int)
## Prima pressione di Interagisci (X, R; carovana D-093): tenerlo premuto ripara (`interact_held`).
signal interact_pressed

enum AimMode { AUTO, MANUAL }
## Dopo un colpo in mira automatica il corpo guarda il bersaglio per questo tempo (O-04).
const SHOT_FACING_SECONDS := 0.35
const SHOT_FACING_SPEED := 28.0
var aim_mode := AimMode.AUTO
var _shot_facing := Vector3.ZERO
var _shot_facing_left := 0.0

enum AimDevice { GAMEPAD, MOUSE }

## Azioni con semantica Started di Unreal: un comando per pressione.
const STARTED_ACTIONS: Array[StringName] = [&"dash", &"terrain_tool", &"terrain_mode", &"weapon_aim_mode",
	&"weapon_active_1", &"weapon_active_2", &"interact"]

const BODY_COLOR_LINEAR := Color(1.0, 0.35, 0.02)
const HIT_COLOR_LINEAR := Color(1.0, 0.02, 0.02)
const HIT_FLASH_SECONDS := 0.3

# --- Movimento procedurale (ActorMotion): solo sul nodo visivo `Model`. La scala del
# dash resta su `_body` (figlio di `Model`) e i colori sul materiale: si compongono.
# Il passo non e qui: lo fanno le animazioni dello scheletro (`_animator`, D-060).
# I parametri (inclinazione, impulsi del dash, rinculo, sussulto) sono nel PlayerTuning,
# gruppo "Motion" (R-41).

@export var tuning: PlayerTuning
## Rilievo continuo (D-082) su cui agisce il pennello. Opzionale.
@export var terrain_field: TerrainField
## Lampioni (D-058, tappa 2): senza, il tool cicla solo fra scavo e rialzo.
@export var lamp_field: LampField
## Opzionale: nodo col segnale `fired` (la chiodatrice). Se presente ogni colpo da un
## rinculo visivo; se ha `last_fire_direction` il rinculo e opposto al colpo.
@export var recoil_source: Node

## Scala la velocita massima senza toccare il tuning; ricalcolato a ogni passo
## dalla cella sotto il personaggio (UpdateTerrainSpeedModifier).
var speed_multiplier := 1.0
var aim_device := AimDevice.GAMEPAD
var is_dashing := false
var is_dash_on_cooldown := false
var terrain_tool_mode: int = TerrainField.ToolMode.DIG
const TOOL_MODE_NAMES: Array[String] = ["Dig", "Raise", "Level", "Lamp"]
## Pennello continuo (D-082): vero finche il tasto del tool e premuto.
var tool_held := false
## Interagisci tenuto premuto (riparazione della carovana, D-093), per sorgente come `tool_held`.
## Bot, test e catture possono impostarlo a mano: la rete di sicurezza vale solo per le pressioni
## nate da eventi.
var interact_held := false
## A bordo di una macchina: la imposta il piano C.
var pilot: Node3D = null
## Attesa prima del prossimo affondo dell'animazione di scavo.
var _dig_anim_left := 0.0
var pack: SoilPack
var brush_radius_bonus_m := 0.0
## Terra chiesta allo zaino per metro cubo alzato (Getto rapido: 0,8 al primo livello).
var raise_cost_scale := 1.0
## Colore della tuta a riposo (lineare): l'arancio dell'Ingegnere o quello della classe.
var body_color_linear := BODY_COLOR_LINEAR
var tool_range_bonus_m := 0.0
var _preview: BrushPreview
var _brush_was_blocked := false
## Punto mondo bersaglio del tool, aggiornato a ogni passo fisico.
var terrain_target := Vector3.ZERO
## Punti vita (prototipo della promessa A, D-038). Senza un ArenaRun che li
## imposta il personaggio non muore: le altre scene restano invariate.
var max_health := 0
var health := 0
var invulnerability_seconds := 0.8
## Moltiplicatore permanente della velocita (upgrade), combinato col terreno.
var speed_bonus := 1.0
var _invulnerable_left := 0.0
## Carica dell'Ariete (D-092): secondi rimasti e velocita imposta, intoccabile finche dura.
var _charge_left := 0.0
var _charge_velocity := Vector3.ZERO

var _movement := PlanarMovement.new()
## Ultima direzione di movimento valida (normalizzata): direzione del dash.
var _last_valid_move_direction := Vector3.ZERO
var _dash_direction := Vector3.ZERO
## Tempo dall'attivazione del dash: durata e cooldown si misurano entrambi da qui.
var _time_since_dash := 0.0
var _effective_dash_duration := 0.0
## Per azione: le sorgenti (classe dell'evento: tasto, pulsante o asse del joypad, mouse)
## che la tengono premuta. Il comando parte solo quando nessuna sorgente la tiene (P-02).
var _held_actions: Dictionary[StringName, Dictionary] = {}
var _pending_actions: Array[StringName] = []
## Spostamento del mouse sommato nella finestra corrente e tempo che resta alla finestra (P-01).
var _mouse_delta_accum := 0.0
var _mouse_delta_window_left := 0.0
## Secondi dall'ultimo movimento del mouse.
var _mouse_idle_seconds := 0.0
## Stick sinistro letto dagli eventi del joypad (non dalle azioni: la tastiera non conta).
var _left_stick := Vector2.ZERO
var _body_material := StandardMaterial3D.new()
var _base_body_scale := Vector3.ONE
var _hit_flash_left := 0.0
## Stato del movimento procedurale (vedi le costanti LEAN_*, DASH_*, RECOIL_*, FLINCH_*).
var _model_rest := Transform3D.IDENTITY
var _lean_pitch := 0.0
var _lean_roll := 0.0
var _was_dashing := false
## Negativo = schiacciato (partenza del dash), positivo = allungato (arrivo); torna a 0.
var _dash_pulse := 0.0
var _recoil := 0.0
## Direzione del rinculo nello spazio del personaggio (unitaria).
var _recoil_direction := Vector3.BACK
var _flinch := 0.0
var _motion_at_rest := true

## Mesh del modello (tools/blender/build_actor_assets.py, `player_engineer`): la tuta
## e la superficie `suit`, colorata da `_body_material`; il resto ha colori fissi.
@onready var _body: MeshInstance3D = ActorModel.mesh_instance_of($Model)
@onready var _collision: CollisionShape3D = $Collision
## Radice del modello: l'unico nodo mosso dal movimento procedurale.
@onready var _model: Node3D = $Model
## Animazioni dello scheletro (corsa, mira, scavo, schivata, colpo, morte); null se il modello non ne ha.
@onready var _animator: CharacterAnimator = CharacterAnimator.attach($Model)
## Zainetto di terra sul modello (spec sezione 3): sacca e striscia indicatore.
const PACK_GAUGE_SHADER := preload("res://resources/materials/pack_gauge.gdshader")
const PACK_FULL_SCALE := 1.12
var _pack_sack: MeshInstance3D
var _pack_gauge_material: ShaderMaterial


func _ready() -> void:
	if tuning == null:
		tuning = PlayerTuning.new()
	_movement.configure(tuning)

	# La tuta: la tinta e lo stato (dash, colpo) va in `albedo_color`. Col modello rifinito
	# (D-071) l'ombreggiatura sta nella texture cotta; con quello a blocchi nel colore di vertice.
	var suit_source := ActorModel.surface_material(_body, "suit") as StandardMaterial3D
	if suit_source != null and suit_source.albedo_texture != null:
		_body_material.albedo_texture = suit_source.albedo_texture
		_body_material.roughness = suit_source.roughness
		ActorModel.copy_normal_map(suit_source, _body_material)
	else:
		_body_material.vertex_color_use_as_albedo = true
		_body_material.roughness = 0.8
	ActorModel.enable_rim(_body_material)
	_body_material.next_pass = ActorModel.outline_material()
	var overrides: Dictionary[String, Material] = {"suit": _body_material}
	if ActorModel.surface_material(_body, "detail") != null:
		# Modello a blocchi: lampada dell'elmetto e punta dell'attrezzo dallo shader a colori di vertice.
		overrides["detail"] = ActorModel.paint_material(Color.WHITE, 2.5)
	ActorModel.apply_materials(_body, overrides)
	ActorModel.outline_remaining_surfaces(_body)
	_base_body_scale = _body.scale
	_set_body_color(body_color_linear)
	_model_rest = _model.transform
	_setup_pack_sack()
	if recoil_source != null and recoil_source.has_signal(&"fired"):
		recoil_source.connect(&"fired", _on_recoil_source_fired)

	if terrain_field != null:
		pack = SoilPack.new(terrain_field.tuning.pack_capacity_m3, terrain_field.tuning.pack_start_m3)
		pack.changed.connect(_on_pack_changed)
		_on_pack_changed(pack.amount, pack.capacity)
		_preview = BrushPreview.new()
		_preview.name = "BrushPreview"
		add_child(_preview)
		_preview.top_level = true
		floor_max_angle = atan(terrain_field.tuning.max_grade)

	print("PROTOTYPE01_CHARACTER_READY")
	if terrain_field != null:
		_update_terrain_target()
		print("PROTOTYPE01_TERRAIN_MODE Dig")


func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		# Spostamento cumulativo in una finestra breve: un tocco del trackpad o del
		# giroscopio (frazioni di pixel) non ruba la mira al controller.
		if _mouse_delta_window_left <= 0.0:
			_mouse_delta_accum = 0.0
			_mouse_delta_window_left = tuning.mouse_aim_delta_window
		_mouse_delta_accum += motion.relative.length()
		_mouse_idle_seconds = 0.0
		if _mouse_delta_accum >= tuning.mouse_aim_delta_threshold:
			_mouse_delta_accum = 0.0
			_mouse_delta_window_left = 0.0
			_set_aim_device(AimDevice.MOUSE)
		return
	var joy := event as InputEventJoypadMotion
	if joy != null:
		if joy.axis == JOY_AXIS_LEFT_X:
			_left_stick.x = joy.axis_value
		elif joy.axis == JOY_AXIS_LEFT_Y:
			_left_stick.y = joy.axis_value


## Rileva il fronte di pressione: un grilletto analogico invia un evento a ogni
## variazione sopra la dead zone e non deve ripetere il comando. I modificatori
## sono ignorati come in Unreal. Il comando e eseguito al passo fisico successivo,
## come l'input Unreal elaborato prima del Tick: nessuna pressione va persa.
## Ogni sorgente (tasto, grilletto, pulsante, mouse) tiene l'azione per conto suo:
## rilasciarne una mentre un'altra e premuta non riarma il comando (P-02).
func _unhandled_input(event: InputEvent) -> void:
	# Una ripetizione automatica del tasto non e ne pressione ne rilascio (audit I-03).
	if event.is_echo():
		return
	for action in STARTED_ACTIONS:
		if not event.is_action(action):
			continue
		var sources: Dictionary = _held_actions.get_or_add(action, {})
		var was_held := not sources.is_empty()
		var source := event.get_class()
		if event.is_action_pressed(action):
			sources[source] = true
			if not was_held:
				if action == &"terrain_tool" and terrain_field != null:
					tool_held = true
				elif action == &"interact":
					interact_held = true
					interact_pressed.emit()
				else:
					_pending_actions.append(action)
		else:
			sources.erase(source)
			if action == &"terrain_tool" and terrain_field != null and sources.is_empty():
				tool_held = false
			if action == &"interact" and sources.is_empty():
				interact_held = false


## Un rilascio avvenuto in pausa non arriva mai: alla ripresa nessuna azione e
## "ancora premuta", altrimenti la pressione successiva verrebbe scartata (R-17). Lo stesso
## quando la finestra perde il focus: Godot svuota lo stato di Input senza eventi, e il
## pennello scaverebbe da solo fino al clic successivo (audit I-01).
func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_held_actions.clear()
		_pending_actions.clear()
		tool_held = false
		interact_held = false
		_left_stick = Vector2.ZERO


func _run_pending_actions() -> void:
	for action in _pending_actions:
		match action:
			&"dash":
				_start_dash()
			&"terrain_mode":
				_toggle_terrain_mode()
			&"weapon_aim_mode":
				toggle_aim_mode()
			&"weapon_active_1":
				active_weapon_pressed.emit(0)
			&"weapon_active_2":
				active_weapon_pressed.emit(1)
	_pending_actions.clear()


func _physics_process(delta: float) -> void:
	_run_pending_actions()
	_update_terrain_speed_modifier()
	var move_direction := _read_move_direction()

	var aim_input := _raw_aim_input()
	var dead_zone_sq := tuning.aim_stick_dead_zone * tuning.aim_stick_dead_zone
	_mouse_idle_seconds += delta
	_mouse_delta_window_left = maxf(_mouse_delta_window_left - delta, 0.0)
	if aim_input.length_squared() > dead_zone_sq:
		_set_aim_device(AimDevice.GAMEPAD)
	elif _left_stick.length_squared() > dead_zone_sq and _mouse_idle_seconds > tuning.mouse_aim_idle_seconds:
		# Si gioca col controller e il mouse e fermo: la mira torna allo stick.
		_set_aim_device(AimDevice.GAMEPAD)
	_apply_facing_rotation(aim_input, delta)

	var planar := Vector3(velocity.x, 0.0, velocity.z)
	var requested := Vector3.ZERO
	if is_dashing:
		planar = _dash_direction * UnrealSpace.length(tuning.dash_speed_cm)
	else:
		requested = move_direction.limit_length(1.0)
	planar = _movement.calc_velocity(planar, requested, delta, speed_multiplier)
	if _charge_left > 0.0:
		planar = _charge_velocity

	velocity.x = planar.x
	velocity.z = planar.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity += get_gravity() * delta
	move_and_slide()

	# Dopo il movimento, come il TimerManager Unreal che avanza a fine tick.
	_update_dash_timers(delta)
	_update_hit_flash(delta)
	_update_pit_escape(delta, move_direction)
	_invulnerable_left = maxf(_invulnerable_left - delta, 0.0)
	_update_charge(delta)
	_dig_anim_left = maxf(_dig_anim_left - delta, 0.0)
	_update_terrain_target()
	# Rete di sicurezza (audit I-01): un rilascio che non e arrivato come evento. Solo per le
	# pressioni nate da eventi: bot, test e catture impostano `tool_held` direttamente.
	if tool_held and _held_actions.has(&"terrain_tool") and not Input.is_action_pressed(&"terrain_tool"):
		tool_held = false
		_held_actions.erase(&"terrain_tool")
	# Lo stesso per Interagisci, ma solo con una sorgente che lo tiene davvero (non `has`: la
	# voce resta vuota dopo ogni rilascio e spegnerebbe la tenuta impostata a mano).
	var interact_sources: Dictionary = _held_actions.get(&"interact", {})
	if interact_held and not interact_sources.is_empty() and not Input.is_action_pressed(&"interact"):
		interact_held = false
		_held_actions.erase(&"interact")
	if terrain_field != null and tool_held:
		_apply_brush(delta)
	else:
		_brush_was_blocked = false
	_update_motion(delta)


## Buca senza uscita (playtest O-03): se si spinge contro una parete troppo ripida e si
## resta fermi per ESCAPE_STUCK_SECONDS, la parete si ritaglia in una rampa percorribile
## nella direzione spinta. Scavare resta libero ovunque; uscire non richiede di sapere
## che si puo alzare terra.
const ESCAPE_STUCK_SECONDS := 0.9
const ESCAPE_RAMP_GRADE := 0.5
const ESCAPE_RAMP_STEP := 0.7
const ESCAPE_RAMP_STEPS := 7
const ESCAPE_RAMP_RADIUS := 1.2
## Profondita minima sotto la base perche la rampa scatti (m).
const ESCAPE_MIN_DEPTH := 0.5
var _stuck_seconds := 0.0
var escape_ramps := 0


func _update_pit_escape(delta: float, move_direction: Vector3) -> void:
	if terrain_field == null or is_dashing or move_direction.length() < 0.5 or not is_alive():
		_stuck_seconds = 0.0
		return
	var dir := Vector3(move_direction.x, 0.0, move_direction.z).normalized()
	var ahead := global_position + dir * 0.6
	var steep := terrain_field.grade_between(global_position, ahead) > terrain_field.tuning.max_grade
	var slow := Vector2(velocity.x, velocity.z).length() < 0.6
	# Solo dentro uno scavo (sotto la base del livello): spingere contro un proprio argine
	# non lo deve tagliare.
	steep = steep and terrain_field.delta_at(global_position) < -ESCAPE_MIN_DEPTH
	_stuck_seconds = _stuck_seconds + delta if steep and slow else 0.0
	if _stuck_seconds >= ESCAPE_STUCK_SECONDS:
		_stuck_seconds = 0.0
		carve_escape_ramp(dir)


## Ritaglia una rampa (pendenza ESCAPE_RAMP_GRADE) dal piede del giocatore lungo [param dir].
func carve_escape_ramp(dir: Vector3) -> void:
	var ground := terrain_field.height_at(global_position)
	for k in range(1, ESCAPE_RAMP_STEPS + 1):
		var p := global_position + dir * (k * ESCAPE_RAMP_STEP)
		var target := ground + k * ESCAPE_RAMP_STEP * ESCAPE_RAMP_GRADE
		if terrain_field.height_at(p) > target:
			terrain_field.level(p, ESCAPE_RAMP_RADIUS, target, 1.0)
	escape_ramps += 1
	print("PROTOTYPE01_ESCAPE_RAMP n=%d" % escape_ramps)
	escape_ramp_carved.emit()


## In salita la velocita massima cala con la pendenza davanti (rilievo continuo).
func _update_terrain_speed_modifier() -> void:
	speed_multiplier = speed_bonus
	if terrain_field != null:
		var planar := Vector3(velocity.x, 0.0, velocity.z)
		if not planar.is_zero_approx():
			var g := terrain_field.grade_between(global_position, global_position + planar.normalized() * 0.5)
			if g > 0.0:
				speed_multiplier *= lerpf(1.0, 0.5, clampf(g / terrain_field.tuning.max_grade, 0.0, 1.0))
		return


## Scava -> Alza -> Livella -> Lampione -> Scava (Lampione solo con un LampField, D-058).
func _toggle_terrain_mode() -> void:
	_toggle_field_mode()


## Bersaglio del pennello davanti al giocatore (o sotto il cursore), con l'anello di anteprima.
func _update_terrain_target() -> void:
	if terrain_field != null:
		_update_field_target()


## Materiale della striscia dello zainetto (null senza sacca nel modello).
func pack_gauge_material() -> ShaderMaterial:
	return _pack_gauge_material


## La sacca `PackSack` del modello: la striscia prende lo shader del riempimento.
func _setup_pack_sack() -> void:
	_pack_sack = _model.find_child("PackSack", true, false) as MeshInstance3D
	if _pack_sack == null or _pack_sack.mesh == null:
		return
	_pack_gauge_material = ShaderMaterial.new()
	_pack_gauge_material.shader = PACK_GAUGE_SHADER
	for surface in _pack_sack.mesh.get_surface_count():
		var source := _pack_sack.mesh.surface_get_material(surface)
		if source != null and source.resource_name == "pack_gauge":
			_pack_sack.set_surface_override_material(surface, _pack_gauge_material)
	ActorModel.outline_remaining_surfaces(_pack_sack)


func _on_pack_changed(amount: float, capacity: float) -> void:
	var ratio := amount / capacity if capacity > 0.0 else 0.0
	if _pack_gauge_material != null:
		_pack_gauge_material.set_shader_parameter(&"pack_fill", ratio)
	if _pack_sack != null:
		_pack_sack.scale = Vector3.ONE * (PACK_FULL_SCALE if ratio > 0.9 else 1.0)


func brush_radius() -> float:
	return terrain_field.tuning.brush_radius_m + brush_radius_bonus_m


## DIG -> RAISE -> LEVEL -> (LAMP se il LampField conosce il rilievo) -> DIG.
func _toggle_field_mode() -> void:
	var lamp_ok := lamp_field != null and lamp_field.terrain_field != null
	match terrain_tool_mode:
		TerrainField.ToolMode.DIG:
			terrain_tool_mode = TerrainField.ToolMode.RAISE
		TerrainField.ToolMode.RAISE:
			terrain_tool_mode = TerrainField.ToolMode.LEVEL
		TerrainField.ToolMode.LEVEL:
			terrain_tool_mode = TerrainField.ToolMode.LAMP if lamp_ok else TerrainField.ToolMode.DIG
		_:
			terrain_tool_mode = TerrainField.ToolMode.DIG
	print("PROTOTYPE01_TERRAIN_MODE %s" % TOOL_MODE_NAMES[terrain_tool_mode])
	terrain_mode_changed.emit(terrain_tool_mode)
	_update_terrain_target()


func _update_field_target() -> void:
	var forward := -global_basis.z
	forward.y = 0.0
	if forward.is_zero_approx():
		_preview.hide_ring()
		return
	var reach := terrain_field.tuning.tool_range_m + tool_range_bonus_m
	terrain_target = global_position + forward.normalized() * reach
	terrain_target.y = terrain_field.height_at(terrain_target)
	if aim_device == AimDevice.MOUSE:
		var mouse_point: Variant = _mouse_ground_point()
		if mouse_point != null:
			var point: Vector3 = mouse_point
			var planar := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
			terrain_target = global_position + planar.limit_length(reach * 2.2)
			terrain_target.y = terrain_field.height_at(terrain_target)
	_preview.show_ring(terrain_target + Vector3(0.0, 1.0, 0.0), brush_radius(), _preview_color())


## Punto del cursore sul terreno (null senza camera).
func _mouse_ground_point() -> Variant:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var screen := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(screen)
	var ray := camera.project_ray_normal(screen)
	return ray_ground_point(terrain_field, origin, ray, terrain_field.height_at(global_position))


## Intersezione del raggio con il rilievo: piano alla quota [param start_height], poi tre
## iterazioni a punto fisso sulla quota sotto il punto trovato (audit G-02: col solo piano
## alla quota del giocatore, in una buca da 2,5 m l'anello stava 1,75 m oltre il cursore).
static func ray_ground_point(field: TerrainField, origin: Vector3, ray: Vector3, start_height: float) -> Variant:
	if ray.y > -0.001:
		return null
	var height := start_height
	var point := Vector3.ZERO
	for i in 4:
		var t := (height - origin.y) / ray.y
		if t < 0.0:
			return null
		point = origin + ray * t
		height = field.height_at(point)
	return point


## Una pennellata per passo fisico finche il tasto e premuto (spec sezione 3).
func _apply_brush(delta: float) -> void:
	if _brush_blocked():
		# Un solo rifiuto per ostacolo, non uno a ogni passo fisico.
		if not _brush_was_blocked:
			terrain_tool_rejected.emit()
		_brush_was_blocked = true
		return
	_brush_was_blocked = false
	var radius := brush_radius()
	var rate := terrain_field.tuning.sculpt_rate_m_s * delta
	match terrain_tool_mode:
		TerrainField.ToolMode.DIG:
			var volume := terrain_field.player_sculpt(terrain_target, radius, -rate, terrain_tool_mode)
			pack.give(-volume)
		TerrainField.ToolMode.RAISE:
			# Chiede allo zaino la terra della pennellata intera (pi r^2 / 3 * rate, scalata da
			# Getto rapido); se ne ha meno, alza di meno.
			var wanted := PI * radius * radius / 3.0 * rate * raise_cost_scale
			var got := pack.take(wanted)
			if got > 0.0:
				var placed := terrain_field.player_sculpt(terrain_target, radius, rate * got / wanted, terrain_tool_mode)
				# Aree protette, quota massima e bordo posano meno della pennellata: la terra
				# non posata torna nello zaino (audit G-01: lo zaino scambia terra, non la perde).
				var spent := placed * raise_cost_scale
				if got > spent:
					pack.give(got - spent)
		TerrainField.ToolMode.LEVEL:
			# La terra per alzare i dintorni viene dallo zaino: oltre quella la pennellata si scala.
			var volume := terrain_field.player_level_budget(terrain_target, radius, terrain_field.tuning.level_rate * delta, pack.amount / raise_cost_scale)
			if volume < 0.0:
				pack.give(-volume)
			else:
				pack.take(volume * raise_cost_scale)
		TerrainField.ToolMode.LAMP:
			tool_held = false
			if lamp_field == null or not lamp_field.place_at(terrain_target):
				terrain_tool_rejected.emit()
	# Un affondo per volta (audit G-03): rilanciato a ogni passo restava sui primi fotogrammi.
	if _animator != null and _dig_anim_left <= 0.0:
		_dig_anim_left = CharacterAnimator.DIG_SECONDS
		_animator.play_dig()


func _brush_blocked() -> bool:
	if terrain_field.is_protected(terrain_target):
		return true
	match terrain_tool_mode:
		TerrainField.ToolMode.RAISE:
			return pack.is_empty()
		TerrainField.ToolMode.LAMP:
			return lamp_field == null or not lamp_field.can_place(terrain_target) or not lamp_field.can_afford(terrain_target)
	return false


func _preview_color() -> Color:
	if _brush_blocked():
		return BrushPreview.INVALID_COLOR
	match terrain_tool_mode:
		TerrainField.ToolMode.DIG:
			return BrushPreview.DIG_COLOR
		TerrainField.ToolMode.RAISE:
			return BrushPreview.RAISE_COLOR
		TerrainField.ToolMode.LEVEL:
			return BrushPreview.LEVEL_COLOR
	return BrushPreview.LAMP_COLOR


## Sostituisce il tuning a caldo (preset di feel). Lo stato del dash in corso resta valido.
func apply_tuning(new_tuning: PlayerTuning) -> void:
	tuning = new_tuning
	_movement.configure(tuning)


## Volume collidente in coordinate mondo, come GetActorBounds(true) in Unreal.
## Usato dalla griglia terreno per non rialzare celle sopra il personaggio.
func get_collision_aabb() -> AABB:
	var capsule := _collision.shape as CapsuleShape3D
	var extent := Vector3(capsule.radius, capsule.height * 0.5, capsule.radius)
	return AABB(_collision.global_position - extent, extent * 2.0)


## Legge il movimento e aggiorna l'ultima direzione valida, come HandleMoveTriggered.
func _read_move_direction() -> Vector3:
	# Valore grezzo, senza la dead zone delle azioni: come il trigger Down di
	# IA_Move, sotto la soglia di attuazione non c'e movimento e sopra conta
	# il modulo reale dello stick.
	var move_input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back", 0.0)
	if move_input.length() < tuning.move_actuation_threshold:
		move_input = Vector2.ZERO
	var move_direction := Vector3(move_input.x, 0.0, move_input.y)
	if not move_direction.is_zero_approx():
		_last_valid_move_direction = move_direction.normalized()
	return move_direction


## Stick destro senza dead zone di azione: la dead zone e applicata come in Unreal.
func _raw_aim_input() -> Vector2:
	var aim_input := Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down", 0.0)
	# Autoload cercato a runtime: i test precaricano le scene prima che gli
	# autoload esistano, e il nome globale non compilerebbe.
	var settings := get_node_or_null(^"/root/GameSettings")
	if settings != null:
		if settings.invert_aim_x:
			aim_input.x = -aim_input.x
		if settings.invert_aim_y:
			aim_input.y = -aim_input.y
	return aim_input


func _set_aim_device(device: AimDevice) -> void:
	if aim_device == device:
		return
	aim_device = device
	print("PROTOTYPE01_AIM_DEVICE %s" % ("mouse" if device == AimDevice.MOUSE else "gamepad"))
	aim_device_changed.emit(device)


## Passa da mira automatica a manuale e viceversa (D-089), in qualsiasi momento.
func toggle_aim_mode() -> void:
	set_aim_mode(AimMode.MANUAL if aim_mode == AimMode.AUTO else AimMode.AUTO)


func set_aim_mode(mode: int) -> void:
	aim_mode = mode as AimMode
	aim_mode_changed.emit(aim_mode)


## Direzione planare in cui guarda il personaggio (quella della mira manuale).
func facing_direction() -> Vector3:
	var forward := -global_basis.z
	forward.y = 0.0
	return forward.normalized() if not forward.is_zero_approx() else Vector3.FORWARD


## Carica dell'Ariete (D-092): [param distance] metri in [param seconds] secondi verso
## [param direction], intoccabile. Falso se morto, gia in carica o in scatto.
func start_charge(direction: Vector3, distance: float, seconds: float) -> bool:
	if not is_alive() or is_dashing or _charge_left > 0.0 or seconds <= 0.0:
		return false
	var planar := Vector3(direction.x, 0.0, direction.z)
	planar = planar.normalized() if planar.length_squared() > 1e-6 else facing_direction()
	_charge_velocity = planar * distance / seconds
	_charge_left = seconds
	return true


func is_charging() -> bool:
	return _charge_left > 0.0


## Intoccabile per almeno [param seconds] (bivio Scudo dell'Ariete).
func grant_invulnerability(seconds: float) -> void:
	_invulnerable_left = maxf(_invulnerable_left, seconds)


func _update_charge(delta: float) -> void:
	if _charge_left <= 0.0:
		return
	_charge_left -= delta
	if _charge_left <= 0.0:
		_charge_left = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		charge_finished.emit()


## Punto del terreno sotto il cursore quando si mira col mouse (armi attive, D-092), altrimenti null.
func cursor_ground_point() -> Variant:
	if aim_device != AimDevice.MOUSE or not is_inside_tree():
		return null
	var offset := aim_direction_at_screen(get_viewport().get_mouse_position())
	return global_position + offset if not offset.is_zero_approx() else null


## Un colpo automatico verso [param direction]: il corpo si gira verso il bersaglio, cosi il
## chiodo esce dalla canna e non dalle spalle (playtest O-04).
func face_shot(direction: Vector3) -> void:
	_shot_facing = Vector3(direction.x, 0.0, direction.z).normalized()
	_shot_facing_left = SHOT_FACING_SECONDS


func _apply_facing_rotation(aim_input: Vector2, delta: float) -> void:
	if _shot_facing_left > 0.0 and not _shot_facing.is_zero_approx():
		_shot_facing_left -= delta
		rotation.y = _interp_yaw(rotation.y, atan2(-_shot_facing.x, -_shot_facing.z), delta, SHOT_FACING_SPEED)
		return
	var direction := Vector3.ZERO
	var interp_speed := tuning.gamepad_aim_rotation_interp_speed

	if aim_device == AimDevice.MOUSE:
		direction = _mouse_aim_direction()
		interp_speed = tuning.mouse_aim_rotation_interp_speed
	else:
		var dead_zone := clampf(tuning.aim_stick_dead_zone, 0.0, 0.99)
		var magnitude := aim_input.length()
		if magnitude > dead_zone:
			var normalized := (minf(magnitude, 1.0) - dead_zone) / (1.0 - dead_zone)
			var response := clampf(normalized * maxf(tuning.gamepad_aim_sensitivity, 0.0), 0.0, 1.0)
			if response > 1e-4:
				direction = Vector3(aim_input.x, 0.0, aim_input.y)
				interp_speed = maxf(tuning.gamepad_aim_rotation_interp_speed, 0.0) * response

	if direction.is_zero_approx():
		return
	var target_yaw := atan2(-direction.x, -direction.z)
	rotation.y = _interp_yaw(rotation.y, target_yaw, delta, interp_speed)


## FMath::RInterpTo ridotto allo yaw.
static func _interp_yaw(current: float, target: float, delta: float, speed: float) -> float:
	if speed <= 0.0:
		return target
	var difference := wrapf(target - current, -PI, PI)
	if absf(difference) < 1e-6:
		return target
	return wrapf(current + difference * clampf(delta * speed, 0.0, 1.0), -PI, PI)


func _mouse_aim_direction() -> Vector3:
	return aim_direction_at_screen(get_viewport().get_mouse_position())


## Deproietta un punto dello schermo sul piano orizzontale passante per il
## personaggio e restituisce la direzione planare verso quel punto.
func aim_direction_at_screen(screen_position: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.ZERO
	var origin := camera.project_ray_origin(screen_position)
	var ray := camera.project_ray_normal(screen_position)
	if is_zero_approx(ray.y):
		return Vector3.ZERO
	var t := (global_position.y - origin.y) / ray.y
	if t < 0.0:
		return Vector3.ZERO
	var direction := origin + ray * t - global_position
	direction.y = 0.0
	return direction


func _start_dash() -> void:
	if is_dashing or is_dash_on_cooldown:
		return

	# In Unreal il movimento dello stesso frame e elaborato prima del dash.
	_read_move_direction()
	var forward := -global_basis.z
	forward.y = 0.0
	_dash_direction = _last_valid_move_direction if not _last_valid_move_direction.is_zero_approx() else forward
	_dash_direction.y = 0.0
	_dash_direction = _dash_direction.normalized()
	if _dash_direction.is_zero_approx():
		_dash_direction = forward.normalized()

	is_dashing = true
	_time_since_dash = 0.0
	_effective_dash_duration = maxf(tuning.dash_duration, 0.01)
	_set_state_color(tuning.dash_color_linear)
	_body.scale = _base_body_scale * tuning.dash_scale_multiplier
	if _animator != null:
		_animator.play_dodge()
	print("PROTOTYPE01_DASH_STARTED")
	dash_started.emit()


func _update_dash_timers(delta: float) -> void:
	if not (is_dashing or is_dash_on_cooldown):
		return
	_time_since_dash += delta
	# Tolleranza per l'accumulo di float: 11 * (1/60) deve contare come 0,1833 s.
	if is_dashing and _time_since_dash >= _effective_dash_duration - 1e-6:
		_end_dash()
	if is_dash_on_cooldown and _time_since_dash >= maxf(tuning.dash_cooldown, _effective_dash_duration) - 1e-6:
		_end_dash_cooldown()


func _end_dash() -> void:
	is_dashing = false
	is_dash_on_cooldown = true
	velocity.x = 0.0
	velocity.z = 0.0
	_body.scale = _base_body_scale
	_set_state_color(tuning.dash_cooldown_color_linear)


func _end_dash_cooldown() -> void:
	is_dash_on_cooldown = false
	_set_state_color(body_color_linear)
	print("PROTOTYPE01_DASH_READY")
	dash_ready.emit()


func set_max_health(value: int, heal_full := true) -> void:
	max_health = maxi(value, 1)
	health = max_health if heal_full else mini(health, max_health)
	health_changed.emit(health, max_health)


## Recupera vita fino al massimo; non rianima.
func heal(amount: int) -> void:
	if health <= 0 or amount <= 0:
		return
	health = mini(health + amount, max_health)
	health_changed.emit(health, max_health)


func is_alive() -> bool:
	return max_health <= 0 or health > 0


## Danno con breve invulnerabilita. Restituisce true se il colpo e andato a segno.
func take_damage(amount: int) -> bool:
	# Lo scatto rende intoccabili (playtest O-01): e la mossa per uscire dall'accerchiamento.
	if max_health <= 0 or health <= 0 or _invulnerable_left > 0.0 or is_dashing or _charge_left > 0.0:
		return false
	health = maxi(health - amount, 0)
	_invulnerable_left = invulnerability_seconds
	on_hit()
	print("PROTOTYPE01_PLAYER_DAMAGED health=%d" % health)
	health_changed.emit(health, max_health)
	damaged.emit(amount)
	if health == 0:
		if _animator != null:
			_animator.play_death()
		tool_held = false
		interact_held = false
		died.emit()
	return true


## Colpito dalla sfera (Companion Slice): lampo rosso, nessun danno.
func on_hit() -> void:
	_hit_flash_left = HIT_FLASH_SECONDS
	_body_material.albedo_color = HIT_COLOR_LINEAR.linear_to_srgb()
	_flinch = 1.0
	if _animator != null:
		_animator.play_hit()


func _update_hit_flash(delta: float) -> void:
	if _hit_flash_left <= 0.0:
		return
	_hit_flash_left -= delta
	if _hit_flash_left <= 0.0:
		var color := body_color_linear
		if is_dashing:
			color = tuning.dash_color_linear
		elif is_dash_on_cooldown:
			color = tuning.dash_cooldown_color_linear
		_set_body_color(color)


## Tuta del colore di classe (D-092: segnaposto delle classi senza modello). Diventa il
## colore di riposo; scatto e colpo restano gli stessi.
func set_class_color(linear_color: Color) -> void:
	body_color_linear = linear_color
	if _body_material != null and not is_dashing and not is_dash_on_cooldown:
		_set_state_color(linear_color)


func _set_body_color(linear_color: Color) -> void:
	_body_material.albedo_color = linear_color.linear_to_srgb()


## Colore di stato (dash, cooldown, riposo): il lampo rosso del danno ha la precedenza
## finche dura; alla sua fine `_update_hit_flash` applica il colore giusto (P-07).
func _set_state_color(linear_color: Color) -> void:
	if _hit_flash_left > 0.0:
		return
	_set_body_color(linear_color)


# --- Movimento procedurale ---------------------------------------------------------------

## Rinculo visivo di un colpo. [param world_direction] e la direzione in cui il corpo
## viene spinto (opposta al colpo); se e zero, all'indietro rispetto a dove guarda.
## Non conosce l'arma: lo chiama chi la collega (vedi anche `recoil_source`).
func kick(world_direction := Vector3.ZERO) -> void:
	var local := Vector3(world_direction.x, 0.0, world_direction.z) * global_basis
	_recoil_direction = local.normalized() if local.length_squared() > 1e-6 else Vector3.BACK
	_recoil = 1.0


func _on_recoil_source_fired(_count: int = 1) -> void:
	var shot: Variant = recoil_source.get(&"last_fire_direction")
	kick(-(shot as Vector3) if shot is Vector3 else Vector3.ZERO)


## Inclinazione, impulsi del dash, rinculo e sussulto, sommati in una sola
## trasformazione di `Model` a partire dalla posa di riposo. Legge lo stato di gioco,
## non lo cambia.
func _update_motion(delta: float) -> void:
	var walk_speed := maxf(UnrealSpace.length(tuning.planar_move_speed_cm), 0.01)
	# Velocita nello spazio del personaggio: guarda e si muove in direzioni indipendenti.
	var local_velocity := Vector3(velocity.x, 0.0, velocity.z) * global_basis
	if _animator != null:
		_animator.set_locomotion(local_velocity, walk_speed)
	if not ActorMotion.enabled:
		if not _motion_at_rest:
			_model.transform = _model_rest
			_motion_at_rest = true
		return

	var lean := local_velocity.limit_length(walk_speed * tuning.lean_speed_cap) / walk_speed * tuning.lean_angle
	# Avanti e -Z: beccheggio negativo = busto in avanti; rollio negativo = verso destra.
	_lean_pitch = ActorMotion.smooth(_lean_pitch, lean.z, tuning.lean_rate, delta)
	_lean_roll = ActorMotion.smooth(_lean_roll, -lean.x, tuning.lean_rate, delta)
	var pitch := _lean_pitch
	var roll := _lean_roll
	var slide := Vector3.ZERO

	if is_dashing != _was_dashing:
		_was_dashing = is_dashing
		_dash_pulse = -1.0 if is_dashing else 1.0
	_dash_pulse = move_toward(_dash_pulse, 0.0, delta / tuning.dash_pulse_seconds)
	var pulse := _dash_pulse * _dash_pulse
	var height := 1.0 + (pulse * tuning.dash_stretch if _dash_pulse > 0.0 else -pulse * tuning.dash_squash)

	if _recoil > 0.0:
		_recoil = maxf(_recoil - delta / tuning.recoil_seconds, 0.0)
		var punch := _recoil * _recoil
		slide += _recoil_direction * (tuning.recoil_back * punch)
		pitch += _recoil_direction.z * tuning.recoil_tilt * punch
		roll -= _recoil_direction.x * tuning.recoil_tilt * punch
	if _flinch > 0.0:
		_flinch = maxf(_flinch - delta / tuning.flinch_seconds, 0.0)
		var hurt := _flinch * _flinch
		height *= 1.0 - tuning.flinch_squash * hurt
		slide.z += tuning.flinch_back * hurt
		pitch += tuning.flinch_pitch * hurt

	var width := 1.0 - (height - 1.0) * 0.5
	var pose := Basis.from_euler(Vector3(pitch, 0.0, roll)).scaled_local(Vector3(width, height, width))
	_model.transform = _model_rest * Transform3D(pose, Vector3(slide.x, 0.0, slide.z))
	_motion_at_rest = false
