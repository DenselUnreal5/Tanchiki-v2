# Iron Storm — perk shorts 06–10 (English)

Five ready-to-publish videos: Evasion (level 3), Scavenger (level 3), Nitro (level 4), Energy Shield (level 4), Double Shot (level 5).

- `en/`: H.264 MP4, 1080×1920, 30 fps, 15 seconds, AAC stereo sound. English name, unlock level and effect captions are burned into the picture.
- `subtitles/`: separate English UTF-8 SRT and styled ASS.
- `posters/`: matching JPG cover frames.
- `catalog.csv` / `perks.json`: names, levels and data from the game.
- `verification.json`: media and simulation checks, including complete video decoding.
- `music-original.wav`: original procedural synth music, mixed with native game effects. No voiceover.

Staged training comparisons use normal-speed game simulation. Ordinary projectile damage against tanks is fixed at the middle of its native range for a readable comparison; Double Shot retains its 60% per-shell multiplier. Evasion remains random at 15% and displays actual dodge counts. Scavenger gets a fresh brick structure every three seconds. Nitro and shield scenes reset as separate takes every seven seconds; shield resets are not its gameplay recharge time (the actual 30-second cycle is stated in the captions).

Production sources and reproduction commands: `docs/perk-shorts.md`, `scripts/render_perk_shorts.py`, `godot/tests/perk_short.gd`. Raw AVI, logs and isolated player profiles are kept outside Git.

Use the MP4 files in `en/` for social media uploads.
