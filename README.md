# Tak

A 3D implementation of the abstract strategy game [Tak](https://ustak.org/play-beautiful-game-tak/)
that you play against a computer opponent. Rust provides the rules and the AI; Godot 4 provides
the board, the stones and the interface.

Tak was designed by James Ernest and Patrick Rothfuss. This is an unofficial, non-commercial
fan project and is not affiliated with or endorsed by them or Cheapass Games.

## Features

- 4x4, 5x5 and 6x6 boards with the full rules: flat stones, standing stones (walls), capstones,
  stack movement, road wins and flat wins.
- Computer opponent (Tiltak) at three strengths: Easy, Medium and Hard.
- Play as white or black.
- Stack moves slide stone by stone from the source square, and a winning road glows gold.
- Moving a stack is previewed on the board: stones you have dealt appear on their squares, the rest
  hover as your hand, and "Pick up N" / "Drop N" labels say what you are holding. The mouse wheel or
  number keys set both counts, and a stone can be taken back before the move is played.
- Rotate the board with `Q` and `E` to look at a position from any side.
- Checkboxes toggle the board coordinates (on by default) and the stack sizes (off by default),
  shown as small camera-facing badges against each stack.
- Procedurally generated wood board and stones, with shadows, ambient occlusion and glow.
  There are no art assets to download.
- A terminal version for quick games and testing.

## Install

There are no prebuilt downloads yet, so you build the game once from source. It takes a few
minutes, mostly compiling the Rust engine. You need:

- [Rust](https://rustup.rs/) (stable, with Cargo) and `git` (Cargo fetches the Tiltak engine from GitHub).
- [Godot](https://godotengine.org/download) 4.3 or newer (developed on 4.7.1), the standard
  version, not .NET.
- A computer with a Vulkan-capable graphics card and current drivers.

Then get the source: `git clone <this repository's URL>` and `cd tak`.

### Linux (x86_64; the only platform tested so far)

1. Install a C compiler and linker: `sudo apt install build-essential` (Debian/Ubuntu) or
   `sudo dnf install gcc` (Fedora).
2. Install Rust with rustup, and Godot from godotengine.org or your package manager. Make sure
   `godot` is on your `PATH`.
3. In the project folder, run `./run.sh`. The first run builds the Rust bridge, then starts the game.

### macOS (not yet tested)

1. Install the Xcode command line tools: `xcode-select --install`.
2. Install Rust with rustup. Download Godot and drag it to Applications.
3. In the project folder, build and run with the Godot app's executable:
   ```
   GODOT=/Applications/Godot.app/Contents/MacOS/Godot ./run.sh
   ```
   If macOS refuses to open Godot or the built library because it is from an unidentified
   developer, allow it under System Settings > Privacy & Security, or run
   `xattr -dr com.apple.quarantine /Applications/Godot.app`.

### Windows (not yet tested)

1. Install the [Visual Studio Build Tools](https://visualstudio.microsoft.com/downloads/) with the
   "Desktop development with C++" workload, then Rust with rustup (choose the MSVC toolchain),
   and Git.
2. Download Godot and unzip it somewhere.
3. In PowerShell, in the project folder:
   ```
   cargo build --release -p tak-godot
   mkdir godot\bin
   copy target\release\tak_godot.dll godot\bin\
   C:\path\to\Godot_v4.x-stable_win64.exe --path godot
   ```
   (From Git Bash, `GODOT=/c/path/to/Godot.exe ./run.sh` does the same.)

### If something goes wrong

- *"Can't open dynamic library" or the board never appears:* the Rust bridge is missing or built
  for another platform. Delete `godot/bin` and build again.
- *Black screen or a rendering error:* update your graphics drivers; the game needs Vulkan.
- Please report problems with your operating system, graphics card and the text of any error.

## Terminal version

A text-only game, for quick games and testing:

```
cargo run --release -p tak-cli -- 5 medium     # size 4|5|6, level easy|medium|hard
```

## Controls

| Action | How |
|---|---|
| Place a stone | Click an empty square |
| Choose stone (flat) / wall / capstone | `S`, `W`, `C` or the buttons at the bottom. The choice goes back to flat after each placement |
| Move a stack | Click a stack of yours, then click where it goes |
| Choose how many stones to pick up | Mouse wheel (or keys `1`-`8`) after clicking the stack. The top-left shows "Pick up N" |
| Choose how many to drop on a square | Mouse wheel or keys `1`-`8` after clicking the square. The top-left shows "Drop N on c1". Click that square again to finish once nothing is left in hand |
| Drop one more on the same square | Click that square again |
| Continue to the next square | Click the next square along the line. The move plays when the last stone is dropped by a click. If the wheel or a digit key empties the hand, the move waits in a "Hand empty" (ready) state, showing the finished board: click the highlighted square to play it, or wheel down to take some back |
| Take one stone back | Right-click or `Backspace`. Steps back through the squares you have dealt to, then to the pick-up step; with nothing dealt it cancels |
| Cancel a move | `Esc`, or click the stack you picked up |
| Rotate the board | `Q` / `E` turn it left / right in 45° steps; `R` returns to the default view. The labels turn with the board |
| Undo | `U`, `Ctrl+Z` or the Undo button. Takes back your last move and the engine's reply; if the engine is still thinking, its search is cancelled |

Green rings show the squares you can click next. A gold ring marks the selected stack. On the
first move of the game each player places a flat stone of the *opponent's* colour; this is the
standard Tak opening, and the status line reminds you.

## Project layout

| Path | Purpose |
|---|---|
| `crates/tak-core` | Wraps Tiltak's rules and search behind a small interface. The only place the engine is touched. Moves cross the boundary as PTN strings. |
| `crates/tak-godot` | GDExtension that exposes a `TakGame` class to Godot. The engine search runs on a Rust thread and is polled from Godot. |
| `crates/tak-cli` | Terminal game. |
| `godot/` | The Godot project: scene, procedural meshes and wood materials, input and HUD. |
| `docs/` | Design notes, e.g. `stack-move-ux.md` (the planned "lift and deal" stack-move preview). |
| `LICENSE` | GNU General Public License, version 3. |

## Tests

```
cargo test --release                                  # rules wrapper and engine
godot --path godot -- --selftest                      # scripted click-through of the UI
godot --path godot -- --shot=/tmp/x.png --size=6 --plies=30    # screenshot of a sample position
```

The self-test checks every assertion with a pass or fail line and exits non-zero if any fail. It
covers screen picking on every square at several board rotations (including tall stacks and the
lifted hand), placing and undoing, moving stacks by click and by mouse wheel, the dealt-stone
preview, the "Hand empty" ready state, taking stones back, and stacks with no legal move.

## Difficulty levels

| Level | How the engine plays |
|---|---|
| Easy | 200 search nodes, with Tiltak's weaker-bot rollouts and random noise |
| Medium | 5,000 nodes, with rollouts |
| Hard | 100,000 nodes, the plain engine |

These node counts are first guesses. Strength has not been measured yet.

## Roadmap

- Calibrate the levels by playing them against each other.
- Menus, settings and sound.
- Phase 2, online play: either a lobby with ratings and matchmaking, or a PlayTak client. Not
  started; decide after phase 1 has been played for a while.

## Licence

Copyright (C) 2026 Stuart Forsyth

This program is free software: you can redistribute it and/or modify it under the terms of the
GNU General Public License as published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not,
see <https://www.gnu.org/licenses/>. The full text is in the `LICENSE` file.

### Why GPL

The computer opponent is [Tiltak](https://github.com/MortenLohne/tiltak) by Morten Lohne, which is
licensed GPL-3.0-or-later. This project links it directly, so the whole program is released under
the same licence. If you distribute a build, you must make the corresponding source available
under the GPL.

### Third-party software

| Component | Licence |
|---|---|
| [Tiltak](https://github.com/MortenLohne/tiltak) (pinned to commit `fc4f52f`) | GPL-3.0-or-later |
| [Godot Engine](https://godotengine.org/) | MIT |
| [godot-rust (gdext)](https://github.com/godot-rust/gdext) | MPL-2.0 |
| `board-game-traits`, `pgn-traits` and other Rust crates | See each crate's own licence |

Run `cargo tree` for the full dependency list.
