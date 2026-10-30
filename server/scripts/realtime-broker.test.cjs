// H3 integration against the deployed Centrifugo config (disposable container).
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const root = process.env.BROKER_URL || 'http://127.0.0.1:18100';
const secret = process.env.BROKER_TEST_SECRET || 'h3-test-secret';
const jwt = claims => {
  const encoded = [ {alg:'HS256',typ:'JWT'}, {...claims,exp:Math.floor(Date.now()/1000)+120} ].map(x=>Buffer.from(JSON.stringify(x)).toString('base64url')).join('.');
  return encoded+'.'+crypto.createHmac('sha256',secret).update(encoded).digest('base64url');
};
// Сокет клиента: команды с ответом и живые публикации.
const open = async sub => {
 const socket = new WebSocket(root.replace('http','ws')+'/connection/websocket');
 let seq=0;const pending=new Map();const publications=[];
 socket.onmessage=({data})=>{
  for(const line of String(data).trim().split('\n')) {
   const frame=JSON.parse(line);
   if(frame.id) { const done=pending.get(frame.id); if(done) { pending.delete(frame.id);done(frame); } }
   if(frame.push?.pub) publications.push(frame.push);
  }
 };
 const command=(method,body)=>new Promise((resolve,reject)=>{
  const id=++seq;
  const timer=setTimeout(()=>reject(new Error('broker timeout '+method)),5000);
  pending.set(id,frame=>{clearTimeout(timer);resolve(frame)});
  socket.send(JSON.stringify({id,[method]:body}));
 });
 await new Promise((resolve,reject)=>{socket.onopen=resolve;socket.onerror=reject});
 assert.ok((await command('connect',{token:jwt({sub})})).connect);
 return {socket,command,publications};
};
const serverPublish = async (channel,data) => {
 const response=await fetch(root+'/api/publish',{method:'POST',headers:{'Content-Type':'application/json','X-API-Key':process.env.BROKER_TEST_API_KEY||'h3-test-api'},body:JSON.stringify({channel,data})});
 assert.equal(response.status,200);
};
// A11: каналы pair/user держат историю — пропущенное за обрыв приходит при
// переподключении с recover, без перечитывания списков.
const recovery = async channel => {
 const first=await open('alice');
 let position;
 try {
  const reply=(await first.command('subscribe',{channel,token:jwt({sub:'alice',channel})})).subscribe;
  assert.ok(reply,'subscribe '+channel);
  assert.equal(reply.recoverable,true,channel+' must be recoverable');
  position={epoch:reply.epoch,offset:reply.offset||0};
 } finally {first.socket.close()}
 // Обрыв: пока клиента нет, сервер публикует два события.
 const missed=[{n:1},{n:2}];
 for(const data of missed) await serverPublish(channel,data);
 const second=await open('alice');
 try {
  const reply=(await second.command('subscribe',{channel,token:jwt({sub:'alice',channel}),recover:true,epoch:position.epoch,offset:position.offset})).subscribe;
  assert.ok(reply,'resubscribe '+channel);
  assert.equal(reply.recovered,true,channel+' must recover');
  assert.deepEqual((reply.publications||[]).map(p=>p.data),missed);
 } finally {second.socket.close()}
};
(async()=>{
 const {socket,command,publications}=await open('alice');
 try {
  const channels=['pair:pairaaaaaaaaaaa','loc:pair_alice_bob','user:alice','signal:pairaaaaaaaaaaa','locsignal:pair_alice_bob'];
  for(const channel of channels) assert.ok((await command('subscribe',{channel,token:jwt({sub:'alice',channel})})).subscribe);
  for(const channel of channels.slice(0,3)) {
   const response=await command('publish',{channel,data:{event:'delete',collection:'groups',record:{id:'forged'}}});
   assert.ok(response.error,'client must not publish to '+channel);
  }
  for(const channel of channels.slice(3)) assert.ok((await command('publish',{channel,data:{t:'alive'}})).publish);
  assert.equal(publications.filter(p=>channels.slice(0,3).includes(p.channel)).length,0,'signals cannot reach server-delta channels');
  const fixture=require('../../test/fork/realtime/fixtures/signed_delta.json');
  await serverPublish(channels[0],fixture.envelope);
  await new Promise(resolve=>setTimeout(resolve,100));
  assert.deepEqual(publications.find(p=>p.channel===channels[0]).pub.data,fixture.envelope);
  console.log('ok: client delta publication denied; signals isolated; server envelope delivered');
 } finally {socket.close()}
 for(const channel of ['pair:pairbbbbbbbbbbb','user:alice']) await recovery(channel);
 console.log('ok: pair/user publications missed during a drop are recovered from history');
})().catch(error=>{console.error(error);process.exitCode=1});
