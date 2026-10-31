---@meta
--- Lua API Definitions for Rayzr
--- Language Server Protocol (LSP) stubs for autocomplete and type checking.

---@class RaycastHit
---@field hit boolean Whether the ray struck a physics shape
---@field point_x number World X hit coordinate
---@field point_y number World Y hit coordinate
---@field normal_x number World surface normal X
---@field normal_y number World surface normal Y
---@field fraction number Hit fraction from 0.0 to 1.0 along ray length
---@field node? Node Engine node attached to the struck body, if any

---@class Node
---@field name string The node's name (assigning renames it). Properties read and write as fields: `node.rotation = node.rotation + 5`.
---Represents an engine scene hierarchy node with transform, lifecycle, and optional physics.
local Node = {}

-- --- Node types: each has the Node methods plus its own --------------------------

---Nodes that show text (TextNode, UILabelNode, UIButtonNode, UITextInputNode).
---@class TextHolder
local TextHolder = {}

---UI nodes with a list (Dropdown, Radio Group, List View, Tree View, Bullet / Numbered List, Table, Toolbar, XY Plot, Tab Container, Notched Slider).
---@class UIListHolder
local UIListHolder = {}

---Nodes with a walkable grid (TileMapNode, LdtkLevelNode).
---@class NavGrid
local NavGrid = {}

---The camera the scene is seen through (follow, zoom, shake, limits).
---@class CameraNode : Node
local CameraNode = {}

---Vector art: an SVG (or one group of it: a symbol, a swappable part) or a built-in shape, crisp at any zoom.
---@class VectorShapeNode : Node
local VectorShapeNode = {}

---Moves a vector mouth with a voice (Rhubarb Lip Sync cues).
---@class LipSyncNode : Node
local LipSyncNode = {}

---Counts down and raises "timeout".
---@class TimerNode : Node
local TimerNode = {}

---@class ScriptNode : Node

---A sprite: draws an image.
---@class TextureNode : Node
local TextureNode = {}

---A sub-region sprite: draws a cropped slice / atlas region of an image.
---@class AtlasSpriteNode : Node
---@field region number[]
local AtlasSpriteNode = {}

---@class FrameAnimationNode : Node

---Plays frame / sprite-sheet animations with property tracks.
---@class AnimationPlayerNode : Node
local AnimationPlayerNode = {}

---A finite state machine.
---@class StateMachineNode : Node
local StateMachineNode = {}

---A particle effect.
---@class ParticleEmitterNode : Node
local ParticleEmitterNode = {}

---A sound effect.
---@class SoundNode : Node
local SoundNode = {}

---Streamed music.
---@class MusicNode : Node
local MusicNode = {}

---@class StaticBodyNode : Node

---A physics body moved by forces and collisions.
---@class DynamicBodyNode : Node
local DynamicBodyNode = {}

---A kinematic physics body moved by velocity or transform (moving platforms, elevators, doors).
---@class KinematicBodyNode : Node
local KinematicBodyNode = {}

---A character controller (move and slide, floors, walls).
---@class CharacterMoverNode : Node
local CharacterMoverNode = {}

---A sensor: reports bodies that overlap it.
---@class AreaNode : Node
local AreaNode = {}

---A ray that reports what it hits.
---@class RaycastNode : Node
local RaycastNode = {}

---An LDtk level (layers, entities, IntGrid).
---@class LdtkLevelNode : Node, NavGrid
local LdtkLevelNode = {}

---A painted tile map.
---@class TileMapNode : Node, NavGrid

---A 2D point or spot light.
---@class LightNode : Node
local LightNode = {}

---@class JointNode : Node

---Text in the world (fonts, rich text, typewriter).
---@class TextNode : Node, TextHolder
local TextNode = {}

---A dialogue box that types out lines.
---@class DialogueNode : Node
local DialogueNode = {}

---@class NineSliceNode : Node

---@class ParallaxNode : Node

---A polyline.
---@class LineNode : Node
local LineNode = {}

---A fading ribbon behind a moving node.
---@class TrailNode : Node
local TrailNode = {}

---Knows when the camera sees a rectangle: "screen_entered" / "screen_exited"; can pause, disable or remove its parent off screen.
---@class VisibilityNotifierNode : Node
local VisibilityNotifierNode = {}

---A grid area agents find paths in: baked from static bodies, solid tile maps and LDtk Solid cells; scripts can block cells (doors).
---@class NavigationRegionNode : Node, NavGrid
local NavigationRegionNode = {}

---Follows a path to a target and moves its parent: speed, radius (keeps clear of walls and other agents), avoidance; "navigation_finished" / "target_unreachable".
---@class NavigationAgentNode : Node
local NavigationAgentNode = {}

---Skeletal (cutout) animation from a Spine .json or DragonBones _ske.json export: animations crossfade, skins, IK, events ("skeleton_event"), "animation_finished"; scripts can turn bones.
---@class SkeletonNode : Node
local SkeletonNode = {}

---Under a Skeleton: follows one of its bones (bone, followRotation, followScale) - put a weapon or particles under it.
---@class BoneAttachmentNode : Node
local BoneAttachmentNode = {}

---An Aseprite file (.aseprite / .ase) shown and played as Aseprite does: tags with their direction and repeat count, per-frame durations, layers hidden / shown per node, the origin following a slice's pivot; its slices and user data for scripts. Saving the file in Aseprite updates it live. Events: "animation_finished"(tag), "animation_looped"(tag), "frame_changed"(frame).
---@class AsepriteNode : Node
local AsepriteNode = {}

---A virtual camera: follow modes (Glued, Simple, Group, Path, Framed), limits (incl. the LDtk level the target is in), trauma shake; the scene's camera shows the highest priority one and blends on a switch. "became_active" / "became_inactive".
---@class AdvancedCameraNode : Node
local AdvancedCameraNode = {}

---A curve through points with Bézier handles (routes, rails, platforms' tracks); a PathFollowNode child travels along it.
---@class PathNode : Node
local PathNode = {}

---Travels along its parent PathNode: progress (px), speed, loop (Stop / Loop / PingPong), rotate; "path_finished" / "path_looped".
---@class PathFollowNode : Node
local PathFollowNode = {}

---Spawns components where it is (position, rotation, flip): mode Single / All / Random / Sequential / Shuffle over its list; spawned under the scene's root, its parent, itself or a path; count, chance, cooldown, maxAlive, totalLimit, spread, jitter, speed, auto spawn, pooling. "spawned" (the root) / "limit_reached" / "list_finished".
---@class SpawnerNode : Node
local SpawnerNode = {}

---Generates a level from a generator (.levelgen.json) into a TileMap (its `tilemap` path, else its first TileMap child, else its parent) - when the scene starts, on generate() or a signal; seed / randomSeed (lastSeed: the one used), the generator's parameters set on the node, background generation. "generated" (the seed) / "generation_failed" (why).
---@class LevelGeneratorNode : Node
local LevelGeneratorNode = {}

---@class PostEffectNode : Node

---@class TouchJoystickNode : Node
local TouchJoystickNode = {}

---@class TouchButtonNode : Node
local TouchButtonNode = {}

---@class UIContainerNode : Node

---@class UILabelNode : Node, TextHolder

---@class UIButtonNode : Node, TextHolder

---@class UISliderNode : Node

---@class UICheckboxNode : Node

---@class UIProgressBarNode : Node

---@class UITextInputNode : Node, TextHolder

---@class UIDropdownNode : Node, UIListHolder

---@class UIRadioGroupNode : Node, UIListHolder

---@class UIToggleSwitchNode : Node

---@class UIKnobNode : Node

---@class UINotchedSliderNode : Node, UIListHolder

---@class UIVolumeFaderNode : Node

---@class UIVolumeMeterNode : Node

---@class UISeparatorNode : Node

---@class UIXYPlotNode : Node, UIListHolder

---@class UIListViewNode : Node, UIListHolder

---@class UITreeViewNode : Node, UIListHolder

---@class UIUnorderedListNode : Node, UIListHolder

---@class UIOrderedListNode : Node, UIListHolder

---@class UITableNode : Node, UIListHolder

---@class UIIconNode : Node

---@class UIToolbarNode : Node, UIListHolder

---@class UITabContainerNode : Node, UIListHolder

---Gets the concrete runtime type of the node (e.g. "Node", "TextureNode", "DynamicBodyNode", "CameraNode").
---
---Example: `if self.node:get_type() == "DynamicBodyNode" then Log.info("physics body") end`
---A custom node type's own name ("Hurtbox"): see `get_base_type` for its built-in type.
---@return string The type name, such as "TextureNode"; a custom node type's own name ("Hurtbox"); "Unknown" for a destroyed node
function Node:get_type() end

---Gets the node's built-in type, also for a custom node type: "AreaNode" for a Hurtbox
---(an Area with its script); the same as `get_type()` for other nodes.
---
---Example: `if self.node:get_base_type() == "AreaNode" then Log.info("an area") end`
---@return string The built-in type name ("AreaNode" for a Hurtbox); "Unknown" for a destroyed node
function Node:get_base_type() end

---Is the node of that type: its custom type ("Hurtbox"), its built-in type ("AreaNode"), or "Node" (every node)?
---
---Example: `if other:is("Hurtbox") then other:get_script():take_damage(2) end`
---@param typeName string A custom type ("Hurtbox"), a built-in type ("AreaNode") or "Node"; case-sensitive
---@return boolean true when the node is of that type or inherits it; false for a destroyed node
function Node:is(typeName) end

---Gets the display/debug name of the node.
---
---Example: `Log.info("Spawned " .. self.node:get_name())`
---@return string The node's name as shown in the Scene tree; nil for a destroyed node
function Node:get_name() end

---Sets the display/debug name of the node.
---
---Example: `self.node:set_name("Enemy_" .. tostring(index))`
---@param name string The new name; get_node paths and Scene.find_node look it up by this from now on
function Node:set_name(name) end

---Gets the local position of the node.
---
---Example: `local x, y = self.node:get_position()`
---@return number x X in px, relative to the parent (0 for a destroyed node)
---@return number y Y in px, relative to the parent (+y is down)
function Node:get_position() end

---Sets the local position of the node.
---
---Example: `self.node:set_position(320, 180)`
---@param x number X in px, relative to the parent; a Vec2 or {x, y} here sets both
---@param y number Y in px, relative to the parent (+y is down); omit when x is a vector
function Node:set_position(x, y) end

---Translates the node position by the given delta offset.
---
---Example: `self.node:translate(self.speed * dt, 0)`
---@param dx number Pixels to move along X, in the parent's space; a Vec2 here moves on both axes
---@param dy number Pixels to move along Y (+y is down); omit when dx is a vector
function Node:translate(dx, dy) end

---Gets the local rotation of the node in degrees.
---
---Example: `local angle = self.node:get_rotation()`
---@return number rotation Degrees relative to the parent, clockwise; not wrapped to 0..360
function Node:get_rotation() end

---Sets the local rotation of the node in degrees.
---
---Example: `self.node:set_rotation(90)`
---@param degrees number Degrees relative to the parent, clockwise (0 = unrotated)
function Node:set_rotation(degrees) end

---Rotates the node by delta degrees.
---
---Example: `self.node:rotate(180 * dt)`
---@param degrees number Degrees to add to the rotation; positive turns clockwise
function Node:rotate(degrees) end

---Gets the local scale factor of the node.
---
---Example: `local sx, sy = self.node:get_scale()`
---@return number sx Horizontal multiplier relative to the parent (1 = as is, negative = flipped)
---@return number sy Vertical multiplier relative to the parent
function Node:get_scale() end

---Sets the local scale factor of the node.
---
---Example: `self.node:set_scale(-1, 1)`
---@param sx number Horizontal multiplier (1 = as is, 2 = twice as wide, negative flips)
---@param sy? number Vertical multiplier; omitted, the same as sx (a uniform scale)
function Node:set_scale(sx, sy) end

---Shows another image on a TextureNode or an AtlasSpriteNode (project-relative
---path, e.g. a `texture` script property). Returns false for other nodes or
---when the file can't be loaded.
---
---Example: `local sprite = self.node:get_node("Sprite"); sprite:set_texture("textures/coin.png")`
---@param path TexturePath|string Project-relative image path, e.g. "textures/coin.png"; the drawn size becomes the new image's
---@return boolean ok true when the image loaded; false for other node types or a file that can't be loaded (the old image stays)
function TextureNode:set_texture(path) end

---Gets the world-space global position of the node calculated from parent transforms.
---
---Example: `local gx, gy = self.node:get_global_position()`
---@return number x World X in px, with every parent's position, rotation and scale applied (computed before and after each frame's updates)
---@return number y World Y in px (+y is down)
function Node:get_global_position() end

---Gets the world-space global rotation of the node in degrees.
---
---Example: `local world_angle = self.node:get_global_rotation()`
---@return number rotation World rotation in degrees: this node's plus every parent's
function Node:get_global_rotation() end

---Checks if the node is actively updated in the scene loop.
---
---Example: `if not self.node:is_enabled() then return end`
---@return boolean This node's own Enabled flag (a disabled parent doesn't change it); false for a destroyed node
function Node:is_enabled() end

---Enables or disables updates for the node and its children.
---
---Example: `Scene.find_node("Enemy"):set_enabled(false)`
---@param enabled boolean false stops the node and its children: no update, no drawing, physics bodies stopped; true brings them back
function Node:set_enabled(enabled) end

---Checks if the node is rendered in the scene draw loop.
---
---Example: `local shown = self.node:is_visible()`
---@return boolean This node's own Visible flag (true even when a parent is hidden); false for a destroyed node
function Node:is_visible() end

---Sets whether the node is rendered.
---
---Example: `self.node:get_node("Shield"):set_visible(true)`
---@param visible boolean false stops this node drawing itself; it keeps updating, and its children still draw
function Node:set_visible(visible) end

---Flashes the node a colour (white on a hit), fading back over `seconds`.
---Works on anything drawn from a texture (sprites, animations, tile maps,
---text); a node with a material isn't flashed.
---
---Example: `self.node:get_child("Sprite"):flash("#ffffff", 0.12)`
---@param color? string|number[] "#rrggbb[aa]" or {r, g, b[, a]} 0..1 (default white; alpha: how strong)
---@param seconds? number Default 0.1
function Node:flash(color, seconds) end

---Blinks the node (and its children) on and off - invulnerability after a hit.
---
---Example: `self.node:blink(1.0)`
---@param seconds? number How long (default 1; 0 stops it)
---@param rate? number Changes per second (default 12)
function Node:blink(seconds, rate) end

---Squash and stretch: the node (and its children) stretches tall and thin,
---then springs back - jumps, landings, pickups. Negative amounts squash
---flat first.
---
---Example: `self.node:squash(-0.3, 0.25) -- landing`
---@param amount? number How much (default 0.25: 25% taller at first)
---@param seconds? number Default 0.3
function Node:squash(amount, seconds) end

---Returns the component path of this node if it is a component root, or nil if it is not an instance root.
---
---Example: `local path = self.node:get_component(); if path then Log.info("Instance of " .. path) end`
---@return string? The component file's project path when this node is a component instance's root; nil for any other node
function Node:get_component() end

---Returns the root node of the linked component instance this node belongs to, or nil if not part of a component.
---
---Example: `local root = self.node:get_instance_root(); if root then Log.info("Belongs to root " .. root:get_name()) end`
---@return Node? The root of the component instance holding this node (itself when it is that root); nil outside a component
function Node:get_instance_root() end

---Gets the parent node, or nil if this is a root node.
---
---Example: `local parent = self.node:get_parent(); if parent then Log.info(parent:get_name()) end`
---@return Node? The parent node; nil for the scene root, a detached node or a destroyed one
function Node:get_parent() end

---Returns an array of all direct child nodes.
---
---Example: `for _, child in ipairs(self.node:get_children()) do child:set_visible(false) end`
---@return Node[] The direct children in tree order, as a new list (changing it changes nothing); empty when there are none
function Node:get_children() end

---Adds a tag (group) to the node; false when it already has it.
---
---Example: `self.node:add_tag("enemies")`
---@param tag NodeTag|string The tag name, case-sensitive (the project's tags complete)
---@return boolean true when added; false when the node already had it
function Node:add_tag(tag) end

---Removes a tag (group) from the node; returns false when it did not have it.
---
---Example: `local removed = self.node:remove_tag("enemies")`
---@param tag NodeTag|string The tag name, case-sensitive
---@return boolean removed true when removed; false when the node did not have it
function Node:remove_tag(tag) end

---Checks whether the node has the given tag (group).
---
---Example: `if other:has_tag("player") then self:collect() end`
---@param tag NodeTag|string The tag name, case-sensitive
---@return boolean true when the node has the tag
function Node:has_tag(tag) end

---Returns an array of all tags (groups) on the node.
---
---Example: `for _, tag in ipairs(self.node:get_tags()) do Log.info(tag) end`
---@return string[] The node's tags as a new list; empty when it has none
function Node:get_tags() end

---Finds a direct child node by its exact name.
---
---Example: `local sprite = self.node:get_child("Sprite")`
---@param name NodeName|string The child's exact name, case-sensitive; only direct children are searched
---@return Node? The first direct child with that name, or nil
function Node:get_child(name) end

---Finds a node by path relative to this one: "Gun", "Body/Gun", "../Player", "." (self).
---
---Example: `local gun = self.node:get_node("Body/Gun")`
---@param path string Names separated by /, from this node: "Gun", "Body/Gun", ".." the parent, "." itself
---@return Node? node The node, or nil if there is none (a warning is logged once per path)
function Node:get_node(path) end

---Reparents a child node under this node.
---
---Example: `local item = Scene.find_node("Key"); self.node:add_child(item)`
---@param child Node The node to move under this one; it leaves its old parent and keeps its local position, so it can jump on screen
function Node:add_child(child) end

---Detaches a child node from this node.
---
---Example: `self.node:remove_child(self.node:get_child("Shield"))`
---@param child Node A direct child of this node (otherwise an error is logged); it is detached, not destroyed, and stops updating and drawing until added again
function Node:remove_child(child) end

---Removes this node and all its children from the active scene (at the end
---of the frame, so it's safe from its own update).
---
---Example: `self.node:destroy()`
function Node:destroy() end

---Removes this node and its children at the end of the frame (= destroy).
---
---Example: `if self.health <= 0 then self.node:queue_free() end`
function Node:queue_free() end

-- ----------------------------------------------------------------------------
-- Events
-- ----------------------------------------------------------------------------

---@alias NodeEvent
---| "entered_tree"       # (all nodes) the node joined the scene
---| "exited_tree"        # (all nodes) the node is being removed
---| "child_added"        # (all nodes) value: the child Node
---| "child_removed"      # (all nodes) value: the child Node
---| "parent_added"       # (all nodes) value: the new parent Node
---| "parent_removed"     # (all nodes) value: the old parent Node
---| "timeout"            # TimerNode: the duration elapsed
---| "tick"               # TimerNode: every frame while running, value: elapsed seconds
---| "body_entered"       # AreaNode: value: the Node that entered
---| "body_exited"        # AreaNode: value: the Node that left (nil if it was destroyed)
---| "collision_started"  # Static/Dynamic/Kinematic body, CharacterMover: value: the other Node
---| "collision_ended"    # Static/Dynamic/Kinematic body, CharacterMover: value: the other Node
---| "hit_started"        # RaycastNode: value: the Node the ray started hitting
---| "hit_ended"          # RaycastNode: value: the Node it stopped hitting
---| "particle_hit"       # ParticleEmitterNode (collision on): value: the Node a particle hit (particle_get_last_hit: where)
---| "animation_finished" # FrameAnimationNode / AnimationPlayerNode (non-looping); value: animation name
---| "state_changed"      # StateMachineNode: value: the state entered
---| "finished"           # SoundNode / MusicNode: playback ended; ParticleEmitterNode: a one-shot (or stopped) emitter's last particle died
---| "clicked"            # UIButtonNode
---| "value_changed"      # UI slider/checkbox/text input/dropdown/radio/knob/fader; value: new value
---| "submitted"          # UITextInputNode: value: text
---| "selected"           # UI list views: value: selected index
---| "row_selected"       # UITableNode: value: row index
---| "sorted"             # UITableNode
---| "item_clicked"       # UI toolbar: value: item id
---| "level_loaded"       # LdtkLevelNode: colliders/entities built; value: level identifier
---| "entity_spawned"     # LdtkLevelNode: value: the spawned Node
---| "revealed"           # TextNode: the typewriter reached the end
---| "line_shown"         # DialogueNode: a line was fully shown; value: its index (1-based)
---| "chosen"             # DialogueNode: a choice was taken; value: its index (1-based)

---Events every node raises.
---@alias NodeTreeEvent
---| "entered_tree"       # the node joined the scene
---| "exited_tree"        # the node is being removed
---| "child_added"        # value: the child Node
---| "child_removed"      # value: the child Node
---| "parent_added"       # value: the new parent Node
---| "parent_removed"     # value: the old parent Node

---Connects a handler to an event of this node (from any script). Handlers
---are removed automatically when the connecting script or this node is
---destroyed. A script also receives its own node's events as methods named
---`on_<event>` (e.g. `function MyScript:on_timeout() end`).
---
---Example: `self.conn = timer:connect("timeout", function(value, source) self:fire() end)`
---@param event NodeEvent|ProjectEvent|string Event name (custom ones: the project's `emit` names)
---@param handler fun(value: any, source: Node) Called with the event value and this node
---@return integer id Connection id for `disconnect`
function Node:connect(event, handler) end

---Removes a connection made with `connect`.
---
---Example: `local removed = timer:disconnect(self.conn)`
---@param id integer The id connect returned (ids are global: any node can remove any connection)
---@return boolean removed true when removed; false when no connection has that id
function Node:disconnect(id) end

---Raises a custom event on this node: calls the node script's `on_<event>`
---method and every handler connected to that event name.
---
---Example: `self.node:emit("health_changed", self.health)`
---@param event ProjectEvent|string The event name: calls this node's script on_<event> method, its Inspector Signals, then every connect handler (the project's custom events complete)
---@param value? any Passed to the handlers: a boolean, number, string or node (a table arrives as nil); nil for none
function Node:emit(event, value) end

-- node events begin (generated from the engine: lua_events_definitions_test.odin)

---@alias TimerNodeEvent NodeTreeEvent|"tick"|"timeout"|ProjectEvent
---Connects a handler to one of this node's events: tick (Every frame while the timer runs), timeout (The timer's duration elapsed); the tree events; custom ones.
---
---Example: `self.node:connect("tick", function(value, source) Log.info("tick") end)`
---@param event TimerNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: TimerNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function TimerNode:connect(event, handler) end

---@alias SpawnerNodeEvent NodeTreeEvent|"spawned"|"limit_reached"|"list_finished"|ProjectEvent
---Connects a handler to one of this node's events: spawned (The spawner made a node (the spawned root; spawn_info(node): its entry)), limit_reached (The spawner reached its Total Limit), list_finished (A Sequential spawner (Stop) spawned its last entry); the tree events; custom ones.
---
---Example: `self.node:connect("spawned", function(value, source) Log.info("spawned") end)`
---@param event SpawnerNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: SpawnerNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function SpawnerNode:connect(event, handler) end

---@alias LevelGeneratorNodeEvent NodeTreeEvent|"generated"|"generation_failed"|ProjectEvent
---Connects a handler to one of this node's events: generated (The level generator's level is in (its seed)), generation_failed (The level generator couldn't make the level (why)); the tree events; custom ones.
---
---Example: `self.node:connect("generated", function(value, source) Log.info("generated") end)`
---@param event LevelGeneratorNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: LevelGeneratorNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function LevelGeneratorNode:connect(event, handler) end

---@alias FrameAnimationNodeEvent NodeTreeEvent|"animation_finished"|ProjectEvent
---Connects a handler to one of this node's events: animation_finished (A non-looping animation ended (Aseprite: a tag's repeats are done)); the tree events; custom ones.
---
---Example: `self.node:connect("animation_finished", function(value, source) Log.info("animation_finished") end)`
---@param event FrameAnimationNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: FrameAnimationNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function FrameAnimationNode:connect(event, handler) end

---@alias AnimationPlayerNodeEvent NodeTreeEvent|"animation_finished"|"animation_event"|ProjectEvent
---Connects a handler to one of this node's events: animation_finished (A non-looping animation ended (Aseprite: a tag's repeats are done)), animation_event (A Method key of the animation fired (its method name)); the tree events; custom ones.
---
---Example: `self.node:connect("animation_finished", function(value, source) Log.info("animation_finished") end)`
---@param event AnimationPlayerNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: AnimationPlayerNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function AnimationPlayerNode:connect(event, handler) end

---@alias AsepriteNodeEvent NodeTreeEvent|"animation_finished"|"animation_looped"|"frame_changed"|ProjectEvent
---Connects a handler to one of this node's events: animation_finished (A non-looping animation ended (Aseprite: a tag's repeats are done)), animation_looped (An Aseprite tag started again (a repeat or a ping-pong turn)), frame_changed (The Aseprite node shows another frame (0-based)); the tree events; custom ones.
---
---Example: `self.node:connect("animation_finished", function(value, source) Log.info("animation_finished") end)`
---@param event AsepriteNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: AsepriteNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function AsepriteNode:connect(event, handler) end

---@alias StateMachineNodeEvent NodeTreeEvent|"state_changed"|ProjectEvent
---Connects a handler to one of this node's events: state_changed (The state machine entered a state); the tree events; custom ones.
---
---Example: `self.node:connect("state_changed", function(value, source) Log.info("state_changed") end)`
---@param event StateMachineNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: StateMachineNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function StateMachineNode:connect(event, handler) end

---@alias ParticleEmitterNodeEvent NodeTreeEvent|"particle_hit"|"finished"|ProjectEvent
---Connects a handler to one of this node's events: particle_hit (A particle hit a body (collision on; particle_get_last_hit: where)), finished (Playback (or the dialogue) ended); the tree events; custom ones.
---
---Example: `self.node:connect("particle_hit", function(value, source) Log.info("particle_hit") end)`
---@param event ParticleEmitterNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: ParticleEmitterNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function ParticleEmitterNode:connect(event, handler) end

---@alias SoundNodeEvent NodeTreeEvent|"finished"|ProjectEvent
---Connects a handler to one of this node's events: finished (Playback (or the dialogue) ended); the tree events; custom ones.
---
---Example: `self.node:connect("finished", function(value, source) Log.info("finished") end)`
---@param event SoundNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: SoundNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function SoundNode:connect(event, handler) end

---@alias MusicNodeEvent NodeTreeEvent|"finished"|ProjectEvent
---Connects a handler to one of this node's events: finished (Playback (or the dialogue) ended); the tree events; custom ones.
---
---Example: `self.node:connect("finished", function(value, source) Log.info("finished") end)`
---@param event MusicNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: MusicNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function MusicNode:connect(event, handler) end

---@alias StaticBodyNodeEvent NodeTreeEvent|"collision_started"|"collision_ended"|ProjectEvent
---Connects a handler to one of this node's events: collision_started (Contact with another body began), collision_ended (Contact with another body ended); the tree events; custom ones.
---
---Example: `self.node:connect("collision_started", function(value, source) Log.info("collision_started") end)`
---@param event StaticBodyNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: StaticBodyNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function StaticBodyNode:connect(event, handler) end

---@alias DynamicBodyNodeEvent NodeTreeEvent|"collision_started"|"collision_ended"|ProjectEvent
---Connects a handler to one of this node's events: collision_started (Contact with another body began), collision_ended (Contact with another body ended); the tree events; custom ones.
---
---Example: `self.node:connect("collision_started", function(value, source) Log.info("collision_started") end)`
---@param event DynamicBodyNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: DynamicBodyNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function DynamicBodyNode:connect(event, handler) end

---@alias KinematicBodyNodeEvent NodeTreeEvent|"collision_started"|"collision_ended"|ProjectEvent
---Connects a handler to one of this node's events: collision_started (Contact with another body began), collision_ended (Contact with another body ended); the tree events; custom ones.
---
---Example: `self.node:connect("collision_started", function(value, source) Log.info("collision_started") end)`
---@param event KinematicBodyNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: KinematicBodyNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function KinematicBodyNode:connect(event, handler) end

---@alias CharacterMoverNodeEvent NodeTreeEvent|"collision_started"|"collision_ended"|ProjectEvent
---Connects a handler to one of this node's events: collision_started (Contact with another body began), collision_ended (Contact with another body ended); the tree events; custom ones.
---
---Example: `self.node:connect("collision_started", function(value, source) Log.info("collision_started") end)`
---@param event CharacterMoverNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: CharacterMoverNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function CharacterMoverNode:connect(event, handler) end

---@alias AreaNodeEvent NodeTreeEvent|"body_entered"|"body_exited"|ProjectEvent
---Connects a handler to one of this node's events: body_entered (A body entered the area), body_exited (A body left the area); the tree events; custom ones.
---
---Example: `self.node:connect("body_entered", function(value, source) Log.info("body_entered") end)`
---@param event AreaNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: AreaNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function AreaNode:connect(event, handler) end

---@alias RaycastNodeEvent NodeTreeEvent|"hit_started"|"hit_ended"|ProjectEvent
---Connects a handler to one of this node's events: hit_started (The ray started hitting a node), hit_ended (The ray stopped hitting a node); the tree events; custom ones.
---
---Example: `self.node:connect("hit_started", function(value, source) Log.info("hit_started") end)`
---@param event RaycastNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: RaycastNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function RaycastNode:connect(event, handler) end

---@alias VisibilityNotifierNodeEvent NodeTreeEvent|"screen_entered"|"screen_exited"|ProjectEvent
---Connects a handler to one of this node's events: screen_entered (The camera started seeing it), screen_exited (The camera stopped seeing it); the tree events; custom ones.
---
---Example: `self.node:connect("screen_entered", function(value, source) Log.info("screen_entered") end)`
---@param event VisibilityNotifierNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: VisibilityNotifierNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function VisibilityNotifierNode:connect(event, handler) end

---@alias SkeletonNodeEvent NodeTreeEvent|"animation_finished"|"skeleton_event"|ProjectEvent
---Connects a handler to one of this node's events: animation_finished (A non-looping animation ended (Aseprite: a tag's repeats are done)), skeleton_event (An event key of the skeleton's animation fired (its name)); the tree events; custom ones.
---
---Example: `self.node:connect("animation_finished", function(value, source) Log.info("animation_finished") end)`
---@param event SkeletonNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: SkeletonNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function SkeletonNode:connect(event, handler) end

---@alias AdvancedCameraNodeEvent NodeTreeEvent|"became_active"|"became_inactive"|ProjectEvent
---Connects a handler to one of this node's events: became_active (The host camera switched to this advanced camera), became_inactive (Another advanced camera took over); the tree events; custom ones.
---
---Example: `self.node:connect("became_active", function(value, source) Log.info("became_active") end)`
---@param event AdvancedCameraNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: AdvancedCameraNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function AdvancedCameraNode:connect(event, handler) end

---@alias NavigationAgentNodeEvent NodeTreeEvent|"navigation_finished"|"target_unreachable"|ProjectEvent
---Connects a handler to one of this node's events: navigation_finished (The agent arrived at its target), target_unreachable (No way to the agent's target); the tree events; custom ones.
---
---Example: `self.node:connect("navigation_finished", function(value, source) Log.info("navigation_finished") end)`
---@param event NavigationAgentNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: NavigationAgentNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function NavigationAgentNode:connect(event, handler) end

---@alias PathFollowNodeEvent NodeTreeEvent|"path_finished"|"path_looped"|ProjectEvent
---Connects a handler to one of this node's events: path_finished (The follower reached the end of its path (loop: Stop)), path_looped (The follower wrapped round or turned back (Loop / Ping Pong)); the tree events; custom ones.
---
---Example: `self.node:connect("path_finished", function(value, source) Log.info("path_finished") end)`
---@param event PathFollowNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: PathFollowNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function PathFollowNode:connect(event, handler) end

---@alias LdtkLevelNodeEvent NodeTreeEvent|"level_loaded"|"entity_spawned"|ProjectEvent
---Connects a handler to one of this node's events: level_loaded (The LDtk level was built), entity_spawned (An LDtk entity was spawned); the tree events; custom ones.
---
---Example: `self.node:connect("level_loaded", function(value, source) Log.info("level_loaded") end)`
---@param event LdtkLevelNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: LdtkLevelNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function LdtkLevelNode:connect(event, handler) end

---@alias TextNodeEvent NodeTreeEvent|"revealed"|ProjectEvent
---Connects a handler to one of this node's events: revealed (The text finished revealing); the tree events; custom ones.
---
---Example: `self.node:connect("revealed", function(value, source) Log.info("revealed") end)`
---@param event TextNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: TextNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function TextNode:connect(event, handler) end

---@alias DialogueNodeEvent NodeTreeEvent|"line_shown"|"finished"|"chosen"|ProjectEvent
---Connects a handler to one of this node's events: line_shown (A dialogue line was fully shown (1-based)), finished (Playback (or the dialogue) ended), chosen (A dialogue choice was taken (1-based)); the tree events; custom ones.
---
---Example: `self.node:connect("line_shown", function(value, source) Log.info("line_shown") end)`
---@param event DialogueNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: DialogueNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function DialogueNode:connect(event, handler) end

---@alias LipSyncNodeEvent NodeTreeEvent|"finished"|ProjectEvent
---Connects a handler to one of this node's events: finished (Playback (or the dialogue) ended); the tree events; custom ones.
---
---Example: `self.node:connect("finished", function(value, source) Log.info("finished") end)`
---@param event LipSyncNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: LipSyncNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function LipSyncNode:connect(event, handler) end

---@alias UIButtonNodeEvent NodeTreeEvent|"clicked"|ProjectEvent
---Connects a handler to one of this node's events: clicked (The button was clicked); the tree events; custom ones.
---
---Example: `self.node:connect("clicked", function(value, source) Log.info("clicked") end)`
---@param event UIButtonNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: UIButtonNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function UIButtonNode:connect(event, handler) end

---@alias UISliderNodeEvent NodeTreeEvent|"value_changed"|ProjectEvent
---Connects a handler to one of this node's events: value_changed (The value changed); the tree events; custom ones.
---
---Example: `self.node:connect("value_changed", function(value, source) Log.info("value_changed") end)`
---@param event UISliderNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: UISliderNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function UISliderNode:connect(event, handler) end

---@alias UICheckboxNodeEvent NodeTreeEvent|"value_changed"|ProjectEvent
---Connects a handler to one of this node's events: value_changed (The value changed); the tree events; custom ones.
---
---Example: `self.node:connect("value_changed", function(value, source) Log.info("value_changed") end)`
---@param event UICheckboxNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: UICheckboxNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function UICheckboxNode:connect(event, handler) end

---@alias UITextInputNodeEvent NodeTreeEvent|"value_changed"|"submitted"|ProjectEvent
---Connects a handler to one of this node's events: value_changed (The value changed), submitted (Enter was pressed); the tree events; custom ones.
---
---Example: `self.node:connect("value_changed", function(value, source) Log.info("value_changed") end)`
---@param event UITextInputNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: UITextInputNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function UITextInputNode:connect(event, handler) end

---@alias UIDropdownNodeEvent NodeTreeEvent|"value_changed"|ProjectEvent
---Connects a handler to one of this node's events: value_changed (The value changed); the tree events; custom ones.
---
---Example: `self.node:connect("value_changed", function(value, source) Log.info("value_changed") end)`
---@param event UIDropdownNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: UIDropdownNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function UIDropdownNode:connect(event, handler) end

---@alias UIRadioGroupNodeEvent NodeTreeEvent|"value_changed"|ProjectEvent
---Connects a handler to one of this node's events: value_changed (The value changed); the tree events; custom ones.
---
---Example: `self.node:connect("value_changed", function(value, source) Log.info("value_changed") end)`
---@param event UIRadioGroupNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: UIRadioGroupNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function UIRadioGroupNode:connect(event, handler) end

---@alias UIToggleSwitchNodeEvent NodeTreeEvent|"value_changed"|ProjectEvent
---Connects a handler to one of this node's events: value_changed (The value changed); the tree events; custom ones.
---
---Example: `self.node:connect("value_changed", function(value, source) Log.info("value_changed") end)`
---@param event UIToggleSwitchNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: UIToggleSwitchNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function UIToggleSwitchNode:connect(event, handler) end

---@alias UIKnobNodeEvent NodeTreeEvent|"value_changed"|ProjectEvent
---Connects a handler to one of this node's events: value_changed (The value changed); the tree events; custom ones.
---
---Example: `self.node:connect("value_changed", function(value, source) Log.info("value_changed") end)`
---@param event UIKnobNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: UIKnobNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function UIKnobNode:connect(event, handler) end

---@alias UINotchedSliderNodeEvent NodeTreeEvent|"value_changed"|ProjectEvent
---Connects a handler to one of this node's events: value_changed (The value changed); the tree events; custom ones.
---
---Example: `self.node:connect("value_changed", function(value, source) Log.info("value_changed") end)`
---@param event UINotchedSliderNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: UINotchedSliderNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function UINotchedSliderNode:connect(event, handler) end

---@alias UIVolumeFaderNodeEvent NodeTreeEvent|"value_changed"|ProjectEvent
---Connects a handler to one of this node's events: value_changed (The value changed); the tree events; custom ones.
---
---Example: `self.node:connect("value_changed", function(value, source) Log.info("value_changed") end)`
---@param event UIVolumeFaderNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: UIVolumeFaderNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function UIVolumeFaderNode:connect(event, handler) end

---@alias UIListViewNodeEvent NodeTreeEvent|"selected"|ProjectEvent
---Connects a handler to one of this node's events: selected (The selection changed); the tree events; custom ones.
---
---Example: `self.node:connect("selected", function(value, source) Log.info("selected") end)`
---@param event UIListViewNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: UIListViewNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function UIListViewNode:connect(event, handler) end

---@alias UIUnorderedListNodeEvent NodeTreeEvent|"selected"|ProjectEvent
---Connects a handler to one of this node's events: selected (The selection changed); the tree events; custom ones.
---
---Example: `self.node:connect("selected", function(value, source) Log.info("selected") end)`
---@param event UIUnorderedListNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: UIUnorderedListNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function UIUnorderedListNode:connect(event, handler) end

---@alias UIOrderedListNodeEvent NodeTreeEvent|"selected"|ProjectEvent
---Connects a handler to one of this node's events: selected (The selection changed); the tree events; custom ones.
---
---Example: `self.node:connect("selected", function(value, source) Log.info("selected") end)`
---@param event UIOrderedListNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: UIOrderedListNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function UIOrderedListNode:connect(event, handler) end

---@alias UITableNodeEvent NodeTreeEvent|"row_selected"|"sorted"|ProjectEvent
---Connects a handler to one of this node's events: row_selected (A table row was selected), sorted (The table was sorted (by a header click or set_property)); the tree events; custom ones.
---
---Example: `self.node:connect("row_selected", function(value, source) Log.info("row_selected") end)`
---@param event UITableNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: UITableNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function UITableNode:connect(event, handler) end

---@alias UIToolbarNodeEvent NodeTreeEvent|"item_clicked"|ProjectEvent
---Connects a handler to one of this node's events: item_clicked (A toolbar item was clicked); the tree events; custom ones.
---
---Example: `self.node:connect("item_clicked", function(value, source) Log.info("item_clicked") end)`
---@param event UIToolbarNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: UIToolbarNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function UIToolbarNode:connect(event, handler) end

---@alias UITabContainerNodeEvent NodeTreeEvent|"tab_changed"|ProjectEvent
---Connects a handler to one of this node's events: tab_changed (Another tab was opened (0-based)); the tree events; custom ones.
---
---Example: `self.node:connect("tab_changed", function(value, source) Log.info("tab_changed") end)`
---@param event UITabContainerNodeEvent|string The event's name (the Signals tab lists them)
---@param handler fun(value: any, source: UITabContainerNode) Called with the event's value and the node that raised it
---@return integer id Connection id for `disconnect`
function UITabContainerNode:connect(event, handler) end
-- node events end

-- node properties begin (generated from the engine: lua_properties_definitions_test.odin)

---@class Node
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.

---@alias NodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("position")`
---@param path NodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: Node, path: "position"): Vec2
---@overload fun(self: Node, path: "scale"): Vec2
---@overload fun(self: Node, path: "rotation"): number
---@overload fun(self: Node, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: Node, path: "zIndex"): integer
---@overload fun(self: Node, path: "ySort"): boolean
---@overload fun(self: Node, path: "ySortOffset"): number
---@overload fun(self: Node, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: Node, path: "paused"): boolean
---@overload fun(self: Node, path: "enabled"): boolean
function Node:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("position", 100, 50)`
---@param path NodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: Node, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: Node, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: Node, path: "rotation", value: number)
---@overload fun(self: Node, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: Node, path: "zIndex", value: integer)
---@overload fun(self: Node, path: "ySort", value: boolean)
---@overload fun(self: Node, path: "ySortOffset", value: number)
---@overload fun(self: Node, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: Node, path: "paused", value: boolean)
---@overload fun(self: Node, path: "enabled", value: boolean)
function Node:set_property(path, value, y) end

---@class CameraNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field isCurrent boolean The camera the game renders through (one per scene).
---@field followMode "Static"|"SingleTarget"|"MultiTarget"|"Manual" Static: stays put. Single Target: follows its Follow Target. Multi Target: frames all t...
---@field dragType "None"|"SmoothDamp"|"SpringDamp"|"LookAhead"|"AutoSpeed" How the camera catches up with its target: none (locked), smooth damp, spring, look-ahe...
---@field targetPosition Vec2 Where the camera is heading (world px).
---@field currentPosition Vec2 Where the camera is now (world px).
---@field smoothDrag boolean Ease towards the target instead of snapping.
---@field smoothDragSpeed Vec2 Smooth-damp time per axis (s): higher lags more.
---@field springConstant number Spring Damp: stiffness pulling the camera to the target.
---@field dampingRatio number Spring Damp: 1 settles without overshoot, lower wobbles.
---@field predictionTime Vec2 Look Ahead: how far ahead of the target to aim, in seconds of its velocity.
---@field maxDistance Vec2 Most the camera trails its target while smoothing (px per axis).
---@field offset Vec2 Added to the target position (world px).
---@field smoothOffset boolean Ease offset changes in.
---@field smoothOffsetSpeed number How fast offset changes ease in.
---@field screenOffset Vec2 With Custom Screen Offset: where on screen the camera's position appears (px from the t...
---@field customScreenOffset boolean Put the camera's position at Screen Offset instead of the window's centre.
---@field currentRotation number The camera's rotation now (degrees).
---@field targetRotation number Rotation the camera turns to (degrees).
---@field allowRotation boolean Let the camera rotate (else it stays upright).
---@field smoothRotation boolean Ease rotation changes in.
---@field smoothRotationSpeed number How fast rotation eases in.
---@field zoom number Zoom now (1 = 100%, 2 = everything twice as big); set Target Zoom.
---@field targetZoom number Zoom the camera starts at and eases to (1 = 100%).
---@field smoothZoom boolean Ease zoom changes in.
---@field smoothZoomSpeed number How fast zoom eases in.
---@field minZoom number Smallest zoom (auto zoom and scripts).
---@field maxZoom number Largest zoom (auto zoom and scripts).
---@field autoZoom boolean Multi Target: zoom out to keep every target on screen.
---@field zoomMargin number Auto zoom: extra space around the targets (0.1 = 10%).
---@field hasLimits boolean Keep the view inside the left / right / top / bottom limits.
---@field smoothLimit boolean Ease into the limits instead of stopping hard.
---@field leftLimit number Left edge the view may not pass (world px).
---@field rightLimit number Right edge the view may not pass (world px).
---@field topLimit number Top edge the view may not pass (world px).
---@field bottomLimit number Bottom edge the view may not pass (world px).
---@field useHMargins boolean Dead zone: the target moves freely between the left / right margins before the camera f...
---@field useVMargins boolean Dead zone: the target moves freely between the top / bottom margins before the camera f...
---@field leftMargin number Left dead-zone margin (fraction of the screen).
---@field rightMargin number Right dead-zone margin (fraction of the screen).
---@field topMargin number Top dead-zone margin (fraction of the screen).
---@field bottomMargin number Bottom dead-zone margin (fraction of the screen).
---@field enableMouseFollow boolean Nudge the camera towards the mouse.
---@field mouseInfluence Vec2 How much the mouse pulls the camera per axis (0-1).
---@field shakePreset "Custom"|"Gunshot"|"Earthquake"|"Handheld"|"Explosion"|"Impact"|"Rumble"|"Vibration"|"Wobbly" The shake camera_shake / Camera.shake play (gunshot, earthquake...); Custom uses the se...
---@field isShaking boolean A shake is running.
---@field shakeSpeed number Custom shake: how fast it shakes.
---@field shakeIntensity number Custom shake: how far it moves (px).
---@field shakeTrauma number Shake strength now (0-1); decays over time.

---@alias CameraNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "isCurrent" # boolean - The camera the game renders through (one per scene).
---| "followMode" # "Static"|"SingleTarget"|"MultiTarget"|"Manual" - Static: stays put. Single Target: follows its Follow Target. Multi Target: frames all t...
---| "dragType" # "None"|"SmoothDamp"|"SpringDamp"|"LookAhead"|"AutoSpeed" - How the camera catches up with its target: none (locked), smooth damp, spring, look-ahe...
---| "targetPosition" # Vec2 - Where the camera is heading (world px).
---| "currentPosition" # Vec2 (runtime) - Where the camera is now (world px).
---| "smoothDrag" # boolean - Ease towards the target instead of snapping.
---| "smoothDragSpeed" # Vec2 - Smooth-damp time per axis (s): higher lags more.
---| "springConstant" # number - Spring Damp: stiffness pulling the camera to the target.
---| "dampingRatio" # number - Spring Damp: 1 settles without overshoot, lower wobbles.
---| "predictionTime" # Vec2 - Look Ahead: how far ahead of the target to aim, in seconds of its velocity.
---| "maxDistance" # Vec2 - Most the camera trails its target while smoothing (px per axis).
---| "offset" # Vec2 - Added to the target position (world px).
---| "smoothOffset" # boolean - Ease offset changes in.
---| "smoothOffsetSpeed" # number - How fast offset changes ease in.
---| "screenOffset" # Vec2 - With Custom Screen Offset: where on screen the camera's position appears (px from the t...
---| "customScreenOffset" # boolean - Put the camera's position at Screen Offset instead of the window's centre.
---| "currentRotation" # number (runtime) - The camera's rotation now (degrees).
---| "targetRotation" # number - Rotation the camera turns to (degrees).
---| "allowRotation" # boolean - Let the camera rotate (else it stays upright).
---| "smoothRotation" # boolean - Ease rotation changes in.
---| "smoothRotationSpeed" # number - How fast rotation eases in.
---| "zoom" # number (runtime) - Zoom now (1 = 100%, 2 = everything twice as big); set Target Zoom.
---| "targetZoom" # number - Zoom the camera starts at and eases to (1 = 100%).
---| "smoothZoom" # boolean - Ease zoom changes in.
---| "smoothZoomSpeed" # number - How fast zoom eases in.
---| "minZoom" # number - Smallest zoom (auto zoom and scripts).
---| "maxZoom" # number - Largest zoom (auto zoom and scripts).
---| "autoZoom" # boolean - Multi Target: zoom out to keep every target on screen.
---| "zoomMargin" # number - Auto zoom: extra space around the targets (0.1 = 10%).
---| "hasLimits" # boolean - Keep the view inside the left / right / top / bottom limits.
---| "smoothLimit" # boolean - Ease into the limits instead of stopping hard.
---| "leftLimit" # number - Left edge the view may not pass (world px).
---| "rightLimit" # number - Right edge the view may not pass (world px).
---| "topLimit" # number - Top edge the view may not pass (world px).
---| "bottomLimit" # number - Bottom edge the view may not pass (world px).
---| "useHMargins" # boolean - Dead zone: the target moves freely between the left / right margins before the camera f...
---| "useVMargins" # boolean - Dead zone: the target moves freely between the top / bottom margins before the camera f...
---| "leftMargin" # number - Left dead-zone margin (fraction of the screen).
---| "rightMargin" # number - Right dead-zone margin (fraction of the screen).
---| "topMargin" # number - Top dead-zone margin (fraction of the screen).
---| "bottomMargin" # number - Bottom dead-zone margin (fraction of the screen).
---| "enableMouseFollow" # boolean - Nudge the camera towards the mouse.
---| "mouseInfluence" # Vec2 - How much the mouse pulls the camera per axis (0-1).
---| "shakePreset" # "Custom"|"Gunshot"|"Earthquake"|"Handheld"|"Explosion"|"Impact"|"Rumble"|"Vibration"|"Wobbly" - The shake camera_shake / Camera.shake play (gunshot, earthquake...); Custom uses the se...
---| "isShaking" # boolean (runtime) - A shake is running.
---| "shakeSpeed" # number - Custom shake: how fast it shakes.
---| "shakeIntensity" # number - Custom shake: how far it moves (px).
---| "shakeTrauma" # number - Shake strength now (0-1); decays over time.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("isCurrent")`
---@param path CameraNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: CameraNode, path: "position"): Vec2
---@overload fun(self: CameraNode, path: "scale"): Vec2
---@overload fun(self: CameraNode, path: "rotation"): number
---@overload fun(self: CameraNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: CameraNode, path: "zIndex"): integer
---@overload fun(self: CameraNode, path: "ySort"): boolean
---@overload fun(self: CameraNode, path: "ySortOffset"): number
---@overload fun(self: CameraNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: CameraNode, path: "paused"): boolean
---@overload fun(self: CameraNode, path: "enabled"): boolean
---@overload fun(self: CameraNode, path: "isCurrent"): boolean
---@overload fun(self: CameraNode, path: "followMode"): "Static"|"SingleTarget"|"MultiTarget"|"Manual"
---@overload fun(self: CameraNode, path: "dragType"): "None"|"SmoothDamp"|"SpringDamp"|"LookAhead"|"AutoSpeed"
---@overload fun(self: CameraNode, path: "targetPosition"): Vec2
---@overload fun(self: CameraNode, path: "currentPosition"): Vec2
---@overload fun(self: CameraNode, path: "smoothDrag"): boolean
---@overload fun(self: CameraNode, path: "smoothDragSpeed"): Vec2
---@overload fun(self: CameraNode, path: "springConstant"): number
---@overload fun(self: CameraNode, path: "dampingRatio"): number
---@overload fun(self: CameraNode, path: "predictionTime"): Vec2
---@overload fun(self: CameraNode, path: "maxDistance"): Vec2
---@overload fun(self: CameraNode, path: "offset"): Vec2
---@overload fun(self: CameraNode, path: "smoothOffset"): boolean
---@overload fun(self: CameraNode, path: "smoothOffsetSpeed"): number
---@overload fun(self: CameraNode, path: "screenOffset"): Vec2
---@overload fun(self: CameraNode, path: "customScreenOffset"): boolean
---@overload fun(self: CameraNode, path: "currentRotation"): number
---@overload fun(self: CameraNode, path: "targetRotation"): number
---@overload fun(self: CameraNode, path: "allowRotation"): boolean
---@overload fun(self: CameraNode, path: "smoothRotation"): boolean
---@overload fun(self: CameraNode, path: "smoothRotationSpeed"): number
---@overload fun(self: CameraNode, path: "zoom"): number
---@overload fun(self: CameraNode, path: "targetZoom"): number
---@overload fun(self: CameraNode, path: "smoothZoom"): boolean
---@overload fun(self: CameraNode, path: "smoothZoomSpeed"): number
---@overload fun(self: CameraNode, path: "minZoom"): number
---@overload fun(self: CameraNode, path: "maxZoom"): number
---@overload fun(self: CameraNode, path: "autoZoom"): boolean
---@overload fun(self: CameraNode, path: "zoomMargin"): number
---@overload fun(self: CameraNode, path: "hasLimits"): boolean
---@overload fun(self: CameraNode, path: "smoothLimit"): boolean
---@overload fun(self: CameraNode, path: "leftLimit"): number
---@overload fun(self: CameraNode, path: "rightLimit"): number
---@overload fun(self: CameraNode, path: "topLimit"): number
---@overload fun(self: CameraNode, path: "bottomLimit"): number
---@overload fun(self: CameraNode, path: "useHMargins"): boolean
---@overload fun(self: CameraNode, path: "useVMargins"): boolean
---@overload fun(self: CameraNode, path: "leftMargin"): number
---@overload fun(self: CameraNode, path: "rightMargin"): number
---@overload fun(self: CameraNode, path: "topMargin"): number
---@overload fun(self: CameraNode, path: "bottomMargin"): number
---@overload fun(self: CameraNode, path: "enableMouseFollow"): boolean
---@overload fun(self: CameraNode, path: "mouseInfluence"): Vec2
---@overload fun(self: CameraNode, path: "shakePreset"): "Custom"|"Gunshot"|"Earthquake"|"Handheld"|"Explosion"|"Impact"|"Rumble"|"Vibration"|"Wobbly"
---@overload fun(self: CameraNode, path: "isShaking"): boolean
---@overload fun(self: CameraNode, path: "shakeSpeed"): number
---@overload fun(self: CameraNode, path: "shakeIntensity"): number
---@overload fun(self: CameraNode, path: "shakeTrauma"): number
function CameraNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("isCurrent", true)`
---@param path CameraNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: CameraNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "rotation", value: number)
---@overload fun(self: CameraNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: CameraNode, path: "zIndex", value: integer)
---@overload fun(self: CameraNode, path: "ySort", value: boolean)
---@overload fun(self: CameraNode, path: "ySortOffset", value: number)
---@overload fun(self: CameraNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: CameraNode, path: "paused", value: boolean)
---@overload fun(self: CameraNode, path: "enabled", value: boolean)
---@overload fun(self: CameraNode, path: "isCurrent", value: boolean)
---@overload fun(self: CameraNode, path: "followMode", value: "Static"|"SingleTarget"|"MultiTarget"|"Manual")
---@overload fun(self: CameraNode, path: "dragType", value: "None"|"SmoothDamp"|"SpringDamp"|"LookAhead"|"AutoSpeed")
---@overload fun(self: CameraNode, path: "targetPosition", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "currentPosition", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "smoothDrag", value: boolean)
---@overload fun(self: CameraNode, path: "smoothDragSpeed", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "springConstant", value: number)
---@overload fun(self: CameraNode, path: "dampingRatio", value: number)
---@overload fun(self: CameraNode, path: "predictionTime", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "maxDistance", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "offset", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "smoothOffset", value: boolean)
---@overload fun(self: CameraNode, path: "smoothOffsetSpeed", value: number)
---@overload fun(self: CameraNode, path: "screenOffset", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "customScreenOffset", value: boolean)
---@overload fun(self: CameraNode, path: "currentRotation", value: number)
---@overload fun(self: CameraNode, path: "targetRotation", value: number)
---@overload fun(self: CameraNode, path: "allowRotation", value: boolean)
---@overload fun(self: CameraNode, path: "smoothRotation", value: boolean)
---@overload fun(self: CameraNode, path: "smoothRotationSpeed", value: number)
---@overload fun(self: CameraNode, path: "zoom", value: number)
---@overload fun(self: CameraNode, path: "targetZoom", value: number)
---@overload fun(self: CameraNode, path: "smoothZoom", value: boolean)
---@overload fun(self: CameraNode, path: "smoothZoomSpeed", value: number)
---@overload fun(self: CameraNode, path: "minZoom", value: number)
---@overload fun(self: CameraNode, path: "maxZoom", value: number)
---@overload fun(self: CameraNode, path: "autoZoom", value: boolean)
---@overload fun(self: CameraNode, path: "zoomMargin", value: number)
---@overload fun(self: CameraNode, path: "hasLimits", value: boolean)
---@overload fun(self: CameraNode, path: "smoothLimit", value: boolean)
---@overload fun(self: CameraNode, path: "leftLimit", value: number)
---@overload fun(self: CameraNode, path: "rightLimit", value: number)
---@overload fun(self: CameraNode, path: "topLimit", value: number)
---@overload fun(self: CameraNode, path: "bottomLimit", value: number)
---@overload fun(self: CameraNode, path: "useHMargins", value: boolean)
---@overload fun(self: CameraNode, path: "useVMargins", value: boolean)
---@overload fun(self: CameraNode, path: "leftMargin", value: number)
---@overload fun(self: CameraNode, path: "rightMargin", value: number)
---@overload fun(self: CameraNode, path: "topMargin", value: number)
---@overload fun(self: CameraNode, path: "bottomMargin", value: number)
---@overload fun(self: CameraNode, path: "enableMouseFollow", value: boolean)
---@overload fun(self: CameraNode, path: "mouseInfluence", x: number|Vec2|number[], y?: number)
---@overload fun(self: CameraNode, path: "shakePreset", value: "Custom"|"Gunshot"|"Earthquake"|"Handheld"|"Explosion"|"Impact"|"Rumble"|"Vibration"|"Wobbly")
---@overload fun(self: CameraNode, path: "isShaking", value: boolean)
---@overload fun(self: CameraNode, path: "shakeSpeed", value: number)
---@overload fun(self: CameraNode, path: "shakeIntensity", value: number)
---@overload fun(self: CameraNode, path: "shakeTrauma", value: number)
function CameraNode:set_property(path, value, y) end

---@class SpawnerNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field mode "Single"|"All"|"Random"|"Sequential"|"Shuffle" What one spawn makes: Single (the first entry), All (every entry), Random (one by weigh...
---@field sequenceEnd "Loop"|"Ping_Pong"|"Stop" Sequential, after the last entry: Loop (the first again), Ping Pong (back down the list...
---@field count integer How many picks one spawn makes (a burst): with Random, Sequential and Shuffle each pick...
---@field parentMode "Scene_Root"|"Spawner_Parent"|"Spawner"|"Node_Path" Where spawned nodes go: the scene's root (they stay where spawned), the spawner's paren...
---@field parentPath string With Parent Mode Node Path: the node they go under, as a path from the spawner ("../Bul...
---@field offset Vec2 Where they appear, from the spawner (px, turning and flipping with it); each entry adds...
---@field inheritRotation boolean Spawned nodes take the spawner's world rotation (else upright).
---@field inheritScale boolean Spawned nodes take the spawner's world scale (a flipped spawner flips them).
---@field spread number Random turn of each spawned node (and its velocity), in degrees around the facing: 360 ...
---@field jitter Vec2 Random distance from the spawn point (px, either way on each axis).
---@field speed number Velocity (px/s) along the facing for spawned dynamic and kinematic bodies; 0 = none.
---@field autoSpawn boolean Spawn by itself every Interval seconds, after Start Delay.
---@field startDelay number Auto Spawn: seconds before the first spawn.
---@field interval number Auto Spawn: seconds between spawns.
---@field intervalJitter number Auto Spawn: up to this many seconds added to each interval at random.
---@field cooldown number Seconds after a spawn during which spawn() does nothing (fire rate).
---@field chance number How likely a spawn is to happen (0..1): 1 always.
---@field maxAlive integer At most this many spawned nodes in the scene at once (0 = no cap): spawning waits until...
---@field totalLimit integer Spawns ever (0 = no cap); then limit_reached, and no more until spawn_reset().
---@field usePool boolean Take instances from the scene's pool for each component (and return them when destroyed...
---@field spawnedTotal integer Nodes spawned so far (runtime, read-only).

---@alias SpawnerNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "mode" # "Single"|"All"|"Random"|"Sequential"|"Shuffle" - What one spawn makes: Single (the first entry), All (every entry), Random (one by weigh...
---| "sequenceEnd" # "Loop"|"Ping_Pong"|"Stop" - Sequential, after the last entry: Loop (the first again), Ping Pong (back down the list...
---| "count" # integer - How many picks one spawn makes (a burst): with Random, Sequential and Shuffle each pick...
---| "parentMode" # "Scene_Root"|"Spawner_Parent"|"Spawner"|"Node_Path" - Where spawned nodes go: the scene's root (they stay where spawned), the spawner's paren...
---| "parentPath" # string - With Parent Mode Node Path: the node they go under, as a path from the spawner ("../Bul...
---| "offset" # Vec2 - Where they appear, from the spawner (px, turning and flipping with it); each entry adds...
---| "inheritRotation" # boolean - Spawned nodes take the spawner's world rotation (else upright).
---| "inheritScale" # boolean - Spawned nodes take the spawner's world scale (a flipped spawner flips them).
---| "spread" # number - Random turn of each spawned node (and its velocity), in degrees around the facing: 360 ...
---| "jitter" # Vec2 - Random distance from the spawn point (px, either way on each axis).
---| "speed" # number - Velocity (px/s) along the facing for spawned dynamic and kinematic bodies; 0 = none.
---| "autoSpawn" # boolean - Spawn by itself every Interval seconds, after Start Delay.
---| "startDelay" # number - Auto Spawn: seconds before the first spawn.
---| "interval" # number - Auto Spawn: seconds between spawns.
---| "intervalJitter" # number - Auto Spawn: up to this many seconds added to each interval at random.
---| "cooldown" # number - Seconds after a spawn during which spawn() does nothing (fire rate).
---| "chance" # number - How likely a spawn is to happen (0..1): 1 always.
---| "maxAlive" # integer - At most this many spawned nodes in the scene at once (0 = no cap): spawning waits until...
---| "totalLimit" # integer - Spawns ever (0 = no cap); then limit_reached, and no more until spawn_reset().
---| "usePool" # boolean - Take instances from the scene's pool for each component (and return them when destroyed...
---| "spawnedTotal" # integer (runtime) - Nodes spawned so far (runtime, read-only).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("mode")`
---@param path SpawnerNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: SpawnerNode, path: "position"): Vec2
---@overload fun(self: SpawnerNode, path: "scale"): Vec2
---@overload fun(self: SpawnerNode, path: "rotation"): number
---@overload fun(self: SpawnerNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: SpawnerNode, path: "zIndex"): integer
---@overload fun(self: SpawnerNode, path: "ySort"): boolean
---@overload fun(self: SpawnerNode, path: "ySortOffset"): number
---@overload fun(self: SpawnerNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: SpawnerNode, path: "paused"): boolean
---@overload fun(self: SpawnerNode, path: "enabled"): boolean
---@overload fun(self: SpawnerNode, path: "mode"): "Single"|"All"|"Random"|"Sequential"|"Shuffle"
---@overload fun(self: SpawnerNode, path: "sequenceEnd"): "Loop"|"Ping_Pong"|"Stop"
---@overload fun(self: SpawnerNode, path: "count"): integer
---@overload fun(self: SpawnerNode, path: "parentMode"): "Scene_Root"|"Spawner_Parent"|"Spawner"|"Node_Path"
---@overload fun(self: SpawnerNode, path: "parentPath"): string
---@overload fun(self: SpawnerNode, path: "offset"): Vec2
---@overload fun(self: SpawnerNode, path: "inheritRotation"): boolean
---@overload fun(self: SpawnerNode, path: "inheritScale"): boolean
---@overload fun(self: SpawnerNode, path: "spread"): number
---@overload fun(self: SpawnerNode, path: "jitter"): Vec2
---@overload fun(self: SpawnerNode, path: "speed"): number
---@overload fun(self: SpawnerNode, path: "autoSpawn"): boolean
---@overload fun(self: SpawnerNode, path: "startDelay"): number
---@overload fun(self: SpawnerNode, path: "interval"): number
---@overload fun(self: SpawnerNode, path: "intervalJitter"): number
---@overload fun(self: SpawnerNode, path: "cooldown"): number
---@overload fun(self: SpawnerNode, path: "chance"): number
---@overload fun(self: SpawnerNode, path: "maxAlive"): integer
---@overload fun(self: SpawnerNode, path: "totalLimit"): integer
---@overload fun(self: SpawnerNode, path: "usePool"): boolean
---@overload fun(self: SpawnerNode, path: "spawnedTotal"): integer
function SpawnerNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("mode", "All")`
---@param path SpawnerNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: SpawnerNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: SpawnerNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: SpawnerNode, path: "rotation", value: number)
---@overload fun(self: SpawnerNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: SpawnerNode, path: "zIndex", value: integer)
---@overload fun(self: SpawnerNode, path: "ySort", value: boolean)
---@overload fun(self: SpawnerNode, path: "ySortOffset", value: number)
---@overload fun(self: SpawnerNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: SpawnerNode, path: "paused", value: boolean)
---@overload fun(self: SpawnerNode, path: "enabled", value: boolean)
---@overload fun(self: SpawnerNode, path: "mode", value: "Single"|"All"|"Random"|"Sequential"|"Shuffle")
---@overload fun(self: SpawnerNode, path: "sequenceEnd", value: "Loop"|"Ping_Pong"|"Stop")
---@overload fun(self: SpawnerNode, path: "count", value: integer)
---@overload fun(self: SpawnerNode, path: "parentMode", value: "Scene_Root"|"Spawner_Parent"|"Spawner"|"Node_Path")
---@overload fun(self: SpawnerNode, path: "parentPath", value: string)
---@overload fun(self: SpawnerNode, path: "offset", x: number|Vec2|number[], y?: number)
---@overload fun(self: SpawnerNode, path: "inheritRotation", value: boolean)
---@overload fun(self: SpawnerNode, path: "inheritScale", value: boolean)
---@overload fun(self: SpawnerNode, path: "spread", value: number)
---@overload fun(self: SpawnerNode, path: "jitter", x: number|Vec2|number[], y?: number)
---@overload fun(self: SpawnerNode, path: "speed", value: number)
---@overload fun(self: SpawnerNode, path: "autoSpawn", value: boolean)
---@overload fun(self: SpawnerNode, path: "startDelay", value: number)
---@overload fun(self: SpawnerNode, path: "interval", value: number)
---@overload fun(self: SpawnerNode, path: "intervalJitter", value: number)
---@overload fun(self: SpawnerNode, path: "cooldown", value: number)
---@overload fun(self: SpawnerNode, path: "chance", value: number)
---@overload fun(self: SpawnerNode, path: "maxAlive", value: integer)
---@overload fun(self: SpawnerNode, path: "totalLimit", value: integer)
---@overload fun(self: SpawnerNode, path: "usePool", value: boolean)
---@overload fun(self: SpawnerNode, path: "spawnedTotal", value: integer)
function SpawnerNode:set_property(path, value, y) end

---@class LevelGeneratorNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field generator string The generator it makes levels from (a .levelgen.json).
---@field tilemap string The TileMap it fills, as a path from this node; empty: its first TileMap child, else it...
---@field seed integer The level's seed: the same seed, the same level (0: the generator's own).
---@field randomSeed boolean A new random seed every time it generates (Last Seed tells which).
---@field generateOnReady boolean Generate when the scene starts (else call generate() or connect a signal to it).
---@field background boolean Generate on a worker thread while the game runs; the level goes in when it is done (gen...
---@field attempts integer With Random Seed: seeds tried when the generator refuses a level (a Check node: too lit...
---@field lastSeed integer The seed of the last level made (runtime, read-only).

---@alias LevelGeneratorNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "generator" # string - The generator it makes levels from (a .levelgen.json).
---| "tilemap" # string - The TileMap it fills, as a path from this node; empty: its first TileMap child, else it...
---| "seed" # integer - The level's seed: the same seed, the same level (0: the generator's own).
---| "randomSeed" # boolean - A new random seed every time it generates (Last Seed tells which).
---| "generateOnReady" # boolean - Generate when the scene starts (else call generate() or connect a signal to it).
---| "background" # boolean - Generate on a worker thread while the game runs; the level goes in when it is done (gen...
---| "attempts" # integer - With Random Seed: seeds tried when the generator refuses a level (a Check node: too lit...
---| "lastSeed" # integer (runtime) - The seed of the last level made (runtime, read-only).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("generator")`
---@param path LevelGeneratorNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: LevelGeneratorNode, path: "position"): Vec2
---@overload fun(self: LevelGeneratorNode, path: "scale"): Vec2
---@overload fun(self: LevelGeneratorNode, path: "rotation"): number
---@overload fun(self: LevelGeneratorNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: LevelGeneratorNode, path: "zIndex"): integer
---@overload fun(self: LevelGeneratorNode, path: "ySort"): boolean
---@overload fun(self: LevelGeneratorNode, path: "ySortOffset"): number
---@overload fun(self: LevelGeneratorNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: LevelGeneratorNode, path: "paused"): boolean
---@overload fun(self: LevelGeneratorNode, path: "enabled"): boolean
---@overload fun(self: LevelGeneratorNode, path: "generator"): string
---@overload fun(self: LevelGeneratorNode, path: "tilemap"): string
---@overload fun(self: LevelGeneratorNode, path: "seed"): integer
---@overload fun(self: LevelGeneratorNode, path: "randomSeed"): boolean
---@overload fun(self: LevelGeneratorNode, path: "generateOnReady"): boolean
---@overload fun(self: LevelGeneratorNode, path: "background"): boolean
---@overload fun(self: LevelGeneratorNode, path: "attempts"): integer
---@overload fun(self: LevelGeneratorNode, path: "lastSeed"): integer
function LevelGeneratorNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("generator", "text")`
---@param path LevelGeneratorNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: LevelGeneratorNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: LevelGeneratorNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: LevelGeneratorNode, path: "rotation", value: number)
---@overload fun(self: LevelGeneratorNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: LevelGeneratorNode, path: "zIndex", value: integer)
---@overload fun(self: LevelGeneratorNode, path: "ySort", value: boolean)
---@overload fun(self: LevelGeneratorNode, path: "ySortOffset", value: number)
---@overload fun(self: LevelGeneratorNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: LevelGeneratorNode, path: "paused", value: boolean)
---@overload fun(self: LevelGeneratorNode, path: "enabled", value: boolean)
---@overload fun(self: LevelGeneratorNode, path: "generator", value: string)
---@overload fun(self: LevelGeneratorNode, path: "tilemap", value: string)
---@overload fun(self: LevelGeneratorNode, path: "seed", value: integer)
---@overload fun(self: LevelGeneratorNode, path: "randomSeed", value: boolean)
---@overload fun(self: LevelGeneratorNode, path: "generateOnReady", value: boolean)
---@overload fun(self: LevelGeneratorNode, path: "background", value: boolean)
---@overload fun(self: LevelGeneratorNode, path: "attempts", value: integer)
---@overload fun(self: LevelGeneratorNode, path: "lastSeed", value: integer)
function LevelGeneratorNode:set_property(path, value, y) end

---@class TextureNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field origin Vec2 Where in the image the position is, and what it rotates and scales around: a fraction o...
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field tint number[] Multiplies the texture's colours (white = unchanged; alpha fades it).

---@alias TextureNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "origin" # Vec2 - Where in the image the position is, and what it rotates and scales around: a fraction o...
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "tint" # number[] - Multiplies the texture's colours (white = unchanged; alpha fades it).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("tint")`
---@param path TextureNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: TextureNode, path: "position"): Vec2
---@overload fun(self: TextureNode, path: "scale"): Vec2
---@overload fun(self: TextureNode, path: "rotation"): number
---@overload fun(self: TextureNode, path: "origin"): Vec2
---@overload fun(self: TextureNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: TextureNode, path: "zIndex"): integer
---@overload fun(self: TextureNode, path: "ySort"): boolean
---@overload fun(self: TextureNode, path: "ySortOffset"): number
---@overload fun(self: TextureNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: TextureNode, path: "paused"): boolean
---@overload fun(self: TextureNode, path: "enabled"): boolean
---@overload fun(self: TextureNode, path: "tint"): number[]
function TextureNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("tint", "#ff8800")`
---@param path TextureNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: TextureNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: TextureNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: TextureNode, path: "rotation", value: number)
---@overload fun(self: TextureNode, path: "origin", x: number|Vec2|number[], y?: number)
---@overload fun(self: TextureNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: TextureNode, path: "zIndex", value: integer)
---@overload fun(self: TextureNode, path: "ySort", value: boolean)
---@overload fun(self: TextureNode, path: "ySortOffset", value: number)
---@overload fun(self: TextureNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: TextureNode, path: "paused", value: boolean)
---@overload fun(self: TextureNode, path: "enabled", value: boolean)
---@overload fun(self: TextureNode, path: "tint", value: number[])
function TextureNode:set_property(path, value, y) end

---@class AtlasSpriteNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field origin Vec2 Where in the image the position is, and what it rotates and scales around: a fraction o...
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field tint number[] Multiplies the texture's colours (white = unchanged; alpha fades it).

---@alias AtlasSpriteNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "origin" # Vec2 - Where in the image the position is, and what it rotates and scales around: a fraction o...
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "tint" # number[] - Multiplies the texture's colours (white = unchanged; alpha fades it).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("tint")`
---@param path AtlasSpriteNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: AtlasSpriteNode, path: "position"): Vec2
---@overload fun(self: AtlasSpriteNode, path: "scale"): Vec2
---@overload fun(self: AtlasSpriteNode, path: "rotation"): number
---@overload fun(self: AtlasSpriteNode, path: "origin"): Vec2
---@overload fun(self: AtlasSpriteNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: AtlasSpriteNode, path: "zIndex"): integer
---@overload fun(self: AtlasSpriteNode, path: "ySort"): boolean
---@overload fun(self: AtlasSpriteNode, path: "ySortOffset"): number
---@overload fun(self: AtlasSpriteNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: AtlasSpriteNode, path: "paused"): boolean
---@overload fun(self: AtlasSpriteNode, path: "enabled"): boolean
---@overload fun(self: AtlasSpriteNode, path: "tint"): number[]
function AtlasSpriteNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("tint", "#ff8800")`
---@param path AtlasSpriteNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: AtlasSpriteNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: AtlasSpriteNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: AtlasSpriteNode, path: "rotation", value: number)
---@overload fun(self: AtlasSpriteNode, path: "origin", x: number|Vec2|number[], y?: number)
---@overload fun(self: AtlasSpriteNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: AtlasSpriteNode, path: "zIndex", value: integer)
---@overload fun(self: AtlasSpriteNode, path: "ySort", value: boolean)
---@overload fun(self: AtlasSpriteNode, path: "ySortOffset", value: number)
---@overload fun(self: AtlasSpriteNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: AtlasSpriteNode, path: "paused", value: boolean)
---@overload fun(self: AtlasSpriteNode, path: "enabled", value: boolean)
---@overload fun(self: AtlasSpriteNode, path: "tint", value: number[])
function AtlasSpriteNode:set_property(path, value, y) end

---@class FrameAnimationNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field origin Vec2 Where in the image the position is, and what it rotates and scales around: a fraction o...
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.

---@alias FrameAnimationNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "origin" # Vec2 - Where in the image the position is, and what it rotates and scales around: a fraction o...
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("position")`
---@param path FrameAnimationNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: FrameAnimationNode, path: "position"): Vec2
---@overload fun(self: FrameAnimationNode, path: "scale"): Vec2
---@overload fun(self: FrameAnimationNode, path: "rotation"): number
---@overload fun(self: FrameAnimationNode, path: "origin"): Vec2
---@overload fun(self: FrameAnimationNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: FrameAnimationNode, path: "zIndex"): integer
---@overload fun(self: FrameAnimationNode, path: "ySort"): boolean
---@overload fun(self: FrameAnimationNode, path: "ySortOffset"): number
---@overload fun(self: FrameAnimationNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: FrameAnimationNode, path: "paused"): boolean
---@overload fun(self: FrameAnimationNode, path: "enabled"): boolean
function FrameAnimationNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("position", 100, 50)`
---@param path FrameAnimationNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: FrameAnimationNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: FrameAnimationNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: FrameAnimationNode, path: "rotation", value: number)
---@overload fun(self: FrameAnimationNode, path: "origin", x: number|Vec2|number[], y?: number)
---@overload fun(self: FrameAnimationNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: FrameAnimationNode, path: "zIndex", value: integer)
---@overload fun(self: FrameAnimationNode, path: "ySort", value: boolean)
---@overload fun(self: FrameAnimationNode, path: "ySortOffset", value: number)
---@overload fun(self: FrameAnimationNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: FrameAnimationNode, path: "paused", value: boolean)
---@overload fun(self: FrameAnimationNode, path: "enabled", value: boolean)
function FrameAnimationNode:set_property(path, value, y) end

---@class AnimationPlayerNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field origin Vec2 Where in the image the position is, and what it rotates and scales around: a fraction o...
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field reverse boolean Play the animation backwards.
---@field autoplay boolean Start playing the current animation when the node becomes ready.
---@field fps number Frames per second of the animations that don't set their own (the Animation tab's FPS b...
---@field defaultAnimation string The animation selected when the scene loads (it plays with Autoplay); empty = the one s...

---@alias AnimationPlayerNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "origin" # Vec2 - Where in the image the position is, and what it rotates and scales around: a fraction o...
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "reverse" # boolean - Play the animation backwards.
---| "autoplay" # boolean - Start playing the current animation when the node becomes ready.
---| "fps" # number - Frames per second of the animations that don't set their own (the Animation tab's FPS b...
---| "defaultAnimation" # string - The animation selected when the scene loads (it plays with Autoplay); empty = the one s...

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("reverse")`
---@param path AnimationPlayerNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: AnimationPlayerNode, path: "position"): Vec2
---@overload fun(self: AnimationPlayerNode, path: "scale"): Vec2
---@overload fun(self: AnimationPlayerNode, path: "rotation"): number
---@overload fun(self: AnimationPlayerNode, path: "origin"): Vec2
---@overload fun(self: AnimationPlayerNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: AnimationPlayerNode, path: "zIndex"): integer
---@overload fun(self: AnimationPlayerNode, path: "ySort"): boolean
---@overload fun(self: AnimationPlayerNode, path: "ySortOffset"): number
---@overload fun(self: AnimationPlayerNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: AnimationPlayerNode, path: "paused"): boolean
---@overload fun(self: AnimationPlayerNode, path: "enabled"): boolean
---@overload fun(self: AnimationPlayerNode, path: "reverse"): boolean
---@overload fun(self: AnimationPlayerNode, path: "autoplay"): boolean
---@overload fun(self: AnimationPlayerNode, path: "fps"): number
---@overload fun(self: AnimationPlayerNode, path: "defaultAnimation"): string
function AnimationPlayerNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("reverse", true)`
---@param path AnimationPlayerNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: AnimationPlayerNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: AnimationPlayerNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: AnimationPlayerNode, path: "rotation", value: number)
---@overload fun(self: AnimationPlayerNode, path: "origin", x: number|Vec2|number[], y?: number)
---@overload fun(self: AnimationPlayerNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: AnimationPlayerNode, path: "zIndex", value: integer)
---@overload fun(self: AnimationPlayerNode, path: "ySort", value: boolean)
---@overload fun(self: AnimationPlayerNode, path: "ySortOffset", value: number)
---@overload fun(self: AnimationPlayerNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: AnimationPlayerNode, path: "paused", value: boolean)
---@overload fun(self: AnimationPlayerNode, path: "enabled", value: boolean)
---@overload fun(self: AnimationPlayerNode, path: "reverse", value: boolean)
---@overload fun(self: AnimationPlayerNode, path: "autoplay", value: boolean)
---@overload fun(self: AnimationPlayerNode, path: "fps", value: number)
---@overload fun(self: AnimationPlayerNode, path: "defaultAnimation", value: string)
function AnimationPlayerNode:set_property(path, value, y) end

---@class AsepriteNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field origin Vec2 Where in the image the position is, and what it rotates and scales around: a fraction o...
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field file string The Aseprite file (.aseprite / .ase, project-relative). Saving it in Aseprite updates t...
---@field animation string The tag played (its direction and repeat count as set in Aseprite); empty = every frame...
---@field autoplay boolean Start the animation when the node becomes ready.
---@field loop boolean Tags without a repeat count loop; off: they play once.
---@field speed number Playback speed (1 = the frame durations set in Aseprite).
---@field frame integer The frame shown (0-based): where playing starts, or where it stopped.
---@field hideLayers string Layers not drawn (names, comma separated; a group hides its layers).
---@field showLayers string Layers hidden in the file but drawn anyway (names, comma separated).
---@field pivotSlice string A slice with a pivot (set in Aseprite): the node's origin follows it, frame by frame. E...
---@field tint number[] Multiplies the sprite's colours.

---@alias AsepriteNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "origin" # Vec2 - Where in the image the position is, and what it rotates and scales around: a fraction o...
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "file" # string - The Aseprite file (.aseprite / .ase, project-relative). Saving it in Aseprite updates t...
---| "animation" # string - The tag played (its direction and repeat count as set in Aseprite); empty = every frame...
---| "autoplay" # boolean - Start the animation when the node becomes ready.
---| "loop" # boolean - Tags without a repeat count loop; off: they play once.
---| "speed" # number - Playback speed (1 = the frame durations set in Aseprite).
---| "frame" # integer - The frame shown (0-based): where playing starts, or where it stopped.
---| "hideLayers" # string - Layers not drawn (names, comma separated; a group hides its layers).
---| "showLayers" # string - Layers hidden in the file but drawn anyway (names, comma separated).
---| "pivotSlice" # string - A slice with a pivot (set in Aseprite): the node's origin follows it, frame by frame. E...
---| "tint" # number[] - Multiplies the sprite's colours.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("file")`
---@param path AsepriteNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: AsepriteNode, path: "position"): Vec2
---@overload fun(self: AsepriteNode, path: "scale"): Vec2
---@overload fun(self: AsepriteNode, path: "rotation"): number
---@overload fun(self: AsepriteNode, path: "origin"): Vec2
---@overload fun(self: AsepriteNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: AsepriteNode, path: "zIndex"): integer
---@overload fun(self: AsepriteNode, path: "ySort"): boolean
---@overload fun(self: AsepriteNode, path: "ySortOffset"): number
---@overload fun(self: AsepriteNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: AsepriteNode, path: "paused"): boolean
---@overload fun(self: AsepriteNode, path: "enabled"): boolean
---@overload fun(self: AsepriteNode, path: "file"): string
---@overload fun(self: AsepriteNode, path: "animation"): string
---@overload fun(self: AsepriteNode, path: "autoplay"): boolean
---@overload fun(self: AsepriteNode, path: "loop"): boolean
---@overload fun(self: AsepriteNode, path: "speed"): number
---@overload fun(self: AsepriteNode, path: "frame"): integer
---@overload fun(self: AsepriteNode, path: "hideLayers"): string
---@overload fun(self: AsepriteNode, path: "showLayers"): string
---@overload fun(self: AsepriteNode, path: "pivotSlice"): string
---@overload fun(self: AsepriteNode, path: "tint"): number[]
function AsepriteNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("file", "text")`
---@param path AsepriteNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: AsepriteNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: AsepriteNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: AsepriteNode, path: "rotation", value: number)
---@overload fun(self: AsepriteNode, path: "origin", x: number|Vec2|number[], y?: number)
---@overload fun(self: AsepriteNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: AsepriteNode, path: "zIndex", value: integer)
---@overload fun(self: AsepriteNode, path: "ySort", value: boolean)
---@overload fun(self: AsepriteNode, path: "ySortOffset", value: number)
---@overload fun(self: AsepriteNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: AsepriteNode, path: "paused", value: boolean)
---@overload fun(self: AsepriteNode, path: "enabled", value: boolean)
---@overload fun(self: AsepriteNode, path: "file", value: string)
---@overload fun(self: AsepriteNode, path: "animation", value: string)
---@overload fun(self: AsepriteNode, path: "autoplay", value: boolean)
---@overload fun(self: AsepriteNode, path: "loop", value: boolean)
---@overload fun(self: AsepriteNode, path: "speed", value: number)
---@overload fun(self: AsepriteNode, path: "frame", value: integer)
---@overload fun(self: AsepriteNode, path: "hideLayers", value: string)
---@overload fun(self: AsepriteNode, path: "showLayers", value: string)
---@overload fun(self: AsepriteNode, path: "pivotSlice", value: string)
---@overload fun(self: AsepriteNode, path: "tint", value: number[])
function AsepriteNode:set_property(path, value, y) end

---@class ParticleEmitterNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field subEmitter string Sub-emitter: another Particle Emitter, as a path from this node (e.g. a child's name), ...
---@field subEmitterOn "Death"|"Hit"|"Both" When the sub-emitter bursts: a particle's Death (its lifetime ended), a Hit on a body (...
---@field subEmitterAmount integer Particles the sub-emitter emits each time.

---@alias ParticleEmitterNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "emitter.amount" # integer - Particles alive at once (the pool size).
---| "emitter.lifetime" # number - Seconds each particle lives.
---| "emitter.lifetimeVariance" # number - Each particle's lifetime varies by up to this fraction (0.3: 70%..130% of Lifetime).
---| "emitter.position" # Vec2 (runtime) - Emitter position (follows the node).
---| "emitter.burst" # number - 0 spreads emission evenly over the lifetime, 1 releases every particle at once.
---| "emitter.size" # Vec2 - Particle size (px).
---| "emitter.sizeVariance" # number - How much of Size Spread is applied at random (0-1).
---| "emitter.sizeSpread" # number - Largest random size change (px).
---| "emitter.scaleStart" # Vec2 - Scale at birth (multiplies Size).
---| "emitter.scaleEnd" # Vec2 - Scale at death; it interpolates over the lifetime.
---| "emitter.rotation" # number - Starting rotation (degrees).
---| "emitter.rotationVariance" # number - How much of Rotation Spread is applied at random (0-1).
---| "emitter.rotationSpread" # number - Largest random rotation change (degrees).
---| "emitter.torque" # number - Spin speed (degrees/s).
---| "emitter.torqueVariance" # number - How much of Torque Spread is applied at random (0-1).
---| "emitter.torqueSpread" # number - Largest random spin change (degrees/s).
---| "emitter.torqueAcceleration" # number - Change in spin speed per second.
---| "emitter.useColorRamp" # boolean - Colour over the lifetime from the colour ramp (else Particle Color to Color End).
---| "emitter.particleColor" # number[] - Colour at birth.
---| "emitter.colorEnd" # number[] - Colour at death.
---| "emitter.colorVariance" # number - Random colour variation (0-1).
---| "emitter.spread" # Vec2 - Particles start anywhere within ± this box around the emitter (px).
---| "emitter.velocity" # number - Starting speed (px/s).
---| "emitter.velocityVariance" # number - How much of Velocity Spread is applied at random (0-1).
---| "emitter.velocitySpread" # number - Largest random speed change (px/s).
---| "emitter.velocityScale" # number - Multiplies every particle's movement (slow motion < 1).
---| "emitter.acceleration" # number - Change in speed per second along the direction of travel.
---| "emitter.angle" # number - Emission direction (degrees; 0 = right, 90 = down).
---| "emitter.angleVariance" # number - How much of Angle Spread is applied at random (0-1).
---| "emitter.angleSpread" # number - Largest random change to the angle (± degrees; 180 = all round).
---| "emitter.gravityDirection" # Vec2 - Direction gravity pulls particles.
---| "emitter.gravityVelocity" # number - Strength of that gravity (px/s²).
---| "emitter.wind" # Vec2 - Constant drift added to every particle (px/s).
---| "emitter.collisionEnabled" # boolean - Particles collide with the physics world: bodies, tile maps, LDtk solids (not trigger a...
---| "emitter.collisionMode" # "Bounce"|"Stop"|"Kill" - On a hit: Bounce (elasticity, friction), Stop (rest there) or Kill. Each hit raises par...
---| "emitter.elasticity" # number - Bounce: how much speed off the surface is kept (0 stops, 1 keeps it all).
---| "emitter.friction" # number - Bounce: how much speed along the surface is lost (0 slides, 1 stops).
---| "emitter.shape" # "Circle"|"Ellipse"|"Rectangle"|"Pixel"|"Line"|"Texture"|"Custom" - Shape each particle is drawn as.
---| "emitter.emitting" # boolean - Emit new particles (existing ones finish their lives).
---| "emitter.continuous" # boolean - Keep emitting (else one cycle, then stop).
---| "emitter.localSpace" # boolean - Particles move, turn and scale with the node (an exhaust, an aura); off: they stay in t...
---| "emitter.blendMode" # "Alpha"|"Additive"|"Multiply"|"Premultiplied" - How particles mix with what's behind: Alpha (normal), Additive (fire, glow, sparks), Mu...
---| "emitter.sheetColumns" # integer - The texture as a sprite sheet: frames across (1: the whole texture).
---| "emitter.sheetRows" # integer - The texture as a sprite sheet: frames down.
---| "emitter.frameMode" # "OverLifetime"|"Speed"|"Random" - Which sheet frame a particle shows: Over Lifetime (the sheet once), Speed (Frame Speed ...
---| "emitter.frameSpeed" # number - Frames per second (Frame Mode: Speed).
---| "emitter.alignToVelocity" # boolean - Particles face where they move (rain, sparks, arrows); Rotation adds to it.
---| "emitter.trailLength" # integer - Trail: how many points of each particle's recent path are drawn as a ribbon behind it (...
---| "emitter.trailSegment" # number - Trail: pixels a particle moves between two trail points (smaller: smoother, shorter).
---| "emitter.trailWidth" # number - Trail: the ribbon's width at the particle, a fraction of the particle's size (it thins ...
---| "emitter.emissionShape" # "Rectangle"|"Point"|"Circle"|"Ring"|"Line"|"RectangleEdge" - Where particles are born: Rectangle (the Spread box), Point, Circle, Ring, Line (along ...
---| "emitter.emissionRadius" # number - Circle / Ring: the outer radius.
---| "emitter.emissionInnerRadius" # number - Ring: the inner radius (no particles inside it).
---| "emitter.emitAlongNormal" # boolean - Particles leave the shape outward (circle / ring: away from the centre; edges: out of t...
---| "emitter.radialVelocity" # number - Speed away from the emitter (negative: towards it), px/s - bursts, implosions.
---| "emitter.orbitVelocity" # number - Turning around the emitter, degrees/s - vortexes, magic circles.
---| "emitter.damping" # number - Speed lost per second (drag): particles slow down and drift.
---| "emitter.gpu" # boolean - Animate the particles on the GPU: 100k+ at almost no CPU cost. Not with collision, Lua ...
---| "emitter.prewarm" # boolean - Start as if it had already run a whole lifetime (smoke already there when the scene sta...
---| "emitter.seed" # integer - The same pattern every start (a fixed seed); 0 = different each time.
---| "emitter.autoVisibility" # boolean - Off-screen test from where the particles are (on), or from Visibility Rect (off: cheape...
---| "subEmitter" # string - Sub-emitter: another Particle Emitter, as a path from this node (e.g. a child's name), ...
---| "subEmitterOn" # "Death"|"Hit"|"Both" - When the sub-emitter bursts: a particle's Death (its lifetime ended), a Hit on a body (...
---| "subEmitterAmount" # integer - Particles the sub-emitter emits each time.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("subEmitter")`
---@param path ParticleEmitterNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: ParticleEmitterNode, path: "position"): Vec2
---@overload fun(self: ParticleEmitterNode, path: "scale"): Vec2
---@overload fun(self: ParticleEmitterNode, path: "rotation"): number
---@overload fun(self: ParticleEmitterNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: ParticleEmitterNode, path: "zIndex"): integer
---@overload fun(self: ParticleEmitterNode, path: "ySort"): boolean
---@overload fun(self: ParticleEmitterNode, path: "ySortOffset"): number
---@overload fun(self: ParticleEmitterNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: ParticleEmitterNode, path: "paused"): boolean
---@overload fun(self: ParticleEmitterNode, path: "enabled"): boolean
---@overload fun(self: ParticleEmitterNode, path: "emitter.amount"): integer
---@overload fun(self: ParticleEmitterNode, path: "emitter.lifetime"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.lifetimeVariance"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.position"): Vec2
---@overload fun(self: ParticleEmitterNode, path: "emitter.burst"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.size"): Vec2
---@overload fun(self: ParticleEmitterNode, path: "emitter.sizeVariance"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.sizeSpread"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.scaleStart"): Vec2
---@overload fun(self: ParticleEmitterNode, path: "emitter.scaleEnd"): Vec2
---@overload fun(self: ParticleEmitterNode, path: "emitter.rotation"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.rotationVariance"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.rotationSpread"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.torque"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.torqueVariance"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.torqueSpread"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.torqueAcceleration"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.useColorRamp"): boolean
---@overload fun(self: ParticleEmitterNode, path: "emitter.particleColor"): number[]
---@overload fun(self: ParticleEmitterNode, path: "emitter.colorEnd"): number[]
---@overload fun(self: ParticleEmitterNode, path: "emitter.colorVariance"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.spread"): Vec2
---@overload fun(self: ParticleEmitterNode, path: "emitter.velocity"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.velocityVariance"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.velocitySpread"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.velocityScale"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.acceleration"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.angle"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.angleVariance"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.angleSpread"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.gravityDirection"): Vec2
---@overload fun(self: ParticleEmitterNode, path: "emitter.gravityVelocity"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.wind"): Vec2
---@overload fun(self: ParticleEmitterNode, path: "emitter.collisionEnabled"): boolean
---@overload fun(self: ParticleEmitterNode, path: "emitter.collisionMode"): "Bounce"|"Stop"|"Kill"
---@overload fun(self: ParticleEmitterNode, path: "emitter.elasticity"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.friction"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.shape"): "Circle"|"Ellipse"|"Rectangle"|"Pixel"|"Line"|"Texture"|"Custom"
---@overload fun(self: ParticleEmitterNode, path: "emitter.emitting"): boolean
---@overload fun(self: ParticleEmitterNode, path: "emitter.continuous"): boolean
---@overload fun(self: ParticleEmitterNode, path: "emitter.localSpace"): boolean
---@overload fun(self: ParticleEmitterNode, path: "emitter.blendMode"): "Alpha"|"Additive"|"Multiply"|"Premultiplied"
---@overload fun(self: ParticleEmitterNode, path: "emitter.sheetColumns"): integer
---@overload fun(self: ParticleEmitterNode, path: "emitter.sheetRows"): integer
---@overload fun(self: ParticleEmitterNode, path: "emitter.frameMode"): "OverLifetime"|"Speed"|"Random"
---@overload fun(self: ParticleEmitterNode, path: "emitter.frameSpeed"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.alignToVelocity"): boolean
---@overload fun(self: ParticleEmitterNode, path: "emitter.trailLength"): integer
---@overload fun(self: ParticleEmitterNode, path: "emitter.trailSegment"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.trailWidth"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.emissionShape"): "Rectangle"|"Point"|"Circle"|"Ring"|"Line"|"RectangleEdge"
---@overload fun(self: ParticleEmitterNode, path: "emitter.emissionRadius"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.emissionInnerRadius"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.emitAlongNormal"): boolean
---@overload fun(self: ParticleEmitterNode, path: "emitter.radialVelocity"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.orbitVelocity"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.damping"): number
---@overload fun(self: ParticleEmitterNode, path: "emitter.gpu"): boolean
---@overload fun(self: ParticleEmitterNode, path: "emitter.prewarm"): boolean
---@overload fun(self: ParticleEmitterNode, path: "emitter.seed"): integer
---@overload fun(self: ParticleEmitterNode, path: "emitter.autoVisibility"): boolean
---@overload fun(self: ParticleEmitterNode, path: "subEmitter"): string
---@overload fun(self: ParticleEmitterNode, path: "subEmitterOn"): "Death"|"Hit"|"Both"
---@overload fun(self: ParticleEmitterNode, path: "subEmitterAmount"): integer
function ParticleEmitterNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("subEmitter", "text")`
---@param path ParticleEmitterNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: ParticleEmitterNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParticleEmitterNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParticleEmitterNode, path: "rotation", value: number)
---@overload fun(self: ParticleEmitterNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: ParticleEmitterNode, path: "zIndex", value: integer)
---@overload fun(self: ParticleEmitterNode, path: "ySort", value: boolean)
---@overload fun(self: ParticleEmitterNode, path: "ySortOffset", value: number)
---@overload fun(self: ParticleEmitterNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: ParticleEmitterNode, path: "paused", value: boolean)
---@overload fun(self: ParticleEmitterNode, path: "enabled", value: boolean)
---@overload fun(self: ParticleEmitterNode, path: "emitter.amount", value: integer)
---@overload fun(self: ParticleEmitterNode, path: "emitter.lifetime", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.lifetimeVariance", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.position", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.burst", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.size", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.sizeVariance", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.sizeSpread", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.scaleStart", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.scaleEnd", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.rotation", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.rotationVariance", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.rotationSpread", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.torque", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.torqueVariance", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.torqueSpread", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.torqueAcceleration", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.useColorRamp", value: boolean)
---@overload fun(self: ParticleEmitterNode, path: "emitter.particleColor", value: number[])
---@overload fun(self: ParticleEmitterNode, path: "emitter.colorEnd", value: number[])
---@overload fun(self: ParticleEmitterNode, path: "emitter.colorVariance", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.spread", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.velocity", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.velocityVariance", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.velocitySpread", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.velocityScale", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.acceleration", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.angle", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.angleVariance", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.angleSpread", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.gravityDirection", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.gravityVelocity", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.wind", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.collisionEnabled", value: boolean)
---@overload fun(self: ParticleEmitterNode, path: "emitter.collisionMode", value: "Bounce"|"Stop"|"Kill")
---@overload fun(self: ParticleEmitterNode, path: "emitter.elasticity", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.friction", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.shape", value: "Circle"|"Ellipse"|"Rectangle"|"Pixel"|"Line"|"Texture"|"Custom")
---@overload fun(self: ParticleEmitterNode, path: "emitter.emitting", value: boolean)
---@overload fun(self: ParticleEmitterNode, path: "emitter.continuous", value: boolean)
---@overload fun(self: ParticleEmitterNode, path: "emitter.localSpace", value: boolean)
---@overload fun(self: ParticleEmitterNode, path: "emitter.blendMode", value: "Alpha"|"Additive"|"Multiply"|"Premultiplied")
---@overload fun(self: ParticleEmitterNode, path: "emitter.sheetColumns", value: integer)
---@overload fun(self: ParticleEmitterNode, path: "emitter.sheetRows", value: integer)
---@overload fun(self: ParticleEmitterNode, path: "emitter.frameMode", value: "OverLifetime"|"Speed"|"Random")
---@overload fun(self: ParticleEmitterNode, path: "emitter.frameSpeed", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.alignToVelocity", value: boolean)
---@overload fun(self: ParticleEmitterNode, path: "emitter.trailLength", value: integer)
---@overload fun(self: ParticleEmitterNode, path: "emitter.trailSegment", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.trailWidth", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.emissionShape", value: "Rectangle"|"Point"|"Circle"|"Ring"|"Line"|"RectangleEdge")
---@overload fun(self: ParticleEmitterNode, path: "emitter.emissionRadius", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.emissionInnerRadius", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.emitAlongNormal", value: boolean)
---@overload fun(self: ParticleEmitterNode, path: "emitter.radialVelocity", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.orbitVelocity", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.damping", value: number)
---@overload fun(self: ParticleEmitterNode, path: "emitter.gpu", value: boolean)
---@overload fun(self: ParticleEmitterNode, path: "emitter.prewarm", value: boolean)
---@overload fun(self: ParticleEmitterNode, path: "emitter.seed", value: integer)
---@overload fun(self: ParticleEmitterNode, path: "emitter.autoVisibility", value: boolean)
---@overload fun(self: ParticleEmitterNode, path: "subEmitter", value: string)
---@overload fun(self: ParticleEmitterNode, path: "subEmitterOn", value: "Death"|"Hit"|"Both")
---@overload fun(self: ParticleEmitterNode, path: "subEmitterAmount", value: integer)
function ParticleEmitterNode:set_property(path, value, y) end

---@class SoundNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field playMode "Single"|"All"|"Sequential"|"Sequential_Reversed"|"Random"|"Shuffle" What a play starts from its sounds: Single (the chosen one), All (every sound at once),...
---@field single integer Single mode: which sound plays (1 = the first in the list).
---@field volume number Volume (0-1), before the bus and master volumes.
---@field pitch number Playback speed / pitch (1 = normal).
---@field volumeRandom number Each play's volume varies by up to this much either way (0.1 = +/-0.1 around Volume): r...
---@field pitchRandom number Each play's pitch varies by up to this many semitones either way (1-2 makes footsteps a...
---@field panRandom number Each play's pan moves by up to this much either way (-1 left .. 1 right).
---@field delayRandom number Each play waits a random 0..this many seconds (layered sounds, crowds) - All mode delay...
---@field cooldown number Plays within this many seconds of the last one are skipped (rapid fire won't stack doze...
---@field bus string The mixer bus it plays into (the Mixer tab; empty = SFX): its fader, effects and output...
---@field caption string Shown on the subtitle track when it plays, for players with sound captions on (e.g. "[d...
---@field autoplay boolean Play once when the node becomes ready.
---@field voices integer Plays over itself up to this many times (1: a new play restarts it).
---@field positional boolean Volume and pan follow the node's distance and side from the listener (the current camera).
---@field minDistance number Positional: full volume within this distance (px).
---@field maxDistance number Positional: silent beyond this distance (px).

---@alias SoundNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "playMode" # "Single"|"All"|"Sequential"|"Sequential_Reversed"|"Random"|"Shuffle" - What a play starts from its sounds: Single (the chosen one), All (every sound at once),...
---| "single" # integer - Single mode: which sound plays (1 = the first in the list).
---| "volume" # number - Volume (0-1), before the bus and master volumes.
---| "pitch" # number - Playback speed / pitch (1 = normal).
---| "volumeRandom" # number - Each play's volume varies by up to this much either way (0.1 = +/-0.1 around Volume): r...
---| "pitchRandom" # number - Each play's pitch varies by up to this many semitones either way (1-2 makes footsteps a...
---| "panRandom" # number - Each play's pan moves by up to this much either way (-1 left .. 1 right).
---| "delayRandom" # number - Each play waits a random 0..this many seconds (layered sounds, crowds) - All mode delay...
---| "cooldown" # number - Plays within this many seconds of the last one are skipped (rapid fire won't stack doze...
---| "bus" # string - The mixer bus it plays into (the Mixer tab; empty = SFX): its fader, effects and output...
---| "caption" # string - Shown on the subtitle track when it plays, for players with sound captions on (e.g. "[d...
---| "autoplay" # boolean - Play once when the node becomes ready.
---| "voices" # integer - Plays over itself up to this many times (1: a new play restarts it).
---| "positional" # boolean - Volume and pan follow the node's distance and side from the listener (the current camera).
---| "minDistance" # number - Positional: full volume within this distance (px).
---| "maxDistance" # number - Positional: silent beyond this distance (px).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("playMode")`
---@param path SoundNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: SoundNode, path: "position"): Vec2
---@overload fun(self: SoundNode, path: "scale"): Vec2
---@overload fun(self: SoundNode, path: "rotation"): number
---@overload fun(self: SoundNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: SoundNode, path: "zIndex"): integer
---@overload fun(self: SoundNode, path: "ySort"): boolean
---@overload fun(self: SoundNode, path: "ySortOffset"): number
---@overload fun(self: SoundNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: SoundNode, path: "paused"): boolean
---@overload fun(self: SoundNode, path: "enabled"): boolean
---@overload fun(self: SoundNode, path: "playMode"): "Single"|"All"|"Sequential"|"Sequential_Reversed"|"Random"|"Shuffle"
---@overload fun(self: SoundNode, path: "single"): integer
---@overload fun(self: SoundNode, path: "volume"): number
---@overload fun(self: SoundNode, path: "pitch"): number
---@overload fun(self: SoundNode, path: "volumeRandom"): number
---@overload fun(self: SoundNode, path: "pitchRandom"): number
---@overload fun(self: SoundNode, path: "panRandom"): number
---@overload fun(self: SoundNode, path: "delayRandom"): number
---@overload fun(self: SoundNode, path: "cooldown"): number
---@overload fun(self: SoundNode, path: "bus"): string
---@overload fun(self: SoundNode, path: "caption"): string
---@overload fun(self: SoundNode, path: "autoplay"): boolean
---@overload fun(self: SoundNode, path: "voices"): integer
---@overload fun(self: SoundNode, path: "positional"): boolean
---@overload fun(self: SoundNode, path: "minDistance"): number
---@overload fun(self: SoundNode, path: "maxDistance"): number
function SoundNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("playMode", "All")`
---@param path SoundNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: SoundNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: SoundNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: SoundNode, path: "rotation", value: number)
---@overload fun(self: SoundNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: SoundNode, path: "zIndex", value: integer)
---@overload fun(self: SoundNode, path: "ySort", value: boolean)
---@overload fun(self: SoundNode, path: "ySortOffset", value: number)
---@overload fun(self: SoundNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: SoundNode, path: "paused", value: boolean)
---@overload fun(self: SoundNode, path: "enabled", value: boolean)
---@overload fun(self: SoundNode, path: "playMode", value: "Single"|"All"|"Sequential"|"Sequential_Reversed"|"Random"|"Shuffle")
---@overload fun(self: SoundNode, path: "single", value: integer)
---@overload fun(self: SoundNode, path: "volume", value: number)
---@overload fun(self: SoundNode, path: "pitch", value: number)
---@overload fun(self: SoundNode, path: "volumeRandom", value: number)
---@overload fun(self: SoundNode, path: "pitchRandom", value: number)
---@overload fun(self: SoundNode, path: "panRandom", value: number)
---@overload fun(self: SoundNode, path: "delayRandom", value: number)
---@overload fun(self: SoundNode, path: "cooldown", value: number)
---@overload fun(self: SoundNode, path: "bus", value: string)
---@overload fun(self: SoundNode, path: "caption", value: string)
---@overload fun(self: SoundNode, path: "autoplay", value: boolean)
---@overload fun(self: SoundNode, path: "voices", value: integer)
---@overload fun(self: SoundNode, path: "positional", value: boolean)
---@overload fun(self: SoundNode, path: "minDistance", value: number)
---@overload fun(self: SoundNode, path: "maxDistance", value: number)
function SoundNode:set_property(path, value, y) end

---@class MusicNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field volume number Volume (0-1), before the bus and master volumes.
---@field pitch number Playback speed / pitch (1 = normal).
---@field pan number Stereo position: 0 left, 0.5 centre, 1 right.
---@field bus string The mixer bus it plays into (the Mixer tab; empty = Music): its fader, effects and outp...
---@field caption string Shown on the subtitle track when it starts, for players with sound captions on (e.g. "[...
---@field looping boolean Start again at the end.
---@field autoplay boolean Start playing when the node becomes ready.
---@field isPlaying boolean Playing now.
---@field isPaused boolean Paused now.

---@alias MusicNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "volume" # number - Volume (0-1), before the bus and master volumes.
---| "pitch" # number - Playback speed / pitch (1 = normal).
---| "pan" # number - Stereo position: 0 left, 0.5 centre, 1 right.
---| "bus" # string - The mixer bus it plays into (the Mixer tab; empty = Music): its fader, effects and outp...
---| "caption" # string - Shown on the subtitle track when it starts, for players with sound captions on (e.g. "[...
---| "looping" # boolean - Start again at the end.
---| "autoplay" # boolean - Start playing when the node becomes ready.
---| "isPlaying" # boolean (runtime) - Playing now.
---| "isPaused" # boolean (runtime) - Paused now.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("volume")`
---@param path MusicNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: MusicNode, path: "position"): Vec2
---@overload fun(self: MusicNode, path: "scale"): Vec2
---@overload fun(self: MusicNode, path: "rotation"): number
---@overload fun(self: MusicNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: MusicNode, path: "zIndex"): integer
---@overload fun(self: MusicNode, path: "ySort"): boolean
---@overload fun(self: MusicNode, path: "ySortOffset"): number
---@overload fun(self: MusicNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: MusicNode, path: "paused"): boolean
---@overload fun(self: MusicNode, path: "enabled"): boolean
---@overload fun(self: MusicNode, path: "volume"): number
---@overload fun(self: MusicNode, path: "pitch"): number
---@overload fun(self: MusicNode, path: "pan"): number
---@overload fun(self: MusicNode, path: "bus"): string
---@overload fun(self: MusicNode, path: "caption"): string
---@overload fun(self: MusicNode, path: "looping"): boolean
---@overload fun(self: MusicNode, path: "autoplay"): boolean
---@overload fun(self: MusicNode, path: "isPlaying"): boolean
---@overload fun(self: MusicNode, path: "isPaused"): boolean
function MusicNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("volume", 1.5)`
---@param path MusicNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: MusicNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: MusicNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: MusicNode, path: "rotation", value: number)
---@overload fun(self: MusicNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: MusicNode, path: "zIndex", value: integer)
---@overload fun(self: MusicNode, path: "ySort", value: boolean)
---@overload fun(self: MusicNode, path: "ySortOffset", value: number)
---@overload fun(self: MusicNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: MusicNode, path: "paused", value: boolean)
---@overload fun(self: MusicNode, path: "enabled", value: boolean)
---@overload fun(self: MusicNode, path: "volume", value: number)
---@overload fun(self: MusicNode, path: "pitch", value: number)
---@overload fun(self: MusicNode, path: "pan", value: number)
---@overload fun(self: MusicNode, path: "bus", value: string)
---@overload fun(self: MusicNode, path: "caption", value: string)
---@overload fun(self: MusicNode, path: "looping", value: boolean)
---@overload fun(self: MusicNode, path: "autoplay", value: boolean)
---@overload fun(self: MusicNode, path: "isPlaying", value: boolean)
---@overload fun(self: MusicNode, path: "isPaused", value: boolean)
function MusicNode:set_property(path, value, y) end

---@class StaticBodyNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field debugColor number[] Colour of the collider outline drawn with Show Bounds & Colliders (and the game's debug...
---@field oneWay boolean Jump-through platform: bodies pass from below and land on top.

---@alias StaticBodyNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "debugColor" # number[] - Colour of the collider outline drawn with Show Bounds & Colliders (and the game's debug...
---| "oneWay" # boolean - Jump-through platform: bodies pass from below and land on top.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("debugColor")`
---@param path StaticBodyNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: StaticBodyNode, path: "position"): Vec2
---@overload fun(self: StaticBodyNode, path: "scale"): Vec2
---@overload fun(self: StaticBodyNode, path: "rotation"): number
---@overload fun(self: StaticBodyNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: StaticBodyNode, path: "zIndex"): integer
---@overload fun(self: StaticBodyNode, path: "ySort"): boolean
---@overload fun(self: StaticBodyNode, path: "ySortOffset"): number
---@overload fun(self: StaticBodyNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: StaticBodyNode, path: "paused"): boolean
---@overload fun(self: StaticBodyNode, path: "enabled"): boolean
---@overload fun(self: StaticBodyNode, path: "debugColor"): number[]
---@overload fun(self: StaticBodyNode, path: "oneWay"): boolean
function StaticBodyNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("debugColor", "#ff8800")`
---@param path StaticBodyNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: StaticBodyNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: StaticBodyNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: StaticBodyNode, path: "rotation", value: number)
---@overload fun(self: StaticBodyNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: StaticBodyNode, path: "zIndex", value: integer)
---@overload fun(self: StaticBodyNode, path: "ySort", value: boolean)
---@overload fun(self: StaticBodyNode, path: "ySortOffset", value: number)
---@overload fun(self: StaticBodyNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: StaticBodyNode, path: "paused", value: boolean)
---@overload fun(self: StaticBodyNode, path: "enabled", value: boolean)
---@overload fun(self: StaticBodyNode, path: "debugColor", value: number[])
---@overload fun(self: StaticBodyNode, path: "oneWay", value: boolean)
function StaticBodyNode:set_property(path, value, y) end

---@class DynamicBodyNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field linearVelocity Vec2 Velocity (px/s).
---@field angularVelocity number Spin (degrees/s).
---@field linearDamping number Slows movement over time (air drag).
---@field angularDamping number Slows spin over time.
---@field gravityScale number Multiplies the world's gravity for this body (0 floats, negative rises).
---@field sleepThreshold number Below this speed the body may sleep (px/s).
---@field enableSleep boolean Let the body sleep when at rest (saves time; contacts wake it).
---@field isAwake boolean Awake (simulated) now.
---@field fixedRotation boolean Never rotate (characters, upright crates).
---@field isBullet boolean Continuous collision against other moving bodies (fast projectiles).
---@field allowFastRotation boolean Allow very fast spin (wheels); can be less stable.
---@field debugColor number[] Colour of the collider outline drawn with Show Bounds & Colliders (and the game's debug...

---@alias DynamicBodyNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "linearVelocity" # Vec2 - Velocity (px/s).
---| "angularVelocity" # number - Spin (degrees/s).
---| "linearDamping" # number - Slows movement over time (air drag).
---| "angularDamping" # number - Slows spin over time.
---| "gravityScale" # number - Multiplies the world's gravity for this body (0 floats, negative rises).
---| "sleepThreshold" # number - Below this speed the body may sleep (px/s).
---| "enableSleep" # boolean - Let the body sleep when at rest (saves time; contacts wake it).
---| "isAwake" # boolean - Awake (simulated) now.
---| "fixedRotation" # boolean - Never rotate (characters, upright crates).
---| "isBullet" # boolean - Continuous collision against other moving bodies (fast projectiles).
---| "allowFastRotation" # boolean - Allow very fast spin (wheels); can be less stable.
---| "debugColor" # number[] - Colour of the collider outline drawn with Show Bounds & Colliders (and the game's debug...

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("linearVelocity")`
---@param path DynamicBodyNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: DynamicBodyNode, path: "position"): Vec2
---@overload fun(self: DynamicBodyNode, path: "scale"): Vec2
---@overload fun(self: DynamicBodyNode, path: "rotation"): number
---@overload fun(self: DynamicBodyNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: DynamicBodyNode, path: "zIndex"): integer
---@overload fun(self: DynamicBodyNode, path: "ySort"): boolean
---@overload fun(self: DynamicBodyNode, path: "ySortOffset"): number
---@overload fun(self: DynamicBodyNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: DynamicBodyNode, path: "paused"): boolean
---@overload fun(self: DynamicBodyNode, path: "enabled"): boolean
---@overload fun(self: DynamicBodyNode, path: "linearVelocity"): Vec2
---@overload fun(self: DynamicBodyNode, path: "angularVelocity"): number
---@overload fun(self: DynamicBodyNode, path: "linearDamping"): number
---@overload fun(self: DynamicBodyNode, path: "angularDamping"): number
---@overload fun(self: DynamicBodyNode, path: "gravityScale"): number
---@overload fun(self: DynamicBodyNode, path: "sleepThreshold"): number
---@overload fun(self: DynamicBodyNode, path: "enableSleep"): boolean
---@overload fun(self: DynamicBodyNode, path: "isAwake"): boolean
---@overload fun(self: DynamicBodyNode, path: "fixedRotation"): boolean
---@overload fun(self: DynamicBodyNode, path: "isBullet"): boolean
---@overload fun(self: DynamicBodyNode, path: "allowFastRotation"): boolean
---@overload fun(self: DynamicBodyNode, path: "debugColor"): number[]
function DynamicBodyNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("linearVelocity", 100, 50)`
---@param path DynamicBodyNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: DynamicBodyNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: DynamicBodyNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: DynamicBodyNode, path: "rotation", value: number)
---@overload fun(self: DynamicBodyNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: DynamicBodyNode, path: "zIndex", value: integer)
---@overload fun(self: DynamicBodyNode, path: "ySort", value: boolean)
---@overload fun(self: DynamicBodyNode, path: "ySortOffset", value: number)
---@overload fun(self: DynamicBodyNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: DynamicBodyNode, path: "paused", value: boolean)
---@overload fun(self: DynamicBodyNode, path: "enabled", value: boolean)
---@overload fun(self: DynamicBodyNode, path: "linearVelocity", x: number|Vec2|number[], y?: number)
---@overload fun(self: DynamicBodyNode, path: "angularVelocity", value: number)
---@overload fun(self: DynamicBodyNode, path: "linearDamping", value: number)
---@overload fun(self: DynamicBodyNode, path: "angularDamping", value: number)
---@overload fun(self: DynamicBodyNode, path: "gravityScale", value: number)
---@overload fun(self: DynamicBodyNode, path: "sleepThreshold", value: number)
---@overload fun(self: DynamicBodyNode, path: "enableSleep", value: boolean)
---@overload fun(self: DynamicBodyNode, path: "isAwake", value: boolean)
---@overload fun(self: DynamicBodyNode, path: "fixedRotation", value: boolean)
---@overload fun(self: DynamicBodyNode, path: "isBullet", value: boolean)
---@overload fun(self: DynamicBodyNode, path: "allowFastRotation", value: boolean)
---@overload fun(self: DynamicBodyNode, path: "debugColor", value: number[])
function DynamicBodyNode:set_property(path, value, y) end

---@class KinematicBodyNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field linearVelocity Vec2 Velocity (px/s).
---@field angularVelocity number Spin (degrees/s).
---@field oneWay boolean Jump-through platform: bodies pass from below and land on top.
---@field debugColor number[] Colour of the collider outline drawn with Show Bounds & Colliders (and the game's debug...

---@alias KinematicBodyNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "linearVelocity" # Vec2 - Velocity (px/s).
---| "angularVelocity" # number - Spin (degrees/s).
---| "oneWay" # boolean - Jump-through platform: bodies pass from below and land on top.
---| "debugColor" # number[] - Colour of the collider outline drawn with Show Bounds & Colliders (and the game's debug...

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("linearVelocity")`
---@param path KinematicBodyNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: KinematicBodyNode, path: "position"): Vec2
---@overload fun(self: KinematicBodyNode, path: "scale"): Vec2
---@overload fun(self: KinematicBodyNode, path: "rotation"): number
---@overload fun(self: KinematicBodyNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: KinematicBodyNode, path: "zIndex"): integer
---@overload fun(self: KinematicBodyNode, path: "ySort"): boolean
---@overload fun(self: KinematicBodyNode, path: "ySortOffset"): number
---@overload fun(self: KinematicBodyNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: KinematicBodyNode, path: "paused"): boolean
---@overload fun(self: KinematicBodyNode, path: "enabled"): boolean
---@overload fun(self: KinematicBodyNode, path: "linearVelocity"): Vec2
---@overload fun(self: KinematicBodyNode, path: "angularVelocity"): number
---@overload fun(self: KinematicBodyNode, path: "oneWay"): boolean
---@overload fun(self: KinematicBodyNode, path: "debugColor"): number[]
function KinematicBodyNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("linearVelocity", 100, 50)`
---@param path KinematicBodyNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: KinematicBodyNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: KinematicBodyNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: KinematicBodyNode, path: "rotation", value: number)
---@overload fun(self: KinematicBodyNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: KinematicBodyNode, path: "zIndex", value: integer)
---@overload fun(self: KinematicBodyNode, path: "ySort", value: boolean)
---@overload fun(self: KinematicBodyNode, path: "ySortOffset", value: number)
---@overload fun(self: KinematicBodyNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: KinematicBodyNode, path: "paused", value: boolean)
---@overload fun(self: KinematicBodyNode, path: "enabled", value: boolean)
---@overload fun(self: KinematicBodyNode, path: "linearVelocity", x: number|Vec2|number[], y?: number)
---@overload fun(self: KinematicBodyNode, path: "angularVelocity", value: number)
---@overload fun(self: KinematicBodyNode, path: "oneWay", value: boolean)
---@overload fun(self: KinematicBodyNode, path: "debugColor", value: number[])
function KinematicBodyNode:set_property(path, value, y) end

---@class CharacterMoverNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field radius number Capsule radius (px).
---@field height number Capsule height (px).
---@field velocity Vec2 Velocity now (px/s).
---@field targetSpeedX number Horizontal speed the built-in movement accelerates to (px/s).
---@field maxSpeed number Top running speed (px/s).
---@field acceleration number How quickly it reaches top speed (px/s²).
---@field jumpSpeed number Upward speed of a jump (px/s).
---@field gravityScale number Multiplies the world's gravity for the character.
---@field pushLimit number Most push per step from overlapping bodies (px/s; 0 = unlimited).
---@field clipVelocity boolean Remove velocity into walls and floors it hits (slide along them).
---@field enableKeyboardInput boolean Built-in movement: the move / jump input actions drive it.
---@field playerIndex integer Player whose actions drive this mover (1..4; 0 = none / NPC / AI).
---@field isGrounded boolean Standing on something now.
---@field debugColor number[] Colour of the collider outline drawn with Show Bounds & Colliders (and the game's debug...
---@field controlMode "BuiltIn"|"Script" Built-in movement, or Script: the script moves it (character_move_and_slide).

---@alias CharacterMoverNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "radius" # number - Capsule radius (px).
---| "height" # number - Capsule height (px).
---| "velocity" # Vec2 (runtime) - Velocity now (px/s).
---| "targetSpeedX" # number (runtime) - Horizontal speed the built-in movement accelerates to (px/s).
---| "maxSpeed" # number - Top running speed (px/s).
---| "acceleration" # number - How quickly it reaches top speed (px/s²).
---| "jumpSpeed" # number - Upward speed of a jump (px/s).
---| "gravityScale" # number - Multiplies the world's gravity for the character.
---| "pushLimit" # number - Most push per step from overlapping bodies (px/s; 0 = unlimited).
---| "clipVelocity" # boolean - Remove velocity into walls and floors it hits (slide along them).
---| "enableKeyboardInput" # boolean - Built-in movement: the move / jump input actions drive it.
---| "playerIndex" # integer - Player whose actions drive this mover (1..4; 0 = none / NPC / AI).
---| "isGrounded" # boolean (runtime) - Standing on something now.
---| "debugColor" # number[] - Colour of the collider outline drawn with Show Bounds & Colliders (and the game's debug...
---| "controlMode" # "BuiltIn"|"Script" - Built-in movement, or Script: the script moves it (character_move_and_slide).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("radius")`
---@param path CharacterMoverNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: CharacterMoverNode, path: "position"): Vec2
---@overload fun(self: CharacterMoverNode, path: "scale"): Vec2
---@overload fun(self: CharacterMoverNode, path: "rotation"): number
---@overload fun(self: CharacterMoverNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: CharacterMoverNode, path: "zIndex"): integer
---@overload fun(self: CharacterMoverNode, path: "ySort"): boolean
---@overload fun(self: CharacterMoverNode, path: "ySortOffset"): number
---@overload fun(self: CharacterMoverNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: CharacterMoverNode, path: "paused"): boolean
---@overload fun(self: CharacterMoverNode, path: "enabled"): boolean
---@overload fun(self: CharacterMoverNode, path: "radius"): number
---@overload fun(self: CharacterMoverNode, path: "height"): number
---@overload fun(self: CharacterMoverNode, path: "velocity"): Vec2
---@overload fun(self: CharacterMoverNode, path: "targetSpeedX"): number
---@overload fun(self: CharacterMoverNode, path: "maxSpeed"): number
---@overload fun(self: CharacterMoverNode, path: "acceleration"): number
---@overload fun(self: CharacterMoverNode, path: "jumpSpeed"): number
---@overload fun(self: CharacterMoverNode, path: "gravityScale"): number
---@overload fun(self: CharacterMoverNode, path: "pushLimit"): number
---@overload fun(self: CharacterMoverNode, path: "clipVelocity"): boolean
---@overload fun(self: CharacterMoverNode, path: "enableKeyboardInput"): boolean
---@overload fun(self: CharacterMoverNode, path: "playerIndex"): integer
---@overload fun(self: CharacterMoverNode, path: "isGrounded"): boolean
---@overload fun(self: CharacterMoverNode, path: "debugColor"): number[]
---@overload fun(self: CharacterMoverNode, path: "controlMode"): "BuiltIn"|"Script"
function CharacterMoverNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("radius", 1.5)`
---@param path CharacterMoverNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: CharacterMoverNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: CharacterMoverNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: CharacterMoverNode, path: "rotation", value: number)
---@overload fun(self: CharacterMoverNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: CharacterMoverNode, path: "zIndex", value: integer)
---@overload fun(self: CharacterMoverNode, path: "ySort", value: boolean)
---@overload fun(self: CharacterMoverNode, path: "ySortOffset", value: number)
---@overload fun(self: CharacterMoverNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: CharacterMoverNode, path: "paused", value: boolean)
---@overload fun(self: CharacterMoverNode, path: "enabled", value: boolean)
---@overload fun(self: CharacterMoverNode, path: "radius", value: number)
---@overload fun(self: CharacterMoverNode, path: "height", value: number)
---@overload fun(self: CharacterMoverNode, path: "velocity", x: number|Vec2|number[], y?: number)
---@overload fun(self: CharacterMoverNode, path: "targetSpeedX", value: number)
---@overload fun(self: CharacterMoverNode, path: "maxSpeed", value: number)
---@overload fun(self: CharacterMoverNode, path: "acceleration", value: number)
---@overload fun(self: CharacterMoverNode, path: "jumpSpeed", value: number)
---@overload fun(self: CharacterMoverNode, path: "gravityScale", value: number)
---@overload fun(self: CharacterMoverNode, path: "pushLimit", value: number)
---@overload fun(self: CharacterMoverNode, path: "clipVelocity", value: boolean)
---@overload fun(self: CharacterMoverNode, path: "enableKeyboardInput", value: boolean)
---@overload fun(self: CharacterMoverNode, path: "playerIndex", value: integer)
---@overload fun(self: CharacterMoverNode, path: "isGrounded", value: boolean)
---@overload fun(self: CharacterMoverNode, path: "debugColor", value: number[])
---@overload fun(self: CharacterMoverNode, path: "controlMode", value: "BuiltIn"|"Script")
function CharacterMoverNode:set_property(path, value, y) end

---@class AreaNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field monitoring boolean Detect overlapping bodies and emit body_entered / body_exited. Off: no events or overla...
---@field overlapCount integer Bodies overlapping now.
---@field hasOverlaps boolean Anything overlapping now.
---@field debugColor number[] Outline colour when nothing overlaps.
---@field activeColor number[] Outline colour while something overlaps.

---@alias AreaNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "monitoring" # boolean - Detect overlapping bodies and emit body_entered / body_exited. Off: no events or overla...
---| "overlapCount" # integer (runtime) - Bodies overlapping now.
---| "hasOverlaps" # boolean (runtime) - Anything overlapping now.
---| "debugColor" # number[] - Outline colour when nothing overlaps.
---| "activeColor" # number[] - Outline colour while something overlaps.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("monitoring")`
---@param path AreaNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: AreaNode, path: "position"): Vec2
---@overload fun(self: AreaNode, path: "scale"): Vec2
---@overload fun(self: AreaNode, path: "rotation"): number
---@overload fun(self: AreaNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: AreaNode, path: "zIndex"): integer
---@overload fun(self: AreaNode, path: "ySort"): boolean
---@overload fun(self: AreaNode, path: "ySortOffset"): number
---@overload fun(self: AreaNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: AreaNode, path: "paused"): boolean
---@overload fun(self: AreaNode, path: "enabled"): boolean
---@overload fun(self: AreaNode, path: "monitoring"): boolean
---@overload fun(self: AreaNode, path: "overlapCount"): integer
---@overload fun(self: AreaNode, path: "hasOverlaps"): boolean
---@overload fun(self: AreaNode, path: "debugColor"): number[]
---@overload fun(self: AreaNode, path: "activeColor"): number[]
function AreaNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("monitoring", true)`
---@param path AreaNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: AreaNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: AreaNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: AreaNode, path: "rotation", value: number)
---@overload fun(self: AreaNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: AreaNode, path: "zIndex", value: integer)
---@overload fun(self: AreaNode, path: "ySort", value: boolean)
---@overload fun(self: AreaNode, path: "ySortOffset", value: number)
---@overload fun(self: AreaNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: AreaNode, path: "paused", value: boolean)
---@overload fun(self: AreaNode, path: "enabled", value: boolean)
---@overload fun(self: AreaNode, path: "monitoring", value: boolean)
---@overload fun(self: AreaNode, path: "overlapCount", value: integer)
---@overload fun(self: AreaNode, path: "hasOverlaps", value: boolean)
---@overload fun(self: AreaNode, path: "debugColor", value: number[])
---@overload fun(self: AreaNode, path: "activeColor", value: number[])
function AreaNode:set_property(path, value, y) end

---@class RaycastNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field monitoring boolean Cast the ray each frame and emit hit_started / hit_ended events.
---@field direction Vec2 Direction of the ray (rotated with the node).
---@field length number Length of the ray (px).
---@field collideWithSensors boolean Sensor shapes (areas) also stop the ray.
---@field isColliding boolean The ray hit something this frame.
---@field hitFraction number Where along the ray it hit (0 start, 1 end).
---@field hitPoint Vec2 World point of the hit (px).
---@field hitNormal Vec2 Surface direction at the hit.
---@field excludeParent boolean Ignore the body the ray is under (its parent), so a ray on a character doesn't hit the ...
---@field rayColor number[] Ray colour when it hits nothing.
---@field hitColor number[] Ray colour when it hits.

---@alias RaycastNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "monitoring" # boolean - Cast the ray each frame and emit hit_started / hit_ended events.
---| "direction" # Vec2 - Direction of the ray (rotated with the node).
---| "length" # number - Length of the ray (px).
---| "collideWithSensors" # boolean - Sensor shapes (areas) also stop the ray.
---| "isColliding" # boolean (runtime) - The ray hit something this frame.
---| "hitFraction" # number (runtime) - Where along the ray it hit (0 start, 1 end).
---| "hitPoint" # Vec2 (runtime) - World point of the hit (px).
---| "hitNormal" # Vec2 (runtime) - Surface direction at the hit.
---| "excludeParent" # boolean - Ignore the body the ray is under (its parent), so a ray on a character doesn't hit the ...
---| "rayColor" # number[] - Ray colour when it hits nothing.
---| "hitColor" # number[] - Ray colour when it hits.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("monitoring")`
---@param path RaycastNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: RaycastNode, path: "position"): Vec2
---@overload fun(self: RaycastNode, path: "scale"): Vec2
---@overload fun(self: RaycastNode, path: "rotation"): number
---@overload fun(self: RaycastNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: RaycastNode, path: "zIndex"): integer
---@overload fun(self: RaycastNode, path: "ySort"): boolean
---@overload fun(self: RaycastNode, path: "ySortOffset"): number
---@overload fun(self: RaycastNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: RaycastNode, path: "paused"): boolean
---@overload fun(self: RaycastNode, path: "enabled"): boolean
---@overload fun(self: RaycastNode, path: "monitoring"): boolean
---@overload fun(self: RaycastNode, path: "direction"): Vec2
---@overload fun(self: RaycastNode, path: "length"): number
---@overload fun(self: RaycastNode, path: "collideWithSensors"): boolean
---@overload fun(self: RaycastNode, path: "isColliding"): boolean
---@overload fun(self: RaycastNode, path: "hitFraction"): number
---@overload fun(self: RaycastNode, path: "hitPoint"): Vec2
---@overload fun(self: RaycastNode, path: "hitNormal"): Vec2
---@overload fun(self: RaycastNode, path: "excludeParent"): boolean
---@overload fun(self: RaycastNode, path: "rayColor"): number[]
---@overload fun(self: RaycastNode, path: "hitColor"): number[]
function RaycastNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("monitoring", true)`
---@param path RaycastNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: RaycastNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: RaycastNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: RaycastNode, path: "rotation", value: number)
---@overload fun(self: RaycastNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: RaycastNode, path: "zIndex", value: integer)
---@overload fun(self: RaycastNode, path: "ySort", value: boolean)
---@overload fun(self: RaycastNode, path: "ySortOffset", value: number)
---@overload fun(self: RaycastNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: RaycastNode, path: "paused", value: boolean)
---@overload fun(self: RaycastNode, path: "enabled", value: boolean)
---@overload fun(self: RaycastNode, path: "monitoring", value: boolean)
---@overload fun(self: RaycastNode, path: "direction", x: number|Vec2|number[], y?: number)
---@overload fun(self: RaycastNode, path: "length", value: number)
---@overload fun(self: RaycastNode, path: "collideWithSensors", value: boolean)
---@overload fun(self: RaycastNode, path: "isColliding", value: boolean)
---@overload fun(self: RaycastNode, path: "hitFraction", value: number)
---@overload fun(self: RaycastNode, path: "hitPoint", x: number|Vec2|number[], y?: number)
---@overload fun(self: RaycastNode, path: "hitNormal", x: number|Vec2|number[], y?: number)
---@overload fun(self: RaycastNode, path: "excludeParent", value: boolean)
---@overload fun(self: RaycastNode, path: "rayColor", value: number[])
---@overload fun(self: RaycastNode, path: "hitColor", value: number[])
function RaycastNode:set_property(path, value, y) end

---@class VisibilityNotifierNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 The rectangle (centred on the node, scaled with it) the camera has to see.
---@field margin number Grows the camera's view by this many pixels: fires a little before it really shows.
---@field action "None"|"Pause_Parent"|"Disable_Parent"|"Remove_Parent" What happens to the parent off screen: Pause (stops updating, resumes when seen), Disab...
---@field onScreen boolean The camera sees it now (runtime, read-only).

---@alias VisibilityNotifierNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - The rectangle (centred on the node, scaled with it) the camera has to see.
---| "margin" # number - Grows the camera's view by this many pixels: fires a little before it really shows.
---| "action" # "None"|"Pause_Parent"|"Disable_Parent"|"Remove_Parent" - What happens to the parent off screen: Pause (stops updating, resumes when seen), Disab...
---| "onScreen" # boolean (runtime) - The camera sees it now (runtime, read-only).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path VisibilityNotifierNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: VisibilityNotifierNode, path: "position"): Vec2
---@overload fun(self: VisibilityNotifierNode, path: "scale"): Vec2
---@overload fun(self: VisibilityNotifierNode, path: "rotation"): number
---@overload fun(self: VisibilityNotifierNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: VisibilityNotifierNode, path: "zIndex"): integer
---@overload fun(self: VisibilityNotifierNode, path: "ySort"): boolean
---@overload fun(self: VisibilityNotifierNode, path: "ySortOffset"): number
---@overload fun(self: VisibilityNotifierNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: VisibilityNotifierNode, path: "paused"): boolean
---@overload fun(self: VisibilityNotifierNode, path: "enabled"): boolean
---@overload fun(self: VisibilityNotifierNode, path: "size"): Vec2
---@overload fun(self: VisibilityNotifierNode, path: "margin"): number
---@overload fun(self: VisibilityNotifierNode, path: "action"): "None"|"Pause_Parent"|"Disable_Parent"|"Remove_Parent"
---@overload fun(self: VisibilityNotifierNode, path: "onScreen"): boolean
function VisibilityNotifierNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path VisibilityNotifierNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: VisibilityNotifierNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: VisibilityNotifierNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: VisibilityNotifierNode, path: "rotation", value: number)
---@overload fun(self: VisibilityNotifierNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: VisibilityNotifierNode, path: "zIndex", value: integer)
---@overload fun(self: VisibilityNotifierNode, path: "ySort", value: boolean)
---@overload fun(self: VisibilityNotifierNode, path: "ySortOffset", value: number)
---@overload fun(self: VisibilityNotifierNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: VisibilityNotifierNode, path: "paused", value: boolean)
---@overload fun(self: VisibilityNotifierNode, path: "enabled", value: boolean)
---@overload fun(self: VisibilityNotifierNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: VisibilityNotifierNode, path: "margin", value: number)
---@overload fun(self: VisibilityNotifierNode, path: "action", value: "None"|"Pause_Parent"|"Disable_Parent"|"Remove_Parent")
---@overload fun(self: VisibilityNotifierNode, path: "onScreen", value: boolean)
function VisibilityNotifierNode:set_property(path, value, y) end

---@class ScreenLayerNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field anchor "TopLeft"|"Top"|"TopRight"|"Left"|"Center"|"Right"|"BottomLeft"|"Bottom"|"BottomRight" The point of the screen it sits at (its position is an offset from it): top left ... bo...

---@alias ScreenLayerNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "anchor" # "TopLeft"|"Top"|"TopRight"|"Left"|"Center"|"Right"|"BottomLeft"|"Bottom"|"BottomRight" - The point of the screen it sits at (its position is an offset from it): top left ... bo...

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("anchor")`
---@param path ScreenLayerNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: ScreenLayerNode, path: "position"): Vec2
---@overload fun(self: ScreenLayerNode, path: "scale"): Vec2
---@overload fun(self: ScreenLayerNode, path: "rotation"): number
---@overload fun(self: ScreenLayerNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: ScreenLayerNode, path: "zIndex"): integer
---@overload fun(self: ScreenLayerNode, path: "ySort"): boolean
---@overload fun(self: ScreenLayerNode, path: "ySortOffset"): number
---@overload fun(self: ScreenLayerNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: ScreenLayerNode, path: "paused"): boolean
---@overload fun(self: ScreenLayerNode, path: "enabled"): boolean
---@overload fun(self: ScreenLayerNode, path: "anchor"): "TopLeft"|"Top"|"TopRight"|"Left"|"Center"|"Right"|"BottomLeft"|"Bottom"|"BottomRight"
function ScreenLayerNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("anchor", "Top")`
---@param path ScreenLayerNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: ScreenLayerNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: ScreenLayerNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: ScreenLayerNode, path: "rotation", value: number)
---@overload fun(self: ScreenLayerNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: ScreenLayerNode, path: "zIndex", value: integer)
---@overload fun(self: ScreenLayerNode, path: "ySort", value: boolean)
---@overload fun(self: ScreenLayerNode, path: "ySortOffset", value: number)
---@overload fun(self: ScreenLayerNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: ScreenLayerNode, path: "paused", value: boolean)
---@overload fun(self: ScreenLayerNode, path: "enabled", value: boolean)
---@overload fun(self: ScreenLayerNode, path: "anchor", value: "TopLeft"|"Top"|"TopRight"|"Left"|"Center"|"Right"|"BottomLeft"|"Bottom"|"BottomRight")
function ScreenLayerNode:set_property(path, value, y) end

---@class TouchJoystickNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field radius number The base's radius: the thumb this far from the middle is a full push.
---@field knobRadius number The knob's radius (the part under the thumb).
---@field floating boolean The joystick appears where the thumb lands (anywhere in Area) instead of staying put - ...
---@field area Vec2 Floating: where a thumb can start it, a rectangle this size centred on the node.
---@field deadzone number Pushes shorter than this (0..1 of the radius) count as none.
---@field actionLeft string The input action pushing left presses (with the push's strength).
---@field actionRight string The input action pushing right presses.
---@field actionUp string The input action pushing up presses.
---@field actionDown string The input action pushing down presses.
---@field color number[] The base's colour.
---@field knobColor number[] The knob's colour.
---@field alwaysShow boolean Shown from the start. Off: only once the device has been touched, so keyboard and gamep...

---@alias TouchJoystickNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "radius" # number - The base's radius: the thumb this far from the middle is a full push.
---| "knobRadius" # number - The knob's radius (the part under the thumb).
---| "floating" # boolean - The joystick appears where the thumb lands (anywhere in Area) instead of staying put - ...
---| "area" # Vec2 - Floating: where a thumb can start it, a rectangle this size centred on the node.
---| "deadzone" # number - Pushes shorter than this (0..1 of the radius) count as none.
---| "actionLeft" # string - The input action pushing left presses (with the push's strength).
---| "actionRight" # string - The input action pushing right presses.
---| "actionUp" # string - The input action pushing up presses.
---| "actionDown" # string - The input action pushing down presses.
---| "color" # number[] - The base's colour.
---| "knobColor" # number[] - The knob's colour.
---| "alwaysShow" # boolean - Shown from the start. Off: only once the device has been touched, so keyboard and gamep...

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("radius")`
---@param path TouchJoystickNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: TouchJoystickNode, path: "position"): Vec2
---@overload fun(self: TouchJoystickNode, path: "scale"): Vec2
---@overload fun(self: TouchJoystickNode, path: "rotation"): number
---@overload fun(self: TouchJoystickNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: TouchJoystickNode, path: "zIndex"): integer
---@overload fun(self: TouchJoystickNode, path: "ySort"): boolean
---@overload fun(self: TouchJoystickNode, path: "ySortOffset"): number
---@overload fun(self: TouchJoystickNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: TouchJoystickNode, path: "paused"): boolean
---@overload fun(self: TouchJoystickNode, path: "enabled"): boolean
---@overload fun(self: TouchJoystickNode, path: "radius"): number
---@overload fun(self: TouchJoystickNode, path: "knobRadius"): number
---@overload fun(self: TouchJoystickNode, path: "floating"): boolean
---@overload fun(self: TouchJoystickNode, path: "area"): Vec2
---@overload fun(self: TouchJoystickNode, path: "deadzone"): number
---@overload fun(self: TouchJoystickNode, path: "actionLeft"): string
---@overload fun(self: TouchJoystickNode, path: "actionRight"): string
---@overload fun(self: TouchJoystickNode, path: "actionUp"): string
---@overload fun(self: TouchJoystickNode, path: "actionDown"): string
---@overload fun(self: TouchJoystickNode, path: "color"): number[]
---@overload fun(self: TouchJoystickNode, path: "knobColor"): number[]
---@overload fun(self: TouchJoystickNode, path: "alwaysShow"): boolean
function TouchJoystickNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("radius", 1.5)`
---@param path TouchJoystickNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: TouchJoystickNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: TouchJoystickNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: TouchJoystickNode, path: "rotation", value: number)
---@overload fun(self: TouchJoystickNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: TouchJoystickNode, path: "zIndex", value: integer)
---@overload fun(self: TouchJoystickNode, path: "ySort", value: boolean)
---@overload fun(self: TouchJoystickNode, path: "ySortOffset", value: number)
---@overload fun(self: TouchJoystickNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: TouchJoystickNode, path: "paused", value: boolean)
---@overload fun(self: TouchJoystickNode, path: "enabled", value: boolean)
---@overload fun(self: TouchJoystickNode, path: "radius", value: number)
---@overload fun(self: TouchJoystickNode, path: "knobRadius", value: number)
---@overload fun(self: TouchJoystickNode, path: "floating", value: boolean)
---@overload fun(self: TouchJoystickNode, path: "area", x: number|Vec2|number[], y?: number)
---@overload fun(self: TouchJoystickNode, path: "deadzone", value: number)
---@overload fun(self: TouchJoystickNode, path: "actionLeft", value: string)
---@overload fun(self: TouchJoystickNode, path: "actionRight", value: string)
---@overload fun(self: TouchJoystickNode, path: "actionUp", value: string)
---@overload fun(self: TouchJoystickNode, path: "actionDown", value: string)
---@overload fun(self: TouchJoystickNode, path: "color", value: number[])
---@overload fun(self: TouchJoystickNode, path: "knobColor", value: number[])
---@overload fun(self: TouchJoystickNode, path: "alwaysShow", value: boolean)
function TouchJoystickNode:set_property(path, value, y) end

---@class TouchButtonNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field radius number The button's radius (a finger a little outside still counts).
---@field action string The input action it presses while a finger is on it ("jump", "fire", a project action);...
---@field label string Text drawn on it ("A", "Jump").
---@field fontSize number The label's size (px).
---@field color number[] Its fill at rest.
---@field pressedColor number[] Its fill while pressed.
---@field textColor number[] The label's and the outline's colour.
---@field alwaysShow boolean Shown from the start. Off: only once the device has been touched, so keyboard and gamep...

---@alias TouchButtonNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "radius" # number - The button's radius (a finger a little outside still counts).
---| "action" # string - The input action it presses while a finger is on it ("jump", "fire", a project action);...
---| "label" # string - Text drawn on it ("A", "Jump").
---| "fontSize" # number - The label's size (px).
---| "color" # number[] - Its fill at rest.
---| "pressedColor" # number[] - Its fill while pressed.
---| "textColor" # number[] - The label's and the outline's colour.
---| "alwaysShow" # boolean - Shown from the start. Off: only once the device has been touched, so keyboard and gamep...

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("radius")`
---@param path TouchButtonNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: TouchButtonNode, path: "position"): Vec2
---@overload fun(self: TouchButtonNode, path: "scale"): Vec2
---@overload fun(self: TouchButtonNode, path: "rotation"): number
---@overload fun(self: TouchButtonNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: TouchButtonNode, path: "zIndex"): integer
---@overload fun(self: TouchButtonNode, path: "ySort"): boolean
---@overload fun(self: TouchButtonNode, path: "ySortOffset"): number
---@overload fun(self: TouchButtonNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: TouchButtonNode, path: "paused"): boolean
---@overload fun(self: TouchButtonNode, path: "enabled"): boolean
---@overload fun(self: TouchButtonNode, path: "radius"): number
---@overload fun(self: TouchButtonNode, path: "action"): string
---@overload fun(self: TouchButtonNode, path: "label"): string
---@overload fun(self: TouchButtonNode, path: "fontSize"): number
---@overload fun(self: TouchButtonNode, path: "color"): number[]
---@overload fun(self: TouchButtonNode, path: "pressedColor"): number[]
---@overload fun(self: TouchButtonNode, path: "textColor"): number[]
---@overload fun(self: TouchButtonNode, path: "alwaysShow"): boolean
function TouchButtonNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("radius", 1.5)`
---@param path TouchButtonNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: TouchButtonNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: TouchButtonNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: TouchButtonNode, path: "rotation", value: number)
---@overload fun(self: TouchButtonNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: TouchButtonNode, path: "zIndex", value: integer)
---@overload fun(self: TouchButtonNode, path: "ySort", value: boolean)
---@overload fun(self: TouchButtonNode, path: "ySortOffset", value: number)
---@overload fun(self: TouchButtonNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: TouchButtonNode, path: "paused", value: boolean)
---@overload fun(self: TouchButtonNode, path: "enabled", value: boolean)
---@overload fun(self: TouchButtonNode, path: "radius", value: number)
---@overload fun(self: TouchButtonNode, path: "action", value: string)
---@overload fun(self: TouchButtonNode, path: "label", value: string)
---@overload fun(self: TouchButtonNode, path: "fontSize", value: number)
---@overload fun(self: TouchButtonNode, path: "color", value: number[])
---@overload fun(self: TouchButtonNode, path: "pressedColor", value: number[])
---@overload fun(self: TouchButtonNode, path: "textColor", value: number[])
---@overload fun(self: TouchButtonNode, path: "alwaysShow", value: boolean)
function TouchButtonNode:set_property(path, value, y) end

---@class SkeletonNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field file string The skeleton: a Spine .json export or a DragonBones _ske.json (project-relative).
---@field atlas string Its texture atlas; empty = next to it (name.atlas for Spine, name_tex.json for DragonBo...
---@field armature string DragonBones: the armature to show (empty = the first).
---@field animation string The animation played when the scene starts (and shown in the editor).
---@field skin string The skin (attachment set); empty = the default skin.
---@field loop boolean Play the animation over and over.
---@field autoplay boolean Start the animation when the node becomes ready.
---@field speed number Playback speed (1 = as authored).
---@field mixTime number Seconds to crossfade from one animation to the next.
---@field tint number[] Multiplies every slot's colour.
---@field showBones boolean Draw the bones over the art (also in the game, for debugging).

---@alias SkeletonNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "file" # string - The skeleton: a Spine .json export or a DragonBones _ske.json (project-relative).
---| "atlas" # string - Its texture atlas; empty = next to it (name.atlas for Spine, name_tex.json for DragonBo...
---| "armature" # string - DragonBones: the armature to show (empty = the first).
---| "animation" # string - The animation played when the scene starts (and shown in the editor).
---| "skin" # string - The skin (attachment set); empty = the default skin.
---| "loop" # boolean - Play the animation over and over.
---| "autoplay" # boolean - Start the animation when the node becomes ready.
---| "speed" # number - Playback speed (1 = as authored).
---| "mixTime" # number - Seconds to crossfade from one animation to the next.
---| "tint" # number[] - Multiplies every slot's colour.
---| "showBones" # boolean - Draw the bones over the art (also in the game, for debugging).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("file")`
---@param path SkeletonNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: SkeletonNode, path: "position"): Vec2
---@overload fun(self: SkeletonNode, path: "scale"): Vec2
---@overload fun(self: SkeletonNode, path: "rotation"): number
---@overload fun(self: SkeletonNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: SkeletonNode, path: "zIndex"): integer
---@overload fun(self: SkeletonNode, path: "ySort"): boolean
---@overload fun(self: SkeletonNode, path: "ySortOffset"): number
---@overload fun(self: SkeletonNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: SkeletonNode, path: "paused"): boolean
---@overload fun(self: SkeletonNode, path: "enabled"): boolean
---@overload fun(self: SkeletonNode, path: "file"): string
---@overload fun(self: SkeletonNode, path: "atlas"): string
---@overload fun(self: SkeletonNode, path: "armature"): string
---@overload fun(self: SkeletonNode, path: "animation"): string
---@overload fun(self: SkeletonNode, path: "skin"): string
---@overload fun(self: SkeletonNode, path: "loop"): boolean
---@overload fun(self: SkeletonNode, path: "autoplay"): boolean
---@overload fun(self: SkeletonNode, path: "speed"): number
---@overload fun(self: SkeletonNode, path: "mixTime"): number
---@overload fun(self: SkeletonNode, path: "tint"): number[]
---@overload fun(self: SkeletonNode, path: "showBones"): boolean
function SkeletonNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("file", "text")`
---@param path SkeletonNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: SkeletonNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: SkeletonNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: SkeletonNode, path: "rotation", value: number)
---@overload fun(self: SkeletonNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: SkeletonNode, path: "zIndex", value: integer)
---@overload fun(self: SkeletonNode, path: "ySort", value: boolean)
---@overload fun(self: SkeletonNode, path: "ySortOffset", value: number)
---@overload fun(self: SkeletonNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: SkeletonNode, path: "paused", value: boolean)
---@overload fun(self: SkeletonNode, path: "enabled", value: boolean)
---@overload fun(self: SkeletonNode, path: "file", value: string)
---@overload fun(self: SkeletonNode, path: "atlas", value: string)
---@overload fun(self: SkeletonNode, path: "armature", value: string)
---@overload fun(self: SkeletonNode, path: "animation", value: string)
---@overload fun(self: SkeletonNode, path: "skin", value: string)
---@overload fun(self: SkeletonNode, path: "loop", value: boolean)
---@overload fun(self: SkeletonNode, path: "autoplay", value: boolean)
---@overload fun(self: SkeletonNode, path: "speed", value: number)
---@overload fun(self: SkeletonNode, path: "mixTime", value: number)
---@overload fun(self: SkeletonNode, path: "tint", value: number[])
---@overload fun(self: SkeletonNode, path: "showBones", value: boolean)
function SkeletonNode:set_property(path, value, y) end

---@class BoneAttachmentNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field bone string The parent skeleton's bone this node follows (its children ride along: a weapon in the ...
---@field followRotation boolean Turn with the bone.
---@field followScale boolean Scale with the bone.

---@alias BoneAttachmentNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "bone" # string - The parent skeleton's bone this node follows (its children ride along: a weapon in the ...
---| "followRotation" # boolean - Turn with the bone.
---| "followScale" # boolean - Scale with the bone.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("bone")`
---@param path BoneAttachmentNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: BoneAttachmentNode, path: "position"): Vec2
---@overload fun(self: BoneAttachmentNode, path: "scale"): Vec2
---@overload fun(self: BoneAttachmentNode, path: "rotation"): number
---@overload fun(self: BoneAttachmentNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: BoneAttachmentNode, path: "zIndex"): integer
---@overload fun(self: BoneAttachmentNode, path: "ySort"): boolean
---@overload fun(self: BoneAttachmentNode, path: "ySortOffset"): number
---@overload fun(self: BoneAttachmentNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: BoneAttachmentNode, path: "paused"): boolean
---@overload fun(self: BoneAttachmentNode, path: "enabled"): boolean
---@overload fun(self: BoneAttachmentNode, path: "bone"): string
---@overload fun(self: BoneAttachmentNode, path: "followRotation"): boolean
---@overload fun(self: BoneAttachmentNode, path: "followScale"): boolean
function BoneAttachmentNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("bone", "text")`
---@param path BoneAttachmentNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: BoneAttachmentNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: BoneAttachmentNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: BoneAttachmentNode, path: "rotation", value: number)
---@overload fun(self: BoneAttachmentNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: BoneAttachmentNode, path: "zIndex", value: integer)
---@overload fun(self: BoneAttachmentNode, path: "ySort", value: boolean)
---@overload fun(self: BoneAttachmentNode, path: "ySortOffset", value: number)
---@overload fun(self: BoneAttachmentNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: BoneAttachmentNode, path: "paused", value: boolean)
---@overload fun(self: BoneAttachmentNode, path: "enabled", value: boolean)
---@overload fun(self: BoneAttachmentNode, path: "bone", value: string)
---@overload fun(self: BoneAttachmentNode, path: "followRotation", value: boolean)
---@overload fun(self: BoneAttachmentNode, path: "followScale", value: boolean)
function BoneAttachmentNode:set_property(path, value, y) end

---@class AdvancedCameraNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field priority integer The host camera shows the enabled advanced camera with the highest priority (a tie: the...
---@field followMode "None"|"Glued"|"Simple"|"Group"|"Path"|"Framed" None (stays where placed), Glued (exactly on the target), Simple (offset, damping, look...
---@field followTarget string The node it follows (a path like Player or ../Hero).
---@field followTargets string Group: more nodes to frame, comma separated.
---@field followPath string Path: the PathNode the camera rides along.
---@field followOffset Vec2 Added to the target's position (px).
---@field damping number Smoothing time in seconds: 0 locks on, 0.2-0.5 feels smooth.
---@field axisLock "None"|"X"|"Y"|"XY" Don't follow along these axes (e.g. Y for a side-scroller that never moves vertically).
---@field lookahead number Looks ahead of a moving target by this many seconds of its velocity.
---@field deadZone Vec2 Framed: the part of the view (fraction of width / height) the target can move in withou...
---@field zoom number Zoom (2 = twice as close).
---@field autoZoom boolean Group: zoom so every target fits, between Auto Zoom Min and Max.
---@field autoZoomMin number Group auto zoom: farthest out.
---@field autoZoomMax number Group auto zoom: closest in.
---@field autoZoomMargin number Group auto zoom: space kept around the targets (px).
---@field limitMode "None"|"Rect"|"Node"|"LdtkLevel" Keeps the view inside: None, Rect (Limit Rect), Node (a TileMap / LDtk level / Navigati...
---@field limitNode string Node limits: the node whose bounds the view stays in.
---@field limitMargin number Shrinks (+) or grows (-) the limits (px).
---@field limitBlend number Seconds to glide to new limits (moving into another LDtk level); 0 = at once.
---@field blendTime number Seconds the host takes to move from the previous camera to this one when it becomes act...
---@field blendEase "Linear"|"In_Sine"|"Out_Sine"|"In_Out_Sine"|"In_Quad"|"Out_Quad"|"In_Out_Quad"|"In_Cubic"|"Out_Cubic"|"In_Out_Cubic"|"In_Quart"|"Out_Quart"|"In_Out_Quart"|"In_Expo"|"Out_Expo"|"In_Out_Expo"|"In_Back"|"Out_Back"|"In_Out_Back"|"In_Elastic"|"Out_Elastic"|"In_Out_Elastic"|"In_Bounce"|"Out_Bounce"|"In_Out_Bounce"|"Constant" The easing of that blend.
---@field snapToPixel boolean Round the position to whole pixels (pixel art).
---@field shakeIntensity number Shake offset at full trauma (px).
---@field shakeRotation number Shake rotation at full trauma (degrees).
---@field shakeDecay number Trauma lost per second.
---@field shakeFrequency number How fast the shake moves (noise speed).
---@field traumaExponent number Shake = trauma ^ exponent: 2-3 makes small hits subtle and big ones strong.
---@field trauma number Current trauma 0..1 (add_trauma stacks it; runtime).
---@field active boolean The host camera shows this one now (runtime, read-only).

---@alias AdvancedCameraNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "priority" # integer - The host camera shows the enabled advanced camera with the highest priority (a tie: the...
---| "followMode" # "None"|"Glued"|"Simple"|"Group"|"Path"|"Framed" - None (stays where placed), Glued (exactly on the target), Simple (offset, damping, look...
---| "followTarget" # string - The node it follows (a path like Player or ../Hero).
---| "followTargets" # string - Group: more nodes to frame, comma separated.
---| "followPath" # string - Path: the PathNode the camera rides along.
---| "followOffset" # Vec2 - Added to the target's position (px).
---| "damping" # number - Smoothing time in seconds: 0 locks on, 0.2-0.5 feels smooth.
---| "axisLock" # "None"|"X"|"Y"|"XY" - Don't follow along these axes (e.g. Y for a side-scroller that never moves vertically).
---| "lookahead" # number - Looks ahead of a moving target by this many seconds of its velocity.
---| "deadZone" # Vec2 - Framed: the part of the view (fraction of width / height) the target can move in withou...
---| "zoom" # number - Zoom (2 = twice as close).
---| "autoZoom" # boolean - Group: zoom so every target fits, between Auto Zoom Min and Max.
---| "autoZoomMin" # number - Group auto zoom: farthest out.
---| "autoZoomMax" # number - Group auto zoom: closest in.
---| "autoZoomMargin" # number - Group auto zoom: space kept around the targets (px).
---| "limitMode" # "None"|"Rect"|"Node"|"LdtkLevel" - Keeps the view inside: None, Rect (Limit Rect), Node (a TileMap / LDtk level / Navigati...
---| "limitNode" # string - Node limits: the node whose bounds the view stays in.
---| "limitMargin" # number - Shrinks (+) or grows (-) the limits (px).
---| "limitBlend" # number - Seconds to glide to new limits (moving into another LDtk level); 0 = at once.
---| "blendTime" # number - Seconds the host takes to move from the previous camera to this one when it becomes act...
---| "blendEase" # "Linear"|"In_Sine"|"Out_Sine"|"In_Out_Sine"|"In_Quad"|"Out_Quad"|"In_Out_Quad"|"In_Cubic"|"Out_Cubic"|"In_Out_Cubic"|"In_Quart"|"Out_Quart"|"In_Out_Quart"|"In_Expo"|"Out_Expo"|"In_Out_Expo"|"In_Back"|"Out_Back"|"In_Out_Back"|"In_Elastic"|"Out_Elastic"|"In_Out_Elastic"|"In_Bounce"|"Out_Bounce"|"In_Out_Bounce"|"Constant" - The easing of that blend.
---| "snapToPixel" # boolean - Round the position to whole pixels (pixel art).
---| "shakeIntensity" # number - Shake offset at full trauma (px).
---| "shakeRotation" # number - Shake rotation at full trauma (degrees).
---| "shakeDecay" # number - Trauma lost per second.
---| "shakeFrequency" # number - How fast the shake moves (noise speed).
---| "traumaExponent" # number - Shake = trauma ^ exponent: 2-3 makes small hits subtle and big ones strong.
---| "trauma" # number (runtime) - Current trauma 0..1 (add_trauma stacks it; runtime).
---| "active" # boolean (runtime) - The host camera shows this one now (runtime, read-only).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("priority")`
---@param path AdvancedCameraNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: AdvancedCameraNode, path: "position"): Vec2
---@overload fun(self: AdvancedCameraNode, path: "scale"): Vec2
---@overload fun(self: AdvancedCameraNode, path: "rotation"): number
---@overload fun(self: AdvancedCameraNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: AdvancedCameraNode, path: "zIndex"): integer
---@overload fun(self: AdvancedCameraNode, path: "ySort"): boolean
---@overload fun(self: AdvancedCameraNode, path: "ySortOffset"): number
---@overload fun(self: AdvancedCameraNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: AdvancedCameraNode, path: "paused"): boolean
---@overload fun(self: AdvancedCameraNode, path: "enabled"): boolean
---@overload fun(self: AdvancedCameraNode, path: "priority"): integer
---@overload fun(self: AdvancedCameraNode, path: "followMode"): "None"|"Glued"|"Simple"|"Group"|"Path"|"Framed"
---@overload fun(self: AdvancedCameraNode, path: "followTarget"): string
---@overload fun(self: AdvancedCameraNode, path: "followTargets"): string
---@overload fun(self: AdvancedCameraNode, path: "followPath"): string
---@overload fun(self: AdvancedCameraNode, path: "followOffset"): Vec2
---@overload fun(self: AdvancedCameraNode, path: "damping"): number
---@overload fun(self: AdvancedCameraNode, path: "axisLock"): "None"|"X"|"Y"|"XY"
---@overload fun(self: AdvancedCameraNode, path: "lookahead"): number
---@overload fun(self: AdvancedCameraNode, path: "deadZone"): Vec2
---@overload fun(self: AdvancedCameraNode, path: "zoom"): number
---@overload fun(self: AdvancedCameraNode, path: "autoZoom"): boolean
---@overload fun(self: AdvancedCameraNode, path: "autoZoomMin"): number
---@overload fun(self: AdvancedCameraNode, path: "autoZoomMax"): number
---@overload fun(self: AdvancedCameraNode, path: "autoZoomMargin"): number
---@overload fun(self: AdvancedCameraNode, path: "limitMode"): "None"|"Rect"|"Node"|"LdtkLevel"
---@overload fun(self: AdvancedCameraNode, path: "limitNode"): string
---@overload fun(self: AdvancedCameraNode, path: "limitMargin"): number
---@overload fun(self: AdvancedCameraNode, path: "limitBlend"): number
---@overload fun(self: AdvancedCameraNode, path: "blendTime"): number
---@overload fun(self: AdvancedCameraNode, path: "blendEase"): "Linear"|"In_Sine"|"Out_Sine"|"In_Out_Sine"|"In_Quad"|"Out_Quad"|"In_Out_Quad"|"In_Cubic"|"Out_Cubic"|"In_Out_Cubic"|"In_Quart"|"Out_Quart"|"In_Out_Quart"|"In_Expo"|"Out_Expo"|"In_Out_Expo"|"In_Back"|"Out_Back"|"In_Out_Back"|"In_Elastic"|"Out_Elastic"|"In_Out_Elastic"|"In_Bounce"|"Out_Bounce"|"In_Out_Bounce"|"Constant"
---@overload fun(self: AdvancedCameraNode, path: "snapToPixel"): boolean
---@overload fun(self: AdvancedCameraNode, path: "shakeIntensity"): number
---@overload fun(self: AdvancedCameraNode, path: "shakeRotation"): number
---@overload fun(self: AdvancedCameraNode, path: "shakeDecay"): number
---@overload fun(self: AdvancedCameraNode, path: "shakeFrequency"): number
---@overload fun(self: AdvancedCameraNode, path: "traumaExponent"): number
---@overload fun(self: AdvancedCameraNode, path: "trauma"): number
---@overload fun(self: AdvancedCameraNode, path: "active"): boolean
function AdvancedCameraNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("priority", 2)`
---@param path AdvancedCameraNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: AdvancedCameraNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: AdvancedCameraNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: AdvancedCameraNode, path: "rotation", value: number)
---@overload fun(self: AdvancedCameraNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: AdvancedCameraNode, path: "zIndex", value: integer)
---@overload fun(self: AdvancedCameraNode, path: "ySort", value: boolean)
---@overload fun(self: AdvancedCameraNode, path: "ySortOffset", value: number)
---@overload fun(self: AdvancedCameraNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: AdvancedCameraNode, path: "paused", value: boolean)
---@overload fun(self: AdvancedCameraNode, path: "enabled", value: boolean)
---@overload fun(self: AdvancedCameraNode, path: "priority", value: integer)
---@overload fun(self: AdvancedCameraNode, path: "followMode", value: "None"|"Glued"|"Simple"|"Group"|"Path"|"Framed")
---@overload fun(self: AdvancedCameraNode, path: "followTarget", value: string)
---@overload fun(self: AdvancedCameraNode, path: "followTargets", value: string)
---@overload fun(self: AdvancedCameraNode, path: "followPath", value: string)
---@overload fun(self: AdvancedCameraNode, path: "followOffset", x: number|Vec2|number[], y?: number)
---@overload fun(self: AdvancedCameraNode, path: "damping", value: number)
---@overload fun(self: AdvancedCameraNode, path: "axisLock", value: "None"|"X"|"Y"|"XY")
---@overload fun(self: AdvancedCameraNode, path: "lookahead", value: number)
---@overload fun(self: AdvancedCameraNode, path: "deadZone", x: number|Vec2|number[], y?: number)
---@overload fun(self: AdvancedCameraNode, path: "zoom", value: number)
---@overload fun(self: AdvancedCameraNode, path: "autoZoom", value: boolean)
---@overload fun(self: AdvancedCameraNode, path: "autoZoomMin", value: number)
---@overload fun(self: AdvancedCameraNode, path: "autoZoomMax", value: number)
---@overload fun(self: AdvancedCameraNode, path: "autoZoomMargin", value: number)
---@overload fun(self: AdvancedCameraNode, path: "limitMode", value: "None"|"Rect"|"Node"|"LdtkLevel")
---@overload fun(self: AdvancedCameraNode, path: "limitNode", value: string)
---@overload fun(self: AdvancedCameraNode, path: "limitMargin", value: number)
---@overload fun(self: AdvancedCameraNode, path: "limitBlend", value: number)
---@overload fun(self: AdvancedCameraNode, path: "blendTime", value: number)
---@overload fun(self: AdvancedCameraNode, path: "blendEase", value: "Linear"|"In_Sine"|"Out_Sine"|"In_Out_Sine"|"In_Quad"|"Out_Quad"|"In_Out_Quad"|"In_Cubic"|"Out_Cubic"|"In_Out_Cubic"|"In_Quart"|"Out_Quart"|"In_Out_Quart"|"In_Expo"|"Out_Expo"|"In_Out_Expo"|"In_Back"|"Out_Back"|"In_Out_Back"|"In_Elastic"|"Out_Elastic"|"In_Out_Elastic"|"In_Bounce"|"Out_Bounce"|"In_Out_Bounce"|"Constant")
---@overload fun(self: AdvancedCameraNode, path: "snapToPixel", value: boolean)
---@overload fun(self: AdvancedCameraNode, path: "shakeIntensity", value: number)
---@overload fun(self: AdvancedCameraNode, path: "shakeRotation", value: number)
---@overload fun(self: AdvancedCameraNode, path: "shakeDecay", value: number)
---@overload fun(self: AdvancedCameraNode, path: "shakeFrequency", value: number)
---@overload fun(self: AdvancedCameraNode, path: "traumaExponent", value: number)
---@overload fun(self: AdvancedCameraNode, path: "trauma", value: number)
---@overload fun(self: AdvancedCameraNode, path: "active", value: boolean)
function AdvancedCameraNode:set_property(path, value, y) end

---@class PathNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field closed boolean Join the last point back to the first (a loop).
---@field bakeInterval number Distance between the points the curve is turned into (px): smaller follows the curve mo...
---@field lineWidth number Draw the path in the game this wide (rails, ropes); 0 = invisible (the editor always sh...
---@field color number[] Colour of the drawn path (and of its outline in the editor).

---@alias PathNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "closed" # boolean - Join the last point back to the first (a loop).
---| "bakeInterval" # number - Distance between the points the curve is turned into (px): smaller follows the curve mo...
---| "lineWidth" # number - Draw the path in the game this wide (rails, ropes); 0 = invisible (the editor always sh...
---| "color" # number[] - Colour of the drawn path (and of its outline in the editor).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("closed")`
---@param path PathNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: PathNode, path: "position"): Vec2
---@overload fun(self: PathNode, path: "scale"): Vec2
---@overload fun(self: PathNode, path: "rotation"): number
---@overload fun(self: PathNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: PathNode, path: "zIndex"): integer
---@overload fun(self: PathNode, path: "ySort"): boolean
---@overload fun(self: PathNode, path: "ySortOffset"): number
---@overload fun(self: PathNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: PathNode, path: "paused"): boolean
---@overload fun(self: PathNode, path: "enabled"): boolean
---@overload fun(self: PathNode, path: "closed"): boolean
---@overload fun(self: PathNode, path: "bakeInterval"): number
---@overload fun(self: PathNode, path: "lineWidth"): number
---@overload fun(self: PathNode, path: "color"): number[]
function PathNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("closed", true)`
---@param path PathNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: PathNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: PathNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: PathNode, path: "rotation", value: number)
---@overload fun(self: PathNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: PathNode, path: "zIndex", value: integer)
---@overload fun(self: PathNode, path: "ySort", value: boolean)
---@overload fun(self: PathNode, path: "ySortOffset", value: number)
---@overload fun(self: PathNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: PathNode, path: "paused", value: boolean)
---@overload fun(self: PathNode, path: "enabled", value: boolean)
---@overload fun(self: PathNode, path: "closed", value: boolean)
---@overload fun(self: PathNode, path: "bakeInterval", value: number)
---@overload fun(self: PathNode, path: "lineWidth", value: number)
---@overload fun(self: PathNode, path: "color", value: number[])
function PathNode:set_property(path, value, y) end

---@class NavigationRegionNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 The area agents find paths in, from the node's position (px).
---@field cellSize number Size of a grid cell (px): smaller follows walls more closely, larger finds paths faster.
---@field usePhysics boolean Static bodies' collision shapes inside the area block.
---@field useTileMaps boolean Solid tile maps' painted tiles block.
---@field useLdtk boolean LDtk IntGrid cells with a Solid collision rule block.

---@alias NavigationRegionNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - The area agents find paths in, from the node's position (px).
---| "cellSize" # number - Size of a grid cell (px): smaller follows walls more closely, larger finds paths faster.
---| "usePhysics" # boolean - Static bodies' collision shapes inside the area block.
---| "useTileMaps" # boolean - Solid tile maps' painted tiles block.
---| "useLdtk" # boolean - LDtk IntGrid cells with a Solid collision rule block.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path NavigationRegionNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: NavigationRegionNode, path: "position"): Vec2
---@overload fun(self: NavigationRegionNode, path: "scale"): Vec2
---@overload fun(self: NavigationRegionNode, path: "rotation"): number
---@overload fun(self: NavigationRegionNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: NavigationRegionNode, path: "zIndex"): integer
---@overload fun(self: NavigationRegionNode, path: "ySort"): boolean
---@overload fun(self: NavigationRegionNode, path: "ySortOffset"): number
---@overload fun(self: NavigationRegionNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: NavigationRegionNode, path: "paused"): boolean
---@overload fun(self: NavigationRegionNode, path: "enabled"): boolean
---@overload fun(self: NavigationRegionNode, path: "size"): Vec2
---@overload fun(self: NavigationRegionNode, path: "cellSize"): number
---@overload fun(self: NavigationRegionNode, path: "usePhysics"): boolean
---@overload fun(self: NavigationRegionNode, path: "useTileMaps"): boolean
---@overload fun(self: NavigationRegionNode, path: "useLdtk"): boolean
function NavigationRegionNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path NavigationRegionNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: NavigationRegionNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: NavigationRegionNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: NavigationRegionNode, path: "rotation", value: number)
---@overload fun(self: NavigationRegionNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: NavigationRegionNode, path: "zIndex", value: integer)
---@overload fun(self: NavigationRegionNode, path: "ySort", value: boolean)
---@overload fun(self: NavigationRegionNode, path: "ySortOffset", value: number)
---@overload fun(self: NavigationRegionNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: NavigationRegionNode, path: "paused", value: boolean)
---@overload fun(self: NavigationRegionNode, path: "enabled", value: boolean)
---@overload fun(self: NavigationRegionNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: NavigationRegionNode, path: "cellSize", value: number)
---@overload fun(self: NavigationRegionNode, path: "usePhysics", value: boolean)
---@overload fun(self: NavigationRegionNode, path: "useTileMaps", value: boolean)
---@overload fun(self: NavigationRegionNode, path: "useLdtk", value: boolean)
function NavigationRegionNode:set_property(path, value, y) end

---@class NavigationAgentNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field speed number How fast it moves along its path (px/s).
---@field radius number Its size: paths keep this far from walls, and agents keep this far apart.
---@field arriveDistance number How close to the target counts as arrived (px).
---@field repathInterval number Seconds between new paths while moving (a moving target, opened doors); 0 = only when t...
---@field navMap string The NavigationRegion, TileMap or LDtk level to find paths in (a node path); empty = the...
---@field moveParent boolean Move the parent along the path (a CharacterMover, a DynamicBody or any node); off: read...
---@field avoidance boolean Steer away from other agents (their radius).
---@field velocity Vec2 The velocity it wants this frame (px/s; read-only).

---@alias NavigationAgentNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "speed" # number - How fast it moves along its path (px/s).
---| "radius" # number - Its size: paths keep this far from walls, and agents keep this far apart.
---| "arriveDistance" # number - How close to the target counts as arrived (px).
---| "repathInterval" # number - Seconds between new paths while moving (a moving target, opened doors); 0 = only when t...
---| "navMap" # string - The NavigationRegion, TileMap or LDtk level to find paths in (a node path); empty = the...
---| "moveParent" # boolean - Move the parent along the path (a CharacterMover, a DynamicBody or any node); off: read...
---| "avoidance" # boolean - Steer away from other agents (their radius).
---| "velocity" # Vec2 (runtime) - The velocity it wants this frame (px/s; read-only).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("speed")`
---@param path NavigationAgentNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: NavigationAgentNode, path: "position"): Vec2
---@overload fun(self: NavigationAgentNode, path: "scale"): Vec2
---@overload fun(self: NavigationAgentNode, path: "rotation"): number
---@overload fun(self: NavigationAgentNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: NavigationAgentNode, path: "zIndex"): integer
---@overload fun(self: NavigationAgentNode, path: "ySort"): boolean
---@overload fun(self: NavigationAgentNode, path: "ySortOffset"): number
---@overload fun(self: NavigationAgentNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: NavigationAgentNode, path: "paused"): boolean
---@overload fun(self: NavigationAgentNode, path: "enabled"): boolean
---@overload fun(self: NavigationAgentNode, path: "speed"): number
---@overload fun(self: NavigationAgentNode, path: "radius"): number
---@overload fun(self: NavigationAgentNode, path: "arriveDistance"): number
---@overload fun(self: NavigationAgentNode, path: "repathInterval"): number
---@overload fun(self: NavigationAgentNode, path: "navMap"): string
---@overload fun(self: NavigationAgentNode, path: "moveParent"): boolean
---@overload fun(self: NavigationAgentNode, path: "avoidance"): boolean
---@overload fun(self: NavigationAgentNode, path: "velocity"): Vec2
function NavigationAgentNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("speed", 1.5)`
---@param path NavigationAgentNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: NavigationAgentNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: NavigationAgentNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: NavigationAgentNode, path: "rotation", value: number)
---@overload fun(self: NavigationAgentNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: NavigationAgentNode, path: "zIndex", value: integer)
---@overload fun(self: NavigationAgentNode, path: "ySort", value: boolean)
---@overload fun(self: NavigationAgentNode, path: "ySortOffset", value: number)
---@overload fun(self: NavigationAgentNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: NavigationAgentNode, path: "paused", value: boolean)
---@overload fun(self: NavigationAgentNode, path: "enabled", value: boolean)
---@overload fun(self: NavigationAgentNode, path: "speed", value: number)
---@overload fun(self: NavigationAgentNode, path: "radius", value: number)
---@overload fun(self: NavigationAgentNode, path: "arriveDistance", value: number)
---@overload fun(self: NavigationAgentNode, path: "repathInterval", value: number)
---@overload fun(self: NavigationAgentNode, path: "navMap", value: string)
---@overload fun(self: NavigationAgentNode, path: "moveParent", value: boolean)
---@overload fun(self: NavigationAgentNode, path: "avoidance", value: boolean)
---@overload fun(self: NavigationAgentNode, path: "velocity", x: number|Vec2|number[], y?: number)
function NavigationAgentNode:set_property(path, value, y) end

---@class PathFollowNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field progress number Distance travelled along the parent path (px). Set it to place the follower; scripts ca...
---@field speed number Pixels per second it moves along the path by itself (negative: backwards; 0: only scrip...
---@field loop "Stop"|"Loop"|"PingPong" At the end: Stop (path_finished), Loop (start again) or Ping Pong (turn back).
---@field rotate boolean Turn to face the direction it travels.
---@field sideOffset number Pixels to the side of the path (positive: to the right of the travel direction) - lanes...

---@alias PathFollowNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "progress" # number - Distance travelled along the parent path (px). Set it to place the follower; scripts ca...
---| "speed" # number - Pixels per second it moves along the path by itself (negative: backwards; 0: only scrip...
---| "loop" # "Stop"|"Loop"|"PingPong" - At the end: Stop (path_finished), Loop (start again) or Ping Pong (turn back).
---| "rotate" # boolean - Turn to face the direction it travels.
---| "sideOffset" # number - Pixels to the side of the path (positive: to the right of the travel direction) - lanes...

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("progress")`
---@param path PathFollowNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: PathFollowNode, path: "position"): Vec2
---@overload fun(self: PathFollowNode, path: "scale"): Vec2
---@overload fun(self: PathFollowNode, path: "rotation"): number
---@overload fun(self: PathFollowNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: PathFollowNode, path: "zIndex"): integer
---@overload fun(self: PathFollowNode, path: "ySort"): boolean
---@overload fun(self: PathFollowNode, path: "ySortOffset"): number
---@overload fun(self: PathFollowNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: PathFollowNode, path: "paused"): boolean
---@overload fun(self: PathFollowNode, path: "enabled"): boolean
---@overload fun(self: PathFollowNode, path: "progress"): number
---@overload fun(self: PathFollowNode, path: "speed"): number
---@overload fun(self: PathFollowNode, path: "loop"): "Stop"|"Loop"|"PingPong"
---@overload fun(self: PathFollowNode, path: "rotate"): boolean
---@overload fun(self: PathFollowNode, path: "sideOffset"): number
function PathFollowNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("progress", 1.5)`
---@param path PathFollowNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: PathFollowNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: PathFollowNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: PathFollowNode, path: "rotation", value: number)
---@overload fun(self: PathFollowNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: PathFollowNode, path: "zIndex", value: integer)
---@overload fun(self: PathFollowNode, path: "ySort", value: boolean)
---@overload fun(self: PathFollowNode, path: "ySortOffset", value: number)
---@overload fun(self: PathFollowNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: PathFollowNode, path: "paused", value: boolean)
---@overload fun(self: PathFollowNode, path: "enabled", value: boolean)
---@overload fun(self: PathFollowNode, path: "progress", value: number)
---@overload fun(self: PathFollowNode, path: "speed", value: number)
---@overload fun(self: PathFollowNode, path: "loop", value: "Stop"|"Loop"|"PingPong")
---@overload fun(self: PathFollowNode, path: "rotate", value: boolean)
---@overload fun(self: PathFollowNode, path: "sideOffset", value: number)
function PathFollowNode:set_property(path, value, y) end

---@class LdtkLevelNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field enablePhysics boolean Build colliders from IntGrid cells whose collision rule is Solid / One Way.
---@field spawnEntities boolean Spawn the level's entities (mapped to components) when ready.
---@field parallax boolean Apply the LDtk layers' parallax factors.
---@field drawBackground boolean Draw the level's background colour / image.
---@field drawEntityTiles boolean In the game, draw entities' LDtk icons (their editor visuals) too - for entities no nod...
---@field tintColor number[] Multiplies every layer's colours.
---@field drawDebugColliders boolean Outline the generated colliders.
---@field drawDebugEntities boolean Outline entity bounds with their names.
---@field matchCustomNodes boolean Entities set to Auto also spawn as the project's custom node type of the same name (whe...

---@alias LdtkLevelNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "enablePhysics" # boolean - Build colliders from IntGrid cells whose collision rule is Solid / One Way.
---| "spawnEntities" # boolean - Spawn the level's entities (mapped to components) when ready.
---| "parallax" # boolean - Apply the LDtk layers' parallax factors.
---| "drawBackground" # boolean - Draw the level's background colour / image.
---| "drawEntityTiles" # boolean - In the game, draw entities' LDtk icons (their editor visuals) too - for entities no nod...
---| "tintColor" # number[] - Multiplies every layer's colours.
---| "drawDebugColliders" # boolean - Outline the generated colliders.
---| "drawDebugEntities" # boolean - Outline entity bounds with their names.
---| "matchCustomNodes" # boolean - Entities set to Auto also spawn as the project's custom node type of the same name (whe...

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("enablePhysics")`
---@param path LdtkLevelNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: LdtkLevelNode, path: "position"): Vec2
---@overload fun(self: LdtkLevelNode, path: "scale"): Vec2
---@overload fun(self: LdtkLevelNode, path: "rotation"): number
---@overload fun(self: LdtkLevelNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: LdtkLevelNode, path: "zIndex"): integer
---@overload fun(self: LdtkLevelNode, path: "ySort"): boolean
---@overload fun(self: LdtkLevelNode, path: "ySortOffset"): number
---@overload fun(self: LdtkLevelNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: LdtkLevelNode, path: "paused"): boolean
---@overload fun(self: LdtkLevelNode, path: "enabled"): boolean
---@overload fun(self: LdtkLevelNode, path: "enablePhysics"): boolean
---@overload fun(self: LdtkLevelNode, path: "spawnEntities"): boolean
---@overload fun(self: LdtkLevelNode, path: "parallax"): boolean
---@overload fun(self: LdtkLevelNode, path: "drawBackground"): boolean
---@overload fun(self: LdtkLevelNode, path: "drawEntityTiles"): boolean
---@overload fun(self: LdtkLevelNode, path: "tintColor"): number[]
---@overload fun(self: LdtkLevelNode, path: "drawDebugColliders"): boolean
---@overload fun(self: LdtkLevelNode, path: "drawDebugEntities"): boolean
---@overload fun(self: LdtkLevelNode, path: "matchCustomNodes"): boolean
function LdtkLevelNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("enablePhysics", true)`
---@param path LdtkLevelNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: LdtkLevelNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: LdtkLevelNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: LdtkLevelNode, path: "rotation", value: number)
---@overload fun(self: LdtkLevelNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: LdtkLevelNode, path: "zIndex", value: integer)
---@overload fun(self: LdtkLevelNode, path: "ySort", value: boolean)
---@overload fun(self: LdtkLevelNode, path: "ySortOffset", value: number)
---@overload fun(self: LdtkLevelNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: LdtkLevelNode, path: "paused", value: boolean)
---@overload fun(self: LdtkLevelNode, path: "enabled", value: boolean)
---@overload fun(self: LdtkLevelNode, path: "enablePhysics", value: boolean)
---@overload fun(self: LdtkLevelNode, path: "spawnEntities", value: boolean)
---@overload fun(self: LdtkLevelNode, path: "parallax", value: boolean)
---@overload fun(self: LdtkLevelNode, path: "drawBackground", value: boolean)
---@overload fun(self: LdtkLevelNode, path: "drawEntityTiles", value: boolean)
---@overload fun(self: LdtkLevelNode, path: "tintColor", value: number[])
---@overload fun(self: LdtkLevelNode, path: "drawDebugColliders", value: boolean)
---@overload fun(self: LdtkLevelNode, path: "drawDebugEntities", value: boolean)
---@overload fun(self: LdtkLevelNode, path: "matchCustomNodes", value: boolean)
function LdtkLevelNode:set_property(path, value, y) end

---@class TileMapNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field solid boolean Build static colliders for the painted tiles.
---@field tint number[] Multiplies the texture's colours (white = unchanged; alpha fades it).
---@field layout "Square"|"Isometric"|"Staggered"|"HexPointy"|"HexFlat" The cells' shape: Square; Isometric (diamonds on a grid turned 45 degrees); Staggered (...
---@field stagger "Odd"|"Even" Staggered and hex grids: which rows (Hex Flat: columns) are shifted by half a cell - th...
---@field cellSize Vec2 The grid's cell in pixels (0 = the tile size). Tiles taller than their cell - walls, bl...
---@field tileOffset Vec2 Moves every tile image by this many pixels: for art whose cell isn't at the image's bot...
---@field asepriteLayer string With an Aseprite file as the tileset: the tilemap layer the map comes from (its tiles, ...

---@alias TileMapNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "solid" # boolean - Build static colliders for the painted tiles.
---| "tint" # number[] - Multiplies the texture's colours (white = unchanged; alpha fades it).
---| "layout" # "Square"|"Isometric"|"Staggered"|"HexPointy"|"HexFlat" - The cells' shape: Square; Isometric (diamonds on a grid turned 45 degrees); Staggered (...
---| "stagger" # "Odd"|"Even" - Staggered and hex grids: which rows (Hex Flat: columns) are shifted by half a cell - th...
---| "cellSize" # Vec2 - The grid's cell in pixels (0 = the tile size). Tiles taller than their cell - walls, bl...
---| "tileOffset" # Vec2 - Moves every tile image by this many pixels: for art whose cell isn't at the image's bot...
---| "asepriteLayer" # string - With an Aseprite file as the tileset: the tilemap layer the map comes from (its tiles, ...

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("solid")`
---@param path TileMapNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: TileMapNode, path: "position"): Vec2
---@overload fun(self: TileMapNode, path: "scale"): Vec2
---@overload fun(self: TileMapNode, path: "rotation"): number
---@overload fun(self: TileMapNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: TileMapNode, path: "zIndex"): integer
---@overload fun(self: TileMapNode, path: "ySort"): boolean
---@overload fun(self: TileMapNode, path: "ySortOffset"): number
---@overload fun(self: TileMapNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: TileMapNode, path: "paused"): boolean
---@overload fun(self: TileMapNode, path: "enabled"): boolean
---@overload fun(self: TileMapNode, path: "solid"): boolean
---@overload fun(self: TileMapNode, path: "tint"): number[]
---@overload fun(self: TileMapNode, path: "layout"): "Square"|"Isometric"|"Staggered"|"HexPointy"|"HexFlat"
---@overload fun(self: TileMapNode, path: "stagger"): "Odd"|"Even"
---@overload fun(self: TileMapNode, path: "cellSize"): Vec2
---@overload fun(self: TileMapNode, path: "tileOffset"): Vec2
---@overload fun(self: TileMapNode, path: "asepriteLayer"): string
function TileMapNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("solid", true)`
---@param path TileMapNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: TileMapNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: TileMapNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: TileMapNode, path: "rotation", value: number)
---@overload fun(self: TileMapNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: TileMapNode, path: "zIndex", value: integer)
---@overload fun(self: TileMapNode, path: "ySort", value: boolean)
---@overload fun(self: TileMapNode, path: "ySortOffset", value: number)
---@overload fun(self: TileMapNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: TileMapNode, path: "paused", value: boolean)
---@overload fun(self: TileMapNode, path: "enabled", value: boolean)
---@overload fun(self: TileMapNode, path: "solid", value: boolean)
---@overload fun(self: TileMapNode, path: "tint", value: number[])
---@overload fun(self: TileMapNode, path: "layout", value: "Square"|"Isometric"|"Staggered"|"HexPointy"|"HexFlat")
---@overload fun(self: TileMapNode, path: "stagger", value: "Odd"|"Even")
---@overload fun(self: TileMapNode, path: "cellSize", x: number|Vec2|number[], y?: number)
---@overload fun(self: TileMapNode, path: "tileOffset", x: number|Vec2|number[], y?: number)
---@overload fun(self: TileMapNode, path: "asepriteLayer", value: string)
function TileMapNode:set_property(path, value, y) end

---@class LightNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field kind "Point"|"Spot" Point: shines all round. Spot: a cone along the node's rotation.
---@field color number[] Colour of the light.
---@field energy number Brightness multiplier.
---@field radius number Reach of the light (px).
---@field falloff number Fade towards the edge: 1 linear, 2 smooth, higher = tighter.
---@field spread number Spot: half-angle of the cone (degrees).
---@field shadows boolean Cast shadows from the scene's physics shapes (bodies, LDtk and tile map colliders; not ...

---@alias LightNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "kind" # "Point"|"Spot" - Point: shines all round. Spot: a cone along the node's rotation.
---| "color" # number[] - Colour of the light.
---| "energy" # number - Brightness multiplier.
---| "radius" # number - Reach of the light (px).
---| "falloff" # number - Fade towards the edge: 1 linear, 2 smooth, higher = tighter.
---| "spread" # number - Spot: half-angle of the cone (degrees).
---| "shadows" # boolean - Cast shadows from the scene's physics shapes (bodies, LDtk and tile map colliders; not ...

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("kind")`
---@param path LightNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: LightNode, path: "position"): Vec2
---@overload fun(self: LightNode, path: "scale"): Vec2
---@overload fun(self: LightNode, path: "rotation"): number
---@overload fun(self: LightNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: LightNode, path: "zIndex"): integer
---@overload fun(self: LightNode, path: "ySort"): boolean
---@overload fun(self: LightNode, path: "ySortOffset"): number
---@overload fun(self: LightNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: LightNode, path: "paused"): boolean
---@overload fun(self: LightNode, path: "enabled"): boolean
---@overload fun(self: LightNode, path: "kind"): "Point"|"Spot"
---@overload fun(self: LightNode, path: "color"): number[]
---@overload fun(self: LightNode, path: "energy"): number
---@overload fun(self: LightNode, path: "radius"): number
---@overload fun(self: LightNode, path: "falloff"): number
---@overload fun(self: LightNode, path: "spread"): number
---@overload fun(self: LightNode, path: "shadows"): boolean
function LightNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("kind", "Spot")`
---@param path LightNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: LightNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: LightNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: LightNode, path: "rotation", value: number)
---@overload fun(self: LightNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: LightNode, path: "zIndex", value: integer)
---@overload fun(self: LightNode, path: "ySort", value: boolean)
---@overload fun(self: LightNode, path: "ySortOffset", value: number)
---@overload fun(self: LightNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: LightNode, path: "paused", value: boolean)
---@overload fun(self: LightNode, path: "enabled", value: boolean)
---@overload fun(self: LightNode, path: "kind", value: "Point"|"Spot")
---@overload fun(self: LightNode, path: "color", value: number[])
---@overload fun(self: LightNode, path: "energy", value: number)
---@overload fun(self: LightNode, path: "radius", value: number)
---@overload fun(self: LightNode, path: "falloff", value: number)
---@overload fun(self: LightNode, path: "spread", value: number)
---@overload fun(self: LightNode, path: "shadows", value: boolean)
function LightNode:set_property(path, value, y) end

---@class JointNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field debugColor number[] Colour of the line drawn between the anchors.

---@alias JointNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "joint.type" # "Distance"|"Filter"|"Motor"|"Mouse"|"Prismatic"|"Revolute"|"Weld"|"Wheel" - Kind of joint; only that kind's settings are shown.
---| "joint.distance.localAnchorA" # Vec2 - Anchor on body A, relative to its origin (px).
---| "joint.distance.localAnchorB" # Vec2 - Anchor on body B, relative to its origin (px).
---| "joint.distance.length" # number - Rest distance between the anchors (px).
---| "joint.distance.enableSpring" # boolean - Make the joint springy instead of rigid.
---| "joint.distance.hertz" # number - Spring stiffness as an oscillation frequency (Hz); 0 = no spring.
---| "joint.distance.dampingRatio" # number - Spring damping: 0 bounces forever, 1 settles without overshoot.
---| "joint.distance.enableLimit" # boolean - Clamp the joint's travel to the lower / upper limits.
---| "joint.distance.minLength" # number - Shortest the joint may get (px; with the limit on).
---| "joint.distance.maxLength" # number - Longest the joint may get (px; with the limit on).
---| "joint.distance.enableMotor" # boolean - Drive the joint at Motor Speed, up to the maximum force / torque.
---| "joint.distance.maxMotorForce" # number - Strongest push the motor applies (pixel-scale bodies are heavy: mass ~ area in px²).
---| "joint.distance.motorSpeed" # number - Speed the motor lengthens (+) or shortens (-) the joint (px/s).
---| "joint.distance.collideConnected" # boolean - Let the two connected bodies collide with each other.
---| "joint.motor.linearOffset" # Vec2 - Where body B is driven to, relative to body A (px).
---| "joint.motor.angularOffset" # number - Angle body B is driven to, relative to body A (degrees).
---| "joint.motor.maxForce" # number - Strongest pull towards the offset (pixel-scale bodies are heavy).
---| "joint.motor.maxTorque" # number - Strongest twist towards the angle (pixel-scale bodies are heavy).
---| "joint.motor.correctionFactor" # number - How quickly position errors are corrected (0-1).
---| "joint.motor.collideConnected" # boolean - Let the two connected bodies collide with each other.
---| "joint.mouse.target" # Vec2 - World point the body is pulled to (px).
---| "joint.mouse.hertz" # number - Stiffness of the pull (Hz).
---| "joint.mouse.dampingRatio" # number - Damping of the pull: 1 = no overshoot.
---| "joint.mouse.maxForce" # number - Strongest pull applied.
---| "joint.mouse.collideConnected" # boolean - Let the two connected bodies collide with each other.
---| "joint.prismatic.localAnchorA" # Vec2 - Anchor on body A, relative to its origin (px).
---| "joint.prismatic.localAnchorB" # Vec2 - Anchor on body B, relative to its origin (px).
---| "joint.prismatic.localAxisA" # Vec2 - Direction body B slides along, in body A's space.
---| "joint.prismatic.referenceAngle" # number - Body B's angle relative to body A that counts as zero (degrees).
---| "joint.prismatic.targetTranslation" # number - Position the spring pulls to along the axis (px).
---| "joint.prismatic.enableSpring" # boolean - Make the joint springy instead of rigid.
---| "joint.prismatic.hertz" # number - Spring stiffness as an oscillation frequency (Hz); 0 = no spring.
---| "joint.prismatic.dampingRatio" # number - Spring damping: 0 bounces forever, 1 settles without overshoot.
---| "joint.prismatic.enableLimit" # boolean - Clamp the joint's travel to the lower / upper limits.
---| "joint.prismatic.lowerTranslation" # number - Furthest back along the axis (px; with the limit on).
---| "joint.prismatic.upperTranslation" # number - Furthest forward along the axis (px; with the limit on).
---| "joint.prismatic.enableMotor" # boolean - Drive the joint at Motor Speed, up to the maximum force / torque.
---| "joint.prismatic.maxMotorForce" # number - Strongest push the motor applies (pixel-scale bodies are heavy).
---| "joint.prismatic.motorSpeed" # number - Sliding speed the motor drives (px/s).
---| "joint.prismatic.collideConnected" # boolean - Let the two connected bodies collide with each other.
---| "joint.revolute.localAnchorA" # Vec2 - Anchor on body A, relative to its origin (px).
---| "joint.revolute.localAnchorB" # Vec2 - Anchor on body B, relative to its origin (px).
---| "joint.revolute.referenceAngle" # number - Body B's angle relative to body A that counts as zero (degrees).
---| "joint.revolute.targetAngle" # number - Angle the spring pulls to (degrees).
---| "joint.revolute.enableSpring" # boolean - Make the joint springy instead of rigid.
---| "joint.revolute.hertz" # number - Spring stiffness as an oscillation frequency (Hz); 0 = no spring.
---| "joint.revolute.dampingRatio" # number - Spring damping: 0 bounces forever, 1 settles without overshoot.
---| "joint.revolute.enableLimit" # boolean - Clamp the joint's travel to the lower / upper limits.
---| "joint.revolute.lowerAngle" # number - Smallest angle (degrees; with the limit on).
---| "joint.revolute.upperAngle" # number - Largest angle (degrees; with the limit on).
---| "joint.revolute.enableMotor" # boolean - Drive the joint at Motor Speed, up to the maximum force / torque.
---| "joint.revolute.maxMotorTorque" # number - Strongest twist the motor applies (pixel-scale bodies are heavy).
---| "joint.revolute.motorSpeed" # number - Spin speed the motor drives (radians/s).
---| "joint.revolute.collideConnected" # boolean - Let the two connected bodies collide with each other.
---| "joint.weld.localAnchorA" # Vec2 - Anchor on body A, relative to its origin (px).
---| "joint.weld.localAnchorB" # Vec2 - Anchor on body B, relative to its origin (px).
---| "joint.weld.referenceAngle" # number - Body B's angle relative to body A that counts as zero (degrees).
---| "joint.weld.linearHertz" # number - Positional softness (Hz); 0 = rigid.
---| "joint.weld.angularHertz" # number - Angular softness (Hz); 0 = rigid.
---| "joint.weld.linearDampingRatio" # number - Damping of the positional softness.
---| "joint.weld.angularDampingRatio" # number - Damping of the angular softness.
---| "joint.weld.collideConnected" # boolean - Let the two connected bodies collide with each other.
---| "joint.wheel.localAnchorA" # Vec2 - Anchor on body A, relative to its origin (px).
---| "joint.wheel.localAnchorB" # Vec2 - Anchor on body B, relative to its origin (px).
---| "joint.wheel.localAxisA" # Vec2 - Suspension direction, in body A's space.
---| "joint.wheel.enableSpring" # boolean - Springy suspension along the axis.
---| "joint.wheel.hertz" # number - Spring stiffness as an oscillation frequency (Hz); 0 = no spring.
---| "joint.wheel.dampingRatio" # number - Spring damping: 0 bounces forever, 1 settles without overshoot.
---| "joint.wheel.enableLimit" # boolean - Clamp the joint's travel to the lower / upper limits.
---| "joint.wheel.lowerTranslation" # number - Suspension's lowest travel (px; with the limit on).
---| "joint.wheel.upperTranslation" # number - Suspension's highest travel (px; with the limit on).
---| "joint.wheel.enableMotor" # boolean - Drive the joint at Motor Speed, up to the maximum force / torque.
---| "joint.wheel.maxMotorTorque" # number - Strongest twist the wheel motor applies (pixel-scale bodies are heavy).
---| "joint.wheel.motorSpeed" # number - Wheel spin speed the motor drives (radians/s).
---| "joint.wheel.collideConnected" # boolean - Let the two connected bodies collide with each other.
---| "debugColor" # number[] - Colour of the line drawn between the anchors.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("debugColor")`
---@param path JointNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: JointNode, path: "position"): Vec2
---@overload fun(self: JointNode, path: "scale"): Vec2
---@overload fun(self: JointNode, path: "rotation"): number
---@overload fun(self: JointNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: JointNode, path: "zIndex"): integer
---@overload fun(self: JointNode, path: "ySort"): boolean
---@overload fun(self: JointNode, path: "ySortOffset"): number
---@overload fun(self: JointNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: JointNode, path: "paused"): boolean
---@overload fun(self: JointNode, path: "enabled"): boolean
---@overload fun(self: JointNode, path: "joint.type"): "Distance"|"Filter"|"Motor"|"Mouse"|"Prismatic"|"Revolute"|"Weld"|"Wheel"
---@overload fun(self: JointNode, path: "joint.distance.localAnchorA"): Vec2
---@overload fun(self: JointNode, path: "joint.distance.localAnchorB"): Vec2
---@overload fun(self: JointNode, path: "joint.distance.length"): number
---@overload fun(self: JointNode, path: "joint.distance.enableSpring"): boolean
---@overload fun(self: JointNode, path: "joint.distance.hertz"): number
---@overload fun(self: JointNode, path: "joint.distance.dampingRatio"): number
---@overload fun(self: JointNode, path: "joint.distance.enableLimit"): boolean
---@overload fun(self: JointNode, path: "joint.distance.minLength"): number
---@overload fun(self: JointNode, path: "joint.distance.maxLength"): number
---@overload fun(self: JointNode, path: "joint.distance.enableMotor"): boolean
---@overload fun(self: JointNode, path: "joint.distance.maxMotorForce"): number
---@overload fun(self: JointNode, path: "joint.distance.motorSpeed"): number
---@overload fun(self: JointNode, path: "joint.distance.collideConnected"): boolean
---@overload fun(self: JointNode, path: "joint.motor.linearOffset"): Vec2
---@overload fun(self: JointNode, path: "joint.motor.angularOffset"): number
---@overload fun(self: JointNode, path: "joint.motor.maxForce"): number
---@overload fun(self: JointNode, path: "joint.motor.maxTorque"): number
---@overload fun(self: JointNode, path: "joint.motor.correctionFactor"): number
---@overload fun(self: JointNode, path: "joint.motor.collideConnected"): boolean
---@overload fun(self: JointNode, path: "joint.mouse.target"): Vec2
---@overload fun(self: JointNode, path: "joint.mouse.hertz"): number
---@overload fun(self: JointNode, path: "joint.mouse.dampingRatio"): number
---@overload fun(self: JointNode, path: "joint.mouse.maxForce"): number
---@overload fun(self: JointNode, path: "joint.mouse.collideConnected"): boolean
---@overload fun(self: JointNode, path: "joint.prismatic.localAnchorA"): Vec2
---@overload fun(self: JointNode, path: "joint.prismatic.localAnchorB"): Vec2
---@overload fun(self: JointNode, path: "joint.prismatic.localAxisA"): Vec2
---@overload fun(self: JointNode, path: "joint.prismatic.referenceAngle"): number
---@overload fun(self: JointNode, path: "joint.prismatic.targetTranslation"): number
---@overload fun(self: JointNode, path: "joint.prismatic.enableSpring"): boolean
---@overload fun(self: JointNode, path: "joint.prismatic.hertz"): number
---@overload fun(self: JointNode, path: "joint.prismatic.dampingRatio"): number
---@overload fun(self: JointNode, path: "joint.prismatic.enableLimit"): boolean
---@overload fun(self: JointNode, path: "joint.prismatic.lowerTranslation"): number
---@overload fun(self: JointNode, path: "joint.prismatic.upperTranslation"): number
---@overload fun(self: JointNode, path: "joint.prismatic.enableMotor"): boolean
---@overload fun(self: JointNode, path: "joint.prismatic.maxMotorForce"): number
---@overload fun(self: JointNode, path: "joint.prismatic.motorSpeed"): number
---@overload fun(self: JointNode, path: "joint.prismatic.collideConnected"): boolean
---@overload fun(self: JointNode, path: "joint.revolute.localAnchorA"): Vec2
---@overload fun(self: JointNode, path: "joint.revolute.localAnchorB"): Vec2
---@overload fun(self: JointNode, path: "joint.revolute.referenceAngle"): number
---@overload fun(self: JointNode, path: "joint.revolute.targetAngle"): number
---@overload fun(self: JointNode, path: "joint.revolute.enableSpring"): boolean
---@overload fun(self: JointNode, path: "joint.revolute.hertz"): number
---@overload fun(self: JointNode, path: "joint.revolute.dampingRatio"): number
---@overload fun(self: JointNode, path: "joint.revolute.enableLimit"): boolean
---@overload fun(self: JointNode, path: "joint.revolute.lowerAngle"): number
---@overload fun(self: JointNode, path: "joint.revolute.upperAngle"): number
---@overload fun(self: JointNode, path: "joint.revolute.enableMotor"): boolean
---@overload fun(self: JointNode, path: "joint.revolute.maxMotorTorque"): number
---@overload fun(self: JointNode, path: "joint.revolute.motorSpeed"): number
---@overload fun(self: JointNode, path: "joint.revolute.collideConnected"): boolean
---@overload fun(self: JointNode, path: "joint.weld.localAnchorA"): Vec2
---@overload fun(self: JointNode, path: "joint.weld.localAnchorB"): Vec2
---@overload fun(self: JointNode, path: "joint.weld.referenceAngle"): number
---@overload fun(self: JointNode, path: "joint.weld.linearHertz"): number
---@overload fun(self: JointNode, path: "joint.weld.angularHertz"): number
---@overload fun(self: JointNode, path: "joint.weld.linearDampingRatio"): number
---@overload fun(self: JointNode, path: "joint.weld.angularDampingRatio"): number
---@overload fun(self: JointNode, path: "joint.weld.collideConnected"): boolean
---@overload fun(self: JointNode, path: "joint.wheel.localAnchorA"): Vec2
---@overload fun(self: JointNode, path: "joint.wheel.localAnchorB"): Vec2
---@overload fun(self: JointNode, path: "joint.wheel.localAxisA"): Vec2
---@overload fun(self: JointNode, path: "joint.wheel.enableSpring"): boolean
---@overload fun(self: JointNode, path: "joint.wheel.hertz"): number
---@overload fun(self: JointNode, path: "joint.wheel.dampingRatio"): number
---@overload fun(self: JointNode, path: "joint.wheel.enableLimit"): boolean
---@overload fun(self: JointNode, path: "joint.wheel.lowerTranslation"): number
---@overload fun(self: JointNode, path: "joint.wheel.upperTranslation"): number
---@overload fun(self: JointNode, path: "joint.wheel.enableMotor"): boolean
---@overload fun(self: JointNode, path: "joint.wheel.maxMotorTorque"): number
---@overload fun(self: JointNode, path: "joint.wheel.motorSpeed"): number
---@overload fun(self: JointNode, path: "joint.wheel.collideConnected"): boolean
---@overload fun(self: JointNode, path: "debugColor"): number[]
function JointNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("debugColor", "#ff8800")`
---@param path JointNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: JointNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "rotation", value: number)
---@overload fun(self: JointNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: JointNode, path: "zIndex", value: integer)
---@overload fun(self: JointNode, path: "ySort", value: boolean)
---@overload fun(self: JointNode, path: "ySortOffset", value: number)
---@overload fun(self: JointNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: JointNode, path: "paused", value: boolean)
---@overload fun(self: JointNode, path: "enabled", value: boolean)
---@overload fun(self: JointNode, path: "joint.type", value: "Distance"|"Filter"|"Motor"|"Mouse"|"Prismatic"|"Revolute"|"Weld"|"Wheel")
---@overload fun(self: JointNode, path: "joint.distance.localAnchorA", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.distance.localAnchorB", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.distance.length", value: number)
---@overload fun(self: JointNode, path: "joint.distance.enableSpring", value: boolean)
---@overload fun(self: JointNode, path: "joint.distance.hertz", value: number)
---@overload fun(self: JointNode, path: "joint.distance.dampingRatio", value: number)
---@overload fun(self: JointNode, path: "joint.distance.enableLimit", value: boolean)
---@overload fun(self: JointNode, path: "joint.distance.minLength", value: number)
---@overload fun(self: JointNode, path: "joint.distance.maxLength", value: number)
---@overload fun(self: JointNode, path: "joint.distance.enableMotor", value: boolean)
---@overload fun(self: JointNode, path: "joint.distance.maxMotorForce", value: number)
---@overload fun(self: JointNode, path: "joint.distance.motorSpeed", value: number)
---@overload fun(self: JointNode, path: "joint.distance.collideConnected", value: boolean)
---@overload fun(self: JointNode, path: "joint.motor.linearOffset", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.motor.angularOffset", value: number)
---@overload fun(self: JointNode, path: "joint.motor.maxForce", value: number)
---@overload fun(self: JointNode, path: "joint.motor.maxTorque", value: number)
---@overload fun(self: JointNode, path: "joint.motor.correctionFactor", value: number)
---@overload fun(self: JointNode, path: "joint.motor.collideConnected", value: boolean)
---@overload fun(self: JointNode, path: "joint.mouse.target", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.mouse.hertz", value: number)
---@overload fun(self: JointNode, path: "joint.mouse.dampingRatio", value: number)
---@overload fun(self: JointNode, path: "joint.mouse.maxForce", value: number)
---@overload fun(self: JointNode, path: "joint.mouse.collideConnected", value: boolean)
---@overload fun(self: JointNode, path: "joint.prismatic.localAnchorA", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.prismatic.localAnchorB", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.prismatic.localAxisA", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.prismatic.referenceAngle", value: number)
---@overload fun(self: JointNode, path: "joint.prismatic.targetTranslation", value: number)
---@overload fun(self: JointNode, path: "joint.prismatic.enableSpring", value: boolean)
---@overload fun(self: JointNode, path: "joint.prismatic.hertz", value: number)
---@overload fun(self: JointNode, path: "joint.prismatic.dampingRatio", value: number)
---@overload fun(self: JointNode, path: "joint.prismatic.enableLimit", value: boolean)
---@overload fun(self: JointNode, path: "joint.prismatic.lowerTranslation", value: number)
---@overload fun(self: JointNode, path: "joint.prismatic.upperTranslation", value: number)
---@overload fun(self: JointNode, path: "joint.prismatic.enableMotor", value: boolean)
---@overload fun(self: JointNode, path: "joint.prismatic.maxMotorForce", value: number)
---@overload fun(self: JointNode, path: "joint.prismatic.motorSpeed", value: number)
---@overload fun(self: JointNode, path: "joint.prismatic.collideConnected", value: boolean)
---@overload fun(self: JointNode, path: "joint.revolute.localAnchorA", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.revolute.localAnchorB", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.revolute.referenceAngle", value: number)
---@overload fun(self: JointNode, path: "joint.revolute.targetAngle", value: number)
---@overload fun(self: JointNode, path: "joint.revolute.enableSpring", value: boolean)
---@overload fun(self: JointNode, path: "joint.revolute.hertz", value: number)
---@overload fun(self: JointNode, path: "joint.revolute.dampingRatio", value: number)
---@overload fun(self: JointNode, path: "joint.revolute.enableLimit", value: boolean)
---@overload fun(self: JointNode, path: "joint.revolute.lowerAngle", value: number)
---@overload fun(self: JointNode, path: "joint.revolute.upperAngle", value: number)
---@overload fun(self: JointNode, path: "joint.revolute.enableMotor", value: boolean)
---@overload fun(self: JointNode, path: "joint.revolute.maxMotorTorque", value: number)
---@overload fun(self: JointNode, path: "joint.revolute.motorSpeed", value: number)
---@overload fun(self: JointNode, path: "joint.revolute.collideConnected", value: boolean)
---@overload fun(self: JointNode, path: "joint.weld.localAnchorA", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.weld.localAnchorB", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.weld.referenceAngle", value: number)
---@overload fun(self: JointNode, path: "joint.weld.linearHertz", value: number)
---@overload fun(self: JointNode, path: "joint.weld.angularHertz", value: number)
---@overload fun(self: JointNode, path: "joint.weld.linearDampingRatio", value: number)
---@overload fun(self: JointNode, path: "joint.weld.angularDampingRatio", value: number)
---@overload fun(self: JointNode, path: "joint.weld.collideConnected", value: boolean)
---@overload fun(self: JointNode, path: "joint.wheel.localAnchorA", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.wheel.localAnchorB", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.wheel.localAxisA", x: number|Vec2|number[], y?: number)
---@overload fun(self: JointNode, path: "joint.wheel.enableSpring", value: boolean)
---@overload fun(self: JointNode, path: "joint.wheel.hertz", value: number)
---@overload fun(self: JointNode, path: "joint.wheel.dampingRatio", value: number)
---@overload fun(self: JointNode, path: "joint.wheel.enableLimit", value: boolean)
---@overload fun(self: JointNode, path: "joint.wheel.lowerTranslation", value: number)
---@overload fun(self: JointNode, path: "joint.wheel.upperTranslation", value: number)
---@overload fun(self: JointNode, path: "joint.wheel.enableMotor", value: boolean)
---@overload fun(self: JointNode, path: "joint.wheel.maxMotorTorque", value: number)
---@overload fun(self: JointNode, path: "joint.wheel.motorSpeed", value: number)
---@overload fun(self: JointNode, path: "joint.wheel.collideConnected", value: boolean)
---@overload fun(self: JointNode, path: "debugColor", value: number[])
function JointNode:set_property(path, value, y) end

---@class TextNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field origin Vec2 Where in the image the position is, and what it rotates and scales around: a fraction o...
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field text string The text; rich text markup when Rich Text is on, a locale key when Localized.
---@field font string Project font (.ttf / .otf / .fnt; "" = the engine font).
---@field fontSize number Text size (px).
---@field color number[] Text colour (rich text [color] overrides it).
---@field align "Left"|"Center"|"Right" Alignment of the lines within the text block.
---@field maxWidth number Wrap lines at this width (px); 0 = only at line breaks.
---@field lineSpacing number Line height as a multiple of the font size.
---@field richText boolean Interpret [color=..] [size=..] [wave] [shake] tags.
---@field localized boolean The text is a key in the locale tables; shows the current language's translation.
---@field sdf boolean Signed-distance-field rendering: stays sharp when scaled or zoomed (vector fonts).
---@field revealSpeed number Typewriter: characters per second (0 = all at once); emits "revealed" when done.

---@alias TextNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "origin" # Vec2 - Where in the image the position is, and what it rotates and scales around: a fraction o...
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "text" # string - The text; rich text markup when Rich Text is on, a locale key when Localized.
---| "font" # string - Project font (.ttf / .otf / .fnt; "" = the engine font).
---| "fontSize" # number - Text size (px).
---| "color" # number[] - Text colour (rich text [color] overrides it).
---| "align" # "Left"|"Center"|"Right" - Alignment of the lines within the text block.
---| "maxWidth" # number - Wrap lines at this width (px); 0 = only at line breaks.
---| "lineSpacing" # number - Line height as a multiple of the font size.
---| "richText" # boolean - Interpret [color=..] [size=..] [wave] [shake] tags.
---| "localized" # boolean - The text is a key in the locale tables; shows the current language's translation.
---| "sdf" # boolean - Signed-distance-field rendering: stays sharp when scaled or zoomed (vector fonts).
---| "revealSpeed" # number - Typewriter: characters per second (0 = all at once); emits "revealed" when done.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("text")`
---@param path TextNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: TextNode, path: "position"): Vec2
---@overload fun(self: TextNode, path: "scale"): Vec2
---@overload fun(self: TextNode, path: "rotation"): number
---@overload fun(self: TextNode, path: "origin"): Vec2
---@overload fun(self: TextNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: TextNode, path: "zIndex"): integer
---@overload fun(self: TextNode, path: "ySort"): boolean
---@overload fun(self: TextNode, path: "ySortOffset"): number
---@overload fun(self: TextNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: TextNode, path: "paused"): boolean
---@overload fun(self: TextNode, path: "enabled"): boolean
---@overload fun(self: TextNode, path: "text"): string
---@overload fun(self: TextNode, path: "font"): string
---@overload fun(self: TextNode, path: "fontSize"): number
---@overload fun(self: TextNode, path: "color"): number[]
---@overload fun(self: TextNode, path: "align"): "Left"|"Center"|"Right"
---@overload fun(self: TextNode, path: "maxWidth"): number
---@overload fun(self: TextNode, path: "lineSpacing"): number
---@overload fun(self: TextNode, path: "richText"): boolean
---@overload fun(self: TextNode, path: "localized"): boolean
---@overload fun(self: TextNode, path: "sdf"): boolean
---@overload fun(self: TextNode, path: "revealSpeed"): number
function TextNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("text", "text")`
---@param path TextNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: TextNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: TextNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: TextNode, path: "rotation", value: number)
---@overload fun(self: TextNode, path: "origin", x: number|Vec2|number[], y?: number)
---@overload fun(self: TextNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: TextNode, path: "zIndex", value: integer)
---@overload fun(self: TextNode, path: "ySort", value: boolean)
---@overload fun(self: TextNode, path: "ySortOffset", value: number)
---@overload fun(self: TextNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: TextNode, path: "paused", value: boolean)
---@overload fun(self: TextNode, path: "enabled", value: boolean)
---@overload fun(self: TextNode, path: "text", value: string)
---@overload fun(self: TextNode, path: "font", value: string)
---@overload fun(self: TextNode, path: "fontSize", value: number)
---@overload fun(self: TextNode, path: "color", value: number[])
---@overload fun(self: TextNode, path: "align", value: "Left"|"Center"|"Right")
---@overload fun(self: TextNode, path: "maxWidth", value: number)
---@overload fun(self: TextNode, path: "lineSpacing", value: number)
---@overload fun(self: TextNode, path: "richText", value: boolean)
---@overload fun(self: TextNode, path: "localized", value: boolean)
---@overload fun(self: TextNode, path: "sdf", value: boolean)
---@overload fun(self: TextNode, path: "revealSpeed", value: number)
function TextNode:set_property(path, value, y) end

---@class DialogueNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field font string Project font ("" = the engine font).
---@field fontSize number Text size (px).
---@field textColor number[] Colour of the line's text.
---@field speakerColor number[] Colour of the speaker's name.
---@field panelColor number[] Fill colour of the box.
---@field borderColor number[] Colour of the box's border.
---@field padding number Space between the border and the text (px).
---@field revealSpeed number Typewriter speed in characters per second (0 = whole lines).
---@field advanceAction string Input action that shows the rest of the line, then the next ("confirm").
---@field localized boolean Lines are keys in the locale tables (locale/*.csv).
---@field mode "Box"|"Subtitles" Box: a dialogue box the player advances. Subtitles: the lines go on the subtitle track ...
---@field lipSync string A Lip Sync node (path) whose mouth moves with each voiced line.
---@field choiceColor number[] Fill of the selected choice when a line offers choices.
---@field autoAdvance boolean Go on to the next line by itself a moment after each line is shown (stops at choices).
---@field autoDelay number Auto Advance: seconds to wait after a line is shown, plus a little per character.

---@alias DialogueNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "font" # string - Project font ("" = the engine font).
---| "fontSize" # number - Text size (px).
---| "textColor" # number[] - Colour of the line's text.
---| "speakerColor" # number[] - Colour of the speaker's name.
---| "panelColor" # number[] - Fill colour of the box.
---| "borderColor" # number[] - Colour of the box's border.
---| "padding" # number - Space between the border and the text (px).
---| "revealSpeed" # number - Typewriter speed in characters per second (0 = whole lines).
---| "advanceAction" # string - Input action that shows the rest of the line, then the next ("confirm").
---| "localized" # boolean - Lines are keys in the locale tables (locale/*.csv).
---| "mode" # "Box"|"Subtitles" - Box: a dialogue box the player advances. Subtitles: the lines go on the subtitle track ...
---| "lipSync" # string - A Lip Sync node (path) whose mouth moves with each voiced line.
---| "choiceColor" # number[] - Fill of the selected choice when a line offers choices.
---| "autoAdvance" # boolean - Go on to the next line by itself a moment after each line is shown (stops at choices).
---| "autoDelay" # number - Auto Advance: seconds to wait after a line is shown, plus a little per character.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path DialogueNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: DialogueNode, path: "position"): Vec2
---@overload fun(self: DialogueNode, path: "scale"): Vec2
---@overload fun(self: DialogueNode, path: "rotation"): number
---@overload fun(self: DialogueNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: DialogueNode, path: "zIndex"): integer
---@overload fun(self: DialogueNode, path: "ySort"): boolean
---@overload fun(self: DialogueNode, path: "ySortOffset"): number
---@overload fun(self: DialogueNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: DialogueNode, path: "paused"): boolean
---@overload fun(self: DialogueNode, path: "enabled"): boolean
---@overload fun(self: DialogueNode, path: "size"): Vec2
---@overload fun(self: DialogueNode, path: "keyboardFocus"): boolean
---@overload fun(self: DialogueNode, path: "font"): string
---@overload fun(self: DialogueNode, path: "fontSize"): number
---@overload fun(self: DialogueNode, path: "textColor"): number[]
---@overload fun(self: DialogueNode, path: "speakerColor"): number[]
---@overload fun(self: DialogueNode, path: "panelColor"): number[]
---@overload fun(self: DialogueNode, path: "borderColor"): number[]
---@overload fun(self: DialogueNode, path: "padding"): number
---@overload fun(self: DialogueNode, path: "revealSpeed"): number
---@overload fun(self: DialogueNode, path: "advanceAction"): string
---@overload fun(self: DialogueNode, path: "localized"): boolean
---@overload fun(self: DialogueNode, path: "mode"): "Box"|"Subtitles"
---@overload fun(self: DialogueNode, path: "lipSync"): string
---@overload fun(self: DialogueNode, path: "choiceColor"): number[]
---@overload fun(self: DialogueNode, path: "autoAdvance"): boolean
---@overload fun(self: DialogueNode, path: "autoDelay"): number
function DialogueNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path DialogueNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: DialogueNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: DialogueNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: DialogueNode, path: "rotation", value: number)
---@overload fun(self: DialogueNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: DialogueNode, path: "zIndex", value: integer)
---@overload fun(self: DialogueNode, path: "ySort", value: boolean)
---@overload fun(self: DialogueNode, path: "ySortOffset", value: number)
---@overload fun(self: DialogueNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: DialogueNode, path: "paused", value: boolean)
---@overload fun(self: DialogueNode, path: "enabled", value: boolean)
---@overload fun(self: DialogueNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: DialogueNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: DialogueNode, path: "font", value: string)
---@overload fun(self: DialogueNode, path: "fontSize", value: number)
---@overload fun(self: DialogueNode, path: "textColor", value: number[])
---@overload fun(self: DialogueNode, path: "speakerColor", value: number[])
---@overload fun(self: DialogueNode, path: "panelColor", value: number[])
---@overload fun(self: DialogueNode, path: "borderColor", value: number[])
---@overload fun(self: DialogueNode, path: "padding", value: number)
---@overload fun(self: DialogueNode, path: "revealSpeed", value: number)
---@overload fun(self: DialogueNode, path: "advanceAction", value: string)
---@overload fun(self: DialogueNode, path: "localized", value: boolean)
---@overload fun(self: DialogueNode, path: "mode", value: "Box"|"Subtitles")
---@overload fun(self: DialogueNode, path: "lipSync", value: string)
---@overload fun(self: DialogueNode, path: "choiceColor", value: number[])
---@overload fun(self: DialogueNode, path: "autoAdvance", value: boolean)
---@overload fun(self: DialogueNode, path: "autoDelay", value: number)
function DialogueNode:set_property(path, value, y) end

---@class LipSyncNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field mouth string The mouth: a Vector Shape whose group's frames are mouth shapes (path from this node, e...
---@field sound string The voice it plays (with Play, autoplay or lipsync_play).
---@field cues string Rhubarb Lip Sync's output (TSV or JSON); empty: the sound's .json / .tsv beside it.
---@field mapping string Mouth frame names per Rhubarb shape ("A=MBP,B=etc,X=rest"); empty: frames named A-H and...
---@field autoplay boolean Play the sound when the scene starts.
---@field playing boolean A voice is moving the mouth now.
---@field time number Seconds into the voice.

---@alias LipSyncNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "mouth" # string - The mouth: a Vector Shape whose group's frames are mouth shapes (path from this node, e...
---| "sound" # string - The voice it plays (with Play, autoplay or lipsync_play).
---| "cues" # string - Rhubarb Lip Sync's output (TSV or JSON); empty: the sound's .json / .tsv beside it.
---| "mapping" # string - Mouth frame names per Rhubarb shape ("A=MBP,B=etc,X=rest"); empty: frames named A-H and...
---| "autoplay" # boolean - Play the sound when the scene starts.
---| "playing" # boolean (runtime) - A voice is moving the mouth now.
---| "time" # number (runtime) - Seconds into the voice.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("mouth")`
---@param path LipSyncNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: LipSyncNode, path: "position"): Vec2
---@overload fun(self: LipSyncNode, path: "scale"): Vec2
---@overload fun(self: LipSyncNode, path: "rotation"): number
---@overload fun(self: LipSyncNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: LipSyncNode, path: "zIndex"): integer
---@overload fun(self: LipSyncNode, path: "ySort"): boolean
---@overload fun(self: LipSyncNode, path: "ySortOffset"): number
---@overload fun(self: LipSyncNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: LipSyncNode, path: "paused"): boolean
---@overload fun(self: LipSyncNode, path: "enabled"): boolean
---@overload fun(self: LipSyncNode, path: "mouth"): string
---@overload fun(self: LipSyncNode, path: "sound"): string
---@overload fun(self: LipSyncNode, path: "cues"): string
---@overload fun(self: LipSyncNode, path: "mapping"): string
---@overload fun(self: LipSyncNode, path: "autoplay"): boolean
---@overload fun(self: LipSyncNode, path: "playing"): boolean
---@overload fun(self: LipSyncNode, path: "time"): number
function LipSyncNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("mouth", "text")`
---@param path LipSyncNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: LipSyncNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: LipSyncNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: LipSyncNode, path: "rotation", value: number)
---@overload fun(self: LipSyncNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: LipSyncNode, path: "zIndex", value: integer)
---@overload fun(self: LipSyncNode, path: "ySort", value: boolean)
---@overload fun(self: LipSyncNode, path: "ySortOffset", value: number)
---@overload fun(self: LipSyncNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: LipSyncNode, path: "paused", value: boolean)
---@overload fun(self: LipSyncNode, path: "enabled", value: boolean)
---@overload fun(self: LipSyncNode, path: "mouth", value: string)
---@overload fun(self: LipSyncNode, path: "sound", value: string)
---@overload fun(self: LipSyncNode, path: "cues", value: string)
---@overload fun(self: LipSyncNode, path: "mapping", value: string)
---@overload fun(self: LipSyncNode, path: "autoplay", value: boolean)
---@overload fun(self: LipSyncNode, path: "playing", value: boolean)
---@overload fun(self: LipSyncNode, path: "time", value: number)
function LipSyncNode:set_property(path, value, y) end

---@class NineSliceNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field origin Vec2 Where in the image the position is, and what it rotates and scales around: a fraction o...
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field texturePath string Texture to slice.
---@field size Vec2 Drawn size (px); the borders keep their size, the middle stretches.
---@field marginsLT Vec2 Left and top border widths (texture px).
---@field marginsRB Vec2 Right and bottom border widths (texture px).
---@field tint number[] Multiplies the texture's colours (white = unchanged; alpha fades it).

---@alias NineSliceNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "origin" # Vec2 - Where in the image the position is, and what it rotates and scales around: a fraction o...
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "texturePath" # string - Texture to slice.
---| "size" # Vec2 - Drawn size (px); the borders keep their size, the middle stretches.
---| "marginsLT" # Vec2 - Left and top border widths (texture px).
---| "marginsRB" # Vec2 - Right and bottom border widths (texture px).
---| "tint" # number[] - Multiplies the texture's colours (white = unchanged; alpha fades it).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("texturePath")`
---@param path NineSliceNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: NineSliceNode, path: "position"): Vec2
---@overload fun(self: NineSliceNode, path: "scale"): Vec2
---@overload fun(self: NineSliceNode, path: "rotation"): number
---@overload fun(self: NineSliceNode, path: "origin"): Vec2
---@overload fun(self: NineSliceNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: NineSliceNode, path: "zIndex"): integer
---@overload fun(self: NineSliceNode, path: "ySort"): boolean
---@overload fun(self: NineSliceNode, path: "ySortOffset"): number
---@overload fun(self: NineSliceNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: NineSliceNode, path: "paused"): boolean
---@overload fun(self: NineSliceNode, path: "enabled"): boolean
---@overload fun(self: NineSliceNode, path: "texturePath"): string
---@overload fun(self: NineSliceNode, path: "size"): Vec2
---@overload fun(self: NineSliceNode, path: "marginsLT"): Vec2
---@overload fun(self: NineSliceNode, path: "marginsRB"): Vec2
---@overload fun(self: NineSliceNode, path: "tint"): number[]
function NineSliceNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("texturePath", "text")`
---@param path NineSliceNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: NineSliceNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: NineSliceNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: NineSliceNode, path: "rotation", value: number)
---@overload fun(self: NineSliceNode, path: "origin", x: number|Vec2|number[], y?: number)
---@overload fun(self: NineSliceNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: NineSliceNode, path: "zIndex", value: integer)
---@overload fun(self: NineSliceNode, path: "ySort", value: boolean)
---@overload fun(self: NineSliceNode, path: "ySortOffset", value: number)
---@overload fun(self: NineSliceNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: NineSliceNode, path: "paused", value: boolean)
---@overload fun(self: NineSliceNode, path: "enabled", value: boolean)
---@overload fun(self: NineSliceNode, path: "texturePath", value: string)
---@overload fun(self: NineSliceNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: NineSliceNode, path: "marginsLT", x: number|Vec2|number[], y?: number)
---@overload fun(self: NineSliceNode, path: "marginsRB", x: number|Vec2|number[], y?: number)
---@overload fun(self: NineSliceNode, path: "tint", value: number[])
function NineSliceNode:set_property(path, value, y) end

---@class ParallaxNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field texturePath string Background texture.
---@field factor Vec2 Movement relative to the camera: 1 moves with the world, 0 stays fixed on screen.
---@field repeatX boolean Tile horizontally to fill the view.
---@field repeatY boolean Tile vertically to fill the view.
---@field scrollSpeed Vec2 Drifts by itself (px/s; clouds).
---@field tint number[] Multiplies the texture's colours (white = unchanged; alpha fades it).

---@alias ParallaxNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "texturePath" # string - Background texture.
---| "factor" # Vec2 - Movement relative to the camera: 1 moves with the world, 0 stays fixed on screen.
---| "repeatX" # boolean - Tile horizontally to fill the view.
---| "repeatY" # boolean - Tile vertically to fill the view.
---| "scrollSpeed" # Vec2 - Drifts by itself (px/s; clouds).
---| "tint" # number[] - Multiplies the texture's colours (white = unchanged; alpha fades it).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("texturePath")`
---@param path ParallaxNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: ParallaxNode, path: "position"): Vec2
---@overload fun(self: ParallaxNode, path: "scale"): Vec2
---@overload fun(self: ParallaxNode, path: "rotation"): number
---@overload fun(self: ParallaxNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: ParallaxNode, path: "zIndex"): integer
---@overload fun(self: ParallaxNode, path: "ySort"): boolean
---@overload fun(self: ParallaxNode, path: "ySortOffset"): number
---@overload fun(self: ParallaxNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: ParallaxNode, path: "paused"): boolean
---@overload fun(self: ParallaxNode, path: "enabled"): boolean
---@overload fun(self: ParallaxNode, path: "texturePath"): string
---@overload fun(self: ParallaxNode, path: "factor"): Vec2
---@overload fun(self: ParallaxNode, path: "repeatX"): boolean
---@overload fun(self: ParallaxNode, path: "repeatY"): boolean
---@overload fun(self: ParallaxNode, path: "scrollSpeed"): Vec2
---@overload fun(self: ParallaxNode, path: "tint"): number[]
function ParallaxNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("texturePath", "text")`
---@param path ParallaxNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: ParallaxNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParallaxNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParallaxNode, path: "rotation", value: number)
---@overload fun(self: ParallaxNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: ParallaxNode, path: "zIndex", value: integer)
---@overload fun(self: ParallaxNode, path: "ySort", value: boolean)
---@overload fun(self: ParallaxNode, path: "ySortOffset", value: number)
---@overload fun(self: ParallaxNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: ParallaxNode, path: "paused", value: boolean)
---@overload fun(self: ParallaxNode, path: "enabled", value: boolean)
---@overload fun(self: ParallaxNode, path: "texturePath", value: string)
---@overload fun(self: ParallaxNode, path: "factor", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParallaxNode, path: "repeatX", value: boolean)
---@overload fun(self: ParallaxNode, path: "repeatY", value: boolean)
---@overload fun(self: ParallaxNode, path: "scrollSpeed", x: number|Vec2|number[], y?: number)
---@overload fun(self: ParallaxNode, path: "tint", value: number[])
function ParallaxNode:set_property(path, value, y) end

---@class LineNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field width number Line thickness (px).
---@field color number[] Line colour.
---@field closed boolean Join the last point to the first.
---@field rounded boolean Round joints and caps.

---@alias LineNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "width" # number - Line thickness (px).
---| "color" # number[] - Line colour.
---| "closed" # boolean - Join the last point to the first.
---| "rounded" # boolean - Round joints and caps.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("width")`
---@param path LineNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: LineNode, path: "position"): Vec2
---@overload fun(self: LineNode, path: "scale"): Vec2
---@overload fun(self: LineNode, path: "rotation"): number
---@overload fun(self: LineNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: LineNode, path: "zIndex"): integer
---@overload fun(self: LineNode, path: "ySort"): boolean
---@overload fun(self: LineNode, path: "ySortOffset"): number
---@overload fun(self: LineNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: LineNode, path: "paused"): boolean
---@overload fun(self: LineNode, path: "enabled"): boolean
---@overload fun(self: LineNode, path: "width"): number
---@overload fun(self: LineNode, path: "color"): number[]
---@overload fun(self: LineNode, path: "closed"): boolean
---@overload fun(self: LineNode, path: "rounded"): boolean
function LineNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("width", 1.5)`
---@param path LineNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: LineNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: LineNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: LineNode, path: "rotation", value: number)
---@overload fun(self: LineNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: LineNode, path: "zIndex", value: integer)
---@overload fun(self: LineNode, path: "ySort", value: boolean)
---@overload fun(self: LineNode, path: "ySortOffset", value: number)
---@overload fun(self: LineNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: LineNode, path: "paused", value: boolean)
---@overload fun(self: LineNode, path: "enabled", value: boolean)
---@overload fun(self: LineNode, path: "width", value: number)
---@overload fun(self: LineNode, path: "color", value: number[])
---@overload fun(self: LineNode, path: "closed", value: boolean)
---@overload fun(self: LineNode, path: "rounded", value: boolean)
function LineNode:set_property(path, value, y) end

---@class VectorShapeNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field file string The SVG it draws (project path); empty: the preset. Reloads when the file is saved.
---@field group string A symbol: draw only this named group of the file (Inkscape layer, Illustrator group; "a...
---@field frame integer Part swapping: show only this child group of the group (mouths, hands, eyes); -1 shows ...
---@field preset "Star"|"Ring"|"Badge"|"Character"|"Gradients" The built-in shape it draws when it has no file.
---@field fillColor number[] The shape's fill colour.
---@field strokeColor number[] The outline's colour.
---@field strokeWidth number Outline thickness (px, in the shape's own scale); 0 = no outline.
---@field tint number[] Multiplies the texture's colours (white = unchanged; alpha fades it).
---@field brightness number Darken (-1 black) or lighten (1 white) the art (Flash's brightness effect).
---@field colorAdd number[] A colour added to the art's colours (Flash's advanced colour offset): flash white on a ...
---@field trimStart number Trim paths: where along each path drawing starts (0..1 of its length). Key Start / End ...
---@field trimEnd number Trim paths: where along each path drawing stops (1 = the end; 0.5 draws the first half).
---@field trimOffset number Trim paths: moves the drawn part along the path, wrapping round (animate it for a runni...
---@field trimEach boolean Trim every subpath on its own (a ring's circles drawn on together) instead of one after...
---@field morphTo string Shape tween: another group of the same file to morph into (Flash's shape tweens).
---@field morph number Shape tween: 0 draws the group, 1 draws Morph To, between interpolates paths, colours, ...
---@field lineScale "Scale"|"Constant" Scale: outlines get thicker / thinner with the node's scale. Constant: they keep their ...
---@field shadowColor number[] Drop shadow filter: its colour (alpha 0: no shadow). Filters draw the art through a tex...
---@field shadowOffset Vec2 Drop shadow: how far the shadow sits from the art (screen px).
---@field shadowBlur number Drop shadow: how soft its edge is (screen px).
---@field glowColor number[] Glow filter: an outer glow's colour (alpha 0: no glow).
---@field glowSize number Glow: how far it spreads (screen px).
---@field glowStrength number Glow: how strong it is (1 = the blurred coverage; more: brighter, harder).
---@field outlineColor number[] Outline filter: a line round the whole drawing (cel-shading, selection); alpha 0: none.
---@field outlineWidth number Outline: its thickness (screen px).
---@field blur number Blur filter: blurs the art itself (screen px); 0 = sharp.
---@field saturation number Colour filter: 0 grey, 1 as drawn, 2 vivid.
---@field contrast number Colour filter: 1 as drawn; less: flatter, more: punchier.
---@field hue number Colour filter: turns the colours round the colour wheel (degrees).
---@field skinBones string Vector skinning: the bones of a Skeleton above it that the art bends with ("upper, lowe...
---@field skinSmooth number Vector skinning: how far round each joint (px) neighbouring bones blend - 0 makes rigid...
---@field warpTopLeft Vec2 Four-corner warp (squash and stretch): how far the art's top-left corner moves (px); th...
---@field warpTopRight Vec2 Four-corner warp: how far the top-right corner moves (px).
---@field warpBottomLeft Vec2 Four-corner warp: how far the bottom-left corner moves (px).
---@field warpBottomRight Vec2 Four-corner warp: how far the bottom-right corner moves (px).
---@field collider "None"|"Solid"|"Outline" Collision from the art: Solid makes convex pieces (any body), Outline edge loops (smoot...
---@field colliderDetail number How closely the collider follows the art (its units): bigger means fewer corners, faste...
---@field colliderFriction number The collider's friction (0 ice ... 1 rubber).
---@field colliderBounce number The collider's restitution (0 no bounce ... 1 full bounce).
---@field colliderDensity number The collider's density: the mass it gives a Dynamic Body.

---@alias VectorShapeNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "file" # string - The SVG it draws (project path); empty: the preset. Reloads when the file is saved.
---| "group" # string - A symbol: draw only this named group of the file (Inkscape layer, Illustrator group; "a...
---| "frame" # integer - Part swapping: show only this child group of the group (mouths, hands, eyes); -1 shows ...
---| "preset" # "Star"|"Ring"|"Badge"|"Character"|"Gradients" - The built-in shape it draws when it has no file.
---| "fillColor" # number[] - The shape's fill colour.
---| "strokeColor" # number[] - The outline's colour.
---| "strokeWidth" # number - Outline thickness (px, in the shape's own scale); 0 = no outline.
---| "tint" # number[] - Multiplies the texture's colours (white = unchanged; alpha fades it).
---| "brightness" # number - Darken (-1 black) or lighten (1 white) the art (Flash's brightness effect).
---| "colorAdd" # number[] - A colour added to the art's colours (Flash's advanced colour offset): flash white on a ...
---| "trimStart" # number - Trim paths: where along each path drawing starts (0..1 of its length). Key Start / End ...
---| "trimEnd" # number - Trim paths: where along each path drawing stops (1 = the end; 0.5 draws the first half).
---| "trimOffset" # number - Trim paths: moves the drawn part along the path, wrapping round (animate it for a runni...
---| "trimEach" # boolean - Trim every subpath on its own (a ring's circles drawn on together) instead of one after...
---| "morphTo" # string - Shape tween: another group of the same file to morph into (Flash's shape tweens).
---| "morph" # number - Shape tween: 0 draws the group, 1 draws Morph To, between interpolates paths, colours, ...
---| "lineScale" # "Scale"|"Constant" - Scale: outlines get thicker / thinner with the node's scale. Constant: they keep their ...
---| "shadowColor" # number[] - Drop shadow filter: its colour (alpha 0: no shadow). Filters draw the art through a tex...
---| "shadowOffset" # Vec2 - Drop shadow: how far the shadow sits from the art (screen px).
---| "shadowBlur" # number - Drop shadow: how soft its edge is (screen px).
---| "glowColor" # number[] - Glow filter: an outer glow's colour (alpha 0: no glow).
---| "glowSize" # number - Glow: how far it spreads (screen px).
---| "glowStrength" # number - Glow: how strong it is (1 = the blurred coverage; more: brighter, harder).
---| "outlineColor" # number[] - Outline filter: a line round the whole drawing (cel-shading, selection); alpha 0: none.
---| "outlineWidth" # number - Outline: its thickness (screen px).
---| "blur" # number - Blur filter: blurs the art itself (screen px); 0 = sharp.
---| "saturation" # number - Colour filter: 0 grey, 1 as drawn, 2 vivid.
---| "contrast" # number - Colour filter: 1 as drawn; less: flatter, more: punchier.
---| "hue" # number - Colour filter: turns the colours round the colour wheel (degrees).
---| "skinBones" # string - Vector skinning: the bones of a Skeleton above it that the art bends with ("upper, lowe...
---| "skinSmooth" # number - Vector skinning: how far round each joint (px) neighbouring bones blend - 0 makes rigid...
---| "warpTopLeft" # Vec2 - Four-corner warp (squash and stretch): how far the art's top-left corner moves (px); th...
---| "warpTopRight" # Vec2 - Four-corner warp: how far the top-right corner moves (px).
---| "warpBottomLeft" # Vec2 - Four-corner warp: how far the bottom-left corner moves (px).
---| "warpBottomRight" # Vec2 - Four-corner warp: how far the bottom-right corner moves (px).
---| "collider" # "None"|"Solid"|"Outline" - Collision from the art: Solid makes convex pieces (any body), Outline edge loops (smoot...
---| "colliderDetail" # number - How closely the collider follows the art (its units): bigger means fewer corners, faste...
---| "colliderFriction" # number - The collider's friction (0 ice ... 1 rubber).
---| "colliderBounce" # number - The collider's restitution (0 no bounce ... 1 full bounce).
---| "colliderDensity" # number - The collider's density: the mass it gives a Dynamic Body.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("file")`
---@param path VectorShapeNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: VectorShapeNode, path: "position"): Vec2
---@overload fun(self: VectorShapeNode, path: "scale"): Vec2
---@overload fun(self: VectorShapeNode, path: "rotation"): number
---@overload fun(self: VectorShapeNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: VectorShapeNode, path: "zIndex"): integer
---@overload fun(self: VectorShapeNode, path: "ySort"): boolean
---@overload fun(self: VectorShapeNode, path: "ySortOffset"): number
---@overload fun(self: VectorShapeNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: VectorShapeNode, path: "paused"): boolean
---@overload fun(self: VectorShapeNode, path: "enabled"): boolean
---@overload fun(self: VectorShapeNode, path: "file"): string
---@overload fun(self: VectorShapeNode, path: "group"): string
---@overload fun(self: VectorShapeNode, path: "frame"): integer
---@overload fun(self: VectorShapeNode, path: "preset"): "Star"|"Ring"|"Badge"|"Character"|"Gradients"
---@overload fun(self: VectorShapeNode, path: "fillColor"): number[]
---@overload fun(self: VectorShapeNode, path: "strokeColor"): number[]
---@overload fun(self: VectorShapeNode, path: "strokeWidth"): number
---@overload fun(self: VectorShapeNode, path: "tint"): number[]
---@overload fun(self: VectorShapeNode, path: "brightness"): number
---@overload fun(self: VectorShapeNode, path: "colorAdd"): number[]
---@overload fun(self: VectorShapeNode, path: "trimStart"): number
---@overload fun(self: VectorShapeNode, path: "trimEnd"): number
---@overload fun(self: VectorShapeNode, path: "trimOffset"): number
---@overload fun(self: VectorShapeNode, path: "trimEach"): boolean
---@overload fun(self: VectorShapeNode, path: "morphTo"): string
---@overload fun(self: VectorShapeNode, path: "morph"): number
---@overload fun(self: VectorShapeNode, path: "lineScale"): "Scale"|"Constant"
---@overload fun(self: VectorShapeNode, path: "shadowColor"): number[]
---@overload fun(self: VectorShapeNode, path: "shadowOffset"): Vec2
---@overload fun(self: VectorShapeNode, path: "shadowBlur"): number
---@overload fun(self: VectorShapeNode, path: "glowColor"): number[]
---@overload fun(self: VectorShapeNode, path: "glowSize"): number
---@overload fun(self: VectorShapeNode, path: "glowStrength"): number
---@overload fun(self: VectorShapeNode, path: "outlineColor"): number[]
---@overload fun(self: VectorShapeNode, path: "outlineWidth"): number
---@overload fun(self: VectorShapeNode, path: "blur"): number
---@overload fun(self: VectorShapeNode, path: "saturation"): number
---@overload fun(self: VectorShapeNode, path: "contrast"): number
---@overload fun(self: VectorShapeNode, path: "hue"): number
---@overload fun(self: VectorShapeNode, path: "skinBones"): string
---@overload fun(self: VectorShapeNode, path: "skinSmooth"): number
---@overload fun(self: VectorShapeNode, path: "warpTopLeft"): Vec2
---@overload fun(self: VectorShapeNode, path: "warpTopRight"): Vec2
---@overload fun(self: VectorShapeNode, path: "warpBottomLeft"): Vec2
---@overload fun(self: VectorShapeNode, path: "warpBottomRight"): Vec2
---@overload fun(self: VectorShapeNode, path: "collider"): "None"|"Solid"|"Outline"
---@overload fun(self: VectorShapeNode, path: "colliderDetail"): number
---@overload fun(self: VectorShapeNode, path: "colliderFriction"): number
---@overload fun(self: VectorShapeNode, path: "colliderBounce"): number
---@overload fun(self: VectorShapeNode, path: "colliderDensity"): number
function VectorShapeNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("file", "text")`
---@param path VectorShapeNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: VectorShapeNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: VectorShapeNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: VectorShapeNode, path: "rotation", value: number)
---@overload fun(self: VectorShapeNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: VectorShapeNode, path: "zIndex", value: integer)
---@overload fun(self: VectorShapeNode, path: "ySort", value: boolean)
---@overload fun(self: VectorShapeNode, path: "ySortOffset", value: number)
---@overload fun(self: VectorShapeNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: VectorShapeNode, path: "paused", value: boolean)
---@overload fun(self: VectorShapeNode, path: "enabled", value: boolean)
---@overload fun(self: VectorShapeNode, path: "file", value: string)
---@overload fun(self: VectorShapeNode, path: "group", value: string)
---@overload fun(self: VectorShapeNode, path: "frame", value: integer)
---@overload fun(self: VectorShapeNode, path: "preset", value: "Star"|"Ring"|"Badge"|"Character"|"Gradients")
---@overload fun(self: VectorShapeNode, path: "fillColor", value: number[])
---@overload fun(self: VectorShapeNode, path: "strokeColor", value: number[])
---@overload fun(self: VectorShapeNode, path: "strokeWidth", value: number)
---@overload fun(self: VectorShapeNode, path: "tint", value: number[])
---@overload fun(self: VectorShapeNode, path: "brightness", value: number)
---@overload fun(self: VectorShapeNode, path: "colorAdd", value: number[])
---@overload fun(self: VectorShapeNode, path: "trimStart", value: number)
---@overload fun(self: VectorShapeNode, path: "trimEnd", value: number)
---@overload fun(self: VectorShapeNode, path: "trimOffset", value: number)
---@overload fun(self: VectorShapeNode, path: "trimEach", value: boolean)
---@overload fun(self: VectorShapeNode, path: "morphTo", value: string)
---@overload fun(self: VectorShapeNode, path: "morph", value: number)
---@overload fun(self: VectorShapeNode, path: "lineScale", value: "Scale"|"Constant")
---@overload fun(self: VectorShapeNode, path: "shadowColor", value: number[])
---@overload fun(self: VectorShapeNode, path: "shadowOffset", x: number|Vec2|number[], y?: number)
---@overload fun(self: VectorShapeNode, path: "shadowBlur", value: number)
---@overload fun(self: VectorShapeNode, path: "glowColor", value: number[])
---@overload fun(self: VectorShapeNode, path: "glowSize", value: number)
---@overload fun(self: VectorShapeNode, path: "glowStrength", value: number)
---@overload fun(self: VectorShapeNode, path: "outlineColor", value: number[])
---@overload fun(self: VectorShapeNode, path: "outlineWidth", value: number)
---@overload fun(self: VectorShapeNode, path: "blur", value: number)
---@overload fun(self: VectorShapeNode, path: "saturation", value: number)
---@overload fun(self: VectorShapeNode, path: "contrast", value: number)
---@overload fun(self: VectorShapeNode, path: "hue", value: number)
---@overload fun(self: VectorShapeNode, path: "skinBones", value: string)
---@overload fun(self: VectorShapeNode, path: "skinSmooth", value: number)
---@overload fun(self: VectorShapeNode, path: "warpTopLeft", x: number|Vec2|number[], y?: number)
---@overload fun(self: VectorShapeNode, path: "warpTopRight", x: number|Vec2|number[], y?: number)
---@overload fun(self: VectorShapeNode, path: "warpBottomLeft", x: number|Vec2|number[], y?: number)
---@overload fun(self: VectorShapeNode, path: "warpBottomRight", x: number|Vec2|number[], y?: number)
---@overload fun(self: VectorShapeNode, path: "collider", value: "None"|"Solid"|"Outline")
---@overload fun(self: VectorShapeNode, path: "colliderDetail", value: number)
---@overload fun(self: VectorShapeNode, path: "colliderFriction", value: number)
---@overload fun(self: VectorShapeNode, path: "colliderBounce", value: number)
---@overload fun(self: VectorShapeNode, path: "colliderDensity", value: number)
function VectorShapeNode:set_property(path, value, y) end

---@class TrailNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field lifetime number Seconds a point of the trail lasts.
---@field width number Width at the head (it tapers to the tail; px).
---@field color number[] Colour at the head.
---@field endColor number[] Colour at the tail (fades to it).
---@field minDistance number Distance the parent must move before a new point is recorded (px).
---@field emitting boolean Record new points (off: the trail fades away).

---@alias TrailNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "lifetime" # number - Seconds a point of the trail lasts.
---| "width" # number - Width at the head (it tapers to the tail; px).
---| "color" # number[] - Colour at the head.
---| "endColor" # number[] - Colour at the tail (fades to it).
---| "minDistance" # number - Distance the parent must move before a new point is recorded (px).
---| "emitting" # boolean - Record new points (off: the trail fades away).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("lifetime")`
---@param path TrailNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: TrailNode, path: "position"): Vec2
---@overload fun(self: TrailNode, path: "scale"): Vec2
---@overload fun(self: TrailNode, path: "rotation"): number
---@overload fun(self: TrailNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: TrailNode, path: "zIndex"): integer
---@overload fun(self: TrailNode, path: "ySort"): boolean
---@overload fun(self: TrailNode, path: "ySortOffset"): number
---@overload fun(self: TrailNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: TrailNode, path: "paused"): boolean
---@overload fun(self: TrailNode, path: "enabled"): boolean
---@overload fun(self: TrailNode, path: "lifetime"): number
---@overload fun(self: TrailNode, path: "width"): number
---@overload fun(self: TrailNode, path: "color"): number[]
---@overload fun(self: TrailNode, path: "endColor"): number[]
---@overload fun(self: TrailNode, path: "minDistance"): number
---@overload fun(self: TrailNode, path: "emitting"): boolean
function TrailNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("lifetime", 1.5)`
---@param path TrailNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: TrailNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: TrailNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: TrailNode, path: "rotation", value: number)
---@overload fun(self: TrailNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: TrailNode, path: "zIndex", value: integer)
---@overload fun(self: TrailNode, path: "ySort", value: boolean)
---@overload fun(self: TrailNode, path: "ySortOffset", value: number)
---@overload fun(self: TrailNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: TrailNode, path: "paused", value: boolean)
---@overload fun(self: TrailNode, path: "enabled", value: boolean)
---@overload fun(self: TrailNode, path: "lifetime", value: number)
---@overload fun(self: TrailNode, path: "width", value: number)
---@overload fun(self: TrailNode, path: "color", value: number[])
---@overload fun(self: TrailNode, path: "endColor", value: number[])
---@overload fun(self: TrailNode, path: "minDistance", value: number)
---@overload fun(self: TrailNode, path: "emitting", value: boolean)
function TrailNode:set_property(path, value, y) end

---@class UIContainerNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field title string Header text.
---@field direction "Vertical"|"Horizontal"|"Grid" Children are laid out in a column, a row or a grid.
---@field alignment "Start"|"Center"|"End"|"Stretch" Where children sit across the layout direction.
---@field spacing number Gap between items (px).
---@field paddingTop number Space above the children (px).
---@field paddingBottom number Space below the children (px).
---@field paddingLeft number Space left of the children (px).
---@field paddingRight number Space right of the children (px).
---@field columns integer Grid layout: columns per row.
---@field autoSizeHeight boolean Grow to fit the children.
---@field drawBackground boolean Fill the background.
---@field drawBorder boolean Draw a border.
---@field showHeader boolean Draw a header with the title.
---@field headerHeight number Height of the header (px).
---@field backgroundColor number[] Fill colour of the background.
---@field headerColor number[] Header fill colour.
---@field borderColor number[] Colour of the border.
---@field titleColor number[] Title text colour.

---@alias UIContainerNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "title" # string - Header text.
---| "direction" # "Vertical"|"Horizontal"|"Grid" - Children are laid out in a column, a row or a grid.
---| "alignment" # "Start"|"Center"|"End"|"Stretch" - Where children sit across the layout direction.
---| "spacing" # number - Gap between items (px).
---| "paddingTop" # number - Space above the children (px).
---| "paddingBottom" # number - Space below the children (px).
---| "paddingLeft" # number - Space left of the children (px).
---| "paddingRight" # number - Space right of the children (px).
---| "columns" # integer - Grid layout: columns per row.
---| "autoSizeHeight" # boolean - Grow to fit the children.
---| "drawBackground" # boolean - Fill the background.
---| "drawBorder" # boolean - Draw a border.
---| "showHeader" # boolean - Draw a header with the title.
---| "headerHeight" # number - Height of the header (px).
---| "backgroundColor" # number[] - Fill colour of the background.
---| "headerColor" # number[] - Header fill colour.
---| "borderColor" # number[] - Colour of the border.
---| "titleColor" # number[] - Title text colour.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UIContainerNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UIContainerNode, path: "position"): Vec2
---@overload fun(self: UIContainerNode, path: "scale"): Vec2
---@overload fun(self: UIContainerNode, path: "rotation"): number
---@overload fun(self: UIContainerNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIContainerNode, path: "zIndex"): integer
---@overload fun(self: UIContainerNode, path: "ySort"): boolean
---@overload fun(self: UIContainerNode, path: "ySortOffset"): number
---@overload fun(self: UIContainerNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIContainerNode, path: "paused"): boolean
---@overload fun(self: UIContainerNode, path: "enabled"): boolean
---@overload fun(self: UIContainerNode, path: "size"): Vec2
---@overload fun(self: UIContainerNode, path: "keyboardFocus"): boolean
---@overload fun(self: UIContainerNode, path: "title"): string
---@overload fun(self: UIContainerNode, path: "direction"): "Vertical"|"Horizontal"|"Grid"
---@overload fun(self: UIContainerNode, path: "alignment"): "Start"|"Center"|"End"|"Stretch"
---@overload fun(self: UIContainerNode, path: "spacing"): number
---@overload fun(self: UIContainerNode, path: "paddingTop"): number
---@overload fun(self: UIContainerNode, path: "paddingBottom"): number
---@overload fun(self: UIContainerNode, path: "paddingLeft"): number
---@overload fun(self: UIContainerNode, path: "paddingRight"): number
---@overload fun(self: UIContainerNode, path: "columns"): integer
---@overload fun(self: UIContainerNode, path: "autoSizeHeight"): boolean
---@overload fun(self: UIContainerNode, path: "drawBackground"): boolean
---@overload fun(self: UIContainerNode, path: "drawBorder"): boolean
---@overload fun(self: UIContainerNode, path: "showHeader"): boolean
---@overload fun(self: UIContainerNode, path: "headerHeight"): number
---@overload fun(self: UIContainerNode, path: "backgroundColor"): number[]
---@overload fun(self: UIContainerNode, path: "headerColor"): number[]
---@overload fun(self: UIContainerNode, path: "borderColor"): number[]
---@overload fun(self: UIContainerNode, path: "titleColor"): number[]
function UIContainerNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UIContainerNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UIContainerNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIContainerNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIContainerNode, path: "rotation", value: number)
---@overload fun(self: UIContainerNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIContainerNode, path: "zIndex", value: integer)
---@overload fun(self: UIContainerNode, path: "ySort", value: boolean)
---@overload fun(self: UIContainerNode, path: "ySortOffset", value: number)
---@overload fun(self: UIContainerNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIContainerNode, path: "paused", value: boolean)
---@overload fun(self: UIContainerNode, path: "enabled", value: boolean)
---@overload fun(self: UIContainerNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIContainerNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UIContainerNode, path: "title", value: string)
---@overload fun(self: UIContainerNode, path: "direction", value: "Vertical"|"Horizontal"|"Grid")
---@overload fun(self: UIContainerNode, path: "alignment", value: "Start"|"Center"|"End"|"Stretch")
---@overload fun(self: UIContainerNode, path: "spacing", value: number)
---@overload fun(self: UIContainerNode, path: "paddingTop", value: number)
---@overload fun(self: UIContainerNode, path: "paddingBottom", value: number)
---@overload fun(self: UIContainerNode, path: "paddingLeft", value: number)
---@overload fun(self: UIContainerNode, path: "paddingRight", value: number)
---@overload fun(self: UIContainerNode, path: "columns", value: integer)
---@overload fun(self: UIContainerNode, path: "autoSizeHeight", value: boolean)
---@overload fun(self: UIContainerNode, path: "drawBackground", value: boolean)
---@overload fun(self: UIContainerNode, path: "drawBorder", value: boolean)
---@overload fun(self: UIContainerNode, path: "showHeader", value: boolean)
---@overload fun(self: UIContainerNode, path: "headerHeight", value: number)
---@overload fun(self: UIContainerNode, path: "backgroundColor", value: number[])
---@overload fun(self: UIContainerNode, path: "headerColor", value: number[])
---@overload fun(self: UIContainerNode, path: "borderColor", value: number[])
---@overload fun(self: UIContainerNode, path: "titleColor", value: number[])
function UIContainerNode:set_property(path, value, y) end

---@class UILabelNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field text string Label text.
---@field fontSize number Text size (px).
---@field textColor number[] Colour of the text.
---@field align "Left"|"Center"|"Right" Horizontal text alignment.
---@field drawBackground boolean Fill the background.
---@field backgroundColor number[] Fill colour of the background.

---@alias UILabelNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "text" # string - Label text.
---| "fontSize" # number - Text size (px).
---| "textColor" # number[] - Colour of the text.
---| "align" # "Left"|"Center"|"Right" - Horizontal text alignment.
---| "drawBackground" # boolean - Fill the background.
---| "backgroundColor" # number[] - Fill colour of the background.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UILabelNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UILabelNode, path: "position"): Vec2
---@overload fun(self: UILabelNode, path: "scale"): Vec2
---@overload fun(self: UILabelNode, path: "rotation"): number
---@overload fun(self: UILabelNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UILabelNode, path: "zIndex"): integer
---@overload fun(self: UILabelNode, path: "ySort"): boolean
---@overload fun(self: UILabelNode, path: "ySortOffset"): number
---@overload fun(self: UILabelNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UILabelNode, path: "paused"): boolean
---@overload fun(self: UILabelNode, path: "enabled"): boolean
---@overload fun(self: UILabelNode, path: "size"): Vec2
---@overload fun(self: UILabelNode, path: "keyboardFocus"): boolean
---@overload fun(self: UILabelNode, path: "text"): string
---@overload fun(self: UILabelNode, path: "fontSize"): number
---@overload fun(self: UILabelNode, path: "textColor"): number[]
---@overload fun(self: UILabelNode, path: "align"): "Left"|"Center"|"Right"
---@overload fun(self: UILabelNode, path: "drawBackground"): boolean
---@overload fun(self: UILabelNode, path: "backgroundColor"): number[]
function UILabelNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UILabelNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UILabelNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UILabelNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UILabelNode, path: "rotation", value: number)
---@overload fun(self: UILabelNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UILabelNode, path: "zIndex", value: integer)
---@overload fun(self: UILabelNode, path: "ySort", value: boolean)
---@overload fun(self: UILabelNode, path: "ySortOffset", value: number)
---@overload fun(self: UILabelNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UILabelNode, path: "paused", value: boolean)
---@overload fun(self: UILabelNode, path: "enabled", value: boolean)
---@overload fun(self: UILabelNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UILabelNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UILabelNode, path: "text", value: string)
---@overload fun(self: UILabelNode, path: "fontSize", value: number)
---@overload fun(self: UILabelNode, path: "textColor", value: number[])
---@overload fun(self: UILabelNode, path: "align", value: "Left"|"Center"|"Right")
---@overload fun(self: UILabelNode, path: "drawBackground", value: boolean)
---@overload fun(self: UILabelNode, path: "backgroundColor", value: number[])
function UILabelNode:set_property(path, value, y) end

---@class UIButtonNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field text string Button caption.
---@field fontSize number Text size (px).
---@field icon "None"|"Digit0"|"Digit1"|"Digit2"|"Digit3"|"Digit4"|"Digit5"|"Digit6"|"Digit7"|"Digit8"|"Digit9"|"A"|"AddressBook"|"AddressCard"|"AlignCenter"|"AlignJustify"|"AlignLeft"|"AlignRight"|"Anchor"|"AnchorCircleCheck"|"AnchorCircleExclamation"|"AnchorCircleXmark"|"AnchorLock"|"AngleDown"|"AngleLeft"|"AngleRight"|"AngleUp"|"AnglesDown"|"AnglesLeft"|"AnglesRight"|"AnglesUp"|"Ankh"|"AppleWhole"|"Archway"|"ArrowDown"|"ArrowDown19"|"ArrowDown91"|"ArrowDownAZ"|"ArrowDownLong"|"ArrowDownShortWide"|"ArrowDownUpAcrossLine"|"ArrowDownUpLock"|"ArrowDownWideShort"|"ArrowDownZA"|"ArrowLeft"|"ArrowLeftLong"|"ArrowPointer"|"ArrowRight"|"ArrowRightArrowLeft"|"ArrowRightFromBracket"|"ArrowRightLong"|"ArrowRightToBracket"|"ArrowRightToCity"|"ArrowRotateLeft"|"ArrowRotateRight"|"ArrowTrendDown"|"ArrowTrendUp"|"ArrowTurnDown"|"ArrowTurnUp"|"ArrowUp"|"ArrowUp19"|"ArrowUp91"|"ArrowUpAZ"|"ArrowUpFromBracket"|"ArrowUpFromGroundWater"|"ArrowUpFromWaterPump"|"ArrowUpLong"|"ArrowUpRightDots"|"ArrowUpRightFromSquare"|"ArrowUpShortWide"|"ArrowUpWideShort"|"ArrowUpZA"|"ArrowsDownToLine"|"ArrowsDownToPeople"|"ArrowsLeftRight"|"ArrowsLeftRightToLine"|"ArrowsRotate"|"ArrowsSpin"|"ArrowsSplitUpAndLeft"|"ArrowsToCircle"|"ArrowsToDot"|"ArrowsToEye"|"ArrowsTurnRight"|"ArrowsTurnToDots"|"ArrowsUpDown"|"ArrowsUpDownLeftRight"|"ArrowsUpToLine"|"Asterisk"|"At"|"Atom"|"AudioDescription"|"AustralSign"|"Award"|"B"|"Baby"|"BabyCarriage"|"Backward"|"BackwardFast"|"BackwardStep"|"Bacon"|"Bacteria"|"Bacterium"|"BagShopping"|"Bahai"|"BahtSign"|"Ban"|"BanSmoking"|"Bandage"|"BangladeshiTakaSign"|"Barcode"|"Bars"|"BarsProgress"|"BarsStaggered"|"Baseball"|"BaseballBatBall"|"BasketShopping"|"Basketball"|"Bath"|"BatteryEmpty"|"BatteryFull"|"BatteryHalf"|"BatteryQuarter"|"BatteryThreeQuarters"|"Bed"|"BedPulse"|"BeerMugEmpty"|"Bell"|"BellConcierge"|"BellSlash"|"BezierCurve"|"Bicycle"|"Binoculars"|"Biohazard"|"BitcoinSign"|"Blender"|"BlenderPhone"|"Blog"|"Bold"|"Bolt"|"BoltLightning"|"Bomb"|"Bone"|"Bong"|"Book"|"BookAtlas"|"BookBible"|"BookBookmark"|"BookJournalWhills"|"BookMedical"|"BookOpen"|"BookOpenReader"|"BookQuran"|"BookSkull"|"BookTanakh"|"Bookmark"|"BorderAll"|"BorderNone"|"BorderTopLeft"|"BoreHole"|"BottleDroplet"|"BottleWater"|"BowlFood"|"BowlRice"|"BowlingBall"|"Box"|"BoxArchive"|"BoxOpen"|"BoxTissue"|"BoxesPacking"|"BoxesStacked"|"Braille"|"Brain"|"BrazilianRealSign"|"BreadSlice"|"Bridge"|"BridgeCircleCheck"|"BridgeCircleExclamation"|"BridgeCircleXmark"|"BridgeLock"|"BridgeWater"|"Briefcase"|"BriefcaseMedical"|"Broom"|"BroomBall"|"Brush"|"Bucket"|"Bug"|"BugSlash"|"Bugs"|"Building"|"BuildingCircleArrowRight"|"BuildingCircleCheck"|"BuildingCircleExclamation"|"BuildingCircleXmark"|"BuildingColumns"|"BuildingFlag"|"BuildingLock"|"BuildingNgo"|"BuildingShield"|"BuildingUn"|"BuildingUser"|"BuildingWheat"|"Bullhorn"|"Bullseye"|"Burger"|"Burst"|"Bus"|"BusSimple"|"BusinessTime"|"C"|"CableCar"|"CakeCandles"|"Calculator"|"Calendar"|"CalendarCheck"|"CalendarDay"|"CalendarDays"|"CalendarMinus"|"CalendarPlus"|"CalendarWeek"|"CalendarXmark"|"Camera"|"CameraRetro"|"CameraRotate"|"Campground"|"CandyCane"|"Cannabis"|"Capsules"|"Car"|"CarBattery"|"CarBurst"|"CarOn"|"CarRear"|"CarSide"|"CarTunnel"|"Caravan"|"CaretDown"|"CaretLeft"|"CaretRight"|"CaretUp"|"Carrot"|"CartArrowDown"|"CartFlatbed"|"CartFlatbedSuitcase"|"CartPlus"|"CartShopping"|"CashRegister"|"Cat"|"CediSign"|"CentSign"|"Certificate"|"Chair"|"Chalkboard"|"ChalkboardUser"|"ChampagneGlasses"|"ChargingStation"|"ChartArea"|"ChartBar"|"ChartColumn"|"ChartDiagram"|"ChartGantt"|"ChartLine"|"ChartPie"|"ChartSimple"|"Check"|"CheckDouble"|"CheckToSlot"|"Cheese"|"Chess"|"ChessBishop"|"ChessBoard"|"ChessKing"|"ChessKnight"|"ChessPawn"|"ChessQueen"|"ChessRook"|"ChevronDown"|"ChevronLeft"|"ChevronRight"|"ChevronUp"|"Child"|"ChildCombatant"|"ChildDress"|"ChildReaching"|"Children"|"Church"|"Circle"|"CircleArrowDown"|"CircleArrowLeft"|"CircleArrowRight"|"CircleArrowUp"|"CircleCheck"|"CircleChevronDown"|"CircleChevronLeft"|"CircleChevronRight"|"CircleChevronUp"|"CircleDollarToSlot"|"CircleDot"|"CircleDown"|"CircleExclamation"|"CircleH"|"CircleHalfStroke"|"CircleInfo"|"CircleLeft"|"CircleMinus"|"CircleNodes"|"CircleNotch"|"CirclePause"|"CirclePlay"|"CirclePlus"|"CircleQuestion"|"CircleRadiation"|"CircleRight"|"CircleStop"|"CircleUp"|"CircleUser"|"CircleXmark"|"City"|"Clapperboard"|"Clipboard"|"ClipboardCheck"|"ClipboardList"|"ClipboardQuestion"|"ClipboardUser"|"Clock"|"ClockRotateLeft"|"Clone"|"ClosedCaptioning"|"Cloud"|"CloudArrowDown"|"CloudArrowUp"|"CloudBolt"|"CloudMeatball"|"CloudMoon"|"CloudMoonRain"|"CloudRain"|"CloudShowersHeavy"|"CloudShowersWater"|"CloudSun"|"CloudSunRain"|"Clover"|"Code"|"CodeBranch"|"CodeCommit"|"CodeCompare"|"CodeFork"|"CodeMerge"|"CodePullRequest"|"Coins"|"ColonSign"|"Comment"|"CommentDollar"|"CommentDots"|"CommentMedical"|"CommentNodes"|"CommentSlash"|"CommentSms"|"Comments"|"CommentsDollar"|"CompactDisc"|"Compass"|"CompassDrafting"|"Compress"|"Computer"|"ComputerMouse"|"Cookie"|"CookieBite"|"Copy"|"Copyright"|"Couch"|"Cow"|"CreditCard"|"Crop"|"CropSimple"|"Cross"|"Crosshairs"|"Crow"|"Crown"|"Crutch"|"CruzeiroSign"|"Cube"|"Cubes"|"CubesStacked"|"D"|"Database"|"DeleteLeft"|"Democrat"|"Desktop"|"Dharmachakra"|"DiagramNext"|"DiagramPredecessor"|"DiagramProject"|"DiagramSuccessor"|"Diamond"|"DiamondTurnRight"|"Dice"|"DiceD20"|"DiceD6"|"DiceFive"|"DiceFour"|"DiceOne"|"DiceSix"|"DiceThree"|"DiceTwo"|"Disease"|"Display"|"Divide"|"Dna"|"Dog"|"DollarSign"|"Dolly"|"DongSign"|"DoorClosed"|"DoorOpen"|"Dove"|"DownLeftAndUpRightToCenter"|"DownLong"|"Download"|"Dragon"|"DrawPolygon"|"Droplet"|"DropletSlash"|"Drum"|"DrumSteelpan"|"DrumstickBite"|"Dumbbell"|"Dumpster"|"DumpsterFire"|"Dungeon"|"E"|"EarDeaf"|"EarListen"|"EarthAfrica"|"EarthAmericas"|"EarthAsia"|"EarthEurope"|"EarthOceania"|"Egg"|"Eject"|"Elevator"|"Ellipsis"|"EllipsisVertical"|"Envelope"|"EnvelopeCircleCheck"|"EnvelopeOpen"|"EnvelopeOpenText"|"EnvelopesBulk"|"Equals"|"Eraser"|"Ethernet"|"EuroSign"|"Exclamation"|"Expand"|"Explosion"|"Eye"|"EyeDropper"|"EyeLowVision"|"EyeSlash"|"F"|"FaceAngry"|"FaceDizzy"|"FaceFlushed"|"FaceFrown"|"FaceFrownOpen"|"FaceGrimace"|"FaceGrin"|"FaceGrinBeam"|"FaceGrinBeamSweat"|"FaceGrinHearts"|"FaceGrinSquint"|"FaceGrinSquintTears"|"FaceGrinStars"|"FaceGrinTears"|"FaceGrinTongue"|"FaceGrinTongueSquint"|"FaceGrinTongueWink"|"FaceGrinWide"|"FaceGrinWink"|"FaceKiss"|"FaceKissBeam"|"FaceKissWinkHeart"|"FaceLaugh"|"FaceLaughBeam"|"FaceLaughSquint"|"FaceLaughWink"|"FaceMeh"|"FaceMehBlank"|"FaceRollingEyes"|"FaceSadCry"|"FaceSadTear"|"FaceSmile"|"FaceSmileBeam"|"FaceSmileWink"|"FaceSurprise"|"FaceTired"|"Fan"|"Faucet"|"FaucetDrip"|"Fax"|"Feather"|"FeatherPointed"|"Ferry"|"File"|"FileArrowDown"|"FileArrowUp"|"FileAudio"|"FileCircleCheck"|"FileCircleExclamation"|"FileCircleMinus"|"FileCirclePlus"|"FileCircleQuestion"|"FileCircleXmark"|"FileCode"|"FileContract"|"FileCsv"|"FileExcel"|"FileExport"|"FileFragment"|"FileHalfDashed"|"FileImage"|"FileImport"|"FileInvoice"|"FileInvoiceDollar"|"FileLines"|"FileMedical"|"FilePdf"|"FilePen"|"FilePowerpoint"|"FilePrescription"|"FileShield"|"FileSignature"|"FileVideo"|"FileWaveform"|"FileWord"|"FileZipper"|"Fill"|"FillDrip"|"Film"|"Filter"|"FilterCircleDollar"|"FilterCircleXmark"|"Fingerprint"|"Fire"|"FireBurner"|"FireExtinguisher"|"FireFlameCurved"|"FireFlameSimple"|"Fish"|"FishFins"|"Flag"|"FlagCheckered"|"FlagUsa"|"Flask"|"FlaskVial"|"FloppyDisk"|"FlorinSign"|"Folder"|"FolderClosed"|"FolderMinus"|"FolderOpen"|"FolderPlus"|"FolderTree"|"Font"|"FontAwesome"|"Football"|"Forward"|"ForwardFast"|"ForwardStep"|"FrancSign"|"Frog"|"Futbol"|"G"|"Gamepad"|"GasPump"|"Gauge"|"GaugeHigh"|"GaugeSimple"|"GaugeSimpleHigh"|"Gavel"|"Gear"|"Gears"|"Gem"|"Genderless"|"Ghost"|"Gift"|"Gifts"|"GlassWater"|"GlassWaterDroplet"|"Glasses"|"Globe"|"GolfBallTee"|"Gopuram"|"GraduationCap"|"GreaterThan"|"GreaterThanEqual"|"Grip"|"GripLines"|"GripLinesVertical"|"GripVertical"|"GroupArrowsRotate"|"GuaraniSign"|"Guitar"|"Gun"|"H"|"Hammer"|"Hamsa"|"Hand"|"HandBackFist"|"HandDots"|"HandFist"|"HandHolding"|"HandHoldingDollar"|"HandHoldingDroplet"|"HandHoldingHand"|"HandHoldingHeart"|"HandHoldingMedical"|"HandLizard"|"HandMiddleFinger"|"HandPeace"|"HandPointDown"|"HandPointLeft"|"HandPointRight"|"HandPointUp"|"HandPointer"|"HandScissors"|"HandSparkles"|"HandSpock"|"Handcuffs"|"Hands"|"HandsAslInterpreting"|"HandsBound"|"HandsBubbles"|"HandsClapping"|"HandsHolding"|"HandsHoldingChild"|"HandsHoldingCircle"|"HandsPraying"|"Handshake"|"HandshakeAngle"|"HandshakeSimple"|"HandshakeSimpleSlash"|"HandshakeSlash"|"Hanukiah"|"HardDrive"|"Hashtag"|"HatCowboy"|"HatCowboySide"|"HatWizard"|"HeadSideCough"|"HeadSideCoughSlash"|"HeadSideMask"|"HeadSideVirus"|"Heading"|"Headphones"|"HeadphonesSimple"|"Headset"|"Heart"|"HeartCircleBolt"|"HeartCircleCheck"|"HeartCircleExclamation"|"HeartCircleMinus"|"HeartCirclePlus"|"HeartCircleXmark"|"HeartCrack"|"HeartPulse"|"Helicopter"|"HelicopterSymbol"|"HelmetSafety"|"HelmetUn"|"HexagonNodes"|"HexagonNodesBolt"|"Highlighter"|"HillAvalanche"|"HillRockslide"|"Hippo"|"HockeyPuck"|"HollyBerry"|"Horse"|"HorseHead"|"Hospital"|"HospitalUser"|"HotTubPerson"|"Hotdog"|"Hotel"|"Hourglass"|"HourglassEnd"|"HourglassHalf"|"HourglassStart"|"House"|"HouseChimney"|"HouseChimneyCrack"|"HouseChimneyMedical"|"HouseChimneyUser"|"HouseChimneyWindow"|"HouseCircleCheck"|"HouseCircleExclamation"|"HouseCircleXmark"|"HouseCrack"|"HouseFire"|"HouseFlag"|"HouseFloodWater"|"HouseFloodWaterCircleArrowRight"|"HouseLaptop"|"HouseLock"|"HouseMedical"|"HouseMedicalCircleCheck"|"HouseMedicalCircleExclamation"|"HouseMedicalCircleXmark"|"HouseMedicalFlag"|"HouseSignal"|"HouseTsunami"|"HouseUser"|"HryvniaSign"|"Hurricane"|"I"|"ICursor"|"IceCream"|"Icicles"|"Icons"|"IdBadge"|"IdCard"|"IdCardClip"|"Igloo"|"Image"|"ImagePortrait"|"Images"|"Inbox"|"Indent"|"IndianRupeeSign"|"Industry"|"Infinity"|"Info"|"Italic"|"J"|"Jar"|"JarWheat"|"Jedi"|"JetFighter"|"JetFighterUp"|"Joint"|"JugDetergent"|"K"|"Kaaba"|"Key"|"Keyboard"|"Khanda"|"KipSign"|"KitMedical"|"KitchenSet"|"KiwiBird"|"L"|"LandMineOn"|"Landmark"|"LandmarkDome"|"LandmarkFlag"|"Language"|"Laptop"|"LaptopCode"|"LaptopFile"|"LaptopMedical"|"LariSign"|"LayerGroup"|"Leaf"|"LeftLong"|"LeftRight"|"Lemon"|"LessThan"|"LessThanEqual"|"LifeRing"|"Lightbulb"|"LinesLeaning"|"Link"|"LinkSlash"|"LiraSign"|"List"|"ListCheck"|"ListOl"|"ListUl"|"LitecoinSign"|"LocationArrow"|"LocationCrosshairs"|"LocationDot"|"LocationPin"|"LocationPinLock"|"Lock"|"LockOpen"|"Locust"|"Lungs"|"LungsVirus"|"M"|"Magnet"|"MagnifyingGlass"|"MagnifyingGlassArrowRight"|"MagnifyingGlassChart"|"MagnifyingGlassDollar"|"MagnifyingGlassLocation"|"MagnifyingGlassMinus"|"MagnifyingGlassPlus"|"ManatSign"|"Map"|"MapLocation"|"MapLocationDot"|"MapPin"|"Marker"|"Mars"|"MarsAndVenus"|"MarsAndVenusBurst"|"MarsDouble"|"MarsStroke"|"MarsStrokeRight"|"MarsStrokeUp"|"MartiniGlass"|"MartiniGlassCitrus"|"MartiniGlassEmpty"|"Mask"|"MaskFace"|"MaskVentilator"|"MasksTheater"|"MattressPillow"|"Maximize"|"Medal"|"Memory"|"Menorah"|"Mercury"|"Message"|"Meteor"|"Microchip"|"Microphone"|"MicrophoneLines"|"MicrophoneLinesSlash"|"MicrophoneSlash"|"Microscope"|"MillSign"|"Minimize"|"Minus"|"Mitten"|"Mobile"|"MobileButton"|"MobileRetro"|"MobileScreen"|"MobileScreenButton"|"MoneyBill"|"MoneyBill1"|"MoneyBill1Wave"|"MoneyBillTransfer"|"MoneyBillTrendUp"|"MoneyBillWave"|"MoneyBillWheat"|"MoneyBills"|"MoneyCheck"|"MoneyCheckDollar"|"Monument"|"Moon"|"MortarPestle"|"Mosque"|"Mosquito"|"MosquitoNet"|"Motorcycle"|"Mound"|"Mountain"|"MountainCity"|"MountainSun"|"MugHot"|"MugSaucer"|"Music"|"N"|"NairaSign"|"NetworkWired"|"Neuter"|"Newspaper"|"NotEqual"|"Notdef"|"NoteSticky"|"NotesMedical"|"O"|"ObjectGroup"|"ObjectUngroup"|"OilCan"|"OilWell"|"Om"|"Otter"|"Outdent"|"P"|"Pager"|"PaintRoller"|"Paintbrush"|"Palette"|"Pallet"|"Panorama"|"PaperPlane"|"Paperclip"|"ParachuteBox"|"Paragraph"|"Passport"|"Paste"|"Pause"|"Paw"|"Peace"|"Pen"|"PenClip"|"PenFancy"|"PenNib"|"PenRuler"|"PenToSquare"|"Pencil"|"PeopleArrows"|"PeopleCarryBox"|"PeopleGroup"|"PeopleLine"|"PeoplePulling"|"PeopleRobbery"|"PeopleRoof"|"PepperHot"|"Percent"|"Person"|"PersonArrowDownToLine"|"PersonArrowUpFromLine"|"PersonBiking"|"PersonBooth"|"PersonBreastfeeding"|"PersonBurst"|"PersonCane"|"PersonChalkboard"|"PersonCircleCheck"|"PersonCircleExclamation"|"PersonCircleMinus"|"PersonCirclePlus"|"PersonCircleQuestion"|"PersonCircleXmark"|"PersonDigging"|"PersonDotsFromLine"|"PersonDress"|"PersonDressBurst"|"PersonDrowning"|"PersonFalling"|"PersonFallingBurst"|"PersonHalfDress"|"PersonHarassing"|"PersonHiking"|"PersonMilitaryPointing"|"PersonMilitaryRifle"|"PersonMilitaryToPerson"|"PersonPraying"|"PersonPregnant"|"PersonRays"|"PersonRifle"|"PersonRunning"|"PersonShelter"|"PersonSkating"|"PersonSkiing"|"PersonSkiingNordic"|"PersonSnowboarding"|"PersonSwimming"|"PersonThroughWindow"|"PersonWalking"|"PersonWalkingArrowLoopLeft"|"PersonWalkingArrowRight"|"PersonWalkingDashedLineArrowRight"|"PersonWalkingLuggage"|"PersonWalkingWithCane"|"PesetaSign"|"PesoSign"|"Phone"|"PhoneFlip"|"PhoneSlash"|"PhoneVolume"|"PhotoFilm"|"PiggyBank"|"Pills"|"PizzaSlice"|"PlaceOfWorship"|"Plane"|"PlaneArrival"|"PlaneCircleCheck"|"PlaneCircleExclamation"|"PlaneCircleXmark"|"PlaneDeparture"|"PlaneLock"|"PlaneSlash"|"PlaneUp"|"PlantWilt"|"PlateWheat"|"Play"|"Plug"|"PlugCircleBolt"|"PlugCircleCheck"|"PlugCircleExclamation"|"PlugCircleMinus"|"PlugCirclePlus"|"PlugCircleXmark"|"Plus"|"PlusMinus"|"Podcast"|"Poo"|"PooStorm"|"Poop"|"PowerOff"|"Prescription"|"PrescriptionBottle"|"PrescriptionBottleMedical"|"Print"|"PumpMedical"|"PumpSoap"|"PuzzlePiece"|"Q"|"Qrcode"|"Question"|"QuoteLeft"|"QuoteRight"|"R"|"Radiation"|"Radio"|"Rainbow"|"RankingStar"|"Receipt"|"RecordVinyl"|"RectangleAd"|"RectangleList"|"RectangleXmark"|"Recycle"|"Registered"|"Repeat"|"Reply"|"ReplyAll"|"Republican"|"Restroom"|"Retweet"|"Ribbon"|"RightFromBracket"|"RightLeft"|"RightLong"|"RightToBracket"|"Ring"|"Road"|"RoadBarrier"|"RoadBridge"|"RoadCircleCheck"|"RoadCircleExclamation"|"RoadCircleXmark"|"RoadLock"|"RoadSpikes"|"Robot"|"Rocket"|"Rotate"|"RotateLeft"|"RotateRight"|"Route"|"Rss"|"RubleSign"|"Rug"|"Ruler"|"RulerCombined"|"RulerHorizontal"|"RulerVertical"|"RupeeSign"|"RupiahSign"|"S"|"SackDollar"|"SackXmark"|"Sailboat"|"Satellite"|"SatelliteDish"|"ScaleBalanced"|"ScaleUnbalanced"|"ScaleUnbalancedFlip"|"School"|"SchoolCircleCheck"|"SchoolCircleExclamation"|"SchoolCircleXmark"|"SchoolFlag"|"SchoolLock"|"Scissors"|"Screwdriver"|"ScrewdriverWrench"|"Scroll"|"ScrollTorah"|"SdCard"|"Section"|"Seedling"|"Server"|"Shapes"|"Share"|"ShareFromSquare"|"ShareNodes"|"SheetPlastic"|"ShekelSign"|"Shield"|"ShieldCat"|"ShieldDog"|"ShieldHalved"|"ShieldHeart"|"ShieldVirus"|"Ship"|"Shirt"|"ShoePrints"|"Shop"|"ShopLock"|"ShopSlash"|"Shower"|"Shrimp"|"Shuffle"|"ShuttleSpace"|"SignHanging"|"Signal"|"Signature"|"SignsPost"|"SimCard"|"Sink"|"Sitemap"|"Skull"|"SkullCrossbones"|"Slash"|"Sleigh"|"Sliders"|"Smog"|"Smoking"|"Snowflake"|"Snowman"|"Snowplow"|"Soap"|"Socks"|"SolarPanel"|"Sort"|"SortDown"|"SortUp"|"Spa"|"SpaghettiMonsterFlying"|"SpellCheck"|"Spider"|"Spinner"|"Splotch"|"Spoon"|"SprayCan"|"SprayCanSparkles"|"Square"|"SquareArrowUpRight"|"SquareBinary"|"SquareCaretDown"|"SquareCaretLeft"|"SquareCaretRight"|"SquareCaretUp"|"SquareCheck"|"SquareEnvelope"|"SquareFull"|"SquareH"|"SquareMinus"|"SquareNfi"|"SquareParking"|"SquarePen"|"SquarePersonConfined"|"SquarePhone"|"SquarePhoneFlip"|"SquarePlus"|"SquarePollHorizontal"|"SquarePollVertical"|"SquareRootVariable"|"SquareRss"|"SquareShareNodes"|"SquareUpRight"|"SquareVirus"|"SquareXmark"|"StaffSnake"|"Stairs"|"Stamp"|"Stapler"|"Star"|"StarAndCrescent"|"StarHalf"|"StarHalfStroke"|"StarOfDavid"|"StarOfLife"|"SterlingSign"|"Stethoscope"|"Stop"|"Stopwatch"|"Stopwatch20"|"Store"|"StoreSlash"|"StreetView"|"Strikethrough"|"Stroopwafel"|"Subscript"|"Suitcase"|"SuitcaseMedical"|"SuitcaseRolling"|"Sun"|"SunPlantWilt"|"Superscript"|"Swatchbook"|"Synagogue"|"Syringe"|"T"|"Table"|"TableCells"|"TableCellsColumnLock"|"TableCellsLarge"|"TableCellsRowLock"|"TableCellsRowUnlock"|"TableColumns"|"TableList"|"TableTennisPaddleBall"|"Tablet"|"TabletButton"|"TabletScreenButton"|"Tablets"|"TachographDigital"|"Tag"|"Tags"|"Tape"|"Tarp"|"TarpDroplet"|"Taxi"|"Teeth"|"TeethOpen"|"TemperatureArrowDown"|"TemperatureArrowUp"|"TemperatureEmpty"|"TemperatureFull"|"TemperatureHalf"|"TemperatureHigh"|"TemperatureLow"|"TemperatureQuarter"|"TemperatureThreeQuarters"|"TengeSign"|"Tent"|"TentArrowDownToLine"|"TentArrowLeftRight"|"TentArrowTurnLeft"|"TentArrowsDown"|"Tents"|"Terminal"|"TextHeight"|"TextSlash"|"TextWidth"|"Thermometer"|"ThumbsDown"|"ThumbsUp"|"Thumbtack"|"ThumbtackSlash"|"Ticket"|"TicketSimple"|"Timeline"|"ToggleOff"|"ToggleOn"|"Toilet"|"ToiletPaper"|"ToiletPaperSlash"|"ToiletPortable"|"ToiletsPortable"|"Toolbox"|"Tooth"|"ToriiGate"|"Tornado"|"TowerBroadcast"|"TowerCell"|"TowerObservation"|"Tractor"|"Trademark"|"TrafficLight"|"Trailer"|"Train"|"TrainSubway"|"TrainTram"|"Transgender"|"Trash"|"TrashArrowUp"|"TrashCan"|"TrashCanArrowUp"|"Tree"|"TreeCity"|"TriangleExclamation"|"Trophy"|"Trowel"|"TrowelBricks"|"Truck"|"TruckArrowRight"|"TruckDroplet"|"TruckFast"|"TruckField"|"TruckFieldUn"|"TruckFront"|"TruckMedical"|"TruckMonster"|"TruckMoving"|"TruckPickup"|"TruckPlane"|"TruckRampBox"|"Tty"|"TurkishLiraSign"|"TurnDown"|"TurnUp"|"Tv"|"U"|"Umbrella"|"UmbrellaBeach"|"Underline"|"UniversalAccess"|"Unlock"|"UnlockKeyhole"|"UpDown"|"UpDownLeftRight"|"UpLong"|"UpRightAndDownLeftFromCenter"|"UpRightFromSquare"|"Upload"|"User"|"UserAstronaut"|"UserCheck"|"UserClock"|"UserDoctor"|"UserGear"|"UserGraduate"|"UserGroup"|"UserInjured"|"UserLarge"|"UserLargeSlash"|"UserLock"|"UserMinus"|"UserNinja"|"UserNurse"|"UserPen"|"UserPlus"|"UserSecret"|"UserShield"|"UserSlash"|"UserTag"|"UserTie"|"UserXmark"|"Users"|"UsersBetweenLines"|"UsersGear"|"UsersLine"|"UsersRays"|"UsersRectangle"|"UsersSlash"|"UsersViewfinder"|"Utensils"|"V"|"VanShuttle"|"Vault"|"VectorSquare"|"Venus"|"VenusDouble"|"VenusMars"|"Vest"|"VestPatches"|"Vial"|"VialCircleCheck"|"VialVirus"|"Vials"|"Video"|"VideoSlash"|"Vihara"|"Virus"|"VirusCovid"|"VirusCovidSlash"|"VirusSlash"|"Viruses"|"Voicemail"|"Volcano"|"Volleyball"|"VolumeHigh"|"VolumeLow"|"VolumeOff"|"VolumeXmark"|"VrCardboard"|"W"|"WalkieTalkie"|"Wallet"|"WandMagic"|"WandMagicSparkles"|"WandSparkles"|"Warehouse"|"Water"|"WaterLadder"|"WaveSquare"|"WebAwesome"|"WeightHanging"|"WeightScale"|"WheatAwn"|"WheatAwnCircleExclamation"|"Wheelchair"|"WheelchairMove"|"WhiskeyGlass"|"Wifi"|"Wind"|"WindowMaximize"|"WindowMinimize"|"WindowRestore"|"WineBottle"|"WineGlass"|"WineGlassEmpty"|"WonSign"|"Worm"|"Wrench"|"X"|"XRay"|"Xmark"|"XmarksLines"|"Y"|"YenSign"|"YinYang"|"Z"|"Search"|"Save"|"Settings"|"Cog"|"Home"|"Edit"|"Close"|"Cancel"|"Refresh"|"Warning"|"CheckCircle"|"TimesCircle"|"VolumeMute"|"Cut"|"Undo"|"Redo"|"StepForward"|"StepBackward"|"Pin"|"ZoomIn"|"ZoomOut" Icon shown (Font Awesome).
---@field iconSize number Icon size (px).
---@field normalColor number[] Fill colour at rest.
---@field hoverColor number[] Fill colour under the mouse.
---@field pressedColor number[] Fill colour while pressed.
---@field borderColor number[] Colour of the border.
---@field textColor number[] Colour of the text.
---@field align "Left"|"Center"|"Right" Horizontal text alignment.

---@alias UIButtonNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "text" # string - Button caption.
---| "fontSize" # number - Text size (px).
---| "icon" # "None"|"Digit0"|"Digit1"|"Digit2"|"Digit3"|"Digit4"|"Digit5"|"Digit6"|"Digit7"|"Digit8"|"Digit9"|"A"|"AddressBook"|"AddressCard"|"AlignCenter"|"AlignJustify"|"AlignLeft"|"AlignRight"|"Anchor"|"AnchorCircleCheck"|"AnchorCircleExclamation"|"AnchorCircleXmark"|"AnchorLock"|"AngleDown"|"AngleLeft"|"AngleRight"|"AngleUp"|"AnglesDown"|"AnglesLeft"|"AnglesRight"|"AnglesUp"|"Ankh"|"AppleWhole"|"Archway"|"ArrowDown"|"ArrowDown19"|"ArrowDown91"|"ArrowDownAZ"|"ArrowDownLong"|"ArrowDownShortWide"|"ArrowDownUpAcrossLine"|"ArrowDownUpLock"|"ArrowDownWideShort"|"ArrowDownZA"|"ArrowLeft"|"ArrowLeftLong"|"ArrowPointer"|"ArrowRight"|"ArrowRightArrowLeft"|"ArrowRightFromBracket"|"ArrowRightLong"|"ArrowRightToBracket"|"ArrowRightToCity"|"ArrowRotateLeft"|"ArrowRotateRight"|"ArrowTrendDown"|"ArrowTrendUp"|"ArrowTurnDown"|"ArrowTurnUp"|"ArrowUp"|"ArrowUp19"|"ArrowUp91"|"ArrowUpAZ"|"ArrowUpFromBracket"|"ArrowUpFromGroundWater"|"ArrowUpFromWaterPump"|"ArrowUpLong"|"ArrowUpRightDots"|"ArrowUpRightFromSquare"|"ArrowUpShortWide"|"ArrowUpWideShort"|"ArrowUpZA"|"ArrowsDownToLine"|"ArrowsDownToPeople"|"ArrowsLeftRight"|"ArrowsLeftRightToLine"|"ArrowsRotate"|"ArrowsSpin"|"ArrowsSplitUpAndLeft"|"ArrowsToCircle"|"ArrowsToDot"|"ArrowsToEye"|"ArrowsTurnRight"|"ArrowsTurnToDots"|"ArrowsUpDown"|"ArrowsUpDownLeftRight"|"ArrowsUpToLine"|"Asterisk"|"At"|"Atom"|"AudioDescription"|"AustralSign"|"Award"|"B"|"Baby"|"BabyCarriage"|"Backward"|"BackwardFast"|"BackwardStep"|"Bacon"|"Bacteria"|"Bacterium"|"BagShopping"|"Bahai"|"BahtSign"|"Ban"|"BanSmoking"|"Bandage"|"BangladeshiTakaSign"|"Barcode"|"Bars"|"BarsProgress"|"BarsStaggered"|"Baseball"|"BaseballBatBall"|"BasketShopping"|"Basketball"|"Bath"|"BatteryEmpty"|"BatteryFull"|"BatteryHalf"|"BatteryQuarter"|"BatteryThreeQuarters"|"Bed"|"BedPulse"|"BeerMugEmpty"|"Bell"|"BellConcierge"|"BellSlash"|"BezierCurve"|"Bicycle"|"Binoculars"|"Biohazard"|"BitcoinSign"|"Blender"|"BlenderPhone"|"Blog"|"Bold"|"Bolt"|"BoltLightning"|"Bomb"|"Bone"|"Bong"|"Book"|"BookAtlas"|"BookBible"|"BookBookmark"|"BookJournalWhills"|"BookMedical"|"BookOpen"|"BookOpenReader"|"BookQuran"|"BookSkull"|"BookTanakh"|"Bookmark"|"BorderAll"|"BorderNone"|"BorderTopLeft"|"BoreHole"|"BottleDroplet"|"BottleWater"|"BowlFood"|"BowlRice"|"BowlingBall"|"Box"|"BoxArchive"|"BoxOpen"|"BoxTissue"|"BoxesPacking"|"BoxesStacked"|"Braille"|"Brain"|"BrazilianRealSign"|"BreadSlice"|"Bridge"|"BridgeCircleCheck"|"BridgeCircleExclamation"|"BridgeCircleXmark"|"BridgeLock"|"BridgeWater"|"Briefcase"|"BriefcaseMedical"|"Broom"|"BroomBall"|"Brush"|"Bucket"|"Bug"|"BugSlash"|"Bugs"|"Building"|"BuildingCircleArrowRight"|"BuildingCircleCheck"|"BuildingCircleExclamation"|"BuildingCircleXmark"|"BuildingColumns"|"BuildingFlag"|"BuildingLock"|"BuildingNgo"|"BuildingShield"|"BuildingUn"|"BuildingUser"|"BuildingWheat"|"Bullhorn"|"Bullseye"|"Burger"|"Burst"|"Bus"|"BusSimple"|"BusinessTime"|"C"|"CableCar"|"CakeCandles"|"Calculator"|"Calendar"|"CalendarCheck"|"CalendarDay"|"CalendarDays"|"CalendarMinus"|"CalendarPlus"|"CalendarWeek"|"CalendarXmark"|"Camera"|"CameraRetro"|"CameraRotate"|"Campground"|"CandyCane"|"Cannabis"|"Capsules"|"Car"|"CarBattery"|"CarBurst"|"CarOn"|"CarRear"|"CarSide"|"CarTunnel"|"Caravan"|"CaretDown"|"CaretLeft"|"CaretRight"|"CaretUp"|"Carrot"|"CartArrowDown"|"CartFlatbed"|"CartFlatbedSuitcase"|"CartPlus"|"CartShopping"|"CashRegister"|"Cat"|"CediSign"|"CentSign"|"Certificate"|"Chair"|"Chalkboard"|"ChalkboardUser"|"ChampagneGlasses"|"ChargingStation"|"ChartArea"|"ChartBar"|"ChartColumn"|"ChartDiagram"|"ChartGantt"|"ChartLine"|"ChartPie"|"ChartSimple"|"Check"|"CheckDouble"|"CheckToSlot"|"Cheese"|"Chess"|"ChessBishop"|"ChessBoard"|"ChessKing"|"ChessKnight"|"ChessPawn"|"ChessQueen"|"ChessRook"|"ChevronDown"|"ChevronLeft"|"ChevronRight"|"ChevronUp"|"Child"|"ChildCombatant"|"ChildDress"|"ChildReaching"|"Children"|"Church"|"Circle"|"CircleArrowDown"|"CircleArrowLeft"|"CircleArrowRight"|"CircleArrowUp"|"CircleCheck"|"CircleChevronDown"|"CircleChevronLeft"|"CircleChevronRight"|"CircleChevronUp"|"CircleDollarToSlot"|"CircleDot"|"CircleDown"|"CircleExclamation"|"CircleH"|"CircleHalfStroke"|"CircleInfo"|"CircleLeft"|"CircleMinus"|"CircleNodes"|"CircleNotch"|"CirclePause"|"CirclePlay"|"CirclePlus"|"CircleQuestion"|"CircleRadiation"|"CircleRight"|"CircleStop"|"CircleUp"|"CircleUser"|"CircleXmark"|"City"|"Clapperboard"|"Clipboard"|"ClipboardCheck"|"ClipboardList"|"ClipboardQuestion"|"ClipboardUser"|"Clock"|"ClockRotateLeft"|"Clone"|"ClosedCaptioning"|"Cloud"|"CloudArrowDown"|"CloudArrowUp"|"CloudBolt"|"CloudMeatball"|"CloudMoon"|"CloudMoonRain"|"CloudRain"|"CloudShowersHeavy"|"CloudShowersWater"|"CloudSun"|"CloudSunRain"|"Clover"|"Code"|"CodeBranch"|"CodeCommit"|"CodeCompare"|"CodeFork"|"CodeMerge"|"CodePullRequest"|"Coins"|"ColonSign"|"Comment"|"CommentDollar"|"CommentDots"|"CommentMedical"|"CommentNodes"|"CommentSlash"|"CommentSms"|"Comments"|"CommentsDollar"|"CompactDisc"|"Compass"|"CompassDrafting"|"Compress"|"Computer"|"ComputerMouse"|"Cookie"|"CookieBite"|"Copy"|"Copyright"|"Couch"|"Cow"|"CreditCard"|"Crop"|"CropSimple"|"Cross"|"Crosshairs"|"Crow"|"Crown"|"Crutch"|"CruzeiroSign"|"Cube"|"Cubes"|"CubesStacked"|"D"|"Database"|"DeleteLeft"|"Democrat"|"Desktop"|"Dharmachakra"|"DiagramNext"|"DiagramPredecessor"|"DiagramProject"|"DiagramSuccessor"|"Diamond"|"DiamondTurnRight"|"Dice"|"DiceD20"|"DiceD6"|"DiceFive"|"DiceFour"|"DiceOne"|"DiceSix"|"DiceThree"|"DiceTwo"|"Disease"|"Display"|"Divide"|"Dna"|"Dog"|"DollarSign"|"Dolly"|"DongSign"|"DoorClosed"|"DoorOpen"|"Dove"|"DownLeftAndUpRightToCenter"|"DownLong"|"Download"|"Dragon"|"DrawPolygon"|"Droplet"|"DropletSlash"|"Drum"|"DrumSteelpan"|"DrumstickBite"|"Dumbbell"|"Dumpster"|"DumpsterFire"|"Dungeon"|"E"|"EarDeaf"|"EarListen"|"EarthAfrica"|"EarthAmericas"|"EarthAsia"|"EarthEurope"|"EarthOceania"|"Egg"|"Eject"|"Elevator"|"Ellipsis"|"EllipsisVertical"|"Envelope"|"EnvelopeCircleCheck"|"EnvelopeOpen"|"EnvelopeOpenText"|"EnvelopesBulk"|"Equals"|"Eraser"|"Ethernet"|"EuroSign"|"Exclamation"|"Expand"|"Explosion"|"Eye"|"EyeDropper"|"EyeLowVision"|"EyeSlash"|"F"|"FaceAngry"|"FaceDizzy"|"FaceFlushed"|"FaceFrown"|"FaceFrownOpen"|"FaceGrimace"|"FaceGrin"|"FaceGrinBeam"|"FaceGrinBeamSweat"|"FaceGrinHearts"|"FaceGrinSquint"|"FaceGrinSquintTears"|"FaceGrinStars"|"FaceGrinTears"|"FaceGrinTongue"|"FaceGrinTongueSquint"|"FaceGrinTongueWink"|"FaceGrinWide"|"FaceGrinWink"|"FaceKiss"|"FaceKissBeam"|"FaceKissWinkHeart"|"FaceLaugh"|"FaceLaughBeam"|"FaceLaughSquint"|"FaceLaughWink"|"FaceMeh"|"FaceMehBlank"|"FaceRollingEyes"|"FaceSadCry"|"FaceSadTear"|"FaceSmile"|"FaceSmileBeam"|"FaceSmileWink"|"FaceSurprise"|"FaceTired"|"Fan"|"Faucet"|"FaucetDrip"|"Fax"|"Feather"|"FeatherPointed"|"Ferry"|"File"|"FileArrowDown"|"FileArrowUp"|"FileAudio"|"FileCircleCheck"|"FileCircleExclamation"|"FileCircleMinus"|"FileCirclePlus"|"FileCircleQuestion"|"FileCircleXmark"|"FileCode"|"FileContract"|"FileCsv"|"FileExcel"|"FileExport"|"FileFragment"|"FileHalfDashed"|"FileImage"|"FileImport"|"FileInvoice"|"FileInvoiceDollar"|"FileLines"|"FileMedical"|"FilePdf"|"FilePen"|"FilePowerpoint"|"FilePrescription"|"FileShield"|"FileSignature"|"FileVideo"|"FileWaveform"|"FileWord"|"FileZipper"|"Fill"|"FillDrip"|"Film"|"Filter"|"FilterCircleDollar"|"FilterCircleXmark"|"Fingerprint"|"Fire"|"FireBurner"|"FireExtinguisher"|"FireFlameCurved"|"FireFlameSimple"|"Fish"|"FishFins"|"Flag"|"FlagCheckered"|"FlagUsa"|"Flask"|"FlaskVial"|"FloppyDisk"|"FlorinSign"|"Folder"|"FolderClosed"|"FolderMinus"|"FolderOpen"|"FolderPlus"|"FolderTree"|"Font"|"FontAwesome"|"Football"|"Forward"|"ForwardFast"|"ForwardStep"|"FrancSign"|"Frog"|"Futbol"|"G"|"Gamepad"|"GasPump"|"Gauge"|"GaugeHigh"|"GaugeSimple"|"GaugeSimpleHigh"|"Gavel"|"Gear"|"Gears"|"Gem"|"Genderless"|"Ghost"|"Gift"|"Gifts"|"GlassWater"|"GlassWaterDroplet"|"Glasses"|"Globe"|"GolfBallTee"|"Gopuram"|"GraduationCap"|"GreaterThan"|"GreaterThanEqual"|"Grip"|"GripLines"|"GripLinesVertical"|"GripVertical"|"GroupArrowsRotate"|"GuaraniSign"|"Guitar"|"Gun"|"H"|"Hammer"|"Hamsa"|"Hand"|"HandBackFist"|"HandDots"|"HandFist"|"HandHolding"|"HandHoldingDollar"|"HandHoldingDroplet"|"HandHoldingHand"|"HandHoldingHeart"|"HandHoldingMedical"|"HandLizard"|"HandMiddleFinger"|"HandPeace"|"HandPointDown"|"HandPointLeft"|"HandPointRight"|"HandPointUp"|"HandPointer"|"HandScissors"|"HandSparkles"|"HandSpock"|"Handcuffs"|"Hands"|"HandsAslInterpreting"|"HandsBound"|"HandsBubbles"|"HandsClapping"|"HandsHolding"|"HandsHoldingChild"|"HandsHoldingCircle"|"HandsPraying"|"Handshake"|"HandshakeAngle"|"HandshakeSimple"|"HandshakeSimpleSlash"|"HandshakeSlash"|"Hanukiah"|"HardDrive"|"Hashtag"|"HatCowboy"|"HatCowboySide"|"HatWizard"|"HeadSideCough"|"HeadSideCoughSlash"|"HeadSideMask"|"HeadSideVirus"|"Heading"|"Headphones"|"HeadphonesSimple"|"Headset"|"Heart"|"HeartCircleBolt"|"HeartCircleCheck"|"HeartCircleExclamation"|"HeartCircleMinus"|"HeartCirclePlus"|"HeartCircleXmark"|"HeartCrack"|"HeartPulse"|"Helicopter"|"HelicopterSymbol"|"HelmetSafety"|"HelmetUn"|"HexagonNodes"|"HexagonNodesBolt"|"Highlighter"|"HillAvalanche"|"HillRockslide"|"Hippo"|"HockeyPuck"|"HollyBerry"|"Horse"|"HorseHead"|"Hospital"|"HospitalUser"|"HotTubPerson"|"Hotdog"|"Hotel"|"Hourglass"|"HourglassEnd"|"HourglassHalf"|"HourglassStart"|"House"|"HouseChimney"|"HouseChimneyCrack"|"HouseChimneyMedical"|"HouseChimneyUser"|"HouseChimneyWindow"|"HouseCircleCheck"|"HouseCircleExclamation"|"HouseCircleXmark"|"HouseCrack"|"HouseFire"|"HouseFlag"|"HouseFloodWater"|"HouseFloodWaterCircleArrowRight"|"HouseLaptop"|"HouseLock"|"HouseMedical"|"HouseMedicalCircleCheck"|"HouseMedicalCircleExclamation"|"HouseMedicalCircleXmark"|"HouseMedicalFlag"|"HouseSignal"|"HouseTsunami"|"HouseUser"|"HryvniaSign"|"Hurricane"|"I"|"ICursor"|"IceCream"|"Icicles"|"Icons"|"IdBadge"|"IdCard"|"IdCardClip"|"Igloo"|"Image"|"ImagePortrait"|"Images"|"Inbox"|"Indent"|"IndianRupeeSign"|"Industry"|"Infinity"|"Info"|"Italic"|"J"|"Jar"|"JarWheat"|"Jedi"|"JetFighter"|"JetFighterUp"|"Joint"|"JugDetergent"|"K"|"Kaaba"|"Key"|"Keyboard"|"Khanda"|"KipSign"|"KitMedical"|"KitchenSet"|"KiwiBird"|"L"|"LandMineOn"|"Landmark"|"LandmarkDome"|"LandmarkFlag"|"Language"|"Laptop"|"LaptopCode"|"LaptopFile"|"LaptopMedical"|"LariSign"|"LayerGroup"|"Leaf"|"LeftLong"|"LeftRight"|"Lemon"|"LessThan"|"LessThanEqual"|"LifeRing"|"Lightbulb"|"LinesLeaning"|"Link"|"LinkSlash"|"LiraSign"|"List"|"ListCheck"|"ListOl"|"ListUl"|"LitecoinSign"|"LocationArrow"|"LocationCrosshairs"|"LocationDot"|"LocationPin"|"LocationPinLock"|"Lock"|"LockOpen"|"Locust"|"Lungs"|"LungsVirus"|"M"|"Magnet"|"MagnifyingGlass"|"MagnifyingGlassArrowRight"|"MagnifyingGlassChart"|"MagnifyingGlassDollar"|"MagnifyingGlassLocation"|"MagnifyingGlassMinus"|"MagnifyingGlassPlus"|"ManatSign"|"Map"|"MapLocation"|"MapLocationDot"|"MapPin"|"Marker"|"Mars"|"MarsAndVenus"|"MarsAndVenusBurst"|"MarsDouble"|"MarsStroke"|"MarsStrokeRight"|"MarsStrokeUp"|"MartiniGlass"|"MartiniGlassCitrus"|"MartiniGlassEmpty"|"Mask"|"MaskFace"|"MaskVentilator"|"MasksTheater"|"MattressPillow"|"Maximize"|"Medal"|"Memory"|"Menorah"|"Mercury"|"Message"|"Meteor"|"Microchip"|"Microphone"|"MicrophoneLines"|"MicrophoneLinesSlash"|"MicrophoneSlash"|"Microscope"|"MillSign"|"Minimize"|"Minus"|"Mitten"|"Mobile"|"MobileButton"|"MobileRetro"|"MobileScreen"|"MobileScreenButton"|"MoneyBill"|"MoneyBill1"|"MoneyBill1Wave"|"MoneyBillTransfer"|"MoneyBillTrendUp"|"MoneyBillWave"|"MoneyBillWheat"|"MoneyBills"|"MoneyCheck"|"MoneyCheckDollar"|"Monument"|"Moon"|"MortarPestle"|"Mosque"|"Mosquito"|"MosquitoNet"|"Motorcycle"|"Mound"|"Mountain"|"MountainCity"|"MountainSun"|"MugHot"|"MugSaucer"|"Music"|"N"|"NairaSign"|"NetworkWired"|"Neuter"|"Newspaper"|"NotEqual"|"Notdef"|"NoteSticky"|"NotesMedical"|"O"|"ObjectGroup"|"ObjectUngroup"|"OilCan"|"OilWell"|"Om"|"Otter"|"Outdent"|"P"|"Pager"|"PaintRoller"|"Paintbrush"|"Palette"|"Pallet"|"Panorama"|"PaperPlane"|"Paperclip"|"ParachuteBox"|"Paragraph"|"Passport"|"Paste"|"Pause"|"Paw"|"Peace"|"Pen"|"PenClip"|"PenFancy"|"PenNib"|"PenRuler"|"PenToSquare"|"Pencil"|"PeopleArrows"|"PeopleCarryBox"|"PeopleGroup"|"PeopleLine"|"PeoplePulling"|"PeopleRobbery"|"PeopleRoof"|"PepperHot"|"Percent"|"Person"|"PersonArrowDownToLine"|"PersonArrowUpFromLine"|"PersonBiking"|"PersonBooth"|"PersonBreastfeeding"|"PersonBurst"|"PersonCane"|"PersonChalkboard"|"PersonCircleCheck"|"PersonCircleExclamation"|"PersonCircleMinus"|"PersonCirclePlus"|"PersonCircleQuestion"|"PersonCircleXmark"|"PersonDigging"|"PersonDotsFromLine"|"PersonDress"|"PersonDressBurst"|"PersonDrowning"|"PersonFalling"|"PersonFallingBurst"|"PersonHalfDress"|"PersonHarassing"|"PersonHiking"|"PersonMilitaryPointing"|"PersonMilitaryRifle"|"PersonMilitaryToPerson"|"PersonPraying"|"PersonPregnant"|"PersonRays"|"PersonRifle"|"PersonRunning"|"PersonShelter"|"PersonSkating"|"PersonSkiing"|"PersonSkiingNordic"|"PersonSnowboarding"|"PersonSwimming"|"PersonThroughWindow"|"PersonWalking"|"PersonWalkingArrowLoopLeft"|"PersonWalkingArrowRight"|"PersonWalkingDashedLineArrowRight"|"PersonWalkingLuggage"|"PersonWalkingWithCane"|"PesetaSign"|"PesoSign"|"Phone"|"PhoneFlip"|"PhoneSlash"|"PhoneVolume"|"PhotoFilm"|"PiggyBank"|"Pills"|"PizzaSlice"|"PlaceOfWorship"|"Plane"|"PlaneArrival"|"PlaneCircleCheck"|"PlaneCircleExclamation"|"PlaneCircleXmark"|"PlaneDeparture"|"PlaneLock"|"PlaneSlash"|"PlaneUp"|"PlantWilt"|"PlateWheat"|"Play"|"Plug"|"PlugCircleBolt"|"PlugCircleCheck"|"PlugCircleExclamation"|"PlugCircleMinus"|"PlugCirclePlus"|"PlugCircleXmark"|"Plus"|"PlusMinus"|"Podcast"|"Poo"|"PooStorm"|"Poop"|"PowerOff"|"Prescription"|"PrescriptionBottle"|"PrescriptionBottleMedical"|"Print"|"PumpMedical"|"PumpSoap"|"PuzzlePiece"|"Q"|"Qrcode"|"Question"|"QuoteLeft"|"QuoteRight"|"R"|"Radiation"|"Radio"|"Rainbow"|"RankingStar"|"Receipt"|"RecordVinyl"|"RectangleAd"|"RectangleList"|"RectangleXmark"|"Recycle"|"Registered"|"Repeat"|"Reply"|"ReplyAll"|"Republican"|"Restroom"|"Retweet"|"Ribbon"|"RightFromBracket"|"RightLeft"|"RightLong"|"RightToBracket"|"Ring"|"Road"|"RoadBarrier"|"RoadBridge"|"RoadCircleCheck"|"RoadCircleExclamation"|"RoadCircleXmark"|"RoadLock"|"RoadSpikes"|"Robot"|"Rocket"|"Rotate"|"RotateLeft"|"RotateRight"|"Route"|"Rss"|"RubleSign"|"Rug"|"Ruler"|"RulerCombined"|"RulerHorizontal"|"RulerVertical"|"RupeeSign"|"RupiahSign"|"S"|"SackDollar"|"SackXmark"|"Sailboat"|"Satellite"|"SatelliteDish"|"ScaleBalanced"|"ScaleUnbalanced"|"ScaleUnbalancedFlip"|"School"|"SchoolCircleCheck"|"SchoolCircleExclamation"|"SchoolCircleXmark"|"SchoolFlag"|"SchoolLock"|"Scissors"|"Screwdriver"|"ScrewdriverWrench"|"Scroll"|"ScrollTorah"|"SdCard"|"Section"|"Seedling"|"Server"|"Shapes"|"Share"|"ShareFromSquare"|"ShareNodes"|"SheetPlastic"|"ShekelSign"|"Shield"|"ShieldCat"|"ShieldDog"|"ShieldHalved"|"ShieldHeart"|"ShieldVirus"|"Ship"|"Shirt"|"ShoePrints"|"Shop"|"ShopLock"|"ShopSlash"|"Shower"|"Shrimp"|"Shuffle"|"ShuttleSpace"|"SignHanging"|"Signal"|"Signature"|"SignsPost"|"SimCard"|"Sink"|"Sitemap"|"Skull"|"SkullCrossbones"|"Slash"|"Sleigh"|"Sliders"|"Smog"|"Smoking"|"Snowflake"|"Snowman"|"Snowplow"|"Soap"|"Socks"|"SolarPanel"|"Sort"|"SortDown"|"SortUp"|"Spa"|"SpaghettiMonsterFlying"|"SpellCheck"|"Spider"|"Spinner"|"Splotch"|"Spoon"|"SprayCan"|"SprayCanSparkles"|"Square"|"SquareArrowUpRight"|"SquareBinary"|"SquareCaretDown"|"SquareCaretLeft"|"SquareCaretRight"|"SquareCaretUp"|"SquareCheck"|"SquareEnvelope"|"SquareFull"|"SquareH"|"SquareMinus"|"SquareNfi"|"SquareParking"|"SquarePen"|"SquarePersonConfined"|"SquarePhone"|"SquarePhoneFlip"|"SquarePlus"|"SquarePollHorizontal"|"SquarePollVertical"|"SquareRootVariable"|"SquareRss"|"SquareShareNodes"|"SquareUpRight"|"SquareVirus"|"SquareXmark"|"StaffSnake"|"Stairs"|"Stamp"|"Stapler"|"Star"|"StarAndCrescent"|"StarHalf"|"StarHalfStroke"|"StarOfDavid"|"StarOfLife"|"SterlingSign"|"Stethoscope"|"Stop"|"Stopwatch"|"Stopwatch20"|"Store"|"StoreSlash"|"StreetView"|"Strikethrough"|"Stroopwafel"|"Subscript"|"Suitcase"|"SuitcaseMedical"|"SuitcaseRolling"|"Sun"|"SunPlantWilt"|"Superscript"|"Swatchbook"|"Synagogue"|"Syringe"|"T"|"Table"|"TableCells"|"TableCellsColumnLock"|"TableCellsLarge"|"TableCellsRowLock"|"TableCellsRowUnlock"|"TableColumns"|"TableList"|"TableTennisPaddleBall"|"Tablet"|"TabletButton"|"TabletScreenButton"|"Tablets"|"TachographDigital"|"Tag"|"Tags"|"Tape"|"Tarp"|"TarpDroplet"|"Taxi"|"Teeth"|"TeethOpen"|"TemperatureArrowDown"|"TemperatureArrowUp"|"TemperatureEmpty"|"TemperatureFull"|"TemperatureHalf"|"TemperatureHigh"|"TemperatureLow"|"TemperatureQuarter"|"TemperatureThreeQuarters"|"TengeSign"|"Tent"|"TentArrowDownToLine"|"TentArrowLeftRight"|"TentArrowTurnLeft"|"TentArrowsDown"|"Tents"|"Terminal"|"TextHeight"|"TextSlash"|"TextWidth"|"Thermometer"|"ThumbsDown"|"ThumbsUp"|"Thumbtack"|"ThumbtackSlash"|"Ticket"|"TicketSimple"|"Timeline"|"ToggleOff"|"ToggleOn"|"Toilet"|"ToiletPaper"|"ToiletPaperSlash"|"ToiletPortable"|"ToiletsPortable"|"Toolbox"|"Tooth"|"ToriiGate"|"Tornado"|"TowerBroadcast"|"TowerCell"|"TowerObservation"|"Tractor"|"Trademark"|"TrafficLight"|"Trailer"|"Train"|"TrainSubway"|"TrainTram"|"Transgender"|"Trash"|"TrashArrowUp"|"TrashCan"|"TrashCanArrowUp"|"Tree"|"TreeCity"|"TriangleExclamation"|"Trophy"|"Trowel"|"TrowelBricks"|"Truck"|"TruckArrowRight"|"TruckDroplet"|"TruckFast"|"TruckField"|"TruckFieldUn"|"TruckFront"|"TruckMedical"|"TruckMonster"|"TruckMoving"|"TruckPickup"|"TruckPlane"|"TruckRampBox"|"Tty"|"TurkishLiraSign"|"TurnDown"|"TurnUp"|"Tv"|"U"|"Umbrella"|"UmbrellaBeach"|"Underline"|"UniversalAccess"|"Unlock"|"UnlockKeyhole"|"UpDown"|"UpDownLeftRight"|"UpLong"|"UpRightAndDownLeftFromCenter"|"UpRightFromSquare"|"Upload"|"User"|"UserAstronaut"|"UserCheck"|"UserClock"|"UserDoctor"|"UserGear"|"UserGraduate"|"UserGroup"|"UserInjured"|"UserLarge"|"UserLargeSlash"|"UserLock"|"UserMinus"|"UserNinja"|"UserNurse"|"UserPen"|"UserPlus"|"UserSecret"|"UserShield"|"UserSlash"|"UserTag"|"UserTie"|"UserXmark"|"Users"|"UsersBetweenLines"|"UsersGear"|"UsersLine"|"UsersRays"|"UsersRectangle"|"UsersSlash"|"UsersViewfinder"|"Utensils"|"V"|"VanShuttle"|"Vault"|"VectorSquare"|"Venus"|"VenusDouble"|"VenusMars"|"Vest"|"VestPatches"|"Vial"|"VialCircleCheck"|"VialVirus"|"Vials"|"Video"|"VideoSlash"|"Vihara"|"Virus"|"VirusCovid"|"VirusCovidSlash"|"VirusSlash"|"Viruses"|"Voicemail"|"Volcano"|"Volleyball"|"VolumeHigh"|"VolumeLow"|"VolumeOff"|"VolumeXmark"|"VrCardboard"|"W"|"WalkieTalkie"|"Wallet"|"WandMagic"|"WandMagicSparkles"|"WandSparkles"|"Warehouse"|"Water"|"WaterLadder"|"WaveSquare"|"WebAwesome"|"WeightHanging"|"WeightScale"|"WheatAwn"|"WheatAwnCircleExclamation"|"Wheelchair"|"WheelchairMove"|"WhiskeyGlass"|"Wifi"|"Wind"|"WindowMaximize"|"WindowMinimize"|"WindowRestore"|"WineBottle"|"WineGlass"|"WineGlassEmpty"|"WonSign"|"Worm"|"Wrench"|"X"|"XRay"|"Xmark"|"XmarksLines"|"Y"|"YenSign"|"YinYang"|"Z"|"Search"|"Save"|"Settings"|"Cog"|"Home"|"Edit"|"Close"|"Cancel"|"Refresh"|"Warning"|"CheckCircle"|"TimesCircle"|"VolumeMute"|"Cut"|"Undo"|"Redo"|"StepForward"|"StepBackward"|"Pin"|"ZoomIn"|"ZoomOut" - Icon shown (Font Awesome).
---| "iconSize" # number - Icon size (px).
---| "normalColor" # number[] - Fill colour at rest.
---| "hoverColor" # number[] - Fill colour under the mouse.
---| "pressedColor" # number[] - Fill colour while pressed.
---| "borderColor" # number[] - Colour of the border.
---| "textColor" # number[] - Colour of the text.
---| "align" # "Left"|"Center"|"Right" - Horizontal text alignment.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UIButtonNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UIButtonNode, path: "position"): Vec2
---@overload fun(self: UIButtonNode, path: "scale"): Vec2
---@overload fun(self: UIButtonNode, path: "rotation"): number
---@overload fun(self: UIButtonNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIButtonNode, path: "zIndex"): integer
---@overload fun(self: UIButtonNode, path: "ySort"): boolean
---@overload fun(self: UIButtonNode, path: "ySortOffset"): number
---@overload fun(self: UIButtonNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIButtonNode, path: "paused"): boolean
---@overload fun(self: UIButtonNode, path: "enabled"): boolean
---@overload fun(self: UIButtonNode, path: "size"): Vec2
---@overload fun(self: UIButtonNode, path: "keyboardFocus"): boolean
---@overload fun(self: UIButtonNode, path: "text"): string
---@overload fun(self: UIButtonNode, path: "fontSize"): number
---@overload fun(self: UIButtonNode, path: "icon"): "None"|"Digit0"|"Digit1"|"Digit2"|"Digit3"|"Digit4"|"Digit5"|"Digit6"|"Digit7"|"Digit8"|"Digit9"|"A"|"AddressBook"|"AddressCard"|"AlignCenter"|"AlignJustify"|"AlignLeft"|"AlignRight"|"Anchor"|"AnchorCircleCheck"|"AnchorCircleExclamation"|"AnchorCircleXmark"|"AnchorLock"|"AngleDown"|"AngleLeft"|"AngleRight"|"AngleUp"|"AnglesDown"|"AnglesLeft"|"AnglesRight"|"AnglesUp"|"Ankh"|"AppleWhole"|"Archway"|"ArrowDown"|"ArrowDown19"|"ArrowDown91"|"ArrowDownAZ"|"ArrowDownLong"|"ArrowDownShortWide"|"ArrowDownUpAcrossLine"|"ArrowDownUpLock"|"ArrowDownWideShort"|"ArrowDownZA"|"ArrowLeft"|"ArrowLeftLong"|"ArrowPointer"|"ArrowRight"|"ArrowRightArrowLeft"|"ArrowRightFromBracket"|"ArrowRightLong"|"ArrowRightToBracket"|"ArrowRightToCity"|"ArrowRotateLeft"|"ArrowRotateRight"|"ArrowTrendDown"|"ArrowTrendUp"|"ArrowTurnDown"|"ArrowTurnUp"|"ArrowUp"|"ArrowUp19"|"ArrowUp91"|"ArrowUpAZ"|"ArrowUpFromBracket"|"ArrowUpFromGroundWater"|"ArrowUpFromWaterPump"|"ArrowUpLong"|"ArrowUpRightDots"|"ArrowUpRightFromSquare"|"ArrowUpShortWide"|"ArrowUpWideShort"|"ArrowUpZA"|"ArrowsDownToLine"|"ArrowsDownToPeople"|"ArrowsLeftRight"|"ArrowsLeftRightToLine"|"ArrowsRotate"|"ArrowsSpin"|"ArrowsSplitUpAndLeft"|"ArrowsToCircle"|"ArrowsToDot"|"ArrowsToEye"|"ArrowsTurnRight"|"ArrowsTurnToDots"|"ArrowsUpDown"|"ArrowsUpDownLeftRight"|"ArrowsUpToLine"|"Asterisk"|"At"|"Atom"|"AudioDescription"|"AustralSign"|"Award"|"B"|"Baby"|"BabyCarriage"|"Backward"|"BackwardFast"|"BackwardStep"|"Bacon"|"Bacteria"|"Bacterium"|"BagShopping"|"Bahai"|"BahtSign"|"Ban"|"BanSmoking"|"Bandage"|"BangladeshiTakaSign"|"Barcode"|"Bars"|"BarsProgress"|"BarsStaggered"|"Baseball"|"BaseballBatBall"|"BasketShopping"|"Basketball"|"Bath"|"BatteryEmpty"|"BatteryFull"|"BatteryHalf"|"BatteryQuarter"|"BatteryThreeQuarters"|"Bed"|"BedPulse"|"BeerMugEmpty"|"Bell"|"BellConcierge"|"BellSlash"|"BezierCurve"|"Bicycle"|"Binoculars"|"Biohazard"|"BitcoinSign"|"Blender"|"BlenderPhone"|"Blog"|"Bold"|"Bolt"|"BoltLightning"|"Bomb"|"Bone"|"Bong"|"Book"|"BookAtlas"|"BookBible"|"BookBookmark"|"BookJournalWhills"|"BookMedical"|"BookOpen"|"BookOpenReader"|"BookQuran"|"BookSkull"|"BookTanakh"|"Bookmark"|"BorderAll"|"BorderNone"|"BorderTopLeft"|"BoreHole"|"BottleDroplet"|"BottleWater"|"BowlFood"|"BowlRice"|"BowlingBall"|"Box"|"BoxArchive"|"BoxOpen"|"BoxTissue"|"BoxesPacking"|"BoxesStacked"|"Braille"|"Brain"|"BrazilianRealSign"|"BreadSlice"|"Bridge"|"BridgeCircleCheck"|"BridgeCircleExclamation"|"BridgeCircleXmark"|"BridgeLock"|"BridgeWater"|"Briefcase"|"BriefcaseMedical"|"Broom"|"BroomBall"|"Brush"|"Bucket"|"Bug"|"BugSlash"|"Bugs"|"Building"|"BuildingCircleArrowRight"|"BuildingCircleCheck"|"BuildingCircleExclamation"|"BuildingCircleXmark"|"BuildingColumns"|"BuildingFlag"|"BuildingLock"|"BuildingNgo"|"BuildingShield"|"BuildingUn"|"BuildingUser"|"BuildingWheat"|"Bullhorn"|"Bullseye"|"Burger"|"Burst"|"Bus"|"BusSimple"|"BusinessTime"|"C"|"CableCar"|"CakeCandles"|"Calculator"|"Calendar"|"CalendarCheck"|"CalendarDay"|"CalendarDays"|"CalendarMinus"|"CalendarPlus"|"CalendarWeek"|"CalendarXmark"|"Camera"|"CameraRetro"|"CameraRotate"|"Campground"|"CandyCane"|"Cannabis"|"Capsules"|"Car"|"CarBattery"|"CarBurst"|"CarOn"|"CarRear"|"CarSide"|"CarTunnel"|"Caravan"|"CaretDown"|"CaretLeft"|"CaretRight"|"CaretUp"|"Carrot"|"CartArrowDown"|"CartFlatbed"|"CartFlatbedSuitcase"|"CartPlus"|"CartShopping"|"CashRegister"|"Cat"|"CediSign"|"CentSign"|"Certificate"|"Chair"|"Chalkboard"|"ChalkboardUser"|"ChampagneGlasses"|"ChargingStation"|"ChartArea"|"ChartBar"|"ChartColumn"|"ChartDiagram"|"ChartGantt"|"ChartLine"|"ChartPie"|"ChartSimple"|"Check"|"CheckDouble"|"CheckToSlot"|"Cheese"|"Chess"|"ChessBishop"|"ChessBoard"|"ChessKing"|"ChessKnight"|"ChessPawn"|"ChessQueen"|"ChessRook"|"ChevronDown"|"ChevronLeft"|"ChevronRight"|"ChevronUp"|"Child"|"ChildCombatant"|"ChildDress"|"ChildReaching"|"Children"|"Church"|"Circle"|"CircleArrowDown"|"CircleArrowLeft"|"CircleArrowRight"|"CircleArrowUp"|"CircleCheck"|"CircleChevronDown"|"CircleChevronLeft"|"CircleChevronRight"|"CircleChevronUp"|"CircleDollarToSlot"|"CircleDot"|"CircleDown"|"CircleExclamation"|"CircleH"|"CircleHalfStroke"|"CircleInfo"|"CircleLeft"|"CircleMinus"|"CircleNodes"|"CircleNotch"|"CirclePause"|"CirclePlay"|"CirclePlus"|"CircleQuestion"|"CircleRadiation"|"CircleRight"|"CircleStop"|"CircleUp"|"CircleUser"|"CircleXmark"|"City"|"Clapperboard"|"Clipboard"|"ClipboardCheck"|"ClipboardList"|"ClipboardQuestion"|"ClipboardUser"|"Clock"|"ClockRotateLeft"|"Clone"|"ClosedCaptioning"|"Cloud"|"CloudArrowDown"|"CloudArrowUp"|"CloudBolt"|"CloudMeatball"|"CloudMoon"|"CloudMoonRain"|"CloudRain"|"CloudShowersHeavy"|"CloudShowersWater"|"CloudSun"|"CloudSunRain"|"Clover"|"Code"|"CodeBranch"|"CodeCommit"|"CodeCompare"|"CodeFork"|"CodeMerge"|"CodePullRequest"|"Coins"|"ColonSign"|"Comment"|"CommentDollar"|"CommentDots"|"CommentMedical"|"CommentNodes"|"CommentSlash"|"CommentSms"|"Comments"|"CommentsDollar"|"CompactDisc"|"Compass"|"CompassDrafting"|"Compress"|"Computer"|"ComputerMouse"|"Cookie"|"CookieBite"|"Copy"|"Copyright"|"Couch"|"Cow"|"CreditCard"|"Crop"|"CropSimple"|"Cross"|"Crosshairs"|"Crow"|"Crown"|"Crutch"|"CruzeiroSign"|"Cube"|"Cubes"|"CubesStacked"|"D"|"Database"|"DeleteLeft"|"Democrat"|"Desktop"|"Dharmachakra"|"DiagramNext"|"DiagramPredecessor"|"DiagramProject"|"DiagramSuccessor"|"Diamond"|"DiamondTurnRight"|"Dice"|"DiceD20"|"DiceD6"|"DiceFive"|"DiceFour"|"DiceOne"|"DiceSix"|"DiceThree"|"DiceTwo"|"Disease"|"Display"|"Divide"|"Dna"|"Dog"|"DollarSign"|"Dolly"|"DongSign"|"DoorClosed"|"DoorOpen"|"Dove"|"DownLeftAndUpRightToCenter"|"DownLong"|"Download"|"Dragon"|"DrawPolygon"|"Droplet"|"DropletSlash"|"Drum"|"DrumSteelpan"|"DrumstickBite"|"Dumbbell"|"Dumpster"|"DumpsterFire"|"Dungeon"|"E"|"EarDeaf"|"EarListen"|"EarthAfrica"|"EarthAmericas"|"EarthAsia"|"EarthEurope"|"EarthOceania"|"Egg"|"Eject"|"Elevator"|"Ellipsis"|"EllipsisVertical"|"Envelope"|"EnvelopeCircleCheck"|"EnvelopeOpen"|"EnvelopeOpenText"|"EnvelopesBulk"|"Equals"|"Eraser"|"Ethernet"|"EuroSign"|"Exclamation"|"Expand"|"Explosion"|"Eye"|"EyeDropper"|"EyeLowVision"|"EyeSlash"|"F"|"FaceAngry"|"FaceDizzy"|"FaceFlushed"|"FaceFrown"|"FaceFrownOpen"|"FaceGrimace"|"FaceGrin"|"FaceGrinBeam"|"FaceGrinBeamSweat"|"FaceGrinHearts"|"FaceGrinSquint"|"FaceGrinSquintTears"|"FaceGrinStars"|"FaceGrinTears"|"FaceGrinTongue"|"FaceGrinTongueSquint"|"FaceGrinTongueWink"|"FaceGrinWide"|"FaceGrinWink"|"FaceKiss"|"FaceKissBeam"|"FaceKissWinkHeart"|"FaceLaugh"|"FaceLaughBeam"|"FaceLaughSquint"|"FaceLaughWink"|"FaceMeh"|"FaceMehBlank"|"FaceRollingEyes"|"FaceSadCry"|"FaceSadTear"|"FaceSmile"|"FaceSmileBeam"|"FaceSmileWink"|"FaceSurprise"|"FaceTired"|"Fan"|"Faucet"|"FaucetDrip"|"Fax"|"Feather"|"FeatherPointed"|"Ferry"|"File"|"FileArrowDown"|"FileArrowUp"|"FileAudio"|"FileCircleCheck"|"FileCircleExclamation"|"FileCircleMinus"|"FileCirclePlus"|"FileCircleQuestion"|"FileCircleXmark"|"FileCode"|"FileContract"|"FileCsv"|"FileExcel"|"FileExport"|"FileFragment"|"FileHalfDashed"|"FileImage"|"FileImport"|"FileInvoice"|"FileInvoiceDollar"|"FileLines"|"FileMedical"|"FilePdf"|"FilePen"|"FilePowerpoint"|"FilePrescription"|"FileShield"|"FileSignature"|"FileVideo"|"FileWaveform"|"FileWord"|"FileZipper"|"Fill"|"FillDrip"|"Film"|"Filter"|"FilterCircleDollar"|"FilterCircleXmark"|"Fingerprint"|"Fire"|"FireBurner"|"FireExtinguisher"|"FireFlameCurved"|"FireFlameSimple"|"Fish"|"FishFins"|"Flag"|"FlagCheckered"|"FlagUsa"|"Flask"|"FlaskVial"|"FloppyDisk"|"FlorinSign"|"Folder"|"FolderClosed"|"FolderMinus"|"FolderOpen"|"FolderPlus"|"FolderTree"|"Font"|"FontAwesome"|"Football"|"Forward"|"ForwardFast"|"ForwardStep"|"FrancSign"|"Frog"|"Futbol"|"G"|"Gamepad"|"GasPump"|"Gauge"|"GaugeHigh"|"GaugeSimple"|"GaugeSimpleHigh"|"Gavel"|"Gear"|"Gears"|"Gem"|"Genderless"|"Ghost"|"Gift"|"Gifts"|"GlassWater"|"GlassWaterDroplet"|"Glasses"|"Globe"|"GolfBallTee"|"Gopuram"|"GraduationCap"|"GreaterThan"|"GreaterThanEqual"|"Grip"|"GripLines"|"GripLinesVertical"|"GripVertical"|"GroupArrowsRotate"|"GuaraniSign"|"Guitar"|"Gun"|"H"|"Hammer"|"Hamsa"|"Hand"|"HandBackFist"|"HandDots"|"HandFist"|"HandHolding"|"HandHoldingDollar"|"HandHoldingDroplet"|"HandHoldingHand"|"HandHoldingHeart"|"HandHoldingMedical"|"HandLizard"|"HandMiddleFinger"|"HandPeace"|"HandPointDown"|"HandPointLeft"|"HandPointRight"|"HandPointUp"|"HandPointer"|"HandScissors"|"HandSparkles"|"HandSpock"|"Handcuffs"|"Hands"|"HandsAslInterpreting"|"HandsBound"|"HandsBubbles"|"HandsClapping"|"HandsHolding"|"HandsHoldingChild"|"HandsHoldingCircle"|"HandsPraying"|"Handshake"|"HandshakeAngle"|"HandshakeSimple"|"HandshakeSimpleSlash"|"HandshakeSlash"|"Hanukiah"|"HardDrive"|"Hashtag"|"HatCowboy"|"HatCowboySide"|"HatWizard"|"HeadSideCough"|"HeadSideCoughSlash"|"HeadSideMask"|"HeadSideVirus"|"Heading"|"Headphones"|"HeadphonesSimple"|"Headset"|"Heart"|"HeartCircleBolt"|"HeartCircleCheck"|"HeartCircleExclamation"|"HeartCircleMinus"|"HeartCirclePlus"|"HeartCircleXmark"|"HeartCrack"|"HeartPulse"|"Helicopter"|"HelicopterSymbol"|"HelmetSafety"|"HelmetUn"|"HexagonNodes"|"HexagonNodesBolt"|"Highlighter"|"HillAvalanche"|"HillRockslide"|"Hippo"|"HockeyPuck"|"HollyBerry"|"Horse"|"HorseHead"|"Hospital"|"HospitalUser"|"HotTubPerson"|"Hotdog"|"Hotel"|"Hourglass"|"HourglassEnd"|"HourglassHalf"|"HourglassStart"|"House"|"HouseChimney"|"HouseChimneyCrack"|"HouseChimneyMedical"|"HouseChimneyUser"|"HouseChimneyWindow"|"HouseCircleCheck"|"HouseCircleExclamation"|"HouseCircleXmark"|"HouseCrack"|"HouseFire"|"HouseFlag"|"HouseFloodWater"|"HouseFloodWaterCircleArrowRight"|"HouseLaptop"|"HouseLock"|"HouseMedical"|"HouseMedicalCircleCheck"|"HouseMedicalCircleExclamation"|"HouseMedicalCircleXmark"|"HouseMedicalFlag"|"HouseSignal"|"HouseTsunami"|"HouseUser"|"HryvniaSign"|"Hurricane"|"I"|"ICursor"|"IceCream"|"Icicles"|"Icons"|"IdBadge"|"IdCard"|"IdCardClip"|"Igloo"|"Image"|"ImagePortrait"|"Images"|"Inbox"|"Indent"|"IndianRupeeSign"|"Industry"|"Infinity"|"Info"|"Italic"|"J"|"Jar"|"JarWheat"|"Jedi"|"JetFighter"|"JetFighterUp"|"Joint"|"JugDetergent"|"K"|"Kaaba"|"Key"|"Keyboard"|"Khanda"|"KipSign"|"KitMedical"|"KitchenSet"|"KiwiBird"|"L"|"LandMineOn"|"Landmark"|"LandmarkDome"|"LandmarkFlag"|"Language"|"Laptop"|"LaptopCode"|"LaptopFile"|"LaptopMedical"|"LariSign"|"LayerGroup"|"Leaf"|"LeftLong"|"LeftRight"|"Lemon"|"LessThan"|"LessThanEqual"|"LifeRing"|"Lightbulb"|"LinesLeaning"|"Link"|"LinkSlash"|"LiraSign"|"List"|"ListCheck"|"ListOl"|"ListUl"|"LitecoinSign"|"LocationArrow"|"LocationCrosshairs"|"LocationDot"|"LocationPin"|"LocationPinLock"|"Lock"|"LockOpen"|"Locust"|"Lungs"|"LungsVirus"|"M"|"Magnet"|"MagnifyingGlass"|"MagnifyingGlassArrowRight"|"MagnifyingGlassChart"|"MagnifyingGlassDollar"|"MagnifyingGlassLocation"|"MagnifyingGlassMinus"|"MagnifyingGlassPlus"|"ManatSign"|"Map"|"MapLocation"|"MapLocationDot"|"MapPin"|"Marker"|"Mars"|"MarsAndVenus"|"MarsAndVenusBurst"|"MarsDouble"|"MarsStroke"|"MarsStrokeRight"|"MarsStrokeUp"|"MartiniGlass"|"MartiniGlassCitrus"|"MartiniGlassEmpty"|"Mask"|"MaskFace"|"MaskVentilator"|"MasksTheater"|"MattressPillow"|"Maximize"|"Medal"|"Memory"|"Menorah"|"Mercury"|"Message"|"Meteor"|"Microchip"|"Microphone"|"MicrophoneLines"|"MicrophoneLinesSlash"|"MicrophoneSlash"|"Microscope"|"MillSign"|"Minimize"|"Minus"|"Mitten"|"Mobile"|"MobileButton"|"MobileRetro"|"MobileScreen"|"MobileScreenButton"|"MoneyBill"|"MoneyBill1"|"MoneyBill1Wave"|"MoneyBillTransfer"|"MoneyBillTrendUp"|"MoneyBillWave"|"MoneyBillWheat"|"MoneyBills"|"MoneyCheck"|"MoneyCheckDollar"|"Monument"|"Moon"|"MortarPestle"|"Mosque"|"Mosquito"|"MosquitoNet"|"Motorcycle"|"Mound"|"Mountain"|"MountainCity"|"MountainSun"|"MugHot"|"MugSaucer"|"Music"|"N"|"NairaSign"|"NetworkWired"|"Neuter"|"Newspaper"|"NotEqual"|"Notdef"|"NoteSticky"|"NotesMedical"|"O"|"ObjectGroup"|"ObjectUngroup"|"OilCan"|"OilWell"|"Om"|"Otter"|"Outdent"|"P"|"Pager"|"PaintRoller"|"Paintbrush"|"Palette"|"Pallet"|"Panorama"|"PaperPlane"|"Paperclip"|"ParachuteBox"|"Paragraph"|"Passport"|"Paste"|"Pause"|"Paw"|"Peace"|"Pen"|"PenClip"|"PenFancy"|"PenNib"|"PenRuler"|"PenToSquare"|"Pencil"|"PeopleArrows"|"PeopleCarryBox"|"PeopleGroup"|"PeopleLine"|"PeoplePulling"|"PeopleRobbery"|"PeopleRoof"|"PepperHot"|"Percent"|"Person"|"PersonArrowDownToLine"|"PersonArrowUpFromLine"|"PersonBiking"|"PersonBooth"|"PersonBreastfeeding"|"PersonBurst"|"PersonCane"|"PersonChalkboard"|"PersonCircleCheck"|"PersonCircleExclamation"|"PersonCircleMinus"|"PersonCirclePlus"|"PersonCircleQuestion"|"PersonCircleXmark"|"PersonDigging"|"PersonDotsFromLine"|"PersonDress"|"PersonDressBurst"|"PersonDrowning"|"PersonFalling"|"PersonFallingBurst"|"PersonHalfDress"|"PersonHarassing"|"PersonHiking"|"PersonMilitaryPointing"|"PersonMilitaryRifle"|"PersonMilitaryToPerson"|"PersonPraying"|"PersonPregnant"|"PersonRays"|"PersonRifle"|"PersonRunning"|"PersonShelter"|"PersonSkating"|"PersonSkiing"|"PersonSkiingNordic"|"PersonSnowboarding"|"PersonSwimming"|"PersonThroughWindow"|"PersonWalking"|"PersonWalkingArrowLoopLeft"|"PersonWalkingArrowRight"|"PersonWalkingDashedLineArrowRight"|"PersonWalkingLuggage"|"PersonWalkingWithCane"|"PesetaSign"|"PesoSign"|"Phone"|"PhoneFlip"|"PhoneSlash"|"PhoneVolume"|"PhotoFilm"|"PiggyBank"|"Pills"|"PizzaSlice"|"PlaceOfWorship"|"Plane"|"PlaneArrival"|"PlaneCircleCheck"|"PlaneCircleExclamation"|"PlaneCircleXmark"|"PlaneDeparture"|"PlaneLock"|"PlaneSlash"|"PlaneUp"|"PlantWilt"|"PlateWheat"|"Play"|"Plug"|"PlugCircleBolt"|"PlugCircleCheck"|"PlugCircleExclamation"|"PlugCircleMinus"|"PlugCirclePlus"|"PlugCircleXmark"|"Plus"|"PlusMinus"|"Podcast"|"Poo"|"PooStorm"|"Poop"|"PowerOff"|"Prescription"|"PrescriptionBottle"|"PrescriptionBottleMedical"|"Print"|"PumpMedical"|"PumpSoap"|"PuzzlePiece"|"Q"|"Qrcode"|"Question"|"QuoteLeft"|"QuoteRight"|"R"|"Radiation"|"Radio"|"Rainbow"|"RankingStar"|"Receipt"|"RecordVinyl"|"RectangleAd"|"RectangleList"|"RectangleXmark"|"Recycle"|"Registered"|"Repeat"|"Reply"|"ReplyAll"|"Republican"|"Restroom"|"Retweet"|"Ribbon"|"RightFromBracket"|"RightLeft"|"RightLong"|"RightToBracket"|"Ring"|"Road"|"RoadBarrier"|"RoadBridge"|"RoadCircleCheck"|"RoadCircleExclamation"|"RoadCircleXmark"|"RoadLock"|"RoadSpikes"|"Robot"|"Rocket"|"Rotate"|"RotateLeft"|"RotateRight"|"Route"|"Rss"|"RubleSign"|"Rug"|"Ruler"|"RulerCombined"|"RulerHorizontal"|"RulerVertical"|"RupeeSign"|"RupiahSign"|"S"|"SackDollar"|"SackXmark"|"Sailboat"|"Satellite"|"SatelliteDish"|"ScaleBalanced"|"ScaleUnbalanced"|"ScaleUnbalancedFlip"|"School"|"SchoolCircleCheck"|"SchoolCircleExclamation"|"SchoolCircleXmark"|"SchoolFlag"|"SchoolLock"|"Scissors"|"Screwdriver"|"ScrewdriverWrench"|"Scroll"|"ScrollTorah"|"SdCard"|"Section"|"Seedling"|"Server"|"Shapes"|"Share"|"ShareFromSquare"|"ShareNodes"|"SheetPlastic"|"ShekelSign"|"Shield"|"ShieldCat"|"ShieldDog"|"ShieldHalved"|"ShieldHeart"|"ShieldVirus"|"Ship"|"Shirt"|"ShoePrints"|"Shop"|"ShopLock"|"ShopSlash"|"Shower"|"Shrimp"|"Shuffle"|"ShuttleSpace"|"SignHanging"|"Signal"|"Signature"|"SignsPost"|"SimCard"|"Sink"|"Sitemap"|"Skull"|"SkullCrossbones"|"Slash"|"Sleigh"|"Sliders"|"Smog"|"Smoking"|"Snowflake"|"Snowman"|"Snowplow"|"Soap"|"Socks"|"SolarPanel"|"Sort"|"SortDown"|"SortUp"|"Spa"|"SpaghettiMonsterFlying"|"SpellCheck"|"Spider"|"Spinner"|"Splotch"|"Spoon"|"SprayCan"|"SprayCanSparkles"|"Square"|"SquareArrowUpRight"|"SquareBinary"|"SquareCaretDown"|"SquareCaretLeft"|"SquareCaretRight"|"SquareCaretUp"|"SquareCheck"|"SquareEnvelope"|"SquareFull"|"SquareH"|"SquareMinus"|"SquareNfi"|"SquareParking"|"SquarePen"|"SquarePersonConfined"|"SquarePhone"|"SquarePhoneFlip"|"SquarePlus"|"SquarePollHorizontal"|"SquarePollVertical"|"SquareRootVariable"|"SquareRss"|"SquareShareNodes"|"SquareUpRight"|"SquareVirus"|"SquareXmark"|"StaffSnake"|"Stairs"|"Stamp"|"Stapler"|"Star"|"StarAndCrescent"|"StarHalf"|"StarHalfStroke"|"StarOfDavid"|"StarOfLife"|"SterlingSign"|"Stethoscope"|"Stop"|"Stopwatch"|"Stopwatch20"|"Store"|"StoreSlash"|"StreetView"|"Strikethrough"|"Stroopwafel"|"Subscript"|"Suitcase"|"SuitcaseMedical"|"SuitcaseRolling"|"Sun"|"SunPlantWilt"|"Superscript"|"Swatchbook"|"Synagogue"|"Syringe"|"T"|"Table"|"TableCells"|"TableCellsColumnLock"|"TableCellsLarge"|"TableCellsRowLock"|"TableCellsRowUnlock"|"TableColumns"|"TableList"|"TableTennisPaddleBall"|"Tablet"|"TabletButton"|"TabletScreenButton"|"Tablets"|"TachographDigital"|"Tag"|"Tags"|"Tape"|"Tarp"|"TarpDroplet"|"Taxi"|"Teeth"|"TeethOpen"|"TemperatureArrowDown"|"TemperatureArrowUp"|"TemperatureEmpty"|"TemperatureFull"|"TemperatureHalf"|"TemperatureHigh"|"TemperatureLow"|"TemperatureQuarter"|"TemperatureThreeQuarters"|"TengeSign"|"Tent"|"TentArrowDownToLine"|"TentArrowLeftRight"|"TentArrowTurnLeft"|"TentArrowsDown"|"Tents"|"Terminal"|"TextHeight"|"TextSlash"|"TextWidth"|"Thermometer"|"ThumbsDown"|"ThumbsUp"|"Thumbtack"|"ThumbtackSlash"|"Ticket"|"TicketSimple"|"Timeline"|"ToggleOff"|"ToggleOn"|"Toilet"|"ToiletPaper"|"ToiletPaperSlash"|"ToiletPortable"|"ToiletsPortable"|"Toolbox"|"Tooth"|"ToriiGate"|"Tornado"|"TowerBroadcast"|"TowerCell"|"TowerObservation"|"Tractor"|"Trademark"|"TrafficLight"|"Trailer"|"Train"|"TrainSubway"|"TrainTram"|"Transgender"|"Trash"|"TrashArrowUp"|"TrashCan"|"TrashCanArrowUp"|"Tree"|"TreeCity"|"TriangleExclamation"|"Trophy"|"Trowel"|"TrowelBricks"|"Truck"|"TruckArrowRight"|"TruckDroplet"|"TruckFast"|"TruckField"|"TruckFieldUn"|"TruckFront"|"TruckMedical"|"TruckMonster"|"TruckMoving"|"TruckPickup"|"TruckPlane"|"TruckRampBox"|"Tty"|"TurkishLiraSign"|"TurnDown"|"TurnUp"|"Tv"|"U"|"Umbrella"|"UmbrellaBeach"|"Underline"|"UniversalAccess"|"Unlock"|"UnlockKeyhole"|"UpDown"|"UpDownLeftRight"|"UpLong"|"UpRightAndDownLeftFromCenter"|"UpRightFromSquare"|"Upload"|"User"|"UserAstronaut"|"UserCheck"|"UserClock"|"UserDoctor"|"UserGear"|"UserGraduate"|"UserGroup"|"UserInjured"|"UserLarge"|"UserLargeSlash"|"UserLock"|"UserMinus"|"UserNinja"|"UserNurse"|"UserPen"|"UserPlus"|"UserSecret"|"UserShield"|"UserSlash"|"UserTag"|"UserTie"|"UserXmark"|"Users"|"UsersBetweenLines"|"UsersGear"|"UsersLine"|"UsersRays"|"UsersRectangle"|"UsersSlash"|"UsersViewfinder"|"Utensils"|"V"|"VanShuttle"|"Vault"|"VectorSquare"|"Venus"|"VenusDouble"|"VenusMars"|"Vest"|"VestPatches"|"Vial"|"VialCircleCheck"|"VialVirus"|"Vials"|"Video"|"VideoSlash"|"Vihara"|"Virus"|"VirusCovid"|"VirusCovidSlash"|"VirusSlash"|"Viruses"|"Voicemail"|"Volcano"|"Volleyball"|"VolumeHigh"|"VolumeLow"|"VolumeOff"|"VolumeXmark"|"VrCardboard"|"W"|"WalkieTalkie"|"Wallet"|"WandMagic"|"WandMagicSparkles"|"WandSparkles"|"Warehouse"|"Water"|"WaterLadder"|"WaveSquare"|"WebAwesome"|"WeightHanging"|"WeightScale"|"WheatAwn"|"WheatAwnCircleExclamation"|"Wheelchair"|"WheelchairMove"|"WhiskeyGlass"|"Wifi"|"Wind"|"WindowMaximize"|"WindowMinimize"|"WindowRestore"|"WineBottle"|"WineGlass"|"WineGlassEmpty"|"WonSign"|"Worm"|"Wrench"|"X"|"XRay"|"Xmark"|"XmarksLines"|"Y"|"YenSign"|"YinYang"|"Z"|"Search"|"Save"|"Settings"|"Cog"|"Home"|"Edit"|"Close"|"Cancel"|"Refresh"|"Warning"|"CheckCircle"|"TimesCircle"|"VolumeMute"|"Cut"|"Undo"|"Redo"|"StepForward"|"StepBackward"|"Pin"|"ZoomIn"|"ZoomOut"
---@overload fun(self: UIButtonNode, path: "iconSize"): number
---@overload fun(self: UIButtonNode, path: "normalColor"): number[]
---@overload fun(self: UIButtonNode, path: "hoverColor"): number[]
---@overload fun(self: UIButtonNode, path: "pressedColor"): number[]
---@overload fun(self: UIButtonNode, path: "borderColor"): number[]
---@overload fun(self: UIButtonNode, path: "textColor"): number[]
---@overload fun(self: UIButtonNode, path: "align"): "Left"|"Center"|"Right"
function UIButtonNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UIButtonNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UIButtonNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIButtonNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIButtonNode, path: "rotation", value: number)
---@overload fun(self: UIButtonNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIButtonNode, path: "zIndex", value: integer)
---@overload fun(self: UIButtonNode, path: "ySort", value: boolean)
---@overload fun(self: UIButtonNode, path: "ySortOffset", value: number)
---@overload fun(self: UIButtonNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIButtonNode, path: "paused", value: boolean)
---@overload fun(self: UIButtonNode, path: "enabled", value: boolean)
---@overload fun(self: UIButtonNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIButtonNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UIButtonNode, path: "text", value: string)
---@overload fun(self: UIButtonNode, path: "fontSize", value: number)
---@overload fun(self: UIButtonNode, path: "icon", value: "None"|"Digit0"|"Digit1"|"Digit2"|"Digit3"|"Digit4"|"Digit5"|"Digit6"|"Digit7"|"Digit8"|"Digit9"|"A"|"AddressBook"|"AddressCard"|"AlignCenter"|"AlignJustify"|"AlignLeft"|"AlignRight"|"Anchor"|"AnchorCircleCheck"|"AnchorCircleExclamation"|"AnchorCircleXmark"|"AnchorLock"|"AngleDown"|"AngleLeft"|"AngleRight"|"AngleUp"|"AnglesDown"|"AnglesLeft"|"AnglesRight"|"AnglesUp"|"Ankh"|"AppleWhole"|"Archway"|"ArrowDown"|"ArrowDown19"|"ArrowDown91"|"ArrowDownAZ"|"ArrowDownLong"|"ArrowDownShortWide"|"ArrowDownUpAcrossLine"|"ArrowDownUpLock"|"ArrowDownWideShort"|"ArrowDownZA"|"ArrowLeft"|"ArrowLeftLong"|"ArrowPointer"|"ArrowRight"|"ArrowRightArrowLeft"|"ArrowRightFromBracket"|"ArrowRightLong"|"ArrowRightToBracket"|"ArrowRightToCity"|"ArrowRotateLeft"|"ArrowRotateRight"|"ArrowTrendDown"|"ArrowTrendUp"|"ArrowTurnDown"|"ArrowTurnUp"|"ArrowUp"|"ArrowUp19"|"ArrowUp91"|"ArrowUpAZ"|"ArrowUpFromBracket"|"ArrowUpFromGroundWater"|"ArrowUpFromWaterPump"|"ArrowUpLong"|"ArrowUpRightDots"|"ArrowUpRightFromSquare"|"ArrowUpShortWide"|"ArrowUpWideShort"|"ArrowUpZA"|"ArrowsDownToLine"|"ArrowsDownToPeople"|"ArrowsLeftRight"|"ArrowsLeftRightToLine"|"ArrowsRotate"|"ArrowsSpin"|"ArrowsSplitUpAndLeft"|"ArrowsToCircle"|"ArrowsToDot"|"ArrowsToEye"|"ArrowsTurnRight"|"ArrowsTurnToDots"|"ArrowsUpDown"|"ArrowsUpDownLeftRight"|"ArrowsUpToLine"|"Asterisk"|"At"|"Atom"|"AudioDescription"|"AustralSign"|"Award"|"B"|"Baby"|"BabyCarriage"|"Backward"|"BackwardFast"|"BackwardStep"|"Bacon"|"Bacteria"|"Bacterium"|"BagShopping"|"Bahai"|"BahtSign"|"Ban"|"BanSmoking"|"Bandage"|"BangladeshiTakaSign"|"Barcode"|"Bars"|"BarsProgress"|"BarsStaggered"|"Baseball"|"BaseballBatBall"|"BasketShopping"|"Basketball"|"Bath"|"BatteryEmpty"|"BatteryFull"|"BatteryHalf"|"BatteryQuarter"|"BatteryThreeQuarters"|"Bed"|"BedPulse"|"BeerMugEmpty"|"Bell"|"BellConcierge"|"BellSlash"|"BezierCurve"|"Bicycle"|"Binoculars"|"Biohazard"|"BitcoinSign"|"Blender"|"BlenderPhone"|"Blog"|"Bold"|"Bolt"|"BoltLightning"|"Bomb"|"Bone"|"Bong"|"Book"|"BookAtlas"|"BookBible"|"BookBookmark"|"BookJournalWhills"|"BookMedical"|"BookOpen"|"BookOpenReader"|"BookQuran"|"BookSkull"|"BookTanakh"|"Bookmark"|"BorderAll"|"BorderNone"|"BorderTopLeft"|"BoreHole"|"BottleDroplet"|"BottleWater"|"BowlFood"|"BowlRice"|"BowlingBall"|"Box"|"BoxArchive"|"BoxOpen"|"BoxTissue"|"BoxesPacking"|"BoxesStacked"|"Braille"|"Brain"|"BrazilianRealSign"|"BreadSlice"|"Bridge"|"BridgeCircleCheck"|"BridgeCircleExclamation"|"BridgeCircleXmark"|"BridgeLock"|"BridgeWater"|"Briefcase"|"BriefcaseMedical"|"Broom"|"BroomBall"|"Brush"|"Bucket"|"Bug"|"BugSlash"|"Bugs"|"Building"|"BuildingCircleArrowRight"|"BuildingCircleCheck"|"BuildingCircleExclamation"|"BuildingCircleXmark"|"BuildingColumns"|"BuildingFlag"|"BuildingLock"|"BuildingNgo"|"BuildingShield"|"BuildingUn"|"BuildingUser"|"BuildingWheat"|"Bullhorn"|"Bullseye"|"Burger"|"Burst"|"Bus"|"BusSimple"|"BusinessTime"|"C"|"CableCar"|"CakeCandles"|"Calculator"|"Calendar"|"CalendarCheck"|"CalendarDay"|"CalendarDays"|"CalendarMinus"|"CalendarPlus"|"CalendarWeek"|"CalendarXmark"|"Camera"|"CameraRetro"|"CameraRotate"|"Campground"|"CandyCane"|"Cannabis"|"Capsules"|"Car"|"CarBattery"|"CarBurst"|"CarOn"|"CarRear"|"CarSide"|"CarTunnel"|"Caravan"|"CaretDown"|"CaretLeft"|"CaretRight"|"CaretUp"|"Carrot"|"CartArrowDown"|"CartFlatbed"|"CartFlatbedSuitcase"|"CartPlus"|"CartShopping"|"CashRegister"|"Cat"|"CediSign"|"CentSign"|"Certificate"|"Chair"|"Chalkboard"|"ChalkboardUser"|"ChampagneGlasses"|"ChargingStation"|"ChartArea"|"ChartBar"|"ChartColumn"|"ChartDiagram"|"ChartGantt"|"ChartLine"|"ChartPie"|"ChartSimple"|"Check"|"CheckDouble"|"CheckToSlot"|"Cheese"|"Chess"|"ChessBishop"|"ChessBoard"|"ChessKing"|"ChessKnight"|"ChessPawn"|"ChessQueen"|"ChessRook"|"ChevronDown"|"ChevronLeft"|"ChevronRight"|"ChevronUp"|"Child"|"ChildCombatant"|"ChildDress"|"ChildReaching"|"Children"|"Church"|"Circle"|"CircleArrowDown"|"CircleArrowLeft"|"CircleArrowRight"|"CircleArrowUp"|"CircleCheck"|"CircleChevronDown"|"CircleChevronLeft"|"CircleChevronRight"|"CircleChevronUp"|"CircleDollarToSlot"|"CircleDot"|"CircleDown"|"CircleExclamation"|"CircleH"|"CircleHalfStroke"|"CircleInfo"|"CircleLeft"|"CircleMinus"|"CircleNodes"|"CircleNotch"|"CirclePause"|"CirclePlay"|"CirclePlus"|"CircleQuestion"|"CircleRadiation"|"CircleRight"|"CircleStop"|"CircleUp"|"CircleUser"|"CircleXmark"|"City"|"Clapperboard"|"Clipboard"|"ClipboardCheck"|"ClipboardList"|"ClipboardQuestion"|"ClipboardUser"|"Clock"|"ClockRotateLeft"|"Clone"|"ClosedCaptioning"|"Cloud"|"CloudArrowDown"|"CloudArrowUp"|"CloudBolt"|"CloudMeatball"|"CloudMoon"|"CloudMoonRain"|"CloudRain"|"CloudShowersHeavy"|"CloudShowersWater"|"CloudSun"|"CloudSunRain"|"Clover"|"Code"|"CodeBranch"|"CodeCommit"|"CodeCompare"|"CodeFork"|"CodeMerge"|"CodePullRequest"|"Coins"|"ColonSign"|"Comment"|"CommentDollar"|"CommentDots"|"CommentMedical"|"CommentNodes"|"CommentSlash"|"CommentSms"|"Comments"|"CommentsDollar"|"CompactDisc"|"Compass"|"CompassDrafting"|"Compress"|"Computer"|"ComputerMouse"|"Cookie"|"CookieBite"|"Copy"|"Copyright"|"Couch"|"Cow"|"CreditCard"|"Crop"|"CropSimple"|"Cross"|"Crosshairs"|"Crow"|"Crown"|"Crutch"|"CruzeiroSign"|"Cube"|"Cubes"|"CubesStacked"|"D"|"Database"|"DeleteLeft"|"Democrat"|"Desktop"|"Dharmachakra"|"DiagramNext"|"DiagramPredecessor"|"DiagramProject"|"DiagramSuccessor"|"Diamond"|"DiamondTurnRight"|"Dice"|"DiceD20"|"DiceD6"|"DiceFive"|"DiceFour"|"DiceOne"|"DiceSix"|"DiceThree"|"DiceTwo"|"Disease"|"Display"|"Divide"|"Dna"|"Dog"|"DollarSign"|"Dolly"|"DongSign"|"DoorClosed"|"DoorOpen"|"Dove"|"DownLeftAndUpRightToCenter"|"DownLong"|"Download"|"Dragon"|"DrawPolygon"|"Droplet"|"DropletSlash"|"Drum"|"DrumSteelpan"|"DrumstickBite"|"Dumbbell"|"Dumpster"|"DumpsterFire"|"Dungeon"|"E"|"EarDeaf"|"EarListen"|"EarthAfrica"|"EarthAmericas"|"EarthAsia"|"EarthEurope"|"EarthOceania"|"Egg"|"Eject"|"Elevator"|"Ellipsis"|"EllipsisVertical"|"Envelope"|"EnvelopeCircleCheck"|"EnvelopeOpen"|"EnvelopeOpenText"|"EnvelopesBulk"|"Equals"|"Eraser"|"Ethernet"|"EuroSign"|"Exclamation"|"Expand"|"Explosion"|"Eye"|"EyeDropper"|"EyeLowVision"|"EyeSlash"|"F"|"FaceAngry"|"FaceDizzy"|"FaceFlushed"|"FaceFrown"|"FaceFrownOpen"|"FaceGrimace"|"FaceGrin"|"FaceGrinBeam"|"FaceGrinBeamSweat"|"FaceGrinHearts"|"FaceGrinSquint"|"FaceGrinSquintTears"|"FaceGrinStars"|"FaceGrinTears"|"FaceGrinTongue"|"FaceGrinTongueSquint"|"FaceGrinTongueWink"|"FaceGrinWide"|"FaceGrinWink"|"FaceKiss"|"FaceKissBeam"|"FaceKissWinkHeart"|"FaceLaugh"|"FaceLaughBeam"|"FaceLaughSquint"|"FaceLaughWink"|"FaceMeh"|"FaceMehBlank"|"FaceRollingEyes"|"FaceSadCry"|"FaceSadTear"|"FaceSmile"|"FaceSmileBeam"|"FaceSmileWink"|"FaceSurprise"|"FaceTired"|"Fan"|"Faucet"|"FaucetDrip"|"Fax"|"Feather"|"FeatherPointed"|"Ferry"|"File"|"FileArrowDown"|"FileArrowUp"|"FileAudio"|"FileCircleCheck"|"FileCircleExclamation"|"FileCircleMinus"|"FileCirclePlus"|"FileCircleQuestion"|"FileCircleXmark"|"FileCode"|"FileContract"|"FileCsv"|"FileExcel"|"FileExport"|"FileFragment"|"FileHalfDashed"|"FileImage"|"FileImport"|"FileInvoice"|"FileInvoiceDollar"|"FileLines"|"FileMedical"|"FilePdf"|"FilePen"|"FilePowerpoint"|"FilePrescription"|"FileShield"|"FileSignature"|"FileVideo"|"FileWaveform"|"FileWord"|"FileZipper"|"Fill"|"FillDrip"|"Film"|"Filter"|"FilterCircleDollar"|"FilterCircleXmark"|"Fingerprint"|"Fire"|"FireBurner"|"FireExtinguisher"|"FireFlameCurved"|"FireFlameSimple"|"Fish"|"FishFins"|"Flag"|"FlagCheckered"|"FlagUsa"|"Flask"|"FlaskVial"|"FloppyDisk"|"FlorinSign"|"Folder"|"FolderClosed"|"FolderMinus"|"FolderOpen"|"FolderPlus"|"FolderTree"|"Font"|"FontAwesome"|"Football"|"Forward"|"ForwardFast"|"ForwardStep"|"FrancSign"|"Frog"|"Futbol"|"G"|"Gamepad"|"GasPump"|"Gauge"|"GaugeHigh"|"GaugeSimple"|"GaugeSimpleHigh"|"Gavel"|"Gear"|"Gears"|"Gem"|"Genderless"|"Ghost"|"Gift"|"Gifts"|"GlassWater"|"GlassWaterDroplet"|"Glasses"|"Globe"|"GolfBallTee"|"Gopuram"|"GraduationCap"|"GreaterThan"|"GreaterThanEqual"|"Grip"|"GripLines"|"GripLinesVertical"|"GripVertical"|"GroupArrowsRotate"|"GuaraniSign"|"Guitar"|"Gun"|"H"|"Hammer"|"Hamsa"|"Hand"|"HandBackFist"|"HandDots"|"HandFist"|"HandHolding"|"HandHoldingDollar"|"HandHoldingDroplet"|"HandHoldingHand"|"HandHoldingHeart"|"HandHoldingMedical"|"HandLizard"|"HandMiddleFinger"|"HandPeace"|"HandPointDown"|"HandPointLeft"|"HandPointRight"|"HandPointUp"|"HandPointer"|"HandScissors"|"HandSparkles"|"HandSpock"|"Handcuffs"|"Hands"|"HandsAslInterpreting"|"HandsBound"|"HandsBubbles"|"HandsClapping"|"HandsHolding"|"HandsHoldingChild"|"HandsHoldingCircle"|"HandsPraying"|"Handshake"|"HandshakeAngle"|"HandshakeSimple"|"HandshakeSimpleSlash"|"HandshakeSlash"|"Hanukiah"|"HardDrive"|"Hashtag"|"HatCowboy"|"HatCowboySide"|"HatWizard"|"HeadSideCough"|"HeadSideCoughSlash"|"HeadSideMask"|"HeadSideVirus"|"Heading"|"Headphones"|"HeadphonesSimple"|"Headset"|"Heart"|"HeartCircleBolt"|"HeartCircleCheck"|"HeartCircleExclamation"|"HeartCircleMinus"|"HeartCirclePlus"|"HeartCircleXmark"|"HeartCrack"|"HeartPulse"|"Helicopter"|"HelicopterSymbol"|"HelmetSafety"|"HelmetUn"|"HexagonNodes"|"HexagonNodesBolt"|"Highlighter"|"HillAvalanche"|"HillRockslide"|"Hippo"|"HockeyPuck"|"HollyBerry"|"Horse"|"HorseHead"|"Hospital"|"HospitalUser"|"HotTubPerson"|"Hotdog"|"Hotel"|"Hourglass"|"HourglassEnd"|"HourglassHalf"|"HourglassStart"|"House"|"HouseChimney"|"HouseChimneyCrack"|"HouseChimneyMedical"|"HouseChimneyUser"|"HouseChimneyWindow"|"HouseCircleCheck"|"HouseCircleExclamation"|"HouseCircleXmark"|"HouseCrack"|"HouseFire"|"HouseFlag"|"HouseFloodWater"|"HouseFloodWaterCircleArrowRight"|"HouseLaptop"|"HouseLock"|"HouseMedical"|"HouseMedicalCircleCheck"|"HouseMedicalCircleExclamation"|"HouseMedicalCircleXmark"|"HouseMedicalFlag"|"HouseSignal"|"HouseTsunami"|"HouseUser"|"HryvniaSign"|"Hurricane"|"I"|"ICursor"|"IceCream"|"Icicles"|"Icons"|"IdBadge"|"IdCard"|"IdCardClip"|"Igloo"|"Image"|"ImagePortrait"|"Images"|"Inbox"|"Indent"|"IndianRupeeSign"|"Industry"|"Infinity"|"Info"|"Italic"|"J"|"Jar"|"JarWheat"|"Jedi"|"JetFighter"|"JetFighterUp"|"Joint"|"JugDetergent"|"K"|"Kaaba"|"Key"|"Keyboard"|"Khanda"|"KipSign"|"KitMedical"|"KitchenSet"|"KiwiBird"|"L"|"LandMineOn"|"Landmark"|"LandmarkDome"|"LandmarkFlag"|"Language"|"Laptop"|"LaptopCode"|"LaptopFile"|"LaptopMedical"|"LariSign"|"LayerGroup"|"Leaf"|"LeftLong"|"LeftRight"|"Lemon"|"LessThan"|"LessThanEqual"|"LifeRing"|"Lightbulb"|"LinesLeaning"|"Link"|"LinkSlash"|"LiraSign"|"List"|"ListCheck"|"ListOl"|"ListUl"|"LitecoinSign"|"LocationArrow"|"LocationCrosshairs"|"LocationDot"|"LocationPin"|"LocationPinLock"|"Lock"|"LockOpen"|"Locust"|"Lungs"|"LungsVirus"|"M"|"Magnet"|"MagnifyingGlass"|"MagnifyingGlassArrowRight"|"MagnifyingGlassChart"|"MagnifyingGlassDollar"|"MagnifyingGlassLocation"|"MagnifyingGlassMinus"|"MagnifyingGlassPlus"|"ManatSign"|"Map"|"MapLocation"|"MapLocationDot"|"MapPin"|"Marker"|"Mars"|"MarsAndVenus"|"MarsAndVenusBurst"|"MarsDouble"|"MarsStroke"|"MarsStrokeRight"|"MarsStrokeUp"|"MartiniGlass"|"MartiniGlassCitrus"|"MartiniGlassEmpty"|"Mask"|"MaskFace"|"MaskVentilator"|"MasksTheater"|"MattressPillow"|"Maximize"|"Medal"|"Memory"|"Menorah"|"Mercury"|"Message"|"Meteor"|"Microchip"|"Microphone"|"MicrophoneLines"|"MicrophoneLinesSlash"|"MicrophoneSlash"|"Microscope"|"MillSign"|"Minimize"|"Minus"|"Mitten"|"Mobile"|"MobileButton"|"MobileRetro"|"MobileScreen"|"MobileScreenButton"|"MoneyBill"|"MoneyBill1"|"MoneyBill1Wave"|"MoneyBillTransfer"|"MoneyBillTrendUp"|"MoneyBillWave"|"MoneyBillWheat"|"MoneyBills"|"MoneyCheck"|"MoneyCheckDollar"|"Monument"|"Moon"|"MortarPestle"|"Mosque"|"Mosquito"|"MosquitoNet"|"Motorcycle"|"Mound"|"Mountain"|"MountainCity"|"MountainSun"|"MugHot"|"MugSaucer"|"Music"|"N"|"NairaSign"|"NetworkWired"|"Neuter"|"Newspaper"|"NotEqual"|"Notdef"|"NoteSticky"|"NotesMedical"|"O"|"ObjectGroup"|"ObjectUngroup"|"OilCan"|"OilWell"|"Om"|"Otter"|"Outdent"|"P"|"Pager"|"PaintRoller"|"Paintbrush"|"Palette"|"Pallet"|"Panorama"|"PaperPlane"|"Paperclip"|"ParachuteBox"|"Paragraph"|"Passport"|"Paste"|"Pause"|"Paw"|"Peace"|"Pen"|"PenClip"|"PenFancy"|"PenNib"|"PenRuler"|"PenToSquare"|"Pencil"|"PeopleArrows"|"PeopleCarryBox"|"PeopleGroup"|"PeopleLine"|"PeoplePulling"|"PeopleRobbery"|"PeopleRoof"|"PepperHot"|"Percent"|"Person"|"PersonArrowDownToLine"|"PersonArrowUpFromLine"|"PersonBiking"|"PersonBooth"|"PersonBreastfeeding"|"PersonBurst"|"PersonCane"|"PersonChalkboard"|"PersonCircleCheck"|"PersonCircleExclamation"|"PersonCircleMinus"|"PersonCirclePlus"|"PersonCircleQuestion"|"PersonCircleXmark"|"PersonDigging"|"PersonDotsFromLine"|"PersonDress"|"PersonDressBurst"|"PersonDrowning"|"PersonFalling"|"PersonFallingBurst"|"PersonHalfDress"|"PersonHarassing"|"PersonHiking"|"PersonMilitaryPointing"|"PersonMilitaryRifle"|"PersonMilitaryToPerson"|"PersonPraying"|"PersonPregnant"|"PersonRays"|"PersonRifle"|"PersonRunning"|"PersonShelter"|"PersonSkating"|"PersonSkiing"|"PersonSkiingNordic"|"PersonSnowboarding"|"PersonSwimming"|"PersonThroughWindow"|"PersonWalking"|"PersonWalkingArrowLoopLeft"|"PersonWalkingArrowRight"|"PersonWalkingDashedLineArrowRight"|"PersonWalkingLuggage"|"PersonWalkingWithCane"|"PesetaSign"|"PesoSign"|"Phone"|"PhoneFlip"|"PhoneSlash"|"PhoneVolume"|"PhotoFilm"|"PiggyBank"|"Pills"|"PizzaSlice"|"PlaceOfWorship"|"Plane"|"PlaneArrival"|"PlaneCircleCheck"|"PlaneCircleExclamation"|"PlaneCircleXmark"|"PlaneDeparture"|"PlaneLock"|"PlaneSlash"|"PlaneUp"|"PlantWilt"|"PlateWheat"|"Play"|"Plug"|"PlugCircleBolt"|"PlugCircleCheck"|"PlugCircleExclamation"|"PlugCircleMinus"|"PlugCirclePlus"|"PlugCircleXmark"|"Plus"|"PlusMinus"|"Podcast"|"Poo"|"PooStorm"|"Poop"|"PowerOff"|"Prescription"|"PrescriptionBottle"|"PrescriptionBottleMedical"|"Print"|"PumpMedical"|"PumpSoap"|"PuzzlePiece"|"Q"|"Qrcode"|"Question"|"QuoteLeft"|"QuoteRight"|"R"|"Radiation"|"Radio"|"Rainbow"|"RankingStar"|"Receipt"|"RecordVinyl"|"RectangleAd"|"RectangleList"|"RectangleXmark"|"Recycle"|"Registered"|"Repeat"|"Reply"|"ReplyAll"|"Republican"|"Restroom"|"Retweet"|"Ribbon"|"RightFromBracket"|"RightLeft"|"RightLong"|"RightToBracket"|"Ring"|"Road"|"RoadBarrier"|"RoadBridge"|"RoadCircleCheck"|"RoadCircleExclamation"|"RoadCircleXmark"|"RoadLock"|"RoadSpikes"|"Robot"|"Rocket"|"Rotate"|"RotateLeft"|"RotateRight"|"Route"|"Rss"|"RubleSign"|"Rug"|"Ruler"|"RulerCombined"|"RulerHorizontal"|"RulerVertical"|"RupeeSign"|"RupiahSign"|"S"|"SackDollar"|"SackXmark"|"Sailboat"|"Satellite"|"SatelliteDish"|"ScaleBalanced"|"ScaleUnbalanced"|"ScaleUnbalancedFlip"|"School"|"SchoolCircleCheck"|"SchoolCircleExclamation"|"SchoolCircleXmark"|"SchoolFlag"|"SchoolLock"|"Scissors"|"Screwdriver"|"ScrewdriverWrench"|"Scroll"|"ScrollTorah"|"SdCard"|"Section"|"Seedling"|"Server"|"Shapes"|"Share"|"ShareFromSquare"|"ShareNodes"|"SheetPlastic"|"ShekelSign"|"Shield"|"ShieldCat"|"ShieldDog"|"ShieldHalved"|"ShieldHeart"|"ShieldVirus"|"Ship"|"Shirt"|"ShoePrints"|"Shop"|"ShopLock"|"ShopSlash"|"Shower"|"Shrimp"|"Shuffle"|"ShuttleSpace"|"SignHanging"|"Signal"|"Signature"|"SignsPost"|"SimCard"|"Sink"|"Sitemap"|"Skull"|"SkullCrossbones"|"Slash"|"Sleigh"|"Sliders"|"Smog"|"Smoking"|"Snowflake"|"Snowman"|"Snowplow"|"Soap"|"Socks"|"SolarPanel"|"Sort"|"SortDown"|"SortUp"|"Spa"|"SpaghettiMonsterFlying"|"SpellCheck"|"Spider"|"Spinner"|"Splotch"|"Spoon"|"SprayCan"|"SprayCanSparkles"|"Square"|"SquareArrowUpRight"|"SquareBinary"|"SquareCaretDown"|"SquareCaretLeft"|"SquareCaretRight"|"SquareCaretUp"|"SquareCheck"|"SquareEnvelope"|"SquareFull"|"SquareH"|"SquareMinus"|"SquareNfi"|"SquareParking"|"SquarePen"|"SquarePersonConfined"|"SquarePhone"|"SquarePhoneFlip"|"SquarePlus"|"SquarePollHorizontal"|"SquarePollVertical"|"SquareRootVariable"|"SquareRss"|"SquareShareNodes"|"SquareUpRight"|"SquareVirus"|"SquareXmark"|"StaffSnake"|"Stairs"|"Stamp"|"Stapler"|"Star"|"StarAndCrescent"|"StarHalf"|"StarHalfStroke"|"StarOfDavid"|"StarOfLife"|"SterlingSign"|"Stethoscope"|"Stop"|"Stopwatch"|"Stopwatch20"|"Store"|"StoreSlash"|"StreetView"|"Strikethrough"|"Stroopwafel"|"Subscript"|"Suitcase"|"SuitcaseMedical"|"SuitcaseRolling"|"Sun"|"SunPlantWilt"|"Superscript"|"Swatchbook"|"Synagogue"|"Syringe"|"T"|"Table"|"TableCells"|"TableCellsColumnLock"|"TableCellsLarge"|"TableCellsRowLock"|"TableCellsRowUnlock"|"TableColumns"|"TableList"|"TableTennisPaddleBall"|"Tablet"|"TabletButton"|"TabletScreenButton"|"Tablets"|"TachographDigital"|"Tag"|"Tags"|"Tape"|"Tarp"|"TarpDroplet"|"Taxi"|"Teeth"|"TeethOpen"|"TemperatureArrowDown"|"TemperatureArrowUp"|"TemperatureEmpty"|"TemperatureFull"|"TemperatureHalf"|"TemperatureHigh"|"TemperatureLow"|"TemperatureQuarter"|"TemperatureThreeQuarters"|"TengeSign"|"Tent"|"TentArrowDownToLine"|"TentArrowLeftRight"|"TentArrowTurnLeft"|"TentArrowsDown"|"Tents"|"Terminal"|"TextHeight"|"TextSlash"|"TextWidth"|"Thermometer"|"ThumbsDown"|"ThumbsUp"|"Thumbtack"|"ThumbtackSlash"|"Ticket"|"TicketSimple"|"Timeline"|"ToggleOff"|"ToggleOn"|"Toilet"|"ToiletPaper"|"ToiletPaperSlash"|"ToiletPortable"|"ToiletsPortable"|"Toolbox"|"Tooth"|"ToriiGate"|"Tornado"|"TowerBroadcast"|"TowerCell"|"TowerObservation"|"Tractor"|"Trademark"|"TrafficLight"|"Trailer"|"Train"|"TrainSubway"|"TrainTram"|"Transgender"|"Trash"|"TrashArrowUp"|"TrashCan"|"TrashCanArrowUp"|"Tree"|"TreeCity"|"TriangleExclamation"|"Trophy"|"Trowel"|"TrowelBricks"|"Truck"|"TruckArrowRight"|"TruckDroplet"|"TruckFast"|"TruckField"|"TruckFieldUn"|"TruckFront"|"TruckMedical"|"TruckMonster"|"TruckMoving"|"TruckPickup"|"TruckPlane"|"TruckRampBox"|"Tty"|"TurkishLiraSign"|"TurnDown"|"TurnUp"|"Tv"|"U"|"Umbrella"|"UmbrellaBeach"|"Underline"|"UniversalAccess"|"Unlock"|"UnlockKeyhole"|"UpDown"|"UpDownLeftRight"|"UpLong"|"UpRightAndDownLeftFromCenter"|"UpRightFromSquare"|"Upload"|"User"|"UserAstronaut"|"UserCheck"|"UserClock"|"UserDoctor"|"UserGear"|"UserGraduate"|"UserGroup"|"UserInjured"|"UserLarge"|"UserLargeSlash"|"UserLock"|"UserMinus"|"UserNinja"|"UserNurse"|"UserPen"|"UserPlus"|"UserSecret"|"UserShield"|"UserSlash"|"UserTag"|"UserTie"|"UserXmark"|"Users"|"UsersBetweenLines"|"UsersGear"|"UsersLine"|"UsersRays"|"UsersRectangle"|"UsersSlash"|"UsersViewfinder"|"Utensils"|"V"|"VanShuttle"|"Vault"|"VectorSquare"|"Venus"|"VenusDouble"|"VenusMars"|"Vest"|"VestPatches"|"Vial"|"VialCircleCheck"|"VialVirus"|"Vials"|"Video"|"VideoSlash"|"Vihara"|"Virus"|"VirusCovid"|"VirusCovidSlash"|"VirusSlash"|"Viruses"|"Voicemail"|"Volcano"|"Volleyball"|"VolumeHigh"|"VolumeLow"|"VolumeOff"|"VolumeXmark"|"VrCardboard"|"W"|"WalkieTalkie"|"Wallet"|"WandMagic"|"WandMagicSparkles"|"WandSparkles"|"Warehouse"|"Water"|"WaterLadder"|"WaveSquare"|"WebAwesome"|"WeightHanging"|"WeightScale"|"WheatAwn"|"WheatAwnCircleExclamation"|"Wheelchair"|"WheelchairMove"|"WhiskeyGlass"|"Wifi"|"Wind"|"WindowMaximize"|"WindowMinimize"|"WindowRestore"|"WineBottle"|"WineGlass"|"WineGlassEmpty"|"WonSign"|"Worm"|"Wrench"|"X"|"XRay"|"Xmark"|"XmarksLines"|"Y"|"YenSign"|"YinYang"|"Z"|"Search"|"Save"|"Settings"|"Cog"|"Home"|"Edit"|"Close"|"Cancel"|"Refresh"|"Warning"|"CheckCircle"|"TimesCircle"|"VolumeMute"|"Cut"|"Undo"|"Redo"|"StepForward"|"StepBackward"|"Pin"|"ZoomIn"|"ZoomOut")
---@overload fun(self: UIButtonNode, path: "iconSize", value: number)
---@overload fun(self: UIButtonNode, path: "normalColor", value: number[])
---@overload fun(self: UIButtonNode, path: "hoverColor", value: number[])
---@overload fun(self: UIButtonNode, path: "pressedColor", value: number[])
---@overload fun(self: UIButtonNode, path: "borderColor", value: number[])
---@overload fun(self: UIButtonNode, path: "textColor", value: number[])
---@overload fun(self: UIButtonNode, path: "align", value: "Left"|"Center"|"Right")
function UIButtonNode:set_property(path, value, y) end

---@class UISliderNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field label string Caption shown next to the control.
---@field value number Current value (between min and max).
---@field minValue number Lowest value.
---@field maxValue number Highest value.
---@field defaultValue number Value a right-click restores (a slider's reset button too).
---@field fineScale number Drag speed with Shift held (fine adjustment).
---@field isInteger boolean Snap to whole numbers.
---@field showResetButton boolean Show a button that restores the default value.
---@field labelWidth number Width reserved for the label (px); 0 = none.

---@alias UISliderNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "label" # string - Caption shown next to the control.
---| "value" # number - Current value (between min and max).
---| "minValue" # number - Lowest value.
---| "maxValue" # number - Highest value.
---| "defaultValue" # number - Value a right-click restores (a slider's reset button too).
---| "fineScale" # number - Drag speed with Shift held (fine adjustment).
---| "isInteger" # boolean - Snap to whole numbers.
---| "showResetButton" # boolean - Show a button that restores the default value.
---| "labelWidth" # number - Width reserved for the label (px); 0 = none.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UISliderNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UISliderNode, path: "position"): Vec2
---@overload fun(self: UISliderNode, path: "scale"): Vec2
---@overload fun(self: UISliderNode, path: "rotation"): number
---@overload fun(self: UISliderNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UISliderNode, path: "zIndex"): integer
---@overload fun(self: UISliderNode, path: "ySort"): boolean
---@overload fun(self: UISliderNode, path: "ySortOffset"): number
---@overload fun(self: UISliderNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UISliderNode, path: "paused"): boolean
---@overload fun(self: UISliderNode, path: "enabled"): boolean
---@overload fun(self: UISliderNode, path: "size"): Vec2
---@overload fun(self: UISliderNode, path: "keyboardFocus"): boolean
---@overload fun(self: UISliderNode, path: "label"): string
---@overload fun(self: UISliderNode, path: "value"): number
---@overload fun(self: UISliderNode, path: "minValue"): number
---@overload fun(self: UISliderNode, path: "maxValue"): number
---@overload fun(self: UISliderNode, path: "defaultValue"): number
---@overload fun(self: UISliderNode, path: "fineScale"): number
---@overload fun(self: UISliderNode, path: "isInteger"): boolean
---@overload fun(self: UISliderNode, path: "showResetButton"): boolean
---@overload fun(self: UISliderNode, path: "labelWidth"): number
function UISliderNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UISliderNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UISliderNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UISliderNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UISliderNode, path: "rotation", value: number)
---@overload fun(self: UISliderNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UISliderNode, path: "zIndex", value: integer)
---@overload fun(self: UISliderNode, path: "ySort", value: boolean)
---@overload fun(self: UISliderNode, path: "ySortOffset", value: number)
---@overload fun(self: UISliderNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UISliderNode, path: "paused", value: boolean)
---@overload fun(self: UISliderNode, path: "enabled", value: boolean)
---@overload fun(self: UISliderNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UISliderNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UISliderNode, path: "label", value: string)
---@overload fun(self: UISliderNode, path: "value", value: number)
---@overload fun(self: UISliderNode, path: "minValue", value: number)
---@overload fun(self: UISliderNode, path: "maxValue", value: number)
---@overload fun(self: UISliderNode, path: "defaultValue", value: number)
---@overload fun(self: UISliderNode, path: "fineScale", value: number)
---@overload fun(self: UISliderNode, path: "isInteger", value: boolean)
---@overload fun(self: UISliderNode, path: "showResetButton", value: boolean)
---@overload fun(self: UISliderNode, path: "labelWidth", value: number)
function UISliderNode:set_property(path, value, y) end

---@class UICheckboxNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field label string Caption shown next to the control.
---@field checked boolean Ticked now.
---@field defaultChecked boolean State restored by reset.
---@field accentColor number[] Tick and fill colour.
---@field boxSize number Box size (px).

---@alias UICheckboxNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "label" # string - Caption shown next to the control.
---| "checked" # boolean - Ticked now.
---| "defaultChecked" # boolean - State restored by reset.
---| "accentColor" # number[] - Tick and fill colour.
---| "boxSize" # number - Box size (px).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UICheckboxNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UICheckboxNode, path: "position"): Vec2
---@overload fun(self: UICheckboxNode, path: "scale"): Vec2
---@overload fun(self: UICheckboxNode, path: "rotation"): number
---@overload fun(self: UICheckboxNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UICheckboxNode, path: "zIndex"): integer
---@overload fun(self: UICheckboxNode, path: "ySort"): boolean
---@overload fun(self: UICheckboxNode, path: "ySortOffset"): number
---@overload fun(self: UICheckboxNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UICheckboxNode, path: "paused"): boolean
---@overload fun(self: UICheckboxNode, path: "enabled"): boolean
---@overload fun(self: UICheckboxNode, path: "size"): Vec2
---@overload fun(self: UICheckboxNode, path: "keyboardFocus"): boolean
---@overload fun(self: UICheckboxNode, path: "label"): string
---@overload fun(self: UICheckboxNode, path: "checked"): boolean
---@overload fun(self: UICheckboxNode, path: "defaultChecked"): boolean
---@overload fun(self: UICheckboxNode, path: "accentColor"): number[]
---@overload fun(self: UICheckboxNode, path: "boxSize"): number
function UICheckboxNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UICheckboxNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UICheckboxNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UICheckboxNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UICheckboxNode, path: "rotation", value: number)
---@overload fun(self: UICheckboxNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UICheckboxNode, path: "zIndex", value: integer)
---@overload fun(self: UICheckboxNode, path: "ySort", value: boolean)
---@overload fun(self: UICheckboxNode, path: "ySortOffset", value: number)
---@overload fun(self: UICheckboxNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UICheckboxNode, path: "paused", value: boolean)
---@overload fun(self: UICheckboxNode, path: "enabled", value: boolean)
---@overload fun(self: UICheckboxNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UICheckboxNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UICheckboxNode, path: "label", value: string)
---@overload fun(self: UICheckboxNode, path: "checked", value: boolean)
---@overload fun(self: UICheckboxNode, path: "defaultChecked", value: boolean)
---@overload fun(self: UICheckboxNode, path: "accentColor", value: number[])
---@overload fun(self: UICheckboxNode, path: "boxSize", value: number)
function UICheckboxNode:set_property(path, value, y) end

---@class UIProgressBarNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field label string Caption shown next to the control.
---@field value number Progress (between min and max).
---@field minValue number Lowest value.
---@field maxValue number Highest value.
---@field fillColor number[] Colour of the filled part.
---@field direction "Horizontal"|"Vertical" Direction the bar fills.
---@field showText boolean Show the percentage.

---@alias UIProgressBarNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "label" # string - Caption shown next to the control.
---| "value" # number - Progress (between min and max).
---| "minValue" # number - Lowest value.
---| "maxValue" # number - Highest value.
---| "fillColor" # number[] - Colour of the filled part.
---| "direction" # "Horizontal"|"Vertical" - Direction the bar fills.
---| "showText" # boolean - Show the percentage.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UIProgressBarNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UIProgressBarNode, path: "position"): Vec2
---@overload fun(self: UIProgressBarNode, path: "scale"): Vec2
---@overload fun(self: UIProgressBarNode, path: "rotation"): number
---@overload fun(self: UIProgressBarNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIProgressBarNode, path: "zIndex"): integer
---@overload fun(self: UIProgressBarNode, path: "ySort"): boolean
---@overload fun(self: UIProgressBarNode, path: "ySortOffset"): number
---@overload fun(self: UIProgressBarNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIProgressBarNode, path: "paused"): boolean
---@overload fun(self: UIProgressBarNode, path: "enabled"): boolean
---@overload fun(self: UIProgressBarNode, path: "size"): Vec2
---@overload fun(self: UIProgressBarNode, path: "keyboardFocus"): boolean
---@overload fun(self: UIProgressBarNode, path: "label"): string
---@overload fun(self: UIProgressBarNode, path: "value"): number
---@overload fun(self: UIProgressBarNode, path: "minValue"): number
---@overload fun(self: UIProgressBarNode, path: "maxValue"): number
---@overload fun(self: UIProgressBarNode, path: "fillColor"): number[]
---@overload fun(self: UIProgressBarNode, path: "direction"): "Horizontal"|"Vertical"
---@overload fun(self: UIProgressBarNode, path: "showText"): boolean
function UIProgressBarNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UIProgressBarNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UIProgressBarNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIProgressBarNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIProgressBarNode, path: "rotation", value: number)
---@overload fun(self: UIProgressBarNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIProgressBarNode, path: "zIndex", value: integer)
---@overload fun(self: UIProgressBarNode, path: "ySort", value: boolean)
---@overload fun(self: UIProgressBarNode, path: "ySortOffset", value: number)
---@overload fun(self: UIProgressBarNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIProgressBarNode, path: "paused", value: boolean)
---@overload fun(self: UIProgressBarNode, path: "enabled", value: boolean)
---@overload fun(self: UIProgressBarNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIProgressBarNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UIProgressBarNode, path: "label", value: string)
---@overload fun(self: UIProgressBarNode, path: "value", value: number)
---@overload fun(self: UIProgressBarNode, path: "minValue", value: number)
---@overload fun(self: UIProgressBarNode, path: "maxValue", value: number)
---@overload fun(self: UIProgressBarNode, path: "fillColor", value: number[])
---@overload fun(self: UIProgressBarNode, path: "direction", value: "Horizontal"|"Vertical")
---@overload fun(self: UIProgressBarNode, path: "showText", value: boolean)
function UIProgressBarNode:set_property(path, value, y) end

---@class UITextInputNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field label string Caption shown next to the control.
---@field placeholder string Grey hint shown while the field is empty.
---@field text string What's typed: the starting text (saved), and what the player typed while running.
---@field labelWidth number Width reserved for the label (px); 0 = none.
---@field maxLength integer Most characters accepted.

---@alias UITextInputNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "label" # string - Caption shown next to the control.
---| "placeholder" # string - Grey hint shown while the field is empty.
---| "text" # string - What's typed: the starting text (saved), and what the player typed while running.
---| "labelWidth" # number - Width reserved for the label (px); 0 = none.
---| "maxLength" # integer - Most characters accepted.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UITextInputNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UITextInputNode, path: "position"): Vec2
---@overload fun(self: UITextInputNode, path: "scale"): Vec2
---@overload fun(self: UITextInputNode, path: "rotation"): number
---@overload fun(self: UITextInputNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UITextInputNode, path: "zIndex"): integer
---@overload fun(self: UITextInputNode, path: "ySort"): boolean
---@overload fun(self: UITextInputNode, path: "ySortOffset"): number
---@overload fun(self: UITextInputNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UITextInputNode, path: "paused"): boolean
---@overload fun(self: UITextInputNode, path: "enabled"): boolean
---@overload fun(self: UITextInputNode, path: "size"): Vec2
---@overload fun(self: UITextInputNode, path: "keyboardFocus"): boolean
---@overload fun(self: UITextInputNode, path: "label"): string
---@overload fun(self: UITextInputNode, path: "placeholder"): string
---@overload fun(self: UITextInputNode, path: "text"): string
---@overload fun(self: UITextInputNode, path: "labelWidth"): number
---@overload fun(self: UITextInputNode, path: "maxLength"): integer
function UITextInputNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UITextInputNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UITextInputNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITextInputNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITextInputNode, path: "rotation", value: number)
---@overload fun(self: UITextInputNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UITextInputNode, path: "zIndex", value: integer)
---@overload fun(self: UITextInputNode, path: "ySort", value: boolean)
---@overload fun(self: UITextInputNode, path: "ySortOffset", value: number)
---@overload fun(self: UITextInputNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UITextInputNode, path: "paused", value: boolean)
---@overload fun(self: UITextInputNode, path: "enabled", value: boolean)
---@overload fun(self: UITextInputNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITextInputNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UITextInputNode, path: "label", value: string)
---@overload fun(self: UITextInputNode, path: "placeholder", value: string)
---@overload fun(self: UITextInputNode, path: "text", value: string)
---@overload fun(self: UITextInputNode, path: "labelWidth", value: number)
---@overload fun(self: UITextInputNode, path: "maxLength", value: integer)
function UITextInputNode:set_property(path, value, y) end

---@class UIDropdownNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field label string Caption shown next to the control.
---@field items string[] The choices, one a line.
---@field selectedIndex integer Index of the selected item (-1 = none).
---@field defaultIndex integer Index restored by reset.
---@field labelWidth number Width reserved for the label (px); 0 = none.
---@field isOpen boolean List open now.

---@alias UIDropdownNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "label" # string - Caption shown next to the control.
---| "items" # string[] - The choices, one a line.
---| "selectedIndex" # integer - Index of the selected item (-1 = none).
---| "defaultIndex" # integer - Index restored by reset.
---| "labelWidth" # number - Width reserved for the label (px); 0 = none.
---| "isOpen" # boolean - List open now.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UIDropdownNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UIDropdownNode, path: "position"): Vec2
---@overload fun(self: UIDropdownNode, path: "scale"): Vec2
---@overload fun(self: UIDropdownNode, path: "rotation"): number
---@overload fun(self: UIDropdownNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIDropdownNode, path: "zIndex"): integer
---@overload fun(self: UIDropdownNode, path: "ySort"): boolean
---@overload fun(self: UIDropdownNode, path: "ySortOffset"): number
---@overload fun(self: UIDropdownNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIDropdownNode, path: "paused"): boolean
---@overload fun(self: UIDropdownNode, path: "enabled"): boolean
---@overload fun(self: UIDropdownNode, path: "size"): Vec2
---@overload fun(self: UIDropdownNode, path: "keyboardFocus"): boolean
---@overload fun(self: UIDropdownNode, path: "label"): string
---@overload fun(self: UIDropdownNode, path: "items"): string[]
---@overload fun(self: UIDropdownNode, path: "selectedIndex"): integer
---@overload fun(self: UIDropdownNode, path: "defaultIndex"): integer
---@overload fun(self: UIDropdownNode, path: "labelWidth"): number
---@overload fun(self: UIDropdownNode, path: "isOpen"): boolean
function UIDropdownNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UIDropdownNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UIDropdownNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIDropdownNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIDropdownNode, path: "rotation", value: number)
---@overload fun(self: UIDropdownNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIDropdownNode, path: "zIndex", value: integer)
---@overload fun(self: UIDropdownNode, path: "ySort", value: boolean)
---@overload fun(self: UIDropdownNode, path: "ySortOffset", value: number)
---@overload fun(self: UIDropdownNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIDropdownNode, path: "paused", value: boolean)
---@overload fun(self: UIDropdownNode, path: "enabled", value: boolean)
---@overload fun(self: UIDropdownNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIDropdownNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UIDropdownNode, path: "label", value: string)
---@overload fun(self: UIDropdownNode, path: "items", value: string[])
---@overload fun(self: UIDropdownNode, path: "selectedIndex", value: integer)
---@overload fun(self: UIDropdownNode, path: "defaultIndex", value: integer)
---@overload fun(self: UIDropdownNode, path: "labelWidth", value: number)
---@overload fun(self: UIDropdownNode, path: "isOpen", value: boolean)
function UIDropdownNode:set_property(path, value, y) end

---@class UIRadioGroupNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field label string Caption shown next to the control.
---@field labelWidth number Width reserved for the label (px); 0 = none.
---@field options string[] The options, one a line.
---@field selectedIndex integer Index of the selected item (-1 = none).
---@field defaultIndex integer Index restored by reset.
---@field horizontal boolean Options in a row (else a column).

---@alias UIRadioGroupNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "label" # string - Caption shown next to the control.
---| "labelWidth" # number - Width reserved for the label (px); 0 = none.
---| "options" # string[] - The options, one a line.
---| "selectedIndex" # integer - Index of the selected item (-1 = none).
---| "defaultIndex" # integer - Index restored by reset.
---| "horizontal" # boolean - Options in a row (else a column).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UIRadioGroupNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UIRadioGroupNode, path: "position"): Vec2
---@overload fun(self: UIRadioGroupNode, path: "scale"): Vec2
---@overload fun(self: UIRadioGroupNode, path: "rotation"): number
---@overload fun(self: UIRadioGroupNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIRadioGroupNode, path: "zIndex"): integer
---@overload fun(self: UIRadioGroupNode, path: "ySort"): boolean
---@overload fun(self: UIRadioGroupNode, path: "ySortOffset"): number
---@overload fun(self: UIRadioGroupNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIRadioGroupNode, path: "paused"): boolean
---@overload fun(self: UIRadioGroupNode, path: "enabled"): boolean
---@overload fun(self: UIRadioGroupNode, path: "size"): Vec2
---@overload fun(self: UIRadioGroupNode, path: "keyboardFocus"): boolean
---@overload fun(self: UIRadioGroupNode, path: "label"): string
---@overload fun(self: UIRadioGroupNode, path: "labelWidth"): number
---@overload fun(self: UIRadioGroupNode, path: "options"): string[]
---@overload fun(self: UIRadioGroupNode, path: "selectedIndex"): integer
---@overload fun(self: UIRadioGroupNode, path: "defaultIndex"): integer
---@overload fun(self: UIRadioGroupNode, path: "horizontal"): boolean
function UIRadioGroupNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UIRadioGroupNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UIRadioGroupNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIRadioGroupNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIRadioGroupNode, path: "rotation", value: number)
---@overload fun(self: UIRadioGroupNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIRadioGroupNode, path: "zIndex", value: integer)
---@overload fun(self: UIRadioGroupNode, path: "ySort", value: boolean)
---@overload fun(self: UIRadioGroupNode, path: "ySortOffset", value: number)
---@overload fun(self: UIRadioGroupNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIRadioGroupNode, path: "paused", value: boolean)
---@overload fun(self: UIRadioGroupNode, path: "enabled", value: boolean)
---@overload fun(self: UIRadioGroupNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIRadioGroupNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UIRadioGroupNode, path: "label", value: string)
---@overload fun(self: UIRadioGroupNode, path: "labelWidth", value: number)
---@overload fun(self: UIRadioGroupNode, path: "options", value: string[])
---@overload fun(self: UIRadioGroupNode, path: "selectedIndex", value: integer)
---@overload fun(self: UIRadioGroupNode, path: "defaultIndex", value: integer)
---@overload fun(self: UIRadioGroupNode, path: "horizontal", value: boolean)
function UIRadioGroupNode:set_property(path, value, y) end

---@class UIToggleSwitchNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field label string Caption shown next to the control.
---@field active boolean Switched on.

---@alias UIToggleSwitchNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "label" # string - Caption shown next to the control.
---| "active" # boolean - Switched on.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UIToggleSwitchNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UIToggleSwitchNode, path: "position"): Vec2
---@overload fun(self: UIToggleSwitchNode, path: "scale"): Vec2
---@overload fun(self: UIToggleSwitchNode, path: "rotation"): number
---@overload fun(self: UIToggleSwitchNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIToggleSwitchNode, path: "zIndex"): integer
---@overload fun(self: UIToggleSwitchNode, path: "ySort"): boolean
---@overload fun(self: UIToggleSwitchNode, path: "ySortOffset"): number
---@overload fun(self: UIToggleSwitchNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIToggleSwitchNode, path: "paused"): boolean
---@overload fun(self: UIToggleSwitchNode, path: "enabled"): boolean
---@overload fun(self: UIToggleSwitchNode, path: "size"): Vec2
---@overload fun(self: UIToggleSwitchNode, path: "keyboardFocus"): boolean
---@overload fun(self: UIToggleSwitchNode, path: "label"): string
---@overload fun(self: UIToggleSwitchNode, path: "active"): boolean
function UIToggleSwitchNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UIToggleSwitchNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UIToggleSwitchNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIToggleSwitchNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIToggleSwitchNode, path: "rotation", value: number)
---@overload fun(self: UIToggleSwitchNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIToggleSwitchNode, path: "zIndex", value: integer)
---@overload fun(self: UIToggleSwitchNode, path: "ySort", value: boolean)
---@overload fun(self: UIToggleSwitchNode, path: "ySortOffset", value: number)
---@overload fun(self: UIToggleSwitchNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIToggleSwitchNode, path: "paused", value: boolean)
---@overload fun(self: UIToggleSwitchNode, path: "enabled", value: boolean)
---@overload fun(self: UIToggleSwitchNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIToggleSwitchNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UIToggleSwitchNode, path: "label", value: string)
---@overload fun(self: UIToggleSwitchNode, path: "active", value: boolean)
function UIToggleSwitchNode:set_property(path, value, y) end

---@class UIKnobNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field label string Caption shown next to the control.
---@field value number Current value (between min and max).
---@field minValue number Lowest value.
---@field maxValue number Highest value.
---@field defaultValue number Value a right-click restores (a slider's reset button too).

---@alias UIKnobNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "label" # string - Caption shown next to the control.
---| "value" # number - Current value (between min and max).
---| "minValue" # number - Lowest value.
---| "maxValue" # number - Highest value.
---| "defaultValue" # number - Value a right-click restores (a slider's reset button too).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UIKnobNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UIKnobNode, path: "position"): Vec2
---@overload fun(self: UIKnobNode, path: "scale"): Vec2
---@overload fun(self: UIKnobNode, path: "rotation"): number
---@overload fun(self: UIKnobNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIKnobNode, path: "zIndex"): integer
---@overload fun(self: UIKnobNode, path: "ySort"): boolean
---@overload fun(self: UIKnobNode, path: "ySortOffset"): number
---@overload fun(self: UIKnobNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIKnobNode, path: "paused"): boolean
---@overload fun(self: UIKnobNode, path: "enabled"): boolean
---@overload fun(self: UIKnobNode, path: "size"): Vec2
---@overload fun(self: UIKnobNode, path: "keyboardFocus"): boolean
---@overload fun(self: UIKnobNode, path: "label"): string
---@overload fun(self: UIKnobNode, path: "value"): number
---@overload fun(self: UIKnobNode, path: "minValue"): number
---@overload fun(self: UIKnobNode, path: "maxValue"): number
---@overload fun(self: UIKnobNode, path: "defaultValue"): number
function UIKnobNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UIKnobNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UIKnobNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIKnobNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIKnobNode, path: "rotation", value: number)
---@overload fun(self: UIKnobNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIKnobNode, path: "zIndex", value: integer)
---@overload fun(self: UIKnobNode, path: "ySort", value: boolean)
---@overload fun(self: UIKnobNode, path: "ySortOffset", value: number)
---@overload fun(self: UIKnobNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIKnobNode, path: "paused", value: boolean)
---@overload fun(self: UIKnobNode, path: "enabled", value: boolean)
---@overload fun(self: UIKnobNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIKnobNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UIKnobNode, path: "label", value: string)
---@overload fun(self: UIKnobNode, path: "value", value: number)
---@overload fun(self: UIKnobNode, path: "minValue", value: number)
---@overload fun(self: UIKnobNode, path: "maxValue", value: number)
---@overload fun(self: UIKnobNode, path: "defaultValue", value: number)
function UIKnobNode:set_property(path, value, y) end

---@class UINotchedSliderNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field label string Caption shown next to the control.
---@field value number Current value.
---@field minValue number Lowest value.
---@field maxValue number Highest value.
---@field numNotches integer Number of notch marks.
---@field notchLabels string[] A label under each notch, one a line (left to right).
---@field snapToNotches boolean Snap the value to the notches.
---@field orientation "Horizontal"|"Vertical" Horizontal or vertical.

---@alias UINotchedSliderNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "label" # string - Caption shown next to the control.
---| "value" # number - Current value.
---| "minValue" # number - Lowest value.
---| "maxValue" # number - Highest value.
---| "numNotches" # integer - Number of notch marks.
---| "notchLabels" # string[] - A label under each notch, one a line (left to right).
---| "snapToNotches" # boolean - Snap the value to the notches.
---| "orientation" # "Horizontal"|"Vertical" - Horizontal or vertical.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UINotchedSliderNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UINotchedSliderNode, path: "position"): Vec2
---@overload fun(self: UINotchedSliderNode, path: "scale"): Vec2
---@overload fun(self: UINotchedSliderNode, path: "rotation"): number
---@overload fun(self: UINotchedSliderNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UINotchedSliderNode, path: "zIndex"): integer
---@overload fun(self: UINotchedSliderNode, path: "ySort"): boolean
---@overload fun(self: UINotchedSliderNode, path: "ySortOffset"): number
---@overload fun(self: UINotchedSliderNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UINotchedSliderNode, path: "paused"): boolean
---@overload fun(self: UINotchedSliderNode, path: "enabled"): boolean
---@overload fun(self: UINotchedSliderNode, path: "size"): Vec2
---@overload fun(self: UINotchedSliderNode, path: "keyboardFocus"): boolean
---@overload fun(self: UINotchedSliderNode, path: "label"): string
---@overload fun(self: UINotchedSliderNode, path: "value"): number
---@overload fun(self: UINotchedSliderNode, path: "minValue"): number
---@overload fun(self: UINotchedSliderNode, path: "maxValue"): number
---@overload fun(self: UINotchedSliderNode, path: "numNotches"): integer
---@overload fun(self: UINotchedSliderNode, path: "notchLabels"): string[]
---@overload fun(self: UINotchedSliderNode, path: "snapToNotches"): boolean
---@overload fun(self: UINotchedSliderNode, path: "orientation"): "Horizontal"|"Vertical"
function UINotchedSliderNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UINotchedSliderNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UINotchedSliderNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UINotchedSliderNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UINotchedSliderNode, path: "rotation", value: number)
---@overload fun(self: UINotchedSliderNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UINotchedSliderNode, path: "zIndex", value: integer)
---@overload fun(self: UINotchedSliderNode, path: "ySort", value: boolean)
---@overload fun(self: UINotchedSliderNode, path: "ySortOffset", value: number)
---@overload fun(self: UINotchedSliderNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UINotchedSliderNode, path: "paused", value: boolean)
---@overload fun(self: UINotchedSliderNode, path: "enabled", value: boolean)
---@overload fun(self: UINotchedSliderNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UINotchedSliderNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UINotchedSliderNode, path: "label", value: string)
---@overload fun(self: UINotchedSliderNode, path: "value", value: number)
---@overload fun(self: UINotchedSliderNode, path: "minValue", value: number)
---@overload fun(self: UINotchedSliderNode, path: "maxValue", value: number)
---@overload fun(self: UINotchedSliderNode, path: "numNotches", value: integer)
---@overload fun(self: UINotchedSliderNode, path: "notchLabels", value: string[])
---@overload fun(self: UINotchedSliderNode, path: "snapToNotches", value: boolean)
---@overload fun(self: UINotchedSliderNode, path: "orientation", value: "Horizontal"|"Vertical")
function UINotchedSliderNode:set_property(path, value, y) end

---@class UIVolumeFaderNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field label string Caption shown next to the control.
---@field valueDb number Level (dB).
---@field minDb number Bottom of the fader (dB).
---@field maxDb number Top of the fader (dB).
---@field defaultDb number Level restored by reset (dB).

---@alias UIVolumeFaderNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "label" # string - Caption shown next to the control.
---| "valueDb" # number - Level (dB).
---| "minDb" # number - Bottom of the fader (dB).
---| "maxDb" # number - Top of the fader (dB).
---| "defaultDb" # number - Level restored by reset (dB).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UIVolumeFaderNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UIVolumeFaderNode, path: "position"): Vec2
---@overload fun(self: UIVolumeFaderNode, path: "scale"): Vec2
---@overload fun(self: UIVolumeFaderNode, path: "rotation"): number
---@overload fun(self: UIVolumeFaderNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIVolumeFaderNode, path: "zIndex"): integer
---@overload fun(self: UIVolumeFaderNode, path: "ySort"): boolean
---@overload fun(self: UIVolumeFaderNode, path: "ySortOffset"): number
---@overload fun(self: UIVolumeFaderNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIVolumeFaderNode, path: "paused"): boolean
---@overload fun(self: UIVolumeFaderNode, path: "enabled"): boolean
---@overload fun(self: UIVolumeFaderNode, path: "size"): Vec2
---@overload fun(self: UIVolumeFaderNode, path: "keyboardFocus"): boolean
---@overload fun(self: UIVolumeFaderNode, path: "label"): string
---@overload fun(self: UIVolumeFaderNode, path: "valueDb"): number
---@overload fun(self: UIVolumeFaderNode, path: "minDb"): number
---@overload fun(self: UIVolumeFaderNode, path: "maxDb"): number
---@overload fun(self: UIVolumeFaderNode, path: "defaultDb"): number
function UIVolumeFaderNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UIVolumeFaderNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UIVolumeFaderNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIVolumeFaderNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIVolumeFaderNode, path: "rotation", value: number)
---@overload fun(self: UIVolumeFaderNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIVolumeFaderNode, path: "zIndex", value: integer)
---@overload fun(self: UIVolumeFaderNode, path: "ySort", value: boolean)
---@overload fun(self: UIVolumeFaderNode, path: "ySortOffset", value: number)
---@overload fun(self: UIVolumeFaderNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIVolumeFaderNode, path: "paused", value: boolean)
---@overload fun(self: UIVolumeFaderNode, path: "enabled", value: boolean)
---@overload fun(self: UIVolumeFaderNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIVolumeFaderNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UIVolumeFaderNode, path: "label", value: string)
---@overload fun(self: UIVolumeFaderNode, path: "valueDb", value: number)
---@overload fun(self: UIVolumeFaderNode, path: "minDb", value: number)
---@overload fun(self: UIVolumeFaderNode, path: "maxDb", value: number)
---@overload fun(self: UIVolumeFaderNode, path: "defaultDb", value: number)
function UIVolumeFaderNode:set_property(path, value, y) end

---@class UIVolumeMeterNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field label string Caption shown next to the control.
---@field levelL number Left channel level (dB).
---@field levelR number Right channel level (dB).
---@field minDb number Bottom of the meter (dB).
---@field maxDb number Top of the meter (dB).
---@field orientation "Vertical"|"Horizontal" Horizontal or vertical.

---@alias UIVolumeMeterNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "label" # string - Caption shown next to the control.
---| "levelL" # number - Left channel level (dB).
---| "levelR" # number - Right channel level (dB).
---| "minDb" # number - Bottom of the meter (dB).
---| "maxDb" # number - Top of the meter (dB).
---| "orientation" # "Vertical"|"Horizontal" - Horizontal or vertical.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UIVolumeMeterNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UIVolumeMeterNode, path: "position"): Vec2
---@overload fun(self: UIVolumeMeterNode, path: "scale"): Vec2
---@overload fun(self: UIVolumeMeterNode, path: "rotation"): number
---@overload fun(self: UIVolumeMeterNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIVolumeMeterNode, path: "zIndex"): integer
---@overload fun(self: UIVolumeMeterNode, path: "ySort"): boolean
---@overload fun(self: UIVolumeMeterNode, path: "ySortOffset"): number
---@overload fun(self: UIVolumeMeterNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIVolumeMeterNode, path: "paused"): boolean
---@overload fun(self: UIVolumeMeterNode, path: "enabled"): boolean
---@overload fun(self: UIVolumeMeterNode, path: "size"): Vec2
---@overload fun(self: UIVolumeMeterNode, path: "keyboardFocus"): boolean
---@overload fun(self: UIVolumeMeterNode, path: "label"): string
---@overload fun(self: UIVolumeMeterNode, path: "levelL"): number
---@overload fun(self: UIVolumeMeterNode, path: "levelR"): number
---@overload fun(self: UIVolumeMeterNode, path: "minDb"): number
---@overload fun(self: UIVolumeMeterNode, path: "maxDb"): number
---@overload fun(self: UIVolumeMeterNode, path: "orientation"): "Vertical"|"Horizontal"
function UIVolumeMeterNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UIVolumeMeterNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UIVolumeMeterNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIVolumeMeterNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIVolumeMeterNode, path: "rotation", value: number)
---@overload fun(self: UIVolumeMeterNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIVolumeMeterNode, path: "zIndex", value: integer)
---@overload fun(self: UIVolumeMeterNode, path: "ySort", value: boolean)
---@overload fun(self: UIVolumeMeterNode, path: "ySortOffset", value: number)
---@overload fun(self: UIVolumeMeterNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIVolumeMeterNode, path: "paused", value: boolean)
---@overload fun(self: UIVolumeMeterNode, path: "enabled", value: boolean)
---@overload fun(self: UIVolumeMeterNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIVolumeMeterNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UIVolumeMeterNode, path: "label", value: string)
---@overload fun(self: UIVolumeMeterNode, path: "levelL", value: number)
---@overload fun(self: UIVolumeMeterNode, path: "levelR", value: number)
---@overload fun(self: UIVolumeMeterNode, path: "minDb", value: number)
---@overload fun(self: UIVolumeMeterNode, path: "maxDb", value: number)
---@overload fun(self: UIVolumeMeterNode, path: "orientation", value: "Vertical"|"Horizontal")
function UIVolumeMeterNode:set_property(path, value, y) end

---@class UISeparatorNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field label string Text at the start of the line ("" = a plain line); with text it's at least 18 px tall.
---@field lineColor number[] Colour of the line.

---@alias UISeparatorNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "label" # string - Text at the start of the line ("" = a plain line); with text it's at least 18 px tall.
---| "lineColor" # number[] - Colour of the line.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UISeparatorNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UISeparatorNode, path: "position"): Vec2
---@overload fun(self: UISeparatorNode, path: "scale"): Vec2
---@overload fun(self: UISeparatorNode, path: "rotation"): number
---@overload fun(self: UISeparatorNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UISeparatorNode, path: "zIndex"): integer
---@overload fun(self: UISeparatorNode, path: "ySort"): boolean
---@overload fun(self: UISeparatorNode, path: "ySortOffset"): number
---@overload fun(self: UISeparatorNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UISeparatorNode, path: "paused"): boolean
---@overload fun(self: UISeparatorNode, path: "enabled"): boolean
---@overload fun(self: UISeparatorNode, path: "size"): Vec2
---@overload fun(self: UISeparatorNode, path: "keyboardFocus"): boolean
---@overload fun(self: UISeparatorNode, path: "label"): string
---@overload fun(self: UISeparatorNode, path: "lineColor"): number[]
function UISeparatorNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UISeparatorNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UISeparatorNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UISeparatorNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UISeparatorNode, path: "rotation", value: number)
---@overload fun(self: UISeparatorNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UISeparatorNode, path: "zIndex", value: integer)
---@overload fun(self: UISeparatorNode, path: "ySort", value: boolean)
---@overload fun(self: UISeparatorNode, path: "ySortOffset", value: number)
---@overload fun(self: UISeparatorNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UISeparatorNode, path: "paused", value: boolean)
---@overload fun(self: UISeparatorNode, path: "enabled", value: boolean)
---@overload fun(self: UISeparatorNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UISeparatorNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UISeparatorNode, path: "label", value: string)
---@overload fun(self: UISeparatorNode, path: "lineColor", value: number[])
function UISeparatorNode:set_property(path, value, y) end

---@class UIXYPlotNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field title string Heading above the plot.
---@field xLabel string Label under the x axis.
---@field yLabel string Label beside the y axis.
---@field series1Name string Name of the first series (the legend).
---@field series2Name string Name of the second series (the legend).
---@field xMin number Left end of the X axis.
---@field xMax number Right end of the X axis.
---@field yMin number Bottom of the Y axis.
---@field yMax number Top of the Y axis.
---@field autoScaleX boolean Fit the X axis to the data.
---@field autoScaleY boolean Fit the Y axis to the data.
---@field showGrid boolean Draw grid lines.
---@field showPoints boolean Mark each data point.
---@field showCrosshair boolean Crosshair with the value under the mouse.
---@field lineColor number[] Colour of the line.
---@field secondaryLineColor number[] Colour of the second series.
---@field gridColor number[] Grid line colour.
---@field points string[] The first series: one point a line, "x, y".
---@field secondaryPoints string[] The second series: one point a line, "x, y".

---@alias UIXYPlotNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "title" # string - Heading above the plot.
---| "xLabel" # string - Label under the x axis.
---| "yLabel" # string - Label beside the y axis.
---| "series1Name" # string - Name of the first series (the legend).
---| "series2Name" # string - Name of the second series (the legend).
---| "xMin" # number - Left end of the X axis.
---| "xMax" # number - Right end of the X axis.
---| "yMin" # number - Bottom of the Y axis.
---| "yMax" # number - Top of the Y axis.
---| "autoScaleX" # boolean - Fit the X axis to the data.
---| "autoScaleY" # boolean - Fit the Y axis to the data.
---| "showGrid" # boolean - Draw grid lines.
---| "showPoints" # boolean - Mark each data point.
---| "showCrosshair" # boolean - Crosshair with the value under the mouse.
---| "lineColor" # number[] - Colour of the line.
---| "secondaryLineColor" # number[] - Colour of the second series.
---| "gridColor" # number[] - Grid line colour.
---| "points" # string[] - The first series: one point a line, "x, y".
---| "secondaryPoints" # string[] - The second series: one point a line, "x, y".

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UIXYPlotNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UIXYPlotNode, path: "position"): Vec2
---@overload fun(self: UIXYPlotNode, path: "scale"): Vec2
---@overload fun(self: UIXYPlotNode, path: "rotation"): number
---@overload fun(self: UIXYPlotNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIXYPlotNode, path: "zIndex"): integer
---@overload fun(self: UIXYPlotNode, path: "ySort"): boolean
---@overload fun(self: UIXYPlotNode, path: "ySortOffset"): number
---@overload fun(self: UIXYPlotNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIXYPlotNode, path: "paused"): boolean
---@overload fun(self: UIXYPlotNode, path: "enabled"): boolean
---@overload fun(self: UIXYPlotNode, path: "size"): Vec2
---@overload fun(self: UIXYPlotNode, path: "keyboardFocus"): boolean
---@overload fun(self: UIXYPlotNode, path: "title"): string
---@overload fun(self: UIXYPlotNode, path: "xLabel"): string
---@overload fun(self: UIXYPlotNode, path: "yLabel"): string
---@overload fun(self: UIXYPlotNode, path: "series1Name"): string
---@overload fun(self: UIXYPlotNode, path: "series2Name"): string
---@overload fun(self: UIXYPlotNode, path: "xMin"): number
---@overload fun(self: UIXYPlotNode, path: "xMax"): number
---@overload fun(self: UIXYPlotNode, path: "yMin"): number
---@overload fun(self: UIXYPlotNode, path: "yMax"): number
---@overload fun(self: UIXYPlotNode, path: "autoScaleX"): boolean
---@overload fun(self: UIXYPlotNode, path: "autoScaleY"): boolean
---@overload fun(self: UIXYPlotNode, path: "showGrid"): boolean
---@overload fun(self: UIXYPlotNode, path: "showPoints"): boolean
---@overload fun(self: UIXYPlotNode, path: "showCrosshair"): boolean
---@overload fun(self: UIXYPlotNode, path: "lineColor"): number[]
---@overload fun(self: UIXYPlotNode, path: "secondaryLineColor"): number[]
---@overload fun(self: UIXYPlotNode, path: "gridColor"): number[]
---@overload fun(self: UIXYPlotNode, path: "points"): string[]
---@overload fun(self: UIXYPlotNode, path: "secondaryPoints"): string[]
function UIXYPlotNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UIXYPlotNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UIXYPlotNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIXYPlotNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIXYPlotNode, path: "rotation", value: number)
---@overload fun(self: UIXYPlotNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIXYPlotNode, path: "zIndex", value: integer)
---@overload fun(self: UIXYPlotNode, path: "ySort", value: boolean)
---@overload fun(self: UIXYPlotNode, path: "ySortOffset", value: number)
---@overload fun(self: UIXYPlotNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIXYPlotNode, path: "paused", value: boolean)
---@overload fun(self: UIXYPlotNode, path: "enabled", value: boolean)
---@overload fun(self: UIXYPlotNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIXYPlotNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UIXYPlotNode, path: "title", value: string)
---@overload fun(self: UIXYPlotNode, path: "xLabel", value: string)
---@overload fun(self: UIXYPlotNode, path: "yLabel", value: string)
---@overload fun(self: UIXYPlotNode, path: "series1Name", value: string)
---@overload fun(self: UIXYPlotNode, path: "series2Name", value: string)
---@overload fun(self: UIXYPlotNode, path: "xMin", value: number)
---@overload fun(self: UIXYPlotNode, path: "xMax", value: number)
---@overload fun(self: UIXYPlotNode, path: "yMin", value: number)
---@overload fun(self: UIXYPlotNode, path: "yMax", value: number)
---@overload fun(self: UIXYPlotNode, path: "autoScaleX", value: boolean)
---@overload fun(self: UIXYPlotNode, path: "autoScaleY", value: boolean)
---@overload fun(self: UIXYPlotNode, path: "showGrid", value: boolean)
---@overload fun(self: UIXYPlotNode, path: "showPoints", value: boolean)
---@overload fun(self: UIXYPlotNode, path: "showCrosshair", value: boolean)
---@overload fun(self: UIXYPlotNode, path: "lineColor", value: number[])
---@overload fun(self: UIXYPlotNode, path: "secondaryLineColor", value: number[])
---@overload fun(self: UIXYPlotNode, path: "gridColor", value: number[])
---@overload fun(self: UIXYPlotNode, path: "points", value: string[])
---@overload fun(self: UIXYPlotNode, path: "secondaryPoints", value: string[])
function UIXYPlotNode:set_property(path, value, y) end

---@class UIListViewNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field items string[] The rows, one a line.
---@field selectedIndex integer Index of the selected item (-1 = none).
---@field itemHeight number Height of each row (px).

---@alias UIListViewNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "items" # string[] - The rows, one a line.
---| "selectedIndex" # integer - Index of the selected item (-1 = none).
---| "itemHeight" # number - Height of each row (px).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UIListViewNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UIListViewNode, path: "position"): Vec2
---@overload fun(self: UIListViewNode, path: "scale"): Vec2
---@overload fun(self: UIListViewNode, path: "rotation"): number
---@overload fun(self: UIListViewNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIListViewNode, path: "zIndex"): integer
---@overload fun(self: UIListViewNode, path: "ySort"): boolean
---@overload fun(self: UIListViewNode, path: "ySortOffset"): number
---@overload fun(self: UIListViewNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIListViewNode, path: "paused"): boolean
---@overload fun(self: UIListViewNode, path: "enabled"): boolean
---@overload fun(self: UIListViewNode, path: "size"): Vec2
---@overload fun(self: UIListViewNode, path: "keyboardFocus"): boolean
---@overload fun(self: UIListViewNode, path: "items"): string[]
---@overload fun(self: UIListViewNode, path: "selectedIndex"): integer
---@overload fun(self: UIListViewNode, path: "itemHeight"): number
function UIListViewNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UIListViewNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UIListViewNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIListViewNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIListViewNode, path: "rotation", value: number)
---@overload fun(self: UIListViewNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIListViewNode, path: "zIndex", value: integer)
---@overload fun(self: UIListViewNode, path: "ySort", value: boolean)
---@overload fun(self: UIListViewNode, path: "ySortOffset", value: number)
---@overload fun(self: UIListViewNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIListViewNode, path: "paused", value: boolean)
---@overload fun(self: UIListViewNode, path: "enabled", value: boolean)
---@overload fun(self: UIListViewNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIListViewNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UIListViewNode, path: "items", value: string[])
---@overload fun(self: UIListViewNode, path: "selectedIndex", value: integer)
---@overload fun(self: UIListViewNode, path: "itemHeight", value: number)
function UIListViewNode:set_property(path, value, y) end

---@class UITreeViewNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field selectedId integer Id of the selected item (-1 = none).
---@field itemHeight number Height of each row (px).
---@field items string[] The items, one a line; 2 spaces at the start nest one under the item above.

---@alias UITreeViewNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "selectedId" # integer - Id of the selected item (-1 = none).
---| "itemHeight" # number - Height of each row (px).
---| "items" # string[] - The items, one a line; 2 spaces at the start nest one under the item above.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UITreeViewNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UITreeViewNode, path: "position"): Vec2
---@overload fun(self: UITreeViewNode, path: "scale"): Vec2
---@overload fun(self: UITreeViewNode, path: "rotation"): number
---@overload fun(self: UITreeViewNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UITreeViewNode, path: "zIndex"): integer
---@overload fun(self: UITreeViewNode, path: "ySort"): boolean
---@overload fun(self: UITreeViewNode, path: "ySortOffset"): number
---@overload fun(self: UITreeViewNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UITreeViewNode, path: "paused"): boolean
---@overload fun(self: UITreeViewNode, path: "enabled"): boolean
---@overload fun(self: UITreeViewNode, path: "size"): Vec2
---@overload fun(self: UITreeViewNode, path: "keyboardFocus"): boolean
---@overload fun(self: UITreeViewNode, path: "selectedId"): integer
---@overload fun(self: UITreeViewNode, path: "itemHeight"): number
---@overload fun(self: UITreeViewNode, path: "items"): string[]
function UITreeViewNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UITreeViewNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UITreeViewNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITreeViewNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITreeViewNode, path: "rotation", value: number)
---@overload fun(self: UITreeViewNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UITreeViewNode, path: "zIndex", value: integer)
---@overload fun(self: UITreeViewNode, path: "ySort", value: boolean)
---@overload fun(self: UITreeViewNode, path: "ySortOffset", value: number)
---@overload fun(self: UITreeViewNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UITreeViewNode, path: "paused", value: boolean)
---@overload fun(self: UITreeViewNode, path: "enabled", value: boolean)
---@overload fun(self: UITreeViewNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITreeViewNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UITreeViewNode, path: "selectedId", value: integer)
---@overload fun(self: UITreeViewNode, path: "itemHeight", value: number)
---@overload fun(self: UITreeViewNode, path: "items", value: string[])
function UITreeViewNode:set_property(path, value, y) end

---@class UIUnorderedListNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field selectedIndex integer Index of the selected item (-1 = none).
---@field defaultBullet "Disc"|"Circle"|"Square"|"Dash"|"Arrow" Bullet style for items without their own.
---@field itemHeight number Height of each row (px).
---@field items string[] The items, one a line; 2 spaces at the start nest it a level deeper.

---@alias UIUnorderedListNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "selectedIndex" # integer - Index of the selected item (-1 = none).
---| "defaultBullet" # "Disc"|"Circle"|"Square"|"Dash"|"Arrow" - Bullet style for items without their own.
---| "itemHeight" # number - Height of each row (px).
---| "items" # string[] - The items, one a line; 2 spaces at the start nest it a level deeper.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UIUnorderedListNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UIUnorderedListNode, path: "position"): Vec2
---@overload fun(self: UIUnorderedListNode, path: "scale"): Vec2
---@overload fun(self: UIUnorderedListNode, path: "rotation"): number
---@overload fun(self: UIUnorderedListNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIUnorderedListNode, path: "zIndex"): integer
---@overload fun(self: UIUnorderedListNode, path: "ySort"): boolean
---@overload fun(self: UIUnorderedListNode, path: "ySortOffset"): number
---@overload fun(self: UIUnorderedListNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIUnorderedListNode, path: "paused"): boolean
---@overload fun(self: UIUnorderedListNode, path: "enabled"): boolean
---@overload fun(self: UIUnorderedListNode, path: "size"): Vec2
---@overload fun(self: UIUnorderedListNode, path: "keyboardFocus"): boolean
---@overload fun(self: UIUnorderedListNode, path: "selectedIndex"): integer
---@overload fun(self: UIUnorderedListNode, path: "defaultBullet"): "Disc"|"Circle"|"Square"|"Dash"|"Arrow"
---@overload fun(self: UIUnorderedListNode, path: "itemHeight"): number
---@overload fun(self: UIUnorderedListNode, path: "items"): string[]
function UIUnorderedListNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UIUnorderedListNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UIUnorderedListNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIUnorderedListNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIUnorderedListNode, path: "rotation", value: number)
---@overload fun(self: UIUnorderedListNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIUnorderedListNode, path: "zIndex", value: integer)
---@overload fun(self: UIUnorderedListNode, path: "ySort", value: boolean)
---@overload fun(self: UIUnorderedListNode, path: "ySortOffset", value: number)
---@overload fun(self: UIUnorderedListNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIUnorderedListNode, path: "paused", value: boolean)
---@overload fun(self: UIUnorderedListNode, path: "enabled", value: boolean)
---@overload fun(self: UIUnorderedListNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIUnorderedListNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UIUnorderedListNode, path: "selectedIndex", value: integer)
---@overload fun(self: UIUnorderedListNode, path: "defaultBullet", value: "Disc"|"Circle"|"Square"|"Dash"|"Arrow")
---@overload fun(self: UIUnorderedListNode, path: "itemHeight", value: number)
---@overload fun(self: UIUnorderedListNode, path: "items", value: string[])
function UIUnorderedListNode:set_property(path, value, y) end

---@class UIOrderedListNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field selectedIndex integer Index of the selected item (-1 = none).
---@field numbering "Decimal"|"AlphaLower"|"AlphaUpper"|"RomanLower"|"RomanUpper" Numbering style (1, a, i...).
---@field startNumber integer Number of the first item.
---@field itemHeight number Height of each row (px).
---@field items string[] The items, one a line; 2 spaces at the start nest it a level deeper.

---@alias UIOrderedListNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "selectedIndex" # integer - Index of the selected item (-1 = none).
---| "numbering" # "Decimal"|"AlphaLower"|"AlphaUpper"|"RomanLower"|"RomanUpper" - Numbering style (1, a, i...).
---| "startNumber" # integer - Number of the first item.
---| "itemHeight" # number - Height of each row (px).
---| "items" # string[] - The items, one a line; 2 spaces at the start nest it a level deeper.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UIOrderedListNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UIOrderedListNode, path: "position"): Vec2
---@overload fun(self: UIOrderedListNode, path: "scale"): Vec2
---@overload fun(self: UIOrderedListNode, path: "rotation"): number
---@overload fun(self: UIOrderedListNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIOrderedListNode, path: "zIndex"): integer
---@overload fun(self: UIOrderedListNode, path: "ySort"): boolean
---@overload fun(self: UIOrderedListNode, path: "ySortOffset"): number
---@overload fun(self: UIOrderedListNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIOrderedListNode, path: "paused"): boolean
---@overload fun(self: UIOrderedListNode, path: "enabled"): boolean
---@overload fun(self: UIOrderedListNode, path: "size"): Vec2
---@overload fun(self: UIOrderedListNode, path: "keyboardFocus"): boolean
---@overload fun(self: UIOrderedListNode, path: "selectedIndex"): integer
---@overload fun(self: UIOrderedListNode, path: "numbering"): "Decimal"|"AlphaLower"|"AlphaUpper"|"RomanLower"|"RomanUpper"
---@overload fun(self: UIOrderedListNode, path: "startNumber"): integer
---@overload fun(self: UIOrderedListNode, path: "itemHeight"): number
---@overload fun(self: UIOrderedListNode, path: "items"): string[]
function UIOrderedListNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UIOrderedListNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UIOrderedListNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIOrderedListNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIOrderedListNode, path: "rotation", value: number)
---@overload fun(self: UIOrderedListNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIOrderedListNode, path: "zIndex", value: integer)
---@overload fun(self: UIOrderedListNode, path: "ySort", value: boolean)
---@overload fun(self: UIOrderedListNode, path: "ySortOffset", value: number)
---@overload fun(self: UIOrderedListNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIOrderedListNode, path: "paused", value: boolean)
---@overload fun(self: UIOrderedListNode, path: "enabled", value: boolean)
---@overload fun(self: UIOrderedListNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIOrderedListNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UIOrderedListNode, path: "selectedIndex", value: integer)
---@overload fun(self: UIOrderedListNode, path: "numbering", value: "Decimal"|"AlphaLower"|"AlphaUpper"|"RomanLower"|"RomanUpper")
---@overload fun(self: UIOrderedListNode, path: "startNumber", value: integer)
---@overload fun(self: UIOrderedListNode, path: "itemHeight", value: number)
---@overload fun(self: UIOrderedListNode, path: "items", value: string[])
function UIOrderedListNode:set_property(path, value, y) end

---@class UITableNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field selectedRow integer Index of the selected row.
---@field sortColumn integer Column the rows are sorted by.
---@field sortAscending boolean Sort ascending (else descending).
---@field headerHeight number Height of the header (px).
---@field rowHeight number Height of each row (px).
---@field columns string[] The columns, one a line: Title, or Title|width (width <= 1: a share of the table).
---@field rows string[] The rows, one a line, cells split by |.

---@alias UITableNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "selectedRow" # integer - Index of the selected row.
---| "sortColumn" # integer - Column the rows are sorted by.
---| "sortAscending" # boolean - Sort ascending (else descending).
---| "headerHeight" # number - Height of the header (px).
---| "rowHeight" # number - Height of each row (px).
---| "columns" # string[] - The columns, one a line: Title, or Title|width (width <= 1: a share of the table).
---| "rows" # string[] - The rows, one a line, cells split by |.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UITableNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UITableNode, path: "position"): Vec2
---@overload fun(self: UITableNode, path: "scale"): Vec2
---@overload fun(self: UITableNode, path: "rotation"): number
---@overload fun(self: UITableNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UITableNode, path: "zIndex"): integer
---@overload fun(self: UITableNode, path: "ySort"): boolean
---@overload fun(self: UITableNode, path: "ySortOffset"): number
---@overload fun(self: UITableNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UITableNode, path: "paused"): boolean
---@overload fun(self: UITableNode, path: "enabled"): boolean
---@overload fun(self: UITableNode, path: "size"): Vec2
---@overload fun(self: UITableNode, path: "keyboardFocus"): boolean
---@overload fun(self: UITableNode, path: "selectedRow"): integer
---@overload fun(self: UITableNode, path: "sortColumn"): integer
---@overload fun(self: UITableNode, path: "sortAscending"): boolean
---@overload fun(self: UITableNode, path: "headerHeight"): number
---@overload fun(self: UITableNode, path: "rowHeight"): number
---@overload fun(self: UITableNode, path: "columns"): string[]
---@overload fun(self: UITableNode, path: "rows"): string[]
function UITableNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UITableNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UITableNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITableNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITableNode, path: "rotation", value: number)
---@overload fun(self: UITableNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UITableNode, path: "zIndex", value: integer)
---@overload fun(self: UITableNode, path: "ySort", value: boolean)
---@overload fun(self: UITableNode, path: "ySortOffset", value: number)
---@overload fun(self: UITableNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UITableNode, path: "paused", value: boolean)
---@overload fun(self: UITableNode, path: "enabled", value: boolean)
---@overload fun(self: UITableNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITableNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UITableNode, path: "selectedRow", value: integer)
---@overload fun(self: UITableNode, path: "sortColumn", value: integer)
---@overload fun(self: UITableNode, path: "sortAscending", value: boolean)
---@overload fun(self: UITableNode, path: "headerHeight", value: number)
---@overload fun(self: UITableNode, path: "rowHeight", value: number)
---@overload fun(self: UITableNode, path: "columns", value: string[])
---@overload fun(self: UITableNode, path: "rows", value: string[])
function UITableNode:set_property(path, value, y) end

---@class UIIconNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field icon "None"|"Digit0"|"Digit1"|"Digit2"|"Digit3"|"Digit4"|"Digit5"|"Digit6"|"Digit7"|"Digit8"|"Digit9"|"A"|"AddressBook"|"AddressCard"|"AlignCenter"|"AlignJustify"|"AlignLeft"|"AlignRight"|"Anchor"|"AnchorCircleCheck"|"AnchorCircleExclamation"|"AnchorCircleXmark"|"AnchorLock"|"AngleDown"|"AngleLeft"|"AngleRight"|"AngleUp"|"AnglesDown"|"AnglesLeft"|"AnglesRight"|"AnglesUp"|"Ankh"|"AppleWhole"|"Archway"|"ArrowDown"|"ArrowDown19"|"ArrowDown91"|"ArrowDownAZ"|"ArrowDownLong"|"ArrowDownShortWide"|"ArrowDownUpAcrossLine"|"ArrowDownUpLock"|"ArrowDownWideShort"|"ArrowDownZA"|"ArrowLeft"|"ArrowLeftLong"|"ArrowPointer"|"ArrowRight"|"ArrowRightArrowLeft"|"ArrowRightFromBracket"|"ArrowRightLong"|"ArrowRightToBracket"|"ArrowRightToCity"|"ArrowRotateLeft"|"ArrowRotateRight"|"ArrowTrendDown"|"ArrowTrendUp"|"ArrowTurnDown"|"ArrowTurnUp"|"ArrowUp"|"ArrowUp19"|"ArrowUp91"|"ArrowUpAZ"|"ArrowUpFromBracket"|"ArrowUpFromGroundWater"|"ArrowUpFromWaterPump"|"ArrowUpLong"|"ArrowUpRightDots"|"ArrowUpRightFromSquare"|"ArrowUpShortWide"|"ArrowUpWideShort"|"ArrowUpZA"|"ArrowsDownToLine"|"ArrowsDownToPeople"|"ArrowsLeftRight"|"ArrowsLeftRightToLine"|"ArrowsRotate"|"ArrowsSpin"|"ArrowsSplitUpAndLeft"|"ArrowsToCircle"|"ArrowsToDot"|"ArrowsToEye"|"ArrowsTurnRight"|"ArrowsTurnToDots"|"ArrowsUpDown"|"ArrowsUpDownLeftRight"|"ArrowsUpToLine"|"Asterisk"|"At"|"Atom"|"AudioDescription"|"AustralSign"|"Award"|"B"|"Baby"|"BabyCarriage"|"Backward"|"BackwardFast"|"BackwardStep"|"Bacon"|"Bacteria"|"Bacterium"|"BagShopping"|"Bahai"|"BahtSign"|"Ban"|"BanSmoking"|"Bandage"|"BangladeshiTakaSign"|"Barcode"|"Bars"|"BarsProgress"|"BarsStaggered"|"Baseball"|"BaseballBatBall"|"BasketShopping"|"Basketball"|"Bath"|"BatteryEmpty"|"BatteryFull"|"BatteryHalf"|"BatteryQuarter"|"BatteryThreeQuarters"|"Bed"|"BedPulse"|"BeerMugEmpty"|"Bell"|"BellConcierge"|"BellSlash"|"BezierCurve"|"Bicycle"|"Binoculars"|"Biohazard"|"BitcoinSign"|"Blender"|"BlenderPhone"|"Blog"|"Bold"|"Bolt"|"BoltLightning"|"Bomb"|"Bone"|"Bong"|"Book"|"BookAtlas"|"BookBible"|"BookBookmark"|"BookJournalWhills"|"BookMedical"|"BookOpen"|"BookOpenReader"|"BookQuran"|"BookSkull"|"BookTanakh"|"Bookmark"|"BorderAll"|"BorderNone"|"BorderTopLeft"|"BoreHole"|"BottleDroplet"|"BottleWater"|"BowlFood"|"BowlRice"|"BowlingBall"|"Box"|"BoxArchive"|"BoxOpen"|"BoxTissue"|"BoxesPacking"|"BoxesStacked"|"Braille"|"Brain"|"BrazilianRealSign"|"BreadSlice"|"Bridge"|"BridgeCircleCheck"|"BridgeCircleExclamation"|"BridgeCircleXmark"|"BridgeLock"|"BridgeWater"|"Briefcase"|"BriefcaseMedical"|"Broom"|"BroomBall"|"Brush"|"Bucket"|"Bug"|"BugSlash"|"Bugs"|"Building"|"BuildingCircleArrowRight"|"BuildingCircleCheck"|"BuildingCircleExclamation"|"BuildingCircleXmark"|"BuildingColumns"|"BuildingFlag"|"BuildingLock"|"BuildingNgo"|"BuildingShield"|"BuildingUn"|"BuildingUser"|"BuildingWheat"|"Bullhorn"|"Bullseye"|"Burger"|"Burst"|"Bus"|"BusSimple"|"BusinessTime"|"C"|"CableCar"|"CakeCandles"|"Calculator"|"Calendar"|"CalendarCheck"|"CalendarDay"|"CalendarDays"|"CalendarMinus"|"CalendarPlus"|"CalendarWeek"|"CalendarXmark"|"Camera"|"CameraRetro"|"CameraRotate"|"Campground"|"CandyCane"|"Cannabis"|"Capsules"|"Car"|"CarBattery"|"CarBurst"|"CarOn"|"CarRear"|"CarSide"|"CarTunnel"|"Caravan"|"CaretDown"|"CaretLeft"|"CaretRight"|"CaretUp"|"Carrot"|"CartArrowDown"|"CartFlatbed"|"CartFlatbedSuitcase"|"CartPlus"|"CartShopping"|"CashRegister"|"Cat"|"CediSign"|"CentSign"|"Certificate"|"Chair"|"Chalkboard"|"ChalkboardUser"|"ChampagneGlasses"|"ChargingStation"|"ChartArea"|"ChartBar"|"ChartColumn"|"ChartDiagram"|"ChartGantt"|"ChartLine"|"ChartPie"|"ChartSimple"|"Check"|"CheckDouble"|"CheckToSlot"|"Cheese"|"Chess"|"ChessBishop"|"ChessBoard"|"ChessKing"|"ChessKnight"|"ChessPawn"|"ChessQueen"|"ChessRook"|"ChevronDown"|"ChevronLeft"|"ChevronRight"|"ChevronUp"|"Child"|"ChildCombatant"|"ChildDress"|"ChildReaching"|"Children"|"Church"|"Circle"|"CircleArrowDown"|"CircleArrowLeft"|"CircleArrowRight"|"CircleArrowUp"|"CircleCheck"|"CircleChevronDown"|"CircleChevronLeft"|"CircleChevronRight"|"CircleChevronUp"|"CircleDollarToSlot"|"CircleDot"|"CircleDown"|"CircleExclamation"|"CircleH"|"CircleHalfStroke"|"CircleInfo"|"CircleLeft"|"CircleMinus"|"CircleNodes"|"CircleNotch"|"CirclePause"|"CirclePlay"|"CirclePlus"|"CircleQuestion"|"CircleRadiation"|"CircleRight"|"CircleStop"|"CircleUp"|"CircleUser"|"CircleXmark"|"City"|"Clapperboard"|"Clipboard"|"ClipboardCheck"|"ClipboardList"|"ClipboardQuestion"|"ClipboardUser"|"Clock"|"ClockRotateLeft"|"Clone"|"ClosedCaptioning"|"Cloud"|"CloudArrowDown"|"CloudArrowUp"|"CloudBolt"|"CloudMeatball"|"CloudMoon"|"CloudMoonRain"|"CloudRain"|"CloudShowersHeavy"|"CloudShowersWater"|"CloudSun"|"CloudSunRain"|"Clover"|"Code"|"CodeBranch"|"CodeCommit"|"CodeCompare"|"CodeFork"|"CodeMerge"|"CodePullRequest"|"Coins"|"ColonSign"|"Comment"|"CommentDollar"|"CommentDots"|"CommentMedical"|"CommentNodes"|"CommentSlash"|"CommentSms"|"Comments"|"CommentsDollar"|"CompactDisc"|"Compass"|"CompassDrafting"|"Compress"|"Computer"|"ComputerMouse"|"Cookie"|"CookieBite"|"Copy"|"Copyright"|"Couch"|"Cow"|"CreditCard"|"Crop"|"CropSimple"|"Cross"|"Crosshairs"|"Crow"|"Crown"|"Crutch"|"CruzeiroSign"|"Cube"|"Cubes"|"CubesStacked"|"D"|"Database"|"DeleteLeft"|"Democrat"|"Desktop"|"Dharmachakra"|"DiagramNext"|"DiagramPredecessor"|"DiagramProject"|"DiagramSuccessor"|"Diamond"|"DiamondTurnRight"|"Dice"|"DiceD20"|"DiceD6"|"DiceFive"|"DiceFour"|"DiceOne"|"DiceSix"|"DiceThree"|"DiceTwo"|"Disease"|"Display"|"Divide"|"Dna"|"Dog"|"DollarSign"|"Dolly"|"DongSign"|"DoorClosed"|"DoorOpen"|"Dove"|"DownLeftAndUpRightToCenter"|"DownLong"|"Download"|"Dragon"|"DrawPolygon"|"Droplet"|"DropletSlash"|"Drum"|"DrumSteelpan"|"DrumstickBite"|"Dumbbell"|"Dumpster"|"DumpsterFire"|"Dungeon"|"E"|"EarDeaf"|"EarListen"|"EarthAfrica"|"EarthAmericas"|"EarthAsia"|"EarthEurope"|"EarthOceania"|"Egg"|"Eject"|"Elevator"|"Ellipsis"|"EllipsisVertical"|"Envelope"|"EnvelopeCircleCheck"|"EnvelopeOpen"|"EnvelopeOpenText"|"EnvelopesBulk"|"Equals"|"Eraser"|"Ethernet"|"EuroSign"|"Exclamation"|"Expand"|"Explosion"|"Eye"|"EyeDropper"|"EyeLowVision"|"EyeSlash"|"F"|"FaceAngry"|"FaceDizzy"|"FaceFlushed"|"FaceFrown"|"FaceFrownOpen"|"FaceGrimace"|"FaceGrin"|"FaceGrinBeam"|"FaceGrinBeamSweat"|"FaceGrinHearts"|"FaceGrinSquint"|"FaceGrinSquintTears"|"FaceGrinStars"|"FaceGrinTears"|"FaceGrinTongue"|"FaceGrinTongueSquint"|"FaceGrinTongueWink"|"FaceGrinWide"|"FaceGrinWink"|"FaceKiss"|"FaceKissBeam"|"FaceKissWinkHeart"|"FaceLaugh"|"FaceLaughBeam"|"FaceLaughSquint"|"FaceLaughWink"|"FaceMeh"|"FaceMehBlank"|"FaceRollingEyes"|"FaceSadCry"|"FaceSadTear"|"FaceSmile"|"FaceSmileBeam"|"FaceSmileWink"|"FaceSurprise"|"FaceTired"|"Fan"|"Faucet"|"FaucetDrip"|"Fax"|"Feather"|"FeatherPointed"|"Ferry"|"File"|"FileArrowDown"|"FileArrowUp"|"FileAudio"|"FileCircleCheck"|"FileCircleExclamation"|"FileCircleMinus"|"FileCirclePlus"|"FileCircleQuestion"|"FileCircleXmark"|"FileCode"|"FileContract"|"FileCsv"|"FileExcel"|"FileExport"|"FileFragment"|"FileHalfDashed"|"FileImage"|"FileImport"|"FileInvoice"|"FileInvoiceDollar"|"FileLines"|"FileMedical"|"FilePdf"|"FilePen"|"FilePowerpoint"|"FilePrescription"|"FileShield"|"FileSignature"|"FileVideo"|"FileWaveform"|"FileWord"|"FileZipper"|"Fill"|"FillDrip"|"Film"|"Filter"|"FilterCircleDollar"|"FilterCircleXmark"|"Fingerprint"|"Fire"|"FireBurner"|"FireExtinguisher"|"FireFlameCurved"|"FireFlameSimple"|"Fish"|"FishFins"|"Flag"|"FlagCheckered"|"FlagUsa"|"Flask"|"FlaskVial"|"FloppyDisk"|"FlorinSign"|"Folder"|"FolderClosed"|"FolderMinus"|"FolderOpen"|"FolderPlus"|"FolderTree"|"Font"|"FontAwesome"|"Football"|"Forward"|"ForwardFast"|"ForwardStep"|"FrancSign"|"Frog"|"Futbol"|"G"|"Gamepad"|"GasPump"|"Gauge"|"GaugeHigh"|"GaugeSimple"|"GaugeSimpleHigh"|"Gavel"|"Gear"|"Gears"|"Gem"|"Genderless"|"Ghost"|"Gift"|"Gifts"|"GlassWater"|"GlassWaterDroplet"|"Glasses"|"Globe"|"GolfBallTee"|"Gopuram"|"GraduationCap"|"GreaterThan"|"GreaterThanEqual"|"Grip"|"GripLines"|"GripLinesVertical"|"GripVertical"|"GroupArrowsRotate"|"GuaraniSign"|"Guitar"|"Gun"|"H"|"Hammer"|"Hamsa"|"Hand"|"HandBackFist"|"HandDots"|"HandFist"|"HandHolding"|"HandHoldingDollar"|"HandHoldingDroplet"|"HandHoldingHand"|"HandHoldingHeart"|"HandHoldingMedical"|"HandLizard"|"HandMiddleFinger"|"HandPeace"|"HandPointDown"|"HandPointLeft"|"HandPointRight"|"HandPointUp"|"HandPointer"|"HandScissors"|"HandSparkles"|"HandSpock"|"Handcuffs"|"Hands"|"HandsAslInterpreting"|"HandsBound"|"HandsBubbles"|"HandsClapping"|"HandsHolding"|"HandsHoldingChild"|"HandsHoldingCircle"|"HandsPraying"|"Handshake"|"HandshakeAngle"|"HandshakeSimple"|"HandshakeSimpleSlash"|"HandshakeSlash"|"Hanukiah"|"HardDrive"|"Hashtag"|"HatCowboy"|"HatCowboySide"|"HatWizard"|"HeadSideCough"|"HeadSideCoughSlash"|"HeadSideMask"|"HeadSideVirus"|"Heading"|"Headphones"|"HeadphonesSimple"|"Headset"|"Heart"|"HeartCircleBolt"|"HeartCircleCheck"|"HeartCircleExclamation"|"HeartCircleMinus"|"HeartCirclePlus"|"HeartCircleXmark"|"HeartCrack"|"HeartPulse"|"Helicopter"|"HelicopterSymbol"|"HelmetSafety"|"HelmetUn"|"HexagonNodes"|"HexagonNodesBolt"|"Highlighter"|"HillAvalanche"|"HillRockslide"|"Hippo"|"HockeyPuck"|"HollyBerry"|"Horse"|"HorseHead"|"Hospital"|"HospitalUser"|"HotTubPerson"|"Hotdog"|"Hotel"|"Hourglass"|"HourglassEnd"|"HourglassHalf"|"HourglassStart"|"House"|"HouseChimney"|"HouseChimneyCrack"|"HouseChimneyMedical"|"HouseChimneyUser"|"HouseChimneyWindow"|"HouseCircleCheck"|"HouseCircleExclamation"|"HouseCircleXmark"|"HouseCrack"|"HouseFire"|"HouseFlag"|"HouseFloodWater"|"HouseFloodWaterCircleArrowRight"|"HouseLaptop"|"HouseLock"|"HouseMedical"|"HouseMedicalCircleCheck"|"HouseMedicalCircleExclamation"|"HouseMedicalCircleXmark"|"HouseMedicalFlag"|"HouseSignal"|"HouseTsunami"|"HouseUser"|"HryvniaSign"|"Hurricane"|"I"|"ICursor"|"IceCream"|"Icicles"|"Icons"|"IdBadge"|"IdCard"|"IdCardClip"|"Igloo"|"Image"|"ImagePortrait"|"Images"|"Inbox"|"Indent"|"IndianRupeeSign"|"Industry"|"Infinity"|"Info"|"Italic"|"J"|"Jar"|"JarWheat"|"Jedi"|"JetFighter"|"JetFighterUp"|"Joint"|"JugDetergent"|"K"|"Kaaba"|"Key"|"Keyboard"|"Khanda"|"KipSign"|"KitMedical"|"KitchenSet"|"KiwiBird"|"L"|"LandMineOn"|"Landmark"|"LandmarkDome"|"LandmarkFlag"|"Language"|"Laptop"|"LaptopCode"|"LaptopFile"|"LaptopMedical"|"LariSign"|"LayerGroup"|"Leaf"|"LeftLong"|"LeftRight"|"Lemon"|"LessThan"|"LessThanEqual"|"LifeRing"|"Lightbulb"|"LinesLeaning"|"Link"|"LinkSlash"|"LiraSign"|"List"|"ListCheck"|"ListOl"|"ListUl"|"LitecoinSign"|"LocationArrow"|"LocationCrosshairs"|"LocationDot"|"LocationPin"|"LocationPinLock"|"Lock"|"LockOpen"|"Locust"|"Lungs"|"LungsVirus"|"M"|"Magnet"|"MagnifyingGlass"|"MagnifyingGlassArrowRight"|"MagnifyingGlassChart"|"MagnifyingGlassDollar"|"MagnifyingGlassLocation"|"MagnifyingGlassMinus"|"MagnifyingGlassPlus"|"ManatSign"|"Map"|"MapLocation"|"MapLocationDot"|"MapPin"|"Marker"|"Mars"|"MarsAndVenus"|"MarsAndVenusBurst"|"MarsDouble"|"MarsStroke"|"MarsStrokeRight"|"MarsStrokeUp"|"MartiniGlass"|"MartiniGlassCitrus"|"MartiniGlassEmpty"|"Mask"|"MaskFace"|"MaskVentilator"|"MasksTheater"|"MattressPillow"|"Maximize"|"Medal"|"Memory"|"Menorah"|"Mercury"|"Message"|"Meteor"|"Microchip"|"Microphone"|"MicrophoneLines"|"MicrophoneLinesSlash"|"MicrophoneSlash"|"Microscope"|"MillSign"|"Minimize"|"Minus"|"Mitten"|"Mobile"|"MobileButton"|"MobileRetro"|"MobileScreen"|"MobileScreenButton"|"MoneyBill"|"MoneyBill1"|"MoneyBill1Wave"|"MoneyBillTransfer"|"MoneyBillTrendUp"|"MoneyBillWave"|"MoneyBillWheat"|"MoneyBills"|"MoneyCheck"|"MoneyCheckDollar"|"Monument"|"Moon"|"MortarPestle"|"Mosque"|"Mosquito"|"MosquitoNet"|"Motorcycle"|"Mound"|"Mountain"|"MountainCity"|"MountainSun"|"MugHot"|"MugSaucer"|"Music"|"N"|"NairaSign"|"NetworkWired"|"Neuter"|"Newspaper"|"NotEqual"|"Notdef"|"NoteSticky"|"NotesMedical"|"O"|"ObjectGroup"|"ObjectUngroup"|"OilCan"|"OilWell"|"Om"|"Otter"|"Outdent"|"P"|"Pager"|"PaintRoller"|"Paintbrush"|"Palette"|"Pallet"|"Panorama"|"PaperPlane"|"Paperclip"|"ParachuteBox"|"Paragraph"|"Passport"|"Paste"|"Pause"|"Paw"|"Peace"|"Pen"|"PenClip"|"PenFancy"|"PenNib"|"PenRuler"|"PenToSquare"|"Pencil"|"PeopleArrows"|"PeopleCarryBox"|"PeopleGroup"|"PeopleLine"|"PeoplePulling"|"PeopleRobbery"|"PeopleRoof"|"PepperHot"|"Percent"|"Person"|"PersonArrowDownToLine"|"PersonArrowUpFromLine"|"PersonBiking"|"PersonBooth"|"PersonBreastfeeding"|"PersonBurst"|"PersonCane"|"PersonChalkboard"|"PersonCircleCheck"|"PersonCircleExclamation"|"PersonCircleMinus"|"PersonCirclePlus"|"PersonCircleQuestion"|"PersonCircleXmark"|"PersonDigging"|"PersonDotsFromLine"|"PersonDress"|"PersonDressBurst"|"PersonDrowning"|"PersonFalling"|"PersonFallingBurst"|"PersonHalfDress"|"PersonHarassing"|"PersonHiking"|"PersonMilitaryPointing"|"PersonMilitaryRifle"|"PersonMilitaryToPerson"|"PersonPraying"|"PersonPregnant"|"PersonRays"|"PersonRifle"|"PersonRunning"|"PersonShelter"|"PersonSkating"|"PersonSkiing"|"PersonSkiingNordic"|"PersonSnowboarding"|"PersonSwimming"|"PersonThroughWindow"|"PersonWalking"|"PersonWalkingArrowLoopLeft"|"PersonWalkingArrowRight"|"PersonWalkingDashedLineArrowRight"|"PersonWalkingLuggage"|"PersonWalkingWithCane"|"PesetaSign"|"PesoSign"|"Phone"|"PhoneFlip"|"PhoneSlash"|"PhoneVolume"|"PhotoFilm"|"PiggyBank"|"Pills"|"PizzaSlice"|"PlaceOfWorship"|"Plane"|"PlaneArrival"|"PlaneCircleCheck"|"PlaneCircleExclamation"|"PlaneCircleXmark"|"PlaneDeparture"|"PlaneLock"|"PlaneSlash"|"PlaneUp"|"PlantWilt"|"PlateWheat"|"Play"|"Plug"|"PlugCircleBolt"|"PlugCircleCheck"|"PlugCircleExclamation"|"PlugCircleMinus"|"PlugCirclePlus"|"PlugCircleXmark"|"Plus"|"PlusMinus"|"Podcast"|"Poo"|"PooStorm"|"Poop"|"PowerOff"|"Prescription"|"PrescriptionBottle"|"PrescriptionBottleMedical"|"Print"|"PumpMedical"|"PumpSoap"|"PuzzlePiece"|"Q"|"Qrcode"|"Question"|"QuoteLeft"|"QuoteRight"|"R"|"Radiation"|"Radio"|"Rainbow"|"RankingStar"|"Receipt"|"RecordVinyl"|"RectangleAd"|"RectangleList"|"RectangleXmark"|"Recycle"|"Registered"|"Repeat"|"Reply"|"ReplyAll"|"Republican"|"Restroom"|"Retweet"|"Ribbon"|"RightFromBracket"|"RightLeft"|"RightLong"|"RightToBracket"|"Ring"|"Road"|"RoadBarrier"|"RoadBridge"|"RoadCircleCheck"|"RoadCircleExclamation"|"RoadCircleXmark"|"RoadLock"|"RoadSpikes"|"Robot"|"Rocket"|"Rotate"|"RotateLeft"|"RotateRight"|"Route"|"Rss"|"RubleSign"|"Rug"|"Ruler"|"RulerCombined"|"RulerHorizontal"|"RulerVertical"|"RupeeSign"|"RupiahSign"|"S"|"SackDollar"|"SackXmark"|"Sailboat"|"Satellite"|"SatelliteDish"|"ScaleBalanced"|"ScaleUnbalanced"|"ScaleUnbalancedFlip"|"School"|"SchoolCircleCheck"|"SchoolCircleExclamation"|"SchoolCircleXmark"|"SchoolFlag"|"SchoolLock"|"Scissors"|"Screwdriver"|"ScrewdriverWrench"|"Scroll"|"ScrollTorah"|"SdCard"|"Section"|"Seedling"|"Server"|"Shapes"|"Share"|"ShareFromSquare"|"ShareNodes"|"SheetPlastic"|"ShekelSign"|"Shield"|"ShieldCat"|"ShieldDog"|"ShieldHalved"|"ShieldHeart"|"ShieldVirus"|"Ship"|"Shirt"|"ShoePrints"|"Shop"|"ShopLock"|"ShopSlash"|"Shower"|"Shrimp"|"Shuffle"|"ShuttleSpace"|"SignHanging"|"Signal"|"Signature"|"SignsPost"|"SimCard"|"Sink"|"Sitemap"|"Skull"|"SkullCrossbones"|"Slash"|"Sleigh"|"Sliders"|"Smog"|"Smoking"|"Snowflake"|"Snowman"|"Snowplow"|"Soap"|"Socks"|"SolarPanel"|"Sort"|"SortDown"|"SortUp"|"Spa"|"SpaghettiMonsterFlying"|"SpellCheck"|"Spider"|"Spinner"|"Splotch"|"Spoon"|"SprayCan"|"SprayCanSparkles"|"Square"|"SquareArrowUpRight"|"SquareBinary"|"SquareCaretDown"|"SquareCaretLeft"|"SquareCaretRight"|"SquareCaretUp"|"SquareCheck"|"SquareEnvelope"|"SquareFull"|"SquareH"|"SquareMinus"|"SquareNfi"|"SquareParking"|"SquarePen"|"SquarePersonConfined"|"SquarePhone"|"SquarePhoneFlip"|"SquarePlus"|"SquarePollHorizontal"|"SquarePollVertical"|"SquareRootVariable"|"SquareRss"|"SquareShareNodes"|"SquareUpRight"|"SquareVirus"|"SquareXmark"|"StaffSnake"|"Stairs"|"Stamp"|"Stapler"|"Star"|"StarAndCrescent"|"StarHalf"|"StarHalfStroke"|"StarOfDavid"|"StarOfLife"|"SterlingSign"|"Stethoscope"|"Stop"|"Stopwatch"|"Stopwatch20"|"Store"|"StoreSlash"|"StreetView"|"Strikethrough"|"Stroopwafel"|"Subscript"|"Suitcase"|"SuitcaseMedical"|"SuitcaseRolling"|"Sun"|"SunPlantWilt"|"Superscript"|"Swatchbook"|"Synagogue"|"Syringe"|"T"|"Table"|"TableCells"|"TableCellsColumnLock"|"TableCellsLarge"|"TableCellsRowLock"|"TableCellsRowUnlock"|"TableColumns"|"TableList"|"TableTennisPaddleBall"|"Tablet"|"TabletButton"|"TabletScreenButton"|"Tablets"|"TachographDigital"|"Tag"|"Tags"|"Tape"|"Tarp"|"TarpDroplet"|"Taxi"|"Teeth"|"TeethOpen"|"TemperatureArrowDown"|"TemperatureArrowUp"|"TemperatureEmpty"|"TemperatureFull"|"TemperatureHalf"|"TemperatureHigh"|"TemperatureLow"|"TemperatureQuarter"|"TemperatureThreeQuarters"|"TengeSign"|"Tent"|"TentArrowDownToLine"|"TentArrowLeftRight"|"TentArrowTurnLeft"|"TentArrowsDown"|"Tents"|"Terminal"|"TextHeight"|"TextSlash"|"TextWidth"|"Thermometer"|"ThumbsDown"|"ThumbsUp"|"Thumbtack"|"ThumbtackSlash"|"Ticket"|"TicketSimple"|"Timeline"|"ToggleOff"|"ToggleOn"|"Toilet"|"ToiletPaper"|"ToiletPaperSlash"|"ToiletPortable"|"ToiletsPortable"|"Toolbox"|"Tooth"|"ToriiGate"|"Tornado"|"TowerBroadcast"|"TowerCell"|"TowerObservation"|"Tractor"|"Trademark"|"TrafficLight"|"Trailer"|"Train"|"TrainSubway"|"TrainTram"|"Transgender"|"Trash"|"TrashArrowUp"|"TrashCan"|"TrashCanArrowUp"|"Tree"|"TreeCity"|"TriangleExclamation"|"Trophy"|"Trowel"|"TrowelBricks"|"Truck"|"TruckArrowRight"|"TruckDroplet"|"TruckFast"|"TruckField"|"TruckFieldUn"|"TruckFront"|"TruckMedical"|"TruckMonster"|"TruckMoving"|"TruckPickup"|"TruckPlane"|"TruckRampBox"|"Tty"|"TurkishLiraSign"|"TurnDown"|"TurnUp"|"Tv"|"U"|"Umbrella"|"UmbrellaBeach"|"Underline"|"UniversalAccess"|"Unlock"|"UnlockKeyhole"|"UpDown"|"UpDownLeftRight"|"UpLong"|"UpRightAndDownLeftFromCenter"|"UpRightFromSquare"|"Upload"|"User"|"UserAstronaut"|"UserCheck"|"UserClock"|"UserDoctor"|"UserGear"|"UserGraduate"|"UserGroup"|"UserInjured"|"UserLarge"|"UserLargeSlash"|"UserLock"|"UserMinus"|"UserNinja"|"UserNurse"|"UserPen"|"UserPlus"|"UserSecret"|"UserShield"|"UserSlash"|"UserTag"|"UserTie"|"UserXmark"|"Users"|"UsersBetweenLines"|"UsersGear"|"UsersLine"|"UsersRays"|"UsersRectangle"|"UsersSlash"|"UsersViewfinder"|"Utensils"|"V"|"VanShuttle"|"Vault"|"VectorSquare"|"Venus"|"VenusDouble"|"VenusMars"|"Vest"|"VestPatches"|"Vial"|"VialCircleCheck"|"VialVirus"|"Vials"|"Video"|"VideoSlash"|"Vihara"|"Virus"|"VirusCovid"|"VirusCovidSlash"|"VirusSlash"|"Viruses"|"Voicemail"|"Volcano"|"Volleyball"|"VolumeHigh"|"VolumeLow"|"VolumeOff"|"VolumeXmark"|"VrCardboard"|"W"|"WalkieTalkie"|"Wallet"|"WandMagic"|"WandMagicSparkles"|"WandSparkles"|"Warehouse"|"Water"|"WaterLadder"|"WaveSquare"|"WebAwesome"|"WeightHanging"|"WeightScale"|"WheatAwn"|"WheatAwnCircleExclamation"|"Wheelchair"|"WheelchairMove"|"WhiskeyGlass"|"Wifi"|"Wind"|"WindowMaximize"|"WindowMinimize"|"WindowRestore"|"WineBottle"|"WineGlass"|"WineGlassEmpty"|"WonSign"|"Worm"|"Wrench"|"X"|"XRay"|"Xmark"|"XmarksLines"|"Y"|"YenSign"|"YinYang"|"Z"|"Search"|"Save"|"Settings"|"Cog"|"Home"|"Edit"|"Close"|"Cancel"|"Refresh"|"Warning"|"CheckCircle"|"TimesCircle"|"VolumeMute"|"Cut"|"Undo"|"Redo"|"StepForward"|"StepBackward"|"Pin"|"ZoomIn"|"ZoomOut" Icon shown (Font Awesome).
---@field iconSize number Icon size (px).
---@field color number[] Icon colour.
---@field align "Left"|"Center"|"Right" Horizontal text alignment.

---@alias UIIconNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "icon" # "None"|"Digit0"|"Digit1"|"Digit2"|"Digit3"|"Digit4"|"Digit5"|"Digit6"|"Digit7"|"Digit8"|"Digit9"|"A"|"AddressBook"|"AddressCard"|"AlignCenter"|"AlignJustify"|"AlignLeft"|"AlignRight"|"Anchor"|"AnchorCircleCheck"|"AnchorCircleExclamation"|"AnchorCircleXmark"|"AnchorLock"|"AngleDown"|"AngleLeft"|"AngleRight"|"AngleUp"|"AnglesDown"|"AnglesLeft"|"AnglesRight"|"AnglesUp"|"Ankh"|"AppleWhole"|"Archway"|"ArrowDown"|"ArrowDown19"|"ArrowDown91"|"ArrowDownAZ"|"ArrowDownLong"|"ArrowDownShortWide"|"ArrowDownUpAcrossLine"|"ArrowDownUpLock"|"ArrowDownWideShort"|"ArrowDownZA"|"ArrowLeft"|"ArrowLeftLong"|"ArrowPointer"|"ArrowRight"|"ArrowRightArrowLeft"|"ArrowRightFromBracket"|"ArrowRightLong"|"ArrowRightToBracket"|"ArrowRightToCity"|"ArrowRotateLeft"|"ArrowRotateRight"|"ArrowTrendDown"|"ArrowTrendUp"|"ArrowTurnDown"|"ArrowTurnUp"|"ArrowUp"|"ArrowUp19"|"ArrowUp91"|"ArrowUpAZ"|"ArrowUpFromBracket"|"ArrowUpFromGroundWater"|"ArrowUpFromWaterPump"|"ArrowUpLong"|"ArrowUpRightDots"|"ArrowUpRightFromSquare"|"ArrowUpShortWide"|"ArrowUpWideShort"|"ArrowUpZA"|"ArrowsDownToLine"|"ArrowsDownToPeople"|"ArrowsLeftRight"|"ArrowsLeftRightToLine"|"ArrowsRotate"|"ArrowsSpin"|"ArrowsSplitUpAndLeft"|"ArrowsToCircle"|"ArrowsToDot"|"ArrowsToEye"|"ArrowsTurnRight"|"ArrowsTurnToDots"|"ArrowsUpDown"|"ArrowsUpDownLeftRight"|"ArrowsUpToLine"|"Asterisk"|"At"|"Atom"|"AudioDescription"|"AustralSign"|"Award"|"B"|"Baby"|"BabyCarriage"|"Backward"|"BackwardFast"|"BackwardStep"|"Bacon"|"Bacteria"|"Bacterium"|"BagShopping"|"Bahai"|"BahtSign"|"Ban"|"BanSmoking"|"Bandage"|"BangladeshiTakaSign"|"Barcode"|"Bars"|"BarsProgress"|"BarsStaggered"|"Baseball"|"BaseballBatBall"|"BasketShopping"|"Basketball"|"Bath"|"BatteryEmpty"|"BatteryFull"|"BatteryHalf"|"BatteryQuarter"|"BatteryThreeQuarters"|"Bed"|"BedPulse"|"BeerMugEmpty"|"Bell"|"BellConcierge"|"BellSlash"|"BezierCurve"|"Bicycle"|"Binoculars"|"Biohazard"|"BitcoinSign"|"Blender"|"BlenderPhone"|"Blog"|"Bold"|"Bolt"|"BoltLightning"|"Bomb"|"Bone"|"Bong"|"Book"|"BookAtlas"|"BookBible"|"BookBookmark"|"BookJournalWhills"|"BookMedical"|"BookOpen"|"BookOpenReader"|"BookQuran"|"BookSkull"|"BookTanakh"|"Bookmark"|"BorderAll"|"BorderNone"|"BorderTopLeft"|"BoreHole"|"BottleDroplet"|"BottleWater"|"BowlFood"|"BowlRice"|"BowlingBall"|"Box"|"BoxArchive"|"BoxOpen"|"BoxTissue"|"BoxesPacking"|"BoxesStacked"|"Braille"|"Brain"|"BrazilianRealSign"|"BreadSlice"|"Bridge"|"BridgeCircleCheck"|"BridgeCircleExclamation"|"BridgeCircleXmark"|"BridgeLock"|"BridgeWater"|"Briefcase"|"BriefcaseMedical"|"Broom"|"BroomBall"|"Brush"|"Bucket"|"Bug"|"BugSlash"|"Bugs"|"Building"|"BuildingCircleArrowRight"|"BuildingCircleCheck"|"BuildingCircleExclamation"|"BuildingCircleXmark"|"BuildingColumns"|"BuildingFlag"|"BuildingLock"|"BuildingNgo"|"BuildingShield"|"BuildingUn"|"BuildingUser"|"BuildingWheat"|"Bullhorn"|"Bullseye"|"Burger"|"Burst"|"Bus"|"BusSimple"|"BusinessTime"|"C"|"CableCar"|"CakeCandles"|"Calculator"|"Calendar"|"CalendarCheck"|"CalendarDay"|"CalendarDays"|"CalendarMinus"|"CalendarPlus"|"CalendarWeek"|"CalendarXmark"|"Camera"|"CameraRetro"|"CameraRotate"|"Campground"|"CandyCane"|"Cannabis"|"Capsules"|"Car"|"CarBattery"|"CarBurst"|"CarOn"|"CarRear"|"CarSide"|"CarTunnel"|"Caravan"|"CaretDown"|"CaretLeft"|"CaretRight"|"CaretUp"|"Carrot"|"CartArrowDown"|"CartFlatbed"|"CartFlatbedSuitcase"|"CartPlus"|"CartShopping"|"CashRegister"|"Cat"|"CediSign"|"CentSign"|"Certificate"|"Chair"|"Chalkboard"|"ChalkboardUser"|"ChampagneGlasses"|"ChargingStation"|"ChartArea"|"ChartBar"|"ChartColumn"|"ChartDiagram"|"ChartGantt"|"ChartLine"|"ChartPie"|"ChartSimple"|"Check"|"CheckDouble"|"CheckToSlot"|"Cheese"|"Chess"|"ChessBishop"|"ChessBoard"|"ChessKing"|"ChessKnight"|"ChessPawn"|"ChessQueen"|"ChessRook"|"ChevronDown"|"ChevronLeft"|"ChevronRight"|"ChevronUp"|"Child"|"ChildCombatant"|"ChildDress"|"ChildReaching"|"Children"|"Church"|"Circle"|"CircleArrowDown"|"CircleArrowLeft"|"CircleArrowRight"|"CircleArrowUp"|"CircleCheck"|"CircleChevronDown"|"CircleChevronLeft"|"CircleChevronRight"|"CircleChevronUp"|"CircleDollarToSlot"|"CircleDot"|"CircleDown"|"CircleExclamation"|"CircleH"|"CircleHalfStroke"|"CircleInfo"|"CircleLeft"|"CircleMinus"|"CircleNodes"|"CircleNotch"|"CirclePause"|"CirclePlay"|"CirclePlus"|"CircleQuestion"|"CircleRadiation"|"CircleRight"|"CircleStop"|"CircleUp"|"CircleUser"|"CircleXmark"|"City"|"Clapperboard"|"Clipboard"|"ClipboardCheck"|"ClipboardList"|"ClipboardQuestion"|"ClipboardUser"|"Clock"|"ClockRotateLeft"|"Clone"|"ClosedCaptioning"|"Cloud"|"CloudArrowDown"|"CloudArrowUp"|"CloudBolt"|"CloudMeatball"|"CloudMoon"|"CloudMoonRain"|"CloudRain"|"CloudShowersHeavy"|"CloudShowersWater"|"CloudSun"|"CloudSunRain"|"Clover"|"Code"|"CodeBranch"|"CodeCommit"|"CodeCompare"|"CodeFork"|"CodeMerge"|"CodePullRequest"|"Coins"|"ColonSign"|"Comment"|"CommentDollar"|"CommentDots"|"CommentMedical"|"CommentNodes"|"CommentSlash"|"CommentSms"|"Comments"|"CommentsDollar"|"CompactDisc"|"Compass"|"CompassDrafting"|"Compress"|"Computer"|"ComputerMouse"|"Cookie"|"CookieBite"|"Copy"|"Copyright"|"Couch"|"Cow"|"CreditCard"|"Crop"|"CropSimple"|"Cross"|"Crosshairs"|"Crow"|"Crown"|"Crutch"|"CruzeiroSign"|"Cube"|"Cubes"|"CubesStacked"|"D"|"Database"|"DeleteLeft"|"Democrat"|"Desktop"|"Dharmachakra"|"DiagramNext"|"DiagramPredecessor"|"DiagramProject"|"DiagramSuccessor"|"Diamond"|"DiamondTurnRight"|"Dice"|"DiceD20"|"DiceD6"|"DiceFive"|"DiceFour"|"DiceOne"|"DiceSix"|"DiceThree"|"DiceTwo"|"Disease"|"Display"|"Divide"|"Dna"|"Dog"|"DollarSign"|"Dolly"|"DongSign"|"DoorClosed"|"DoorOpen"|"Dove"|"DownLeftAndUpRightToCenter"|"DownLong"|"Download"|"Dragon"|"DrawPolygon"|"Droplet"|"DropletSlash"|"Drum"|"DrumSteelpan"|"DrumstickBite"|"Dumbbell"|"Dumpster"|"DumpsterFire"|"Dungeon"|"E"|"EarDeaf"|"EarListen"|"EarthAfrica"|"EarthAmericas"|"EarthAsia"|"EarthEurope"|"EarthOceania"|"Egg"|"Eject"|"Elevator"|"Ellipsis"|"EllipsisVertical"|"Envelope"|"EnvelopeCircleCheck"|"EnvelopeOpen"|"EnvelopeOpenText"|"EnvelopesBulk"|"Equals"|"Eraser"|"Ethernet"|"EuroSign"|"Exclamation"|"Expand"|"Explosion"|"Eye"|"EyeDropper"|"EyeLowVision"|"EyeSlash"|"F"|"FaceAngry"|"FaceDizzy"|"FaceFlushed"|"FaceFrown"|"FaceFrownOpen"|"FaceGrimace"|"FaceGrin"|"FaceGrinBeam"|"FaceGrinBeamSweat"|"FaceGrinHearts"|"FaceGrinSquint"|"FaceGrinSquintTears"|"FaceGrinStars"|"FaceGrinTears"|"FaceGrinTongue"|"FaceGrinTongueSquint"|"FaceGrinTongueWink"|"FaceGrinWide"|"FaceGrinWink"|"FaceKiss"|"FaceKissBeam"|"FaceKissWinkHeart"|"FaceLaugh"|"FaceLaughBeam"|"FaceLaughSquint"|"FaceLaughWink"|"FaceMeh"|"FaceMehBlank"|"FaceRollingEyes"|"FaceSadCry"|"FaceSadTear"|"FaceSmile"|"FaceSmileBeam"|"FaceSmileWink"|"FaceSurprise"|"FaceTired"|"Fan"|"Faucet"|"FaucetDrip"|"Fax"|"Feather"|"FeatherPointed"|"Ferry"|"File"|"FileArrowDown"|"FileArrowUp"|"FileAudio"|"FileCircleCheck"|"FileCircleExclamation"|"FileCircleMinus"|"FileCirclePlus"|"FileCircleQuestion"|"FileCircleXmark"|"FileCode"|"FileContract"|"FileCsv"|"FileExcel"|"FileExport"|"FileFragment"|"FileHalfDashed"|"FileImage"|"FileImport"|"FileInvoice"|"FileInvoiceDollar"|"FileLines"|"FileMedical"|"FilePdf"|"FilePen"|"FilePowerpoint"|"FilePrescription"|"FileShield"|"FileSignature"|"FileVideo"|"FileWaveform"|"FileWord"|"FileZipper"|"Fill"|"FillDrip"|"Film"|"Filter"|"FilterCircleDollar"|"FilterCircleXmark"|"Fingerprint"|"Fire"|"FireBurner"|"FireExtinguisher"|"FireFlameCurved"|"FireFlameSimple"|"Fish"|"FishFins"|"Flag"|"FlagCheckered"|"FlagUsa"|"Flask"|"FlaskVial"|"FloppyDisk"|"FlorinSign"|"Folder"|"FolderClosed"|"FolderMinus"|"FolderOpen"|"FolderPlus"|"FolderTree"|"Font"|"FontAwesome"|"Football"|"Forward"|"ForwardFast"|"ForwardStep"|"FrancSign"|"Frog"|"Futbol"|"G"|"Gamepad"|"GasPump"|"Gauge"|"GaugeHigh"|"GaugeSimple"|"GaugeSimpleHigh"|"Gavel"|"Gear"|"Gears"|"Gem"|"Genderless"|"Ghost"|"Gift"|"Gifts"|"GlassWater"|"GlassWaterDroplet"|"Glasses"|"Globe"|"GolfBallTee"|"Gopuram"|"GraduationCap"|"GreaterThan"|"GreaterThanEqual"|"Grip"|"GripLines"|"GripLinesVertical"|"GripVertical"|"GroupArrowsRotate"|"GuaraniSign"|"Guitar"|"Gun"|"H"|"Hammer"|"Hamsa"|"Hand"|"HandBackFist"|"HandDots"|"HandFist"|"HandHolding"|"HandHoldingDollar"|"HandHoldingDroplet"|"HandHoldingHand"|"HandHoldingHeart"|"HandHoldingMedical"|"HandLizard"|"HandMiddleFinger"|"HandPeace"|"HandPointDown"|"HandPointLeft"|"HandPointRight"|"HandPointUp"|"HandPointer"|"HandScissors"|"HandSparkles"|"HandSpock"|"Handcuffs"|"Hands"|"HandsAslInterpreting"|"HandsBound"|"HandsBubbles"|"HandsClapping"|"HandsHolding"|"HandsHoldingChild"|"HandsHoldingCircle"|"HandsPraying"|"Handshake"|"HandshakeAngle"|"HandshakeSimple"|"HandshakeSimpleSlash"|"HandshakeSlash"|"Hanukiah"|"HardDrive"|"Hashtag"|"HatCowboy"|"HatCowboySide"|"HatWizard"|"HeadSideCough"|"HeadSideCoughSlash"|"HeadSideMask"|"HeadSideVirus"|"Heading"|"Headphones"|"HeadphonesSimple"|"Headset"|"Heart"|"HeartCircleBolt"|"HeartCircleCheck"|"HeartCircleExclamation"|"HeartCircleMinus"|"HeartCirclePlus"|"HeartCircleXmark"|"HeartCrack"|"HeartPulse"|"Helicopter"|"HelicopterSymbol"|"HelmetSafety"|"HelmetUn"|"HexagonNodes"|"HexagonNodesBolt"|"Highlighter"|"HillAvalanche"|"HillRockslide"|"Hippo"|"HockeyPuck"|"HollyBerry"|"Horse"|"HorseHead"|"Hospital"|"HospitalUser"|"HotTubPerson"|"Hotdog"|"Hotel"|"Hourglass"|"HourglassEnd"|"HourglassHalf"|"HourglassStart"|"House"|"HouseChimney"|"HouseChimneyCrack"|"HouseChimneyMedical"|"HouseChimneyUser"|"HouseChimneyWindow"|"HouseCircleCheck"|"HouseCircleExclamation"|"HouseCircleXmark"|"HouseCrack"|"HouseFire"|"HouseFlag"|"HouseFloodWater"|"HouseFloodWaterCircleArrowRight"|"HouseLaptop"|"HouseLock"|"HouseMedical"|"HouseMedicalCircleCheck"|"HouseMedicalCircleExclamation"|"HouseMedicalCircleXmark"|"HouseMedicalFlag"|"HouseSignal"|"HouseTsunami"|"HouseUser"|"HryvniaSign"|"Hurricane"|"I"|"ICursor"|"IceCream"|"Icicles"|"Icons"|"IdBadge"|"IdCard"|"IdCardClip"|"Igloo"|"Image"|"ImagePortrait"|"Images"|"Inbox"|"Indent"|"IndianRupeeSign"|"Industry"|"Infinity"|"Info"|"Italic"|"J"|"Jar"|"JarWheat"|"Jedi"|"JetFighter"|"JetFighterUp"|"Joint"|"JugDetergent"|"K"|"Kaaba"|"Key"|"Keyboard"|"Khanda"|"KipSign"|"KitMedical"|"KitchenSet"|"KiwiBird"|"L"|"LandMineOn"|"Landmark"|"LandmarkDome"|"LandmarkFlag"|"Language"|"Laptop"|"LaptopCode"|"LaptopFile"|"LaptopMedical"|"LariSign"|"LayerGroup"|"Leaf"|"LeftLong"|"LeftRight"|"Lemon"|"LessThan"|"LessThanEqual"|"LifeRing"|"Lightbulb"|"LinesLeaning"|"Link"|"LinkSlash"|"LiraSign"|"List"|"ListCheck"|"ListOl"|"ListUl"|"LitecoinSign"|"LocationArrow"|"LocationCrosshairs"|"LocationDot"|"LocationPin"|"LocationPinLock"|"Lock"|"LockOpen"|"Locust"|"Lungs"|"LungsVirus"|"M"|"Magnet"|"MagnifyingGlass"|"MagnifyingGlassArrowRight"|"MagnifyingGlassChart"|"MagnifyingGlassDollar"|"MagnifyingGlassLocation"|"MagnifyingGlassMinus"|"MagnifyingGlassPlus"|"ManatSign"|"Map"|"MapLocation"|"MapLocationDot"|"MapPin"|"Marker"|"Mars"|"MarsAndVenus"|"MarsAndVenusBurst"|"MarsDouble"|"MarsStroke"|"MarsStrokeRight"|"MarsStrokeUp"|"MartiniGlass"|"MartiniGlassCitrus"|"MartiniGlassEmpty"|"Mask"|"MaskFace"|"MaskVentilator"|"MasksTheater"|"MattressPillow"|"Maximize"|"Medal"|"Memory"|"Menorah"|"Mercury"|"Message"|"Meteor"|"Microchip"|"Microphone"|"MicrophoneLines"|"MicrophoneLinesSlash"|"MicrophoneSlash"|"Microscope"|"MillSign"|"Minimize"|"Minus"|"Mitten"|"Mobile"|"MobileButton"|"MobileRetro"|"MobileScreen"|"MobileScreenButton"|"MoneyBill"|"MoneyBill1"|"MoneyBill1Wave"|"MoneyBillTransfer"|"MoneyBillTrendUp"|"MoneyBillWave"|"MoneyBillWheat"|"MoneyBills"|"MoneyCheck"|"MoneyCheckDollar"|"Monument"|"Moon"|"MortarPestle"|"Mosque"|"Mosquito"|"MosquitoNet"|"Motorcycle"|"Mound"|"Mountain"|"MountainCity"|"MountainSun"|"MugHot"|"MugSaucer"|"Music"|"N"|"NairaSign"|"NetworkWired"|"Neuter"|"Newspaper"|"NotEqual"|"Notdef"|"NoteSticky"|"NotesMedical"|"O"|"ObjectGroup"|"ObjectUngroup"|"OilCan"|"OilWell"|"Om"|"Otter"|"Outdent"|"P"|"Pager"|"PaintRoller"|"Paintbrush"|"Palette"|"Pallet"|"Panorama"|"PaperPlane"|"Paperclip"|"ParachuteBox"|"Paragraph"|"Passport"|"Paste"|"Pause"|"Paw"|"Peace"|"Pen"|"PenClip"|"PenFancy"|"PenNib"|"PenRuler"|"PenToSquare"|"Pencil"|"PeopleArrows"|"PeopleCarryBox"|"PeopleGroup"|"PeopleLine"|"PeoplePulling"|"PeopleRobbery"|"PeopleRoof"|"PepperHot"|"Percent"|"Person"|"PersonArrowDownToLine"|"PersonArrowUpFromLine"|"PersonBiking"|"PersonBooth"|"PersonBreastfeeding"|"PersonBurst"|"PersonCane"|"PersonChalkboard"|"PersonCircleCheck"|"PersonCircleExclamation"|"PersonCircleMinus"|"PersonCirclePlus"|"PersonCircleQuestion"|"PersonCircleXmark"|"PersonDigging"|"PersonDotsFromLine"|"PersonDress"|"PersonDressBurst"|"PersonDrowning"|"PersonFalling"|"PersonFallingBurst"|"PersonHalfDress"|"PersonHarassing"|"PersonHiking"|"PersonMilitaryPointing"|"PersonMilitaryRifle"|"PersonMilitaryToPerson"|"PersonPraying"|"PersonPregnant"|"PersonRays"|"PersonRifle"|"PersonRunning"|"PersonShelter"|"PersonSkating"|"PersonSkiing"|"PersonSkiingNordic"|"PersonSnowboarding"|"PersonSwimming"|"PersonThroughWindow"|"PersonWalking"|"PersonWalkingArrowLoopLeft"|"PersonWalkingArrowRight"|"PersonWalkingDashedLineArrowRight"|"PersonWalkingLuggage"|"PersonWalkingWithCane"|"PesetaSign"|"PesoSign"|"Phone"|"PhoneFlip"|"PhoneSlash"|"PhoneVolume"|"PhotoFilm"|"PiggyBank"|"Pills"|"PizzaSlice"|"PlaceOfWorship"|"Plane"|"PlaneArrival"|"PlaneCircleCheck"|"PlaneCircleExclamation"|"PlaneCircleXmark"|"PlaneDeparture"|"PlaneLock"|"PlaneSlash"|"PlaneUp"|"PlantWilt"|"PlateWheat"|"Play"|"Plug"|"PlugCircleBolt"|"PlugCircleCheck"|"PlugCircleExclamation"|"PlugCircleMinus"|"PlugCirclePlus"|"PlugCircleXmark"|"Plus"|"PlusMinus"|"Podcast"|"Poo"|"PooStorm"|"Poop"|"PowerOff"|"Prescription"|"PrescriptionBottle"|"PrescriptionBottleMedical"|"Print"|"PumpMedical"|"PumpSoap"|"PuzzlePiece"|"Q"|"Qrcode"|"Question"|"QuoteLeft"|"QuoteRight"|"R"|"Radiation"|"Radio"|"Rainbow"|"RankingStar"|"Receipt"|"RecordVinyl"|"RectangleAd"|"RectangleList"|"RectangleXmark"|"Recycle"|"Registered"|"Repeat"|"Reply"|"ReplyAll"|"Republican"|"Restroom"|"Retweet"|"Ribbon"|"RightFromBracket"|"RightLeft"|"RightLong"|"RightToBracket"|"Ring"|"Road"|"RoadBarrier"|"RoadBridge"|"RoadCircleCheck"|"RoadCircleExclamation"|"RoadCircleXmark"|"RoadLock"|"RoadSpikes"|"Robot"|"Rocket"|"Rotate"|"RotateLeft"|"RotateRight"|"Route"|"Rss"|"RubleSign"|"Rug"|"Ruler"|"RulerCombined"|"RulerHorizontal"|"RulerVertical"|"RupeeSign"|"RupiahSign"|"S"|"SackDollar"|"SackXmark"|"Sailboat"|"Satellite"|"SatelliteDish"|"ScaleBalanced"|"ScaleUnbalanced"|"ScaleUnbalancedFlip"|"School"|"SchoolCircleCheck"|"SchoolCircleExclamation"|"SchoolCircleXmark"|"SchoolFlag"|"SchoolLock"|"Scissors"|"Screwdriver"|"ScrewdriverWrench"|"Scroll"|"ScrollTorah"|"SdCard"|"Section"|"Seedling"|"Server"|"Shapes"|"Share"|"ShareFromSquare"|"ShareNodes"|"SheetPlastic"|"ShekelSign"|"Shield"|"ShieldCat"|"ShieldDog"|"ShieldHalved"|"ShieldHeart"|"ShieldVirus"|"Ship"|"Shirt"|"ShoePrints"|"Shop"|"ShopLock"|"ShopSlash"|"Shower"|"Shrimp"|"Shuffle"|"ShuttleSpace"|"SignHanging"|"Signal"|"Signature"|"SignsPost"|"SimCard"|"Sink"|"Sitemap"|"Skull"|"SkullCrossbones"|"Slash"|"Sleigh"|"Sliders"|"Smog"|"Smoking"|"Snowflake"|"Snowman"|"Snowplow"|"Soap"|"Socks"|"SolarPanel"|"Sort"|"SortDown"|"SortUp"|"Spa"|"SpaghettiMonsterFlying"|"SpellCheck"|"Spider"|"Spinner"|"Splotch"|"Spoon"|"SprayCan"|"SprayCanSparkles"|"Square"|"SquareArrowUpRight"|"SquareBinary"|"SquareCaretDown"|"SquareCaretLeft"|"SquareCaretRight"|"SquareCaretUp"|"SquareCheck"|"SquareEnvelope"|"SquareFull"|"SquareH"|"SquareMinus"|"SquareNfi"|"SquareParking"|"SquarePen"|"SquarePersonConfined"|"SquarePhone"|"SquarePhoneFlip"|"SquarePlus"|"SquarePollHorizontal"|"SquarePollVertical"|"SquareRootVariable"|"SquareRss"|"SquareShareNodes"|"SquareUpRight"|"SquareVirus"|"SquareXmark"|"StaffSnake"|"Stairs"|"Stamp"|"Stapler"|"Star"|"StarAndCrescent"|"StarHalf"|"StarHalfStroke"|"StarOfDavid"|"StarOfLife"|"SterlingSign"|"Stethoscope"|"Stop"|"Stopwatch"|"Stopwatch20"|"Store"|"StoreSlash"|"StreetView"|"Strikethrough"|"Stroopwafel"|"Subscript"|"Suitcase"|"SuitcaseMedical"|"SuitcaseRolling"|"Sun"|"SunPlantWilt"|"Superscript"|"Swatchbook"|"Synagogue"|"Syringe"|"T"|"Table"|"TableCells"|"TableCellsColumnLock"|"TableCellsLarge"|"TableCellsRowLock"|"TableCellsRowUnlock"|"TableColumns"|"TableList"|"TableTennisPaddleBall"|"Tablet"|"TabletButton"|"TabletScreenButton"|"Tablets"|"TachographDigital"|"Tag"|"Tags"|"Tape"|"Tarp"|"TarpDroplet"|"Taxi"|"Teeth"|"TeethOpen"|"TemperatureArrowDown"|"TemperatureArrowUp"|"TemperatureEmpty"|"TemperatureFull"|"TemperatureHalf"|"TemperatureHigh"|"TemperatureLow"|"TemperatureQuarter"|"TemperatureThreeQuarters"|"TengeSign"|"Tent"|"TentArrowDownToLine"|"TentArrowLeftRight"|"TentArrowTurnLeft"|"TentArrowsDown"|"Tents"|"Terminal"|"TextHeight"|"TextSlash"|"TextWidth"|"Thermometer"|"ThumbsDown"|"ThumbsUp"|"Thumbtack"|"ThumbtackSlash"|"Ticket"|"TicketSimple"|"Timeline"|"ToggleOff"|"ToggleOn"|"Toilet"|"ToiletPaper"|"ToiletPaperSlash"|"ToiletPortable"|"ToiletsPortable"|"Toolbox"|"Tooth"|"ToriiGate"|"Tornado"|"TowerBroadcast"|"TowerCell"|"TowerObservation"|"Tractor"|"Trademark"|"TrafficLight"|"Trailer"|"Train"|"TrainSubway"|"TrainTram"|"Transgender"|"Trash"|"TrashArrowUp"|"TrashCan"|"TrashCanArrowUp"|"Tree"|"TreeCity"|"TriangleExclamation"|"Trophy"|"Trowel"|"TrowelBricks"|"Truck"|"TruckArrowRight"|"TruckDroplet"|"TruckFast"|"TruckField"|"TruckFieldUn"|"TruckFront"|"TruckMedical"|"TruckMonster"|"TruckMoving"|"TruckPickup"|"TruckPlane"|"TruckRampBox"|"Tty"|"TurkishLiraSign"|"TurnDown"|"TurnUp"|"Tv"|"U"|"Umbrella"|"UmbrellaBeach"|"Underline"|"UniversalAccess"|"Unlock"|"UnlockKeyhole"|"UpDown"|"UpDownLeftRight"|"UpLong"|"UpRightAndDownLeftFromCenter"|"UpRightFromSquare"|"Upload"|"User"|"UserAstronaut"|"UserCheck"|"UserClock"|"UserDoctor"|"UserGear"|"UserGraduate"|"UserGroup"|"UserInjured"|"UserLarge"|"UserLargeSlash"|"UserLock"|"UserMinus"|"UserNinja"|"UserNurse"|"UserPen"|"UserPlus"|"UserSecret"|"UserShield"|"UserSlash"|"UserTag"|"UserTie"|"UserXmark"|"Users"|"UsersBetweenLines"|"UsersGear"|"UsersLine"|"UsersRays"|"UsersRectangle"|"UsersSlash"|"UsersViewfinder"|"Utensils"|"V"|"VanShuttle"|"Vault"|"VectorSquare"|"Venus"|"VenusDouble"|"VenusMars"|"Vest"|"VestPatches"|"Vial"|"VialCircleCheck"|"VialVirus"|"Vials"|"Video"|"VideoSlash"|"Vihara"|"Virus"|"VirusCovid"|"VirusCovidSlash"|"VirusSlash"|"Viruses"|"Voicemail"|"Volcano"|"Volleyball"|"VolumeHigh"|"VolumeLow"|"VolumeOff"|"VolumeXmark"|"VrCardboard"|"W"|"WalkieTalkie"|"Wallet"|"WandMagic"|"WandMagicSparkles"|"WandSparkles"|"Warehouse"|"Water"|"WaterLadder"|"WaveSquare"|"WebAwesome"|"WeightHanging"|"WeightScale"|"WheatAwn"|"WheatAwnCircleExclamation"|"Wheelchair"|"WheelchairMove"|"WhiskeyGlass"|"Wifi"|"Wind"|"WindowMaximize"|"WindowMinimize"|"WindowRestore"|"WineBottle"|"WineGlass"|"WineGlassEmpty"|"WonSign"|"Worm"|"Wrench"|"X"|"XRay"|"Xmark"|"XmarksLines"|"Y"|"YenSign"|"YinYang"|"Z"|"Search"|"Save"|"Settings"|"Cog"|"Home"|"Edit"|"Close"|"Cancel"|"Refresh"|"Warning"|"CheckCircle"|"TimesCircle"|"VolumeMute"|"Cut"|"Undo"|"Redo"|"StepForward"|"StepBackward"|"Pin"|"ZoomIn"|"ZoomOut" - Icon shown (Font Awesome).
---| "iconSize" # number - Icon size (px).
---| "color" # number[] - Icon colour.
---| "align" # "Left"|"Center"|"Right" - Horizontal text alignment.

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UIIconNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UIIconNode, path: "position"): Vec2
---@overload fun(self: UIIconNode, path: "scale"): Vec2
---@overload fun(self: UIIconNode, path: "rotation"): number
---@overload fun(self: UIIconNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIIconNode, path: "zIndex"): integer
---@overload fun(self: UIIconNode, path: "ySort"): boolean
---@overload fun(self: UIIconNode, path: "ySortOffset"): number
---@overload fun(self: UIIconNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIIconNode, path: "paused"): boolean
---@overload fun(self: UIIconNode, path: "enabled"): boolean
---@overload fun(self: UIIconNode, path: "size"): Vec2
---@overload fun(self: UIIconNode, path: "keyboardFocus"): boolean
---@overload fun(self: UIIconNode, path: "icon"): "None"|"Digit0"|"Digit1"|"Digit2"|"Digit3"|"Digit4"|"Digit5"|"Digit6"|"Digit7"|"Digit8"|"Digit9"|"A"|"AddressBook"|"AddressCard"|"AlignCenter"|"AlignJustify"|"AlignLeft"|"AlignRight"|"Anchor"|"AnchorCircleCheck"|"AnchorCircleExclamation"|"AnchorCircleXmark"|"AnchorLock"|"AngleDown"|"AngleLeft"|"AngleRight"|"AngleUp"|"AnglesDown"|"AnglesLeft"|"AnglesRight"|"AnglesUp"|"Ankh"|"AppleWhole"|"Archway"|"ArrowDown"|"ArrowDown19"|"ArrowDown91"|"ArrowDownAZ"|"ArrowDownLong"|"ArrowDownShortWide"|"ArrowDownUpAcrossLine"|"ArrowDownUpLock"|"ArrowDownWideShort"|"ArrowDownZA"|"ArrowLeft"|"ArrowLeftLong"|"ArrowPointer"|"ArrowRight"|"ArrowRightArrowLeft"|"ArrowRightFromBracket"|"ArrowRightLong"|"ArrowRightToBracket"|"ArrowRightToCity"|"ArrowRotateLeft"|"ArrowRotateRight"|"ArrowTrendDown"|"ArrowTrendUp"|"ArrowTurnDown"|"ArrowTurnUp"|"ArrowUp"|"ArrowUp19"|"ArrowUp91"|"ArrowUpAZ"|"ArrowUpFromBracket"|"ArrowUpFromGroundWater"|"ArrowUpFromWaterPump"|"ArrowUpLong"|"ArrowUpRightDots"|"ArrowUpRightFromSquare"|"ArrowUpShortWide"|"ArrowUpWideShort"|"ArrowUpZA"|"ArrowsDownToLine"|"ArrowsDownToPeople"|"ArrowsLeftRight"|"ArrowsLeftRightToLine"|"ArrowsRotate"|"ArrowsSpin"|"ArrowsSplitUpAndLeft"|"ArrowsToCircle"|"ArrowsToDot"|"ArrowsToEye"|"ArrowsTurnRight"|"ArrowsTurnToDots"|"ArrowsUpDown"|"ArrowsUpDownLeftRight"|"ArrowsUpToLine"|"Asterisk"|"At"|"Atom"|"AudioDescription"|"AustralSign"|"Award"|"B"|"Baby"|"BabyCarriage"|"Backward"|"BackwardFast"|"BackwardStep"|"Bacon"|"Bacteria"|"Bacterium"|"BagShopping"|"Bahai"|"BahtSign"|"Ban"|"BanSmoking"|"Bandage"|"BangladeshiTakaSign"|"Barcode"|"Bars"|"BarsProgress"|"BarsStaggered"|"Baseball"|"BaseballBatBall"|"BasketShopping"|"Basketball"|"Bath"|"BatteryEmpty"|"BatteryFull"|"BatteryHalf"|"BatteryQuarter"|"BatteryThreeQuarters"|"Bed"|"BedPulse"|"BeerMugEmpty"|"Bell"|"BellConcierge"|"BellSlash"|"BezierCurve"|"Bicycle"|"Binoculars"|"Biohazard"|"BitcoinSign"|"Blender"|"BlenderPhone"|"Blog"|"Bold"|"Bolt"|"BoltLightning"|"Bomb"|"Bone"|"Bong"|"Book"|"BookAtlas"|"BookBible"|"BookBookmark"|"BookJournalWhills"|"BookMedical"|"BookOpen"|"BookOpenReader"|"BookQuran"|"BookSkull"|"BookTanakh"|"Bookmark"|"BorderAll"|"BorderNone"|"BorderTopLeft"|"BoreHole"|"BottleDroplet"|"BottleWater"|"BowlFood"|"BowlRice"|"BowlingBall"|"Box"|"BoxArchive"|"BoxOpen"|"BoxTissue"|"BoxesPacking"|"BoxesStacked"|"Braille"|"Brain"|"BrazilianRealSign"|"BreadSlice"|"Bridge"|"BridgeCircleCheck"|"BridgeCircleExclamation"|"BridgeCircleXmark"|"BridgeLock"|"BridgeWater"|"Briefcase"|"BriefcaseMedical"|"Broom"|"BroomBall"|"Brush"|"Bucket"|"Bug"|"BugSlash"|"Bugs"|"Building"|"BuildingCircleArrowRight"|"BuildingCircleCheck"|"BuildingCircleExclamation"|"BuildingCircleXmark"|"BuildingColumns"|"BuildingFlag"|"BuildingLock"|"BuildingNgo"|"BuildingShield"|"BuildingUn"|"BuildingUser"|"BuildingWheat"|"Bullhorn"|"Bullseye"|"Burger"|"Burst"|"Bus"|"BusSimple"|"BusinessTime"|"C"|"CableCar"|"CakeCandles"|"Calculator"|"Calendar"|"CalendarCheck"|"CalendarDay"|"CalendarDays"|"CalendarMinus"|"CalendarPlus"|"CalendarWeek"|"CalendarXmark"|"Camera"|"CameraRetro"|"CameraRotate"|"Campground"|"CandyCane"|"Cannabis"|"Capsules"|"Car"|"CarBattery"|"CarBurst"|"CarOn"|"CarRear"|"CarSide"|"CarTunnel"|"Caravan"|"CaretDown"|"CaretLeft"|"CaretRight"|"CaretUp"|"Carrot"|"CartArrowDown"|"CartFlatbed"|"CartFlatbedSuitcase"|"CartPlus"|"CartShopping"|"CashRegister"|"Cat"|"CediSign"|"CentSign"|"Certificate"|"Chair"|"Chalkboard"|"ChalkboardUser"|"ChampagneGlasses"|"ChargingStation"|"ChartArea"|"ChartBar"|"ChartColumn"|"ChartDiagram"|"ChartGantt"|"ChartLine"|"ChartPie"|"ChartSimple"|"Check"|"CheckDouble"|"CheckToSlot"|"Cheese"|"Chess"|"ChessBishop"|"ChessBoard"|"ChessKing"|"ChessKnight"|"ChessPawn"|"ChessQueen"|"ChessRook"|"ChevronDown"|"ChevronLeft"|"ChevronRight"|"ChevronUp"|"Child"|"ChildCombatant"|"ChildDress"|"ChildReaching"|"Children"|"Church"|"Circle"|"CircleArrowDown"|"CircleArrowLeft"|"CircleArrowRight"|"CircleArrowUp"|"CircleCheck"|"CircleChevronDown"|"CircleChevronLeft"|"CircleChevronRight"|"CircleChevronUp"|"CircleDollarToSlot"|"CircleDot"|"CircleDown"|"CircleExclamation"|"CircleH"|"CircleHalfStroke"|"CircleInfo"|"CircleLeft"|"CircleMinus"|"CircleNodes"|"CircleNotch"|"CirclePause"|"CirclePlay"|"CirclePlus"|"CircleQuestion"|"CircleRadiation"|"CircleRight"|"CircleStop"|"CircleUp"|"CircleUser"|"CircleXmark"|"City"|"Clapperboard"|"Clipboard"|"ClipboardCheck"|"ClipboardList"|"ClipboardQuestion"|"ClipboardUser"|"Clock"|"ClockRotateLeft"|"Clone"|"ClosedCaptioning"|"Cloud"|"CloudArrowDown"|"CloudArrowUp"|"CloudBolt"|"CloudMeatball"|"CloudMoon"|"CloudMoonRain"|"CloudRain"|"CloudShowersHeavy"|"CloudShowersWater"|"CloudSun"|"CloudSunRain"|"Clover"|"Code"|"CodeBranch"|"CodeCommit"|"CodeCompare"|"CodeFork"|"CodeMerge"|"CodePullRequest"|"Coins"|"ColonSign"|"Comment"|"CommentDollar"|"CommentDots"|"CommentMedical"|"CommentNodes"|"CommentSlash"|"CommentSms"|"Comments"|"CommentsDollar"|"CompactDisc"|"Compass"|"CompassDrafting"|"Compress"|"Computer"|"ComputerMouse"|"Cookie"|"CookieBite"|"Copy"|"Copyright"|"Couch"|"Cow"|"CreditCard"|"Crop"|"CropSimple"|"Cross"|"Crosshairs"|"Crow"|"Crown"|"Crutch"|"CruzeiroSign"|"Cube"|"Cubes"|"CubesStacked"|"D"|"Database"|"DeleteLeft"|"Democrat"|"Desktop"|"Dharmachakra"|"DiagramNext"|"DiagramPredecessor"|"DiagramProject"|"DiagramSuccessor"|"Diamond"|"DiamondTurnRight"|"Dice"|"DiceD20"|"DiceD6"|"DiceFive"|"DiceFour"|"DiceOne"|"DiceSix"|"DiceThree"|"DiceTwo"|"Disease"|"Display"|"Divide"|"Dna"|"Dog"|"DollarSign"|"Dolly"|"DongSign"|"DoorClosed"|"DoorOpen"|"Dove"|"DownLeftAndUpRightToCenter"|"DownLong"|"Download"|"Dragon"|"DrawPolygon"|"Droplet"|"DropletSlash"|"Drum"|"DrumSteelpan"|"DrumstickBite"|"Dumbbell"|"Dumpster"|"DumpsterFire"|"Dungeon"|"E"|"EarDeaf"|"EarListen"|"EarthAfrica"|"EarthAmericas"|"EarthAsia"|"EarthEurope"|"EarthOceania"|"Egg"|"Eject"|"Elevator"|"Ellipsis"|"EllipsisVertical"|"Envelope"|"EnvelopeCircleCheck"|"EnvelopeOpen"|"EnvelopeOpenText"|"EnvelopesBulk"|"Equals"|"Eraser"|"Ethernet"|"EuroSign"|"Exclamation"|"Expand"|"Explosion"|"Eye"|"EyeDropper"|"EyeLowVision"|"EyeSlash"|"F"|"FaceAngry"|"FaceDizzy"|"FaceFlushed"|"FaceFrown"|"FaceFrownOpen"|"FaceGrimace"|"FaceGrin"|"FaceGrinBeam"|"FaceGrinBeamSweat"|"FaceGrinHearts"|"FaceGrinSquint"|"FaceGrinSquintTears"|"FaceGrinStars"|"FaceGrinTears"|"FaceGrinTongue"|"FaceGrinTongueSquint"|"FaceGrinTongueWink"|"FaceGrinWide"|"FaceGrinWink"|"FaceKiss"|"FaceKissBeam"|"FaceKissWinkHeart"|"FaceLaugh"|"FaceLaughBeam"|"FaceLaughSquint"|"FaceLaughWink"|"FaceMeh"|"FaceMehBlank"|"FaceRollingEyes"|"FaceSadCry"|"FaceSadTear"|"FaceSmile"|"FaceSmileBeam"|"FaceSmileWink"|"FaceSurprise"|"FaceTired"|"Fan"|"Faucet"|"FaucetDrip"|"Fax"|"Feather"|"FeatherPointed"|"Ferry"|"File"|"FileArrowDown"|"FileArrowUp"|"FileAudio"|"FileCircleCheck"|"FileCircleExclamation"|"FileCircleMinus"|"FileCirclePlus"|"FileCircleQuestion"|"FileCircleXmark"|"FileCode"|"FileContract"|"FileCsv"|"FileExcel"|"FileExport"|"FileFragment"|"FileHalfDashed"|"FileImage"|"FileImport"|"FileInvoice"|"FileInvoiceDollar"|"FileLines"|"FileMedical"|"FilePdf"|"FilePen"|"FilePowerpoint"|"FilePrescription"|"FileShield"|"FileSignature"|"FileVideo"|"FileWaveform"|"FileWord"|"FileZipper"|"Fill"|"FillDrip"|"Film"|"Filter"|"FilterCircleDollar"|"FilterCircleXmark"|"Fingerprint"|"Fire"|"FireBurner"|"FireExtinguisher"|"FireFlameCurved"|"FireFlameSimple"|"Fish"|"FishFins"|"Flag"|"FlagCheckered"|"FlagUsa"|"Flask"|"FlaskVial"|"FloppyDisk"|"FlorinSign"|"Folder"|"FolderClosed"|"FolderMinus"|"FolderOpen"|"FolderPlus"|"FolderTree"|"Font"|"FontAwesome"|"Football"|"Forward"|"ForwardFast"|"ForwardStep"|"FrancSign"|"Frog"|"Futbol"|"G"|"Gamepad"|"GasPump"|"Gauge"|"GaugeHigh"|"GaugeSimple"|"GaugeSimpleHigh"|"Gavel"|"Gear"|"Gears"|"Gem"|"Genderless"|"Ghost"|"Gift"|"Gifts"|"GlassWater"|"GlassWaterDroplet"|"Glasses"|"Globe"|"GolfBallTee"|"Gopuram"|"GraduationCap"|"GreaterThan"|"GreaterThanEqual"|"Grip"|"GripLines"|"GripLinesVertical"|"GripVertical"|"GroupArrowsRotate"|"GuaraniSign"|"Guitar"|"Gun"|"H"|"Hammer"|"Hamsa"|"Hand"|"HandBackFist"|"HandDots"|"HandFist"|"HandHolding"|"HandHoldingDollar"|"HandHoldingDroplet"|"HandHoldingHand"|"HandHoldingHeart"|"HandHoldingMedical"|"HandLizard"|"HandMiddleFinger"|"HandPeace"|"HandPointDown"|"HandPointLeft"|"HandPointRight"|"HandPointUp"|"HandPointer"|"HandScissors"|"HandSparkles"|"HandSpock"|"Handcuffs"|"Hands"|"HandsAslInterpreting"|"HandsBound"|"HandsBubbles"|"HandsClapping"|"HandsHolding"|"HandsHoldingChild"|"HandsHoldingCircle"|"HandsPraying"|"Handshake"|"HandshakeAngle"|"HandshakeSimple"|"HandshakeSimpleSlash"|"HandshakeSlash"|"Hanukiah"|"HardDrive"|"Hashtag"|"HatCowboy"|"HatCowboySide"|"HatWizard"|"HeadSideCough"|"HeadSideCoughSlash"|"HeadSideMask"|"HeadSideVirus"|"Heading"|"Headphones"|"HeadphonesSimple"|"Headset"|"Heart"|"HeartCircleBolt"|"HeartCircleCheck"|"HeartCircleExclamation"|"HeartCircleMinus"|"HeartCirclePlus"|"HeartCircleXmark"|"HeartCrack"|"HeartPulse"|"Helicopter"|"HelicopterSymbol"|"HelmetSafety"|"HelmetUn"|"HexagonNodes"|"HexagonNodesBolt"|"Highlighter"|"HillAvalanche"|"HillRockslide"|"Hippo"|"HockeyPuck"|"HollyBerry"|"Horse"|"HorseHead"|"Hospital"|"HospitalUser"|"HotTubPerson"|"Hotdog"|"Hotel"|"Hourglass"|"HourglassEnd"|"HourglassHalf"|"HourglassStart"|"House"|"HouseChimney"|"HouseChimneyCrack"|"HouseChimneyMedical"|"HouseChimneyUser"|"HouseChimneyWindow"|"HouseCircleCheck"|"HouseCircleExclamation"|"HouseCircleXmark"|"HouseCrack"|"HouseFire"|"HouseFlag"|"HouseFloodWater"|"HouseFloodWaterCircleArrowRight"|"HouseLaptop"|"HouseLock"|"HouseMedical"|"HouseMedicalCircleCheck"|"HouseMedicalCircleExclamation"|"HouseMedicalCircleXmark"|"HouseMedicalFlag"|"HouseSignal"|"HouseTsunami"|"HouseUser"|"HryvniaSign"|"Hurricane"|"I"|"ICursor"|"IceCream"|"Icicles"|"Icons"|"IdBadge"|"IdCard"|"IdCardClip"|"Igloo"|"Image"|"ImagePortrait"|"Images"|"Inbox"|"Indent"|"IndianRupeeSign"|"Industry"|"Infinity"|"Info"|"Italic"|"J"|"Jar"|"JarWheat"|"Jedi"|"JetFighter"|"JetFighterUp"|"Joint"|"JugDetergent"|"K"|"Kaaba"|"Key"|"Keyboard"|"Khanda"|"KipSign"|"KitMedical"|"KitchenSet"|"KiwiBird"|"L"|"LandMineOn"|"Landmark"|"LandmarkDome"|"LandmarkFlag"|"Language"|"Laptop"|"LaptopCode"|"LaptopFile"|"LaptopMedical"|"LariSign"|"LayerGroup"|"Leaf"|"LeftLong"|"LeftRight"|"Lemon"|"LessThan"|"LessThanEqual"|"LifeRing"|"Lightbulb"|"LinesLeaning"|"Link"|"LinkSlash"|"LiraSign"|"List"|"ListCheck"|"ListOl"|"ListUl"|"LitecoinSign"|"LocationArrow"|"LocationCrosshairs"|"LocationDot"|"LocationPin"|"LocationPinLock"|"Lock"|"LockOpen"|"Locust"|"Lungs"|"LungsVirus"|"M"|"Magnet"|"MagnifyingGlass"|"MagnifyingGlassArrowRight"|"MagnifyingGlassChart"|"MagnifyingGlassDollar"|"MagnifyingGlassLocation"|"MagnifyingGlassMinus"|"MagnifyingGlassPlus"|"ManatSign"|"Map"|"MapLocation"|"MapLocationDot"|"MapPin"|"Marker"|"Mars"|"MarsAndVenus"|"MarsAndVenusBurst"|"MarsDouble"|"MarsStroke"|"MarsStrokeRight"|"MarsStrokeUp"|"MartiniGlass"|"MartiniGlassCitrus"|"MartiniGlassEmpty"|"Mask"|"MaskFace"|"MaskVentilator"|"MasksTheater"|"MattressPillow"|"Maximize"|"Medal"|"Memory"|"Menorah"|"Mercury"|"Message"|"Meteor"|"Microchip"|"Microphone"|"MicrophoneLines"|"MicrophoneLinesSlash"|"MicrophoneSlash"|"Microscope"|"MillSign"|"Minimize"|"Minus"|"Mitten"|"Mobile"|"MobileButton"|"MobileRetro"|"MobileScreen"|"MobileScreenButton"|"MoneyBill"|"MoneyBill1"|"MoneyBill1Wave"|"MoneyBillTransfer"|"MoneyBillTrendUp"|"MoneyBillWave"|"MoneyBillWheat"|"MoneyBills"|"MoneyCheck"|"MoneyCheckDollar"|"Monument"|"Moon"|"MortarPestle"|"Mosque"|"Mosquito"|"MosquitoNet"|"Motorcycle"|"Mound"|"Mountain"|"MountainCity"|"MountainSun"|"MugHot"|"MugSaucer"|"Music"|"N"|"NairaSign"|"NetworkWired"|"Neuter"|"Newspaper"|"NotEqual"|"Notdef"|"NoteSticky"|"NotesMedical"|"O"|"ObjectGroup"|"ObjectUngroup"|"OilCan"|"OilWell"|"Om"|"Otter"|"Outdent"|"P"|"Pager"|"PaintRoller"|"Paintbrush"|"Palette"|"Pallet"|"Panorama"|"PaperPlane"|"Paperclip"|"ParachuteBox"|"Paragraph"|"Passport"|"Paste"|"Pause"|"Paw"|"Peace"|"Pen"|"PenClip"|"PenFancy"|"PenNib"|"PenRuler"|"PenToSquare"|"Pencil"|"PeopleArrows"|"PeopleCarryBox"|"PeopleGroup"|"PeopleLine"|"PeoplePulling"|"PeopleRobbery"|"PeopleRoof"|"PepperHot"|"Percent"|"Person"|"PersonArrowDownToLine"|"PersonArrowUpFromLine"|"PersonBiking"|"PersonBooth"|"PersonBreastfeeding"|"PersonBurst"|"PersonCane"|"PersonChalkboard"|"PersonCircleCheck"|"PersonCircleExclamation"|"PersonCircleMinus"|"PersonCirclePlus"|"PersonCircleQuestion"|"PersonCircleXmark"|"PersonDigging"|"PersonDotsFromLine"|"PersonDress"|"PersonDressBurst"|"PersonDrowning"|"PersonFalling"|"PersonFallingBurst"|"PersonHalfDress"|"PersonHarassing"|"PersonHiking"|"PersonMilitaryPointing"|"PersonMilitaryRifle"|"PersonMilitaryToPerson"|"PersonPraying"|"PersonPregnant"|"PersonRays"|"PersonRifle"|"PersonRunning"|"PersonShelter"|"PersonSkating"|"PersonSkiing"|"PersonSkiingNordic"|"PersonSnowboarding"|"PersonSwimming"|"PersonThroughWindow"|"PersonWalking"|"PersonWalkingArrowLoopLeft"|"PersonWalkingArrowRight"|"PersonWalkingDashedLineArrowRight"|"PersonWalkingLuggage"|"PersonWalkingWithCane"|"PesetaSign"|"PesoSign"|"Phone"|"PhoneFlip"|"PhoneSlash"|"PhoneVolume"|"PhotoFilm"|"PiggyBank"|"Pills"|"PizzaSlice"|"PlaceOfWorship"|"Plane"|"PlaneArrival"|"PlaneCircleCheck"|"PlaneCircleExclamation"|"PlaneCircleXmark"|"PlaneDeparture"|"PlaneLock"|"PlaneSlash"|"PlaneUp"|"PlantWilt"|"PlateWheat"|"Play"|"Plug"|"PlugCircleBolt"|"PlugCircleCheck"|"PlugCircleExclamation"|"PlugCircleMinus"|"PlugCirclePlus"|"PlugCircleXmark"|"Plus"|"PlusMinus"|"Podcast"|"Poo"|"PooStorm"|"Poop"|"PowerOff"|"Prescription"|"PrescriptionBottle"|"PrescriptionBottleMedical"|"Print"|"PumpMedical"|"PumpSoap"|"PuzzlePiece"|"Q"|"Qrcode"|"Question"|"QuoteLeft"|"QuoteRight"|"R"|"Radiation"|"Radio"|"Rainbow"|"RankingStar"|"Receipt"|"RecordVinyl"|"RectangleAd"|"RectangleList"|"RectangleXmark"|"Recycle"|"Registered"|"Repeat"|"Reply"|"ReplyAll"|"Republican"|"Restroom"|"Retweet"|"Ribbon"|"RightFromBracket"|"RightLeft"|"RightLong"|"RightToBracket"|"Ring"|"Road"|"RoadBarrier"|"RoadBridge"|"RoadCircleCheck"|"RoadCircleExclamation"|"RoadCircleXmark"|"RoadLock"|"RoadSpikes"|"Robot"|"Rocket"|"Rotate"|"RotateLeft"|"RotateRight"|"Route"|"Rss"|"RubleSign"|"Rug"|"Ruler"|"RulerCombined"|"RulerHorizontal"|"RulerVertical"|"RupeeSign"|"RupiahSign"|"S"|"SackDollar"|"SackXmark"|"Sailboat"|"Satellite"|"SatelliteDish"|"ScaleBalanced"|"ScaleUnbalanced"|"ScaleUnbalancedFlip"|"School"|"SchoolCircleCheck"|"SchoolCircleExclamation"|"SchoolCircleXmark"|"SchoolFlag"|"SchoolLock"|"Scissors"|"Screwdriver"|"ScrewdriverWrench"|"Scroll"|"ScrollTorah"|"SdCard"|"Section"|"Seedling"|"Server"|"Shapes"|"Share"|"ShareFromSquare"|"ShareNodes"|"SheetPlastic"|"ShekelSign"|"Shield"|"ShieldCat"|"ShieldDog"|"ShieldHalved"|"ShieldHeart"|"ShieldVirus"|"Ship"|"Shirt"|"ShoePrints"|"Shop"|"ShopLock"|"ShopSlash"|"Shower"|"Shrimp"|"Shuffle"|"ShuttleSpace"|"SignHanging"|"Signal"|"Signature"|"SignsPost"|"SimCard"|"Sink"|"Sitemap"|"Skull"|"SkullCrossbones"|"Slash"|"Sleigh"|"Sliders"|"Smog"|"Smoking"|"Snowflake"|"Snowman"|"Snowplow"|"Soap"|"Socks"|"SolarPanel"|"Sort"|"SortDown"|"SortUp"|"Spa"|"SpaghettiMonsterFlying"|"SpellCheck"|"Spider"|"Spinner"|"Splotch"|"Spoon"|"SprayCan"|"SprayCanSparkles"|"Square"|"SquareArrowUpRight"|"SquareBinary"|"SquareCaretDown"|"SquareCaretLeft"|"SquareCaretRight"|"SquareCaretUp"|"SquareCheck"|"SquareEnvelope"|"SquareFull"|"SquareH"|"SquareMinus"|"SquareNfi"|"SquareParking"|"SquarePen"|"SquarePersonConfined"|"SquarePhone"|"SquarePhoneFlip"|"SquarePlus"|"SquarePollHorizontal"|"SquarePollVertical"|"SquareRootVariable"|"SquareRss"|"SquareShareNodes"|"SquareUpRight"|"SquareVirus"|"SquareXmark"|"StaffSnake"|"Stairs"|"Stamp"|"Stapler"|"Star"|"StarAndCrescent"|"StarHalf"|"StarHalfStroke"|"StarOfDavid"|"StarOfLife"|"SterlingSign"|"Stethoscope"|"Stop"|"Stopwatch"|"Stopwatch20"|"Store"|"StoreSlash"|"StreetView"|"Strikethrough"|"Stroopwafel"|"Subscript"|"Suitcase"|"SuitcaseMedical"|"SuitcaseRolling"|"Sun"|"SunPlantWilt"|"Superscript"|"Swatchbook"|"Synagogue"|"Syringe"|"T"|"Table"|"TableCells"|"TableCellsColumnLock"|"TableCellsLarge"|"TableCellsRowLock"|"TableCellsRowUnlock"|"TableColumns"|"TableList"|"TableTennisPaddleBall"|"Tablet"|"TabletButton"|"TabletScreenButton"|"Tablets"|"TachographDigital"|"Tag"|"Tags"|"Tape"|"Tarp"|"TarpDroplet"|"Taxi"|"Teeth"|"TeethOpen"|"TemperatureArrowDown"|"TemperatureArrowUp"|"TemperatureEmpty"|"TemperatureFull"|"TemperatureHalf"|"TemperatureHigh"|"TemperatureLow"|"TemperatureQuarter"|"TemperatureThreeQuarters"|"TengeSign"|"Tent"|"TentArrowDownToLine"|"TentArrowLeftRight"|"TentArrowTurnLeft"|"TentArrowsDown"|"Tents"|"Terminal"|"TextHeight"|"TextSlash"|"TextWidth"|"Thermometer"|"ThumbsDown"|"ThumbsUp"|"Thumbtack"|"ThumbtackSlash"|"Ticket"|"TicketSimple"|"Timeline"|"ToggleOff"|"ToggleOn"|"Toilet"|"ToiletPaper"|"ToiletPaperSlash"|"ToiletPortable"|"ToiletsPortable"|"Toolbox"|"Tooth"|"ToriiGate"|"Tornado"|"TowerBroadcast"|"TowerCell"|"TowerObservation"|"Tractor"|"Trademark"|"TrafficLight"|"Trailer"|"Train"|"TrainSubway"|"TrainTram"|"Transgender"|"Trash"|"TrashArrowUp"|"TrashCan"|"TrashCanArrowUp"|"Tree"|"TreeCity"|"TriangleExclamation"|"Trophy"|"Trowel"|"TrowelBricks"|"Truck"|"TruckArrowRight"|"TruckDroplet"|"TruckFast"|"TruckField"|"TruckFieldUn"|"TruckFront"|"TruckMedical"|"TruckMonster"|"TruckMoving"|"TruckPickup"|"TruckPlane"|"TruckRampBox"|"Tty"|"TurkishLiraSign"|"TurnDown"|"TurnUp"|"Tv"|"U"|"Umbrella"|"UmbrellaBeach"|"Underline"|"UniversalAccess"|"Unlock"|"UnlockKeyhole"|"UpDown"|"UpDownLeftRight"|"UpLong"|"UpRightAndDownLeftFromCenter"|"UpRightFromSquare"|"Upload"|"User"|"UserAstronaut"|"UserCheck"|"UserClock"|"UserDoctor"|"UserGear"|"UserGraduate"|"UserGroup"|"UserInjured"|"UserLarge"|"UserLargeSlash"|"UserLock"|"UserMinus"|"UserNinja"|"UserNurse"|"UserPen"|"UserPlus"|"UserSecret"|"UserShield"|"UserSlash"|"UserTag"|"UserTie"|"UserXmark"|"Users"|"UsersBetweenLines"|"UsersGear"|"UsersLine"|"UsersRays"|"UsersRectangle"|"UsersSlash"|"UsersViewfinder"|"Utensils"|"V"|"VanShuttle"|"Vault"|"VectorSquare"|"Venus"|"VenusDouble"|"VenusMars"|"Vest"|"VestPatches"|"Vial"|"VialCircleCheck"|"VialVirus"|"Vials"|"Video"|"VideoSlash"|"Vihara"|"Virus"|"VirusCovid"|"VirusCovidSlash"|"VirusSlash"|"Viruses"|"Voicemail"|"Volcano"|"Volleyball"|"VolumeHigh"|"VolumeLow"|"VolumeOff"|"VolumeXmark"|"VrCardboard"|"W"|"WalkieTalkie"|"Wallet"|"WandMagic"|"WandMagicSparkles"|"WandSparkles"|"Warehouse"|"Water"|"WaterLadder"|"WaveSquare"|"WebAwesome"|"WeightHanging"|"WeightScale"|"WheatAwn"|"WheatAwnCircleExclamation"|"Wheelchair"|"WheelchairMove"|"WhiskeyGlass"|"Wifi"|"Wind"|"WindowMaximize"|"WindowMinimize"|"WindowRestore"|"WineBottle"|"WineGlass"|"WineGlassEmpty"|"WonSign"|"Worm"|"Wrench"|"X"|"XRay"|"Xmark"|"XmarksLines"|"Y"|"YenSign"|"YinYang"|"Z"|"Search"|"Save"|"Settings"|"Cog"|"Home"|"Edit"|"Close"|"Cancel"|"Refresh"|"Warning"|"CheckCircle"|"TimesCircle"|"VolumeMute"|"Cut"|"Undo"|"Redo"|"StepForward"|"StepBackward"|"Pin"|"ZoomIn"|"ZoomOut"
---@overload fun(self: UIIconNode, path: "iconSize"): number
---@overload fun(self: UIIconNode, path: "color"): number[]
---@overload fun(self: UIIconNode, path: "align"): "Left"|"Center"|"Right"
function UIIconNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UIIconNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UIIconNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIIconNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIIconNode, path: "rotation", value: number)
---@overload fun(self: UIIconNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIIconNode, path: "zIndex", value: integer)
---@overload fun(self: UIIconNode, path: "ySort", value: boolean)
---@overload fun(self: UIIconNode, path: "ySortOffset", value: number)
---@overload fun(self: UIIconNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIIconNode, path: "paused", value: boolean)
---@overload fun(self: UIIconNode, path: "enabled", value: boolean)
---@overload fun(self: UIIconNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIIconNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UIIconNode, path: "icon", value: "None"|"Digit0"|"Digit1"|"Digit2"|"Digit3"|"Digit4"|"Digit5"|"Digit6"|"Digit7"|"Digit8"|"Digit9"|"A"|"AddressBook"|"AddressCard"|"AlignCenter"|"AlignJustify"|"AlignLeft"|"AlignRight"|"Anchor"|"AnchorCircleCheck"|"AnchorCircleExclamation"|"AnchorCircleXmark"|"AnchorLock"|"AngleDown"|"AngleLeft"|"AngleRight"|"AngleUp"|"AnglesDown"|"AnglesLeft"|"AnglesRight"|"AnglesUp"|"Ankh"|"AppleWhole"|"Archway"|"ArrowDown"|"ArrowDown19"|"ArrowDown91"|"ArrowDownAZ"|"ArrowDownLong"|"ArrowDownShortWide"|"ArrowDownUpAcrossLine"|"ArrowDownUpLock"|"ArrowDownWideShort"|"ArrowDownZA"|"ArrowLeft"|"ArrowLeftLong"|"ArrowPointer"|"ArrowRight"|"ArrowRightArrowLeft"|"ArrowRightFromBracket"|"ArrowRightLong"|"ArrowRightToBracket"|"ArrowRightToCity"|"ArrowRotateLeft"|"ArrowRotateRight"|"ArrowTrendDown"|"ArrowTrendUp"|"ArrowTurnDown"|"ArrowTurnUp"|"ArrowUp"|"ArrowUp19"|"ArrowUp91"|"ArrowUpAZ"|"ArrowUpFromBracket"|"ArrowUpFromGroundWater"|"ArrowUpFromWaterPump"|"ArrowUpLong"|"ArrowUpRightDots"|"ArrowUpRightFromSquare"|"ArrowUpShortWide"|"ArrowUpWideShort"|"ArrowUpZA"|"ArrowsDownToLine"|"ArrowsDownToPeople"|"ArrowsLeftRight"|"ArrowsLeftRightToLine"|"ArrowsRotate"|"ArrowsSpin"|"ArrowsSplitUpAndLeft"|"ArrowsToCircle"|"ArrowsToDot"|"ArrowsToEye"|"ArrowsTurnRight"|"ArrowsTurnToDots"|"ArrowsUpDown"|"ArrowsUpDownLeftRight"|"ArrowsUpToLine"|"Asterisk"|"At"|"Atom"|"AudioDescription"|"AustralSign"|"Award"|"B"|"Baby"|"BabyCarriage"|"Backward"|"BackwardFast"|"BackwardStep"|"Bacon"|"Bacteria"|"Bacterium"|"BagShopping"|"Bahai"|"BahtSign"|"Ban"|"BanSmoking"|"Bandage"|"BangladeshiTakaSign"|"Barcode"|"Bars"|"BarsProgress"|"BarsStaggered"|"Baseball"|"BaseballBatBall"|"BasketShopping"|"Basketball"|"Bath"|"BatteryEmpty"|"BatteryFull"|"BatteryHalf"|"BatteryQuarter"|"BatteryThreeQuarters"|"Bed"|"BedPulse"|"BeerMugEmpty"|"Bell"|"BellConcierge"|"BellSlash"|"BezierCurve"|"Bicycle"|"Binoculars"|"Biohazard"|"BitcoinSign"|"Blender"|"BlenderPhone"|"Blog"|"Bold"|"Bolt"|"BoltLightning"|"Bomb"|"Bone"|"Bong"|"Book"|"BookAtlas"|"BookBible"|"BookBookmark"|"BookJournalWhills"|"BookMedical"|"BookOpen"|"BookOpenReader"|"BookQuran"|"BookSkull"|"BookTanakh"|"Bookmark"|"BorderAll"|"BorderNone"|"BorderTopLeft"|"BoreHole"|"BottleDroplet"|"BottleWater"|"BowlFood"|"BowlRice"|"BowlingBall"|"Box"|"BoxArchive"|"BoxOpen"|"BoxTissue"|"BoxesPacking"|"BoxesStacked"|"Braille"|"Brain"|"BrazilianRealSign"|"BreadSlice"|"Bridge"|"BridgeCircleCheck"|"BridgeCircleExclamation"|"BridgeCircleXmark"|"BridgeLock"|"BridgeWater"|"Briefcase"|"BriefcaseMedical"|"Broom"|"BroomBall"|"Brush"|"Bucket"|"Bug"|"BugSlash"|"Bugs"|"Building"|"BuildingCircleArrowRight"|"BuildingCircleCheck"|"BuildingCircleExclamation"|"BuildingCircleXmark"|"BuildingColumns"|"BuildingFlag"|"BuildingLock"|"BuildingNgo"|"BuildingShield"|"BuildingUn"|"BuildingUser"|"BuildingWheat"|"Bullhorn"|"Bullseye"|"Burger"|"Burst"|"Bus"|"BusSimple"|"BusinessTime"|"C"|"CableCar"|"CakeCandles"|"Calculator"|"Calendar"|"CalendarCheck"|"CalendarDay"|"CalendarDays"|"CalendarMinus"|"CalendarPlus"|"CalendarWeek"|"CalendarXmark"|"Camera"|"CameraRetro"|"CameraRotate"|"Campground"|"CandyCane"|"Cannabis"|"Capsules"|"Car"|"CarBattery"|"CarBurst"|"CarOn"|"CarRear"|"CarSide"|"CarTunnel"|"Caravan"|"CaretDown"|"CaretLeft"|"CaretRight"|"CaretUp"|"Carrot"|"CartArrowDown"|"CartFlatbed"|"CartFlatbedSuitcase"|"CartPlus"|"CartShopping"|"CashRegister"|"Cat"|"CediSign"|"CentSign"|"Certificate"|"Chair"|"Chalkboard"|"ChalkboardUser"|"ChampagneGlasses"|"ChargingStation"|"ChartArea"|"ChartBar"|"ChartColumn"|"ChartDiagram"|"ChartGantt"|"ChartLine"|"ChartPie"|"ChartSimple"|"Check"|"CheckDouble"|"CheckToSlot"|"Cheese"|"Chess"|"ChessBishop"|"ChessBoard"|"ChessKing"|"ChessKnight"|"ChessPawn"|"ChessQueen"|"ChessRook"|"ChevronDown"|"ChevronLeft"|"ChevronRight"|"ChevronUp"|"Child"|"ChildCombatant"|"ChildDress"|"ChildReaching"|"Children"|"Church"|"Circle"|"CircleArrowDown"|"CircleArrowLeft"|"CircleArrowRight"|"CircleArrowUp"|"CircleCheck"|"CircleChevronDown"|"CircleChevronLeft"|"CircleChevronRight"|"CircleChevronUp"|"CircleDollarToSlot"|"CircleDot"|"CircleDown"|"CircleExclamation"|"CircleH"|"CircleHalfStroke"|"CircleInfo"|"CircleLeft"|"CircleMinus"|"CircleNodes"|"CircleNotch"|"CirclePause"|"CirclePlay"|"CirclePlus"|"CircleQuestion"|"CircleRadiation"|"CircleRight"|"CircleStop"|"CircleUp"|"CircleUser"|"CircleXmark"|"City"|"Clapperboard"|"Clipboard"|"ClipboardCheck"|"ClipboardList"|"ClipboardQuestion"|"ClipboardUser"|"Clock"|"ClockRotateLeft"|"Clone"|"ClosedCaptioning"|"Cloud"|"CloudArrowDown"|"CloudArrowUp"|"CloudBolt"|"CloudMeatball"|"CloudMoon"|"CloudMoonRain"|"CloudRain"|"CloudShowersHeavy"|"CloudShowersWater"|"CloudSun"|"CloudSunRain"|"Clover"|"Code"|"CodeBranch"|"CodeCommit"|"CodeCompare"|"CodeFork"|"CodeMerge"|"CodePullRequest"|"Coins"|"ColonSign"|"Comment"|"CommentDollar"|"CommentDots"|"CommentMedical"|"CommentNodes"|"CommentSlash"|"CommentSms"|"Comments"|"CommentsDollar"|"CompactDisc"|"Compass"|"CompassDrafting"|"Compress"|"Computer"|"ComputerMouse"|"Cookie"|"CookieBite"|"Copy"|"Copyright"|"Couch"|"Cow"|"CreditCard"|"Crop"|"CropSimple"|"Cross"|"Crosshairs"|"Crow"|"Crown"|"Crutch"|"CruzeiroSign"|"Cube"|"Cubes"|"CubesStacked"|"D"|"Database"|"DeleteLeft"|"Democrat"|"Desktop"|"Dharmachakra"|"DiagramNext"|"DiagramPredecessor"|"DiagramProject"|"DiagramSuccessor"|"Diamond"|"DiamondTurnRight"|"Dice"|"DiceD20"|"DiceD6"|"DiceFive"|"DiceFour"|"DiceOne"|"DiceSix"|"DiceThree"|"DiceTwo"|"Disease"|"Display"|"Divide"|"Dna"|"Dog"|"DollarSign"|"Dolly"|"DongSign"|"DoorClosed"|"DoorOpen"|"Dove"|"DownLeftAndUpRightToCenter"|"DownLong"|"Download"|"Dragon"|"DrawPolygon"|"Droplet"|"DropletSlash"|"Drum"|"DrumSteelpan"|"DrumstickBite"|"Dumbbell"|"Dumpster"|"DumpsterFire"|"Dungeon"|"E"|"EarDeaf"|"EarListen"|"EarthAfrica"|"EarthAmericas"|"EarthAsia"|"EarthEurope"|"EarthOceania"|"Egg"|"Eject"|"Elevator"|"Ellipsis"|"EllipsisVertical"|"Envelope"|"EnvelopeCircleCheck"|"EnvelopeOpen"|"EnvelopeOpenText"|"EnvelopesBulk"|"Equals"|"Eraser"|"Ethernet"|"EuroSign"|"Exclamation"|"Expand"|"Explosion"|"Eye"|"EyeDropper"|"EyeLowVision"|"EyeSlash"|"F"|"FaceAngry"|"FaceDizzy"|"FaceFlushed"|"FaceFrown"|"FaceFrownOpen"|"FaceGrimace"|"FaceGrin"|"FaceGrinBeam"|"FaceGrinBeamSweat"|"FaceGrinHearts"|"FaceGrinSquint"|"FaceGrinSquintTears"|"FaceGrinStars"|"FaceGrinTears"|"FaceGrinTongue"|"FaceGrinTongueSquint"|"FaceGrinTongueWink"|"FaceGrinWide"|"FaceGrinWink"|"FaceKiss"|"FaceKissBeam"|"FaceKissWinkHeart"|"FaceLaugh"|"FaceLaughBeam"|"FaceLaughSquint"|"FaceLaughWink"|"FaceMeh"|"FaceMehBlank"|"FaceRollingEyes"|"FaceSadCry"|"FaceSadTear"|"FaceSmile"|"FaceSmileBeam"|"FaceSmileWink"|"FaceSurprise"|"FaceTired"|"Fan"|"Faucet"|"FaucetDrip"|"Fax"|"Feather"|"FeatherPointed"|"Ferry"|"File"|"FileArrowDown"|"FileArrowUp"|"FileAudio"|"FileCircleCheck"|"FileCircleExclamation"|"FileCircleMinus"|"FileCirclePlus"|"FileCircleQuestion"|"FileCircleXmark"|"FileCode"|"FileContract"|"FileCsv"|"FileExcel"|"FileExport"|"FileFragment"|"FileHalfDashed"|"FileImage"|"FileImport"|"FileInvoice"|"FileInvoiceDollar"|"FileLines"|"FileMedical"|"FilePdf"|"FilePen"|"FilePowerpoint"|"FilePrescription"|"FileShield"|"FileSignature"|"FileVideo"|"FileWaveform"|"FileWord"|"FileZipper"|"Fill"|"FillDrip"|"Film"|"Filter"|"FilterCircleDollar"|"FilterCircleXmark"|"Fingerprint"|"Fire"|"FireBurner"|"FireExtinguisher"|"FireFlameCurved"|"FireFlameSimple"|"Fish"|"FishFins"|"Flag"|"FlagCheckered"|"FlagUsa"|"Flask"|"FlaskVial"|"FloppyDisk"|"FlorinSign"|"Folder"|"FolderClosed"|"FolderMinus"|"FolderOpen"|"FolderPlus"|"FolderTree"|"Font"|"FontAwesome"|"Football"|"Forward"|"ForwardFast"|"ForwardStep"|"FrancSign"|"Frog"|"Futbol"|"G"|"Gamepad"|"GasPump"|"Gauge"|"GaugeHigh"|"GaugeSimple"|"GaugeSimpleHigh"|"Gavel"|"Gear"|"Gears"|"Gem"|"Genderless"|"Ghost"|"Gift"|"Gifts"|"GlassWater"|"GlassWaterDroplet"|"Glasses"|"Globe"|"GolfBallTee"|"Gopuram"|"GraduationCap"|"GreaterThan"|"GreaterThanEqual"|"Grip"|"GripLines"|"GripLinesVertical"|"GripVertical"|"GroupArrowsRotate"|"GuaraniSign"|"Guitar"|"Gun"|"H"|"Hammer"|"Hamsa"|"Hand"|"HandBackFist"|"HandDots"|"HandFist"|"HandHolding"|"HandHoldingDollar"|"HandHoldingDroplet"|"HandHoldingHand"|"HandHoldingHeart"|"HandHoldingMedical"|"HandLizard"|"HandMiddleFinger"|"HandPeace"|"HandPointDown"|"HandPointLeft"|"HandPointRight"|"HandPointUp"|"HandPointer"|"HandScissors"|"HandSparkles"|"HandSpock"|"Handcuffs"|"Hands"|"HandsAslInterpreting"|"HandsBound"|"HandsBubbles"|"HandsClapping"|"HandsHolding"|"HandsHoldingChild"|"HandsHoldingCircle"|"HandsPraying"|"Handshake"|"HandshakeAngle"|"HandshakeSimple"|"HandshakeSimpleSlash"|"HandshakeSlash"|"Hanukiah"|"HardDrive"|"Hashtag"|"HatCowboy"|"HatCowboySide"|"HatWizard"|"HeadSideCough"|"HeadSideCoughSlash"|"HeadSideMask"|"HeadSideVirus"|"Heading"|"Headphones"|"HeadphonesSimple"|"Headset"|"Heart"|"HeartCircleBolt"|"HeartCircleCheck"|"HeartCircleExclamation"|"HeartCircleMinus"|"HeartCirclePlus"|"HeartCircleXmark"|"HeartCrack"|"HeartPulse"|"Helicopter"|"HelicopterSymbol"|"HelmetSafety"|"HelmetUn"|"HexagonNodes"|"HexagonNodesBolt"|"Highlighter"|"HillAvalanche"|"HillRockslide"|"Hippo"|"HockeyPuck"|"HollyBerry"|"Horse"|"HorseHead"|"Hospital"|"HospitalUser"|"HotTubPerson"|"Hotdog"|"Hotel"|"Hourglass"|"HourglassEnd"|"HourglassHalf"|"HourglassStart"|"House"|"HouseChimney"|"HouseChimneyCrack"|"HouseChimneyMedical"|"HouseChimneyUser"|"HouseChimneyWindow"|"HouseCircleCheck"|"HouseCircleExclamation"|"HouseCircleXmark"|"HouseCrack"|"HouseFire"|"HouseFlag"|"HouseFloodWater"|"HouseFloodWaterCircleArrowRight"|"HouseLaptop"|"HouseLock"|"HouseMedical"|"HouseMedicalCircleCheck"|"HouseMedicalCircleExclamation"|"HouseMedicalCircleXmark"|"HouseMedicalFlag"|"HouseSignal"|"HouseTsunami"|"HouseUser"|"HryvniaSign"|"Hurricane"|"I"|"ICursor"|"IceCream"|"Icicles"|"Icons"|"IdBadge"|"IdCard"|"IdCardClip"|"Igloo"|"Image"|"ImagePortrait"|"Images"|"Inbox"|"Indent"|"IndianRupeeSign"|"Industry"|"Infinity"|"Info"|"Italic"|"J"|"Jar"|"JarWheat"|"Jedi"|"JetFighter"|"JetFighterUp"|"Joint"|"JugDetergent"|"K"|"Kaaba"|"Key"|"Keyboard"|"Khanda"|"KipSign"|"KitMedical"|"KitchenSet"|"KiwiBird"|"L"|"LandMineOn"|"Landmark"|"LandmarkDome"|"LandmarkFlag"|"Language"|"Laptop"|"LaptopCode"|"LaptopFile"|"LaptopMedical"|"LariSign"|"LayerGroup"|"Leaf"|"LeftLong"|"LeftRight"|"Lemon"|"LessThan"|"LessThanEqual"|"LifeRing"|"Lightbulb"|"LinesLeaning"|"Link"|"LinkSlash"|"LiraSign"|"List"|"ListCheck"|"ListOl"|"ListUl"|"LitecoinSign"|"LocationArrow"|"LocationCrosshairs"|"LocationDot"|"LocationPin"|"LocationPinLock"|"Lock"|"LockOpen"|"Locust"|"Lungs"|"LungsVirus"|"M"|"Magnet"|"MagnifyingGlass"|"MagnifyingGlassArrowRight"|"MagnifyingGlassChart"|"MagnifyingGlassDollar"|"MagnifyingGlassLocation"|"MagnifyingGlassMinus"|"MagnifyingGlassPlus"|"ManatSign"|"Map"|"MapLocation"|"MapLocationDot"|"MapPin"|"Marker"|"Mars"|"MarsAndVenus"|"MarsAndVenusBurst"|"MarsDouble"|"MarsStroke"|"MarsStrokeRight"|"MarsStrokeUp"|"MartiniGlass"|"MartiniGlassCitrus"|"MartiniGlassEmpty"|"Mask"|"MaskFace"|"MaskVentilator"|"MasksTheater"|"MattressPillow"|"Maximize"|"Medal"|"Memory"|"Menorah"|"Mercury"|"Message"|"Meteor"|"Microchip"|"Microphone"|"MicrophoneLines"|"MicrophoneLinesSlash"|"MicrophoneSlash"|"Microscope"|"MillSign"|"Minimize"|"Minus"|"Mitten"|"Mobile"|"MobileButton"|"MobileRetro"|"MobileScreen"|"MobileScreenButton"|"MoneyBill"|"MoneyBill1"|"MoneyBill1Wave"|"MoneyBillTransfer"|"MoneyBillTrendUp"|"MoneyBillWave"|"MoneyBillWheat"|"MoneyBills"|"MoneyCheck"|"MoneyCheckDollar"|"Monument"|"Moon"|"MortarPestle"|"Mosque"|"Mosquito"|"MosquitoNet"|"Motorcycle"|"Mound"|"Mountain"|"MountainCity"|"MountainSun"|"MugHot"|"MugSaucer"|"Music"|"N"|"NairaSign"|"NetworkWired"|"Neuter"|"Newspaper"|"NotEqual"|"Notdef"|"NoteSticky"|"NotesMedical"|"O"|"ObjectGroup"|"ObjectUngroup"|"OilCan"|"OilWell"|"Om"|"Otter"|"Outdent"|"P"|"Pager"|"PaintRoller"|"Paintbrush"|"Palette"|"Pallet"|"Panorama"|"PaperPlane"|"Paperclip"|"ParachuteBox"|"Paragraph"|"Passport"|"Paste"|"Pause"|"Paw"|"Peace"|"Pen"|"PenClip"|"PenFancy"|"PenNib"|"PenRuler"|"PenToSquare"|"Pencil"|"PeopleArrows"|"PeopleCarryBox"|"PeopleGroup"|"PeopleLine"|"PeoplePulling"|"PeopleRobbery"|"PeopleRoof"|"PepperHot"|"Percent"|"Person"|"PersonArrowDownToLine"|"PersonArrowUpFromLine"|"PersonBiking"|"PersonBooth"|"PersonBreastfeeding"|"PersonBurst"|"PersonCane"|"PersonChalkboard"|"PersonCircleCheck"|"PersonCircleExclamation"|"PersonCircleMinus"|"PersonCirclePlus"|"PersonCircleQuestion"|"PersonCircleXmark"|"PersonDigging"|"PersonDotsFromLine"|"PersonDress"|"PersonDressBurst"|"PersonDrowning"|"PersonFalling"|"PersonFallingBurst"|"PersonHalfDress"|"PersonHarassing"|"PersonHiking"|"PersonMilitaryPointing"|"PersonMilitaryRifle"|"PersonMilitaryToPerson"|"PersonPraying"|"PersonPregnant"|"PersonRays"|"PersonRifle"|"PersonRunning"|"PersonShelter"|"PersonSkating"|"PersonSkiing"|"PersonSkiingNordic"|"PersonSnowboarding"|"PersonSwimming"|"PersonThroughWindow"|"PersonWalking"|"PersonWalkingArrowLoopLeft"|"PersonWalkingArrowRight"|"PersonWalkingDashedLineArrowRight"|"PersonWalkingLuggage"|"PersonWalkingWithCane"|"PesetaSign"|"PesoSign"|"Phone"|"PhoneFlip"|"PhoneSlash"|"PhoneVolume"|"PhotoFilm"|"PiggyBank"|"Pills"|"PizzaSlice"|"PlaceOfWorship"|"Plane"|"PlaneArrival"|"PlaneCircleCheck"|"PlaneCircleExclamation"|"PlaneCircleXmark"|"PlaneDeparture"|"PlaneLock"|"PlaneSlash"|"PlaneUp"|"PlantWilt"|"PlateWheat"|"Play"|"Plug"|"PlugCircleBolt"|"PlugCircleCheck"|"PlugCircleExclamation"|"PlugCircleMinus"|"PlugCirclePlus"|"PlugCircleXmark"|"Plus"|"PlusMinus"|"Podcast"|"Poo"|"PooStorm"|"Poop"|"PowerOff"|"Prescription"|"PrescriptionBottle"|"PrescriptionBottleMedical"|"Print"|"PumpMedical"|"PumpSoap"|"PuzzlePiece"|"Q"|"Qrcode"|"Question"|"QuoteLeft"|"QuoteRight"|"R"|"Radiation"|"Radio"|"Rainbow"|"RankingStar"|"Receipt"|"RecordVinyl"|"RectangleAd"|"RectangleList"|"RectangleXmark"|"Recycle"|"Registered"|"Repeat"|"Reply"|"ReplyAll"|"Republican"|"Restroom"|"Retweet"|"Ribbon"|"RightFromBracket"|"RightLeft"|"RightLong"|"RightToBracket"|"Ring"|"Road"|"RoadBarrier"|"RoadBridge"|"RoadCircleCheck"|"RoadCircleExclamation"|"RoadCircleXmark"|"RoadLock"|"RoadSpikes"|"Robot"|"Rocket"|"Rotate"|"RotateLeft"|"RotateRight"|"Route"|"Rss"|"RubleSign"|"Rug"|"Ruler"|"RulerCombined"|"RulerHorizontal"|"RulerVertical"|"RupeeSign"|"RupiahSign"|"S"|"SackDollar"|"SackXmark"|"Sailboat"|"Satellite"|"SatelliteDish"|"ScaleBalanced"|"ScaleUnbalanced"|"ScaleUnbalancedFlip"|"School"|"SchoolCircleCheck"|"SchoolCircleExclamation"|"SchoolCircleXmark"|"SchoolFlag"|"SchoolLock"|"Scissors"|"Screwdriver"|"ScrewdriverWrench"|"Scroll"|"ScrollTorah"|"SdCard"|"Section"|"Seedling"|"Server"|"Shapes"|"Share"|"ShareFromSquare"|"ShareNodes"|"SheetPlastic"|"ShekelSign"|"Shield"|"ShieldCat"|"ShieldDog"|"ShieldHalved"|"ShieldHeart"|"ShieldVirus"|"Ship"|"Shirt"|"ShoePrints"|"Shop"|"ShopLock"|"ShopSlash"|"Shower"|"Shrimp"|"Shuffle"|"ShuttleSpace"|"SignHanging"|"Signal"|"Signature"|"SignsPost"|"SimCard"|"Sink"|"Sitemap"|"Skull"|"SkullCrossbones"|"Slash"|"Sleigh"|"Sliders"|"Smog"|"Smoking"|"Snowflake"|"Snowman"|"Snowplow"|"Soap"|"Socks"|"SolarPanel"|"Sort"|"SortDown"|"SortUp"|"Spa"|"SpaghettiMonsterFlying"|"SpellCheck"|"Spider"|"Spinner"|"Splotch"|"Spoon"|"SprayCan"|"SprayCanSparkles"|"Square"|"SquareArrowUpRight"|"SquareBinary"|"SquareCaretDown"|"SquareCaretLeft"|"SquareCaretRight"|"SquareCaretUp"|"SquareCheck"|"SquareEnvelope"|"SquareFull"|"SquareH"|"SquareMinus"|"SquareNfi"|"SquareParking"|"SquarePen"|"SquarePersonConfined"|"SquarePhone"|"SquarePhoneFlip"|"SquarePlus"|"SquarePollHorizontal"|"SquarePollVertical"|"SquareRootVariable"|"SquareRss"|"SquareShareNodes"|"SquareUpRight"|"SquareVirus"|"SquareXmark"|"StaffSnake"|"Stairs"|"Stamp"|"Stapler"|"Star"|"StarAndCrescent"|"StarHalf"|"StarHalfStroke"|"StarOfDavid"|"StarOfLife"|"SterlingSign"|"Stethoscope"|"Stop"|"Stopwatch"|"Stopwatch20"|"Store"|"StoreSlash"|"StreetView"|"Strikethrough"|"Stroopwafel"|"Subscript"|"Suitcase"|"SuitcaseMedical"|"SuitcaseRolling"|"Sun"|"SunPlantWilt"|"Superscript"|"Swatchbook"|"Synagogue"|"Syringe"|"T"|"Table"|"TableCells"|"TableCellsColumnLock"|"TableCellsLarge"|"TableCellsRowLock"|"TableCellsRowUnlock"|"TableColumns"|"TableList"|"TableTennisPaddleBall"|"Tablet"|"TabletButton"|"TabletScreenButton"|"Tablets"|"TachographDigital"|"Tag"|"Tags"|"Tape"|"Tarp"|"TarpDroplet"|"Taxi"|"Teeth"|"TeethOpen"|"TemperatureArrowDown"|"TemperatureArrowUp"|"TemperatureEmpty"|"TemperatureFull"|"TemperatureHalf"|"TemperatureHigh"|"TemperatureLow"|"TemperatureQuarter"|"TemperatureThreeQuarters"|"TengeSign"|"Tent"|"TentArrowDownToLine"|"TentArrowLeftRight"|"TentArrowTurnLeft"|"TentArrowsDown"|"Tents"|"Terminal"|"TextHeight"|"TextSlash"|"TextWidth"|"Thermometer"|"ThumbsDown"|"ThumbsUp"|"Thumbtack"|"ThumbtackSlash"|"Ticket"|"TicketSimple"|"Timeline"|"ToggleOff"|"ToggleOn"|"Toilet"|"ToiletPaper"|"ToiletPaperSlash"|"ToiletPortable"|"ToiletsPortable"|"Toolbox"|"Tooth"|"ToriiGate"|"Tornado"|"TowerBroadcast"|"TowerCell"|"TowerObservation"|"Tractor"|"Trademark"|"TrafficLight"|"Trailer"|"Train"|"TrainSubway"|"TrainTram"|"Transgender"|"Trash"|"TrashArrowUp"|"TrashCan"|"TrashCanArrowUp"|"Tree"|"TreeCity"|"TriangleExclamation"|"Trophy"|"Trowel"|"TrowelBricks"|"Truck"|"TruckArrowRight"|"TruckDroplet"|"TruckFast"|"TruckField"|"TruckFieldUn"|"TruckFront"|"TruckMedical"|"TruckMonster"|"TruckMoving"|"TruckPickup"|"TruckPlane"|"TruckRampBox"|"Tty"|"TurkishLiraSign"|"TurnDown"|"TurnUp"|"Tv"|"U"|"Umbrella"|"UmbrellaBeach"|"Underline"|"UniversalAccess"|"Unlock"|"UnlockKeyhole"|"UpDown"|"UpDownLeftRight"|"UpLong"|"UpRightAndDownLeftFromCenter"|"UpRightFromSquare"|"Upload"|"User"|"UserAstronaut"|"UserCheck"|"UserClock"|"UserDoctor"|"UserGear"|"UserGraduate"|"UserGroup"|"UserInjured"|"UserLarge"|"UserLargeSlash"|"UserLock"|"UserMinus"|"UserNinja"|"UserNurse"|"UserPen"|"UserPlus"|"UserSecret"|"UserShield"|"UserSlash"|"UserTag"|"UserTie"|"UserXmark"|"Users"|"UsersBetweenLines"|"UsersGear"|"UsersLine"|"UsersRays"|"UsersRectangle"|"UsersSlash"|"UsersViewfinder"|"Utensils"|"V"|"VanShuttle"|"Vault"|"VectorSquare"|"Venus"|"VenusDouble"|"VenusMars"|"Vest"|"VestPatches"|"Vial"|"VialCircleCheck"|"VialVirus"|"Vials"|"Video"|"VideoSlash"|"Vihara"|"Virus"|"VirusCovid"|"VirusCovidSlash"|"VirusSlash"|"Viruses"|"Voicemail"|"Volcano"|"Volleyball"|"VolumeHigh"|"VolumeLow"|"VolumeOff"|"VolumeXmark"|"VrCardboard"|"W"|"WalkieTalkie"|"Wallet"|"WandMagic"|"WandMagicSparkles"|"WandSparkles"|"Warehouse"|"Water"|"WaterLadder"|"WaveSquare"|"WebAwesome"|"WeightHanging"|"WeightScale"|"WheatAwn"|"WheatAwnCircleExclamation"|"Wheelchair"|"WheelchairMove"|"WhiskeyGlass"|"Wifi"|"Wind"|"WindowMaximize"|"WindowMinimize"|"WindowRestore"|"WineBottle"|"WineGlass"|"WineGlassEmpty"|"WonSign"|"Worm"|"Wrench"|"X"|"XRay"|"Xmark"|"XmarksLines"|"Y"|"YenSign"|"YinYang"|"Z"|"Search"|"Save"|"Settings"|"Cog"|"Home"|"Edit"|"Close"|"Cancel"|"Refresh"|"Warning"|"CheckCircle"|"TimesCircle"|"VolumeMute"|"Cut"|"Undo"|"Redo"|"StepForward"|"StepBackward"|"Pin"|"ZoomIn"|"ZoomOut")
---@overload fun(self: UIIconNode, path: "iconSize", value: number)
---@overload fun(self: UIIconNode, path: "color", value: number[])
---@overload fun(self: UIIconNode, path: "align", value: "Left"|"Center"|"Right")
function UIIconNode:set_property(path, value, y) end

---@class UIToolbarNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field activeToggleId integer Id of the pressed toggle button.
---@field buttonSize Vec2 Size of each button (px).
---@field spacing number Gap between items (px).
---@field items string[] The items, one a line: Icon|Label|Tooltip (toggle: first for a toggle), - a separator, ...

---@alias UIToolbarNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "activeToggleId" # integer - Id of the pressed toggle button.
---| "buttonSize" # Vec2 - Size of each button (px).
---| "spacing" # number - Gap between items (px).
---| "items" # string[] - The items, one a line: Icon|Label|Tooltip (toggle: first for a toggle), - a separator, ...

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UIToolbarNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UIToolbarNode, path: "position"): Vec2
---@overload fun(self: UIToolbarNode, path: "scale"): Vec2
---@overload fun(self: UIToolbarNode, path: "rotation"): number
---@overload fun(self: UIToolbarNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UIToolbarNode, path: "zIndex"): integer
---@overload fun(self: UIToolbarNode, path: "ySort"): boolean
---@overload fun(self: UIToolbarNode, path: "ySortOffset"): number
---@overload fun(self: UIToolbarNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UIToolbarNode, path: "paused"): boolean
---@overload fun(self: UIToolbarNode, path: "enabled"): boolean
---@overload fun(self: UIToolbarNode, path: "size"): Vec2
---@overload fun(self: UIToolbarNode, path: "keyboardFocus"): boolean
---@overload fun(self: UIToolbarNode, path: "activeToggleId"): integer
---@overload fun(self: UIToolbarNode, path: "buttonSize"): Vec2
---@overload fun(self: UIToolbarNode, path: "spacing"): number
---@overload fun(self: UIToolbarNode, path: "items"): string[]
function UIToolbarNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UIToolbarNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UIToolbarNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIToolbarNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIToolbarNode, path: "rotation", value: number)
---@overload fun(self: UIToolbarNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UIToolbarNode, path: "zIndex", value: integer)
---@overload fun(self: UIToolbarNode, path: "ySort", value: boolean)
---@overload fun(self: UIToolbarNode, path: "ySortOffset", value: number)
---@overload fun(self: UIToolbarNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UIToolbarNode, path: "paused", value: boolean)
---@overload fun(self: UIToolbarNode, path: "enabled", value: boolean)
---@overload fun(self: UIToolbarNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIToolbarNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UIToolbarNode, path: "activeToggleId", value: integer)
---@overload fun(self: UIToolbarNode, path: "buttonSize", x: number|Vec2|number[], y?: number)
---@overload fun(self: UIToolbarNode, path: "spacing", value: number)
---@overload fun(self: UIToolbarNode, path: "items", value: string[])
function UIToolbarNode:set_property(path, value, y) end

---@class UITabContainerNode
---@field position Vec2 Position relative to the parent, in pixels (+y is down).
---@field scale Vec2 Size multiplier relative to the parent (1, 1 = as is; negative flips).
---@field rotation number Rotation relative to the parent, in degrees (clockwise).
---@field layer "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---@field zIndex integer Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---@field ySort boolean Draw the children by their Y position (lower on screen = in front), each with its child...
---@field ySortOffset number Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---@field pauseMode "Inherit"|"Pausable"|"Always" Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---@field paused boolean Pauses this node and its children (except Always ones) while the game runs.
---@field enabled boolean Disabled nodes (and their children) neither update nor draw.
---@field size Vec2 Width and height (px).
---@field keyboardFocus boolean Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---@field title string Header text.
---@field direction "Vertical"|"Horizontal"|"Grid" Children are laid out in a column, a row or a grid.
---@field alignment "Start"|"Center"|"End"|"Stretch" Where children sit across the layout direction.
---@field spacing number Gap between items (px).
---@field paddingTop number Space above the children (px).
---@field paddingBottom number Space below the children (px).
---@field paddingLeft number Space left of the children (px).
---@field paddingRight number Space right of the children (px).
---@field columns integer Grid layout: columns per row.
---@field autoSizeHeight boolean Grow to fit the children.
---@field drawBackground boolean Fill the background.
---@field drawBorder boolean Draw a border.
---@field showHeader boolean Draw a header with the title.
---@field headerHeight number Height of the header (px).
---@field backgroundColor number[] Fill colour of the background.
---@field headerColor number[] Header fill colour.
---@field borderColor number[] Colour of the border.
---@field titleColor number[] Title text colour.
---@field tabDirection "Horizontal"|"Vertical" Tabs along the top or the side.
---@field tabNames string[] Each tab's title, one a line, in the order of the child pages.
---@field activeTab integer The open tab (from 0): its page - the UI child at that index - shows, the others are hi...
---@field tabSize number Tab height (or width when vertical; px).

---@alias UITabContainerNodeProperty
---| "position" # Vec2 - Position relative to the parent, in pixels (+y is down).
---| "scale" # Vec2 - Size multiplier relative to the parent (1, 1 = as is; negative flips).
---| "rotation" # number - Rotation relative to the parent, in degrees (clockwise).
---| "layer" # "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8" - Drawing layer: higher layers draw over lower ones (Layer8 is for UI).
---| "zIndex" # integer - Draw order within the layer, added to the parent's: higher draws on top (-10, 0, 10...)...
---| "ySort" # boolean - Draw the children by their Y position (lower on screen = in front), each with its child...
---| "ySortOffset" # number - Added to this node's Y when its parent Y-sorts: move the sorting line to the feet (e.g....
---| "pauseMode" # "Inherit"|"Pausable"|"Always" - Inherit the parent's pausing, Pausable (stops when paused) or Always (keeps running, e....
---| "paused" # boolean - Pauses this node and its children (except Always ones) while the game runs.
---| "enabled" # boolean - Disabled nodes (and their children) neither update nor draw.
---| "size" # Vec2 - Width and height (px).
---| "keyboardFocus" # boolean - Tab and the arrow keys can move to it (then Enter presses it). Off: only the mouse, so ...
---| "title" # string - Header text.
---| "direction" # "Vertical"|"Horizontal"|"Grid" - Children are laid out in a column, a row or a grid.
---| "alignment" # "Start"|"Center"|"End"|"Stretch" - Where children sit across the layout direction.
---| "spacing" # number - Gap between items (px).
---| "paddingTop" # number - Space above the children (px).
---| "paddingBottom" # number - Space below the children (px).
---| "paddingLeft" # number - Space left of the children (px).
---| "paddingRight" # number - Space right of the children (px).
---| "columns" # integer - Grid layout: columns per row.
---| "autoSizeHeight" # boolean - Grow to fit the children.
---| "drawBackground" # boolean - Fill the background.
---| "drawBorder" # boolean - Draw a border.
---| "showHeader" # boolean - Draw a header with the title.
---| "headerHeight" # number - Height of the header (px).
---| "backgroundColor" # number[] - Fill colour of the background.
---| "headerColor" # number[] - Header fill colour.
---| "borderColor" # number[] - Colour of the border.
---| "titleColor" # number[] - Title text colour.
---| "tabDirection" # "Horizontal"|"Vertical" - Tabs along the top or the side.
---| "tabNames" # string[] - Each tab's title, one a line, in the order of the child pages.
---| "activeTab" # integer - The open tab (from 0): its page - the UI child at that index - shows, the others are hi...
---| "tabSize" # number - Tab height (or width when vertical; px).

---Reads an Inspector property by its path (vectors and colours as tables); "script.<name>" reads a field of the node's script.
---
---Example: `local value = self.node:get_property("size")`
---@param path UITabContainerNodeProperty|string The property's path, as the Inspector names it ("position", "emitter.amount") or "script.<field>"
---@return any value Its value: a number, boolean, string or enum name; vectors and colours as tables (nil when there's no such property)
---@overload fun(self: UITabContainerNode, path: "position"): Vec2
---@overload fun(self: UITabContainerNode, path: "scale"): Vec2
---@overload fun(self: UITabContainerNode, path: "rotation"): number
---@overload fun(self: UITabContainerNode, path: "layer"): "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8"
---@overload fun(self: UITabContainerNode, path: "zIndex"): integer
---@overload fun(self: UITabContainerNode, path: "ySort"): boolean
---@overload fun(self: UITabContainerNode, path: "ySortOffset"): number
---@overload fun(self: UITabContainerNode, path: "pauseMode"): "Inherit"|"Pausable"|"Always"
---@overload fun(self: UITabContainerNode, path: "paused"): boolean
---@overload fun(self: UITabContainerNode, path: "enabled"): boolean
---@overload fun(self: UITabContainerNode, path: "size"): Vec2
---@overload fun(self: UITabContainerNode, path: "keyboardFocus"): boolean
---@overload fun(self: UITabContainerNode, path: "title"): string
---@overload fun(self: UITabContainerNode, path: "direction"): "Vertical"|"Horizontal"|"Grid"
---@overload fun(self: UITabContainerNode, path: "alignment"): "Start"|"Center"|"End"|"Stretch"
---@overload fun(self: UITabContainerNode, path: "spacing"): number
---@overload fun(self: UITabContainerNode, path: "paddingTop"): number
---@overload fun(self: UITabContainerNode, path: "paddingBottom"): number
---@overload fun(self: UITabContainerNode, path: "paddingLeft"): number
---@overload fun(self: UITabContainerNode, path: "paddingRight"): number
---@overload fun(self: UITabContainerNode, path: "columns"): integer
---@overload fun(self: UITabContainerNode, path: "autoSizeHeight"): boolean
---@overload fun(self: UITabContainerNode, path: "drawBackground"): boolean
---@overload fun(self: UITabContainerNode, path: "drawBorder"): boolean
---@overload fun(self: UITabContainerNode, path: "showHeader"): boolean
---@overload fun(self: UITabContainerNode, path: "headerHeight"): number
---@overload fun(self: UITabContainerNode, path: "backgroundColor"): number[]
---@overload fun(self: UITabContainerNode, path: "headerColor"): number[]
---@overload fun(self: UITabContainerNode, path: "borderColor"): number[]
---@overload fun(self: UITabContainerNode, path: "titleColor"): number[]
---@overload fun(self: UITabContainerNode, path: "tabDirection"): "Horizontal"|"Vertical"
---@overload fun(self: UITabContainerNode, path: "tabNames"): string[]
---@overload fun(self: UITabContainerNode, path: "activeTab"): integer
---@overload fun(self: UITabContainerNode, path: "tabSize"): number
function UITabContainerNode:get_property(path) end

---Sets an Inspector property by its path: vectors as {x, y} or x, y; colours as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"; enums by name; "script.<name>" a field of the node's script.
---
---Example: `self.node:set_property("size", 100, 50)`
---@param path UITabContainerNodeProperty|string The property's path, as the Inspector names it, or "script.<field>"
---@param value any The new value: a number, boolean, string or enum name; a vector as {x, y} (or x here and y next); a colour as {r, g, b[, a]} 0..1 or "#rrggbb[aa]"
---@param y? number A vector's y when value is its x
---@overload fun(self: UITabContainerNode, path: "position", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITabContainerNode, path: "scale", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITabContainerNode, path: "rotation", value: number)
---@overload fun(self: UITabContainerNode, path: "layer", value: "Layer1"|"Layer2"|"Layer3"|"Layer4"|"Layer5"|"Layer6"|"Layer7"|"Layer8")
---@overload fun(self: UITabContainerNode, path: "zIndex", value: integer)
---@overload fun(self: UITabContainerNode, path: "ySort", value: boolean)
---@overload fun(self: UITabContainerNode, path: "ySortOffset", value: number)
---@overload fun(self: UITabContainerNode, path: "pauseMode", value: "Inherit"|"Pausable"|"Always")
---@overload fun(self: UITabContainerNode, path: "paused", value: boolean)
---@overload fun(self: UITabContainerNode, path: "enabled", value: boolean)
---@overload fun(self: UITabContainerNode, path: "size", x: number|Vec2|number[], y?: number)
---@overload fun(self: UITabContainerNode, path: "keyboardFocus", value: boolean)
---@overload fun(self: UITabContainerNode, path: "title", value: string)
---@overload fun(self: UITabContainerNode, path: "direction", value: "Vertical"|"Horizontal"|"Grid")
---@overload fun(self: UITabContainerNode, path: "alignment", value: "Start"|"Center"|"End"|"Stretch")
---@overload fun(self: UITabContainerNode, path: "spacing", value: number)
---@overload fun(self: UITabContainerNode, path: "paddingTop", value: number)
---@overload fun(self: UITabContainerNode, path: "paddingBottom", value: number)
---@overload fun(self: UITabContainerNode, path: "paddingLeft", value: number)
---@overload fun(self: UITabContainerNode, path: "paddingRight", value: number)
---@overload fun(self: UITabContainerNode, path: "columns", value: integer)
---@overload fun(self: UITabContainerNode, path: "autoSizeHeight", value: boolean)
---@overload fun(self: UITabContainerNode, path: "drawBackground", value: boolean)
---@overload fun(self: UITabContainerNode, path: "drawBorder", value: boolean)
---@overload fun(self: UITabContainerNode, path: "showHeader", value: boolean)
---@overload fun(self: UITabContainerNode, path: "headerHeight", value: number)
---@overload fun(self: UITabContainerNode, path: "backgroundColor", value: number[])
---@overload fun(self: UITabContainerNode, path: "headerColor", value: number[])
---@overload fun(self: UITabContainerNode, path: "borderColor", value: number[])
---@overload fun(self: UITabContainerNode, path: "titleColor", value: number[])
---@overload fun(self: UITabContainerNode, path: "tabDirection", value: "Horizontal"|"Vertical")
---@overload fun(self: UITabContainerNode, path: "tabNames", value: string[])
---@overload fun(self: UITabContainerNode, path: "activeTab", value: integer)
---@overload fun(self: UITabContainerNode, path: "tabSize", value: number)
function UITabContainerNode:set_property(path, value, y) end
-- node properties end

-- ----------------------------------------------------------------------------
-- DynamicBodyNode Physics Methods
-- ----------------------------------------------------------------------------

---Applies a continuous force to this node this step (requires DynamicBodyNode). Units are pixels: the acceleration is force / mass (px/s^2), and mass is density x area in px^2 (a 64x64 box at density 1 weighs 4096), so scale by get_mass().
---
---Example: `self.node:apply_force(0, -self.node:get_mass() * 1500)`
---@param fx number Force x in mass x px/s^2, applied for this physics step only (call it every step to keep pushing); a Vec2 here gives both x and y. Ignored before the body exists
---@param fy number Force y in mass x px/s^2 (+y is down)
function DynamicBodyNode:apply_force(fx, fy) end

---Applies an instantaneous impulse to this node (requires DynamicBodyNode). It changes the velocity by impulse / mass (px/s); mass is density x area in px^2 (a 64x64 box at density 1 weighs 4096), so scale by get_mass().
---
---Example: `self.node:apply_impulse(0, -self.node:get_mass() * 300) -- 300 px/s upwards`
---@param ix number Impulse x in mass x px/s: the speed changes at once by impulse / mass; a Vec2 here gives both x and y. Ignored before the body exists
---@param iy number Impulse y in mass x px/s (+y is down; negative pushes up)
function DynamicBodyNode:apply_impulse(ix, iy) end

---The body's mass: density x area in px^2 (a 64x64 box at density 1 weighs 4096). 0 before its body exists.
---
---Example: `self.node:apply_impulse(0, -self.node:get_mass() * 300)`
---@return number mass Density x area in px^2 (a 64x64 box at density 1 is 4096); 0 before the body exists
function DynamicBodyNode:get_mass() end

---Gets the linear velocity of the physics body or character mover in px/s.
---
---Example: `local vx, vy = self.node:get_linear_velocity(); if vy > 400 then self.falling = true end`
---@return number vx Velocity x in px/s (the node's Linear Velocity before the body exists)
---@return number vy Velocity y in px/s (+y is down)
function DynamicBodyNode:get_linear_velocity() end

---Sets the linear velocity of the physics body or character mover directly.
---
---Example: `self.node:set_linear_velocity(200, 0)`
---@param vx number Velocity x in px/s; a Vec2 here gives both x and y. Wakes the body
---@param vy number Velocity y in px/s (+y is down)
function DynamicBodyNode:set_linear_velocity(vx, vy) end

---Gets the angular velocity of the physics body in degrees per second.
---
---Example: `local omega = self.node:get_angular_velocity(); if math.abs(omega) > 720 then Log.info("spinning") end`
---@return number omega Spin in degrees per second (positive is clockwise on screen)
function DynamicBodyNode:get_angular_velocity() end

---Sets the angular velocity of the physics body in degrees per second.
---
---Example: `self.node:set_angular_velocity(180)`
---@param omega number Spin in degrees per second (positive is clockwise on screen); wakes the body
function DynamicBodyNode:set_angular_velocity(omega) end

---Gets the linear velocity of the kinematic body in px/s.
---
---Example: `local vx, vy = self.node:get_linear_velocity()`
---@return number vx Velocity x in px/s (the node's Linear Velocity before the body exists)
---@return number vy Velocity y in px/s (+y is down)
function KinematicBodyNode:get_linear_velocity() end

---Sets the linear velocity of the kinematic body directly.
---
---Example: `self.node:set_linear_velocity(120, 0)`
---@param vx number Velocity x in px/s; a Vec2 here gives both x and y. The body keeps this speed (gravity and collisions don't change it)
---@param vy number Velocity y in px/s (+y is down)
function KinematicBodyNode:set_linear_velocity(vx, vy) end

---Gets the angular velocity of the kinematic body in degrees per second.
---
---Example: `local omega = self.node:get_angular_velocity()`
---@return number omega Spin in degrees per second (positive is clockwise on screen)
function KinematicBodyNode:get_angular_velocity() end

---Sets the angular velocity of the kinematic body in degrees per second.
---
---Example: `self.node:set_angular_velocity(90)`
---@param omega number Spin in degrees per second (positive is clockwise on screen); it keeps spinning at this rate
function KinematicBodyNode:set_angular_velocity(omega) end

---Gets the gravity scale multiplier for this physics body.
---
---Example: `local g = self.node:get_gravity_scale(); self.node:set_gravity_scale(g * 0.5)`
---@return number scale Multiplier of the world gravity: 1 normal (the default), 0 none, negative falls up
function DynamicBodyNode:get_gravity_scale() end

---Sets the gravity scale multiplier for this physics body.
---
---Example: `self.node:set_gravity_scale(0)`
---@param scale number Multiplier of the world gravity: 1 normal, 0 floats, 2 twice as heavy, negative falls up
function DynamicBodyNode:set_gravity_scale(scale) end

---Checks whether rotation is locked on this body.
---
---Example: `if not self.node:is_fixed_rotation() then self.node:set_fixed_rotation(true) end`
---@return boolean fixed True when the body can't rotate (collisions don't spin it)
function DynamicBodyNode:is_fixed_rotation() end

---Locks or unlocks rotation on this physics body.
---
---Example: `self.node:set_fixed_rotation(true)`
---@param fixed boolean True locks rotation (good for characters and crates that must stay upright); false lets collisions spin it
function DynamicBodyNode:set_fixed_rotation(fixed) end

---Sets the linear drag/damping coefficient.
---
---Example: `self.node:set_linear_damping(2.0)`
---@param damping number Drag on movement, 0 or more: 0 none (the default), higher slows the body faster (about 1 / damping seconds to lose most of its speed)
function DynamicBodyNode:set_linear_damping(damping) end

---Sets the angular drag/damping coefficient.
---
---Example: `self.node:set_angular_damping(1.5)`
---@param damping number Drag on spinning, 0 or more: 0 none, higher stops rotation faster
function DynamicBodyNode:set_angular_damping(damping) end

---Checks if the physics body is awake and participating in simulation.
---
---Example: `if not self.node:is_awake() then self.node:set_awake(true) end`
---@return boolean awake True while simulated; false when asleep (resting) or before the body exists
function DynamicBodyNode:is_awake() end

---Wakes up or puts the body to sleep.
---
---Example: `self.node:set_awake(true)`
---@param awake boolean True wakes the body, false puts it to sleep until something touches it; no effect before the body exists
function DynamicBodyNode:set_awake(awake) end

-- ----------------------------------------------------------------------------
-- Materials (any node): shader, blend mode, shader parameters
-- ----------------------------------------------------------------------------

---@alias BuiltinShader
---| "builtin:flash"     # flash_color, amount: tint toward a colour (hit flash)
---| "builtin:outline"   # outline_color, width: outline around the sprite
---| "builtin:dissolve"  # threshold, edge_width, edge_color: burn away
---| "builtin:grayscale" # amount
---| "builtin:wave"      # amplitude, frequency, speed: horizontal wave

---@alias BlendMode "alpha"|"additive"|"multiply"|"add_colors"|"subtract_colors"|"premultiplied"

---Sets the node's shader: a built-in or a project fragment shader (.fs). nil removes it.
---
---Example: `self.node:set_shader("builtin:flash")`
---@param shader BuiltinShader|string|nil "builtin:flash", "builtin:outline", "builtin:dissolve", "builtin:grayscale", "builtin:wave" or a project .fs path; nil removes the shader
function Node:set_shader(shader) end

---Sets a shader parameter (a uniform of the shader): a number, up to four
---numbers, a table {r, g, b, a} / {x, y}, or a texture path.
---
---Example: `self.node:set_shader_param("amount", 0.8)`
---@param name string The uniform's name in the shader, e.g. "amount" or "flash_color"
---@param x number|number[]|string A number, a table of up to 4 numbers ({r, g, b, a} 0..1, {x, y}), or a texture's project path
---@param y? number Second number when x is a number; missing = 0
---@param z? number Third number when x is a number; missing = 0
---@param w? number Fourth number when x is a number; missing = 0
function Node:set_shader_param(name, x, y, z, w) end

---Gets a shader parameter (its value, else the shader's default): up to four
---numbers, or the texture path.
---
---Example: `local amount = self.node:get_shader_param("amount")`
---@param name string The uniform's name in the shader
---@return number|string|nil x The first number, or the texture path for a texture parameter; nil when the node has no shader or no such parameter
---@return number? y The second number (0 when unused); nil for a texture or a missing parameter
---@return number? z The third number (0 when unused); nil for a texture or a missing parameter
---@return number? w The fourth number (0 when unused); nil for a texture or a missing parameter
function Node:get_shader_param(name) end

---Sets how the node is blended with what's behind it.
---
---Example: `self.node:set_blend_mode("additive")`
---@param mode BlendMode "alpha" (normal, the default), "additive", "multiply", "add_colors", "subtract_colors" or "premultiplied"; an unknown name gives "alpha"
function Node:set_blend_mode(mode) end

-- ----------------------------------------------------------------------------
-- LightNode Methods (2D lights; Scene.set_ambient darkens unlit areas)
-- ----------------------------------------------------------------------------

---Sets the light's colour (0..1).
---
---Example: `local lamp = self.node:get_node("Lamp"); lamp:light_set_color(1.0, 0.8, 0.4)`
---@param r number Red, 0 to 1 (clamped)
---@param g number Green, 0 to 1 (clamped)
---@param b number Blue, 0 to 1 (clamped)
function LightNode:light_set_color(r, g, b) end

---Sets the light's energy (a brightness multiplier, 0 or more; the Inspector goes to 8).
---
---Example: `local lamp = self.node:get_node("Lamp"); lamp:light_set_energy(2.5)`
---@param energy number Brightness multiplier: 1 = normal, 0 = off (negative counts as 0); the Inspector goes to 8
function LightNode:light_set_energy(energy) end

---Gets the light's energy (brightness multiplier).
---
---Example: `local lamp = self.node:get_node("Lamp"); lamp:light_set_energy(lamp:light_get_energy() * 0.9)`
---@return number energy The brightness multiplier; 0 for other node types
function LightNode:light_get_energy() end

---Sets the light's radius (px).
---
---Example: `local lamp = self.node:get_node("Lamp"); lamp:light_set_radius(200)`
---@param radius number How far the light reaches, in world px (negative counts as 0)
function LightNode:light_set_radius(radius) end

-- ----------------------------------------------------------------------------
-- Properties (any node) and collision layers (body nodes)
-- ----------------------------------------------------------------------------


---The node's script instance - the `self` its script sees: read or change its
---fields and call its methods (`enemy:get_script():take_damage(10)`). nil
---when the node has no script.
---
---Example: `local enemy = Scene.find_node("Enemy"); enemy:get_script():take_damage(10)`
---@return table? The script's live self table; nil when the node has no script or was destroyed
function Node:get_script() end

---Pauses this node and its children (except "always" ones).
---
---Example: `Scene.find_node("Enemies"):set_paused(true)`
---@param paused boolean true pauses the node and its children (except "always" ones); false lets them run unless a parent or the game is paused
function Node:set_paused(paused) end

---Checks whether the node is paused, by itself, a parent or the game.
---
---Example: `if self.node:is_paused() then return end`
---@return boolean paused true when paused by itself, a parent or the game (as of this frame's update)
function Node:is_paused() end

---Sets how the node reacts to pausing: inherit from its parent, pausable, or always running.
---
---Example: `self.node:set_pause_mode("always")`
---@param mode "inherit"|"pausable"|"always" "inherit" (the parent's mode, the default), "pausable" (stops when paused) or "always" (keeps running, e.g. a pause menu); anything else is inherit
function Node:set_pause_mode(mode) end

---Sets the text of a TextNode (restarting its typewriter), UI label, button or text input (raising its value_changed).
---
---Example: `self.node:get_node("ScoreLabel"):set_text("Score: " .. self.score)`
---@param text string The new text; a TextNode types it out again (Reveal Speed above 0), a text input raises value_changed; other node types ignore it
function TextHolder:set_text(text) end

---Gets the text of a TextNode, UI label, button or text input (what's typed).
---
---Example: `local text = self.node:get_node("ScoreLabel"):get_text()`
---@return string The text shown (a text input: what's typed); "" for other node types
function TextHolder:get_text() end

---Replaces the node's list (#227): a Dropdown's items, a Radio Group's options, a List View's / Tree View's / Bullet or Numbered List's / Toolbar's items, a Table's rows, an XY Plot's points, a Tab Container's tab names, a Notched Slider's notch labels. One string an item, as in the Inspector: 2 leading spaces nest a Tree / List item; table cells split by "|"; toolbar items "Icon|Label|Tooltip"; points "x, y" or Vec2 / {x, y}. Other lists: set_property("columns", {...}).
---
---Example: `self.node:get_node("Difficulty"):ui_set_items({"Easy", "Normal", "Hard"})`
---@param items (string|number|Vec2|number[])[] One entry per item, as typed in the Inspector (strings, numbers, or Vec2 or {x, y} for plot points); replaces the whole list; nodes without a list ignore it
function UIListHolder:ui_set_items(items) end

---The node's list (see ui_set_items), one string an item.
---
---Example: `for i, name in ipairs(self.node:ui_get_items()) do print(i, name) end`
---@return string[] One string per item, as in the Inspector; empty for nodes without a list
function UIListHolder:ui_get_items() end

---TextNode: types the text out again (revealSpeed > 0).
---
---Example: `self.node:get_node("Intro"):text_restart()`
function TextNode:text_restart() end

---@class DialogueLine
---@field speaker? string
---@field text string Rich text ([color=..] [size=..] [wave] [shake]), or a locale key when the box is localized
---@field voice? string A sound played with the line (in Subtitles mode the line lasts as long)
---@field choices? string[] Choices listed above the box once the line is shown; taking one fires "chosen"(index)

---DialogueNode: opens the box with these lines (strings or {speaker, text}),
---or one line: box:dialogue_show(text, speaker). Each line types out; the
---advance action (default "confirm") shows the rest, then the next line.
---A line with `choices` waits for one to be taken (move_up / move_down or
---the mouse, then the advance action or a click).
---Events: "line_shown"(index), "chosen"(index), "finished".
---
---Example: `local box = Scene.find_node("Dialogue"); box:dialogue_show({ { speaker = "Guard", text = "Halt!" } })`
---@param lines string|(string|DialogueLine)[] One line of text, or a list of lines: strings or {speaker, text, voice} tables. Replaces whatever the box was showing
---@param speaker? string Speaker name for a single text line; ignored when lines is a list
function DialogueNode:dialogue_show(lines, speaker) end

---Shows the rest of the line, else the next one.
---
---Example: `Scene.find_node("Dialogue"):dialogue_next()`
function DialogueNode:dialogue_next() end

---Closes the dialogue box.
---
---Example: `Scene.find_node("Dialogue"):dialogue_close()`
function DialogueNode:dialogue_close() end

---Checks whether the dialogue box is currently open.
---
---Example: `if Scene.find_node("Dialogue"):dialogue_is_open() then return end`
---@return boolean open True while a line is showing (from dialogue_show until the last line is passed or dialogue_close)
function DialogueNode:dialogue_is_open() end

---Takes a choice of the shown line, as the player would: "chosen" fires,
---then the next line follows unless the handler showed new lines.
---
---Example: `Scene.find_node("Dialogue"):dialogue_choose(2)`
---@param index integer The choice (1-based)
---@return boolean taken False when no choices are up or the index is out of range
function DialogueNode:dialogue_choose(index) end

---Checks whether the shown line is waiting for a choice.
---
---Example: `if box:dialogue_has_choices() then return end`
---@return boolean waiting True while choices are listed
function DialogueNode:dialogue_has_choices() end

---Turns auto advance on or off: each line goes on by itself a moment after
---it is shown (delay seconds, plus a little per character). Stops at choices.
---
---Example: `box:dialogue_set_auto(true, 1.5)`
---@param on boolean True to go on by itself, false to wait for the player again
---@param delay? number Seconds after a line is shown (default: the node's Auto Delay)
function DialogueNode:dialogue_set_auto(on, delay) end

---Turns skipping on or off: lines show and pass at once. Stops at choices.
---
---Example: `box:dialogue_set_skip(Input.is_key_down("LEFT_CONTROL"))`
---@param on boolean True to pass lines at once, false to type them out again
function DialogueNode:dialogue_set_skip(on) end

---LineNode: replaces its points (local to the node).
---
---Example: `self.node:get_node("Laser"):line_set_points({ {0, 0}, {120, 0} })`
---@param points number[][] { {x, y}, ... } in px, local to the node; replaces every point (an empty table clears the line)
function LineNode:line_set_points(points) end

---LineNode: appends a point (local to the node).
---
---Example: `self.node:get_node("Path"):line_add_point(64, 32)`
---@param x number X in px, local to the node
---@param y number Y in px, local to the node (+y is down)
function LineNode:line_add_point(x, y) end

---LineNode: removes every point.
---
---Example: `self.node:get_node("Path"):line_clear()`
function LineNode:line_clear() end

---TrailNode: drops the recorded ribbon (e.g. after a teleport).
---
---Example: `self.node:set_position(0, 0); self.node:get_node("Trail"):trail_clear()`
function TrailNode:trail_clear() end

---Spawns as the spawner's mode says (or entry `index`, 1-based, whatever the mode); returns the spawned roots - empty when held back (cooldown, maxAlive, totalLimit, chance, an empty list).
---
---Example: `for _, bullet in ipairs(self.node:get_node("Muzzle"):spawn()) do bullet:get_script().owner = self.node end`
---@param index? integer An entry of the list, from 1, spawned whatever the mode; nil picks as the mode says
---@return Node[] nodes The spawned root nodes; empty when held back (cooldown, maxAlive, totalLimit, chance, an empty list)
function SpawnerNode:spawn(index) end

---Spawns at a world position instead of the spawner's (its rotation and offsets still apply).
---
---Example: `self.node:get_node("Loot"):spawn_at(enemy.position)`
---@param x number|Vec2 World x in px, or a Vec2 position (then the index comes second)
---@param y? number World y in px; with a Vec2 for x, the entry index goes here instead
---@param index? integer An entry of the list, from 1; nil picks as the mode says
---@return Node[] nodes The spawned root nodes; empty when held back
function SpawnerNode:spawn_at(x, y, index) end

---Starts over: the sequence, the shuffle bag, spawned-so-far (totalLimit), the cooldown and the auto-spawn delay.
---
---Example: `self.node:get_node("Waves"):spawn_reset()`
function SpawnerNode:spawn_reset() end

---How many of the nodes it spawned are still in the scene (pooled ones until they go back to their pool).
---
---Example: `if spawner:spawn_alive_count() == 0 then self:next_wave() end`
---@return integer count Spawned nodes still in the scene (pooled ones until they go back to their pool)
function SpawnerNode:spawn_alive_count() end

---The spawn list: {component, weight, count} per entry, in order.
---
---Example: `for i, e in ipairs(spawner:spawn_entries()) do Log.info(i, e.component, e.weight) end`
---@return {component: ComponentPath|string, weight: number, count: integer}[] entries One {component, weight, count} table per entry, in list order
function SpawnerNode:spawn_entries() end

---Adds a component to the end of the list.
---
---Example: `spawner:spawn_add("components/BossMinion.component.json", 0.5)`
---@param component ComponentPath|string The component's path (.component.json)
---@param weight? number Random mode: how likely it is picked, relative to the others (default 1)
---@param count? integer How many are spawned each time it is picked (default 1, at least 1)
function SpawnerNode:spawn_add(component, weight, count) end

---Removes the list's entry at `index` (1-based).
---
---Example: `spawner:spawn_remove(1)`
---@param index integer The entry to remove, from 1; out of range does nothing
function SpawnerNode:spawn_remove(index) end

---Empties the list.
---
---Example: `spawner:spawn_clear()`
function SpawnerNode:spawn_clear() end

---Sets a function called for every node this spawner makes - by spawn(), spawn_at(), Auto Spawn, a signal or the pool - once it's placed and before its ready() / on_spawn(): set it up there. info.component is the component's path, info.index its entry in the list (from 1). Setting it again replaces it; nil clears it.
---
---Example: `spawner:set_spawn_callback(function(enemy, info, spawner) enemy:get_script().weapon = weapons[info.index] end)`
---@param fn? fun(node: Node, info: {component: string, index: integer}, spawner: SpawnerNode) Called as fn(node, info, spawner) for every spawned node before its ready(); info is {component, index}. nil clears it
function SpawnerNode:set_spawn_callback(fn) end

---Which list entry a node this spawner made (and still alive) came from: {component, index} (index from 1), or nil.
---
---Example: `spawner:connect("spawned", function(n) if spawner:spawn_info(n).index == 2 then n:get_script().ranged = true end end)`
---@param node Node A node this spawner made
---@return {component: string, index: integer}? info {component, index} (index from 1), or nil when the node isn't one of its live spawns
function SpawnerNode:spawn_info(node) end

---Makes a level into its TileMap (seed: this one, else the node's seed, a random one with randomSeed, or the generator's). Returns true, or false and why (also emitted as "generation_failed"). With background on it returns true once started; "generated" fires when the level is in.
---
---Example: `local ok, why = self.node:get_node("Generator"):generate(Save.get("seed", 7))`
---@param seed? integer Seed for this level; nil or 0 uses the node's Seed, else a random one when Random Seed is on, else the generator file's seed
---@return boolean ok True when the level was made (or, with Background on, started)
---@return string? why The reason when ok is false (e.g. "already generating"); nil on success
function LevelGeneratorNode:generate(seed) end

---Whether a background generation is running.
---
---Example: `if not gen:is_generating() then loading:hide() end`
---@return boolean generating True while a background generation runs
function LevelGeneratorNode:is_generating() end

---Sets a parameter of one of the generator's nodes for this node's levels (from the next generate): one generator file, many levels.
---
---Example: `gen:set_level_param(1, "density", 0.4 + level * 0.02); gen:generate()`
---@param node_id integer The id of a node in the generator file (.levelgen.json)
---@param name string Its parameter's name
---@param value number|boolean A number, or a boolean (stored as 1 or 0); used from the next generate
function LevelGeneratorNode:set_level_param(node_id, name, value) end

---A parameter set on this node with set_level_param (nil: the generator's own applies).
---
---Example: `local density = gen:level_param(1, "density") or 0.45`
---@param node_id integer The generator node's id
---@param name string Its parameter's name
---@return number? value The value set with set_level_param (a boolean comes back as 1 or 0), or nil when none is set (the generator's own applies)
function LevelGeneratorNode:level_param(node_id, name) end

---Drops the parameters set on this node (all, a generator node's, or one).
---
---Example: `gen:clear_level_params()`
---@param node_id? integer Only this generator node's parameters; nil means every node
---@param name? string Only the parameter of this name; nil means all of them
function LevelGeneratorNode:clear_level_params(node_id, name) end

---The path's length in pixels (along the curve).
---
---Example: `local len = self.node:get_node("Route"):path_length()`
---@return number Length along the curve in the path's own px (before its scale); 0 for an empty path
function PathNode:path_length() end

---The point at a distance along the path (world) and the direction the path goes there.
---
---Example: `local pos, dir = route:path_point_at(route:path_length() * 0.5)`
---@param distance number Px along the path from its first point (clamped to 0 .. path_length)
---@return Vec2 position World position of that point
---@return Vec2 direction Unit vector, the direction the path runs there (world)
function PathNode:path_point_at(distance) end

---The distance along the path of the point nearest to a world position (snap something onto the path).
---
---Example: `local d = route:path_closest_offset(player:get_global_position())`
---@param x number|Vec2 World X in px, or a Vec2 world position
---@param y? number World Y in px (omit when x is a Vec2)
---@return number distance Px along the path of its point nearest to the position; 0 for a path under 2 points
function PathNode:path_closest_offset(x, y) end

---How many points the path has.
---
---Example: `for i = 1, route:path_point_count() do print(route:path_get_point(i)) end`
---@return integer Number of points; 0 for an empty path
function PathNode:path_point_count() end

---A point (1-based): its position and its in / out handles, local to the path.
---
---Example: `local pos, handle_in, handle_out = route:path_get_point(1)`
---@param index integer Point number, 1-based
---@return Vec2 position Position, local to the path; nil for an index out of range
---@return Vec2 handle_in Handle towards the previous point, an offset from the position
---@return Vec2 handle_out Handle towards the next point, an offset from the position
function PathNode:path_get_point(index) end

---Moves a point (1-based), optionally setting its handles (offsets; zero = a sharp corner).
---
---Example: `route:path_set_point(2, Vec2(200, 40), Vec2(-30, 0), Vec2(30, 0))`
---@param index integer Point number, 1-based (out of range does nothing)
---@param position Vec2 New position, local to the path
---@param handle_in? Vec2 Handle towards the previous point, offset from the position (nil keeps the current one)
---@param handle_out? Vec2 Handle towards the next point, offset from the position (nil keeps the current one)
function PathNode:path_set_point(index, position, handle_in, handle_out) end

---Adds a point at the end (local to the path), optionally with handles.
---
---Example: `route:path_add_point(Vec2(400, 0))`
---@param position Vec2 Position, local to the path
---@param handle_in? Vec2 Handle towards the previous point, offset from the position (default zero, a sharp corner)
---@param handle_out? Vec2 Handle towards the next point, offset from the position (default zero)
function PathNode:path_add_point(position, handle_in, handle_out) end

---Removes a point (1-based).
---
---Example: `route:path_remove_point(route:path_point_count())`
---@param index integer Point number, 1-based (out of range does nothing)
function PathNode:path_remove_point(index) end

---Removes every point.
---
---Example: `route:path_clear()`
function PathNode:path_clear() end

---How far along its path the follower is: 0 at the start, 1 at the end.
---
---Example: `if platform:follow_ratio() > 0.5 then ... end`
---@return number Progress as a fraction of the path's length, 0 to 1; 0 without a parent path
function PathFollowNode:follow_ratio() end

---Puts the follower at a fraction of its path (0..1) at once.
---
---Example: `platform:follow_set_ratio(0.25)`
---@param ratio number Fraction of the path's length, clamped to 0 .. 1
function PathFollowNode:follow_set_ratio(ratio) end

---Back to the start, moving forwards again (after "path_finished").
---
---Example: `self.node:get_node("Route/Cart"):follow_restart()`
function PathFollowNode:follow_restart() end

---@class NavOptions
---@field diagonal? boolean 8 directions (default true); no cutting past blocked corners
---@field smooth? boolean Straighten where the line of sight is clear (default true)
---@field walkable_painted? boolean TileMap: painted tiles are the floor (default: not `solid`)
---@field radius? number Agent radius (px): the path keeps this far from walls (a goal too close to one moves to the nearest place that fits)

---A* path on this TileMap's, LDtk level's or NavigationRegion's grid
---(TileMap: painted tiles are walls when the map is solid; LDtk: IntGrid
---cells whose collision rule is Solid; a region: what it baked).
---Waypoints from the start to the end, or nil when unreachable.
---
---Example: `local level = Scene.find_node("Level"); local path = level:nav_find_path(x, y, tx, ty, {diagonal = false})`
---@param x1 number Start X, world px
---@param y1 number Start Y, world px
---@param x2 number Goal X, world px
---@param y2 number Goal Y, world px
---@param opts? NavOptions diagonal, smooth (both default true), walkable_painted, radius; nil for the defaults
---@return number[][]? World-px waypoints: the start point, cell centres along the way, then the goal; nil when unreachable or the node has no grid
function NavGrid:nav_find_path(x1, y1, x2, y2, opts) end

---Whether the grid cell at a world position is walkable.
---
---Example: `local level = Scene.find_node("Level"); if level:nav_is_walkable(tx, ty) then self.target = {tx, ty} end`
---@param x number World X in px
---@param y number World Y in px
---@param opts? NavOptions walkable_painted and radius (an agent this many px wide must fit) count here; nil for the defaults
---@return boolean true when the cell there is open; false for a wall, outside the grid, or a node with no grid
function NavGrid:nav_is_walkable(x, y, opts) end

---Rebuilds the region's cells from the scene (after moving walls, loading a level, painting tiles).
---
---Example: `Scene.find_node("NavigationRegion"):nav_rebake()`
function NavigationRegionNode:nav_rebake() end

---Blocks (or opens) a world rectangle for paths - doors, bridges, placed towers. Kept across rebakes.
---
---Example: `region:nav_set_blocked(door.position.x - 16, door.position.y - 32, 32, 64, not self.open)`
---@param x number Left edge, world px
---@param y number Top edge, world px
---@param w number Width in px
---@param h number Height in px
---@param blocked? boolean true blocks every cell the rectangle touches, false reopens them (default true)
function NavigationRegionNode:nav_set_blocked(x, y, w, h, blocked) end

---Sends the agent (and the node it moves) to a world position along a path.
---
---Example: `self.node:get_node("NavigationAgent"):nav_set_target(Scene.find_node("Player"):get_global_position())`
---@param x number|Vec2 Target world X in px, or a Vec2 world position
---@param y? number Target world Y in px (omit when x is a Vec2)
function NavigationAgentNode:nav_set_target(x, y) end

---Stops following the path (velocity 0).
---
---Example: `agent:nav_stop()`
function NavigationAgentNode:nav_stop() end

---Arrived (or no target).
---
---Example: `if agent:nav_is_finished() then self:look_around() end`
---@return boolean true when arrived, stopped, the target was unreachable or none was set
function NavigationAgentNode:nav_is_finished() end

---The waypoints still to go (world).
---
---Example: `local left = #agent:nav_get_path()  -- waypoints still to go`
---@return number[][] Waypoints still to go as {x, y} pairs (indices 1 and 2) in world px; empty when not moving
function NavigationAgentNode:nav_get_path() end

---Path length still to go (px).
---
---Example: `if agent:nav_distance_left() < 64 then self:slow_down() end`
---@return number Path length still to go in px, from the agent's parent; 0 when not moving
function NavigationAgentNode:nav_distance_left() end

---@class AsepriteTag
---@field name string
---@field from integer First frame (0-based)
---@field to integer Last frame
---@field direction "Forward"|"Reverse"|"Ping_Pong"|"Ping_Pong_Reverse"
---@field repeats integer 0 = loops (or once, with loop off)
---@field user AsepriteUserData

---@class AsepriteUserData
---@field text string
---@field color? integer[] {r, g, b, a} 0-255
---@field properties table<string, any> Aseprite's user properties (numbers, strings, booleans, points {x, y}, sizes {width, height}, rects, lists, maps)

---@class AsepriteInfo
---@field width integer
---@field height integer
---@field frames integer[] Each frame's duration (ms)
---@field tags AsepriteTag[]
---@field layers string[] Layer names, bottom first
---@field user AsepriteUserData The sprite's user data

---@class AsepriteSlice
---@field x integer
---@field y integer
---@field width integer
---@field height integer
---@field center? {x: integer, y: integer, width: integer, height: integer} 9-patch centre (relative to the slice)
---@field pivot? {x: integer, y: integer} Relative to the slice's origin
---@field user AsepriteUserData

---Plays a tag (its direction and repeats as set in Aseprite) from its first frame; "" plays every frame, no argument the node's Animation.
---
---Example: `sprite:aseprite_play("run")`
---@param tag? string The tag to play; "" plays every frame, an unknown tag also plays every frame. nil (or no argument) plays the node's Animation
function AsepriteNode:aseprite_play(tag) end

---Stops on the current frame.
---
---Example: `sprite:aseprite_stop()`
function AsepriteNode:aseprite_stop() end

---Goes on from where it stopped.
---
---Example: `if paused_menu_closed then sprite:aseprite_resume() end`
function AsepriteNode:aseprite_resume() end

---A tag is playing (false after its repeats are done, or stopped).
---
---Example: `if not sprite:aseprite_is_playing() then sprite:aseprite_play("idle") end`
---@return boolean playing True while it plays (false after aseprite_stop or when the tag's repeats are done)
function AsepriteNode:aseprite_is_playing() end

---The frame shown (0-based).
---
---Example: `if sprite:aseprite_frame() == 3 then shoot() end`
---@return integer frame The frame shown, from 0
function AsepriteNode:aseprite_frame() end

---Shows a frame (0-based); a playing tag goes on from it.
---
---Example: `sprite:aseprite_set_frame(0)`
---@param frame integer The frame to show, from 0; clamped to the file's frames
function AsepriteNode:aseprite_set_frame(frame) end

---The file: size, frame durations, tags, layers, the sprite's user data.
---
---Example: `for _, tag in ipairs(sprite:aseprite_info().tags) do print(tag.name, tag.direction) end`
---@return AsepriteInfo? info {width, height, frames (durations in ms), tags, layers, user}, or nil when no file is loaded
function AsepriteNode:aseprite_info() end

---A slice in a frame (default: the frame shown) - hitboxes, spawn points, 9-patch panels drawn in Aseprite. nil if it isn't there.
---
---Example: `local hit = sprite:aseprite_slice("hitbox")`
---@param name string The slice's name in Aseprite
---@param frame? integer The frame, from 0; nil uses the frame shown
---@return AsepriteSlice? slice {x, y, width, height, center?, pivot?, user} in the sprite's px, or nil when the slice isn't there in that frame
function AsepriteNode:aseprite_slice(name, frame) end

---A layer's user data (text, colour, properties set in Aseprite's layer properties).
---
---Example: `local damage = sprite:aseprite_layer_data("Weapon").properties.damage`
---@param layer string The layer's name
---@return AsepriteUserData? data {text, color?, properties}, or nil when there is no such layer
function AsepriteNode:aseprite_layer_data(layer) end

---A cel's user data (a layer in a frame; default: the frame shown).
---
---Example: `if sprite:aseprite_cel_data("Body").properties.footstep then play_step() end`
---@param layer string The layer's name
---@param frame? integer The frame, from 0; nil uses the frame shown
---@return AsepriteUserData? data {text, color?, properties}, or nil when that layer has no cel in that frame
function AsepriteNode:aseprite_cel_data(layer, frame) end

---Shows or hides a layer (by name; a group: its layers) - outfits, equipment, damage.
---
---Example: `sprite:aseprite_set_layer_visible("Helmet", has_helmet)`
---@param layer string The layer's name (a group: all its layers)
---@param visible boolean True shows it, false hides it
function AsepriteNode:aseprite_set_layer_visible(layer, visible) end

---Plays an animation (crossfading over `mix` seconds; default: the node's Mix Time). False when the skeleton has no such animation.
---
---Example: `skel:skeleton_play("run")`
---@param name string The animation's name (see skeleton_animations); the one already playing keeps going (only its loop setting changes), so it's safe to call every frame
---@param loop? boolean True (the default) loops; false plays once and fires "finished"
---@param mix? number Crossfade length from the current animation, in seconds: 0 cuts; nil uses the node's Mix Time (default 0.15 s)
---@return boolean ok False when the skeleton has no such animation (nothing changes)
function SkeletonNode:skeleton_play(name, loop, mix) end

---Stops at the current frame.
---
---Example: `skel:skeleton_stop()`
function SkeletonNode:skeleton_stop() end

---An animation is playing.
---
---Example: `if not skel:skeleton_is_playing() then skel:skeleton_play("idle") end`
---@return boolean playing True while an animation plays (false after skeleton_stop or when a one-shot animation ends)
function SkeletonNode:skeleton_is_playing() end

---Switches the skin (attachment set).
---
---Example: `skel:skeleton_set_skin("armored")`
---@param name string The skin's name (see skeleton_skins)
function SkeletonNode:skeleton_set_skin(name) end

---The animations' names.
---
---Example: `for _, a in ipairs(skel:skeleton_animations()) do print(a) end`
---@return string[] names The animations' names, in file order; empty when no skeleton is loaded
function SkeletonNode:skeleton_animations() end

---The skins' names.
---
---Example: `local skins = skel:skeleton_skins()`
---@return string[] names The skins' names; empty when no skeleton is loaded
function SkeletonNode:skeleton_skins() end

---The bones' names.
---
---Example: `local bones = skel:skeleton_bones()`
---@return string[] names The bones' names; empty when no skeleton is loaded
function SkeletonNode:skeleton_bones() end

---A bone's position in the world (nil: no such bone).
---
---Example: `local muzzle = skel:skeleton_bone_position("gun_tip")`
---@param name string The bone's name
---@return Vec2? position The bone's world position in px, or nil when there is no such bone
function SkeletonNode:skeleton_bone_position(name) end

---A bone's rotation in the world (degrees).
---
---Example: `local angle = skel:skeleton_bone_rotation("arm")`
---@param name string The bone's name
---@return number? degrees The bone's world rotation in degrees (the node's rotation included), or nil when there is no such bone
function SkeletonNode:skeleton_bone_rotation(name) end

---Overrides a bone's local rotation (degrees) over the animation; nil gives it back to the animation.
---
---Example: `skel:skeleton_set_bone_rotation("arm", aim_angle)`
---@param name string The bone's name
---@param degrees? number Local rotation in degrees that replaces the animated one every frame; nil removes the override
---@return boolean ok False when there is no such bone
function SkeletonNode:skeleton_set_bone_rotation(name, degrees) end

---An animation's length in seconds (default: the current one).
---
---Example: `local t = skel:skeleton_duration("attack")`
---@param name? string The animation's name; nil uses the current one
---@return number seconds The animation's length in seconds; 0 when there is no such animation
function SkeletonNode:skeleton_duration(name) end

---Adds shake trauma (stacks up to 1, decays by Shake Decay per second).
---
---Example: `cam:add_trauma(0.4)  -- a hit`
---@param amount number Trauma to add: 0.2 a bump, 0.5 a hit, 1 an explosion; the total is capped at 1 (negative calms it)
function AdvancedCameraNode:add_trauma(amount) end

---Raises its priority above every other advanced camera: the host blends to it.
---
---Example: `Scene.find_node("BossCam"):make_active()`
function AdvancedCameraNode:make_active() end

---The scene's camera shows this one now.
---
---Example: `if cam:is_active() then hud:show_hint() end`
---@return boolean true when the scene's camera is showing this one; false for other node types
function AdvancedCameraNode:is_active() end

---Jumps to where it wants to be now (no damping; ends the blend if active) - after a teleport.
---
---Example: `player.position = spawn; cam:snap()`
function AdvancedCameraNode:snap() end


---The collision layers this body's shapes are on: project layer names
---(Project Settings > Physics), "LayerN" or numbers 1-16; several or a table.
---
---Example: `self.node:set_collision_layer("player")`
---@param ... CollisionLayer|string|integer|table Layer names from Project Settings > Physics, "LayerN" or numbers 1-16, as arguments or one table; replaces the layers it had; an unknown name is an error
function Node:set_collision_layer(...) end

---The collision layers this body's shapes collide with.
---
---Example: `self.node:set_collision_mask("world", "enemies")`
---@param ... CollisionLayer|string|integer|table The layers it collides with, given as for set_collision_layer; replaces the mask it had; an unknown name is an error
function Node:set_collision_mask(...) end

-- ----------------------------------------------------------------------------
-- StateMachineNode Methods
--
-- A state machine has states, arrows between them, parameters and triggers.
-- The full guide, with tutorials: engine/docs/state_machine.md.
--
-- Arrows are Manual (the default: only sm_transition takes them) or
-- Automatic (the machine takes them when their conditions hold).
--
-- Callbacks your script defines (on the machine's own script, then on its
-- parent's), in the order they run:
--   on_enter_<state>(previous)  the first thing when a state is entered
--                               (before its child machine starts and its
--                               animation plays); previous is "" on start
--   on_update_<state>(dt)       every update while the state is current
--   on_exit_<state>(next)       the last thing before the state is left
--                               (after its child machine stopped); next is
--                               "" when the machine is stopped
--   can_exit_<state>(next) -> boolean      a guard: false refuses to leave
--   can_enter_<state>(previous) -> boolean a guard: false refuses to enter
-- Right-click a state in the State Machine tab > Add Script Callbacks writes
-- them for you. The machine also emits "state_changed"(state).
-- ----------------------------------------------------------------------------

---Sets a parameter: a value the arrows' conditions compare (`speed > 10`, `on_floor is true`). The value is converted to the parameter's type: a **bool** parameter stores true / false (numbers: non-zero is true), an **int** rounds to a whole number, a **float** keeps it. A parameter the machine doesn't have yet is added as a float.
---
---Use it every update to feed the machine what the game knows (speed, health, whether the player is on the floor); Automatic arrows react to it. For one-shot events (a button press, a hit) use a trigger instead (`sm_trigger`).
---
---Example: `local sm = self.node:get_node("StateMachine"); sm:sm_set("speed", math.abs(vx)); sm:sm_set("on_floor", self.node:character_is_on_floor())`
---@param name StateMachineParam|string The parameter (State Machine tab > Parameters and Triggers); an unknown name is added as a float
---@param value number|boolean A number, or a boolean (stored as 1 or 0); converted to the parameter's type
function StateMachineNode:sm_set(name, value) end

---Gets a parameter's value, typed: a **bool** parameter returns true / false, an **int** an integer, a **float** a number. Returns nil when the machine has no parameter of that name.
---
---Example: `local lives = self.node:get_node("StateMachine"):sm_get("lives")  -- an integer`
---@param name StateMachineParam|string The parameter's name
---@return number|boolean|nil value True or false for a bool parameter, an integer for an int, a number for a float; nil when there is no such parameter
function StateMachineNode:sm_get(name) end

---Sets a trigger: a one-shot event such as a button press or a hit. An **Automatic** arrow with a `trigger` condition fires when it's set (and the arrow's other conditions and the guards agree); the arrow that fires uses it up. If no arrow out of the current state can use it, it is cleared after the machine's next update - so a press can't fire much later from another state. Give the trigger a **buffer** (State Machine tab > Parameters & Triggers) to keep it waiting longer: a jump pressed 0.1 s before landing still happens on landing.
---
---Triggers only drive Automatic arrows; to take a Manual arrow, call `sm_transition`.
---
---Example: `if Input.is_action_just_pressed("jump") then self.node:get_node("StateMachine"):sm_trigger("jump") end`
---@param name StateMachineTrigger|string The trigger (State Machine tab > Parameters and Triggers)
---@return boolean ok false (and a warning) when the machine has no trigger of that name
function StateMachineNode:sm_trigger(name) end

---Whether a trigger is set and not used up yet (waiting for an arrow, or in its buffer time).
---
---Example: `if sm:sm_trigger_pending("attack") then self:show_combo_hint() end`
---@param name StateMachineTrigger|string The trigger's name
---@return boolean pending True while the trigger is set and not used up (waiting for an arrow or within its buffer)
function StateMachineNode:sm_trigger_pending(name) end

---Un-sets a trigger, so a buffered press doesn't fire later (e.g. the player let go, or a cutscene started).
---
---Example: `self.node:get_node("StateMachine"):sm_clear_trigger("jump")`
---@param name StateMachineTrigger|string The trigger to un-set; nothing happens when it isn't set
function StateMachineNode:sm_clear_trigger(name) end

---@class SM_TransitionOptions
---@field force? boolean Skip the guards and the arrow's conditions (an arrow is still needed)
---@field blend? number Crossfade seconds for the new state's animation (default: the arrow's)

---Goes to another state now - the way scripts change state. It needs an arrow from the current state (or from Any state) to that state, Manual or Automatic. It checks the guards (the current state's Leave After / interruptible / can leave when / `can_exit_<state>`, the target's can enter when / `can_enter_<state>`) and the arrow's conditions when it has any; `{force = true}` skips both. A state can go to itself only when it has **Allow Retrigger** on.
---
---The change happens inside the call: `on_exit_<old>`, then `on_enter_<new>` run before it returns, so code after it sees the new state. It is refused (with a warning) when called from inside a guard, a `script says` condition or an `on_exit_` callback, and when more than 8 changes have been chained from callbacks (two states sending each other back).
---
---Use it for decisions your script makes: an enemy that sees the player chases, a menu button opens a page, a door opens when the key is used.
---
---Example: `local ok, why = self.node:get_node("Brain"):sm_transition("chase"); if not ok then Log.info(why) end`
---@param state StateMachineState|string The state to go to, by name
---@param options? SM_TransitionOptions {force = true} skips the guards and the arrow's conditions (an arrow is still needed); {blend = seconds} sets the new state's animation crossfade (default: the arrow's)
---@return boolean ok true when it changed state
---@return string? reason why not, e.g. "attack: leave after 0.4s (0.12s so far)", "no arrow from idle to dash"; nil when it changed
function StateMachineNode:sm_transition(state, options) end

---Whether `sm_transition` to a state would work now, and why not - without changing anything. Use it to grey out a button or to pick between options.
---
---Example: `local can = sm:sm_can_transition("dash"); self.dash_icon:set_property("tint", can and "#ffffff" or "#666666")`
---@param state StateMachineState|string The state to test, by name
---@param options? SM_TransitionOptions Only `force` is used: {force = true} tests with the guards and conditions skipped
---@return boolean ok True when sm_transition to that state would work now
---@return string? reason why not; nil when it would work
function StateMachineNode:sm_can_transition(state, options) end

---Gets the name of the current state.
---
---Example: `if self.node:get_node("StateMachine"):sm_state() == "attack" then return end`
---@return string state The current state ("" before it starts)
function StateMachineNode:sm_state() end

---Gets the name of the state before the current one.
---
---Example: `local prev = self.node:get_node("StateMachine"):sm_previous()`
---@return string state The state before the current one ("" at the start)
function StateMachineNode:sm_previous() end

---@class SM_Change
---@field from string The state left ("" when it started)
---@field to string The state entered
---@field time number Seconds the machine had run
---@field why string How: "start", "manual" (sm_transition), "forced" (sm_transition with force) or "transition N" (automatic arrow N)

---The last state changes (up to 32), oldest first. Handy for debugging and for "what did the player just do" logic (e.g. a combo that needs attack1 then attack2).
---
---Example: `for _, c in ipairs(self.node:get_node("Brain"):sm_history()) do Log.info(c.from, "->", c.to, c.why) end`
---@return SM_Change[] changes Up to 32 recent changes, oldest first: {from, to, time, why} each
function StateMachineNode:sm_history() end

---Gets the time in seconds spent in the current state.
---
---Example: `if self.node:get_node("StateMachine"):sm_time() > 2 then self:give_up() end`
---@return number seconds Time spent in the current state
function StateMachineNode:sm_time() end

---Starts the machine in a state, or in its initial state. A running machine leaves its current state first (its `on_exit_` runs); pending triggers are cleared. A machine with Autostart starts by itself on its first update; a child machine starts when its parent's state is entered.
---
---Example: `self.node:get_node("StateMachine"):sm_start("idle")`
---@param state? StateMachineState|string The state to start in; nil starts in the initial state. An unknown name logs a warning and starts in the initial state
function StateMachineNode:sm_start(state) end

---Stops the machine: the current state's child machine stops, then its `on_exit_<state>("")` runs. The state stays current (`sm_state` still returns it); nothing changes state until `sm_start`.
---
---Example: `self.node:get_node("StateMachine"):sm_stop()  -- e.g. when the enemy dies`
function StateMachineNode:sm_stop() end

-- ----------------------------------------------------------------------------
-- CharacterMoverNode Methods
--
-- Two control modes (Inspector: Control Mode):
--   Script (Godot style; new scripts on a CharacterMover use the platformer
--     template): the script sets the velocity and calls
--     character_move_and_slide() every frame.
--   BuiltIn: the node moves itself (speed, acceleration, jump, gravity,
--     optional keyboard input); character_move() steers it.
-- ----------------------------------------------------------------------------

---Moves by the velocity (x dt), sliding along whatever it touches; the velocity
---loses the part going into surfaces. Updates the floor / wall / ceiling state.
---Switches the node to Script mode.
---
---Example: `local collided = self.node:character_move_and_slide(dt)`
---@param dt? number Seconds to move for; nil uses this frame's delta time
---@return boolean collided True when it touched a floor, wall or ceiling during the move
function CharacterMoverNode:character_move_and_slide(dt) end

---Gets the velocity in pixels per second (+y is down).
---
---Example: `local vx, vy = self.node:character_get_velocity(); vx = Input.get_axis("left", "right") * 200`
---@return number vx Velocity x in px/s
---@return number vy Velocity y in px/s (+y is down)
function CharacterMoverNode:character_get_velocity() end

---Sets the velocity in pixels per second (+y is down).
---
---Example: `self.node:character_set_velocity(vx, -350)`
---@param vx number Velocity x in px/s; a Vec2 here gives both x and y
---@param vy number Velocity y in px/s (+y is down; negative jumps)
function CharacterMoverNode:character_set_velocity(vx, vy) end

---Gets the gravity acting on the character: world gravity x its gravity scale.
---
---Example: `local gx, gy = self.node:character_get_gravity(); vy = vy + gy * dt`
---@return number gx Gravity x in px/s^2 (world gravity x the gravity scale)
---@return number gy Gravity y in px/s^2 (+y is down); add gy x dt to vy each frame in Script mode
function CharacterMoverNode:character_get_gravity() end

---Sets the multiplier of the world gravity for this character.
---
---Example: `self.node:character_set_gravity_scale(0.5)`
---@param scale number Multiplier of the world gravity: 1 normal (the default), 0 none, 0.5 floaty
function CharacterMoverNode:character_set_gravity_scale(scale) end

---Was the character standing on a floor after the last move?
---
---Example: `if self.node:character_is_on_floor() and Input.is_action_pressed("jump") then vy = -350 end`
---@return boolean on_floor True when the last move touched a surface whose normal points up (a floor or walkable slope)
function CharacterMoverNode:character_is_on_floor() end

---Was the character touching a wall after the last move?
---
---Example: `if self.node:character_is_on_wall() then vy = math.min(vy, 60) end`
---@return boolean on_wall True when the last move touched a steep surface (neither floor nor ceiling)
function CharacterMoverNode:character_is_on_wall() end

---Was the character touching a ceiling after the last move?
---
---Example: `if self.node:character_is_on_ceiling() then vy = 0 end`
---@return boolean on_ceiling True when the last move touched a surface whose normal points down
function CharacterMoverNode:character_is_on_ceiling() end

---The floor's normal (0, -1 on flat ground; tilted on slopes).
---
---Example: `local nx, ny = self.node:character_get_floor_normal(); local on_slope = math.abs(nx) > 0.1`
---@return number nx Floor normal x (unit length; 0, 0 when not on a floor)
---@return number ny Floor normal y (-1 on flat ground)
function CharacterMoverNode:character_get_floor_normal() end

---The wall's normal (points away from the wall).
---
---Example: `local nx, ny = self.node:character_get_wall_normal(); self.node:character_set_velocity(nx * 250, -300)`
---@return number nx Wall normal x, pointing away from the wall (0, 0 when not on a wall)
---@return number ny Wall normal y
function CharacterMoverNode:character_get_wall_normal() end

---How far the last move actually went.
---
---Example: `local dx, dy = self.node:character_get_last_motion(); self.distance = self.distance + math.abs(dx)`
---@return number dx How far the last move went in x (px), after sliding
---@return number dy How far the last move went in y (px)
function CharacterMoverNode:character_get_last_motion() end

---"script": the script moves it with character_move_and_slide; "builtin": it moves itself.
---
---Example: `self.node:character_set_control_mode("builtin")`
---@param mode "script"|"builtin" "script": moves only when the script calls character_move_and_slide; "builtin": moves itself each frame (speed, acceleration, jump, gravity, player input). Any other string means "script"
function CharacterMoverNode:character_set_control_mode(mode) end

---BuiltIn mode: steers the character horizontally and jumps if grounded.
---
---Example: `self.node:character_move(Input.get_axis("left", "right"), Input.is_action_pressed("jump"))`
---@param dirX number Horizontal input from -1 (left) to 1 (right); the target speed is this x the max speed (character_set_speed), reached with the node's acceleration. Builtin mode only, and not on a node with a script and player index 0 (builtin movement is skipped there); a player's own input overrides it while held
---@param jump? boolean True jumps (vy = -jump speed) when grounded; nil or false doesn't
function CharacterMoverNode:character_move(dirX, jump) end

---Same as character_is_on_floor().
---
---Example: `if self.node:character_is_grounded() then self.coyote = 0.1 end`
---@return boolean grounded True when standing on a floor (false right after a jump starts)
function CharacterMoverNode:character_is_grounded() end

---BuiltIn mode: sets the maximum horizontal run speed.
---
---Example: `self.node:character_set_speed(220)`
---@param speed number Builtin mode: maximum horizontal run speed in px/s (default 240)
function CharacterMoverNode:character_set_speed(speed) end

---BuiltIn mode: sets the jump speed.
---
---Example: `self.node:character_set_jump_speed(400)`
---@param speed number Builtin mode: upward speed of a jump in px/s (default 320)
function CharacterMoverNode:character_set_jump_speed(speed) end

---BuiltIn mode: gets the player index (1..4; 0 = none / NPC / AI) whose actions drive this mover.
---
---Example: `local p = self.node:character_get_player_index()`
---@return integer index Player 1 to 4 whose actions drive it, or 0 for none (an NPC or AI)
function CharacterMoverNode:character_get_player_index() end

---BuiltIn mode: sets the player index (1..4; 0 = none / NPC / AI) whose actions drive this mover.
---
---Example: `self.node:character_set_player_index(1)`
---@param index integer Player 1 to 4 whose actions drive it, or 0 for none (an NPC; a script then controls it); clamped to 0 to 4
function CharacterMoverNode:character_set_player_index(index) end

-- ----------------------------------------------------------------------------
-- AreaNode (Sensor Trigger) Methods
-- ----------------------------------------------------------------------------

---Checks whether any physics nodes are currently inside this sensor area.
---
---Example: `if self.node:get_node("Hitbox"):area_is_overlapping() then self:take_damage(1) end`
---@return boolean overlapping True when at least one body is inside; always false while monitoring is off
function AreaNode:area_is_overlapping() end

---Returns the number of bodies currently overlapping this sensor area.
---
---Example: `local count = self.node:get_node("Zone"):area_get_overlap_count()`
---@return number count How many nodes are inside now (each counted once); 0 while monitoring is off
function AreaNode:area_get_overlap_count() end

---Returns an array of all nodes currently overlapping this sensor area.
---
---Example: `for _, n in ipairs(self.node:area_get_overlapping_nodes()) do Log.info(n:get_name()) end`
---@return Node[] nodes The nodes inside now, each once (in no fixed order); empty while monitoring is off
function AreaNode:area_get_overlapping_nodes() end

---Enables or disables overlap monitoring on this sensor area.
---
---Example: `self.node:get_node("Hitbox"):area_set_monitoring(true)`
---@param enabled boolean True reports bodies entering and leaving (body_entered, body_exited) and tracks overlaps; false forgets the current overlaps without body_exited (it can still be found by raycasts and queries). On by default
function AreaNode:area_set_monitoring(enabled) end

---Returns whether overlap monitoring is currently enabled on this sensor area.
---
---Example: `if self.node:get_node("Hitbox"):area_is_monitoring() then ... end`
---@return boolean monitoring True when it tracks overlaps and sends body_entered / body_exited
function AreaNode:area_is_monitoring() end

-- ----------------------------------------------------------------------------
-- RaycastNode Methods
-- ----------------------------------------------------------------------------

---Executes the raycast immediately against the physics world.
---
---Example: `local ray = self.node:get_node("Ray"); ray:raycast_cast()`
function RaycastNode:raycast_cast() end

---Checks whether the raycast is currently intersecting a physics obstacle.
---
---Example: `local ray = self.node:get_node("Ray"); ray:raycast_cast(); local grounded = ray:raycast_is_colliding()`
---@return boolean colliding True when the last cast hit something (refreshed each frame while monitoring, or by raycast_cast)
function RaycastNode:raycast_is_colliding() end

---Gets the world-space intersection point of the raycast hit.
---
---Example: `local ray = self.node:get_node("Ray"); local x, y = ray:raycast_get_hit_point()`
---@return number x Hit point x in world px; the ray's end when nothing was hit
---@return number y Hit point y in world px
function RaycastNode:raycast_get_hit_point() end

---Gets the world-space surface normal at the raycast intersection.
---
---Example: `local ray = self.node:get_node("Ray"); local nx, ny = ray:raycast_get_hit_normal()`
---@return number nx Surface normal x at the hit (unit length, pointing out of the surface); 0, 0 when nothing was hit
---@return number ny Surface normal y
function RaycastNode:raycast_get_hit_normal() end

---Gets the fraction from 0.0 to 1.0 along the ray length where the hit occurred.
---
---Example: `local ray = self.node:get_node("Ray"); local dist = ray:raycast_get_hit_fraction() * 64`
---@return number fraction How far along the ray the hit is, 0 (at the origin) to 1 (the end, also when nothing was hit); multiply by the length for px
function RaycastNode:raycast_get_hit_fraction() end

---Gets the Node struck by the raycast, or nil if none.
---
---Example: `local ray = self.node:get_node("Ray"); local hit = ray:raycast_get_hit_node(); if hit then Log.info(hit.name) end`
---@return Node? node The node whose body was hit, or nil when nothing was hit
function RaycastNode:raycast_get_hit_node() end

---Sets the local direction vector for the raycast node.
---
---Example: `local ray = self.node:get_node("Ray"); ray:raycast_set_direction(1, 0)`
---@param dx number Direction x in the node's local space (rotated with it); normalized, so only the direction counts; a Vec2 here gives both x and y. 0, 0 means straight down
---@param dy number Direction y (+y is down)
function RaycastNode:raycast_set_direction(dx, dy) end

---Sets the maximum reach length in pixels for the raycast node.
---
---Example: `local ray = self.node:get_node("Ray"); ray:raycast_set_length(128)`
---@param length number Reach in px (scaled with the node), at least 1; default 450
function RaycastNode:raycast_set_length(length) end

---Enables or disables automatic per-frame raycast checks on this node.
---
---Example: `self.node:get_node("Ray"):raycast_set_monitoring(false)`
---@param enabled boolean True casts every frame and sends hit_started / hit_ended; false stops that and clears the hit (raycast_cast still works). On by default
function RaycastNode:raycast_set_monitoring(enabled) end

---Returns whether automatic per-frame raycast checks are enabled on this node.
---
---Example: `if self.node:get_node("Ray"):raycast_is_monitoring() then ... end`
---@return boolean monitoring True when it casts by itself every frame
function RaycastNode:raycast_is_monitoring() end

-- ----------------------------------------------------------------------------
-- ParticleEmitterNode Methods
-- ----------------------------------------------------------------------------

---Starts continuous or burst particle emission.
---
---Example: `self.node:get_node("Sparks"):particle_start()`
function ParticleEmitterNode:particle_start() end

---Stops particle emission.
---
---Example: `self.node:get_node("Sparks"):particle_stop()`
function ParticleEmitterNode:particle_stop() end

---Checks if particles are actively being emitted.
---
---Example: `local fx = self.node:get_node("Smoke"); if not fx:particle_is_emitting() then fx:particle_start() end`
---@return boolean emitting True while it emits new particles (false after particle_stop or when a one-shot cycle ends; live particles may still be flying)
function ParticleEmitterNode:particle_is_emitting() end

---Sets the maximum particle pool count for this emitter.
---
---Example: `self.node:get_node("Sparks"):particle_set_amount(64)`
---@param amount integer Particles emitted per cycle (one lifetime), so about how many are alive at once; default 100. Takes effect from the next emission
function ParticleEmitterNode:particle_set_amount(amount) end

---Sets the base lifetime in seconds for newly spawned particles.
---
---Example: `self.node:get_node("Sparks"):particle_set_lifetime(1.5)`
---@param lifetime number Seconds each new particle lives (also the length of one emission cycle); default 2. Particles already alive keep theirs
function ParticleEmitterNode:particle_set_lifetime(lifetime) end

---Where the last particle hit a body (collision on): the world point, the surface normal and the node hit. Returns nil when no particle has hit anything yet. Use it in a `particle_hit` handler.
---
---Example: `local x, y = self.node:particle_get_last_hit(); if x then Scene.instantiate("components/Splash.component.json", nil, x, y) end`
---@return number? x Hit point x in world px, or nil when no particle has hit anything yet (then it is the only value)
---@return number? y Hit point y in world px
---@return number? nx Surface normal x at the hit (unit length)
---@return number? ny Surface normal y
---@return Node? hit The node that was hit, or nil when it is gone
function ParticleEmitterNode:particle_get_last_hit() end

---Sets the particles' texture (used by the Texture shape; a sprite sheet when Sheet Columns / Rows are set). "" or nil removes it.
---
---Example: `self.node:get_node("Sparks"):particle_set_texture("textures/spark.png")`
---@param path TexturePath|string|nil Project texture path (a sprite sheet when Sheet Columns / Rows are set); "" or nil removes it
function ParticleEmitterNode:particle_set_texture(path) end

---Emits `count` particles right now (default 1), whether the emitter is emitting or not: a burst on demand (a hit, an explosion, footsteps).
---
---Example: `self.node:get_node("Dust"):particle_emit(12)`
---@param count? integer How many particles to emit now (default 1), from the node's current position
function ParticleEmitterNode:particle_emit(count) end

---Clears every particle and starts emitting again (with Seed set, the same pattern again).
---
---Example: `self.node:get_node("Fireworks"):particle_restart()`
function ParticleEmitterNode:particle_restart() end

---Gives the emitter a preset look and restarts it: its look and motion settings are replaced (its texture, collision layers and GPU mode stay). Names, any case: `"fire"`, `"smoke"`, `"sparks"`, `"rain"`, `"snow"`, `"explosion"`, `"magic"`.
---
---Example: `self.node:get_node("Torch"):particle_apply_preset("fire")`
---@param name string The preset's name
---@return boolean applied false when the name isn't a preset
function ParticleEmitterNode:particle_apply_preset(name) end

---How many particles are alive now.
---
---Example: `if self.node:particle_get_alive_count() == 0 then self.node:destroy() end`
---@return integer count Particles alive right now
function ParticleEmitterNode:particle_get_alive_count() end

-- ----------------------------------------------------------------------------
-- TextureNode Methods
-- ----------------------------------------------------------------------------

---Gets the base unscaled pixel width and height of the texture.
---
---Example: `local w, h = self.node:get_node("Sprite"):texture_get_size()`
---@return number width Width in px of the image as drawn, before scale; 0 for other node types
---@return number height Height in px, before scale; 0 for other node types
function TextureNode:texture_get_size() end

---Sets the origin (what it rotates and scales around) in pixels of the image;
---stored as a fraction of it - set_property("origin", fx, fy) takes that.
---
---Example: `local sprite = self.node:get_node("Sprite"); sprite:texture_set_origin(16, 16)`
---@param ox number Origin X in px from the image's left edge (default: its centre); a Vec2 here sets both
---@param oy number Origin Y in px from the image's top edge; omit when ox is a vector
function TextureNode:texture_set_origin(ox, oy) end

---Gets the file path string from which this texture was loaded.
---
---Example: `local path = self.node:get_node("Sprite"):texture_get_path()`
---@return string The project-relative image path; "" when it has none or for other node types
function TextureNode:texture_get_path() end

-- ----------------------------------------------------------------------------
-- AtlasSpriteNode Methods
-- ----------------------------------------------------------------------------

---Gets the base unscaled pixel width and height of the region.
---
---Example: `local w, h = self.node:texture_get_size()`
---@return number width Width in px of the region as drawn (the whole image when no region is set), before scale
---@return number height Height in px, before scale
function AtlasSpriteNode:texture_get_size() end

---Sets the origin (what it rotates and scales around) in pixels of the region.
---
---Example: `self.node:texture_set_origin(16, 16)`
---@param ox number Origin X in px from the region's left edge (default: its centre); a Vec2 here sets both
---@param oy number Origin Y in px from the region's top edge; omit when ox is a vector
function AtlasSpriteNode:texture_set_origin(ox, oy) end

---Gets the file path string from which this texture was loaded.
---
---Example: `local path = self.node:texture_get_path()`
---@return string The project-relative image path; "" when it has none
function AtlasSpriteNode:texture_get_path() end

---Shows another image (project-relative path), keeping the region; e.g. the same layout on a recoloured sheet. Returns false when the file can't be loaded.
---
---Example: `self.node:set_texture("textures/hero_blue.png")`
---@param path TexturePath|string Project-relative image path, e.g. "textures/hero_blue.png"; the region stays the same
---@return boolean ok true when the image loaded; false when the file can't be loaded (the old image stays)
function AtlasSpriteNode:set_texture(path) end

---Sets the sub-region rectangle (in texture pixels) to display.
---
---Example: `self.node:atlas_set_region(0, 0, 32, 32)`
---@param x number Left edge in texture px
---@param y number Top edge in texture px
---@param width number Width in texture px; 0 shows the whole image
---@param height number Height in texture px; 0 shows the whole image
function AtlasSpriteNode:atlas_set_region(x, y, width, height) end

---Gets the sub-region rectangle (x, y, width, height) in texture pixels.
---
---Example: `local x, y, w, h = self.node:atlas_get_region()`
---@return number x Left edge in texture px
---@return number y Top edge in texture px
---@return number width Width in texture px (0 = the whole image)
---@return number height Height in texture px (0 = the whole image)
function AtlasSpriteNode:atlas_get_region() end

-- ----------------------------------------------------------------------------
-- AnimationPlayerNode Methods
-- ----------------------------------------------------------------------------

---Plays an animation, optionally switching to the specified animation name first.
---Naming the animation already playing changes nothing (a paused one resumes), so calling it
---every frame is fine; without a name it restarts the current one. An unknown name warns and
---changes nothing. With `blend` > 0 the previous pose crossfades into the new animation over that many seconds.
---Event tracks fire while playing: method tracks call `self:<method>(frame)` on the
---track's target node script; sound tracks play their audio file on the key's frame.
---
---Example: `self.node:get_node("AnimationPlayer"):animation_play("run", 0.15)`
---@param name? AnimationName|string The animation to play (the project's names complete); nil restarts the current one
---@param blend? number Seconds to crossfade property tracks from the previous animation; default 0 (cut)
function AnimationPlayerNode:animation_play(name, blend) end

---Stops animation playback and freezes at current frame.
---
---Example: `self.node:get_node("AnimationPlayer"):animation_stop()`
function AnimationPlayerNode:animation_stop() end

---Pauses animation playback.
---
---Example: `self.node:get_node("AnimationPlayer"):animation_pause()`
function AnimationPlayerNode:animation_pause() end

---Resumes animation playback from the current frame.
---
---Example: `self.node:get_node("AnimationPlayer"):animation_resume()`
function AnimationPlayerNode:animation_resume() end

---Goes back to the current animation's first frame (its last when reversed), playing or paused as it was.
---
---Example: `self.node:get_node("AnimationPlayer"):animation_reset()`
function AnimationPlayerNode:animation_reset() end

---Sets playback speed in frames per second.
---
---Example: `self.node:get_node("AnimationPlayer"):animation_set_fps(12)`
---@param fps number Frames per second for animations without their own FPS (default 12; values under 0.1 count as 0.1)
function AnimationPlayerNode:animation_set_fps(fps) end

---Gets the name of the currently active animation track.
---
---Example: `local current = self.node:get_node("AnimationPlayer"):animation_get_current()`
---@return string The current animation's name; "" when it has none or for other node types
function AnimationPlayerNode:animation_get_current() end

-- ----------------------------------------------------------------------------
-- TimerNode Methods
-- ----------------------------------------------------------------------------

---Part swapping: shows the frame (a child group of the node's group) of that name - a mouth shape, a hand pose, eyes open or closed. Returns false when there is none.
---
---Example: `self.node:get_node("Mouth"):vector_swap("D")`
---@param name string The frame's name (a child group of the node's group, see vector_frames)
---@return boolean ok False when there is no frame of that name (nothing changes)
function VectorShapeNode:vector_swap(name) end

---The names of the frames the node's `frame` picks from (its group's child groups), in order.
---
---Example: `for i, name in ipairs(self.node:vector_frames()) do Log.info(i - 1 .. " " .. name) end`
---@return string[] names The frames' names in order (the node's frame property counts from 0); empty when it has none
function VectorShapeNode:vector_frames() end

---The component instance painted on a cell of the tile map's Components layer (0-based cells; a big component covers every cell of its footprint), or nil.
---
---Example: `local coin = map:tilemap_component_at(3, 5)`
---@param x integer Cell column, 0-based
---@param y integer Cell row, 0-based
---@return Node? The component instance covering that cell; nil when none
function TileMapNode:tilemap_component_at(x, y) end

---Paints a component on a cell: a linked instance at the cell's centre (a bigger one over its footprint), replacing what it covers. Returns the instance.
---
---Example: `map:tilemap_set_component(4, 2, "components/Coin.component.json")`
---@param x integer Cell column, 0-based (must be inside the map)
---@param y integer Cell row, 0-based (must be inside the map)
---@param component string Path of the .component.json, relative to the project
---@return Node? The new instance (a child of the tile map); nil when the cell is outside the map or the component can't load
function TileMapNode:tilemap_set_component(x, y, component) end

---Removes the component instance covering a cell; false when there is none.
---
---Example: `map:tilemap_clear_component(4, 2)`
---@param x integer Cell column, 0-based
---@param y integer Cell row, 0-based
---@return boolean true when an instance was removed; false when the cell had none
function TileMapNode:tilemap_clear_component(x, y) end

---The tile painted on a cell (0-based cells, inside the map or beyond it): its index in the tileset, or -1 for an empty cell.
---
---Example: `if map:tilemap_get_tile(x, y) == -1 then Log.info("empty") end`
---@param x integer Cell column, 0-based (may be outside the map)
---@param y integer Cell row, 0-based (may be outside the map)
---@return integer The tile's index in the tileset; -1 for an empty cell
function TileMapNode:tilemap_get_tile(x, y) end

---Paints a tile on a cell (its index in the tileset; -1 or nil erases). A Solid map's colliders follow at the end of the frame, and path finding sees the change. Returns true if the cell changed.
---
---Example: `local x, y = map:tilemap_cell_at(self.node:get_global_position()); map:tilemap_set_tile(x, y + 1, -1) -- dig`
---@param x integer Cell column, 0-based (outside the map grows the painted area)
---@param y integer Cell row, 0-based
---@param tile integer? Tile index in the tileset; -1 or nil erases
---@return boolean true when the cell changed; false when it already held that tile
function TileMapNode:tilemap_set_tile(x, y, tile) end

---The cell under a world position (it may be outside the map).
---
---Example: `local cx, cy = map:tilemap_cell_at(player:get_global_position())`
---@overload fun(self: TileMapNode, x: number, y: number): integer, integer
---@param pos Vec2 World position in px (x, y numbers also accepted)
---@return integer x Cell column, 0-based (may be outside the map); nil when not a tile map
---@return integer y Cell row, 0-based (may be outside the map)
function TileMapNode:tilemap_cell_at(pos) end

---The world position of a cell's centre.
---
---Example: `local wx, wy = map:tilemap_cell_position(4, 2); coin.position = Vec2(wx, wy) -- (coin at the scene root: world = local)`
---@param x integer Cell column, 0-based
---@param y integer Cell row, 0-based
---@return number wx World X in px of the cell's centre; nil when not a tile map
---@return number wy World Y in px of the cell's centre
function TileMapNode:tilemap_cell_position(x, y) end

---The cells sharing a side with a cell: four on square, isometric and
---staggered grids, six on hex grids (which ones depend on the row or
---column: shifted ones have different neighbours).
---
---Example: `for _, c in ipairs(map:tilemap_neighbors(x, y)) do if map:tilemap_get_tile(c[1], c[2]) == WATER then near_water = true end end`
---@param x integer Cell column, 0-based
---@param y integer Cell row, 0-based
---@return integer[][] neighbors Each one {x, y}; empty when not a tile map
function TileMapNode:tilemap_neighbors(x, y) end

---A cell's outline in the world: its corners clockwise from the top - 4
---for square and diamond cells, 6 for hex ones. For drawing a highlight
---(on_draw with the Vector module, in the drawing node's space).
---
---Example: `local pts = map:tilemap_cell_outline(x, y); Vector.move_to(pts[1][1], pts[1][2]); for i = 2, #pts do Vector.line_to(pts[i][1], pts[i][2]) end; Vector.close_path(); Vector.stroke()`
---@param x integer Cell column, 0-based
---@param y integer Cell row, 0-based
---@return number[][] corners Each one {wx, wy} in world px; empty when not a tile map
function TileMapNode:tilemap_cell_outline(x, y) end

---TouchJoystickNode: this frame's push - each axis -1..1, length up to 1
---(0, 0 when no thumb is on it).
---
---Example: `local x, y = Scene.find_node("Stick"):touch_get_vector(); self.aim = Vec2(x, y)`
---@return number x
---@return number y
function TouchJoystickNode:touch_get_vector() end

---A Touch Button (or Joystick) has a finger on it.
---
---Example: `if Scene.find_node("Boost"):touch_is_down() then speed = speed * 2 end`
---@return boolean down
function TouchButtonNode:touch_is_down() end

---Carves a circle out of the art (world position and radius): every shape keeps its paint, and a collider follows - destructible terrain, bites, bullet holes. The node draws its own carved copy until `vector_reset`.
---
---Example: `ground:vector_cut(bomb.position, 48)`
---@overload fun(self: VectorShapeNode, x: number, y: number, radius: number)
---@param pos Vec2 Centre of the hole in world px (x, y numbers also work)
---@param radius number Radius in world px; 0 or less does nothing
function VectorShapeNode:vector_cut(pos, radius) end

---Carves a polygon (world points) out of the art, like `vector_cut`.
---
---Example: `wall:vector_cut_polygon({Vec2(100, 0), Vec2(140, 0), Vec2(120, 60)})`
---@param points Vec2[] The polygon's corners in world px, at least 3 (fewer does nothing)
function VectorShapeNode:vector_cut_polygon(points) end

---Brings carved art (and its collider) back as it was.
---
---Example: `ground:vector_reset()`
function VectorShapeNode:vector_reset() end

---The length of the art's paths, one after another (world units).
---
---Example: `local len = self.node:vector_length()`
---@return number length Total length of the art's paths in world px (scaled with the node)
function VectorShapeNode:vector_length() end

---The point (world) and direction (unit) at a distance along the art's paths, one after another - move things along an SVG path.
---
---Example: `local pos, dir = track:vector_point_at(self.d); self.node.position = pos`
---@param distance number Distance along the paths in world px, clamped to 0 .. vector_length()
---@return Vec2 pos The point there, in world px
---@return Vec2 dir The path's direction there (unit length, world space)
function VectorShapeNode:vector_point_at(distance) end

---The point on the art's paths nearest to a world position, and its distance along them.
---
---Example: `local d, at = rail:vector_closest(player.position)`
---@overload fun(self: VectorShapeNode, x: number, y: number): number, Vec2
---@param pos Vec2 A world position in px (x, y numbers also work)
---@return number distance How far along the paths the nearest point is, in world px (use it with vector_point_at)
---@return Vec2 at The nearest point on the paths, in world px
function VectorShapeNode:vector_closest(pos) end

---Whether a world point is on the art (its fills and strokes, holes left out).
---
---Example: `local wx, wy = Camera.screen_to_world(Input.get_mouse_position()); if balloon:vector_contains(Vec2(wx, wy)) then pop() end`
---@overload fun(self: VectorShapeNode, x: number, y: number): boolean
---@param pos Vec2 A world position in px (x, y numbers also work)
---@return boolean inside True when the point is on a fill or stroke (holes left out)
function VectorShapeNode:vector_contains(pos) end

---Plays a voice (default: the node's sound) and moves the mouth with its Rhubarb cues (the sound's .json / .tsv beside it, or the node's cues file). Returns false when there are no cues.
---
---Example: `self.node:get_node("LipSync"):lipsync_play("voices/hello.wav")`
---@param sound? string Project-relative voice file, e.g. "voices/hello.wav"; nil plays the node's own sound
---@return boolean ok true when it started; false when no Rhubarb cues were found (nothing plays) or for other node types
function LipSyncNode:lipsync_play(sound) end

---Stops the voice and rests the mouth.
---
---Example: `self.node:get_node("LipSync"):lipsync_stop()`
function LipSyncNode:lipsync_stop() end

---Whether a voice is moving the mouth now.
---
---Example: `if not lips:lipsync_is_playing() then lips:lipsync_play() end`
---@return boolean true while a voice moves the mouth; false for other node types
function LipSyncNode:lipsync_is_playing() end

---Starts or restarts the timer from zero.
---
---Example: `local timer = self.node:get_node("Cooldown"); timer:timer_start()`
function TimerNode:timer_start() end

---Stops the timer.
---
---Example: `self.node:get_node("Cooldown"):timer_stop()`
function TimerNode:timer_stop() end

---Checks if the timer is actively running.
---
---Example: `if self.node:get_node("Cooldown"):timer_is_running() then return end`
---@return boolean running True while it counts (false after timer_stop, or after the timeout when not looping)
function TimerNode:timer_is_running() end

---Gets the elapsed time in seconds since start.
---
---Example: `local t = self.node:get_node("Cooldown"):timer_get_elapsed()`
---@return number seconds Time since it started, in seconds; back to 0 at each timeout; kept by timer_stop
function TimerNode:timer_get_elapsed() end

---Sets the timer expiration duration in seconds.
---
---Example: `self.node:get_node("Cooldown"):timer_set_duration(0.5)`
---@param durationSec number Seconds until "timeout"; applies at once, also to a running timer
function TimerNode:timer_set_duration(durationSec) end

---Sets whether the timer automatically restarts upon expiring.
---
---Example: `self.node:get_node("SpawnTimer"):timer_set_loop(true)`
---@param loop boolean True restarts it from 0 at each timeout; false stops it after the first
function TimerNode:timer_set_loop(loop) end

-- ----------------------------------------------------------------------------
-- SoundNode & MusicNode Methods
-- ----------------------------------------------------------------------------

---Plays the sound effect associated with this SoundNode.
---
---Example: `self.node:get_node("JumpSound"):sound_play()`
function SoundNode:sound_play() end

---Stops playing the sound effect.
---
---Example: `self.node:get_node("EngineSound"):sound_stop()`
function SoundNode:sound_stop() end

---Pauses the sound effect.
---
---Example: `self.node:get_node("EngineSound"):sound_pause()`
function SoundNode:sound_pause() end

---Resumes the paused sound effect.
---
---Example: `self.node:get_node("EngineSound"):sound_resume()`
function SoundNode:sound_resume() end

---Plays one sound of its list (1 = the first), whatever the play mode; variation and delay apply.
---
---Example: `self.node:get_node("Footsteps"):sound_play_index(2)`
---@param index integer Which sound of the list, from 1; out of range plays nothing. The cooldown doesn't apply
function SoundNode:sound_play_index(index) end

---How many sounds it has.
---
---Example: `local n = self.node:get_node("Footsteps"):sound_count()`
---@return integer count How many sounds are in its list
function SoundNode:sound_count() end

---The sound it played last (1 = the first; 0 = none yet).
---
---Example: `local i = self.node:get_node("Footsteps"):sound_last()`
---@return integer index The sound played last, from 1; 0 when none has played yet
function SoundNode:sound_last() end

---Plays or resumes the background music on this MusicNode.
---
---Example: `Scene.find_node("Music"):music_play()`
function MusicNode:music_play() end

---Stops background music on this MusicNode.
---
---Example: `Scene.find_node("Music"):music_stop()`
function MusicNode:music_stop() end

---Pauses background music on this MusicNode.
---
---Example: `Scene.find_node("Music"):music_pause()`
function MusicNode:music_pause() end

---Resumes paused background music on this MusicNode.
---
---Example: `Scene.find_node("Music"):music_resume()`
function MusicNode:music_resume() end

---Fades this MusicNode's volume to `volume` (0..1) over `seconds`, starting
---it if it isn't playing.
---
---Example: `Scene.find_node("Music"):music_fade(0, 2.0, true)`
---@param volume number Target fade level from 0 to 1, multiplied with the node's Volume; a fade to 0 doesn't start stopped music
---@param seconds number How long the fade takes, in seconds
---@param stop_at_end? boolean True stops the music when the fade reaches 0 (default false: it keeps playing silently)
function MusicNode:music_fade(volume, seconds, stop_at_end) end

-- ----------------------------------------------------------------------------
-- CameraNode (Node-invoked) Methods
-- ----------------------------------------------------------------------------

---Sets the zoom level on this CameraNode.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_set_zoom(2.0)`
---@param zoom number 1 = 100%, 2 = everything twice as big; clamped to Min / Max Zoom (default 0.1 to 10); eased there when Smooth Zoom is on
function CameraNode:camera_set_zoom(zoom) end

---Gets the configured zoom level on this CameraNode.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_set_zoom(cam:camera_get_zoom() * 1.1)`
---@return number The zoom it is set to (it may still be easing there); 1 for other node types
function CameraNode:camera_get_zoom() end

---Sets the target Node to follow.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_set_target(Scene.find_node("Player"))`
---@param target Node? The node to follow, from now on in single-target mode; nil stops following and the camera stays where it is
function CameraNode:camera_set_target(target) end

---Adds a node to the group this camera frames (see Camera.add_target).
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_add_target(Scene.find_node("Boss"), {weight = 2})`
---@param target Node The node to add; a single follow target joins the group too, and adding one again updates its options
---@param options? CameraTargetOptions weight (default 1), weight_x, weight_y, radius (px, default 50), offset_x, offset_y, priority; nil for the defaults
function CameraNode:camera_add_target(target, options) end

---Takes a node out of this camera's group.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_remove_target(Scene.find_node("Boss"))`
---@param target Node The node to take out; with none left the camera stays where it is
function CameraNode:camera_remove_target(target) end

---Stops this camera following anything.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_clear_targets()`
function CameraNode:camera_clear_targets() end

---The node this camera follows (single target), or nil.
---
---Example: `local cam = Scene.find_node("MainCamera"); local target = cam:camera_get_target()`
---@return Node? The single node it follows; nil when there is none
function CameraNode:camera_get_target() end

---Every node this camera follows.
---
---Example: `local cam = Scene.find_node("MainCamera"); for _, t in ipairs(cam:camera_get_targets()) do Log.info(t.name) end`
---@return Node[] Every node it follows (the group, or the single target alone); empty when none
function CameraNode:camera_get_targets() end

---Sets the fixed world position for the camera target.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_set_target_position(640, 360)`
---@param x number World X in px to centre on; a single target stops being followed (in group mode the group still wins); a Vec2 here sets both
---@param y number World Y in px; omit when x is a vector
function CameraNode:camera_set_target_position(x, y) end

---Shakes this camera: its Shake Preset (Custom: its Shake Types / Speed / Intensity). Strength is how far it moves, in pixels.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_shake(6, 0.3)`
---@param strength? number How far it moves, in px; nil for the Shake Preset's
---@param duration? number Seconds it lasts; nil for the preset's (which can be endless)
function CameraNode:camera_shake(strength, duration) end

---Immediately cancels any active screen shake.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_stop_shake()`
function CameraNode:camera_stop_shake() end

---Checks if screen shake is currently active.
---
---Example: `local cam = Scene.find_node("MainCamera"); if not cam:camera_is_shaking() then cam:camera_shake(4) end`
---@return boolean true while a shake plays; false for other node types
function CameraNode:camera_is_shaking() end

---Constrains camera movement within bounding rectangle limits.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_set_limits(0, 2560, 0, 720)`
---@param left number World X in px the view's left edge never goes past
---@param right number World X of the right edge; when narrower than the view, the camera centres between left and right
---@param top number World Y in px the view's top edge never goes above
---@param bottom number World Y of the bottom edge (+y is down)
function CameraNode:camera_set_limits(left, right, top, bottom) end

---Clears all bounding rectangle limits.
---
---Example: `local cam = Scene.find_node("MainCamera"); cam:camera_clear_limits()`
function CameraNode:camera_clear_limits() end

-- ----------------------------------------------------------------------------
-- LDtk Node Methods (on an LdtkLevelNode; see engine/LDTK.md)
-- ----------------------------------------------------------------------------

---@class LdtkColor
---@field r integer
---@field g integer
---@field b integer
---@field a integer

---@class LdtkTileRect
---@field tileset_uid integer
---@field x number
---@field y number
---@field w number
---@field h number

---@class LdtkEntityRef
---@field field string EntityRef field name
---@field iid string Referenced entity iid
---@field index integer Element of an array field (0 = single field)
---@field level? string Level holding the target

---@class LdtkEntity
---@field identifier string Entity definition identifier (e.g. "Turret")
---@field iid string Unique instance id (EntityRef fields point to it)
---@field x number X in level pixels (pivot point)
---@field y number Y in level pixels (pivot point)
---@field world_x number X in world coordinates
---@field world_y number Y in world coordinates
---@field cx integer Grid cell X
---@field cy integer Grid cell Y
---@field width number
---@field height number
---@field pivot_x number
---@field pivot_y number
---@field level string Level identifier
---@field color LdtkColor Smart colour
---@field tile? LdtkTileRect The entity's LDtk tile
---@field tags string[]
---@field fields table<string, any> Field values (arrays as Lua arrays; Point = {cx, cy}; Enum = value id; EntityRef = iid; Tile = LdtkTileRect)
---@field enums table<string, string> Enum fields: field name -> enum name
---@field refs LdtkEntityRef[] EntityRef values of its fields
---@field node? Node The spawned node (while the level is built)

---@class LdtkLevel
---@field identifier string
---@field iid string
---@field uid integer
---@field world string World identifier
---@field world_x integer
---@field world_y integer
---@field depth integer World depth
---@field width integer Pixels
---@field height integer Pixels
---@field x number Level origin in world coordinates
---@field y number
---@field bg_color LdtkColor
---@field fields table<string, any> Level fields
---@field layers string[] Layer identifiers (top first)
---@field neighbours LdtkNeighbour[]

---@class LdtkNeighbour
---@field level string Level identifier
---@field iid string
---@field dir string n s e w nw ne sw se < > o

---@class LdtkWorld
---@field identifier string
---@field iid string
---@field layout string Free, GridVania, LinearHorizontal, LinearVertical
---@field grid_width integer
---@field grid_height integer
---@field levels string[]

---@class LdtkLayer
---@field identifier string
---@field type string IntGrid, Entities, Tiles, AutoLayer
---@field grid_size integer
---@field width integer Cells
---@field height integer Cells
---@field visible boolean
---@field opacity number
---@field parallax_x number
---@field parallax_y number
---@field parallax_scaling boolean
---@field offset_x number
---@field offset_y number
---@field entities integer
---@field tiles integer

---@class LdtkIntGridValue
---@field value integer
---@field identifier string
---@field color LdtkColor
---@field collision string none, solid, one_way, trigger

---@class LdtkTile
---@field id integer Tile id in its tileset
---@field tileset_uid integer
---@field flip_x boolean
---@field flip_y boolean
---@field custom_data string Tileset custom data of the tile
---@field enums string[] Enum values tagging the tile

---@class LdtkEnumValue
---@field id string
---@field index integer
---@field color LdtkColor
---@field tile? LdtkTileRect

---@class LdtkEntityDef
---@field identifier string
---@field width number
---@field height number
---@field color LdtkColor
---@field tags string[]
---@field fields {identifier: string, type: string, enum?: string}[]

---@class LdtkLink
---@field source Node
---@field target? Node
---@field field string
---@field source_iid string
---@field target_iid string
---@field index integer

---Gets the current level identifier.
---
---Example: `local lv = Scene.find_node("Level"); Log.info("In " .. lv:ldtk_get_level_identifier())`
---@return string The current level's identifier; "" when no level is loaded
function LdtkLevelNode:ldtk_get_level_identifier() end

---Lists level identifiers (every level, or one world's).
---
---Example: `local lv = Scene.find_node("Level"); for _, id in ipairs(lv:ldtk_get_levels()) do Log.info(id) end`
---@param world? string World identifier (default: every level of the project); an unknown world gives an empty list
---@return string[] Level identifiers in project order
function LdtkLevelNode:ldtk_get_levels(world) end

---Switches to another level (identifier or iid); colliders and entities are rebuilt.
---
---Example: `local lv = Scene.find_node("Level"); local ok = lv:ldtk_load_level("Level_2")`
---@param identifier LdtkLevel|string Level identifier (looked up in the current world first) or iid
---@return boolean ok true when the level was found and built; false for an unknown level or no project
function LdtkLevelNode:ldtk_load_level(identifier) end

---Gets a level's details (the current level by default).
---
---Example: `local lv = Scene.find_node("Level"); local info = lv:ldtk_get_level(); Log.info(info.width)`
---@param level? LdtkLevel|string Level identifier or iid (default: the current level); an unknown name gives the empty result
---@return LdtkLevel? The level's details (x, y are its origin in world px); nil for an unknown level or no project
function LdtkLevelNode:ldtk_get_level(level) end

---Gets the current level size in pixels.
---
---Example: `local lv = Scene.find_node("Level"); local w, h = lv:ldtk_get_level_size(); Log.info(w, h)`
---@return number width The current level's width in px (0 with no level)
---@return number height The current level's height in px (0 with no level)
function LdtkLevelNode:ldtk_get_level_size() end

---Gets a level field value (nil if absent or null).
---
---Example: `local lv = Scene.find_node("Level"); local music = lv:ldtk_get_level_field("music")`
---@param name string Level field identifier, as named in LDtk
---@param level? LdtkLevel|string Level identifier or iid (default: the current level)
---@return any The field's value (arrays as Lua arrays, Point as {cx, cy}, Enum as its value id, EntityRef as an iid); nil when absent or null
function LdtkLevelNode:ldtk_get_level_field(name, level) end

---Gets every field of a level.
---
---Example: `local lv = Scene.find_node("Level"); local fields = lv:ldtk_get_level_fields(); Log.info(fields.music)`
---@param level? LdtkLevel|string Level identifier or iid (default: the current level); an unknown name gives the empty result
---@return table<string, any> Field identifier to value (null fields are left out); empty for an unknown level
function LdtkLevelNode:ldtk_get_level_fields(level) end

---Lists a level's neighbours.
---
---Example: `local lv = Scene.find_node("Level"); for _, n in ipairs(lv:ldtk_get_neighbours()) do Log.info(n.dir) end`
---@param level? LdtkLevel|string Level identifier or iid (default: the current level); an unknown name gives the empty result
---@return LdtkNeighbour[] The level's neighbours with their direction (n, s, e, w, nw, ne, sw, se, < or > for depth, o for overlap); empty for an unknown level
function LdtkLevelNode:ldtk_get_neighbours(level) end

---The level at a world position (world mode: any loaded level; otherwise looked up in the world layout).
---
---Example: `local lv = Scene.find_node("Level"); local id = lv:ldtk_level_at(self.node:get_global_position())`
---@param x number World X in px
---@param y number World Y in px
---@return string? Identifier of the level under the point; nil when there is none
function LdtkLevelNode:ldtk_level_at(x, y) end

---Lists the project's worlds.
---
---Example: `local lv = Scene.find_node("Level"); for _, w in ipairs(lv:ldtk_get_worlds()) do Log.info(w.identifier) end`
---@return LdtkWorld[] Every world of the project with its layout and level identifiers
function LdtkLevelNode:ldtk_get_worlds() end

---Gets the current world identifier.
---
---Example: `local lv = Scene.find_node("Level"); local world = lv:ldtk_get_world()`
---@return string The current world's identifier
function LdtkLevelNode:ldtk_get_world() end

---Switches world (its first level, or `level`).
---
---Example: `local lv = Scene.find_node("Level"); local ok = lv:ldtk_set_world("Dungeon", "Dungeon_Entrance")`
---@param world string World identifier
---@param level? LdtkLevel|string Level identifier in that world to load (default: the world's first level)
---@return boolean ok true when switched; false (nothing changes) for an unknown or empty world, or a level not in it
function LdtkLevelNode:ldtk_set_world(world, level) end

---World mode: every level of the world at its world position (rebuilds).
---
---Example: `local lv = Scene.find_node("Level"); lv:ldtk_set_world_mode(true)`
---@param on boolean true to load every level of the world at its world position, false for the current level only
function LdtkLevelNode:ldtk_set_world_mode(on) end

---Returns true when world mode is on (every level of the world loaded at its world position).
---
---Example: `local lv = Scene.find_node("Level"); if not lv:ldtk_is_world_mode() then lv:ldtk_set_world_mode(true) end`
---@return boolean true when world mode is on
function LdtkLevelNode:ldtk_is_world_mode() end

---Lists a level's layers (top first).
---
---Example: `local lv = Scene.find_node("Level"); for _, layer in ipairs(lv:ldtk_get_layers()) do Log.info(layer.type) end`
---@param level? LdtkLevel|string Level identifier or iid (default: the current level); an unknown name gives the empty result
---@return LdtkLayer[] The level's layers, top first; empty for an unknown level
function LdtkLevelNode:ldtk_get_layers(level) end

---Shows or hides a layer (in every loaded level).
---
---Example: `local lv = Scene.find_node("Level"); lv:ldtk_set_layer_visible("Background", false)`
---@param name LdtkLayer|string Layer identifier, e.g. "Collisions"
---@param visible boolean true to show the layer, false to hide it
function LdtkLevelNode:ldtk_set_layer_visible(name, visible) end

---Returns whether a layer is currently shown.
---
---Example: `local lv = Scene.find_node("Level"); lv:ldtk_set_layer_visible("Fog", not lv:ldtk_is_layer_visible("Fog"))`
---@param name LdtkLayer|string Layer identifier (checked in the current level)
---@return boolean true when the layer exists and is shown
function LdtkLevelNode:ldtk_is_layer_visible(name) end

---Gets the IntGrid value at a world position (0 = empty).
---
---Example: `local lv = Scene.find_node("Level"); local v = lv:ldtk_get_int_grid("Collisions", self.node:get_global_position())`
---@param layer LdtkLayer|string IntGrid layer identifier, e.g. "Collisions"
---@param x number World X in px
---@param y number World Y in px
---@return integer The IntGrid value under the point; 0 for an empty cell, a point outside the level or an unknown layer
function LdtkLevelNode:ldtk_get_int_grid(layer, x, y) end

---Gets the identifier of the IntGrid value at a world position ("" if none / unnamed).
---
---Example: `local lv = Scene.find_node("Level"); local name = lv:ldtk_get_int_grid_name("Collisions", self.node:get_global_position())`
---@param layer LdtkLayer|string IntGrid layer identifier
---@param x number World X in px
---@param y number World Y in px
---@return string The value's identifier set in LDtk; "" for an empty cell or an unnamed value
function LdtkLevelNode:ldtk_get_int_grid_name(layer, x, y) end

---Gets the IntGrid value of a cell.
---
---Example: `local lv = Scene.find_node("Level"); local v = lv:ldtk_get_int_grid_cell("Collisions", 4, 7)`
---@param layer LdtkLayer|string IntGrid layer identifier
---@param cx integer Cell column, 0-based
---@param cy integer Cell row, 0-based
---@param level? LdtkLevel|string Level identifier or iid (default: the current level)
---@return integer The cell's IntGrid value; 0 for an empty cell, a cell outside the layer or an unknown layer or level
function LdtkLevelNode:ldtk_get_int_grid_cell(layer, cx, cy, level) end

---Lists an IntGrid layer's values (name, colour, collision).
---
---Example: `local lv = Scene.find_node("Level"); local values = lv:ldtk_get_int_grid_values("Collisions")`
---@param layer LdtkLayer|string IntGrid layer identifier
---@return LdtkIntGridValue[] The values defined on the layer with their name, colour and collision rule; empty for an unknown layer
function LdtkLevelNode:ldtk_get_int_grid_values(layer) end

---World position -> layer cell.
---
---Example: `local lv = Scene.find_node("Level"); local cx, cy = lv:ldtk_world_to_cell("Collisions", self.node:get_global_position())`
---@param layer LdtkLayer|string Layer identifier, e.g. "Collisions"
---@param x number World X in px
---@param y number World Y in px
---@return integer cx Cell column, 0-based (may be outside the layer); -1 for an unknown layer or no level under the point
---@return integer cy Cell row, 0-based; -1 in the same cases
function LdtkLevelNode:ldtk_world_to_cell(layer, x, y) end

---Layer cell -> world position of its centre.
---
---Example: `local lv = Scene.find_node("Level"); self.node:set_position(lv:ldtk_cell_to_world("Collisions", 4, 7))`
---@param layer LdtkLayer|string Layer identifier, e.g. "Collisions"
---@param cx integer Cell column, 0-based
---@param cy integer Cell row, 0-based
---@param level? LdtkLevel|string Level identifier or iid (default: the current level)
---@return number? x World X in px of the cell's centre (0 with no level loaded); nil for an unknown level
---@return number y World Y in px of the cell's centre
function LdtkLevelNode:ldtk_cell_to_world(layer, cx, cy, level) end

---Collision at a world position: "solid", "one_way", "trigger" or "none", plus the layer and value name.
---
---Example: `local lv = Scene.find_node("Level"); local kind, layer, value = lv:ldtk_get_collision(self.node:get_global_position())`
---@param x number World X in px
---@param y number World Y in px
---@return string type Collision kind: "solid", "one_way", "trigger" or "none"
---@return string? layer Identifier of the IntGrid layer that matched (top layer first); nil for "none"
---@return string|integer|nil value The IntGrid value's identifier, or its number when unnamed; nil for "none"
function LdtkLevelNode:ldtk_get_collision(x, y) end

---The trigger areas built from IntGrid values set to Trigger ("<Layer>_<value>" -> AreaNode).
---Connect to their "body_entered" / "body_exited" events.
---
---Example: `local lv = Scene.find_node("Level"); local spikes = lv:ldtk_get_triggers()["Collisions_spikes"]`
---@return table<string, Node> Trigger AreaNodes by name ("<Layer>_<value>"), from IntGrid values whose collision is Trigger
function LdtkLevelNode:ldtk_get_triggers() end

---Gets the tile of a Tiles/AutoLayer layer at a world position.
---
---Example: `local lv = Scene.find_node("Level"); local tile = lv:ldtk_get_tile("Ground", self.node:get_global_position())`
---@param layer LdtkLayer|string Tiles or AutoLayer layer identifier
---@param x number World X in px
---@param y number World Y in px
---@return LdtkTile? The topmost tile under the point (id, tileset, flips, custom data, enum tags); nil when there is none
function LdtkLevelNode:ldtk_get_tile(layer, x, y) end

---Gets the enum values tagging the tile at a world position (tileset enum tags).
---
---Example: `local lv = Scene.find_node("Level"); local tags = lv:ldtk_get_tile_enums("Ground", self.node:get_global_position())`
---@param layer LdtkLayer|string Tiles or AutoLayer layer identifier
---@param x number World X in px
---@param y number World Y in px
---@return string[] Enum value ids tagging that tile in its tileset; empty when no tile or no tags
function LdtkLevelNode:ldtk_get_tile_enums(layer, x, y) end

---Gets an enum's values (colour, tile, index).
---
---Example: `local lv = Scene.find_node("Level"); for _, v in ipairs(lv:ldtk_get_enum("ItemType") or {}) do Log.info(v.id) end`
---@param name LdtkEnumName Enum identifier, e.g. "ItemType"
---@return LdtkEnumValue[]? The enum's values in order (index is 1-based); nil for an unknown enum
function LdtkLevelNode:ldtk_get_enum(name) end

---Every enum: name -> value ids.
---
---Example: `local lv = Scene.find_node("Level"); local item_types = lv:ldtk_get_enums()["ItemType"]`
---@return table<string, string[]> Enum identifier to its value ids, for every enum of the project
function LdtkLevelNode:ldtk_get_enums() end

---Lists the loaded levels' entities, optionally only those with an identifier.
---
---Example: `local lv = Scene.find_node("Level"); for _, e in ipairs(lv:ldtk_get_entities("Enemy")) do Log.info(e.iid) end`
---@param identifier? LdtkEntity Entity definition identifier to keep, e.g. "Enemy" (default: every entity)
---@return LdtkEntity[] Entities of the loaded levels (every level in world mode), with world_x and world_y in world px
function LdtkLevelNode:ldtk_get_entities(identifier) end

---Lists the loaded levels' entities with a tag.
---
---Example: `local lv = Scene.find_node("Level"); local pickups = lv:ldtk_get_entities_by_tag("pickup")`
---@param tag string Entity tag set on the definition in LDtk
---@return LdtkEntity[] Entities of the loaded levels carrying that tag
function LdtkLevelNode:ldtk_get_entities_by_tag(tag) end

---Gets an entity anywhere in the project by iid.
---
---Example: `local lv = Scene.find_node("Level"); local e = lv:ldtk_get_entity(self.target_iid)`
---@param iid string The entity's instance id
---@return LdtkEntity? The entity, from any level of the project (node is set only while it is spawned); nil for an unknown iid
function LdtkLevelNode:ldtk_get_entity(iid) end

---Gets the node spawned for an entity (by iid).
---
---Example: `local lv = Scene.find_node("Level"); local door = lv:ldtk_get_entity_node(self.door_iid)`
---@param iid string The entity's instance id
---@return Node? The node spawned for it; nil when it is not spawned (level not loaded, no node for the entity, or the node was destroyed)
function LdtkLevelNode:ldtk_get_entity_node(iid) end

---Lists the project's entity definitions.
---
---Example: `local lv = Scene.find_node("Level"); local defs = lv:ldtk_get_entity_defs(); Log.info(defs[1].identifier)`
---@return LdtkEntityDef[] Every entity definition with its size in px, colour, tags and field list
function LdtkLevelNode:ldtk_get_entity_defs() end

---Lists the resolved EntityRef links between spawned entities.
---
---Example: `local lv = Scene.find_node("Level"); for _, link in ipairs(lv:ldtk_get_links()) do Log.info(link.field) end`
---@return LdtkLink[] Each resolved EntityRef (source node, target node when spawned, field, iids, index: 1-based array element or 0)
function LdtkLevelNode:ldtk_get_links() end

-- On any node spawned from an LDtk entity:

---The LDtk entity this node was spawned from (nil otherwise).
---
---Example: `local e = self.node:ldtk_entity(); if e then Log.info(e.identifier) end`
---@return LdtkEntity? The entity this node was spawned from; nil for a node not spawned by an LdtkLevelNode
function LdtkLevelNode:ldtk_entity() end

---The LdtkLevelNode that spawned this node.
---
---Example: `local level = self.node:ldtk_level_node()`
---@return Node? The LdtkLevelNode that spawned this node; nil when none did
function LdtkLevelNode:ldtk_level_node() end

---A field of this node's entity.
---
---Example: `self.health = self.node:ldtk_field("health") or 3`
---@param name string Field identifier on this node's entity
---@return any The field's value (same conversions as entity fields); nil when absent, null, or the node is not an entity
function LdtkLevelNode:ldtk_field(name) end

---The node an EntityRef field points to (the first one for arrays).
---
---Example: `local door = self.node:ldtk_ref("target_door"); if door then door:set_visible(false) end`
---@param field string EntityRef field identifier on this node's entity
---@return Node? The spawned node it points to (the first for an array field); nil when unset, not spawned or not an entity
function LdtkLevelNode:ldtk_ref(field) end

---Nodes referenced by a field, or every reference ({field, iid, node}) without one.
---
---Example: `for _, n in ipairs(self.node:ldtk_refs("lights")) do n:set_visible(true) end`
---@param field? string EntityRef field identifier (default: every reference of every field)
---@return Node[]|{field: string, iid: string, node: Node?}[] With a field: the spawned nodes it references, in order. Without: one {field, iid, node} per reference, node nil when not spawned
function LdtkLevelNode:ldtk_refs(field) end

---Entities whose EntityRef fields point at this one.
---
---Example: `for _, r in ipairs(self.node:ldtk_referenced_by("target")) do Log.info(r.field) end`
---@param field? string Only references made through this field identifier (default: any field)
---@return {node: Node, field: string}[] One {node, field} per spawned entity whose EntityRef points at this node; empty when none
function LdtkLevelNode:ldtk_referenced_by(field) end


-- ============================================================================
-- Global Modules

---@alias EaseName "linear"|"constant"|"in_sine"|"out_sine"|"in_out_sine"|"in_quad"|"out_quad"|"in_out_quad"|"in_cubic"|"out_cubic"|"in_out_cubic"|"in_quart"|"out_quart"|"in_out_quart"|"in_expo"|"out_expo"|"in_out_expo"|"in_back"|"out_back"|"in_out_back"|"in_elastic"|"out_elastic"|"in_out_elastic"|"in_bounce"|"out_bounce"|"in_out_bounce"

---@class TweenOptions
---@field delay? number Seconds before it starts (it starts from the value at that time)
---@field loops? integer Extra runs (-1 = forever)
---@field yoyo? boolean Every other run goes back
---@field on_complete? fun(node: Node) Called when it finishes

---@class TweenModule
---Animates node properties over time with easing.
local TweenModule = {}

---Tweens a property to a value: "position", "scale", "rotation", any numeric
---or colour property ("tint", "emitter.amount", ...; colours as {r, g, b[, a]} 0..1),
---or a material parameter ("shader:amount"). Returns the tween's id.
---
---Example: `local id = Tween.to(self.node, "scale", {1.2, 1.2}, 0.15, "out_quad", {loops = -1, yoyo = true})`
---@param node Node The node to animate; its tweens pause with it and end when it is destroyed
---@param property string "position", "scale", "rotation", any numeric or colour property by name ("tint"), or "shader:<param>" for a material parameter
---@param value number|number[] The target: a number, or a list such as {x, y} or {r, g, b[, a]} (colours 0..1, alpha default 1)
---@param duration number Seconds to reach the value; 0 jumps there on the next frame
---@param ease? EaseName Easing curve name, default "out_quad" (an unknown name also gives out_quad)
---@param options? TweenOptions delay (seconds), loops (extra runs, -1 = forever), yoyo and on_complete(node); nil for none
---@return integer id The tween's id for Tween.cancel and Tween.is_running; 0 when the node or property wasn't found
function TweenModule.to(node, property, value, duration, ease, options) end

---Stops a tween (it stays where it is).
---
---Example: `if self.fade_id then Tween.cancel(self.fade_id) end`
---@param id integer A tween id from Tween.to
---@return boolean found false when no tween has that id (finished or already cancelled); on_complete is not called
function TweenModule.cancel(id) end

---Stops a node's tweens (all, or one property's).
---
---Example: `local stopped = Tween.cancel_all(self.node, "position")`
---@param node Node The node whose tweens stop where they are
---@param property? string Only this property's tweens; nil stops every tween on the node
---@return integer count How many tweens were stopped
function TweenModule.cancel_all(node, property) end

---Whether the tween with this id is still playing.
---
---Example: `if not Tween.is_running(self.bounce_id) then self.bounce_id = nil end`
---@param id integer A tween id from Tween.to
---@return boolean true while it plays (its delay and loops included); false once finished or cancelled
function TweenModule.is_running(id) end

---Maps progress 0..1 through an easing curve (for your own animation).
---
---Example: `local k = Tween.ease("in_out_sine", self.elapsed / self.duration)`
---@param ease EaseName Easing curve name; an unknown name is linear (and logs a warning)
---@param t number Progress, clamped to 0..1
---@return number The eased progress: 0 at t = 0, 1 at t = 1 (back and elastic curves overshoot in between)
function TweenModule.ease(ease, t) end

-- ============================================================================

---@class PoolModule
---Reuses instances of a component instead of creating and freeing them (bullets, sparks, coins). A pooled node is parked disabled (no update, no drawing, bodies off) and comes back on take; `node:destroy()` / `queue_free()` on one returns it to its pool. Its root's script gets `on_spawn()` before its first update after every take (after `ready()` the first time) and `on_despawn()` when returned. Pools last while the scene is loaded.
local PoolModule = {}

---Takes an instance of the component: a parked one, else a new one (nil at the pool's max). Added under `parent` (else the scene's root) at x, y local to it.
---
---Example: `local b = Pool.take("components/bullet.component.json", self.node:get_parent(), self.node.position)`
---@param component ComponentPath|string The .component.json path; it names the pool (one per path in the current scene)
---@param parent? Node The node to put it under; nil for the scene's root
---@param x? number|Vec2 X in px local to the parent, or a Vec2 or {x, y} for both; default 0
---@param y? number Y in px local to the parent, when x is a number; default 0
---@return Node? The instance's root node, or nil at the pool's max or when the component can't be loaded (a warning says which)
function PoolModule.take(component, parent, x, y) end

---Returns a taken instance to its pool (the same as `node:destroy()` on it).
---
---Example: `Pool.release(self.node)`
---@param node Node The root of an instance taken from a pool
---@return boolean false when it isn't a taken pooled node (never pooled, or already parked)
function PoolModule.release(node) end

---Makes instances up front (parked) so the first takes don't create them mid-game.
---
---Example: `Pool.prewarm("components/bullet.component.json", 64)`
---@param component ComponentPath|string The .component.json path of the pool
---@param count integer How many instances the pool should have in total (not extra ones); capped by its max
function PoolModule.prewarm(component, count) end

---Caps how many instances the pool makes (0 = no cap); `take` returns nil at the cap.
---
---Example: `Pool.set_max("components/spark.component.json", 200)`
---@param component ComponentPath|string The .component.json path of the pool
---@param max integer The most instances it ever makes; 0 = no cap (negative counts as 0); lowering it frees nothing
function PoolModule.set_max(component, max) end

---How many instances are taken, parked and made in total.
---
---Example: `local active, parked, made = Pool.stats("components/bullet.component.json")`
---@param component ComponentPath|string The .component.json path of the pool
---@return integer active Instances taken and not yet returned (0 for an unknown pool)
---@return integer parked Instances parked, waiting to be taken
---@return integer created Instances made in total (taken plus parked)
function PoolModule.stats(component) end

-- ============================================================================

---@class LevelGenModule
---Procedural levels: a generator file (.levelgen.json) is a graph of nodes - noise, random fill, cellular caves, thresholds, combines... - whose tile output writes a level into a TileMap. The same generator and seed always give the same level. Guide: engine/docs/level_generator.md.
local LevelGenModule = {}

---Generates a level into a TileMap node: its map becomes the generator's size and its cells the tiles (colliders rebuilt when it is Solid); entity outputs' components are placed as its children (generating again replaces them). Emits `level_generated` (the tile map's name) on the event bus.
---
---Example: `local ok, why = LevelGen.generate("levels/caves.levelgen.json", self.node:get_node("Ground"), os.time())`
---@param generator string A .levelgen.json file, such as "levels/caves.levelgen.json"
---@param tilemap TileMapNode The TileMap node to fill: its size, cells and generated entities are replaced
---@param seed? integer Seed as an integer; nil or 0 uses the generator's own seed
---@return boolean ok true when the level was written
---@return string? why Why it failed (bad file, not a TileMap node...); nil on success
function LevelGenModule.generate(generator, tilemap, seed) end

---A generator's values without a tile map (row-major, 0..1 usually) - to place things yourself; `node_id` reads any node's grid (default: the output).
---
---Example: `local g = LevelGen.values("levels/caves.levelgen.json", 42); local solid = g.values[y * g.width + x + 1] >= 0.5`
---@param generator string A .levelgen.json file, such as "levels/caves.levelgen.json"
---@param seed? integer Seed as an integer; nil or 0 uses the generator's own seed
---@param node_id? integer Id of the graph node whose grid to read; nil or 0 for the generator's output
---@return {width: integer, height: integer, values: number[]}? grid width and height in cells and values row-major (index y * width + x + 1); nil on error
---@return string? why Why it failed (bad file, no such node...); nil on success
function LevelGenModule.values(generator, seed, node_id) end

---The entity outputs' placements without a tile map: a component and a cell (x, y) each.
---
---Example: `for _, e in ipairs(LevelGen.entities("levels/caves.levelgen.json", seed)) do Scene.instantiate(e.component, nil, e.x * 16 + 8, e.y * 16 + 8) end`
---@param generator string A .levelgen.json file, such as "levels/caves.levelgen.json"
---@param seed? integer Seed as an integer; nil or 0 uses the generator's own seed
---@return {component: ComponentPath|string, x: integer, y: integer}[]? entities One entry per placed entity: its component and cell x, y (cells from 0, not px); nil on error
---@return string? why Why it failed; nil on success
function LevelGenModule.entities(generator, seed) end

-- ============================================================================

---@class EventsModule
---The global event bus: named events any script (or engine code) can emit and any script can listen to, without a reference to the other side - gameplay telling the HUD the score changed, a level telling the game flow it's complete, audio or achievements reacting to gameplay. Handlers run in the order they were connected; they may emit, connect, disconnect or destroy nodes. Connections end with the script that made them (or `disconnect`, or the scope node). The bus lasts across scene changes. Node events (`node:connect` / `node:emit`) are separate.
local EventsModule = {}

---Calls `handler(value, source)` every time `event` is emitted; `source` is the node of the script that emitted it (or the node passed to `emit`), nil from global code. Released when the connecting script's node is destroyed, or with `scope` when given (a global script's connections otherwise last for the game).
---
---Example: `self.scoreConn = Events.connect("score_changed", function(score) self.label.text = tostring(score) end)`
---@param event ProjectEvent|string Event name: one of the project's custom events, or any string
---@param handler fun(value: any, source: Node?) Called as handler(value, source) on every emit; an error in it is logged and the other handlers still run
---@param scope? Node A node that ends the connection when destroyed; nil: it ends with the connecting script's node (from global code, never)
---@return integer id Connection id for Events.disconnect
function EventsModule.connect(event, handler, scope) end

---Like `connect`, but the handler is released after its first call.
---
---Example: `Events.once("level_complete", function(level) Save.set("last_level", level) end)`
---@param event ProjectEvent|string Event name: one of the project's custom events, or any string
---@param handler fun(value: any, source: Node?) Called as handler(value, source) on the next emit only, then released
---@param scope? Node A node that ends the connection when destroyed (before it ran); nil: the connecting script's node
---@return integer id Connection id for Events.disconnect
function EventsModule.once(event, handler, scope) end

---Removes a connection made with `connect` or `once`.
---
---Example: `Events.disconnect(self.scoreConn)`
---@param id integer An id from Events.connect or Events.once
---@return boolean true when removed; false when it was already gone (or the id is a node connection's)
function EventsModule.disconnect(id) end

---Emits a global event now: every handler runs before `emit` returns. The value can be anything, tables included (engine code listening gets numbers, strings, booleans and nodes). The source defaults to this script's node.
---
---Example: `Events.emit("score_changed", self.score)`
---@param event ProjectEvent|string Event name: one of the project's custom events, or any string
---@param value? any Passed to the handlers as it is, tables included; nil for none
---@param source? Node The node handlers get as source; default the emitting script's node (nil from global code)
function EventsModule.emit(event, value, source) end

---Emits a global event at the end of the frame (after every node has updated), in the order emitted - for events raised in the middle of an update that listeners shouldn't handle there. A source that is destroyed meanwhile arrives as nil.
---
---Example: `Events.emit_deferred("enemy_killed", { kind = "slime", points = 50 })`
---@param event ProjectEvent|string Event name: one of the project's custom events, or any string
---@param value? any Passed to the handlers as it is, tables included; nil for none
---@param source? Node The node handlers get as source; default the emitting script's node, nil if it is destroyed before the frame ends
function EventsModule.emit_deferred(event, value, source) end

---How many handlers listen to an event (Lua connections and engine listeners).
---
---Example: `if Events.listener_count("player_died") == 0 then Log.warn("nobody handles player_died") end`
---@param event ProjectEvent|string Event name: one of the project's custom events, or any string
---@return integer count Lua connections plus engine listeners; 0 when nobody listens
function EventsModule.listener_count(event) end

-- ============================================================================

---@alias AccessibilityKey "ui_scale"|"colorblind"|"colorblind_strength"|"colorblind_simulate"|"subtitles"|"captions"|"subtitle_scale"|"subtitle_background"|"screen_shake"

---@class AccessibilitySettings
---@field ui_scale number 0.5..3 - top-level UI elements grow around the screen corner / edge / centre they're nearest to
---@field colorblind "none"|"protanopia"|"deuteranopia"|"tritanopia" Colour filter (corrects the picture)
---@field colorblind_strength number 0..1
---@field colorblind_simulate boolean Show how it looks with the deficiency instead (testing)
---@field subtitles boolean Spoken lines on the subtitle track
---@field captions boolean Sounds' captions on the subtitle track
---@field subtitle_scale number 0.5..3
---@field subtitle_background number Backdrop opacity 0..1
---@field screen_shake number 0..2 - scales every camera shake / trauma

---@class AccessibilityModule
---The player's accessibility settings: applied at once, saved with
---Accessibility.save() (accessibility.json next to the save files) and
---loaded when the game starts over the project's defaults (Project
---Settings > Accessibility). See the Accessibility Menu script template.
local AccessibilityModule = {}

---A setting's value.
---
---Example: `local s = Accessibility.get("ui_scale")`
---@param key AccessibilityKey The setting's name, e.g. "ui_scale", "colorblind" or "subtitles"
---@return any Its value: a number, a boolean, or the colour filter's name for colorblind; nil for an unknown key
function AccessibilityModule.get(key) end

---Changes a setting (false for an unknown key or value).
---
---Example: `Accessibility.set("colorblind", "deuteranopia")`
---@param key AccessibilityKey The setting's name
---@param value number|boolean|string A number for scales and strengths (clamped to the setting's range), true or false for switches, or "none", "protanopia", "deuteranopia" or "tritanopia" for colorblind
---@return boolean ok true when applied; false (with a warning) for an unknown key or colour filter name
function AccessibilityModule.set(key, value) end

---Every setting.
---
---Example: `for k, v in pairs(Accessibility.get_all()) do print(k, v) end`
---@return AccessibilitySettings A table of every setting by key
function AccessibilityModule.get_all() end

---Saves the player's settings.
---
---Example: `Accessibility.save()`
---@return boolean ok true when accessibility.json was written; false when it couldn't be
function AccessibilityModule.save() end

---Back to the project's defaults (save to keep).
---
---Example: `Accessibility.reset()`
function AccessibilityModule.reset() end

---@class SubtitleOptions
---@field speaker? string Shown before the line
---@field duration? number Seconds (default: its reading time)
---@field caption? boolean A sound caption (shown when the player has captions on) instead of a spoken line
---@field color? Color

---@class SubtitlesModule
---The subtitle track: lines at the bottom centre over everything, each for
---a time (up to 3 at once). Spoken lines show when the player has
---subtitles on, captions when captions are on.
local SubtitlesModule = {}

---Shows a line; returns its id (0 when the player turned that kind off).
---
---Example: `Subtitles.show("Over here!", {speaker = "Ada"})`
---@param text string The line, rich text allowed; an empty string shows nothing
---@param options? SubtitleOptions speaker (shown before the line), duration (seconds; default its reading time: 0.8 s + 15 characters a second, at least 1.5 s), caption (true for a sound caption) and color ({r, g, b, a} 0..255; default white, light blue for captions)
---@return integer id The line's id for hide; 0 when the text is empty or the player turned that kind of line off
function SubtitlesModule.show(text, options) end

---Takes a line down early.
---
---Example: `Subtitles.hide(id)`
---@param id integer An id from show; 0 or a line that has already gone does nothing
function SubtitlesModule.hide(id) end

---Takes every line down.
---
---Example: `Subtitles.clear()`
function SubtitlesModule.clear() end

---Lines on screen now.
---
---Example: `if Subtitles.count() == 0 then self:next_bark() end`
---@return integer How many lines are on screen now (0 to 3)
function SubtitlesModule.count() end

-- ============================================================================

---@class ResourceBase
---What every resource table has (engine/docs/resources.md): its class's
---properties as fields (the values from its .resource.json), the class's
---methods, and these. Changes made at runtime are never written to the file.
---@field resource_path string The resource file ("resources/sword.resource.json").
---@field on_load? fun(self: self) Called once per table, after its property values are set.
local ResourceBase = {}

---A copy of this resource as it is now: its tables are copied too (other
---resources it holds stay shared). Owned by the calling script's component
---instance; on_load is not called.
---
---Example: `local mine = self.stats:duplicate(); mine.speed = mine.speed * 2`
---@generic T
---@param self T The resource table to copy (call it with a colon: res:duplicate())
---@return T copy The copy, with the same class and methods; nil (with a warning) when called on something that isn't a resource
function ResourceBase:duplicate() end

---@class ResourceModule
---Resources: data assets of a Lua class (resources/*.resource.json). A
---script usually gets one through a `type = "resource"` property; these
---load one by path.
local ResourceModule = {}

---The shared table of a resource file - the same table everywhere (loaded,
---and on_load called, the first time). nil when the file or its class has
---a problem (a warning says what).
---
---Example: `local sword = Resource.load("resources/sword.resource.json"); Log.info(sword.damage)`
---@param path ResourcePath|string A .resource.json path, such as "resources/sword.resource.json"
---@return ResourceBase? The resource's shared table (the same one on every call), or nil when the file or its class has a problem (a warning says what)
function ResourceModule.load(path) end

---A fresh table of a resource file (its values from the file, on_load
---called), owned by the calling script's component instance and released
---with it.
---
---Example: `self.ammo = Resource.new("resources/clip.resource.json")`
---@param path ResourcePath|string A .resource.json path, such as "resources/sword.resource.json"
---@return ResourceBase? A fresh table owned by the calling script's component instance, or nil when the file or its class has a problem
function ResourceModule.new(path) end

---@alias SaveValue nil|boolean|number|string|table

---@class SaveModule
---Persistent save data: plain values (booleans, numbers, strings, tables of
---those) stored as JSON in the player's user-data folder
---(macOS ~/Library/Application Support/<game>, Windows %APPDATA%\<game>,
---Linux ~/.local/share/<game>). Read on first use; written by Save.flush()
---and when the game quits.
local SaveModule = {}

---Stores a value (nil removes the key). Tables are stored by reference:
---changes to a table you got from Save.get are saved too.
---
---Example: `if score > Save.get("best_score", 0) then Save.set("best_score", score) end`
---@param key SaveKey|string The name to store under; must be a string (anything else is a script error)
---@param value SaveValue A boolean, number, string or table of those; nil removes the key
function SaveModule.set(key, value) end

---Returns the stored value for a key, or the default when the key is not set.
---
---Example: `local settings = Save.get("settings", {music = 0.8, fullscreen = false})`
---@param key SaveKey|string The name it was stored under
---@param default? SaveValue Returned when the key isn't set (it isn't stored); default nil
---@return SaveValue The stored value, or default
function SaveModule.get(key, default) end

---Whether a value is stored under the key.
---
---Example: `if not Save.has("tutorial_done") then Scene.change_scene("tutorial") end`
---@param key SaveKey|string The name to look up
---@return boolean true when the key holds a value (false counts as a value)
function SaveModule.has(key) end

---Removes a key from the save data.
---
---Example: `Save.delete("checkpoint")`
---@param key SaveKey|string The name to remove; a key that isn't set does nothing
function SaveModule.delete(key) end

---Returns every stored key, sorted.
---
---Example: `for _, key in ipairs(Save.keys()) do Log.info(key, Save.get(key)) end`
---@return string[] keys Every stored key, sorted alphabetically
function SaveModule.keys() end

---Removes every key (the file is rewritten on the next flush).
---
---Example: `Save.clear(); Save.flush()`
function SaveModule.clear() end

---Writes the save file now.
---
---Example: `if not Save.flush() then Log.warn("could not write save file") end`
---@return boolean ok true when the file was written; false when it couldn't be (an error is logged)
function SaveModule.flush() end

---Switches to another save file (<name>.json; default "save"), writing the
---current one first. Returns the current slot.
---
---Example: `local now = Save.slot("slot_2") -- "slot_2": the slot in use after switching`
---@param name? string The slot to switch to: the file <name>.json in the user-data folder (characters other than letters, digits, space, - _ and . become _); nil, "" or the current slot only reads it
---@return string slot The slot in use after the call ("save" by default)
function SaveModule.slot(name) end

---Returns the file path of the current save slot.
---
---Example: `Log.info("saving to", Save.path())`
---@return string path The full path of the current slot's file
function SaveModule.path() end

-- ============================================================================

---@class CrashReport
---@field path string The report file
---@field text string Its contents (version, platform, reason, stack, recent log lines)

---@class CrashModule
---Crash reports from earlier runs of this game. A crash (an engine error, a
---failed check, invalid memory access) writes a report to the player's
---user-data folder (`<user data>/crashes`). Read them at startup and send
---them where you like (Editor-free: your own server, a "send report?" menu).
local CrashModule = {}

---The reports from earlier runs not yet dismissed (oldest first).
---
---Example: `for _, r in ipairs(Crash.pending()) do show_report_dialog(r.text); Crash.dismiss(r.path) end`
---@return CrashReport[] Reports not yet dismissed, oldest first, each with path and text (empty when there are none or no crash folder)
function CrashModule.pending() end

---Stops offering a report (it stays in the folder as .seen).
---
---Example: `Crash.dismiss(report.path)`
---@param path string A report's path from Crash.pending()
---@return boolean ok false when the path isn't a pending report in the crash folder
function CrashModule.dismiss(path) end

---Adds a line to the next crash report's "recent" list (what the game was
---doing: "entered level 3", "boss fight"). The last 48 lines are kept.
---
---Example: `Crash.note("loaded " .. level_name)`
---@param text string What the game is doing, e.g. "entered level 3" (newlines become spaces; cut at 240 bytes)
function CrashModule.note(text) end

---The crash folder.
---
---Example: `print("crash reports in " .. Crash.dir())`
---@return string The crash folder's path ("" when there is none, e.g. on the web)
function CrashModule.dir() end

-- ============================================================================

---@class EngineModule
---Core engine statistics, frame timing, and display information.
local EngineModule = {}

---Gets current display refresh frames per second.
---
---Example: `Log.info("FPS: " .. Engine.get_fps())`
---@return integer Frames drawn per second, averaged over the last moments (not the monitor's refresh rate)
function EngineModule.get_fps() end

---Gets the last frame duration in seconds.
---
---Example: `local dt = Engine.get_delta_time(); self.elapsed = self.elapsed + dt`
---@return number The last frame's length in seconds (about 0.0167 at 60 fps)
function EngineModule.get_delta_time() end

---Gets running time in seconds since the engine launched.
---
---Example: `local t = Engine.get_time(); self.node:set_position(self.base_x, self.base_y + math.sin(t * 2) * 8)`
---@return number Seconds since the game window opened; keeps counting while paused
function EngineModule.get_time() end

---Gets current physical window width and height in screen pixels.
---
---Example: `local w, h = Engine.get_window_size()`
---@return integer width The window's width in screen px (the screen's when fullscreen)
---@return integer height The window's height in screen px
function EngineModule.get_window_size() end

---Gets virtual canvas reference resolution (e.g. 1280x720).
---
---Example: `local vw, vh = Engine.get_virtual_size(); self.node:set_position(vw / 2, vh / 2)`
---@return number width The game's drawing width in px from Project Settings > Video (default 1280; with Screen Fill Expand it grows to the window's shape)
---@return number height The game's drawing height in px (default 720)
function EngineModule.get_virtual_size() end

---Pauses the game: nodes with pause mode "pausable" (the default) stop
---updating and physics stops; "always" nodes keep running (pause menus).
---
---Example: `if Input.is_action_pressed("pause") then Engine.set_paused(not Engine.is_paused()) end`
---@param paused boolean true pauses the game, false resumes it
function EngineModule.set_paused(paused) end

---Sets the time scale: the whole game's (no tag), or that of the nodes with
---a tag and their children. 0.5 is half speed, 0 stops, 1 is normal. The
---whole game's scales physics, animation, tweens and every script's dt; a
---tag's scales those nodes' updates (their bodies freeze at 0). Scales
---multiply. UI nodes, cameras and Always nodes keep real time.
---
---Example: `Engine.set_time_scale(0.3, "enemy") -- a "bullet time" power-up`
---@param scale number 0 or more (1: normal)
---@param tag? string A node tag; nil: the whole game
function EngineModule.set_time_scale(scale, tag) end

---The time scale (the whole game's, or a tag's: 1 when none is set).
---
---Example: `if Engine.get_time_scale() < 1 then self.label.text = "SLOW" end`
---@param tag? string A node tag; nil: the whole game
---@return number scale
function EngineModule.get_time_scale(tag) end

---Hit-stop / freeze frames: stops the game (or only the nodes with the given
---tags) for a moment of real time - the weight of a heavy hit. UI nodes,
---cameras (their shake goes on) and Always nodes keep going.
---
---Example: `Engine.hit_stop(0.08); Camera.add_trauma(0.4)`
---@param seconds number How long (real time), e.g. 0.05 - 0.15
---@param tags? string|string[] Only nodes with one of these tags; nil: the whole game
function EngineModule.hit_stop(seconds, tags) end

---Slow motion that eases down to a time scale, holds, and eases back to
---normal over `seconds` of real time.
---
---Example: `Engine.slow_motion(0.25, 1.2) -- the last enemy falls`
---@param scale number The slowest (0..1)
---@param seconds number The whole effect, real time
---@param ease? EaseName The ramps' curve (default "out_quad")
function EngineModule.slow_motion(scale, seconds, ease) end

---Returns whether the game is currently paused.
---
---Example: `if Engine.is_paused() then return end`
---@return boolean true while the game is paused (Engine.set_paused, or a scene transition that pauses)
function EngineModule.is_paused() end

---Fullscreen on or off: the window covers the screen at its resolution (the
---game is scaled to it) or goes back to the project's window size.
---
---Example: `if Input.is_key_pressed("F11") then Engine.set_fullscreen(not Engine.is_fullscreen()) end`
---@param on boolean true covers the screen (borderless), false goes back to the project's window size; takes effect on the next frame
function EngineModule.set_fullscreen(on) end

---Whether the game is fullscreen.
---
---Example: `local full = Engine.is_fullscreen(); Log.info("Fullscreen: " .. tostring(full))`
---@return boolean true when fullscreen, or when fullscreen was just asked for and is about to happen
function EngineModule.is_fullscreen() end


---@class InputModule
---Engine input subsystem for keyboard, mouse, and mapped action queries.
---Actions are named in Settings > Project > Input (project.json "input"):
---built-in names (move_up, move_down, move_left, move_right, jump, fire,
---secondary, boost, interact, pause, confirm, cancel, custom1..4) plus any
---the project adds, each bound to keys, mouse buttons or gamepad input.
---
---Players: up to 4. Player 1 is the keyboard + mouse and the first
---gamepad; players 2-4 each have a gamepad (the 2nd, 3rd, 4th plugged in).
---Action queries take an optional player (default 1). Scripts get
---on_gamepad_connected(player, name) / on_gamepad_disconnected(player).
local InputModule = {}

---Checks if an action was pressed this frame (just triggered).
---
---Example: `if Input.is_action_pressed("jump") then self.vy = -self.jump_speed end`
---@param action InputAction The action's name from Project Settings > Input, e.g. "jump" (case doesn't matter; an unknown name gives false)
---@param player? integer Which player, 1-4 (default 1; out-of-range numbers are clamped)
---@return boolean true only on the frame the action went down
function InputModule.is_action_pressed(action, player) end

---Checks if an action is currently held down.
---
---Example: `if Input.is_action_down("fire", self.player) then self:shoot() end`
---@param action InputAction The action's name from Project Settings > Input, e.g. "fire" (an unknown name gives false)
---@param player? integer Which player, 1-4 (default 1)
---@return boolean true every frame the action is held
function InputModule.is_action_down(action, player) end

---Checks if an action was released this frame.
---
---Example: `if Input.is_action_released("jump") and self.vy < 0 then self.vy = self.vy * 0.5 end`
---@param action InputAction The action's name from Project Settings > Input, e.g. "jump" (an unknown name gives false)
---@param player? integer Which player, 1-4 (default 1)
---@return boolean true only on the frame the action was let go
function InputModule.is_action_released(action, player) end

---Calculates a 1D axis value between -1.0 and 1.0 from negative and positive action names.
---
---Example: `local dir = Input.get_axis("move_left", "move_right"); self.vx = dir * self.speed`
---@param neg_action InputAction The action that pushes toward -1, e.g. "move_left"
---@param pos_action InputAction The action that pushes toward +1, e.g. "move_right"
---@param player? integer Which player, 1-4 (default 1)
---@return number axis -1 to 1: the positive action's strength minus the negative one's (in between for an analog stick; 0 when both or neither are held)
function InputModule.get_axis(neg_action, pos_action, player) end

---Calculates a normalized 2D direction vector from 4 directional action inputs.
---
---Example: `local dx, dy = Input.get_vector("move_left", "move_right", "move_up", "move_down")` - or `Input.get_vector(2)`: player 2's move_* actions.
---@param left? InputAction|integer The action for -x (default "move_left"), or a player number to read that player's move_* actions
---@param right? InputAction The action for +x (default "move_right")
---@param up? InputAction The action for -y (default "move_up")
---@param down? InputAction The action for +y (default "move_down")
---@param player? integer Which player, 1-4 (default 1)
---@return number x Horizontal part, -1 to 1 (right is positive)
---@return number y Vertical part, -1 to 1 (down is positive, like screen y); the vector's length is capped at 1, so diagonals aren't faster
function InputModule.get_vector(left, right, up, down, player) end

-- key names begin (generated: lua_keys_definitions_test.odin)
---Keyboard keys (raylib names; also RETURN, ESC, SHIFT, CTRL, ALT and "0"-"9").
---@alias KeyName
---| "APOSTROPHE"
---| "COMMA"
---| "MINUS"
---| "PERIOD"
---| "SLASH"
---| "ZERO"
---| "ONE"
---| "TWO"
---| "THREE"
---| "FOUR"
---| "FIVE"
---| "SIX"
---| "SEVEN"
---| "EIGHT"
---| "NINE"
---| "SEMICOLON"
---| "EQUAL"
---| "A"
---| "B"
---| "C"
---| "D"
---| "E"
---| "F"
---| "G"
---| "H"
---| "I"
---| "J"
---| "K"
---| "L"
---| "M"
---| "N"
---| "O"
---| "P"
---| "Q"
---| "R"
---| "S"
---| "T"
---| "U"
---| "V"
---| "W"
---| "X"
---| "Y"
---| "Z"
---| "LEFT_BRACKET"
---| "BACKSLASH"
---| "RIGHT_BRACKET"
---| "GRAVE"
---| "SPACE"
---| "ESCAPE"
---| "ENTER"
---| "TAB"
---| "BACKSPACE"
---| "INSERT"
---| "DELETE"
---| "RIGHT"
---| "LEFT"
---| "DOWN"
---| "UP"
---| "PAGE_UP"
---| "PAGE_DOWN"
---| "HOME"
---| "END"
---| "CAPS_LOCK"
---| "SCROLL_LOCK"
---| "NUM_LOCK"
---| "PRINT_SCREEN"
---| "PAUSE"
---| "F1"
---| "F2"
---| "F3"
---| "F4"
---| "F5"
---| "F6"
---| "F7"
---| "F8"
---| "F9"
---| "F10"
---| "F11"
---| "F12"
---| "LEFT_SHIFT"
---| "LEFT_CONTROL"
---| "LEFT_ALT"
---| "LEFT_SUPER"
---| "RIGHT_SHIFT"
---| "RIGHT_CONTROL"
---| "RIGHT_ALT"
---| "RIGHT_SUPER"
---| "KB_MENU"
---| "KP_0"
---| "KP_1"
---| "KP_2"
---| "KP_3"
---| "KP_4"
---| "KP_5"
---| "KP_6"
---| "KP_7"
---| "KP_8"
---| "KP_9"
---| "KP_DECIMAL"
---| "KP_DIVIDE"
---| "KP_MULTIPLY"
---| "KP_SUBTRACT"
---| "KP_ADD"
---| "KP_ENTER"
---| "KP_EQUAL"
---| "BACK"
---| "MENU"
---| "VOLUME_UP"
---| "VOLUME_DOWN"
---| "RETURN"
---| "ESC"
---| "SHIFT"
---| "CTRL"
---| "ALT"
-- key names end

---Mouse buttons.
---@alias MouseButton "LEFT"|"RIGHT"|"MIDDLE"|"SIDE"|"EXTRA"|"FORWARD"|"BACK"

---Queries raw keyboard key press state for a single frame.
---
---Example: `if Input.is_key_pressed("F5") then Scene.reload() end`
---@param key KeyName|string A raylib key name like "SPACE", "W", "F5", "LEFT_ALT" (also "RETURN", "ESC", "SHIFT", "CTRL", "ALT", "0"-"9"; case doesn't matter, an unknown name gives false)
---@return boolean true only on the frame the key went down
function InputModule.is_key_pressed(key) end

---Queries raw keyboard key held state.
---
---Example: `if Input.is_key_down("LEFT_SHIFT") then speed = speed * 2 end`
---@param key KeyName|string A raylib key name like "LEFT_SHIFT" or "D" (an unknown name gives false)
---@return boolean true every frame the key is held
function InputModule.is_key_down(key) end

---Queries raw keyboard key release state for a single frame.
---
---Example: `if Input.is_key_released("SPACE") then self.charging = false end`
---@param key KeyName|string A raylib key name like "SPACE" (an unknown name gives false)
---@return boolean true only on the frame the key was let go
function InputModule.is_key_released(key) end

---Queries mouse button pressed state for a single frame. False while a UI widget has the mouse (a click on a button isn't also a shot).
---
---Example: `if Input.is_mouse_button_pressed("LEFT") then self:shoot() end`
---@param button MouseButton|string "LEFT", "RIGHT", "MIDDLE", "SIDE", "EXTRA", "FORWARD" or "BACK" (nil means "LEFT")
---@return boolean true only on the frame the button went down; false while a UI widget has the mouse
function InputModule.is_mouse_button_pressed(button) end

---Queries mouse button held state. False while a UI widget has the mouse.
---
---Example: `if Input.is_mouse_button_down("RIGHT") then self.aiming = true end`
---@param button MouseButton|string "LEFT", "RIGHT", "MIDDLE", "SIDE", "EXTRA", "FORWARD" or "BACK" (nil means "LEFT")
---@return boolean true every frame the button is held; false while a UI widget has the mouse
function InputModule.is_mouse_button_down(button) end

---Queries mouse button release state for a single frame. False while a UI widget has the mouse.
---
---Example: `if Input.is_mouse_button_released("LEFT") then self.dragging = false end`
---@param button MouseButton|string "LEFT", "RIGHT", "MIDDLE", "SIDE", "EXTRA", "FORWARD" or "BACK" (nil means "LEFT")
---@return boolean true only on the frame the button was let go; false while a UI widget has the mouse
function InputModule.is_mouse_button_released(button) end

---Gets the current mouse cursor position in screen pixels.
---
---Example: `local mx, my = Input.get_mouse_position(); local wx, wy = Camera.screen_to_world(mx, my)`
---@return number x Cursor x in game-screen px (the virtual resolution, before the camera; pass it to Camera.screen_to_world for world px)
---@return number y Cursor y in game-screen px
function InputModule.get_mouse_position() end

---Gets mouse wheel scroll delta for this frame.
---
---Example: `local wheel = Input.get_mouse_wheel_move(); Camera.set_zoom(Camera.get_zoom() + wheel * 0.1)`
---@return number This frame's wheel scroll: positive scrolls up, about 1 per notch (fractions on a trackpad), 0 when still
function InputModule.get_mouse_wheel_move() end

---@class TouchPoint
---@field id integer The finger's id (stays the same while it's down)
---@field x number Where it is, in game px (like the mouse)
---@field y number
---@field pressed boolean It went down this frame
---@field released boolean It went up this frame (then it's gone)
---@field control boolean It's on an on-screen control (a Touch Joystick or Touch Button)

---The fingers on the screen (touch screens: the web export on phones and
---tablets). By default the first free finger is also the mouse.
---
---Example: `for _, f in ipairs(Input.get_touches()) do if f.pressed then self:spark(f.x, f.y) end end`
---@return TouchPoint[] touches Every finger down, and those let go this frame
function InputModule.get_touches() end

---Where a tap was this frame (a quick touch that hardly moved).
---
---Example: `local x, y = Input.get_tap(); if x then self:jump_to(x, y) end`
---@return number? x Game px; nil when there was no tap this frame
---@return number? y
function InputModule.get_tap() end

---Where a double tap was this frame (a second tap soon after one, near it).
---
---Example: `if Input.get_double_tap() then Camera.set_zoom(1) end`
---@return number? x Game px; nil when there was none this frame
---@return number? y
function InputModule.get_double_tap() end

---Where a long press fired this frame (a finger held still for half a second).
---
---Example: `local x, y = Input.get_long_press(); if x then self:open_menu(x, y) end`
---@return number? x Game px; nil when there was none this frame
---@return number? y
function InputModule.get_long_press() end

---A swipe this frame (a quick stroke): its direction and speed.
---
---Example: `local dx, dy = Input.get_swipe(); if dx and dx > 0.7 then self:next_page() end`
---@return number? dx Direction x (unit length with dy); nil when there was no swipe
---@return number? dy Direction y
---@return number? speed px per second
function InputModule.get_swipe() end

---Two fingers this frame: how much they spread (pinch zoom) and moved
---together (two-finger drag).
---
---Example: `local s, dx, dy, on = Input.get_pinch(); if on then Camera.set_zoom(Camera.get_zoom() * s) end`
---@return number scale This frame's spread (1: none; above 1 apart, below together)
---@return number dx Their middle's move this frame (game px)
---@return number dy
---@return boolean pinching Two free fingers are down
function InputModule.get_pinch() end

---Whether the screen has been touched since the game started (on-screen
---controls show from then on).
---
---Example: `self.help.text = Input.is_touch_device() and "Tap to jump" or "Press Space to jump"`
---@return boolean touched
function InputModule.is_touch_device() end

---@class InputBindingInfo
---@field device "key"|"mouse"|"button"|"axis"
---@field name string The raw name ("SPACE", "LEFT", "RIGHT_FACE_DOWN", "LEFT_X")
---@field key? string
---@field mouse? string
---@field button? string
---@field axis? string
---@field positive? boolean Axis direction
---@field text string What to show the player ("Space", "Left Shift", "A", "Left Stick Right")

---@class InputBindingSpec
---@field key? string A keyboard key ("SPACE", "W", "LEFT_SHIFT")
---@field mouse? string A mouse button ("LEFT", "RIGHT", "MIDDLE")
---@field button? string A gamepad button ("RIGHT_FACE_DOWN" = A, "LEFT_TRIGGER_1" = LB, "MIDDLE_RIGHT" = Start)
---@field axis? string A gamepad axis ("LEFT_X", "LEFT_Y", "RIGHT_X", "RIGHT_Y")
---@field positive? boolean Axis direction (true: right / down)

---@class InputListenOptions
---@field slot? integer Which binding to replace (1-based); default: the first one of the same device kind, else a new one
---@field device? "any"|"keyboard"|"gamepad" Which inputs count (default any)
---@field conflicts? "clear"|"swap"|"allow" Another action using it loses it (clear, default), gets this one's old binding (swap), or keeps it (allow)
---@field cancel? string The key that cancels (default "ESCAPE")
---@field on_done? fun(result: "bound"|"cancelled", text: string) Called when it's bound or cancelled

---An action's bindings, each with a player-facing `text`.
---
---Example: `for i, b in ipairs(Input.get_bindings("jump")) do print(i, b.text) end`
---@param action InputAction The action's name, e.g. "jump"
---@return InputBindingInfo[] Its bindings in slot order (empty for an unknown action), each with device, name and a player-facing text
function InputModule.get_bindings(action) end

---What to show for an action's bindings: "Space / A" (or one slot's).
---
---Example: `label.text = "Jump: " .. Input.binding_text("jump")`
---@param action InputAction The action's name, e.g. "jump"
---@param slot? integer Only this binding, 1-based (default: all of them joined with " / ")
---@return string What to show the player, e.g. "Space / A"; "-" when there is nothing to show
function InputModule.binding_text(action, slot) end

---Sets one of an action's bindings (nil removes that slot); slot 0 replaces the first binding of the same device kind. Saved for the player.
---
---Example: `Input.set_binding("jump", 1, {key = "W"})`
---@param action InputAction The action's name, e.g. "jump"
---@param slot integer Which binding, 1-based (past the end adds one, up to 4); 0 replaces the first binding of the same device kind
---@param binding InputBindingSpec|nil The new input, e.g. {key = "W"} or {axis = "LEFT_X", positive = true}; nil removes the slot
---@param conflicts? "clear"|"swap"|"allow" Another action already using it: "clear" takes it away (default), "swap" gives it this slot's old binding, "allow" keeps both
---@return boolean false (nothing changes) for an unknown action, a binding it can't read, or a full action (4 bindings) with no slot for this one; the change is saved for the player
function InputModule.set_binding(action, slot, binding, conflicts) end

---Waits for the player to press the key / button / stick to bind to an action (a "press a key..." prompt). Everything must be let go first, so the button that opened the menu isn't taken. Escape cancels. The result is saved for the player.
---
---Example: `Input.listen("jump", {on_done = function(result, text) self.label.text = text end})`
---@param action InputAction The action to rebind, e.g. "jump"
---@param options? InputListenOptions slot, device ("any", "keyboard" or "gamepad"), conflicts, cancel key (default "ESCAPE") and an on_done(result, text) callback
---@return boolean false for an unknown action (nothing starts)
function InputModule.listen(action, options) end

---Whether Input.listen is waiting for a press.
---
---Example: `if Input.is_listening() then return end -- the menu ignores input meanwhile`
---@return boolean true while Input.listen is waiting for a press
function InputModule.is_listening() end

---Stops waiting (on_done gets "cancelled").
---
---Example: `Input.cancel_listen()`
function InputModule.cancel_listen() end

---Back to the project's bindings: one action, or all of them. Saved for the player.
---
---Example: `Input.reset_bindings()`
---@param action? InputAction The action to reset (default nil: every action)
function InputModule.reset_bindings(action) end

---Saves the player's bindings now (set_binding, listen and reset_bindings already do).
---
---Example: `Input.save_bindings()`
---@return boolean ok false when the file couldn't be written
function InputModule.save_bindings() end

---The actions that already use a binding.
---
---Example: `local used = Input.find_conflicts({key = "SPACE"})`
---@param binding InputBindingSpec The input to look for, e.g. {key = "SPACE"} or {button = "RIGHT_FACE_DOWN"}
---@return string[] Names of the actions bound to it (empty when none, or when the binding isn't valid)
function InputModule.find_conflicts(binding) end

---The kind of device the player used last - show keyboard or gamepad prompts.
---
---Example: `hint.text = Input.last_device() == "gamepad" and "Press A" or "Press Space"`
---@return "keyboard"|"gamepad" "gamepad" after a pad button press, else "keyboard" (also for the mouse)
function InputModule.last_device() end

---The project's actions, in the order of Project Settings > Input (for building a controls menu).
---
---Example: `for _, name in ipairs(Input.get_actions()) do print(name, Input.binding_text(name)) end`
---@return string[] The action names, in Project Settings > Input order
function InputModule.get_actions() end

---Rumbles a player's gamepad. low: the heavy (left) motor, high: the light (right) one, 0-1 each. False when the player has no gamepad. (Windows: XInput pads; Linux: pads with force feedback; macOS: controllers with haptics; the web: where the browser has it.)
---
---Example: `Input.vibrate(0.4, 0.8, 0.25, self.player)`
---@param low number Heavy (left) motor strength, 0..1
---@param high? number Light (right) motor strength, 0..1 (default: same as low)
---@param seconds? number How long, in seconds (default 0.2, at most 10; 0 stops it)
---@param player? integer Which player, 1-4 (default 1)
---@return boolean false when the player has no gamepad connected
function InputModule.vibrate(low, high, seconds, player) end

---Stops a player's rumble.
---
---Example: `Input.stop_vibration(2)`
---@param player? integer Which player, 1-4 (default 1)
function InputModule.stop_vibration(player) end

---The rumble a player's gamepad has now (0, 0: none).
---
---Example: `local low, high = Input.get_vibration()`
---@param player? integer Which player, 1-4 (default 1)
---@return number low Heavy motor strength now, 0..1 (0 when not rumbling)
---@return number high Light motor strength now, 0..1 (0 when not rumbling)
function InputModule.get_vibration(player) end

---The button prompt image for an action: its first binding on the device the player uses now (a key on the keyboard; A / Cross / B... on a pad). Use it as any image path (set_texture, UI images). nil when the action has nothing on that device.
---
---Example: `self.node:get_node("Prompt"):set_texture(Input.glyph("jump"))` - "prompts:xbox/xbox_button_a"
---@param action InputAction The action's name, e.g. "jump"
---@param player? integer Which player's device to use, 1-4 (default 1)
---@param device? "keyboard"|"xbox"|"playstation"|"switch"|"steamdeck" Force a family: "keyboard", "xbox", "playstation", "switch" or "steamdeck" (default: what the player uses now)
---@return string? An image path like "prompts:xbox/xbox_button_a" for set_texture or UI images; nil when the action has no binding on that device
function InputModule.glyph(action, player, device) end

---The device a player uses now: "keyboard" (player 1, last used the keyboard / mouse or has no pad), the gamepad's kind (from its name), or "none".
---
---Example: `if Input.device() == "playstation" then hint.text = "Press Cross" end`
---@param player? integer Which player, 1-4 (default 1)
---@return "keyboard"|"xbox"|"playstation"|"switch"|"steamdeck"|"generic"|"none" "keyboard" (player 1 on keyboard or mouse, or without a pad), the pad family ("xbox", "playstation", "switch", "steamdeck", "generic"), or "none"
function InputModule.device(player) end

---Does the player have a gamepad connected?
---
---Example: `if not Input.is_gamepad_connected(2) then label.text = "P2: connect a controller" end`
---@param player? integer Which player, 1-4 (default 1)
---@return boolean true when that player's gamepad is plugged in
function InputModule.is_gamepad_connected(player) end

---The name of a player's gamepad (nil: none).
---
---Example: `print(Input.gamepad_name(1))` - "Xbox Wireless Controller"
---@param player? integer Which player, 1-4 (default 1)
---@return string? The pad's name, e.g. "Xbox Wireless Controller"; nil when the player has none
function InputModule.gamepad_name(player) end

---The gamepad (1-4) a player has (nil: none).
---
---Example: `local pad = Input.get_player_gamepad(2)`
---@param player integer Which player, 1-4
---@return integer? The gamepad number, 1-4; nil when the player has none
function InputModule.get_player_gamepad(player) end

---Gives a player a gamepad (nil: none). A player that had it gets this player's old one, so two players never share a pad - a "press A to join" screen.
---
---Example: `for _, p in ipairs(Input.gamepads()) do if not p.player then Input.set_player_gamepad(next_free, p.pad) end end`
---@param player integer Which player, 1-4
---@param pad? integer The gamepad number, 1-4 (nil takes the player's pad away; a player who had this pad gets the old one)
function InputModule.set_player_gamepad(player, pad) end

---The connected gamepads.
---
---Example: `for _, p in ipairs(Input.gamepads()) do print(p.pad, p.name, p.device, p.player) end`
---@return {pad: integer, name: string, device: string, player: integer?}[] One entry per connected pad: pad number (1-4), name, device family, and player (nil when nobody has it)
function InputModule.gamepads() end

---How many players: player 1 plus every other player with a gamepad.
---
---Example: `for p = 2, 4 do if Input.is_gamepad_connected(p) then self:spawn_player(p) end end -- (players with a pad: count with player_count)`
---@return integer 1 plus each of players 2-4 that has a connected gamepad
function InputModule.player_count() end


---@class AudioModule
---Engine audio playback and the mixer: every sound and music plays into a bus (Master, Music, SFX and the project's own - the Mixer tab), each with a fader, pan, mute / solo and effects.
local AudioModule = {}

---Plays a sound effect from the given file path. Calls in quick succession
---overlap instead of restarting it.
---
---Example: `Audio.play_sound("sounds/jump.wav", 0.8, 1.1)`
---@param path AudioPath|string The sound file, project-relative (e.g. "audio/jump.wav"); loaded on first use, then cached
---@param volume? number 0..1 (default 1), before the bus fader
---@param pitch? number Playback speed and pitch: 1 is normal, 2 an octave up, 0.5 an octave down (default 1)
---@param bus? string The mixer bus by name, any case (default: the sound's import bus, else SFX); an unknown name plays into Master
function AudioModule.play_sound(path, volume, pitch, bus) end

---Plays a one-shot heard from a world position: quieter with distance from
---the listener (the camera, or Audio.set_listener) and panned to its side.
---
---Example: `local x, y = self.node:get_position(); Audio.play_sound_at("sounds/explosion.wav", x, y)`
---@param path AudioPath|string The sound file, project-relative; plays into its import bus, else SFX
---@param x number World X the sound comes from (px)
---@param y number World Y the sound comes from (px)
---@param volume? number 0..1 (default 1) before distance: full within 100 px of the listener, fading to silent at 900 px, panned fully at 450 px to a side
function AudioModule.play_sound_at(path, x, y, volume) end

---@alias AudioBus "master"|"music"|"sfx"|string

---Sets a mixer bus's fader (linear: 1 = 0 dB, 0.5 = -6 dB). "master", "music" and "sfx" also update the project's volumes.
---
---Example: `Audio.set_bus_volume("music", 0.5)`
---@param bus AudioBus A bus name, any case; "master", "music" and "sfx" (any case) also set the project's volumes, clamped to 0..1
---@param volume number Linear fader: 1 = 0 dB, 0.5 about -6 dB, 0 silent; clamped to 0..1 for master, music and sfx, at least 0 for other buses
function AudioModule.set_bus_volume(bus, volume) end

---Returns a bus's fader (linear).
---
---Example: `local vol = Audio.get_bus_volume("sfx"); Audio.set_bus_volume("sfx", vol * 0.5)`
---@param bus AudioBus A bus name, any case
---@return number volume The linear fader value (1 when there's no such bus)
function AudioModule.get_bus_volume(bus) end

---Mutes / unmutes a bus.
---
---Example: `Audio.set_bus_mute("Voice", true)`
---@param bus AudioBus A bus name, any case (an unknown name does nothing)
---@param mute boolean true silences the bus, false lets it through again
function AudioModule.set_bus_mute(bus, mute) end

---Solos a bus (only soloed buses - and what they feed - are heard).
---
---Example: `Audio.set_bus_solo("Music", true)`
---@param bus AudioBus A bus name, any case (an unknown name does nothing)
---@param solo boolean true solos the bus, false takes it out of solo
function AudioModule.set_bus_solo(bus, solo) end

---Pans a bus: -1 left, 0 centre, 1 right.
---
---Example: `Audio.set_bus_pan("Ambience", -0.3)`
---@param bus AudioBus A bus name, any case (an unknown name does nothing)
---@param pan number -1 left, 0 centre, 1 right (clamped to -1..1)
function AudioModule.set_bus_pan(bus, pan) end

---The mixer's buses, Master first.
---
---Example: `for _, name in ipairs(Audio.get_buses()) do print(name, Audio.get_bus_volume(name)) end`
---@return string[] Every bus name, Master first
function AudioModule.get_buses() end

---A bus's level right now (post-fader peaks, falling off smoothly) - for in-game meters or music-reactive effects.
---
---Example: `local l, r = Audio.bus_peak("Music"); self.node.scale = {1 + l * 0.2, 1 + l * 0.2}`
---@param bus AudioBus A bus name, any case
---@return number left Left level now, about 0..1 (above 1 when the bus clips; 0 for an unknown bus)
---@return number right Right level now, same scale
function AudioModule.bus_peak(bus) end

---Sets an effect parameter on a bus: the effect by type name (the first of it) or 1-based position. Types and parameters: eq (low_gain, low_freq, mid_gain, mid_freq, high_gain, high_freq), lowpass / highpass (cutoff, resonance), compressor (threshold, ratio, attack, release, makeup), limiter (ceiling, release), delay (time, feedback, mix), reverb (size, damping, mix), distortion (drive, mix, output).
---
---Example: `Audio.set_effect("Music", "lowpass", "cutoff", 600) -- muffle the music underwater`
---@param bus AudioBus A bus name, any case
---@param effect string|integer The effect's type name in lowercase ("lowpass", "reverb"; the first of that type on the bus) or its 1-based position in the bus's chain
---@param param string The parameter name, e.g. "cutoff" (lowercase, from the list above)
---@param value number The new value in the parameter's unit (Hz, dB, ms, ratio or 0..1), clamped to its range
---@return boolean true when set; false when there's no such bus, effect or parameter
function AudioModule.set_effect(bus, effect, param, value) end

---Enables or bypasses an effect on a bus.
---
---Example: `Audio.set_effect_enabled("Music", "lowpass", in_water)`
---@param bus AudioBus A bus name, any case
---@param effect string|integer The effect's lowercase type name (the first of that type) or 1-based position
---@param enabled boolean true runs the effect, false bypasses it
function AudioModule.set_effect_enabled(bus, effect, enabled) end

---A low-pass filter on the whole mix (e.g. underwater, a pause menu) - a Low-pass effect on the Master bus.
---
---Example: `Audio.set_lowpass(800)  -- muffled while the pause menu is open`
---@param hz number Cutoff in Hz (about 40..20000; lower sounds more muffled); 0 or less bypasses the filter
function AudioModule.set_lowpass(hz) end

---Reverb on the whole mix - a Reverb effect on the Master bus.
---
---Example: `Audio.set_reverb(0.4, 0.8)`
---@param mix number Wet amount 0..1 (clamped); 0 bypasses the reverb
---@param size? number Room size 0..1 (default 0.5)
function AudioModule.set_reverb(mix, size) end

---Where positional sounds are heard from (nil: the current camera).
---
---Example: `Audio.set_listener(Scene.find_node("Player"))`
---@param node Node? The node positional sounds are heard from; nil goes back to the current camera (as does destroying the node)
function AudioModule.set_listener(node) end

---Fades one MusicNode out (stopping it) while another fades in.
---
---Example: `Audio.crossfade(Scene.find_node("ExploreMusic"), Scene.find_node("BattleMusic"), 2.0)`
---@param from Node? The MusicNode to fade out and stop at the end; nil (or another node type) only fades in
---@param to Node The MusicNode to fade to full volume, started if it isn't playing
---@param seconds number Fade length in seconds
function AudioModule.crossfade(from, to, seconds) end

---Streams a music track from the given file path.
---
---Example: `Audio.play_music("music/theme.ogg", true)`
---@param path AudioPath|string The music file, project-relative (e.g. "audio/theme.ogg"); streamed from disk, restarted from the beginning if already playing
---@param loop? boolean true repeats the track, false plays it once (default true)
---@param bus? string The mixer bus by name, any case (default: the file's import bus, else Music); an unknown name plays into Master
function AudioModule.play_music(path, loop, bus) end

---Stops playing the specified music stream.
---
---Example: `Audio.stop_music("music/theme.ogg")`
---@param path AudioPath|string The same file path given to play_music
function AudioModule.stop_music(path) end

---Pauses playback of the specified music stream.
---
---Example: `Audio.pause_music("music/theme.ogg")`
---@param path AudioPath|string The same file path given to play_music
function AudioModule.pause_music(path) end

---Resumes playback of the specified paused music stream.
---
---Example: `Audio.resume_music("music/theme.ogg")`
---@param path AudioPath|string The same file path given to play_music
function AudioModule.resume_music(path) end

---Checks if the specified music stream is currently playing.
---
---Example: `if not Audio.is_music_playing("music/theme.ogg") then Audio.play_music("music/theme.ogg") end`
---@param path AudioPath|string The same file path given to play_music
---@return boolean true while the track has been started and hasn't ended or been stopped (still true while paused)
function AudioModule.is_music_playing(path) end

---Sets volume for a specific music stream.
---
---Example: `Audio.set_music_volume("music/theme.ogg", 0.6)`
---@param path AudioPath|string The same file path given to play_music
---@param volume number Linear 0..1 before the bus fader (negative counts as 0); the next play_music starts at the file's own volume again
function AudioModule.set_music_volume(path, volume) end

---Sets the global master audio volume.
---
---Example: `Audio.set_master_volume(0.75)`
---@param volume number 0 (silent) to 1 (full), clamped: the Master bus fader, same as set_bus_volume("master", volume)
function AudioModule.set_master_volume(volume) end


---@class CameraModule
---Global camera control operating on the active scene's primary CameraNode.
local CameraModule = {}

---Gets current target world position of the camera.
---
---Example: `local cx, cy = Camera.get_target_position()`
---@return number x World X the camera is moving toward (follow target plus offset while following); 0 with no current camera
---@return number y World Y the camera is moving toward; 0 with no current camera
function CameraModule.get_target_position() end

---Sets target world position for the camera.
---
---Example: `local x, y = self.node:get_position(); Camera.set_target_position(x, y)`
---@param x number World X to look at, in px (a Vec2 also works here, with y left out)
---@param y number World Y to look at, in px
function CameraModule.set_target_position(x, y) end

---Sets a node for the camera to smoothly follow (nil stops following).
---A follow target picked in the Inspector is set automatically when the scene loads.
---
---Example: `Camera.set_target(Scene.find_node("Player"))`
---@param target Node? The node to follow (Single Target mode, snapped to at once); nil stops following it
function CameraModule.set_target(target) end

---@class CameraTargetOptions
---@field weight? number Pull of this target on the framing (default 1)
---@field weight_x? number Horizontal pull (default: weight)
---@field weight_y? number Vertical pull (default: weight)
---@field radius? number Space kept around it when auto-zooming (default 50)
---@field offset_x? number
---@field offset_y? number
---@field priority? integer

---Adds a node to the group the camera frames: it centres on their weighted
---average and, with Auto Zoom on, zooms to keep them all in view. A single
---follow target joins the group first. Adding a node again updates its options.
---
---Example: `Camera.add_target(Scene.find_node("Boss"), {weight = 2, radius = 120})`
---@param target Node The node to add to the framed group; adding it again updates its options
---@param options? CameraTargetOptions weight (default 1), weight_x, weight_y, radius in px (default 50), offset_x, offset_y, priority; nil for the defaults
function CameraModule.add_target(target, options) end

---Takes a node out of the group.
---
---Example: `Camera.remove_target(Scene.find_node("Boss"))`
---@param target Node The node to take out of the group; nothing happens if it isn't in it
function CameraModule.remove_target(target) end

---Stops following: clears the group and the follow target.
---
---Example: `Camera.clear_targets()`
function CameraModule.clear_targets() end

---The node the camera follows (single target), or nil.
---
---Example: `local target = Camera.get_target(); if target then Log.info(target.name) end`
---@return Node? The single follow target, or nil when there is none or no current camera
function CameraModule.get_target() end

---Every node the camera follows (the group, or the single target).
---
---Example: `for _, node in ipairs(Camera.get_targets()) do Log.info(node.name) end`
---@return Node[] The group's live nodes (or the single target alone); an empty list with no current camera
function CameraModule.get_targets() end

---Gets configured target zoom level.
---
---Example: `local zoom = Camera.get_zoom(); Camera.set_zoom(zoom * 1.1)`
---@return number The zoom the camera is easing to (2 = everything twice as big); 1 with no current camera
function CameraModule.get_zoom() end

---Sets camera target zoom.
---
---Example: `Camera.set_zoom(2.0)`
---@param zoom number New zoom, 1 = normal, 2 = twice as big; clamped to the camera's Min Zoom and Max Zoom (default 0.1 to 10), eased when Smooth Zoom is on
function CameraModule.set_zoom(zoom) end

---Gets screen offset vector.
---
---Example: `local ox, oy = Camera.get_offset()`
---@return number ox Horizontal offset in world px; 0 with no current camera
---@return number oy Vertical offset in world px; 0 with no current camera
function CameraModule.get_offset() end

---Sets screen offset vector.
---
---Example: `Camera.set_offset(0, -40)`
---@param ox number Horizontal shift of the look point, in world px (positive looks further right); a Vec2 also works, with oy left out
---@param oy number Vertical shift of the look point, in world px (negative looks higher)
function CameraModule.set_offset(ox, oy) end

---Gets camera rotation in degrees.
---
---Example: `local deg = Camera.get_rotation(); Camera.set_rotation(deg + 90 * dt)`
---@return number The camera's rotation right now, in degrees; 0 with no current camera
function CameraModule.get_rotation() end

---Sets camera rotation in degrees.
---
---Example: `Camera.set_rotation(15)`
---@param degrees number New rotation in degrees, clockwise; eased when Smooth Rotation is on
function CameraModule.set_rotation(degrees) end

---Shakes the current camera: its Shake Preset (Custom: its Shake Types / Speed / Intensity). Strength is how far it moves, in pixels.
---
---Example: `Camera.shake(6, 0.3)`
---@param strength? number How far it moves, in px; nil uses the Shake Preset's strength
---@param duration? number How long it lasts, in seconds; nil uses the preset's (an endless preset stays endless)
function CameraModule.shake(strength, duration) end

---Immediately stops active screen shake.
---
---Example: `Camera.stop_shake()`
function CameraModule.stop_shake() end

---Checks if screen shake is active.
---
---Example: `if not Camera.is_shaking() then Camera.shake(4, 0.2) end`
---@return boolean True while a shake is playing; false with no current camera
function CameraModule.is_shaking() end

---Adds shake trauma to the active advanced camera (stacks up to 1; see AdvancedCameraNode).
---
---Example: `Camera.add_trauma(0.3)`
---@param amount number Trauma to add, 0 to 1; the total is capped at 1 and does nothing without an Advanced Camera
function CameraModule.add_trauma(amount) end

---Kicks the camera in a direction - a nudge that springs back, for recoil
---or a hit's direction (on top of the shake; the accessibility screen-shake
---setting scales it).
---
---Example: `Camera.kick(-6, 0) -- the gun's recoil when firing right`
---@overload fun(v: Vec2)
---@param dx number Pixels (the bigger, the farther it goes)
---@param dy number Pixels
function CameraModule.kick(dx, dy) end

---The advanced camera the scene's camera shows (nil if there are none).
---
---Example: `local cam = Camera.get_active()`
---@return AdvancedCameraNode? The active AdvancedCameraNode, or nil when the scene has none
function CameraModule.get_active() end

---Constrains camera movement within bounding rectangle limits.
---
---Example: `Camera.set_limits(0, 3200, 0, 1800)`
---@param left number Leftmost world X the view may show, in px
---@param right number Rightmost world X the view may show, in px
---@param top number Topmost world Y the view may show, in px
---@param bottom number Bottommost world Y the view may show, in px
function CameraModule.set_limits(left, right, top, bottom) end

---Clears all bounding rectangle limits.
---
---Example: `Camera.clear_limits()`
function CameraModule.clear_limits() end

---Transforms screen coordinates to world coordinates.
---
---Example: `local wx, wy = Camera.screen_to_world(Input.get_mouse_position())`
---@param sx number Screen X in px from the left edge (a Vec2 also works, with sy left out)
---@param sy number Screen Y in px from the top edge
---@return number wx World X under that screen point (the input unchanged with no current camera)
---@return number wy World Y under that screen point
function CameraModule.screen_to_world(sx, sy) end

---Transforms world coordinates to screen pixel coordinates.
---
---Example: `local sx, sy = Camera.world_to_screen(self.node:get_global_position())`
---@param wx number World X in px (a Vec2 also works, with wy left out)
---@param wy number World Y in px
---@return number sx Screen X in px from the left edge (the input unchanged with no current camera)
---@return number sy Screen Y in px from the top edge
function CameraModule.world_to_screen(wx, wy) end

---Gets visible world bounds rectangle currently seen by camera.
---
---Example: `local x, y, w, h = Camera.get_visible_world_bounds()`
---@return number x World X of the view's left edge
---@return number y World Y of the view's top edge
---@return number width Width of the view in world px (shrinks as zoom grows)
---@return number height Height of the view in world px
function CameraModule.get_visible_world_bounds() end


---@class PhysicsModule
---Global physics world queries, gravity, and simulation control.
local PhysicsModule = {}

---Gets world gravity vector in pixels per second squared.
---
---Example: `local gx, gy = Physics.get_gravity()`
---@return number gx Horizontal gravity in px per second squared
---@return number gy Vertical gravity in px per second squared (positive pulls down)
function PhysicsModule.get_gravity() end

---Sets world gravity vector.
---
---Example: `Physics.set_gravity(0, 980)`
---@param gx number Horizontal gravity in px per second squared (a Vec2 also works, with gy left out)
---@param gy number Vertical gravity in px per second squared; positive pulls down, 0 for none
function PhysicsModule.set_gravity(gx, gy) end

---Draws collision shapes, joints and areas while the game runs (debugging);
---the project's Show Colliders setting (physics.debug_draw) sets the start.
---
---Example: `if Input.is_key_pressed("F3") then Physics.set_debug_draw(not Physics.get_debug_draw()) end`
---@param on boolean True draws colliders, joints and areas over the game; false hides them
function PhysicsModule.set_debug_draw(on) end

---Whether colliders are drawn while the game runs.
---
---Example: `local showing = Physics.get_debug_draw()`
---@return boolean True while colliders are drawn
function PhysicsModule.get_debug_draw() end

---Checks if physics simulation is paused.
---
---Example: `if Physics.is_paused() then Physics.set_paused(false) end`
---@return boolean True while the physics simulation is paused
function PhysicsModule.is_paused() end

---Pauses or unpauses physics simulation.
---
---Example: `Physics.set_paused(true)`
---@param paused boolean True freezes bodies (scripts keep running); false resumes
function PhysicsModule.set_paused(paused) end

---Casts a ray between start and end world points against non-sensor colliders.
---
---Example: `local hit = Physics.raycast(x, y, x, y + 64); if hit and hit.node then Log.info(hit.node.name) end`
---@param startX number World X where the ray starts, in px (a Vec2 also works, with startY left out)
---@param startY number World Y where the ray starts, in px
---@param endX number World X where the ray ends, in px (a Vec2 also works, with endY left out)
---@param endY number World Y where the ray ends, in px
---@param ... CollisionLayer|string|integer|table Optional: only colliders on these layers are hit (names from Project Settings > Physics, 1-16, or a list); none hits every layer. An unknown name is an error
---@return RaycastHit? hit The closest hit: point_x, point_y, normal_x, normal_y, fraction 0 to 1 along the ray, and node; nil when nothing solid is in the way
function PhysicsModule.raycast(startX, startY, endX, endY) end

---The project's name for collision layer n (Project Settings > Physics), or "".
---
---Example: `local name = Physics.layer_name(3); Log.info("Layer 3: " .. name)`
---@param n integer Layer number, 1 to 16
---@return string name The layer's name from Project Settings, or an empty string when unnamed or out of range
function PhysicsModule.layer_name(n) end


---@class SceneModule
---Active scene queries, node discovery, switching, and dynamic instantiation.
local SceneModule = {}

---Finds any node in the active scene hierarchy by name.
---
---Example: `local player = Scene.find_node("Player"); if player then player:queue_free() end`
---@param name NodeName|string The node's exact name (case-sensitive); the first match anywhere in the scene
---@return Node? node The first node with that name, or nil when there is none
function SceneModule.find_node(name) end

---Every node in the active scene with a tag, in tree order.
---
---Example: `for _, enemy in ipairs(Scene.find_by_tag("enemy")) do enemy:queue_free() end`
---@param tag NodeTag|string The tag to look for, as set in the Inspector or with node:add_tag
---@return Node[] Every node with the tag, in tree order; an empty list when none has it
function SceneModule.find_by_tag(tag) end

---Sets the scene's ambient light (0..1): the colour where no light reaches.
---White = an unlit scene. With LightNodes, the scene is lit by them on top.
---
---Example: `Scene.set_ambient(0.2, 0.2, 0.35)`
---@param r number Red, 0 to 1
---@param g number Green, 0 to 1
---@param b number Blue, 0 to 1
---@param a? number Alpha, 0 to 1; default 1
function SceneModule.set_ambient(r, g, b, a) end

---Gets the scene's ambient light (0..1).
---
---Example: `local r, g, b, a = Scene.get_ambient()`
---@return number r Red, 0 to 1 (1 when the scene sets no ambient)
---@return number g Green, 0 to 1
---@return number b Blue, 0 to 1
---@return number a Alpha, 0 to 1
function SceneModule.get_ambient() end

---Gets the name of the currently active scene.
---
---Example: `Log.info("Entered scene: " .. Scene.get_name())`
---@return string The active scene's name, or an empty string when no scene is loaded
function SceneModule.get_name() end

---@alias TransitionKind "fade"|"wipe_left"|"wipe_right"|"wipe_up"|"wipe_down"|"circle"|"crossfade"|"dissolve"|"pixelate"|"slide_left"|"slide_right"|"slide_up"|"slide_down"|"push_left"|"push_right"|"push_up"|"push_down"

---@class SceneTransition
---@field transition? TransitionKind|string A built-in transition, a name given to Scene.register_transition, or a shader file ("shaders/swirl.fs"); default "fade" (or the project's default)
---@field duration? number Seconds - each half of a cover transition (fade, wipe_*, circle: covering, uncovering), the whole of the others; default 0.4
---@field easing? EaseName The curve (default "in_out_sine")
---@field color? number[]|string {r, g, b[, a]} 0..1 or "#rrggbb": the cover's colour (dissolve: its burning rim); default black
---@field transition_in? TransitionKind The uncover half of a cover transition (default: as covering)
---@field duration_in? number Seconds of the uncover half (default: `duration`)
---@field easing_in? EaseName The uncover half's curve (default: `easing`)
---@field pause? boolean Pause the game (Engine.set_paused) while it runs - scripts and physics wait; "always" nodes still run
---@field loading? SceneName|ScenePath A loading screen scene shown while the scene loads in the background
---@field min_time? number Seconds the loading screen stays at least (default 0.5)

---Switches to another scene by name (or its file, e.g. a `scene` property) -
---at once (or with the project's default transition), or behind a
---transition. Cover transitions (fade, wipe_*, circle) cover the screen,
---switch once the new scene's assets are loaded, then uncover; the others
---(crossfade, dissolve, pixelate, slide_*, push_*, shaders) show the old
---scene's last frame with the new scene. Events on the global bus:
---`transition_started`, `transition_midpoint`, `transition_finished` (the
---scene's name). A change asked for during a transition waits for it.
---
---With `loading`, it goes through a loading screen: a transition into that
---scene, the target loading in the background (textures decoded on worker
---threads), then a transition into the target once it's loaded.
---
---Example: `Scene.change_scene("level_2", {transition = "slide_left", duration = 0.6, easing = "out_cubic"})`
---@param name SceneName|ScenePath The scene's name, or its file ("scenes/level_2.scene.json"); an unknown one logs an error and nothing happens
---@param transition? SceneTransition How to switch: transition, duration, easing, color, pause, loading and more; nil uses the project's default transition, or switches at once
function SceneModule.change_scene(name, transition) end

---Names a shader transition: a fragment shader whose `texture0` is the old
---scene's last frame and `new_scene` the new scene, with `progress` (0 old ..
---1 new), `resolution` and `transition_color` uniforms. Then
---`Scene.change_scene(name, {transition = "<name>"})`.
---
---Example: `Scene.register_transition("swirl", "shaders/swirl.fs")`
---@param name string The name to use as transition in Scene.change_scene
---@param shader string A project fragment shader file ("shaders/swirl.fs") or "builtin:<name>"
function SceneModule.register_transition(name, shader) end

---Starts loading a scene's assets in the background (a little each frame),
---so switching to it later is quick.
---
---Example: `Scene.preload("level_2")`
---@param name SceneName The scene's name, or its file ("scenes/level_2.scene.json") as for change_scene; an unknown one reports an error and does nothing
function SceneModule.preload(name) end

---Returns how far a scene started with Scene.preload has loaded, from 0 to 1.
---
---Example: `local p = Scene.preload_progress("level_2"); Log.info("Loading: " .. math.floor(p * 100) .. "%")`
---@param name SceneName The scene's name or file, as passed to Scene.preload
---@return number How much has loaded, 0 to 1; 0 for an unknown scene
function SceneModule.preload_progress(name) end

---Returns whether a scene transition is currently in progress.
---
---Example: `if Scene.is_transitioning() then return end`
---@return boolean True while a scene transition is running
function SceneModule.is_transitioning() end

---How far the scene behind the loading screen has loaded, 0 to 1 (1 when nothing is loading) - for a loading screen's progress bar.
---
---Example: `self.node:get_node("Bar").value = Scene.loading_progress() * 100`
---@return number How much of the target scene has loaded, 0 to 1; 1 when nothing is loading
function SceneModule.loading_progress() end

---The name of the scene the loading screen is loading, or nil.
---
---Example: `local next = Scene.loading_target()`
---@return string? The name of the scene the loading screen is loading, or nil when no loading screen is up
function SceneModule.loading_target() end

---Reloads the currently active scene (with the project's default transition, if it has one).
---
---Example: `if Input.is_key_pressed("R") then Scene.reload() end`
function SceneModule.reload() end

---Returns an array of all active nodes in the current scene.
---
---Example: `Log.info("Node count: " .. #Scene.get_nodes())`
---@return Node[] Every node in the active scene; an empty list with no scene
function SceneModule.get_nodes() end

---Dynamically instantiates a new scene node and adds it to the active scene graph.
---
---Example: `local timer = Scene.create_node("TimerNode", "Cooldown", self.node)`
---@param nodeType string A node type or Add Node search name ("TimerNode", "timer", "sprite"); default "Node"; an unknown type makes a plain Node and logs a warning
---@param name? string The new node's name; nil leaves the default
---@param parent? Node The node to add it under; nil adds it under the scene's root
---@return Node? node The new node, or nil when there is no active scene
function SceneModule.create_node(nodeType, name, parent) end

---Instances a component at runtime - `Scene.instantiate("components/Bullet.component.json", self.node:get_parent(), self.node.position, { speed = 300 })`.
---Added under `parent` (else the scene's root), at x, y local to it (two
---numbers or a Vec2). An optional table of property values is applied to the root's script before ready() runs. Returns its root node (typed per component), or nil.
---
---Example: `local b = Scene.instantiate("components/Bullet.component.json", self.node:get_parent(), self.node.position, { speed = 300 })`
---@param component ComponentPath|string The component file, e.g. "components/Bullet.component.json"
---@param parent? Node The node to add it under; nil adds it under the scene's root
---@param x? number|Vec2|table<string, any> X position local to the parent, in px; or a Vec2 position; or the properties table when no position is given
---@param y? number|table<string, any> Y position local to the parent, in px; or the properties table when x is a Vec2
---@param properties? table<string, any> Values for the root's script properties, set before its ready() runs
---@return Node? The component's root node, or nil (with a warning) when the file isn't a component
function SceneModule.instantiate(component, parent, x, y, properties) end

---Creates a node of a built-in type ("TimerNode") or one of the project's custom
---node types ("Hurtbox": its base type, script and default values), under
---`parent` (else the scene's root), at x, y local to it (two numbers or a Vec2). nil for an unknown type.
---
---Example: `local hurt = Scene.create("Hurtbox", self.node, 0, -8)`
---@param typeName string A built-in node type ("TimerNode") or one of the project's custom node types ("Hurtbox")
---@param parent? Node The node to add it under; nil adds it under the scene's root
---@param x? number|Vec2 X position local to the parent, in px; or a Vec2 position; nil keeps the type's default
---@param y? number Y position local to the parent, in px
---@return Node? The new node, or nil (with a warning) for an unknown type
function SceneModule.create(typeName, parent, x, y) end

---The current scene's nodes of a type - a custom node type ("Hurtbox"), a
---built-in one ("AreaNode") or "Node" - in tree order (`node:is`).
---
---Example: `for _, h in ipairs(Scene.find_nodes_of_type("Hurtbox")) do h:get_script():heal(1) end`
---@param typeName string A custom node type ("Hurtbox"), a built-in type ("AreaNode"), or "Node" for every node
---@return Node[] The matching nodes in tree order; an empty list when none match
function SceneModule.find_nodes_of_type(typeName) end

---Checks if debug collider and bounds rendering is enabled on this scene.
---
---Example: `local on = Scene.get_draw_bounds(); Scene.set_draw_bounds(not on)`
---@return boolean True while the scene draws debug colliders and bounds; false with no scene
function SceneModule.get_draw_bounds() end

---Enables or disables debug bounds rendering on the scene.
---
---Example: `Scene.set_draw_bounds(true)`
---@param draw boolean True draws debug colliders and bounds; false hides them
function SceneModule.set_draw_bounds(draw) end


---@class LogModule
---Engine logging subsystem routed to Odin's logging channels.
local LogModule = {}

---Logs an informational message.
---
---Example: `Log.info("player spawned at", x, y)`
---@param ... any Values to print, any type (each turned to text like tostring, joined by tabs)
function LogModule.info(...) end

---Logs a warning message.
---
---Example: `Log.warn("missing texture:", "textures/coin.png")`
---@param ... any Values to print as a warning, any type (joined by tabs)
function LogModule.warn(...) end

---Logs an error message.
---
---Example: `Log.error("could not load level", "level_2")`
---@param ... any Values to print as an error, any type (joined by tabs); the script keeps running
function LogModule.error(...) end


-- Global Instances available in every script
---@type EngineModule
Engine = EngineModule

---@type InputModule
Input = InputModule

---@type AudioModule
Audio = AudioModule

---@type CameraModule
Camera = CameraModule

---@type PhysicsModule
Physics = PhysicsModule

---Sampling curve script properties ({ type = "curve" }: points {t, v}).
---@class CurveModule
CurveModule = {}

---The curve's value at t (linear between points; clamped at the ends).
---
---Example: `local speed = self.max_speed * Curve.sample(self.speed_curve, self.elapsed / 2.0)`
---@param points number[][] A curve property's value: {t, v} points sorted by t; an empty list samples as 0
---@param t number Where to sample, usually 0..1; before the first point or past the last the end value holds
---@return number The value at t, linear between the points around it
function CurveModule.sample(points, t) end

---Sampling gradient script properties ({ type = "gradient" }: stops {t, r, g, b, a}).
---@class GradientModule
GradientModule = {}

---The gradient's colour at t (linear between stops), 0..1 channels.
---
---Example: `local r, g, b, a = Gradient.sample(self.tint, self.health / self.max_health)`
---@param stops number[][] A gradient property's value: {t, r, g, b, a} stops sorted by t (alpha default 1); an empty list gives white
---@param t number Where to sample, usually 0..1; before the first stop or past the last the end colour holds
---@return number r Red 0..1
---@return number g Green 0..1
---@return number b Blue 0..1
---@return number a Alpha 0..1
function GradientModule.sample(stops, t) end


-- ----------------------------------------------------------------------------
-- Vectors: Vec2 / Vec3 / Vec4 (vector properties come back as Vec2; setters
-- taking x, y also take a vector). v[1] / v[2] work too.
-- ----------------------------------------------------------------------------

---A 2D vector: v.x, v.y (also v[1]...); + - * / with a vector or a number.
---@class Vec2
---@field x number
---@field y number
---@operator add(Vec2|number): Vec2
---@operator sub(Vec2|number): Vec2
---@operator mul(Vec2|number): Vec2
---@operator div(Vec2|number): Vec2
---@operator unm: Vec2
local Vec2_ = {}
---Returns the vector's length (magnitude).
---
---Example: `local speed = self.velocity:length()`
---@return number The length: sqrt of the sum of the squared components
function Vec2_:length() end
---Returns the squared length, cheaper than length() for comparisons.
---
---Example: `if (target - pos):length_squared() < 16 * 16 then self.arrived = true end`
---@return number The length squared (no square root): compare it with a squared distance
function Vec2_:length_squared() end
---A vector of length 1 in the same direction (zero stays zero).
---
---Example: `local dir = (target - pos):normalized()`
---@return Vec2 A new Vec2 of length 1 pointing the same way; a zero vector stays zero
function Vec2_:normalized() end
---Returns the dot product with another vector.
---
---Example: `local facing = forward:dot((target - pos):normalized())`
---@param other Vec2 The Vec2 to multiply with, component by component
---@return number The sum of the components' products: 0 for perpendicular directions
function Vec2_:dot(other) end
---Returns the distance to another vector.
---
---Example: `local d = pos:distance(target)`
---@param other Vec2 The other point, as a Vec2
---@return number The straight-line distance between the two points (same units as the components)
function Vec2_:distance(other) end
---Returns the vector interpolated toward other by t (0 = this, 1 = other).
---
---Example: `local mid = a:lerp(b, 0.5)`
---@param other Vec2 The Vec2 to move toward
---@param t number 0 = this vector, 1 = other, 0.5 halfway; not clamped, so values outside 0..1 extrapolate
---@return Vec2 A new Vec2 between the two
function Vec2_:lerp(other, t) end
---Returns a new vector with the same components.
---
---Example: `local start = pos:copy()`
---@return Vec2 A new Vec2 with the same components; changing one doesn't change the other
function Vec2_:copy() end
---The components as values: `local x, y = v:unpack()`.
---
---Example: `local x, y = Vec2(3, 4):unpack()`
---@return number The components in order (x, y) as separate values
function Vec2_:unpack() end

---A 3D vector: v.x, v.y, v.z (also v[1]...); + - * / with a vector or a number.
---@class Vec3
---@field x number
---@field y number
---@field z number
---@operator add(Vec3|number): Vec3
---@operator sub(Vec3|number): Vec3
---@operator mul(Vec3|number): Vec3
---@operator div(Vec3|number): Vec3
---@operator unm: Vec3
local Vec3_ = {}
---Returns the vector's length (magnitude).
---
---Example: `local len = Vec3(1, 2, 2):length()`
---@return number The length: sqrt of the sum of the squared components
function Vec3_:length() end
---Returns the squared length, cheaper than length() for comparisons.
---
---Example: `local len2 = Vec3(1, 2, 3):length_squared()`
---@return number The length squared (no square root): compare it with a squared distance
function Vec3_:length_squared() end
---A vector of length 1 in the same direction (zero stays zero).
---
---Example: `local axis = Vec3(1, 2, 3):normalized()`
---@return Vec3 A new Vec3 of length 1 pointing the same way; a zero vector stays zero
function Vec3_:normalized() end
---Returns the dot product with another vector.
---
---Example: `local d = Vec3(1, 0, 0):dot(Vec3(0, 1, 0))`
---@param other Vec3 The Vec3 to multiply with, component by component
---@return number The sum of the components' products: 0 for perpendicular directions
function Vec3_:dot(other) end
---Returns the distance to another vector.
---
---Example: `local d = Vec3(0, 0, 0):distance(Vec3(1, 2, 2))`
---@param other Vec3 The other point, as a Vec3
---@return number The straight-line distance between the two points (same units as the components)
function Vec3_:distance(other) end
---Returns the vector interpolated toward other by t (0 = this, 1 = other).
---
---Example: `local mid = Vec3(0, 0, 0):lerp(Vec3(10, 20, 30), 0.5)`
---@param other Vec3 The Vec3 to move toward
---@param t number 0 = this vector, 1 = other, 0.5 halfway; not clamped, so values outside 0..1 extrapolate
---@return Vec3 A new Vec3 between the two
function Vec3_:lerp(other, t) end
---Returns a new vector with the same components.
---
---Example: `local backup = Vec3(1, 2, 3):copy()`
---@return Vec3 A new Vec3 with the same components; changing one doesn't change the other
function Vec3_:copy() end
---The components as values: `local x, y = v:unpack()`.
---
---Example: `local x, y, z = Vec3(1, 2, 3):unpack()`
---@return number The components in order (x, y, z) as separate values
function Vec3_:unpack() end

---A 4D vector: v.x, v.y, v.z, v.w (also v[1]...); + - * / with a vector or a number.
---@class Vec4
---@field x number
---@field y number
---@field z number
---@field w number
---@operator add(Vec4|number): Vec4
---@operator sub(Vec4|number): Vec4
---@operator mul(Vec4|number): Vec4
---@operator div(Vec4|number): Vec4
---@operator unm: Vec4
local Vec4_ = {}
---Returns the vector's length (magnitude).
---
---Example: `local len = Vec4(1, 1, 1, 1):length()`
---@return number The length: sqrt of the sum of the squared components
function Vec4_:length() end
---Returns the squared length, cheaper than length() for comparisons.
---
---Example: `local len2 = Vec4(1, 2, 3, 4):length_squared()`
---@return number The length squared (no square root): compare it with a squared distance
function Vec4_:length_squared() end
---A vector of length 1 in the same direction (zero stays zero).
---
---Example: `local q = Vec4(0, 0, 1, 1):normalized()`
---@return Vec4 A new Vec4 of length 1 pointing the same way; a zero vector stays zero
function Vec4_:normalized() end
---Returns the dot product with another vector.
---
---Example: `local d = Vec4(1, 0, 0, 0):dot(Vec4(0.5, 0.5, 0, 0))`
---@param other Vec4 The Vec4 to multiply with, component by component
---@return number The sum of the components' products: 0 for perpendicular directions
function Vec4_:dot(other) end
---Returns the distance to another vector.
---
---Example: `local d = Vec4(1, 0, 0, 1):distance(Vec4(0, 1, 0, 1))`
---@param other Vec4 The other point, as a Vec4
---@return number The straight-line distance between the two points (same units as the components)
function Vec4_:distance(other) end
---Returns the vector interpolated toward other by t (0 = this, 1 = other).
---
---Example: `local c = Vec4(1, 0, 0, 1):lerp(Vec4(0, 0, 1, 1), t)`
---@param other Vec4 The Vec4 to move toward
---@param t number 0 = this vector, 1 = other, 0.5 halfway; not clamped, so values outside 0..1 extrapolate
---@return Vec4 A new Vec4 between the two
function Vec4_:lerp(other, t) end
---Returns a new vector with the same components.
---
---Example: `local backup = Vec4(1, 2, 3, 4):copy()`
---@return Vec4 A new Vec4 with the same components; changing one doesn't change the other
function Vec4_:copy() end
---The components as values: `local x, y = v:unpack()`.
---
---Example: `local x, y, z, w = Vec4(1, 0, 0, 1):unpack()`
---@return number The components in order (x, y, z, w) as separate values
function Vec4_:unpack() end

---The angle of the vector in degrees (0 = right, 90 = down).
---
---Example: `local deg = (target - pos):angle(); self.node:set_rotation(deg)`
---@return number Degrees from the +x axis, -180 to 180: 0 = right, 90 = down, -90 = up
function Vec2_:angle() end
---The vector rotated by degrees (clockwise on screen).
---
---Example: `local spread = Vec2.RIGHT:rotated(15) * 300`
---@param degrees number How far to turn it; positive is clockwise on screen (+y down)
---@return Vec2 A new Vec2 of the same length, turned
function Vec2_:rotated(degrees) end

---Makes a Vec2: `Vec2(3, 4)`; constants Vec2.ZERO, ONE, UP, DOWN, LEFT, RIGHT.
---@class Vec2Constructor
---@overload fun(x?: number, y?: number): Vec2
---@field ZERO Vec2
---@field ONE Vec2
---@field UP Vec2
---@field DOWN Vec2
---@field LEFT Vec2
---@field RIGHT Vec2
---@field new fun(x?: number, y?: number): Vec2

---Makes a Vec3: `Vec3(1, 2, 3)`.
---@class Vec3Constructor
---@overload fun(x?: number, y?: number, z?: number): Vec3
---@field new fun(x?: number, y?: number, z?: number): Vec3

---Makes a Vec4: `Vec4(1, 2, 3, 4)`.
---@class Vec4Constructor
---@overload fun(x?: number, y?: number, z?: number, w?: number): Vec4
---@field new fun(x?: number, y?: number, z?: number, w?: number): Vec4

---@type Vec2Constructor
Vec2 = {}
---@type Vec3Constructor
Vec3 = {}
---@type Vec4Constructor
Vec4 = {}

---@type CurveModule
Curve = CurveModule

---@type GradientModule
Gradient = GradientModule

---@type SceneModule
Scene = SceneModule
Tween = TweenModule

---@type PoolModule
Pool = PoolModule

---@type EventsModule
Events = EventsModule

---@type LevelGenModule
LevelGen = LevelGenModule

---@type AccessibilityModule
Accessibility = AccessibilityModule

---@type SubtitlesModule
Subtitles = SubtitlesModule

---@type SaveModule
Save = SaveModule

---@type ResourceModule
Resource = ResourceModule

---@type CrashModule
Crash = CrashModule

---@class NavigationModule
local NavigationModule = {}

---Same as map:nav_find_path(x1, y1, x2, y2, opts).
---
---Example: `local path = Navigation.find_path(Scene.find_node("Level"), x, y, tx, ty, {smooth = false})`
---@param map Node The TileMapNode, LdtkLevelNode or NavigationRegionNode whose grid to path on
---@param x1 number Start world X, in px
---@param y1 number Start world Y, in px
---@param x2 number Goal world X, in px
---@param y2 number Goal world Y, in px
---@param opts? NavOptions diagonal (default true), smooth (default true), radius in px (default 0), walkable_painted (TileMap only); nil for the defaults
---@return number[][]? path Waypoints as {x, y} world points from the start to the goal (or the nearest spot that fits the radius); nil when unreachable, the start or goal is blocked, or map has no grid
function NavigationModule.find_path(map, x1, y1, x2, y2, opts) end

---@type NavigationModule
Navigation = NavigationModule

---The text for a key in the current language (locale/*.csv), with {name}
---placeholders filled from `args`; falls back to another language, then the key.
---
---Example: `self.node:set_text(tr("greeting", {name = player_name}))`
---@param key LocaleKey|string
---@param args? table<string, any>
---@return string
function tr(key, args) end

---@class LocaleModule
local LocaleModule = {}

---Switches the language texts are shown in (a column of the locale tables).
---
---Example: `Locale.set("fr")`
---@param language Language|string A language column of the locale tables, e.g. "fr"; one the tables lack changes nothing (and logs a warning)
---@return boolean ok true when switched; false for a language the tables lack
function LocaleModule.set(language) end

---Returns the current language.
---
---Example: `if Locale.get() == "fr" then self.flag = "textures/flag_fr.png" end`
---@return string language The current language, e.g. "en"; the tables' first language when none was set, "" when there are no tables
function LocaleModule.get() end

---Returns the languages available in the project's locale tables.
---
---Example: `for _, lang in ipairs(Locale.languages()) do Log.info(lang) end`
---@return string[] languages The language columns of the project's locale/*.csv files, in header order (empty when there are none)
function LocaleModule.languages() end

---@type LocaleModule
Locale = LocaleModule

---@type LogModule
Log = LogModule


---@class ProjectModule
---Engine project management, data-driven scene serialization, and .rayzr package access.
local ProjectModule = {}

---Loads a complete project either from a directory containing project.json or from a .rayzr package archive.
---
---Example: `local ok = Project.load("assets/demo_project.rayzr")`
---@param pathOrDir string A folder holding project.json, or a .rayzr package file; relative to the working directory or absolute
---@return boolean success true when the project loaded; false when the path, the package or its project.json is missing or invalid
function ProjectModule.load(pathOrDir) end

---Packages a loose project directory into a portable .rayzr container archive with zlib compression.
---
---Example: `local ok = Project.export_rayzr("assets/demo_project", "bin/demo_project.rayzr")`
---@param projectDir string The project folder to pack (the one holding project.json), relative to the working directory or absolute
---@param outRayzrPath string Where to write the .rayzr file
---@return boolean success true when the package was written
function ProjectModule.export_rayzr(projectDir, outRayzrPath) end

---The old name of export_rayzr (before the engine was renamed from Ore).
---
---Example: `Project.export_ore("assets/demo_project", "bin/demo_project.rayzr")`
---@deprecated Use Project.export_rayzr
---@param projectDir string The project folder to pack, as for export_rayzr
---@param outRayzrPath string Where to write the .rayzr file
---@return boolean success true when the package was written
function ProjectModule.export_ore(projectDir, outRayzrPath) end

---Serializes the currently active scene graph and node states to a JSON formatted string.
---
---Example: `local json = Project.serialize_scene(); Log.info(#json, "bytes")`
---@return string json The current scene as JSON text (the scene file format); "{}" when no scene is loaded
function ProjectModule.serialize_scene() end

---Reads a text file either from the mounted .rayzr archive package or the loose project directory.
---
---Example: `local credits = Project.read_file("data/credits.txt"); if credits then label:set_text(credits) end`
---@param relPath string Project-relative path, e.g. "data/items.json" (the package first, then the project folder)
---@return string? content The file's text, or nil when it isn't found
function ProjectModule.read_file(relPath) end

---Checks if a file exists in the active project (.rayzr archive or disk).
---
---Example: `if Project.has_file("levels/level_2.json") then Scene.change_scene("level_2") end`
---@param relPath string Project-relative path, e.g. "levels/level_2.json"
---@return boolean exists true when the file is in the package (when running from one) or in the project folder
function ProjectModule.has_file(relPath) end

---@type ProjectModule
Project = ProjectModule

---A gradient made by Vector.linear_gradient / Vector.radial_gradient (pass it to fill_paint / stroke_paint).
---@class VectorPaint
---@field kind "linear"|"radial"
---@field stops {[1]: number, [2]: string|number[]}[] Offsets 0..1 and colours
---@field spread? "pad"|"reflect"|"repeat"

---Draws vector shapes from a script's on_draw() in the node's local space: crisp at any zoom, anti-aliased, cached while the drawing stays the same (engine/docs/vector.md). Colours: "#rrggbb[aa]", {r, g, b[, a]} 0..1, or r, g, b[, a].
---@class VectorModule
local VectorModule = {}

---Starts a new path (forgets the current one; fill / stroke keep what they drew).
---
---Example: `Vector.begin_path(); Vector.circle(0, 0, 10); Vector.fill()`
function VectorModule.begin_path() end

---Starts a subpath at a point.
---
---Example: `Vector.move_to(0, 0); Vector.line_to(100, 0); Vector.stroke()`
---@param x number Start x in px (local space)
---@param y number Start y in px (+y is down)
function VectorModule.move_to(x, y) end

---A straight line from the current point.
---
---Example: `Vector.move_to(0, 0); Vector.line_to(50, 80); Vector.stroke()`
---@param x number End x in px
---@param y number End y in px
function VectorModule.line_to(x, y) end

---A quadratic Bezier curve (one control point) from the current point.
---
---Example: `Vector.move_to(0, 0); Vector.quad_to(50, -60, 100, 0); Vector.stroke()`
---@param cx number Control point x in px
---@param cy number Control point y in px
---@param x number End x in px
---@param y number End y in px
function VectorModule.quad_to(cx, cy, x, y) end

---A cubic Bezier curve (two control points) from the current point.
---
---Example: `Vector.move_to(0, 0); Vector.cubic_to(30, -50, 70, 50, 100, 0); Vector.stroke()`
---@param c1x number First control point x in px (pulls the start)
---@param c1y number First control point y in px
---@param c2x number Second control point x in px (pulls the end)
---@param c2y number Second control point y in px
---@param x number End x in px
---@param y number End y in px
function VectorModule.cubic_to(c1x, c1y, c2x, c2y, x, y) end

---A circular arc around (cx, cy) from angle a0 to a1 in degrees (clockwise on screen; ccw = true for the other way), joined to the current point by a line.
---
---Example: `Vector.begin_path(); Vector.move_to(0, 0); Vector.arc(0, 0, 40, -30, 30); Vector.close_path(); Vector.fill()`
---@param cx number Centre x in px
---@param cy number Centre y in px
---@param r number Radius in px
---@param a0 number Start angle in degrees (0 points right)
---@param a1 number End angle in degrees
---@param ccw? boolean true to sweep counter-clockwise on screen; default false (clockwise)
function VectorModule.arc(cx, cy, r, a0, a1, ccw) end

---Closes the current subpath (a line back to its start; joins instead of caps).
---
---Example: `Vector.move_to(0, 0); Vector.line_to(40, 0); Vector.line_to(20, 30); Vector.close_path(); Vector.fill()`
function VectorModule.close_path() end

---Adds a rectangle subpath.
---
---Example: `Vector.fill_color("#3366ff"); Vector.rect(-50, -25, 100, 50); Vector.fill()`
---@param x number Left edge in px
---@param y number Top edge in px
---@param w number Width in px
---@param h number Height in px
function VectorModule.rect(x, y, w, h) end

---Adds a circle subpath.
---
---Example: `Vector.fill_color(1, 0.8, 0); Vector.circle(0, 0, 30); Vector.fill()`
---@param x number Centre x in px
---@param y number Centre y in px
---@param r number Radius in px
function VectorModule.circle(x, y, r) end

---Adds an ellipse subpath.
---
---Example: `Vector.ellipse(0, 0, 60, 30); Vector.stroke()`
---@param x number Centre x in px
---@param y number Centre y in px
---@param rx number Horizontal radius in px
---@param ry number Vertical radius in px
function VectorModule.ellipse(x, y, rx, ry) end

---Fills the current path with the fill colour or paint (the fill rule decides holes).
---
---Example: `Vector.circle(0, 0, 20); Vector.fill()`
function VectorModule.fill() end

---Outlines the current path with the stroke colour or paint, width, joins, caps and dash.
---
---Example: `Vector.stroke_width(4); Vector.circle(0, 0, 20); Vector.stroke()`
function VectorModule.stroke() end

---Makes the current path (by the fill rule) the clip: what is drawn next only shows inside it, until restore() (a clip inside a clip replaces it).
---
---Example: `Vector.save(); Vector.circle(0, 0, 40); Vector.clip(); Vector.begin_path(); Vector.rect(-60, -10, 120, 20); Vector.fill(); Vector.restore()`
function VectorModule.clip() end

---Sets the fill colour (and drops a fill paint).
---
---Example: `Vector.fill_color("#ff8800")`
---@param color string|number[]|number "#rrggbb[aa]", a list {r, g, b[, a]} (0..1), or the red channel 0..1 when g and b follow; anything else is opaque black (default white)
---@param g? number Green 0..1 when color is a number
---@param b? number Blue 0..1 when color is a number
---@param a? number Alpha 0..1 when color is a number; default 1
function VectorModule.fill_color(color, g, b, a) end

---Sets the stroke colour (and drops a stroke paint).
---
---Example: `Vector.stroke_color(0, 0, 0, 0.5)`
---@param color string|number[]|number "#rrggbb[aa]", a list {r, g, b[, a]} (0..1), or the red channel 0..1 when g and b follow; anything else is opaque black (default black)
---@param g? number Green 0..1 when color is a number
---@param b? number Blue 0..1 when color is a number
---@param a? number Alpha 0..1 when color is a number; default 1
function VectorModule.stroke_color(color, g, b, a) end

---Fills with a gradient (in the coordinates in effect when fill() is called).
---
---Example: `Vector.fill_paint(Vector.linear_gradient(0, -50, 0, 50, { {0, "#3060c0"}, {1, "#ffd080"} }))`
---@param paint VectorPaint A gradient from Vector.linear_gradient or Vector.radial_gradient; a table without stops is ignored
function VectorModule.fill_paint(paint) end

---Strokes with a gradient.
---
---Example: `Vector.stroke_paint(Vector.radial_gradient(0, 0, 40, { {0, "#ffffff"}, {1, "#0040ff"} }))`
---@param paint VectorPaint A gradient from Vector.linear_gradient or Vector.radial_gradient; a table without stops is ignored
function VectorModule.stroke_paint(paint) end

---A linear gradient from (x0, y0) to (x1, y1): stops are {offset 0..1, colour}; spread "pad" (default), "reflect" or "repeat".
---
---Example: `local sky = Vector.linear_gradient(0, -100, 0, 0, { {0, "#203c90"}, {1, "#f08050"} })`
---@param x0 number Start x in px (offset 0)
---@param y0 number Start y in px
---@param x1 number End x in px (offset 1)
---@param y1 number End y in px
---@param stops {[1]: number, [2]: string|number[]}[] List of {offset, colour} pairs: offset 0..1, colour as in fill_color (up to 16 stops)
---@param spread? "pad"|"reflect"|"repeat" Past the ends: "pad" (default) holds the end colours, "reflect" mirrors, "repeat" starts over
---@return VectorPaint A paint for fill_paint or stroke_paint
function VectorModule.linear_gradient(x0, y0, x1, y1, stops, spread) end

---A radial gradient around (cx, cy) with radius r.
---
---Example: `local orb = Vector.radial_gradient(0, 0, 40, { {0, "#ffffff"}, {0.4, "#78c8ff"}, {1, "#0a2878"} })`
---@param cx number Centre x in px (offset 0)
---@param cy number Centre y in px
---@param r number Radius in px (offset 1)
---@param stops {[1]: number, [2]: string|number[]}[] List of {offset, colour} pairs: offset 0..1, colour as in fill_color (up to 16 stops)
---@param spread? "pad"|"reflect"|"repeat" Past the ends: "pad" (default) holds the end colours, "reflect" mirrors, "repeat" starts over
---@return VectorPaint A paint for fill_paint or stroke_paint
function VectorModule.radial_gradient(cx, cy, r, stops, spread) end

---Sets the stroke width (scaled by the current transform).
---
---Example: `Vector.stroke_width(6)`
---@param w number Width in px, default 1 (negative counts as 0)
function VectorModule.stroke_width(w) end

---How stroke corners join: "miter" (default), "round" or "bevel".
---
---Example: `Vector.line_join("round")`
---@param join "miter"|"round"|"bevel" "miter" (default), "round" or "bevel"; anything else is miter
function VectorModule.line_join(join) end

---How open strokes end: "butt" (default), "round" or "square".
---
---Example: `Vector.line_cap("round")`
---@param cap "butt"|"round"|"square" "butt" (default), "round" or "square"; anything else is butt
function VectorModule.line_cap(cap) end

---How far a miter corner may reach (in half widths) before it is beveled (default 4).
---
---Example: `Vector.miter_limit(10)`
---@param limit number How far a miter may reach, in half stroke widths; default 4, at least 1
function VectorModule.miter_limit(limit) end

---A dash pattern (on, off, ... lengths; an odd list repeats) and its offset; an empty table = solid.
---
---Example: `Vector.dash({12, 6}); Vector.circle(0, 0, 40); Vector.stroke()`
---@param pattern number[] On, off, ... lengths in px (up to 8; an odd list repeats); {} for a solid line
---@param offset? number How far into the pattern the stroke starts, in px; default 0
function VectorModule.dash(pattern, offset) end

---The fill rule: "nonzero" (default) or "evenodd" (overlaps alternate filled / empty).
---
---Example: `Vector.fill_rule("evenodd"); Vector.circle(0, 0, 40); Vector.circle(0, 0, 20); Vector.fill()`
---@param rule "nonzero"|"evenodd" "nonzero" (default) or "evenodd"; anything else is nonzero
function VectorModule.fill_rule(rule) end

---The opacity of what is drawn next (0..1).
---
---Example: `Vector.opacity(0.5); Vector.rect(0, 0, 50, 50); Vector.fill()`
---@param a number Opacity 0..1 for what is drawn next; default 1
function VectorModule.opacity(a) end

---Saves the style and transform (restore brings them back).
---
---Example: `Vector.save(); Vector.rotate(45); Vector.rect(-10, -10, 20, 20); Vector.fill(); Vector.restore()`
function VectorModule.save() end

---Restores the last saved style and transform.
---
---Example: `Vector.restore()`
function VectorModule.restore() end

---Moves what is drawn next.
---
---Example: `Vector.translate(100, 0)`
---@param x number Px to move right
---@param y number Px to move down
function VectorModule.translate(x, y) end

---Rotates what is drawn next (degrees, clockwise on screen).
---
---Example: `Vector.rotate(self.angle)`
---@param degrees number Angle in degrees, clockwise on screen
function VectorModule.rotate(degrees) end

---Scales what is drawn next (one number: both axes).
---
---Example: `Vector.scale(2)`
---@param sx number Horizontal factor (1 = as is, negative flips); default 1
---@param sy? number Vertical factor; nil uses sx
function VectorModule.scale(sx, sy) end

---@type VectorModule
Vector = VectorModule

---@class ScriptInstanceBase
---@field node Node The node this script is attached to.
---@field properties table<string, any> Custom exported script properties table.
---@field ready? fun(self: self) Lifecycle callback invoked when the node enters the scene.
---@field update? fun(self: self, dt: number) Lifecycle callback invoked each frame with delta time in seconds.
---@field on_draw? fun(self: self) Draw callback: draw with the Vector module in the node's local space, in the node's draw order (engine/docs/vector.md).
---@field on_destroy? fun(self: self) Lifecycle callback invoked when the node is destroyed.
---@field on_entered_tree? fun(self: self) Event: the node joined the scene.
---@field on_exited_tree? fun(self: self) Event: the node is being removed.
---@field on_child_added? fun(self: self, child: Node) Event: a child was added.
---@field on_child_removed? fun(self: self, child: Node) Event: a child was removed.
---@field on_timeout? fun(self: self) Event (TimerNode): the duration elapsed.
---@field on_tick? fun(self: self, elapsed: number) Event (TimerNode): each frame while running.
---@field on_body_entered? fun(self: self, other: Node) Event (AreaNode): a body entered.
---@field on_body_exited? fun(self: self, other: Node?) Event (AreaNode): a body left.
---@field on_collision_started? fun(self: self, other: Node) Event (bodies): contact began.
---@field on_collision_ended? fun(self: self, other: Node) Event (bodies): contact ended.
---@field on_hit_started? fun(self: self, other: Node) Event (RaycastNode): the ray hit a node.
---@field on_hit_ended? fun(self: self, other: Node) Event (RaycastNode): the ray stopped hitting it.
---@field on_animation_finished? fun(self: self, name: string?) Event: a non-looping animation ended.
---@field on_state_changed? fun(self: self, state: string) Event (StateMachineNode): entered a state.
---@field on_finished? fun(self: self) Event (Sound/Music): playback ended.
---@field on_clicked? fun(self: self) Event (UIButtonNode): clicked.
---@field on_value_changed? fun(self: self, value: any) Event (UI inputs): the value changed.
---@field on_submitted? fun(self: self, text: string) Event (UITextInputNode): Enter pressed.
---@field on_selected? fun(self: self, index: integer) Event (UI lists): selection changed.
---@field on_gamepad_connected? fun(self: self, player: integer, name: string) Event (every script): a player's gamepad was plugged in.
---@field on_gamepad_disconnected? fun(self: self, player: integer) Event (every script): a player's gamepad was unplugged.
