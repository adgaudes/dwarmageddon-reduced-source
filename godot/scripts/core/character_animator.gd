class_name CharacterAnimator
extends Node
## Animazioni con scheletro di un personaggio (D-060, tools/blender/build_character_assets.py):
## fermo/corsa miscelati sulla velocita; la corsa sceglie fra avanti, sinistra, destra e
## indietro secondo l'angolo fra mira e marcia, e le gambe si girano (HipTwistModifier)
## dello scarto che resta; braccia e testa stanno nella posa di mira. Scavo, schivata,
## colpo e morte a comando. Legge solo cio che gli passa il proprietario e muove solo le
## ossa: corpo fisico e valori di gioco non sanno che esiste.
## Con ActorMotion.enabled spento resta fermo nell'ultima posa.

const IDLE := &"Idle"
const AIM := &"Pistol_Aim_Neutral"
const HIT := &"Hit_Chest"
const DEATH := &"Death01"
const DIG := &"Dig"
const DODGE := &"Dodge"
const GAIT_FORWARD := &"forward"
const GAIT_LEFT := &"left"
const GAIT_RIGHT := &"right"
const GAIT_BACK := &"back"
## Per andatura: animazione, angolo (rad) fra mira e marcia a cui e esatta (rotazione
## attorno a +Y: positivo = verso sinistra), velocita (m/s) a cui e a passo naturale.
const GAITS: Dictionary[StringName, Array] = {
	GAIT_FORWARD: [&"Jog_Fwd", 0.0, 3.2],
	GAIT_LEFT: [&"Strafe_Left", PI * 0.5, 2.6],
	GAIT_RIGHT: [&"Strafe_Right", -PI * 0.5, 2.6],
	GAIT_BACK: [&"Run_Bwd", PI, 2.2],
}
const HIPS_BONE := &"DEF-hips"
const SPINE_BONE := &"DEF-spine.001"
## Petto: HipTwistModifier lo tiene rivolto dove si mira.
const CHEST_BONE := &"DEF-spine.003"
## Ossa che seguono la posa di mira invece della corsa.
const AIM_BONES: Array[String] = [
	"DEF-spine.003", "DEF-neck", "DEF-head",
	"DEF-shoulder.L", "DEF-upper_arm.L", "DEF-forearm.L", "DEF-hand.L",
	"DEF-shoulder.R", "DEF-upper_arm.R", "DEF-forearm.R", "DEF-hand.R",
]
## Ossa prese dallo scavo: tutto il busto, le gambe continuano a correre.
const DIG_BONES: Array[String] = [
	"DEF-spine.001", "DEF-spine.002", "DEF-spine.003", "DEF-neck", "DEF-head",
	"DEF-shoulder.L", "DEF-upper_arm.L", "DEF-forearm.L", "DEF-hand.L",
	"DEF-shoulder.R", "DEF-upper_arm.R", "DEF-forearm.R", "DEF-hand.R",
]
## Limiti del ritmo della corsa rispetto al passo naturale.
const GAIT_RATE_MIN := 0.7
const GAIT_RATE_MAX := 2.2
## Frazione della velocita di riferimento a cui la corsa ha sostituito del tutto il fermo.
const GAIT_FULL_BLEND := 0.5
## Secondi di dissolvenza fra un'andatura e l'altra.
const GAIT_CROSSFADE := 0.15
## Un'andatura resta finche la marcia non esce dal suo quarto piu questa isteresi (rad):
## evita lo sfarfallio in diagonale.
const GAIT_HYSTERESIS := deg_to_rad(12.0)
## Velocita (1/s) con cui miscela e torsione inseguono il movimento.
const BLEND_RATE := 12.0
const TWIST_RATE := 14.0
## Durata (s) dell'affondo di scavo e della capriola, qualunque sia la lunghezza dell'animazione.
const DIG_SECONDS := 0.45
const DODGE_SECONDS := 0.4
## Il colpo subito prende solo il busto (DIG_BONES) e dura al massimo questo: in mezzo
## all'orda le gambe continuano a correre (R-39).
const HIT_SECONDS := 0.35

var _tree: AnimationTree
var _player: AnimationPlayer
var _twist: HipTwistModifier
var _move_target := 0.0
var _move := 0.0
var _rate := 1.0
var _twist_target := 0.0
var _gait := GAIT_FORWARD
var _applied_gait := GAIT_FORWARD
var _dead := false
var _frozen := false
var _aim_filter_size := 0
var _fired: Dictionary[StringName, int] = {}


