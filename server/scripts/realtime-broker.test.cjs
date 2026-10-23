// H3 integration against the deployed Centrifugo config (disposable container).
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const root = process.env.BROKER_URL || 'http://127.0.0.1:18100';
const secret = process.env.BROKER_TEST_SECRET || 'h3-test-secret';
const jwt = claims => {
  const encoded = [ {alg:'HS256',typ:'JWT'}, {...claims,exp:Math.floor(Date.now()/1000)+120} ].map(x=>Buffer.from(JSON.stringify(x)).toString('base64url')).join('.');
  return encoded+'.'+crypto.createHmac('sha256',secret).update(encoded).digest('base64url');
};
(async()=>{
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
 try {
  await new Promise((resolve,reject)=>{socket.onopen=resolve;socket.onerror=reject});
  assert.ok((await command('connect',{token:jwt({sub:'alice'})})).connect);
  const channels=['pair:pairaaaaaaaaaaa','loc:pair_alice_bob','user:alice','signal:pairaaaaaaaaaaa','locsignal:pair_alice_bob'];
  for(const channel of channels) assert.ok((await command('subscribe',{channel,token:jwt({sub:'alice',channel})})).subscribe);
  for(const channel of channels.slice(0,3)) {
   const response=await command('publish',{channel,data:{event:'delete',collection:'groups',record:{id:'forged'}}});
   assert.ok(response.error,'client must not publish to '+channel);
  }
  for(const channel of channels.slice(3)) assert.ok((await command('publish',{channel,data:{t:'alive'}})).publish);
  assert.equal(publications.filter(p=>channels.slice(0,3).includes(p.channel)).length,0,'signals cannot reach server-delta channels');
  const fixture=require('../../test/fork/realtime/fixtures/signed_delta.json');
  const response=await fetch(root+'/api/publish',{method:'POST',headers:{'Content-Type':'application/json','X-API-Key':process.env.BROKER_TEST_API_KEY||'h3-test-api'},body:JSON.stringify({channel:channels[0],data:fixture.envelope})});
  assert.equal(response.status,200);
  await new Promise(resolve=>setTimeout(resolve,100));
  assert.deepEqual(publications.find(p=>p.channel===channels[0]).pub.data,fixture.envelope);
  console.log('ok: client delta publication denied; signals isolated; server envelope delivered');
 } finally {socket.close()}
})().catch(error=>{console.error(error);process.exitCode=1});
