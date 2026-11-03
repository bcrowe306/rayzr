package editor

import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import imgui "lib/imgui"
import rl "vendor:raylib"
import e "../engine"

// ============================================================================
// Node Reference window (#45): a page per node type, the same page the docs
// site builds (scripts/docs/export_site.py, node_page) - its description,
// the hand-written docs/nodes/<Type>.md (what it's for, when to use it, how
// it works, signals, examples, screenshots), its Inspector properties
// (docs/generated/nodes.json) and its Lua methods (engine_api.lua). All
// embedded: offline, and always the installed version's. Screenshots load
// from docs/images (the checkout, or the installed editor's resources).
//
// Opened from a node's menu in the hierarchy (Documentation), the Inspector
// header's ? button, Shift+F1 on the selected node, or Help > Node Reference
// (the index). Links between node pages (`[Area](AreaNode.md)`) open there.
//
// It also shows the editor manual (#45): "editor/<page>" is
// docs/editor/<page>.md, "editor/" (EDITOR_INDEX) the list of them in the
// Editor section of docs/site.json - Help > Editor Manual, a bottom tab's
// right-click > Help. Links between editor and node pages open here too.
// ============================================================================

@(private = "file")
NODES_JSON :: #load("../docs/generated/nodes.json", string)
@(private = "file")
NODE_PAGES := #load_directory("../docs/nodes")
@(private = "file")
EDITOR_PAGES := #load_directory("../docs/editor")
@(private = "file")
SITE_JSON :: #load("../docs/site.json", string)

INDEX_PAGE :: "" // NodeReference_Open(INDEX_PAGE): every node by category
EDITOR_INDEX :: "editor/" // NodeReference_Open(EDITOR_INDEX): the editor manual's pages

// NodeReference_HasEditorPage: docs/editor/<page>.md exists.
NodeReference_HasEditorPage :: proc(page: string) -> bool {return editor_page_text(page) != ""}

// NodeReference_OpenEditor shows an editor manual page by its file name
// ("inspector" = docs/editor/inspector.md; "" = the list).
NodeReference_OpenEditor :: proc(page: string) {
	NodeReference_Open(strings.concatenate({EDITOR_INDEX, page}, context.temp_allocator))
}

@(private = "file")
nodeRef: struct {
	open:     bool,
	page:     string, // a node type, or INDEX_PAGE
	doc:      Md_Doc,
	history:  [dynamic]string,
	textures: map[string]rl.Texture2D, // screenshots by path
	scrollUp: bool,
	modalFrame: i32, // last frame shown over a modal dialog (NodeReference_RenderModal)
}

// NodeReference_Open shows a node type's page ("" = the index).
NodeReference_Open :: proc(typeName: string) {
	if nodeRef.open && nodeRef.page != typeName do append(&nodeRef.history, strings.clone(nodeRef.page))
	node_ref_show(typeName)
	nodeRef.open = true
}

NodeReference_IsOpen :: proc() -> bool {return nodeRef.open}
NodeReference_Page :: proc() -> string {return nodeRef.page}

@(private = "file")
node_ref_show :: proc(typeName: string) {
	// Clone first: a followed link's name points into the doc's arena (#232).
	page := strings.clone(typeName)
	Md_Destroy(&nodeRef.doc)
	delete(nodeRef.page)
	nodeRef.page = page
	nodeRef.doc = Md_Parse(NodeReference_Markdown(page, context.temp_allocator))
	nodeRef.scrollUp = true
}

// --- the page ------------------------------------------------------------------------

@(private = "file")
Node_Doc_Entry :: struct {
	type, name, category, description: string,
	properties:                        json.Array,
}

@(private = "file")
node_ref_entries :: proc() -> (json.Object, []Node_Doc_Entry) {
	val, err := json.parse_string(NODES_JSON, allocator = context.temp_allocator)
	if err != .None do return nil, nil
	root, _ := val.(json.Object)
	list, _ := root["nodes"].(json.Array)
	out := make([dynamic]Node_Doc_Entry, context.temp_allocator)
	for v in list {
		o, _ := v.(json.Object)
		props, _ := o["properties"].(json.Array)
		append(&out, Node_Doc_Entry{
			type        = o["type"].(json.String) or_else "",
			name        = o["name"].(json.String) or_else "",
			category    = o["category"].(json.String) or_else "",
			description = o["description"].(json.String) or_else "",
			properties  = props,
		})
	}
	return root, out[:]
}

