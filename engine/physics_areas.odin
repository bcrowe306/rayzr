package engine

import "core:slice"
import b2 "vendor:box2d"

// ============================================================================
// Area overrides: an Area that changes gravity and damping for the bodies
// inside it - water, low gravity, wind, a planet pulling towards its centre.
// Each fixed step (physics_step.odin), Dynamic Bodies inside get the extra
// force; Character Movers inside use the area's gravity. Areas with a higher
// Priority are applied first; a Replace stops lower ones (Add ones still add
// on top of what's above them).
// ============================================================================

Area_GravityMode :: enum {
	Off,     // the world's gravity
	Add,     // the world's gravity plus the area's (wind, currents)
	Replace, // only the area's (water, low gravity, zero-g)
}

@(private = "file")
area_overrides :: proc(a: ^AreaNode) -> bool {
	return a.gravityMode != .Off || a.dampingOverride
}

// area_gravity: the area's gravity on a body at `p` (towards its centre with
// Gravity Point).
@(private = "file")
area_gravity :: proc(a: ^AreaNode, p: [2]f32) -> [2]f32 {
	if !a.gravityPoint do return a.gravity
	d := a.globalPosition - p
	l := b2.Length(d)
	if l < 1 do return {}
	return d / l * a.gravityStrength
}

// areas_with_overrides: the scene's running areas that override something,
// highest priority first (temp).
@(private = "file")
areas_with_overrides :: proc(scene: ^Scene) -> []^AreaNode {
	out := make([dynamic]^AreaNode, context.temp_allocator)
	if scene == nil || scene.manager == nil do return {}
	for n in scene.manager.nodes {
		if n == nil || n.typeId != AreaNode || !n.enabled || n.pausedNow || n.removing do continue
		a := cast(^AreaNode)n
		if area_overrides(a) && len(a.overlappingNodes) > 0 do append(&out, a)
	}
	slice.stable_sort_by(out[:], proc(x, y: ^AreaNode) -> bool {return x.priority > y.priority})
	return out[:]
}

@(private = "file")
area_holds :: proc(a: ^AreaNode, n: ^Node) -> bool {
	for o in a.overlappingNodes do if o == n do return true
	return false
}

// area_effect: the gravity on `n` at `p` from the areas holding it, and
// which area's damping applies (nil: none).
@(private = "file")
area_effect :: proc(areas: []^AreaNode, n: ^Node, p, worldG: [2]f32) -> (g: [2]f32, inside: bool, damp: ^AreaNode) {
	g = worldG
	replaced := false
	extra: [2]f32
	for a in areas {
		if !area_holds(a, n) do continue
		inside = true
		if a.dampingOverride && damp == nil do damp = a
		switch a.gravityMode {
		case .Off:
		case .Add:
			if !replaced do extra += area_gravity(a, p)
		case .Replace:
			if !replaced {
				g = area_gravity(a, p)
				replaced = true
			}
		}
	}
	g += extra
	return
}

// Area_GravityFor: the gravity a Character Mover gets from the areas it's in
// (inArea false: none overrides it).
Area_GravityFor :: proc(cm: ^CharacterMoverNode, ctx: ^GameContext) -> (g: [2]f32, inArea: bool) {
	if ctx == nil || ctx.game == nil || ctx.scene == nil do return {}, false
	areas := areas_with_overrides(ctx.scene)
	if len(areas) == 0 do return {}, false
	worldG := ctx.game.physicsWorld.gravity
	gg, inside, _ := area_effect(areas, cm, cm.globalPosition, worldG)
	if !inside do return {}, false
	return gg, true
}

// Area_ApplyOverrides: before a step, the Dynamic Bodies inside overriding
// areas get the force that makes their gravity (and damping) the area's.
Area_ApplyOverrides :: proc(scene: ^Scene, ctx: ^GameContext, h: f32) {
	if ctx == nil || ctx.game == nil do return
	areas := areas_with_overrides(scene)
	if len(areas) == 0 do return
	worldG := ctx.game.physicsWorld.gravity
	seen := make(map[^Node]bool, allocator = context.temp_allocator)
	for a in areas {
		for n in a.overlappingNodes {
			if n == nil || n.typeId != DynamicBodyNode || n in seen || !Node_IsAlive(n) do continue
			seen[n] = true
			db := cast(^DynamicBodyNode)n
			if !b2.Body_IsValid(db.bodyId) || !b2.Body_IsEnabled(db.bodyId) do continue
			p := b2.Body_GetWorldCenterOfMass(db.bodyId)
			g, _, damp := area_effect(areas, n, p, worldG)
			m := b2.Body_GetMass(db.bodyId)
			gs := db.gravityScale
			force := (g - worldG) * gs * m
			if damp != nil {
				v := b2.Body_GetLinearVelocity(db.bodyId)
				force -= v * damp.linearDamping * m
				w := b2.Body_GetAngularVelocity(db.bodyId)
				b2.Body_ApplyTorque(db.bodyId, -w * damp.angularDamping * b2.Body_GetRotationalInertia(db.bodyId), true)
			}
			if force != {} do b2.Body_ApplyForceToCenter(db.bodyId, force, true)
		}
	}
}
