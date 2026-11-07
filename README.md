# Dwarmageddon: Dig or Die (reduced source copy)

A single-player 3D isometric survivor-like with terrain transformation, in development. Written in GDScript for **Godot 4.7.2 standard** (not .NET), about 219 project scripts and 60 test suites.

This is a size-reduced copy of the working branch, not a release. Code comments and documents are in Italian; identifiers are in English.

**Licence:** the author's content in this copy is under the Apache License 2.0 (`LICENSE`, `NOTICE`). Third-party components keep their own licences. `LICENSING.md` says which paths each licence covers, and `THIRD_PARTY_NOTICES.md` lists the components. The game's name and logo are not licensed as trademarks.

## What the game has

Two levels (district, railway) on a Terrain3D height field, a player tool that digs and raises terrain, enemy hordes on a flow field, bosses, train and earthquake events, day/night with placeable lamps, a weapon and class system, a caravan of modular machines with fusion, a workshop with a persistent profile, and a campaign map. Colossus piloting is only partly built.

| Path | Content |
|---|---|
| `godot/scripts/` | Game code, by domain (`arena`, `run`, `caravan`, `combat`, `enemies`, `terrain`, `navigation`, `player`, `progression`, `ui`, `services`, `audio`) |
| `godot/tests/` | Test suites run with `--script`; `godot/tests/tools/` holds capture and benchmark scripts, which are not suites |
| `godot/scenes/`, `godot/resources/`, `godot/levels/` | Scenes, tuning data and shaders, baked relief |
| `godot/assets/` | Models, textures, fonts (reduced, see below) |
| `godot/addons/` | Third-party addons |
| `docs/` | Technical documents: start from `docs/GODOT_WORKFLOW.md`; what differs from the full project is in `docs/COPY_NOTES.md` |
| `tools/godot/` | `run_checks.sh` (Linux, headless) and `Invoke-GodotChecks.ps1` (Windows, the project's own gate) |

## Differences from the full project

- **No sound files.** The 47 effects in `godot/assets/audio/sfx/` were derived from a third-party library that cannot be redistributed. 28 ids fall back to code synthesis; the 19 weapon ids have no fallback and stay silent.
- **Five placeholder animations** on the player model: `Strafe_Left`, `Strafe_Right`, `Run_Bwd`, `Dig`, `Dodge`. They are retimed copies of CC0 clips with the original names and durations; they do not look like the real motions.
- **One patched addon file:** `godot/addons/debug_menu/debug_menu.gd` skips its startup thread under `--headless`, which otherwise stops suites from exiting.
- **Textures at 1/4 resolution** in `godot/assets/textures/{surfaces,terrain}/` and `godot/assets/models/`; expected sizes changed accordingly in `godot/tests/restyle_tests.gd`.
- **Native libraries** for Windows and Linux x86_64 only. No Terrain3D editor brushes.
- **Not included:** Blender and audio pipelines (`tools/blender`, `tools/audio`), so models and sounds cannot be regenerated here; design, business and playtest documents.

## Running

Godot is not bundled. Download Godot 4.7.2 standard, then:

```bash
export GODOT_BIN=/path/to/Godot_v4.7.2-stable_linux.x86_64
"$GODOT_BIN" --headless --path godot --import                     # required once on a clean tree
"$GODOT_BIN" --path godot                                         # play (needs a display and GPU)
"$GODOT_BIN" --headless --path godot --quit-after 180 -- --autostart   # headless start of a level
```

The first import prints about 40 `ERROR:` lines about `res://.godot/imported/...` and `theme.tres`: the project theme loads before the cache exists. A second import prints none.

## Checks

```bash
bash tools/godot/run_checks.sh                        # import, check-only, all suites, smoke test
bash tools/godot/run_checks.sh --no-import --no-check-only --no-smoke --suite audio_tests
"$GODOT_BIN" --headless --path godot --fixed-fps 60 --script res://tests/<suite>.gd
"$GODOT_BIN" --headless --path godot --check-only --script res://<path>.gd
```

`run_checks.sh` needs bash, `timeout`, `xargs` and `pkill`. Results go to `output/checks/` (`suites.tsv` holds one row per suite). A suite counts as OK only with exit code 0, `PROTOTYPE01_TESTS PASS` and no runtime errors.

Headless runs do not exercise Terrain3D rendering or shader compilation, and they cannot judge sound, animation or particle effects.

**Expected baseline of an unchanged copy:** the gate exits 1 because `audio_tests` fails on the missing sound files. Details and measurements are in `docs/COPY_NOTES.md`.
