package engine

import "core:strings"

// ============================================================================
// Node Type Registry
//
// One table maps a node type's name (as written in scene JSON) to its typeid
// and a factory that builds a fully initialised, working node of that type
// (update/render procs set, physics body created, ...). The scene loader and
// the editor's "Add Node" both create nodes through it, so a node created in
// the editor behaves exactly like one loaded from a file.
// ============================================================================

Node_Factory :: proc(scene: ^Scene, parent: ^Node) -> ^Node

Node_Type_Info :: struct {
	name:     string,   // canonical JSON "type"
	type:     typeid,
	create:   Node_Factory,
	aliases:  []string, // accepted (lower-case) legacy names
}

// The canonical list. Order is also the editor's display order.
NODE_TYPES := [?]Node_Type_Info{
	{"Node", Node, factory_node, {"node", "empty"}},
	{"CameraNode", CameraNode, factory_camera, {"camera"}},
	{"TimerNode", TimerNode, factory_timer, {"timer"}},
	{"SpawnerNode", SpawnerNode, factory_spawner, {"spawner", "spawn"}},
	{"LevelGeneratorNode", LevelGeneratorNode, factory_level_generator, {"levelgenerator", "levelgen", "generator", "procedural"}},
	{"ScriptNode", ScriptNode, factory_script, {"script"}},
	{"TextureNode", TextureNode, factory_texture, {"texture", "sprite"}},
	{"AtlasSpriteNode", AtlasSpriteNode, factory_atlas_sprite, {"atlassprite", "atlas", "subtexture", "spritesheet"}},
	{"FrameAnimationNode", FrameAnimationNode, factory_frame_animation, {"animationnode", "frameanimation", "animation"}},
	{"AnimationPlayerNode", AnimationPlayerNode, factory_animation_player, {"animationplayer"}},
	{"AsepriteNode", AsepriteNode, factory_aseprite, {"aseprite", "ase"}},
	{"StateMachineNode", StateMachineNode, factory_state_machine, {"statemachine", "state_machine"}},
	{"ParticleEmitterNode", ParticleEmitterNode, factory_particles, {"particle", "particles", "particleemitter"}},
	{"SoundNode", SoundNode, factory_sound, {"sound"}},
	{"MusicNode", MusicNode, factory_music, {"music"}},
	{"StaticBodyNode", StaticBodyNode, factory_static_body, {"staticbody", "static_body"}},
	{"DynamicBodyNode", DynamicBodyNode, factory_dynamic_body, {"dynamicbody", "dynamic_body"}},
	{"KinematicBodyNode", KinematicBodyNode, factory_kinematic_body, {"kinematicbody", "kinematic_body", "kinematicphysics", "kinematic_physics"}},
	{"CharacterMoverNode", CharacterMoverNode, factory_character, {"charactermover", "character_mover"}},
	{"AreaNode", AreaNode, factory_area, {"area"}},
	{"RaycastNode", RaycastNode, factory_raycast, {"raycast"}},
	{"VisibilityNotifierNode", VisibilityNotifierNode, factory_visibility, {"visibility", "on screen", "notifier"}},
	{"ScreenLayerNode", ScreenLayerNode, factory_screen_layer, {"screen layer", "screenlayer", "hud", "canvas layer", "overlay", "ui layer"}},
	{"TouchJoystickNode", TouchJoystickNode, factory_touch_joystick, {"touch joystick", "touchjoystick", "virtual joystick", "joystick", "thumbstick"}},
	{"TouchButtonNode", TouchButtonNode, factory_touch_button, {"touch button", "touchbutton", "virtual button", "on-screen button"}},
	{"ViewportNode", ViewportNode, factory_viewport, {"viewport", "render texture", "render target", "subviewport", "minimap", "split screen", "picture in picture"}},
	{"OscillatorNode", OscillatorNode, factory_oscillator, {"oscillator", "lfo", "wave", "sine", "bob", "pulse", "automation"}},
	{"SkeletonNode", SkeletonNode, factory_skeleton, {"skeleton", "spine", "dragonbones", "bones", "rig", "cutout"}},
	{"BoneAttachmentNode", BoneAttachmentNode, factory_bone_attachment, {"bone attachment", "attach to bone"}},
	{"AdvancedCameraNode", AdvancedCameraNode, factory_adv_camera, {"advanced camera", "virtual camera", "phantom", "cinemachine"}},
	{"PathNode", PathNode, factory_path, {"path", "curve", "bezier", "route", "rail"}},
	{"NavigationRegionNode", NavigationRegionNode, factory_nav_region, {"navigation", "nav region", "navmesh", "pathfinding"}},
	{"NavigationAgentNode", NavigationAgentNode, factory_nav_agent, {"nav agent", "agent", "pathfinding agent"}},
	{"PathFollowNode", PathFollowNode, factory_path_follow, {"path follow", "follower", "moving platform"}},
	{"LdtkLevelNode", LdtkLevelNode, factory_ldtk, {"ldtk", "ldtklevel"}},
	{"TileMapNode", TileMapNode, factory_tilemap, {"tilemap"}},
	{"LightNode", LightNode, factory_light, {"light", "pointlight", "spotlight"}},
	{"JointNode", JointNode, factory_joint, {"joint", "physicsjoint"}},
	{"TextNode", TextNode, factory_text, {"text", "label2d", "textlabel"}},
	{"DialogueNode", DialogueNode, factory_dialogue, {"dialogue", "dialoguebox"}},
	{"LipSyncNode", LipSyncNode, factory_lipsync, {"lipsync", "lip sync", "mouth", "rhubarb"}},
	{"NineSliceNode", NineSliceNode, factory_nine_slice, {"nineslice", "ninepatch"}},
	{"ParallaxNode", ParallaxNode, factory_parallax, {"parallax", "parallaxlayer"}},
	{"LineNode", LineNode, factory_line, {"line", "line2d"}},
	{"VectorShapeNode", VectorShapeNode, factory_vector_shape, {"vector", "vectorshape", "svg", "shape"}},
	{"TrailNode", TrailNode, factory_trail, {"trail"}},
	{"PostEffectNode", PostEffectNode, factory_post_effect, {"posteffect", "post_effect"}},
	{"UIContainerNode", UIContainerNode, factory_ui_container, {"uicontainer", "uipanel", "uipanelnode"}},
	{"UILabelNode", UILabelNode, factory_ui_label, {"uilabel"}},
	{"UIButtonNode", UIButtonNode, factory_ui_button, {"uibutton"}},
	{"UISliderNode", UISliderNode, factory_ui_slider, {"uislider"}},
	{"UICheckboxNode", UICheckboxNode, factory_ui_checkbox, {"uicheckbox"}},
	{"UIProgressBarNode", UIProgressBarNode, factory_ui_progress, {"uiprogressbar"}},
	{"UITextInputNode", UITextInputNode, factory_textinput, {"uitextinput"}},
	{"UIDropdownNode", UIDropdownNode, factory_dropdown, {"uidropdown"}},
	{"UIRadioGroupNode", UIRadioGroupNode, factory_radiogroup, {"uiradiogroup"}},
	{"UIToggleSwitchNode", UIToggleSwitchNode, factory_toggleswitch, {"uitoggleswitch"}},
	{"UIKnobNode", UIKnobNode, factory_knob, {"uiknob"}},
	{"UINotchedSliderNode", UINotchedSliderNode, factory_notchedslider, {"uinotchedslider"}},
	{"UIVolumeFaderNode", UIVolumeFaderNode, factory_volumefader, {"uivolumefader"}},
	{"UIVolumeMeterNode", UIVolumeMeterNode, factory_volumemeter, {"uivolumemeter"}},
	{"UISeparatorNode", UISeparatorNode, factory_separator, {"uiseparator"}},
	{"UIXYPlotNode", UIXYPlotNode, factory_xyplot, {"uixyplot"}},
	{"UIListViewNode", UIListViewNode, factory_listview, {"uilistview"}},
	{"UITreeViewNode", UITreeViewNode, factory_treeview, {"uitreeview"}},
	{"UIUnorderedListNode", UIUnorderedListNode, factory_unorderedlist, {"uiunorderedlist"}},
	{"UIOrderedListNode", UIOrderedListNode, factory_orderedlist, {"uiorderedlist"}},
	{"UITableNode", UITableNode, factory_table, {"uitable"}},
	{"UIIconNode", UIIconNode, factory_icon, {"uiicon"}},
	{"UIToolbarNode", UIToolbarNode, factory_toolbar, {"uitoolbar"}},
	{"UITabContainerNode", UITabContainerNode, factory_tabcontainer, {"uitabcontainer"}},
}

