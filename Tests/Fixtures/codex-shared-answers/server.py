"""Isolated same-UID Unix WebSocket peer. All messages and answers are synthetic."""
import base64, hashlib, json, os, socket, struct, sys, threading
from pathlib import Path
root=Path(sys.argv[1]);listener=socket.socket(socket.AF_UNIX);listener.bind(str(root/'rpc.sock'));os.chmod(root/'rpc.sock',0o600);listener.listen(4)
def exact(s,n):
 b=b''
 while len(b)<n:
  chunk=s.recv(n-len(b))
  if not chunk:raise EOFError()
  b+=chunk
 return b
def send(s,o):
 b=json.dumps(o).encode();n=len(b)
 h=bytes([0x81,n]) if n<126 else b'\x81\x7e'+struct.pack('!H',n) if n<65536 else b'\x81\x7f'+struct.pack('!Q',n)
 s.sendall(h+b)
def serve(s):
 try:
  h=b''
  while not h.endswith(b'\r\n\r\n'):h+=exact(s,1)
  assert h.startswith(b'GET /rpc HTTP/1.1\r\n')
  key=next(x.split(b':',1)[1].strip() for x in h.split(b'\r\n') if x.lower().startswith(b'sec-websocket-key:'))
  accept=base64.b64encode(hashlib.sha1(key+b'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest())
  s.sendall(b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+accept+b'\r\n\r\n')
  while True:
   a,b=exact(s,2);n=b&127
   if n==126:n=struct.unpack('!H',exact(s,2))[0]
   elif n==127:n=struct.unpack('!Q',exact(s,8))[0]
   assert n<=2097152
   mask=exact(s,4) if b&128 else None;body=exact(s,n)
   if a&15==8:break
   if mask:body=bytes(v^mask[i%4] for i,v in enumerate(body))
   req=json.loads(body);method=req.get('method');params=req.get('params',{})
   with (root/'requests.jsonl').open('a') as f:f.write(json.dumps(req)+'\n')
   if 'id'not in req:continue
   state=json.loads((root/'state.json').read_text());turn=state.get('turn','turn');thread='conversation';source=state.get('source','vscode')
   metadata={'id':thread,'source':source,'status':{'type':'active','activeFlags':[]}}
   if method=='initialize':result={}
   elif method=='thread/loaded/list':result={'data':[] if state.get('unloaded') else [thread],'nextCursor':None}
   elif method in ['thread/resume','thread/read']:
    if params.get('includeTurns'):
     metadata['turns']=[{'id':turn,'status':'inProgress','items':[{'id':'call','type':'agentMessage','questions':[{'title':'Fixture choice?','options':['A','B']}]}]}]
    result={'thread':metadata}
   elif method=='thread/turns/list' and state.get('inlineOnly'):
    send(s,{'id':req['id'],'error':{'code':-32601,'message':'list_turns is not supported yet'}});continue
   elif method=='thread/turns/list':result={'data':[{'id':turn,'status':'completed' if state.get('terminal') else 'inProgress'}],'nextCursor':None}
   elif method=='thread/items/list':
    item={'id':state.get('call','call'),'type':'agentMessage','questions':[{'title':'Fixture choice?','options':['A','B']}]}
    if state.get('twoQuestions'):item['questions'].append({'title':'Second fixture?','options':['C','D']})
    items=[item]
    if state.get('answered'):
     qid=json.dumps(['request_user_input_async',item['id'],0],separators=(',',':'))
     text='<send_user_message_question_reply>\n'+json.dumps([{'questionItemId':qid,'question':'Fixture choice?','answer':'A'}])+'\n</send_user_message_question_reply>'
     items.append({'id':'reply','type':'userMessage','content':[{'type':'text','text':text}]})
    result={'data':[{'turnId':turn,'item':i} for i in items],'nextCursor':'repeating' if state.get('cursorLoop') else None}
   elif method=='turn/steer':
    if state.get('dropReply'):return
    if params['expectedTurnId']!=turn:
     send(s,{'id':req['id'],'error':{'code':-32602,'message':'turn mismatch'}});continue
    result={'turnId':'unexpected' if state.get('wrongAck') else turn}
   else:
    send(s,{'id':req['id'],'error':{'code':-32601,'message':'unknown method'}});continue
   send(s,{'id':req['id'],'result':result})
 except (EOFError,ConnectionError,OSError):pass
 finally:s.close()
while True:
 s,_=listener.accept();threading.Thread(target=serve,args=(s,),daemon=True).start()
