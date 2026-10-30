#!/usr/bin/env python3
"""Build pinned libgit2 with system Apple TLS; no shell git executable in IPA."""
import argparse,pathlib,subprocess,shutil,os
p=argparse.ArgumentParser();p.add_argument('--platform',choices=['device','simulator','macos'],required=True);a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[1]
cmake=os.environ.get('TMC_CMAKE') or shutil.which('cmake')
if not cmake: raise SystemExit('Install CMake or set TMC_CMAKE to its executable')
build=root/'build'/('git-'+a.platform)
args=[cmake,'-S',str(root/'Vendor/libgit2'),'-B',str(build),'-DCMAKE_BUILD_TYPE=Release','-DBUILD_SHARED_LIBS=OFF','-DBUILD_TESTS=OFF','-DBUILD_CLI=OFF','-DUSE_SSH=OFF','-DUSE_HTTPS=SecureTransport','-DUSE_BUNDLED_ZLIB=ON','-DUSE_NTLMCLIENT=OFF','-DUSE_GSSAPI=OFF','-DREGEX_BACKEND=builtin','-DCMAKE_POLICY_VERSION_MINIMUM=3.5']
if a.platform!='macos':
 sdk='iphoneos' if a.platform=='device' else 'iphonesimulator'
 args+=['-DCMAKE_SYSTEM_NAME=iOS','-DCMAKE_OSX_SYSROOT='+subprocess.check_output(['xcrun','--sdk',sdk,'--show-sdk-path'],text=True).strip(),'-DCMAKE_OSX_ARCHITECTURES='+('arm64' if a.platform=='device' else 'x86_64'),'-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0']
subprocess.run(args,check=True)
subprocess.run([cmake,'--build',str(build),'-j','6'],check=True)
