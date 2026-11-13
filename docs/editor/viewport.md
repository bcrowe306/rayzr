# Viewport

The viewport shows the active scene the way the game draws it, and lets you
work on it directly: pick nodes, move, rotate and scale them with gizmos,
edit collision shapes, and drop assets in from the Assets panel. Overlays
show what the game doesn't draw - the grid, node bounds, colliders, the
camera's frame, guides.

![The viewport](../images/editor_viewport.png)

## When to use it

- Place and arrange nodes by eye.
- Check what the game's camera will see.
- Edit a physics body's collision shapes with handles.
- Draw and edit vector art on a Vector Shape: double-click it for
  [vector edit mode](vector-edit.md).
- Add images, sounds, components and levels by dragging them in.
- Try the scene with **Simulate** (F7) without leaving the editor.
- For exact values use the [Inspector](inspector.md); to find a node by
  name, the [Scene panel](scene-tree.md).

## What's in it

### Moving around

| Action | What it does |
|---|---|
| Mouse wheel | Zoom around the mouse (2% to 6400%). |
| Middle mouse drag | Pan, with any tool. |
| **Pan** tool (T) + left drag | Pan. |
| Cmd+= / Cmd+- (Ctrl+= / Ctrl+-) | Zoom in / out. |
| Cmd+0 | Zoom to 100%. |
| **Home** | Fit the whole scene. |
| Shift+Home | Fit the game view: the camera's frame at the project's resolution. |
| Shift+F | Fit the selected nodes. |
| **F** | Centre the view on the selected node (the zoom stays). |

The toolbar's zoom box has the same fits and fixed levels (25% to 3200%).
The status bar shows the mouse's world position and the zoom.

### Selecting

| Action | What it does |
|---|---|
| Click a node | Select it. The one drawn on top wins (layer, Z index, Y sort, tree order). |
| Cmd+click, Shift+click | Add to the selection. |
| Drag on empty space (Select tool) | Box select: every node the box touches. |
| Click empty space | Deselect. |
| Esc | Deselect (first leaves shape editing). |

Nodes that draw nothing (timers, sounds, plain nodes) show a small square
you can click. Locked and editor-hidden nodes can't be picked.

### Gizmos

Pick a tool in the toolbar or with its key. The gizmo sits on the selected
node; with several selected, the others move along.

| Tool | Handles |
|---|---|
| **Select** (Q) | A ring marks the node; no handles. |
| **Move** (W) | The square moves freely; the red arrow moves along X, the green one along Y. |
| **Rotate** (E) | Drag the blue ring. |
| **Scale** (R) | The red and green squares scale X or Y; the white corner dot scales both. |

While you drag, a tooltip shows the new position, rotation or scale.
Gizmos work in world space, so children of rotated or scaled parents
behave. Each drag is one undo step.

**Pivot**: hold **Alt** when you start dragging the move square to move
the node's pivot instead. What it shows stays where it is - its image,
children, line points and collision shapes. The pivot snaps to the node's
own edges and centre.

