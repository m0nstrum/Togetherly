"""Live regression for PLAN 1.1; run via SMOKE_AFTER on a disposable server."""
import json
import os
import urllib.request
import urllib.error

base = os.environ['SMOKE_BASE_URL']
a, b, pair = (os.environ['SMOKE_' + k] for k in ('AID', 'BID', 'PAIR'))
at, bt = (os.environ['SMOKE_' + k] for k in ('ATOK', 'BTOK'))

def request(method, path, token, body=None):
    req = urllib.request.Request(base + path, method=method, headers={
        'Authorization': token, 'Content-Type': 'application/json'},
        data=None if body is None else json.dumps(body).encode())
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, json.load(e)

def check(method, path, token, body=None, expected=200):
    code, value = request(method, path, token, body)
    assert code == expected, (method, path, body, code, value)
    return value

presence = check('POST', '/api/collections/user_presence/records', bt, {'user_uid': b})
# D11: геоканал выдаётся только тому, кто делится сам.
check('POST', '/api/collections/live_location/records', at, {'channel': 'pair_' + a + '_' + b, 'user_uid': a})
for ch in ('user:' + b, 'pair:' + pair, 'loc:pair_' + a + '_' + b):
    check('POST', '/api/centrifugo/subscription-token', at, {'channel': ch})
check('GET', '/api/user/card?uid=' + b, at)
check('PATCH', '/api/collections/groups/records/' + pair, at, {'disbanded': True})
for ch in ('user:' + b, 'pair:' + pair, 'loc:pair_' + a + '_' + b):
    check('POST', '/api/centrifugo/subscription-token', at, {'channel': ch}, 403)
check('GET', '/api/user/card?uid=' + b, at, expected=403)
check('GET', '/api/collections/user_presence/records/' + presence['id'], at, expected=404)
check('POST', '/api/collections/chat_messages/records', at,
      {'group_id': pair, 'user_uid': a, 'text': 'after breakup'}, 400)
check('POST', '/api/group/patch-map', at,
      {'groupId': pair, 'field': 'member_moods', 'uid': a, 'value': 'changed'}, 403)
check('PATCH', '/api/collections/groups/records/' + pair, at, {'disbanded': False}, 404)
check('GET', '/api/collections/groups/records/' + pair, at)
print('ok: breakup revokes current data, writes and new subscription tokens')
