#!/usr/bin/env python3
"""Authenticated smart-HTTP round trip inside the iOS application + Keychain."""
import http.server,threading,tempfile,pathlib,subprocess,os,urllib.parse,base64,json,time
R=pathlib.Path(__file__).resolve().parents[1];OUT=R/'evidence/0.6.0-git';OUT.mkdir(parents=True,exist_ok=True);B='com.xuegao.theosmobilecompiler'
def run(*args):return subprocess.check_output(args,text=True,stderr=subprocess.DEVNULL).strip()
with tempfile.TemporaryDirectory(prefix='tf-git-ios-http-') as tmp:
 root=pathlib.Path(tmp);bare=root/'repo.git';run('git','init','--bare','--initial-branch=main',str(bare));run('git','-C',str(bare),'config','http.receivepack','true');seed=root/'seed';seed.mkdir();run('git','-C',str(seed),'init','--initial-branch=main');(seed/'test.m').write_text('int example = 1;\n');run('git','-C',str(seed),'add','.');run('git','-C',str(seed),'-c','user.name=Test','-c','user.email=test@example.com','commit','-m','base');run('git','-C',str(seed),'remote','add','origin',str(bare));run('git','-C',str(seed),'push','origin','main')
 class Handler(http.server.BaseHTTPRequestHandler):
  passed=0;rejected=0
  def do_GET(self):self.serve()
  def do_POST(self):self.serve()
  def log_message(self,*args):pass
  def serve(self):
   expected='Basic '+base64.b64encode(b'test:fixture-token').decode()
   if self.headers.get('Authorization')!=expected:
    type(self).rejected+=1;self.send_response(401);self.send_header('WWW-Authenticate','Basic realm="Git iOS fixture"');self.send_header('Content-Length','0');self.end_headers();return
   type(self).passed+=1;parts=urllib.parse.urlsplit(self.path);body=self.rfile.read(int(self.headers.get('Content-Length','0')))
   if self.headers.get('Transfer-Encoding','').lower()=='chunked':
    chunks=[]
    while True:
     n=int(self.rfile.readline().strip().split(b';')[0],16)
     if not n:self.rfile.readline();break
     chunks.append(self.rfile.read(n));self.rfile.read(2)
    body=b''.join(chunks)
   env={**os.environ,'GIT_PROJECT_ROOT':str(root),'GIT_HTTP_EXPORT_ALL':'1','PATH_INFO':parts.path,'QUERY_STRING':parts.query,'REQUEST_METHOD':self.command,'CONTENT_TYPE':self.headers.get('Content-Type',''),'CONTENT_LENGTH':str(len(body)),'REMOTE_USER':'test'}
   p=subprocess.run(['git','http-backend'],env=env,input=body,capture_output=True);head,_,data=p.stdout.partition(b'\r\n\r\n');headers=[];code=200
   for line in head.decode().splitlines():
    k,_,v=line.partition(':')
    if k.lower()=='status':code=int(v.strip().split()[0])
    elif k:headers.append((k,v.strip()))
   self.send_response(code)
   for k,v in headers:self.send_header(k,v)
   self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
 server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start();url=f'http://127.0.0.1:{server.server_port}/repo.git'
 run('xcrun','simctl','install','booted',str(R/'build/simulator/TheosMobileCompiler.app'));doc=pathlib.Path(run('xcrun','simctl','get_app_container','booted',B,'data'))/'Documents';report=doc/'git-ui-test.json'
 if report.exists():report.unlink()
 run('xcrun','simctl','launch','--terminate-running-process','booted',B,'--git-ui-test','--git-test','--git-auth-url',url,'--git-https-test')
 deadline=time.monotonic()+90
 while time.monotonic()<deadline and not report.exists():time.sleep(.3)
 assert report.exists(),'iOS application test did not finish';r=json.loads(report.read_text());assert all(r.get(key) for key in ['restore','undo','keychainSaved','keychainReadMatches','keychainDeleted','httpsClone','authCredentialSaved','authenticatedClone','authenticatedPush','wrongCredentialRejected']),r
 assert Handler.passed>=3 and Handler.rejected>=2
 r['serverAuthenticatedRequests']=Handler.passed;r['serverRejectedRequests']=Handler.rejected;r['remoteCommitMessage']=run('git','-C',str(bare),'log','-1','--format=%s');assert r['remoteCommitMessage']=='Authenticated iOS push';(OUT/'ios-runtime.json').write_text(json.dumps(r,ensure_ascii=False,indent=2));print('iOS Git: commit / diff / restore / undo / Keychain / HTTPS clone / authenticated clone+push / rejected token passed');server.shutdown()
