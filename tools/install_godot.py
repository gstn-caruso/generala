#!/usr/bin/env python3
"""Install native official Godot and matching templates, verifying SHA-512."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import sys
import time
import urllib.request
import zipfile

from platforms import GROUPS, host_group, template_names


def fetch(url, destination):
    for attempt in range(3):
        try:
            urllib.request.urlretrieve(url, destination)
            return
        except OSError:
            if attempt == 2:
                raise
            time.sleep(2 ** attempt)


def digest(path, algorithm="sha512"):
    result = hashlib.new(algorithm)
    with Path(path).open("rb") as source:
        for chunk in iter(lambda: source.read(4 * 1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def extract_member(archive, member, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + ".tmp")
    with archive.open(member) as source, temporary.open("wb") as target:
        shutil.copyfileobj(source, target)
    if os.name != "nt":
        mode = (archive.getinfo(member).external_attr >> 16) & 0o777
        temporary.chmod(mode or 0o755)
    temporary.replace(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--group", choices=GROUPS, default=host_group())
    parser.add_argument("--editor-only", action="store_true")
    args = parser.parse_args()
    version = json.loads(Path("release-config.json").read_text())["godot_version"]
    arm = platform.machine().lower() in ("arm64", "aarch64")
    host = "macos" if sys.platform == "darwin" else "windows" if os.name == "nt" else "linux"
    if host == "macos":
        suffix = "macos.universal.zip"
    elif host == "windows":
        suffix = "windows_arm64.exe.zip" if arm else "win64.exe.zip"
    else:
        suffix = "linux.arm64.zip" if arm else "linux.x86_64.zip"
    cache = Path.home() / ".cache/godot-release" / version
    editor_dir = cache / (host + ("-arm64" if arm else "-x86_64")) / "editor"
    editor_name = f"Godot_v{version}-stable_" + suffix.removesuffix(".zip")
    if host == "macos":
        editor = editor_dir / "Godot.app/Contents/MacOS/Godot"
    elif host == "windows":
        editor = editor_dir / editor_name.replace(".exe", "_console.exe")
    else:
        editor = editor_dir / editor_name
    templates = cache / "templates"
    names = [] if args.editor_only else template_names(args.group)
    missing = [name for name in names if not (templates / name).is_file()]
    base = f"https://github.com/godotengine/godot-builds/releases/download/{version}-stable/"
    if not editor.is_file() or missing:
        cache.mkdir(parents=True, exist_ok=True)
        with urllib.request.urlopen(base + "SHA512-SUMS.txt", timeout=60) as source:
            expected = {line.split()[1].lstrip("*"): line.split()[0]
                        for line in source.read().decode().splitlines() if len(line.split()) == 2}

        def download_archive(filename):
            archive = cache / filename
            print("Downloading", filename, flush=True)
            fetch(base + filename, archive)
            if digest(archive) != expected[filename]:
                archive.unlink()
                raise RuntimeError("Official SHA-512 checksum mismatch: " + filename)
            return archive

        if not editor.is_file():
            archive = download_archive(f"Godot_v{version}-stable_" + suffix)
            try:
                with zipfile.ZipFile(archive) as package:
                    for info in package.infolist():
                        if not info.is_dir():
                            relative = Path(info.filename)
                            if relative.is_absolute() or ".." in relative.parts:
                                raise RuntimeError("Invalid editor archive member")
                            extract_member(package, info.filename, editor_dir / relative)
            finally:
                archive.unlink(missing_ok=True)
        if missing:
            archive = download_archive(f"Godot_v{version}-stable_export_templates.tpz")
            try:
                with zipfile.ZipFile(archive) as package:
                    for name in missing:
                        extract_member(package, "templates/" + name, templates / name)
            finally:
                archive.unlink(missing_ok=True)
    if not editor.is_file():
        raise RuntimeError("Editor executable not found: " + str(editor))
    if os.environ.get("GITHUB_ENV"):
        with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as output:
            output.write(f"GODOT={editor}\nGODOT_TEMPLATES={templates}\n")
    print(editor)
    print(templates)


if __name__ == "__main__":
    main()
