# Drop-click: review and build plan

Status: plan, 2026-11-20 (Fable). Reviews Opus's findings in the scratchpad `drop-review.md`
and the unbuilt design `docs/stack-move-ux.md` against the code at f5d47af. Scope:
`godot/scripts/main.gd` and `godot/scripts/board_view.gd`. The engine, `_ok`, `_next_targets`
and `_ptn_for` are correct and stay as they are.

Settled by Stuart and not reopened here: the wheel sets the pick-up count and the per-square
drop count; no double-click-drop-all; no click-the-source-to-put-one-back.

## 1. Verdict on the findings

| # | Finding | Verdict |
|---|---|---|
| 1 | Picking ignores stack height | **Right, and worse than stated.** Checked: 4x4 camera sits at about 39.5 degrees, so a point h above the board picks 1.2h further back. The self-test's own b1 stack (three flats, 0.6 tall) picks as b2 from the default yaw. Any stack of three or more, every wall, and every lifted hand is mis-picked. "Behind" rotates with the orbit, so the fix must be geometric, not a yaw-specific offset. Column boxes (below) are yaw-independent. |
| 2 | Wheel can empty the hand with no visible change; two commit rules | **Half right.** The invisible state is real and is fixed by drawing the dealt stones. The "two rules" diagnosis is wrong: the rule is *a board click commits, a dial never does*, and that is one rule once the wheel-emptied state is drawn as the finished move and named ("ready"). See section 2. |
| 3 | Default carry may have no target | **Right, narrow.** Only one case exists: a capstone on a stack whose every enterable neighbour is a wall (cap must travel alone to flatten), so carry 1 is legal and carry 2+ is not. Opus's fix is right and cheap. A second, uncaught case: a stack with no legal move at all (flat top, walled in) selects and shows no rings. Both go in increment 1. |
| 4 | Dealt stones invisible | **Right; the main item.** Real nodes, no tint (section 2). |
| 5 | No take-back-one; right-click discards all | **Right.** Right-click (and Backspace) step back one stone; Esc cancels. Needed because the wheel only edits the *current* square; earlier squares are otherwise reachable only by cancelling. |
| 6 | Source click should put one back | **Rejected.** Stuart settled this in favour of the wheel. One meaning for clicking the source: put everything back. During dealing it also stays "cancel"; a third gesture for "step back" would duplicate right-click. |
| 7 | Commit the moment the hand is empty, by wheel too | **Rejected** (section 2). |
| 8 | Illegal clicks ignored silently | Right but deferred; the engine gives no reason strings and the hover/rings already say where you may click. |
| 9 | Digits 1-8 while dealing | **Right, cheap** once `_adjust_drop` becomes `_set_drop(want)`. It is the fastest "shove the whole stack one square": click, click, press N, click. |
| 10 | Wheel edits only the current square | Agreed, fine with 5. |

Missing from both reviews:

- **Commit animation.** Once dealt stones are drawn where they land, `_play_human` must not let
  `_slides_for` fly them in from the source again. `_refresh(false, ptn)` for dealt moves; the
  engine's reply keeps its animation. Compute "was dealing" *before* `sel` is cleared.
- **Stacked tweens.** `set_lift` creates a new tween per call without killing the last; a fast
  wheel leaves two tweens fighting over one node. The preview must keep one tween per node.
- **Stack-count badges go stale** while stones are dealt away. Hide the badges of the source and
  dealt squares during a preview; restore on clear. No provisional numbers (the old design's
  billboard labels are cut: the stones are visible and countable).
- **Hover uses `_pick` too**, so the hover tile currently also slides one square back over tall
  stacks; the picking fix repairs both.
- **The self-test cannot fail.** It prints "expect" strings and always exits 0; Opus read the
  prints by eye. Increment 0 adds `_check` and a non-zero exit so every later increment has
  a real done-condition.
- **Old design's `hand_square_hit`** (one box for the hand) is not enough now: tall *unlifted*
  stacks mis-pick too. One mechanism, column boxes for every square, covers the hand, the dealt
  piles and plain stacks, from every yaw.

## 2. Decisions

**Commit rule: a board click commits; wheel and digit keys only set numbers.** The wheel is a
dial with notches that overshoot; if reaching "all remaining here" played the move, every
scroll-up to the maximum would commit, with the engine then thinking and Undo taking back its
reply as well. With click-commit the player can wheel to "all here", look, wheel back, and move
on. The state where the hand is empty but nothing has been clicked is a proper state, **ready**:
every stone is drawn on its square, gold ring on the source, one green ring on the current
square, HUD "Hand empty: click c1 to play". The two paths to an empty hand are then: a click
that drops the last stone plays at once (the click *is* the commit), a wheel/digit that drops
the last stone shows the finished board and waits for the click. One rule, stated in the HUD.

