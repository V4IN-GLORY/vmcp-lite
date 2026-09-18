# Roblox UI styling, distilled from the official docs

Sources: [ui/styling](https://create.roblox.com/docs/ui/styling), [editor](https://create.roblox.com/docs/ui/styling/editor), [compatibility](https://create.roblox.com/docs/ui/styling/compatibility), [css-comparisons](https://create.roblox.com/docs/ui/styling/css-comparisons). The SKILL.md holds what these pages don't: the silent failures.

## Instances

| Class | Role |
|---|---|
| `StyleSheet` | holds rules; its **attributes are tokens** (`$Name`) |
| `StyleRule` | `Selector`, `Priority`, `SetProperties{}` / `SetProperty`, `SetPropertyTransition(s)`, `SelectorError` (read it) |
| `StyleLink` | under a `ScreenGui`; `StyleSheet` = the sheet. **One sheet per tree.** |
| `StyleDerive` | under a sheet; pulls tokens/rules/themes in from another sheet |
| `StyleBase` | engine defaults (`Design/BaseStyleSheet` in the editor layout; don't delete) |

Style Editor layout (what Studio generates, match it so the human can open yours):

```
ReplicatedStorage/Design/
  BaseStyleSheet     engine defaults, derived by StyleSheet
  StyleSheet         your rules
  TokenSheet         attributes = tokens
  Themes/<Group>/<A> one sheet per theme, all with the same attribute names
StarterGui/ScreenGui/StyleLink → Design/StyleSheet
```

Swapping a theme = pointing the derive at another sheet with the same token names.

## Selector grammar (CSS → Roblox)

| CSS | Roblox | Example |
|---|---|---|
| element | class name | `"TextButton"` |
| `.class` | **tag** (CollectionService) | `".ButtonPrimary"` |
| `#id` | instance **Name** | `"#ModalFrame"` |
| `:hover` | GuiState `:Hover`, `:Press` (+ the other GuiState values: Idle, NonInteractable) | `"ImageLabel:Hover"` |
| `a > b` | `>` child | `".MenuContainer > TextButton"` |
| `a b` | `>>` descendant | `".MenuContainer >> TextButton"` |
| `a, b` | `,` list | `"ImageLabel, TextLabel"` (docs say it works; one list matched nothing for us — verify with `inspect_style`) |
| `::before` | `::UIComponent` phantom modifier | `"Frame.RoundedCorner20::UICorner"` |
| `@media` | `@Query` built-in or custom | `"@ViewportDisplaySizeSmall Frame"` |
| nesting (SCSS) | nested `StyleRule`s **merge selectors** | child rule `":Hover"` under `"TextButton"` = `TextButton:Hover` |

Compound is fine: `"TextLabel.Tab.Active"`, `".Tab.Active > .Marker"`.

### Queries

```lua
queryCondition.Selector = "::StyleQuery #WideContainer"
queryCondition:SetProperty("MinSize", Vector2.new(400, 0))
queryStyle.Selector = "@WideContainer Frame > TextButton"
```

`StyleQuery` properties: `AspectRatioRange`, `MaxSize`, `MinSize`, `PreferredInputType`, `ReduceMotionEnabled`, `ViewportDisplaySize`. Built-ins: `@ViewportDisplaySizeSmall`, `@PreferredInputTouch`, `@ReducedMotionEnabledTrue`.

## Tokens, transitions

```lua
sheet:SetAttribute("ButtonBgColor", Color3.fromHex("335FFF"))
rule:SetProperties({ BackgroundColor3 = "$ButtonBgColor" })
rule:SetPropertyTransitions({ BackgroundColor3 = TweenInfo.new(1, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out) })
```

Tokens resolve through the derive chain, so a token sheet + theme sheets + a rules sheet is the normal split.

## Precedence

Direct property on the instance > any rule. Among rules: more specific selector wins, then `StyleRule.Priority` (higher wins). Give state rules explicit priorities (hover 1, active 2) rather than trusting specificity. A property value **equal to the class default counts as unset** on both sides: an instance's default-valued property loses to a class rule, and a rule storing a default-valued property arrives empty in a playtest.

## What can be styled (compatibility page)

**GuiObject**: Active, AnchorPoint, AutomaticSize, BackgroundColor3, BackgroundTransparency, BorderColor3, BorderMode, BorderSizePixel, ClipsDescendants, Interactable, LayoutOrder, Position, Rotation, Selectable, SelectionOrder, Size, SizeConstraint, Transparency, Visible, ZIndex
**GuiButton**: AutoButtonColor
**TextLabel / TextButton**: Font, FontFace, LineHeight, MaxVisibleGraphemes, OpenTypeFeatures, RichText, Text, TextColor3, TextDirection, TextScaled, TextSize, TextStrokeColor3, TextStrokeTransparency, TextTransparency, TextTruncate, TextWrapped, TextXAlignment, TextYAlignment
**ImageLabel**: Image, ImageColor3, ImageContent, ImageRectOffset, ImageRectSize, ImageTransparency, ResampleMode, ScaleType, SliceCenter, SliceScale, TileSize
**ImageButton**: the above + HoverImage(Content), PressedImage(Content)
**TextBox**: ClearTextOnFocus, MultiLine, PlaceholderColor3, PlaceholderText, ShowNativeInput, TextEditable
**ScrollingFrame**: AutomaticCanvasSize, Bottom/Mid/TopImage(Content), CanvasSize, ElasticBehavior, Horizontal/VerticalScrollBarInset, ScrollBarImageColor3, ScrollBarImageTransparency, ScrollBarThickness, ScrollingDirection, ScrollingEnabled, VerticalScrollBarPosition
**ViewportFrame**: Ambient, ImageColor3, ImageTransparency, LightColor, LightDirection
**InputActionLabel**: FontFace, ImageColor3, ImageTransparency, TextColor3, TextSize, TextTransparency, TextWrapped, TextX/YAlignment
**Path2D**: Closed, Color3, Thickness, Visible, ZIndex · **CanvasGroup**: GroupColor3, GroupTransparency

Modifiers (also as `::` phantoms): **UICorner** CornerRadius + per-corner radii · **UIGradient** Color, Enabled, Offset, Rotation, Transparency · **UIPadding** PaddingBottom/Left/Right/Top · **UIShadow** BlurRadius, Color, Offset, Spread, Transparency, ZIndex · **UIStroke** ApplyStrokeMode, Color, Enabled, LineJoinMode, Thickness, Transparency

Layouts: **UIListLayout** HorizontalFlex, HorizontalPadding, ItemLineAlignment, Padding, VerticalFlex, VerticalPadding, Wraps · **UIGridStyleLayout** FillDirection, HorizontalAlignment, SortOrder, VerticalAlignment · **UIGridLayout** CellPadding, CellSize, FillDirectionMaxCells, StartCorner · **UIPageLayout** Animated, Circular, Easing*, GamepadInputEnabled, Padding, ScrollWheelInputEnabled, TouchInputEnabled, TweenTime

Constraints: **UIAspectRatioConstraint** AspectRatio, AspectType, DominantAxis · **UISizeConstraint** MaxSize, MinSize · **UITextSizeConstraint** Max/MinTextSize · **UIScale** Scale · **UIFlexItem** FlexMode, GrowRatio, ItemLineAlignment, ShrinkRatio

Anything not listed is refused silently by `SetProperties` — `vmcp.Style.Apply` / `Check` return the refused names. "Additional support may be added over time."

## Editor notes

Styled properties show a ⚠ in the Properties window; overridden (direct) values show bold; right-click → Reset to Default hands a property back to the rules. Removing the derive from `Design/StyleSheet` to `BaseStyleSheet` makes unstyled values unpredictable.
