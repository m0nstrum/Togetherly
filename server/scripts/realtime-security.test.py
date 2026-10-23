"""H3: real JS authorization and short-lived tokens via disposable smoke server."""
import base64
import json
import os
import time
import urllib.error
import urllib.request

base = os.environ['SMOKE_BASE_URL']
a, b, pair = (os.environ['SMOKE_' + k] for k in ('AID', 'BID', 'PAIR'))
token = os.environ['SMOKE_ATOK']
def request(method, path, body=None, expected=200, auth=token):
    req = urllib.request.Request(base+path, method=method,
        headers={'Authorization':auth,'Content-Type':'application/json'},
        data=None if body is None else json.dumps(body).encode())
    try:
        with urllib.request.urlopen(req) as response: code,data=response.status,json.load(response)
    except urllib.error.HTTPError as error: code,data=error.code,json.load(error)
    assert code==expected,(path,code,data)
    return data

def claims(jwt):
    return json.loads(base64.urlsafe_b64decode(jwt.split('.')[1]+'==='))

data=request('POST','/api/centrifugo/connection-token',{})
c=claims(data['token'])
assert c['sub']==a and 0<c['exp']-time.time()<=121
channels=['pair:'+pair,'signal:'+pair,'loc:pair_'+a+'_'+b,'locsignal:pair_'+a+'_'+b,'user:'+b]
for channel in channels:
    c=claims(request('POST','/api/centrifugo/subscription-token',{'channel':channel})['token'])
    assert c['channel']==channel and c['sub']==a and 0<c['exp']-time.time()<=121
for channel in ['signal:not-your-pair','locsignal:pair_'+a+'_outsider']:
    request('POST','/api/centrifugo/subscription-token',{'channel':channel},403)
key=request('GET','/api/fork/realtime-key')
assert isinstance(key['time'],int) and abs(key['time']/1000-time.time())<30
assert key['alg']=='Ed25519' and len(base64.urlsafe_b64decode(key['key']+'==='))==32
request('GET','/api/fork/realtime-key',expected=401,auth='')
request('PATCH','/api/collections/groups/records/'+pair,{'disbanded':True})
for channel in channels:
    request('POST','/api/centrifugo/subscription-token',{'channel':channel},403)
print('ok: realtime key authenticated; token TTL <=120s; revoked pair cannot refresh data or signals')