// Node_TypeInfoByName finds a type by canonical name or alias (any case).
Node_TypeInfoByName :: proc(name: string) -> (^Node_Type_Info, bool) {
	for &info in NODE_TYPES {
		if strings.equal_fold(info.name, name) do return &info, true
		for a in info.aliases {
			if strings.equal_fold(a, name) do return &info, true
		}
	}
	return nil, false
}

Node_TypeInfoById :: proc(t: typeid) -> (^Node_Type_Info, bool) {
	for &info in NODE_TYPES {
		if info.type == t do return &info, true
	}
	return nil, false
}

// Node_TypeName is the JSON "type" of a node ("Node" for unknown types).
Node_TypeName :: proc(node: ^Node) -> string {
	if node == nil do return "Node"
	if info, ok := Node_TypeInfoById(node.typeId); ok do return info.name
	return "Node"
}

// Node_CreateByTypeName builds a node of the named type under `parent`
// (the scene root when nil). Unknown names create a plain Node.
Node_CreateByTypeName :: proc(scene: ^Scene, typeName: string, parent: ^Node = nil) -> ^Node {
	if scene == nil || scene.manager == nil do return nil
	target := parent if parent != nil else scene.rootNode
	info, ok := Node_TypeInfoByName(typeName)
	node: ^Node
	if ok {
		node = info.create(scene, target)
	} else {
		node = factory_node(scene, target)
	}
	if node == nil do return nil
	if node.typeId == nil || (ok && node.typeId != info.type) {
		node.typeId = info.type if ok else typeid_of(Node)
	}
	place_under(scene, node, target)
	if scene.rootNode != nil && scene.rootNode.gameContext != nil && node.gameContext == nil {
		node.gameContext = scene.rootNode.gameContext
	}
	return node
}

