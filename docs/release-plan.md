# Release plan: downloadable builds of Tak

Fable plan, 2026-11-20. Goal: a non-technical friend downloads one file from the GitHub
Releases page, unzips it and plays, on Windows, macOS or Linux. No executor has started; this
is the brief they will work from.

Inputs read: `README.md`, `godot/tak.gdextension`, `godot/project.godot`, `build.sh`, `run.sh`,
`Cargo.toml`, `crates/tak-godot/Cargo.toml`, `ls` of the root and `godot/`. Facts from Stuart:
Rust workspace, GDExtension via godot-rust 0.5.5 (`compatibility_minimum = 4.3`), Godot 4.7.1,
default Forward+ renderer, GPL-3.0-or-later, Tiltak pinned to a git rev, only Linux ever built
or run, no Windows or Mac machine, no money for code signing, repo public at
`github.com/stuartforsyth/tak`.

## Recommendation in one paragraph

Build the three native libraries on GitHub-hosted runners (Linux, Windows, macOS universal),
then do all three Godot exports on one Linux runner with the pinned headless Godot editor and a
checked-in `godot/export_presets.cfg`, through a `packaging/package.sh` script that also runs
unchanged on stuart-gaming so every step except the Windows and Mac compiles can be verified
locally first. Ship plain archives (zip for Windows and macOS, tar.gz for Linux), each with
`LICENSE` and a short `README.txt` carrying the source offer and the one-time security-warning
steps. Publish from a `v*` tag with `gh release create`. No installers, no signing, no
auto-update, no renderer fallback build: Godot 4.3+ already falls back to OpenGL by itself.
Mark Windows and macOS "untested, please tell me what happened" in the README and on the
release. The first downloadable release is `v0.1.0`.

## The challenge: what "download and test" assumes and leaves out

Stated once, with a recommendation; Stuart decides and I will not re-raise.

