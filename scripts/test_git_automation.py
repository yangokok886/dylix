#!/usr/bin/env python3
"""Real libgit2 archive transactions. Uses only temporary repository copies."""
import pathlib, subprocess, tempfile, json, hashlib, os
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=ROOT/'evidence/0.6.3-git-automation'; OUT.mkdir(parents=True,exist_ok=True)
exe='/private/tmp/tf-git-auto-fixture'
subprocess.run(['xcrun','--sdk','macosx','clang','-fobjc-arc','-fmodules','-fmodules-cache-path=/private/tmp/tmc-rules-module-cache','-I'+str(ROOT/'Vendor/libgit2/include'),'-I'+str(ROOT/'App'),'-framework','Foundation','-framework','Security','-framework','CoreFoundation',str(ROOT/'tests/GitFixtureDriver.m'),str(ROOT/'App/GitService.m'),str(ROOT/'build/git-macos/libgit2.a'),'-liconv','-o',exe],check=True)
checks=[]
def check(v,label):
 assert v,label; checks.append(label)
def svc(op,root,fail=False,**args):
 p=subprocess.run([exe,op,str(root),json.dumps(args),'--git-test'],capture_output=True,text=True,timeout=30)
 value=json.loads(p.stdout)
 if fail: assert value['error'],(op,value);return value['error']
 assert not value['error'],(op,value,p.stderr)
 return value['result']
def git(root,*args):return subprocess.check_output(['git','-C',str(root),*args],stderr=subprocess.DEVNULL,text=True).strip()
def write(root,name,value):
 p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(value)
