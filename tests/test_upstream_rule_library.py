"""Original fixtures based on pinned upstream diagnostics; runs real bundled Clang14.
Requires the isolated EmbeddedClangRuleProbe and CompatibilityRepairCLI, not app UI.
"""
import json,os,re,subprocess,tempfile,hashlib
from pathlib import Path
R=Path(__file__).resolve().parents[1]
OUT=R/'evidence/rules-upstream-expansion';OUT.mkdir(parents=True,exist_ok=True)
CLI=os.environ.get('TMC_RULE_CLI','/private/tmp/tmc-upstream-rules-cli')
PROBE=os.environ.get('TMC_EMBEDDED_PROBE','/private/tmp/tmc-embedded-rule-probe')
FRAMEWORKS=(R/'build/simulator/TheosMobileCompiler.app/Frameworks').resolve()
catalog=json.loads((R/'Resources/CompatibilityRules/rules.json').read_text())
assert len({r['id'] for r in catalog['rules']})==len(catalog['rules'])==44
for r in catalog['rules'][26:]:
 assert r['upstream']['revision'] in ['llvmorg-14.0.0','777925d1add4ee3485a2432a6f6d5e3ded59de7b']
 if r['id'] in ['TF027','TF028','TF029','TF030']:
  r['handling']['automaticEnabled']=True;r['validation']['status']='verified'
