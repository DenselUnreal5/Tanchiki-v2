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

Rendering is selected by the map's location ID, including the existing chunk
cache; map generation, collision and movement rules are unchanged.

Resource checks (Godot 4.7, from repository root):

```sh
godot --headless --path godot --editor --import
godot --headless --path godot tests/terrain_textures_check.tscn
godot --headless --path godot tests/locations_check.tscn
godot --headless --path godot tests/map_check.tscn
```
