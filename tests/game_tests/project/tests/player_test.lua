local function player() return Scene.find_node("Player") end

function test_starts_fresh()
    Test.expect_eq(player():get_script().jumps, 0, "no jumps yet")
    Test.expect_eq(Scene.get_name(), "main", "the first scene")
end

function test_jump_press()
    local _, y = player():get_position()
    Test.press("jump")
    Test.step(5)
    local _, y2 = player():get_position()
    Test.expect_near(y2, y - 10, 0.01, "one jump moves 10 px")
    Test.expect_eq(player():get_script().jumps, 1, "jumps")
end

function test_dash_hold()
    local x = player():get_position()
    Test.hold("dash")
    Test.step(10)
    Test.release("dash")
    Test.step(3)
    local x2 = player():get_position()
    Test.expect_near(x2, x + 20, 0.01, "dash 2 px a frame")
end

function test_wait_until()
    Test.press_key("SPACE")
    local ok = Test.wait_until(function() return player():get_script().jumps >= 1 end, 30)
    Test.expect(ok, "the jump arrived")
end

function test_load_scene()
    Test.load_scene("other")
    Test.require(Scene.find_node("Sign") ~= nil, "the other scene is up")
    Test.expect(Scene.find_node("Player") == nil, "the player's scene is gone")
end

function test_fails_on_purpose()
    Test.expect(false, "this one fails")
    Test.expect_eq(1 + 1, 3, "math")
end

function test_errors_on_purpose()
    local t = nil
    return t.field
end

function test_skipped()
    Test.skip("not ready")
    Test.fail("never reached")
end

function test_times_out()
    Test.timeout(30)
    Test.wait_until(function() return false end, 1000)
end

local function test_not_a_test() end
