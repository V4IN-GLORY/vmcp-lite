---
name: vmcp-ui
description: Building Roblox UI components with VMCP as UI Labs stories — plain Instances for structure, Vide only for state and motion, one *.story per component that both the UI Labs plugin (for the human) and the mount_story tool (for the agent) mount, then screenshot_ui to look and fix. Use when building or changing a menu, HUD, panel, component, story or storybook.
---

# UI components and stories

A component is a folder: `init.luau` returns `function(props) -> Instance`, and `<Name>.story.luau`
beside it is the contract that both UI Labs and `mount_story` run. The loop is edit → `mount_story`
→ look → edit; nothing is judged from reading AbsolutePosition numbers.

```
src/client/UI/
  UI.storybook.luau          { name = "VMCP UI", storyRoots = { script.Parent } }
  Assets.luau                rbxassetids, the only place ids live (see vmcp-icons)
  Make.luau                  Label / Box / Image builders; pixels on the design stage, tags for rules
  design/icons.json          the icon set spec (+ .svg plates)
  Stage.luau                 Stage.new(parent, size?) fits a fixed-pixel stage to its parent; Stage.Dummy() mannequin
  HexStat/init.luau          component
  HexStat/HexStat.story.luau story
src/design/init.luau         Design.Build() -> the StyleSheet; tokens + themes, Style Editor layout
src/client/CyberpunkHUD.client.luau  controller: Stage + Design.Link, mounts the screen
```

## The loop

1. `mount_story story=StarterPlayer.StarterPlayerScripts.Client.UI.HexStat controls={"value":14}`
   mounts the story into `StarterGui.VMCPStory` (default target 1280×720, `size` to change), links
   `ReplicatedStorage.Design.StyleSheet`, waits a frame for styles, and returns a `screenshot_ui`
   PNG. Asset icons draw for real when `upload_image` published them. Torn down after the shot
   unless `keep=true`, which leaves it for `inspect_style` / `run_luau` probes.
2. Edit the source. Rojo syncs it. `mount_story` again — it **clones the story's folder** for the
   mount, so the edit is what runs (Studio's require cache is per instance and would otherwise
   serve the first version forever). Modules *outside* that folder (`Make`, `Assets`, `Design`)
   stay cached until the plugin is re-added.
3. Alignment is numbers, not eyes: `run_luau` printing `AbsolutePosition.Y + AbsoluteSize.Y / 2`
   for each label/icon/bar in a row, centres equal. The bitmap font can't show baselines.
4. Before calling it done: playtest, `screenshot_ui context=client`, because a rule whose value
   equals the class default arrives empty on the client (`vmcp-styling`, "default-valued rule").

The human sees the same stories in the UI Labs plugin (asset 14293316215): hot reload, a control
panel per story, no play mode. Don't write anything a story needs that only one of the two
mounts provides.

## Writing a component

Structure is `Instance.new` through `Make`; a component takes a props table and returns the root
instance without parenting it. Sizes are pixels on the 1920×1080 stage; the controller's
`UIScale` fits the stage to the viewport in 1/20 steps and on whole pixels.

```lua
local function HexStat(props: Props): ImageLabel
	local hex = Make.Image(nil, Assets.hex, props.x - W / 2, props.y - H / 2, W, H)
	Make.Label(hex, props.name, 0, 22, W, 30, 20, { "Cyan" }, CENTER)
	local value = Make.Label(hex, "", W / 2 + 6, 62, 40, 40, 30, { "Cyan", "Mono" })
	local shown = Vide.spring(props.value, 0.4)
	Vide.effect(function()
		value.Text = tostring(math.round(shown()))
	end)
	return hex
end
```

**Vide is for state and motion only.** A prop that changes at runtime is a `source`; the
component reads it in an `effect` (formatting) or through a `spring` (motion). Everything static
is a plain Instance and a plain value.

```lua
-- wrong: Vide as the builder
return Vide.create("Frame") { Size = UDim2.fromOffset(240, 150), Vide.create("TextLabel") { Text = props.name } }

-- right: instances for structure, Vide where something moves
local hex = Make.Image(nil, Assets.hex, x, y, 240, 150)
Vide.effect(function() value.Text = tostring(math.round(shown())) end)
```

