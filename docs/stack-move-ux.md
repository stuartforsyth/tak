# Stack movement: mouse-driven design

Status: design, 2026-11-20 (Fable). Not built. Scope: `godot/scripts/main.gd` (controller)
and `godot/scripts/board_view.gd` (3D view). The Rust engine and the PTN validation in the
controller (`_ok`, `_next_targets`, `_ptn_for`) are correct and stay as they are.

## 1. Premise check: is "click squares along a line" right?

Yes, with one change of mental model. Today the clicks are an *input sequence* whose effect
is only reported in a status line. The fix is not a different gesture; it is to make every
click **physically deal a stone onto the board**, so the board itself is the preview. The
rest of this document is that idea plus three small additions (put one back, take one back,
drop all).

Alternatives considered and rejected as the primary mechanic:

| Alternative | Why not |
|---|---|
| **Click-and-drag** along the line; pointer chooses extent | A drag fixes direction and extent but not the two other degrees of freedom (carry count and per-square drops), so it still needs wheel or clicks mid-drag. Release commits with no chance to look at the result, which is wrong for a thinking game. Press-move-release on a 49-degree 3D view is also fiddly and would fight any future camera drag. |
| **Hold-to-drop-more** (auto-repeat) | Not discoverable, timing dependent, and the player watches stones tick down instead of deciding. Kept as a fallback for one case (see 6). |
| **Click a stone in the stack** to pick up that stone and everything above it | Good for tall stacks and used by ptn.ninja, but needs per-piece picking (there is none; `_pick` is a plane test) and the lifted stones are only 0.2 units tall on screen. Deferred with a trigger (see 7). |
| **Hand / preview panel** in the HUD | Moves the eye off the board. The 3D board already has room to show the hand; a panel duplicates it. |
| **Wheel to set per-square counts** | Fine as a power-user extra; not discoverable. Deferred. |

What other clients do: PlayTak and ptn.ninja both pick up the whole stack (capped by the
carry limit) on one click, and every later click drops one stone on the clicked square,
including the source square, which puts a stone back. The hand is drawn floating on the
board. This is the model recommended here; it keeps the game to **one verb**: *a click on a
square drops one stone there*.

## 2. Recommended design: "lift and deal"

### States

`sel = {src, n, dir, drops}` as today. Three phases:

1. **Hand over source** (`dir == ""`): the top `n` stones hover above the source stack.
2. **Dealing** (`dir != ""`, hand not empty): dropped stones sit on their squares; the hand
   hovers above the last square dealt to.
3. **Hand empty**: the move plays at once. There is no confirm step; Undo covers mistakes.

### Interaction, step by step

