#!/usr/bin/env python3
"""Install the pinned, SDK-free Dylix toolchain. No external scripts are run."""
import argparse, hashlib, json, pathlib, shutil, tarfile, tempfile, urllib.request
ROOT = pathlib.Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--archive', type=pathlib.Path, help='Use a previously downloaded release asset')
args = p.parse_args()
lock = json.loads((ROOT / 'dependencies.lock.json').read_text())
asset = lock['asset']
with tempfile.TemporaryDirectory(prefix='dylix-toolchain-') as tmp:
    tmp = pathlib.Path(tmp)
    archive = args.archive or tmp / 'toolchain.tar.gz'
    if args.archive is None:
        print('Downloading:', asset['url'])
        with urllib.request.urlopen(asset['url'], timeout=120) as response, archive.open('wb') as out:
            shutil.copyfileobj(response, out)
    digest = hashlib.sha256()
    with archive.open('rb') as data:
        for chunk in iter(lambda: data.read(1024 * 1024), b''):
            digest.update(chunk)
    if digest.hexdigest() != asset['sha256']:
        raise SystemExit('Toolchain SHA-256 mismatch; nothing installed')
    stage = tmp / 'unpacked'
    with tarfile.open(archive, 'r:gz') as tar:
        for member in tar.getmembers():
            path = pathlib.PurePosixPath(member.name)
            if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] not in {'Vendor', 'LICENSES'} or not (member.isdir() or member.isfile()):
                raise SystemExit('Unexpected archive entry: ' + member.name)
        tar.extractall(stage)
    for relative, expected in lock['files'].items():
        path = stage / relative
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise SystemExit('Extracted dependency failed validation: ' + relative)
    dest = ROOT / 'Vendor'
    dest.mkdir(exist_ok=True)
    for framework in sorted((stage / 'Vendor').glob('*.xcframework')):
        target = dest / framework.name
        if target.exists():
            expected = {k: v for k, v in lock['files'].items() if k.startswith('Vendor/' + framework.name + '/')}
            if not all((ROOT / k).is_file() and hashlib.sha256((ROOT / k).read_bytes()).hexdigest() == v for k, v in expected.items()):
                raise SystemExit('Existing dependency differs; move it aside before retrying: ' + str(target))
            print('Verified existing:', framework.name)
        else:
            shutil.move(str(framework), str(target))
            print('Installed:', framework.name)
print('Done. Provide Apple SDK paths separately; see docs/BUILDING.md.')
