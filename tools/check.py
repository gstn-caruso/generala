#!/usr/bin/env python3
"""Run imports and integration tests, treating Godot's logged errors as failures."""
import json
import os
import re
import subprocess
import sys
import shutil
import tempfile
from pathlib import Path


def run_godot(arguments, timeout=180):
    executable = os.environ.get("GODOT", "godot")
    result = subprocess.run([executable, "--headless", "--path", ".", *arguments], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    print(result.stdout, end="", flush=True)
    if result.returncode or re.search(r"^(?:SCRIPT )?ERROR:", result.stdout, re.MULTILINE):
        raise RuntimeError("Godot check failed: " + " ".join(arguments))


def main():
    config = json.loads(Path("release-config.json").read_text())
    # A clean copy catches missing imports while leaving an open editor and saves alone.
    project = Path.cwd()
    with tempfile.TemporaryDirectory(prefix="generala-check-") as temporary:
        workspace = Path(temporary) / "project"
        shutil.copytree(project, workspace, ignore=shutil.ignore_patterns(
            ".git", ".godot", "build", "__pycache__", ".venv", ".env", ".env.*",
            "KayKit_BoardGameBits_1.0_FREE"))
        previous_data_home = os.environ.get("XDG_DATA_HOME")
        os.environ["XDG_DATA_HOME"] = str(Path(temporary) / "user-data")
        try:
            os.chdir(workspace)
            run_godot(["--editor", "--import", "--quit"])
            for script in config["tests"]:
                run_godot(["--fixed-fps", "60", "--script", "res://" + script, "--", "--test-mode"], timeout=60)
        finally:
            os.chdir(project)
            if previous_data_home is None:
                os.environ.pop("XDG_DATA_HOME", None)
            else:
                os.environ["XDG_DATA_HOME"] = previous_data_home


if __name__ == "__main__":
    main()
