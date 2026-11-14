#!/usr/bin/env python3
"""Publish a complete, checksum-verified matrix; never replace a published release."""
import argparse
import json
import os
from pathlib import Path
import subprocess

from install_godot import digest
from platforms import GROUPS


def expected_artifacts(group, version):
    names = set()
    for target in GROUPS[group]:
        prefix = f"generala-{version}-{target}"
        names.add(prefix + ".zip")
        if target.startswith("linux-"):
            architecture = "amd64" if target.endswith("x86_64") else "arm64"
            rpm_arch = "x86_64" if architecture == "amd64" else "aarch64"
            names.update([prefix + ".tar.gz", prefix + ".AppImage",
                f"generala_{version}_{architecture}.deb", f"generala-{version}-1.{rpm_arch}.rpm"])
        elif target.startswith("windows-"):
            names.add(prefix + ".exe")
        elif target.startswith("macos-"):
            names.add(prefix + ".dmg")
    return names


def verify_artifacts(folder, version, commit, groups):
    result = {}
    for group in groups:
        manifest = json.loads((folder / f"manifest-{group}.json").read_text())
        if (manifest["version"], manifest["commit"], manifest["group"]) != (version, commit, group):
            raise RuntimeError("Artifact provenance mismatch: " + group)
        names = {entry["name"] for entry in manifest["artifacts"]}
        if names != expected_artifacts(group, version):
            raise RuntimeError("Incomplete artifact set: " + group)
        for entry in manifest["artifacts"]:
            name = entry["name"]
            if Path(name).name != name or name in result:
                raise RuntimeError("Invalid or duplicate artifact name")
            file = folder / name
            if not file.is_file() or file.stat().st_size != entry["size"] or not entry["size"]:
                raise RuntimeError("Missing or truncated artifact: " + name)
            if digest(file, "sha256") != entry["sha256"]:
                raise RuntimeError("Artifact checksum mismatch: " + name)
            result[name] = entry["sha256"]
    (folder / "SHA256SUMS.txt").write_text("".join(
        f"{result[name]}  {name}\n" for name in sorted(result)), encoding="utf-8")
    return sorted(result)


def gh(*args):
    return subprocess.check_output(["gh", *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    config = json.loads(Path("release-config.json").read_text())
    folder = Path("build/releases")
    commit = os.environ.get("GITHUB_SHA") or gh("api", "repos/{owner}/{repo}/commits/main", "--jq", ".sha")
    names = verify_artifacts(folder, args.version, commit, config["build_groups"])
    print(f"Verified {len(names)} artifacts for {commit}.")
    if args.verify_only:
        return
    tag = "v" + args.version
    release = subprocess.run(["gh", "release", "view", tag, "--json", "targetCommitish,isDraft,assets"],
                             text=True, capture_output=True)
    if release.returncode == 0:
        data = json.loads(release.stdout)
        if data["targetCommitish"] != commit or gh("api", f"repos/{{owner}}/{{repo}}/commits/{tag}", "--jq", ".sha") != commit:
            raise RuntimeError("Existing release points at another commit")
        if not data["isDraft"]:
            published = {a["name"] for a in data["assets"] if a["size"] > 0}
            if published != set(names) | {"SHA256SUMS.txt"}:
                raise RuntimeError("Published release has an incomplete asset set")
            print("Release already published for this commit; preserving its artifacts.")
            return
    else:
        gh("release", "create", tag, "--target", commit, "--title", tag,
           "--notes-file", str(folder / "release-notes.md"), "--draft")
    gh("release", "upload", tag, *[str(folder / name) for name in [*names, "SHA256SUMS.txt"]], "--clobber")
    gh("release", "edit", tag, "--draft=false")
    print(gh("release", "view", tag, "--json", "url", "--jq", ".url"))


if __name__ == "__main__":
    main()
