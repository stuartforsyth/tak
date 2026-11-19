#!/usr/bin/env bash
# Build the Rust bridge and copy it where the Godot project loads it (Linux, macOS, Windows Git Bash).
set -euo pipefail
cd "$(dirname "$0")"
cargo build --release -p tak-godot
mkdir -p godot/bin
case "$(uname -s)" in
  Darwin) lib=libtak_godot.dylib ;;
  MINGW*|MSYS*|CYGWIN*) lib=tak_godot.dll ;;
  *) lib=libtak_godot.so ;;
esac
cp "target/release/$lib" godot/bin/
