# TODO_NOW

Work list for the engine + editor, in order. Each item: code, test (engine
test and/or editor drive), verify (screenshots for UI), document, commit.
Multithreading (job pool, Box2D tasks, background loading) is deliberately
out of scope here.

## Phase 1 — Quick wins

- [x] 1.1 Editor viewport renders in one tree pass (`Scene_CollectRenderables`), not one walk per layer
- [x] 1.2 Culling: skip nodes whose bounds are outside the camera view (game and editor); tile maps and LDtk draw only visible tiles
- [x] 1.3 Lua language server: ship engine definitions with the editor (not the repo checkout); write `.luarc.json` into each project
- [x] 1.4 Generated project types (`.rayzr/project_types.lua`): input action names, scene/asset paths, node names per scene, script classes with their properties, signals, LDtk entities/enums/levels, components

## Phase 2 — Core engine features

- [x] 2.1 Shaders & materials: per-node material (shader + uniforms), blend modes, Inspector editing, Lua `set_shader_param`
- [x] 2.2 2D lighting: light map render target, point/spot lights, ambient colour, occluder shadows from collision shapes; normal maps later
- [x] 2.3 Tweens & easing: `Tween.to(node, "position", {x, y}, 0.3, "out_quad")`, easing curves on animation tracks
- [x] 2.4 Animation tracks: method-call and audio tracks, blending/crossfade between animations
- [x] 2.5 State machine node: states, transitions, conditions, Lua `on_enter_<state>`/`on_exit_<state>`, drives the AnimationPlayer
- [x] 2.6 Save/load: `Save.set/get/flush` JSON in the platform user-data folder

## Phase 3 — Export

- [x] 3.1 Prebuilt runners per platform shipped with the editor; export copies the runner + `.rayzr` (no compiler needed), name and icon
- [x] 3.2 macOS `.app` bundle (Info.plist, icon, `.rayzr` in Resources, universal binary); optional codesign/notarize step
- [x] 3.3 Windows packaging (icon, version info, no console in release); Linux AppImage
- [x] 3.4 Web (emscripten): raylib + Box2D + Lua to wasm, `.rayzr` preloaded, click-to-start audio (done as roadmap 5: the prebuilt web runner; `web_export` drive)
- [x] 3.5 Export presets per target (icon, version, window, include/exclude, debug/release) in `project.json`

## Phase 4 — Performance (single-threaded)

- [x] 4.1 Node diet: event subjects out of every node (side table), shared vtables, per-type pools instead of an arena per node; split hot transform data
- [x] 4.2 Batching: sort draws by texture per layer, texture atlases, cache static LDtk/tile layers in render textures
- [x] 4.3 `#soa` + SIMD for particles and tile layers (verify the `#soa` compiler issue first)
- [x] 4.4 Editor: incremental undo/modified tracking (change counters, not whole-scene JSON); cache per-frame inspector/LDtk work
- [x] 4.5 Extend `bench_scene_hot_paths` to rendering and scripts; record baselines in GAPS.md

## Phase 5 — Engine features (rest)

- [x] 5.1 Audio: positional audio, bus mixer (volume, low-pass/reverb), music crossfade, one-shot pooling
- [x] 5.2 Physics: joints as editor nodes, one-way platforms for StaticBody, named collision layers
- [x] 5.3 Navigation: A* on tile maps / LDtk grids
- [x] 5.4 Text: bitmap/SDF fonts, rich text, dialogue box; localization string tables
- [x] 5.5 Scene flow: transitions, background scene loading (main thread, incremental), pausing subtrees
- [x] 5.6 Extras: parallax node, 9-slice sprite, trail/line renderer, screen-space post effects

## Phase 6 — Editor workflows & UX

- [x] 6.1 Tooltips & docs on every Inspector property (type, range, doc from tags); Inspector help pane
- [x] 6.2 Multi-edit (mixed values shown as —)
- [x] 6.3 Viewport: rulers/guides, smart snapping to node edges/centres, pivot editing, per-node lock/hide, show-all-colliders
- [x] 6.4 Scene tree: search by type/tag, groups/tags, reorder by drag, cross-scene copy/paste
- [x] 6.5 Asset browser: thumbnail grid, real folders (create/move/rename with reference updates), find usages, per-asset import settings
- [x] 6.6 Sprite-sheet slicer → frame animations
- [x] 6.7 Play-in-editor: remote scene tree of the running game, frame step, hot reload while playing
- [x] 6.8 Layout presets / workspaces and reset layout
- [x] 6.9 Welcome / new-project window with templates; icons for every node type; empty-state guidance

## Phase 7 — Code editor & Lua

- [x] 7.1 Node subtypes in definitions (`TextureNode`, `CameraNode`, …) so methods complete per type
- [x] 7.2 Definitions checked against the registered Lua bindings (test fails on drift)
- [x] 7.3 Per-line token cache keyed on buffer version; measure with a 10k-line file
- [x] 7.4 Overlays: hover / signature / completion docs as bounded, wrapped, scrollable popups clamped to the editor
- [x] 7.5 Lua debugger: breakpoints, stepping, locals (debug hooks)

## Phase 8 — Lua integration (2026-10-23)

