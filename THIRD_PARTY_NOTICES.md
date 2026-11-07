# Third-party notices

Provenance as recorded by the project owner in the project's tools and licences register, plus the licence files listed here. Each licence file stays next to its component.

| Component | Path | Licence | Licence file |
|---|---|---|---|
| Terrain3D 1.0.2 (Cory Petkovsek, Roope Palmroos and contributors) | `godot/addons/terrain_3d/` | MIT | `godot/addons/terrain_3d/LICENSE.txt` |
| Debug Draw 3D 1.7.3 (DmitriySalnikov) | `godot/addons/debug_draw_3d/` | MIT | `godot/addons/debug_draw_3d/LICENSE` |
| Debug Menu 1.2.0 (Hugo Locurcio and contributors) | `godot/addons/debug_menu/` | MIT | `godot/addons/debug_menu/LICENSE.md` |
| Controller Icons 3.1.8 (Ricardo Subtil) | `godot/addons/controller_icons/` | Addon: MIT. Icons, per the upstream README: Xelu's Free Controllers & Keyboard Prompts by Nicolae Berbece and additions by @TacticalLaptopBag and @DataPlusProgram, CC0. Addon icon by @adambelis, CC0, using the Godot logo (CC BY 4.0, Andrea Calabró) | `godot/addons/controller_icons/LICENSE` |
| SimpleGrassTextured 2.1.0 (IcterusGames), plugin not enabled | `godot/addons/simplegrasstextured/` | MIT | `godot/addons/simplegrasstextured/LICENSE` |
| Alfa Slab One (JM Sole) | `godot/assets/fonts/AlfaSlabOne-Regular.ttf` | SIL OFL 1.1, Reserved Font Name "Alfa Slab" | `godot/assets/fonts/OFL-AlfaSlabOne.txt` |
| Rubik (The Rubik Project Authors) | `godot/assets/fonts/Rubik[wght].ttf` | SIL OFL 1.1 | `godot/assets/fonts/OFL-Rubik.txt` |
| Universal Animation Library Standard 1.0 (Quaternius): clips in `player_engineer.glb` | `godot/assets/models/player_engineer.glb` | CC0 1.0 | `docs/licenses/Quaternius-UAL-CC0.txt` |
| Terrain textures: Poly Haven (asphalt_02, brown_mud_leaves_01, concrete_debris), ambientCG (Ground037, PavingStones149, Ground104, Gravel040), downscaled | `godot/assets/textures/terrain/` | CC0 (register entry; licence pages https://polyhaven.com/license and https://docs.ambientcg.com/license/) | none, CC0 requires none |
| Wall textures: Poly Haven (damaged_plaster, concrete_moss, red_brick_plaster_patch_02, concrete_floor_damaged_01), downscaled | `godot/assets/textures/surfaces/walls_*` | CC0 (register entry) | none, CC0 requires none |

Two project shaders derive from Terrain3D 1.0.2 (MIT, same copyright as above) and stay under its terms: `godot/resources/materials/grass_field_process.gdshader` (from its particle example) and `godot/resources/materials/terrain_relief.gdshader` (from the shader it generates). `godot/addons/debug_menu/debug_menu.gd` carries a small change, described in `docs/COPY_NOTES.md`.

The Terrain3D and Debug Draw 3D native libraries are included for Windows and Linux x86_64 only.

Godot Engine is not included; it is distributed under the MIT licence by its own project.

The rest of this copy is under the Apache License 2.0: see `LICENSING.md`.
