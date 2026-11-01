from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import json,subprocess,sys,threading,time
root=Path(sys.argv[1]);config=root/'config';config.mkdir(exist_ok=True)
work=root/'work';work.mkdir(exist_ok=True)
requests=[]
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*args): pass
 def do_POST(self):
  obj=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))));requests.append({'path':self.path,'model':obj.get('model')})
  if obj.get('stream'):
   self.send_response(200);self.send_header('Content-Type','text/event-stream');self.end_headers()
   chunks=[{'id':'fixture','object':'chat.completion.chunk','created':1,'model':'fixture','choices':[{'index':0,'delta':{'role':'assistant','content':'QUOTAVIEW_LOCAL_SMOKE_OK'},'finish_reason':None}]},
   {'id':'fixture','object':'chat.completion.chunk','created':1,'model':'fixture','choices':[{'index':0,'delta':{},'finish_reason':'stop'}],'usage':{'prompt_tokens':1,'completion_tokens':1,'total_tokens':2}}]
   for c in chunks: self.wfile.write(('data: '+json.dumps(c)+'\n\n').encode());self.wfile.flush();time.sleep(.1)
   self.wfile.write(b'data: [DONE]\n\n');self.wfile.flush()
  else:
   self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers()
   self.wfile.write(json.dumps({'id':'fixture','object':'chat.completion','created':1,'model':'fixture','choices':[{'index':0,'message':{'role':'assistant','content':'QUOTAVIEW_LOCAL_SMOKE_OK'},'finish_reason':'stop'}],'usage':{'prompt_tokens':1,'completion_tokens':1,'total_tokens':2}}).encode())
server=ThreadingHTTPServer(('127.0.0.1',0),Handler);threading.Thread(target=server.serve_forever,daemon=True).start()
configuration={'$schema':'https://opencode.ai/config.json','model':'quotaview-fixture/fixture','small_model':'quotaview-fixture/fixture','autoupdate':False,'share':'disabled','snapshot':False,'enabled_providers':['quotaview-fixture'],'provider':{'quotaview-fixture':{'npm':'@ai-sdk/openai-compatible','name':'QuotaView Local Fixture','options':{'baseURL':f'http://127.0.0.1:{server.server_port}/v1'},'models':{'fixture':{'name':'Fixture','limit':{'context':32000,'output':1000}}}}}}
(config/'opencode.json').write_text(json.dumps(configuration))
env={'PATH':'/usr/bin:/bin:/opt/homebrew/bin','OPENCODE_TEST_HOME':str(root/'home'),'OPENCODE_DISABLE_AUTOUPDATE':'1','OPENCODE_DISABLE_MODELS_FETCH':'1','OPENCODE_DISABLE_PROJECT_CONFIG':'1','OPENCODE_CONFIG_DIR':str(config),'NO_COLOR':'1'}
for kind in ['CONFIG','DATA','CACHE','STATE']:
 d=root/kind.lower();d.mkdir(exist_ok=True);env['XDG_'+kind+'_HOME']=str(d)
client=str(Path('.build/agent-usable-087b31/client/opencode').resolve())
try:
 with (root/'client.log').open('w') as out:
  completed=subprocess.run([client,'run','--format','json','Reply exactly QUOTAVIEW_LOCAL_SMOKE_OK'],cwd=work,env=env,stdout=out,stderr=out,timeout=45)
 print(json.dumps({'exit':completed.returncode,'requests':requests,'log':str(root/'client.log')}))
 sys.exit(completed.returncode)
finally: server.shutdown()
