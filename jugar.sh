#!/usr/bin/env bash
set -euo pipefail

generala_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
generala_cache="${XDG_DATA_HOME:-$HOME/.local/share}/generala/godot-4.7.2"
generala_engine="${GODOT_BIN:-}"

if [[ -z "$generala_engine" ]]; then
    for generala_command in godot4 godot; do
        if generala_candidate="$(command -v "$generala_command")"; then
            generala_version="$("$generala_candidate" --version)"
            if [[ "$generala_version" =~ ^4\.([0-9]+)\. ]] && (( BASH_REMATCH[1] >= 6 )); then
                generala_engine="$generala_candidate"
                break
            fi
        fi
    done
fi

if [[ -z "$generala_engine" ]]; then
    if [[ ! -x "$generala_cache" ]]; then
        "$generala_root/tools/instalar_godot.sh"
    fi
    generala_engine="$generala_cache"
fi

# Import on a fresh checkout or when upgrading to the KayKit models.
if [[ ! -f "$generala_root/.godot/global_script_class_cache.cfg" || ! -d "$generala_root/.godot/imported" ]] ||
    ! compgen -G "$generala_root/.godot/imported/D6_B.gltf-*.scn" > /dev/null; then
    "$generala_engine" --headless --path "$generala_root" --editor --import --quit
fi
exec "$generala_engine" --path "$generala_root" "$@"
