"""Review Pub's exact verbose file lists without printing potential secrets.

Usage: python tool/audit_package_content.py
In a full source checkout, first run tool/check_publication.ps1. It executes
`dart pub --verbose publish --dry-run` serially and copies each complete Pub
cache transcript to .dart_tool/publication/content/<package>-pub-verbose.log.
Do not substitute interleaved console output for a complete transcript. Logs
may report release blockers: this reviews content, not readiness to publish.
"""
from __future__ import annotations

import hashlib
import json
import re
import shutil
from urllib.parse import unquote, urlsplit
from datetime import datetime
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent.parent
LOGS = ROOT / '.dart_tool/publication/content'
PACKAGES = {
    'lux_video_thumbnail': ROOT,
    **{f'lux_video_thumbnail_{name}': ROOT / 'packages' / f'lux_video_thumbnail_{name}'
       for name in ('platform_interface', 'android', 'web')},
}
RULES = {
    'private-key': rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----',
    'aws-access-key': rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b',
    'github-token': rb'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})',
    'google-api-key': rb'\bAIza[A-Za-z0-9_-]{35}\b',
    'live-service-token': rb'\b(?:sk_live_|sk-proj-)[A-Za-z0-9_-]{24,}',
    'slack-token': rb'\bxox[baprs]-[A-Za-z0-9-]{20,}',
    'credential-url': rb'https?://[^\s/\x27\x22:@]+:[^\s/\x27\x22@]+@',
    'assigned-secret': rb'(?i)(?:api[_-]?key|client[_-]?secret|password|access[_-]?token)\s*[:=]\s*[\x27\x22][A-Za-z0-9_+/=-]{20,}[\x27\x22]',
    'user-home-path': rb'(?i)(?:[a-z]:[\\/]+Users[\\/]+[^\s\\/\x22\x27]+|/(?:Users|home)/[a-z0-9_.-]+)',
    'workspace-path': rb'(?i)[a-z]:[\\/]+Dev[\\/]+lux_video_thumbnail',
}
FORBIDDEN_PARTS = {'build', '.dart_tool', '.gradle', '.idea', '.vscode', '.kilo',
                   '.codex', '.agents', 'coverage', 'node_modules', 'Pods'}
FORBIDDEN_FILES = {'pubspec_overrides.yaml', 'pubspec.lock', 'local.properties',
                   'key.properties', 'google-services.json', 'GoogleService-Info.plist',
                   'Generated.xcconfig', 'flutter_export_environment.sh'}
FORBIDDEN_SUFFIXES = {'.jks', '.keystore', '.pem', '.key', '.p12', '.pfx', '.log',
                      '.apk', '.aab', '.aar', '.class', '.iml', '.dill'}
FEDERATED_PACKAGE_PREFIXES = {
    'packages/lux_video_thumbnail_android/',
    'packages/lux_video_thumbnail_platform_interface/',
    'packages/lux_video_thumbnail_web/',
}