def archive(root,**args):return svc('archive',root,message='auto fixture',**args)
with tempfile.TemporaryDirectory(prefix='tf-archive-') as temp:
 unborn=pathlib.Path(temp)/'unborn';unborn.mkdir();svc('init',unborn);write(unborn,'first.m','int value=0;');protected_unborn=archive(unborn,protection=True);check(protected_unborn['status']=='committed','protection before initial branch commit');check(protected_unborn['id'] in [row['id'] for row in svc('history',unborn)],'unborn branch protection visible in history')
 root=pathlib.Path(temp)/'repo';root.mkdir();svc('init',root)
 write(root,'source.m','int value=1;\n');write(root,'control','Name: Fixture\n')
 first=archive(root);check(first['status']=='committed','unborn branch creates real commit');check(git(root,'status','--porcelain')=='','index agrees with new HEAD')
 check(archive(root)['status']=='unchanged','unchanged tree does not create empty commit')
 write(root,'source.m','int value=2;\n');write(root,'new.mm','int helper=1;\n');(root/'control').unlink()
 r=archive(root);check(r['status']=='committed','modified/new/deleted files archived');check('new.mm' in git(root,'ls-tree','--name-only','HEAD'),'new source included');check('control' not in git(root,'ls-tree','--name-only','HEAD'),'deletion included');check(git(root,'status','--porcelain')=='','ordinary archive leaves no staged reversal')
 write(root,'source.m','int value=3;\n');svc('stage',root,paths=['source.m']);write(root,'source.m','int value=4;\n');before=(root/'.git/index').read_bytes();head=git(root,'rev-parse','HEAD')
 error=svc('archive',root,fail=True,message='blocked');check('暂存区' in error,'partial staging pauses archive');check((root/'.git/index').read_bytes()==before,'paused archive preserves index byte-for-byte');check(git(root,'rev-parse','HEAD')==head,'paused archive preserves HEAD')
 protected=archive(root,protection=True);check(protected['status']=='committed','protection handles partial staged work without consuming it');check((root/'.git/index').read_bytes()==before,'protection preserves index bytes');check(git(root,'rev-parse','HEAD')==head,'protection does not move branch');check('int value=4;' in git(root,'show',protected['id']+':source.m'),'protection records disk version rather than staged version');check(archive(root,protection=True)['status']=='unchanged','repeated identical protection creates no duplicate');check(protected['id'] in [row['id'] for row in svc('history',root)],'protection visible in history')
 svc('stage',root,paths=['source.m'],remove=True);archive(root)
 (root/'new.mm').rename(root/'renamed.mm');check(archive(root)['status']=='committed','renamed source archives');check('new.mm' not in git(root,'ls-tree','--name-only','HEAD') and 'renamed.mm' in git(root,'ls-tree','--name-only','HEAD'),'rename leaves no duplicate old source')
 # Exclusions apply even when HEAD already tracks an artifact.
 write(root,'tracked.dylib','old');git(root,'add','-f','tracked.dylib');git(root,'-c','user.name=T','-c','user.email=t@example.org','commit','-m','tracked fixture')
 write(root,'tracked.dylib','new');write(root,'a.o','object');write(root,'.env','TOKEN=synthetic');write(root,'credentials.json','{"token":"synthetic"}');write(root,'build/cache.c','cache');write(root,'x.p12','synthetic');write(root,'scratch.tmp','temporary');write(root,'.studio-git-settings.json','{}')
 check(archive(root)['status']=='unchanged','only artifacts/secrets/local state produce no commit');check(git(root,'show','HEAD:tracked.dylib')=='old','tracked artifact changes excluded')
 write(root,'source.m','int value=5;\n');check(archive(root)['status']=='committed','source still archives beside excluded files');check(git(root,'show','HEAD:tracked.dylib')=='old','source commit does not include changed tracked artifact');check('.env' not in git(root,'ls-tree','-r','--name-only','HEAD'),'credential-like files excluded')
 write(root,'.gitignore',(root/'.gitignore').read_text()+'\nignored/\n');write(root,'ignored/hidden.m','ignored');archive(root);check('ignored/hidden.m' not in git(root,'ls-tree','-r','--name-only','HEAD'),'repository .gitignore respected')
 head=git(root,'rev-parse','HEAD');write(root,'source.m','int value=6;\n');write(root,'.git/MERGE_HEAD',head+'\n');check('特殊操作' in svc('archive',root,fail=True,message='merge'),'merge state pauses automation');(root/'.git/MERGE_HEAD').unlink()
 git(root,'checkout','--detach',head);check('分离 HEAD' in svc('archive',root,fail=True,message='detached'),'detached HEAD pauses automation');git(root,'checkout','main')
 check('提交者' in svc('archive',root,fail=True,message='identity',name='',email=''),'missing identity gives explicit error')

 # Failed ref/index writes must not leave a staged reversal or advance HEAD.
 oldhead=git(root,'rev-parse','HEAD');before=(root/'.git/index').read_bytes();write(root,'source.m','int value=rollback;\n');write(root,'.git/refs/heads/main.lock','fixture lock')
 check('自动存档失败' in svc('archive',root,fail=True,message='locked ref'),'locked branch ref returns explicit error');check((root/'.git/index').read_bytes()==before,'ref failure rolls index back byte-for-byte');check(git(root,'rev-parse','HEAD')==oldhead,'ref failure leaves HEAD unchanged');(root/'.git/refs/heads/main.lock').unlink()
 write(root,'.git/index.lock','fixture lock');svc('archive',root,fail=True,message='locked index');check((root/'.git/index').read_bytes()==before,'index lock failure preserves original index');check(git(root,'rev-parse','HEAD')==oldhead,'index lock failure leaves HEAD unchanged');(root/'.git/index.lock').unlink()
 archive(root)
 # Auto-push destination consent, independent switch, background and cooldown.
 bare=pathlib.Path(temp)/'remote.git';subprocess.run(['git','init','--bare','--initial-branch=main',str(bare)],capture_output=True,check=True)
 svc('remote',root,url=str(bare));archive_id=git(root,'rev-parse','HEAD')
 check('未启用' in svc('autoPush',root,id=archive_id)['push'],'auto-push defaults off independently of commits')
 svc('settings',root,push=True,pushURL=str(bare),pushBranch='wrong-branch')
 check('仓库或分支已变化' in svc('autoPush',root,id=archive_id)['push'],'changed branch consent blocks upload')
 svc('settings',root,push=True,pushURL=str(bare)+'-other',pushBranch='main')
 check('仓库或分支已变化' in svc('autoPush',root,id=archive_id)['push'],'changed URL consent blocks upload')
 svc('settings',root,push=True,pushURL=str(bare),pushBranch='main')
 check('后台' in svc('autoPush',root,id=archive_id,foreground=False)['push'],'background blocks automatic upload')
 check('分支已变化' in svc('autoPush',root,id='0'*40)['push'],'changed HEAD blocks stale automatic push')
 check(svc('autoPush',root,id=archive_id)['push']=='推送成功','approved local auto-push reaches real bare remote')
 check(git(bare,'rev-parse','main')==archive_id,'remote branch matches archived commit')
 write(root,'source.m','int value=7;\n');new_id=archive(root)['id'];bad=str(pathlib.Path(temp)/'missing.git');svc('remote',root,url=bad);svc('settings',root,push=True,pushURL=bad,pushBranch='main')
 check(svc('autoPush',root,id=new_id)['push']=='failed','network failure gives a stored failure result')
 check(git(root,'rev-parse','HEAD')==new_id,'network failure preserves local archive')
 svc('remote',root,url=str(bare));svc('settings',root,push=True,pushURL=str(bare),pushBranch='main')
 check('冷却' in svc('autoPush',root,id=new_id)['push'],'network failure prevents high-frequency retry')
 check(git(bare,'rev-parse','main')==archive_id,'cooldown makes no remote change')
 # Protection before file restore is tested separately by core regression.
 original=ROOT/'Resources/SampleObjectiveC';fingerprints={str(p.relative_to(original)):hashlib.sha256(p.read_bytes()).hexdigest() for p in original.rglob('*') if p.is_file()}
 copy=pathlib.Path(temp)/'copy';subprocess.run(['cp','-R',str(original),str(copy)],check=True);svc('init',copy);archive(copy);write(copy,'Additional.m','int copied=1;\n');archive(copy)
 check(fingerprints=={str(p.relative_to(original)):hashlib.sha256(p.read_bytes()).hexdigest() for p in original.rglob('*') if p.is_file()},'original fixture read-only; changes only in copy')