## Crea l'animatore per [param model] e lo aggiunge come suo figlio; null se il modello
## non ha scheletro e animazioni, o se manca un clip richiesto (avviso con l'elenco).
## Un secondo `attach` sullo stesso modello restituisce l'animatore esistente (R-37).
static func attach(model: Node) -> CharacterAnimator:
	for child in model.get_children():
		if child is CharacterAnimator:
			return child
	var players := model.find_children("*", "AnimationPlayer", true, false)
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if players.is_empty() or skeletons.is_empty():
		return null
	var player := players[0] as AnimationPlayer
	var missing := PackedStringArray()
	for animation in required_clips():
		if not player.has_animation(animation):
			missing.append(animation)
	if not missing.is_empty():
		push_warning("CharacterAnimator: %s senza i clip %s, nessuna animazione" % [model.name, ", ".join(missing)])
		return null
	var animator := CharacterAnimator.new()
	animator.name = "CharacterAnimator"
	model.add_child(animator)
	animator._build(player, skeletons[0])
	return animator


## Clip che il modello deve avere perche l'animatore funzioni.
static func required_clips() -> Array[StringName]:
	var clips: Array[StringName] = [IDLE, AIM, HIT, DEATH, DIG, DODGE]
	for gait: StringName in GAITS:
		clips.append(GAITS[gait][0])
	return clips


## Miscela corrente fermo (0) / corsa (1).
func move_blend() -> float:
	return _move


## Torsione corrente delle gambe (rad).
func twist() -> float:
	return _twist.angle


## Andatura scelta: una delle chiavi di [constant GAITS].
func gait() -> StringName:
	return _gait


func aim_filter_size() -> int:
	return _aim_filter_size


## Quante volte e stata chiesta un'azione a comando (`dig`, `dodge`, `hit`).
func fired_count(action: StringName) -> int:
	return _fired.get(action, 0)


## [param local_velocity] nello spazio del personaggio (avanti = -Z);
## [param reference_speed] e la sua velocita normale di marcia.
func set_locomotion(local_velocity: Vector3, reference_speed: float) -> void:
	var planar := Vector2(local_velocity.x, local_velocity.z)
	var speed := planar.length()
	_move_target = clampf(speed / maxf(reference_speed * GAIT_FULL_BLEND, 0.01), 0.0, 1.0)
	if speed < 0.05:
		_twist_target = 0.0
		_rate = 1.0
		return
	# Rotazione attorno a +Y che porta "avanti" (-Z) sulla direzione di marcia.
	var heading := atan2(-planar.x, -planar.y)
	if absf(angle_difference(GAITS[_gait][1], heading)) > PI * 0.25 + GAIT_HYSTERESIS:
		for candidate: StringName in GAITS:
			if absf(angle_difference(GAITS[candidate][1], heading)) <= PI * 0.25:
				_gait = candidate
				break
	_twist_target = angle_difference(GAITS[_gait][1], heading)
	_rate = clampf(speed / GAITS[_gait][2], GAIT_RATE_MIN, GAIT_RATE_MAX)


## Un affondo dell'attrezzo col busto; le gambe continuano quello che stavano facendo.
func play_dig() -> void:
	_fire(&"dig")


## Capriola a corpo intero (lo scatto).
func play_dodge() -> void:
	_fire(&"dodge")


func play_hit() -> void:
	_fire(&"hit")


## Ferma la miscela e fa cadere il personaggio; [method revive] lo rimette in piedi.
func play_death() -> void:
	if _dead:
		return
	_dead = true
	_tree.active = false
	_twist.angle = 0.0
	# La fine della run mette in pausa l'albero: la caduta deve vedersi lo stesso.
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.play(DEATH)


func revive() -> void:
	if not _dead:
		return
	_dead = false
	_player.stop()
	_player.process_mode = Node.PROCESS_MODE_INHERIT
	_tree.active = true


