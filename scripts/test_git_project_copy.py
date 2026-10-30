#!/usr/bin/env python3
"""Run Git workflows on a local Theos project copy; audit original read-only."""
import pathlib,tempfile,subprocess,json,hashlib,os
from test_local_projects import copy_sources
root=pathlib.Path(__file__).resolve().parents[1];original=pathlib.Path(os.environ.get('DYLIX_TEST_PROJECT',str(root/'fixtures/optional-local-project')));exe='/private/tmp/tf-git-fixture';out=root/'evidence/0.6.0-git';out.mkdir(parents=True,exist_ok=True)
def manifest():
 return {str(p.relative_to(original)):{'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'mtime_ns':p.stat().st_mtime_ns} for p in original.rglob('*') if p.is_file() and not p.is_symlink()}
def op(action,dest,**kw):
 p=subprocess.run([exe,action,str(dest),json.dumps(kw),'--git-test'],capture_output=True,text=True,check=True);r=json.loads(p.stdout);assert not r['error'],r;return r['result']
before=manifest()
with tempfile.TemporaryDirectory(prefix='tf-git-project-') as t:
 dest=pathlib.Path(t);copied=copy_sources(original,dest);op('init',dest);status=op('status',dest);paths=[f['path'] for f in status['files']];op('stage',dest,paths=paths);first=op('commit',dest,message='Read-only original copy baseline');source='AutoMessageManager.m';data=(dest/source).read_text();(dest/source).write_text(data+'\n// Git test copy only\n');status=op('status',dest);assert len(status['files'])==1 and status['files'][0]['path']==source;plan=op('restorePreview',dest,path=source,revision=first);op('restore',dest,**plan);assert (dest/source).read_text()==data;op('undo',dest);assert (dest/source).read_text().endswith('// Git test copy only\n');op('stage',dest,paths=[source]);op('commit',dest,message='Change in sandbox copy');assert len(op('history',dest))==2
 result={'project':str(original),'copiedFiles':len(copied),'trackedFiles':len(paths),'baselineCommit':first,'editRestoreUndoCommit':True,'originalFiles':len(before),'originalUnchanged':before==manifest()};assert result['originalUnchanged'];(out/'project-copy.json').write_text(json.dumps(result,ensure_ascii=False,indent=2));print(json.dumps(result,ensure_ascii=False))