The arrow keys nudge the selection 1 pixel (Shift: one grid step). They only
do while the viewport, the Scene tree or the Inspector has the keyboard: in the
bottom panel (the File Browser's rows) or the Assets panel they move through
that panel instead.

### Snapping

| Setting | Where | What it does |
|---|---|---|
| **Snap to Grid** | Magnet button, Shift+S | Moves snap to the grid size (toolbar). |
| **Snap Rotation** | View menu | Rotation snaps to 15°. |
| **Smart Snapping** | View menu, on by default | The moved node's edges and centre snap to other nodes' edges and centres and to guides, within a few pixels. A magenta line shows the match. Grid snapping applies on the other axis. |

### Rulers and guides

**View > Rulers & Guides** (Cmd+Shift+R) shows rulers along the top and
left edge, in world units, with the mouse position marked.

- Drag from the left ruler for a vertical guide, from the top one for a
  horizontal guide.
- Drag a guide to move it; drag it back onto a ruler (or out of the
  viewport) to remove it.
- **View > Clear Guides** removes them all.

Guides snap to the grid, are saved with the scene and are ignored by the
game.

### Overlays

| Overlay | Turn it on | What it shows |
|---|---|---|
| **Grid** | Toolbar, Shift+G | The grid (every fifth line brighter) and the origin axes: red for X, green for Y. |
| **Bounds & Colliders** | Toolbar eye, View menu | Every node's outline. Without it, only the selection is outlined (with corner dots). |
| **Show All Colliders** | View menu | Every collision shape, also of LDtk levels and tile maps. |
| **Camera frames** | Toolbar camera, View menu | Each camera's frame - what the game will show at the project's virtual resolution - with its name, size and zoom, its limits and dead zones. Without a camera, the default view. |
| **Labels** | Toolbar tag, View menu | The names on camera frames, camera limits, the Expand frame, Advanced Cameras and LDtk entities. They are drawn at one size on screen (zooming in doesn't grow them) and fade while the mouse is over one, so the node under it can be seen and clicked. Turn them off when they are in the way; the editor remembers. |
| **Screen shape** | Toolbar, only with **Screen Fill: Expand** | A dashed frame for the picked screen shape (16:9, 4:3, phone portrait...) around the design frame; edge-anchored HUD follows it. |
| **Lighting** | Toolbar sun | Lights, the scene's ambient light and post effects. |
| **Colour vision** | View menu | The scene as players with protanopia, deuteranopia or tritanopia see it. |

The viewport also draws editor-only helpers: a marker for each light (and
the radius of selected ones), visibility notifier rectangles (yellow),
navigation regions, paths, a dashed line from a selected camera to the
node it follows, the Y-sort line of a selected node under a Y-sorted
parent, LDtk entity placements, and onion skins while you animate.

Screen Layers (HUD) sit inside the camera frame, where the game will show
them.

### Editing collision shapes

Select a physics body (Static, Dynamic, Area, Character Mover). An **Edit
Shapes** button appears at the top left of the viewport (or use **Edit in
Viewport** in the Inspector's **Collision Shapes** section). The gizmo
gives way to handles on the body's shapes:

| Shape | Handles |
|---|---|
| Any | Drag the centre to move it; drag the orange knob to rotate it (not circles). |
| Box | Edges and corners resize it; the opposite side stays put. Hold **Shift** to resize around the centre. |
| Circle | A radius handle. |
| Capsule | Radius (side) and length (ends). |
| Polygon, chain | Drag points. Click a **+** between two points to add one; right-click a point to remove it. |
| Segment | Its two end points. |

A polygon must be convex: a concave one turns red, and collides as its
outline (its convex hull). Grid snapping applies, and with it rotation
snaps to 15°. Every drag is one undo step. Press **Esc** or click the
button again to stop.

Changing a shape's **Type** in the Inspector keeps its footprint (a box
becomes a polygon with the same corners). Shapes are in the node's own
units: they scale with the node and its parents, like everything it draws.

Other nodes have their own handles while selected: a Path's points and
curve handles, and a Tile Map's painting tools (see the
[Tile Map tab](tab-tilemap.md)).

### Drawing vector art

Double-click a selected **Vector Shape** (or click **Edit Art** in the
Inspector) to draw in it: the rest of the scene dims and the Vector toolbar
takes over the viewport's mouse, with select, node, pen, shape, pencil,
brush, bucket, eyedropper and gradient tools. **Esc** or **Done** goes back.
See [Vector edit mode](vector-edit.md).

### Dropping assets

Drag from the Assets panel into the viewport. The new node lands where you
drop it (several selected assets land in a row).

| Asset | What happens |
|---|---|
| Image | A Texture Sprite with it. |
| Aseprite file | An Aseprite node playing its first tag. |
| Vector file (SVG) | A Vector Shape - or, dropped onto one, that shape draws it. |
| Sound | A Sound node with it. |
| Component | An instance of it. |
| Custom node type | A node of that type. |
| LDtk level | A level node. |
| Script | Attached to the node under the mouse (else the selected one). |
| Shader | Applied to the node under the mouse (else the selected one). |
| Level generator | Opens the Level Generator. |
| A symbol from the [Library tab](tab-library.md) | A Vector Shape drawing it. |

You can also drop files from your computer's file browser onto the
viewport: they are imported into the project, and images, sounds,
components, levels, Aseprite and vector files are placed where you drop
them.

### Right-click

The scene viewport has no context menu: right-click a node in the
[Scene panel](scene-tree.md) for its actions. In the viewport, right-click
removes a polygon point while editing shapes and erases while painting
tiles. In vector edit mode, right-clicking an anchor (Nodes tool) makes it
**Smooth**, **Symmetric** or **Corner**.

### Image previews

Double-click a texture, an Aseprite file or an SVG in [Assets](assets.md)
(or right-click it > **Preview**) and it opens in a tab of its own beside
the scene tabs. While that tab is selected, the viewport shows the image
instead of the scene; click a scene tab to go back. Each image keeps its
tab until you close it (**x**, middle-click or Cmd+W); double-clicking an
image that is already open switches to its tab.

| | |
|---|---|
| Mouse wheel | Zooms at the cursor. |
| Drag (left or middle button) | Pans. |
| **Fit** (expand icon) | The whole image in the view. Small images are enlarged in whole steps (at most 8x), so pixel art stays crisp. |
| **1:1** | Actual size: one image pixel per screen pixel (an SVG: its document size). |
| **-** / **+** | Zoom out / in; the zoom is between them. |
| **Pixel grid** (grid icon) | Lines between the pixels, from 800% zoom. |
| **Frames** (cells icon) | The frames the image is cut into, numbered: a texture's slicing preset (**Slice Sprite Sheet...**, saved in its [import settings](assets.md)), an Aseprite file's frames. Shown only when it has frames. |

A checkerboard shows behind transparent pixels, and a texture is drawn with
its import filter (**Point** keeps pixels sharp). An Aseprite file shows
every frame on one sheet; an SVG is drawn at twice its size, so it stays
sharp when you zoom in.

The bar under the image shows its size (an SVG: its document size), the
file type and size, a texture's filter and wrap (and **mipmaps** or
**atlas** when set), how many frames it has, and the pixel under the mouse:
its position and colour (`#RRGGBBAA`) with a swatch. A file that changes on
disk reloads in its tab.

