# Field notes — failure modes that have already happened once

The pipeline in SKILL.md is correct, and it was followed to the letter on a 1 500-part build that still
shipped a valley where its roof should have been and a set of horizontal logs where its trees should
have been — with four render passes and a QA line reading "0 unsupported, 0 paper thin" on the record.
Nothing here replaces the phases; this is the list of things that survive them.

Every item is written as a **general rule**, with the instance that produced it in a line or two
underneath. The instance is there because a concrete case makes a rule stick, not because the rule
only applies to it. If you catch yourself thinking "this one is about roofs", you have read it wrong:
it is about anything with a direction, any helper that already orients a part, any report you skimmed,
or any render you accepted without naming what it proved.

### 1. A direction can be inverted without moving a single number the report prints

Applies to: sloped planes, stairs and ramps, tapering stacks (each stage narrower than the one below),
arch springing and voussoir taper, wall and face normals, the raised end of a fallen beam, a shaft or
blade or barrel, a roof overhang, lettering on a sign, a bracket that must hang downward.

Why it slips through: **orientation is not in the bounds.** Turning a part about its own centre leaves
its bounding box unchanged; mirroring a placement leaves the extents identical; reversing a taper
leaves the size the same. Every check that reads sizes, counts, overlaps and support is blind to it.
This file already says the report "can't see a backwards roof slope" — that is exactly right, and it
is not a licence to move on. Only two things catch this class of error:

- an explicit assertion in the build's own QA (§3), and
- a render panel in which the direction is actually visible (inspect.md).

Instance: a sloped plane was written `CFrame.Angles(0, 0, side * pitch)` where the geometry needed
`-side * pitch`. Its own long axis therefore climbed outward, so its high end sat at the outer edge
and its low end at the centre line — two slopes meeting in a valley in the middle of a building that
should have carried a gable, with the ridge cap left hanging above the gap. Bounds, group extents,
part count, `unsupported: 0` and `paper thin: 0` all passed on that build.

### 2. A helper that already orients a part must not be oriented again

Applies to: anything with a length along one axis — posts and columns, trunks and branches, axles and
pivots, chains and cables, rafters, ribs, limbs, barrelled props, beams spanning two points.

Most builder sets bake a rotation in so callers can think in the part's own terms: a vertical-post
helper turns a cylinder's length onto +Y, a "through the wall" helper turns it onto the wall normal, a
"between two points" helper uses `lookAt`. That rotation is applied *after* the caller's frame, so
adding another turn about the same axis **composes** with it rather than replacing it — and two
quarter turns cancel into a half turn. The symptom is always "it came out lying down / pointing
backwards / 180° from what I asked", and it usually drags the attached detail with it: roots, boughs,
crowns, brackets, hands, blades.

Rule: know each helper's axis convention, and rotate a thing once. Keep a table of your own helpers
somewhere you will actually read it, and when something must point where no helper covers, reach for
the between-two-points helper rather than stacking rotations.

Instance: tree trunks were built with the through-the-wall helper *and* an extra quarter turn, so every
trunk lay horizontally at chest height with its roots underneath and its crown boughs hanging in the
air around it. Same class, found by sweeping rather than by luck: a wheel hub built with the
vertical-post helper where it needed an axle along the wall normal, and a ribcage built from rods
pointing the wrong way through the chest.

Two habits that close the whole family: **sweep every call of the helper** rather than fixing only the
element that happened to be noticed, and **grep by helper name** before calling the class fixed.

### 3. Put the assertion in the build, not in the transcript

If you can state an invariant in words, you can assert it in a line and print PASS/FAIL — and then the
QA travels with the map instead of living in the conversation. Reviewing by eye at the end of a long
session is precisely the step that fails, because by then the panel that would have shown it is twenty
turns back.

One check per invariant, each counting its own violations, one line of output each:

```lua
-- named(pattern) is your own filter over the build's parts; any list of BaseParts will do.
local faults = 0
local function check(label, list, holds)
	local bad = 0
	for _, d in ipairs(list) do
		if not holds(d) then bad += 1 end
	end
	faults += bad
	print(string.format("[build] QA  %-30s %4d checked, %d wrong", label, #list, bad))
end

check("sloped planes climb inboard", named("^Slope"), function(d)
	local axis = d.CFrame.XVector                       -- the part's own long axis
	local inward = if d.Position.X >= 0 then 1 else -1
	-- moving toward the middle must mean moving up, whichever way the box is turned
	return math.abs(axis.Y) > 0.2 and axis.Y * axis.X * inward < -0.1
end)
check("posts stand vertical", named("Post"), function(d)
	return math.abs(d.CFrame.XVector.Y) > 0.97
end)
check("openings clear the threshold", named("^Step%d"), function(d)   -- no prop stands in a doorway
	return true
end)
check("props are bedded, not floating", named("^Rubble"), function(d)
	return d.Position.Y - d.Size.Y / 2 < 0.2
end)
if faults > 0 then print("[build] QA  FAULT -- see the lines above") end
```

