#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
    printf '%s\n' 'Instalá Godot 4.6 o superior desde https://godotengine.org/download/ e importá project.godot.' >&2
    exit 1
fi

generala_cache="${XDG_DATA_HOME:-$HOME/.local/share}/generala"
generala_temp="$(mktemp -d)"
trap 'rm -rf -- "$generala_temp"' EXIT
generala_url='https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip'
printf '%s\n' 'Descargando Godot 4.7.2 oficial en el directorio local del usuario…'
curl --fail --location --retry 2 "$generala_url" --output "$generala_temp/godot.zip"
python3 - "$generala_temp/godot.zip" "$generala_cache" <<'PY'
import hashlib
import os
from pathlib import Path
import sys
import zipfile

archive = Path(sys.argv[1])
expected = "cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4"
if hashlib.sha256(archive.read_bytes()).hexdigest() != expected:
    raise SystemExit("El archivo no pasó la verificación SHA-256.")
destination = Path(sys.argv[2])
destination.mkdir(parents=True, exist_ok=True)
temporary = destination / "godot-4.7.2.tmp"
with zipfile.ZipFile(archive) as package:
    temporary.write_bytes(package.read("Godot_v4.7.2-stable_linux.x86_64"))
temporary.chmod(0o755)
os.replace(temporary, destination / "godot-4.7.2")
print(f"Godot listo: {destination / 'godot-4.7.2'}")
PY
