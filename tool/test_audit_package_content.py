"""Regression tests for exact Pub list selection; no SDK/network required."""
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import audit_package_content as audit


class PubFileListTest(unittest.TestCase):
    def setUp(self):
        (audit.ROOT / '.dart_tool').mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(dir=audit.ROOT / '.dart_tool')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'lib').mkdir()
        (self.root / 'pubspec.yaml').write_text('name: fixture')
        (self.root / 'lib/fixture.dart').write_text('// entrypoint')
        (self.root / 'lib/other.dart').write_text('// implementation')
        self.logs = self.root / 'logs'
        self.logs.mkdir()
        self.patch = patch.object(audit, 'LOGS', self.logs)
        self.patch.start()
        self.addCleanup(self.patch.stop)

    def block(self, *files):
        return 'FINE: Creating .tar.gz stream containing:\n' + ''.join(
            f'    | .\\{file}\n' for file in files)

    def select(self, log, encoding='utf-8'):
        (self.logs / 'fixture-pub-verbose.log').write_text(log, encoding=encoding)
        return audit.selected_files('fixture', self.root)

    def test_interleaved_console_uses_complete_transcript_in_both_encodings(self):
        log = self.block('pubspec.yaml') + 'MSG : dependency progress\n' + self.block(
            'pubspec.yaml', 'lib/fixture.dart', 'lib/other.dart')
        for encoding in ('utf-8', 'utf-16'):
            with self.subTest(encoding=encoding):
                self.assertEqual(self.select(log, encoding),
                                 ['lib/fixture.dart', 'lib/other.dart', 'pubspec.yaml'])

    def test_truncated_list_without_entrypoint_fails_closed(self):
        with self.assertRaisesRegex(ValueError, 'entrypoint'):
            self.select(self.block('pubspec.yaml'))

    def test_absolute_paths_inside_package_are_normalized(self):
        log = 'FINE: Creating .tar.gz stream containing:\n' + ''.join(
            f'    | {self.root / file}\n'
            for file in ('pubspec.yaml', 'lib/fixture.dart', 'lib/other.dart')
        )
        self.assertEqual(
            self.select(log),
            ['lib/fixture.dart', 'lib/other.dart', 'pubspec.yaml'],
        )

    def test_inconsistent_lists_fail_closed(self):
        log = self.block('pubspec.yaml', 'lib/fixture.dart') + 'MSG : pause\n' + self.block(
            'pubspec.yaml', 'lib/other.dart')
        with self.assertRaisesRegex(ValueError, 'inconsistent'):
            self.select(log)

    def test_archive_traversal_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'unsafe'):
            self.select(self.block('../private'))


if __name__ == '__main__':
    unittest.main()
