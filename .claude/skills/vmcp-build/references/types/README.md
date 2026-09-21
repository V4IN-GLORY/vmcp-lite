# Build types

One file per kind of thing people build. The core skill knows how to build anything; a type file
knows what *this* kind of thing needs that the core doesn't say — the proportions that make it
read, the palette that fits, the details that sell it, and the mistakes that have already
happened on one.

## For the model

- Name the type at the end of phase 1 as `-- type: <name>` in the design block.
- If `types/<name>.md` exists, load it before the blockout. It overrides nothing in the core;
  it adds numbers and defaults so you don't rediscover them.
- If it doesn't exist, build from the core. When the build is done and the user is happy, offer
  once: "want me to write this up as `types/<name>.md` so the next one starts from here?" Fill
  the template below from what you actually did and what actually went wrong — not from
  general knowledge.

## For the user — turning a build into a reference

After a build you're happy with:

1. Ask the model to write `references/types/<name>.md` from the template below. It should pull
   the numbers from the design block and the source, the palette from `P`, and the failure
   modes from the pass lines it wrote during the build.
2. Read it. Cut anything that's the core skill restated. Keep only what's specific to the type.
3. Add a row to `references/INDEX.md`.
4. Open a PR against the repo with just those two files. Title: `build type: <name>`.

Keep it under ~150 lines. A type file the model has to scroll is a type file it won't read.

## Template

```markdown
# <Type name>

When this applies: <one line — the prompts that should load this file>.
Doesn't cover: <one line — near-misses that want a different type or the plain core>.

## Masses and numbers

The 3–5 masses and the base numbers that worked, with the ratios that made it read:

- <mass>: <size>, <proportion to another mass>
- W, D, H, T defaults: ...
- bay count / pitch / floor heights: ...

## Access

What an interior of this type needs to be walkable — openings, stairs, the sizes that were
right at character scale.

## Palette

The `P` table that worked, as code, with the placement comments. Say which roles carried the
build and which one was the warm accent.

## Details that make it read

The accent pieces and props that turned the blockout into the thing, in the order they earned
their place. Helpers worth copying go here as short code blocks.

## Failure modes seen on this type

Each one: what it looked like in the render, what the derivation bug was, the fix. These are
the most valuable lines in the file.

## Source snippets

Optional. Helpers specific to the type (an arch, a crenellation run, a conveyor, a checkpoint
pad) that a future build can paste in.
```
