# Notes on this copy

What differs from the full project, and what was measured on this copy on 7 November 2026.

## Baseline

Measured on a clean tree, Linux x86_64 (WSL2 Ubuntu), Godot 4.7.2 stable, seed 20261014, `tools/godot/run_checks.sh --jobs 5`, about 2 minutes:

| Step | Result |
|---|---|
| First import | exit 0, about 4 s, 40 `ERROR:` lines (see below) |
| Second import | exit 0, 0 error lines, no file changed |
| `--check-only`, 219 project scripts | 0 failed (addons not checked, as in the original gate) |
| 60 suites | 59 OK, 1 FAIL: `audio_tests` |
| Headless smoke test | exit 0, all 12 markers, 0 runtime errors |
| `run_checks.sh` exit code | 1, because of `audio_tests` |

The same gate on the full project before reduction: 49 suites OK, 11 stuck at exit (see "Exit hang"), 0 failed.

On Windows 11 with an RTX 4050, the project's own `Invoke-GodotChecks.ps1` gave the same result on this copy: 219 scripts OK, 59 suites OK, `audio_tests` FAIL with 47 failures. Its windowed step also passed (`restyle_tests` with real Terrain3D and shaders, a 320x200 start with all markers and no errors), as did the headless smoke test.

## Known failure: `audio_tests`

47 checks fail, one per missing sound file. They assert that each id has an OGG sample. Nothing else in the suite fails.

- 28 ids (`SfxLibrary._synthesize`) fall back to code synthesis. The suite verifies format, length, peak and tail of that synthesis, and those checks pass.
- 19 ids (`w_*`) have no synthesis, so weapons are silent. The source comment says so: "campioni Sonniss, nessuna sintesi di riserva". What they hold depends on the route, measured with a probe script:

| Route | `w_ram_fire` holds | `RunAudio.play` | `play_count` |
|---|---|---|---|
| `SfxLibrary.build_all` alone | null | false | 0 |
| After `precache_async` (the menu and the intro call it) | `AudioStreamWAV` of 0 bytes, 0 s | true | 1 |

On both routes the key exists, so `RunAudio.weapon_sound_id` returns `w_*` and `WEAPON_FALLBACK` (`nail_shot`, `terrain_raise`) is never used. `audio_tests` runs the precache first, so "ogni arma suona" counts plays of empty streams and passes although nothing can be heard.

Nobody has listened to the fallback. Headless audio uses a dummy driver.

## First import errors

All 40 lines report missing `res://.godot/imported/...` files, `theme.tres` and the fonts and UI textures it references. `project.godot` sets a custom theme, and the engine loads it before the import cache exists. The second import prints none. The full project prints the same 40.

One first import of the full project ended with exit 134 (abort, core dump) after finishing the reimport, while loading the editor layout. It did not come back in 6 further imports of the full project or about 15 of this copy. Cause unknown.

## Exit hang

**Symptom.** A suite prints `PROTOTYPE01_TESTS PASS` and the process never ends. On Linux this was close to deterministic per suite: 11 or 12 of 60, nearly the same ones per run.

**What was measured** (runs of a script that prints PASS and calls `quit()`):

| Variant | Hangs |
|---|---|
| Project as it was | 60 of 60 |
| Quitting after 30 or 300 frames, or a 1 s or 3 s timer | 24 of 24 each |
| Without the `DebugMenu` autoload | 0 of 24 |
| Without any other single autoload | 24 of 24 each |
| Empty project | 0 of 60 |
| `DebugMenu` startup thread skipped under headless | 0 of 12, and 0 of 12 on each of the 12 stuck suites |

`debug_menu.gd` starts a `Thread` in `_ready` and joins it in `_exit_tree`. The most likely reading is that the thread waits for something the main thread never provides under headless, while the main thread waits in the join. This was not confirmed with a stack trace: no debugger was available. Why 48 of the suites do not hang was not established.

**In this copy** `godot/addons/debug_menu/debug_menu.gd` returns before starting the thread when `DisplayServer.get_name() == "headless"`. The windowed behaviour is unchanged. No test was changed for this.

`run_checks.sh` still detects the condition: after PASS or FAIL a process gets `--exit-grace` seconds (default 20), then it is killed and reported as an exit hang. When running a suite by hand, use `timeout`.

## Parallel runs

`run_checks.sh` gives each process its own `user://` through `XDG_*` variables. Without that, `profile_v2_tests` and `settings_tests` showed failures in parallel (6 of 24 runs) and passed 8 of 8 alone with the isolation. The shared files are the probable cause; it was not investigated further.

## Changes to files

| File | Change | Why |
|---|---|---|
| `godot/assets/models/*.glb` | Embedded images at 1/4 | Size |
| `godot/assets/models/player_engineer.glb` | Five clips replaced, see below | Licence of the originals |
| `godot/assets/models/*.png`, `godot/assets/textures/{surfaces,terrain}/*.png` | 1/4 resolution, metadata dropped | Size |
| `godot/assets/models/*.import`, `project.godot` | Rewritten by a Godot import | Avoids a diff at the first import |
| `godot/tests/restyle_tests.gd` | Expected sizes: ground 512, walls and plants 256, terrain 256 | Follows the resized assets. The windowed checks ran only on Windows |
| `godot/addons/debug_menu/debug_menu.gd` | Thread skipped under headless | See "Exit hang" |

Removed: `godot/assets/audio/sfx/` (94 files with their `.import`), `godot/addons/terrain_3d/brushes/` (36), native libraries for other platforms (16).

### Placeholder clips in `player_engineer.glb`

| Clip | Made from | Duration |
|---|---|---|
| `Strafe_Left_Loop`, `Strafe_Right_Loop` | `Walk_Loop`, retimed | 0.667 s |
| `Run_Bwd_Loop` | `Jog_Fwd_Loop`, reversed and retimed | 0.625 s |
| `Dig` | `Interact`, retimed | 1.167 s |
| `Dodge` | `Roll` from the Quaternius library: bone rotations and vertical hips motion | 1.5 s |

All sources are CC0 (`docs/licenses/Quaternius-UAL-CC0.txt`). They satisfy the animator's contract and tests. `Strafe_*` are forward walks, so the lateral gaits are wrong in play.

Looked at once, in still captures from a window on Windows (`capture_character.gd`, `capture_run.gd`): the model is intact and the `Dodge` pose reads as a roll. The level, the HUD and the enemies render with the reduced textures. The clips have not been judged in motion.

## Not verified here

- Motion of the placeholder clips and the look of the textures beyond those captures.
- Android, macOS, web, Linux arm64 and any export: the libraries are gone, and exports were not run. `export_presets.cfg` is unchanged and points to paths outside this copy.
- Steam Deck.

## References that lead nowhere

Comments and documents cite decisions (`D-0xx`), audit items and files such as `docs/DECISIONS.md`, `docs/MIGRATION_STATUS.md` and `docs/superpowers/...` that are not in this copy. `docs/reviews/FULL_AUDIT_2026-10-14.md` is dated: several of its items were fixed after it, so check each against the code before relying on it. `docs/GODOT_WORKFLOW.md` lost its final sections (MCP servers, editor coexistence, work cycle) and the Blender MCP paragraph.
