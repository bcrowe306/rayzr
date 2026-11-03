#!/usr/bin/env python3
"""Builds the New Project templates (templates/<id>/) from the level maps,
scripts and art below (TODO E.2; editor/project_templates.odin lists them).

    python3 scripts/templates/make_templates.py            # all
    python3 scripts/templates/make_templates.py platformer # one

Each template is a complete project folder: project.json, scenes/, scripts/,
textures/ (Kenney CC0 art from assets/kenney/), a README.md and
template.json (name, description, icon, order). Levels are drawn as text
maps here and turned into TileMap data / nodes, so they're easy to change:
edit, run this, open the template in the editor.
"""
import json
import os
import shutil
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
KENNEY = os.path.join(ROOT, "assets", "kenney")
OUT = os.path.join(ROOT, "templates")
SCRIPTS = os.path.join(os.path.dirname(__file__), "scripts")


# --- helpers -------------------------------------------------------------------

def rle(cells):
    """Row-major tile indices -> TileMap "data" ([[count, tile], ...])."""
    out = []
    for t in cells:
        if out and out[-1][1] == t:
            out[-1][0] += 1
        else:
            out.append([1, t])
    return out


def tilemap(name, tileset, tile, grid, solid=False, layer=1, z=0, pos=(0, 0)):
    h = len(grid)
    w = len(grid[0])
    cells = [grid[r][c] for r in range(h) for c in range(w)]
    return {
        "type": "TileMapNode", "name": name, "position": list(pos), "layer": layer, "z_index": z,
        "tilemap": {"tileset": tileset, "tile_size": [tile, tile], "map_size": [w, h], "data": rle(cells)},
        "properties": {"solid": solid},
    }


def sprite(name, sheet, grid, anims, default=None, pos=(0, 0), pivot=(0.5, 0.5), layer=2, z=0, fps=8):
    """An AnimationPlayerNode: anims = {name: ([cells], fps, loop)}."""
    first = default or next(iter(anims))
    return {
        "type": "AnimationPlayerNode", "name": name, "position": list(pos), "pivot": list(pivot),
        "layer": layer, "z_index": z, "fps": fps, "animation": first, "default_animation": first,
        "animations": [
            {"name": n, "loop": loop, "fps": f, "sheet": sheet, "grid": list(grid), "cells": cells,
             "start": 0, "end": len(cells) - 1}
            for n, (cells, f, loop) in anims.items()
        ],
        "properties": {"autoplay": True},
    }


PIXEL_FONT = "fonts/kenney_pixel.ttf"  # Kenney Pixel (CC0): crisp at 16 / 32 px


def text(name, value, pos, size=16, align="Left", color="#ffffffff", layer=7, pivot=(0, 0)):
    return {"type": "TextNode", "name": name, "position": list(pos), "pivot": list(pivot), "layer": layer,
            "properties": {"text": value, "font": PIXEL_FONT, "fontSize": size, "align": align, "color": color}}


def action(name, *bindings):
    out = []
    for b in bindings:
        if b.startswith("pad:"):
            out.append({"button": b[4:]})
        elif b.startswith("axis:"):
            axis, sign = b[5:].split(":")
            out.append({"axis": axis, "positive": sign == "+", "deadzone": 0.3})
        elif b.startswith("mouse:"):
            out.append({"mouse": b[6:]})
        else:
            out.append({"key": b})
    return {"name": name, "bindings": out}


MOVE_ACTIONS = [
    action("move_left", "A", "LEFT", "pad:LEFT_FACE_LEFT", "axis:LEFT_X:-"),
    action("move_right", "D", "RIGHT", "pad:LEFT_FACE_RIGHT", "axis:LEFT_X:+"),
    action("move_up", "W", "UP", "pad:LEFT_FACE_UP", "axis:LEFT_Y:-"),
    action("move_down", "S", "DOWN", "pad:LEFT_FACE_DOWN", "axis:LEFT_Y:+"),
]


def project(name, scenes, actions, virtual=(320, 180), gravity=(0, 900), pixel=True, globals_=None):
    p = {
        "name": name, "version": "0.1.0", "initial_scene": scenes[0],
        "window": {"title": name, "width": 1280, "height": 720,
                   "virtual_width": virtual[0], "virtual_height": virtual[1], "target_fps": 60},
        "video": {"fullscreen": False, "vsync": True, "resizable": True, "msaa": False, "high_dpi": False,
                  "sharp_scaling": pixel, "integer_scaling": pixel, "pixel_snap": pixel, "smooth_camera": pixel},
        "audio": {"master_volume": 1, "music_volume": 1, "sfx_volume": 1},
        "physics": {"gravity": list(gravity), "debug_draw": False},
        "input": {"actions": actions},
        "scenes": scenes,
    }
    if globals_:
        p["globals"] = globals_
    return p


def scene(name, children, background=(0, 0, 0, 255)):
    return {"name": name, "background": list(background),
            "root": {"type": "Node", "name": "root", "children": children}}


def with_touch(sc, size, stick=("move_left", "move_right", "move_up", "move_down"), buttons=(("jump", "A"),),
               pause=None):
    """On-screen controls for phones (#276): a floating joystick in the bottom-left
    half, buttons bottom right (and a pause button top right) - Screen Layers
    added to a scene. They show once the device is touched. size: the virtual
    resolution (the controls are sized for it)."""
    vw, vh = size
    k = vh / 720
    kids = sc["root"]["children"]
    if stick:  # (None: no joystick - a game played by tapping)
        left, right, up, down = stick
        kids.append({"type": "ScreenLayerNode", "name": "TouchLeft", "properties": {"anchor": "BottomLeft"}, "children": [
            {"type": "TouchJoystickNode", "name": "TouchStick", "position": [vw * 0.25, -vh * 0.3],
             "properties": {"radius": 70 * k, "knobRadius": 30 * k, "floating": True, "area": [vw * 0.5, vh * 0.6],
                            "actionLeft": left, "actionRight": right, "actionUp": up, "actionDown": down}}]})
    places = [(-110, -110), (-240, -80), (-110, -240), (-240, -210)]
    if buttons:
        kids.append({"type": "ScreenLayerNode", "name": "TouchRight", "properties": {"anchor": "BottomRight"}, "children": [
            {"type": "TouchButtonNode", "name": "Touch" + act.split(",")[0].title().replace("_", ""), "position": [x * k, y * k],
             "properties": {"radius": 52 * k, "action": act, "label": lab, "fontSize": max(36 * k, 12)}}
            for (act, lab), (x, y) in zip(buttons, places)]})
    if pause:
        kids.append({"type": "ScreenLayerNode", "name": "TouchTop", "properties": {"anchor": "TopRight"}, "children": [
            {"type": "TouchButtonNode", "name": "TouchPause", "position": [-60 * k, 60 * k],
             "properties": {"radius": 34 * k, "action": pause, "label": "II", "fontSize": max(24 * k, 8)}}]})
    return sc


def grid_of(rows, width=None):
    width = width or max(len(r) for r in rows)
    for i, r in enumerate(rows):
        assert len(r) <= width, f"row {i} is {len(r)} wide (max {width})"
    return [r.ljust(width, ".") for r in rows]


# --- game screens (#329) ---------------------------------------------------------
# The templates that are small complete games share a title screen (Play,
# the start Level, Settings with the volume, Quit), a pause menu and a
# result screen (a win or a game over), all Text nodes run by
# scripts/common/menu.lua, and the global Game (scripts/common/game.lua):
# the run (level, score, lives) and the save data (settings, progress).

PIXEL_STYLE = {"size": (320, 180), "big": 32, "small": 16, "step": 18, "item_w": 170, "item_h": 16}
HD_STYLE = {"size": (1280, 720), "big": 96, "small": 48, "step": 64, "item_w": 640, "item_h": 56}


def menu_text(name, value, pos, st, color, size=None, item=False):
    n = text(name, value, pos, size=size or st["small"], align="Center", color=color, pivot=(0.5, 0.5))
    if item:
        n["tags"] = ["item"]
    return n


def menu(name, kind, children, st, selected, visible=True, pause=False):
    n = {"type": "Node", "name": name, "layer": 7,
         "script": {"path": "scripts/menu.lua", "properties": {"kind": kind, "item_width": st["item_w"],
                                                                "item_height": st["item_h"], "selected": selected}},
         "children": children}
    if not visible:
        n["visible"] = False
    if pause:
        n["pause_mode"] = "always"
    return n


def title_scene(game_name, st, color, selected, background, decor=(), level_word="Level"):
    """The title screen: the name, the best score, the menu; the settings."""
    w, h = st["size"]
    k, step = h / 180, st["step"]
    y0 = 88 * k
    items = [("Play", "Play"), ("Level", level_word), ("Settings", "Settings"), ("Quit", "Quit")]
    main = menu("Menu", "title", [
        menu_text("Title", game_name, (w / 2, 36 * k), st, color, size=st["big"]),
        menu_text("Best", "", (w / 2, 62 * k), st, color),
    ] + [menu_text(n, l, (w / 2, y0 + i * step), st, color, item=True) for i, (n, l) in enumerate(items)], st, selected)
    settings = menu("SettingsMenu", "settings", [
        menu_text("Heading", "Settings", (w / 2, 50 * k), st, color, size=st["big"]),
        menu_text("Volume", "Volume", (w / 2, 96 * k), st, color, item=True),
        menu_text("Back", "Back", (w / 2, 96 * k + step), st, color, item=True),
    ], st, selected, visible=False)
    camera = {"type": "CameraNode", "name": "Camera", "position": [w / 2, h / 2], "properties": {"isCurrent": True}}
    return scene("title", [camera] + list(decor) + [main, settings], background=background)


def result_scene(st, color, selected, background, decor=()):
    """After a win or a game over: the score, the best, Again / Title."""
    w, h = st["size"]
    k, step = h / 180, st["step"]
    camera = {"type": "CameraNode", "name": "Camera", "position": [w / 2, h / 2], "properties": {"isCurrent": True}}
    return scene("result", [camera] + list(decor) + [menu("Menu", "result", [
        menu_text("Heading", "", (w / 2, 46 * k), st, color, size=st["big"]),
        menu_text("Score", "", (w / 2, 78 * k), st, color),
        menu_text("Best", "", (w / 2, 78 * k + step), st, color),
        menu_text("Again", "Play again", (w / 2, 124 * k), st, color, item=True),
        menu_text("Title", "Title screen", (w / 2, 124 * k + step), st, color, item=True),
    ], st, selected)], background=background)


def pause_menu(st, selected, shade="#14141ec8", color="#ffffffff"):
    """The pause menu: Esc / P / Start (or the touch II button) opens it."""
    w, h = st["size"]
    k, step = h / 180, st["step"]
    return menu("PauseMenu", "pause", [
        {"type": "UIContainerNode", "name": "Shade", "layer": 7, "position": [0, 0],
         "properties": {"size": [w, h], "drawBackground": True, "drawBorder": False, "showHeader": False,
                        "backgroundColor": shade}},
        menu_text("Heading", "Paused", (w / 2, 46 * k), st, color, size=st["big"]),
        menu_text("Resume", "Resume", (w / 2, 84 * k), st, color, item=True),
        menu_text("Restart", "Restart level", (w / 2, 84 * k + step), st, color, item=True),
        menu_text("Title", "Title screen", (w / 2, 84 * k + 2 * step), st, color, item=True),
    ], st, selected, visible=False, pause=True)


