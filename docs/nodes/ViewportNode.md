## What it's for

A Viewport draws a view into a texture of its own and shows it where it
stands. It can show the running scene through a camera of its own, or only
its own children. Other nodes can use the picture too: a Sprite as its
texture, or a material as a texture parameter.

## When to use it

- **Minimaps**: the level seen from far above, in a corner of the screen.
- **Split-screen**: two Viewports side by side, each following one player.
- **Picture-in-picture and security cameras**: another part of the level
  in a small window.
- **In-world screens**: a TV or computer screen showing its own animated
  content (its children), drawn on a Sprite that can be rotated or scaled.
- **Portals and reflections**: a material that samples the picture.
- **Photo mode**: a Viewport set to update **Once**, saved with
  `node:save_png`.

## Using it

1. **Add Node** (Ctrl+A) > *Viewport*. Set its **Size**, the size it's
   drawn at.
2. **World** mode (the default): add a *Camera 2D* under it. That camera
   is the viewport's, not the scene's. Give it a **Follow Target**, a
   **Zoom** (0.1 for a minimap) and limits as usual. Its frame in the
   editor is the picture's size.
3. **Children** mode: put what it shows under it, laid out from its top
   left corner. Those nodes are drawn only into the picture.
4. For something that stays on screen, such as a minimap or split-screen,
   put the Viewport under a [Screen Layer](ScreenLayerNode.md).
5. To use the picture elsewhere, set a Sprite's texture to
   `viewport:<the viewport's name>`. A material's texture parameter takes
   the same path. Turn **Display** off if the viewport shouldn't also draw
   itself.

The editor shows each Viewport's picture live, with a frame around it.

## How it works

- **Render Size** is how many pixels it renders: {0, 0} means **Size**.
  Smaller is cheaper; with **Pixelated** on, a 160x90 minimap drawn at
  320x180 keeps crisp pixels.
- **Update Mode**:
  - **Every Frame** redraws it every frame.
  - **When Visible** skips it while it's hidden or off screen.
  - **Once** takes one picture; `node:refresh()` takes another.
- **World** shows the world layers its camera draws (all of them without a
  camera), never Screen Layers, so the HUD isn't in it. Without a camera it
  shows the world around itself.
- **Covers Screen** (World mode): the viewports fill the screen, so the
  main view's world isn't drawn underneath. Only Screen Layers are drawn
  over them. Use it for split-screen.
- **Background** is what's behind the picture: the scene's background
  colour (World) or transparent (Children) unless you set one.
- Viewports render before the frame, deepest first, so a viewport shown
  inside another is ready in time. A viewport never shows itself.
- Children mode only moves the drawing: those nodes still update, collide
  and run their scripts with the rest of the game.

## Scripts

- `viewport:get_texture()` returns its path, `"viewport:<name>"`, for
  `sprite:set_texture(...)`.
- `viewport:refresh()` redraws a viewport set to **Once**.
- `viewport:save_png("photos/shot.png")` saves the picture. A relative path
  goes in the game's save-data folder.
- Its properties work like any node's:
  `viewport:set_property("renderSize", 160, 90)`.

## Example

Split-screen for two players:

```
HUD (Screen Layer)
├── Left   (Viewport: Size 638 x 720, Covers Screen)
│   └── Camera 2D  (Follow Target: ../../../Player1)
└── Right  (Viewport: Position 642, 0, Size 638 x 720, Covers Screen)
    └── Camera 2D  (Follow Target: ../../../Player2)
```

A security monitor showing another room on a tilted screen:

```lua
---@class Monitor : ScriptInstanceBase
local Monitor = {}

function Monitor:ready()
    -- "SecurityCam" is a Viewport (Display off) with a Camera 2D in the vault.
    local cam = Scene.find_node("SecurityCam")
    self.node:set_texture(cam:get_texture()) -- this node is a Sprite
end

return Monitor
```
