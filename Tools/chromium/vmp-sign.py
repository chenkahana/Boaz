#!/usr/bin/env python3
"""Widevine VMP-sign an assembled Boaz.app before Apple code signing.

Widevine verifies the Chromium framework executable against Resources/<framework>.sig (see
chrome/common/media/cdm_host_file_path.cc). The signature comes from Google's signature_generator.py and the
credential Google issues with Widevine partner access; neither is in this repository.

BOAZ_WIDEVINE_VMP_CERT unset: skip. Set: BOAZ_WIDEVINE_VMP_TOOL must name Google's signature_generator.py,
and any failure stops the release.
"""
import argparse
import os
import pathlib
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('app', type=pathlib.Path)
    app = parser.parse_args().app
    if not os.environ.get('BOAZ_WIDEVINE_VMP_CERT'):
        print('Widevine VMP signing skipped (no certificate)')
        return
    tool = pathlib.Path(os.environ.get('BOAZ_WIDEVINE_VMP_TOOL', ''))
    if not tool.is_file():
        sys.exit('BOAZ_WIDEVINE_VMP_TOOL must name Google\'s signature_generator.py')
    frameworks = sorted((app / 'Contents/Frameworks').glob('* Framework.framework'))
    if len(frameworks) != 1:
        sys.exit(f'Expected one Chromium framework in {app}, found {len(frameworks)}')
    current = (frameworks[0] / 'Versions/Current').resolve()
    executable = current / frameworks[0].stem
    signature = current / 'Resources' / (frameworks[0].stem + '.sig')
    if not executable.is_file():
        sys.exit(f'Missing framework executable: {executable}')
    signature.unlink(missing_ok=True)
    # flags=1 marks the main host binary, as chrome/BUILD.gn's sign_chrome_framework_for_widevine does.
    subprocess.run([sys.executable, '-I', str(tool), '--input_file', str(executable),
                    '--output_file', str(signature), '--flags', '1'], check=True)
    if not signature.is_file() or signature.stat().st_size == 0:
        sys.exit(f'Widevine VMP signing produced no signature: {signature}')
    print(f'Widevine VMP signature written: {signature}')


if __name__ == '__main__':
    main()
