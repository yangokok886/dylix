"""Exercise parseable Fix-It emitted by the actual bundled Clang14 in the simulator."""
import json,os,subprocess,tempfile,time,shutil,re
from pathlib import Path
R=Path(__file__).resolve().parents[1];OUT=R/'evidence/0.5.5-rules/embedded-fixit';OUT.mkdir(parents=True,exist_ok=True)
def run(*args):
 p=subprocess.run(list(map(str,args)),capture_output=True,text=True);assert p.returncode==0,(p.stdout,p.stderr);return p.stdout.strip()
doc=Path(run('xcrun','simctl','get_app_container','booted','com.xuegao.theosmobilecompiler','data'))/'Documents'
with tempfile.TemporaryDirectory(prefix='tmc-fixit-') as tmp:
 root=Path(tmp);(root/'Test.c').write_text('const char *fixit_title = "中文"\n');(root/'MobileCompiler.json').write_text(json.dumps(dict(name='FixItExactByteTest',productName='FixItByte',sources=['Test.c'],package=False)))
 def build():
  before=set(doc.glob('Build-*'));run('xcrun','simctl','launch','--terminate-running-process','booted','com.xuegao.theosmobilecompiler','--self-test-project','--test-project-path',root)
  deadline=time.monotonic()+40
  while time.monotonic()<deadline:
   for b in set(doc.glob('Build-*'))-before:
    if (b/'report.json').exists():return b,json.loads((b/'report.json').read_text())
   time.sleep(.25)
  raise AssertionError('build timeout')
 b,report=build();assert not report['success'];log=(b/'build.log').read_text();(OUT/'before.log').write_text(log)
 assert '-fdiagnostics-parseable-fixits' in log and 'fix-it:' in log
 # Importer copies the source; locate the actual snapshot from compiler output.
 m=re.search(r'^fix-it:"(.+/Test.c)"',log,re.M);assert m,log;snapshot=Path(m[1]).parent
 env=dict(os.environ,TMC_RULES_PATH=str((R/'Resources/CompatibilityRules/rules.json').resolve()))
 # Staging promotion for the two new rules only within this test.
 catalog=json.loads((R/'Resources/CompatibilityRules/rules.json').read_text())
 for r in catalog['rules']:
  if r['id']=='TF004':r['validation']['status']='verified'
 cp=root/'rules.json';cp.write_text(json.dumps(catalog));env['TMC_RULES_PATH']=str(cp)
 logs=root/'log';logs.write_text(log)
 def cli(mode,file,extra=None):
  args=['/private/tmp/tmc-compatibility-tests',mode,str(root),str(file)]
  if extra:args.append(str(extra))
  p=subprocess.run(args,env=env,capture_output=True,text=True);assert not p.returncode,p.stdout;return json.loads(p.stdout)
 fixes=cli('fixits',logs,snapshot)['plan'];assert len(fixes)==1;df=root/'diagnostics.json';df.write_text(json.dumps(fixes));plan=cli('apply',df)['plan'];assert len(plan)==1
 assert (root/'Test.c').read_text()=='const char *fixit_title = "中文";\n';(OUT/'fixit-plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2))
 b,report=build();assert report['success'],(b/'build.log').read_text();shutil.copy2(b/'build.log',OUT/'after.log');shutil.copy2(b/'report.json',OUT/'after-report.json')
 cli('undo',df);assert (root/'Test.c').read_text()=='const char *fixit_title = "中文"\n'
 (OUT/'result.json').write_text(json.dumps(dict(embeddedClang14=True,byteColumnUTF8=True,initialFailed=True,repairBuildPassed=True,undoExact=True),indent=2))
 # Existing real dependency in a nested folder: infer only a unique include search directory.
 (root/'Test.c').write_text('#include "Actual.h"\nint header_value(void) { return ACTUAL_VALUE; }\n');(root/'Vendor/Headers').mkdir(parents=True);(root/'Vendor/Headers/Actual.h').write_text('#define ACTUAL_VALUE 42\n')
 b,report=build();assert not report['success'];log=(b/'build.log').read_text();(OUT/'header-before.log').write_text(log)
 m=re.search(r"^(.+/Test.c):([0-9]+):([0-9]+): fatal error: ('Actual.h' file not found)",log,re.M);assert m,log;snapshot=Path(m[1]).parent
 (root/'MobileCompiler.json').write_bytes((snapshot/'MobileCompiler.json').read_bytes())
 for r in catalog['rules']:
  if r['id']=='TF005':r['validation']['status']='verified'
 cp.write_text(json.dumps(catalog))
 df.write_text(json.dumps([dict(file='Test.c',path=m[1],line=int(m[2]),column=int(m[3]),message=m[4])]))
 before=(root/'MobileCompiler.json').read_text();plan=cli('apply',df)['plan'];assert plan[0]['file']=='MobileCompiler.json'
 b,report=build();assert report['success'],(b/'build.log').read_text();shutil.copy2(b/'build.log',OUT/'header-after.log');(OUT/'header-plan.json').write_text(json.dumps(plan,indent=2));cli('undo',df);assert (root/'MobileCompiler.json').read_text()==before
 (OUT/'header-result.json').write_text(json.dumps(dict(uniqueRealHeader=True,configSnapshot=True,successfulRebuild=True,undoExact=True),indent=2))
 print('Embedded LLVM14: UTF8 semicolon Fix-It and unique real header search path repair; successful rebuilds and exact undo passed')
