## Use it for

- **Finding nodes**: `Scene.find_node("Player")` gets a node by name from anywhere; `find_by_tag("enemy")` and `find_nodes_of_type("AreaNode")` get every match, in tree order.
- **Changing levels**: `Scene.change_scene("level_2", {transition = "fade"})` switches scenes behind a transition, or through a loading screen with `loading`; `Scene.reload()` restarts the current one.
- **Faster switches**: `Scene.preload("level_2")` loads a scene's assets in the background while the player is still busy; `preload_progress` says how far it got.
- **Spawning at runtime**: `Scene.instantiate` places a component (a bullet, an enemy) with its script properties set; `Scene.create` makes a node of a built-in or custom type.
- **Lighting the scene**: `Scene.set_ambient(r, g, b)` sets the colour where no [Light](../nodes/LightNode.md) reaches - dark for a cave, white for an unlit scene.
- **Loading screens**: in the loading screen's script, `loading_progress` drives a progress bar and `loading_target` names the scene being loaded.

## Example

An exit door that loads the next level in the background and fades to it when the player walks in; the script is on an [Area](../nodes/AreaNode.md) at the door.

```lua
---@class Exit : ScriptInstanceBase
local Exit = {}

Exit.properties = {
    next_level = { type = "string", default = "level_2", label = "Next Level" }, -- a scene name
}

function Exit:ready()
    self.leaving = false
    Scene.preload(self.next_level)
end

---@param other Node?
function Exit:on_body_entered(other)
    if self.leaving or not other or not other:has_tag("player") then return end
    if Scene.is_transitioning() then return end
    self.leaving = true
    Log.info("leaving " .. Scene.get_name() .. ", preloaded "
        .. math.floor(Scene.preload_progress(self.next_level) * 100) .. "%")
    Scene.change_scene(self.next_level, {transition = "fade", duration = 0.4, color = "#000000"})
end

return Exit
```

## Notes

- `find_node` returns the first node with that name - give nodes you look up unique names. Look nodes up in `ready()` and keep them, rather than every frame.
- `change_scene`, `preload` and `preload_progress` take a scene's name or its file (a `scene` script property). An unknown one logs an error and nothing changes. `reload` uses the project's default transition, like `change_scene` without options.
- A change asked for during a transition waits for it. The global event bus ([Events](../../engine/docs/events.md)) gets `transition_started`, `transition_midpoint` and `transition_finished` with the scene's name. See [Changing scenes](../../engine/docs/scene_flow.md) for every transition and option.
- `Scene.create` and `Scene.create_node` return nil (with a warning) for an unknown type.
- `instantiate` and `create` take a position local to the parent - two numbers or a Vec2.