# Run real Theos source copies, auditing both content and original timestamps.
from test_local_projects import copy_sources
original=pathlib.Path(os.environ.get('DYLIX_TEST_PROJECT',str(ROOT/'fixtures/optional-local-project')))
if original.exists():
 def audit():return {str(p.relative_to(original)):(hashlib.sha256(p.read_bytes()).hexdigest(),p.stat().st_mtime_ns) for p in original.rglob('*') if p.is_file() and not p.is_symlink()}
 before=audit()
 with tempfile.TemporaryDirectory(prefix='tf-auto-theos-copy-') as temp:
  copy=pathlib.Path(temp);copied=copy_sources(original,copy);svc('init',copy);check(archive(copy)['status']=='committed','real AutoMessagePlugin source copy initial archive')
  source=copy/'AutoMessageManager.m';source.write_text(source.read_text()+'\n// Automatic archive test, temporary copy only\n')
  check(archive(copy)['status']=='committed','real Theos copy source modification archives');check(git(copy,'status','--porcelain')=='','real Theos copy index clean after archive')
 check(before==audit(),'彩虹编译 original content and modification timestamps unchanged')
report={'checks':checks,'count':len(checks),'result':'passed'};(OUT/'core-tests.json').write_text(json.dumps(report,ensure_ascii=False,indent=2));print(json.dumps(report,ensure_ascii=False,indent=2))
