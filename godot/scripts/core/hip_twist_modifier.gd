class_name HipTwistModifier
extends SkeletonModifier3D
## Tiene il busto sulla mira mentre le gambe vanno dove serve. Due correzioni, applicate
## dopo le animazioni come ogni SkeletonModifier3D:
## - gira il bacino (e con lui le gambe) di [member angle] attorno alla verticale e
##   contro-ruota la colonna;
## - toglie al petto la rotazione attorno alla verticale che gli arriva da bacino e
##   colonna (le corse laterali girano i fianchi): chi mira guarda sempre avanti. La
##   correzione sfuma quando il petto non e piu dritto (capriola, caduta).

## Radianti attorno a +Y nello spazio dello scheletro; 0 = nessuna torsione.
var angle := 0.0

## Componente verticale dell'asse "su" del petto sotto cui la correzione e nulla, e
## ampiezza della fascia in cui cresce fino a piena.
const UPRIGHT_MIN := 0.5
const UPRIGHT_FADE := 0.3

var _hips := -1
var _spine := -1
var _chest := -1


## [param hips_bone] e l'osso che porta le gambe, [param spine_bone] il primo sopra,
## [param chest_bone] quello da tenere sulla mira (vuoto = nessuna correzione).
## Lo scheletro si passa esplicito: appena aggiunto, get_skeleton() e ancora nullo.
func setup(skeleton: Skeleton3D, hips_bone: StringName, spine_bone: StringName, chest_bone: StringName = &"") -> void:
	_hips = skeleton.find_bone(hips_bone)
	_spine = skeleton.find_bone(spine_bone)
	_chest = skeleton.find_bone(chest_bone) if chest_bone != &"" else -1


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if _hips >= 0 and _spine >= 0 and not is_zero_approx(angle):
		var hips := skeleton.get_bone_global_pose(_hips)
		hips.basis = Basis(Vector3.UP, angle) * hips.basis
		skeleton.set_bone_global_pose(_hips, hips)
		# Letta dopo: contiene gia la torsione del bacino, che qui si toglie.
		var spine := skeleton.get_bone_global_pose(_spine)
		spine.basis = Basis(Vector3.UP, -angle) * spine.basis
		skeleton.set_bone_global_pose(_spine, spine)
	if _chest < 0:
		return
	var chest := skeleton.get_bone_global_pose(_chest)
	var turned := chest.basis.orthonormalized() * skeleton.get_bone_global_rest(_chest).basis.orthonormalized().inverse()
	var upright := clampf(((turned * Vector3.UP).y - UPRIGHT_MIN) / UPRIGHT_FADE, 0.0, 1.0)
	var heading := turned * Vector3.BACK
	var yaw := atan2(heading.x, heading.z) * upright
	if is_zero_approx(yaw):
		return
	chest.basis = Basis(Vector3.UP, -yaw) * chest.basis
	skeleton.set_bone_global_pose(_chest, chest)
