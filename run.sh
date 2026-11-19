#!/usr/bin/env bash
# Run the game. Builds the Rust bridge first if it hasn't been built yet.
set -euo pipefail
cd "$(dirname "$0")"
ls godot/bin/*tak_godot* >/dev/null 2>&1 || ./build.sh
exec "${GODOT:-godot}" --path godot "$@"
