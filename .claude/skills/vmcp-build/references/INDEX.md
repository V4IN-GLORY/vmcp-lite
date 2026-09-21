# vmcp-build reference library

Read this once at the start of a build. Load a file when the step that needs it comes up, not
before. Each line: file — what's in it — when to load.

## Always relevant, by phase

| file | what | load when |
|---|---|---|
| `materials.md` | palette roles, placement rules, the bland test, variety by role, the accent vocabulary, grounds, ruin-as-data | phase 1 (palette table), and before any pass that textures walls |
| `scale.md` | the character-as-ruler table, `ScaleRef` | phase 1 (access list), and whenever a size is in doubt |
| `geometry.md` | boxes-only rule, arches, projection, no-gaps, Z-fighting + the mechanical coplanar check, openings, glass, gables, cutaway flag, coplanar offenders by class, stale-server workaround | before the shell / opening / roof passes; the coplanar check runs after **every** apply |
| `props.md` | `placeOn`, candles, rubble bedding, hero-prop budget and render pass | before interior / exterior / hero prop passes |
| `lighting.md` | Light instances, Neon sources, beams, per-effect particle setups | before the effects pass |
| `renderer.md` | what the rasterizer draws, view presets, targeted panels, `get_build` round-trip and limits, tool quirks | first render of a session, and whenever a panel doesn't show what you asked for |
| `inspect.md` | phase 4 in full: sweep, cutaway, the checklist, what a panel must prove | start of phase 4 |
| `field-notes.md` | the failures that survived the pipeline: inverted directions, double rotations, QA assertions in the build, transport limits, report triage | first time a six-rule item bites; before phase 4 on 300+ parts |
| `context-budget.md` | why one long session costs 30× and how to run phases in fresh contexts | before starting anything over ~300 parts, or when a session passes ~40 % of the window |

## Build types — `types/`

Per-type tips written from real builds. Name the type at the end of phase 1 (`-- type: <name>`)
and load `types/<name>.md` if it exists. If it doesn't, build from the core and offer to write
one afterwards — `types/README.md` has the template and the PR steps.

| type | covers |
|---|---|
| `cathedral.md` | churches, chapels, abbeys, gothic ruins — nave/aisle/tower proportions, pointed arches, buttresses, tracery, ruin tables |
| `slop-game.md` | fast stylised maps for obbies, tycoons, simulators — flat colour, big readable masses, spawn/pad conventions, part budgets |

Add a row here when you add a type.
