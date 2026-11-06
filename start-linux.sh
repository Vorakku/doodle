#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
binary="$project_dir/build/doodle_reef"
[[ -x "$binary" ]] || { echo 'Build first: bash build-linux.sh' >&2; exit 1; }
if [[ -n "${DOODLE_REEF_DATA_DIR:-}" ]]; then
    data_dir="$DOODLE_REEF_DATA_DIR"
elif [[ -n "${XDG_DATA_HOME:-}" ]]; then
    data_dir="$XDG_DATA_HOME/doodle-reef"
else
    data_dir="$HOME/.local/share/doodle-reef"
fi
mkdir -p -- "$data_dir"
# Preserve a portable reef when first moving this project from Windows to Linux.
if [[ ! -e "$data_dir/creatures.reef" && -f "$project_dir/build/data/creatures.reef" ]]; then
    cp -n -- "$project_dir/build/data/creatures.reef" "$data_dir/creatures.reef"
fi
exec "$binary" --data-dir "$data_dir" "$@"
