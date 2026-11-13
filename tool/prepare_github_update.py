"""Generate release metadata from signed APKs, never from guessed version codes."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apks', nargs='+', type=Path)
    parser.add_argument('--aapt', required=True, help='Path to Android SDK aapt')
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    manifest = None
    for apk in args.apks:
        badging = subprocess.check_output([args.aapt, 'dump', 'badging', str(apk)], text=True, encoding='utf-8')
        package = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging)
        if not package:
            raise ValueError('Could not read APK package metadata')
        name, code, version = package.groups()
        if name != 'com.mosaicvideo.mosaic' or not re.fullmatch(r'\d+\.\d+\.\d+', version):
            raise ValueError('Only production Mosaic APKs with stable versions can be published')
        if manifest is None:
            manifest = {'schema': 1, 'packageName': name, 'version': version, 'apks': []}
        if manifest['version'] != version:
            raise ValueError('All APKs must have the same version name')
        abi_line = re.search(r'^native-code: (.+)$', badging, re.M)
        abis = re.findall(r"'([^']+)'", abi_line[1]) if abi_line else []
        abi = abis[0] if len(abis) == 1 else 'universal'
        if any(item['abi'] == abi for item in manifest['apks']):
            raise ValueError('Duplicate ABI')
        digest = hashlib.sha256()
        with apk.open('rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(chunk)
        manifest['apks'].append({'abi': abi, 'asset': apk.name, 'size': apk.stat().st_size,
                                 'sha256': digest.hexdigest(), 'versionCode': int(code)})
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(f'Prepared {args.out.name}: {manifest["version"]}, {len(manifest["apks"])} APK(s)')


if __name__ == '__main__':
    main()
