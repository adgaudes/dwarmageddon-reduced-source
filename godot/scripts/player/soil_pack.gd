class_name SoilPack
extends RefCounted
## Zainetto di terra dell'ingegnere (spec sezione 3): scavare lo riempie, alzare lo
## svuota; a zaino vuoto non si alza, a zaino pieno la terra in eccesso si perde.

signal changed(amount: float, capacity: float)

var capacity: float
var amount: float


func _init(capacity_m3 := 60.0, start_m3 := 20.0) -> void:
	capacity = capacity_m3
	amount = clampf(start_m3, 0.0, capacity_m3)


func take(m3: float) -> float:
	var given := clampf(m3, 0.0, amount)
	if given > 0.0:
		amount -= given
		changed.emit(amount, capacity)
	return given


func give(m3: float) -> float:
	var room := capacity - amount
	var accepted := clampf(m3, 0.0, room)
	amount += accepted
	changed.emit(amount, capacity)
	return accepted


func is_empty() -> bool:
	return amount <= 0.001


func fill_ratio() -> float:
	return amount / maxf(capacity, 0.001)


func add_capacity(m3: float) -> void:
	capacity += m3
	changed.emit(amount, capacity)