func _fire(action: StringName) -> void:
	# A movimento spento la richiesta non si accoda: partirebbe alla riaccensione (P-10).
	if _dead or _frozen or not ActorMotion.enabled:
		return
	_fired[action] = fired_count(action) + 1
	_tree.set("parameters/%s_shot/request" % action, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _build(player: AnimationPlayer, skeleton: Skeleton3D) -> void:
	_player = player
	player.get_animation(IDLE).loop_mode = Animation.LOOP_LINEAR

	var blend := AnimationNodeBlendTree.new()
	# Andature: una transizione con dissolvenza, poi il ritmo, poi la miscela col fermo.
	var gaits := AnimationNodeTransition.new()
	gaits.xfade_time = GAIT_CROSSFADE
	gaits.input_count = GAITS.size()
	blend.add_node(&"gait", gaits)
	var index := 0
	for gait_name: StringName in GAITS:
		var animation: StringName = GAITS[gait_name][0]
		player.get_animation(animation).loop_mode = Animation.LOOP_LINEAR
		gaits.set_input_name(index, gait_name)
		blend.add_node(gait_name, _clip(animation))
		blend.connect_node(&"gait", index, gait_name)
		index += 1
	blend.add_node(&"gait_rate", AnimationNodeTimeScale.new())
	blend.connect_node(&"gait_rate", 0, &"gait")
	blend.add_node(&"idle", _clip(IDLE))
	blend.add_node(&"move", AnimationNodeBlend2.new())
	blend.connect_node(&"move", 0, &"idle")
	blend.connect_node(&"move", 1, &"gait_rate")

	# Posa di mira su braccia e testa.
	blend.add_node(&"aim", _clip(AIM))
	var upper := AnimationNodeBlend2.new()
	_aim_filter_size = _filter(upper, player.get_animation(AIM), AIM_BONES)
	blend.add_node(&"upper", upper)
	blend.connect_node(&"upper", 0, &"move")
	blend.connect_node(&"upper", 1, &"aim")

	# Azioni a comando, una sopra l'altra: scavo (solo busto), capriola, colpo (solo busto).
	var rates: Dictionary[String, float] = {}
	var dig_shot := _one_shot(blend, "dig", DIG, DIG_SECONDS, &"upper", rates)
	_filter(dig_shot, player.get_animation(DIG), DIG_BONES)
	_one_shot(blend, "dodge", DODGE, DODGE_SECONDS, &"dig_shot", rates)
	var hit_seconds := minf(HIT_SECONDS, player.get_animation(HIT).length)
	var hit_shot := _one_shot(blend, "hit", HIT, hit_seconds, &"dodge_shot", rates)
	_filter(hit_shot, player.get_animation(HIT), DIG_BONES)
	blend.connect_node(&"output", 0, &"hit_shot")

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_tree.tree_root = blend
	player.get_parent().add_child(_tree)
	_tree.anim_player = _tree.get_path_to(player)
	_tree.set(&"parameters/upper/blend_amount", 1.0)
	_tree.set(&"parameters/move/blend_amount", 0.0)
	_tree.set(&"parameters/gait_rate/scale", 1.0)
	for rate_name in rates:
		_tree.set("parameters/%s/scale" % rate_name, rates[rate_name])
	_tree.active = true

	_twist = HipTwistModifier.new()
	_twist.name = "HipTwist"
	skeleton.add_child(_twist)
	_twist.setup(skeleton, HIPS_BONE, SPINE_BONE, CHEST_BONE)
	# La posa iniziale c'e subito, anche se ActorMotion e spento dal primo frame.
	_tree.advance(0.0)


func _clip(animation: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = animation
	return node


## Accende su [param node] il filtro delle tracce di [param animation] che muovono
## [param bones]; restituisce quante ne ha trovate.
func _filter(node: AnimationNode, animation: Animation, bones: Array[String]) -> int:
	node.filter_enabled = true
	var count := 0
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		if path.get_subname_count() > 0 and bones.has(String(path.get_subname(0))):
			node.set_filter_path(path, true)
			count += 1
	return count


## Aggiunge `<action>` (animazione), `<action>_rate` e `<action>_shot` sopra [param below].
## Con [param seconds] > 0 l'animazione viene compressa o allungata a quella durata: il
## ritmo che serve finisce in [param rates], da applicare quando l'albero esiste.
func _one_shot(blend: AnimationNodeBlendTree, action: String, animation: StringName, seconds: float,
		below: StringName, rates: Dictionary[String, float]) -> AnimationNodeOneShot:
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.04
	shot.fadeout_time = 0.12
	blend.add_node(action, _clip(animation))
	blend.add_node(action + "_rate", AnimationNodeTimeScale.new())
	blend.add_node(action + "_shot", shot)
	blend.connect_node(action + "_rate", 0, action)
	blend.connect_node(action + "_shot", 0, below)
	blend.connect_node(action + "_shot", 1, action + "_rate")
	rates[action + "_rate"] = _player.get_animation(animation).length / seconds if seconds > 0.0 else 1.0
	return shot


func _process(delta: float) -> void:
	var frozen := not ActorMotion.enabled
	if frozen != _frozen:
		_frozen = frozen
		_tree.callback_mode_process = (AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if frozen
			else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE)
	if frozen or _dead:
		return
	if _gait != _applied_gait:
		_applied_gait = _gait
		_tree.set(&"parameters/gait/transition_request", String(_gait))
	_move = ActorMotion.smooth(_move, _move_target, BLEND_RATE, delta)
	_twist.angle = ActorMotion.smooth(_twist.angle, _twist_target, TWIST_RATE, delta)
	_tree.set(&"parameters/move/blend_amount", _move)
	_tree.set(&"parameters/gait_rate/scale", _rate)
