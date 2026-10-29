"""Склейка отчётов lcov и сводка в coverage_summary.py."""
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name('coverage_summary.py').resolve()


class CoverageSummaryTest(unittest.TestCase):
    def run_on(self, *reports):
        with tempfile.TemporaryDirectory() as directory:
            paths = []
            for i, body in enumerate(reports):
                path = pathlib.Path(directory) / f'{i}.info'
                path.write_text(body, encoding='utf-8')
                paths.append(str(path))
            return subprocess.run(['python3', str(SCRIPT), *paths],
                                  capture_output=True, text=True)

    def test_reports_merge_by_line(self):
        # Строка 2 не пройдена в первом прогоне, но пройдена во втором.
        first = ('SF:/ci/repo/lib/fork/a.dart\nDA:1,3\nDA:2,0\nend_of_record\n'
                 'SF:lib/main.dart\nDA:1,0\nend_of_record\n')
        second = 'SF:lib/fork/a.dart\nDA:2,1\nend_of_record\n'
        result = self.run_on(first, second)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('**66.7 %** — 2 из 3 строк в 2 файлах.', result.stdout)
        self.assertIn('| `lib/fork` | 1 | 2 | 100.0 % |', result.stdout)
        self.assertIn('| `lib` | 1 | 1 | 0.0 % |', result.stdout)

    def test_missing_or_empty_report_fails(self):
        self.assertEqual(subprocess.run(['python3', str(SCRIPT), '/нет/такого'],
                                        capture_output=True).returncode, 1)
        self.assertEqual(self.run_on('').returncode, 1)


if __name__ == '__main__':
    unittest.main()
