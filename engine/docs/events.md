# Global events (the event bus)

## What it is, and why

Node events need the node: to hear a button's `clicked` you `connect` to
that button. That fits parents and children, but a lot of a game's
messages have no natural owner:

- gameplay -> UI: `score_changed`, `player_died`, `coin_collected`
- a level -> the game flow: `level_complete`, `checkpoint_reached`
- audio, effects and achievements reacting to gameplay
- independently placed components (an enemy, a HUD) that never find each other

The **event bus** carries named events from anyone to anyone. A script
**emits** `"score_changed"`; every script that **connected** to
`"score_changed"` hears it - neither side holds a reference to the other.
The bus belongs to the game, so it keeps working across scene changes.

## The short version

```lua
-- The HUD listens...
function Hud:ready()
    Events.connect("score_changed", function(score)
        self.node:get_child("Score").text = tostring(score)
    end)
end

-- ...and the coin, wherever it is, tells everyone.
function Coin:on_body_entered(other)
    GameState.score = GameState.score + 10
    Events.emit("score_changed", GameState.score)
    self.node:queue_free()
end
```

The connection is released when the HUD's node is destroyed: nothing to
clean up.

## The Lua API (`Events`)

| Call | |
|---|---|
| `Events.connect(event, fn [, scope])` -> id | `fn(value, source)` runs on every emit of `event`. |
| `Events.once(event, fn [, scope])` -> id | The same, released after the first call. |
| `Events.disconnect(id)` -> bool | Removes a connection early. |
| `Events.emit(event [, value [, source]])` | Delivers now: every handler has run when `emit` returns. |
| `Events.emit_deferred(event [, value [, source]])` | Delivers at the end of the frame. |
| `Events.listener_count(event)` -> integer | Handlers listening (Lua and engine code). |

- **value** can be anything - a number, a string, a node, a table:
  `Events.emit("enemy_killed", { kind = "slime", points = 50 })`. Lua
  handlers get the value itself (the same table). Engine (Odin) listeners
  get numbers, strings, booleans and nodes; a table arrives there as nil.
  The same goes for `node:emit`: Lua handlers and `on_<event>` methods get
  the table itself.
- **source** is the node of the script that called `emit` (nil from global
  code), or the node you pass. Handlers can use it to know who is talking:
  `function(value, source) if source == self.target then ... end end`.
- Event names are plain strings. Names your scripts emit complete in the
  Code tab for `Events.connect` / `Events.emit` (as for `node:emit`).

### Order and re-entrancy

- Engine listeners run first, then the Lua handlers, each in the order they
  were connected.
- A handler may emit (events nest: the inner one is delivered before the
  outer `emit` continues), connect, disconnect or destroy nodes. A handler
  disconnected by an earlier one in the same emit doesn't run; one connected
  during an emit runs from the next emit.
- An error in a handler is reported (Debug panel / log) and the other
  handlers still run.

### Deferred events

`Events.emit_deferred` queues the event; the queue is delivered once per
frame, after every node has updated (and in the editor's *Simulate*, after
its update). Events are delivered in the order they were emitted; events
emitted by a handler while the queue is delivered wait for the next frame.
Use it when the emitter is in the middle of something the listeners
shouldn't interrupt - e.g. an enemy dying during a physics callback,
where a handler might destroy more nodes.

A source destroyed before the delivery arrives as nil (so does a node
passed as the value).

### Lifetimes

- A connection made by a script ends when that script's node is destroyed
  (a scene change destroys the scene's nodes, and so their connections).
- With a **scope** node, the connection also ends when that node goes:
  `Events.connect("wave_started", fn, self.node:get_parent())`.
- A **global script**'s connections (Project Settings > Globals) last for
  the whole game - the place for listeners that outlive scenes (music,
  achievements, analytics).
- Like node events, the bus doesn't deliver to Lua while you are editing;
  it does in *Simulate* and in the game.

## From engine code (Odin)

The bus is `game.events` (`engine/event_bus.odin`); a node reaches it as
`&node.gameContext.game.events`.

```odin
on_player_died :: proc(source: rawptr, value: EventValue, ctx: ^GameContext, user_data: rawptr) {
	banner := cast(^Node)user_data
	banner.renderable = true // (what node:set_visible(true) does)
}

id := EventBus_Subscribe(&game.events, "player_died", on_player_died, banner, scope = banner)
EventBus_Publish(&game.events, "player_died", int(0), source = player)        // now
EventBus_PublishDeferred(&game.events, "player_died", int(0), source = player) // end of frame
EventBus_Unsubscribe(&game.events, "player_died", id)
```

`source` is the publishing `^Node` (or nil). A subscription with a `scope`
node ends when that node is destroyed; others last until unsubscribed or
until the game ends. Lua's emits reach Odin listeners and Odin's publishes
reach Lua handlers.

## Tutorial: a HUD that never looks for the player

1. Make a global script `scripts/game_state.lua` (Project Settings >
   Globals, name `GameState`) holding `score = 0` and `lives = 3`.
2. On the player, when it gets hurt:

   ```lua
   function Player:hurt()
       GameState.lives = GameState.lives - 1
       Events.emit("lives_changed", GameState.lives)
       if GameState.lives == 0 then Events.emit_deferred("player_died") end
   end
   ```

3. On the HUD (a UI scene or component, anywhere in the tree):

   ```lua
   function Hud:ready()
       Events.connect("lives_changed", function(lives)
           self.node:get_child("Lives").text = "x" .. lives
       end)
       Events.once("player_died", function()
           self.node:get_child("GameOver"):set_visible(true)
       end)
   end
   ```

4. In the game flow global script, change scene when the player dies:

   ```lua
   function GameState:ready()
       Events.connect("player_died", function()
           Scene.change_scene("game_over", { transition = "fade" })
       end)
   end
   ```

The player, the HUD and the game flow only share event names. Replace the
HUD, add a sound that plays on `lives_changed`, or test the HUD on its own
by emitting from the Lua console - nothing else changes.

## Limits

- Event names aren't declared up front; a typo means nobody listens.
  `Events.listener_count` helps check.
- Handlers are called directly (no priorities, no wildcards, no channels).
- Undelivered deferred events are dropped when the game quits.
