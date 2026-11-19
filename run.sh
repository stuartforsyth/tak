#!/usr/bin/env bash
# Run the game. Builds the Rust bridge first if it hasn't been built yet.
set -euo pipefail
cd "$(dirname "$0")"
[ -f godot/bin/libtak_godot.so ] || ./build.sh
exec godot --path godot "$@"
