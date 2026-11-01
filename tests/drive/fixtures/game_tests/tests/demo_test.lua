-- The Tests panel drive (tests/drive/game_tests.drive): one passes, one fails.
function test_ship_is_there()
    Test.step(2)
    Test.expect(Scene.find_node("PlayerShip") ~= nil, "the player ship")
end

function test_fails_on_purpose()
    Test.expect_eq(1 + 1, 3, "math")
end
