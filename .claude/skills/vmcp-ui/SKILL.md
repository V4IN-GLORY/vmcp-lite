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
  HexStat/init.luau          component
  HexStat/HexStat.story.luau story
src/design/init.luau         Design.Build() -> the StyleSheet; tokens + themes, Style Editor layout
src/client/CyberpunkUI.client.luau   controller: stage + UIScale + StyleLink, mounts the screen
```

## The loop

1. `mount_story story=StarterPlayer.StarterPlayerScripts.Client.UI.HexStat.HexStat.story controls={"value":14}`
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

Vide story — controls arrive as `Vide.source`s, so pass them straight into props that are
sources and call the ones that aren't:

```lua
return {
	vide = Vide,
	controls = {
		name = UILabs.String("REFLEXES"),
		icon = UILabs.Choose({ "reflex", "body", "tech" }),
		value = UILabs.Number(7, 0, 20, 1),
		accent = UILabs.Datatype.Color3(Color3.fromRGB(70, 230, 255)),
	},
	story = function(props)
		local c = props.controls
		HexStat({ name = c.name(), icon = c.icon(), value = c.value, x = 200, y = 120 }).Parent = props.target
	end,
}
```

Generic story (no Vide) — `render(props)` gets `props.controls` as plain values and returns a
cleanup:

```lua
return {
	controls = { filled = UILabs.Boolean(true) },
	render = function(props)
		local slot = CyberwareSlot({ x = 40, y = 40, item = if props.controls.filled then GOLD else nil })
		slot.Parent = props.target
		return function() slot:Destroy() end
	end,
}
```

Rules for a story: it requires its component with `require(script.Parent)`; it uses
`props.target` and nothing else (no `StarterGui`, no `vmcp.*`, no `Players`); a Vide story just
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
