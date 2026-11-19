#!/usr/bin/env bash
# Build the Rust bridge and copy it where the Godot project loads it.
set -euo pipefail
cd "$(dirname "$0")"
cargo build --release -p tak-godot
mkdir -p godot/bin
cp target/release/libtak_godot.so godot/bin/
