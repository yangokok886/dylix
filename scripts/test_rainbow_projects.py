#!/usr/bin/env python3
"""Read-only original projects; compile sandbox copies and audit actual DEBs."""
import hashlib,io,json,os,plistlib,re,shutil,struct,subprocess,tarfile,time
from pathlib import Path
from test_local_projects import copy_sources
R=Path(__file__).resolve().parents[1];SOURCE=Path(os.environ.get('DYLIX_TEST_PROJECTS',str(R/'fixtures/optional-local-projects')));OUT=R/'evidence/0.5.2-rainbow-projects';OUT.mkdir(exist_ok=True);B='com.xuegao.theosmobilecompiler'
CASES=[('kook','kook'),('AutoMessagePlugin','AutoMessagePlugin'),('AutoMessagePlugin2','AutoMessagePlugin 2'),('WCElite','微信优化 2/wcyh/wcyh'),('RainbowHelper','Rainbow/RainbowHelper/RainbowHelper'),('xncj','虚拟插件/xncj/xncj'),('xiangqing','xiangqing/xiangqing'),('FLEX','FLEX')]
def run(args,**kwargs):return subprocess.run(list(map(str,args)),capture_output=True,text=True,**kwargs)
def sim(*args):
 p=run(['xcrun','simctl',*args]);assert not p.returncode,p.stderr;return p.stdout.strip()
def manifest(root):
 entries={}
 for directory,dirs,files in os.walk(root,followlinks=False):
  dirs.sort()
  for name in sorted(dirs+files):
   path=Path(directory)/name;relative=str(path.relative_to(root));st=path.lstat()
   if path.is_symlink():entries[relative]=dict(type='symlink',target=os.readlink(path))
   elif path.is_file():entries[relative]=dict(type='file',size=st.st_size,mtime_ns=st.st_mtime_ns,sha256=hashlib.sha256(path.read_bytes()).hexdigest())
   else:entries[relative]=dict(type='directory',mtime_ns=st.st_mtime_ns)
 return entries
def fields(control):
 return {l.split(':',1)[0].lower():l.split(':',1)[1].strip() for l in control.splitlines() if ':' in l and not l.startswith((' ','\t'))}
def read_plist(raw):
 try:return plistlib.loads(raw)
 except plistlib.InvalidFileException:
  parsed=subprocess.run(['plutil','-convert','xml1','-o','-','--','-'],input=raw,capture_output=True)
  assert parsed.returncode==0,parsed.stderr.decode()
  return plistlib.loads(parsed.stdout)
