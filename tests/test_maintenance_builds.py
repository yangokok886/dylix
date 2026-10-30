"""Run real embedded compiler and inspect payloads on disposable simulator fixtures."""
import io,json,pathlib,plistlib,subprocess,tarfile,tempfile,time
R=pathlib.Path(__file__).resolve().parents[1];O=R/'evidence/1.0.0-maintenance';D='059E3F19-5F2D-4C4F-86B2-C39F89179142';B='com.xuegao.theosmobilecompiler'
def sim(*args):return subprocess.check_output(['xcrun','simctl',*map(str,args)],text=True).strip()
doc=pathlib.Path(sim('get_app_container',D,B,'data'))/'Documents';results=[]
with tempfile.TemporaryDirectory(prefix='tf-maint-builds-') as temp:
 for label,options in [('three-packages',{'package':True,'packageSchemes':['rootless','rootful','roothide']}),('disabled-deb',{'package':False,'outputPattern-deb':'{unknown}'}),('disabled-dylib',{'package':True,'exportDylib':False,'outputPattern-dylib':'{unknown}'})]:
  source=pathlib.Path(temp)/label;source.mkdir();(source/'中文源码.c').write_text('int maintenance(void){return 42;}\n')
  config={'name':'维护测试','productName':'Maintenance','sources':['中文源码.c'],'exportDylib':True,'packageSchemes':['rootless']};config.update(options);(source/'MobileCompiler.json').write_text(json.dumps(config,ensure_ascii=False))
  (source/'control').write_text('Package: local.maintenance\nName: Maintenance\nVersion: 1.0.0\nArchitecture: iphoneos-arm64\nMaintainer: Test\nDescription: Fixture\n')
  (source/'Maintenance.plist').write_bytes(plistlib.dumps({'Filter':{'Bundles':['com.example.target']}}))
  resource=source/'layout/Library/Application Support/Maintenance.bundle/test.txt';resource.parent.mkdir(parents=True);resource.write_text('resource fixture')
  before=set(doc.glob('Build-*'));sim('launch','--terminate-running-process',D,B,'--self-test-project','--test-project-path',source)
  deadline=time.monotonic()+90;build=None
  while time.monotonic()<deadline:
   found=[p for p in set(doc.glob('Build-*'))-before if (p/'report.json').exists()]
   if found:build=found[0];break
   time.sleep(.3)
  assert build,label+' timed out';report=json.loads((build/'report.json').read_text());assert report['success'],(label,report,(build/'build.log').read_text()[-2000:]);log=(build/'build.log').read_text();assert '中文源码.c' in log and '构建成功' in log,log
  dylibs=list(build.glob('*.dylib'));assert len(dylibs)==(0 if options.get('exportDylib') is False else 1),dylibs
  for package in report.get('packages',[]):
   raw=(build/package['name']).read_bytes();at=8;members={}
   while at<len(raw):
    h=raw[at:at+60];size=int(h[48:58]);members[h[:16].decode().strip().rstrip('/')]=raw[at+60:at+60+size];at+=60+size+size%2
   with tarfile.open(fileobj=io.BytesIO(members['data.tar'])) as t:
    prefix='./var/jb/' if package['scheme']=='rootless' else './';assert prefix+'Library/Application Support/Maintenance.bundle/test.txt' in t.getnames()
   with tarfile.open(fileobj=io.BytesIO(members['control.tar'])) as t:
    control=t.extractfile('./control').read().decode();arch={'rootless':'iphoneos-arm64','rootful':'iphoneos-arm','roothide':'iphoneos-arm64e'}[package['scheme']];assert 'Architecture: '+arch in control
  assert len(report.get('packages',[]))==(3 if label=='three-packages' else 0 if label=='disabled-deb' else 1)
  (O/(label+'-report.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2));(O/(label+'-build.log')).write_text(log);results.append({'case':label,'passed':True,'packages':len(report.get('packages',[])),'dylibs':len(dylibs),'unicodeLogs':True});print(label,'PASS',flush=True)
(O/'embedded-builds.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
