"""Production repair library: verified rule gates, byte fix-its, configuration, selection, history."""
import json,os,subprocess,tempfile
from pathlib import Path
R=Path(__file__).resolve().parents[1];CLI=os.environ.get('TMC_RULE_CLI','/private/tmp/tmc-compatibility-tests')
with tempfile.TemporaryDirectory() as tmp:
 base=Path(tmp);root=base/'project';root.mkdir();snapshot=base/'snapshot';snapshot.mkdir()
 catalog=json.loads((R/'Resources/CompatibilityRules/rules.json').read_text())
 assert len(catalog['rules'])>=26 and len({r['id'] for r in catalog['rules']})==len(catalog['rules'])
 # Validation staging uses test-only metadata. Release gate promoted only after this passes.
 for r in catalog['rules']:
  if r['id'] in ['TF004','TF005']:r['validation']['status']='verified'
 rules=base/'rules.json';rules.write_text(json.dumps(catalog));env=dict(os.environ,TMC_RULES_PATH=str(rules))
 def write(file,text):
  for directory in [root,snapshot]:
   path=directory/file;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(text)
 def invoke(mode,arg,selection=None,ok=True):
  cmd=[CLI,mode,str(root),str(arg)]
  if selection is not None:cmd.append(str(selection))
  result=subprocess.run(cmd,env=env,capture_output=True,text=True);r=json.loads(result.stdout);assert (result.returncode==0)==ok,(result.stderr,r);return r['plan']
 def diagnostics(items):
  p=base/'diagnostics.json';p.write_text(json.dumps(items));return p
 def fixit(source,line,col,endline,endcol,replacement=';',message="expected ';' after top level declarator"):
  path=snapshot/'Test.c';log=base/'build.log';log.write_text(f'{path}:{line}:{col}: error: {message}\nfix-it:{json.dumps(str(path))}:{{{line}:{col}-{endline}:{endcol}}}:{json.dumps(replacement)}\n');return invoke('fixits',log,snapshot)
 # UTF8 byte column, exact half-open insertion. Non-ASCII preceding code is preserved.
 source='const char *title = "中文"\n';write('Test.c',source);col=len(source.rstrip('\n').encode())+1
 f=diagnostics(fixit(source,1,col,1,col));plan=invoke('plan',f);assert len(plan)==1 and plan[0]['after']=='const char *title = "中文";\n'
 invoke('apply',f);assert (root/'Test.c').read_text()==plan[0]['after'];assert invoke('plan',f)==[]
 history=list((root/'.studio-repair-history').glob('*.json'));assert len(history)==1
 build=base/'build';build.mkdir();(build/'build.log').write_text('build successful');(build/'report.json').write_text('{"success":true}')
 invoke('rebuild',build);record=json.loads(history[0].read_text());assert record['beforeDiagnostics']['diagnostics'] and record['afterDiagnostics']['report']['success']
 invoke('undo',f);assert (root/'Test.c').read_text()==source
 # Invalid ranges, unsupported replacement, wrong diagnostic, macro/comment sources, stale snapshots.
 for args in [(1,999,1,999,';',"expected ';'"),(1,2,1,3,';',"expected ';'"),(1,1,1,1,'int',"expected ';'"),(1,col,1,col,';','unknown type')]:
  assert invoke('plan',diagnostics(fixit(source,*args)))==[]
 for text in ['#define FOO int a\n','int a // comment\n','int a /* comment */\n']:
  write('Test.c',text);c=len(text.rstrip('\n').encode())+1;assert invoke('plan',diagnostics(fixit(text,1,c,1,c)))==[]
 # Macro expansion notes are rejected even if a single precise range was emitted.
 write('Test.c','int a\n');path=snapshot/'Test.c';log=base/'macro.log';log.write_text(f'{path}:1:6: error: expected semicolon\nfix-it:"{path}":{{1:6-1:6}}:";"\n{path}:1:1: note: expanded from macro FOO\n');assert invoke('fixits',log,snapshot)==[]
 # Unique existing header produces a configuration edit, never a fabricated file.
 write('Test.c','#include "Actual.h"\n');write('Vendor/Headers/Actual.h','int actual(void);\n');write('MobileCompiler.json','{"sources":["Test.c"],"includeDirectories":[]}')
 d=dict(file='Test.c',path=str(snapshot/'Test.c'),line=1,message="'Actual.h' file not found")
 f=diagnostics([d]);plan=invoke('plan',f);assert len(plan)==1 and plan[0]['file']=='MobileCompiler.json';assert plan[0]['edits'][0]['kind']=='configuration'
 # Exact preview includes its source/header prerequisites. New dependency edits reject application.
 preview=base/'preview.json';preview.write_text(json.dumps(plan));(root/'Vendor/Headers/Actual.h').write_text('// edited dependency\n');invoke('apply-plan',preview,ok=False);assert json.loads((root/'MobileCompiler.json').read_text())['includeDirectories']==[]
 (root/'Vendor/Headers/Actual.h').write_text('int actual(void);\n')
 invoke('apply',f);assert json.loads((root/'MobileCompiler.json').read_text())['includeDirectories']==['Vendor/Headers'];assert invoke('plan',f)==[]
 invoke('undo',f);assert json.loads((root/'MobileCompiler.json').read_text())['includeDirectories']==[]
 write('Other/Actual.h','int other(void);\n');assert invoke('plan',f)==[];assert any(x['id']=='TF007' for x in invoke('findings',f));(root/'Other/Actual.h').unlink()
 f=diagnostics([{**d,'message':"'Missing.h' file not found"}]);assert invoke('plan',f)==[];assert any(x['id']=='TF006' for x in invoke('findings',f))
 f=diagnostics([d]);(root/'MobileCompiler.json').write_text('{"sources":[]}');assert invoke('plan',f)==[]
 # Partial selection: original three independent rules recomposed against exact original positions.
 source='__weak typeof(self) weakSelf = self;\nconfig.payloadMode = [modeNum integerValue];\nstruct task_basic_info info;\n';write('Tweak.xm',source)
 ds=[dict(file='Tweak.xm',path=str(snapshot/'Tweak.xm'),line=i,message=m) for i,m in [(1,'expected unqualified-id'),(2,"assigning to 'Mode' from incompatible type 'NSInteger'"),(3,"variable has incomplete type 'struct task_basic_info'")]]
 f=diagnostics(ds);plan=invoke('plan',f);assert len(plan[0]['edits'])==3
 selected=base/'selection.json';selected.write_text(json.dumps([e['id'] for e in plan[0]['edits'] if e['ruleID']=='TF001']))
 partial=invoke('plan',f,selected);assert '__typeof__' in partial[0]['after'] and '#include' not in partial[0]['after'] and '(Mode)' not in partial[0]['after']
 invoke('apply',f,selected);invoke('undo',f);assert (root/'Tweak.xm').read_text()==source
 # False matches: comments, different statements, unknown types, no actual Mach reference.
 write('Tweak.xm','// unrelated\n');f=diagnostics([dict(file='Tweak.xm',path=str(snapshot/'Tweak.xm'),line=1,message="variable has incomplete type 'struct task_basic_info'")]);assert invoke('plan',f)==[]
 write('Tweak.xm','/*\n__weak typeof(self) weakSelf = self;\nstruct task_basic_info info;\n*/\n');f=diagnostics([dict(file='Tweak.xm',path=str(snapshot/'Tweak.xm'),line=2,message='expected unqualified-id'),dict(file='Tweak.xm',path=str(snapshot/'Tweak.xm'),line=3,message="variable has incomplete type 'struct task_basic_info'")]);assert invoke('plan',f)==[]
 # Multi-Fix-It diagnostic groups are excluded.
 write('Test.c','int a\n');path=snapshot/'Test.c';log=base/'multi.log';log.write_text(f'{path}:1:6: error: expected \';\'\nfix-it:"{path}":{{1:6-1:6}}:";"\nfix-it:"{path}":{{1:1-1:1}}:";"\n');assert invoke('fixits',log,snapshot)==[]
 print(f'Rule library: {len(catalog["rules"])} metadata entries; UTF8 Fix-It, invalid ranges, dependency ambiguity, config snapshot, partial selection, repeat, undo and history passed')
