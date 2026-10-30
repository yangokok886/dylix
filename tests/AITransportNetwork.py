#!/usr/bin/env python3
"""Real URLSession against local protocol fixtures; never uses an API key."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from pathlib import Path
import json, subprocess, threading, time, base64, struct, zlib
def png_colors(encoded):
    """Decode the generated image pixels, never infer expected colors from prompt text."""
    data=base64.b64decode(encoded); offset=8; packed=b''
    while offset<len(data):
        length=struct.unpack('>I',data[offset:offset+4])[0]; kind=data[offset+4:offset+8]; chunk=data[offset+8:offset+8+length]
        if kind==b'IHDR': width,height,depth,color,*_=struct.unpack('>IIBBBBB',chunk)
        elif kind==b'IDAT': packed+=chunk
        offset+=length+12
    assert depth==8 and color in (2,6) and width==384 and height==256
    bpp=3 if color==2 else 4; stride=width*bpp; raw=zlib.decompress(packed); rows=[]; previous=bytearray(stride); offset=0
    def paeth(a,b,c):
        p=a+b-c; pa,pb,pc=abs(p-a),abs(p-b),abs(p-c)
        return a if pa<=pb and pa<=pc else b if pb<=pc else c
    for _ in range(height):
        filt=raw[offset]; offset+=1; row=bytearray(raw[offset:offset+stride]); offset+=stride
        for x in range(stride):
            left=row[x-bpp] if x>=bpp else 0; up=previous[x]; upper_left=previous[x-bpp] if x>=bpp else 0
            predictor=(0,left,up,(left+up)//2,paeth(left,up,upper_left))[filt]
            row[x]=(row[x]+predictor)&255
        rows.append(row); previous=row
    def name(x):
        r,g,b=rows[128][x*bpp:x*bpp+3]
        return 'yellow' if r>180 and g>150 else 'red' if r>180 else 'blue' if b>180 else 'green'
    return {'circle':name(98),'square':name(286)}
def image_data(value):
    if isinstance(value,dict):
        if value.get('type')=='image_url': return value['image_url']['url'].split(',',1)[1]
        if value.get('type')=='input_image': return value['image_url'].split(',',1)[1]
        if value.get('type')=='image': return value['source']['data']
        for child in value.values():
            found=image_data(child)
            if found:return found
    elif isinstance(value,list):
        for child in value:
            found=image_data(child)
            if found:return found
    return None
class Fixture(BaseHTTPRequestHandler):
    protocol_version='HTTP/1.1'
    def log_message(self,*args): pass
    def reply(self,body,code=200,kind='application/json'):
        raw=body if isinstance(body,bytes) else json.dumps(body).encode()
        self.send_response(code);self.send_header('Content-Type',kind);self.send_header('Content-Length',str(len(raw)));self.end_headers()
        try:self.wfile.write(raw)
        except (BrokenPipeError,ConnectionResetError):pass
    def do_GET(self):
        if '/paged/' in self.path:
            if 'after=' in self.path:self.reply({'data':[{'id':'page-b'}],'has_more':False})
            else:self.reply({'data':[{'id':'page-a'}],'has_more':True,'last_id':'page-a'})
        elif '/mixed/' in self.path:self.reply({'data':{'items':[{'id':'gpt-fixture'},{'id':'claude-fixture'},{'model':'gemini-fixture'},'deepseek-fixture',' qwen-fixture ','gpt-fixture']}})
        elif '/array/' in self.path:self.reply(['gpt-fixture','claude-fixture'])
        elif '/many/' in self.path:self.reply({'data':[{'id':'model-'+str(i)} for i in range(750)]})
        elif '/cursor/' in self.path:
            self.reply({'models':['cursor-b']} if 'cursor=' in self.path else {'models':['cursor-a'],'next_cursor':'cursor-a'})
        elif '/loop/' in self.path:self.reply({'data':[{'id':'repeat'}],'has_more':True,'last_id':'repeat'})
        elif '/foreign/' in self.path:self.reply({'data':[{'id':'local'}],'next':'https://other.example.test/v1/models'})
        else:self.reply({'data':[{'id':'fixture-a'},{'id':'fixture-b'},{'id':'fixture-a'}]})
    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))))
        model=body['model']
        if model in ['401','429','503']:self.reply({'error':{'message':'fixture private details should not escape'}},int(model));return
        if model=='redirect':
            self.send_response(307);self.send_header('Location','http://localhost:'+str(self.server.server_port)+'/must-not-arrive');self.send_header('Content-Length','0');self.end_headers();return
        if model=='slow':time.sleep(.8)
        stream=body.get('stream',False);tools=body.get('tools',[]);tool=bool(tools) and model!='no-tools'
        prompt=str(body)
        picture=image_data(body)
        content=json.dumps(png_colors(picture)) if picture else 'OK'
        if not stream:
            if self.path.endswith('/messages'):out={'type':'message','content':[{'type':'text','text':content}],'stop_reason':'end_turn'}
            elif self.path.endswith('/responses'):out={'object':'response','status':'completed','output':[{'type':'message','content':[{'type':'output_text','text':content}]}]}
            else:
                message={'role':'assistant','content':content}
                if tool:message['tool_calls']=[{'id':'probe-1','type':'function','function':{'name':'probe_ping','arguments':'{"value":"OK"}'}}]
                out={'choices':[{'index':0,'message':message,'finish_reason':'tool_calls' if tool else 'stop'}]}
            self.reply(out);return
        if self.path.endswith('/responses'):events=[{'type':'response.output_text.delta','sequence_number':1,'delta':content},{'type':'response.completed','sequence_number':2,'response':{'status':'completed','output':[]}}]
        elif self.path.endswith('/messages'):events=[{'type':'content_block_delta','index':0,'delta':{'type':'text_delta','text':content}},{'type':'message_stop'}]
        else:events=[{'choices':[{'index':0,'delta':{'content':content},'finish_reason':None}]},{'choices':[{'index':0,'delta':{},'finish_reason':'stop'}]}]
        if model=='interrupted':events=events[:1]
        raw=''.join('data: '+json.dumps(e)+'\n\n' for e in events).encode()
        if self.path.endswith('/completions') and model!='interrupted':raw+=b'data: [DONE]\n\n'
        self.reply(raw,kind='text/event-stream')
if __name__=='__main__':
    root=Path(__file__).resolve().parents[1]
    binary=Path('/private/tmp/tf-ai-transport-tests')
    subprocess.run(['xcrun','clang','-isysroot','/Library/Developer/CommandLineTools/SDKs/MacOSX15.2.sdk','-fobjc-arc','-fmodules','-DTFAI_TRANSPORT_TESTING=1',str(root/'tests/AITransportTests.m'),*[str(x) for x in (root/'App/AI/Providers').glob('*.m')],*[str(x) for x in (root/'App/AI/Transport').glob('*.m')],'-framework','Foundation','-framework','Security','-framework','CoreGraphics','-framework','ImageIO','-o',str(binary)],check=True)
    server=ThreadingHTTPServer(('127.0.0.1',0),Fixture)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    try:result=subprocess.run([str(binary),'http://127.0.0.1:'+str(server.server_port),'--ai-runtime-test'],check=False)
    finally:server.shutdown()
    raise SystemExit(result.returncode)
