## Use it for

- **Translated text**: put the texts in CSV tables in the project's `locale/` folder (`key,en,fr,...`) and show them with `tr("menu.start")`, or mark a [Text](../nodes/TextNode.md) or dialogue box **Localized** so its text is a key.
- **A language option**: `Locale.languages()` lists the tables' languages, `Locale.set("fr")` switches, `Locale.get()` says which one is on.
- **Per-language details**: check `Locale.get()` to swap a flag image or a font that the tables can't hold.

## Example

A button in the options menu that cycles through the project's languages. `Locale.set` remembers the choice, so the game starts in it next time. The script is on a [Button](../nodes/UIButtonNode.md).

```lua
---@class LanguageButton : ScriptInstanceBase
local LanguageButton = {}

function LanguageButton:ready()
    self:refresh()
end

function LanguageButton:on_clicked()
    local langs = Locale.languages()
    if #langs == 0 then return end
    local current = Locale.get()
    local next_index = 1
    for i, lang in ipairs(langs) do
        if lang == current then next_index = i % #langs + 1 end
    end
    Locale.set(langs[next_index])
    self:refresh()
end

function LanguageButton:refresh()
    self.node.text = tr("options.language", { name = Locale.get() })
end

return LanguageButton
```

With a table row like `options.language,"Language: {name}","Langue : {name}"`.

## Notes

- **The player's choice is remembered.** `Locale.set(lang)` saves it next to the save files, and the game starts in it next time instead of Project Settings > General > **Language**. `Locale.set(lang, false)` switches without remembering (a preview).
- **Localized nodes update by themselves** when the language changes. Text you set with `tr` is a one-time copy: set it again after `Locale.set`.
- **Missing texts fall back**: a key with no text in the current language shows another language's text, then the key itself. `Locale.set` refuses a language the tables don't have: it returns false, logs a warning and keeps the current one.
- Tables are re-read when they change, so editing a CSV updates a running game.