def selected_files(name: str, source: Path) -> list[str]:
    # Match the authoritative list used to construct Pub's tar stream, not its
    # display tree (which also includes empty directories and rounded sizes).
    raw = (LOGS / f'{name}-pub-verbose.log').read_bytes()
    text = raw.decode('utf-16' if raw.startswith((b'\xff\xfe', b'\xfe\xff')) else 'utf-8-sig')
    text = text.replace('\r\n', '\n')
    marker = 'FINE: Creating .tar.gz stream containing:\n'
    if marker not in text:
        raise ValueError(f'{name}: missing verbose tar list')
    # Pub's asynchronous console records can interrupt this block. A failed
    # dry-run also appends its full log transcript with the uninterrupted record.
    # Never silently accept the first, potentially truncated console block.
    candidates = []
    source_root = source.resolve()
    for block in text.split(marker)[1:]:
        entries = set()
        for line in block.splitlines():
            if not line.startswith('    | '):
                break
            listed = line[6:]
            listed_path = Path(listed)
            if listed_path.is_absolute():
                candidate = listed_path.resolve()
                if not candidate.is_relative_to(source_root):
                    raise ValueError(f'{name}: redirected archive entry')
                relative = candidate.relative_to(source_root).as_posix()
            else:
                relative = listed.replace('\\', '/')
                while relative.startswith('./'):
                    relative = relative[2:]
                path = PurePosixPath(relative)
                if '..' in path.parts or path.is_absolute() or ':' in relative:
                    raise ValueError(f'{name}: unsafe archive path')
                candidate = source_root / path
            path = PurePosixPath(relative)
            if '..' in path.parts or path.is_absolute() or ':' in relative:
                raise ValueError(f'{name}: unsafe archive path')
            if not candidate.resolve().is_relative_to(source_root):
                raise ValueError(f'{name}: redirected archive entry')
            if candidate.is_file():
                entries.add(path.as_posix())
        candidates.append(entries)
    entries = max(candidates, key=len)
    if any(not candidate.issubset(entries) for candidate in candidates):
        raise ValueError(f'{name}: inconsistent or incomplete verbose tar lists')
    if 'pubspec.yaml' not in entries:
        raise ValueError(f'{name}: no manifest in archive')
    if f'lib/{name}.dart' not in entries:
        raise ValueError(f'{name}: missing package entrypoint; tar list may be incomplete')
    return sorted(set(entries))


def main() -> None:
    reviewed = LOGS / ('reviewed-' + datetime.now().strftime('%Y%m%dT%H%M%S%f'))
    reviewed.mkdir(parents=True, exist_ok=False)
    report = {'reviewed_directory': str(reviewed.relative_to(ROOT)), 'packages': {}}
    for name, source in PACKAGES.items():
        files = selected_files(name, source)
        file_set = {(source / relative).resolve() for relative in files}
        findings = []
        hashes = {}
        byte_count = 0
        for relative in files:
            path = PurePosixPath(relative)
            if (FORBIDDEN_PARTS.intersection(path.parts) or path.name in FORBIDDEN_FILES
                    or path.suffix in FORBIDDEN_SUFFIXES or any(p.startswith('.') for p in path.parts)):
                findings.append({'file': relative, 'rule': 'excluded-state-or-credentials'})
            # The source repository is a federated plugin. Its public
            # implementation packages are deliberately included in the root
            # archive so Pub can publish nested packages from the same checkout.
            # Other duplicate platform directories remain release blockers.
            expected_federated_source = any(
                relative.startswith(prefix) for prefix in FEDERATED_PACKAGE_PREFIXES
            )
            if (name == 'lux_video_thumbnail'
                    and path.parts[0] in {'android', 'ios'}
                    and not expected_federated_source):
                findings.append({'file': relative, 'rule': 'duplicate-or-legacy-platform'})
            data = (source / relative).read_bytes()
            if path.suffix == '.md':
                for link in re.findall(r'\[[^\]]*\]\(([^)]+)\)', data.decode('utf-8-sig')):
                    target = urlsplit(link.strip('<>'))
                    if target.scheme or target.netloc or not target.path:
                        continue
                    linked_file = (source / path.parent / unquote(target.path)).resolve()
                    if linked_file not in file_set:
                        findings.append({'file': relative, 'rule': 'missing-packaged-link',
                                         'target': target.path})
            byte_count += len(data)
            hashes[relative] = hashlib.sha256(data).hexdigest()
            for rule, pattern in RULES.items():
                for match in re.finditer(pattern, data):
                    # Only report location/rule, never the matched credential.
                    findings.append({'file': relative, 'rule': rule,
                                     'line': data[:match.start()].count(b'\n') + 1})
            destination = reviewed / name / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / relative, destination)
        report['packages'][name] = {
            'files': files, 'sha256': hashes, 'uncompressed_bytes': byte_count,
            'findings': findings,
        }
        print(f'{name}: {len(files)} files, {byte_count} source bytes, {len(findings)} findings')
    (LOGS / 'content-review.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('Report saved under .dart_tool/publication/content/content-review.json')
    if any(p['findings'] for p in report['packages'].values()):
        raise SystemExit(1)


if __name__ == '__main__':
    main()
