class_name FillLight
extends DirectionalLight3D
## Luce di riempimento (D-094): con il sole in controluce le facce rivolte alla camera
## (pareti delle rovine, fronti dei prop) restavano quasi nere. Questa luce fredda, senza
## ombre e senza riflessi, arriva quasi orizzontale da dietro la camera: schiarisce le
## pareti verticali e tocca poco il suolo, quindi il contrasto del sole resta. Segue il
## sole: la sua energia scala con quella del sole rispetto al giorno (notte = quasi spenta).

const ENERGY := 0.6
const COLOR := Color(0.55, 0.65, 1.0)
## Da sud, leggermente da ovest, circa 15 gradi sull'orizzonte (la camera guarda verso -Z).
const DIRECTION := Vector3(-0.3, -0.27, -1.0)

var sun: DirectionalLight3D
var _day_energy := 1.0


func _init() -> void:
	name = "FillLight"
	light_color = COLOR
	light_energy = ENERGY
	light_specular = 0.0
	shadow_enabled = false
	basis = Basis.looking_at(DIRECTION.normalized(), Vector3.UP)


func _ready() -> void:
	if sun != null:
		_day_energy = maxf(sun.light_energy, 0.001)


func _process(_delta: float) -> void:
	if sun != null:
		light_energy = ENERGY * clampf(sun.light_energy / _day_energy, 0.0, 1.0)
