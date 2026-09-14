# UI Group

<!-- from github.com/Roblox/libmp/docs/ALL-SCOPES.md -->
The UI group contains scopes for GUI layout, styling, text rendering, tweening, input hit-testing, localization, and UI data structure maintenance. UI work runs primarily on the main thread during the Prepare phase of rendering.

---

## Layout

### Layout

**Runs the UI layout system — computes positions and sizes for all dirty GuiObjects.**

The main layout pass that processes the UI tree. Computes AbsolutePosition and AbsoluteSize for every GuiObject with dirty layout.

**Performance notes:** The most expensive UI scope in complex games. Cost depends on:
- Number of dirty layout nodes (GuiObjects whose properties changed)
- Depth of the UI hierarchy
- Use of UIListLayout, UIGridLayout, UIPageLayout (add layout computation)
- AutomaticSize elements (require multiple layout passes)

**What game creators can do:**
- Minimize property changes that trigger re-layout (Size, Position, Visible)
- Use `LayoutOrder` instead of reparenting to reorder elements
- Avoid deeply nested UI structures
- Use `AutomaticSize = None` when the size is known
- Batch UI updates rather than changing many properties across multiple frames
- Reduce the amount of UI elements being resized or repositioned (via UILayout, TweenService, etc.)
- Consider fixed sizes for BillboardGuis


---

### Post-Layout Event Dispatch

**Dispatches events after layout completes — fires `AbsoluteSize`/`AbsolutePosition` changed signals.**

After layout recomputes positions, this scope fires property-changed signals for any objects whose absolute geometry changed.

**Performance notes:** Cost proportional to the number of elements whose position/size changed. Lua callbacks connected to these signals execute here.


---

### Layout Viewport

**Computes layout for viewport-specific UI elements.**


---

## Tweening

### TweenService

**Steps all active tweens forward by the frame's delta time.**

Advances TweenService:Create() tweens, evaluating their easing functions and firing their completion/cancellation callbacks. Also steps legacy objects tweened via TweenSize/TweenPosition.

**Performance notes:** O(active tweens). Usually fast. Hundreds of simultaneous tweens can add up.

**What game creators can do:**
- Cancel tweens that are no longer visible
- Use fewer simultaneous tweens
- Prefer TweenService over manual lerping in Heartbeat
- Ensure tween completion callbacks do little work


---

### updateGenericTweens

**Updates non-property tweens (NumberSequence animations, etc.).**


---

## Styling (CSS-like system)

### StyleEngine::update / StyleEngine::updateV2 / StyleEngine::updateV3

**Updates the UI style engine — resolves CSS-like style rules for GuiObjects.**

Processes style sheets and resolves property values for elements that match style selectors.

**Performance notes:** Cost depends on the number of styled elements and rule complexity. Games using the style system extensively will see time here.


---

### StyleEngine::addRoot

**Adds a new root element to the style engine's managed tree.**


---

### StyleEngine::update() - sync instances

**Synchronizes styled instance state with the style engine's internal representation.**


---

### StyleEngine::updateSubtrees / StyleEngine::resolveProperties / StyleEngine::applyProperties

**Sub-phases of style resolution: tree traversal, property computation, and property application.**


---

### applying property overrides

**Applies the resolved style property values to each matched instance (the property-application step of the style update).**


---

### StyleAnimator::update / ProcessArchetypeChanges / ComputeAnimatedProperties

**Updates style animations — processes archetype (visual state) transitions and computes interpolated values.**


---

### StyleTree::updateSelectors

**Updates CSS-like selector matching when the instance tree changes.**


---

### StyleCache::update

**Updates the style cache — invalidates and recomputes cached style resolutions.**


---

## Text & Fonts

### load font family metadata

**Loads font family metadata — parses font files to extract available weights, styles, and metrics.**

One-time cost per font family. Cached after first load.


---

### lookup font / request font face load

**Looks up a font face in the font system and initiates loading if not already cached.**


---

### TextRender::render

**Renders text glyphs for a text element — submits glyph geometry to the GPU.**

**Performance notes:** Cost per text element. Many TextLabels with frequently-changing text are expensive.


---

### update GlyphRenderer list

**Updates the list of active glyph renderers for font atlas management.**


---

## Hit Testing & Input

### getBestFitProximityPrompts

**Finds the best proximity prompts to display based on distance and screen position.**

Evaluates all active ProximityPrompts to determine which should be shown on screen.

**Performance notes:** Called from the heartbeat. See Heartbeat group for details.


---

### checkIfLineOfSightClear

**Raycasts to check if a ProximityPrompt has clear line of sight to the player.**

**Performance notes:** One raycast per visible prompt.


---

### doRebuildRenderAndInputLists

**Rebuilds the sorted lists of UI elements for rendering and input hit-testing.**

Called when the UI hierarchy changes (elements added, removed, or re-parented).

**Performance notes:** Sort of visible elements. Expensive with thousands of UI elements.

