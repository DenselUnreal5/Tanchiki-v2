# Terrain artwork

`biomes.png` is an 8-column, 4-row sprite atlas. Rows: winter (`frost`),
industrial exclusion zone (`exclusion`), coast (`shore`), wasteland (`dust`).
Columns: ground, secondary ground/sand, tree, bush, masonry roof, wooden roof,
citadel, warehouse. Ground cells are opaque; props have transparent backgrounds.
The artwork was generated for this project. `TerrainTextures` selects normalized
atlas regions and clips filtering at the cell borders.

The new biomes reuse the city's road and bridge geometry. `TerrainTextures`
adapts green verges to each biome once, caches the result, and leaves the shared
city source images unchanged. Wide water tiles use banks only on sides adjacent
to land, so the coast has continuous open sea rather than repeated river corners.
The existing desert cacti and oilfield props remain in use in `dust`.

Desert ground now uses `dust/sand_ground.png`, imported at 64 pixels. Empty
ground, sand and dune tiles share this quiet sandy surface, including beneath
transparent props. Roads use the city's neutral curbs with matching sandy
verges, and water uses muted blue-green tones. The map editor draws the same
sand and bank textures as gameplay instead of painting sand with a flat color.

Rendering is selected by the map's location ID, including the existing chunk
cache; map generation, collision and movement rules are unchanged.

Resource checks (Godot 4.7, from repository root):

```sh
godot --headless --path godot --editor --import
godot --headless --path godot tests/terrain_textures_check.tscn
godot --headless --path godot tests/locations_check.tscn
godot --headless --path godot tests/map_check.tscn
```

For a rendered editor/game regression check, run with a graphics display:
`godot --path godot tests/desert_render_check.tscn` (X11/Xvfb works on Linux).
