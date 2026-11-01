package engine

import "core:log"
import "core:strings"
import rl "vendor:raylib"

AtlasSpriteNode :: struct {
	using node: Node,
	shininess: f32 `gui:"true" min:"0" max:"1"`, // lit: a glint from lights (#274; its image's _s.png too)
	filePath:   string,
	size:       [2]f32,
	texture:    ^Texture,
	origin:     rl.Vector2,            // pixel origin overriding Node.pivot when not {0, 0} (node_origin.odin)
	tint:       rl.Color `gui:"true"`, // multiplies the texture ({} = white)
	region:     rl.Rectangle `gui:"true"`, // sub-rectangle (x, y, width, height) in texture pixels
}

AtlasSpriteNode_Init :: proc(an: ^AtlasSpriteNode) {
	InitializeNode(an)
	an.render = AtlasSpriteNode_Render
	an.tint = rl.WHITE
	an.onDestroy = AtlasSpriteNode_Destroy
}

AtlasSpriteNode_SetTexture :: proc(an: ^AtlasSpriteNode, tex: ^Texture) {
	if an.texture == tex do return
	if an.texture != nil do ResourceManager_ReleaseTexture(Node_ResourceManager(an), an.texture)
	an.texture = tex
	if an.region.width > 0 && an.region.height > 0 {
		an.size = {an.region.width, an.region.height}
	} else if tex != nil {
		an.size = Texture_Size(tex)
	}
}

AtlasSpriteNode_SetRegion :: proc(an: ^AtlasSpriteNode, region: rl.Rectangle) {
	an.region = region
	if region.width > 0 && region.height > 0 {
		an.size = {region.width, region.height}
	} else if an.texture != nil {
		an.size = Texture_Size(an.texture)
	}
}

AtlasSpriteNode_Destroy :: proc(node: ^Node, gameContext: ^GameContext) {
	an := cast(^AtlasSpriteNode)node
	if an.texture != nil {
		rm := &gameContext.game.resourceManager if gameContext != nil && gameContext.game != nil else Node_ResourceManager(an)
		ResourceManager_ReleaseTexture(rm, an.texture)
		an.texture = nil
	}
}

AtlasSpriteNode_Create :: proc(scene: ^Scene, resource_manager: ^ResourceManager, filePath: string, region: rl.Rectangle = {}) -> ^AtlasSpriteNode {
	an := CreateNode(scene.manager, AtlasSpriteNode)
	AtlasSpriteNode_Init(an)
	an.filePath = strings.clone(filePath, an.allocator)
	if resource_manager != nil && filePath != "" {
		tex, ok := resource_manager.loadTexture(resource_manager, filePath)
		if ok {
			an.texture = tex
			an.size = Texture_Size(tex)
		} else {
			log.error("Failed to load texture from file: ", filePath)
		}
	}
	if region.width > 0 && region.height > 0 {
		AtlasSpriteNode_SetRegion(an, region)
	}
	scene->addNode(an)
	return an
}

AtlasSpriteNode_Render :: proc(node: ^Node, gameContext: ^GameContext, deltaTime: f32) {
	if !rl.IsWindowReady() do return
	an := cast(^AtlasSpriteNode)node
	if an.texture == nil || an.texture.texture.id == 0 do return

	texFull := Texture_Full(an.texture)
	source := texFull
	if an.region.width > 0 && an.region.height > 0 {
		source = {
			texFull.x + an.region.x,
			texFull.y + an.region.y,
			an.region.width,
			an.region.height,
		}
	}

	pos := an.globalPosition
	scl := an.globalScale
	rot := an.globalRotation

	origin := Node_OriginPx(an, an.size)
	tint := an.tint if an.tint != {} else rl.WHITE
	Texture_DrawScaled(an.texture.texture, source, pos, an.size, scl, origin, rot, tint)
}