| Step | Mouse | What the board shows |
|---|---|---|
| Pick up | Click a stack whose top stone is yours | Top `min(height, size)` stones lift and hover above the stack (`LIFT` above its top). Gold ring on the source, green rings on the legal first squares. |
| Choose count | Click the source square: one stone goes back down (`n -= 1`). Clicking when `n == 1` puts the last one down, which ends the selection. Double-click the source: everything goes back down (cancel). Keys `1`-`8` and the wheel still work as extras. | The hand shrinks; the source's height number shows the stones that stay. |
| Choose direction | Click a green neighbouring square | One stone flies from the hand onto that square, resting on top of whatever is there. The hand moves to hover above that square. Green rings now mark "this square again" (if legal) and "the next square along". |
| Drop more here | Click the same square again | One more stone lands; hand count falls. |
| Drop everything here | **Double-click** the square | First click drops one, second drops the rest. Hand empty, so the move plays. This is the one-gesture way to shove a whole stack one square, the most common Tak move. |
| Move on | Click the next green square along the line | One stone lands there; the hand moves on. |
| Take one back | **Right-click** | The last stone dropped returns to the hand. If that square now holds none of this move's stones, the hand moves back to the previous square. If the direction's only stone is taken back, direction clears and the hand is over the source again. |
| Cancel | Right-click when nothing has been dealt, `Esc` at any time, or click the source square after dealing has started | Everything returns to the source stack; marks clear. |
| Commit | Automatic when the hand is empty | The real position is shown. Because the stones are already where they will end up, the committed move is drawn **without** the fly-in animation (that animation stays for the engine's moves). |
| Mistake | Click a square with no ring | Ignored. (A red ring pulse is deferred; see 7.) |

Right-click changes meaning: today it cancels, afterwards it steps back one drop and cancels
only when there is nothing to step back. `Esc` keeps the old "cancel everything" behaviour.
This is the one habit change for an existing player and the README row must say so.

### What is drawn (board_view)

- **Dealt stones** are the real lifted stone nodes, tweened (0.12 s) to the destination
  square at the correct height: the destination's current top plus `FLAT_H` per stone
  already dealt there. Same mesh, same material; no ghost tint. The board looks like the
  result so far, which is the point. A wall in hand is drawn as a wall wherever it lands.
- **The hand** is the remaining lifted nodes, stacked at `LIFT` above the top of the current
  square (source until the first drop, then the last square dealt to).
- **Height numbers** on affected squares: the source keeps its top-face number and it reads
  the stones that stay (hidden if fewer than two). Each dealt square gets a temporary
  billboard number above its provisional top (the same style `_add_count` uses for walls and
  capstones), reading old height plus stones dealt. Its static top-face number is hidden
  while covered. All of this is undone when the preview is cleared.
- **Rings**: unchanged in meaning. Gold on the source, green on the squares the next click may
  land on. No extra ring for dealt squares; the stones sitting there are the marker.
- **Picking through the hand**: the hand floats up to 1.4 units above the board; with the
  camera at about 49 degrees a click on a floating stone lands on the plane roughly one square
  *behind* it, which can be the next legal square on a "+" move. `_pick` must therefore test
  the ray against the hand's world-space `AABB` first and return the hand's square when it
  hits. Without this the "click the same square again" step is unreliable, so it is part of
  the first increment.

### Known imperfections (accepted for now)

- A capstone dealt onto a wall is previewed as a capstone resting on an upright wall; the
  real position flattens the wall. Rare; the engine's result is correct.
- On commit the stacks are rebuilt with per-square seeded jitter, so dealt stones may shift
  by a few millimetres. Cosmetic.

### Hints (discoverability, no keys required)

`carry_label` copy per phase:

- No selection: `Click a stack of yours to pick it up.` (existing, keep)
- Hand over source: `In hand: 3 of 3. Click a green square to drop a stone there, or the
  stack to put one back. Right-click or Esc cancels.`
- Dealing: `In hand: 2. Same square drops another (double-click drops all); next square
  moves on. Right-click takes the last one back.`

`status` stays `Moving a stack` while a move is in progress. README controls table rows
updated to match (pick up, put one back, drop one, drop all, move on, take one back, cancel).

## 3. Changes at function and state level

### main.gd

- `_unhandled_input`: left press with `ev.double_click` goes to `_drop_all(sq)` instead of
  `_click(sq)`; right press goes to `_step_back()` instead of `_cancel()`; `Esc` stays
  `_cancel()`. Wheel and `1`-`8` unchanged.
- `_pick(pos)`: before the plane test, ask `view.hand_square_hit(origin, dir)`; if it returns
  a square, use it.
- `_move_click(sq)`: when `dir == ""` and `sq == src`, call `_set_carry(n - 1)`, cancelling at
  zero, instead of cancelling outright. After `dir != ""`, `sq == src` still cancels.
- `_drop_all(sq)` (new): if `sq == src` and `dir == ""` and `n < max_carry` then `_cancel()`;
  if `sq == src` and the hand is full, do nothing (this is the second press of a double-click
  that lifted the stack). Otherwise, if `sq` is the current square and `_ok` accepts
  `drops[-1] + remaining`, set it and commit. `_next_targets` already guarantees the square
  can take one more; Tak has no per-square cap, so taking all is legal whenever one is.
- `_step_back()` (new): if `drops` is empty, `_cancel()`. Else `drops[-1] -= 1`; pop when it
  reaches zero; if `drops` is now empty, `dir = ""`. Then `_update_preview()` and HUD.
- `_update_marks()` renamed `_update_preview()`: calls `view.set_marks(_next_targets(), src)`
  and `view.set_preview(src, n, dir, drops)` (empty `src` clears). Replaces the `set_lift`
  calls.
- `_play_human(ptn)`: pass `animate = sel.is_empty()` to `_refresh`, so dealt moves do not
  fly in again; placements still animate.
- `_update_hud()`: the three copy strings above.
- Test hooks: `_click(sq)`, `_drop_all(sq)`, `_step_back()`, `_cancel()` are all callable by
  the self-test without synthesising input events.

### board_view.gd

- `_build_stack`: record `_tops[sq] = top_y` and `_labels[sq] = label` (or null) so the
  preview can place stones and move numbers without rebuilding.
- `set_preview(src, n, dir, drops)` (replaces `set_lift`): for the top `n` nodes of
  `_nodes[src]`, in order, assign a destination: the first `drops[0]` go to the first square
  along `dir`, and so on; the rest hover above the current square. Position each node
  (relative to the source root) at `square_pos(dest) - square_pos(src)` plus the computed
  height, tweened 0.12 s as `set_lift` does now. Record the hand's world `AABB`
  (`_hand_box`) and the current square. Update numbers: set the source label's text and
  visibility; create or update billboard labels in a `_preview_labels` node for dealt squares
  and hide those squares' static labels. `set_preview("", 0, "", [])` restores everything.
- `hand_square_hit(origin, dir) -> String`: `_hand_box.intersects_ray` test; returns the
  hand's square or `""`.
- `_slides_for` / `_slide_in`: unchanged; they now only run for engine moves and for
  `--slide` demos.

## 4. Tests

Self-test (`godot --path godot -- --selftest`), extending the existing 4x4 `b1` scenario
(white stack of three on `b1`, line east):

1. Click `b1`: `n == 3`; hand box is above `b1`; the top node of `b1` is lifted.
2. Click `b1` again: `n == 2`. Right-click: selection cleared (nothing dealt means cancel).
3. Click `b1`, click `c1`: `dir == ">"`, `drops == [1]`; the top node of `b1` now sits within
   0.05 of `square_pos("c1")` in x and z; the hand box is above `c1`.
4. Picking: `_pick(camera.unproject_position(hand_box.get_center()))` returns `c1`, not `c2`.
5. Click `d1`: `drops == [1, 1]`. Right-click: `drops == [1]`, hand above `c1`. Right-click:
   `drops == []`, `dir == ""`, hand above `b1`.
6. Click `c1`, `_drop_all("c1")`: move `3b1>` played; `b1` empty, `c1 == "111"`.
7. New game, same setup; click `b1`, click `c1`, click `d1`, click `d1`: move `3b1>12`
   played (the existing check).
8. `_drop_all("b1")` straight after a lift: selection still present, `n == 3` (double-click
   pickup must not cancel).
9. After each committed move, the preview labels node is empty and no node of any stack is
   displaced from its `base_y`.

Screenshot demo: `--stackdemo --deal` performs steps 1 and 3 and 5's first click, then
screenshots: hand of one stone above `d1`, one stone dealt on `c1`, numbers reading `1` on
`c1`... (a single stone has no number) and the hand visible. The existing `--stackdemo`
(lift with carry 2) and `--slide` shots are kept; the first must still render through
`set_preview` with `dir == ""`.

## 5. Build order

**Increment 1: the board is the preview.** `set_preview`, `_tops`/`_labels`, provisional
numbers, `hand_square_hit`, `_update_preview`, no-fly-in on commit, hint copy, self-test
steps 1, 3, 4, 7, 9, demo `--deal`. Delivers the biggest fix (seeing what you have dealt) and
makes every later step safe to add. Controller input mapping is untouched in this increment
except `_pick`.

**Increment 2: fewer clicks and a way back.** Source-click put-back, double-click
`_drop_all`, right-click `_step_back`, `Esc` cancel, README rows, self-test steps 2, 5, 6, 8.
Small, pure controller work; ship right after increment 1 once the preview looks right in a
screenshot.

## 6. Fallback

If double-click proves accident-prone in play (two deliberate quick clicks meaning "two
here" get read as "all here" and commit), replace it with press-and-hold on the current
square: after 0.35 s, one stone per 0.25 s until release or empty hand. Same hint slot, same
`_drop_all`-style helper. Do not build both.

## 7. Deferred, with triggers

| Item | Trigger to build it |
|---|---|
| Click a stone in the lifted hand to keep that stone and above (one-click count) | Playing on 6x6 shows put-back clicks on tall stacks are a nuisance |
| Wheel over the current square adds or takes back one stone there | A player asks for it; it is a ten-line extension of `_adjust_carry` |
| Red ring pulse on an illegal click | A tester clicks a dead square and does not notice nothing happened |
| Preview flattens a wall under a dealt capstone | Someone is misled by the upright wall in a preview |
| Hand follows the hovered square along the line ("if I click here") | Players say they want to see the next drop before clicking |
| Commit without the jitter pop | The pop is noticed and disliked |

## 8. Bloat check

Cut from earlier drafts: rings on dealt squares (the stones are the marker), a count label
above the hand (the status line and the visible stones suffice), HUD buttons for take-back
and cancel (right-click and Esc are mouse and one key), ghost tint on dealt stones (an
honest-looking board is the preview), wheel-while-dealing (deferred), per-piece picking
(deferred with stone-click), and any confirm step before commit.

## 9. Open questions for Stuart

1. **Right-click becomes "take one back".** Cancel moves to `Esc`, repeated right-clicks, or
   clicking the source after dealing starts. Is losing one-press right-click cancel acceptable?
2. **Double-click drops all and commits in one gesture.** No confirm. Undo takes back the
   engine's reply too. Is auto-commit on an empty hand still the right call, or should the
   last stone of a double-click wait for a confirming click?
3. **Dealt stones look real.** Nothing marks them as provisional except the floating hand
   and the rings. Is that honest enough, or should they be tinted?
4. **Count by putting stones back** costs up to five clicks on a 6-stack. Is that fine for
   now, with stone-click deferred, or is stone-click wanted in increment 2?
5. **Hand stays over the last dealt square** rather than following the pointer. Accept the
   loss of the "hover to preview the next drop" feel?
6. **The cap-on-wall preview is wrong** until the deferred item lands. Acceptable?
7. **Failure mode**: if the hand `AABB` test is skipped or wrong, "click the same square
   again" silently targets the square behind on "+" moves. The self-test step 4 guards it;
   should the demo screenshot also show a "+" move so the overlap is visible?
