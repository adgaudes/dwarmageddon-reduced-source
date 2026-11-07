// Vento condiviso della vegetazione (D-083, 12 ottobre 2026): un campo coerente, non
// un'oscillazione per istanza. Una raffica viaggia lungo `wind_dir` (onda lunga piu
// rumore lento), ogni pianta la legge nel punto della propria origine e si piega in
// quella direzione; un fremito laterale piu rapido, sfasato per pianta, rompe la
// sincronia. Lo spostamento cresce col quadrato dell'altezza normalizzata, cosi il
// piede resta piantato e la punta ondeggia.

#include "res://resources/materials/noise.gdshaderinc"

// Direzione del vento sul piano xz (normalizzata qui, non dai parametri).
const vec2 WIND_DIR = normalize(vec2(1.0, 0.42));

// Forza della raffica in `origin` (0 = calma, 1 = raffica piena).
float wind_gust(vec2 origin, float time) {
	float along = dot(origin, WIND_DIR);
	float wave = sin(along * 0.22 - time * 1.35) * 0.5 + 0.5;
	float drift = value_noise(origin * 0.07 - WIND_DIR * time * 0.45);
	return clamp(wave * 0.55 + drift * 0.75, 0.0, 1.0);
}

// Spostamento del vertice: `height` e l'altezza normalizzata 0..1 del vertice nella
// pianta, `strength` l'ampiezza massima in unita locali, `seed` sfasa il fremito.
vec3 wind_offset(vec2 origin, float height, float strength, float seed, float time) {
	float h = clamp(height, 0.0, 1.0);
	float bend = h * h * strength;
	float gust = wind_gust(origin, time);
	float lean = (0.25 + 0.75 * gust) * bend;
	float flutter = sin(time * 3.1 + seed * 6.2831) * 0.22 * bend * (0.4 + 0.6 * gust);
	vec2 side = vec2(-WIND_DIR.y, WIND_DIR.x);
	vec2 xz = WIND_DIR * lean + side * flutter;
	// La punta che si piega si abbassa un poco: evita che la pianta "si allunghi".
	return vec3(xz.x, -0.25 * lean * h, xz.y);
}
