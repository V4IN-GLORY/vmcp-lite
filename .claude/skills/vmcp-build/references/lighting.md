# Lighting and effects inside the build

Load before the effects pass. Never `game.Lighting` -- see the hard rule in SKILL.md.

Light is made with light instances, not with geometry pretending to be light:

- `PointLight` in a lantern or fire, `SpotLight` from a window or doorway inward, `SurfaceLight`
  on a glowing panel. `Brightness` 1–3, `Range` 8–30, a warm `Color` for flame.
- A visible light *source* is a small Neon part (a candle flame 0.3 studs, a lamp globe) with a
  `PointLight` inside it.
- Godrays / light shafts are a `Beam` between two attachments (Transparency sequence fading to
  1, `LightEmission = 1`, `Width0` at the window, wider at the floor) or a `ParticleEmitter`
  with a soft texture — never a tilted glass or transparent box.
- Fog, dust, smoke, embers: `ParticleEmitter` on an invisible carrier part (`Transparency = 1`,
  `CanCollide = false`). The carrier is a mount, not the effect; it never has a colour, a
  material or Glass.
- **A default `ParticleEmitter` is a white sparkle spray and is never shipped.** Every emitter
  gets a full setup: `Texture`, `Color`, `Size` (a `NumberSequence` that grows or fades),
  `Transparency` (0 → 1 over life, never constant), `Lifetime`, `Rate`, `Speed`,
  `SpreadAngle`, `Drag`/`Acceleration`, `LightEmission`, `Rotation`/`RotSpeed`. Write a
  helper per effect and name the effect, e.g.:
  - *fog*: big soft texture, `Size` 8–14, `Transparency` `{0: 1, 0.3: 0.85, 1: 1}`,
    `Lifetime` 8–14, `Rate` 1–2, `Speed` 0.3–0.8, `Drag` 1, slow `RotSpeed`, emitter shape a
    wide flat box hugging the floor, `LightEmission` 0.
  - *dust motes in a light shaft*: tiny texture, `Size` 0.05–0.15, `Rate` 6–12, `Speed`
    0.1–0.3, `Lifetime` 6–10, `Acceleration` slightly negative Y, `LightEmission` 0.6,
    emitter box the shape of the shaft.
  - *embers / candle sparks*: `Size` 0.1 → 0, warm `Color`, `Speed` 1–3 upward,
    `Acceleration` `(0, -1, 0)`, `Lifetime` 1–2, `Rate` 2–5, `LightEmission` 1.
  - *smoke*: `Size` 0.5 → 3, grey, `Transparency` `{0: 0.6, 1: 1}`, `Speed` 1, `Drag` 2.
  Restrained: a few emitters where they mean something (the light shaft, the altar candles, the
  low ground) — not one on every part.
- `Glass` is for windows and bottles, `ForceField` for force fields. Neither is a lighting tool.

Never `game.Lighting` — see the hard rule at the top.
