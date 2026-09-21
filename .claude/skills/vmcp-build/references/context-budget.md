# The build loop must not live in one conversation

The pipeline is a loop of small, independent commits to a file on disk. Nothing about pass 30 needs the
transcript of pass 29 — and yet that is exactly what a single-session build pays for on every request.

A real 1 500-part build, audited from its own session transcript (recipe at the end of this section):

- total: **44.3 M tokens** over 157 requests — 1.09 M fresh input, 43.2 M cached re-reads (**97.5 %**)
- peak conversation size: **644 k tokens**
- every tool result that ever reached the model, added together: 542 KB, about **139 k tokens**
- of the 1.09 M fresh input, **0.88 M — 80 % — was re-processing, not new information**

Two of those lines overturn the intuition. **The reports were not the expense**: every `apply_build` and
`render_build` result ever shown to the model is 0.3 % of the session. And **the new information was not
the expense either** — four fifths of the fresh-input budget went on re-reading text the model had
already read, because something had invalidated the cached prefix.

So cost scales as `steps × context size`, and the second factor is what punishes a long build: at a
644 k-token conversation, every single request re-reads all of it. Capping that same session at 120 k
tokens removes about 67 % of those reads; at 60 k, about 83 %.

**The most expensive thing measured in that session was looking at a picture.** Requests following an
image attach averaged **46 110** fresh input tokens; every other request averaged **1 549** — a 30×
difference — and only about 12 k of that 46 k was new content. Attaching an image invalidated the cached
prefix, so the whole conversation was re-read at full price to deliver a few thousand tokens of picture
and report. Summed over the build, image-triggered re-prefill accounted for **0.88 M tokens, 80 % of all
fresh input**. Near the end, at 560 k context, a single render cost 170 k fresh tokens to deliver about
1.7 k of new content: a hundredfold overhead on the act of checking your own work.

None of that argues against rendering — rendering is mandatory (SKILL.md). It argues for rendering
**deliberately**: take every view a pass needs in one attach, take them while the context is short, and
never re-attach a picture you have already shown.

1. **One phase per fresh context.** State belongs on disk and nowhere else: a phase should read only the
   line ranges it needs, change the file, run its own assertions, and end by returning a short report —
   not by accumulating. A long build is a *sequence* of short sessions. If the harness has subagents, one
   detail group is a natural unit of delegation: fresh context in, file changed, half a page out.
2. **Spend the context budget deliberately; never discover the ceiling.** Plan the hand-off at roughly
   40 % of the window. A compaction you schedule costs the summary it writes; a compaction forced at the
   limit costs a **full re-prefill of the entire conversation**. That is not hypothetical — the session
   above crossed 1 M mid-build and paid 650 k then 636 k fresh input tokens to repair itself, 38 % of all
   new input in the whole build, spent on conversation upkeep rather than on geometry.
3. **Digest inside the runner; never let a raw report into the transcript.** A result that lands in
   history is paid for again by every later step. The pattern that works: call the tool from inside the
   code runner, reduce the result to counts and named faults, and print five lines. Transport limits (field-notes.md §4)
   are the same problem seen from the other end.
4. **Render in batches; every attach re-reads the whole conversation.** A render after every pass stays
   required, but the *cost* of one is the entire prefix, not the picture. Take the views a pass needs in a
   single call, prefer several small aimed views to one wide one, take them while the context is still
   short, and never re-attach an image you have already shown. Downscale before attaching.
5. **Stay append-only within a phase.** Editing, pruning, re-ordering, or splicing new material into the
   middle of history invalidates the cached prefix and re-bills the whole context at full price. This is
   the mechanism behind the 30× figure above: it was not the images themselves, it was where they landed.
6. **The late defect is the expensive one.** A bug found in phase 4 is found, diagnosed and fixed at
   maximum context, which is precisely when every step costs the most. The orientation assertions in field-notes.md §1
   and §3 are therefore a cost control as much as a correctness one: front-loading invariants is far
   cheaper than debugging at 600 k.

**Auditing a session instead of guessing.** The harness writes a transcript to
`~/.dsh/sessions/<slug>/<session-id>/session.v3.jsonl.zstd`. It is **multi-frame** zstd: a single-shot
decompress returns only the first frame and looks like a 196-byte session, which is how this analysis
nearly ended before it started. Split the buffer on the frame magic `28 b5 2f fd`, decompress each slice,
concatenate, and parse the lines as JSON. Then sum the `cacheReadTokens` and `inputTokens` fields of
every `usage` object and bucket them by request index. The shape tells you which lever you own: rising
`cacheReadTokens` with flat `inputTokens` means you are paying for context length, while spiking
`inputTokens` means you are invalidating the cache — and if the spikes line up with the steps where an
image arrived, the attach is what invalidated it.

Count **one usage record per request**. That file held 270 of them for 157 requests, and adding up all
270 overstates a session by about 2×. It is a cheap mistake to make and it was made here: the first
version of this section reported 88.5 M and called 95 % of it cache reads before the duplicate records
were noticed. The deduplicated figure is 44.3 M and 97.5 %.

