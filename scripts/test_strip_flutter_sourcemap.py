import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / 'strip_flutter_sourcemap.py'


class StripFlutterSourceMap(unittest.TestCase):
    def test_removes_only_loader_map_reference(self):
        with tempfile.TemporaryDirectory() as directory:
            loader = Path(directory) / 'flutter.js'
            loader.write_text('loader();\n//# sourceMappingURL=flutter.js.map\n')
            subprocess.run([sys.executable, str(SCRIPT), str(loader)], check=True)
            self.assertEqual(loader.read_text(), 'loader();\n')

    def test_missing_loader_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run([sys.executable, str(SCRIPT), str(Path(directory) / 'missing')], capture_output=True)
            self.assertNotEqual(result.returncode, 0)
