#!/usr/bin/env bash
# Makes the aquarium the desktop background on every current Hyprland monitor, across logins.
# Usage: set-background-linux.sh DATA_DIR | --off
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
units_dir="$config_home/systemd/user"
unit_file="$units_dir/doodle-reef-wallpaper@.service"
caelestia_config="$config_home/caelestia/shell.json"

die() { echo "DOODLE REEF background: $1" >&2; exit 1; }

set_caelestia_wallpaper() {
    [[ -f "$caelestia_config" ]] || return 0
    local target tmp
    target="$(readlink -f -- "$caelestia_config")"
    [[ -e "$target.doodle-reef.bak" ]] || cp -- "$target" "$target.doodle-reef.bak"
    tmp="$(mktemp -- "$target.XXXXXX")"
    if jq --argjson on "$1" '.background.wallpaperEnabled = $on' "$target" > "$tmp"; then
        chmod --reference="$target" -- "$tmp"
        mv -- "$tmp" "$target"
    else
        rm -f -- "$tmp"
        return 1
    fi
}

turn_off() {
    # Give Caelestia its wallpaper back first, so the desktop never shows through empty.
    set_caelestia_wallpaper true
    shopt -s nullglob
    local link
    for link in "$units_dir"/graphical-session.target.wants/doodle-reef-wallpaper@*.service; do
        systemctl --user disable --now "${link##*/}"
    done
    rm -f -- "$unit_file"
    systemctl --user daemon-reload
}

systemd_quote() {
    local s="${1//\\/\\\\}"
    s="${s//\"/\\\"}"; s="${s//%/%%}"; s="${s//\$/\$\$}"
    printf '"%s"' "$s"
}

[[ $# -eq 1 ]] || die "usage: set-background-linux.sh DATA_DIR | --off"
if [[ "$1" == --off ]]; then turn_off; exit 0; fi

for tool in hyprctl jq systemctl; do
    command -v "$tool" >/dev/null || die "missing required tool: $tool"
done
binary="$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/doodle_reef"
[[ -x "$binary" ]] || die "$binary not found; run build-linux.sh"
data_dir="$(realpath -- "$1")"
# shortcut: needs a systemd-managed session (uwsm), add an exec-once fallback for others if wanted.
systemctl --user --quiet is-active graphical-session.target ||
    die "graphical-session.target is not active; start Hyprland through uwsm"

mapfile -t monitors < <(hyprctl monitors -j | jq -r '.[].name')
[[ ${#monitors[@]} -gt 0 ]] || die "Hyprland reports no monitors"
units=()
for monitor in "${monitors[@]}"; do units+=("doodle-reef-wallpaper@$monitor.service"); done

mkdir -p -- "$units_dir"
cat > "$unit_file" <<EOF
[Unit]
Description=DOODLE REEF wallpaper on %i
PartOf=graphical-session.target
After=graphical-session.target
StartLimitIntervalSec=0

[Service]
ExecStart=$(systemd_quote "$binary") --wallpaper --output %i --data-dir $(systemd_quote "$data_dir")
# A monitor that was unplugged ends its process; keep retrying until it returns.
Restart=always
RestartSec=10

[Install]
WantedBy=graphical-session.target
EOF
systemctl --user daemon-reload
systemctl --user enable "${units[@]}" 2>/dev/null
systemctl --user restart "${units[@]}"

# Only hide the current wallpaper once the aquarium is really on screen.
for _ in {1..40}; do
    count="$(hyprctl layers -j | jq '[.. | objects | select(.namespace? == "doodle-reef")] | length')"
    if (( count >= ${#monitors[@]} )); then
        set_caelestia_wallpaper false
        exit 0
    fi
    sleep 0.25
done
turn_off
die "the aquarium did not appear; see: journalctl --user -u 'doodle-reef-wallpaper@*'"
