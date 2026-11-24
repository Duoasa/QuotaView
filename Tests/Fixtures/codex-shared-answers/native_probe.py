import os, json, socket, struct, base64, subprocess, tempfile, time, threading, sys
from pathlib import Path
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
evidence = Path(sys.argv[1] if len(sys.argv) > 1 else '.build/shared-answers-native')
evidence.mkdir(parents=True, exist_ok=True)
root=Path(tempfile.mkdtemp(prefix='qv-shared-native-',dir='/private/tmp'));os.chmod(root,0o700)
class WS:
 def __init__(self,path):
  self.s=socket.socket(socket.AF_UNIX);self.s.settimeout(12);self.s.connect(str(path));self.i=0
  key=base64.b64encode(os.urandom(16)).decode();self.s.sendall(f'GET /rpc HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: {key}\r\n\r\n'.encode())
  h=b''
  while not h.endswith(b'\r\n\r\n'):h+=self.s.recv(1)
  assert b'101' in h,h
 def send(self,o):
  b=json.dumps(o).encode();n=len(b);m=os.urandom(4)
  h=bytes([0x81,0x80|n]) if n<126 else bytes([0x81,0xfe])+struct.pack('!H',n) if n<65536 else bytes([0x81,0xff])+struct.pack('!Q',n)
  self.s.sendall(h+m+bytes(v^m[i%4] for i,v in enumerate(b)))
 def read(self,n):
  b=b''
  while len(b)<n:
   chunk=self.s.recv(n-len(b))
   if not chunk:raise EOFError()
   b+=chunk
  return b
 def recv(self):
  a,b=self.read(2);n=b&127
  if n==126:n=struct.unpack('!H',self.read(2))[0]
  elif n==127:n=struct.unpack('!Q',self.read(8))[0]
  if b&128:m=self.read(4)
  body=self.read(n)
  if a&15==8:raise EOFError()
  if a&15!=1:return self.recv()
  return json.loads(body)
 def rpc(self,method,params):
  self.i+=1;i=self.i;self.send({'id':i,'method':method,'params':params})
  while True:
   x=self.recv()
   if x.get('id')==i and 'method' not in x:
    if 'error'in x:raise RuntimeError(x['error'])
    return x['result']
 def init(self,experimental=False):
  r=self.rpc('initialize',{'clientInfo':{'name':'quotaview_isolated_probe','version':'1'},'capabilities':{'experimentalApi':experimental}});self.send({'method':'initialized','params':{}});return r
hold=threading.Event();received=[]
class Backend(BaseHTTPRequestHandler):
 def log_message(self,*a):pass
 def do_POST(self):
  payload=json.loads(self.rfile.read(int(self.headers['Content-Length'])));received.append(payload)
  self.send_response(200);self.send_header('Content-Type','text/event-stream');self.end_headers()
  def event(obj):
   self.wfile.write(b'data: '+json.dumps(obj).encode()+b'\n\n');self.wfile.flush()
  event({'type':'response.created','response':{'id':'fixture-response'}})
  if len(received)==1:
   item={'type':'function_call','id':'fc_fixture','call_id':'fixture-call','name':'request_user_input_async','arguments':json.dumps({'questions':[{'title':'Fixture choice?','options':['A','B']}]})}
   event({'type':'response.output_item.added','output_index':0,'item':item})
   event({'type':'response.output_item.done','output_index':0,'item':item})
   event({'type':'response.completed','response':{'id':'fixture-response','output':[item],'usage':{'input_tokens':1,'output_tokens':1,'total_tokens':2}}})
  else:hold.wait(20)
server=ThreadingHTTPServer(('127.0.0.1',0),Backend);threading.Thread(target=server.serve_forever,daemon=True).start()
cli='/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex'
catalog=json.loads((Path.home() / '.codex/models_cache.json').read_text())['models'][0]
catalog.update({'slug':'fixture-model','prefer_websockets':False,'use_responses_lite':False,'experimental_supported_tools':['request_user_input_async']})
(root/'models.json').write_text(json.dumps({'models':[catalog]}))
config={'model_catalog_json':str(root/'models.json'),'model_provider':'qv_fixture','model':'fixture-model','model_providers.qv_fixture':{'name':'Local fixture','base_url':f'http://127.0.0.1:{server.server_port}/v1','wire_api':'responses','requires_openai_auth':False},'mcp_servers':{},'plugins':{},'log_dir':str(root/'logs'),'sqlite_home':str(root/'sqlite'),'history.persistence':'none','analytics.enabled':False,'feedback.enabled':False,'features.memories':False,'hooks':{}}
# TOML inline values, not shell interpolation.
def toml(v):
 if isinstance(v,dict):return '{'+','.join(json.dumps(k)+'='+toml(x) for k,x in v.items())+'}'
 return json.dumps(v)
