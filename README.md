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
- Procedurally generated wood board and stones, with shadows, ambient occlusion and glow.
  There are no art assets to download.
- A terminal version for quick games and testing.

## Requirements

- Rust (stable) and Cargo.
- [Godot](https://godotengine.org/) 4.3 or newer (developed on 4.7.1).
- Linux x86_64 is the only platform tested so far.

## Build and run

```
./build.sh                         # builds the Rust bridge, copies it to godot/bin/
godot --path godot                 # play
```

Terminal version:

```
cargo run --release -p tak-cli -- 5 medium     # size 4|5|6, level easy|medium|hard
```

## Controls

| Action | How |
|---|---|
| Place a stone | Click an empty square |
| Choose flat / wall / capstone | `F`, `S`, `C` or the buttons at the bottom |
| Move a stack | Click a stack of yours, then click where it goes |
| Choose how many stones to carry | Keys `1`-`6` or the mouse wheel, before the first drop |
| Drop more stones on the same square | Click that square again |
| Continue to the next square | Click the next square along the line |
| Cancel a move | Right-click or `Esc` |

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
| `LICENSE` | GNU General Public License, version 3. |

## Tests

```
cargo test --release                                  # rules wrapper and engine
godot --path godot -- --selftest                      # scripted click-through of the UI
godot --path godot -- --shot=/tmp/x.png --size=6 --plies=30    # screenshot of a sample position
```

The self-test checks that screen picking maps to the right square on every square, then plays real
clicks: placing a stone, moving one stone, and moving a three-stone stack across two squares.

## Difficulty levels

| Level | How the engine plays |
|---|---|
| Easy | 200 search nodes, with Tiltak's weaker-bot rollouts and random noise |
| Medium | 5,000 nodes, with rollouts |
| Hard | 100,000 nodes, the plain engine |

These node counts are first guesses. Strength has not been measured yet.

## Roadmap

- Animate moves sliding from the source square, and glow the winning road.
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