GAME_ACTIONS = [action("confirm", "ENTER", "KP_ENTER", "SPACE", "pad:RIGHT_FACE_DOWN"),
                action("pause", "ESCAPE", "P", "pad:MIDDLE_RIGHT")]
GAME_GLOBALS = [{"name": "Game", "script": "scripts/game.lua"}]


def game_scripts(t, levels, lives=3, score_name="Score", lower_is_better=False, level_word="Level"):
    """scripts/game.lua (the global Game, with this game's levels) and menu.lua."""
    cfg = "\n".join([
        "-- This game (make_templates.py writes it): its levels, in order; the lives a",
        "-- run starts with; what the score counts; whether a lower result is better;",
        "-- what a level is called.",
        "Game.LEVELS = { " + ", ".join(f'"{lv}"' for lv in levels) + " }",
        f"Game.LIVES = {lives if lives else 'nil'}",
        f'Game.SCORE_NAME = "{score_name}"',
        f"Game.LOWER_IS_BETTER = {'true' if lower_is_better else 'false'}",
        f'Game.LEVEL_WORD = "{level_word}"',
    ])
    with open(os.path.join(SCRIPTS, "common", "game.lua")) as f:
        t.write("scripts/game.lua", f.read().replace("--$CONFIG$", cfg))
    t.script("menu", src="common")