Autocomplete and type safety
- [x] 8.1 Typed `get_script()`: returns the script's generated class (methods, fields)
- [x] 8.2 Event names complete in `connect` / `emit` (engine events per node type + custom ones scripts emit) and `on_<event>` methods
- [x] 8.3 Typed `get_property` / `set_property` paths per node class
- [x] 8.4 Typed `get_node("path")` (paths relative to each script's nodes)
- [x] 8.5 Asset / scene / action aliases on more API parameters
- [x] 8.6 Diagnostics: Lua runtime errors as squiggles in the Code tab (Play / Simulate); warnings for unknown node paths / property names

Drag and drop, editor ↔ code
- [x] 8.7 Drop an animation / input action / scene / sound into code
- [x] 8.8 Drop a Signals-panel event row into code: a `connect` with the handler signature
- [x] 8.9 Drop a node onto a method: a `connect` to one of its events
- [x] 8.10 Node-reference exported properties (`type = "node"`, Inspector picker); dropping a node on the `properties` table adds one
- [x] 8.11 Rename-safe references: renaming / moving a node offers to update `get_node` / `find_node` in scripts
- [x] 8.12 Code → scene: Cmd+click a `get_node("...")` path selects the node; find a script's usages

Exported properties
- [x] 8.13 More types: enum, range/slider, array, curve, gradient, colour alpha; `group` / `header`, `tooltip`
- [x] 8.14 `---` comments above a property become its help-pane text
- [x] 8.15 Live editing of exported values in the running game (Game tab)

Engine API
- [x] 8.16 Vec2 / Vec3 / Vec4 types with operators, used by the API
- [x] 8.17 Property-style access (`self.node.position = ...`), old methods kept
- [x] 8.18 Spawning: `Scene.instantiate(component, parent, x, y)` (typed root), `node:queue_free()`
- [x] 8.19 Global scripts (autoloads) in Project Settings, reachable from every script; globe marker in the asset browser
- [x] 8.27 Resources (#46): data assets of a Lua class (`Class.resource = {...}` marker, `resources/*.resource.json`); `type = "resource"` properties, `Resource.load` / `new`, `duplicate`, `on_load`; shared or one per component instance (`local_copy`); hot reload; Assets section, New Resource, Resource Class template; Inspector editing saved on release with undo; typed completion - engine/docs/resources.md
- [ ] 8.28 Resources, next: drop a resource onto a property field, an Open button, help-pane text; resources inside resources; resources embedded in scenes; per-instance values without a second file
- (on hold) coroutines (`wait` / `await` / `tween`) - not wanted yet; (not chosen) lifecycle hooks

Script authoring
- [x] 8.20 New-script templates (character, enemy patrol, UI menu, pickup, door/trigger)
- [x] 8.21 Snippets (Tab-expanded): ready, update, connect, properties, tween
- [x] 8.22 Attach by dropping a `.lua` onto a scene-tree node
- [x] 8.23 Lua console: evaluate expressions in the simulating / running game
- [x] 8.24 Debugger: watch expressions, conditional breakpoints

Docs in place
- [x] 8.25 Every API function documented in `engine_api.lua` (description + example) for hover
- [x] 8.26 F1 on an API symbol opens its section of the scripting reference in the editor

## Phase 13 — Engine improvements (2026-10-25)

Brainstormed 2026-10-25, most important first (export targets left out).
Decisions (2026-10-25): E.1 reports go to a prefilled GitHub issue (no
server; games: local crash log + a developer hook). E.2/E.4 art: CC0 packs
(Kenney); docs on GitHub Pages. E.3 is our own reader from the spec (the
aseprite/ source is EULA-licensed: reference only, never copied or linked).
E.4 started with a time-boxed raylib-on-SDL trial: blocked (vendor:raylib
can't link another raylib build), so the native rumble layer (XInput /
GameController / evdev) it is - engine/docs/gamepads.md.
Each item's PR is merged once local tests + CI pass.
Each item: a feature branch, tests + drives, docs, a PR merged when CI is
green (its dev build: RELEASING.md).

Rebrand (2026-10-25):
- [x] B.1 Ore / odin_raylib_engine -> Rayzr: names in code, docs, tests, CI, packages (rayzr-editor-*, Rayzr Editor.app, com.rayzr.*), the .rayzr package (magic RYZ1; ORE1 / .ore still read), projects' .rayzr/ (old .ore/ moved on open), ~/.config/rayzr_editor (moved from ore_editor), Lua Project.export_rayzr (export_ore kept); the icon (branding/, scripts/branding/make_icons.odin) in the macOS .icns, the Windows .exe (icon.ico, written in after linking: scripts/branding/set_exe_icon.odin), deb / AppImage, the window, the Welcome window, the docs site; exported games without an icon get it; the GitHub repo is bcrowe306/rayzr

High impact (now):
- [x] E.1 Crash and bug reports (roadmap 22): editor panics / Lua errors write a crash file (version, platform, stack, log tail, recent actions), offered on the next start (a prefilled GitHub issue); exported games write crash logs to the user-data folder, with an optional developer hook - done: engine/crash_report*.odin (panics, signals, Windows exceptions; unwinder stacks, recent lines), editor/crash_reports.odin (offered on the next start, Report on GitHub, Help > Report a Bug), the Crash Lua module, scripts/test_crash.sh (CI), crash_report drive, engine/docs/crash_reports.md
- [x] E.2 Starter templates, sample games, docs site: New Project templates (platformer, top-down RPG, shmup, puzzle), 2-3 larger samples, guides + the Lua API reference published by CI - done: templates/ built by scripts/templates/make_templates.py (Kenney CC0 art + pixel font), played by test_templates.py (runner --input-script; CI), levels proven finishable (find_route.py, runner --trace) / solvable (a Sokoban solver); samples Platformer Adventure + Asteroids; Welcome cards with previews; docs site (scripts/docs/build_site.py, MkDocs, GitHub Pages, generated Lua API reference); engine fixes found on the way (component tags, int properties from scenes, set_texture on new nodes, smooth-camera UI alpha, create_node log, hex colours in set_property)
- [x] E.3 Aseprite import (aseprite/ submodule as the reference, format: aseprite/docs/ase-file-specs.md): .ase / .aseprite read directly - every chunk (layers incl. groups / blend modes / opacity, cels incl. linked / compressed / tilemap cels, tags with direction / repeat, frame durations, slices with 9-patch / pivot, palettes, tilesets, user data); tags become animations, re-import on save - done: engine/aseprite.odin (reader), aseprite_render.odin (compositor + Aseprite's MIT blend functions; pixel-identical to Aseprite on our fixtures and its 20 test sprites), aseprite_resource.odin (shared, live reload; any image path), AsepriteNode (tags, directions, repeats, durations, layer overrides, pivot slice, events, Lua), TileMapNode from a tilemap layer; editor: assets, drop, Inspector section with preview, Edit in Aseprite; tests/aseprite fixtures + references made by Aseprite (scripts/aseprite_fixtures.sh), aseprite drive, runtime suite; engine/docs/aseprite.md
- [x] E.4 Full gamepad support (roadmap 20): several controllers with player assignment, hot-plug, rumble, controller-specific button prompts (Input.glyph) - done: the SDL trial was blocked (Odin's vendor:raylib links its own GLFW raylib; SDL would mean forking the bindings for engine / editor / ui), so a native layer: engine/input_players.odin (4 players, per-player actions, assignment + swaps, hot-plug -> on_gamepad_connected / _disconnected, devices from pad names, simulated pads), input_rumble_*.odin (XInput / evdev FF_RUMBLE / GameController + CoreHaptics / web), input_glyphs.odin (Kenney Input Prompts embedded; "prompts:<family>/<name>" image paths; Input.glyph follows the last device), Lua API with optional player args; runner --input-script pad events; Project Settings > Input shows prompts; tests (engine, tests/gamepads runtime suite in CI, gamepads drive); engine/docs/gamepads.md

Next:
- [ ] E.5 Automated tests for game code: a headless test runner stepping scenes, a Lua test API (press, step, expect), input record / replay, run in CI
- [ ] E.6 In-game developer console (debug builds): Lua console + registered commands, perf overlay, debug-draw toggles, slow motion / frame step
- [ ] E.7 Editor auto-updater: download the newer package, verify the checksum, replace and restart
- [ ] E.8 Team-friendly scenes: stable node ids + sorted keys (small diffs), a scene merge tool, a git panel

Later:
- [ ] E.9 Multiplayer (roadmap 21): local co-op first, then client-server (replicated nodes, RPCs); rollback separately
- [ ] E.10 Runtime mods: sandboxed Lua in exported games, mod folders, asset overrides (reuses the plugin host)
- [ ] E.11 Multithreading: a job system for physics / particles / animation / culling, when a real game needs it
- [ ] E.12 Plugin and template registry: browse community plugins / templates in the editor (a GitHub index)
- [ ] E.13 Single-binary exports: game.rayzr + font appended to the runner on Windows / Linux (a footer: offset + magic; Windows signed after appending), macOS keeps the .app (Resources: signing-safe); an export option

## Phase 14 — 2D vector art: Flash-style characters (2026-10-25)

Goal: characters drawn and animated as vectors the way Flash / Adobe Animate
did it - crisp at any zoom / resolution, symbols with swappable parts
(mouths, hands, eyes), shape tweens, bones bending vector shapes - drawn in
the editor or imported from Inkscape / Illustrator / Affinity / Animate.
Decided (2026-10-25): Flash-style characters first; neon-arcade glow and
destructible boolean terrain are secondary.

Constraints: raylib is OpenGL 3.3 and macOS has no compute shaders, so no
Vello-style GPU rasterizer - tessellate on the CPU (or NanoVG's
stencil-then-cover) and cache the meshes. Every item: integration with
nodes / animation / skeletons / Lua, performance (cached meshes, transforms
in the vertex shader, instancing, flat vertex arrays), safety (leak / UAF
tests, arenas for per-frame tessellation), docs with tutorials, tests + drives.

Decided (2026-10-26):
- Import first: art comes from Inkscape / Illustrator / Affinity SVGs (the user's own files are the fixtures); Rayzr does symbols, rigging, animation; in-editor drawing tools later.
- Symbols first, bones later: Flash-style symbol timelines, part swapping, lip-sync before vector skinning.
- Dozens of characters on screen at 60 fps, web export included.
- Renderer: our own tessellator on rlgl, not vendor:nanovg (NanoVG uses its own GL loader, has no web build, re-tessellates every frame, gives no meshes for skinning or collision). Flatten, normalize fills with Clipper2 (C export bound like Box2D / Lua, web build too), triangulate with earcut, expand strokes, feathered-fringe anti-aliasing, a gradient shader; cached meshes, matrix-only transforms, instancing, worker-thread re-tessellation into frame arenas.
- SVG: our own parser on core:encoding/xml. Animation: symbols carry nested timelines in the asset; AnimationPlayer drives the top level.
- Milestone order: M0 spike (rlgl path in viewport / game / web runner, a benchmark: a complex character x 100) -> M1 core (V.1-V.3) -> M2 assets (V.4, V.5) -> M3 characters (V.6-V.8) -> M5 characters II (V.9-V.11) -> M6 geometry (V.15, V.16) -> M4 editor tools (V.12-V.14) -> M7 extras (V.17-V.19; Animate import stays last). Each milestone: a branch + PR merged when green, golden-image render tests, drives, guide + Lua docs, features.json.

Foundation:
- [x] M0 spike - done 2026-10-26: engine/vector_path.odin (paths, flattening by Wang's formula), vector_earcut.odin (earcut 2.2.4 port, z-order hashed), vector_tess.odin (fills with holes by nesting, strokes with miter / round / bevel joins and butt / round / square caps, one-pixel feathered fringes, hairlines), vector_mesh.odin (caches per power-of-two scale bucket, GPU meshes split at 65535 vertices, an immediate rlgl path), VectorShapeNode with presets (Star, Ring, Badge, Character); measured: 100 benchmark characters 1.7 ms/frame cached on the GPU vs 56 ms through the batch, tessellation 0.16-0.57 ms per character; proven in the runner (golden images, tests/vector), the editor viewport (vector_shape drive) and the web runner (scripts/web/test_project.sh); scripts/pack_rayzr.odin, golden-image support in test_templates.py (png_diff.py); engine/docs/vector.md
- [x] V.1 Vector data model (done in M0 / M1, 2026-10-26: paths, styles, solid / linear / radial paints with stops / spread / transform, strokes with joins / caps / miter / dashes, fill rules, opacity, clip paths; the native .vec.json asset format moves to M3 (symbols and timelines need a format the editor writes); soft masks to M5) - paths (move / line / quad / cubic / arc / close), shapes = path + fill + stroke, groups with transforms; fills (solid, linear / radial gradients, image patterns, opacity), strokes (width, miter / round / bevel joins, butt / round / square caps, dashes, miter limit), non-zero / even-odd fill rules (holes), clip paths / masks; a native asset format (`.vec.json`) the editor writes, SVG being the import format
- [x] V.2 Renderer (done in M0 / M1: our own tessellator, not nanovg - Clipper2 normalization, earcut, feathered fringes, cached GPU meshes, a gradient shader; clips are geometric (Clipper2) instead of stencil masks, which render textures lack) - curve flattening with a screen-space tolerance (re-flattened only when zoom changes enough), fill triangulation (earcut / libtess2-style for holes and self-intersections) or stencil-then-cover, stroke expansion (joins, caps, dashes), analytic edge anti-aliasing (NanoVG-style feathered fringe, no MSAA needed), gradient / pattern shaders, stencil masks. Evaluate Odin's `vendor:nanovg` first as a fast path (flush raylib's batch with rlDrawRenderBatchActive, restore GL state after); keep our own tessellator if it doesn't fit caching / instancing
- [x] V.3 Immediate-mode vector API (done in M1: on_draw + the Vector module, cached by a hash of the drawing; Vector_Canvas_* from Odin) - canvas / NanoVG-style begin_path / move_to / line_to / bezier_to / arc / close / fill / stroke / set_fill (colour, gradient) / set_stroke / save / restore / transform, usable from on_draw; engine_api.lua docs with examples
- [x] V.4 VectorShapeNode (done in M0 / M2, 2026-10-26: cached meshes per scale bucket shared by every node of an asset (repeated copies share one GPU mesh instead of hardware instancing), tint, culling bounds, exact picking, background tessellation on 2 worker threads) - draws a vector asset with cached meshes (static GPU buffers; only matrix changes on move / rotate / scale; re-tessellated on shape edits or large zoom changes), per-instance tint / alpha, instancing for repeated shapes, tessellation of dirty shapes on worker threads into a per-frame arena; picking by the shape (point-in-path), bounds for culling / visibility notifiers
- [x] V.5 SVG import (done in M2: engine/vector_svg.odin + editor/vector_editor.odin; fixtures shaped like the four tools' exports; vector_scale / origin import settings; the user's own SVGs still to add as fixtures) - nanosvg-style parser (path, rect, circle, ellipse, line, polyline, polygon, g, transform, use / defs, linear / radial gradients, style / presentation attributes, opacity, clip paths), groups become sub-shapes / layers; import settings (scale, origin / pivot, merge layers) in `<asset>.import.json`, live reload on save, Assets preview; real files from Inkscape / Illustrator / Affinity / Figma as test fixtures

Flash-style characters:
- [x] V.6 Symbols and instances (done in M3, 2026-10-26: a symbol is a named SVG group drawn by a Vector Shape's `group` ("head/mouth" paths), instances share its meshes with their own transform / tint / brightness / colour offset (`colorAdd`, in the vector shader); saving the SVG updates every instance; a symbol with its own timeline is a component with an Animation Player; Explode into Parts makes a Vector Shape per child group; the native .vec.json format moves to M4 with the drawing tools) - Symbols and instances (Flash's library): a vector asset can contain named symbols (reusable groups with their own timeline); instances in a character with their own transform, colour effects (tint, brightness, alpha, advanced colour transform) and first-frame / loop / play-once modes; editing a symbol updates every instance
- [x] V.7 Part swapping (done in M3: `frame` picks a child group with the symbol's stable box, the Inspector's Frame picker, `node:vector_swap(name)` / `vector_frames()`, hidden layers (display:none) imported as frames; LipSyncNode reads Rhubarb TSV / JSON cues beside the sound, mapping for other charts (Preston Blair), Rhubarb's fallbacks, follows a DialogueNode line's voice by its playback time) - Part swapping: swap sets for mouths / hands / eyes / expressions (a symbol's frames chosen by name or index), keyable on the animation timeline and settable from Lua (`vector_swap(node, "mouth", "O")`); lip-sync mouth charts (Preston Blair set: A-I, O, U, E, L, WQ, MBP, FV, rest) driven by dialogue / subtitle lines or a phoneme file (Rhubarb Lip Sync output)
- [x] V.8 Vector timeline animation (done in M3 on the existing animation editor: keys on part transforms, brightness, colour offset, tint, zIndex and `frame` (new frame keys hold: the Constant ease), hold / on-twos keys are Constant keys; vector frame-by-frame drawing comes with M4's tools) - Vector timeline animation: keyframes on symbol instances (transform, colour effect, swap frame, visibility, draw order) in the existing animation editor, classic tweens with the existing easing / Bezier curves, frame-by-frame vector keys (hold frames, "on twos"), onion skin (exists) working with vector frames, labels / events
- [x] V.9 Shape tweens / morphing (done in M5, 2026-10-26: engine/vector_morph.odin - paths as cubics, segment counts evened, closed outlines turned the same way and started at the closest points (the automatic hint; manual shape hints wait for M4's editing tools), styles blended (solid <-> gradient too), extra shapes shrink / fade; VectorShapeNode morphTo / morph, trimStart / trimEnd / trimOffset / trimEach; the Inspector's Morph to picker) - Shape tweens / morphing: interpolate one path into another (point correspondence by resampling to the same point count, shape hints to pin matching points like Flash), fill / stroke / gradient interpolation; trim paths (animate a stroke's drawn start / end) for draw-on lines and effects
- [x] V.10 (done in M5, 2026-10-26: engine/vector_skin.odin - a Vector Shape under a Skeleton bends with the bones its skinBones names ("*" = all), bound in the setup pose by distance to the bones (up to 4 per vertex, skinSmooth px of blending round joints; long triangles split first), weights in the mesh's spare attributes, per-frame bone matrices as uniforms in a skinned vector shader (CPU path for immediate mode), re-bound only when bones / smoothing / placement / tessellation change; IK and animations drive it; a four-corner warp (warpTopLeft ... warpBottomRight) on any Vector Shape in the same shader; picking and culling follow the bend; bones-only Spine rigs load (no atlas) and are listed; the Inspector's Bend with picker; tests, golden scene (GPU + immediate, web checked), 100-limb benchmark 1.3 ms, the vector_skin drive, docs; painted weights / path-point binding left for later) Vector skinning on the skeletal runtime (item 7): vector shapes as SkeletonNode attachments (tessellated meshes weighted to bones, deformed in the vertex shader), path points bound to bones (smooth bending of limbs without visible joints), IK (exists) on vector rigs, mesh warp / free-form deformers for squash and stretch
- [x] V.11 (done in M5, 2026-10-26: engine/vector_filters.odin - drop shadow, glow, outline (dilate; cel-shading look), blur, saturation / contrast / hue as shader passes into a per-node texture made before the frame (game and editor viewport), remade only when the art / zoom / scale / a filter / colour effects change, drawn as one rotated / flipped quad; lineScale Constant keeps outline widths at any node scale (re-tessellated per 1% of scale); tests, a golden scene, the vector_filters drive, docs; bevel and an arbitrary colour matrix left out) Character effects: per-instance filters like Flash's - drop shadow, glow, blur, bevel, colour matrix - as cheap shader passes (render the character to a texture once when filters are used), line-weight scaling options (strokes scale with the character or stay constant thickness), outline / cel-shading strokes

Editor:
- [ ] V.12 Vector drawing tools: pen (Bezier with handles), node editing (smooth / corner / symmetric points, add / delete / convert), primitives (rect with corner radius, ellipse, polygon, star), pencil / brush with curve fitting (freehand to smooth Beziers - the Flash brush feel), paint bucket on closed regions, snapping (grid, points, guides), layers and draw order
- [ ] V.13 Fill / stroke inspector: colour, gradient editor with stops and on-canvas gradient handles (Flash's gradient transform tool), stroke style, opacity, swatches / project palette; eyedropper
- [ ] V.14 Symbol workflow in the editor: Convert to Symbol, a Library panel (symbols per vector asset, previews, usage counts), double-click to edit a symbol in place (the rest dimmed), swap-symbol dialog, the timeline per symbol
- [x] V.15 (done in M6, 2026-10-26: engine/vector_ops.odin on Clipper2 - Vector_Polys (rings with holes), union / subtract / intersect / exclude of polygons or shapes, offsets, outline stroke (caps, joins, dashes), a drawing's covered area (fill rules, strokes, clip paths), Ramer-Douglas-Peucker simplify, flatten, cutting a drawing with paints kept (carving: vector_cut / vector_cut_polygon / vector_reset), convex decomposition (earcut + Hertel-Mehlhorn); the editor's boolean buttons come with V.12's tools) Path operations: boolean union / subtract / intersect / exclude, offset / outline stroke to fill, simplify, flatten (Clipper2-based); also the basis for runtime collision
- [x] V.16 (done in M6: engine/vector_collider.odin - VectorShapeNode.collider Solid (convex pieces, dynamic bodies too) / Outline (Box2D chain loops: terrain) with detail / friction / bounce / density, on the Static / Dynamic Body or Area above it or a static body of its own, remade only when the art changes (file, frame, morph, cut), overlay with the physics debug view; path queries on a shared Polyline (polyline.odin, PathNode uses it): vector_length / point_at / closest / contains, a Path Follow rides a Vector Shape; tests, a golden scene (web checked), the vector_collider drive, docs) Collision from vector shapes: flatten + convex decomposition into physics shapes (auto-regenerated when the shape changes), shown as an overlay; path queries (closest point, length, point / tangent at a distance) shared with PathNode

Text and import (later):
- [ ] V.17 Crisp text at any scale: MSDF font atlases for vector-style text, text on a path
- [ ] V.18 Adobe Animate import: XFL / uncompressed .fla (DOMDocument.xml: symbols, timelines, shapes with Flash's edge format, tweens) and/or Animate's SVG / texture-atlas exports; Lottie / Rive as possible extra formats
- [ ] V.19 Templates and docs: a vector character sample (rigged character with walk / idle / talk, swap sets, lip-sync), a "Drawing and animating a vector character" tutorial, engine/docs/vector.md

## Phase 12 — Distribution, CI/CD and export targets (2026-10-25)

Goal: users install the editor like any app (no compiler, no Homebrew, no
repo) and it exports to every desktop platform and the web from any of them;
tagged versions build and publish themselves.

Editor that runs anywhere:
- [x] D.1 Relocatable editor: resources found next to the executable (`Contents/Resources` in a .app) or in the source checkout; fonts and small files embedded (`#load`); no paths relative to the working directory
- [x] D.2 Play runs the prebuilt runner (the one export uses), no Odin compiler; the rebuild-on-change path only in a source checkout with `odin` installed
- [x] D.3 Lua 5.4 as a static library built from source (macOS uses Homebrew's dylib today), in the editor and the runners
- [x] D.4 (was R.1) libcmark for a released editor: the Scripting Reference's markdown (`editor/markdown_view.odin`, `vendor:commonmark`) links the system `libcmark` (`brew install cmark` on dev machines - `/opt/homebrew/opt/cmark/lib/libcmark.dylib`), which users won't have. Before shipping the editor, either
  - a) bundle it as a dynamic lib: copy `libcmark.dylib` (`.so` / `cmark.dll`) next to the editor (macOS: into the .app's `Frameworks`, `install_name_tool -change` to `@rpath/libcmark.dylib`, `-Wl,-rpath,@executable_path/../Frameworks` as `scripts/build_runners.sh` does for the runners), or
  - b) build cmark as a static lib (cmake `-DBUILD_SHARED_LIBS=OFF`, per platform; the vendor's `build.bat` does this on Windows) and link it in, so the editor has no extra file.
  The game runner doesn't use cmark.
  Or c) replace it: the markdown view uses a subset; a small Odin renderer removes the dependency.
- [x] D.5 lua-language-server built per platform and bundled (the Code tab's completion / diagnostics)
- [x] D.6 The editor ships the runners for every platform (`runners/{macos,windows,linux,web}`), so any editor exports every desktop target and the web
- [x] D.7 One version string (from the git tag) in the editor, the runner and each `.rayzr`; the runner warns about a project from a newer version
- [x] D.8 Third-party license notices bundled (raylib, Lua, Box2D, Dear ImGui, LuaLS, cmark, Open Sans, Font Awesome)
- [x] D.9 Check for updates against GitHub Releases (Help > Check for Updates, at startup unless turned off; status bar link; the auto-updater: #291, docs/editor/updates.md)

CI/CD (GitHub Actions):
- [x] C.1 CI on pushes / pull requests: build the editor, the runner and the Play binary, engine + ui unit tests, on macOS (arm64), Windows (x64) and Linux (x64)
- [x] C.2 Smoke test in CI: the runner plays the demo project and the packaged editor plays, exports and starts its language server (scripts/test_package.sh) - on Linux under Xvfb (hosted macOS runners have no GPU); editor drives stay local
- [x] C.3 Release workflow on `v*` tags: build the editor and runners per platform, put every platform's runners in each editor package, publish a GitHub Release with checksums
- [ ] C.4 macOS signing + notarization (Developer ID, hardened runtime, every dylib signed; certificates as repository secrets) - needs an Apple Developer account
- [ ] C.5 Windows code signing (Azure Trusted Signing or an OV certificate) - optional for early releases (SmartScreen warns without it)
- [x] C.8 Dev builds: every push to main that passes CI publishes a pre-release v<VERSION>-dev.<commit count> for every platform (release.yml on workflow_run; VERSION = the next release); dev-build editors check for newer dev builds; pre-release versions compare part by part (dev.10 > dev.9) - RELEASING.md
- [x] C.6 Linux glibc baseline: built on Ubuntu 22.04 (glibc 2.35: Ubuntu 22.04+, Debian 12+, Fedora 36+); Ubuntu 20.04 is past its standard support, so no older container
- [x] C.7 Packages: .dmg (macOS), .zip (Windows; an installer later if wanted), AppImage + .deb + .tar.gz (Linux) - checked with a dry run (release-dryrun branch): the CI-built app carries all four runners and passes scripts/test_package.sh

Export targets:
- [x] X.1 Linux .deb of the editor in releases (scripts/ci/deb_editor.sh; with the AppImage and .tar.gz). Not .rpm / Flatpak: the AppImage and .tar.gz run on those distributions, and games export as AppImages
- [x] X.2 Web polish: no worker threads on the web (textures decode on the main thread: async_decode.odin), so no COOP / COEP headers are needed; the runner is 3.2 MB of wasm (1.24 MB gzip, 0.98 MB brotli - hosts like itch.io serve it compressed)
- [ ] X.3 Steam (roadmap 19): Steamworks as a Lua module (achievements, overlay, cloud saves); Steam Deck (gamepad-first UI, 1280x800; the Linux runner, or Windows under Proton)
- [ ] X.4 Android (roadmap 18): NDK build, touch input, app lifecycle (pause / resume, GL context loss), assets read from the APK, signed AAB
- [ ] X.5 iOS (roadmap 18): raylib has no official iOS backend (a fork or Metal path), Xcode project, provisioning, App Store review
- [ ] X.6 Consoles (PS5, Xbox, Switch): not now - devkits under NDA, a renderer port per console (no raylib backends), unofficial Odin toolchains; keep the platform layer contained and the C dependencies portable

Testing:
- [x] T.1 Editor drives in the background and in parallel: hidden windows that never take the focus (editor and game `--hidden`), JOBS at a time, `# drive: serial` drives after the others (`scripts/editor_drive.sh`, VISIBLE=1 to watch)

## Phase 10 — State machines for gameplay (2026-10-23)

- [x] 10.1 Engine: on_update_<state>(dt), "script says" conditions, or-groups, child machines, history (sm_history), graph positions
- [x] 10.2 State Machine graph tab (add / connect / move / delete states, side panel, script callbacks)
- [x] 10.3 Live debugging: current state + fired transition (Simulate and Play), history, break on enter
- [x] 10.4 Lua / docs polish: generated types, drives, README

## Roadmap — 2D engine gaps (2026-10-24)

Numbers are the user's (referenced in comments).

Decisions (2026-10-24): 3 saves **.ldtk** directly (round-trips with the LDtk app; extras in LDtk custom fields). 24 = virtual cameras + host (many AdvancedCamera nodes with priorities; CameraNode hosts and blends) and must work with LDtk level / room linking (neighbours, room limits). 7 = own runtime + DragonBones / Spine importers + light editing (a rig editor may come later). 5: install emscripten with Homebrew; shipping the editor needs a way to bundle it (note for release packaging). A: buses route to master (or another bus); effects per bus.

Every feature: works with the rest of the engine and the editor (integration); memory layout / cache misses / rendering cost / parallelism considered (performance); leak and use-after-free checked, arenas where lifetimes are shared (safety); documented for the engine API and the editor, with examples / tutorials (docs). Tests + drives per feature.

Missing (all):
- [x] 1 Navigation: (A* on TileMap / LDtk grids existed) NavigationRegionNode (a rectangle baked from static physics shapes, solid tile maps, LDtk Solid cells; script-blocked cells for doors), agent radius via a clearance map (radius option everywhere), NavigationAgentNode (path following, repath interval, moves a CharacterMover / DynamicBody / node, separation avoidance, events); Lua; viewport cells / paths, Inspector Bake; guide with tutorials, test, drive
- [x] 2 Y-sort / depth sorting (top-down, isometric): zIndex (relative), ySort, ySortOffset; sorted in the one render walk (stable sorts only where used); picking follows draw order; guide engine/docs/draw_order.md, test, y_sort drive
- [x] 3 Level editor: root tabs **Game** / **Level** (Cmd+Shift+1/2); the Level tab edits LDtk projects in place (`.ldtk` + external `.ldtkl`) - an order-preserving JSON tree with LDtk's own formatter (byte-exact round trips), LDtk's auto-layer rule engine ported (JS double arithmetic, Perlin, stamps, flips, chance, modulo / checker, break on match, killed-by, optional groups, biomes; regenerates LDtk's tiles exactly on its 1.5 samples), toc / neighbours like LDtk; worlds and levels (add / delete / rename / move / resize / depth / colour / fields), IntGrid / Tiles painting (brush, rectangle, fill, erase, pick, stamps, flips, incremental rules), entities (place / move / resize / fields), definitions (layers, IntGrid values, entities and fields, enums, tilesets, rule groups and a rule pattern editor), terrain rules from a 3x3 block, per-tile custom data / enum tags, animated tiles (custom data `anim=` / `fps=`, played by the engine's LdtkLevelNode and the editors); undo (cell strokes, level / project snapshots, coalesced live edits); Ldtk_Doc engine API; guide with tutorials, tests, drive
- [x] 4 Paths: PathNode (Bézier points, baked polyline by distance, closest offset, drawn line), PathFollowNode (speed, Stop / Loop / PingPong, rotate, side offset, events); viewport editing (drag points / handles, double-click insert keeping the shape, Alt+click remove), Inspector points; CharacterMover rides moving floors; Lua path_* / follow_*; guide with tutorials, test, drive
- [x] 5 Web export: a prebuilt web runner (scripts/build_web_runner.sh: raylib 5.5 WebGL 2, Lua 5.4.7, Box2D 3.1.1 and zlib with emcc; the engine for js_wasm32 from a patched source copy) - exporting needs no compiler, ship runners/web/ with the editor; the engine runs per animation frame (Runner_Start / Frame / Stop), osx / pathx / vmemx web packages, malloc-backed allocators (built with -default-to-panic-allocator), vendored Lua bindings (64-bit numbers everywhere), GLSL 330 -> ES 300, synchronous decoding; page shell (click to play / ?autostart, IndexedDB saves, fonts, favicon, title); Web export target, File > Export > Open Web Export in Browser (local server); headless Chrome capture tool; guide, drive
- [x] 6 Visibility notifier: VisibilityNotifierNode (size, margin, action: pause / disable / remove the parent), screen_entered / exited, onScreen; per-manager notifier list, one pass after the transforms (game + Simulate); guide engine/docs/visibility.md, test, drive

Common:
- [x] A Audio mixer: our own mixer behind one raylib stream (sounds decoded to 48 kHz floats, music streamed from raylib's decoders; miniaudio's node graph can't link next to raylib's copy), buses (fader, pan, mute / solo, routing, up to 8 effects: EQ, low/high-pass, compressor, limiter, delay, reverb, distortion), meters; Sound / Music nodes' bus; project.json buses; Mixer tab (DAW strips, Master at the right, live over the link in Play); Lua Audio.* bus / effect API; guide with tutorials, tests, a real-device run, drive
- [x] 7 Skeletal / cutout animation: our own runtime (bones with shear and inherit modes, slots, skins, regions, weighted / linked meshes, 1-2 bone IK, rotate / translate / scale / shear / attachment / colour / draw order / event timelines, linear / stepped / Bezier curves, crossfades); Spine 3.8-4.2 JSON + .atlas and DragonBones 5.x _ske.json + _tex.json importers (axes / skew converted); SkeletonNode (shared counted data cache, events, finished, bone rotation overrides) and BoneAttachmentNode (in game and editor); Lua skeleton_*; Inspector (file / animation / skin pickers, preview play / scrub, bones list with highlight, attach); guide with a tutorial, test with hand-made fixtures, real renders, drive. (Rig editor: later)
- [x] 8 Object pooling: Pool.take / release / prewarm / set_max / stats, destroy() returns pooled nodes, on_spawn / on_despawn, bodies off while parked, per-scene pools freed on unload; Profiler rows; guide + tutorial engine/docs/pooling.md, test, drive. Also: Lua C callbacks now run with their script manager's context (Script_Context: the engine's allocator and logger - no more bad frees under the leak tracker; errors from Lua-triggered engine code are logged)
- [x] 9 Pixel-perfect rendering: Integer Scaling, Pixel Snap (camera + sprites), Smooth Camera (world in a margin texture shifted by the leftover fraction at the upscale; UI layers on top); Project Settings > Video; guide engine/docs/pixel_perfect.md, test, runner screenshots, drive
- [x] 10 Sprite atlas packing on export: Atlas in a texture's import settings; export packs the ticked textures (by filter; mipmapped / too big skipped) with MaxRects into pages up to 2048 px, 2 px gaps with edge extrusion, atlas/page_n.png + atlas.json (originals kept); the game mounts it from the package and atlased textures load as page + rectangle (pages refcounted), Texture_Size / Texture_Src / Texture_Full at every draw site (sprites, sheets, frame animations, nine-slice, parallax, tile maps), materials load their own copy; verified pixel-identical against the loose project; guide, test, drive
- [x] 11 Input rebinding: Input.listen (release-first, keys / mouse / pad buttons / sticks, conflicts clear / swap / allow, on_done), set / get / reset bindings, player-facing names, saved to input_bindings.json and loaded at start; gamepad UI navigation (D-pad / stick with repeat, A); Controls Menu template; Scene.create_node makes any node type; guide, tests, drive
- [x] 12 Scene transitions: (transitions + preload existed) loading screens (change_scene loading / min_time, Scene.loading_progress / loading_target, Game_ChangeSceneVia), textures decoded on worker threads (async_decode.odin; jobs owned by the decoder, abandon-safe), preload finds "texture" (it only read legacy "texture_path") and images named by properties; guide with a tutorial, tests, a real-game run

Editor:
- [x] 13 Editor plugins in Lua - designed 2026-10-25, built 13.1-13.7: editor/docs/plugins.md (project + user plugins, trust prompt + permissions, editor-only)
  - [x] 13.1 Plugin host: discovery, plugin.json, a Lua state per plugin, protected calls, on_load / on_unload, hot reload, Settings > Plugins
  - [x] 13.2 Trust prompt + permissions (per project, remembered)
  - [x] 13.3 A: commands (menus, palette, keymap), selection, scene, Editor.edit undo, create / destroy, assets + Editor.fs, dialogs
  - [x] 13.4 B: dockable panels + the `ui` widget set
  - [x] 13.5 C: events (selection, save, import, before Play, after export, project opened)
  - [x] 13.6 editor_api.lua definitions, Tools > New Plugin, guide + examples, drives
  - [x] 13.7 D: inspectors, viewport overlays / handles, importers
- [x] 14 Live remote scene tree in Play: (the Game tab's tree / text props existed) the Scene panel's Local / Remote view and the Inspector on the running game's node; typed live properties (drags, check boxes, colours, enum lists incl. script enums, ranges; throttled while dragging); enabled / visible toggles, Remove from Game, Pick (click in the game window; topmost node per layer space), amber outline of the selection in the game, Apply to Scene (undoable, Node_SetFromText); trees re-sent only when their hash changed; README, tests, drive
- [x] 15 Multiple open scenes as tabs: a tab per open scene / component document above the viewport (reorder, unsaved dot, tooltip, context menu), per-tab camera / selection / undo, close with Save / Don't Save / Cancel (unloads the scene, frees its undo entries; closed component documents reuse their scene), Cmd+W, Cmd+Alt+Right/Left, Ctrl+PageDown/Up, Ctrl+Tab; open tabs restored per project (.rayzr/open_scenes.json); README, drive
- [x] 16 Animation editor depth: (easing presets and method / sound event tracks existed) custom key curves (cubic Bezier editor with handles and presets, saved as a 7th key element, drawn on the timeline rows), method keys with an argument and a method picker from the target script, the player's animation_event signal, onion skin in the viewport (before / after counts, opacity, follows the player's own tracks, wraps looping animations); toolbar wraps in narrow panels; guide with tutorials, test, drive
- [x] 17 Per-asset import settings: `<asset>.import.json` next to the file (hidden in Assets, moved / copied / deleted with it, read through the package in exported games, cached per path in one arena): textures filter / wrap / mipmaps / slicing preset (the Sprite Sheet Slicer opens with it, Save Preset) / Export Keep or QOI (re-encoded into the package; loaders sniff QOI headers); audio gain (baked into decoded sounds, music volume) and default bus (nodes / Audio calls without one); old project.json texture_import still read and moved on the first change; preview panel rows (wrapping); guide with tutorials, test, drive. Also: two process-lifetime caches no longer show as leaks

Platform and shipping (later): 18 mobile export + touch, 19 Steam, 20 gamepad rumble / multiple controllers / glyphs, 21 networking, 22 crash reports.

Quality of life:
- [x] 23 Accessibility: settings per player (accessibility.json, over project.json defaults; Project Settings > Accessibility), UI scale (top-level UI elements grow around their nearest screen corner / edge / centre; UI input mouse in the same space), colour-blind filters (daltonize correction / simulate shader on the final frame; View > Colour Vision preview in the editor), subtitle track (dialogue / captions, size, backdrop), Dialogue Mode Subtitles with per-line voice sounds, Sound / Music captions, screen shake scale (both cameras), remappable controls (11); Lua Accessibility.* / Subtitles.*; Accessibility Menu template; guide with a tutorial, test, real-game screenshots, drive
- [x] 24 Advanced camera: AdvancedCameraNode virtual cameras hosted by the scene's CameraNode (highest priority shown, eased blends of position / zoom / rotation, a transient host when the scene has no camera); follow modes None / Glued / Simple (offset, damping, look-ahead) / Group (auto zoom) / Path / Framed (dead zone), axis lock; limits Rect / Node bounds / the LDtk level the target is in (glides between linked levels); trauma shake (trauma ^ exponent, noise, decay); Lua add_trauma / make_active / is_active / snap, Camera.add_trauma / get_active, became_active / inactive; Inspector node pickers, viewport frames / dead zone / limits (preview on a copy); guide with tutorials, tests, drive

## Phase 11 — State transition guards (2026-10-23)

Arrows allow a change (their conditions: when it goes by itself); states can refuse. Chosen: full guards, sm_travel stays forced + sm_request, a per-state "Any state interrupts" toggle, blocked attempts shown live only (not in the history).

- [x] 11.1 Engine: minTime, noInterrupt, leaveWhen / enterWhen on states, can_exit_ / can_enter_ script guards, StateMachine_Request / sm_request (ok, reason), explain (ways out with each condition's result and the block), saved; tests
- [x] 11.2 Editor: Guards in the state side panel (shared condition list), lock badge, Add Guard Callbacks, Ways out (live, Simulate and Play), blocked arrows red, live condition marks; generated types for can_exit_ / can_enter_
- [x] 11.3 Drive state_guards, docs

## Phase 9 — Code editor on par with Zed (2026-10-23)

Docs: `editor/CODE_EDITOR.md`. Constraints: no frame-time cost (cache per buffer version, draw only visible lines), no leaks (owned allocations freed with the doc / on close).

Copy / paste
- [x] 9.1 Whole-line paste (a whole-line copy pastes as a line above), paste re-indent, clipboard history (Cmd+Shift+V), Copy Path / Absolute Path / Location
Context menus
- [x] 9.2 Grouped context menu with shortcuts; context items (symbol, selection, node / asset path strings); gutter menu; tab menu (close others / right / saved, copy path, reveal, pin)
Selection & multi-cursor
- [x] 9.3 Expand / shrink selection (word -> string / brackets -> line -> block -> function -> file)
- [x] 9.4 Column selection (Alt+drag), cursors at line ends (Shift+Alt+I), skip occurrence, select inside brackets / quotes, undo last cursor
Display
- [x] 9.5 Matching bracket highlight + jump, rainbow brackets, indent guides
- [x] 9.6 Symbol highlights (LSP document highlight), visible whitespace, soft wrap
- [x] 9.7 Code folding (gutter arrows; functions, tables, comment blocks)
- [x] 9.8 Scrollbar markers (errors, find matches, breakpoints, changes) - the minimap
- [x] 9.9 Sticky scroll + breadcrumbs
- [x] 9.10 Inlay hints (LSP)
- [x] 9.11 Git gutter (added / modified / removed)
Navigation
- [x] 9.12 Back / forward history
- [x] 9.13 Outline (Cmd+Shift+O) and workspace symbols (Cmd+T)
- [x] 9.14 Next / previous diagnostic (F8), next / previous change
- [x] 9.15 Find in files (Cmd+Shift+F) with a results pane
- [x] 9.16 Peek definition / references inline
Refactoring
- [x] 9.17 Code actions / lightbulb (Cmd+.): LSP quick fixes + engine fixes (unknown node path, unknown input action)
- [x] 9.18 Extract local / extract method / inline variable; wrap in if / function / do; get_property <-> field, strings <-> Vec2
- [x] 9.19 Rename across files with a preview
Files
- [x] 9.20 Tab pinning + preview tab
- [x] 9.21 Files changed on disk: reload prompt; local history (restore earlier saves)
Engine
- [x] 9.22 Inline values while debugging
- [x] 9.23 Property in code <-> Inspector (click to select)
- [x] 9.24 Colour swatches beside {r, g, b, a} with a picker
- [x] 9.25 Texture path hover preview
