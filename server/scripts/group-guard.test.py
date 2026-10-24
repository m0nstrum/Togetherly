"""M3: direct PATCH of groups cannot act for the partner (real JS hooks)."""
import json
import os
import urllib.error
import urllib.request

base = os.environ['SMOKE_BASE_URL']
a, b, pair = (os.environ['SMOKE_' + k] for k in ('AID', 'BID', 'PAIR'))
atok, btok = os.environ['SMOKE_ATOK'], os.environ['SMOKE_BTOK']
path = '/api/collections/groups/records/' + pair


def request(method, url, token, body=None, expected=200):
    req = urllib.request.Request(base + url, method=method,
        headers={'Authorization': token, 'Content-Type': 'application/json'},
        data=None if body is None else json.dumps(body).encode())
    try:
        with urllib.request.urlopen(req) as response:
            code, data = response.status, json.load(response)
    except urllib.error.HTTPError as error:
        code, data = error.code, json.load(error)
    assert code == expected, (method, url, code, data)
    return data


request('PATCH', path, atok, {'member_moods': {a: 'mine'}})
group = request('GET', path, atok)
moods = group['member_moods']

# B forges A's mood or drops it; B's own key stays writable.
request('PATCH', path, btok, {'member_moods': {**moods, a: 'forged'}}, 403)
request('PATCH', path, btok, {'member_moods': {b: 'theirs'}}, 403)
request('PATCH', path, btok, {'member_moods': {**moods, b: 'theirs'}})
# B cannot remove A from the pair.
request('PATCH', path, btok, {'members': [b]}, 403)

group = request('GET', path, atok)
assert set(group['members']) == {a, b}, group['members']
assert group['member_moods'].get(a) == 'mine', group['member_moods']
assert group['member_moods'].get(b) == 'theirs', group['member_moods']

# Leaving yourself still works.
request('PATCH', path, btok, {'members': [a]})
print('ok: partner cannot remove you or rewrite your member_* values')