class Template:
    def __init__(self, tid, name, description, icon, order):
        self.id = tid
        self.dir = os.path.join(OUT, tid)
        self.meta = {"name": name, "description": description, "icon": icon, "order": order}

    def begin(self):
        # (preview.png is made by test_templates.py --previews: kept.)
        pv = os.path.join(self.dir, "preview.png")
        preview = open(pv, "rb").read() if os.path.isfile(pv) else None
        if os.path.isdir(self.dir):
            shutil.rmtree(self.dir)
        if preview:
            os.makedirs(self.dir)
            open(pv, "wb").write(preview)
        for sub in ("scenes", "scripts", "textures", "audio", "components"):
            os.makedirs(os.path.join(self.dir, sub), exist_ok=True)
        self.write("template.json", json.dumps(self.meta, indent=2) + "\n")
        self.art("fonts/kenney_pixel.ttf", PIXEL_FONT)

    def write(self, rel, data):
        p = os.path.join(self.dir, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(data)

    def json(self, rel, obj):
        self.write(rel, json.dumps(obj, indent=1) + "\n")

    def art(self, src, rel):
        dst = os.path.join(self.dir, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(os.path.join(KENNEY, src), dst)

    def script(self, name, rel=None, src=None):
        """scripts/<name>.lua from scripts/templates/scripts/<template>/<name>.lua"""
        with open(os.path.join(SCRIPTS, src or self.id, name + ".lua")) as f:
            self.write(rel or f"scripts/{name}.lua", f.read())

    def license(self, *packs):
        lines = ["Art and font: Kenney (www.kenney.nl), Creative Commons Zero (CC0) - free for any",
                 "use, no attribution required. Packs: " + ", ".join(packs + ("Kenney Fonts",)) + ".", ""]
        self.write("textures/LICENSE-ART.txt", "\n".join(lines))


# --- platformer ------------------------------------------------------------------

PLATFORMER_LEVEL = [
    "............................................................",
    "............................................................",
    "............................................................",
    "...........................ooo..............................",
    "..........................=====..............ooo............",
    "................ooo............................===..........",
    "...............=====....................###.............D..",
    "......o.o..............................#####..........######",
    ".P.................e........^^......########....e....#######",
    "################################..##########################",
    "################################..##########################",
    "################################..##########################",
]


def _level2():
    """Level 2 (built here: gaps a jump clears - 2 tiles; steps of 2 tiles)."""
    W, H = 68, 11
    g = [["."] * W for _ in range(H)]

    def put(c, r, ch):
        g[r][c] = ch

    for c in range(W):  # ground (rows 8-10), two pits
        if c not in range(10, 12) and c not in range(28, 30):
            for r in range(8, H):
                put(c, r, "#")
    for c in range(49, 54):  # a block to climb (2 tiles)
        put(c, 6, "#"); put(c, 7, "#")
    for c in range(60, W):  # the door's ledge (2 tiles up)
        put(c, 6, "#"); put(c, 7, "#")
    for c in range(14, 19):
        put(c, 5, "=")
    for c in range(31, 36):
        put(c, 5, "=")
    for c, r in ((7, 6), (9, 6), (15, 4), (16, 4), (17, 4), (10, 5), (28, 5), (32, 4), (33, 4), (34, 4),
                 (50, 4), (51, 4), (52, 4), (63, 5)):
        put(c, r, "o")
    for c in (39, 40):  # (two: a jump clears them)
        put(c, 7, "^")
    put(23, 7, "e"); put(51, 5, "e")  # (the second patrols the block)
    put(1, 7, "P")
    put(65, 5, "D")
    return ["".join(row) for row in g]


PLATFORMER_LEVEL2 = _level2()


def platformer_scene(t, rows, name, next_level="", game_level=None):
    """A platformer level (scene children) from a text map:
    # ground, = one-way platform, o coin, ^ spikes, e enemy, P player, D door.
    game_level: the level's number in a game (#329: the HUD shows the level
    and the lives, Game runs the levels)."""
    T = 18  # tile size
    TILES, CHARS = "textures/tiles.png", "textures/characters.png"
    TG, CG = (20, 9), (9, 3)  # sheet grids
    rows = grid_of(rows)
    H, W = len(rows), len(rows[0])

    def at(c, r):
        return rows[r][c] if 0 <= r < H and 0 <= c < W else "."

    solid = [[-1] * W for _ in range(H)]
    decor = [[-1] * W for _ in range(H)]
    children = []
    platforms, coins, spikes, enemies = [], [], [], []
    player = door = None
    for r in range(H):
        for c in range(W):
            ch = rows[r][c]
            if ch == "#":
                left, right = at(c - 1, r) == "#", at(c + 1, r) == "#"
                if at(c, r - 1) != "#":  # grass on top
                    solid[r][c] = 2 if left and right else (1 if right else (3 if left else 0))
                    if at(c, r - 1) == "." and (c * 7 + r * 3) % 9 == 0:
                        decor[r - 1][c] = 124 if c % 2 else 125  # grass tufts
                else:
                    solid[r][c] = (4, 5, 24, 25)[(c * 5 + r * 3) % 4]  # plain dirt
            elif ch == "=":
                left, right = at(c - 1, r) == "=", at(c + 1, r) == "="
                decor[r][c] = 49 if left and right else (48 if right else (50 if left else 47))
                if not left:
                    n = 0
                    while at(c + n, r) == "=":
                        n += 1
                    platforms.append((c, r, n))
            elif ch == "o":
                coins.append((c, r))
            elif ch == "^":
                spikes.append((c, r))
            elif ch == "e":
                enemies.append((c, r))
            elif ch == "P":
                player = (c, r)
            elif ch == "D":
                door = (c, r)
    assert player and door

    def center(c, r):
        return [c * T + T / 2, r * T + T / 2]

    children.append({"type": "CameraNode", "name": "Camera", "position": center(*player), "follow": "../Player",
                     "properties": {"isCurrent": True, "followMode": "SingleTarget", "dragType": "SmoothDamp",
                                    "hasLimits": True, "leftLimit": 0, "rightLimit": W * T, "topLimit": -4 * T,
                                    "bottomLimit": H * T}})
    # The backdrop: sky, then trees and clouds, then fill - scrolled slower than
    # the level (parallax.lua).
    BW = (W * T) // 24 + 2
    back = [[(9, 11)[c % 2] for c in range(BW)]] + [[16 + c % 4 for c in range(BW)] for _ in range(4)]
    children.append({**tilemap("Backdrop", "textures/backgrounds.png", 24, back, layer=0, pos=(0, (H - 6) * T)),
                     "script": {"path": "scripts/parallax.lua", "properties": {"factor": 0.5}}})
    children.append(tilemap("Decor", TILES, T, decor, layer=1, z=-1))
    children.append(tilemap("Level", TILES, T, solid, solid=True, layer=1))
    for i, (c, r, n) in enumerate(platforms):
        children.append({"type": "StaticBodyNode", "name": f"Platform{i + 1}", "position": [c * T + n * T / 2, r * T + 3],
                         "properties": {"oneWay": True}, "shapes": [{"type": "Box", "size": [n * T, 6]}]})
    for i, (c, r) in enumerate(coins):
        children.append({"type": "AreaNode", "name": f"Coin{i + 1}", "position": center(c, r), "tags": ["coin"],
                         "shapes": [{"type": "Circle", "radius": 6}], "script": {"path": "scripts/coin.lua"},
                         "children": [sprite("Sprite", TILES, TG, {"spin": ([151, 152], 6, True)}, layer=2)]})
    for i, (c, r) in enumerate(spikes):
        children.append({"type": "AreaNode", "name": f"Spikes{i + 1}", "position": center(c, r),
                         "shapes": [{"type": "Box", "size": [14, 6], "offset": [0, 5]}], "script": {"path": "scripts/hazard.lua"},
                         "children": [sprite("Sprite", TILES, TG, {"idle": ([68], 1, False)}, layer=2)]})
    for i, (c, r) in enumerate(enemies):
        children.append({
            "type": "CharacterMoverNode", "name": f"Enemy{i + 1}", "position": center(c, r), "tags": ["enemy"],
            "shapes": [{"type": "Capsule", "radius": 6, "size": [12, 4]}],
            "properties": {"controlMode": "Script", "categoryLayers": ["Layer3"], "maskLayers": ["Layer1"]},
            "script": {"path": "scripts/enemy.lua", "properties": {"speed": 30}},
            "children": [
                sprite("Sprite", CHARS, CG, {"walk": ([18, 19], 4, True), "squashed": ([20], 1, False)},
                       pos=(0, -3), layer=2),
                {"type": "AreaNode", "name": "Hitbox", "shapes": [{"type": "Box", "size": [16, 14]}],
                 "script": {"path": "scripts/enemy_hitbox.lua"}},
            ]})
    dc, dr = door
    children.append({"type": "AreaNode", "name": "Door", "position": [dc * T + T / 2, dr * T + T / 2],
                     "shapes": [{"type": "Box", "size": [10, 16]}],
                     "script": {"path": "scripts/goal.lua", "properties": {"next_level": next_level}},
                     "children": [sprite("Top", TILES, TG, {"idle": ([130], 1, False)}, pos=(0, -T), layer=1),
                                  sprite("Bottom", TILES, TG, {"idle": ([150], 1, False)}, layer=1)]})
    children.append({
        "type": "CharacterMoverNode", "name": "Player", "position": center(*player), "tags": ["player"],
        "shapes": [{"type": "Capsule", "radius": 6, "size": [12, 6]}],
        "properties": {"controlMode": "Script", "categoryLayers": ["Layer2"], "maskLayers": ["Layer1"]},
        "script": {"path": "scripts/player.lua", "properties": {"fall_limit": H * T + 40}},
        "children": [sprite("Sprite", CHARS, CG, {"idle": ([0], 1, True), "run": ([0, 1], 8, True),
                                                  "jump": ([1], 1, False)}, pos=(0, -3), layer=3)]})
    hud = {"type": "Node", "name": "HUD", "script": {"path": "scripts/hud.lua"}, "children": [
        text("Coins", "Coins 0", (8, 4), color="#3c3c5aff"),
        text("Message", "", (160, 70), size=32, align="Center", pivot=(0.5, 0.5), color="#3c3c5aff"),
    ]}
    if game_level:
        hud["script"]["properties"] = {"level": game_level}
        hud["children"] += [text("LevelText", "", (160, 4), align="Center", pivot=(0.5, 0), color="#3c3c5aff"),
                            text("Lives", "", (312, 4), align="Right", pivot=(1, 0), color="#3c3c5aff")]
    children.append(hud)
    return scene(name, children, background=(223, 246, 245, 255))


def platformer_art(t):
    t.art("pixel-platformer/tilemap_packed.png", "textures/tiles.png")
    t.art("pixel-platformer/tilemap-characters_packed.png", "textures/characters.png")
    t.art("pixel-platformer/tilemap-backgrounds_packed.png", "textures/backgrounds.png")
    t.license("Pixel Platformer")


PLATFORMER_SCRIPTS = ("player", "enemy", "enemy_hitbox", "coin", "hazard", "goal", "hud", "parallax")
PLATFORMER_ACTIONS = MOVE_ACTIONS + [action("jump", "SPACE", "W", "UP", "pad:RIGHT_FACE_DOWN")]


def platformer():
    t = Template("platformer", "Platformer",
                 "Run and jump through two levels: coins, spikes, enemies to stomp, a door to the end, three "
                 "lives. A title screen, settings, a pause menu, saved progress.", "person-running", 1)
    t.begin()
    platformer_art(t)
    # A small game (#329): the title, two levels (three lives), the result
    # screen; the furthest level and the best coin count saved.
    ink, red = "#3c3c5aff", "#c0392bff"
    levels = ["scenes/level1.scene.json", "scenes/level2.scene.json"]
    for i, rows in enumerate((PLATFORMER_LEVEL, PLATFORMER_LEVEL2)):
        sc = platformer_scene(t, rows, f"level{i + 1}", game_level=i + 1)
        sc["root"]["children"].append(pause_menu(PIXEL_STYLE, red))
        t.json(levels[i], with_touch(sc, (320, 180), stick=("move_left", "move_right", "", ""), pause="pause"))
    sky = (223, 246, 245, 255)

    def backdrop():
        return tilemap("Backdrop", "textures/backgrounds.png", 24, [[(9, 11)[c % 2] for c in range(15)]] +
                       [[16 + c % 4 for c in range(15)] for _ in range(3)], layer=0, pos=(0, 84))
    t.json("scenes/title.scene.json", title_scene("Platformer", PIXEL_STYLE, ink, red, sky, [backdrop()]))
    t.json("scenes/result.scene.json", result_scene(PIXEL_STYLE, ink, red, sky, [backdrop()]))
    t.json("project.json", project("Platformer", ["scenes/title.scene.json"] + levels + ["scenes/result.scene.json"],
                                   PLATFORMER_ACTIONS + GAME_ACTIONS, globals_=GAME_GLOBALS))
    for s_ in PLATFORMER_SCRIPTS:
        t.script(s_)
    game_scripts(t, levels, lives=3, score_name="Coins")
    # Starter physics components (they were snippets built into the editor: #87).
    t.json("components/physics_crate.component.json", {
        "type": "DynamicBodyNode", "name": "PhysicsCrate", "uid": "crate000",
        "shapes": [{"type": "Box", "size": [64, 64], "density": 1.5, "friction": 0.4, "restitution": 0.2}]})
    t.json("components/static_platform.component.json", {
        "type": "StaticBodyNode", "name": "StaticPlatform", "uid": "platf000",
        "shapes": [{"type": "Box", "size": [400, 32], "density": 0, "friction": 0.8, "restitution": 0}]})
    t.json("components/trigger_zone.component.json", {
        "type": "AreaNode", "name": "TriggerZone", "uid": "trigr000",
        "shapes": [{"type": "Box", "size": [128, 128], "isSensor": True}]})
    with open(os.path.join(SCRIPTS, "platformer", "README.md")) as f:
        t.write("README.md", f.read())
    return t


def adventure():
    """A sample: the platformer grown into a small game - the shared title,
    settings, pause and result screens (#329), lives, saved progress; each
    door's Next Level routes the levels."""
    t = Template("adventure", "Platformer Adventure (sample)",
                 "The platformer grown into a small game: a title screen, settings, two levels routed by their "
                 "doors, three lives, a game over, saved progress, a pause menu - how the pieces fit together.",
                 "gamepad", 50)
    t.meta["kind"] = "sample"
    t.begin()
    platformer_art(t)
    ink, red, sky = "#3c3c5aff", "#c0392bff", (223, 246, 245, 255)
    levels = ["scenes/level1.scene.json", "scenes/level2.scene.json"]
    # The routes: level 1's door leads to level 2, level 2's (none) to the result.
    routes = ["scenes/level2.scene.json", ""]
    side = ("move_left", "move_right", "move_up", "move_down")  # (up / down pick in the pause menu)
    for i, rows in enumerate((PLATFORMER_LEVEL, PLATFORMER_LEVEL2)):
        sc = platformer_scene(t, rows, f"level{i + 1}", routes[i], game_level=i + 1)
        sc["root"]["children"].append(pause_menu(PIXEL_STYLE, red))
        t.json(levels[i], with_touch(sc, (320, 180), stick=side, pause="pause"))

    def backdrop():
        return tilemap("Backdrop", "textures/backgrounds.png", 24, [[(9, 11)[c % 2] for c in range(15)]] +
                       [[16 + c % 4 for c in range(15)] for _ in range(3)], layer=0, pos=(0, 84))
    t.json("scenes/title.scene.json", title_scene("Platformer Adventure", PIXEL_STYLE, ink, red, sky, [backdrop()]))
    t.json("scenes/result.scene.json", result_scene(PIXEL_STYLE, ink, red, sky, [backdrop()]))
    t.json("project.json", project("Platformer Adventure", ["scenes/title.scene.json"] + levels + ["scenes/result.scene.json"],
                                   PLATFORMER_ACTIONS + GAME_ACTIONS, globals_=GAME_GLOBALS))
    # The Platformer's scripts, but its own door (the routes).
    for s_ in PLATFORMER_SCRIPTS:
        if s_ != "goal":
            t.script(s_, src="platformer")
    t.script("goal")
    game_scripts(t, levels, lives=3, score_name="Coins")
    with open(os.path.join(SCRIPTS, "adventure", "README.md")) as f:
        t.write("README.md", f.read())
    return t


# --- top-down RPG -------------------------------------------------------------------

# Floors as text: # wall, . floor, P player, N the wizard, s slime, p potion,
# g gold, c the chest (the key), L the locked door, X the exit (the stairs).
RPG_MAP = [
    "##############################",
    "#.......#..........#.........#",
    "#.P.....#...s......#.........#",
    "#.......#.......s..#....X....#",
    "#...N...+..........L.........#",
    "#.......#....s.....#.........#",
    "#.......#.........c#....g....#",
    "#..p..g.#...g......#.........#",
    "#.......#..........#.........#",
    "##############################",
]

RPG_MAP2 = [
    "##############################",
    "#......#..........s.#........#",
    "#.P....#............#...g....#",
    "#......+.....s......#........#",
    "#..g...#............L....X...#",
    "#......#....s.......#........#",
    "####.##############.#........#",
    "#c...s..............#........#",
    "#p......g...s.......#...g....#",
    "##############################",
]


def rpg_floor(rows, name, level):
    """A floor (a scene) from a text map: the tile maps, the wizard, slimes,
    potions, gold, the chest, the locked door, the exit, the player, the HUD."""
    T = 16
    SHEET, SG = "textures/dungeon.png", (12, 11)
    rows = grid_of(rows)
    H, W = len(rows), len(rows[0])
    walls = [[-1] * W for _ in range(H)]
    floor = [[-1] * W for _ in range(H)]
    ents = {}
    for r in range(H):
        for c in range(W):
            ch = rows[r][c]
            if ch == "#":
                walls[r][c] = 40
            else:
                floor[r][c] = (48, 48, 49, 50, 48, 48)[(c * 7 + r * 5) % 6]
                if ch not in ".+":
                    ents.setdefault(ch, []).append((c, r))

    def center(c, r):
        return [c * T + T / 2, r * T + T / 2]

    def char(name, cell, pos, script, tags=(), props=None, extra=()):
        return {"type": "CharacterMoverNode", "name": name, "position": pos, "tags": list(tags),
                "shapes": [{"type": "Capsule", "radius": 5, "size": [10, 2]}],
                "properties": {"controlMode": "Script", "categoryLayers": ["Layer2"], "maskLayers": ["Layer1"]},
                "script": {"path": script, "properties": props or {}},
                "children": [sprite("Sprite", SHEET, SG, {"idle": ([cell], 1, True)}, pos=(0, -3), layer=2)] + list(extra)}

    (pc, pr), = ents["P"]
    children = [
        {"type": "CameraNode", "name": "Camera", "position": center(pc, pr), "follow": "../Player",
         "properties": {"isCurrent": True, "followMode": "SingleTarget", "dragType": "SmoothDamp",
                        "hasLimits": True, "leftLimit": 0, "rightLimit": W * T, "topLimit": -T, "bottomLimit": H * T + T}},
        tilemap("Floor", SHEET, T, floor, layer=1, z=-1),
        tilemap("Walls", SHEET, T, walls, solid=True, layer=1),
    ]
    for (nc, nr) in ents.get("N", []):
        children.append({"type": "Node", "name": "Wizard", "position": center(nc, nr), "tags": ["interactable"],
                         "script": {"path": "scripts/npc.lua"},
                         "children": [sprite("Sprite", SHEET, SG, {"idle": ([84], 1, True)}, pos=(0, -2), layer=2)]})
    for i, (c, r) in enumerate(ents.get("s", [])):
        children.append(char(f"Slime{i + 1}", 108, center(c, r), "scripts/slime.lua", tags=["enemy"]))
    for i, (c, r) in enumerate(ents.get("p", [])):
        children.append({"type": "AreaNode", "name": f"Potion{i + 1}", "position": center(c, r),
                         "shapes": [{"type": "Circle", "radius": 6}], "script": {"path": "scripts/potion.lua"},
                         "children": [sprite("Sprite", SHEET, SG, {"idle": ([115], 1, True)}, layer=2)]})
    for i, (c, r) in enumerate(ents.get("g", [])):
        children.append({"type": "AreaNode", "name": f"Gold{i + 1}", "position": center(c, r), "tags": ["gold"],
                         "shapes": [{"type": "Circle", "radius": 6}], "script": {"path": "scripts/gold.lua"},
                         "children": [sprite("Sprite", "textures/ui.png", (20, 9), {"spin": ([151, 152], 6, True)}, layer=2)]})
    (cc, cr), = ents["c"]
    children.append({"type": "Node", "name": "Chest", "position": center(cc, cr), "tags": ["interactable"],
                     "script": {"path": "scripts/chest.lua"},
                     "children": [sprite("Sprite", SHEET, SG, {"closed": ([89], 1, True), "open": ([91], 1, True)}, layer=2)]})
    (lc, lr), = ents["L"]
    children.append({"type": "StaticBodyNode", "name": "LockedDoor", "position": center(lc, lr), "tags": ["interactable"],
                     "shapes": [{"type": "Box", "size": [T, T]}], "script": {"path": "scripts/locked_door.lua"},
                     "children": [sprite("Sprite", SHEET, SG, {"closed": ([46], 1, True), "open": ([34], 1, True)}, layer=1)]})
    (xc, xr), = ents["X"]
    children.append({"type": "AreaNode", "name": "Exit", "position": center(xc, xr),
                     "shapes": [{"type": "Box", "size": [10, 10]}], "script": {"path": "scripts/exit.lua"},
                     "children": [sprite("Sprite", SHEET, SG, {"idle": ([22], 1, True)}, layer=1)]})
    children.append(char("Player", 96, center(pc, pr), "scripts/player.lua", tags=["player"], extra=[
        sprite("Sword", SHEET, SG, {"idle": ([104], 1, True)}, pos=(8, -2), layer=3),
    ]))
    hearts = [sprite(f"Heart{i + 1}", "textures/ui.png", (20, 9), {"full": ([44], 1, True), "empty": ([46], 1, True)},
                     pos=(10 + i * 14, 10), layer=7) for i in range(3)]
    children.append({"type": "Node", "name": "HUD", "script": {"path": "scripts/hud.lua", "properties": {"level": level}},
                     "children": hearts + [
        text("Key", "", (56, 2), color="#f5d76eff"),
        text("FloorText", "", (160, 2), align="Center", pivot=(0.5, 0)),
        text("Gold", "Gold 0", (312, 2), align="Right", pivot=(1, 0), color="#f5d76eff"),
        text("Hint", "", (160, 158), align="Center", pivot=(0.5, 0)),
        text("Message", "", (160, 60), size=32, align="Center", pivot=(0.5, 0.5)),
    ]})
    children.append({"type": "DialogueNode", "name": "Dialogue", "position": [10, 118], "layer": 7,
                     "properties": {"size": [300, 52], "font": PIXEL_FONT, "fontSize": 16, "padding": 6, "revealSpeed": 60,
                                    "panelColor": "#1c1820f5", "advanceAction": "confirm"}})
    children.append(pause_menu(PIXEL_STYLE, "#e74c3cff"))
    return with_touch(scene(name, children, background=(37, 19, 26, 255)), (320, 180),
                      buttons=(("attack", "A"), ("interact, confirm", "E")), pause="pause")


def rpg():
    t = Template("rpg", "Top-down RPG",
                 "Explore two dungeon floors: talk to a wizard, fight slimes with a sword, collect gold, find "
                 "each floor's key, unlock the door and take the stairs. A title screen, settings, a pause "
                 "menu, saved progress.", "dungeon", 2)
    t.begin()
    t.art("tiny-dungeon/tilemap_packed.png", "textures/dungeon.png")
    t.art("pixel-platformer/tilemap_packed.png", "textures/ui.png")  # hearts, gold
    t.license("Tiny Dungeon", "Pixel Platformer (hearts, gold)")
    # A small game (#329): two floors (the stairs lead down to the next), the
    # hearts are your life - a defeat is game over; the furthest floor and
    # the most gold saved; the title, a pause menu, the result screen.
    levels = ["scenes/floor1.scene.json", "scenes/floor2.scene.json"]
    for i, rows in enumerate((RPG_MAP, RPG_MAP2)):
        t.json(levels[i], rpg_floor(rows, f"floor{i + 1}", i + 1))
    white, red, dark = "#e9dcc2ff", "#e74c3cff", (37, 19, 26, 255)

    def backdrop():  # (walls above and below)
        return tilemap("Backdrop", "textures/dungeon.png", 16, [[40] * 20] + [[-1] * 20] * 9 + [[40] * 20] * 2,
                       layer=0, z=-1)
    t.json("scenes/title.scene.json", title_scene("Top-down RPG", PIXEL_STYLE, white, red, dark, [backdrop()], level_word="Floor"))
    t.json("scenes/result.scene.json", result_scene(PIXEL_STYLE, white, red, dark, [backdrop()]))
    t.json("project.json", project("Top-down RPG", ["scenes/title.scene.json"] + levels + ["scenes/result.scene.json"], MOVE_ACTIONS + [
        action("attack", "SPACE", "J", "pad:RIGHT_FACE_LEFT"),
        action("interact", "E", "K", "pad:RIGHT_FACE_DOWN"),
        action("confirm", "E", "ENTER", "KP_ENTER", "K", "pad:RIGHT_FACE_DOWN"),
        action("pause", "ESCAPE", "P", "pad:MIDDLE_RIGHT"),
    ], gravity=(0, 0), globals_=GAME_GLOBALS))
    for s_ in ("player", "slime", "npc", "chest", "locked_door", "potion", "gold", "exit", "hud"):
        t.script(s_)
    game_scripts(t, levels, lives=None, score_name="Gold", level_word="Floor")
    with open(os.path.join(SCRIPTS, "rpg", "README.md")) as f:
        t.write("README.md", f.read())
    return t


# --- shmup ----------------------------------------------------------------------

def shmup():
    t = Template("shmup", "Shoot 'em up",
                 "Fly right through three stages of enemies: shoot, dodge their bullets, keep your three lives. "
                 "A title screen, settings, a pause menu, a saved high score.", "jet-fighter", 3)
    t.begin()
    t.art("pixel-shmup/ships_packed.png", "textures/ships.png")
    t.art("pixel-shmup/tiles_packed.png", "textures/tiles.png")
    t.license("Pixel Shmup")
    SHIPS, SG = "textures/ships.png", (4, 6)
    TILES, TG = "textures/tiles.png", (12, 10)
    # The sea: water with islands, 2 screens wide (the second repeats the
    # first: scroll.lua wraps it).
    W, H = 40, 12
    sea = [[42] * W for _ in range(H)]
    for (ic, ir) in ((3, 2), (12, 7), (22, 1), (31, 6)):
        for dr, row in enumerate(((37, 38, 39), (49, 50, 51), (61, 62, 63))):
            for dc, cell in enumerate(row):
                sea[ir + dr][ic + dc] = cell
                sea[ir + dr][(ic + dc + 20) % W] = cell
    explosion = sprite("Sprite", TILES, TG, {"boom": ([4, 5, 6, 7, 8], 14, False)}, layer=3)
    t.json("components/player_bullet.component.json", {
        "type": "Node", "name": "PlayerBullet", "tags": ["player_bullet"],
        "script": {"path": "scripts/bullet.lua", "properties": {"speed": 260, "dir_x": 1, "radius": 3}},
        "children": [{**sprite("Sprite", TILES, TG, {"idle": ([0], 1, True)}, layer=3), "rotation": 90}]})
    t.json("components/enemy_bullet.component.json", {
        "type": "Node", "name": "EnemyBullet", "tags": ["enemy_bullet"],
        "script": {"path": "scripts/bullet.lua", "properties": {"speed": 110, "dir_x": -1, "radius": 3}},
        "children": [sprite("Sprite", TILES, TG, {"idle": ([3], 1, True)}, layer=3)]})
    for kind, cell, props in (("drifter", 17, {"speed": 50, "wobble": 18, "hp": 1, "shoots": False, "points": 100}),
                              ("shooter", 21, {"speed": 35, "wobble": 6, "hp": 3, "shoots": True, "points": 300})):
        t.json(f"components/{kind}.component.json", {
            "type": "Node", "name": kind.capitalize(), "tags": ["enemy"],
            "script": {"path": "scripts/enemy.lua", "properties": props},
            "children": [{**sprite("Sprite", SHIPS, SG, {"idle": ([cell], 1, True)}, layer=2), "rotation": 90}]})
    t.json("components/explosion.component.json", {
        "type": "Node", "name": "Explosion", "script": {"path": "scripts/explosion.lua"}, "children": [explosion]})
    ink, red, sky = "#1d3b4cff", "#c0392bff", (140, 214, 225, 255)

    def sea_map():
        return {**tilemap("Sea", TILES, 16, sea, layer=0, pos=(0, -6)),
                "script": {"path": "scripts/scroll.lua", "properties": {"speed": 20, "wrap": 320}}}
    # A small game (#329): three stages - the first down the middle, then
    # sweeping waves with shooters - three lives for the whole run, the best
    # score saved; the title, a pause menu, the result screen.
    STAGES = [{"count": 6, "interval": 0.8, "shooter_every": 0, "spread": 0},
              {"count": 8, "interval": 0.9, "shooter_every": 4, "spread": 1},
              {"count": 10, "interval": 0.75, "shooter_every": 3, "spread": 1}]
    levels = [f"scenes/stage{i + 1}.scene.json" for i in range(len(STAGES))]
    for i, props in enumerate(STAGES):
        children = [
            {"type": "CameraNode", "name": "Camera", "position": [160, 90], "properties": {"isCurrent": True}},
            sea_map(),
            {"type": "Node", "name": "Player", "position": [40, 90], "tags": ["player"],
             "script": {"path": "scripts/player.lua"},
             "children": [{**sprite("Sprite", SHIPS, SG, {"idle": ([1], 1, True)}, layer=2), "rotation": -90}]},
            {"type": "Node", "name": "Spawner", "script": {"path": "scripts/spawner.lua", "properties": {"stage": i + 1, **props}}},
            {"type": "Node", "name": "Shots"},  # bullets, enemies, explosions go here
            {"type": "Node", "name": "HUD", "script": {"path": "scripts/hud.lua"}, "children": [
                text("Score", "Score 0", (6, 2), color=ink),
                text("Stage", "", (160, 2), align="Center", pivot=(0.5, 0), color=ink),
                text("High", "Best 0", (314, 2), align="Right", pivot=(1, 0), color=ink),
                text("Lives", "Lives 3", (6, 162), color=ink),
                text("Message", "", (160, 80), size=32, align="Center", pivot=(0.5, 0.5), color=ink),
            ]},
            pause_menu(PIXEL_STYLE, red),
        ]
        t.json(levels[i], with_touch(scene(f"stage{i + 1}", children, background=sky), (320, 180),
                                     buttons=(("fire", "F"),), pause="pause"))
    t.json("scenes/title.scene.json", title_scene("Shoot 'em up", PIXEL_STYLE, ink, red, sky, [sea_map()], level_word="Stage"))
    t.json("scenes/result.scene.json", result_scene(PIXEL_STYLE, ink, red, sky, [sea_map()]))
    t.json("project.json", project("Shoot 'em up", ["scenes/title.scene.json"] + levels + ["scenes/result.scene.json"],
                                   MOVE_ACTIONS + [action("fire", "SPACE", "J", "pad:RIGHT_FACE_DOWN")] + GAME_ACTIONS,
                                   gravity=(0, 0), globals_=GAME_GLOBALS))
    for s_ in ("player", "bullet", "enemy", "spawner", "explosion", "scroll", "hud"):
        t.script(s_)
    game_scripts(t, levels, lives=3, score_name="Score", level_word="Stage")
    with open(os.path.join(SCRIPTS, "shmup", "README.md")) as f:
        t.write("README.md", f.read())
    return t


# --- puzzle (Sokoban) ------------------------------------------------------------------

# The levels (also in scripts/puzzle.lua - this list checks they can be solved):
# # wall, . goal, $ crate, * crate on a goal, @ player, + player on a goal.
PUZZLE_LEVELS = [
    ["#######", "#     #", "# @$ .#", "#     #", "#######"],
    ["########", "#      #", "#  $ . #", "# @$ . #", "#      #", "########"],
    ["#########", "#   #   #", "# $ $ $ #", "#  . .  #", "## ### .#", " #  @   #", " ########"],
]


def sokoban_solve(rows, limit=2_000_000):
    """Breadth-first: the shortest solution as moves (UDLR), None if none."""
    from collections import deque
    walls, goals, crates, player = set(), set(), set(), None
    for r, row in enumerate(rows):
        for c, ch in enumerate(row):
            if ch == "#":
                walls.add((c, r))
            if ch in ".*+":
                goals.add((c, r))
            if ch in "$*":
                crates.add((c, r))
            if ch in "@+":
                player = (c, r)
    moves = {"U": (0, -1), "D": (0, 1), "L": (-1, 0), "R": (1, 0)}
    start = (player, frozenset(crates))
    seen, q = {start: None}, deque([start])
    while q:
        st = q.popleft()
        p, cr = st
        if all(x in goals for x in cr):
            path = []
            while seen[st]:
                st, m = seen[st]
                path.append(m)
            return "".join(reversed(path))
        for m, (dx, dy) in moves.items():
            n = (p[0] + dx, p[1] + dy)
            if n in walls:
                continue
            ncr = cr
            if n in cr:
                b = (n[0] + dx, n[1] + dy)
                if b in walls or b in cr:
                    continue
                ncr = (cr - {n}) | {b}
            ns = (n, frozenset(ncr))
            if ns not in seen:
                seen[ns] = (st, m)
                q.append(ns)
                if len(seen) > limit:
                    return None
    return None


def puzzle():
    t = Template("puzzle", "Puzzle (Sokoban)",
                 "Push every crate onto a target. Three levels written as text in a script, move limits, undo, "
                 "restart, smooth moves. A title screen, settings, a pause menu, saved progress.", "puzzle-piece", 4)
    limits = []
    for i, lv in enumerate(PUZZLE_LEVELS):
        sol = sokoban_solve(lv)
        assert sol is not None, f"puzzle level {i + 1} can't be solved"
        limits.append(2 * len(sol) + 6)  # (the move limit: room for a few mistakes)
    t.begin()
    for name in ("ground", "wall", "crate", "crate_on_goal", "goal", "player"):
        t.art(f"sokoban/{name}.png", f"textures/{name}.png")
    t.license("Sokoban")
    # The levels go into the script as Lua strings.
    lua_levels = ",\n".join("    {\n" + ",\n".join(f'        "{row}"' for row in lv) + ",\n    }" for lv in PUZZLE_LEVELS)
    with open(os.path.join(SCRIPTS, "puzzle", "puzzle.lua")) as f:
        t.write("scripts/puzzle.lua", f.read().replace("--$LEVELS$", lua_levels)
                .replace("--$LIMITS$", ", ".join(str(n) for n in limits)))
    # A small game (#329): the three levels with move limits (out of moves:
    # game over), the furthest level and each level's fewest moves saved;
    # the title, a pause menu, the result screen.
    ink, red, sand = "#3b2a20ff", "#c0392bff", (229, 207, 167, 255)
    children = [
        {"type": "CameraNode", "name": "Camera", "position": [640, 360], "properties": {"isCurrent": True}},
        {"type": "Node", "name": "Board", "script": {"path": "scripts/puzzle.lua", "properties": {"start_level": 1}}},
        text("Level", "Level 1", (24, 16), size=32, color=ink),
        text("Moves", "Moves 0", (1256, 16), size=32, align="Right", pivot=(1, 0), color=ink),
        text("Help", "Arrows / WASD move   Z undo   R restart   Esc pause", (640, 690), size=32, align="Center",
             pivot=(0.5, 1), color="#3b2a20aa"),
        text("Message", "", (640, 80), size=48, align="Center", pivot=(0.5, 0.5), color=ink),
        pause_menu(HD_STYLE, red),
    ]
    t.json("scenes/puzzle.scene.json", with_touch(scene("puzzle", children, background=sand), (1280, 720),
                                                  buttons=(("undo", "Undo"), ("restart", "R")), pause="pause"))
    t.json("scenes/title.scene.json", title_scene("Puzzle", HD_STYLE, ink, red, sand))
    t.json("scenes/result.scene.json", result_scene(HD_STYLE, ink, red, sand))
    t.json("project.json", project("Puzzle", ["scenes/title.scene.json", "scenes/puzzle.scene.json", "scenes/result.scene.json"],
                                   MOVE_ACTIONS + [
        action("undo", "Z", "U", "BACKSPACE", "pad:RIGHT_FACE_RIGHT"),
        action("restart", "R", "pad:RIGHT_FACE_UP"),
    ] + GAME_ACTIONS, virtual=(1280, 720), gravity=(0, 0), pixel=False, globals_=GAME_GLOBALS))
    # (Every level is the puzzle scene: the board builds the run's level.)
    game_scripts(t, ["scenes/puzzle.scene.json"] * len(PUZZLE_LEVELS), lives=None, score_name="Moves", lower_is_better=True)
    with open(os.path.join(SCRIPTS, "puzzle", "README.md")) as f:
        t.write("README.md", f.read())
    return t


# --- visual novel -----------------------------------------------------------------

def visual_novel():
    t = Template("visual_novel", "Visual Novel",
                 "A short branching story: characters, backgrounds, choices that change what happens, three "
                 "endings. Save slots, a backlog, auto and skip, a title screen with settings. Write your own "
                 "in story.lua.", "book", 5)
    t.begin()
    for who in ("ada", "theo", "unit"):
        for pose in ("idle", "talk", "think", "cheer", "hurt"):
            t.art(f"toon-characters/{who}_{pose}.png", f"textures/{who}_{pose}.png")
    for bg in ("castle", "forest", "talltrees", "desert"):
        t.art(f"background-elements/{bg}.png", f"textures/bg_{bg}.png")
    t.license("Toon Characters", "Background Elements")
    PANEL, BORDER, ACCENT = "#0f121ce6", "#5c8dffff", "#5c8dffc8"

    def background(name="Background", bg="castle"):
        # (the 1024 x 576 pictures, scaled to the 1280 x 720 screen)
        return {"type": "TextureNode", "name": name, "position": [0, 0], "pivot": [0, 0], "scale": [1.25, 1.25], "layer": 1,
                "texture": f"textures/bg_{bg}.png"}

    def figure(name, who, x, visible=True):
        return {"type": "TextureNode", "name": name, "position": [x, 724], "scale": [2, 2], "layer": 2,
                "pivot": [0.5, 1], "visible": visible, "texture": f"textures/{who}_idle.png"}

    def button(name, label, w=260, h=48, size=24, **extra):
        return {"type": "UIButtonNode", "name": name, "layer": 8,
                "properties": {"size": [w, h], "text": label, "fontSize": size, "normalColor": PANEL,
                               "hoverColor": ACCENT, "borderColor": BORDER, "textColor": "#eef0f6ff", **extra}}

    def column(name, pos, size, children, title=None, layer=8):
        props = {"size": list(size), "direction": "Vertical", "alignment": "Center", "spacing": 12,
                 "paddingTop": 16, "paddingBottom": 16, "drawBackground": title is not None,
                 "drawBorder": title is not None, "showHeader": False, "backgroundColor": PANEL, "borderColor": BORDER}
        if title:
            props.update({"title": title, "showHeader": True, "headerHeight": 36, "headerColor": "#1e2840ff"})
        return {"type": "UIContainerNode", "name": name, "position": list(pos), "layer": layer,
                "properties": props, "children": children}

    def label(name, value, pos, size=28, align="Center", pivot=(0.5, 0), color="#ffffffff", layer=7, **extra):
        n = {"type": "TextNode", "name": name, "position": list(pos), "pivot": list(pivot), "layer": layer,
             "properties": {"text": value, "fontSize": size, "align": align, "color": color, "richText": True}}
        n["properties"].update(extra)
        return n

    slots = column("Slots", (340, 150), (600, 290), [button(f"Slot{i}", f"{i}.", w=540) for i in (1, 2, 3)] +
                   [button("Close", "Close", w=160, h=40, size=20)], title="Load a slot")
    slots["script"] = {"path": "scripts/slots.lua"}
    camera = {"type": "CameraNode", "name": "Camera", "position": [640, 360], "properties": {"isCurrent": True}}

    # The story: stage, the box, the buttons under it, the backlog, the slots.
    quick = {"type": "UIContainerNode", "name": "QuickMenu", "position": [452, 684], "layer": 8,
             "properties": {"size": [688, 32], "direction": "Horizontal", "alignment": "Center", "spacing": 8,
                            "drawBackground": False, "drawBorder": False, "showHeader": False},
             # (mouse only: the arrows and Enter stay the story's - keyboardFocus off)
             "children": [button(n, l, w=106, h=28, size=16, keyboardFocus=False) for n, l in (
                 ("AutoButton", "Auto"), ("SkipButton", "Skip"), ("LogButton", "Log"),
                 ("SaveButton", "Save"), ("LoadButton", "Load"), ("TitleButton", "Title"))]}
    log = {"type": "Node", "name": "Log", "children": [
        column("LogPanel", (90, 40), (1100, 640), [], title="Backlog  (wheel / up / down to scroll)"),
        label("LogText", "", (120, 96), size=22, align="Left", pivot=(0, 0), layer=8, maxWidth=1040, lineSpacing=1.3),
        dict(button("LogClose", "Close", w=140, h=40, size=20), position=[1030, 624]),
    ]}
    story = [
        camera, background(),
        figure("SlotLeft", "ada", 300, False), figure("SlotCenter", "unit", 640, False), figure("SlotRight", "theo", 980, False),
        {"type": "Node", "name": "Story", "script": {"path": "scripts/story.lua"}},
        {"type": "Node", "name": "VN", "script": {"path": "scripts/vn.lua"}},
        {"type": "DialogueNode", "name": "Dialogue", "position": [140, 500], "layer": 7,
         "properties": {"size": [1000, 180], "fontSize": 26, "padding": 22, "revealSpeed": 40,
                        "panelColor": PANEL, "borderColor": BORDER, "choiceColor": ACCENT, "advanceAction": "confirm"}},
        quick,
        dict(label("Ending", "", (640, 300), size=64, layer=8, pivot=(0.5, 0.5)), visible=False),
        label("Toast", "", (1260, 16), size=22, align="Right", pivot=(1, 0), layer=8),
        log, slots,
    ]
    t.json("scenes/story.scene.json", scene("story", story, background=(20, 22, 30, 255)))

    # The title screen.
    sliders = [{"type": "UISliderNode", "name": n, "layer": 8,
                "properties": {"size": [520, 36], "label": l, "labelWidth": 170, "minValue": lo, "maxValue": hi,
                               "value": v, "defaultValue": v, "isInteger": n == "TextSpeed"}}
               for n, l, lo, hi, v in (("TextSpeed", "Text speed", 10, 120, 40), ("AutoDelay", "Auto delay (s)", 0.3, 4, 1.2),
                                       ("MusicVolume", "Music", 0, 1, 1), ("SoundVolume", "Sound", 0, 1, 1))]
    title = [
        camera, background(),
        figure("Ada", "ada", 260, True), figure("Theo", "theo", 1020, True),
        {"type": "Node", "name": "Title", "script": {"path": "scripts/title.lua"}},
        label("Name", "The Castle Road", (640, 60), size=80, color="#1e2840ff"),
        label("Endings", "", (640, 660), size=22, color="#1e2840cc"),
        column("Menu", (500, 220), (280, 300), [button("NewGame", "New game"), button("Continue", "Continue"),
                                               button("Load", "Load"), button("Settings", "Settings")]),
        column("SettingsPanel", (340, 190), (600, 300), sliders + [button("SettingsClose", "Done", w=160, h=40, size=20)],
               title="Settings"),
        slots,
    ]
    t.json("scenes/title.scene.json", scene("title", title, background=(20, 22, 30, 255)))

    t.json("project.json", project("Visual Novel", ["scenes/title.scene.json", "scenes/story.scene.json"], MOVE_ACTIONS + [
        action("confirm", "SPACE", "ENTER", "KP_ENTER", "pad:RIGHT_FACE_DOWN"),
        action("cancel", "ESCAPE", "BACKSPACE", "pad:RIGHT_FACE_RIGHT"),
        action("auto", "A", "pad:RIGHT_FACE_LEFT"),
        action("skip", "LEFT_CONTROL", "RIGHT_CONTROL", "pad:RIGHT_TRIGGER_1"),
        action("log", "L", "pad:RIGHT_FACE_UP"),
        action("quick_save", "F5"),
        action("quick_load", "F9"),
    ], virtual=(1280, 720), gravity=(0, 0), pixel=False))
    for s_ in ("story", "vn", "slots", "title"):
        t.script(s_)
    with open(os.path.join(SCRIPTS, "visual_novel", "README.md")) as f:
        t.write("README.md", f.read())
    return t


# --- dungeon (isometric) ------------------------------------------------------------

# The rooms, as text: one character a cell, rows are grid y, columns grid x
# (x runs down-right on screen, y down-left). The back walls are made from
# the edges: x = 0 and y = 0.
#   . floor   # inner wall (on the cell's upper-right edge)   C chest   o a hole (no floor: falls in)
#   D door (top wall)   d door (left wall)   W window (top wall)   w window (left wall)
#   P pillar   b barrel   B barrels   k crates   t table   p woodpile   @ the hero
DUNGEON_ROOMS = [
    # (room, seconds to get out)
    ([
        "...W..D...",
        ".p......b.",
        "..........",
        "...P..P...",
        "w.........",
        "....o.@...",
        ".###....C.",
        ".......t..",
        ".B.P..oo..",
        "........k.",
    ], 60),
    ([
        "...W......",
        "..C.......",
        "....oo....",
        ".P..oo..P.",
        "w.........",
        "d...oo....",
        "..........",
        ".###...b..",
        "....@.....",
        "..k....B..",
    ], 50),
    ([
        "..W....D..",
        "......o...",
        "..oo..o.b.",
        "..oo......",
        "w.....oo..",
        ".P....oo.C",
        "..........",
        ".oo.......",
        ".oo..@..P.",
        "......t...",
    ], 45),
]

DUNGEON_ACTIONS = MOVE_ACTIONS + [action("interact", "E", "ENTER", "SPACE", "pad:RIGHT_FACE_DOWN")]


def dungeon_room(rows, name, room, seconds, style, ink, selected):
    """A room (a scene): the maps, the hero, the HUD, the pause menu."""
    H, W = len(rows), len(rows[0])
    CW, CH = 128, 64      # the diamond cell
    TILE = [128, 144]     # the tile images (taller: walls, pillars)
    OFFSET = [0, 10]      # the floor's slab under its diamond
    ORIGIN = (0, 0)
    FLOOR, FLOOR_VARIANTS = 0, [0, 0, 0, 0, 0, 1, 0]
    WALL_LEFT, WALL_TOP, CORNER_BACK = 9, 10, 14   # (stoneWall_E / _S, stoneWallCorner_S)
    DOOR_LEFT, DOOR_TOP, WINDOW_LEFT, WINDOW_TOP = 17, 18, 25, 26
    PROPS = {"P": 45, "b": 40, "B": 41, "k": 44, "t": 46, "p": 47, "C": 34}

    def center(x, y):
        return [ORIGIN[0] + (x - y) * CW / 2 + CW / 2, ORIGIN[1] + (x + y) * CH / 2 + CH / 2]

    # (A scatter of the variants: a hash of the cell, not a pattern.)
    floor = [[FLOOR_VARIANTS[((x * 73856093) ^ (y * 19349663)) % 97 % len(FLOOR_VARIANTS)] for x in range(W)] for y in range(H)]
    walls = [[-1] * W for _ in range(H)]
    props = [[-1] * W for _ in range(H)]
    hero = (W // 2, H // 2)
    for y in range(H):
        for x in range(W):
            ch = rows[y][x]
            if x == 0 and y == 0:
                walls[y][x] = CORNER_BACK
            elif y == 0:
                walls[y][x] = {"D": DOOR_TOP, "W": WINDOW_TOP}.get(ch, WALL_TOP)
            elif x == 0:
                walls[y][x] = {"d": DOOR_LEFT, "w": WINDOW_LEFT}.get(ch, WALL_LEFT)
            elif ch == "#":
                walls[y][x] = WALL_TOP
            elif ch in PROPS:
                props[y][x] = PROPS[ch]
            elif ch == "o":
                floor[y][x] = -1
            elif ch == "@":
                hero = (x, y)

    def imap(name, grid, layer, ysort=False, solid=False, sort_offset=0, tileset="textures/dungeon.png"):
        n = tilemap(name, tileset, 0, grid, solid=solid, layer=layer, pos=ORIGIN)
        n["tilemap"]["tile_size"] = TILE
        n["properties"].update({"layout": "Isometric", "cellSize": [CW, CH], "tileOffset": OFFSET})
        if ysort:
            n["ySort"] = True
            n["ySortOffset"] = sort_offset
        return n

    walk = imap("Walk", [[-1] * W for _ in range(H)], 1, tileset="")
    del walk["tilemap"]["tileset"]
    hero_anims = {}
    for row in range(8):
        hero_anims[f"idle_{row}"] = ([row * 11], 1, True)
        hero_anims[f"run_{row}"] = ([row * 11 + 1 + k for k in range(10)], 16, True)
    hx, hy = center(*hero)
    children = [
        {"type": "CameraNode", "name": "Camera", "position": [hx, hy], "follow": "../World/Hero",
         "properties": {"isCurrent": True, "followMode": "SingleTarget", "dragType": "SmoothDamp"}},
        {"type": "Node", "name": "Dungeon", "script": {"path": "scripts/dungeon.lua",
                                                       "properties": {"room": room, "time_limit": seconds}}},
        imap("Floor", floor, 1),
        walk,
        {"type": "Node", "name": "Cursor", "layer": 1, "script": {"path": "scripts/cursor.lua"}},
        {"type": "Node", "name": "World", "ySort": True, "children": [
            # (Walls sort at their cell's top: a back wall is behind whoever stands
            # in its cell; props at its middle: in front of whoever is behind.)
            imap("Walls", walls, 2, ysort=True, solid=True, sort_offset=-56),
            imap("Props", props, 2, ysort=True, solid=True, sort_offset=-24),
            {"type": "CharacterMoverNode", "name": "Hero", "position": [hx, hy], "tags": ["player"],
             "shapes": [{"type": "Circle", "radius": 10}],
             "properties": {"controlMode": "Script", "categoryLayers": ["Layer2"], "maskLayers": ["Layer1"]},
             "script": {"path": "scripts/hero.lua"},
             "children": [
                 sprite("Sprite", "textures/hero.png", (11, 8), hero_anims, default="idle_2", pivot=(0.5, 74 / 84), layer=2),
                 {"type": "NavigationAgentNode", "name": "Agent",
                  "properties": {"speed": 150, "radius": 0, "arriveDistance": 4, "repathInterval": 0.5,
                                 "navMap": "../../../Walk", "moveParent": True, "avoidance": False}},
             ]},
        ]},
        text("RoomText", "", (16, 12), size=32, color=ink, layer=7),
        text("KeyIcon", "Key: no", (16, 52), size=32, color="#f5d76eff", layer=7),
        text("Time", "", (16, 92), size=32, color=ink, layer=7),
        text("Lives", "", (1264, 12), size=32, align="Right", pivot=(1, 0), color=ink, layer=7),
        text("Hint", "", (640, 640), size=32, align="Center", pivot=(0.5, 0), color="#ffffffff", layer=7),
        text("Message", "", (640, 120), size=48, align="Center", pivot=(0.5, 0.5), color="#ffffffff", layer=7),
        text("Help", "Click to walk   WASD / arrows walk   E open   Esc pause", (1264, 690), size=32, align="Right",
             pivot=(1, 1), color="#ffffff99", layer=7),
        pause_menu(style, selected),
    ]
    return with_touch(scene(name, children, background=(24, 20, 26, 255)), style["size"], stick=None, buttons=(),
                      pause="pause")


def dungeon():
    t = Template("dungeon", "Isometric Dungeon",
                 "Escape three isometric rooms against the clock: click to walk (path finding round the walls) or "
                 "use WASD, find each room's key, open its door, mind the holes. A title screen, settings, a pause "
                 "menu, saved progress.", "dungeon", 6)
    t.begin()
    t.art("iso-dungeon/tiles.png", "textures/dungeon.png")
    t.art("iso-dungeon/hero.png", "textures/hero.png")
    t.license("Isometric Miniature Dungeon")
    # A small game (#329): three rooms, each with its chest's key and its
    # door, and a time limit; a hole costs a life (three a game), the clock
    # running out ends it. The furthest room and the most time to spare are
    # saved; the title, a pause menu, the result screen.
    ink, red, dark = "#e9dcc2ff", "#e74c3cff", (24, 20, 26, 255)
    levels = [f"scenes/room{i + 1}.scene.json" for i in range(len(DUNGEON_ROOMS))]
    for i, (rows, seconds) in enumerate(DUNGEON_ROOMS):
        t.json(levels[i], dungeon_room(rows, f"room{i + 1}", i + 1, seconds, HD_STYLE, ink, red))
    t.json("scenes/title.scene.json", title_scene("Isometric Dungeon", HD_STYLE, ink, red, dark, level_word="Room"))
    t.json("scenes/result.scene.json", result_scene(HD_STYLE, ink, red, dark))
    t.json("project.json", project("Isometric Dungeon", ["scenes/title.scene.json"] + levels + ["scenes/result.scene.json"],
                                   DUNGEON_ACTIONS + GAME_ACTIONS, virtual=(1280, 720), gravity=(0, 0), pixel=False,
                                   globals_=GAME_GLOBALS))
    for s_ in ("dungeon", "hero", "cursor"):
        t.script(s_)
    game_scripts(t, levels, lives=3, score_name="Time to spare", level_word="Room")
    with open(os.path.join(SCRIPTS, "dungeon", "README.md")) as f:
        t.write("README.md", f.read())
    return t


# --- hex island ---------------------------------------------------------------------

# The island, one character a hex (rows are grid y; odd rows are shifted
# right by half a hex): ~ water, g grass, d dirt, s sand, r stone,
# T tree, P pine, A autumn tree, R rock, b bush, f flower (red / yellow /
# blue in turn), @ the explorer (on grass).
HEX_ISLAND = [
    "~~~~~~~~~~~~~",
    "~~~ssggggs~~~",
    "~~sgTgfggAss~",
    "~sgPgggRgfs~~",
    "~sgg@ggTgggs~",
    "~~sgdddgbs~~~",
    "~sgfgdPgRgfs~",
    "~~ssgAfgss~~~",
    "~~~~sssr~~~~~",
    "~~~~~~~~~~~~~",
]


def hex_island():
    t = Template("hex", "Hex Island",
                 "Explore a little island on a hex grid: click a hex to walk there (paths step hex by hex round "
                 "water, trees and rocks) or step with the keys, and pick every flower.", "map", 7)
    t.begin()
    t.art("hexagon/tiles.png", "textures/hex_tiles.png")
    t.art("hexagon/objects.png", "textures/hex_objects.png")
    t.art("hexagon/alien.png", "textures/explorer.png")
    t.license("Hexagon Tiles")
    rows = HEX_ISLAND
    H, W = len(rows), len(rows[0])
    CW, CH = 65, 66
    GROUND = {"~": 7, "g": 0, "d": 2, "s": 3, "r": 4}
    OBJECTS = {"T": 0, "P": 2, "A": 4, "R": 5, "b": 7}
    FLOWERS = [8, 9, 10]
    ORIGIN = (640 - (W * CW) / 2, 360 - (H * CH * 0.75) / 2 - 20)

    def center(x, y):
        return [ORIGIN[0] + x * CW + (CW / 2 if y % 2 == 1 else 0) + CW / 2, ORIGIN[1] + y * CH * 0.75 + CH / 2]

    ground = [[GROUND.get(rows[y][x], 0) for x in range(W)] for y in range(H)]
    objects = [[-1] * W for _ in range(H)]
    start, nf = (4, 4), 0
    for y in range(H):
        for x in range(W):
            ch = rows[y][x]
            if ch in OBJECTS:
                objects[y][x] = OBJECTS[ch]
            elif ch == "f":
                objects[y][x] = FLOWERS[nf % 3]
                nf += 1
            elif ch == "@":
                start = (x, y)

    def hmap(name, grid, tileset, tile, layer, offset, ysort=False):
        n = tilemap(name, tileset, 0, grid, layer=layer, pos=ORIGIN)
        n["tilemap"]["tile_size"] = tile
        n["properties"].update({"layout": "HexPointy", "stagger": "Odd", "cellSize": [CW, CH], "tileOffset": offset})
        if ysort:
            n["ySort"] = True
        if not tileset:
            del n["tilemap"]["tileset"]
        return n

    sx, sy = center(*start)
    children = [
        {"type": "CameraNode", "name": "Camera", "position": [640, 360], "properties": {"isCurrent": True}},
        hmap("Ground", ground, "textures/hex_tiles.png", [65, 89], 1, [0, 23]),
        hmap("Walk", [[-1] * W for _ in range(H)], "", [65, 89], 1, [0, 0]),
        {"type": "Node", "name": "Island", "layer": 1, "script": {"path": "scripts/island.lua"}},
        {"type": "Node", "name": "World", "ySort": True, "children": [
            hmap("Objects", objects, "textures/hex_objects.png", [65, 107], 2, [0, -25], ysort=True),
            {"type": "Node", "name": "Explorer", "position": [sx, sy], "script": {"path": "scripts/explorer.lua"},
             "children": [{"type": "TextureNode", "name": "Sprite", "position": [0, 6], "pivot": [0.5, 1], "layer": 2,
                           "texture": "textures/explorer.png"}]},
        ]},
        text("Flowers", "Flowers 0 / 0", (16, 12), size=32, color="#ffffffff", layer=7),
        text("Message", "", (640, 60), size=48, align="Center", pivot=(0.5, 0.5), color="#ffe066ff", layer=7),
        text("Help", "Click a hex to walk   D A E Q C Z: one step", (1264, 690), size=32, align="Right",
             pivot=(1, 1), color="#ffffffaa", layer=7),
    ]
    t.json("scenes/island.scene.json", scene("island", children, background=(64, 140, 196, 255)))
    t.json("project.json", project("Hex Island", ["scenes/island.scene.json"], [
        action("step_e", "D", "RIGHT"), action("step_w", "A", "LEFT"),
        action("step_ne", "E"), action("step_nw", "Q"),
        action("step_se", "C"), action("step_sw", "Z"),
    ], virtual=(1280, 720), gravity=(0, 0), pixel=False))
    for s_ in ("island", "explorer"):
        t.script(s_, src="hex")
    with open(os.path.join(SCRIPTS, "hex", "README.md")) as f:
        t.write("README.md", f.read())
    return t


# --- vector character (#272) -------------------------------------------------------
#
# Pip: one hand-drawn SVG (scripts/vector_character/pip.svg) cut into a
# Vector Shape per part under a Skeleton whose bones-only Spine rig is
# written below; a Lip Sync node moves the mouth with a synthesized mumble
# timed to a hand-written Rhubarb cue file.

PIP_ORIGIN = (150, 400)  # the SVG point at the Skeleton's origin: between the feet, on the ground
PIP_PARTS = [  # (part, its bones, skinSmooth), back to front: the SVG's top-level groups
    ("arm_back", "arm_back_upper, arm_back_lower", 14),
    ("leg_back", "leg_back_upper, leg_back_lower", 12),
    ("leg_front", "leg_front_upper, leg_front_lower", 12),
    ("body", "torso", 0),
    ("head", "head", 0),
    ("eyes", "head", 0),
    ("mouth", "head", 0),
    ("arm_front", "arm_front_upper, arm_front_lower", 14),
]


def svg_group_boxes(path):
    """The box of each top-level group of an SVG, as the engine measures a
    part (Vector_PartBox: every point of its paths - curve handles too - and
    no stroke width; hidden frames count). Reads what pip.svg uses: rect,
    circle, ellipse and paths of absolute M L C Q Z."""
    import re
    import xml.etree.ElementTree as ET
    ns = "{http://www.w3.org/2000/svg}"
    boxes = {}
    for g in ET.parse(path).getroot():
        if g.tag != ns + "g":
            continue
        xs, ys = [], []
        for el in g.iter():
            tag = el.tag[len(ns):]
            f = lambda k: float(el.get(k, 0))  # noqa: E731
            if tag == "rect":
                xs += [f("x"), f("x") + f("width")]; ys += [f("y"), f("y") + f("height")]
            elif tag == "circle":
                xs += [f("cx") - f("r"), f("cx") + f("r")]; ys += [f("cy") - f("r"), f("cy") + f("r")]
            elif tag == "ellipse":
                xs += [f("cx") - f("rx"), f("cx") + f("rx")]; ys += [f("cy") - f("ry"), f("cy") + f("ry")]
            elif tag == "path":
                d = el.get("d")
                assert not re.search(r"[^MLCQZ0-9.,\s-]", d), f"svg_group_boxes: {d!r} (absolute M L C Q Z only)"
                nums = [float(n) for n in re.findall(r"-?\d+(?:\.\d+)?", d)]
                xs += nums[0::2]; ys += nums[1::2]
        boxes[g.get("id")] = (min(xs), min(ys), max(xs), max(ys))
    return boxes


def ease_keys(keys, field="value"):
    """Spine 4 keys with ease-in-out Bezier curves (flat at both keys)."""
    out = []
    for i, k in enumerate(keys):
        k = dict(k)
        if i + 1 < len(keys):
            t0, t1 = k["time"], keys[i + 1]["time"]
            v0, v1 = k.get(field, 0), keys[i + 1].get(field, 0)
            dt = t1 - t0
            k["curve"] = [round(t0 + dt / 3, 4), v0, round(t1 - dt / 3, 4), v1]
        out.append(k)
    return out


def rot(*tv):
    """rotate keys from (time, degrees) pairs (Spine's: counter-clockwise, relative to the setup pose)."""
    return ease_keys([{"time": t, "value": v} for t, v in zip(tv[0::2], tv[1::2])])


def pip_rig():
    """Pip's bones-only Spine rig. Spine is y-up with counter-clockwise
    angles (the engine flips it on load). Bones point along their x axis:
    the torso and head up (90), arms and legs down (the arms 180 from the
    torso, the legs -90 from the hip). Lengths reach the next joint."""
    bones = [
        {"name": "root"},
        {"name": "hip", "parent": "root", "y": 130},                                   # (150, 270) in the SVG
        {"name": "torso", "parent": "hip", "rotation": 90, "length": 90},              # up to the neck (150, 180)
        {"name": "head", "parent": "torso", "x": 90, "length": 130},
        {"name": "arm_back_upper", "parent": "torso", "x": 78, "rotation": 180, "length": 55},  # shoulder (150, 192)
        {"name": "arm_back_lower", "parent": "arm_back_upper", "x": 55, "length": 48},
        {"name": "arm_front_upper", "parent": "torso", "x": 78, "rotation": 180, "length": 55},
        {"name": "arm_front_lower", "parent": "arm_front_upper", "x": 55, "length": 48},
        {"name": "leg_back_upper", "parent": "hip", "x": -7, "rotation": -90, "length": 62},   # hip joint (143, 270)
        {"name": "leg_back_lower", "parent": "leg_back_upper", "x": 62, "length": 52},
        {"name": "leg_front_upper", "parent": "hip", "x": 7, "rotation": -90, "length": 62},   # (157, 270)
        {"name": "leg_front_lower", "parent": "leg_front_upper", "x": 62, "length": 52},
    ]
    # A positive rotation swings a hanging limb forward (Pip faces right).
    idle = {  # breathing, 2 s
        "hip": {"translate": ease_keys([{"time": 0, "x": 0, "y": 0}, {"time": 1, "x": 0, "y": 2}, {"time": 2, "x": 0, "y": 0}], "x")},
        "torso": {"rotate": rot(0, 0, 1, -1.5, 2, 0)},
        "head": {"rotate": rot(0, 0, 1, 3, 2, 0)},
        "arm_front_upper": {"rotate": rot(0, 2, 1, 5, 2, 2)},
        "arm_front_lower": {"rotate": rot(0, 6, 1, 10, 2, 6)},
        "arm_back_upper": {"rotate": rot(0, -2, 1, -5, 2, -2)},
        "arm_back_lower": {"rotate": rot(0, 6, 1, 10, 2, 6)},
    }
    W = [0, 0.2, 0.4, 0.6, 0.8]  # a step each 0.4 s: contact, passing, contact, passing, contact

    def cycle(*vals):
        return rot(*[x for pair in zip(W, vals) for x in pair])
    walk = {
        # Lower at the contacts (legs apart), higher passing.
        "hip": {"translate": ease_keys([{"time": t, "x": 0, "y": y} for t, y in zip(W, (-7, 0, -7, 0, -7))], "x")},
        "torso": {"rotate": cycle(-5, -3, -5, -3, -5)},
        "head": {"rotate": cycle(3, 1, 3, 1, 3)},
        "leg_front_upper": {"rotate": cycle(25, 5, -25, 0, 25)},
        "leg_front_lower": {"rotate": cycle(-5, -10, -15, -55, -5)},
        "leg_back_upper": {"rotate": cycle(-25, 0, 25, 5, -25)},
        "leg_back_lower": {"rotate": cycle(-15, -55, -5, -10, -15)},
        "arm_front_upper": {"rotate": cycle(-25, 0, 25, 0, -25)},
        "arm_front_lower": {"rotate": cycle(10, 20, 35, 20, 10)},
        "arm_back_upper": {"rotate": cycle(25, 0, -25, 0, 25)},
        "arm_back_lower": {"rotate": cycle(35, 20, 10, 20, 35)},
    }
    talk = {  # head bobs and a hand that gestures, 1.2 s
        "head": {"rotate": rot(0, 0, 0.2, 5, 0.45, -2, 0.7, 4, 0.95, -1, 1.2, 0)},
        "torso": {"rotate": rot(0, 0, 0.6, -2, 1.2, 0)},
        "arm_front_upper": {"rotate": rot(0, 5, 0.4, 30, 0.8, 20, 1.2, 5)},
        "arm_front_lower": {"rotate": rot(0, 10, 0.4, 70, 0.8, 50, 1.2, 10)},
        "arm_back_upper": {"rotate": rot(0, -3, 0.6, -6, 1.2, -3)},
    }
    return {
        "skeleton": {"spine": "4.2.22", "width": 300, "height": 420,
                     "$comment": "Pip's rig: bones only (the art is art/pip.svg, bent by them). Written by scripts/templates/make_templates.py."},
        "bones": bones,
        "slots": [],
        "skins": [{"name": "default", "attachments": {}}],
        "animations": {"idle": {"bones": idle}, "walk": {"bones": walk}, "talk": {"bones": talk}},
    }


# Rhubarb's mouth shapes as the mumble's sounds: (loudness, formants in Hz).
MUMBLE_SOUNDS = {
    "A": (0.25, (250,)),        # a hum: lips closed
    "B": (0.5, (300, 2300)),    # "ee", a consonant's edge
    "C": (0.8, (530, 1850)),    # "eh"
    "D": (1.0, (750, 1200)),    # "ah"
    "E": (0.85, (500, 900)),    # "oh"
    "F": (0.6, (320, 800)),     # "oo"
    "X": (0.0, ()),             # rest
}


def mumble_wav(cues_tsv, path, rate=22050):
    """A cartoon mumble that says the cue file: each cue's vowel (MUMBLE_SOUNDS)
    as a voice of harmonics shaped by its formants, the pitch wandering round
    a phrase's intonation, gliding from cue to cue; 16-bit mono WAV."""
    import math
    import random
    import struct
    import wave
    cues = []
    for line in cues_tsv.strip().splitlines():
        t, shape = line.split()
        cues.append((float(t), shape))
    end = cues[-1][0] + 0.15
    n = int(end * rate)
    rnd = random.Random(272)
    H = 18  # harmonics
    BLOCK = 64

    def weights(shape, f0):
        loud, formants = MUMBLE_SOUNDS[shape]
        w = []
        for k in range(1, H + 1):
            f = k * f0
            peak = sum(math.exp(-((f - F) / 140.0) ** 2) for F in formants) if formants else 0
            w.append(loud * (0.15 + peak) / math.sqrt(k) if formants else 0.0)
        return w
    # Each cue's pitch: a phrase falling from 240 to 190 Hz, with a wobble.
    pitch = [240 - 50 * (t / end) + rnd.uniform(-18, 18) for t, _ in cues]
    phases = [0.0] * H
    cur = [0.0] * H
    f0 = pitch[0]
    samples = []
    ci = 0
    for b in range(0, n, BLOCK):
        t = b / rate
        while ci + 1 < len(cues) and cues[ci + 1][0] <= t:
            ci += 1
        target_f0 = pitch[ci]
        target = weights(cues[ci][1], target_f0)
        # (Glide over ~15 ms: no clicks between shapes.)
        k = 1 - math.exp(-BLOCK / (rate * 0.015))
        f0 += (target_f0 - f0) * k
        cur = [c + (w - c) * k for c, w in zip(cur, target)]
        for i in range(b, min(b + BLOCK, n)):
            vib = 1 + 0.02 * math.sin(2 * math.pi * 5.5 * i / rate)
            s = 0.0
            for h in range(H):
                if cur[h] < 1e-4:
                    continue
                phases[h] += 2 * math.pi * (h + 1) * f0 * vib / rate
                s += cur[h] * math.sin(phases[h])
            samples.append(s)
    peak = max(abs(s) for s in samples) or 1
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", int(s / peak * 0.6 * 32767)) for s in samples))


def vector_character():
    t = Template("vector_character", "Vector Character",
                 "Pip, a cartoon character drawn as vector art and rigged with bones: walk left and right, "
                 "talk with lip-sync, blink. One SVG cut into parts, a Skeleton, a Lip Sync node.", "bezier-curve", 8)
    t.begin()
    src = os.path.join(SCRIPTS, "vector_character")
    for name, rel in (("pip.svg", "art/pip.svg"), ("backdrop.svg", "art/backdrop.svg"),
                      ("pip_mumble.tsv", "audio/pip_mumble.tsv")):
        with open(os.path.join(src, name)) as f:
            t.write(rel, f.read())
    with open(os.path.join(src, "pip_mumble.tsv")) as f:
        mumble_wav(f.read(), os.path.join(t.dir, "audio", "pip_mumble.wav"))
    t.json("rigs/pip.json", pip_rig())
    t.script("pip")
    t.write("art/LICENSE-ART.txt", "Pip and the backdrop were drawn for Rayzr: the same licence as the engine.\n"
                                   "The voice is synthesized by scripts/templates/make_templates.py.\n"
                                   "Font (fonts/): Kenney Pixel by Kenney (www.kenney.nl), CC0.\n")
    os.rmdir(os.path.join(t.dir, "textures"))  # (no textures: vector art)
    os.rmdir(os.path.join(t.dir, "components"))

    boxes = svg_group_boxes(os.path.join(src, "pip.svg"))
    ox, oy = PIP_ORIGIN
    parts = []
    for name, bones, smooth in PIP_PARTS:
        x0, y0, x1, y1 = boxes[name]
        # Explode into Parts' layout: the part's centre, where it was drawn.
        props = {"file": "art/pip.svg", "group": name, "skinBones": bones, "skinSmooth": smooth}
        if name in ("eyes", "mouth"):
            props["frame"] = 0  # (eyes open, the mouth at rest)
        parts.append({"type": "VectorShapeNode", "name": "".join(w.title() for w in name.split("_")),
                      "position": [(x0 + x1) / 2 - ox, (y0 + y1) / 2 - oy], "properties": props})
    children = [
        {"type": "CameraNode", "name": "Camera", "position": [640, 360], "properties": {"isCurrent": True}},
        {"type": "VectorShapeNode", "name": "Backdrop", "position": [0, 0], "pivot": [0, 0], "layer": 0,
         "properties": {"file": "art/backdrop.svg"}},
        {"type": "Node", "name": "Pip", "position": [640, 640], "layer": 2,
         "script": {"path": "scripts/pip.lua"},
         "children": [
             {"type": "SkeletonNode", "name": "Rig",
              "properties": {"file": "rigs/pip.json", "animation": "idle", "loop": True, "autoplay": True,
                             "mixTime": 0.2},
              "children": parts},
             {"type": "LipSyncNode", "name": "LipSync",
              "properties": {"mouth": "../Rig/Mouth", "sound": "audio/pip_mumble.wav"}},
         ]},
        text("Help", "A / D or arrows: walk    T: talk", (640, 40), size=32, align="Center", pivot=(0.5, 0.5),
             color="#24425cff"),
    ]
    sc = with_touch(scene("pip", children, background=(143, 208, 242, 255)), (1280, 720),
                    stick=("move_left", "move_right", "", ""), buttons=(("talk", "T"),))
    t.json("scenes/pip.scene.json", sc)
    t.json("project.json", project("Vector Character", ["scenes/pip.scene.json"], MOVE_ACTIONS[:2] + [
        action("talk", "T", "pad:RIGHT_FACE_DOWN"),
    ], virtual=(1280, 720), pixel=False))
    with open(os.path.join(src, "README.md")) as f:
        t.write("README.md", f.read())
    return t


TEMPLATES = {"platformer": platformer, "rpg": rpg, "shmup": shmup, "puzzle": puzzle, "adventure": adventure,
             "visual_novel": visual_novel, "dungeon": dungeon, "hex": hex_island, "vector_character": vector_character}

if __name__ == "__main__":
    which = sys.argv[1:] or list(TEMPLATES)
    for name in which:
        tpl = TEMPLATES[name]()
        print(f"templates/{tpl.id}")
