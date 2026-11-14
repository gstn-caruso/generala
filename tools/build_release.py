#!/usr/bin/env python3
"""Build and validate native packages from pinned Godot export templates."""
import argparse
import configparser
import gzip
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import zipfile

from check import run_godot
from install_godot import digest, fetch
from platforms import GROUPS, TARGETS, host_group

OUT = Path("build/releases")
IDENTIFIER = "io.github.gstn-caruso.generala"
APPIMAGE_TOOLS = {
    "x86_64": ("appimagetool-x86_64.AppImage", "ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"),
    "arm64": ("appimagetool-aarch64.AppImage", "f0837e7448a0c1e4e650a93bb3e85802546e60654ef287576f46c71c126a9158"),
}
APPIMAGE_RUNTIMES = {
    "x86_64": ("runtime-x86_64", "2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d"),
    "arm64": ("runtime-aarch64", "00cbdfcf917cc6c0ff6d3347d59e0ca1f7f45a6df1a428a0d6d8a78664d87444"),
}


def run(arguments, timeout=180, env=None):
    result = subprocess.run([str(a) for a in arguments], env=env, text=True,
        encoding="utf-8", errors="replace", stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=timeout)
    print(result.stdout, end="", flush=True)
    if result.returncode:
        raise RuntimeError("Command failed: " + " ".join(str(a) for a in arguments))
    return result.stdout


def smoke(binary, prefix=()):
    with tempfile.TemporaryDirectory(prefix="generala-package-test-") as temporary:
        env = {**os.environ, "XDG_DATA_HOME": temporary, "APPDATA": temporary,
               "LOCALAPPDATA": temporary, "APPIMAGE_EXTRACT_AND_RUN": "1"}
        output = run([*prefix, Path(binary).resolve(), "--headless", "--quit-after", "20",
                      "--", "--test-mode"], timeout=90, env=env)
        if re.search(r"^(?:SCRIPT )?ERROR:", output, re.MULTILINE):
            raise RuntimeError("Exported game logged an error")


def timestamp():
    return int(os.environ.get("SOURCE_DATE_EPOCH") or subprocess.check_output(
        ["git", "log", "-1", "--format=%ct"], text=True).strip())


def archive_zip(folder, destination):
    date = time.gmtime(max(timestamp(), 315532800))[:6]
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as package:
        for file in sorted(folder.rglob("*")):
            if file.is_dir() and not file.is_symlink():
                continue
            entry = zipfile.ZipInfo(file.relative_to(folder.parent).as_posix(), date)
            entry.create_system = 3
            entry.compress_type = zipfile.ZIP_DEFLATED
            if file.is_symlink():
                entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                package.writestr(entry, os.readlink(file).encode())
            else:
                executable = bool(file.stat().st_mode & 0o111) or file.suffix == ".exe"
                entry.external_attr = (stat.S_IFREG | (0o755 if executable else 0o644)) << 16
                package.writestr(entry, file.read_bytes())


