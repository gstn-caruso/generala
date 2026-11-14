import hashlib
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from build_release import archive_tar, archive_zip, validate_pe
from platforms import GROUPS, TARGETS, template_names
from publish_release import expected_artifacts, verify_artifacts


class PackageTests(unittest.TestCase):
    def test_pe_architecture_is_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory) / "game.exe"
            for arch, machine in [("x86_64", 0x8664), ("x86_32", 0x14c), ("arm64", 0xaa64)]:
                data = bytearray(0x100)
                data[:2] = b"MZ"
                data[0x3c:0x40] = (0x80).to_bytes(4, "little")
                data[0x80:0x84] = b"PE\0\0"
                data[0x84:0x86] = machine.to_bytes(2, "little")
                file.write_bytes(data)
                validate_pe(file, arch)
                with self.assertRaisesRegex(RuntimeError, "architecture"):
                    validate_pe(file, "arm64" if arch != "arm64" else "x86_32")
            file.write_bytes(b"not an executable")
            with self.assertRaises(RuntimeError):
                validate_pe(file, "x86_64")

    def test_archives_preserve_modes_and_are_repeatable(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, {"SOURCE_DATE_EPOCH": "1700000000"}):
            root = Path(directory)
            folder = root / "game"
            folder.mkdir()
            binary = folder / "generala"
            binary.write_bytes(b"sample executable")
            binary.chmod(0o755)
            (folder / "LICENSE").write_text("license")
            (folder / "link").symlink_to("generala")
            first, second = root / "a.zip", root / "b.zip"
            archive_zip(folder, first)
            archive_zip(folder, second)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            with zipfile.ZipFile(first) as archive:
                self.assertEqual(archive.getinfo("game/generala").external_attr >> 16, stat.S_IFREG | 0o755)
                self.assertTrue(stat.S_ISLNK(archive.getinfo("game/link").external_attr >> 16))
                self.assertEqual(archive.read("game/link"), b"generala")
            archive_tar(folder, root / "a.tar.gz")
            archive_tar(folder, root / "b.tar.gz")
            self.assertEqual((root / "a.tar.gz").read_bytes(), (root / "b.tar.gz").read_bytes())

    def test_all_targets_have_their_required_templates(self):
        self.assertEqual({t for group in GROUPS.values() for t in group}, set(TARGETS))
        names = template_names("windows-x86_64")
        self.assertIn("windows_release_x86_32_console.exe", names)
        self.assertIn("windows_release_x86_64_console.exe", names)

    def test_publish_requires_all_packages_and_valid_checksums(self):
        version, commit = "0.3.0", "a" * 40
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for group in GROUPS:
                entries = []
                for name in expected_artifacts(group, version):
                    data = name.encode()
                    (root / name).write_bytes(data)
                    entries.append({"name": name, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)})
                manifest = {"version": version, "commit": commit, "group": group, "artifacts": entries}
                (root / ("manifest-" + group + ".json")).write_text(json.dumps(manifest))
            names = verify_artifacts(root, version, commit, GROUPS)
            self.assertEqual(len(names), 19)
            self.assertEqual(len((root / "SHA256SUMS.txt").read_text().splitlines()), 19)
            file = root / names[0]
            file.write_bytes(b"tampered")
            with self.assertRaises(RuntimeError):
                verify_artifacts(root, version, commit, GROUPS)
            with self.assertRaisesRegex(RuntimeError, "provenance"):
                verify_artifacts(root, version, "b" * 40, GROUPS)


if __name__ == "__main__":
    unittest.main()