// place_under makes `parent` the node's (only) parent, whatever the type's
// constructor did: some add to the root, some take a parent, some add nothing.
@(private = "file")
place_under :: proc(scene: ^Scene, node, parent: ^Node) {
	if !node.inTree {
		SceneAddNode(scene, node, parent)
		return
	}
	current := GetParent(scene.manager, node)
	if current == parent do return
	if current != nil do RemoveChild(scene.manager, current, node)
	if parent != nil && parent != node do AddChild(scene.manager, parent, node)
}

// --- factories ---------------------------------------------------------------------

@(private = "file")
factory_node :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return CreateNode(scene.manager, Node)
}

@(private = "file")
factory_camera :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return CameraNode_Create(scene, "Camera", true, parent)
}

@(private = "file")
factory_nine_slice :: proc(scene: ^Scene, parent: ^Node) -> ^Node {return NineSliceNode_Create(scene, "NineSlice", parent)}
@(private = "file")
factory_parallax :: proc(scene: ^Scene, parent: ^Node) -> ^Node {return ParallaxNode_Create(scene, "Parallax", parent)}
@(private = "file")
factory_line :: proc(scene: ^Scene, parent: ^Node) -> ^Node {return LineNode_Create(scene, "Line", parent)}
@(private = "file")
factory_vector_shape :: proc(scene: ^Scene, parent: ^Node) -> ^Node {return VectorShapeNode_Create(scene, "VectorShape", parent)}
@(private = "file")
factory_trail :: proc(scene: ^Scene, parent: ^Node) -> ^Node {return TrailNode_Create(scene, "Trail", parent)}
@(private = "file")
factory_post_effect :: proc(scene: ^Scene, parent: ^Node) -> ^Node {return PostEffectNode_Create(scene, "PostEffect", parent)}

@(private = "file")
factory_text :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return TextNode_Create(scene, "Text", parent)
}

@(private = "file")
factory_lipsync :: proc(scene: ^Scene, parent: ^Node) -> ^Node {return LipSyncNode_Create(scene, "LipSync", parent)}

@(private = "file")
factory_dialogue :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return DialogueNode_Create(scene, "Dialogue", parent)
}

