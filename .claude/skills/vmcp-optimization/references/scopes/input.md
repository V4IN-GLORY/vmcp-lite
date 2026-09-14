# Input Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The Input group contains scopes related to processing player input — keyboard, mouse, touch, and gamepad events. These scopes fire during the input processing phase of each frame, before rendering.

---

## ProcessInput

**Top-level scope for processing all pending input events from the UserInputService on the render step.**

This is the main entry point for input processing each frame. It dequeues all pending input events (from the platform input queue) and routes them through the input pipeline: UserInputService → ContextActionService → GUI hit testing.

**Nesting:** Runs during the render preparation phase. Contains ProcessUIActions and ProcessActions.

**Performance notes:** Usually fast. Can be slow if:
- Many input events are queued (e.g., rapid mouse movement with high polling rate)
- Lua callbacks connected to InputBegan/InputChanged/InputEnded are expensive
- GUI hit testing is expensive due to deeply nested UI hierarchies

**What game creators can do:**
- Keep InputBegan/InputChanged/InputEnded callbacks lightweight
- Do minimal work in the callback itself — defer heavier computations off the input event (e.g. with `task.defer`/`task.spawn`, or spread the work across later frames) rather than running them inline
- Avoid deep UI hierarchies that make hit testing expensive
- Use ContextActionService bindings instead of raw input events when possible


---

## ProcessUIActions

**Routes input events through ContextActionService UI-priority bindings.**

Processes state changes for on-screen touch/GUI buttons created by ContextActionService (via `SetTitle`/`SetImage`/`GetButton`-style CAS action buttons), updating each button's action state and firing its connected bindings. This is CAS button input, distinct from keyboard/gamepad action routing.

**Nesting:** Inside ProcessInput.

**Performance notes:** Cost proportional to the number of bound UI actions. Fast in typical games.

**What game creators can do:**
- Unbind actions when they're not needed (e.g., when a menu is closed)
- Avoid binding many actions at the same priority level


---

## ProcessActions

**Routes input events through ContextActionService game-world bindings.**

Processes input events against non-UI actions. This is where movement, combat, and other gameplay bindings fire.

**Nesting:** Inside ProcessInput, after ProcessUIActions.

**Performance notes:** Similar to ProcessUIActions. Expensive if many actions are bound or if their Lua callbacks do heavy work.


---

## ProcessActionsInternal

**Internal dispatch of action processing — iterates through bound actions and invokes matching handlers.**

The inner loop of action processing. Matches input events against bound action keycodes and invokes the corresponding Lua callback functions.

**Nesting:** Inside ProcessActions.

**Performance notes:** Per-event cost. Multiple bound actions with overlapping keys increase processing time.


---

## UIS:InputBeganChangedEnd

**Fires UserInputService.InputBegan, InputChanged, or InputEnded signals to Lua.**

This scope wraps the Lua signal dispatch for raw input events on UserInputService.

**Performance notes:** Cost depends on the number of connections and their callback complexity.


---

## UserInputService::processGestures

**Processes pending touch gesture events (pinch, pan, rotate, tap, etc.).**

Dequeues gesture events from the platform gesture recognizer and fires corresponding Lua signals (TouchPinch, TouchPan, etc.).

**Performance notes:** Only relevant on touch devices. Fast unless many gesture connections exist with expensive callbacks.


---

## NullTool::onMouseHover

**Performs hover detection — raycasts into the 3D scene under the mouse cursor to detect ClickDetectors and hoverable parts.**

Runs each frame while no tool is equipped and the mouse moves. Performs a raycast from the camera through the mouse position to find parts with ClickDetectors or hover state.

**Performance notes:** One raycast per frame when hovering. Normally fast, but can be expensive in dense scenes with many parts.

**What game creators can do:**
- Parts with ClickDetectors add to raycast cost; remove unused ClickDetectors
- Complex collision geometry (MeshParts with high-fidelity collision) increases raycast cost


---

## NullTool::onMouseMove

**Handles mouse-move while a ClickDetector already has input capture — updates the activated cursor and forwards the moved ray to that detector.**

Runs only when a ClickDetector currently holds capture (mouse-down drag). It refreshes the activated cursor icon and calls the detector's moved-ray update, releasing capture if the ray no longer targets it. This is drag tracking on a captured detector, not passive hover/highlight during free mouse movement.

**Performance notes:** Minimal cost per frame.


---

## DEPRECATED_ContextActionService::tryProcess

**Alternate ContextActionService input processing path.**

Still fires in some configurations for backward compatibility.

**Performance notes:** Typically negligible.


---

## GuiLayerCollector::processGesture

**Routes a gesture event through the GUI input system to find which UI element should handle it.**

Hit-tests gesture events against the GUI hierarchy to determine which GuiObject should receive the gesture.

**Performance notes:** Cost depends on the number and depth of active ScreenGuis and their elements.


---

## GuiLayerCollector::processDescendants

**Walks the GUI hierarchy to find input targets for mouse/touch events.**

Traverses the Z-ordered list of GUI elements to determine which element the input event should target. Uses the UI quad tree for spatial acceleration.

**Performance notes:** Expensive with very deep or numerous GUI hierarchies. The quad tree helps, but thousands of overlapping elements still cost.

**What game creators can do:**
- Reduce the total number of visible GuiObjects
- Set `Active = false` on elements that don't need input
- Avoid deeply nested GUI structures


---

## HapticMixer.run

**Mixes haptic motor intensities from multiple sources and applies them to the gamepad.**

Runs per-frame to combine haptic feedback requests and output the final motor intensities to connected haptic devices (gamepad rumble).

**Performance notes:** Negligible. Only runs when haptic devices are present.


---

## HapticService.getNextHapticIntensities

**Collects pending haptic intensity requests from game scripts.**

Gathers all haptic motor intensity values that scripts have set since the last frame.

**Performance notes:** Negligible.


---

## updateControllers

**Updates SDL gamepad controller state — polls connected controllers for button/axis changes.**

Queries the platform input layer for gamepad state changes and generates input events for any buttons pressed/released or axes moved.

**Performance notes:** Negligible. Cost is O(connected controllers).


---

## PollAllInput / PollRawInput / PollLegacyInput

**Polls the platform input system for new events (Windows client) — raw input, legacy input, or all input sources at once.**

**Performance notes:** Negligible in normal use. Fires during the input polling step on the Windows desktop client.


<br>
<br>

---
