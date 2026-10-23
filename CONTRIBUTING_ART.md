# Adding art and sound to Rustbound

You can make the game look and sound better without touching code or breaking
gameplay. Art owns the files in `assets/`; design owns the `.tres` data in
`data/`; code owns `scripts/`. The **validator** enforces the contract below,
so you find out about a problem from a clear message, not a broken build.

## The look in one paragraph

PS2-era low poly. The 3D view renders at about 360 lines with dithering, so
detail you can't see at that size is wasted. Chunky silhouettes that read from
a high three-quarter camera, flat-ish shading (vertex lighting), small
nearest-filtered textures, a limited palette. Every weapon should be
recognizable from above at that resolution.

## Budgets

| | Robot parts | Enemies | Props |
|---|---|---|---|
| Triangles | 200 to **800** | 150 to **400** (hundreds on screen) | up to 1,500 |
| Texture | **128 px** max, one per part | **128 px** max, one material | 128 px, tiling or atlas |
| Size | real size, 1 unit = 1 m, longest side under 4 m | about 2 to 4 times the collision radius tall | real size |

Bold numbers are hard limits (errors). Powers of two for textures. Vertex
colors are fine for grime and fake AO.

## Folder layout

```
assets/parts/<part id>/<part id>.glb      e.g. assets/parts/gun_nail/gun_nail.glb
assets/enemies/<enemy id>/<enemy id>.glb  e.g. assets/enemies/skitter/skitter.glb
assets/props/<name>/<name>.glb
assets/audio/sfx/<sound id>.wav|.ogg
```

Part and enemy ids are the `id` in `data/parts/*.tres` and
`data/enemies/*.tres` (the file names match). Folders starting with `_` (like
`_examples`) are ignored by the game.

**Start from the examples:** `assets/parts/_examples/example_turret/` and
`assets/enemies/_examples/example_bug/` follow every rule below. Open them in
Blender (File > Import > glTF) to see the setup.

## Modeling rules

1. **Origin = attach point.** For a part, the origin is where it bolts onto
   the robot (usually the bottom centre of its mounting face). For an enemy,
   the origin is between its feet on the ground.
2. **Facing: model it the usual Blender way**, front towards Blender's
   **-Y** (what the Front view looks at), top towards **+Z**. The importer
   turns it to face the game's forward.
3. **Sockets are empties.** Wherever something can attach to your part (a
   barrel tip, a foot, a top mount), add an Empty named `Socket_<name>`, where
   `<name>` matches the socket's `marker_name` in the part's `.tres` (ask, or
   look in the inspector under Sockets). Leave it unrotated so whatever
   attaches faces the same way as your model. The import turns it into a
   marker the game snaps to.
4. **No collision in the file.** Don't use `-col`/`-colonly` names; gameplay
   collision comes from code.
5. **Materials:** any Principled BSDF with a base color texture is fine. On
   import every surface is converted to the PS2 material automatically (keeps
   the texture and base color). Use one material per enemy.
6. Export as **glTF Binary (.glb)**, +Y Up, apply modifiers.

## Hooking it up

- **Part:** select `data/parts/<id>.tres`, drag your `.glb` into its
  **Scene** field. Done. Clear the field to go back to the placeholder.
- **Enemy:** select `data/enemies/<id>.tres`, drag the `.glb` into
  **Visual > Model** and adjust **Model Scale** if needed. Its meshes are
  merged into one for the horde renderer.
- **Sound:** drop `<sound id>.wav` (or `.ogg`) in `assets/audio/sfx/`,
  replacing the placeholder. The ids are listed in `autoload/Sfx.gd`
  (`SOUNDS`). Weapons use `fire_<part id>` (e.g. `fire_gun_laser.wav`); a
  weapon with no file of its own uses `fire_default`. Keep one-shots short
  (under 3 s), mono, trimmed tight at the start.

## Checking your work

- In the editor: **Project > Tools > Validate assets.** Errors and warnings
  appear in the Output panel, each naming the file and what to fix.
- From a terminal: `godot --headless res://tools/pipeline/validate_assets.tscn`
  (exit code 1 on errors).
- A **contact sheet** of every part and enemy: run
  `res://tools/pipeline/contact_sheet.tscn` (F6 on the scene). It writes
  `user://contact_sheet.png` (Project > Open User Data Folder). A `*` after a
  name means it's still a placeholder.
- CI runs the validator and attaches the contact sheet to every pull request.

## Placeholders

`tools/gen_placeholder_sfx.py` regenerates the synthesized placeholder sounds.
Placeholder part and enemy shapes are generated in code from each `.tres`
(`Visual` group) until a model is assigned. `tools/pipeline/make_example_assets.gd`
regenerates the two example models.
