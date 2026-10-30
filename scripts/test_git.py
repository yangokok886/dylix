#!/usr/bin/env python3
"""Real Git DAG and smart HTTP round-trip tests; all repositories are temporary."""
import subprocess,json,tempfile,pathlib,os,threading,http.server,urllib.parse,time,base64
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'evidence/0.6.0-git';OUT.mkdir(parents=True,exist_ok=True)
exe='/private/tmp/tf-git-fixture'
subprocess.run(['xcrun','--sdk','macosx','clang','-fobjc-arc','-fmodules','-fmodules-cache-path=/private/tmp/tmc-rules-module-cache','-I'+str(ROOT/'Vendor/libgit2/include'),'-I'+str(ROOT/'App'),'-framework','Foundation','-framework','Security','-framework','CoreFoundation',str(ROOT/'tests/GitFixtureDriver.m'),str(ROOT/'App/GitService.m'),str(ROOT/'build/git-macos/libgit2.a'),'-liconv','-o',exe],check=True)
checks=[]
def check(value,label):
 assert value,label;checks.append(label)
def service(op,root,ok=True,**kw):
 p=subprocess.run([exe,op,str(root),json.dumps(kw),'--git-test'],text=True,capture_output=True,timeout=25);r=json.loads(p.stdout)
 if ok:assert not r['error'],(op,r)
 else:assert r['error'],(op,r)
 return r['result'] if ok else r['error']
