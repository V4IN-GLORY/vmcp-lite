# Heartbeat Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The Heartbeat group contains scopes for the per-frame heartbeat step — it fires `RunService.Heartbeat` callbacks once per frame on the main thread. Heartbeat is one of several per-frame steps run by the task scheduler; physics, rendering, and scripts are separate steps documented in their own groups.

---

## heartbeatInternal

**Fires the internal heartbeat signal to all engine systems that subscribe to the per-frame heartbeat.**

This is the engine-internal heartbeat that notifies services like ProximityPromptService, PointsService, and other engine subsystems that a new frame has begun. It passes wall time, game time, and delta values to all connected listeners.

**Nesting:** Top-level scope on the main thread. All service `onHeartbeat` callbacks run inside this scope.

**Performance notes:** This is the aggregate of every engine service subscribed to the per-frame heartbeat, so a wide scope usually means one nested callback dominates — drill into the per-service scopes (e.g. `proximityPromptOnHeartbeat`) to find it. Some of this cost scales with your experience's content: for example, the number of active ProximityPrompts drives `proximityPromptOnHeartbeat` (see that scope for how to reduce it).

**What game creators can do:** Expand it and reduce the content driving the widest child (for example, fewer active `ProximityPrompt`s reduces `proximityPromptOnHeartbeat`). Note this is engine-service work — your own per-frame script code shows up under `RunService.Heartbeat`, not here.


---

## RunService.Heartbeat

**Fires the `RunService.Heartbeat` Lua event (the script-facing heartbeat callback).**

This is the Lua-facing `RunService.Heartbeat` event. Game scripts that call `RunService.Heartbeat:Connect(function)` execute here. This runs after the internal heartbeat signal.

**Nesting:** Runs immediately after `heartbeatInternal` in the same frame step.

**Performance notes:** If this scope is wide, game scripts connected to `RunService.Heartbeat` are doing expensive work. Common causes:
- Complex per-frame Lua logic (NPC AI, custom physics, UI updates)
- Too many connections to the Heartbeat event
- Heavy math or table operations in connected functions

**What game creators can do:**
- Move expensive work to `RunService.Stepped` or `RunService.PreSimulation` if it only needs to run at physics rate
- Throttle per-frame logic (run expensive operations every Nth frame)
- Use task.defer/task.spawn to spread work across frames
- Reduce the number of Heartbeat connections by consolidating logic


---

## proximityPromptOnHeartbeat

**Updates ProximityPromptService state — determines which proximity prompts are visible and calculates their display priority.**

Each frame, this scope iterates over all active ProximityPrompt instances, checks player distance, performs line-of-sight raycasts, and determines which prompts should be displayed. It handles the "best fit" selection when multiple prompts compete for screen space.

**Nesting:** Fires inside `heartbeatInternal` as a heartbeat subscriber.

**Performance notes:** Cost scales with the number of active ProximityPrompt instances in the workspace. Each prompt requires distance checks, and visible prompts require raycasts for line-of-sight verification.

**What game creators can do:**
- Reduce the number of ProximityPrompt instances in the workspace
- Set `RequiresLineOfSight = false` on prompts that don't need it (eliminates raycasts)
- Decrease `MaxActivationDistance` thresholds to reduce the pool of candidates
- Disable prompts that are far from any player


---

## pointsServiceOnHeartbeat

**Processes batched point award requests in PointsService.**

This is a legacy service scope. It processes any pending batched point awards that were queued since the last frame. In modern games this is typically a no-op.

**Nesting:** Fires inside `heartbeatInternal` as a heartbeat subscriber.

**Performance notes:** Negligible in most games. Only costs time if PointsService is actively awarding points.


<br>
<br>

---
