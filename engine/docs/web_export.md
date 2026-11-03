# Web export

Games export to the web as a folder you can upload anywhere that serves
static files (itch.io, GitHub Pages, your own site):

```
Browser/
├── index.html      the page: a start screen, then the game in a canvas
├── index.js        emscripten's loader
├── index.wasm      the engine (Odin) + raylib + Lua + Box2D, compiled to WebAssembly
├── odin.js         Odin's browser runtime
├── game.rayzr      your game (the same package the desktop exports use)
├── fonts/          the UI font
└── favicon.png     your project icon (when it has one)
```

## Exporting

1. **Project Settings > Export**: add a preset with platform **web** (or
   tick **web** among the targets). Its window title becomes the page title.
2. **Save and Export This Preset** (or **File > Export > Standalone Game**).
3. **File > Export > Open Web Export in Browser** serves the folder on
   `http://127.0.0.1:8765/` and opens it - browsers don't run WebAssembly
   from `file://` pages, so double-clicking index.html doesn't work.

To publish on **itch.io**: zip the folder's *contents*, upload it as an
HTML project, tick "This file will be played in the browser".

## In the browser

- **Click to play**: browsers only allow sound after a click (or key), so
  the page shows a start screen. `index.html?autostart` skips it (kiosks;
  sound may stay off until the page is clicked).
- The game fills the window and keeps its virtual resolution (letterboxed),
  like the desktop runner.
- **Saves** (`Save.*`, input bindings, accessibility settings) go to
  `/save`, kept in the browser's IndexedDB - they survive reloads, per site.
  `Save` data is written on `Save.flush()` and when the tab is hidden; the
  page copies `/save` to IndexedDB every 2 seconds and on hiding.
- Keyboard, mouse, gamepads (the browser's Gamepad API), audio (all
  formats, the mixer and its effects), Lua scripts, physics, shaders
  (materials, post effects, lighting - converted to WebGL 2's GLSL ES 300),
  sprite atlases and QOI textures work as on the desktop.

## Not on the web

- Threads: textures decode on the main thread (loading screens still
  report progress, but a big preload stalls frames).
- Files outside the package, directory listings, `Engine.quit()` (a page
  can't close itself), the native file dialogs.
- Hot reload and the editor link (Play in the editor runs the desktop game).

## The web runner (for engine developers)

Exporting copies a **prebuilt runner** - no compiler is needed. The runner
is built once with emscripten:

```sh
brew install emscripten          # (or the emsdk)
scripts/build_web_runner.sh      # -> bin/runners/web/
```

It downloads and builds raylib 5.5 (WebGL 2), Lua 5.4.7 and Box2D 3.1.1 with
emcc (once, into `bin/web_deps/`), compiles the engine for `js_wasm32`
(`scripts/web_prepare.py` makes a patched copy of the sources: the web
versions of a few packages, below) and links it with the page shell
`scripts/web/shell.html`. `scripts/build_runners.sh` builds it too when
emcc is installed.

**Shipping the editor**: put `runners/web/` (the four runner files) next to
the editor, like `runners/macos/` etc. Users then export to the web
without installing emscripten or Odin.

How the engine runs on the web:

| | Desktop | Web |
|---|---|---|
| Main loop | `Engine_RunProject` loops | the page calls `main_update` each animation frame (`Runner_Start` / `Runner_Frame` / `Runner_Stop`) |
| Files | `core:os` | `engine/osx` (emscripten's libc over its file system); `engine/pathx` for paths |
| Memory | the C heap, virtual-memory arenas | emscripten's malloc (`Engine_HeapAllocator`, `Engine_DefaultContext`), malloc arenas (`engine/vmemx`); built with `-default-to-panic-allocator` so nothing grows memory behind emscripten's back |
| Lua bindings | `engine/lua54` (Odin's vendor bindings, copied) | the same, linking the emcc-built Lua |
| Shaders | GLSL 330 | `Shader_Port`: GLSL ES 300 |
| Texture decoding | worker threads | the main thread |

`node scripts/web/capture.mjs URL out.png [seconds]` runs a page in
headless Chrome and prints its console - the web test drive uses it.

## Limits

- WebGL 2 is required (every current browser).
- The web build compiles a patched copy of the `ui/` package; if that
  package gains new OS-specific code, `scripts/web_prepare.py` may need a
  new patch.
