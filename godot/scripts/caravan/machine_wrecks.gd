class_name MachineWrecks
extends BuriedCaches
## Relitti sepolti (spec D-093, Sezione 5): due per livello sotto cumuli e vagoni, come le
## casse ma col luccichio arancione e un telaio arrugginito che spunta dal suolo, sempre a
## vista, e ne segue la quota. Scavando fino alla base il telaio sale e sparisce e arriva
## `cache_opened`; la scelta fra due moduli (o i rottami a carovana piena) la fa ArenaRun.

## Ruggine scura, usata cosi com'e (sRGB); niente rosso, riservato al guasto.
const RUST_COLOR := Color(0.45, 0.22, 0.1)
## Quanto il telaio spunta sopra il suolo (m): il resto sta sotto.
const FRAME_POKE := 0.35
## Travi del telaio (origine al suolo): dimensioni, centro e beccheggio (rad). Due longheroni
## inclinati che escono dal suolo, una traversa sulla loro testa e un montante spezzato.
const BEAMS := [
	[Vector3(0.1, 0.1, 1.2), Vector3(-0.3, 0.0, 0.0), 0.25],
	[Vector3(0.1, 0.1, 1.2), Vector3(0.3, 0.0, 0.0), 0.25],
	[Vector3(0.7, 0.1, 0.1), Vector3(0.0, 0.1, -0.52), 0.0],
	[Vector3(0.1, 0.5, 0.1), Vector3(-0.3, FRAME_POKE - 0.25, -0.5), 0.0],
]

var _beam_mesh := BoxMesh.new()
var _rust_material := StandardMaterial3D.new()


func _init() -> void:
	glint_color = Color(1.0, 0.45, 0.1)
	marker_name = "WRECK"
	_beam_mesh.size = Vector3.ONE
	_rust_material.albedo_color = RUST_COLOR
	_rust_material.roughness = 1.0


func _make_frame(index: int) -> Node3D:
	return _build_frame(index)


func _make_marker(index: int) -> Node3D:
	return _build_frame(index)


## Telaio del relitto [param index]: la sua imbardata viene dal punto (niente estrazioni a
## caso), cosi due relitti non sono girati uguale e lo stesso relitto resta uguale a se stesso.
func _build_frame(index: int) -> Node3D:
	var frame := Node3D.new()
	var p := position_of(index)
	frame.rotation.y = fposmod(p.x * 0.37 + p.z * 0.61, 1.0) * TAU
	for beam: Array in BEAMS:
		var part := MeshInstance3D.new()
		part.mesh = _beam_mesh
		part.material_override = _rust_material
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.layers = Machine.VISUAL_LAYER
		part.position = beam[1]
		part.rotation.x = beam[2]
		part.scale = beam[0]
		frame.add_child(part)
	return frame
