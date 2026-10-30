#!/usr/bin/env python3
import io,json,shutil,struct,subprocess,tarfile,time
from pathlib import Path
R=Path(__file__).resolve().parents[1];O=R/'evidence/0.5.2-output-checkboxes';O.mkdir(exist_ok=True);B='com.xuegao.theosmobilecompiler'
def sim(*args):return subprocess.check_output(['xcrun','simctl',*map(str,args)],text=True).strip()
sim('install','booted',R/'build/simulator/TheosMobileCompiler.app');doc=Path(sim('get_app_container','booted',B,'data'))/'Documents'
cases=[('all-custom',dict(packageSchemes=['rootless','rootful','roothide'],**{'outputPattern-deb':'MyPlugin','outputPattern-dylib':'MyLibrary'})),('pair',dict(packageSchemes=['rootful','roothide'],**{'outputPattern-dylib':'{product}_{architecture}'})),('single',dict(packageSchemes=['rootful'],**{'outputPattern-dylib':'{product}_{architecture}'})),('disabled',dict(package=False,packageSchemes=['rootless','rootful','roothide'],**{'outputPattern-dylib':'OnlyLib'})),('variable-names',dict(packageSchemes=['rootless','rootful','roothide'],**{'outputPattern-deb':'{name}_{architecture}','outputPattern-dylib':'{product}_{architecture}'}))]
cases += [('deb-only',dict(packageSchemes=['rootless','rootful','roothide'],exportDylib=False))]
results=[]
for label,opts in cases:
 src=doc/('MultiPackages-'+label);src.mkdir(exist_ok=True);(src/'Smoke.m').write_text('#import <Foundation/Foundation.h>\nint smoke(void){return (int)[@"ok" length];}\n');config=dict(name='Test',productName='Smoke',sources=['Smoke.m'],package=True);config.update(opts);(src/'MobileCompiler.json').write_text(json.dumps(config));before=set(doc.glob('Build-*'));subprocess.run(['xcrun','simctl','terminate','booted',B],capture_output=True);sim('launch','booted',B,'--self-test-project','--test-project-path',src)
 complete=[];deadline=time.monotonic()+90
 while time.monotonic()<deadline:
  complete=[p for p in set(doc.glob('Build-*'))-before if (p/'report.json').exists()]
  if complete:break
  time.sleep(.5)
 assert complete,label+' timeout';build=complete[0];report=json.loads((build/'report.json').read_text());dest=O/label;dest.mkdir(exist_ok=True)
 for f in build.iterdir():
  if f.suffix in {'.log','.json','.deb','.dylib'}:shutil.copy2(f,dest/f.name)
 assert report['success'],(label,report.get('packageError'))
 enabled=opts.get('package',True);schemes=opts['packageSchemes'];packages=list(build.glob('*.deb'));dylibs=list(build.glob('*.dylib'));assert len(packages)==(len(schemes) if enabled else 0);assert len(dylibs)==((len(schemes) if enabled else 1) if opts.get('exportDylib',True) else 0)
 compile_count=sum(x['stage']=='compile' for x in report['commands']);links=[x for x in report['commands'] if x['stage'].startswith('link')];assert compile_count==1;assert len(links)==(len(schemes) if enabled else 1)
 for variant in report['variants']:
  scheme=variant['scheme'];deb=(build/variant['deb']).read_bytes();at=8;members={}
  while at<len(deb):
   h=deb[at:at+60];n=int(h[48:58]);members[h[:16].decode().strip()]=deb[at+60:at+60+n];at+=60+n+(n%2)
  with tarfile.open(fileobj=io.BytesIO(members['control.tar'])) as tf:control=tf.extractfile('./control').read().decode()
  arch={'rootless':'iphoneos-arm64','rootful':'iphoneos-arm','roothide':'iphoneos-arm64e'}[scheme];assert 'Architecture: '+arch+'\n' in control
  with tarfile.open(fileobj=io.BytesIO(members['data.tar'])) as tf:
   names=tf.getnames();lib=tf.extractfile(next(n for n in names if n.endswith('.dylib'))).read()
  assert all(n.startswith('./var/jb/' if scheme=='rootless' else './Library/') for n in names)
  disk=(build/variant['dylib']).read_bytes() if opts.get('exportDylib',True) else lib;assert lib==disk;assert struct.unpack('<i',disk[8:12])[0]==0
  command=next(c['command'] for c in links if str(build/variant['dylib']) in c['command']);rpath={'rootless':'/var/jb/Library/Frameworks','rootful':'/Library/Frameworks','roothide':'@loader_path/.jbroot/Library/Frameworks'}[scheme];assert '-rpath '+rpath in command
 if label=='all-custom':assert {p.name for p in packages}=={'MyPlugin_'+s+'.deb' for s in schemes}
 if label=='disabled':assert dylibs[0].name=='OnlyLib.dylib'
 results.append(dict(case=label,success=True,compileCount=compile_count,linkCount=len(links),packages=[p.name for p in packages],dylibs=[p.name for p in dylibs]));(O/'results.json').write_text(json.dumps(results,indent=2));print(label,'PASS',flush=True)
print('All',len(results),'cases passed')