@(private = "file")
factory_joint :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return JointNode_Create(scene, "Joint", parent)
}

@(private = "file")
factory_light :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return LightNode_Create(scene, "Light", parent)
}

factory_timer :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return TimerNode_Create(scene, 1.0, false, false)
}

@(private = "file")
factory_script :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	sn := CreateNode(scene.manager, ScriptNode)
	ScriptNode_Init(sn)
	return sn
}

@(private = "file")
factory_texture :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	tn := CreateNode(scene.manager, TextureNode)
	TextureNode_Init(tn)
	return tn
}

@(private = "file")
factory_atlas_sprite :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	an := CreateNode(scene.manager, AtlasSpriteNode)
	AtlasSpriteNode_Init(an)
	return an
}

@(private = "file")
factory_frame_animation :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return FrameAnimationNode_Create(scene)
}

@(private = "file")
factory_animation_player :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return AnimationPlayerNode_Create(scene, "AnimationPlayer")
}

@(private = "file")
factory_state_machine :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return StateMachineNode_Create(scene, "StateMachine", parent)
}

@(private = "file")
factory_particles :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return ParticleEmitterNode_Create(scene, "Particles")
}

@(private = "file")
factory_sound :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	sn := CreateNode(scene.manager, SoundNode)
	SoundNode_Init(sn)
	return sn
}

@(private = "file")
factory_music :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return MusicNode_Create(scene, nil, "", "Music", false, true, parent)
}

@(private = "file")
factory_static_body :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return StaticBodyNode_Create(scene, "StaticBody", parent)
}

@(private = "file")
factory_dynamic_body :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return DynamicBodyNode_Create(scene, "DynamicBody", parent)
}

@(private = "file")
factory_kinematic_body :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return KinematicBodyNode_Create(scene, "KinematicBody", parent)
}

@(private = "file")
factory_character :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return CharacterMoverNode_Create(scene, "CharacterMover", parent)
}

@(private = "file")
factory_screen_layer :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return ScreenLayerNode_Create(scene, "ScreenLayer", parent)
}

@(private = "file")
factory_touch_joystick :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return TouchJoystickNode_Create(scene, "TouchJoystick", parent)
}

@(private = "file")
factory_touch_button :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return TouchButtonNode_Create(scene, "TouchButton", parent)
}

@(private = "file")
factory_oscillator :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return OscillatorNode_Create(scene, "Oscillator", parent)
}

@(private = "file")
factory_viewport :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return ViewportNode_Create(scene, "Viewport", parent)
}

@(private = "file")
factory_area :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return AreaNode_Create(scene, "Area", parent)
}

@(private = "file")
factory_path :: proc(scene: ^Scene, parent: ^Node) -> ^Node {return PathNode_Create(scene, "Path", parent)}

@(private = "file")
factory_nav_region :: proc(scene: ^Scene, parent: ^Node) -> ^Node {return NavigationRegionNode_Create(scene, "NavigationRegion", parent)}

@(private = "file")
factory_nav_agent :: proc(scene: ^Scene, parent: ^Node) -> ^Node {return NavigationAgentNode_Create(scene, "NavigationAgent", parent)}

@(private = "file")
factory_path_follow :: proc(scene: ^Scene, parent: ^Node) -> ^Node {return PathFollowNode_Create(scene, "PathFollow", parent)}

@(private = "file")
factory_skeleton :: proc(scene: ^Scene, parent: ^Node) -> ^Node {return SkeletonNode_Create(scene, "Skeleton", parent)}

@(private = "file")
factory_aseprite :: proc(scene: ^Scene, parent: ^Node) -> ^Node {return AsepriteNode_Create(scene, "Aseprite", parent)}

@(private = "file")
factory_bone_attachment :: proc(scene: ^Scene, parent: ^Node) -> ^Node {return BoneAttachmentNode_Create(scene, "BoneAttachment", parent)}

@(private = "file")
factory_adv_camera :: proc(scene: ^Scene, parent: ^Node) -> ^Node {return AdvancedCameraNode_Create(scene, "AdvancedCamera", parent)}

@(private = "file")
factory_visibility :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return VisibilityNotifierNode_Create(scene, "VisibilityNotifier", parent)
}

