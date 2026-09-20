# Jev (TypeSafe) in VMCP — plan

Jev is a classifier, not a code model. One request = a text `state` + any mix of `choice` (pick one of ≤255 options), `score` (rubric), `noul` (true/false, 0–1), all answered in parallel in ~70–500ms. Output can't leave the schema. $0.042/MTok in, output free.

Limits (jev-1.13.0): text only; 32k tokens of state, 64k with questions; 1,200 req/min, 250k tok/s. Early access — waitlist at typesafe.ai. JS SDK: `npm install @typesafe-ai/sdk` (Node 20+). Docs index: https://docs.typesafe.ai/llms.txt. Claude Code plugin: `claude plugin marketplace add typesafe-ai/skills && claude plugin install typesafe@typesafe-ai`.

Shape of every win: Jev answers first, Opus only sees what Jev couldn't settle above a confidence threshold (their "SDE cascade"). Never let it skip a read, only rank/filter/route.

Before building anything: get access, and decide we're fine sending script source to a third party per call.

## Where it lives

Relay-side, in `server/src/postprocess.ts` — the one place a result is acted on instead of relayed. One `filter` directive applied to the text content of a tool result, with an optional `intent` arg on the tools that take one. Not plugin-side: Studio can't call out and we'd ship the key into the place. Hooks (guardrail, skill routing) go in Claude Code settings, not VMCP.

Chunk state by top-level group / script when a result is over 32k tokens; chunk option lists at 255.

## Ordered by payoff per hour

1. **Semantic path resolution.** Nearly every tool takes a dotted `root`. Tag each tree line `L052|`, `choice` ranks lines against the user's phrase, paired `noul("a match exists")` so an empty result isn't a confident wrong path (semantic_find cookbook). Applies to get_tree, get_build, screenshot_ui, inspect_style, mount_story, profile_scripts. Saves 1–2 calls per task.
2. **review_remotes ranking.** Per handler, one `noul` per hole type already named in the tool description (type check, ownership, range, rate limit, loadstring, client-steered DataStore). Return full source for flagged handlers, one line "clean 0.94" for the rest. Rank only, never skip.
3. **get_build `intent` filter.** `choice` over top-level group names, return only matching groups' source. Biggest text a build task reads.
4. **Write guardrail hook.** Before apply_build / apply_fix / run_luau: `noul` the source for "touches game.Lighting", "uses an rbxassetid not in assets.json", "edits outside the requested root". Turns the memory rules into a 100ms check. Warn-prefix or block.
5. **Skill/tool routing hook (UserPromptSubmit).** `choice` over the vmcp skills + place ids so one skill body loads per turn (skill_suggestion cookbook). Same trick over MEMORY.md lines for recall.
6. **lint_hotpaths false-positive filter.** Per finding + ~15 lines of context: `noul("runs per frame or per event at scale")` + severity `score`. Drop/demote before return; fewer wasted profile_scripts follow-ups. Same for the whole-game sweep shortlist.
7. **search_scripts `intent` re-rank.** `score` matches against intent, return top 10 of 40–200 (rerank cookbook). Kills the re-search-with-tweaked-pattern turn.
8. **get_logs collapse.** `choice` per line {same failure as asked-about error, unrelated, noise}, fold repeats. ~5x smaller.
9. **inspect_style one-liner.** `choice` per property over {direct value wins, selector error, lost on priority, class-default didn't replicate, sheet not linked}; >0.9 returns one line, else full dump.
10. **apply_build problem triage.** Per overlap/gap/floater: two part names + the source lines that placed them, `choice{intentional, bug, unclear}`. Bugs first, intentional folded to a count. Least trusted — part names don't always carry intent; measure before keeping.
11. **run_timeline failure triage.** `choice` over assertion + logs into a cause set (timing, nil path, remote never fired, client never joined) to pick which snippet to open. Moderate.
12. **Story/component routing.** `choice` over storybook component names from the request so mount_story hits first time. Small.

## Optimization loop, deeper

Nothing here replaces a measurement. It shortens the path to the next measurement or stops a wasted one.

13. **Symptom → script routing.** User says "stutters when the inventory opens". `choice` over the count_lines script list (≤255) plus each script's hot column and first ~20 lines; profile the top 3 instead of sweeping. Pairs with 6 to order the sweep queue before any playtest.
14. **Fix-shape pre-diagnosis.** Per hot function source, `choice` over a fixed catalogue: cache instance lookup, hoist invariant, GetDescendants → tag/QueryDescendants, poll → event, reuse buffer, batch Instance.new, linear scan → set, string build in loop, needs rework. Feeds the propose-first gate (catalogue hit → straight to fix, "needs rework" → propose with pros/cons) and gives the ledger a category to total by. Opus still writes the fix.
15. **Equiv.Check input suggestion.** Before spending a Hammer/Equiv timeline, `noul` per edge-case class (empty table, nil player, first frame, mid-respawn, N=0, N=large) "this change could behave differently here". Pick the inputs Equiv.Check covers from the ones above threshold instead of guessing.
16. **apply_fix diff guardrail.** `noul` on the diff: changes a return shape, touches a remote, reorders side effects, edits outside the hot function, adds a yield. Any high → hand to try_scripts with a warning line instead of applying. Cheap, runs every time.
17. **Ledger dedupe.** Before proposing, `noul("same fix category already tried/rejected on this script")` over the ledger entry. Stops the second pass re-proposing what the first rejected.
18. **Multi-client divergence.** Under multi-client load, `choice` over client ids given each one's log tail: which client diverged. Beats reading N log tails.

## Debugging loop, deeper

19. **Error → cause → next tool.** Luau error text (`attempt to index nil with 'Humanoid'`) → `choice` over cause classes: character-load race, wrong context (client/server), path typo, destroyed instance, replication lag, yielded require. Each cause maps to one next call (run_timeline with ctx:Await, get_tree, search_scripts drift…). A router, so the model skips the "what kind of bug is this" turn.
20. **Live state triage.** `vmcp.Game.Require` dumps are big tables. Given the symptom, `score` each top-level field "inconsistent with the symptom"; return the top few with values, the rest as keys only (pre-parsed value extraction cookbook).
21. **Remote traffic classification.** `vmcp.Remotes` watch: per call `choice{expected, arg shape drifted, spam/rate}`, fold the expected ones to counts. `vmcp.Exploit.AbuseAll` results: per remote `choice{rejected properly, accepted bad args, errored}` so the model reads only the accepted/errored rows.
22. **Stack-trace origin.** For a trace through 5 scripts, `choice` over the frames: which is the origin vs a pass-through. Part of the get_logs collapse (8) but worth its own question.
23. **Flake detection.** Run the failing timeline twice, `noul("same failure")` over both outputs (consistency cookbook). Flaky → don't chase it as a code bug.
24. **Drift relevance.** search_scripts drift list → `noul` per drifted script "could explain the symptom". Sync only those.

Still not: reading numbers out of a capture, deciding a fix is worth applying (win floor is measured), choosing the fix code.

## Not worth it

Anything measured (profile_scripts, Profile.Compare, Equiv.Check, ledger totals). Anything visual (screenshot_ui pixels, render_build, render_anim). Geometry checks VMCP already does exactly. Writing Luau. Material picking — the model already knows the enum.

## How to measure

Per item: tool calls per task and result tokens, before/after, on the same 3–5 real tasks. Keep an item only if it moves one of those.
