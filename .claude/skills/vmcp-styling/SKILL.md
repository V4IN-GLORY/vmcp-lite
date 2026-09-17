---
name: vmcp-styling
description: Roblox UI stylesheets with VMCP — StyleSheet, StyleRule, selectors, tokens and themes, plus the Style helper that catches the two failures the engine hides. Use when building or debugging UI styling.
---

# Stylesheets

Reached from a `run_luau` snippet as `vmcp.Style`. The library is two functions, because there are
exactly two places the engine fails quietly here.

## The silent failures

**`StyleRule:SetProperties` ignores a property the target class doesn't have.** No error, no
warning — the rule just does less than it claims. The usual next move is to go and rewrite the
selector, which was never the problem.

```lua
local missing = vmcp.Style.Apply(rule, "TextLabel", {
    BackgroundColor3 = Color3.fromRGB(30, 30, 40),
    TextColour = Color3.new(1, 1, 1),   -- wrong spelling
})
return missing   -- { "TextColour" }
```

`vmcp.Style.Check(className, properties)` does the same test without applying anything. Both work
by creating one throwaway instance of the class, so an abstract class like `GuiObject` can't be
checked — it says so rather than guessing.

**`StyleRule.SelectorError` is readable but nothing makes you read it.**

```lua
local complaint = vmcp.Style.Selector(rule, "TextLabel:Hovr")
if complaint then return complaint end
```

Returns nil when the selector parsed.

**A styled value never shows up in a plain property read.** `frame.BackgroundColor3` keeps
returning what the instance holds while the rule renders fine, and a rule that seems to do
nothing was usually working all along. `instance:GetStyled("BackgroundColor3")` is the read that
sees rules; `vmcp.Style.Read(instance, { "BackgroundColor3", "TextSize" })` does several at
once. Only computed properties like `AbsoluteSize` reflect styling on their own. A value set
directly on the instance still wins over a rule.

To look at the result rather than probe it, the `screenshot_ui` tool draws a ScreenGui as a PNG
from styled values — see below.

## The rest is plain engine API

```lua
local sheet = Instance.new("StyleSheet")
sheet:SetAttribute("Accent", Color3.fromRGB(90, 140, 255))   -- a token

local rule = Instance.new("StyleRule")
vmcp.Style.Selector(rule, "TextButton")
vmcp.Style.Apply(rule, "TextButton", {
    BackgroundColor3 = "$Accent",     -- tokens are referenced as "$Name"
    TextSize = 18,
})
rule.Parent = sheet

local hover = Instance.new("StyleRule")
vmcp.Style.Selector(hover, "TextButton:Hover")
vmcp.Style.Apply(hover, "TextButton", { BackgroundTransparency = 0.2 })
hover.Parent = sheet

local link = Instance.new("StyleLink")
link.StyleSheet = sheet
link.Parent = screenGui
```

Selectors take a class name, `.Tag`, `#Name`, `:Hover`, `@StyleQuery`, combined with `>`
(direct child), `>>` (descendant) and `,` (either).

Tokens are **StyleSheet attributes**, so swapping a set of attributes reskins everything at once —
that is the whole theming mechanism.

`SetPropertyTransition(property, tweenInfo)` is the CSS-transition equivalent. The `::` combinator
spawns a phantom `UICorner` / `UIStroke` / `UIGradient` from a rule instead of parenting one by
hand. `StyleDerive` chains one sheet onto another.

## Looking at it

`screenshot_ui` (root = a ScreenGui, GuiObject or StarterGui/PlayerGui; context plugin or
client) walks the tree in render order, reads every visual property through `GetStyled`, and the
server draws it as a PNG that comes back inline. Boxes, strokes, gradients, corners, rotation and
clipping are exact; text is a 5x7 bitmap font so its width isn't the engine's (check overflow
with `TextFits`); EditableImage icons are real pixels, asset images a tinted placeholder, and a
ViewportFrame a box naming how many parts it holds. Good for "what overlaps what", not for
judging a font.