### Simulate

**Game > Simulate in Editor** (F7) runs the scene's scripts, physics and
tweens in the viewport. Particle emitters run all the time, so you see
changes at once. Press F7 again to stop: the scene goes back to how it was
before. You can't switch scene tabs while simulating.

## Walkthrough

Lay out a row of platforms:

1. Drag a platform image from Assets into the viewport. A Texture Sprite
   appears where you drop it.
2. Press Cmd+Shift+R (Ctrl+Shift+R) for the rulers. Drag down from the
   top ruler to put a guide at `y = 320`.
3. Press **W**. Drag the sprite's square onto the guide: its bottom edge
   snaps to it (magenta line).
4. Press Cmd+D twice to duplicate it, and drag each copy along the guide.
5. Box select all three on empty space with the Select tool (Q), then
   **Edit > Align > Distribute Horizontally**.
6. Select one platform, press Cmd+A and add a **Static Platform** under
   it. It starts with a box shape. With it selected, click **Edit Shapes**
   and drag the box's edges to fit the image.
7. Press Shift+Home to see the camera's frame. Turn on the camera button
   in the toolbar if you don't see it.
8. Press F7 to simulate, watch, and F7 again to stop.

## Tips

- Lock a background (Cmd+L) so clicks go to what's in front of it.
- Hide in Editor (Cmd+Shift+H) clears the view without changing the game.
- Each scene tab keeps its own view position and zoom.
- An empty scene shows a hint: Cmd+A adds a node, or drop assets in.
- More: [toolbar and menus](toolbar-menus.md),
  [vector edit mode](vector-edit.md),
  [Scene panel](scene-tree.md), [Inspector](inspector.md),
  [CameraNode](../nodes/CameraNode.md),
  [StaticBodyNode](../nodes/StaticBodyNode.md),
  [draw order](../../engine/docs/draw_order.md),
  [paths](../../engine/docs/paths.md).