def audit(build,config,project):
 report=json.loads((build/'report.json').read_text());checks=[]
 for variant in report.get('variants',[]):
  scheme=variant['scheme'];raw=(build/variant['deb']).read_bytes();assert raw[:8]==b'!<arch>\n';members={};at=8
  while at<len(raw):
   h=raw[at:at+60];assert h[58:60]==b'`\n';n=int(h[48:58]);members[h[:16].decode().strip().rstrip('/')]=raw[at+60:at+60+n];at+=60+n+n%2
  assert members['debian-binary']==b'2.0\n'
  with tarfile.open(fileobj=io.BytesIO(members['control.tar'])) as tf:ctl=tf.extractfile('./control').read().decode()
  metadata=fields(ctl);arch={'rootless':'iphoneos-arm64','rootful':'iphoneos-arm','roothide':'iphoneos-arm64e'}[scheme];assert metadata['architecture']==arch
  original=project/'control'
  if original.exists():
   original=fields(original.read_text());assert all(metadata.get(k)==original[k] for k in ['package','version','name'] if k in original)
  with tarfile.open(fileobj=io.BytesIO(members['data.tar'])) as tf:
   entries=tf.getmembers();assert len(entries)==2 and all(x.isfile() and x.uid==0 and x.gid==0 for x in entries)
   libentry=next(x for x in entries if x.name.endswith('.dylib'));plistentry=next(x for x in entries if x.name.endswith('.plist'));lib=tf.extractfile(libentry).read();fil=tf.extractfile(plistentry).read();paths=[x.name for x in entries];assert libentry.mode==0o755 and plistentry.mode==0o644
  prefix='./var/jb/Library/MobileSubstrate/DynamicLibraries/' if scheme=='rootless' else './Library/MobileSubstrate/DynamicLibraries/';assert all(x.startswith(prefix) for x in paths)
  assert lib==(build/variant['dylib']).read_bytes();header=struct.unpack('<IiiI',lib[:16]);assert header==(0xfeedfacf,0x100000c,0,6)
  filterdata=read_plist(fil);assert isinstance(filterdata.get('Filter'),dict) and filterdata['Filter'];original_plists=list(project.glob('*.plist'))
  assert len(original_plists)==1;assert filterdata==read_plist(original_plists[0].read_bytes())
  # Read actual Mach-O LC_RPATH/LC_ID_DYLIB, rather than trusting command strings.
  count=struct.unpack_from('<I',lib,16)[0];offset=32;rpaths=[];install=None;dependencies=[]
  for _ in range(count):
   command,size=struct.unpack_from('<II',lib,offset);assert size>=8 and offset+size<=len(lib)
   if command in [0x8000001c,0xd,0xc,0x80000018,0x8000001f]:
    start=struct.unpack_from('<I',lib,offset+8)[0];value=lib[offset+start:offset+size].split(b'\0')[0].decode()
    if command==0x8000001c:rpaths.append(value)
    elif command==0xd:install=value
    else:dependencies.append(value)
   offset+=size
  expected={'rootless':'/var/jb/Library/Frameworks','rootful':'/Library/Frameworks','roothide':'@loader_path/.jbroot/Library/Frameworks'}[scheme];assert expected in rpaths
  expected_prefix='@loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/' if scheme=='roothide' else '@rpath/';assert install.startswith(expected_prefix)
  checks.append(dict(scheme=scheme,deb=variant['deb'],bytes=len(raw),package=metadata['package'],version=metadata['version'],architecture=arch,paths=paths,filter=filterdata,rpaths=rpaths,installName=install,dependencies=dependencies,sha256=hashlib.sha256(raw).hexdigest(),verified=True))
 assert len(checks)==3;assert sum(x['stage']=='compile' for x in report['commands'])==len(config['sources']);assert len([x for x in report['commands'] if x['stage'].startswith('link')])==3
 return checks
if os.environ.get('TMC_RAINBOW_ADAPT'):
 CASES=[(name+'-adapted',rel) for name,rel in CASES if name in ['xncj','xiangqing','FLEX']]
 OUT=R/'evidence/0.5.2-rainbow-adapted';OUT.mkdir(exist_ok=True)
if os.environ.get('TMC_FLEX_HEADER'):
 CASES=[('FLEX-header-adapted','FLEX')];OUT=R/'evidence/0.5.2-rainbow-flex-header';OUT.mkdir(exist_ok=True)
if os.environ.get('TMC_PROJECT_REL'):
 CASES=[('RequestedAutoMessagePlugin',os.environ['TMC_PROJECT_REL'])];OUT=R/'evidence/0.5.2-requested-automessage';OUT.mkdir(exist_ok=True)
if os.environ.get('TMC_REQUESTED_FIX'):
 OUT=R/'evidence/0.5.2-requested-automessage-adapted';OUT.mkdir(exist_ok=True)
if os.environ.get('TMC_REPAIR_FLEX_ONLY'):
 CASES=[('FLEX-rule-repair','FLEX')]
if os.environ.get('TMC_REPAIR_LOG'):
 OUT=R/'evidence'/('0.5.3-repair-'+('FLEX' if os.environ.get('TMC_RAINBOW_ADAPT') else 'AutoMessage'));OUT.mkdir(exist_ok=True)
sim('install','booted',R/'build/simulator/TheosMobileCompiler.app');doc=Path(sim('get_app_container','booted',B,'data'))/'Documents';results=[];integrity=[]
if os.environ.get('TMC_EVIDENCE_OUT'):
 OUT=R/'evidence'/os.environ['TMC_EVIDENCE_OUT'];OUT.mkdir(exist_ok=True)
