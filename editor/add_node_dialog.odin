package editor

import "core:c"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import e "../engine"
import imgui "lib/imgui"

// ============================================================================
// Add Node Modal Dialog
// Categorized node picker with real-time search and detailed node descriptions
// ============================================================================

NodeCatalogEntry :: struct {
	name:        string,
	category:    string,
	icon:        string,
	description: string,
	typeName:    string, // engine node type (see engine/node_registry.odin)
}

nodeSearchBuf: [64]u8
selectedCatalogIdx: int = 0
showAddNodeDialog: bool = false

NODE_CATALOG := [?]NodeCatalogEntry{
	// 1. Core & 2D
	{
		name        = "Empty Node",
		category    = "Core & 2D",
		icon        = ICON_FA_CIRCLE_DOT,
		description = "Basic 2D transform node with position, rotation, scale, and hierarchy grouping.",
		typeName    = "Node",
	},
	{
		name        = "Camera 2D",
		category    = "Core & 2D",
		icon        = ICON_FA_VIDEO,
		description = "2D Camera viewport controller supporting target tracking, zoom levels, rotation, and screen offsets.",
		typeName    = "CameraNode",
	},
	{
		name        = "Behavior Tree",
		category    = "Animation & Effects",
		icon        = ICON_FA_SITEMAP,
		description = "Game AI as a tree of composites (Sequence, Selector...), decorators and leaves (actions, conditions, Lua scripts), ticked every frame for its parent. Edit it in the Behavior Tree tab; watch it run live.",
		typeName    = "BehaviorTreeNode",
	},
	{
		name        = "GOAP Agent",
		category    = "Animation & Effects",
		icon        = ICON_FA_BULLSEYE,
		description = "Goal-oriented action planning: give its parent goals (conditions on world keys) and actions (conditions, effects, costs, targets); it senses the world, picks the cheapest goal it can reach and plans the actions there. Edit it in the GOAP tab.",
		typeName    = "GoapNode",
	},
	{
		name        = "Oscillator",
		category    = "Animation & Effects",
		icon        = ICON_FA_RIGHT_LEFT,
		description = "A wave (sine, triangle, square, saw, noise or a curve) that drives numeric properties of other nodes: moving platforms, bobbing pickups, flickering lights, pulsing effects. Start, Stop, Pause and Resume from scripts.",
		typeName    = "OscillatorNode",
	},
	{
		name        = "Skeleton",
		category    = "Animation & Effects",
		icon        = ICON_FA_BONE,
		description = "Skeletal (cutout) animation from Spine or DragonBones exports: bones, meshes, skins, IK, events; crossfades; scripts can turn bones.",
		typeName    = "SkeletonNode",
	},
	{
		name        = "Bone Attachment",
		category    = "Animation & Effects",
		icon        = ICON_FA_PAPERCLIP,
		description = "Under a Skeleton: follows one of its bones - put a weapon, a light or particles under it.",
		typeName    = "BoneAttachmentNode",
	},
	{
		name        = "Advanced Camera",
		category    = "Core & 2D",
		icon        = ICON_FA_CAMERA,
		description = "A virtual camera (Phantom Camera style): follow modes (glued, damped with look-ahead, group with auto-zoom, path, dead zone), limits incl. the LDtk level the target is in, trauma shake. The highest priority one is shown; switching blends.",
		typeName    = "AdvancedCameraNode",
	},
	{
		name        = "Timer",
		category    = "Core & 2D",
		icon        = ICON_FA_GEAR,
		description = "Periodic and one-shot countdown timer node for delayed actions and recurring intervals.",
		typeName    = "TimerNode",
	},
	{
		name        = "Spawner",
		category    = "Core & 2D",
		icon        = ICON_FA_CLONE,
		description = "Spawns components where it is (position, rotation, flip): one, all, a random pick or the next in its list - on a call, a signal or a timer, with limits, spread and pooling. Put it on a player to fire bullets from the hand.",
		typeName    = "SpawnerNode",
	},
	{
		name        = "Level Generator",
		category    = "Core & 2D",
		icon        = ICON_FA_SHUFFLE,
		description = "Generates a level from a Level Generator file into a TileMap when the scene starts (or on generate() / a signal): a seed or a random one, the generator's parameters set per node, in the background for big levels.",
		typeName    = "LevelGeneratorNode",
	},
	{
		name        = "Lua Script Node",
		category    = "Core & 2D",
		icon        = ICON_FA_CODE,
		description = "Dedicated Lua scripted node that automatically executes lifecycle callbacks (ready, update, render).",
		typeName    = "ScriptNode",
	},

	// 2. Graphics & Rendering
	{
		name        = "Texture Sprite",
		category    = "Graphics & Rendering",
		icon        = ICON_FA_IMAGE,
		description = "2D textured sprite quad with texture mapping, tinting, origin offsets, and flipping.",
		typeName    = "TextureNode",
	},
	{
		name        = "Viewport",
		category    = "Graphics & Rendering",
		icon        = ICON_FA_WINDOW_MAXIMIZE,
		description = "Draws a view into a texture: the scene through its own Camera child (minimap, split-screen, security camera) or only its children (an in-world screen). Shows itself at its size; Sprites and materials use it as \"viewport:<name>\".",
		typeName    = "ViewportNode",
	},
	{
		name        = "Atlas Sprite",
		category    = "Graphics & Rendering",
		icon        = ICON_FA_CROP,
		description = "2D textured sprite displaying a sub-region (atlas / sheet slice) of a texture.",
		typeName    = "AtlasSpriteNode",
	},
	{
		name        = "Text",
		category    = "Graphics & Rendering",
		icon        = ICON_FA_FONT,
		description = "Text in the world: any project font (or SDF for crisp scaling), wrapping, alignment, rich text ([color=..] [size=..] [wave] [shake]), localization keys and a typewriter reveal.",
		typeName    = "TextNode",
	},
	{
		name        = "Nine Slice Sprite",
		category    = "Graphics & Rendering",
		icon        = ICON_FA_VECTOR_SQUARE,
		description = "A texture stretched to any size while its borders keep their size (panels, buttons, frames).",
		typeName    = "NineSliceNode",
	},
	{
		name        = "Parallax Background",
		category    = "Graphics & Rendering",
		icon        = ICON_FA_MOUNTAIN,
		description = "A background that moves with the camera at a factor (0 = fixed, 1 = world), repeating and optionally drifting.",
		typeName    = "ParallaxNode",
	},
	{
		name        = "Line",
		category    = "Graphics & Rendering",
		icon        = ICON_FA_DRAW_POLYGON,
		description = "A polyline through local points: width, colour, closed, rounded joints (lasers, ropes, outlines).",
		typeName    = "LineNode",
	},
	{
		name        = "Lip Sync",
		category    = "Graphics & Rendering",
		icon        = ICON_FA_WAVE_SQUARE,
		description = "Moves a vector mouth with a voice: Rhubarb Lip Sync cues (A-H, X) pick the mouth's frames while the sound plays - its own or a dialogue line's.",
		typeName    = "LipSyncNode",
	},
	{
		name        = "Vector Shape",
		category    = "Graphics & Rendering",
		icon        = ICON_FA_PAINTBRUSH,
		description = "Vector art from an SVG (Inkscape, Illustrator, Affinity, Figma) or a built-in shape: crisp at any zoom, anti-aliased, cached on the GPU.",
		typeName    = "VectorShapeNode",
	},
	{
		name        = "Path",
		category    = "Animation & Effects",
		icon        = ICON_FA_BEZIER_CURVE,
		description = "A curve through points with Bézier handles, edited in the viewport: routes, rails, moving platforms' tracks, camera paths. Add a Path Follow under it.",
		typeName    = "PathNode",
	},
	{
		name        = "Path Follow",
		category    = "Animation & Effects",
		icon        = ICON_FA_ROUTE,
		description = "Travels along its parent Path (or a Vector Shape's outline): speed, loop / ping-pong / stop, faces the way it goes. Put a sprite, a platform or an enemy under it.",
		typeName    = "PathFollowNode",
	},
	{
		name        = "Trail",
		category    = "Animation & Effects",
		icon        = ICON_FA_WIND,
		description = "A fading, tapering ribbon behind a moving node (place it as a child): lifetime, width, colours.",
		typeName    = "TrailNode",
	},
	{
		name        = "Post Effect",
		category    = "Graphics & Rendering",
		icon        = ICON_FA_FILTER,
		description = "Applies its Material shader to the whole screen: built-in vignette, CRT, pixelate, chromatic aberration, or your own. Several chain in order.",
		typeName    = "PostEffectNode",
	},
	{
		name        = "Screen Layer",
		category    = "UI & Interface",
		icon        = ICON_FA_LAYER_GROUP,
		description = "A HUD: everything under it draws in screen space, on top of the world, and doesn't move with the camera. Anchor it to a corner or edge of the screen (a score top-right stays top-right however wide the screen is); the editor shows it over the camera frame.",
		typeName    = "ScreenLayerNode",
	},
	{
		name        = "Touch Joystick",
		category    = "UI & Interface",
		icon        = ICON_FA_GAMEPAD,
		description = "An on-screen joystick for touch screens: the thumb's push presses four input actions (move_left / right / up / down) with its strength. Fixed or floating (appears where the thumb lands). Put it under a Screen Layer; it shows once the device is touched.",
		typeName    = "TouchJoystickNode",
	},
	{
		name        = "Touch Button",
		category    = "UI & Interface",
		icon        = ICON_FA_HAND,
		description = "An on-screen button for touch screens: presses an input action (jump, fire...) while a finger is on it. Put it under a Screen Layer; it shows once the device is touched.",
		typeName    = "TouchButtonNode",
	},
	{
		name        = "Dialogue Box",
		category    = "UI & Interface",
		icon        = ICON_FA_COMMENT,
		description = "A dialogue box: lines with a speaker type out and advance with the confirm action; lines can offer choices. Scripts: box:dialogue_show({...}); events line_shown / chosen / finished.",
		typeName    = "DialogueNode",
	},
	{
		name        = "LDtk Tilemap Level",
		category    = "Graphics & Rendering",
		icon        = ICON_FA_MAP,
		description = "Full LDtk level renderer for grid-based tile layers, auto-layering, and entity placement.",
		typeName    = "LdtkLevelNode",
	},
	{
		name        = "Light",
		category    = "Graphics & Rendering",
		icon        = ICON_FA_LIGHTBULB,
		description = "2D point or spot light with colour, energy, radius and falloff; casts shadows from physics shapes. Set the scene's Ambient to darken unlit areas.",
		typeName    = "LightNode",
	},
	{
		name        = "Tile Map",
		category    = "Graphics & Rendering",
		icon        = ICON_FA_TABLE_CELLS,
		description = "Grid of tiles from a tileset image, painted in the viewport; optional colliders.",
		typeName    = "TileMapNode",
	},

	// 3. Audio & Sound
	{
		name        = "Sound Effect",
		category    = "Audio & Sound",
		icon        = ICON_FA_VOLUME_HIGH,
		description = "Audio emitter for one-shot and recurring sound effects (.wav, .ogg) with volume and pitch control.",
		typeName    = "SoundNode",
	},
	{
		name        = "Music Streamer",
		category    = "Audio & Sound",
		icon        = ICON_FA_MUSIC,
		description = "Background streaming music player with seamless looping, crossfading, and volume attenuation.",
		typeName    = "MusicNode",
	},

	// 4. Animation & Effects
	{
		name        = "Animation Player",
		category    = "Animation & Effects",
		icon        = ICON_FA_FILM,
		description = "Keyframe animation sequencer supporting property tracks, transitions, and timeline scrubbing.",
		typeName    = "AnimationPlayerNode",
	},
	{
		name        = "State Machine",
		category    = "Animation & Effects",
		icon        = ICON_FA_DIAGRAM_PROJECT,
		description = "States, transitions and conditions on parameters; each state can play an animation on an AnimationPlayer. Scripts get on_enter_<state> / on_exit_<state>.",
		typeName    = "StateMachineNode",
	},
	{
		name        = "Frame Animator",
		category    = "Animation & Effects",
		icon        = ICON_FA_PHOTO_FILM,
		description = "Sprite sheet frame-by-frame animator with configurable frame durations, loops, and ping-pong modes.",
		typeName    = "FrameAnimationNode",
	},
	{
		name        = "Particle Emitter",
		category    = "Animation & Effects",
		icon        = ICON_FA_WAND_MAGIC_SPARKLES,
		description = "2D particle burst and fountain generator with customizable speed, spread, lifetime, and colors.",
		typeName    = "ParticleEmitterNode",
	},

	// 5. Physics & Collision
	{
		name        = "Dynamic Physics Box",
		category    = "Physics & Collision",
		icon        = ICON_FA_CUBES,
		description = "Box2D dynamic rigid body affected by gravity, physical impulses, forces, friction, and bounce.",
		typeName    = "DynamicBodyNode",
	},
	{
		name        = "Static Platform",
		category    = "Physics & Collision",
		icon        = ICON_FA_CUBE,
		description = "Static immovable collision body that dynamic bodies collide with; perfect for ground, walls, and terrain.",
		typeName    = "StaticBodyNode",
	},
	{
		name        = "Kinematic Platform",
		category    = "Physics & Collision",
		icon        = ICON_FA_ARROWS_UP_DOWN_LEFT_RIGHT,
		description = "Kinematic physics body moved by velocity or transform (moving platforms, elevators, doors) that carries characters and pushes dynamic bodies without being pushed back.",
		typeName    = "KinematicBodyNode",
	},
	{
		name        = "Character Mover",
		category    = "Physics & Collision",
		icon        = ICON_FA_PERSON_RUNNING,
		description = "Kinematic character controller with smooth velocity integration, slope climbing, and ground snapping.",
		typeName    = "CharacterMoverNode",
	},
	{
		name        = "Trigger Area",
		category    = "Physics & Collision",
		icon        = ICON_FA_EXPAND,
		description = "Region that reports bodies entering and leaving it (body_entered / body_exited) without colliding: pickups, triggers, hitboxes.",
		typeName    = "AreaNode",
	},
	{
		name        = "Raycast Sensor",
		category    = "Physics & Collision",
		icon        = ICON_FA_ARROW_RIGHT_LONG,
		description = "Directional line-of-sight raycaster detecting intersection points, surface normals, and hit fractions.",
		typeName    = "RaycastNode",
	},
	{
		name        = "Visibility Notifier",
		category    = "Physics & Collision",
		icon        = ICON_FA_EYE,
		description = "Knows when the camera sees a rectangle: screen_entered / screen_exited, and can pause, disable or remove its parent off screen (enemies wake up, bullets despawn).",
		typeName    = "VisibilityNotifierNode",
	},
	{
		name        = "Navigation Region",
		category    = "Physics & Collision",
		icon        = ICON_FA_MAP_LOCATION_DOT,
		description = "An area agents find paths in: baked into a grid from static bodies, solid tile maps and LDtk Solid cells. Bake in the Inspector; scripts can block cells (doors).",
		typeName    = "NavigationRegionNode",
	},
	{
		name        = "Navigation Agent",
		category    = "Physics & Collision",
		icon        = ICON_FA_LOCATION_ARROW,
		description = "Put it under a character: give it a target and it walks there along a path, around walls and other agents (moves a CharacterMover, a DynamicBody or any node).",
		typeName    = "NavigationAgentNode",
	},
	{
		name        = "Joint",
		category    = "Physics & Collision",
		icon        = ICON_FA_LINK,
		description = "Connects two bodies: hinge (revolute), distance, slider (prismatic), weld, wheel or motor; motors, springs and limits. Pick Body A (default: parent) and Body B.",
		typeName    = "JointNode",
	},

	// 6. UI & Interface
	{
		name        = "UI Container",
		category    = "UI & Interface",
		icon        = ICON_FA_OBJECT_GROUP,
		description = "Flexbox-style responsive layout container with horizontal/vertical flow, padding, and alignment.",
		typeName    = "UIContainerNode",
	},
	{
		name        = "UI Label",
		category    = "UI & Interface",
		icon        = ICON_FA_TAG,
		description = "Clean text renderer with font sizing and color styling (one line: no wrapping).",
		typeName    = "UILabelNode",
	},
	{
		name        = "UI Button",
		category    = "UI & Interface",
		icon        = ICON_FA_HAND_POINTER,
		description = "Interactive clickable button with hovered, normal, and pressed visual feedback and event callbacks.",
		typeName    = "UIButtonNode",
	},
	{
		name        = "UI Slider",
		category    = "UI & Interface",
		icon        = ICON_FA_SLIDERS,
		description = "Draggable continuous value slider for settings, volume, and numeric input.",
		typeName    = "UISliderNode",
	},
	{
		name        = "UI Checkbox",
		category    = "UI & Interface",
		icon        = ICON_FA_SQUARE_CHECK,
		description = "Toggle checkbox widget for boolean options and feature flags.",
		typeName    = "UICheckboxNode",
	},
	{
		name        = "UI Progress Bar",
		category    = "UI & Interface",
		icon        = ICON_FA_BARS_PROGRESS,
		description = "Horizontal progress percentage visualizer for health bars, loading indicators, and gauges.",
		typeName    = "UIProgressBarNode",
	},
	{
		name        = "UI Text Input",
		category    = "UI & Interface",
		icon        = ICON_FA_PEN,
		description = "Single-line text field with placeholder; raises submitted and value_changed.",
		typeName    = "UITextInputNode",
	},
	{
		name        = "UI Dropdown",
		category    = "UI & Interface",
		icon        = ICON_FA_CHEVRON_DOWN,
		description = "Drop-down selector over a list of options.",
		typeName    = "UIDropdownNode",
	},
	{
		name        = "UI Radio Group",
		category    = "UI & Interface",
		icon        = ICON_FA_CIRCLE,
		description = "Mutually exclusive options.",
		typeName    = "UIRadioGroupNode",
	},
	{
		name        = "UI Toggle Switch",
		category    = "UI & Interface",
		icon        = ICON_FA_TOGGLE_ON,
		description = "On/off switch.",
		typeName    = "UIToggleSwitchNode",
	},
	{
		name        = "UI Knob",
		category    = "UI & Interface",
		icon        = ICON_FA_ROTATE_RIGHT,
		description = "Rotary value control.",
		typeName    = "UIKnobNode",
	},
	{
		name        = "UI Notched Slider",
		category    = "UI & Interface",
		icon        = ICON_FA_RULER_HORIZONTAL,
		description = "Slider that snaps to detents.",
		typeName    = "UINotchedSliderNode",
	},
	{
		name        = "UI Volume Fader",
		category    = "UI & Interface",
		icon        = ICON_FA_VOLUME_LOW,
		description = "Audio fader in decibels.",
		typeName    = "UIVolumeFaderNode",
	},
	{
		name        = "UI Volume Meter",
		category    = "UI & Interface",
		icon        = ICON_FA_SIGNAL,
		description = "Stereo level meter.",
		typeName    = "UIVolumeMeterNode",
	},
	{
		name        = "UI Separator",
		category    = "UI & Interface",
		icon        = ICON_FA_MINUS,
		description = "Horizontal divider with an optional label.",
		typeName    = "UISeparatorNode",
	},
	{
		name        = "UI XY Plot",
		category    = "UI & Interface",
		icon        = ICON_FA_CHART_LINE,
		description = "Line plot of streaming values.",
		typeName    = "UIXYPlotNode",
	},
	{
		name        = "UI List View",
		category    = "UI & Interface",
		icon        = ICON_FA_LIST,
		description = "Scrollable selectable list; raises selected.",
		typeName    = "UIListViewNode",
	},
	{
		name        = "UI Tree View",
		category    = "UI & Interface",
		icon        = ICON_FA_FOLDER_TREE,
		description = "Hierarchical expandable tree.",
		typeName    = "UITreeViewNode",
	},
	{
		name        = "UI Bullet List",
		category    = "UI & Interface",
		icon        = ICON_FA_LIST_UL,
		description = "HTML-style unordered list.",
		typeName    = "UIUnorderedListNode",
	},
	{
		name        = "UI Numbered List",
		category    = "UI & Interface",
		icon        = ICON_FA_LIST_OL,
		description = "HTML-style ordered list.",
		typeName    = "UIOrderedListNode",
	},
	{
		name        = "UI Table",
		category    = "UI & Interface",
		icon        = ICON_FA_TABLE,
		description = "Sortable data table; raises row_selected and sorted.",
		typeName    = "UITableNode",
	},
	{
		name        = "UI Icon",
		category    = "UI & Interface",
		icon        = ICON_FA_ICONS,
		description = "Vector icon.",
		typeName    = "UIIconNode",
	},
	{
		name        = "UI Toolbar",
		category    = "UI & Interface",
		icon        = ICON_FA_TOOLBOX,
		description = "Row of icon buttons; raises item_clicked.",
		typeName    = "UIToolbarNode",
	},
	{
		name        = "UI Tab Container",
		category    = "UI & Interface",
		icon        = ICON_FA_TABLE_COLUMNS,
		description = "Tabbed pages container.",
		typeName    = "UITabContainerNode",
	},
	{
		name        = "Aseprite Sprite",
		category    = "Animation & Effects",
		icon        = ICON_FA_PALETTE,
		description = "An Aseprite file (.aseprite / .ase) played as Aseprite does: tags, directions, repeats, frame durations; layers on / off, slices and user data for scripts. Saving in Aseprite updates it live.",
		typeName    = "AsepriteNode",
	},
}

