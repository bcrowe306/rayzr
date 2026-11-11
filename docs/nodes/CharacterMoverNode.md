## Shapes

A character mover collides through Box2D's mover functions, which work with
capsules. Its shapes are used as capsules:

- A **capsule** or **circle** as it is.
- A **box**, **polygon** or **chain**: the capsule that fits its bounds (along its longer side).
  Corners are rounded.
- A **segment**: a capsule along it.

With several shapes, it collides with all of them; sensor shapes are skipped.
The debug view draws the shapes you set. With no shape, it uses its
**Radius** and **Height**.

## What it's standing on

`character_get_floor()` says what the character stood on after its last
move, or returns nil while it's in the air. The table it returns has:

- `node`: the floor. For a TileMap or LDtk level this is the map itself, not
  its hidden collider body.
- `point` / `point_x`, `point_y`: where the character touches the floor.
- `normal` and `angle`: the floor's slope, from 0 when flat up to 60 degrees.
- `cell_x`, `cell_y` and `tile`: only on a TileMap, the cell and tile under
  the feet.

Use it for footstep sounds, slippery ice, slow mud or floors that hurt:

```lua
local SURFACE = { [12] = "ice", [13] = "ice", [20] = "mud" } -- tile index -> surface

function Player:surface()
    local f = self.node:character_get_floor()
    if not f then return nil end                -- in the air
    if f.tile then return SURFACE[f.tile] or "ground" end
    if f.node:has_tag("ice") then return "ice" end
    return "ground"
end
```

On an LDtk level, read the IntGrid value at the contact point, just inside
the floor:
`level:ldtk_get_int_grid_name("Collisions", f.point_x, f.point_y + 1)`.
Dynamic Bodies have the same query as `body_get_floor()`.

## Slopes, steps and jumps

The Inspector's floor settings:

- **Floor Max Angle** (60°): the steepest slope it stands on.
- **Floor Snap Length**: stays on the floor going down slopes.
- **Stop On Slope**: doesn't slide while standing still.
- **Step Height**: walks up steps.
- **Coyote Time** and **Jump Buffer Time**: forgiving jumps for the
  built-in movement.

From a script, `character_get_platform_velocity()` gives the velocity of
the moving floor under it. `character_was_on_floor(seconds)` is for coyote
time in your own jump code. `character_test_move(dx, dy)` checks for room
before a move without making it.

With the fixed physics step, move a script-controlled mover in
`on_physics_update(dt)` so it moves the same at any frame rate. The
[Physics scripting](../../engine/docs/physics_scripting.md) guide has
examples of all of these.
