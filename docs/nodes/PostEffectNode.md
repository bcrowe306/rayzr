## Settings

A Post Effect's settings are its **Material** (Inspector > Material): the
shader applied to the whole screen and its parameters. Built-in shaders:
`builtin:vignette` (the default), `builtin:crt`, `builtin:pixelate`,
`builtin:chromatic`, `builtin:grayscale`, `builtin:wave`, `builtin:flash`,
`builtin:dissolve`, `builtin:outline`, `builtin:passthrough` - or a `.fs`
fragment shader of your own. In the editor, post effects show in the
viewport while the toolbar's lighting preview (the sun button) is on.

Several post effects chain in tree order; disable one (its enabled toggle)
to skip it. A hit flash, for example:

```lua
-- On the player, with a PostEffect child named "Flash" (builtin:flash), disabled.
function Player:hurt()
    self.flash = self.node:get_node("Flash")
    self.flash.enabled = true
    self.flash_left = 0.1 -- seconds
end

function Player:update(dt)
    if self.flash_left then
        self.flash_left = self.flash_left - dt
        if self.flash_left <= 0 then
            self.flash.enabled = false
            self.flash_left = nil
        end
    end
end
```