Effects need a Vide root: `mount_story` and the UI Labs Vide story runner provide one, and the
controller wraps its mount in `Vide.root`. A component that runs an effect outside a root
errors — that's the reason a story that "works in UI Labs" can fail as a function story.

Colours and fonts come from rules, not properties: tag the instance (`{ "Cyan", "Mono" }`) and let
`Design`'s rules paint it. Setting `TextColor3` directly beats every rule forever (a transition
can bake one in too — see `vmcp-styling`). Only geometry and text belong on the instance.

Icons are `Assets.<name>` (`rbxassetid://…`, 4096px, white) tinted by an `ImageLabel.<Tag>` rule;
`ScaleType.Fit` is set by the base `ImageLabel` rule so any box shape works. New art goes through
`vmcp-icons`, never `EditableImage`.

## Writing a story

Vide story — controls arrive as `Vide.source`s. The story runs **once**; a control read with
`()` outside an effect is baked at mount and the UI Labs slider does nothing. So read the static
controls in a `Vide.effect`, build inside a nested `Vide.root` (components make springs/effects,
and Vide 0.4 refuses a reactive scope inside another one), and `Vide.cleanup` both the root and
the instance. Controls passed through as sources still animate on their own.

```lua
return {
	vide = Vide,
	controls = {
		name = UILabs.String("REFLEXES"),
		icon = UILabs.Choose({ "reflex", "body", "tech" }),
		value = UILabs.Number(7, 0, 20, 1),
	},
	story = function(props)
		local c = props.controls
		Vide.effect(function()
			local name, icon = c.name(), c.icon() -- read here, not inside the root, or they aren't tracked
			local destroy, hex = Vide.root(function()
				return HexStat({ name = name, icon = icon, value = c.value, x = 200, y = 120 })
			end)
			hex.Parent = props.target
			Vide.cleanup(destroy)
			Vide.cleanup(function() hex:Destroy() end)
		end)
	end,
}
```

Generic story (no Vide) — `render(props)` gets `props.controls` as plain values and nothing
re-renders by itself: rebuild from `props.subscribe`, return a cleanup that unsubscribes:

```lua
return {
	controls = { filled = UILabs.Boolean(true) },
	render = function(props)
		local slot
		local function build(controls)
			if slot then slot:Destroy() end
			slot = CyberwareSlot({ x = 40, y = 40, item = if controls.filled then GOLD else nil })
			slot.Parent = props.target
		end
		build(props.controls)
		local unsubscribe = props.subscribe(build)
		return function() unsubscribe(); slot:Destroy() end
	end,
}
```

Rules for a story: it requires its component with `require(script.Parent)`; it calls
`Design.Link(props.target)` first; a page story puts its page on
`Stage.new(props.target, Vector2.new(1920, 990))` so the UI Labs preview shows the whole page
(the widget is any size and scales nothing); a story never yields (UI Labs runs it under a
no-yield guard and abandons it -- `CreateHumanoidModelFromDescription` yields, `Stage.Dummy()`
doesn't); every prop worth flipping is a control (theme via `Design.SetTheme(c.theme())` in an
effect, counts, rarities, `dummy` for the viewport). It calls (UI Labs' widget has no StyleLink, so without it everything
is grey default labels); it uses `props.target` and nothing else (no `StarterGui`, no `vmcp.*`, no `Players`); a Vide story just
parents, a generic/function story returns cleanup. Controls: `UILabs.Number(def, min, max, step)`,
`String`, `Boolean`, `Choose(list, defIndex)`, `EnumList`, `Datatype.Color3`. Raw values (`x = 10`)
work too. `mount_story` overrides take the raw value; a `Color3` control accepts `"r,g,b"`.

If a story errors while mounting, UI Labs can't run its cleanup and may need a Studio restart;
`mount_story` tears its own target down and returns the traceback.

## Design (theme) module

