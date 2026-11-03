package editor

import "core:strings"
import "core:testing"
import e "../engine"

// #374: a Behavior Tree node dropped onto a sibling takes its place (after
// a right sibling, before a left one); drops that can't happen say so
// before anything is recorded.
@(test)
test_btg_drop_target :: proc(t: ^testing.T) {
	game := new(e.Game)
	e.InitializeGame(game)
	defer game->terminate()
	scene := game->createScene("btg", true)
	e.ProcessSceneChange(&game.sceneManager, &game.gameContext)
	bt := cast(^e.BehaviorTreeNode)e.Node_CreateByTypeName(scene, "BehaviorTreeNode")
	e.ProcessNodeQueues(scene.manager, &game.gameContext)
	root := e.BT_AddNode(bt, -1, .Sequence)
	a := e.BT_AddNode(bt, root, .Wait)
	b := e.BT_AddNode(bt, root, .Wait)
	c := e.BT_AddNode(bt, root, .Wait)
	sel := e.BT_AddNode(bt, root, .Selector)
	inv := e.BT_AddNode(bt, sel, .Inverter)
	order :: proc(bt: ^e.BehaviorTreeNode, p: int) -> string {
		sb := strings.builder_make(context.temp_allocator)
		for ch in bt.nodes[p].children do strings.write_int(&sb, ch)
		return strings.to_string(sb)
	}
	move :: proc(bt: ^e.BehaviorTreeNode, from, onto: int) -> bool {
		parent, at, ok := Btg_DropTarget(bt, from, onto)
		if ok do e.BT_MoveNode(bt, from, parent, at)
		return ok
	}
	testing.expect_value(t, order(bt, root), "1234")
	// a onto its right sibling c: after c (it was just before: off by one).
	testing.expect(t, move(bt, a, c), "a onto c")
	testing.expect_value(t, order(bt, root), "2314")
	// a onto its left sibling b: before b.
	testing.expect(t, move(bt, a, b), "a onto b")
	testing.expect_value(t, order(bt, root), "1234")
	// The neighbour on the right: they swap.
	testing.expect(t, move(bt, b, c), "b onto c")
	testing.expect_value(t, order(bt, root), "1324")
	// Onto a node that isn't a sibling (a decorator): its child; then it's full.
	testing.expect(t, move(bt, a, inv), "a into the inverter")
	testing.expect_value(t, order(bt, inv), "1")
	testing.expect_value(t, order(bt, root), "324")
	_, _, ok := Btg_DropTarget(bt, b, inv)
	testing.expect(t, !ok, "a full decorator refuses")
	_, _, ok = Btg_DropTarget(bt, b, a)
	testing.expect(t, !ok, "a leaf refuses")
	_, _, ok = Btg_DropTarget(bt, sel, inv)
	testing.expect(t, !ok, "not into its own subtree")
	_, _, ok = Btg_DropTarget(bt, root, b)
	testing.expect(t, !ok, "the root stays")
	free_all(context.temp_allocator)
}
