import subprocess,json,time,tempfile,shutil,os
from pathlib import Path
B='com.xuegao.theosmobilecompiler';out=Path(os.environ.get('TMC_NAMING_EVIDENCE','TheosMobileCompiler/evidence/0.5.7-build-settings'));out.mkdir(parents=True,exist_ok=True)
def run(*a):return subprocess.check_output(a,text=True).strip()
doc=Path(run('xcrun','simctl','get_app_container','booted',B,'data'))/'Documents'
with tempfile.TemporaryDirectory() as t:
 p=Path(t);(p/'Test.c').write_text('int mobile_naming_test(void){ return 42; }\n');(p/'MobileCompiler.json').write_text(json.dumps(dict(name='NamingTest',productName='NamingTest',sources=['Test.c'],package=True,packageSchemes=['rootless','rootful','roothide'],exportDylib=True,**{'outputPattern-deb':'{product}_{platform}_{packageArch}_{scheme}','outputPattern-dylib':'{product}'})))
 before=set(doc.glob('Build-*'));run('xcrun','simctl','launch','--terminate-running-process','booted',B,'--self-test-project','--test-project-path',str(p))
 deadline=time.time()+40
 while time.time()<deadline:
  builds=[b for b in set(doc.glob('Build-*'))-before if (b/'report.json').exists()]
  if builds:break
  time.sleep(.25)
 assert builds
 build=builds[0];r=json.loads((build/'report.json').read_text());assert r['success'],(build/'build.log').read_text()
 assert [v['dylib'] for v in r['variants']]==['NamingTest.dylib','.package-link-cache/rootful.dylib','.package-link-cache/roothide.dylib']
 assert [n for n in r['namedArtifacts'] if n.endswith('.dylib')]==['NamingTest.dylib']
 assert len(list(build.glob('*.dylib')))==1
 assert [v['deb'] for v in r['variants']]==['NamingTest_iphoneos_arm64_rootless.deb','NamingTest_iphoneos_arm_rootful.deb','NamingTest_iphoneos_arm64e_roothide.deb']
 for n in ['report.json','build.log']:shutil.copy2(build/n,out/n)
 print('Actual embedded compile: 1 exported dylib and 3 independently token-named DEBs passed')