`ReplicatedStorage.Design` is a ModuleScript whose `Build()` creates, under itself, the layout
the Style Editor generates: `StyleSheet` (rules; derives the tokens), `TokenSheet` (attributes),
`Themes/<Group>/<Name>` (one sheet per theme, same attribute names). Rojo can't author
StyleRule properties, so this is built on first require; the Style Editor can still open and
tweak the live instances. `Design.SetTheme("Ice")` swaps the derive and everything restyles.

Rules use tags (`TextLabel.Cyan`), pseudo-instances (`Frame.Outline::UIStroke`,
`::UICorner`), and tokens (`"$Cyan"`). A rule's value must not equal the class default (it
arrives empty on the client) — put such a value in a differently-named rule with a non-default
partner, or re-set it at runtime. Full grammar in `vmcp-styling/references/roblox-styling.md`.

## Shipping

The controller (`*.client.luau`) makes the ScreenGui, a full-viewport backdrop, the 1920×1080
stage with a `UIScale`, a `StyleLink` to `Design.Build()`, and mounts the top-level component
inside `Vide.root`. Runtime state is a table of sources it exposes (`_G.<Name>`) so a
`run_luau vm=game` probe can set one and watch the spring.

## Things that bite

- `UIListLayout` sorts by Name unless `SortOrder = LayoutOrder`; `P10` lands after `P1`.
- A `UIScale` that isn't a 1/20 step puts every 1px line on a different half-pixel.
- `.Tag` is a CollectionService tag, `#Name` is the instance name. `GetTags()` first when a rule
  "does nothing".
- Two labels with different `TextSize` and `TextYAlignment = Center` don't share a baseline;
  nudge the smaller 2px down or align both Bottom.
- `mount_story` mounts in the plugin VM: a component that requires a game module by absolute
  path (`ReplicatedStorage.Packages.Vide`) is fine; one that reads `Players.LocalPlayer` is not.

## How UI Labs actually runs a story (read before "it works in mount_story but not UI Labs")

UI Labs' hot reloader doesn't `require`. It `loadstring`s the story's source with `script` set
and a `require` that recursively does the same for every dependency -- `Vide`, `UILabs`,
`Make`, `Design`, everything -- fresh per mount, cached only within that mount (string
requires like `"./root"` resolved too). `mount_story` now mirrors this (Tools/MountStory
`newLoader`), which also ends the "plugin serves the first version forever" problem.

Consequences that bit:
- Module-level state is per mount. `Design` used to destroy and rebuild its sheets on every
  fresh run, so the widget's StyleLink from the previous story pointed at a destroyed sheet and
  the next story came up grey: **that was "UI Labs incompatible"**. Now `Design.Build()` in
  edit mode adopts the live sheet when its `Signature` attribute (a hash of tokens/themes/rules)
  matches this source, and `Design.Link` repoints an existing link every time.
- Under Team Create, destroying or renaming a StyleSheet reverts it *and* every StyleSheet
  created within about a second of it (no Lua traceback, "Parent property is locked" warnings
  as it tries to restore them). Reproduced deterministically with plain `Instance.new`; Folders
  are fine. So in edit mode Design never destroys or renames a sheet: a changed source builds a
  new trio beside the old and moves the tagged links (`DesignLink`) over. Old trios stay until
  the place is reopened.
- Deleting a TokenSheet or theme by hand under `Design` leaves the live rules with "$Cyan"
  strings nothing resolves ("Unable to cast string to Color3", everything grey). `Build()`
  checks the two derives still reach a sheet with tokens (`intact`) before adopting, and builds
  a fresh trio otherwise; the manual version is clearing the `Signature` attribute.