for name,relative in CASES:
 print('START',name,flush=True);source=SOURCE/relative;out=OUT/name;out.mkdir(exist_ok=True);before=manifest(source);(out/'original-before.json').write_text(json.dumps(before,ensure_ascii=False));dest=doc/('RainbowReadOnlyTest-'+name+'-'+str(int(time.time())));dest.mkdir();result=dict(project=name,original=str(source),testCopy=str(dest),originalUnchanged=None,adaptations=['Mac Perl Logos sidecars for simulator only','Test-copy configuration selects all three DEB types and arm64; original untouched']);
 try:
  copies=copy_sources(source,dest);result['copiedSourceCount']=len(copies)
  if os.environ.get('TMC_REQUESTED_FIX'):
   f=dest/'AutoMessagePlugin.xm';text=f.read_text();text=text.replace('typeof(', '__typeof__(').replace('config.payloadMode = [modeNum integerValue];','config.payloadMode = (AutoMessagePayloadMode)[modeNum integerValue];');f.write_text(text);result['adaptations']+=['Test-copy only: GNU typeof spelled __typeof__, explicit enum cast at payloadMode assignment']
  if os.environ.get('TMC_RAINBOW_ADAPT'):
   if name.startswith('FLEX'):
    config=json.loads((R/'Resources/FLEXProject/MobileCompiler.json').read_text());config['productName']='FLEX++';config['package']=True
    if os.environ.get('TMC_FLEX_HEADER'):
     (dest/'MobileTestPrefix.h').write_text('#include <mach/task_info.h>\n#include "flex_fishhook.h"\n');config['prefixHeader']='MobileTestPrefix.h';result['adaptations']+=['Test-only prefix header imports mach/task_info.h plus original flex_fishhook.h; no original source edits']
    (dest/'filter.plist').write_bytes(plistlib.dumps({'Filter':{'Bundles':['com.tencent.xin']}}));result['adaptations']+=['Copied existing mobile FLEX source manifest; explicit test filter com.tencent.xin (original has no filter)']
   else:
    leaf='xncj.xm' if name.startswith('xncj') else 'xiangqing.xm';config=dict(name=name,productName=Path(leaf).stem,sources=[leaf],frameworks=['Foundation','UIKit','UserNotifications','CydiaSubstrate'],objcArc=True,package=True)
    packaged=source/'Package'
    if not (dest/'control').exists():shutil.copy2(packaged/'DEBIAN/control',dest/'control')
    for f in (packaged/'Library/MobileSubstrate/DynamicLibraries').glob('*.plist'):shutil.copy2(f,dest/f.name)
    result['adaptations']+=['Test-only explicit source '+leaf+' replaces missing Makefile source; copy original Package control/filter to test root']
   (dest/'MobileCompiler.json').write_text(json.dumps(config,ensure_ascii=False,indent=2))
  prepared=run(['/private/tmp/tmc-archive-import-tests','prepare',dest]);(out/'prepare.json').write_text(prepared.stdout)
  if prepared.returncode:result.update(status='import_failed',detail=prepared.stdout[:3000]);continue
  configpath=dest/'MobileCompiler.json';config=json.loads(configpath.read_text());
  if os.environ.get('TMC_REPAIR_LOG'):
   log=Path(os.environ['TMC_REPAIR_LOG']).read_text();diagnostics=[]
   for m in re.finditer(r'^(.+?):([0-9]+):([0-9]+): (fatal error|error|warning|note): (.*)$',log,re.M):
    path=m[1];matches=[str(f.relative_to(dest)) for f in dest.rglob('*') if f.is_file() and path.endswith('/'+str(f.relative_to(dest)))];relative=max(matches,key=len) if matches else None
    if relative:
     baseline=Path(os.environ['TMC_REPAIR_BASELINE']);manifest_before=json.loads(baseline.read_text());assert manifest_before[relative]['sha256']==hashlib.sha256((dest/relative).read_bytes()).hexdigest(),relative+' changed from logged baseline'
     snap=out/'diagnostic-snapshot'/relative;snap.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(dest/relative,snap)
     diagnostics.append(dict(file=relative,path=str(snap.resolve()),line=int(m[2]),column=int(m[3]),message=m[5],severity=m[4]))
   diag=out/'repair-diagnostics.json';diag.write_text(json.dumps(diagnostics));repair=run(['/private/tmp/tmc-compatibility-tests','apply',dest,diag]);(out/'repair-plan.json').write_text(repair.stdout)
   if repair.returncode:result.update(status='repair_failed',detail=repair.stdout);continue
   result['adaptations']+=['Production TMCCompatibilityPlan generated from real failed build diagnostics, applied with backup'];result['repairEdits']=sum(len(p['edits']) for p in json.loads(repair.stdout)['plan'])
  (out/'imported-config.json').write_text(json.dumps(config,ensure_ascii=False,indent=2));result['sources']=config['sources'];result['sourceCount']=len(config['sources']);result['importNotes']=config.get('importNotes',[])
  failed=False
  for i,relative_source in enumerate(config['sources']):
   if Path(relative_source).suffix not in ['.x','.xm']:continue
   processed=run(['/usr/bin/perl',R/'Resources/logos/bin/logos.pl','-c','generator='+config.get('logosGenerator','MobileSubstrate'),dest/relative_source],env=dict(os.environ,LC_ALL='C',LC_CTYPE='C',LANG='C'));(out/('logos-'+str(i)+'.log')).write_text(processed.stderr)
   if processed.returncode:result.update(status='logos_failed',detail=processed.stderr[:3000]);failed=True;break
   (dest/(relative_source+'.preprocessed')).write_text(processed.stdout)
  if failed:continue
  config.update(package=True,packageSchemes=['rootless','rootful','roothide'],cpuArchitecture='arm64',exportDylib=True);config.pop('packageScheme',None);configpath.write_text(json.dumps(config,ensure_ascii=False,indent=2));(out/'test-config.json').write_bytes(configpath.read_bytes())
  builds_before=set(doc.glob('Build-*'));(doc/'TestImportResult.json').unlink(missing_ok=True);run(['xcrun','simctl','terminate','booted',B]);sim('launch','booted',B,'--self-test-project','--test-project-path',dest,'--test-logos-preprocessed');deadline=time.monotonic()+240;completed=[]
  while time.monotonic()<deadline:
   completed=[b for b in set(doc.glob('Build-*'))-builds_before if (b/'report.json').exists()]
   if completed:break
   imp=doc/'TestImportResult.json'
   if imp.exists():
    data=json.loads(imp.read_text())
    if not data['imported']:result.update(status='app_import_failed',detail=data['message']);break
   time.sleep(.5)
  if not completed:
   result.setdefault('status','timeout');continue
  build=completed[0];report=json.loads((build/'report.json').read_text());log=(build/'build.log').read_text(errors='replace');result.update(status='passed' if report['success'] else 'build_failed',durationSeconds=report.get('durationSeconds'),commandCount=len(report.get('commands',[])),errors=[l for l in log.splitlines() if 'error:' in l or 'Undefined symbols' in l][:15],packageError=report.get('packageError'))
  for f in build.iterdir():
   if f.is_file() and (f.suffix in ['.json','.log','.deb','.dylib'] or f.name.startswith('control')):shutil.copy2(f,out/f.name)
  if report['success']:result['packageAudits']=audit(build,config,dest)
 except Exception as e:result.update(status='test_error',detail=str(e))
 finally:
  after=manifest(source);changed=[key for key in set(before)|set(after) if before.get(key)!=after.get(key)];result['originalUnchanged']=not changed;result['originalChanges']=changed;integrity.append(dict(project=name,entries=len(before),unchanged=not changed,changed=changed));results.append(result);(OUT/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2));(OUT/'original-integrity.json').write_text(json.dumps(integrity,ensure_ascii=False,indent=2));print(name,result['status'],'original unchanged',not changed,flush=True)
print('COMPLETE',len(results),'projects',flush=True)