@(private = "file")
factory_spawner :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return SpawnerNode_Create(scene, "Spawner", parent)
}

@(private = "file")
factory_level_generator :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return LevelGeneratorNode_Create(scene, "LevelGenerator", parent)
}

@(private = "file")
factory_raycast :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return RaycastNode_Create(scene, "Raycast", parent)
}

@(private = "file")
factory_ldtk :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return LdtkLevelNode_Create(scene, "LdtkLevel", "", "", parent)
}

@(private = "file")
factory_ui_container :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UIPanelNode_Create(scene, "Panel", "Panel", {0, 0}, {320, 240}, .Vertical, parent)
}

@(private = "file")
factory_ui_label :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UILabelNode_Create(scene, "Label", "Label", parent = parent)
}

@(private = "file")
factory_ui_button :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UIButtonNode_Create(scene, "Button", "Button", parent = parent)
}

@(private = "file")
factory_ui_slider :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UISliderNode_Create(scene, "Slider", "Value", parent = parent)
}

@(private = "file")
factory_ui_checkbox :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UICheckboxNode_Create(scene, "Checkbox", "Checkbox", parent = parent)
}

@(private = "file")
factory_ui_progress :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UIProgressBarNode_Create(scene, "ProgressBar", "Progress", parent = parent)
}

// Default content for list-like widgets created from the editor.
UI_DEFAULT_OPTIONS := [?]string{"Option A", "Option B", "Option C"}
UI_DEFAULT_TABS := [?]string{"Tab 1", "Tab 2"}

@(private = "file")
factory_textinput :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UITextInputNode_Create(scene, "TextInput", "Input", parent = parent)
}

@(private = "file")
factory_dropdown :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UIDropdownNode_Create(scene, "Dropdown", "Select", UI_DEFAULT_OPTIONS[:], parent = parent)
}

@(private = "file")
factory_radiogroup :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UIRadioGroupNode_Create(scene, "RadioGroup", "Option", UI_DEFAULT_OPTIONS[:], parent = parent)
}

@(private = "file")
factory_toggleswitch :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UIToggleSwitchNode_Create(scene, "ToggleSwitch", "Toggle", parent = parent)
}

@(private = "file")
factory_knob :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UIKnobNode_Create(scene, "Knob", "Volume", parent = parent)
}

@(private = "file")
factory_notchedslider :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UINotchedSliderNode_Create(scene, "NotchedSlider", "Detents", parent = parent)
}

@(private = "file")
factory_volumefader :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UIVolumeFaderNode_Create(scene, "VolumeFader", "Master", parent = parent)
}

@(private = "file")
factory_volumemeter :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UIVolumeMeterNode_Create(scene, "VolumeMeter", "VU", parent = parent)
}

@(private = "file")
factory_separator :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UISeparatorNode_Create(scene, "Separator", "", parent = parent)
}

@(private = "file")
factory_xyplot :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UIXYPlotNode_Create(scene, "Plot", "Signal vs Time", parent = parent)
}

@(private = "file")
factory_listview :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UIListViewNode_Create(scene, "ListView", UI_DEFAULT_OPTIONS[:], parent = parent)
}

@(private = "file")
factory_treeview :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UITreeViewNode_Create(scene, "TreeView", parent = parent)
}

@(private = "file")
factory_unorderedlist :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UIUnorderedListNode_Create(scene, "UnorderedList", parent = parent)
}

@(private = "file")
factory_orderedlist :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UIOrderedListNode_Create(scene, "OrderedList", parent = parent)
}

@(private = "file")
factory_table :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UITableNode_Create(scene, "Table", parent = parent)
}

@(private = "file")
factory_icon :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UIIconNode_Create(scene, "Icon", parent = parent)
}

@(private = "file")
factory_toolbar :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UIToolbarNode_Create(scene, "Toolbar", parent = parent)
}

@(private = "file")
factory_tabcontainer :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return UITabContainerNode_Create(scene, "TabContainer", UI_DEFAULT_TABS[:], parent = parent)
}

@(private = "file")
factory_tilemap :: proc(scene: ^Scene, parent: ^Node) -> ^Node {
	return TileMapNode_Create(scene, "TileMap", parent)
}
