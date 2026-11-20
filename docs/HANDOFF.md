# Tak handoff

Current state as of 2026-11-20, HEAD `dfacd1b`. Read this first; agents need not read the other
docs unless a step names one. Superseded or finished plans: `stack-move-ux.md` (replaced by
`drop-click-plan.md`), `drop-click-plan.md` (all four increments built, leave unread).

## What the game is

3D Tak against the Tiltak engine. Rust (`crates/tak-core`, `tak-godot` GDExtension, `tak-cli`)
plus a Godot 4 project in `godot/` (`scripts/main.gd` controller and HUD, `scripts/board_view.gd`
the 3D board). Linux x86_64 is the only platform ever built or run.

## Built and committed

- Piece keys `S` stone, `W` wall, `C` cap; the choice resets to stone after each placement.
- Winning road glows gold. Stack moves slide in. Coordinates checkbox (on); stack-count badge
  checkbox (off): small opaque camera-facing disc on the stack's front face.
- Orbit: `Q`/`E` turn 45 degrees (eased), `R` resets; flat labels turn with the camera.
- Stack move: wheel or `1`-`8` set the pick-up count, then the drop count on the current square;
  click a green square to deal, same square for one more. Dealt stones are drawn on their
  squares, the hand hovers. Only a board click plays the move; an emptied hand shows a "Hand
  empty: click <sq> to play" state. Right-click or `Backspace` takes one stone back; `Esc` or
  clicking the source cancels. Picking uses per-square column boxes, so tall stacks and the
  lifted hand click the right square at every yaw.
- Window opens at most 92% of the usable screen (never above 1600x900), resizable to 800x450.
- README has an Install section (build from source, per OS) and the updated controls.
- Self-test: `godot --path godot -- --selftest` asserts with `_check`, exits non-zero on failure.
  Last run: 0 failures. Use `timeout 150` (a script parse error makes Godot hang, not exit).

## Not verified by hand

Right-click, `Backspace` and digit-key handlers (the self-test calls the functions directly);
window fit on a real small screen; macOS and Windows builds (never built). One orbit-reset
FAIL and one `--yaw=0` screenshot at the wrong yaw were seen once each and did not recur.

## Next: downloadable releases (planned, nothing built)

Plan: `docs/release-plan.md`. Increments: (1) `godot/export_presets.cfg`, `packaging/package.sh`,
`.cargo/config.toml` (`+crt-static` for Windows), local Linux export plus smoke test;
(2) `.github/workflows/release.yml` (build libs on three runners, export on Linux with pinned
Godot 4.7.1, publish on a `v*` tag, `workflow_dispatch` for dry runs); (3) README "Download and
play" per OS, then "Testing requirements for technical testers", plus `packaging/README.txt`;
(4) Stuart tags `v0.1.0` and sends his friend the link.

Open questions for Stuart (proposed defaults in brackets): friend's OS, chip and macOS version
[none, must ask]; Godot exactly 4.7.1 [yes, confirmed locally]; Mac bundle id
[`com.stuartforsyth.tak`]; publish Windows and Mac as "untested", no pre-release flag [yes];
`packaging/` folder [yes]; GPL source offer via the public repo and pinned Tiltak commit [yes].
Stuart had not answered these when this was written.

## Deferred, with triggers

Illegal-click red flash (a tester clicks a dead square unnoticed); Enter to play; re-select by
clicking another stack; capstone-on-wall preview; hover-follow; tinted dealt stones; click-a-stone
counts; the plan's release deferrals (code signing, installers, auto-update, itch.io, icons).

## Working rules (from Stuart)

Plan before building when asked to "plan" or "review": do not implement unasked. Challenge once,
ask the few deciding questions, then follow his call. Reviews go to Opus first, Fable only on
escalation or on request. Commit only when asked. Every command given to Stuart says which
machine and folder it runs on.