// editor_page_text: docs/editor/<page>.md ("" = none).
@(private = "file")
editor_page_text :: proc(page: string) -> string {
	want := fmt.tprintf("%s.md", page)
	for f in EDITOR_PAGES do if filepath.base(f.name) == want do return string(f.data)
	return ""
}

// editor_page_markdown: an editor manual page, or ("") the list of them -
// the docs/editor pages in docs/site.json's Editor section, in its order.
@(private = "file")
editor_page_markdown :: proc(page: string, allocator: mem.Allocator) -> string {
	if page != "" {
		if text := editor_page_text(page); text != "" do return strings.clone(text, allocator)
		return fmt.aprintf("# %s\n\nNo such page in the editor manual.\n", page, allocator = allocator)
	}
	sb := strings.builder_make(allocator)
	strings.write_string(&sb, "# Editor manual\n\nThe editor, part by part: what each one is for, when you use it, every control, and a short walkthrough. Right-click a bottom tab > **Help** for its page.\n\n")
	val, err := json.parse_string(SITE_JSON, allocator = context.temp_allocator)
	root, _ := val.(json.Object)
	sections, _ := root["sections"].(json.Array)
	if err != .None do return strings.to_string(sb)
	for sv in sections {
		sec, _ := sv.(json.Object)
		if (sec["label"].(json.String) or_else "") != "Editor" do continue
		items, _ := sec["items"].(json.Array)
		for iv in items {
			it, _ := iv.(json.Object)
			file := it["file"].(json.String) or_else ""
			if !strings.has_prefix(file, "docs/editor/") do continue
			stem := filepath.stem(filepath.base(file))
			text := editor_page_text(stem)
			title := it["label"].(json.String) or_else ""
			if title == "" && strings.has_prefix(text, "# ") {
				title, _, _ = strings.partition(text[2:], "\n")
			}
			if title == "" do title = stem
			// Its first paragraph after the title, as a one-line description.
			_, _, body := strings.partition(text, "\n\n")
			desc, _, _ := strings.partition(strings.trim_space(body), "\n\n")
			desc, _ = strings.replace_all(desc, "\n", " ", context.temp_allocator)
			fmt.sbprintf(&sb, "- **[%s](%s.md)**: %s\n", strings.trim_space(title), stem, desc)
		}
	}
	return strings.to_string(sb)
}

// node_ref_extra: docs/nodes/<Type>.md ("" = none).
@(private = "file")
node_ref_extra :: proc(typeName: string) -> string {
	want := fmt.tprintf("%s.md", typeName)
	for f in NODE_PAGES do if filepath.base(f.name) == want do return string(f.data)
	return ""
}

