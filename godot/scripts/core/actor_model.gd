class_name ActorModel
extends RefCounted
## Modelli statici degli attori (D-037, tools/blender/build_actor_assets.py): un solo
## oggetto per .glb, colore nei vertici, materiali con nomi semantici (`detail`,
## `suit`, `stripe`) che qui si rimappano sui materiali del gioco.

const PAINT_SHADER := preload("res://resources/materials/actor_paint.gdshader")
const OUTLINE_SHADER := preload("res://resources/materials/actor_outline.gdshader")

static var _outline_material: ShaderMaterial


## La mesh dell'unico oggetto di un modello importato.
static func mesh_of(scene: PackedScene) -> Mesh:
	var model := scene.instantiate()
	var instance := mesh_instance_of(model)
	var mesh := instance.mesh if instance != null else null
	model.free()
	return mesh


## Il corpo del modello: fra i MeshInstance3D quello con piu superfici (gli accessori
## come lo zainetto di terra ne hanno meno), a parita il primo.
static func mesh_instance_of(model: Node) -> MeshInstance3D:
	if model is MeshInstance3D:
		return model
	var best: MeshInstance3D = null
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var surfaces := instance.mesh.get_surface_count() if instance.mesh != null else 0
		if best == null or surfaces > (best.mesh.get_surface_count() if best.mesh != null else 0):
			best = instance
	return best


## Materiale a colori di vertice. [param tint_linear] colora le facce "vernice".
static func paint_material(tint_linear := Color.WHITE, emission_energy := 2.0, roughness := 0.8) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PAINT_SHADER
	material.set_shader_parameter(&"tint", tint_linear.linear_to_srgb())
	material.set_shader_parameter(&"emission_energy", emission_energy)
	material.set_shader_parameter(&"roughness", roughness)
	material.next_pass = outline_material()
	return material


## Contorno scuro condiviso (D-070): seconda passata a facce interne, spinte lungo la
## normale; stacca gli attori dal suolo nella camera di gioco.
static func outline_material() -> ShaderMaterial:
	if _outline_material == null:
		_outline_material = ShaderMaterial.new()
		_outline_material.shader = OUTLINE_SHADER
	return _outline_material


## Assegna a ogni superficie il materiale col suo nome semantico; le altre restano come sono.
static func apply_materials(instance: MeshInstance3D, materials: Dictionary[String, Material]) -> void:
	for surface in instance.mesh.get_surface_count():
		var source := instance.mesh.surface_get_material(surface)
		var semantic := source.resource_name if source != null else ""
		if materials.has(semantic):
			instance.set_surface_override_material(surface, materials[semantic])


## Materiale "vernice" per un modello: con la texture cotta (D-071, D-072: superficie
## `paint` o `suit` con `albedo_texture`) e uno StandardMaterial3D con la texture e la
## tinta in `albedo_color`; con un modello a blocchi lo shader a colori di vertice.
static func textured_paint(mesh: Mesh, tint_linear := Color.WHITE, emission_energy := 2.0, roughness := 0.8) -> Material:
	# Un modello rifinito ha la texture su tutte le superfici; la "vernice" puo mancare
	# (la lama del Demolitore): allora il materiale serve solo a vestire il resto.
	var standard: StandardMaterial3D = null
	for semantic in ["paint", "suit"]:
		standard = _surface_material_of(mesh, semantic) as StandardMaterial3D
		if standard != null and standard.albedo_texture != null:
			break
		standard = null
	if standard == null:
		for surface in mesh.get_surface_count():
			var any := mesh.surface_get_material(surface) as StandardMaterial3D
			if any != null and any.albedo_texture != null:
				standard = any
				break
	if standard == null:
		return paint_material(tint_linear, emission_energy, roughness)
	var material := StandardMaterial3D.new()
	material.albedo_texture = standard.albedo_texture
	material.albedo_color = tint_linear.linear_to_srgb()
	material.roughness = standard.roughness
	copy_normal_map(standard, material)
	enable_rim(material)
	material.next_pass = outline_material()
	return material


## Rim light leggera (restyling 2026-10-11): stacca gli attori dal suolo come in Hades II.
static func enable_rim(material: BaseMaterial3D) -> void:
	material.rim_enabled = true
	material.rim = 0.35
	material.rim_tint = 0.5


## Porta la normal map cotta (D-074) da un materiale importato a uno costruito dal codice.
static func copy_normal_map(source: BaseMaterial3D, target: BaseMaterial3D) -> void:
	if source.normal_enabled and source.normal_texture != null:
		target.normal_enabled = true
		target.normal_texture = source.normal_texture
		target.normal_scale = source.normal_scale


## Veste una mesh con il materiale "vernice": sulla superficie `paint`/`suit` se il
## modello ha la texture cotta (le altre superfici tengono il materiale importato, con
## il contorno), altrimenti come `material_override` dell'intero modello a blocchi.
static func dress(instance: MeshInstance3D, paint: Material) -> void:
	if paint is ShaderMaterial:
		instance.material_override = paint
		return
	instance.material_override = null
	for surface in instance.mesh.get_surface_count():
		var source := instance.mesh.surface_get_material(surface)
		var semantic := source.resource_name if source != null else ""
		if semantic == "paint" or semantic == "suit":
			instance.set_surface_override_material(surface, paint)
		elif source != null:
			instance.set_surface_override_material(surface, _outlined_copy(source))


const OUTLINED_COPY_META := &"outlined_copy"


## Copia con contorno di un materiale importato, una per materiale: la condividono
## tutte le istanze (i rottamatori restano una draw call per superficie). La copia
## vive come metadato del materiale importato, cosi muore con lui (niente RID persi
## all'uscita, che il gate conta come errori).
static func _outlined_copy(source: Material) -> Material:
	if not source.has_meta(OUTLINED_COPY_META):
		var copy := source.duplicate() as Material
		copy.next_pass = outline_material()
		source.set_meta(OUTLINED_COPY_META, copy)
	return source.get_meta(OUTLINED_COPY_META) as Material


## Energia della luce della superficie `lamp` di un modello rifinito (occhi, fari):
## agisce sulla copia condivisa con il contorno, quindi su tutte le istanze.
static func set_lamp_energy(mesh: Mesh, energy: float) -> void:
	var source := _surface_material_of(mesh, "lamp")
	if source == null:
		return
	var lamp := _outlined_copy(source) as StandardMaterial3D
	if lamp != null:
		lamp.emission_energy_multiplier = energy


static func _surface_material_of(mesh: Mesh, semantic: String) -> Material:
	for surface in mesh.get_surface_count():
		var source := mesh.surface_get_material(surface)
		if source != null and source.resource_name == semantic:
			return source
	return null


## Il materiale importato della superficie con quel nome semantico, o null.
static func surface_material(instance: MeshInstance3D, semantic: String) -> Material:
	for surface in instance.mesh.get_surface_count():
		var source := instance.mesh.surface_get_material(surface)
		if source != null and source.resource_name == semantic:
			return source
	return null


## Alle superfici importate non ancora sovrascritte (texture cotte, D-071) aggiunge il
## contorno: una copia del materiale con `next_pass`, cosi la risorsa importata resta intatta.
static func outline_remaining_surfaces(instance: MeshInstance3D) -> void:
	for surface in instance.mesh.get_surface_count():
		if instance.get_surface_override_material(surface) != null:
			continue
		var source := instance.mesh.surface_get_material(surface)
		if source == null:
			continue
		var copy := source.duplicate() as Material
		copy.next_pass = outline_material()
		instance.set_surface_override_material(surface, copy)
