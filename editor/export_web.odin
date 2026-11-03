package editor

import "core:fmt"
import "core:net"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"
import e "../engine"

// ============================================================================
// Web export (engine/docs/web_export.md): the prebuilt web runner
// (runners/web/: index.html, index.js, index.wasm, odin.js - built once by
// scripts/build_web_runner.sh) copied next to game.rayzr, the UI font and
// the project's icon as the page's favicon; the page title is the game's.
// The folder is a static site: upload it (itch.io: zip it as an HTML game)
// or open it with Game > Open Web Export in Browser - browsers don't run
// wasm from file:// pages, so the editor serves the folder on localhost.
// ============================================================================

WEB_RUNNER_FILES :: [?]string{"index.html", "index.js", "index.wasm", "odin.js"}

export_web :: proc(state: ^EditorState, cfg: ^e.ProjectConfig, runner, rayzr, dir, name: string) -> (string, bool) {
	src := filepath.dir(runner, context.temp_allocator)
	files := WEB_RUNNER_FILES
	for f in files {
		from, _ := filepath.join({src, f}, context.temp_allocator)
		to, _ := filepath.join({dir, f}, context.temp_allocator)
		if f == "index.html" {
			data, err := os.read_entire_file(from, context.temp_allocator)
			if err != nil {
				Editor_Log(state, .Error, "The web runner has no index.html (%s)", from)
				return "", false
			}
			_ = os.write_entire_file(to, transmute([]u8)web_page(string(data), cfg, name))
			continue
		}
		if err := os.copy_file(to, from); err != nil {
			Editor_Log(state, .Error, "Could not copy %s: %v", from, err)
			return "", false
		}
	}
	dstRayzr, _ := filepath.join({dir, "game.rayzr"}, context.temp_allocator)
	if err := os.copy_file(dstRayzr, rayzr); err != nil {
		Editor_Log(state, .Error, "Could not write %s: %v", dstRayzr, err)
		return "", false
	}
	if font := runner_font(runner); font != "" {
		fonts, _ := filepath.join({dir, "fonts"}, context.temp_allocator)
		_ = os.make_directory_all(fonts)
		dst, _ := filepath.join({fonts, RUNNER_FONT}, context.temp_allocator)
		_ = os.copy_file(dst, font)
	}
	if cfg.icon != "" {
		icon, _ := filepath.join({state.projectPath, cfg.icon}, context.temp_allocator)
		dst, _ := filepath.join({dir, "favicon.png"}, context.temp_allocator)
		_ = os.copy_file(dst, icon)
	}
	if state.webExportDir != "" do delete(state.webExportDir)
	state.webExportDir = strings.clone(dir)
	return strings.clone(dir, context.temp_allocator), true
}

// web_page: the runner's page with the game's title (and favicon). The
// favicon link goes before </head>: emcc minifies the page (<meta
// charset=utf-8>, no quotes), so no attribute spelling is matched (#368).
web_page :: proc(html: string, cfg: ^e.ProjectConfig, name: string) -> string {
	title := cfg.windowTitle if cfg.windowTitle != "" else (cfg.name if cfg.name != "" else name)
	esc, _ := strings.replace_all(title, "<", "&lt;", context.temp_allocator)
	out, _ := strings.replace(html, "<title>Game</title>", fmt.tprintf("<title>%s</title>", esc), 1, context.temp_allocator)
	if cfg.icon != "" {
		LINK :: "<link rel=\"icon\" href=\"favicon.png\">"
		if i := strings.index(out, "</head>"); i >= 0 {
			out = strings.concatenate({out[:i], LINK, out[i:]}, context.temp_allocator)
		} else {
			out = strings.concatenate({LINK, out}, context.temp_allocator)
		}
	}
	return out
}

// --- the local preview server -------------------------------------------------------

@(private = "file")
webServer: struct {
	thread: ^thread.Thread,
	socket: net.TCP_Socket,
	root:   string, // (heap)
	port:   int,
	lock:   sync.Mutex,
	running: bool,
}