// NodeReference_Markdown: a node type's page as markdown ("" = the index).
NodeReference_Markdown :: proc(typeName: string, allocator := context.allocator) -> string {
	if strings.has_prefix(typeName, EDITOR_INDEX) do return editor_page_markdown(typeName[len(EDITOR_INDEX):], allocator)
	context.allocator = context.temp_allocator
	root, entries := node_ref_entries()
	sb := strings.builder_make(allocator)
	if typeName == INDEX_PAGE {
		fmt.sbprintf(&sb, "# Nodes\n\nEvery node type, by category. Add one with **Add Node** (%s); every node also has the Transform properties (position, rotation, scale, layer...).\n", Chord_Text({.A, P}))
		cat := ""
		for en in entries {
			if en.category != cat {
				cat = en.category
				fmt.sbprintf(&sb, "\n## %s\n\n| Node | |\n|---|---|\n", cat)
			}
			fmt.sbprintf(&sb, "| [%s](%s.md) | %s |\n", en.name, en.type, md_cell(en.description))
		}
		return strings.to_string(sb)
	}
	en: Node_Doc_Entry
	for x in entries do if x.type == typeName {en = x; break}
	if en.type == "" {
		fmt.sbprintf(&sb, "# %s\n\nNo page for this node type.\n", typeName)
		return strings.to_string(sb)
	}
	fmt.sbprintf(&sb, "# %s\n\n%s\n\n**Type:** `%s` · **Category:** %s\n\n", en.name, en.description, en.type, en.category)
	if extra := node_ref_extra(en.type); extra != "" {
		strings.write_string(&sb, strings.trim_space(extra))
		strings.write_string(&sb, "\n\n")
	}
	strings.write_string(&sb, "## Properties\n\n")
	if len(en.properties) > 0 {
		node_ref_props(&sb, en.properties)
	} else {
		strings.write_string(&sb, "No properties of its own.\n\n")
	}
	// The Transform every node has: in full on the Node page, linked from
	// the others.
	if common, ok := root["common"].(json.Array); ok && en.type == "Node" {
		strings.write_string(&sb, "### Transform (every node)\n\n")
		node_ref_props(&sb, common)
	} else {
		strings.write_string(&sb, "Plus the [Transform properties](Node.md) every node has (position, rotation, scale, layer, Z index...).\n\n")
	}
	if fns := node_ref_lua(en.type); fns != "" {
		fmt.sbprintf(&sb, "## Lua methods\n\nCall them on the node (`self.node` in its script, or `self.node:get_node(\"path\")`). Every node also has the [Node methods](Node.md).\n\n%s", fns)
	}
	return strings.to_string(sb)
}

@(private = "file")
node_ref_props :: proc(sb: ^strings.Builder, props: json.Array) {
	strings.write_string(sb, "| Property | Type | Default | |\n|---|---|---|---|\n")
	for v in props {
		p, _ := v.(json.Object)
		name := p["name"].(json.String) or_else ""
		kind := p["kind"].(json.String) or_else ""
		doc := p["doc"].(json.String) or_else ""
		if names, ok := p["enum"].(json.Array); ok && len(names) > 0 {
			opts := make([dynamic]string, context.temp_allocator)
			for n in names do append(&opts, n.(json.String) or_else "")
			kind = strings.join(opts[:], " / ")
		}
		if _, isRuntime := p["runtime"]; isRuntime do doc = fmt.tprintf("%s (read while running; not saved)", doc)
		fmt.sbprintf(sb, "| `%s` | %s | `%s` | %s |\n", name, md_cell(kind), md_cell(node_ref_value(p["default"])), md_cell(doc))
	}
	strings.write_string(sb, "\n")
}

@(private = "file")
node_ref_value :: proc(v: json.Value) -> string {
	#partial switch x in v {
	case json.String:  return string(x)
	case json.Boolean: return "true" if x else "false"
	case json.Integer: return fmt.tprint(x)
	case json.Float:   return fmt.tprintf("%g", x)
	case json.Array:
		parts := make([dynamic]string, context.temp_allocator)
		for i in x do append(&parts, node_ref_value(i))
		return strings.join(parts[:], ", ")
	}
	return ""
}

