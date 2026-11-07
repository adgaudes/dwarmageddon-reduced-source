class_name ActorMotion
extends RefCounted
## Movimento procedurale degli attori (D-050: modelli statici, nessun rig): funzioni
## condivise da giocatore, compagno, rottamatori e Demolitore. Agisce **solo sui nodi
## visivi**: corpi fisici, collisioni e valori di gioco non sanno che esiste.
## Ogni attore riscrive la trasformazione del proprio visual a ogni passo fisico a
## partire dalla posa di riposo (niente accumulo, niente deriva): con l'interpolazione
## fisica attiva il motore la interpola come il resto.

## Interruttore globale. Spento, ogni attore riporta i visual alla posa di riposo e
## non li tocca piu: catture e test deterministici. Acceso di default.
static var enabled := true

## Sotto questa distanza dal bersaglio [method smooth] ci arriva di colpo: i visual
## tornano esattamente a riposo invece di avvicinarsi all'infinito.
const SNAP_EPSILON := 0.0005
## Passo massimo d'integrazione della molla: sopra, il passo si divide (stabile anche a 30 Hz).
const SPRING_MAX_STEP := 1.0 / 100.0


## Avvicinamento esponenziale a [param target], indipendente dal passo.
static func smooth(current: float, target: float, rate: float, delta: float) -> float:
	var value := lerpf(current, target, 1.0 - exp(-rate * delta))
	return target if absf(target - value) < SNAP_EPSILON else value


## Molla smorzata verso zero. [param state] e (posizione, velocita); restituisce il
## nuovo stato. Si ferma del tutto quando e quasi a riposo.
static func spring(state: Vector2, stiffness: float, damping: float, delta: float) -> Vector2:
	var steps := maxi(ceili(delta / SPRING_MAX_STEP), 1)
	var step := delta / steps
	for i in steps:
		state.y += (-stiffness * state.x - damping * state.y) * step
		state.x += state.y * step
	if absf(state.x) < SNAP_EPSILON and absf(state.y) < SNAP_EPSILON * 10.0:
		return Vector2.ZERO
	return state


## Trasformazione di un "telaio" inclinato di [param pitch] (positivo = muso in su) e
## [param roll] attorno al punto d'appoggio [param ground], espresso nello spazio del
## genitore. Il telaio si solleva di quanto serve perche il bordo dell'impronta
## ([param half_length] x [param half_width]) non entri nel terreno.
static func tilt_on_ground(ground: Vector3, pitch: float, roll: float, half_length: float, half_width: float) -> Transform3D:
	var tilt := Basis.from_euler(Vector3(pitch, 0.0, roll))
	var lift := absf(pitch) * half_length + absf(roll) * half_width
	return Transform3D(tilt, ground - tilt * ground + Vector3(0.0, lift, 0.0))
