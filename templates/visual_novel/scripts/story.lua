-- The story: who's in it and what happens. vn.lua plays it; change this file
-- (and add pictures to textures/) to tell your own.
--
-- A chapter is a list of steps, played in order:
--
--   "Some narration."                       -- a line with no speaker
--   { "ada", "Hello!" }                     -- a character speaks (a key of `characters`)
--   { "ada", "Hello!", pose = "cheer" }     -- ...and changes pose while saying it
--   { bg = "forest" }                       -- the background: textures/bg_forest.png
--   { show = "ada", at = "left" }           -- a character steps in: left, center or right
--   { show = "ada", pose = "think" }        -- (shown already: a new pose / place)
--   { hide = "ada" }                        -- ...and steps out
--   { set = "kind" }                        -- a flag: true (or { set = "coins", value = 3 })
--   { jump = "ending" }                     -- go on in another chapter
--   { jump = "ending", when = "kind" }      -- ...only if the flag is set
--   { choice = "Where to?", options = {     -- the player picks; each option jumps
--       { "The forest", "forest" },
--       { "Back home", "home", set = "careful" },  -- (sets a flag too)
--       { "Ask Unit", "ask", need = "kind" },      -- (only shown when a flag is set)
--   } }
--   { the_end = "The good ending" }         -- the end: back to the title screen
--   { the_end = "Lost", bad = true }        -- a bad ending: the story lost (try other choices)
--
-- Text can use rich-text tags: [color=yellow]...[/color], [wave]...[/wave],
-- [shake]...[/shake].

---@class Story : ScriptInstanceBase
local Story = {}

-- Pictures: textures/<key>_<pose>.png (poses: idle, talk, think, cheer, hurt).
Story.characters = {
    ada = { name = "Ada" },
    theo = { name = "Theo" },
    unit = { name = "Unit-7" },
}

Story.chapters = {
    start = {
        { bg = "castle" },
        "The road to the old castle was quiet. Too quiet, Ada thought.",
        { show = "ada", at = "left" },
        { "ada", "Theo, are you sure this is the way?", pose = "talk" },
        { show = "theo", at = "right" },
        { "theo", "Sure? No. Hopeful? [wave]Very.[/wave]", pose = "cheer" },
        { "ada", "Wonderful.", pose = "think" },
        "Something clanked in the bushes beside the road.",
        { show = "unit", at = "center", pose = "hurt" },
        { "unit", "[shake]ERROR. ERROR.[/shake] Please do not be alarmed. I am lost." },
        { "theo", "A robot! A talking robot!", pose = "cheer" },
        { "ada", "What do we do with it?", pose = "think" },
        { choice = "What does Ada do?", options = {
            { "Help it find its way", "help", set = "kind" },
            { "Keep going - the castle can't wait", "castle" },
        } },
    },

    help = {
        { "ada", "Where are you trying to go, Unit...?", pose = "talk" },
        { show = "unit", pose = "talk" },
        { "unit", "Unit-7. I was sent to the forest to water the tall trees. I took a wrong turn. Several." },
        { "theo", "The forest is right over the hill. We can take you.", pose = "talk" },
        { bg = "forest" },
        { show = "unit", pose = "cheer" },
        { "unit", "Trees! Thank you, kind humans. I will remember this." },
        { "unit", "Take this. I found it under a rock. I do not know what it opens." },
        { set = "key" },
        "Unit-7 hands Ada a small, rusty key.",
        { jump = "castle" },
    },

    castle = {
        { bg = "castle" },
        { hide = "unit" },
        { show = "ada", at = "left", pose = "idle" },
        { show = "theo", at = "right", pose = "idle" },
        "The castle gate is shut. A heavy lock hangs from the bars.",
        { "theo", "Locked. Of course it's locked.", pose = "hurt" },
        { jump = "open_gate", when = "key" },
        { "ada", "We'll have to find another way in.", pose = "think" },
        { choice = "Another way in...", options = {
            { "Climb the wall", "climb" },
            { "Wait for someone to come out", "wait" },
        } },
    },

    open_gate = {
        { "ada", "Wait - Unit-7's key!", pose = "cheer" },
        "The key turns. The gate swings open with a long, happy creak.",
        { "theo", "Being nice to robots. Who knew?", pose = "cheer" },
        { the_end = "The kind ending" },
    },

    climb = {
        { "ada", "Give me a hand, Theo.", pose = "talk" },
        "Halfway up, a stone gives way.",
        { "ada", "Ow.", pose = "hurt" },
        { "theo", "Maybe we come back tomorrow. With a ladder.", pose = "think" },
        { the_end = "The bumpy ending", bad = true },
    },

    wait = {
        { bg = "talltrees" },
        "They wait. And wait. The sun goes down behind the tall trees.",
        { "theo", "I think the castle is closed on Tuesdays.", pose = "think" },
        { "ada", "It's Wednesday, Theo.", pose = "think" },
        { the_end = "The patient ending" },
    },
}

return Story