// node_ref_lua: the type's own methods from engine_api.lua - signature, the
// description, parameters and returns, the example.
@(private = "file")
node_ref_lua :: proc(typeName: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	prefix := fmt.tprintf("function %s:", typeName)
	docs := make([dynamic]string, context.temp_allocator)
	for line in strings.split_lines(ENGINE_API_LUA, context.temp_allocator) {
		if strings.has_prefix(line, "---") {
			append(&docs, line[3:])
			continue
		}
		if strings.has_prefix(line, prefix) {
			sig := strings.trim_suffix(strings.trim_space(line[len(prefix):]), " end")
			fmt.sbprintf(&sb, "### `%s`\n\n", sig)
			params := make([dynamic]string, context.temp_allocator)
			returns := make([dynamic]string, context.temp_allocator)
			for d in docs {
				switch {
				case strings.has_prefix(d, "@param"):
					f := strings.fields(d[len("@param"):], context.temp_allocator)
					if len(f) >= 2 do append(&params, fmt.tprintf("- `%s` (%s)%s", f[0], f[1], node_ref_rest(f[2:])))
				case strings.has_prefix(d, "@return"):
					f := strings.fields(d[len("@return"):], context.temp_allocator)
					if len(f) >= 1 do append(&returns, fmt.tprintf("- %s%s", f[0], node_ref_rest(f[1:])))
				case strings.has_prefix(d, "@") || strings.has_prefix(d, "|"):
				case:
					strings.write_string(&sb, d)
					strings.write_byte(&sb, '\n')
				}
			}
			if len(params) > 0 do fmt.sbprintf(&sb, "\n**Parameters**\n\n%s\n", strings.join(params[:], "\n", context.temp_allocator))
			if len(returns) > 0 do fmt.sbprintf(&sb, "\n**Returns**\n\n%s\n", strings.join(returns[:], "\n", context.temp_allocator))
			strings.write_string(&sb, "\n")
		}
		clear(&docs)
	}
	return strings.to_string(sb)
}

@(private = "file")
node_ref_rest :: proc(words: []string) -> string {
	if len(words) == 0 do return ""
	return strings.concatenate({": ", strings.join(words, " ", context.temp_allocator)}, context.temp_allocator)
}

// md_cell: text safe inside a table cell.
@(private = "file")
md_cell :: proc(s: string) -> string {
	t, _ := strings.replace_all(s, "|", "\\|", context.temp_allocator)
	t, _ = strings.replace_all(t, "\n", " ", context.temp_allocator)
	return t
}

// --- the window ----------------------------------------------------------------------

// node_ref_image: a screenshot, relative to docs/nodes/ (cached).
@(private = "file")
node_ref_image :: proc(url: string) -> ^rl.Texture2D {
	if strings.contains(url, "://") do return nil
	joined, _ := filepath.join({"docs", "nodes", url}, context.temp_allocator)
	rel, _ := filepath.clean(joined, context.temp_allocator)
	if rel in nodeRef.textures do return &nodeRef.textures[rel]
	tex: rl.Texture2D
	if full := Resource_Path(rel); os.exists(full) do tex = rl.LoadTexture(strings.clone_to_cstring(full, context.temp_allocator))
	if nodeRef.textures == nil do nodeRef.textures = make(map[string]rl.Texture2D)
	nodeRef.textures[strings.clone(rel)] = tex // (id 0: missing, not retried)
	return &nodeRef.textures[rel]
}

NodeReference_Render :: proc(state: ^EditorState) {
	if !nodeRef.open do return
	if nodeRef.modalFrame > 0 && imgui.GetFrameCount() - nodeRef.modalFrame <= 1 do return // shown over a modal dialog instead
	imgui.SetNextWindowSize({620, 720}, .FirstUseEver)
	visible := imgui.Begin(fmt.ctprintf("%s  Node Reference###NodeReference", ICON_FA_BOOK), &nodeRef.open)
	defer imgui.End()
	{
		// (The title bar's close button, for drives.)
		wp, ws := imgui.GetWindowPos(), imgui.GetWindowSize()
		st := imgui.GetStyle()
		fs := imgui.GetFontSize()
		x := wp.x + ws.x - st.FramePadding.x - fs
		Drive_ItemRect("noderef.close", {x, wp.y + st.FramePadding.y}, {x + fs, wp.y + st.FramePadding.y + fs})
	}
	if !visible do return
	// (No PanelHelp_Mark: Help > Help for <panel> stays the panel you read about.)
	Drive_Window("noderef") // (annotated docs screenshots)
	node_ref_contents()
}

