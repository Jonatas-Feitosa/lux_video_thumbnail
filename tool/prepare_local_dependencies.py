"""Prepare checkout-only overrides on macOS/Linux/Windows; preserve custom files."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
packages = ['platform_interface', 'android', 'web', 'ios']
for name in packages:
    if not (root / 'packages' / f'lux_video_thumbnail_{name}' / 'pubspec.yaml').is_file():
        raise SystemExit('Requires a full source checkout; published consumers use hosted dependencies.')

overrides = {}
for directory, prefix in [(root, ''), (root / 'example', '../')]:
    overrides[directory] = 'dependency_overrides:\n' + ''.join(
        f'  lux_video_thumbnail_{name}:\n    path: {prefix}packages/lux_video_thumbnail_{name}\n'
        for name in packages)
for name in ['android', 'web', 'ios']:
    overrides[root / 'packages' / f'lux_video_thumbnail_{name}'] = (
        'dependency_overrides:\n  lux_video_thumbnail_platform_interface:\n'
        '    path: ../lux_video_thumbnail_platform_interface\n')
for directory, expected in overrides.items():
    target = directory / 'pubspec_overrides.yaml'
    if target.exists():
        existing = target.read_text(encoding='utf-8-sig').rstrip()
        before_ios = expected.split('  lux_video_thumbnail_ios:')[0].rstrip()
        if existing not in (expected.rstrip(), before_ios):
            raise SystemExit(f'Preserving custom overrides: {target}')
    target.write_text(expected, encoding='utf-8')
print('Local overrides ready. Run flutter pub get.')
