package engine

import "base:runtime"
import "core:c"
import "core:log"
import "core:mem"
import os "osx"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"

// ============================================================================
// Asset Manager (loose project files and .rayzr archive packages)
// ============================================================================

// AssetManager is the file layer: it resolves project-relative paths
// through a mounted .rayzr package or the project directory and reads files.
// Loaded GPU/audio resources are cached in one place, the ResourceManager
// (resource_manager.odin), which reads through this layer.
AssetManager :: struct {
	allocator:     mem.Allocator,
	projectDir:    string,
	package_:      ^RayzrPackage,
}

AssetManager_Init :: proc(am: ^AssetManager, allocator := context.allocator) {
	am.allocator = allocator
	am.projectDir = ""
	am.package_ = nil
}

AssetManager_Destroy :: proc(am: ^AssetManager) {
	if am == nil do return
	if am.projectDir != "" {
		delete(am.projectDir, am.allocator)
		am.projectDir = ""
	}

	if am.package_ != nil {
		RayzrPackage_Close(am.package_)
		am.package_ = nil
	}
}

AssetManager_MountPackage :: proc(am: ^AssetManager, pkg: ^RayzrPackage) {
	if am.package_ != nil && am.package_ != pkg {
		RayzrPackage_Close(am.package_)
	}
	am.package_ = pkg
}

AssetManager_SetProjectDir :: proc(am: ^AssetManager, dir: string) {
	if am.projectDir != "" {
		delete(am.projectDir, am.allocator)
	}
	am.projectDir = strings.clone(dir, am.allocator)
}

// ----------------------------------------------------------------------------
// Low-level Data Access (Resolves Package first, then loose disk path)
// ----------------------------------------------------------------------------

AssetManager_ResolveDiskPath :: proc(am: ^AssetManager, relPath: string, allocator := context.temp_allocator) -> string {
	if am.projectDir == "" do return relPath
	res, _ := filepath.join({am.projectDir, relPath}, allocator)
	return res
}

AssetManager_ReadFileBytes :: proc(am: ^AssetManager, relPath: string, allocator := context.allocator) -> ([]byte, bool) {
	data, _, ok := AssetManager_ReadFileBytesFrom(am, relPath, allocator)
	return data, ok
}

// AssetManager_ReadFileBytesFrom also says which mod the file came from
// (its index in mods.list; -1: the game's own): mods' files go over the
// package and the project folder (mods.odin).
AssetManager_ReadFileBytesFrom :: proc(am: ^AssetManager, relPath: string, allocator := context.allocator) -> (bytes: []byte, modIndex: int, found: bool) {
	modIndex = -1
	// 0. A mod's file
	if modPath, idx, modded := Mods_OverridePath(relPath); modded {
		if data, err := os.read_entire_file(modPath, allocator); err == nil do return data, idx, true
	}

	// 1. Try mounted package
	if am.package_ != nil {
		data, ok := RayzrPackage_ReadFile(am.package_, relPath, allocator)
		if ok do return data, -1, true
	}

	// 2. Try disk relative to projectDir or cwd
	resolved := AssetManager_ResolveDiskPath(am, relPath, context.temp_allocator)
	data, err := os.read_entire_file(resolved, allocator)
	if err == nil do return data, -1, true

	// 3. Fallback to direct relative path
	if resolved != relPath {
		dataDirect, errDirect := os.read_entire_file(relPath, allocator)
		if errDirect == nil do return dataDirect, -1, true
	}

	return nil, -1, false
}

// AssetManager_ReadFileStringFrom: AssetManager_ReadFileBytesFrom as text.
AssetManager_ReadFileStringFrom :: proc(am: ^AssetManager, relPath: string, allocator := context.allocator) -> (text: string, modIndex: int, found: bool) {
	bytes, idx, ok := AssetManager_ReadFileBytesFrom(am, relPath, allocator)
	return string(bytes), idx, ok
}

AssetManager_ReadFileString :: proc(am: ^AssetManager, relPath: string, allocator := context.allocator) -> (string, bool) {
	bytes, ok := AssetManager_ReadFileBytes(am, relPath, allocator)
	if !ok do return "", false
	return string(bytes), true
}