def git(root,*args):return subprocess.check_output(['git','-C',str(root),*args],stderr=subprocess.DEVNULL,text=True).strip()
def write(root,file,text):(root/file).write_text(text)
def commit(root,message):git(root,'add','.');git(root,'-c','user.name=Test','-c','user.email=test@example.com','commit','-m',message)
with tempfile.TemporaryDirectory(prefix='tf-git-integration-') as tmp:
 p=pathlib.Path(tmp);serverroot=p/'server';serverroot.mkdir();bare=serverroot/'repo.git';subprocess.run(['git','init','--bare','--initial-branch=main',str(bare)],check=True,capture_output=True);git(bare,'config','http.receivepack','true')
 seed=p/'seed';seed.mkdir();git(seed,'init','--initial-branch=main');write(seed,'file.m','int value = 1;\n');write(seed,'.gitignore','.studio-*\n*.o\n');commit(seed,'base');git(seed,'remote','add','origin',str(bare));git(seed,'push','origin','main')
 class Handler(http.server.BaseHTTPRequestHandler):
  auth=False;auth_hits=0;reject=False
  def do_GET(self):self.handle_git()
  def do_POST(self):self.handle_git()
  def log_message(self,*args):pass
  def handle_git(self):
   if type(self).auth:
    expected='Basic '+base64.b64encode(b'test:fixture-token').decode()
    if self.headers.get('Authorization')!=expected:
     type(self).auth_hits+=1;self.send_response(401);self.send_header('WWW-Authenticate','Basic realm="fixture"');self.send_header('Content-Length','0');self.end_headers();return
   parts=urllib.parse.urlsplit(self.path);length=int(self.headers.get('Content-Length','0'));body=self.rfile.read(length)
   if self.headers.get('Transfer-Encoding','').lower()=='chunked':
    chunks=[]
    while True:
     size=int(self.rfile.readline().strip().split(b';')[0],16)
     if not size:
      self.rfile.readline();break
     chunks.append(self.rfile.read(size));self.rfile.read(2)
    body=b''.join(chunks);length=len(body)
   env={**os.environ,'GIT_PROJECT_ROOT':str(serverroot),'GIT_HTTP_EXPORT_ALL':'1','PATH_INFO':parts.path,'QUERY_STRING':parts.query,'REQUEST_METHOD':self.command,'CONTENT_TYPE':self.headers.get('Content-Type',''),'CONTENT_LENGTH':str(length),'REMOTE_USER':'test'}
   r=subprocess.run(['git','http-backend'],input=body,capture_output=True,env=env);head,_,data=r.stdout.partition(b'\r\n\r\n');headers=[];code=200
   for line in head.decode().splitlines():
    key,_,value=line.partition(':')
    if key.lower()=='status':code=int(value.strip().split()[0])
    elif key:headers.append((key,value.strip()))
   self.send_response(code)
   for k,v in headers:self.send_header(k,v)
   self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start();url=f'http://127.0.0.1:{server.server_port}/repo.git';a=p/'cloneA';b=p/'cloneB'
 service('clone',a,url=url);check(git(a,'rev-parse','HEAD')==git(seed,'rev-parse','HEAD'),'smart HTTP clone preserves HEAD')
 service('clone',b,url=url);write(a,'file.m','int value = 2;\n');service('stage',a,paths=['file.m']);service('commit',a,message='from A');service('network',a,action='push');check(git(bare,'rev-parse','main')==git(a,'rev-parse','HEAD'),'smart HTTP push updates remote branch')
 old=git(b,'rev-parse','HEAD');service('network',b,action='fetch');check(git(b,'rev-parse','HEAD')==old,'fetch leaves worktree HEAD unchanged');check(service('status',b)['behind']==1,'ahead/behind reflects fetched commit');service('network',b,action='pull');check((b/'file.m').read_text()=='int value = 2;\n','pull fast-forwards worktree')
 write(b,'untracked.m','new\n');check('修改' in service('network',b,ok=False,action='pull'),'dirty pull rejected');(b/'untracked.m').unlink()
 write(a,'file.m','int value = 3;\n');service('stage',a,paths=['file.m']);service('commit',a,message='A conflict');service('network',a,action='push');write(b,'file.m','int value = 4;\n');service('stage',b,paths=['file.m']);service('commit',b,message='B conflict');check(service('network',b,ok=False,action='push'),'non fast-forward push rejected');service('network',b,action='pull');conflicts=service('conflicts',b);check(len(conflicts)==1,'divergent pull yields explicit conflict');check(service('status',b)['merging'],'merge state visible')
 c=conflicts[0];write(b,'file.m','modified after preview\n');check(service('resolve',b,ok=False,path=c['path'],choice='ours',fingerprint=c['fingerprint']),'stale conflict preview rejected');c=service('conflicts',b)[0];service('resolve',b,path=c['path'],choice='manual',text='int value = 5;\n',fingerprint=c['fingerprint']);check(not service('conflicts',b),'manual resolution clears index conflicts');service('commit',b,message='Merge A and B');check(len(git(b,'rev-list','--parents','-n','1','HEAD').split())==3,'merge commit has two parents');service('network',b,action='push');check(git(bare,'rev-parse','main')==git(b,'rev-parse','HEAD'),'resolved merge pushes')
 # Local divergent branches and abort backups.
 service('network',a,action='pull');service('branch',a,name='feature',action='create');service('branch',a,name='feature',action='switch');write(a,'file.m','feature\n');service('stage',a,paths=['file.m']);service('commit',a,message='feature');service('branch',a,name='main',action='switch');write(a,'file.m','main\n');service('stage',a,paths=['file.m']);service('commit',a,message='main');service('merge',a,name='feature');check(len(service('conflicts',a))==1,'local branch merge yields conflict');service('abort',a);check((a/'file.m').read_text()=='main\n','abort restores pre-merge HEAD');check(any(a.glob('.studio-git-merge-backup-*/file.m')),'abort preserves conflicted workfile backup');check(not service('status',a)['merging'],'abort cleans merge state')
 service('merge',a,name='feature');c=service('conflicts',a)[0];service('resolve',a,path=c['path'],choice='theirs',fingerprint=c['fingerprint']);check((a/'file.m').read_text()=='feature\n','theirs conflict choice uses exact blob');service('commit',a,message='local merge')
 # Full revision restore leaves index intact, checks stale paths, and undoes all files.
 before=git(a,'rev-parse','HEAD');write(a,'file.m','uncommitted source\n');write(a,'new-file.m','new source\n');index_before=git(a,'write-tree');plan=service('revisionPreview',a,revision=git(a,'rev-list','--max-parents=0','HEAD'));check(len(plan['files'])==2,'whole revision preview includes modified and untracked files');write(a,'new-file.m','stale\n');service('restore',a,ok=False,**plan);check((a/'file.m').read_text()=='uncommitted source\n','stale revision preview causes no partial restore');write(a,'new-file.m','new source\n');plan=service('revisionPreview',a,revision=git(a,'rev-list','--max-parents=0','HEAD'));service('restore',a,**plan);check(not (a/'new-file.m').exists() and (a/'file.m').read_text()=='int value = 1;\n','whole revision restores exact content and removes new file');check(git(a,'write-tree')==index_before,'revision checkpoint does not change staged index');service('undo',a);check((a/'file.m').read_text()=='uncommitted source\n' and (a/'new-file.m').read_text()=='new source\n','whole revision undo restores both files');check(any('Before revision restore' in c['message'] for c in service('history',a)),'restore checkpoint visible in history');git(a,'reset','--hard','HEAD');(a/'new-file.m').unlink()
 # Server hook rejection must never be reported as success.
 hook=bare/'hooks/pre-receive';hook.write_text('#!/bin/sh\necho fixture-rejected >&2\nexit 1\n');hook.chmod(0o755);service('network',a,action='fetch');service('branch',a,name='rejected',action='create');service('branch',a,name='rejected',action='switch');check('服务器拒绝' in service('network',a,ok=False,action='push'),'server-side push rejection surfaced');hook.unlink()
 # Cancellation removes partial clone, and auth rejection terminates promptly.
 cancel=p/'cancel';service('clone',cancel,ok=False,url=url,cancel=True);check(not cancel.exists(),'cancelled clone removes partial target');Handler.auth=True;start=time.monotonic();service('clone',p/'auth',ok=False,url=url);check(time.monotonic()-start<10,'missing auth returns promptly');check(Handler.auth_hits>0,'HTTP auth challenge exercised')
 server.shutdown()
(OUT/'integration.json').write_text(json.dumps({'passed':len(checks),'checks':checks},ensure_ascii=False,indent=2));print(f'Git integration: {len(checks)} checks passed')
