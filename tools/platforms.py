"""Supported release targets, independent of display language."""
from dataclasses import dataclass
import platform
import sys


@dataclass(frozen=True)
class Target:
    id: str
    family: str
    arch: str
    preset: str
    template: str


TARGETS = {t.id: t for t in [
    Target("linux-x86_64", "linux", "x86_64", "Linux x64", "linux_release.x86_64"),
    Target("linux-arm64", "linux", "arm64", "Linux ARM64", "linux_release.arm64"),
    Target("windows-x86_64", "windows", "x86_64", "Windows x64", "windows_release_x86_64.exe"),
    Target("windows-x86_32", "windows", "x86_32", "Windows x86", "windows_release_x86_32.exe"),
    Target("windows-arm64", "windows", "arm64", "Windows ARM64", "windows_release_arm64.exe"),
    Target("macos-universal", "macos", "universal", "macOS Universal", "macos.zip"),
    Target("web", "web", "wasm32", "Web", "web_nothreads_release.zip"),
]}

GROUPS = {
    "linux-x86_64": ["linux-x86_64", "web"],
    "linux-arm64": ["linux-arm64"],
    "windows-x86_64": ["windows-x86_64", "windows-x86_32"],
    "windows-arm64": ["windows-arm64"],
    "macos": ["macos-universal"],
}


def host_group():
    arm = platform.machine().lower() in ("arm64", "aarch64")
    if sys.platform == "darwin":
        return "macos"
    if sys.platform == "win32":
        return "windows-arm64" if arm else "windows-x86_64"
    return "linux-arm64" if arm else "linux-x86_64"


def template_names(group):
    names = []
    for target_id in GROUPS[group]:
        target = TARGETS[target_id]
        names.append(target.template)
        if target.family == "windows":
            names.append(target.template.replace(".exe", "_console.exe"))
    return names
