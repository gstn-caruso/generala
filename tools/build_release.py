#!/usr/bin/env python3
"""Export a versioned Linux ZIP with notices and SHA-256 checksums."""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

from check import run_godot


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        parser.error("Version must be MAJOR.MINOR.PATCH")
    config = json.loads(Path("release-config.json").read_text())
    slug = config["slug"]
    folder = Path("build") / f"{slug}-{args.version}-linux-x86_64"
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True, exist_ok=True)
    executable = folder / (slug + ".x86_64")
    version_file = Path("version.txt")
    preset_file = Path("export_presets.cfg")
    original_version = version_file.read_bytes()
    original_presets = preset_file.read_bytes()
    try:
        version_file.write_text(args.version + "\n")
        template = os.environ.get("GODOT_RELEASE_TEMPLATE")
        if template:
            preset_file.write_text(original_presets.decode().replace('custom_template/release=""', 'custom_template/release=' + json.dumps(str(Path(template).resolve()))))
        run_godot(["--export-release", config["export_preset"], str(executable.resolve())], timeout=300)
    finally:
        version_file.write_bytes(original_version)
        preset_file.write_bytes(original_presets)
    # Run the actual exported binary with isolated user data, not just the editor.
    with tempfile.TemporaryDirectory(prefix="godot-export-smoke-") as user_data:
        env = {**os.environ, "XDG_DATA_HOME": user_data}
        result = subprocess.run([str(executable.resolve()), "--headless", "--quit-after", "20", "--", "--test-mode"], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=45)
        print(result.stdout, end="")
        if result.returncode or re.search(r"^(?:SCRIPT )?ERROR:", result.stdout, re.MULTILINE):
            raise RuntimeError("Exported binary smoke test failed")
    for filename in ["LICENSE", "THIRD_PARTY_NOTICES.md", "CREDITS.md"]:
        shutil.copy(filename, folder)
    shutil.copytree("licenses", folder / "licenses", dirs_exist_ok=True)
    shutil.copy(version_file, folder / "version.txt")
    (folder / "version.txt").write_text(args.version + "\n")
    (folder / "RUN.txt").write_text(
        f"{config['title']} v{args.version}\n\n"
        f"Extraé el ZIP y ejecutá ./{executable.name}\n"
        f"Si hace falta: chmod +x {executable.name}\n"
        "No requiere instalar Godot. Necesita Linux x86_64 y OpenGL 3.3 o superior.\n\n"
        "1–4 jugadores locales, por turnos en la misma computadora.\n"
        "Espacio: tirar. Clic en los dados o teclas 1–5: conservar/liberar.\n"
        "Clic en una categoría libre de la planilla: anotar y pasar el turno.\n"
        "Esc: menú. F1: reglas. M: sonido.\n\n"
        "Las partidas se guardan localmente de forma automática.\n"
        "Código: MIT. Assets y motor: ver THIRD_PARTY_NOTICES.md y licenses/.\n",
        encoding="utf-8")
    archive = Path("build") / (folder.name + ".zip")
    # Stable archive metadata; keep Unix execute permissions when extracting.
    timestamp = int(os.environ.get("SOURCE_DATE_EPOCH") or subprocess.check_output(
        ["git", "log", "-1", "--format=%ct"], text=True).strip())
    import time
    archive_time = time.gmtime(max(timestamp, 315532800))[:6]
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zipped:
        for file in sorted(folder.rglob("*")):
            if file.is_file():
                entry = zipfile.ZipInfo(str(file.relative_to(folder.parent)), archive_time)
                entry.create_system = 3
                entry.external_attr = (0o100755 if file == executable else 0o100644) << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                zipped.writestr(entry, file.read_bytes())
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (Path("build") / "SHA256SUMS.txt").write_text(f"{digest}  {archive.name}\n")
    print("Built", archive)


if __name__ == "__main__":
    main()
