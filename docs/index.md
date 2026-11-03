# Rayzr documentation

Rayzr is a 2D game engine with a full editor. You build scenes from nodes in
the editor, write gameplay in Lua 5.4 (it reloads while the game runs), and
export standalone games for macOS, Windows, Linux and the web - no compiler
needed.

## Where to start

| If you want to... | Read |
|---|---|
| Install the editor | [Installation](getting-started/installation.md) |
| Make something that plays in ten minutes | [Your first game](getting-started/first-game.md) |
| Start from a complete small game | [Templates](../templates/README.md) |
| Learn step by step, one project at a time | The [tutorials](tutorials/index.md): Lua scripting basics, physics and collisions |
| Find your way around the editor | [Editor tour](editor/tour.md), then the [editor manual](../editor/README.md) |
| Write scripts | The [scripting guide](../engine/SCRIPTING.md) and the [Lua API reference](#reference) |
| Learn one feature in depth | The [engine guides](../engine/docs/README.md): cameras, paths, navigation, audio, animation... |

## Reference

- **Nodes**: every node type with its properties, defaults, Lua methods and
  a scene-file example (in the sidebar under *Reference > Nodes*).
- **Lua API**: every module and function scripts can call, each with an
  example (*Reference > Lua API*).
- **Editor plugin API**: extend the editor itself in Lua.

These reference pages are generated from the engine's own code - the node
registry, the Inspector's property help and the Lua definitions the Code
tab uses for completion - so they always match the version you are reading.

## Versions

The version picker at the top of the sidebar switches between the latest
release, the two before it and the latest development build. Each version's
docs are built from that version's source.
