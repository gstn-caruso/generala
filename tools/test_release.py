import unittest
import json
from pathlib import Path
import subprocess
import sys
import tempfile
from release import HEADER, change_type, next_version


class ReleasePolicyTests(unittest.TestCase):
    def test_initial_release_and_non_product_changes(self):
        self.assertEqual(next_version("", ["feat: initial game"]), "0.1.0")
        self.assertEqual(next_version("v0.1.0", ["docs: clarify controls", "ci: update runner"]), "")

    def test_semver_increments(self):
        self.assertEqual(next_version("v0.1.0", ["fix(menu): restore focus"]), "0.1.1")
        self.assertEqual(next_version("v0.1.1", ["fix: correct names", "feat: add combat"]), "0.2.0")
        self.assertEqual(next_version("v0.2.0", ["feat(save)!: replace save format"]), "1.0.0")
        self.assertEqual(next_version("v2.3.4", ["refactor: replace storage\n\nBREAKING CHANGE: old saves need conversion"]), "3.0.0")
        self.assertEqual(next_version("v1.2.3", ["perf: reduce allocations"]), "1.2.4")

    def test_headers_and_scopes(self):
        self.assertIsNotNone(HEADER.fullmatch("feat(character-creation): add a class"))
        self.assertIsNone(HEADER.fullmatch("add a menu"))
        self.assertIsNone(HEADER.fullmatch("feat: title\nfix: body"))
        self.assertIsNone(change_type("Merge pull request #1 from feature/menu"))
        self.assertEqual(change_type("fix!: change controls"), "major")


class ReleaseRepositoryTests(unittest.TestCase):
    """Exercise real tags/history, including retrying an interrupted draft."""

    def test_initial_retry_docs_and_subsequent_changes(self):
        script = Path(__file__).with_name("release.py").resolve()
        with tempfile.TemporaryDirectory(prefix="generala-release-policy-") as directory:
            root = Path(directory)
            (root / "release-config.json").write_text(json.dumps({
                "title": "Generala", "initial_version": "0.1.0", "summary": "Test"}))

            def git(*arguments):
                return subprocess.run(["git", "-c", "commit.gpgsign=false", "-c",
                    "user.name=Release Test", "-c", "user.email=test@example.invalid",
                    *arguments], cwd=root, check=True, capture_output=True, text=True)

            def plan():
                output = root / "output.txt"
                output.unlink(missing_ok=True)
                subprocess.run([sys.executable, str(script), "plan", "--github-output",
                    str(output)], cwd=root, check=True, capture_output=True, text=True)
                return dict(line.split("=", 1) for line in output.read_text().splitlines())

            git("init", "-b", "main")
            git("commit", "--allow-empty", "-m", "feat: initial game")
            self.assertEqual(plan(), {"version": "0.1.0", "build_version": "0.1.0"})
            git("tag", "v0.1.0")
            self.assertEqual(plan()["version"], "0.1.0")
            git("commit", "--allow-empty", "-m", "docs: clarify controls")
            self.assertEqual(plan(), {"version": "", "build_version": "0.1.0"})
            git("commit", "--allow-empty", "-m", "fix: preserve held dice")
            self.assertEqual(plan()["version"], "0.1.1")
            git("tag", "v0.1.1")
            git("tag", "unrelated-test-tag")
            git("commit", "--allow-empty", "-m", "feat: add local players")
            self.assertEqual(plan()["version"], "0.2.0")
            git("commit", "--allow-empty", "-m", "refactor!: replace the save format")
            self.assertEqual(plan()["version"], "1.0.0")


if __name__ == "__main__":
    unittest.main()
