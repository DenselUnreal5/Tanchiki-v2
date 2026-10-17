# Weather artwork

The existing weather types and gameplay rules are preserved. The visual layer
uses muted colors, pixel-aligned precipitation and branching two-pixel lightning.
Rain has foreground/background drops and small ground splashes; snow has drifting
square/cross flakes and clustered snow patches on textured ground, roofs and roads.
Fog is two drifting layers of a shared, seamless noise texture with stepped alpha,
nearest filtering and a tint from the current location. It uses the simulation
tick, so it pauses with gameplay and does not require real-time shader clocks.
Day/night lighting and lamps remain active.

`godot/scripts/fx/weather_visuals.gd` owns the reusable drawing helpers.
The fog texture is generated once and shared between player views. Decoration
uses hashes instead of consuming simulation randomness. The existing weather
toggle and intensity slider apply to precipitation and fog; reduced flashes
attenuate the sky flash and lightning glow. The damaging bolt itself stays visible
when decorative weather is disabled.

Validation, from the repository root (Godot 4.7):

```sh
godot --headless --path godot tests/weather_check.tscn
godot --path godot tests/weather_visual_check.tscn
```

The visual check requires a graphics display (X11/Xvfb works on Linux). It checks
visible animation, repeatable frames, weather toggles, reduced flashes, visible
combat lightning and preservation of the simulation RNG. The gameplay suite
checks vision, traction, hearing, lightning damage and storm tree destruction.

Battlefield examples: [fog](../screenshots/weather/fog.png),
[rain](../screenshots/weather/rain.png), [snow](../screenshots/weather/snow.png),
[night storm](../screenshots/weather/storm_night.png).
