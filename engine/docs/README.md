# Engine feature guides

One guide per feature: what it does, how to use it in the editor, the
scripting API, examples / tutorials, what is saved, performance notes and
limits. The scripting reference is [`../SCRIPTING.md`](../SCRIPTING.md); the
editor overview is [`../../editor/README.md`](../../editor/README.md).

| Guide | |
|---|---|
| [Level editor](level_editor.md) | The **Level** tab: LDtk projects edited in place - worlds, levels, IntGrid / Tiles / Auto layers with LDtk's rule engine, entities and fields, definitions, terrains, per-tile data and animated tiles; the `Ldtk_Doc` API - with tutorials. |
| [Aseprite](aseprite.md) | .aseprite files used as they are: tags played as Aseprite plays them, layers on / off per node, slices (pivots, hitboxes), user data, tilemap layers as TileMaps; live reload when you save - with a tutorial. |
| [Skeletal animation](skeletal_animation.md) | Spine and DragonBones exports on the engine's own runtime: Skeleton and Bone Attachment nodes, crossfades, skins, IK, events, bone overrides - with a tutorial. |
| [Vector art](vector.md) | Vector shapes crisp at any zoom: tessellation, anti-aliasing, cached GPU meshes, the Vector Shape node - the start of Flash-style vector characters (Phase 14). |
| [Animation editing](animation_editing.md) | Custom key curves (cubic Bezier), method events with arguments and the animation_event signal, onion skin - with tutorials. |
| [State machines](state_machine.md) | States, arrows (Manual / Automatic), conditions, parameters and buffered triggers, guards, callbacks in order, child machines; the State Machine tab (Graph, Parameters & Triggers, Settings) and its live view; `sm_transition` - with tutorials (platformer with input buffering, enemy AI, combo chain) and moving from `sm_request` / `sm_travel`. |
| [Draw order](draw_order.md) | Layers, Z index, Y-sort (top-down / isometric depth). |
| [Navigation](navigation.md) | Path finding on tile maps, LDtk levels and Navigation Regions; agents that walk there (radius, avoidance, doors) - with tutorials. |
| [Accessibility](accessibility.md) | UI scale, colour-blind filters (and an editor preview), subtitles from dialogue and sound captions, screen shake scale; the Accessibility Menu template - with a tutorial. |
| [Advanced camera](advanced_camera.md) | Virtual cameras with priorities and blending, follow modes (group, path, dead zone, look-ahead), limits incl. the LDtk level the target is in, trauma shake - with tutorials. |
| [Android export](android_export.md) | Export to Android phones and tablets: an APK and an AAB (arm64, Android 7+), what the computer needs (SDK, Java, bundletool), signing, testing on an emulator, building the runner. |
| [Web export](web_export.md) | Export to the browser (a static folder for itch.io etc.), what works there, the prebuilt web runner and how the engine runs on WebAssembly. |
| [Sprite atlases](atlas.md) | Tick Atlas on textures: export packs them into pages (fewer draw calls); how it works, what to leave out, helpers for engine code. |
| [Import settings](import_settings.md) | Per-asset settings next to the file: texture filter / wrap / mipmaps / slicing preset / QOI on export, audio gain and default bus - with tutorials. |
| [Audio mixer](audio_mixer.md) | Buses (fader, pan, mute / solo, effects, routing), the Mixer tab, Lua control - with tutorials. |
| [Gamepads and local multiplayer](gamepads.md) | Up to 4 players with their own controllers, hot-plug events, rumble (native per OS), button prompts that match the controller (`Input.glyph`), simulated pads for tests - with a co-op tutorial. |
| [Input and rebinding](input_rebinding.md) | Actions, player rebinding (listen, conflicts, saving), gamepad menus, the Controls Menu template. |
| [Changing scenes](scene_flow.md) | Transitions, preloading, loading screens (background texture decoding) - with a loading screen tutorial. |
| [Paths and followers](paths.md) | Bézier paths edited in the viewport; followers for moving platforms, patrols, rails - with tutorials. |
| [Pixel-perfect rendering](pixel_perfect.md) | Integer scaling, pixel snap, smooth sub-pixel camera - recipes for pixel art. |
| [Components](components.md) | Reusable node trees (prefabs) placed as linked instances: creating and editing them, overrides (marked in the Inspector; revert / apply per value), exposed properties, nesting, spawning from Lua (values, pools), hot reload, missing files, the file format - with a tutorial (an enemy with an exposed speed and its own health). |
| [Custom node types](custom_nodes.md) | Your own node types (a Hurtbox: an Area, its script and a box) listed in Add Node: making them (the dialog, Save as Custom Node), linked values, editing a type as a document, types built on types, script inheritance (`extends`, `super`, Extend Script), changing a base type, LDtk entities, the Lua API - with a tutorial (hurtboxes and hitboxes). |
| [Resources](resources.md) | Data assets of a Lua class: properties edited in the Inspector per `.resource.json`, methods any script can call; shared or one per component instance, `on_load`, hot reload - with a tutorial (per-enemy health). |
| [Procedural levels](level_generator.md) | Generators: a graph of nodes (noise, random fill, cellular caves, threshold, combine...) whose tile output writes a level into a TileMap; deterministic seeds; `LevelGen.generate` / `values` - with cave and terrain examples. |
| [Global events](events.md) | The event bus: `Events.emit` / `Events.connect` between any scripts (and engine code) without references - gameplay to UI, levels to the game flow; deferred events, lifetimes - with a tutorial (a HUD that never looks for the player). |
| [Object pooling](pooling.md) | Reuse bullets, effects, pickups: `Pool.take`, `on_spawn` / `on_despawn`, prewarm, caps - with a tutorial. |
| [Crash reports](crash_reports.md) | What a crash writes (reason, stack, recent lines), where, the editor's "report on GitHub", and the `Crash` Lua module for games. |
| [Visibility notifier](visibility.md) | On screen / off screen events; pause, disable or remove the parent off screen. |
