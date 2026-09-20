# Context diet — plan

What actually eats tokens, tool calls and wall-clock in a VMCP session, measured against this setup on 2026-09-20. Do these before anything in `jev-plan.md`; they're bigger.

Ranked by size of the win.

## 1. Shrink the giant skills

`~/.claude/skills` word counts: vmcp-optimization 20,865 (~28k tokens), vmcp-build 11,975 (~16k), roblox-ui 6,313, impeccable 1,425. One trigger lands the whole body in context and it's re-sent every turn for the rest of the session.

Cut each SKILL.md to the 1–2k words needed on every task of that kind: tool order, gotchas as wrong/right code blocks, thresholds. Everything else moves to `references/*.md` that the skill tells the model to read at the step that needs it (Equiv.Check detail, sweep mode, gprx format, prim.* labels; for build: material tables, render views, problem-list semantics). Use skill-creator for the split and run its evals so triggering doesn't regress. Target: 10x smaller body.

## 2. Drop ghost place registrations

Two sessions of the same place are exposed (Place1_1ee0, Place1_8935). `server/src/manifest.ts` caches every place id ever seen; `bridge/registry.ts` (~L135) lists disconnected ones too, so each Studio close/reopen leaves a ghost and the tool list doubles: 44 tool names in every prompt instead of 22, and the model has to pick one.

Fix: keep only the newest id per place name, or expire entries not seen in N days. One-hour code change; halves the tool surface.

## 3. Prune the skill list

39 skill dirs → ~5k tokens of descriptions in every prompt before any work starts. Roughly half are roblox-* skills unused in VMCP work (growth-design, economy, monetization, localization, cloud, analytics, publish-checklist, server-data, npc-ai, physics, audio…). Move them to a parked folder and symlink back when needed. Also re-scope `grill-me` — "trigger on ANY implementation" adds a turn to most tasks.

## 4. Apply by file path, not by source

`apply_build` already takes `file` (ApplyBuild.luau L66) but the skill says "keep the full source and edit it between passes", which the model reads as re-sending a 500-line build each pass. Output tokens are the slow, expensive ones. Skill should say: write the build to a file once, Edit it, apply by path. Same for apply_fix / try_scripts candidates. Per-pass output drops from thousands of tokens to the diff.

## 5. Lint in the relay before Studio runs it

A fix that fails on a type error or bad require costs a full loop: apply → playtest → error → get_logs → fix → apply again. Run `luau-lsp analyze` (+ selene) on the source in the relay first and return diagnostics inline. ~200ms, deterministic. Applies to apply_build, apply_fix, try_scripts, run_luau.

## 6. Downscale inline images

`postprocess.ts` inlines any PNG under 1.5MB (bytes, not pixels). Image tokens ≈ pixels/750, so a 1920×1080 screenshot is ~2.8k tokens and a 4-view render tile more. Inline at 1024 wide by default, file on disk stays full-res, `full = true` to opt out. Halves image cost on screenshot_ui, apply_build, mount_story, render_build, render_anim.

## 7. Fewer permission prompts

Each one is wall-clock waiting. Run `/fewer-permission-prompts` once to allowlist read-only vmcp / open-pencil calls.

## 8. Workers for the whole-game sweep

Sweep mode runs top-down in one context, so script 12 carries scripts 1–11's captures. One subagent per script with only that script's slice of the skill, returning one ledger line. CLAUDE.md's delegation rules already cover this; the skill just doesn't use them.

## 9. Stable prompt prefix for caching

Tool lists that reorder on reconnect, or skills that reorder, invalidate the prompt cache — full input price next turn. Sort exposed tools by name in the registry; keep skill order deterministic.

## Sizing

1 + 3 ≈ 30–40k tokens off a typical optimization-session turn. 2 and 6 are one-hour code changes. 4 and 5 cut turns rather than tokens, which is where the time goes.

## How to measure

Same as jev-plan: tokens per turn and tool calls per task on 3–5 real tasks, before/after. `/cost` at session end for the headline number.