AddNodeDialog_Open :: proc() {
	showAddNodeDialog = true
	nodeSearchBuf = [64]u8{}
	selectedCatalogIdx = -1 // (the first built-in type: Empty Node)
}

// add_node_entries: the project's custom node types (#156), by category,
// then the built-in catalogue. `customCount`: how many come first. A custom
// entry's typeName is its .node.json.
@(private = "file")
add_node_entries :: proc(state: ^EditorState) -> (entries: []NodeCatalogEntry, customCount: int) {
	out := make([dynamic]NodeCatalogEntry, context.temp_allocator)
	custom := make([dynamic]NodeCatalogEntry, context.temp_allocator)
	for t in e.CustomNodes_All(&state.game.gameContext) {
		desc := t.description if t.description != "" else fmt.tprintf("A %s of your project: %s with its script and values.", t.name, t.base)
		append(&custom, NodeCatalogEntry{
			name        = strings.clone(t.name, context.temp_allocator),
			category    = strings.clone(t.category if t.category != "" else "Project", context.temp_allocator),
			icon        = CustomNode_Icon(t),
			description = strings.clone(desc, context.temp_allocator),
			typeName    = strings.clone(t.path, context.temp_allocator),
		})
	}
	// (Grouped by category, A-Z; by name within one.)
	for i in 1 ..< len(custom) {
		for j := i; j > 0 && (custom[j].category < custom[j - 1].category || (custom[j].category == custom[j - 1].category && custom[j].name < custom[j - 1].name)); j -= 1 {
			custom[j], custom[j - 1] = custom[j - 1], custom[j]
		}
	}
	append(&out, ..custom[:])
	append(&out, ..NODE_CATALOG[:])
	return out[:], len(custom)
}

