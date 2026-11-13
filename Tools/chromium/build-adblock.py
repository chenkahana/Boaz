#!/opt/homebrew/bin/python3.12
"""Build the pinned content-blocking C ABI library inside the guarded SSD image."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import uuid


def vendor_source(stage, root):
    manifest = json.loads((stage / 'patches.lock.json').read_text())
    revision = manifest['revision']
    if len(revision) != 40 or any(c not in '0123456789abcdef' for c in revision):
        raise RuntimeError('Invalid pinned blocking source revision.')
    upstream = root / 'adblock/upstream.git'
    if upstream.resolve() != upstream:
        raise RuntimeError('Blocking source cache is redirected.')
    if not upstream.exists():
        subprocess.run(['git', 'init', '--bare', str(upstream)], check=True)
    if subprocess.check_output(['git', '-C', str(upstream), 'rev-parse', '--is-bare-repository'], text=True).strip() != 'true':
        raise RuntimeError('Expected dedicated bare blocking source cache.')
    present = subprocess.run(['git', '-C', str(upstream), 'cat-file', '-e', revision + '^{commit}'],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if present.returncode:
        subprocess.run(['git', '-C', str(upstream), 'fetch', '--depth=1',
                        manifest['repository'], revision], check=True)
    archive = stage.parent / 'upstream.tar'
    with archive.open('xb') as stream:
        subprocess.run(['git', '-C', str(upstream), 'archive', '--format=tar', revision],
                       stdout=stream, check=True)
    destination = stage / 'vendor/adblock'
    destination.mkdir(parents=True)
    with tarfile.open(archive) as source:
        source.extractall(destination, filter='data')
    for patch in manifest['patches']:
        patch_path = stage / patch['file']
        if hashlib.sha256(patch_path.read_bytes()).hexdigest() != patch['sha256']:
            raise RuntimeError('Blocking patch checksum changed.')
        for entry in patch['files']:
            path = destination / entry['path']
            if path.resolve() != path or not path.is_relative_to(destination):
                raise RuntimeError('Blocking patch path is redirected.')
            if hashlib.sha256(path.read_bytes()).hexdigest() != entry['before']:
                raise RuntimeError('Blocking patch preimage changed: ' + entry['path'])
        subprocess.run(['git', 'apply', '--check', str(patch_path)], cwd=destination, check=True)
        subprocess.run(['git', 'apply', str(patch_path)], cwd=destination, check=True)
        for entry in patch['files']:
            if hashlib.sha256((destination / entry['path']).read_bytes()).hexdigest() != entry['after']:
                raise RuntimeError('Blocking patch postimage changed: ' + entry['path'])
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--resolve-lock', action='store_true',
                        help='Resolve dependencies in a preserved staging directory without compiling.')
    parser.add_argument('--jobs', type=int, default=2, choices=range(1, 5))
    parser.add_argument('--guarded', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    scripts = Path(__file__).resolve().parent
    lock = json.loads((scripts / 'source.lock.json').read_text())
    root = Path(lock['storage_root'])
    if not args.guarded:
        command = [lock['python'], str(scripts.parent / 'cef/run-build.py'), '--',
                   lock['python'], str(Path(__file__).resolve()), '--guarded',
                   '--jobs', str(args.jobs)]
        if args.resolve_lock:
            command.append('--resolve-lock')
        return subprocess.call(command)
    if Path.cwd() != root.parent or os.environ.get('TMPDIR') != str(root.parent / 'tmp'):
        raise RuntimeError('The verified SSD build guard is required.')
    with (root.parent / '.build.lock').open('r') as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            pass
        else:
            raise RuntimeError('Build guard lock is not held.')
    crate = scripts / 'adblock'
    toolchain = root / 'chromium/src/third_party/rust-toolchain/bin'
    for path in (root, crate, toolchain):
        if path.resolve() != path:
            raise RuntimeError(f'Redirected build path: {path}')
    for name in ('cargo', 'rustc', 'rustdoc'):
        if not (toolchain / name).is_file():
            raise RuntimeError(f'Pinned toolchain is missing {name}.')
    if not (crate / 'Cargo.toml').is_file():
        raise RuntimeError('Content-blocking crate is not integrated.')
    if not args.resolve_lock and not (crate / 'Cargo.lock').is_file():
        raise RuntimeError('Resolve and review Cargo.lock before building.')
    run = root / 'adblock' / uuid.uuid4().hex
    run.mkdir(parents=True)
    stage = run / 'source'
    shutil.copytree(crate, stage)
    vendor_source(stage, root)
    inputs = {str(p.relative_to(stage)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted(stage.rglob('*')) if p.is_file()}
    env = dict(os.environ, CARGO_HOME=str(root / 'cache/cargo'),
               CARGO_TARGET_DIR=str(root / 'adblock/target'),
               RUSTC=str(toolchain / 'rustc'), RUSTDOC=str(toolchain / 'rustdoc'),
               RUSTFLAGS='-C link-arg=-Wl,-install_name,@loader_path/../../../libboaz_adblock.dylib')
    command = [str(toolchain / 'cargo')]
    command += ['generate-lockfile'] if args.resolve_lock else [
        'build', '--locked', '--release', '--target', 'aarch64-apple-darwin',
        '--jobs', str(args.jobs)]
    receipt = {'inputs': inputs, 'command': command, 'source': str(stage),
               'toolchain_lock_sha256': hashlib.sha256(
                   (scripts / 'toolchains.lock.json').read_bytes()).hexdigest(),
               'header_sha256': hashlib.sha256((scripts / 'host/boaz_adblock.h').read_bytes()).hexdigest(),
               'rustc': subprocess.check_output([str(toolchain / 'rustc'), '-Vv'], text=True)}
    print(f'Content-blocking run: {run}', flush=True)
    result = subprocess.run(command, cwd=stage, env=env)
    receipt['exit_code'] = result.returncode
    if result.returncode == 0 and args.resolve_lock:
        receipt['resolved_lock'] = str(stage / 'Cargo.lock')
        print(f'Review and integrate resolved lock: {stage / "Cargo.lock"}', flush=True)
    elif result.returncode == 0:
        library = Path(env['CARGO_TARGET_DIR']) / 'aarch64-apple-darwin/release/libboaz_adblock.dylib'
        shutil.copy2(library, run / library.name)
        receipt['library_sha256'] = hashlib.sha256(library.read_bytes()).hexdigest()
        receipt['library'] = str(run / library.name)
    encoded = json.dumps(receipt, indent=2) + '\n'
    (run / 'receipt.json').write_text(encoded)
    if result.returncode == 0 and not args.resolve_lock:
        temporary = run / 'published-receipt.json'
        temporary.write_text(encoded)
        temporary.replace(root / 'adblock-built.json')
    return result.returncode


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f'Content-blocking build stopped: {error}', file=sys.stderr)
        sys.exit(1)
