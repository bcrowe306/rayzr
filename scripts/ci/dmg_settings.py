# dmgbuild settings for the editor's drag-to-install disk image
# (scripts/ci/archive_editor.sh passes -D app=<.app> -D background=<png>):
# the app on the left, an Applications link on the right, the window's
# background (branding/dmg/, scripts/ci/dmg_background.py: the arrow and the
# hint line up with icon_locations), the app's icon as the volume's.
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild provides `defines`)
app_name = os.path.basename(app)

# ULFO (LZFSE): smaller than UDZO; opens on macOS 10.11+ (the editor needs 12.0).
format = "ULFO"
filesystem = "HFS+"
size = None  # (dmgbuild measures the files)

files = [app]
# (Not hide_extensions: it sets Finder info on the bundle, which breaks
# `codesign --verify --strict` on the copied app.)
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")
background = defines["background"]  # noqa: F821 (its @2x beside it is picked up)

window_rect = ((200, 120), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
include_list_view_settings = False

icon_size = 128
text_size = 13
arrange_by = None
label_pos = "bottom"
icon_locations = {
    app_name: (160, 180),
    "Applications": (480, 180),
}