| Topic | What the ask assumes | What I would do |
|---|---|---|
| macOS architecture | One Mac build | The friend's Mac may be Intel or Apple Silicon. Build both Rust targets on the macOS runner and `lipo` them into one universal dylib; Godot's macOS template is universal already. One Mac zip. Cost: ~6 lines of workflow. |
| macOS "right-click Open" | Right-click > Open bypasses Gatekeeper | **It does not on macOS 15 Sequoia or later** (Apple removed the Control-click override in 2024; macOS 26 is current). The route is now: double-click, click Done on the "Apple could not verify" dialog, then System Settings > Privacy & Security > Open Anyway. The README must give both routes keyed by macOS version. On Apple Silicon an unsigned arm64 binary will not launch at all, so the dylib and the app must be ad-hoc signed (the Apple linker does this for the dylib; Godot's built-in ad-hoc signer does the bundle, and works from a Linux host). |
| Windows CRT | A Rust DLL just runs | A default MSVC build links `vcruntime140.dll` dynamically; a fresh Windows 11 may not have it ("VCRUNTIME140.dll was not found"). Set `+crt-static` for the Windows target in `.cargo/config.toml`. Three lines, removes the most likely silent failure. |
| Linux glibc | Build anywhere | Our `.so` requires the builder's glibc or newer. Build on `ubuntu-22.04` (glibc 2.35, covers Ubuntu 22.04+, Debian 12+, Fedora 36+). If GitHub has retired that image, use `ubuntu-24.04` and accept the narrower range; a container build is the fix if a Linux user ever reports `GLIBC_x not found`. |
| Vulkan on old or virtual GPUs | Forward+ works everywhere | It does not (VMs, pre-2016 Intel, remote desktop). Godot 4.3+ falls back Vulkan -> D3D12 (Windows) -> OpenGL3 Compatibility automatically (`rendering/rendering_device/fallback_to_opengl3`, default on). So: no separate Compatibility build; instead verify once, locally, that the game is playable under `--rendering-method gl_compatibility` (glow and SSAO silently degrade). The README says "if the window is black, update graphics drivers; if that fails tell me", and a Compatibility toggle is deferred with that report as its trigger. |
| Finding the native library | The `res://bin/...` path works in an export | Godot copies GDExtension libraries next to the executable (Linux, Windows) or into `Tak.app/Contents/Frameworks` (macOS) at export time and resolves them by basename at runtime. The archive must therefore contain the whole export folder, not just the executable. Embed the `.pck` into the Linux and Windows executables (`binary_format/embed_pck=true`) so each folder has two files plus LICENSE and README. The Mac `.app` is self-contained. |
| Exporting in CI | Someone clicks Export in the editor | Use the headless editor: `godot --headless --path godot --import`, then `--export-release <preset> <path>`, with the matching export templates unzipped into `~/.local/share/godot/export_templates/4.7.1.stable/`. Pin one version string (`GODOT_VERSION=4.7.1`, the version Stuart develops on) in the workflow and in `package.sh`. Verify the asset names exist with `gh release view 4.7.1-stable -R godotengine/godot` before writing the workflow. |
| Archive format | zip for everyone | Windows: zip (Explorer's Extract All). macOS: Godot already produces `Tak.zip` with the `.app` inside and the execute bits intact; add LICENSE and README.txt to that zip with `zip -j` (never re-pack it from an extracted copy; that loses the bits and the symlinks). Linux: tar.gz keeps the execute bit. No `.dmg` (needs a Mac to build), no `.msi`/NSIS installer: both are deferred. |
| Trigger | Tag and go | `on: push: tags: v*` plus `workflow_dispatch`. Dispatch runs build everything and upload workflow artifacts but do not create a Release, so the first fix rounds happen without burning tags. Only a tag run calls `gh release create`. |
| First CI run | It will work | Expect 2 to 4 fix rounds; the Rust matrix (MSVC, macOS targets) is the likeliest to break, the Godot download the least. Mitigations: `package.sh` is proven locally first (with the real `.so` and stub `.dll`/`.dylib` files to check placement); `fail-fast: false` so each round reports all platforms; budget of four rounds, then `opus-specialist`. If macOS alone is still red after two rounds, release Windows + Linux as v0.1.0 and add macOS in v0.1.1. |
| Smoke test | Can't test an export without a GPU | Godot has `--headless` (dummy renderer) and `--quit-after N`. Run the Linux export headless for 60 frames and fail on a non-zero exit or "Can't open dynamic library" in the output; that proves the pck, the scripts and the GDExtension load. The project's own `-- --selftest` does screen picking; try it headless locally once, and add it to CI only if it passes there (it needs no new code either way). Windows and Mac exports get structural checks only (`file` says PE32+, `unzip -l` shows the dylib inside the `.app`). |
| Who tests | The friend | The friend is the first tester on their OS; Stuart is the Linux tester. The release and README say so plainly rather than pretending. |

Also noted while reading, outside the ask: `project.godot` sets a 1600x900 window with no
`resizable`/maximised setting; on a 1366x768 laptop the window will not fit. Not part of this
plan, but the friend may hit it first. See open questions.

## Bloat check: what is in, what is deferred

In: presets, a package script, one workflow, README rewrite (plain "Download and play" first, then a
"Testing requirements for technical testers" section that Stuart asked for on 2026-11-20, which is
also the only home for build-from-source), an in-archive README.txt, `+crt-static` for Windows,
`dist/` in `.gitignore`. That is the smallest set that gives one working download per OS and a
way for technical testers to help when the download fails.

Deferred, each with the trigger that starts it:

| Deferred | Trigger |
|---|---|
| Apple notarisation / Microsoft signing | A second non-technical user, or the friend gives up at the warning dialog. |
| `.dmg`, `.msi`/installer, Start-menu entry | A user who cannot manage a zip, or signing has been bought. |
| Auto-update | More than one release a month with users who do not re-download. |
| itch.io / Steam page | Wanting players beyond friends. |
| Compatibility-renderer toggle or separate build | A tester reports a black screen or a Vulkan error that the automatic fallback did not catch. |
| Custom icons (needs `rcedit` in CI for Windows) | After the first release is played; cosmetic. |
| Rust toolchain pin, `rust-cache`, sha256 pins of the Godot downloads | A CI break caused by a toolchain or download change, or build time hurting the fix loop. |
| Older-glibc container build, AppImage, Flatpak | A Linux user reports `GLIBC_x.y not found`. |
| Running the Windows export under Wine | A Windows crash that needs a local reproduction. |
| CI build on every push to main | The workflow is found broken at tag time twice. |
| In-game version display | Confusion over which build a report comes from (the archive name carries it for now). |
| Vendored source tarball for GPL "corresponding source" | Tiltak's repo becomes unavailable or someone asks for source in a form other than the public repos. |

## Decisions (settled by this plan unless Stuart overrides)

- Godot pinned at **4.7.1-stable** everywhere (workflow env, `package.sh`, README developer section).
- Export presets named exactly `Linux`, `Windows`, `macOS`; outputs `dist/linux/tak.x86_64`, `dist/windows/Tak.exe`, `dist/macos/Tak.zip`.
- Archive names: `tak-<version>-windows.zip`, `tak-<version>-macos.zip`, `tak-<version>-linux.tar.gz`, plus `SHA256SUMS.txt`. Windows and Linux archives contain a top-level `Tak/` folder. Version is the tag without the `v`.
- Windows: no console wrapper exe, `modify_resources=false` (no rcedit), `codesign/enable=false`, pck embedded.
- macOS: `binary_format/architecture="universal"`, `codesign/codesign=1` (built-in ad-hoc), `codesign/entitlements/disable_library_validation=true` (needed so an ad-hoc app may load the GDExtension dylib), `notarization/notarization=0`, bundle identifier `com.stuartforsyth.tak` (open question 3), app category `public.app-category.board-games`.
- Linux: pck embedded, x86_64 only.
- Rust: `cargo build --release --locked -p tak-godot`, stable toolchain via `dtolnay/rust-toolchain@stable`, no cache.
- New folder `packaging/` holds `package.sh`, `README.txt` (goes into every archive) and `release-notes.md`. Root keeps `build.sh`/`run.sh` as they are.
- Release created with the preinstalled `gh` CLI and `GITHUB_TOKEN` (`permissions: contents: write` at workflow level), no third-party release action.

## Increments

Each is a self-contained brief for `sonnet-executor`. The executor reads this file and
`README.md`; it does not read the other docs. Reports in about 300 words.

### Increment 1: export presets, package script, local Linux export (Sonnet, effort high)

Files to create or change:

- `godot/export_presets.cfg` (new, committed).
- `packaging/package.sh` (new, executable).
- `packaging/README.txt` (new; final wording comes in increment 3, a placeholder with the source offer is enough here).
- `.cargo/config.toml` (new) with `[target.x86_64-pc-windows-msvc] rustflags = ["-C", "target-feature=+crt-static"]`.
- `.gitignore`: add `dist/` (keep whatever already ignores `target/`, `godot/bin/`, `godot/.godot/`; check first).

Steps:

1. Confirm the local editor version: `godot --version` must print 4.7.1. Install the matching export templates if `~/.local/share/godot/export_templates/4.7.1.stable/` is missing: download `Godot_v4.7.1-stable_export_templates.tpz` from `https://github.com/godotengine/godot/releases/download/4.7.1-stable/`, unzip, move the contents of its `templates/` folder into that directory. Confirm the asset name with `gh release view 4.7.1-stable -R godotengine/godot --json assets -q '.assets[].name'`.
2. Write `godot/export_presets.cfg` with three presets. Starting content (Godot ignores unknown keys with a warning and defaults the rest; adjust to what the 4.7.1 export log complains about):

   ```
   [preset.0]
   name="Linux"
   platform="Linux"
   runnable=true
   export_filter="all_resources"
   export_path="../dist/linux/tak.x86_64"
   script_export_mode=2

   [preset.0.options]
   binary_format/architecture="x86_64"
   binary_format/embed_pck=true
   debug/export_console_wrapper=0
   texture_format/s3tc_bptc=true
   texture_format/etc2_astc=false

   [preset.1]
   name="Windows"
   platform="Windows Desktop"
   runnable=true
   export_filter="all_resources"
   export_path="../dist/windows/Tak.exe"
   script_export_mode=2

   [preset.1.options]
   binary_format/architecture="x86_64"
   binary_format/embed_pck=true
   debug/export_console_wrapper=0
   codesign/enable=false
   application/modify_resources=false
   application/product_name="Tak"
   texture_format/s3tc_bptc=true
   texture_format/etc2_astc=false

   [preset.2]
   name="macOS"
   platform="macOS"
   runnable=true
   export_filter="all_resources"
   export_path="../dist/macos/Tak.zip"
   script_export_mode=2

   [preset.2.options]
   export/distribution_type=1
   binary_format/architecture="universal"
   application/bundle_identifier="com.stuartforsyth.tak"
   application/app_category="public.app-category.board-games"
   codesign/codesign=1
   codesign/entitlements/disable_library_validation=true
   notarization/notarization=0
   ```

   Do not add `export_credentials.cfg`; nothing needs credentials.
3. Write `packaging/package.sh`. Behaviour:
   - Usage: `packaging/package.sh [--require-all] <version>`. Honours `GODOT` like `run.sh` (`${GODOT:-godot}`), `cd`s to the repo root, `set -euo pipefail`.
   - For each platform whose library is present in `godot/bin/` (`libtak_godot.so`, `tak_godot.dll`, `libtak_godot.dylib`), run the export; with `--require-all`, fail if any library is missing. Before the first export run `"$GODOT" --headless --path godot --import`.
   - Exports: `"$GODOT" --headless --path godot --export-release Linux ../dist/linux/tak.x86_64` and the same for `Windows` and `macOS` (create the `dist/<platform>` folder first). Fail on non-zero exit, and also fail if the export log contains `ERROR` (Godot sometimes exits 0 after a failed export; grep the captured output).
   - Smoke test the Linux export when it was built: `dist/linux/tak.x86_64 --headless --quit-after 60 > dist/smoke.log 2>&1`; fail on non-zero exit or on `Can't open dynamic library` / `GDExtension` + `error` in the log.
   - Assemble archives with the version in the name:
     - Linux: `dist/tak-<v>-linux/Tak/{tak.x86_64, libtak_godot.so, LICENSE, README.txt}` -> `dist/tak-<v>-linux.tar.gz`.
     - Windows: `Tak/{Tak.exe, tak_godot.dll, LICENSE, README.txt}` -> `dist/tak-<v>-windows.zip` (`zip -r`).
     - macOS: copy `dist/macos/Tak.zip` to `dist/tak-<v>-macos.zip`, then `zip -j dist/tak-<v>-macos.zip LICENSE packaging/README.txt`. Never unzip and re-zip it.
     - `README.txt` is copied with `__VERSION__` replaced by `<v>` (sed), so the source offer names the tag.
   - `sha256sum` of the archives into `dist/SHA256SUMS.txt`. Print the archive list at the end.
4. Structural checks for the platforms that cannot run here. Create temporary stub files `godot/bin/tak_godot.dll` and `godot/bin/libtak_godot.dylib` (e.g. `echo stub >`), run `packaging/package.sh 0.0.0-local`, and verify: `unzip -l dist/tak-0.0.0-local-windows.zip` lists `Tak/Tak.exe` and `Tak/tak_godot.dll` and no `Tak.console.exe`; `unzip -l dist/tak-0.0.0-local-macos.zip` lists `Tak.app/Contents/MacOS/Tak`, `Tak.app/Contents/Resources/Tak.pck` and the dylib under `Tak.app/Contents/Frameworks/` (or wherever Godot put it; record the path in the report), plus `LICENSE` and `README.txt`; `file dist/windows/Tak.exe` says `PE32+`. Then delete the stubs and `dist/`.
5. Renderer fallback check, once: run `dist/linux/tak.x86_64 --rendering-method gl_compatibility -- --shot=/tmp/compat.png --size=5 --plies=10` and look at the image. The board and stones must be visible and the game playable. If it crashes, report; do not fix in this increment.
6. Try the self-test headless once: `dist/linux/tak.x86_64 --headless -- --selftest`. Report pass or fail; if it passes, add it to `package.sh` after the `--quit-after` smoke test.

Done-conditions (all checkable on stuart-gaming):

- `packaging/package.sh 0.0.0-local` with only the real `.so` present exits 0 and produces `dist/tak-0.0.0-local-linux.tar.gz` and `dist/SHA256SUMS.txt`.
- Extracting that tarball into an empty folder outside the repo and running `Tak/tak.x86_64` opens the game; `Tak/tak.x86_64 -- --shot=/tmp/x.png --size=5 --plies=10` writes a screenshot with stones on the board. (Stuart runs the interactive check himself if the executor cannot.)
- The stub run in step 4 produces the three layouts described.
- The compatibility screenshot from step 5 exists and the report says what it shows.
- `git status` shows only the new/changed files listed above; `godot/bin/` and `dist/` are not tracked.

### Increment 2: GitHub Actions workflow (Sonnet, effort high; runs in parallel with 3)

File: `.github/workflows/release.yml` (new). Also read `crates/tak-core/Cargo.toml` and confirm the Tiltak git URL is `https://` (an `ssh://` or `git@` URL cannot be fetched by the runner; if so, change it to https in this increment).

Workflow shape (the executor fills in the details; this structure is load-bearing):

```yaml
name: release
on:
  push:
    tags: ["v*"]
  workflow_dispatch:
permissions:
  contents: write
env:
  GODOT_VERSION: "4.7.1"
jobs:
  rust:
    strategy:
      fail-fast: false
      matrix:
        include:
          - { os: ubuntu-22.04,   lib: libtak_godot.so }
          - { os: windows-latest, lib: tak_godot.dll }
          - { os: macos-latest,   lib: libtak_godot.dylib }
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - if: runner.os != 'macOS'
        run: cargo build --release --locked -p tak-godot
      - if: runner.os == 'macOS'
        run: |
          rustup target add aarch64-apple-darwin x86_64-apple-darwin
          cargo build --release --locked -p tak-godot --target aarch64-apple-darwin
          cargo build --release --locked -p tak-godot --target x86_64-apple-darwin
          mkdir -p target/release
          lipo -create -output target/release/libtak_godot.dylib \
            target/aarch64-apple-darwin/release/libtak_godot.dylib \
            target/x86_64-apple-darwin/release/libtak_godot.dylib
          codesign --force --sign - target/release/libtak_godot.dylib
          lipo -info target/release/libtak_godot.dylib
      - uses: actions/upload-artifact@v4
        with: { name: "lib-${{ runner.os }}", path: "target/release/${{ matrix.lib }}", if-no-files-found: error }
  package:
    needs: rust
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4
      - uses: actions/download-artifact@v4
        with: { path: godot/bin, merge-multiple: true }
      - name: Install Godot ${{ env.GODOT_VERSION }} and export templates
        run: |  # download Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip and ..._export_templates.tpz,
                # unzip the editor to ~/godot/, templates into ~/.local/share/godot/export_templates/${GODOT_VERSION}.stable/
      - name: Version
        run: |  # tag run: VERSION=${GITHUB_REF_NAME#v}; dispatch: VERSION=0.0.0-${GITHUB_SHA::7}
      - run: GODOT=~/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64 packaging/package.sh --require-all "$VERSION"
      - name: Check Windows and macOS layouts
        run: |  # file dist/windows/Tak.exe | grep PE32+ ; unzip -l the mac zip | grep Contents/Frameworks/libtak_godot.dylib (path as recorded in increment 1)
      - uses: actions/upload-artifact@v4
        with: { name: dist, path: "dist/tak-*.* dist/SHA256SUMS.txt" }
      - if: startsWith(github.ref, 'refs/tags/v')
        env: { GH_TOKEN: "${{ github.token }}" }
        run: gh release create "$GITHUB_REF_NAME" dist/tak-*.zip dist/tak-*.tar.gz dist/SHA256SUMS.txt --title "Tak $VERSION" --notes-file packaging/release-notes.md
```

Also create `packaging/release-notes.md`: five lines saying which file to download per OS, that Windows and macOS are untested so far, and a link to the README's Download and play section. The `README.txt` placeholder from increment 1 is replaced in increment 3.

Local checks before handing to Stuart: `yamllint`-level sanity (`python3 -c 'import yaml,sys; yaml.safe_load(open(".github/workflows/release.yml"))'`), `gh release view 4.7.1-stable -R godotengine/godot --json assets -q '.assets[].name'` lists both download names used, and `gh api repos/actions/runner-images` is not needed: if `ubuntu-22.04` is refused at run time, switch both jobs to `ubuntu-24.04` and say so in the report.

Done-condition (needs Stuart's push; the orchestrator verifies with `gh`):

- After Stuart pushes to `main`, `gh workflow run release.yml` followed by `gh run watch` ends green; `gh run download -n dist` yields the three archives and the sums file; the Linux tarball runs on stuart-gaming.
- Fix loop: the orchestrator reads `gh run view <id> --log-failed`, sends the failing lines to the executor, four rounds maximum before `opus-specialist`. macOS alone still red after two rounds: remove it from the matrix and from `--require-all` (package only what is present) and ship two platforms.

### Increment 3: README rewrite, technical-testers section and the in-archive README.txt (Sonnet, effort medium; parallel with 2)

Files: `README.md`, `packaging/README.txt`. One brief because both README changes touch the same file.

README.md structure after the change (keep every section not named here as it is):

1. Title, description, Features: unchanged.
2. **Download and play** (replaces Install). Plain language, no shell commands except the Linux one and the Mac last resort. Content:
   - One sentence: "Download the file for your computer from the Releases page" with the link `https://github.com/stuartforsyth/tak/releases/latest`, and "You need a 64-bit computer from about 2016 or later with working graphics drivers. Nothing is installed; delete the folder to remove the game."
   - A three-row table: Windows -> `tak-<version>-windows.zip`; macOS -> `tak-<version>-macos.zip`; Linux -> `tak-<version>-linux.tar.gz`.
   - **Windows**: 1) download the zip; if Edge or Chrome says the file "isn't commonly downloaded", choose Keep (then "Keep anyway"); 2) right-click the zip > Extract All > Extract; 3) open the `Tak` folder and double-click `Tak`; 4) the first time, Windows shows a blue "Windows protected your PC" box: click **More info**, then **Run anyway**. It asks only once. 5) Untested so far: please tell me what happened.
   - **macOS**: 1) download; Safari unzips it to a folder with `Tak` in it (double-click the zip in other browsers); 2) optionally drag `Tak` to Applications; 3) double-click `Tak`. The first time macOS refuses because the game is not registered with Apple. What to do depends on your macOS version (Apple menu > About This Mac): **macOS 15 Sequoia or newer**: click Done, open System Settings > Privacy & Security, scroll to the bottom, find "Tak was blocked", click **Open Anyway**, then **Open Anyway** again and enter your password. **macOS 14 or older**: hold Control and click `Tak`, choose **Open**, then **Open** in the box. Either way it is a one-time step. 4) If macOS says the app is "damaged", open Terminal (Applications > Utilities) and paste `xattr -cr ~/Downloads/Tak.app` (adjust the path to where Tak is), then open it again. 5) Works on Intel and Apple Silicon Macs (one download). Untested so far: please tell me your Mac's chip and macOS version and what happened.
   - **Linux**: `tar xzf tak-<version>-linux.tar.gz && ./Tak/tak.x86_64`. Needs Vulkan drivers (Mesa 22+ or the vendor driver). Tested on Fedora.
   - **If something goes wrong**: black window or "Vulkan" error -> update graphics drivers; the game tries OpenGL automatically if Vulkan is missing. Send the operating system, the graphics card, the exact text of any message and, if possible, a screenshot. Mention the `LICENSE` and `README.txt` in the folder.
   - **Why the warnings**: one paragraph: the game is not signed with a paid Apple or Microsoft certificate, so both systems warn about any program from outside their stores. The source code is public (this repository) and anyone can build it from source.
