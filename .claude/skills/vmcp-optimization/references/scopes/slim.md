# Slim Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The Slim group contains scopes for the SLIM (Scalable Lightweight Interactive Models) LOD system: a multi-stage geometry processing LOD pipeline for avatar and mesh geometry rendering at scale.

---

## SlimController (Legacy)

### SlimController::update

**Main update tick for the SLIM controller — orchestrates all SLIM work for the frame to update all models.**

Coordinates LOD transitions, streaming decisions, and binding updates for all SLIM models.

**Performance notes:** Cost proportional to the number of SLIM models in the scene.


---

### SlimController::updateBindings

**Updates render bindings for SLIM models — connects SLIM data to the rendering system.**


---

### SlimController::updateLoadRequests

**Processes load requests for SLIM model data (mesh, animation, texture streaming).**


---

### SlimController::makeStreamingDecisions

**Determines which SLIM model LOD levels to stream in/out based on distance and budget.**

Applies the streaming policy: closer models get higher LOD, distant ones are simplified or evicted.

**Performance notes:** O(SLIM models). Budget-aware — may evict data to stay within memory budget.


---

### SlimController::garbageCollect

**Garbage-collects SLIM data that is no longer needed (model left view, LOD downgraded).**


---

### SlimController::removeBindings

**Removes render bindings for SLIM models that are being unloaded.**


---

## SlimController2 (Current)

### SlimController2::update

**Main update for the current SLIM controller implementation.**


---

### SlimController2::processCommands

**Processes queued commands for SLIM models (load, unload, transition LOD).**


---

### SlimController2::updateLodStates

**Updates LOD states for all SLIM models — determines current LOD level based on distance/budget.**


---

### SlimController2::updatePrepareRenderBindings

**Prepares render bindings for the rendering system — sets up GPU data for SLIM models.**


---

## Load Balancer

### SlimLoadBalancerImpl::prepare

**Prepares load balancing data — refreshes configuration and processes pending load responses for the frame.**


---

### SlimLoadBalancerImpl::computeScores

**Computes priority scores for each SLIM model — determines who gets resources.**

Scores are based on recent visibility (time since last on-screen), on-screen size, and current LOD state.


---

### SlimLoadBalancerImpl::computeLodDownBias

**Computes a bias toward lower LODs when memory/performance pressure is high.**


---

### SlimLoadBalancerImpl::makeOptimizationScores / sortOptimizationScores

**Generates and sorts optimization scores for load-shedding decisions.**


---

### SlimLoadBalancerImpl::balanceLoadsAndEvictions

**Balances loading new model data against evicting low-priority data to stay within budget.**

The core resource management decision: what to load and what to evict.


---

### SlimLoadBalancerImpl::applyOptimization

**Applies load balancing decisions — triggers actual load/evict operations.**


---

### SlimLoadBalancerImpl::processLoadResponses

**Processes completed load operations — finalizes model data that finished loading.**


---

## Loader

### SlimLoaderImpl::update

**Updates the SLIM loader — processes the load queue and manages worker threads.**


---

### SlimLoaderImpl::workerStep

**One worker thread step — processes the SLIM load pipeline: content-load, ACR, manifest, chunk, and load requests.**


---

### SlimLoaderImpl::loadSynchronousChunks

**Loads SLIM data chunks that must be synchronous (blocking) — used for immediate-need models.**


---

## Renderer

### SlimRenderer::updatePrepare

**Prepares SLIM rendering data for the current frame — updates skinned bone data from replicated SLIM animation streams.**


---

### SlimRenderer::updatePrepareAnimations

**Processes the SLIM animation-stream deletion queue — tears down animation streams for models that no longer need them.**

**Performance notes:** Cost proportional to the number of SLIM animation streams being destroyed this frame.


---

## Replication

### SlimReplicationService::onHeartbeatClient / onHeartbeatServer

**Per-frame replication update for SLIM data — sends/receives SLIM state changes over the network.**

Client side receives SLIM data updates; server side sends them to relevant clients.


<br>
<br>

---
