"""M3 regression: actual JS hooks on a disposable smoke server."""
import json
import os
import urllib.error
import urllib.request

base = os.environ['SMOKE_BASE_URL']
a, b, pair = (os.environ['SMOKE_' + k] for k in ('AID', 'BID', 'PAIR'))
token = os.environ['SMOKE_ATOK']

def request(path, body=None, expected=200):
    req = urllib.request.Request(base + path, method='GET' if body is None else 'POST',
        headers={'Authorization': token, 'Content-Type': 'application/json'},
        data=None if body is None else json.dumps(body).encode())
    try:
        with urllib.request.urlopen(req) as response:
            code, data = response.status, json.load(response)
    except urllib.error.HTTPError as error:
        code, data = error.code, json.load(error)
    assert code == expected, (path, code, data)
    return data

for op, extra in [
    ('patch-map', {'field': 'member_moods', 'value': 'forged'}),
    ('record-activity', {'today': '2026-10-23'}),
    ('miss-you', {'times': 1}),
    ('leave', {}),
]:
    request('/api/group/' + op, {'groupId': pair, 'uid': b, **extra}, 403)
assert set(request('/api/collections/groups/records/' + pair)['members']) == {a, b}
request('/api/group/record-activity', {'groupId': pair, 'today': '2026-10-23'})
request('/api/group/patch-map', {'groupId': pair, 'field': 'member_moods', 'value': 'own'})
group = request('/api/collections/groups/records/' + pair)
assert group['member_moods'].get(a) == 'own'
assert group['member_moods'].get(b) != 'forged'
request('/api/group/leave', {'groupId': pair})
print('ok: group operations use authenticated identity; forged uid rejected')