- **A running game builds its own sheet** (`RunService:IsRunning()` -> destroy the copies, `make()`).
  Adopting the edit-session copy in a playtest broke the 9-slice plates (SliceCenter/ScaleType
  didn't survive the copy) -- the same lossy-copy family as the default-valued-rule trap in
  `vmcp-styling`.
- A `UIPageLayout` drops its scroll offset (CurrentPage unchanged) when its container rescales,
  and a ScreenGui reports 800x600 for its first frame, so the controller snaps the layout back
  (`TweenTime = 0` + `JumpTo(current)`) a frame after every `AbsoluteSize` change. `JumpTo` in
  the frame the pages were added lands on the wrong page.
- `run_luau` sees raw properties, and styled values never land on them in edit mode: judge
  styling from `screenshot_ui` / `inspect_style`, not from `label.TextColor3`.
- `require(game.ServerStorage.VMCP.Tools.X)` in `run_luau` is cached per session too: after
  editing a tool, `loadstring(ScriptEditorService:GetEditorSource(m))` with `script = m`.

## Struggles and lessons, in the order they happened

- **A dotted path can't name a story.** `Path.Resolve` splits on `.`, so
  `...UI.HexStat.HexStat.story` looks for a child called `HexStat` under `HexStat.story`'s parent
  and finds the component instead. `mount_story` takes the component path and finds the `*.story`
  child itself. Any future tool that takes a path to a UI Labs file has the same problem.
- **The plugin Studio runs is not the one you just built.** After `rojo build plugin.project.json`
  + copy to `%LOCALAPPDATA%/Roblox/Plugins`, Studio kept the old `mount_story`, which resolved the
  path with the old rules, treated the component module as a function story and called
  `HexStat(targetFrame)` — "x is not a valid member of Frame Target". The tell: the same
  `Tool.Run` required from the Rojo-synced source (`require(game.ServerStorage.VMCP.Tools.MountStory)`
  in `run_luau`) worked. That's the check to run before debugging a tool: if the source copy
  works and the tool doesn't, re-add the plugin (Plugins → Manage), don't touch the code.
- **Reproduce the tool's exact steps in `run_luau` before changing the tool.** Clone the folder,
  require the clone's story, build the sources, `Vide.root` it — ten lines, and it separates
  "the story is wrong" from "the tool is wrong" in one call.
- **Rojo can't author StyleRule properties** (`PropertiesSerialize` is an opaque BinaryString), so
  `Design` builds the sheets at runtime. Lives in `src/design/` mapped straight to
  `ReplicatedStorage.Design` — putting it under `src/shared/` would have made it appear twice.
- **stylua turns `Component({...}).Parent = page` into a split assignment** (`}).Parent =\n page`).
  Take the instance into a local first; it reads better anyway.
- **Vide's `source<T>` type doesn't survive the wally wrapper** (`Packages/Vide.lua` is
  `return require(...)`, types don't re-export). Components declare `type Source<T> = () -> T`.
- **luau-lsp and heterogeneous arrays**: a `{ { string, {...}, number? } }` table type fails; type
  the rows as `{ { any } }` and annotate on read (`local selector: string = row[1]`).
- **`analyze` before `build`**: the plugin loader accepts a tool with a type error and you find
  out when it's called. `luau-lsp analyze --defs=globalTypes.d.luau --sourcemap=sourcemap.json <file>`
  after `rojo sourcemap default.project.json -o sourcemap.json` (the sourcemap has to know
  `Packages/` and `src/design/` or every require is `unknown`).
- **Uploads were denied for a guessed user id, and the 403 named the right one** ("User 585228735
  is unauthorized to create an Image asset as User 269323"). The plugin sends the Studio user;
  a script calling `uploadImage` directly has to pass it.
- The `src/client/UI/design/` folder (spec + svg) syncs into the place as instances. Harmless;
  `$ignoreUnknownInstances` or moving it out of `src/` if it ever matters.
- **Controls "sometimes" didn't update in UI Labs.** The ones that worked were passed as sources
  (`value = c.value`); the ones read with `()` at the top of `story` were baked at mount. A Vide
  story runs once — wrap the build in `Vide.effect` + nested `Vide.root` + `Vide.cleanup`
  (a bare effect around a component that springs errors "cannot create a new reactive scope
  inside another reactive scope"; `root` is the escape hatch, and reads inside it aren't
  tracked, so read controls before it). Generic stories never
  re-render at all without `props.subscribe`. `mount_story` can't show this bug (it mounts with
  fixed values), so it only surfaces in the plugin.
- **Everything looked grey and unstyled in UI Labs but fine in game.** No StyleLink: the plugin
  mounts into its own widget, and only the controller / `mount_story` were linking `Design`.
  `Design.Link(target)` at the top of every story, idempotent per LayerCollector.
