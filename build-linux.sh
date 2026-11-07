#!/usr/bin/env bash
# Usage: build-linux.sh [--test]
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

goose_bin="${GOOSE:-$PWD/.tools/goose-v2026.3-linux-x64/goose}"
if [[ ! -x "$goose_bin" ]]; then
    echo 'Set GOOSE to the Goose v2026.3 executable, or extract its Linux x64 release into .tools.' >&2
    exit 1
fi
for tool in "${CC:-cc}" pkg-config wayland-scanner; do
    command -v "$tool" >/dev/null || { echo "Missing build tool: $tool" >&2; exit 1; }
done
pkg-config --exists sdl3 wayland-client wayland-protocols
mkdir -p build/wayland .tools/cache
export GOOSE_HOME="${GOOSE_HOME:-$PWD/.tools/cache}"
xdg_xml="$(pkg-config --variable=pkgdatadir wayland-protocols)/stable/xdg-shell/xdg-shell.xml"
wayland-scanner client-header platform/wlr-layer-shell-unstable-v1.xml build/wayland/wlr-layer-shell-client-protocol.h
wayland-scanner private-code platform/wlr-layer-shell-unstable-v1.xml build/wayland/wlr-layer-shell-protocol.c
wayland-scanner private-code "$xdg_xml" build/wayland/xdg-shell-protocol.c

# Goose's bundled libSDL3.a has no Wayland driver, so link the system SDL3 instead.
grep -hv '/libSDL3\.a$' "$("$goose_bin" --gfx-link cc)" "$("$goose_bin" --ui-link cc)" | sort -u > build/link.rsp
read -r -a includes <<< "$(pkg-config --cflags sdl3 wayland-client)"
read -r -a system_libs <<< "$(pkg-config --libs sdl3 wayland-client)"
# Keep the bridge's xdg protocol descriptors separate from SDL's own copies.
protocol_names=()
for name in xdg_wm_base xdg_positioner xdg_surface xdg_toplevel xdg_popup; do
    protocol_names+=("-D${name}_interface=reef_${name}_interface")
done

compile() { # SOURCE.goose OUTPUT [CFLAGS...]
    "$goose_bin" -O2 --standalone -o "$2.c" "$1"
    "${CC:-cc}" -O2 "${@:3}" "$2.c" platform/wallpaper_wayland.c platform/image_file.c platform/image_dialog.c \
        build/wayland/wlr-layer-shell-protocol.c build/wayland/xdg-shell-protocol.c \
        -Ibuild/wayland "${includes[@]}" "${protocol_names[@]}" \
        -Wl,--wrap=SDL_CreateWindow -Wl,--start-group @build/link.rsp -Wl,--end-group \
        "${system_libs[@]}" -lm -ldl -lpthread -o "$2"
}

if [[ "${1:-}" == --test ]]; then
    "$goose_bin" reef_test.goose --debug
    mkdir -p .test-data
    compile reef_ui_test.goose .test-data/reef_ui_test -DREEF_IMPORT_TESTS
    GOOSE_GFX_HEADLESS=1 .test-data/reef_ui_test
    echo 'Model and UI checks passed.'
fi
compile doodle_reef.goose build/doodle_reef
install -m 755 platform/set-background-linux.sh build/set-background-linux.sh
# A running wallpaper keeps the old binary until restarted; does nothing if none is running.
systemctl --user try-restart 'doodle-reef-wallpaper@*.service' 2>/dev/null || true
echo 'Built build/doodle_reef.'
