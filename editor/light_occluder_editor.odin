package editor

import "core:fmt"
import "core:strings"
import e "../engine"
import rl "vendor:raylib"

// ============================================================================
// Make Light Occluder from Sprite (the Scene panel's right-click menu): a
// Light Occluder child of a Sprite (Texture) or Atlas Sprite, its shapes
// traced from the image's opaque pixels (engine/sprite_outline.odin) - a
// tree or a rock casts the shadow of its silhouette.
// ============================================================================

// Editor_CanMakeOccluder: the node is a sprite with an image.
Editor_CanMakeOccluder :: proc(node: ^e.Node) -> bool {
	if node == nil do return false
	switch node.typeId {
	case e.TextureNode: return (cast(^e.TextureNode)node).filePath != "" && !e.Viewport_IsPath((cast(^e.TextureNode)node).filePath)
	case e.AtlasSpriteNode: return (cast(^e.AtlasSpriteNode)node).filePath != ""
	}
	return false
}

// Editor_MakeOccluderFromSprite adds the Light Occluder (one undo step);
// nil when nothing opaque was found.
Editor_MakeOccluderFromSprite :: proc(state: ^EditorState, node: ^e.Node) -> ^e.LightOccluderNode {
	if state.activeScene == nil || !Editor_CanMakeOccluder(node) do return nil
	rel: string
	size: [2]f32
	region: rl.Rectangle
	switch node.typeId {
	case e.TextureNode:
		tn := cast(^e.TextureNode)node
		rel, size = tn.filePath, tn.size
	case e.AtlasSpriteNode:
		an := cast(^e.AtlasSpriteNode)node
		rel, size, region = an.filePath, an.size, an.region
	}
	path := e.Project_ResolveAssetPath(&state.game.gameContext, rel)
	img := rl.LoadImage(strings.clone_to_cstring(path, context.temp_allocator))
	if img.data == nil {
		Editor_Log(state, .Error, "Make Light Occluder: couldn't read %s", rel)
		return nil
	}
	defer rl.UnloadImage(img)
	if region.width <= 0 || region.height <= 0 do region = {0, 0, f32(img.width), f32(img.height)}
	if size == {} do size = {region.width, region.height}
	origin := e.Node_OriginPx(node, size)
	shapes := make([dynamic]e.PhysicsShape, context.temp_allocator)
	n := e.Occluder_ShapesFromImage(img, region, size, origin, &shapes)
	if n == 0 {
		Editor_Log(state, .Warn, "Make Light Occluder: %s has no opaque area to trace", node.name)
		return nil
	}
	Editor_RecordUndo(state, "Make light occluder")
	o := e.LightOccluderNode_Create(state.activeScene, "Occluder", node)
	o.gameContext = &state.game.gameContext
	o.name = strings.clone(Editor_UniqueChildName(state, node, "Occluder", o), o.allocator)
	clear(&o.shapes)
	for s in shapes do append(&o.shapes, s)
	e.ProcessNodeQueues(state.activeScene.manager, &state.game.gameContext)
	e.Node_SetGlobalPositions(state.activeScene.manager, state.activeScene.rootNode)
	state.selectedNode = o
	Editor_Log(state, .Info, "Made a Light Occluder from %s (%d shape%s)", node.name, n, "" if n == 1 else "s")
	return o
}

// occluder_menu_tip: the menu item's tooltip.
occluder_menu_tip :: proc() -> string {
	return fmt.tprintf("A Light Occluder child traced from the image's opaque pixels: lights cast its silhouette's shadow (2D lighting)")
}
