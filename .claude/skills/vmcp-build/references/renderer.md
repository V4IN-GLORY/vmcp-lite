# The renderer, render_build views, get_build

VMCP's own rasterizer (`server/src/scene.ts`), not Studio — works with Studio minimised.

- **Orthographic, one scale across panels**, so panels compare directly.
- **Flat shading, dark line on every edge**, lit from the camera. "Is that one part or three" is
  visible even where faces are flush.
- **Real box / ball / cylinder / wedge**; meshes and unions as bounding boxes; transparency as
  alpha. Lights, decals, beams, particles don't draw.
- **Real material colormaps** tinted by part colour; materials it lacks (Cardboard, Neon,
  ForceField) draw flat. Plastic is always flat.
- **Badges** match the legend; on when the panels show ≤ 40 parts (a clipped panel counts only
  what's inside its radius), off otherwise unless `badges = true`. No badges, no legend — the
  per-part list only exists when the numbers in it point at something in the picture.
- **Views**: `iso`, `corner`, `front`, `back`, `left`, `right`, `top`, `bottom`, or
  `{ yaw, pitch, name }` in degrees. Up to 9 tiled into one sheet; `size` 128–1024 per panel,
  default 512, sheet caps at 3072 wide.
- **Targeted**: `at` (`{x, y, z}` or a dotted path, pivot used) + `radius` centres and scales
  that panel; `clip = true` drops parts further than `radius` from `at`; `view = "front"` picks a
  preset angle in place of yaw/pitch. Targeted panels have their own scale.
  ```
  render_build { root = "Workspace.Chapel", views = [
    "iso",
    { view = "front", at = "Workspace.Chapel.Shell.Door", radius = 8, clip = true, name = "door" },
    { yaw = 30, pitch = 15, at = {12, 4, -20}, radius = 6, name = "sill" },
  ] }
  ```
- PNG lands in the server's `images/` dir under `name`; inlined when small, path printed always.

`front` / `left` for proportions, `top` for footprint, `iso` for whether it reads. Wedges and
rotated parts are where the picture earns its keep — the report can't see a backwards roof slope or a slit between two slabs.

## Existing regions

`get_build { root, depth }` returns the region as this same kind of source — a dump, not derived.
A plain anchored part is one `part(parent, name, class, size, cframe, material, color)` line;
anything with more going on (transparency, collision, lights, emitters) is `ensure` plus one line
per non-default property. Colours come back as `fromRGB`, right-angle rotations as `math.rad`. Small edit: change lines, apply back. Restructure: read it for
sizes and positions, write a derived source, apply with `clear = true`. `render_build` first,
before touching anything that exists.

Applying the same source to another root copies it; a missing last segment is created as a Model.
`vmcp.Build.Problems(root)` / `vmcp.Build.Report(...)` are the same checks from `run_luau`.

Covers parts, meshes, decals, textures, attachments, lights, emitters, beams, surface
appearances, GUI objects, attributes and tags. The dump's property list is curated, so a class
property not on it is silently absent from `get_build` — first thing to check if a round-trip
comes back wrong.

Limits: `get_build` `depth` 12, `maxNodes` 800; `apply_build` / `render_build` measure up to
1500 parts. Always pass `root` — the default is the whole Workspace, which hits the cap on any
real place and measures everything that isn't the build. Prefer a narrow `root` over a bigger cap.


## Tool behaviour to design around

- **Always pass an explicit root.** The default root is the whole Workspace: it measures everything
  that is not the build, blows the part cap on any real place, and — because Terrain is itself a part
  — can fail outright with `GetPartsInPart does not support Terrain` before anything is drawn. Narrow
  roots also make the report readable.
- **A view target that is silently ignored looks exactly like a badly framed picture.** Views take a
  dotted path for their target; a numeric coordinate table is accepted and ignored, so a "close-up"
  quietly becomes another whole-build view. If a panel is not closer than the last one, it is not
  closer — pass the path.
- **Every render and apply returns a full report** (summary, every problem, every part). Batch as many
  views per call as the tool allows, turn off problem-checking and part badges when you only need the
  picture, and keep your own printed output to a line or two. Pictures attach regardless of what you
  print.
- **Not every class can be created from a script.** Some instances exist only as engine-owned or
  editor-authored objects, and `Instance.new` fails with "Unable to create an Instance of type ...".
  Find the creatable equivalent that carries the same effect and build that instead, with a stable name
  so re-runs reuse it rather than stacking another.
- **Long files truncate when read**, both through the file tool and through a shell's stdout. Assume
  nothing about a slice you did not measure.