def archive_tar(folder, destination):
    with destination.open("wb") as output, gzip.GzipFile(filename="", mode="wb",
            fileobj=output, mtime=timestamp()) as compressed, tarfile.open(
            fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as package:
        for file in sorted([folder, *folder.rglob("*")]):
            info = package.gettarinfo(str(file), arcname=file.relative_to(folder.parent).as_posix())
            info.uid = info.gid = 0
            info.uname = info.gname = "root"
            info.mtime = timestamp()
            if info.isfile():
                with file.open("rb") as source:
                    package.addfile(info, source)
            else:
                package.addfile(info)


def add_notices(folder, version, family):
    for name in ["LICENSE", "CREDITS.md", "THIRD_PARTY_NOTICES.md"]:
        shutil.copyfile(name, folder / name)
    shutil.copytree("licenses", folder / "licenses", dirs_exist_ok=True)
    (folder / "version.txt").write_text(version + "\n", encoding="utf-8")
    start = {
        "linux": "Ejecutá ./generala.x86_64 o ./generala.arm64, según el archivo incluido.",
        "windows": "Abrí generala.exe. El archivo .console.exe permite ver el registro de diagnóstico.",
        "macos": "Arrastrá Generala.app a Aplicaciones. App universal para Intel y Apple Silicon.\nFirma ad hoc gratuita, sin notarización. Si Gatekeeper la bloquea, usá Privacidad y seguridad > Abrir igualmente.",
        "web": "Serví esta carpeta por HTTP: python3 -m http.server 8000\nAbrí http://localhost:8000 en un navegador con WebGL 2.0. No abras index.html como archivo local.",
    }[family]
    (folder / "RUN.txt").write_text(
        f"Generala · Club de dados v{version}\n\n{start}\n\n"
        "No requiere instalar Godot.\n"
        "Espacio o clic en el cubilete: tirar. Dados o teclas 1–5: conservar/liberar.\n"
        "Clic en una categoría: anotar. Esc: menú. F1: reglas. M: sonido.\n"
        "1–4 jugadores locales. Guardado automático.\n\n"
        "Código MIT. Licencias de los assets y motor en THIRD_PARTY_NOTICES.md y licenses/.\n",
        encoding="utf-8")


def export_game(target, folder, version, templates):
    executable = folder / ("Generala.app" if target.family == "macos" else
        "index.html" if target.family == "web" else "generala.exe" if target.family == "windows"
        else "generala." + target.arch)
    template = templates / target.template
    if not template.is_file():
        raise RuntimeError("Missing export template: " + str(template))
    version_path, preset_path = Path("version.txt"), Path("export_presets.cfg")
    old_version, old_presets = version_path.read_bytes(), preset_path.read_bytes()
    try:
        version_path.write_text(version + "\n", encoding="utf-8")
        settings = configparser.ConfigParser(interpolation=None, strict=True)
        settings.optionxform = str
        settings.read_string(old_presets.decode("utf-8"))
        section = next(s for s in settings.sections() if re.fullmatch(r"preset\.\d+", s)
                       and json.loads(settings[s]["name"]) == target.preset)
        options = settings[section + ".options"]
        options["custom_template/release"] = json.dumps(str(template.resolve()))
        if target.family == "windows":
            options["application/file_version"] = json.dumps(version + ".0")
            options["application/product_version"] = json.dumps(version + ".0")
        elif target.family == "macos":
            options["application/version"] = json.dumps(version)
            options["application/short_version"] = json.dumps(version)
        with preset_path.open("w", encoding="utf-8") as output:
            settings.write(output)
        run_godot(["--export-release", target.preset, str(executable.resolve())], timeout=300)
    finally:
        version_path.write_bytes(old_version)
        preset_path.write_bytes(old_presets)
    if not executable.exists():
        raise RuntimeError("Export not created: " + str(executable))
    return executable


def linux_tree(binary, root):
    game = root / "usr/games/generala"
    game.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(binary, game)
    game.chmod(0o755)
    applications = root / "usr/share/applications"
    applications.mkdir(parents=True)
    (applications / (IDENTIFIER + ".desktop")).write_text(
        "[Desktop Entry]\nType=Application\nName=Generala\n"
        "Comment=Juego de dados 3D para 1–4 jugadores\n"
        f"Exec=/usr/games/generala\nIcon={IDENTIFIER}\nTerminal=false\n"
        "Categories=Game;BoardGame;\nStartupNotify=true\n", encoding="utf-8")
    icons = root / "usr/share/icons/hicolor/scalable/apps"
    icons.mkdir(parents=True)
    shutil.copyfile("assets/icon.svg", icons / (IDENTIFIER + ".svg"))
    notices = root / "usr/share/doc/generala"
    notices.mkdir(parents=True)
    for name in ["LICENSE", "CREDITS.md", "THIRD_PARTY_NOTICES.md"]:
        shutil.copyfile(name, notices / name)
    shutil.copytree("licenses", notices / "licenses")
    for file in root.rglob("*"):
        if not file.is_symlink():
            os.utime(file, (timestamp(), timestamp()))
    return game


def build_deb(target, binary, version, work):
    root = work / "deb-root"
    installed_game = linux_tree(binary, root)
    control = root / "DEBIAN"
    control.mkdir()
    arch = "amd64" if target.arch == "x86_64" else "arm64"
    size = sum(p.stat().st_size for p in root.rglob("*") if p.is_file()) // 1024 + 1
    (control / "control").write_text(
        f"Package: generala\nVersion: {version}\nArchitecture: {arch}\n"
        "Section: games\nPriority: optional\n"
        "Maintainer: Gastón Caruso <gstn.caruso@gmail.com>\n"
        f"Installed-Size: {size}\n"
        "Depends: libc6, libgcc-s1, libstdc++6, libx11-6, libxcursor1, libxinerama1, libxi6, libxrandr2, libgl1, libasound2t64 | libasound2, libpulse0\n"
        "Homepage: https://github.com/gstn-caruso/generala\n"
        "Description: Generala 3D para 1 a 4 jugadores\n"
        " Dados físicos, planilla de puntajes y guardado automático.\n", encoding="utf-8")
    artifact = OUT / f"generala_{version}_{arch}.deb"
    env = {**os.environ, "SOURCE_DATE_EPOCH": str(timestamp())}
    run(["dpkg-deb", "--root-owner-group", "-Zxz", "--build", root, artifact], timeout=180, env=env)
    metadata = run(["dpkg-deb", "--field", artifact, "Package", "Version", "Architecture"])
    if version not in metadata or arch not in metadata:
        raise RuntimeError("Invalid Debian metadata")
    extracted = work / "deb-extracted"
    run(["dpkg-deb", "--extract", artifact, extracted])
    smoke(extracted / installed_game.relative_to(root))
    return artifact


def build_rpm(target, binary, version, work):
    root = work / "rpm-stage"
    linux_tree(binary, root)
    top = (work / "rpmbuild").resolve()
    for directory in ["BUILD", "BUILDROOT", "RPMS", "SOURCES", "SPECS", "SRPMS"]:
        (top / directory).mkdir(parents=True, exist_ok=True)
    arch = "x86_64" if target.arch == "x86_64" else "aarch64"
    spec = top / "SPECS/generala.spec"
    spec.write_text(f"""Name: generala
Version: {version}
Release: 1
Summary: Generala 3D para 1 a 4 jugadores
License: MIT AND CC0-1.0 AND OFL-1.1 AND LicenseRef-DejaVu
URL: https://github.com/gstn-caruso/generala
BuildArch: {arch}
Requires: glibc, libstdc++, libX11, libXcursor, libXinerama, libXi, libXrandr, mesa-libGL, alsa-lib, pulseaudio-libs
AutoReqProv: no
%description
Juego local de dados 3D con planilla de puntajes y guardado automático.
%prep
%build
%install
mkdir -p %{{buildroot}}
cp -a {shlex.quote(str(root.resolve()))}/usr %{{buildroot}}/
%files
/usr/games/generala
/usr/share/applications/{IDENTIFIER}.desktop
/usr/share/icons/hicolor/scalable/apps/{IDENTIFIER}.svg
/usr/share/doc/generala
""", encoding="utf-8")
    run(["rpmbuild", "-bb", "--define", f"_topdir {top}", "--define", "_build_id_links none",
         "--define", "__os_install_post %{nil}", "--target", arch, spec], timeout=180,
        env={**os.environ, "SOURCE_DATE_EPOCH": str(timestamp())})
    created = next((top / "RPMS").rglob("*.rpm"))
    artifact = OUT / f"generala-{version}-1.{arch}.rpm"
    shutil.copyfile(created, artifact)
    metadata = run(["rpm", "-qp", "--queryformat", "%{VERSION} %{ARCH}", artifact])
    if metadata.strip() != version + " " + arch:
        raise RuntimeError("Invalid RPM metadata")
    return artifact


def build_appimage(target, binary, version, work):
    appdir = (work / "Generala.AppDir").resolve()
    linux_tree(binary, appdir)
    desktop = appdir / (IDENTIFIER + ".desktop")
    shutil.copyfile(appdir / "usr/share/applications" / desktop.name, desktop)
    desktop.write_text(desktop.read_text(encoding="utf-8").replace("Exec=/usr/games/generala", "Exec=generala"), encoding="utf-8")
    shutil.copyfile("assets/icon.svg", appdir / (IDENTIFIER + ".svg"))
    launcher = appdir / "AppRun"
    launcher.write_text('#!/bin/sh\nappdir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"\nexec "$appdir/usr/games/generala" "$@"\n')
    launcher.chmod(0o755)
    filename, expected = APPIMAGE_TOOLS[target.arch]
    tool = Path.home() / ".cache/generala-appimage/1.9.1" / filename
    if not tool.is_file() or digest(tool, "sha256") != expected:
        tool.parent.mkdir(parents=True, exist_ok=True)
        fetch("https://github.com/AppImage/appimagetool/releases/download/1.9.1/" + filename, tool)
    if digest(tool, "sha256") != expected:
        raise RuntimeError("AppImage tool SHA-256 mismatch")
    tool.chmod(0o755)
    runtime_name, runtime_hash = APPIMAGE_RUNTIMES[target.arch]
    runtime = Path.home() / ".cache/generala-appimage/20251108" / runtime_name
    if not runtime.is_file() or digest(runtime, "sha256") != runtime_hash:
        runtime.parent.mkdir(parents=True, exist_ok=True)
        fetch("https://github.com/AppImage/type2-runtime/releases/download/20251108/" + runtime_name, runtime)
    if digest(runtime, "sha256") != runtime_hash:
        raise RuntimeError("AppImage runtime SHA-256 mismatch")
    artifact = (OUT / f"generala-{version}-{target.id}.AppImage").resolve()
    env = {**os.environ, "ARCH": "x86_64" if target.arch == "x86_64" else "aarch64",
        "VERSION": version, "SOURCE_DATE_EPOCH": str(timestamp()), "APPIMAGE_EXTRACT_AND_RUN": "1"}
    run([tool, "--appimage-extract-and-run", "--no-appstream", "--runtime-file", runtime,
        "--mksquashfs-opt=-processors", "--mksquashfs-opt=2", appdir, artifact], timeout=240, env=env)
    artifact.chmod(0o755)
    smoke(artifact)
    return artifact


def validate_pe(binary, arch):
    with binary.open("rb") as source:
        if source.read(2) != b"MZ":
            raise RuntimeError("Missing Windows executable header")
        source.seek(0x3c)
        offset = int.from_bytes(source.read(4), "little")
        source.seek(offset)
        if source.read(4) != b"PE\0\0":
            raise RuntimeError("Missing PE signature")
        machine = int.from_bytes(source.read(2), "little")
    if machine != {"x86_64": 0x8664, "x86_32": 0x14c, "arm64": 0xaa64}[arch]:
        raise RuntimeError("Incorrect Windows architecture")


def native_macos(binary_app):
    info = plistlib.loads((binary_app / "Contents/Info.plist").read_bytes())
    binary = binary_app / "Contents/MacOS" / info["CFBundleExecutable"]
    architectures = run(["lipo", "-archs", binary]).split()
    if not {"x86_64", "arm64"}.issubset(architectures):
        raise RuntimeError("macOS bundle is not Universal 2")
    run(["codesign", "--verify", "--deep", "--strict", binary_app])
    smoke(binary)


def build_target(target, version, templates, skip_rpm=False):
    work = Path("build/work") / target.id
    if work.exists():
        shutil.rmtree(work)
    folder = work / f"generala-{version}-{target.id}"
    folder.mkdir(parents=True)
    binary = export_game(target, folder, version, templates)
    if target.family == "linux":
        binary.chmod(0o755)
        smoke(binary)
    elif target.family == "windows":
        validate_pe(binary, target.arch)
        wrappers = list(folder.glob("*.console.exe")) + list(folder.glob("*_console.exe"))
        if not wrappers:
            raise RuntimeError("Windows export did not include its console test wrapper")
        smoke(wrappers[0])
    elif target.family == "macos":
        native_macos(binary)
    elif target.family == "web":
        from test_web import smoke_web
        smoke_web(folder)
    add_notices(folder, version, target.family)
    artifacts = []
    archive = OUT / (folder.name + ".zip")
    archive_zip(folder, archive)
    artifacts.append(archive)
    if target.family == "linux":
        tar = OUT / (folder.name + ".tar.gz")
        archive_tar(folder, tar)
        artifacts.extend([tar, build_deb(target, binary, version, work),
            build_appimage(target, binary, version, work)])
        if not skip_rpm:
            artifacts.append(build_rpm(target, binary, version, work))
    elif target.family == "windows":
        standalone = OUT / (folder.name + ".exe")
        shutil.copyfile(binary, standalone)
        artifacts.append(standalone)
    elif target.family == "macos":
        disk = OUT / (folder.name + ".dmg")
        (folder / "Applications").symlink_to("/Applications", target_is_directory=True)
        run(["hdiutil", "create", "-volname", "Generala " + version,
             "-srcfolder", folder, "-ov", "-format", "UDZO", disk], timeout=180)
        run(["hdiutil", "verify", disk], timeout=90)
        artifacts.append(disk)
    return artifacts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--group", choices=GROUPS, default=host_group())
    parser.add_argument("--target", choices=TARGETS, action="append")
    parser.add_argument("--skip-rpm", action="store_true", help="Local development only; CI publishes RPMs")
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+\.\d+", args.version):
        parser.error("Version must be MAJOR.MINOR.PATCH")
    config = json.loads(Path("release-config.json").read_text())
    templates = Path(os.environ.get("GODOT_TEMPLATES", str(Path.home() / ".cache/godot-release" / config["godot_version"] / "templates")))
    OUT.mkdir(parents=True, exist_ok=True)
    run_godot(["--editor", "--import", "--quit"])
    artifacts = []
    for target_id in args.target or GROUPS[args.group]:
        artifacts.extend(build_target(TARGETS[target_id], args.version, templates, args.skip_rpm))
    manifest = {"version": args.version, "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "group": args.group, "artifacts": [{"name": p.name, "sha256": digest(p, "sha256"), "size": p.stat().st_size} for p in artifacts]}
    (OUT / ("manifest-" + args.group + ".json")).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print("Built:", ", ".join(p.name for p in artifacts))


if __name__ == "__main__":
    main()