**Take-back, cancel, put-back with the wheel present:**

- Pick-up phase: wheel/digits set n in [1, max] but skip values with no legal first target.
  Wheel-down stops at 1; it never cancels. Right-click, Esc and clicking the source cancel.
- Dealing: wheel/digits set the current square's count in [1, current + in hand]; wheel-down
  stops at 1 (it does not pop the square; a jump back a square on a scroll would surprise).
  **Right-click or Backspace = take one back**: `drops[-1] -= 1`; pop at 0; if `drops` is
  empty, `dir = ""` and the hand is back over the source with n unchanged; right-click in
  pick-up = cancel (unchanged there). Esc and source-click = cancel everything. This is the one
  habit change for an existing player and the README says so.

**Dealt stones are drawn on their squares as the real nodes, untinted.** The board *is* the
preview. Each lifted node of the source stack is offset (still a child of the source root) to
`square_pos(dest) - square_pos(src)` at `base_top[dest] + k * FLAT_H`; the hand hovers at
`LIFT` above the current square's provisional top. Orbit does not touch this: the camera
orbits, the board does not rotate, so node positions are yaw-independent. Picking is by
per-square column boxes (`AABB.intersects_ray`, nearest hit, plane as fallback) whose heights
include dealt stones and the hand, so "click the hand to drop one more" and "click a tall stack
to pick it up" work from every yaw. A column can only steal clicks from squares *behind* it
along the ray, which is what the eye expects.

Accepted imperfections: a cap dealt onto a wall is previewed standing on the upright wall; the
commit rebuild may shift dealt stones by the per-square jitter (millimetres).

## 3. Build order

Each increment is one Sonnet brief, verified by the self-test exit code plus one screenshot where
noted. Ship in this order; stop after any increment and the game is still better than before.

### Increment 0: the self-test can fail (tiny, first)

`main.gd`:
- `var _fails := 0` and `func _check(ok: bool, what: String) -> void` (prints `ok: what` or
  `FAIL: what`, counts fails).
- Convert every existing "(expect ...)" print in `_run_selftest` to a `_check`. The pick
  round-trip loops already count fails; route them through `_check`.
- End of `_run_selftest`: `get_tree().quit(1 if _fails > 0 else 0)`.
- Whatever script runs the self-test must propagate Godot's exit code (do not swallow it with a
  pipe to `tee` without `pipefail`).

Done when: exit 0 today; flipping one expected value gives exit 1 and a `FAIL:` line (Opus
checks this once by hand and reverts).

### Increment 1: picking by column; legal carry defaults (bugs 1 and 3)

`board_view.gd`:
- `const FOOT := 0.62` (column footprint; stones are 0.62, caps narrower, jitter 0.012).
- `var _base_top := {}` (sq -> top height from `_build_stack`) and `var _col_top := {}` (sq ->
  pick height; equals base unless lifted/previewed). `show_position` resets both;
  `_build_stack` sets `_base_top[sq] = top_y` and `_col_top[sq] = top_y`.
- `func pick(origin: Vector3, dir: Vector3) -> String`: for each sq in `_col_top`, build
  `AABB(square_pos(sq) - Vector3(FOOT/2, 0, FOOT/2), Vector3(FOOT, _col_top[sq] + 0.001, FOOT))`
  and test `intersects_ray(origin, dir)`; keep the hit nearest `origin`; return its square. No
  hit: intersect `Plane(Vector3.UP, BOARD_TOP)` and return `world_to_square(hit)` or `""`.
  Assumes the view node sits at the origin unrotated (it does); say so in a comment.
- `set_lift(sq, n)`: also sets `_col_top[sq] = _base_top[sq] + LIFT` for the lifted square and
  restores every other square to `_base_top`. (Replaced by `set_preview` in increment 2.)

`main.gd`:
- `_pick(pos)`: `return view.pick(camera.project_ray_origin(pos), camera.project_ray_normal(pos))`.
- `func _legal_carries(src: String) -> Array`: n from `_max_carry(src)` down to 1 for which
  some direction has `_ok(n, src, dir, [1])`. (Temporarily set `sel` or factor `_next_targets`
  to take `(src, n)`; the factoring is cleaner: `_first_targets(src, n) -> Array`, used by both.)
- `_begin_move(src)`: `var ns := _legal_carries(src)`; if empty, return without selecting;
  else n = `ns[0]`.
- `_set_carry(n)`: ignore n not in `_legal_carries`. `_adjust_carry(delta)` in pick-up: step
  from n by `delta` until a legal value or past [1, max]; nothing happens if none.

Self-test assertions (4x4 b1 scenario, b1 = "111"):
1. `_pick(camera.unproject_position(view.square_pos("b1") + Vector3(0, 0.58, 0))) == "b1"` at
   yaw 0, 90, 180 and 270 (`_orbit(.., false)` between; the plane pick returns b2 at yaw 0 today).