// NodeReference_RenderModal: the viewer as a popup over the modal dialog
// being drawn (Settings), which blocks other windows; called inside it.
// Returns false once closed (its close button, Esc).
NodeReference_RenderModal :: proc(state: ^EditorState) -> bool {
	if !nodeRef.open do return false
	title := fmt.ctprintf("%s  Node Reference###NodeReferenceModal", ICON_FA_BOOK)
	if !imgui.IsPopupOpen(title) do imgui.OpenPopup(title)
	io := imgui.GetIO()
	imgui.SetNextWindowSize({620, min(720, io.DisplaySize.y - 80)}, .Appearing)
	imgui.SetNextWindowPos({io.DisplaySize.x * 0.5, io.DisplaySize.y * 0.5}, .Appearing, {0.5, 0.5})
	if !imgui.BeginPopupModal(title, &nodeRef.open, {}) do return false
	nodeRef.modalFrame = imgui.GetFrameCount()
	{
		// (The title bar's close button, for drives.)
		wp, ws := imgui.GetWindowPos(), imgui.GetWindowSize()
		st := imgui.GetStyle()
		fs := imgui.GetFontSize()
		x := wp.x + ws.x - st.FramePadding.x - fs
		Drive_ItemRect("noderef.close", {x, wp.y + st.FramePadding.y}, {x + fs, wp.y + st.FramePadding.y + fs})
	}
	if imgui.IsKeyPressed(.Escape) {
		nodeRef.open = false
		imgui.CloseCurrentPopup()
	}
	node_ref_contents()
	imgui.EndPopup()
	return nodeRef.open
}

// node_ref_contents: the viewer's toolbar and page (window or popup).
@(private = "file")
node_ref_contents :: proc() {
	if UI_IconButton(ICON_FA_ARROW_LEFT, "noderef.back", "Back", size = 26) && len(nodeRef.history) > 0 {
		prev := pop(&nodeRef.history)
		node_ref_show(prev)
		delete(prev)
	}
	imgui.SameLine(0, 4)
	if UI_IconButton(ICON_FA_LIST, "noderef.index", "Every node", size = 26) do NodeReference_Open(INDEX_PAGE)
	imgui.SameLine(0, 8)
	imgui.AlignTextToFramePadding()
	UI_DimText(nodeRef.page if nodeRef.page != "" else "All nodes")
	if strings.has_prefix(nodeRef.page, EDITOR_INDEX) {
		imgui.SameLine(0, 12)
		if UI_Button(fmt.tprintf("%s  Manual", ICON_FA_LIST), "noderef.editor-index") do NodeReference_OpenEditor("")
		UI_Tooltip("Every page of the editor manual")
	}
	imgui.Separator()
	if imgui.BeginChild("##noderef_body", {0, 0}) {
		if nodeRef.scrollUp {
			imgui.SetScrollY(0)
			nodeRef.scrollUp = false
		}
		prevLoader := mdImageLoader
		mdImageLoader = node_ref_image
		clicked := Md_Draw(&nodeRef.doc)
		mdImageLoader = prevLoader
		Drive_Item("noderef.body")
		node_ref_follow(clicked)
	}
	imgui.EndChild()
}

// node_ref_follow: a clicked link - another node's page, or a web page.
@(private = "file")
node_ref_follow :: proc(url: string) {
	if url == "" do return
	if strings.has_prefix(url, "http://") || strings.has_prefix(url, "https://") {
		rl.OpenURL(strings.clone_to_cstring(url, context.temp_allocator))
		return
	}
	path, _, _ := strings.partition(url, "#")
	if strings.has_suffix(path, ".md") {
		name := filepath.stem(filepath.base(path))
		for info in e.NODE_TYPES do if info.name == name {
			NodeReference_Open(name)
			return
		}
		// An editor manual page (from an editor page, or ../editor/x.md).
		fromEditor := strings.has_prefix(nodeRef.page, EDITOR_INDEX)
		if (fromEditor || strings.contains(path, "editor/")) && editor_page_text(name) != "" {
			NodeReference_OpenEditor(name)
			return
		}
	}
}

NodeReference_Shutdown :: proc() {
	Md_Destroy(&nodeRef.doc)
	delete(nodeRef.page)
	for h in nodeRef.history do delete(h)
	delete(nodeRef.history)
	for k, t in nodeRef.textures {
		if t.id != 0 do rl.UnloadTexture(t)
		delete(k)
	}
	delete(nodeRef.textures)
	nodeRef = {}
}
