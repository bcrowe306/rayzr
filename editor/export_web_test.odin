package editor

import "core:strings"
import "core:testing"
import e "../engine"

// #368: the favicon is linked whether or not emcc minified the page.
@(test)
test_web_page_favicon_368 :: proc(t: ^testing.T) {
	cfg := e.ProjectConfig{name = "Coin Hop", icon = "icon.png"}
	pages := [?]string{
		"<!doctype html>\n<html><head>\n<meta charset=\"utf-8\">\n<title>Game</title>\n</head><body></body></html>",
		"<!doctypehtml><html lang=en><head><meta charset=utf-8><title>Game</title><style>a{}</style></head><body></body></html>",
	}
	for page in pages {
		out := web_page(page, &cfg, "game")
		testing.expect(t, strings.contains(out, "<title>Coin Hop</title>"), out)
		link := strings.index(out, "<link rel=\"icon\" href=\"favicon.png\">")
		testing.expect(t, link >= 0 && link < strings.index(out, "</head>"), out)
		testing.expect_value(t, strings.count(out, "rel=\"icon\""), 1)
	}
	// No icon: no link.
	cfg.icon = ""
	testing.expect(t, !strings.contains(web_page(pages[1], &cfg, "game"), "favicon"))
	free_all(context.temp_allocator)
}
