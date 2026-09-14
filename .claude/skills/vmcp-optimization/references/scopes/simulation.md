# Simulation Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The Simulation group contains scopes for the **Server Authority** simulation system (opt-in, currently in Beta). Under Server Authority the server is the source of truth: the client simulates its own inputs slightly ahead of the server (client-side prediction) and rolls back and re-simulates when the server's authoritative state differs from the prediction. These scopes appear on the client when a game has the Server Authority beta feature enabled. (`AuroraService`/`Aurora*` is the internal name for this system, so the scope strings carry that prefix.)

---

## AuroraService::stepPhysics

**Performs one fixed-rate physics step within the Aurora simulation framework.**

Advances the Aurora physics world by one fixed-rate step: it fires the step signal and then runs the physics world step (stepPhysicsRuntime). Input application and script execution are sequenced by the outer `AuroraService::onWorldFixedRateTick`, not by this scope. Called at the fixed physics rate (typically 60 Hz).

**Performance notes:** Duration depends on scene complexity and the number of simulated bodies. If this scope is wide, the physics world step (nested inside) is the likely culprit.


---

## AuroraService::onWorldFixedRateTick

**Top-level entry point for a single Aurora fixed-rate tick — orchestrates input, scripts, and physics for one simulation frame.**

This is the outer wrapper that sequences the entire fixed-rate simulation step: collecting inputs, firing script signals, stepping physics, and updating predicted state.

**Performance notes:** If consistently wide, check the nested scopes (Update Inputs, fixedRateTickSignal) to identify which phase is expensive.


---

## Update Inputs

**Applies queued player inputs to the simulation state for the current tick.**

Processes the input buffer, applying all inputs that are scheduled for this simulation frame. This includes movement inputs, button presses, and other player actions.

**Performance notes:** Typically fast. Only expensive if many players are sending high-frequency inputs.


---

## fixedRateTickSignal

**Fires the fixed-rate tick signal to all Lua scripts connected to Aurora's fixed-step callback.**

Invokes game scripts that have registered for the fixed-rate simulation callback. This is the script execution phase within each fixed-rate tick.

**Performance notes:** Cost depends entirely on what game scripts do in their fixed-step handlers. Same optimization advice as RunService callbacks.

**What game creators can do:**
- Keep fixed-step script logic lightweight
- Avoid heavy operations (raycasts, spatial queries) every tick


---

## AuroraService::prunePredictedInstances

**Removes predicted instances that are no longer relevant to the current simulation state.**

Cleans up instances that were speculatively created during prediction but are no longer needed (either confirmed by server or invalidated by rollback).

**Performance notes:** Typically fast. Can spike during rollback scenarios with many predicted objects.


---

## AuroraService::getCurrentInputFrame

**Retrieves the current input frame data for the local player.**

Reads the latest input state for the current simulation frame on the client, for client-side prediction.

**Performance notes:** Negligible — simple data lookup.


---

## AuroraService::applyInput

**Applies the input frame matching a given world-step id (all of that frame's actions) to the simulation, on the client or server.**

Takes one input entry and applies its effects to the game state (e.g., character movement, action triggers).

**Performance notes:** Fast per-call, but called for each input in the frame's input list.


---

## AuroraService::applyInputFrame

**Applies an entire frame's worth of inputs at once.**

Batch-applies all inputs for a given simulation frame. This is the primary input application path.

**Performance notes:** Cost proportional to the number of inputs queued for the frame.


---

## AuroraService::rollback

**Rolls back the simulation to a previous state when the server's authoritative state disagrees with the client's prediction.**

Reverts the world state to a known-good server snapshot and prepares to resimulate forward. This involves undoing physics changes, script state, and instance modifications.

**Performance notes:** Rollbacks are expensive — they undo and redo simulation work. Frequent rollbacks indicate prediction/authority disagreements. If this scope appears often:
- Network latency may be high
- Client and server simulations may be diverging frequently
- Complex scenes with many interacting physics bodies increase rollback cost

**What game creators can do:**
- Reduce the number of physically-simulated network-owned parts
- Ensure deterministic behavior in simulation scripts
- Minimize interactions between client-predicted and server-owned objects


---

## AuroraService::resimulate

**Re-runs the simulation forward from the rollback point to the current time.**

After a rollback, this scope replays all simulation steps from the rollback point to "catch up" to the present. Each replayed step re-applies inputs and re-runs physics.

**Performance notes:** Cost = (number of frames to replay) × (cost of one simulation step). Longer rollbacks (higher latency) and more complex scenes make this more expensive.

**What game creators can do:**
- Same as rollback — reduce scene complexity for server-authoritative objects
- Lower network latency reduces the number of frames that need resimulation


---

## AuroraService::checkServerViewAndRollback

**Compares the client's predicted state against the server's authoritative state and triggers a rollback if they disagree.**

This is the prediction validation step. It checks whether the server's latest acknowledged state matches what the client predicted. If not, it initiates a rollback and resimulation.

**Performance notes:** The comparison itself is fast. The expensive part is if it triggers a rollback.


---

## fixedStepCallbacks

**Fires all callbacks registered for the fixed-step simulation rate.**

Invokes engine-internal callbacks that run at the fixed simulation rate. This includes custom fixed-step logic and module callbacks.

**Performance notes:** Typically fast unless modules register expensive fixed-step work.


---

## RunService::getCurrentInputFrame

**Reads the current input frame from the ContextActionService for server-authority input routing.**

Bridge between RunService and the input system — retrieves the local input state for the current frame in the context of Aurora simulation.

**Performance notes:** Negligible.


---

## ContextActionService::applyInputFrame

**Applies an Aurora input frame through the ContextActionService action routing system.**

Routes an input frame through the bound action system, triggering any ContextActionService actions that match the inputs.

**Performance notes:** Cost depends on the number of bound actions and whether they trigger Lua callbacks.


---

## ContextActionService::applyInput

**Applies a single input through ContextActionService action routing.**

Processes one input event through the action binding system.

**Performance notes:** Fast per-call.


---

## UpdatePredictedHashes

**Computes and stores hashes of predicted simulation state for later comparison against server state.**

Generates hash values of the current predicted world state. These hashes are later compared against server-provided hashes to detect prediction mismatches that require rollback.

**Performance notes:** Cost scales with the number of network-replicated physics objects.


<br>
<br>

---
