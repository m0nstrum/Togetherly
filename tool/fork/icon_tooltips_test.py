"""Exercise the guard against false positives from nested calls and literals."""
import pathlib
import subprocess
import tempfile
import unittest

GUARD = pathlib.Path(__file__).with_name('icon_tooltips.py').resolve()


class TooltipsTest(unittest.TestCase):
    def check(self, source, missing):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            (root / 'lib').mkdir()
            (root / 'lib' / 'sample.dart').write_text(source)
            result = subprocess.run(['python3', str(GUARD)], cwd=root,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, int(missing), result.stdout)
            self.assertEqual(result.stdout.count('needs tooltip'), missing)

    def test_all_constructors(self):
        self.check("IconButton(tooltip: label, icon: Icon(x));"
                   "IconButton.filled(tooltip: label);"
                   "IconButton.filledTonal(tooltip: label);"
                   "IconButton.outlined(tooltip: label);", 0)

    def test_comments_strings_and_nested_tooltips_do_not_count(self):
        self.check("IconButton(/* tooltip: */ icon: Foo(tooltip: 'tooltip:'),"
                   "onPressed: () { print('tooltip:'); });", 1)

    def test_nested_buttons_each_need_a_tooltip(self):
        self.check("IconButton(tooltip: label, icon: IconButton(icon: Icon(x)))", 1)


if __name__ == '__main__':
    unittest.main()
