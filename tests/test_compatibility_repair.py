import json,os,subprocess,tempfile
from pathlib import Path
CLI=os.environ.get('TMC_RULE_CLI','/private/tmp/tmc-compatibility-tests')
with tempfile.TemporaryDirectory() as name:
 root=Path(name);source='__weak typeof(self) weakSelf = self;\nconfig.payloadMode = [modeNum integerValue];\nstruct task_basic_info info;\n';(root/'Tweak.xm').write_text(source);snap=root/'snapshot';snap.write_text(source)
 diags=[dict(file='Tweak.xm',path=str(snap),line=i,message=m) for i,m in [(1,'expected unqualified-id'),(2,"assigning to 'AutoMessagePayloadMode' from incompatible type 'NSInteger' (aka 'long')"),(3,"variable has incomplete type 'struct task_basic_info'")]]
 f=root/'diagnostics.json';f.write_text(json.dumps(diags))
 def run(mode,ok=True):
  p=subprocess.run([CLI,mode,str(root),str(f)],capture_output=True,text=True);r=json.loads(p.stdout);assert (p.returncode==0)==ok,r;return r
 plan=run('plan')['plan'];assert len(plan)==1 and len(plan[0]['edits'])==3;assert (root/'Tweak.xm').read_text()==source
 run('apply');changed=(root/'Tweak.xm').read_text();assert '__typeof__(self)' in changed and '(AutoMessagePayloadMode)[modeNum integerValue]' in changed and changed.startswith('#include <mach/task_info.h>');assert (root/'.studio-repair-backup.json').exists()
 assert run('plan')['plan']==[] # stale diagnostics never rewrite edited source
 (root/'Tweak.xm').write_text(changed+'// edited after repair\n');run('undo',False);assert 'edited after repair' in (root/'Tweak.xm').read_text()
 (root/'Tweak.xm').write_text(changed);run('undo');assert (root/'Tweak.xm').read_text()==source
 # traversal, symlink and unknown diagnostics excluded
 outside=root/'outside';outside.write_text(source);(root/'link.xm').symlink_to('/etc/passwd');f.write_text(json.dumps([dict(file='../Tweak.xm',path=str(snap),line=1,message='expected unqualified-id'),dict(file='link.xm',path=str(snap),line=1,message='expected unqualified-id'),dict(file='Tweak.xm',path=str(snap),line=1,message='unknown unrelated issue')]))
 assert run('plan')['plan']==[]
 print('CompatibilityRepair: preview/no-write, 3 rules, apply, stale rejection, undo conflict, exact undo, path checks passed')
