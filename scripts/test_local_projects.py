#!/usr/bin/env python3
"""Compile copies of local Theos projects inside the iOS simulator app.

Raw runs preserve source/configuration. Adapted runs explicitly preprocess Logos
on macOS because the simulator toolchain has no Perl slice. No project Makefile
or install scripts are executed, and original projects are never modified.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
BUNDLE = 'com.xuegao.theosmobilecompiler'
SKIP = {'.git', '.theos', 'build', 'packages', 'Packages', 'Package', 'Payload',
        'node_modules', 'DerivedData', '__MACOSX', 'retdec', 'retdec-build'}


def command(args, **kwargs):
    return subprocess.run(args, text=True, capture_output=True, **kwargs)


def sim(*args):
    result = command(['xcrun', 'simctl', *args])
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result.stdout.strip()


def copy_sources(source, dest):
    manifest = []
    for directory, directories, files in os.walk(source):
        directories[:] = [n for n in directories if n not in SKIP and
                          not n.endswith(('.app', '.framework', '.bundle', '.xcframework'))]
        for name in files:
            p = Path(directory) / name
            if p.is_symlink() or p.suffix.lower() in {'.ipa', '.deb', '.zip', '.dylib', '.a', '.o', '.png', '.jpg', '.mp4'}:
                continue
            relative = p.relative_to(source)
            target = dest / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, target)
            if p.suffix in {'.m', '.mm', '.xm', '.x', '.c', '.cpp', '.h'}:
                manifest.append({'path': str(relative), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()})
    return manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--prepare-cli', default='/private/tmp/tmc-archive-import-tests')
    parser.add_argument('--timeout', type=int, default=240)
    parser.add_argument('--adapted-only', action='store_true')
    parser.add_argument('--projects', nargs='*')
    parser.add_argument('--fixture', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    evidence = args.output or ROOT / 'evidence/local-theos-simulator-20261027'
    evidence.mkdir(parents=True, exist_ok=True)
    sim('install', 'booted', str(ROOT / 'build/simulator/TheosMobileCompiler.app'))
    container = Path(sim('get_app_container', 'booted', BUNDLE, 'data'))
    documents = container / 'Documents'
    documents.mkdir(exist_ok=True)
    cases = [
        ('kook', 'kook'),
        ('AutoMessagePlugin', 'AutoMessagePlugin'),
        ('WCElite', '\u5fae\u4fe1\u4f18\u5316 2/wcyh/wcyh'),
        ('xncj', '\u865a\u62df\u63d2\u4ef6/xncj/xncj'),
        ('xiangqing', 'xiangqing/xiangqing'),
        ('FLEX-original', 'FLEX'),
    ]
    results = []

    def run_case(name, source, adapted=False, flex_baseline=False):
        label = name + ('-host-logos' if adapted else '-raw')
        if flex_baseline:
            label = 'FLEX-existing-mobile-config'
        out = evidence / label
        out.mkdir(exist_ok=True)
        dest = documents / ('LocalTest-' + label)
        if dest.exists():
            shutil.rmtree(dest)
        dest.mkdir()
        manifest = copy_sources(source, dest)
        (out / 'source-hashes.json').write_text(json.dumps(manifest, indent=2))
        result = {'case': label, 'original': str(source), 'host_logos': adapted,
                  'existing_mobile_fixture': flex_baseline, 'source_files_copied': len(manifest)}
        if adapted:
            prepared = command([args.prepare_cli, 'prepare', str(dest)])
            (out / 'prepare.json').write_text(prepared.stdout)
            if prepared.returncode:
                result.update(status='import_failed', detail=prepared.stdout)
                return result
            config_path = dest / 'MobileCompiler.json'
            config = json.loads(config_path.read_text())
            generated = []
            for relative in config['sources']:
                if Path(relative).suffix not in {'.x', '.xm'}:
                    generated.append(relative)
                    continue
                output = relative + '.preprocessed'
                host_environment = dict(os.environ, LC_ALL='C', LC_CTYPE='C', LANG='C')
                preprocessed = command(['/usr/bin/perl', str(ROOT / 'Resources/logos/bin/logos.pl'),
                                        '-c', 'generator=' + config.get('logosGenerator', 'MobileSubstrate'), str(dest / relative)], env=host_environment)
                (out / ('logos-' + str(len(generated)) + '.log')).write_text(preprocessed.stderr)
                if preprocessed.returncode:
                    result.update(status='host_logos_failed', detail=preprocessed.stderr)
                    return result
                (dest / output).write_text(preprocessed.stdout)
                generated.append(relative)
            config['sources'] = generated
            config_path.write_text(json.dumps(config, indent=2))
            result['adaptations'] = ['Mac Perl Logos sidecars; simulator uses production per-source output and language mapping; original source untouched']
        before = set(documents.glob('Build-*'))
        import_result = documents / 'TestImportResult.json'
        import_result.unlink(missing_ok=True)
        command(['xcrun', 'simctl', 'terminate', 'booted', BUNDLE])
        launch_args=['launch','booted',BUNDLE,'--self-test-project','--test-project-path',str(dest)]
        if adapted:launch_args.append('--test-logos-preprocessed')
        launched = sim(*launch_args)
        (out / 'launch.txt').write_text(launched)
        deadline = time.monotonic() + args.timeout
        while time.monotonic() < deadline:
            if import_result.exists():
                try:
                    imported = json.loads(import_result.read_text())
                    if not imported['imported']:
                        result.update(status='import_failed', detail=imported['message'])
                        break
                except (ValueError, OSError):
                    pass
            builds = set(documents.glob('Build-*')) - before
            complete = [b for b in builds if (b / 'report.json').exists()]
            if complete:
                build = sorted(complete, key=lambda p: p.stat().st_mtime)[-1]
                try:
                    report = json.loads((build / 'report.json').read_text())
                except (ValueError, OSError):
                    time.sleep(.5)
                    continue
                log = (build / 'build.log').read_text(errors='replace')
                result.update(status='passed' if report.get('success') else 'build_failed',
                              source_count=report.get('sourceCount'),
                              compiler_commands=len(report.get('commands', [])),
                              duration_seconds=report.get('durationSeconds'),
                              errors=[line for line in log.splitlines() if re.search(r'(fatal error:|error:|dlopen\(|BUILD FAILED|Logos exit=[1-9])', line)][:12])
                for file in build.iterdir():
                    if file.suffix in {'.json', '.log', '.dylib', '.deb'} or file.name == 'Tweak.mm' or file.name.startswith('logos-'):
                        shutil.copy2(file, out / file.name)
                imported_project = sorted(documents.glob('Imported-*'), key=lambda p: p.stat().st_mtime)
                if imported_project and (imported_project[-1] / 'MobileCompiler.json').exists():
                    shutil.copy2(imported_project[-1] / 'MobileCompiler.json', out / 'MobileCompiler.json')
                break
            time.sleep(1)
        else:
            result.update(status='timeout', detail='No completion report; inspect simulator process/crash logs')
            for build in set(documents.glob('Build-*')) - before:
                if (build / 'build.log').exists():
                    shutil.copy2(build / 'build.log', out / 'build.log')
        if import_result.exists():
            shutil.copy2(import_result, out / import_result.name)
        command(['xcrun', 'simctl', 'terminate', 'booted', BUNDLE])
        return result

    result_file = evidence / ('adapted-results.json' if args.adapted_only else 'results.json')
    if args.fixture:
        result=run_case('MultiLogos',args.fixture,adapted=True)
        result_file.write_text(json.dumps([result],ensure_ascii=True,indent=2))
        print(json.dumps(result,ensure_ascii=True),flush=True)
        return
    for name, relative in cases:
        if args.projects and name not in args.projects:continue
        variants = ([True] if name in {'kook', 'AutoMessagePlugin', 'WCElite', 'xncj'} else []) if args.adapted_only else ([False, True] if name in {'kook', 'AutoMessagePlugin', 'WCElite', 'xncj'} else [False])
        for adapted in variants:
            print('START', name, 'host-logos' if adapted else 'raw', flush=True)
            result = run_case(name, args.source_root / relative, adapted)
            results.append(result)
            result_file.write_text(json.dumps(results, ensure_ascii=True, indent=2))
            print(json.dumps(result, ensure_ascii=True), flush=True)
    if not args.adapted_only:
        print('START FLEX existing mobile configuration', flush=True)
        results.append(run_case('FLEX', ROOT / 'Resources/FLEXProject', flex_baseline=True))
        result_file.write_text(json.dumps(results, ensure_ascii=True, indent=2))
        print(json.dumps(results[-1], ensure_ascii=True), flush=True)
    print('COMPLETE', len(results), 'cases', flush=True)


if __name__ == '__main__':
    main()
