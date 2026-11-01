## What it's for

A Text node draws text in the world: a sign, a damage number, a name over a
character, a title, a typed-out message. It uses any font in the project,
wraps and aligns lines, understands colour, size, wave and shake tags, can
show a translation, and can type itself out letter by letter.

## When to use it

- **Text that belongs to the world**: signs, labels over characters,
  floating score numbers, a title in a menu scene.
- **A typewriter message**: set **Reveal Speed** and wait for `revealed`.
- **Not** for a HUD that stays on screen while the camera moves: put the
  text under a [Screen Layer](ScreenLayerNode.md) (or use a
  [UI Label](UILabelNode.md) there).
- **Not** for conversations with speakers and lines: a
  [Dialogue Box](DialogueNode.md) types lines and waits for the player.

## Using it

1. **Add Node** (Ctrl+A) > *Text*. It shows "Text" in the engine font.
2. Type in **Text** (the Inspector's Node tab, **Properties** section). With **Rich Text**
   on (the default) you can mark it up:
   `[color=yellow]gold[/color]`, `[size=40]big[/size]`, `[wave]...[/wave]`,
   `[shake]...[/shake]`.
3. Pick a font in the **Font** section: a `.ttf` / `.otf` / `.fnt` file in
   the project. *None* is the engine font.
4. Set **Font Size** (pixels), **Color**, **Align** (Left, Center, Right),
   **Max Width** (wrap at this width; 0 wraps only at line breaks) and
   **Line Spacing** (times the font size).
5. **Rendering** picks how the letters are drawn. *Auto* (the default)
   keeps text sharp when it is scaled, rotated or zoomed and uses the
   ordinary font at 1:1. *Sharp* always draws from the distance field;
   *Bitmap* always uses the ordinary font (blurry or blocky when scaled, the
   old look).
6. To bend the text along a curve, add a [Path](PathNode.md) and set
   **Path** to it (drag the Path node onto the field, or type `..` when the
   text is the path's child). **Path Align** puts the text at the start,
   middle or end of the path, **Path Offset** moves it along (animate it for
   a marquee) and **Path Upright** turns letters over where the path runs
   right to left so they don't read upside down.
7. For a typewriter, set **Reveal Speed** (characters per second).
8. For a translated text, tick **Localized** and type a key of the locale
   tables in **Text**.

## How it works

- **Origin** (in Transform) is a fraction of the text block: the centre by
  default. (0, 0) puts the top-left of the first line at the node's
  position. The block's size follows the text, so the origin stays at the
  same fraction when the text changes.
- **Align** lines up the lines inside the block; it doesn't move the block.
- Scale: the text scales by the node's X scale on both axes.
- Fonts: a `.ttf` / `.otf` is drawn at the size asked. Sharp text is drawn
  from a multi-channel signed distance field (MSDF) of the same font, so
  corners stay crisp at any scale. Its letters are made the first time they
  are drawn, a few per frame. A CFF-flavoured `.otf` (no `glyf` table)
  falls back to a single-channel distance field, with slightly rounder
  corners. A `.fnt` (BMFont) is always used as drawn.
- Where sharp text is used: Text nodes, Dialogue Boxes, subtitles, the touch
  controls' labels and UI widgets drawn at a UI scale other than 1. Lua has
  no call that draws text directly; use a Text node.
- Text on a path: each letter sits on the path at its distance along it,
  turned to the path's direction; the text's own position, rotation and
  **Align** don't apply, its scale and **Font Size** do. A closed path wraps
  the text around. Renaming or moving the Path node in the editor keeps the
  link. Characters are basic Latin, Latin-1 and common
  punctuation (quotes, dashes, the euro sign).
- Rich text tags: `[color=...]` takes a name (white, black, red, green,
  blue, yellow, orange, purple, gray) or `#rrggbb` / `#rrggbbaa`;
  `[size=N]` is pixels; `[wave]` and `[shake]` move the letters. Close a tag
  with `[/color]`, `[/size]` and so on. `[[` shows a `[`. Unknown tags are
  shown as typed. A `[color]` overrides **Color**.
- **Localized**: **Text** is a key of the CSV tables in `locale/`; the node
  shows the current language's text (see the scripting guide's
  [Text, dialogue and localization](../../engine/SCRIPTING.md)).
- Typewriter: with **Reveal Speed** above 0, characters appear one by one
  (markup tags don't count). `set_text` and `text_restart()` start it
  again.
- New Text nodes are on Layer4, in front of sprites on layers 1-3. See
  [Draw order](../../engine/docs/draw_order.md).

## Signals

| Signal | When | Value |
|---|---|---|
| `revealed` | The typewriter has shown the last character (only with **Reveal Speed** above 0) | none |

## Example

A sign that types its message when the player comes near. The script is on
a Trigger Area; the Text node is its child named `Message`, with
**Reveal Speed** at 30.

```lua
---@class Sign : ScriptInstanceBase
local Sign = {}

Sign.properties = {
    message = { type = "string", default = "Beware of [color=red]bats[/color]!", label = "Message" },
}

function Sign:ready()
    self.text = self.node:get_node("Message") ---@type TextNode
    self.text:set_visible(false)
    self.text:connect("revealed", function()
        Log.info("The sign has been read")
    end)
end

function Sign:on_body_entered(body)
    if body == nil or body:get_name() ~= "Player" then return end
    self.text:set_visible(true)
    self.text:set_text(self.message) -- restarts the typewriter
end

function Sign:on_body_exited(body)
    if body ~= nil and body:get_name() == "Player" then
        self.text:set_visible(false)
    end
end

return Sign
```

A score label is one line: `label:set_text("Score: " .. self.score)`.
`get_text()` reads the text back.

## Screenshot

![A Text node with rich text](../images/node_TextNode.png)
