package engine


RenderLayer :: enum u8 { // (one byte in every node)
	Layer1,
	Layer2,
	Layer3,
	Layer4,
	Layer5,
	Layer6,
	Layer7,
	Layer8,
}

CollisionLayer :: enum u64 {
	Layer1  = 0,
	Layer2  = 1,
	Layer3  = 2,
	Layer4  = 3,
	Layer5  = 4,
	Layer6  = 5,
	Layer7  = 6,
	Layer8  = 7,
	Layer9  = 8,
	Layer10 = 9,
	Layer11 = 10,
	Layer12 = 11,
	Layer13 = 12,
	Layer14 = 13,
	Layer15 = 14,
	Layer16 = 15,
}

CollisionLayerSet :: bit_set[CollisionLayer; u64]

DEFAULT_COLLISION_CATEGORIES :: CollisionLayerSet{.Layer1}

DEFAULT_COLLISION_MASK :: CollisionLayerSet{
	.Layer1, .Layer2, .Layer3, .Layer4,
	.Layer5, .Layer6, .Layer7, .Layer8,
	.Layer9, .Layer10, .Layer11, .Layer12,
	.Layer13, .Layer14, .Layer15, .Layer16,
}

CollisionLayerSet_ToBits :: proc(set: CollisionLayerSet) -> u64 {
	return transmute(u64)set
}

CollisionLayerSet_FromBits :: proc(bits: u64) -> CollisionLayerSet {
	return transmute(CollisionLayerSet)bits
}

// Light layers (lighting.odin): a light lights, and an occluder blocks, the
// nodes that share one of its layers. Named in Project Settings (Light
// Layers); every node, light and occluder starts on all eight.
Light_Layer :: enum u8 {
	Layer1,
	Layer2,
	Layer3,
	Layer4,
	Layer5,
	Layer6,
	Layer7,
	Layer8,
}

LightLayerSet :: bit_set[Light_Layer; u8]

ALL_LIGHT_LAYERS :: LightLayerSet{.Layer1, .Layer2, .Layer3, .Layer4, .Layer5, .Layer6, .Layer7, .Layer8}
