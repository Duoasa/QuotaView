"""Exercise the localization check through its normal command-line entry point."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class LocalizationScanTests(unittest.TestCase):
    def test_nested_app_source_is_checked_alongside_widget(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            checker = root / "scripts/check-localizations.py"
            checker.parent.mkdir()
            shutil.copyfile(Path(__file__).resolve().parents[1] / checker.name, checker)
            app = root / "Sources/QuotaView"
            nested = app / "Settings/Pages/Example.swift"
            nested.parent.mkdir(parents=True)
            nested.write_text('copy.text("设置", "Settings")')
            widget = root / "Sources/QuotaViewWidget/QuotaViewWidget.swift"
            widget.parent.mkdir(parents=True)
            widget.write_text('copy.text("额度", "Quota")')
            catalog = app / "Resources/AppTranslations.json"
            catalog.parent.mkdir()
            translations = {"ja": "例", "ko": "예", "es": "Ejemplo"}
            catalog.write_text(json.dumps({"Quota": translations}))

            missing = subprocess.run([sys.executable, checker], capture_output=True, text=True)
            self.assertNotEqual(missing.returncode, 0)
            self.assertIn("Settings/Pages/Example.swift:1: missing template 'Settings'", missing.stderr)

            catalog.write_text(json.dumps({"Quota": translations, "Settings": translations}))
            result = subprocess.check_output([sys.executable, checker], text=True)
            self.assertIn("2 source templates covered", result)


if __name__ == "__main__":
    unittest.main()
