"""Adapt legacy parity tests to the signed transport without editing upstream.

The payload assertions remain upstream's. Verify envelopes with the disposable
broker's API key before unwrapping; this code is never used by the application.
"""
from pathlib import Path
import sys

source = Path(sys.argv[1]).read_text()
expression = 'm["push"].get("pub", {}).get("data", {})'
if expression in source:
    source = source.replace(expression, '_fork_verified_delta(' + expression + ', m["push"].get("channel", ""))')
    source = '''
def _fork_verified_delta(envelope, channel):
    import base64
    import hashlib
    import json
    import os
    import re
    import time
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    assert envelope.get('v') == 1 and envelope.get('channel') == channel
    at = envelope['at']
    assert isinstance(at, int) and -30000 <= time.time()*1000 - at <= 600000
    nonce = envelope['nonce']
    assert re.fullmatch(r'[a-f0-9]{32}', nonce)
    payload = envelope['payload']
    message = f'tethered-realtime-v1\\n{channel}\\n{at}\\n{nonce}\\n{payload}'.encode()
    seed = hashlib.sha256(b'tethered-realtime-key-v1\\x00' + os.environ['PARITY_API_KEY'].encode()).digest()
    key = Ed25519PrivateKey.from_private_bytes(seed).public_key()
    key.verify(base64.urlsafe_b64decode(envelope['sig']+'==='), message)
    return json.loads(base64.urlsafe_b64decode(payload+'==='))

''' + source
Path(sys.argv[2]).write_text(source)