// WebServer_Serve serves a folder on 127.0.0.1 (one server; a new folder
// replaces the old one) and returns its URL.
WebServer_Serve :: proc(root: string) -> (string, bool) {
	sync.mutex_lock(&webServer.lock)
	if webServer.root != "" do delete(webServer.root)
	webServer.root = strings.clone(root)
	sync.mutex_unlock(&webServer.lock)
	if !webServer.running {
		for port in 8765 ..< 8800 {
			sock, err := net.listen_tcp({net.IP4_Loopback, port})
			if err != nil do continue
			webServer.socket, webServer.port = sock, port
			webServer.running = true
			webServer.thread = thread.create_and_start(web_server_loop)
			break
		}
		if !webServer.running do return "", false
	}
	return fmt.tprintf("http://127.0.0.1:%d/index.html", webServer.port), true
}

// WebServer_Stop closes the server (editor exit).
WebServer_Stop :: proc() {
	if !webServer.running do return
	webServer.running = false
	// Wake the blocked accept with a connection of our own, then close.
	if c, err := net.dial_tcp(net.Endpoint{net.IP4_Loopback, webServer.port}); err == nil do net.close(c)
	thread.join(webServer.thread)
	net.close(webServer.socket)
	thread.destroy(webServer.thread)
	delete(webServer.root)
	webServer = {}
}

@(private = "file")
web_server_loop :: proc() {
	for webServer.running {
		client, _, err := net.accept_tcp(webServer.socket)
		if err != nil do continue
		web_serve_one(client)
		net.close(client)
		free_all(context.temp_allocator)
	}
}

@(private = "file")
web_serve_one :: proc(client: net.TCP_Socket) {
	buf: [4096]u8
	n, err := net.recv_tcp(client, buf[:])
	if err != nil || n <= 0 do return
	req := string(buf[:n])
	line := req[:strings.index_byte(req, '\n')] if strings.index_byte(req, '\n') >= 0 else req
	parts := strings.fields(line, context.temp_allocator)
	if len(parts) < 2 || parts[0] != "GET" do return
	path := parts[1]
	if i := strings.index_byte(path, '?'); i >= 0 do path = path[:i]
	if path == "/" do path = "/index.html"
	sync.mutex_lock(&webServer.lock)
	root := strings.clone(webServer.root, context.temp_allocator)
	sync.mutex_unlock(&webServer.lock)
	body: []u8
	status := "200 OK"
	if strings.contains(path, "..") {
		status = "403 Forbidden"
	} else {
		full, _ := filepath.join({root, path[1:]}, context.temp_allocator)
		data, rerr := os.read_entire_file(full, context.temp_allocator)
		if rerr != nil do status = "404 Not Found"
		else do body = data
	}
	head := fmt.tprintf("HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n", status, web_mime(path), len(body))
	_, _ = net.send_tcp(client, transmute([]u8)head)
	for off := 0; off < len(body); {
		sent, serr := net.send_tcp(client, body[off:])
		if serr != nil || sent <= 0 do break
		off += sent
	}
}

@(private = "file")
web_mime :: proc(path: string) -> string {
	switch strings.to_lower(filepath.ext(path), context.temp_allocator) {
	case ".html": return "text/html; charset=utf-8"
	case ".js": return "text/javascript"
	case ".wasm": return "application/wasm"
	case ".png": return "image/png"
	case ".ttf": return "font/ttf"
	case ".json": return "application/json"
	}
	return "application/octet-stream"
}

// Editor_OpenWebExport serves the last web export and opens it in the
// browser.
Editor_OpenWebExport :: proc(state: ^EditorState) {
	page, _ := filepath.join({state.webExportDir, "index.html"}, context.temp_allocator)
	if state.webExportDir == "" || !os.is_file(page) {
		Editor_Log(state, .Warn, "Export a Web preset first (Project Settings > Export)")
		return
	}
	url, ok := WebServer_Serve(state.webExportDir)
	if !ok {
		Editor_Log(state, .Error, "Could not start the local web server (ports 8765-8799 busy?)")
		return
	}
	Editor_Log(state, .Info, "Serving %s at %s", state.webExportDir, url)
	if GlobalDrive.scriptPath == "" do Editor_OpenExternally(state, url) // (test drives capture it headless instead)
}