2. After `_click("b1")` (hand lifted), the same probe at height 0.8 still returns "b1".
3. `_pick(unproject(square_pos("c2"))) == "c2"` with the stack present (an unoccluded empty
   square is unaffected).
4. New 5x5 scenario, walled-in flat: `a5, e1, c3, Sc4, a1, Sb3, b1, Sd3, a2, Sc2`; white to move;
   `_click("c3")` leaves `sel` empty.
5. New 5x5 scenario, walled-in cap: `a5, e1, c3, Sc4, Cb3, Sd3, b3>, Sb3, a1, Sc2`; c3 ==
   "11C"; `_click("c3")` gives `sel.n == 1` and four targets; `_set_carry(2)` and
   `_adjust_carry(1)` leave n == 1.

Done when: exit 0 and a `--stackdemo` screenshot at `--yaw=90` looks as before.

### Increment 2: the board is the preview (item 4, the ready state)

`board_view.gd`:
- `_build_stack`: `piece.set_meta("home", piece.position)` and `piece.set_meta("h", h)`;
  keep the badge node in `_badges[sq]` (reset in `show_position`).
- Hoist the direction table out of `_slides_for` into `const DIRS` and add
  `_step(sq: String, dir: String, k: int) -> String` (`""` off the board).
- `set_preview(src: String, n: int, dir: String, drops: Array)` replaces `set_lift`:
  - `src == ""`: tween every node to its `home`, `_col_top = _base_top.duplicate()`, re-show
    badges per `counts_visible`, return.
  - Hand nodes are the top n of `_nodes[src]`, bottom first. Walk `drops`: the first `drops[0]`
    nodes go to `_step(src, dir, 1)`, the next `drops[1]` to step 2, and so on; the remainder
    is the hand. Current square = source when `dir == ""`, else the last dealt square.
  - Dealt node j on square d (j-th of that square's dealt group, 0-based) goes to
    `home.x/z + (square_pos(d) - square_pos(src)).x/z`, y = `_base_top[d] + j * FLAT_H`.
    Provisional top of d = `_base_top[d] + sum of "h" of nodes dealt there`.
  - Hand node k (0-based) goes above the current square at y = `provisional top + LIFT + k * FLAT_H`
    (over the source, provisional top = `base_y` of the lowest hand node, so the hand simply
    lifts in place as today).
  - One tween per node: kill the one stored in meta `"tw"` before creating a new 0.12 s
    `position` tween (Vector3, not just y).
  - `_col_top`: start from `_base_top`; source = top of the stones that stay; each dealt
    square = its provisional top; current square += `LIFT` + hand height. Badges of source and
    dealt squares hidden; `set_counts` goes through a `_apply_badges()` that respects this.
- `--stackdemo --deal` demo: click b1, click c1, then screenshot (one stone on c1, two in hand
  above it). Keep the existing `--stackdemo` (carry 2 lifted over b1) and `--slide` shots.

`main.gd`:
- `_update_marks` -> `_update_preview`: `view.set_marks(_next_targets(), src)` and
  `view.set_preview(src, n, dir, drops)` (`src == ""` clears).
- `_play_human(ptn)`: `var dealt := not sel.is_empty() and sel["dir"] != ""` before
  `sel = {}`; `_refresh(not dealt, ptn)`.
- `_update_hud` copy (big `hand_label` / small `carry_label`):
  - pick-up: `Pick up N` / `Wheel or 1-%d sets the count. Click a green square to drop one
    stone there. Right-click or Esc cancels.`
  - dealing: `Drop N on c1  (M in hand)` / `Wheel or 1-8 sets how many go here. Click here for
    one more, or the next square to move on. Right-click takes one back; Esc cancels.`
  - ready: `Hand empty: click c1 to play` / `Wheel down to take some back; Esc cancels.`
    (Increment 3 adds "right-click steps back" to the dealing and ready lines.)

Self-test assertions (b1 scenario; `await` 0.2 s after each click before reading positions):
1. `_click("b1")`, `_click("c1")`: `view._nodes["b1"][0]` global x,z within 0.05 of
   `square_pos("c1")`, y within 0.02 of `BOARD_TOP`; `[1]` and `[2]` above c1 at
   y = `BOARD_TOP + 0.2 + LIFT` and `+ 0.4 + LIFT`; `_col_top["b1"] == 0`, `_col_top["c1"]`
   == `0.2 + LIFT + 0.4` (tolerance 0.01).
2. Picking the hand: `_pick(unproject(square_pos("c1") + Vector3(0, 0.7, 0))) == "c1"` (today: c2).
3. `_click("d1")`: `[1]` on d1 at y 0, `[2]` above d1; `_click("d1")`: move `3b1>12` played,
   `sel` empty, every node of every stack at its `home`, `_col_top == _base_top`.
4. Wheel to ready: new game, `_click("b1")`, `_adjust_carry(-1)`, `_click("c1")`,
   `_adjust_carry(1)`: `sel` not empty (the wheel never commits), `_remaining() == 0`,
   both hand nodes resting on c1 (y 0 and 0.2), `hand_label.text` begins "Hand empty";
   `_click("c1")` plays and c1 == "11".
5. Badges: `counts_box.button_pressed = true`; during a preview `view._badges["b1"].visible`
   is false; after commit it is true.

Done when: exit 0; `--stackdemo --deal` and `--stackdemo --deal --yaw=90` screenshots show
one stone on c1 and two floating above it, nothing floating over b1.

### Increment 3: a way back and the digit keys (items 5 and 9)

`main.gd`:
- `_adjust_drop(delta)` becomes `_set_drop(want: int)` with the same clamp
  `[1, cur + _remaining()]` and `_ok` check; `_adjust_carry` in dealing calls
  `_set_drop(drops[-1] + delta)`.
- `func _step_back() -> void`: if `sel` empty return; if `drops` empty `_cancel()`; else
  `drops[-1] -= 1`, pop at 0, `dir = ""` when `drops` is empty; `_update_preview()`,
  `_update_hud()`.
- `_unhandled_input`: right button -> `_step_back()`; `KEY_BACKSPACE` -> `_step_back()`;
  digits: `_set_carry(k)` when `dir == ""`, else `_set_drop(k)`. Esc unchanged.
- HUD lines gain "Right-click takes one back".
- README controls rows: right-click / Backspace take one back; Esc cancels; 1-8 while dealing.

Self-test assertions:
1. `_click("b1")`, `_click("c1")`, `_click("d1")`: drops `[1, 1]`; `_step_back()`: `[1]`,
   hand of two above c1; `_step_back()`: `drops == []`, `dir == ""`, `n == 3`, three nodes
   lifted over b1; `_step_back()`: `sel` empty.
2. `_click("b1")`, `_click("c1")`, `_set_drop(3)`: `drops == [3]`, `sel` not empty,
   `_next_targets() == ["c1"]`; `_click("c1")`: `3b1>` played, c1 == "111", b1 absent.
3. `_set_drop(9)` clamps to 3; `_set_drop(0)` leaves 1.

Done when: exit 0. No screenshot needed (controller only).

## 4. Deferred, with triggers

| Item | Trigger |
|---|---|
| Illegal-click feedback (red ring pulse or HUD reason) | A tester clicks a dead square and does not notice |
| Enter plays the move in the ready state | Players set counts by digits and then reach for the keyboard |
| Clicking another own stack re-selects it during pick-up | Stuart finds himself right-clicking before every re-select |
| Cap-on-wall preview flattens the wall | Someone is misled by the upright wall |
| Hand follows the hovered square ("if I click here") | Players ask to see the next drop before clicking |
| Tint on dealt stones | A player mistakes a previewed board for a played one |
| Click a stone in the hand to set the count | Tall stacks on 6x6 make the wheel a nuisance |

## 5. Bloat check

Cut: provisional count labels (badges exist, off by default, and the stones are visible);
a separate hand box (column boxes cover it); double-click and source-put-back (settled); any
confirm key; wheel-down popping a square; re-select on stack click; tint. Kept small: Backspace
is one `match` line and gives keyboard players the same gesture as right-click; digits while
dealing reuse `_set_drop`. Four increments, the first two pure correctness; each is a single
Sonnet brief at `medium` effort (increment 2 at `high`: geometry and tweens).

## 6. Open questions for Stuart

1. **Wheel never commits.** You lose "scroll to the max and it plays"; you gain a look at the
   finished board before the click. Is a click to play after a wheel what you want, or do you
   want the wheel to play as soon as the hand is empty, accepting the overshoot risk?
2. **Right-click changes meaning while dealing** (take one back; cancel only in pick-up). Esc
   stays cancel. Acceptable habit change?
3. **Dealt stones look final.** The only signs of a move in progress are the floating hand (gone
   in the ready state), the rings and the HUD. Honest enough, or do you want a tint?
4. **Columns steal clicks from the square behind.** A tall stack hides the near half of the
   square behind it from some yaws, as it does on screen. Fine, or should the hover tile show
   which square a click would hit so you can orbit when in doubt (it will, since hover uses
   the same pick)?
5. **No feedback on a dead click** stays deferred. You said the rings suffice; still true after
   playing a few games?
6. **Failure mode:** if `_col_top` is not restored after commit or cancel, later clicks mis-pick
   on squares that no longer have stacks. Assertion 3 in increment 2 guards it; do you want a
   screenshot of a "+" move at yaw 0 as well, where the overlap is worst?