3. **Testing requirements for technical testers** (new, directly below Download and play; Stuart's addition 2026-11-20). Until installers and signing exist this is how anyone technical tests the game, and it is the only home for build-from-source (the current Install text moves here, so nothing is duplicated). One short intro: "The downloads above are untested on Windows and macOS. If you can read a terminal, this section says what to check and what to send back." Then, per OS, in this order and with these headings so the executor does not have to invent structure:
   - **Prerequisites** (one table, rows Windows 10/11, macOS Intel, macOS Apple Silicon, Linux; columns OS version, graphics, runtime libraries):
     - Windows 10 (1809+) or 11, 64-bit. GPU with a Vulkan 1.0 driver (Intel HD 500 / Skylake 2015 and later, NVIDIA Kepler 2012 and later, AMD GCN 2012 and later); Godot falls back to Direct3D 12 and then OpenGL 3.3 on its own. No Visual C++ redistributable needed: the Rust library is built with a static CRT and Godot's template is static. Virtual machines and Remote Desktop usually have no Vulkan; expect the OpenGL fallback or a black window.
     - macOS Intel: the oldest macOS Godot 4.7 supports (the executor confirms the exact minimum on Godot's "System requirements" docs page for 4.7 and writes that number, not a guess); Metal-capable Mac (2012 and later). The download is universal; the x86_64 slice runs natively.
     - macOS Apple Silicon: same, arm64 slice runs natively; the app is ad-hoc signed, which is why Gatekeeper warns.
     - Linux: x86_64, glibc 2.35 or newer (Ubuntu 22.04+, Debian 12+, Fedora 36+), X11 or Wayland, a Vulkan driver (`mesa-vulkan-drivers` on Debian/Ubuntu, `mesa-vulkan-drivers` on Fedora, or the NVIDIA proprietary driver). Check with `vulkaninfo --summary` if installed.
   - **Running the release build** per OS: Windows: extract, run `Tak.exe` (there is no console build; output goes to the log file below). macOS: `open Tak.app`, or for console output `./Tak.app/Contents/MacOS/Tak` in Terminal. Linux: `./Tak/tak.x86_64` in a terminal.
   - **Building from source (the fallback when the download fails)**: the current README Install text, moved here and trimmed: Rust stable via rustup, git, Godot 4.7.1 standard (not .NET) from godotengine.org, a C toolchain (build-essential / Xcode command line tools / VS Build Tools with "Desktop development with C++"), then `./run.sh` on Linux and macOS (`GODOT=/Applications/Godot.app/Contents/MacOS/Godot ./run.sh` on a Mac) and the manual PowerShell commands on Windows (`cargo build --release -p tak-godot`, copy the DLL to `godot\bin\`, run `Godot...exe --path godot`). Keep the existing "If something goes wrong" developer bullets here.
   - **Self-test**: release build: `./tak.x86_64 -- --selftest` (Linux), `./Tak.app/Contents/MacOS/Tak -- --selftest` (macOS), `Tak.exe -- --selftest` then read the log file (Windows). From source: `godot --path godot -- --selftest`. Meaning: prints one pass/fail line per assertion and exits 0 when all pass, non-zero when any fail; it opens a window because it tests screen picking. Add `--headless` only if increment 1 found that the self-test passes headless.
   - **Useful flags** (a short table; everything before `--` is Godot's, everything after is the game's): `--verbose` (more log output), `--rendering-method gl_compatibility` (force the OpenGL path, the first thing to try on a black window), `--rendering-driver d3d12` (Windows only, force Direct3D 12), `--headless --quit-after 60` (prove the build starts without a GPU), `-- --shot=PATH.png --size=5 --plies=10` (render a sample position to a file and exit), `-- --selftest`.
   - **What to put in a bug report**: OS and version (Windows: Settings > System > About; Mac: Apple menu > About This Mac, including the chip; Linux: `uname -a` and distro); GPU and driver version (Windows: Task Manager > Performance > GPU, or `dxdiag`; Mac: About This Mac > Graphics; Linux: `vulkaninfo --summary | head` or `glxinfo -B`); how you got the game (release file name and version, or built from source at which commit); the exact text of any error; a screenshot; the console output if you ran it from a terminal; and the log file, which Godot writes for exported builds at: Windows `%APPDATA%\Godot\app_userdata\Tak\logs\godot.log`, macOS `~/Library/Application Support/Godot/app_userdata/Tak/logs/godot.log`, Linux `~/.local/share/godot/app_userdata/Tak/logs/godot.log` (the executor confirms the `app_userdata/Tak` name matches `config/name` in `project.godot` by running the Linux export once and listing the folder). Where to send it: a GitHub issue on this repository, or a message to Stuart.
4. Terminal version, Controls, Project layout (add `packaging/` and `.github/workflows/release.yml` rows), Tests, Difficulty levels, Roadmap: unchanged except the layout rows. The Tests section keeps its developer commands and gains one line pointing at the technical-testers section for the release-build equivalents.
5. **Developing** (new, after Tests): "Making a release" only: `packaging/package.sh <version>` builds the archives locally (Linux only unless the other libraries are in `godot/bin/`); CI does all three on a `v*` tag, see `.github/workflows/release.yml`; Godot is pinned at 4.7.1 in both places.
6. Licence section: unchanged, plus one sentence under "Why GPL": "Each download contains the licence and names the tag whose source it was built from."

`packaging/README.txt` (plain text, under 40 lines, `__VERSION__` placeholder): what it is, how to start it per OS (one line each), the same first-run warning steps condensed, the GPL sentence with the source offer ("The complete source for this build: https://github.com/stuartforsyth/tak/releases/tag/v__VERSION__ ; the Tiltak engine it contains: https://github.com/MortenLohne/tiltak at commit fc4f52f"), and the third-party notices: Godot Engine (MIT, copyright Juan Linietsky, Ariel Manzur and contributors), godot-rust (MPL-2.0), Tiltak (GPL-3.0-or-later, Morten Lohne). Say "Tak was designed by James Ernest and Patrick Rothfuss; this is an unofficial fan project."

Done-condition: Stuart reads the Download and play section as the friend would and finds no step that needs a terminal except on Linux; every command in the README is below the Download and play section; the technical-testers section has all six sub-headings above, the macOS minimum version and the log path are confirmed rather than guessed (the report says how); `packaging/package.sh 0.0.0-local` still succeeds and the tarball's `README.txt` shows `v0.0.0-local` in the source line.

### Increment 4: cut v0.1.0 (Stuart, no executor)

Done when the friend has played a game, or reported exactly what stopped them.

## What Stuart does himself

All commands run on stuart-gaming unless stated. None need sudo.

1. After increment 1 is verified: commit. In the repo folder, at the Claude prompt with `!` or your own terminal: `git add -A && git commit -m "Export presets and packaging script"`.
2. After increments 2 and 3: commit and push to main. Own terminal or `!`, repo folder: `git push origin main`.
3. Trial run without a tag. `!` or own terminal, repo folder: `gh workflow run release.yml && sleep 20 && gh run watch` (the orchestrator can do this and read `gh run view --log-failed` for the fix loop). If GitHub says the workflow is not allowed to write: GitHub web, Settings > Actions > General > Workflow permissions > "Read and write permissions" > Save (needed only if the repository or your account restricts the workflow-level `permissions:` block).
4. Cheapest probe once the dispatch run is green: `gh run download -n dist -D /tmp/tak-dist`, extract the Linux tarball into an empty folder, run `Tak/tak.x86_64`, play a few moves.
5. Tag and publish. Own terminal or `!`, repo folder: `git tag -a v0.1.0 -m "First downloadable build" && git push origin v0.1.0`. Watch with `gh run watch`, then open `https://github.com/stuartforsyth/tak/releases/tag/v0.1.0` and check four assets are listed, plus GitHub's automatic source zips.
6. Send the friend the link to the release page plus the README's section for their OS (copy the Windows or macOS steps into the message so they do not have to find them). Ask for: operating system and version, chip (Mac: About This Mac), graphics card (Windows: Settings > System > Display > Advanced display), and what happened at each step.

## What the friend does

Download one file, extract it, start `Tak`, click through the one-time warning following the steps for their OS, play. If it does not start: tell Stuart the exact message (a photo of the screen is fine), the OS version and the computer's age.

## Open questions that decide the plan (answer before increment 1)

1. Which OS does the friend have, and if a Mac, which chip and macOS version? This decides which README section gets the most care and whether macOS may be dropped from v0.1.0 if its CI job fights back.
2. Is `godot --version` on stuart-gaming exactly 4.7.1-stable? The plan pins that; if you develop on something else, pin that instead.
3. Bundle identifier for the Mac app: `com.stuartforsyth.tak` is a placeholder; do you have a domain you would rather use? It is cosmetic without signing but awkward to change later.
4. Are you happy to publish Windows and macOS builds labelled "untested" on a public Releases page, rather than sending the friend a private link first?
5. Should `v0.1.0` be marked a GitHub pre-release? (I say no: "Latest" is what the friend should see.)
6. `packaging/` as a new folder versus a third script at the root: any objection?
7. GPL corresponding source: is "public repo at the tag plus Tiltak's public repo at the pinned commit" enough for you, or do you want a vendored source tarball attached to each release now?

## Questions a relentless reviewer would grill Stuart on

Design intent
- What is success for this release: the friend plays one game, or plays enough games to give feedback on the levels? If the latter, is a download the bottleneck, or is it the missing menu/settings from the roadmap?
- Why three platforms before one of them has a tester? What does a broken Mac download on a public page cost you compared with waiting for a Mac tester?
- The game has a 100,000-node Hard level with no measured strength. On the friend's older laptop, how long is a Hard move going to take, and is there any feedback while it thinks?

UX
- 1600x900 fixed initial window on a 1366x768 laptop: does the window open off-screen, and should the first release start maximised or resizable instead? Cheap to fix in `project.godot`, but it is a change to the game, not the packaging.
- The macOS Sequoia route is six clicks through System Settings. Is that acceptable for this friend, or does it mean the Mac target really wants a Mac tester you can walk through it on a call?
- Linux users get a `.x86_64` file and a terminal command. Is that fine because every Linux tester you have is technical?
- Nothing in the game says which version it is. When the friend says "it crashed", how do you know which build they ran?

Trade-offs
- Universal Mac dylib doubles the Mac Rust build and adds `lipo`/`codesign` steps you cannot test locally. Would arm64-only (every Mac sold since 2020) be the smaller first step, with Intel on request?
- `+crt-static` on Windows makes the DLL self-contained but larger; pck embedding makes `Tak.exe` large and single-file. Any antivirus or SmartScreen concern with a large unsigned exe you would rather avoid by shipping the pck separately?
- Pinning Godot 4.7.1 means a future `godot-rust` bump that needs 4.8 changes two files and the templates. Acceptable, or do you want the pin in a single place (`packaging/godot-version`) read by both the script and the workflow?
- No build on push to main means the release workflow can rot silently between tags. Is a monthly manual dispatch good enough?

Failure modes
- The Mac `.app` is ad-hoc signed by Godot's exporter on a Linux host, and the dylib by Apple's linker on the Mac runner. If the nested signature does not satisfy Gatekeeper, the symptom is "damaged" and the `xattr` command is the only fix. Who walks the friend through Terminal if that happens?
- `--headless --quit-after 60` proves the extension loads, not that the Vulkan path works on the friend's GPU. The compat screenshot proves the OpenGL fallback works on your GPU. Neither proves anything on a 2015 laptop. What is the plan when the report is "black window"?
- Tiltak is fetched from a git rev at build time. If that commit or repo disappears, no release can be rebuilt. Does that change your answer to open question 7?
- GitHub retires runner images; `ubuntu-22.04` may be gone by the time you next tag. Is "switch to 24.04 and accept newer-glibc-only" the standing rule, or do you want the container build on the roadmap now?
- If the friend hits the warning dialog and stops, you learn nothing about the game. Is there a lower-friction fallback (a short screen recording, a call) you would try before buying a certificate?