Shape the list per build: every run of stairs (which way it rises), every ramp, every tapering stack
(each stage smaller than the last), every opening (clear width and height at the threshold), every
overhang (which side is longer), every prop resting on a surface (bedded by the intended fraction),
every element whose function depends on facing a particular way. Assertions cost two lines; a rebuild
costs the session.

The same idea replaces re-reading hundreds of overlap lines: state the *intent* — a prop is bedded a
fifth to a third of its height into the ground, trim stands proud by the trim offset, every layer
differs from the one beneath by the epsilon — and let the check confirm it, instead of arguing with
the report about each pair.

### 4. Transport limits: batch the source, and never clear inside a big apply

- **Large code arguments are truncated in transit.** A single apply of a whole build arrived cut
  mid-line and Studio answered `Expected 'end' (to close 'do' at line N), got <eof>`. Batch instead —
  one phase or one group per apply, comfortably under ~20 KB.
- **Never pair a first-time large apply with a clearing flag.** The truncated chunk still ran far
  enough to delete the previous build, so the map was gone *and* the error pointed at the new code.
  Clear only in a small, verified apply.
- **A syntax error naming the last line of the file is a truncation symptom**, not a missing `end` in
  your logic. Measure the payload before hunting for the mistake in your own code.
- **When a source is split mechanically, carry the text between sections with the following section.**
  Helpers often sit between two phases; splitting on "the first line that starts a section" leaves them
  behind, and the build dies later with `attempt to call a nil value` at the first call to one.
- **Reading a long file back truncates as well**, sometimes silently and mid-file, which then produces
  a bogus header and a syntax error in every batch built from it. Read by line range, assert the last
  line and the total count, and only then trust a slice.
- **`return` your evidence, do not print it.** A printed line from an executed snippet is not reliably
  part of the tool's returned text (it lands in the Studio output window instead), so a snippet that
  prints its answer reads as an empty result.

### 6. Triage the report instead of skimming it

The problem list is the loudest thing the tools return, and it is mostly right. Read it as a
classification exercise, and be able to say which class every entry falls into:

- **Overlap** — usually intentional. Interfacing parts are *supposed* to interpenetrate: trim over
  wall, a ring over the piece it beds into, a lintel into its pier, steps into the ground, bedding
  under a prop. Keep the accepted set finite and nameable for the build; an overlap you cannot name is
  probably a mistake.
- **Floating** — always investigate a *structural* part: it is the one entry that says the geometry is
  not doing what it claims. Between two parts of the same assembly (link to link, chain to ring) it is
  the checker's granularity. **No build is closed with an unexplained floating report.** On the build
  behind these notes, two floating entries were written off as noise and were the roof bug in plain
  sight.
- **Off axis** — intended for organic or damaged elements (rubble, tilted stones, trees, debris), wrong
  for designed-square ones (trim, sills, frames, plates). Decide per element, not per build.
- **Coplanar faces** — a real risk only when two overlapping parts share a plane on all three axes. The
  antidote is systematic (a trim offset, a layer epsilon, a per-step nudge) rather than a fix per pair.
- **Near-duplicate names or identical positions** — a pass ran twice, or a name-based reuse helper was
  bypassed. Fix the reuse, not the duplicates.
- **Paper thin** — a dimension computed to nothing, usually a derived size that went to zero or
  negative and was clamped. Find the arithmetic, not the part.

### 8. Working efficiently in a long build

- Keep the source in **one file on disk** and assemble each apply from that file (read the ranges,
  concatenate, send) instead of re-typing geometry into tool calls. Re-sending a large preamble once
  per iteration is how a session runs out of room.
- Make every builder **idempotent and name-based**, so one group can be re-applied after a fix without
  stacking a second copy and without touching anything else.
- When you fix something, re-apply **only the sections you touched**, re-run the assertion line, and
  re-render the single panel that proves the change.
- **Log one line per pass** — what the numbers said, what the picture showed, what you changed. A build
  whose QA prints PASS/FAIL carries its own evidence; a build whose QA lives in the transcript does not.

