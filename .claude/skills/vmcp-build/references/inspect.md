# Phase 4 -- inspect

Load only after every group is done. Per-group passes only ever looked at their own group; the bugs left are the ones between groups.

**4a. The sweep.** One call, whole build:

```
render_build { root = <whole build>, size = 768, views = [
  "iso", { yaw = 225, pitch = 30, name = "iso-back" },
  "front", "back", "left", "right",
  "top",
] }
```

Then targeted panels, `clip = true`, one per place two groups meet: roof on wall, porch on
facade, stair on ledge, props against walls, tower on nave. Aim `at` the join, `radius` a few
studs, two angles each. As many calls as it takes — the sweep is done when every face of every
group and every join has been in at least two panels, and you've written that coverage line.

**4b. The cutaway.** The renderer draws transparency as alpha, so give the source an
`INSPECT` flag that sets the roof group and one long wall to `Transparency = 0.75` when true.
Apply with it on, render `top` and an iso from the open side, and the interior is visible
without the roof hiding it. Set it back to false and re-apply when done — never leave it on.

**4c. The checklist.** Go through every item and write "checked: fine" or the fix. Not
optional, not "looked fine":

- **Access.** Walk the access list from phase 1 against the cutaway and the elevations. For
  every interior space: is its opening present in the wall, at the width and height from the
  list, on the correct wall, at floor level (sill at `floorTop`, not 1 stud up)? Is the path
  from outside to it, and from it to every neighbouring space, unblocked by a prop, a pier, a
  buttress, a stair landing? Does every stair reach both floors it connects, top step at the
  upper floor's height, headroom ≥ 7 over every step? A space with no way in is a bug unless the
  design block said it's sealed.
- **Gaps.** Sky visible through any roof or wall in any elevation or the cutaway? Slits between
  roof slabs, between wall pieces around an opening, at a corner? Each one is on the access
  list or it's a bug — fix the overlap, not the picture.
- **Primitives.** Any wedge, cylinder or ball that isn't a roof plane, ramp, column, trunk,
  barrel, globe or boulder? Rebuild it from boxes.
- **Lighting.** Every light source is a Light instance; no glass slabs or tinted boxes standing
  in for rays or glow. Nothing under `game.Lighting` changed.
- **Covered up.** Every named feature is findable in at least one panel. A window the porch roof
  now hides, a door behind a buttress, a prop inside a wall, a feature only visible from an
  angle nobody stands at.
- **Scale.** Check every opening, step, ceiling and prop against the Scale table with the
  `ScaleRef` figure in frame — a player is 5 tall and 2 wide, and if it can't walk through
  a door, up a step, or under a beam, the number is wrong. Then group against group — a porch
  a third the height of the door it shelters, a tree taller than the tower.
- **Prop placement.** Every prop on a surface is fully inside its footprint, bottom on the
  top face, sized like the real thing beside the ScaleRef. Nothing overhangs an edge, nothing
  hovers beside the thing it's meant to be on. Small props are clustered, not lined up.
- **Hero props.** Each named prop has had its own three-angle close-up, has 20+ parts or a
  mesh, a distinct material from its surroundings, and a physical mount. None is a box with a
  cylinder on it.
- **Particles.** Every emitter has a texture, size and transparency curve, lifetime, rate and
  speed set for what it is (fog, motes, embers, smoke). No default white sparkles anywhere.
- **Orientation.** Wedges sloping the wrong way, a roof pitch that reads inverted from the back,
  a rotated roof box sloping into the wall. The renderer models wedges as Roblox does — a wedge that
  looks backwards is backwards.
- **Silhouette.** The back reads as well as the front; no blank face the design didn't intend.
- **Material placement.** Run the bland test on every room and every exterior face: three
  roles visible from one standing spot, one of them warm, floor ≠ wall, plinth and cornice
  present, columns not the wall's material. No panel is more than ~60% one material. The
  palette table's comments match what's actually on each surface.
- **Seams.** The coplanar check printed nothing. Quoins and trim are `PROUD`, four walls are
  two long and two short.

Fix in the source, re-apply, re-render only the panels that showed the problem. Done when every
checklist item has its line and every panel reads.


## A render is a claim you have to be able to cash

"The render was done" is not "the geometry was checked". Before writing a pass line, **name the two or
three properties that panel is supposed to prove, and say how each one is visible in it**:

- a slope or ramp → which way it falls, and where the high edge runs;
- a vertical element → that it stands vertical, is rooted, and carries what sits on it;
- an opening → that the way through is clear, at the size a character needs;
- a junction → that the two surfaces meet with no slit and no doubled face;
- a prop on a surface → that it is bedded, not balanced on a corner or hovering;
- scale → something character-sized standing beside it.

If the panel cannot show the property, the panel does not count and you take another one. Practical
consequences: aim views with a path and a small radius; remember that a cutaway is made by transparency
in the *source*, not by the camera; and treat a night look as presentation on top of verified geometry,
because a dark scene with fog and a grade is nearly unreadable for shape. Check shape first, light it
afterwards.

Two failure patterns to watch for in yourself: accepting a whole-build thumbnail as evidence about a
detail, and quoting a number in the summary that you did not compute in that same pass.

