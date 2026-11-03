-- Tests for the saves (the editor's Tests tab runs them). The tests run
-- with a save folder of their own, shared by the whole run, so each test
-- empties the slots first.

local function empty_slots()
    for n = 1, Game.SLOTS do Game:delete_slot(n) end
end

-- Reads slot n back from its file, as the next run would: switching to
-- another slot and back reads the file again.
local function reread(n)
    Game:open_slot(n % Game.SLOTS + 1)
    return Game:open_slot(n)
end

function test_mined_gems_are_saved()
    empty_slots()
    Game:new_game(1)
    Test.load_scene("scenes/main.scene.json")
    for _ = 1, 3 do
        Test.press_key("SPACE")
        Test.step(4)
    end
    Test.expect_eq(Game.data.gems, 3, "three gems mined")
    Save.flush()
    local saved = reread(1)
    Test.require(saved ~= nil, "slot 1 has a game")
    Test.expect_eq(saved.gems, 3, "the file has the three gems")
end

function test_version_1_save_is_migrated()
    empty_slots()
    Save.slot("slot_1")
    Save.set("game", { version = 1, score = 42 })
    Save.flush()
    local data = reread(1)
    Test.require(data ~= nil, "slot 1 has a game")
    Test.expect_eq(data.gems, 42, "score became gems")
    Test.expect_eq(data.level, 1, "pick level 1")
    Test.expect_eq(data.version, Game.SAVE_VERSION, "the current version")
    Test.expect(data.score == nil, "no score left")
end

function test_delete_empties_the_slot()
    empty_slots()
    Game:new_game(2)
    Game:delete_slot(2)
    Test.expect(reread(2) == nil, "slot 2 is empty")
end
