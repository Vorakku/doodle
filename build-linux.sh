#!/usr/bin/env bash
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

"$goose_bin" -O2 --standalone -o build/doodle_reef.c doodle_reef.goose
gfx_link="$("$goose_bin" --gfx-link cc)"
ui_link="$("$goose_bin" --ui-link cc)"
read -r -a includes <<< "$(pkg-config --cflags sdl3 wayland-client)"
read -r -a wayland_libs <<< "$(pkg-config --libs wayland-client)"
# Keep the bridge's xdg protocol descriptors separate from SDL's own copies.
protocol_names=()
for name in xdg_wm_base xdg_positioner xdg_surface xdg_toplevel xdg_popup; do
    protocol_names+=("-D${name}_interface=reef_${name}_interface")
done
"${CC:-cc}" -O2 build/doodle_reef.c platform/wallpaper_wayland.c \
    build/wayland/wlr-layer-shell-protocol.c build/wayland/xdg-shell-protocol.c \
    -Ibuild/wayland "${includes[@]}" "${protocol_names[@]}" \
    -Wl,--wrap=SDL_CreateWindow -Wl,--start-group "@$gfx_link" "@$ui_link" -Wl,--end-group \
    "${wayland_libs[@]}" -lm -ldl -lpthread -o build/doodle_reef
echo 'Built build/doodle_reef. No tests or wallpaper processes were run.'
