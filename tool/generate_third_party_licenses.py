#!/usr/bin/env python3
"""Collect resolved Dart/Flutter package license files without copying media."""
import json
import re
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / '.dart_tool/package_config.json'


def main():
    packages = json.loads(CONFIG.read_text())['packages']
    sections = [
        'CLOUDIO THIRD-PARTY LICENSE INVENTORY\n'
        'Generated from the resolved Dart/Flutter package configuration.\n'
        'Includes development dependencies; not a media or service license.\n'
        'Original vendored/font notices are also retained in their source locations.\n'
    ]
    missing = []
    for package in sorted(packages, key=lambda item: item['name']):
        if package['name'] == 'cloudio_mobile':
            continue
        uri = urlparse(package['rootUri'])
        directory = (Path(unquote(uri.path)) if uri.scheme == 'file'
                     else (CONFIG.parent / unquote(package['rootUri'])).resolve())
        files = sorted(path for path in directory.iterdir()
                       if path.is_file() and
                       (path.name.upper().startswith(('LICENSE', 'COPYING'))
                        or path.name.upper() == 'NOTICE'))
        if not files and package['name'] in {'flutter_test', 'flutter_web_plugins'}:
            sdk_license = directory.parent.parent / 'LICENSE'
            if sdk_license.is_file():
                files = [sdk_license]
        if not files:
            missing.append(package['name'])
            continue
        pubspec = directory / 'pubspec.yaml'
        match = re.search(r'^version:\s*(.+)$', pubspec.read_text(), re.M) if pubspec.exists() else None
        version = match.group(1).strip() if match else 'SDK package'
        sections.append(f'\n{"=" * 72}\n{package["name"]} ({version})\n'
                        f'https://pub.dev/packages/{package["name"]}\n')
        for path in files:
            sections.append(f'\n--- {path.name} ---\n{path.read_text(errors="replace").strip()}\n')
    for name in ['assets/fonts/OFL.txt', 'lib/services/fingerprint/LICENSE']:
        sections.append(f'\n{"=" * 72}\nBundled material: {name}\n\n'
                        f'{(ROOT / name).read_text().strip()}\n')
    if missing:
        sections.append('\nNo package-root license file found (consult upstream / SDK notices):\n'
                        + '\n'.join(missing) + '\n')
    output = ROOT / 'THIRD_PARTY_LICENSES.txt'
    output.write_text('\n'.join(sections))
    print(f'Wrote {output.name}: {output.stat().st_size} bytes; '
          f'{len(packages) - 1} dependency entries inspected; missing: {missing}')


if __name__ == '__main__':
    main()
