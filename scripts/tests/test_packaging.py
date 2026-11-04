import importlib.util
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("package_app", SCRIPTS / "package_app.py")
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PackagingTests(unittest.TestCase):
    def bundle(self, path, version, identifier="com.prism.chatclient"):
        (path / "Contents").mkdir(parents=True)
        with (path / "Contents/Info.plist").open("wb") as file:
            plistlib.dump(dict(CFBundleIdentifier=identifier, CFBundleShortVersionString=version), file)
        return path

    def test_replacement_preserves_old_bundle_without_merging(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            old = self.bundle(root / "Prism.app", "1.0.22")
            (old / "obsolete").write_text("old resource")
            incoming = self.bundle(root / "new.app", "1.0.23")
            package.install_bundle(incoming, old, root / "backups")
            self.assertFalse((old / "obsolete").exists())
            backups = list((root / "backups").glob("*.app"))
            self.assertEqual(len(backups), 1)
            self.assertEqual((backups[0] / "obsolete").read_text(), "old resource")

    def test_failed_install_restores_original_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            old = self.bundle(root / "Prism.app", "1.0.22")
            (old / "marker").write_text("original")
            incoming = self.bundle(root / "new.app", "1.0.23")
            real_move = shutil.move

            def move(source, destination):
                if Path(source).parent.name.startswith("prism-install-"):
                    raise OSError("simulated install failure")
                return real_move(source, destination)

            with patch.object(package.shutil, "move", side_effect=move):
                with self.assertRaisesRegex(OSError, "simulated"):
                    package.install_bundle(incoming, old, root / "backups")
            self.assertEqual((old / "marker").read_text(), "original")

    def test_foreign_application_is_never_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            old = self.bundle(root / "Other.app", "1", "other.bundle")
            incoming = self.bundle(root / "new.app", "1.0.23")
            with self.assertRaisesRegex(ValueError, "different application"):
                package.install_bundle(incoming, old, root / "backups")
            self.assertTrue((old / "Contents/Info.plist").is_file())
            self.assertFalse((root / "backups").exists())

    def test_missing_or_old_sdk_fails_explicitly(self):
        import build_app
        with patch.object(build_app.subprocess, "check_output", side_effect=FileNotFoundError):
            with self.assertRaisesRegex(SystemExit, "Cannot query macOS SDK"):
                build_app.selected_sdk()
        for sdk in ["15.0", "", "unknown"]:
            with patch.object(build_app.subprocess, "check_output", return_value=sdk):
                with self.assertRaisesRegex(SystemExit, "SDK 26"):
                    build_app.selected_sdk()


if __name__ == "__main__":
    unittest.main()