args=[cli]
for k,v in config.items():args+=['-c',k+'='+toml(v)]
args+=['app-server','--listen','unix://'+str(root/'server.sock')]
fixture_environment = dict(os.environ)
(root/'fixture-codex-home').mkdir(mode=0o700)
fixture_environment['CODEX_HOME'] = str(root/'fixture-codex-home')
log=(root/'server.log').open('wb');p=subprocess.Popen(args,stdin=subprocess.DEVNULL,stdout=log,stderr=log,env=fixture_environment)
try:
 for _ in range(600):
  if (root/'server.sock').exists():break
  if p.poll()is not None:raise RuntimeError('server failed '+(root/'server.log').read_text()[-1500:])
  time.sleep(.05)
 print('socket ready',root,flush=True)
 owner=WS(root/'server.sock');owner.init(True);observer=WS(root/'server.sock');observer.init()
 compatibility=WS(root/'server.sock')
 compatibility.rpc('initialize',{'clientInfo':{'name':'quotaview','title':'QuotaView','version':'0.9.7'},'capabilities':{'optOutNotificationMethods':['turn/diff/updated','item/agentMessage/delta','item/plan/delta','item/reasoning/summaryTextDelta','item/reasoning/summaryPartAdded','item/reasoning/textDelta','item/commandExecution/outputDelta','item/fileChange/outputDelta','command/exec/outputDelta','hook/started','hook/completed']}})
 compatibility.send({'method':'initialized','params':{}});print('native initialize shape accepted',flush=True)
 result=owner.rpc('thread/start',{'modelProvider':'qv_fixture','model':'fixture-model','cwd':str(root),'ephemeral':False,'historyMode':'paginated','approvalPolicy':'never','sandbox':'read-only','baseInstructions':'Isolated transport probe. Do not execute tools.','developerInstructions':'Use only the local mock backend.'})
 tid=result['thread']['id'];print('isolated persisted thread created',flush=True)
 turn=owner.rpc('turn/start',{'threadId':tid,'input':[{'type':'text','text':'transport probe','text_elements':[]}]})['turn']['id']
 question=None
 for _ in range(100):
  full=observer.rpc('thread/read',{'threadId':tid,'includeTurns':True})
  latest=full['thread']['turns'][-1]
  for item in latest['items']:
   if item.get('questions'):question=item
  if question:break
  if latest['status']!='inProgress':raise RuntimeError('fixture completed without a native question')
  time.sleep(.05)
 assert question,'native question was not emitted'
 print('native question emitted',question['id'],'source',full['thread']['source'],flush=True)
 assert latest['id']==turn
 loaded=observer.rpc('thread/loaded/list',{'limit':100})['data'];assert tid in loaded
 rd=observer.rpc('thread/read',{'threadId':tid,'includeTurns':False});print('shared read status',rd['thread']['status'],flush=True)
 try:observer.rpc('turn/steer',{'threadId':tid,'expectedTurnId':'wrong-turn','input':[{'type':'text','text':'must reject','text_elements':[]}]});raise AssertionError('wrong turn accepted')
 except RuntimeError:pass
 descriptor=root/'fixture.json';descriptor.write_text(json.dumps({'thread':tid,'turn':turn}))
 test_environment=dict(os.environ);test_environment['QV_SHARED_NATIVE_FIXTURE']=str(descriptor)
 with (evidence / 'native-client-tests.log').open('w') as output:
  tested=subprocess.run(['swift','test','--skip-build','--filter','SharedQuestionAnswerSmokeTests/testNativeIsolatedRuntimeQuestionAndAnswer'],env=test_environment,stdout=output,stderr=subprocess.STDOUT,timeout=30)
 assert tested.returncode==0,'native client test failed; see native-client-tests.log'
 receipt=False
 for _ in range(30):
  accepted=observer.rpc('thread/read',{'threadId':tid,'includeTurns':True})['thread']['turns'][-1]['items']
  receipt=any(i.get('type')=='userMessage' and any('<send_user_message_question_reply>' in c.get('text','') for c in i.get('content',[])) for i in accepted)
  if receipt:break
  time.sleep(.05)
 assert receipt, 'Original turn did not accept the question reply'
 print('QuotaView native client submitted; original turn receipt:',receipt,flush=True)
 owner.rpc('turn/interrupt',{'threadId':tid,'turnId':turn})
 summary={'nativeVersion':'bundled CLI','ephemeral':False,'sharedLoadedThread':True,'sameTurnSteer':True,'nativeQuestionEmitted':True,'quotaViewClientUsed':True,'acceptedReplyReceipt':receipt,'wrongTurnRejected':True,'modelBackend':'127.0.0.1 fixture only','modelRequests':len(received),'root':str(root)}
 (evidence / 'native-probe-result.json').write_text(json.dumps(summary,indent=2)+'\n')
finally:
 hold.set();p.terminate()
 try:p.wait(5)
 except subprocess.TimeoutExpired:p.kill();p.wait()
 server.shutdown();log.close()