// add_node_is_custom: an entry for a custom node type.
@(private = "file")
add_node_is_custom :: proc(entry: NodeCatalogEntry) -> bool {
	return strings.has_suffix(entry.typeName, e.CUSTOM_NODE_SUFFIX)
}

@(private = "file")
catalog_matches :: proc(item: NodeCatalogEntry, filter: string) -> bool {
	if filter == "" do return true
	return strings.contains(strings.to_lower(item.name, context.temp_allocator), filter) ||
		strings.contains(strings.to_lower(item.category, context.temp_allocator), filter) ||
		strings.contains(strings.to_lower(item.description, context.temp_allocator), filter) ||
		strings.contains(strings.to_lower(item.typeName, context.temp_allocator), filter)
}

AddNodeDialog_Render :: proc(state: ^EditorState) {
	if showAddNodeDialog && !imgui.IsPopupOpen("Add Node###AddNodeDialog") {
		imgui.OpenPopup("Add Node###AddNodeDialog")
	}
	io := imgui.GetIO()
	imgui.SetNextWindowSize({760, 500}, .Appearing)
	imgui.SetNextWindowPos({io.DisplaySize.x * 0.5, io.DisplaySize.y * 0.5}, .Appearing, {0.5, 0.5})
	imgui.PushStyleVarImVec2(.WindowPadding, {16, 14})
	defer imgui.PopStyleVar()
	if !imgui.BeginPopupModal("Add Node###AddNodeDialog", &showAddNodeDialog, {.NoResize, .NoTitleBar}) do return

	UI_PanelTitle(ICON_FA_PLUS, "Add Node")
	parent := Editor_InsertionParent(state)
	imgui.SameLine(0, UI_SPACE)
	UI_DimText(fmt.tprintf("under %s", parent.name if parent != nil else "root"))
	imgui.Dummy({0, 4})

	if imgui.IsWindowAppearing() do imgui.SetKeyboardFocusHere()
	imgui.SetNextItemWidth(-1)
	imgui.InputTextWithHint("##NodeSearchFilter", fmt.ctprintf("%s  Search node types", ICON_FA_MAGNIFYING_GLASS), cstring(raw_data(nodeSearchBuf[:])), len(nodeSearchBuf), {})
	Drive_Item("addnode.search")
	filter := strings.to_lower(string(cstring(raw_data(nodeSearchBuf[:]))), context.temp_allocator)
	entries, customCount := add_node_entries(state)
	if selectedCatalogIdx < 0 do selectedCatalogIdx = customCount // (Empty Node)

	// Keep the selection on a visible entry; when the search changes, prefer
	// one whose name matches ("joint" picks Joint, not Line's "round joints").
	@(static) lastFilter: [64]u8
	if string(cstring(raw_data(lastFilter[:]))) != filter {
		lastFilter = {}
		copy(lastFilter[:len(lastFilter) - 1], filter)
		best := -1
		for item, i in entries {
			if filter != "" && (strings.contains(strings.to_lower(item.name, context.temp_allocator), filter) || strings.contains(strings.to_lower(item.typeName, context.temp_allocator), filter)) {
				best = i
				break
			}
		}
		if best >= 0 do selectedCatalogIdx = best
	}
	if selectedCatalogIdx < 0 || selectedCatalogIdx >= len(entries) || !catalog_matches(entries[selectedCatalogIdx], filter) {
		for item, i in entries {
			if catalog_matches(item, filter) {selectedCatalogIdx = i; break}
		}
	}
	if imgui.IsKeyPressed(.DownArrow) || imgui.IsKeyPressed(.UpArrow) {
		dir := 1 if imgui.IsKeyPressed(.DownArrow) else -1
		for k := 1; k < len(entries); k += 1 {
			i := (selectedCatalogIdx + dir * k + len(entries) * 2) % len(entries)
			if catalog_matches(entries[i], filter) {selectedCatalogIdx = i; break}
		}
	}

	imgui.Dummy({0, 4})
	listH := imgui.GetContentRegionAvail().y - 44
	create := false
	imgui.PushStyleColorImVec4(.ChildBg, UI_BG_APP)
	if imgui.BeginChild("##catalog", {360, listH}, {}, {}) {
		lastCat := ""
		for item, i in entries {
			if !catalog_matches(item, filter) do continue
			if item.category != lastCat {
				imgui.Dummy({0, 2})
				imgui.PushFont(GlobalFonts.small)
				imgui.PushStyleColorImVec4(.Text, UI_TEXT_FAINT)
				imgui.TextUnformatted(fmt.ctprintf("  %s%s", strings.to_upper(item.category, context.temp_allocator), "  ·  YOUR PROJECT" if add_node_is_custom(item) else ""))
				imgui.PopStyleColor()
				imgui.PopFont()
				lastCat = item.category
			}
			if imgui.Selectable(fmt.ctprintf("   %s   %s###nodeitem_%d", item.icon, item.name, i), selectedCatalogIdx == i, {}, {0, 26}) {
				selectedCatalogIdx = i
			}
			Drive_Item(fmt.tprintf("addnode:%s", item.name))
			if imgui.IsItemHovered() && imgui.IsMouseDoubleClicked(.Left) {
				selectedCatalogIdx = i
				create = true
			}
		}
	}
	imgui.EndChild()
	imgui.PopStyleColor()

	imgui.SameLine(0, 16)
	if imgui.BeginChild("##detail", {0, listH}, {}, {}) {
		if selectedCatalogIdx >= 0 && selectedCatalogIdx < len(entries) {
			sel := entries[selectedCatalogIdx]
			imgui.PushStyleColorImVec4(.Text, UI_ACCENT)
			imgui.PushFont(GlobalFonts.semibold)
			imgui.TextUnformatted(fmt.ctprintf("%s  %s", sel.icon, sel.name))
			imgui.PopFont()
			imgui.PopStyleColor()
			if add_node_is_custom(sel) {
				// A custom node type: what it's made of.
				if t, _ := e.CustomNode_Get(&state.game.gameContext, sel.typeName); t != nil {
					script := e.CustomNode_Script(t, &state.game.gameContext)
					UI_DimText(fmt.tprintf("A %s%s  ·  %s", t.base, fmt.tprintf(" with %s", script) if script != "" else "", sel.typeName))
				}
			} else {
				UI_DimText(sel.typeName)
			}
			imgui.Dummy({0, 6})
			imgui.TextWrapped("%s", strings.clone_to_cstring(sel.description, context.temp_allocator))
		}
	}
	imgui.EndChild()

	imgui.Dummy({0, 6})
	if imgui.IsKeyPressed(.Enter) || imgui.IsKeyPressed(.KeypadEnter) do create = true
	if UI_Button(fmt.tprintf("%s  Create Custom Node...", ICON_FA_PUZZLE_PIECE), "addnode.new-custom", {0, 30}) {
		showAddNodeDialog = false
		imgui.CloseCurrentPopup()
		CustomNodeDialog_Open(state)
	}
	UI_Tooltip("A node type of your own: a base type, a script and default values")
	imgui.SameLine(0, 0)
	imgui.SetCursorPosX(imgui.GetWindowWidth() - 16 - 120 - 90 - UI_SPACE)
	if UI_Button("Cancel", "addnode.cancel", {90, 30}) || imgui.IsKeyPressed(.Escape) {
		showAddNodeDialog = false
		imgui.CloseCurrentPopup()
	}
	imgui.SameLine(0, UI_SPACE)
	if UI_PrimaryButton("Create", "addnode.create", {120, 30}) do create = true
	if create {
		AddNodeDialog_CreateSelected(state)
		showAddNodeDialog = false
		imgui.CloseCurrentPopup()
	}
	imgui.EndPopup()
}

AddNodeDialog_CreateSelected :: proc(state: ^EditorState) {
	if state.activeScene == nil do return
	entries, _ := add_node_entries(state)
	if selectedCatalogIdx < 0 || selectedCatalogIdx >= len(entries) do return

	entry := entries[selectedCatalogIdx]
	if add_node_is_custom(entry) {
		// A custom node type (#156): its node, under the selection, at the view's centre.
		_ = Editor_AddCustomNode(state, entry.typeName, state.cameraPos)
		return
	}
	newNode := Editor_CreateNode(state, entry.typeName, strings.trim_space(strings.concatenate({entry.name}, context.temp_allocator)))
	if newNode != nil {
		Editor_Log(state, .Info, "Created new node: %s (%s)", newNode.name, entry.name)
	}
}
