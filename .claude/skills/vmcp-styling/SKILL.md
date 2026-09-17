---
name: vmcp-styling
description: Roblox UI stylesheets with VMCP — StyleSheet, StyleRule, selectors, tokens and themes, the Style helper that catches the failures the engine hides, GetStyled, and the screenshot_ui tool for looking at the result. Use when building or debugging UI styling.
---

# Stylesheets

Reached from a `run_luau` snippet as `vmcp.Style`. Three functions: `Check`, `Apply`, `Selector`
for writing rules, `Read` for seeing what they did. Everything else is plain engine API, but the
engine fails quietly in more places than it should — the list below is every one that has cost
real time, in the order you'll hit them.

## Writing rules

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

Selectors take a class name, `.Tag` (CollectionService tag), `#Name` (instance name), `:Hover`
`:Press`, `@StyleQuery`, combined with `>` (direct child) and `>>` (descendant). Tokens are
**StyleSheet attributes**, so swapping a set of attributes reskins everything — that is the whole
theming mechanism; keep tokens in one sheet and rules in another joined by `StyleDerive`.
`SetPropertyTransition(property, tweenInfo)` is the CSS-transition equivalent. The `::` combinator
spawns a phantom `UICorner` / `UIStroke` / `UIGradient` from a rule instead of parenting one by
hand.

A state that isn't `:Hover`/`:Press` (selected tab, active panel) is a tag you add and remove
with `CollectionService`, matched as `.Tab.Active`. Compound class+tag selectors work
(`TextLabel.Center`, `.Tab.Active > .Marker`).

**Precedence you can rely on**: a value set directly on the instance beats every rule; among
rules, more specific beats less (`TextLabel.Center` over `TextLabel`, `.Tab.Active > .Marker`
over `.Tab > .Marker`), and `StyleRule.Priority` (higher wins) settles anything else. Give
state rules an explicit Priority (hover 1, active 2) instead of trusting the specificity maths.

## The silent failures

**`StyleRule:SetProperties` ignores a property the class doesn't have.** No error, no warning.
`vmcp.Style.Apply(rule, "TextLabel", props)` returns the names it refused; `vmcp.Style.Check`
does the same without applying. Both work by creating a throwaway instance, so an abstract
class like `GuiObject` can't be checked and says so.

**`StyleRule.SelectorError` is readable but nothing makes you read it.**
`vmcp.Style.Selector(rule, sel)` returns the complaint, or nil when it parsed.

**A styled value never shows up in a plain property read.** `frame.BackgroundColor3` keeps
returning the instance's own value while the rule renders fine. `instance:GetStyled("Prop")`
is the read that sees rules; `vmcp.Style.Read(instance, { "BackgroundColor3", "TextSize" })`
does several. Only computed properties (`AbsoluteSize`, `AbsolutePosition`, `TextBounds`)
reflect styling on their own. Any QA that reads colours or sizes off instances is reading the
wrong thing.

**A value equal to the class default counts as unset.** `label.TextXAlignment = Center` is the
default, so a `TextLabel { TextXAlignment = Left }` class rule takes it. Anything you need at
its default *against* a class rule wants its own rule (`TextLabel.Center`), not a direct set.

**And a rule *value* equal to the class default doesn't survive into a playtest.** The
`TextLabel.Center { TextXAlignment = Center }` rule worked in the edit session and did nothing
on the client: the saved rule arrived empty, so the `TextLabel { Left }` class rule won and the
numbers slid off their hexes. `rule:SetProperty(...)` again from a LocalScript at startup makes
it stick. Prefer rules that set non-default values; when you must set a default, re-set it at
runtime.

**A comma list in one selector parses but can match nothing.** `.A:Hover > .X, .A.Active > .X`
gave no `SelectorError` and applied to neither. One selector per rule.

**`.Name` is a tag, `#Name` is the instance name.** A label *called* `Value` with tags
`{ "ValueXL" }` does not match `.Value`; the rule silently matches nothing. First move when a
rule "does nothing": `GetTags()` on the target.

**A transition can bake a value into the instance.** Replacing or destroying a rule that had
`SetPropertyTransition` on a live sheet left the tweened `ImageColor3` set *directly* on the
label — and direct beats rule, so from then on no rule could change it, and every later fix
looked like it did nothing. Reset the property to its class default to hand it back to the
rules. This is the mechanism behind "I fixed it and it broke again".

## Debugging a rule that does nothing

In this order, each is one snippet:

1. `rule.SelectorError` — did it parse.
2. `target:GetTags()` / `target.Name` — does the selector actually name it (tag vs name).
3. `target:GetStyled("Prop")` — what the engine resolved; compare with `target.Prop` (direct).
   If direct is anything but the class default, that's your answer: the direct value wins.
4. Probe with a property nothing else touches: add a rule with the same selector setting
   `Rotation = 5`, read `GetStyled("Rotation")`. Applies → the selector matches and it's a
   precedence fight (specificity, Priority, direct value). Doesn't → the selector.
5. `screenshot_ui` to see the whole thing rather than one property.

## Editing a live sheet vs regenerating

Patching rules and instances in place is how the bake-in trap and half-applied states happen:
every live edit interacts with transitions and with whatever the last edit left on the
instances. For anything beyond a one-property check, change the generator and rerun it. It
destroys and rebuilds the ScreenGui, the sheets and the controller, so the tree is exactly what
the source says and nothing else. Live probing is for finding out; the file is for fixing.

## Looking at it

`screenshot_ui` (root = a ScreenGui, GuiObject or StarterGui/PlayerGui; context plugin or
client; scale) walks the tree in render order (Sibling and Global ZIndex), reads every visual
property through `GetStyled`, and the server draws it as a PNG that comes back inline. Boxes,
strokes, gradients, corners, rotation and clipping are exact; text is a 5x7 bitmap font so its
width isn't the engine's (check overflow with `TextFits`, not by eye); EditableImage icons are
real pixels, asset images a tinted placeholder (a tiled one draws as a faint overlay), a
ViewportFrame a box naming how many parts it holds. Good for "what overlaps what", "is the
backdrop actually opaque", "is that icon centred in its row" — it caught a see-through
backdrop (a `UIGradient.Transparency` sequence makes the *element* transparent, not just the
tint) and misaligned rows on the first run. Not for judging a font.

The PNG comes back only from a server that knows the `ui` job; with an older server the tool
reports "doesn't know how to finish a ui job" — restart Claude so `npx` pulls the current one.
