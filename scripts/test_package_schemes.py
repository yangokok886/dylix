#!/usr/bin/env python3
"""Exercise the embedded iOS clang/lld/DEB pipeline for each scheme/CPU pair."""
import json, subprocess, time, shutil, tarfile, io, struct
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'evidence/0.5.0-package-performance'
BUNDLE='com.xuegao.theosmobilecompiler'
def sim(*args):
 return subprocess.check_output(['xcrun','simctl',*map(str,args)],text=True).strip()
sim('install','booted',ROOT/'build/simulator/TheosMobileCompiler.app')
doc=Path(sim('get_app_container','booted',BUNDLE,'data'))/'Documents'
results=[]
for scheme in ['rootless','rootful','roothide']:
 for cpu in ['arm64','arm64e']:
  label=scheme+'-'+cpu
  src=doc/('SchemeTest-'+label);src.mkdir(exist_ok=True)
  (src/'Smoke.m').write_text('#import <Foundation/Foundation.h>\nint smoke(void) { return (int)[@"ok" length]; }\n')
  (src/'MobileCompiler.json').write_text(json.dumps(dict(name='SchemeTest',productName='Smoke',sources=['Smoke.m'],package=True,packageScheme=scheme,cpuArchitecture=cpu)))
  before=set(doc.glob('Build-*'))
  subprocess.run(['xcrun','simctl','terminate','booted',BUNDLE],capture_output=True)
  sim('launch','booted',BUNDLE,'--self-test-project','--test-project-path',src)
  deadline=time.monotonic()+80
  while time.monotonic()<deadline:
   complete=[b for b in set(doc.glob('Build-*'))-before if (b/'report.json').exists()]
   if complete:break
   time.sleep(.5)
  assert complete,label+' timeout'
  build=complete[0];report=json.loads((build/'report.json').read_text());dest=OUT/label;dest.mkdir(exist_ok=True)
  for old in dest.iterdir():
   if old.is_file():old.unlink()
  for f in build.iterdir():
   if f.suffix in {'.json','.log','.deb','.dylib'}:shutil.copy2(f,dest/f.name)
  result=dict(case=label,success=report['success'],commands=report.get('commands'),packageError=report.get('packageError'))
  if cpu=='arm64e':
   assert not report['success'],label+' must reject mismatched ABI'
   assert not list(dest.glob('*.deb')),label+' emitted invalid package'
   result['expectedRejection']=True
  else:
   assert report['success'],label+' failed'
  if report['success']:
   deb=next(dest.glob('*.deb')).read_bytes();assert deb[:8]==b'!<arch>\n';members={};at=8
   while at<len(deb):
    head=deb[at:at+60];size=int(head[48:58]);members[head[:16].decode().strip().rstrip('/')]=deb[at+60:at+60+size];at+=60+size+(size%2)
   with tarfile.open(fileobj=io.BytesIO(members['control.tar'])) as tf:control=tf.extractfile('./control').read().decode()
   with tarfile.open(fileobj=io.BytesIO(members['data.tar'])) as tf:
    paths=tf.getnames();dylib=tf.extractfile(next(n for n in paths if n.endswith('.dylib'))).read()
   arch={'rootless':'iphoneos-arm64','rootful':'iphoneos-arm','roothide':'iphoneos-arm64e'}[scheme]
   assert 'Architecture: '+arch+'\n' in control
   prefix='./var/jb/Library/' if scheme=='rootless' else './Library/'
   assert all(n.startswith(prefix) for n in paths)
   _,cputype,subtype,filetype=struct.unpack('<IiiI',dylib[:16]);assert cputype==0x100000c and filetype==6
   assert subtype&0xffffff==(2 if cpu=='arm64e' else 0),(cpu,subtype)
   result.update(packageArchitecture=arch,paths=paths,machOSubtype=subtype,verified=True)
  results.append(result);(OUT/'scheme-results.json').write_text(json.dumps(results,indent=2));print(label,report['success'],report.get('packageError'),flush=True)
print('Completed',len(results),'cases')
