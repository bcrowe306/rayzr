# Editor test-drives

Test-drives operate the editor the way a user does. A script moves the mouse,
clicks, drags, scrolls, presses keys and types. Each action is injected as a
real ImGui input event, and the real mouse and keyboard are ignored meanwhile.
After each step the script checks the editor's state, the files it wrote, and
the game process it launched, and it captures screenshots along the way.

```bash
./scripts/editor_drive.sh                 # every tests/drive/*.drive
./scripts/editor_drive.sh playtest nodes  # selected drives
EDITOR_DEFINES=-define:RAYZR_MEM_TRACK=true ./scripts/editor_drive.sh code_soak_mem  # memory reports in the kept log
EDITOR_BIN=bin/editor_dev GAME_BIN=bin/game_dev ./scripts/editor_drive.sh state_graph  # beside another run (own binaries)
task editor:drive                         # same as the first line
```

Each drive runs against a **fresh copy** of `assets/demo_project` in `/tmp`, so the
real project is never modified. Results go to `editor_screenshots/drive/<name>/`:
numbered screenshots plus an `index.md` report listing every check. The script
exits non-zero if any check fails.

## Suites

| Drive | Covers |
|---|---|
| `playtest.drive` | Rename and move a node, press Play: the editor saves, the game process starts, and the game's own scene dump contains the edit. Play Current Scene (F6) runs a non-initial scene. |
| `nodes.drive` | Add Node dialog (toolbar and Ctrl+A, search, Create), texture picker, reflected property edit, duplicate, delete, undo/redo, drag-and-drop re-parenting, visibility toggle, save. |
| `viewport.drive` | Click-select, move/rotate/scale gizmos with world-space grid snapping, undo of gizmo edits, pan tool, wheel zoom. |
| `scripts.drive` | Attach a Lua script from the inspector, edit an exported property, save, simulate in the editor (and restore), Play: the game runs with the edited value. |
| `project.drive` | New scene, physics bodies, unsaved edits survive scene switches, Project Settings (gravity, startup scene), simulate a falling crate, Play starts in the new scene. |
| `components.drive` | Save a subtree as a component from the context menu, instantiate it from Assets, built-in templates. |
| `export.drive` | Export `.rayzr`, then run the game from the package (textures load from inside it). |
| `level_generator.drive` | The Level Generator window: a new generator (the cave template), a node added from the canvas menu and linked (a loop refused), undo / redo, a parameter, a new seed, delete, save, Apply to a TileMap. |
| `levelgen_conveniences.drive` | The Level Generator's conveniences: Shift+click and box selection, copy / paste at the mouse (links kept) and duplicate, a comment frame dragged (its nodes follow), resized, titled and saved, nodes pasted into a second generator, the add menu's search (Enter adds the first match); each undone. |
| `bottom_tabs.drive` | View > Bottom Panel: the Mixer tab hidden and shown again (checked, saved in settings.ini); the Animation tab hidden, then back when an AnimationPlayer is selected. |
| `scene_panel_tabs.drive` | The Scene panel's tabs: Signals empty, then a timer -> drone connection listed (click selects the timer, the code button opens the method), flagged while its target is deleted (undo), disconnected there; Settings reached from the Inspector's Scene Settings button. |
| `sound_preview.drive` | The Inspector's Preview on a Sound Effect node (Play / Stop; another selection stops it) and a Music node. |
| `browse_previews.drive` | The File Browser's arrow keys (rows; Right / Left into and out of a folder), Autoplay (a sound plays on selection; off: it doesn't; saved) and Loop toggles, an Aseprite animation playing and paused; the Assets panel's arrow keys with a selected sound playing in the Preview panel. |
| `camera_frame.drive` | A 640x360 virtual resolution: the camera frame and a top-right Screen Layer at (640, 0); Expand with the 4:3 preview shape (saved): the frame grows (dashed) and the layer follows to (640, -60). |
| `sound_effects.drive` | A Sound Effect with two sounds (the list's Add Sound; one imported), Random mode showing weights, the preview by mode and a row's own, Pitch Random set, reordered by dragging, one removed (saved as a single `audio` again). |
| `properties_tab.drive` | The Inspector's Properties tab: a property added to a node with no script (one made; the node at the new default), a resource property with its class picked (then a resource picked in the Inspector), a rename in Edit, Remove (asks; undo restores). |
| `ldtk_entity_icons.drive` | An LDtk level's entities drawn in the scene viewport (icons, else their boxes in their colour) with Draw Entity Tiles off. |
| `file_browser.drive` | The bottom panel's Files tab (View > File Browser): a typed path, history (back / forward / up), a bookmark; image, sound (play / stop) and text previews; a search through sub-folders, the type filter; Load by type, a taken name skipped / replaced, into a chosen folder, several at once, a row dragged onto Assets; switching to another tab stops a playing sound. |
| `assets.drive` | Asset folders collapse/expand (folder icons); the Scenes folder's + creates a scene. |
| `code_shortcuts.drive` | Zed-style code editing: auto-closing pairs, line operations, multi-cursor, find/replace, go to line, LSP rename (with its preview: Apply) and format, font size, Go to File, reopen tab, command palette, Keyboard Shortcuts window. |
| `scene_editing.drive` | Multi-select (tree, box), align, nudge, copy/paste, multi-delete, F2 rename, select all, quit prompt. |
| `signals.drive` | Connect an event to a script method (handler generated, connection saved), disconnect (handler removed; asks when it has code), drag assets into a script (path / asset property). |
| `prefab_overrides.drive` | Edit a child of a linked instance: saved as an override, other instances unaffected, Revert. |
| `animation.drive` | Animation tab: frames from dropped textures, scrubbing, rotation track with keys, preview restore, save. |
| `tilemap.drive` | Tile map: the bottom panel's Tile Map tab opens on selection; tileset, palette (zoom, grid), paint stroke (undo/redo), flood fill, erase, save. |
| `tilemap_components.drive` | The Tile Map tab's Components layer: a component picked, a painted stroke (one linked instance per cell, undo/redo), right-button erase, Shift off-grid placement, flood fill, saved as linked instances. |
| `ui_ux.drive` | Settings (keymap record, input action + key, video, export), linked X/Y and reset, Save As / Revert / Open Project, asset copy/paste/rename/delete, paste as child, LDtk level asset, instance add child + apply to component, particle editor, viewport fit. |
| `animation_player.drive` | The preview right of the timeline (playing, paused on a frame); frames deleted (button, menu, Delete key - the node stays), copied and pasted (buttons, Cmd+C / Cmd+V), the range (fields, menu), per-animation reverse and FPS (right-click: the player's FPS), the default animation, saved. |
| `anim_manage.drive` | Animations renamed (a taken name refused with a warning; the default and a state machine's state follow), duplicated (frames, range, reverse; placed after it), deleted (the copy becomes current, undo restores it), saved. |
| `slicer_zoom_tabs.drive` | Sprite slicer zoom (1:1, + / -, Cmd+wheel, a cell picked zoomed in, Fit); View > Show Tab Bars on (every docked window has its tab) and off, saved in settings.ini. |
| `game_controls.drive` | Play This Scene; toolbar Pause / Resume and Step, F9 / Shift+F9; Restart (a new process, the same scene); Stop, then Game > Restart plays it again; Game > Pause / Stop. |
| `prop_drag.drive` | The help pane's `path = "..."` (a Transform row, a script property `script.<name>`); a property name dragged into a script: get_property, Shift: set_property with the value; another node's via get_node. |
| `bottom_follow.drive` | The AnimationPlayer Inspector (player settings only, `fps` path), the Animation tab's ▾ menu (an animation from a sprite sheet); the bottom panel follows the selection and goes back, a hand-picked tab stays, the setting turns it off. |
| `game_colliders.drive` | The toolbar's Show Colliders button: saved in project.json, switched live in a running game, Game menu entry. |
| `node_drop_typed.drive` | A node dropped into a script: on an empty line a `---@type` local (indented into the function), into an assignment the annotation above it, elsewhere an inline `--[[@as Type]]` cast; undo. |
| `negative_scale.drive` | An AnimationPlayer with scale x -1 draws mirrored around its position; its bounds (selection box, picking) mirror too. |
| `origin.drive` | The Origin row (help path, presets, typed, reset to the centre, undo), none for a camera, a new AnimationPlayer centred, saved as `"pivot"`; a migrated pixel origin. |
| `hier_script.drive` | The scene tree's script marker: shown when a script is attached, opens it, gone when detached. |
| `lua_get_script.drive` | Typed get_script(): a node name that runs a script returns NodeOf_<name>; another script's fields complete through it. |
| `lua_events.drive` | Event names complete: a timer's `connect("` offers timeout, `emit("` the project's custom events, `function X:on_` the on_<event> methods. |
| `lua_properties.drive` | Typed property paths: a camera's set_property(" completes followMode; get_property returns the enum (its names complete in a comparison). |
| `lua_get_node.drive` | Typed get_node: self.node:get_node(" completes the paths in the script's scenes, each typed (EngineExhaust is a FrameAnimationNode). |
| `lua_aliases.drive` | Project names complete in API calls: locale keys (tr), keys (Input.is_key_pressed), save keys (Save.get); animation and state names in the generated types. |
| `lua_runtime_diags.drive` | Simulate: a get_node on a missing path (warning) and a nil index (error) show as diagnostics on their lines; saving clears them. |
| `lua_runtime_diags_play.drive` | Play: a script error in the game's output becomes a diagnostic on its line. |
| `code_drop_items.drive` | Dropped into a script: an input action chip (is_action_pressed, Shift: is_action_down), a sound with Alt (Audio.play_sound), an animation (animation_play). |
| `code_drop_event.drive` | A Signals event row dropped into a script: an indented connect with the handler (value named for the event), the cursor in its body. |
| `code_drop_node_method.drive` | A node dropped onto a method's line: its events in a menu; the pick adds a connect calling the method to ready(). |
| `node_ref_property.drive` | A node dropped into the properties table adds a `type = "node"` property, set to it after the save; the Inspector picker re-points it; saved as a path. |
| `node_refs_rename.drive` | Rename then move a node a script reaches with get_node: the prompt offers the new path each time, Update rewrites it. |
| `code_goto_node.drive` | Cmd+click a get_node path / a find_node name selects the node; a script tab's Find Usages lists where it's used. |
| `script_prop_types.drive` | Script property types: groups, enum combo, tooltip, array add / remove, curve and gradient double-click adds, saved as JSON. |
| `remote_script_props.drive` | Play: the Game tab lists the drone's script.orbit_radius live and an edit changes it in the game. |
| `lua_property_fields.drive` | Property-style access completes: self.node.rot -> rotation; self.node.position is a Vec2 (normalized completes). |
| `lua_spawn.drive` | Scene.instantiate is typed per component: the generated overload returns the root type (DynamicBodyNode), so the result completes apply_impulse and queue_free. |
| `script_globals.drive` | Global scripts: right-click > Make Global (globe and name in Assets, saved in project.json, listed in Project Settings > Globals); the global completes in another script; Simulate runs its ready and update; Remove Global. |
| `script_templates.drive` | New Script dialog: Assets + creates from the picked template (Enemy Patrol, named); a Trigger Area's New Script picks Pickup and attaches it; Cancel creates nothing. |
| `lua_snippets.drive` | Snippets: `method` + Tab (class filled, placeholders across lines), `connect` inside it (indented), `tween` with the completion list open (hint shown, Tab expands), `ready`; undo. |
| `script_drop_tree.drive` | A script dragged from Assets onto a scene-tree row attaches it (node selected); another replaces it; undo restores each. |
| `lua_console.drive` | The Console's Lua line: in Simulate an expression (a node), a statement then its value, an error, history (Up); in Play the game evaluates (`Scene.get_name()`, a Vec2). |
| `debug_watch_condition.drive` | A breakpoint condition from the gutter's right-click: false never stops, true stops with the reason; watch expressions in the paused frame; the Console's Lua line there. |
| `lua_api_reference.drive` | Hover over an engine function shows its description and `Example:`; F1 opens the Scripting Reference with its API entry and the Audio section; search and pick a section; a section with a table (Events) rendered as markdown. |
| `particles_viewport.drive` | Particle emitters animate in the viewport while editing (live particles without Simulate); the Particles tab's button pauses and resumes the preview. |
| `code_clipboard.drive` | A copy with nothing selected pastes as a whole line above the cursor's line; Cmd+Enter indents inside a function; a block pasted there is re-indented; Cmd+Shift+V pastes from the history. |
| `code_context_menu.drive` | The code context menu: a node-name string selects the node, a file path reveals it, a symbol's entries, the Selection submenu; Wrap In if on two lines; the gutter menu; the tab menu. |
| `code_expand_selection.drive` | Expand selection from inside a string: word, string, brackets, call, line, function body, function, file; shrink back. |
| `code_multicursor.drive` | Cursors at line ends (typing at both), undo cursor, skip occurrence, select inside quotes then brackets, Alt+drag column selection. |
| `code_brackets_guides.drive` | Cmd+Shift+\\ jumps between a bracket pair and from inside to the closer; rainbow brackets and indent guides (screenshot) and their settings. |
| `code_display_fold.drive` | The caret word's other uses; fold from the gutter arrow (rows hidden, Up/Down skip it, follows an edit above, the chip unfolds), Fold All / Unfold All, fold at the caret; soft wrap (more rows, Alt+Z off again); whitespace in a selection. |
| `code_git_overview.drive` | The project made a git repo: a modified, an added and a removed line marked in the gutter (and gone after undo); the overview strip scrolls when clicked. |
| `code_sticky_crumbs.drive` | Inside update: its first line pinned and the breadcrumbs function > if; the crumb and the pinned line go to line 24. |
| `code_inlay_hints.drive` | Parameter-name hints on a module call and a node method (at the argument's column), the caret moves over the text not the hint, Ctrl+Alt+H off and on. |
| `code_nav.drive` | Go back / forward after a jump; F8 / Shift+F8 to a syntax error; Alt+F8 / Alt+Shift+F8 between changed blocks (the project made a git repo). |
| `code_symbols.drive` | Outline: a function and a script property by name; workspace symbols: another script's function opens it. |
| `code_find_in_files.drive` | Cmd+Shift+F: three matches in one file, a result opens the script at its line; Replace All writes the closed file. |
| `code_peek.drive` | Peek references of self.rotation (a list, Enter opens one - the same tab), peek the definition of Log.info (engine API), Esc closes. |
| `code_actions.drive` | Lightbulb on a line with an unknown node name; Cmd+. picks PlayerShip from the scene; the lightbulb adds a missing input action to project.json. |
| `code_refactor.drive` | Extract local (typing renames both), inline it back, toggle set_property to a field and {1, 2} to Vec2 from the Refactor menu, extract two lines into a method (renamed by typing). |
| `code_tabs_preview_pin.drive` | A symbol in another file opens as a preview, the next one replaces it, typing keeps it; a pinned tab survives Close Saved. |
| `code_disk_history.drive` | Two saves kept; Local History restores the older; the file changed on disk while edited - the bar, Reload (undo brings the edits back); clean, a change reloads by itself. |
| `code_swatch_texture.drive` | Swatches before a property's colour default and {0.2, 0.4, 0.8} (none for {1, 2, 3}); a click opens the picker; hovering a texture path shows the image. |
| `code_inline_values.drive` | Paused at a breakpoint in update: line 27 shows self and dt; gone after Continue. |
| `code_inspector_link.drive` | Show in Inspector on self.rotation_speed selects PlayerShip and lights its row; the Inspector's thrust_power > Find in Script opens the declaration, name selected. |
| `code_soak_mem.drive` | 40 rounds of Code tab use (typing, undo, fold, soft wrap, find, expand selection, clipboard history, menus); with `EDITOR_DEFINES=-define:RAYZR_MEM_TRACK=true` the log shows the live heap staying flat. |
| `state_graph.drive` | The State Machine tab follows a new StateMachine; right-click adds states, renamed in the side panel; a dot dragged onto a state makes a transition (Manual, a condition added); saved with positions; the way back makes a curved pair and each arrow is picked by clicking its own curve; Delete removes the arrow (not the node). |
| `state_machine.drive` | The Inspector's summary opens the State Machine tab; Settings adds a state per animation; Parameters & Triggers: a float parameter and a buffered trigger; an Automatic arrow with speed > 5; saved (typed params, triggers, mode); in Simulate the parameter edited on its page switches state. |
| `docs_state_machine.drive` | Docs screenshots for engine/docs/state_machine.md (scripts/docs/screenshots.sh docs_state_machine): Parameters & Triggers, the graph (a curved Automatic pair, a dashed Manual arrow), the state and arrow panels, Settings, the live view in Simulate. |
| `state_graph_live.drive` | A machine with break on enter: in Simulate the param set from the Lua line takes it there and pauses, the history shows; in Play the graph shows the game's machine and break on enter pauses the game. |
| `state_machine_lua.drive` | The generated Lua types list `on_enter_` / `on_update_` / `on_exit_<state>` for a new state; Add Script Callbacks without a script says to attach one; with player_ship.lua it writes the three methods into the script. |
| `state_guards.drive` | A state's Leave After, Any State Interrupts (off) and Can enter when set in the side panel and saved, the lock on its box; in Simulate the (Automatic) arrow out is blocked: Ways out says Min_Time and `sm_transition` prints why. |
| `y_sort.drive` | Y Sort Children on a node, a new child's Y Sort Offset row (only under a Y-sorted parent) and Z Index, saved; off again. |
| `visibility_notifier.drive` | A Visibility Notifier added under PlayerShip, its Size row, saved; in Simulate on screen, then the ship moved far away: off screen and (Pause Parent) the ship paused. |
| `node_pool.drive` | Pools from the Lua console in Simulate: prewarm, take, `destroy()` returns the instance (parked, disabled), stats; the Profiler lists the pool. |
| `pixel_perfect.drive` | Project Settings > Video: Integer Scaling, Pixel Snap, then Smooth Camera (disabled until Pixel Snap), saved in project.json. |
| `path.drive` | A Path from Add Node: a point dragged, a point added by double-clicking the curve, one removed in the Inspector, sharp / smooth; a Path Follow under it travels in Simulate; saved. |
| `controls_menu.drive` | A UI Container's New Script picks the Controls Menu template; in Simulate it lists the actions with their keys (confirm hidden), and rebinding shows Press a key... |
| `mixer.drive` | The Mixer tab: a new bus, a Reverb on it (its parameter popup), the level typed in dB, mute; saved in project.json; in Simulate a sound into the bus plays (a voice, the meters move). |
| `navigation.drive` | A Navigation Region added and baked (the Inspector's Bake), a node with a Navigation Agent; saved; in Simulate the agent walks it to a target set from Lua. |
| `accessibility.drive` | Project Settings > Accessibility (Sound Captions) saved in project.json; View > Colour Vision: Deuteranopia previews the viewport; a UI Container's Accessibility Menu template builds its rows in Simulate (captions on from the project) and its filter button follows the setting. |
| `skeleton.drive` | A Spine fixture (tests/drive/fixtures/skeleton_zz) on a Skeleton node: file and animation picked, preview scrubbed, a bone highlighted, a Bone Attachment on the hand; saved; in Simulate it plays (Lua bone position). |
| `web_export.drive` | A web preset with its own title exported (runner files, game.rayzr, titled page); File > Export > Open Web Export in Browser serves it; the game runs in headless Chrome (screenshot). |
| `animation_depth.drive` | A key's Edit Curve with the Ease In preset (frame 2 follows it), saved as bezier handles; the onion skin in the viewport; a method key's argument, saved. |
| `anim_key_inspector.drive` | The key inspector: a key's value typed (the scene follows), an easing, bezier handles shown, two keys set linear and to one value (undo), a key moved by its frame field; saved. |
| `anim_inspector_keys.drive` | The player pinned while its parent is selected; the parent's rotation keyed with the Inspector's diamond at two frames (interpolates); right-click: previous key; auto-key records a typed position (not the scrubbed rotation), undo removes it; saved; unpinned. |
| `new_component.drive` | New Component from the Assets + menu (a Kinematic Body root, opened in its tab), the Components section's menu (a taken name -> `_2`), a component's menu and the command palette. |
| `anim_event_tracks.drive` | Add Track > Emit Particles lists the scene's emitters; the particles track's settings: a key set to a burst of 7, the target picker (emitters only); an enable track on another node, its key turned to enable; labels on the keys; saved. |
| `anim_graph.drive` | The value graph: a vector split into x / y (hidden from the list), a key dragged up in value, bezier handles from the key's menu, the out handle dragged down (frame 2 dips), Frame All; back to the rows; saved. |
| `anim_timeline.drive` | The timeline zoomed (Cmd + wheel, the wheel over the ruler, reset), the ruler in seconds, a node's rows folded; keys selected (click, Cmd, a box, an empty click clears), one dragged a frame earlier (undo), copied and pasted at the playhead, duplicated, deleted; saved. |
| `remote_tree.drive` | Play; the Scene panel's Remote view lists the game's tree; selecting PlayerShip shows its live properties in the Inspector: rotation typed (drag field), visible unticked, the eye toggle; Apply to Scene copies the rotation into the edited scene (undo restores it); Stop leaves the Remote view. |
| `scene_tabs.drive` | A second scene opens in a tab; switching keeps each tab's selection; Cmd+Alt+Right cycles; closing a modified tab asks (Cancel keeps it, Don't Save unloads it); the open tabs are written to .rayzr/open_scenes.json; reopening loads the saved file. |
| `advanced_camera.drive` | An Advanced Camera added, Follow Target picked (PlayerShip), Damping set; saved; in Simulate it's active, the host follows the ship, Shake adds trauma, a second camera with a higher priority takes over. |
| `ui_theme.drive` | No Scene JSON tab; headers, rulers and the Welcome window; theme presets preview live, Save writes `[theme]` to settings.ini, Cancel restores the saved theme. |
| `lua_debugger.drive` | A gutter breakpoint, Play This Scene stops in the script (line, locals, stack), step over, breakpoint removed and Continue, stop. |
| `code_overlays.drive` | Completion docs, signature help and hover boxes inside the Code area and bounded; the hover box stays while the mouse is on it. |
| `code_big_file.drive` | A generated 10,000-line script: an edit's line-state pass stays small, the token cache is >= 5x the full re-tokenize, highlighting far down the file. |
| `lua_node_types.drive` | Typed nodes in Lua: `find_node` overloads per node name, `self.node` typed by where the script is attached, camera methods only on cameras (language-server completion). |
| `welcome.drive` | One icon per node type; Help > Welcome; Platformer, Top-down and Menu projects from templates, each played headless by the game binary; the empty-scene hint. |
| `workspaces.drive` | Animation and Level Design presets (bottom panel height), a saved workspace loaded back, Reset Layout. |
| `remote_game.drive` | Play with the editor link: the Game tab's live tree, pause, one-frame step, inspect and change a node's rotation in the running game, resume, a saved scene reloading in the game, stop. |
| `sprite_slicer.drive` | Slicer: a texture cut 4 x 2, cells picked (click, Shift+click range) as an animation, one per row, a new AnimationPlayer; picked cells saved. |
| `asset_folders.drive` | Folders view: new folder, a texture the scene uses dragged into it (reference updated), Find Usages, folder renamed (references updated), thumbnail grid, texture import settings saved next to it, folder deleted. |
| `atlas.drive` | Atlas ticked on a texture (saved in its import file); Export .rayzr packs it into an atlas page; the exported game runs from the package (screenshot) with the scene's texture. |
| `import_settings.drive` | A texture's filter and Export: QOI saved in its `.import.json` (hidden in Assets), the file following a rename, an audio file's default bus, a slicing preset from the slicer's Save Preset. |
| `scene_tree.drive` | Tags in the Inspector (typed, picked, removed), filter by `#tag` / `t:type`, reorder by dropping on a row's edge (undo), Copy to Scene at the same world position, tags in the generated Lua types. |
| `viewport_tools.drive` | Rulers, a guide dragged from the ruler, Alt-drag pivot (image and child stay), smart snap of an edge to the guide, viewport lock (not pickable) and hide in editor, Show All Colliders, saved. |
| `multi_edit.drive` | Two lights selected: mixed value marked, a number / one axis of the position / a checkbox / a combo applied to both, undo. |
| `inspector_help.drive` | Hovering a property fills the tooltip and the Inspector help pane (field or label); View > Inspector Help hides the pane. |
| `remember_dirs.drive` | An import remembers its folder and the next import dialog opens there; Export .rayzr into a picked folder, the next export and the Output Folder's Browse... start there; a new project's location; all saved in settings.ini `[paths]`. |
| `code_editor.drive` | Open a script in the Code tab; lua-language-server completion of the engine API, signature help, diagnostics, go to definition; save; unsaved-changes prompt; New Script from the Inspector. |

## Script language

One command per line; `#` starts a comment.

```
wait <frames>
wait-until <expr> [timeout=<frames>]
move|hover <target>
click|rclick|dblclick <target>
drag <from> <to> [steps]
scroll <target> <dy>
key <chord>                    # w, delete, f5, escape, ctrl+s, ctrl+shift+z, ctrl+slash, ctrl+rbracket
hold <mods> / release          # keep shift / cmd / alt held for the following clicks/keys
type <text>                    # "\s" types a space (command text is trimmed)
expect <expr>
screenshot <name>
game-args <args...>            # extra args for the game the editor launches
exec <command...>              # run a command to completion
drop-files <target> <path...>  # files/folders dropped from the OS file manager at <target>
dialog-files [<path...>]       # answer for the next system file dialog (none = Cancel)
log <text> | quit
```

**Targets**
- `@<id>`: a widget registered by the UI (`@toolbar.play`, `@hier:PlayerShip`,
  `@insp.position.x`, `@insp.prop:gravityScale`, `@addnode:Texture Sprite`,
  `@asset:scenes/main.scene.json`, `@menu:Game/Simulate in Editor`, `@pick:<value>`,
  `@ctx:duplicate`, `@settings.save`, `@code.area`, `@code.tab:<file>`, `@code.completion:<label>`, ...).
- `@node:<Name>`: a node's position on screen.
- `@world:x,y`: a world position.
- `x,y`: raw window pixels.
- Any target accepts a `+dx,dy` pixel offset.

Clicks scroll the target's panel into view first, like a user would.

**Expressions** have the form `<query> <op> <value>`, where `op` is one of
`== != contains !contains ~= >= <=`. Expected values may use `\n`, `\t`
and `\s` (space). On macOS, Dear ImGui swaps Cmd and Ctrl: `ctrl+` in a
drive is the physical Control key, `cmd+` the Command key; editor shortcuts
accept either (Ctrl-specific bindings such as Ctrl+G win when Ctrl is held),
and `hold cmd` (not ctrl, which macOS turns into a right-click) adds to a
selection. `~=` compares numbers or `x,y` pairs within 0.5.

Queries:
- `selected`, `scene`, `tool`, `zoom`, `camera`, `nodes`, `tile-chunks` (cached tile chunks), `undo-bytes` (memory held by undo snapshots)
- `modified`, `modified-count`, `undo`, `redo`
- `game` (running/stopped), `build`, `log`, `last-log`
- `add-node-open`, `project-settings-open`, `item:<id>`
- `file:<project path>`, `abs-file:<path>`
- `code.open` (tab count), `code.file`, `code.text`, `code.line` (caret line), `code.cursor` (`line:col`),
  `code.dirty`, `code.focused`, `code.lsp` (off/starting/ready/failed), `code.completion` (visible items,
  comma-separated), `code.signature`, `code.errors`, `code.diagnostics`, `code.diagnostic-messages`, `code.hover`
- `code.overlays` (`ok <n>` when every overlay is inside the Code area and bounded), `code.update-ms` (last line-state pass), `code.token-bench` (`full=<ms> cached=<ms> tokenized=<n> lines=<n>`), `code.token-speedup`
- `code.inlays:<line>` (`label@col,...`, `■` = a colour swatch), `code.inline-values:<line>` (the debugger's values on a line), `code.changes` (`line:added|modified|deleted`), `code.git` (Unknown / Loading / None / Ready)
- `code.tabs` (open tabs, `(preview)` / `(pinned)`)
- `code.folds` (folded first lines), `code.rows` (display rows), `code.lines`, `code.symbol-highlights`
- `code.cursors`, `code.selection`, `code.selection-range` (`line:col-line:col`), `code.find` (match count), `code.font`, `code.completion-doc`
- `insp-help` (the Inspector help pane: `<Title>: <doc>`), `guides` (`x=704,y=50`), `usages` (files in the Find Usages window, -1 = closed), `folder-open:<dir>`
- `dialog-start` (the folder the last system file dialog opened in), `last-dir:import` / `last-dir:export` / `last-dir:projects` (the remembered folders)
- `slicer-zoom` (the slicer's zoom, `0.00` = Fit), `slicer-selection` (picked cells, `0,1,2`), `hidden-tab-bars` (docked spaces whose tab bar is hidden)
- `game-pid` (the running game's process id, 0 = none), `last-played` (the scene Restart plays, `project` = the initial scene)
- `insp-help-path` (the path the help pane shows), `insp-flash` (the row Show in Inspector lit)
- `particle-preview` (on / off; `node:<Name>.particles` = an emitter's live particles)
- `ref-section`, `ref-api` (the Scripting Reference window's section and API entry)
- `bottom-tab` (the bottom panel tab shown: Console, Profiler, Game, Animation, Particles, Ldtk, Search, StateGraph)
- `search-total`, `search-files` (find in files)
- `smg-selected` (the graph's selected state / `transition N`), `smg-zoom`, `smg-pan`, `smg-ways` (live ways out: `idle:Min_Time, run:waiting, ...`); `node:<Name>.path-points` (a PathNode's point count); `mixer-buses` (`Master:+0.0,Music:-6.0,...`), `mixer-voices`
- `remote-debug-draw` (the running game's last debug-draw reply)
- `selected-bounds` (the selected node's world bounds, `minx,miny,maxx,maxy`)
- `runtime-diags` (script problems recorded from Simulate / Play)
- `refs-pending` (script reference edits waiting in the rename / move prompt)
- `anim-names` (the selected AnimationPlayer's animations, the current one in `[brackets]`)
- `anim-preview` (`playing` / `paused`), `anim-info` (`frames=<n> range=<a>-<b> reverse=<b> fps=<f> default=<name>` of the selected AnimationPlayer), `theme` (the saved theme), `theme-panel` (the panel colour in use, `#rrggbbaa`), `node-icons` (`<distinct icons>/<node types>`), `workspace` (the current workspace), `window-h:<item>` (height of the window an item is in)
- `anim-keys` (keys selected in the Animation timeline), `anim-zoom` (the timeline's zoom, `1.00` = 100%)
- `debug-stopped`, `debug-line` (`file:line`), `debug-stack`, `debug-local:<name>`, `debug-reason`, `debug-watch:<expr>` (no spaces), `debug-condition:<file>:<line>` (the Lua debugger)
- `remote-connected`, `remote-paused`, `remote-frame`, `remote-steps`, `remote-reloads`, `remote-nodes`, `remote-names`, `remote-prop:<name>` (the Game tab's link to the running game)
- `palette.open`, `shortcuts-open`, `quit-prompt`, `selection`, `selection-count`, `clipboard-nodes`
- `import.imported`, `import.skipped`, `import.failed` (counts from the last import), `import.report`
  (Import Results open), `import.messages` (one `<file>: <status> <path> <message>` line each), `import.dialog`
- `ldtk.node`, `ldtk.level`, `ldtk.world`, `ldtk.world-mode`, `ldtk.active-levels`, `ldtk.page`, `ldtk.rules`,
  `ldtk.link-rules`, `ldtk.mapping:<Entity>` (`auto` / `component <path>` / `node` / `none`),
  `ldtk.collision:<Layer>:<value>`, `ldtk.layer-visible:<Layer>`, `ldtk.focus`, `ldtk.spawned`, `ldtk.links` (of the
  LDtk tab's level)
- `shape.edit` (shape editing on), `shape:<Node>:<index>:<field>` with field `type offset size radius rotation
  vertices points count`; shape handles are items `shape<i>.<Kind><n>` (Move, Rotate, Radius, Edge 0-3,
  Corner 0-3, CapEnd 0-1, Point n, AddPoint n)
- `node-delta:A,B` (global position of B minus A), `anim` (`<animation>:<frame>/<length>:<tracks>` of the selected AnimationPlayer)
- `node:<Name>.<field>`, where field is one of `exists type parent position global locked editor-hidden tags child-names rotation scale visible enabled children script prop.<path> script.<prop> connections overrides tiles material state particles` (`state`: a StateMachine's `<current>/<state count>`)

Widgets register themselves with `Drive_Item("<id>")` right after they are drawn
(see `editor/test_drive.odin` and `UI_IconButton`/`UI_Button` in `ui_style.odin`).

**macOS display:** raylib can't create a window while the display sleeps
(the editor hangs or crashes in `InitWindow`). For long runs keep it awake:
`caffeinate -d -i scripts/editor_drive.sh`.