**What game creators can do:**
- Reduce the total number of on-screen GUI objects.
- Avoid frequently changing `ZIndex` or re-parenting GUI objects — each change rebuilds these lists.
- Prefer `ScreenGui` over many `BillboardGui`s where possible (billboard sorting is camera-dependent and costs more).


---

### reSortInputList

**Re-sorts the UI input list after Z-order changes.**

**Performance notes:** Also re-runs as the camera moves when camera-dependent GUIs (BillboardGuis) are present; cost scales with the number of on-screen GUI objects.

**What game creators can do:**
- Reduce `ZIndex` churn and the number of on-screen GUI objects.
- Reduce `BillboardGui` count — these force a re-sort whenever the camera moves.


---

### GuiService::getSelectionGroupIntersection

**Computes the intersection of gamepad selection groups for navigation.**


---

### Move Gamepad Selection

**Moves the gamepad UI selection cursor in a direction (up/down/left/right).**

Uses spatial queries to find the next selectable element.


---

### Rebuild Quadtree / Update Quadtree / Rebuild Z-order list

**Maintains the spatial quadtree used for fast UI hit-testing and the Z-order rendering list.**

**Performance notes:** Fires when UI elements move or are added/removed. Frequent changes trigger frequent rebuilds.

**Rebuild Z-order list** sorts the Z-order of UI elements (an internal term, distinct from `GuiObject.ZIndex`) to prevent tearing.

**What game creators can do:**
- Reduce the amount of UI elements with the same ZIndex


---

### UIQuadTree::processUpdateList

**Processes pending spatial updates in the UI quadtree.**


---

## RelativeGui (3D-positioned UI)

### RelativeGui input / RelativeGui gesture / RelativeGui build vector

**Processes input, gestures, and child-list rebuilds for a RelativeGui — a GuiObject that positions its children in relative 2D screen space.**

**Performance notes:** Cost per visible 3D-positioned GUI element.


---

## Localization

### LocalizationService::attemptTranslation / attemptLocalization / attemptDynamicTranslation

**Attempts to translate UI text using localization tables.**

Looks up text strings in the localization system and replaces them with translated versions.

**Performance notes:** Usually fast (hash table lookup). Can be expensive if triggered frequently on many elements.


---

### LocalizationService::invalidateAutoTranslations

**Invalidates cached auto-translations when locale changes or translation tables update.**


---

## Text Scraper

### TextScraper::ScraperJob::step / TextScraper::ClientScraperJob::stepDataModelJob / TextScraper::ServerScraperJob::stepDataModelJob

**Scrapes text from the game for automatic localization table generation.**

Background job that drains the queues of already-collected untranslated strings and parameter text for localization. The UI hierarchy is walked upstream when strings are enqueued, not in this step.

**Performance notes:** Background job, doesn't block rendering. But can compete for CPU time.


---

## Path2D

### Path2D_Rebuild

**Rebuilds a Path2D's spline and mesh geometry when it is marked dirty, during the UI render pass.**

Recomputes the path tessellation for rendering.

**Performance notes:** Cost depends on path complexity (number of control points, tessellation quality).


---

## Rendering (within UI group)

### fillGuiVertices

**Fills GPU vertex buffers with UI element geometry (quads, borders, gradients).**

Generates the vertex data that the GPU renders for all visible UI elements.

**Performance notes:** O(visible UI elements). Complex elements (rounded corners, gradients) generate more vertices.

**Labels:** `gui count` indicates the number of LayerCollectors visible.

**What game creators can do:**
- If cost is high, reduce the amount, density, or screen space of UI elements
- If there are too many `Process GuiEffect` labels, reduce use of `UIGradient` and `UICorner` on text labels


---

### Process GuiEffect

**Processes GuiEffect instances (UIBlur, etc.) during UI rendering.**


---

## UIDragDetector

### UIDragDetector::dragStart / UIDragDetector::dragContinue / UIDragDetector::dragEnd

**UIDragDetector lifecycle — handles the start, continuation, and end of a UI drag interaction.**


---

### UIDragDetector::restartDrag

**Restarts a drag operation (e.g., after a constraint change during drag).**


---

### UIDragDetector::applyCallbacksInDragContinue

**Invokes Lua callbacks during drag continuation.**


---

### UIDragDetector::applyDragBounds / boundDragByBoundingRect / boundRotate / boundTranslateLine / boundTranslatePlane

**Applies drag bounds constraints — restricts drag movement to defined regions, lines, planes, or rotations.**


---

### GuiObject::processWithDragDetector

**Processes input on a GuiObject that has a UIDragDetector attached.**


---

## Dynamic Localization

### LocalizationService::attemptDynamicTranslation

**Attempts dynamic runtime translation of text content.**


---

### LocalizationService::attemptLocalization

**Attempts to localize a text string using the active localization table.**


---

## Text Scraping

### TextScraper::ClientScraperJob::stepDataModelJob / TextScraper::ServerScraperJob::stepDataModelJob

**Background text scraping jobs — drain the queues of already-collected untranslated strings and upload them to the auto-localization service. The UI hierarchy is walked upstream when strings are enqueued.**


<br>
<br>

---