results=[]
with tempfile.TemporaryDirectory(prefix='tmc-upstream-rules-') as tmp:
 base=Path(tmp);rp=base/'rules.json';rp.write_text(json.dumps(catalog));env=dict(os.environ,TMC_RULES_PATH=str(rp))
 def cli(mode,root,file,extra=None,ok=True):
  args=[CLI,mode,str(root),str(file)]+([str(extra)] if extra is not None else [])
  p=subprocess.run(args,env=env,capture_output=True,text=True);assert (p.returncode==0)==ok,(args,p.stdout,p.stderr)
  return json.loads(p.stdout)['plan']
 def compile(path,language='objective-c',flags=()):
  p=subprocess.run(['xcrun','simctl','spawn','booted',PROBE,str(FRAMEWORKS),'-triple','arm64-apple-ios15.0','-fobjc-runtime=ios-15.0','-fblocks','-emit-obj','-o',str(path.with_suffix('.o')),'-fdiagnostics-parseable-fixits','-x',language,*flags,str(path)],capture_output=True,text=True,timeout=30)
  assert p.returncode in [0,1],(p.returncode,p.stdout,p.stderr)
  if p.returncode==0:
   assert path.with_suffix('.o').read_bytes()[:4]==bytes.fromhex('cffaedfe'), 'missing Mach-O object'
  return p.returncode,p.stdout+p.stderr
 fixtures=[
  ('objc-string','TF027','m','@class NSString;\nNSString *value = "中文";\n', 'objective-c'),
  ('extra-paren','TF028','m','void g(id value);\nvoid f(void) { g(@"x")); }\n','objective-c'),
  ('extra-bracket','TF028','m','@interface Probe\n- (void)test:(id)value;\n@end\nvoid f(Probe *p) { [p test:@"x"]]; }\n','objective-c'),
  ('struct-tag','TF029','c','struct Probe { int n; };\nProbe *value;\n','c'),
  ('union-tag','TF029','c','union Probe { int n; };\nProbe *value;\n','c'),
  ('enum-tag','TF029','c','enum Probe { A };\nProbe value;\n','c'),
  ('enum-comma','TF030','c','enum Probe {\n A\n B\n};\n','c'),
 ]
 for name,rule,ext,source,language in fixtures:
  root=base/name;root.mkdir();snap=base/(name+'-snapshot');snap.mkdir();file=f'Test.{ext}';path=root/file;path.write_text(source);(snap/file).write_text(source)
  status,log=compile(snap/file,language);assert status==1 and 'fix-it:' in log,(name,status,log)
  folder=OUT/name;folder.mkdir(exist_ok=True);(folder/'before.log').write_text(log);(folder/file).write_text(source)
  logpath=base/'build.log';logpath.write_text(log);fixits=cli('fixits',root,logpath,snap);assert len(fixits)==1,(name,fixits,log)
  diags=base/'diagnostics.json';diags.write_text(json.dumps(fixits));plan=cli('plan',root,diags);assert len(plan)==1 and plan[0]['edits'][0]['ruleID']==rule,(name,plan)
  assert path.read_text()==source
  # Source change after preview and unsupported ranges never silently apply.
  path.write_text(source+'// changed\n');assert cli('plan',root,diags)==[];path.write_text(source)
  cli('apply',root,diags);after=path.read_text();assert after!=source;assert cli('plan',root,diags)==[]
  status,log=compile(path,language);assert status==0,(name,log);(folder/'after.log').write_text(log);(folder/('fixed-'+file)).write_text(after)
  (folder/'plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2))
  path.write_text(after+'// user edit\n');cli('undo',root,diags,ok=False);path.write_text(after);cli('undo',root,diags);assert path.read_text()==source
  # Wrong replacement never uses a nearby rule; stale or invalid positions rejected.
  bad=[{**fixits[0],'replacement':'PAYLOAD'}];diags.write_text(json.dumps(bad));assert cli('plan',root,diags)==[]
  bad=[{**fixits[0],'column':99999,'endColumn':99999}];diags.write_text(json.dumps(bad));assert cli('plan',root,diags)==[]
  results.append(dict(case=name,rule=rule,compiler='bundled LLVM14 cc1 / arm64-apple-ios15.0',initialFailed=True,rebuildPassed=True,machOObjectVerified=True,repeatNoChange=True,undoExact=True,staleRejected=True))
 root=base/'match-tests';root.mkdir();dfile=base/'matches.json'
 samples={
 'TF031':'duplicate symbol: _value\n>>> defined in A.o\n>>> defined in B.o',
 'TF032':"redefinition of 'Probe'",
 'TF033':"receiver type 'Probe' for instance message is a forward declaration",
 'TF034':'variable is not assignable (missing __block type specifier)',
 'TF035':"method definition for 'run' not found",
 'TF036':"'newAPI' is only available on iOS 16.0 or newer",
 'TF037':"non-portable path to file 'Real.h'; specified path differs in case from file name on disk",
 'TF038':"'GUARD_A' is used as a header guard here, followed by #define of a different macro",
 'TF039':'unterminated conditional directive',
 'TF040':'missing %end (%hook opened at Test.xm:1 extends to EOF)',
 'TF041':'%orig found outside of hook or subclass',
 'TF042':'non-initialized hook group: TestGroup',
 'TF043':'re-%init of %group TestGroup, first initialized at Test.xm:1',
 'TF044':'Cannot generate an autoconstructor with multiple %groups. Please explicitly create a constructor.',
 }
 for rule,message in samples.items():
  dfile.write_text(json.dumps([dict(file='Test.xm' if int(rule[2:])>=40 else 'Test.m',line=1,message=message)]))
  findings=cli('findings',root,dfile);assert rule in [f['id'] for f in findings],(rule,findings)
  assert cli('plan',root,dfile)==[]
 for message in ['control reaches end of non-void function','expected unqualified-id','architecture arm64','rootless','rootful','/var/jb/Library/Frameworks','RootHide','%hook Probe',"method definition for 'run' found"]:
  dfile.write_text(json.dumps([dict(file='Test.m',line=1,message=message)]));assert cli('findings',root,dfile)==[],(message,cli('findings',root,dfile))
 dfile.write_text(json.dumps([dict(file='Test.mm',line=1,message="'vector' file not found")]))
 assert 'TF012' not in [f['id'] for f in cli('findings',root,dfile)]
 dfile.write_text(json.dumps([dict(file='Test.m',line=1,message='Undefined symbols for architecture arm64')]))
 ids=[f['id'] for f in cli('findings',root,dfile)];assert 'TF008' not in ids and 'TF009' not in ids and 'TF026' not in ids
 # A second rejected/out-of-project Fix-It still makes the group a multi-edit group.
 (root/'Test.m').write_text('void g(id);\nvoid f(void){g("x");}\n');logpath=base/'multi.log'
 logpath.write_text(f'{root}/Test.m:2:16: error: string literal must be prefixed by \'@\'\nfix-it:"{root}/Test.m":{{2:16-2:16}}:"@"\nfix-it:"/external/header.h":{{1:1-1:1}}:"@"\n')
 assert cli('fixits',root,logpath,root)==[]
 # A fabricated hint inside a block comment must never edit source.
 source='/*\n"x"\n*/\n';(root/'Test.m').write_text(source);snap=base/'comment-snapshot';snap.mkdir();(snap/'Test.m').write_text(source)
 dfile.write_text(json.dumps([dict(file='Test.m',path=str(snap/'Test.m'),line=2,column=1,endLine=2,endColumn=1,replacement='@',message="string literal must be prefixed by '@'",compilerFixIt=True)]))
 assert cli('plan',root,dfile)==[]
 # Generate real bundled-Clang diagnostics for advisory families as well.
 advice_sources={
  'TF032':("int value;\nint value = 1;\nint value = 2;\n",()),
  'TF033':("@class Probe;\nvoid f(Probe *p) { [p run]; }\n",('-fobjc-arc',)),
  'TF034':("void f(void) { int value = 0; void (^b)(void) = ^{ value = 1; }; b(); }\n",()),
  'TF035':("@interface Probe\n- (void)run;\n@end\n@implementation Probe\n@end\n",()),
  'TF036':("void newAPI(void) __attribute__((availability(ios,introduced=16.0)));\nvoid f(void) { newAPI(); }\n",('-Wunguarded-availability',)),
  'TF038':('#include "Guard.h"\n',('-Wheader-guard',)),
  'TF039':('#if 1\nint value;\n',()),
 }
 (root/'RealHeader.h').write_text('int actual;\n')
 (root/'Guard.h').write_text('#ifndef PROBE_HEADER_H\n#define PROBE_HEADER_HH\nint guard_value;\n#endif\n')
 advice_results=[]
 for rule,(source,flags) in advice_sources.items():
  path=root/'Advisory.m';path.write_text(source);status,log=compile(path,flags=flags)
  dfile.write_text(json.dumps([dict(file=path.name,line=1,message=log)]))
  ids=[f['id'] for f in cli('findings',root,dfile)];assert rule in ids,(rule,log,ids)
  assert cli('plan',root,dfile)==[]
  (OUT/(rule+'-compiler.log')).write_text(log);advice_results.append(rule)
 # Real Logos parsing using bundled source; does not modify any user project.
 logos_cases={
 'TF040':'%hook Probe\n- (void)run { %orig; }\n',
 'TF041':'%orig;\n',
 'TF042':'%group G\n%hook Probe\n- (void)run { %orig; }\n%end\n%end\n%group H\n%hook Other\n- (void)run { %orig; }\n%end\n%end\n%ctor {\n %init(G);\n}\n',
 'TF043':'%group G\n%hook Probe\n- (void)run { %orig; }\n%end\n%end\n%ctor { %init(G); %init(G); }\n',
 'TF044':'%group G\n%hook Probe\n- (void)run { %orig; }\n%end\n%end\n',
 }
 for rule,source in logos_cases.items():
  path=root/'Test.xm';path.write_text(source)
  p=subprocess.run(['/usr/bin/perl',str(R/'Resources/logos/bin/logos.pl'),str(path)],env=dict(os.environ,LC_ALL='C',LC_CTYPE='C',LANG='C'),capture_output=True,text=True)
  log=p.stderr;dfile.write_text(json.dumps([dict(file='Test.xm',line=1,message=log)]));ids=[f['id'] for f in cli('findings',root,dfile)]
  assert rule in ids,(rule,log,ids)
  (OUT/(rule+'-logos.log')).write_text(log)
 (OUT/'results.json').write_text(json.dumps(dict(catalogEntries=44,newFixItFamilies=4,embeddedCompilerCases=results,adviceMatchingCases=len(samples),embeddedAdviceCases=advice_results,falseMatchCases=11,multiEditRejected=True,blockCommentRejected=True,logosParserCases=5),ensure_ascii=False,indent=2)+'\n')
 print('Upstream rules: 44 catalog entries; 7 actual embedded Clang14 repair/rebuild/undo cases; 14 advice matches; false-match guards; 5 real Logos cases passed')
