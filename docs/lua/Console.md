## Use it for

- **Cheats and shortcuts while testing**: `Console.register("give", "give <item> [count]", fn)` adds a command; typing `give sword 3` calls `fn({"sword", "3"})`. What the function returns is printed.
- **Poking at the running game**: anything that isn't a command runs as Lua in the game: `Scene.find_node("Player"):get_position()`, `GameState.lives = 9`.
- **Seeing what's going on**:
  - `perf` shows frame times and node, body and draw counts.
  - `physics`, `nav`, `camera` and `outlines` draw collision shapes, navigation regions, the camera's view and limits, and every node's bounds.
- **Slowing things down**:
  - `pause` freezes the game, and `step` (or `step 10`) runs one frame (or ten) at a time.
  - `timescale 0.25` runs everything in slow motion; `timescale 0.25 enemy` slows only nodes tagged *enemy*.
- **Getting around**: `scene level_3` goes to a scene, and `reload` restarts the current one.

## Example

A global script that adds a few cheats, but only in builds that have the console.

```lua
---@class Cheats : ScriptInstanceBase
local Cheats = {}

function Cheats:ready()
    if not Console.is_enabled() then return end

    Console.register("god", "god: the player takes no damage", function()
        GameState.god = not GameState.god
        return GameState.god and "god mode on" or "god mode off"
    end)

    Console.register("lives", "lives <n>: set the player's lives", function(args)
        local n = tonumber(args[1])
        if not n then return "lives: a number, e.g. lives 5" end
        GameState.lives = n
        return "lives = " .. n
    end)

    Console.register("warp", "warp <x> <y>: move the player there", function(args)
        local player = Scene.find_node("Player")
        if player then player:set_position(tonumber(args[1]) or 0, tonumber(args[2]) or 0) end
    end)
end

return Cheats
```

## Notes

- **Where it is**: debug builds and the editor's Play always have the console. Release exports have it only when **Project Settings > General > Developer Console > In Release Builds** is on. Everywhere else the `Console` calls do nothing.
- **The key** is ` (backquote) unless the project picks another under **Developer Console > Key**. Esc clears the line, then closes the console.
- **Keys while typing**:
  - Up and Down go through earlier lines, and Tab completes a command's name.
  - Page Up, Page Down and the mouse wheel scroll.
- **While the console is open the game gets no keys** (`Input.is_action_down` and `Input.is_key_down` read up), so typing doesn't move the player. The game keeps running unless you `pause` it.
- `Log.info`, `print`, warnings and script errors all show in the console, coloured by level. `Console.print` writes only there.
- `help` lists every command, and `help <command>` shows one.
