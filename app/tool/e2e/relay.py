# Minimal local Nostr relay (NIP-01: EVENT, REQ, CLOSE, EOSE; addressable kind 30000-39999 replaced by pubkey+d) for
# the end-to-end test of Fasan Split. Local only, no signature check (the app checks signatures itself).
import asyncio, json, sys
import websockets

events = []          # stored events
subs = {}            # websocket -> {sub_id: [filters]}

def match(f, e):
    if 'ids' in f and e['id'] not in f['ids']: return False
    if 'kinds' in f and e['kind'] not in f['kinds']: return False
    if 'authors' in f and e['pubkey'] not in f['authors']: return False
    if 'since' in f and e['created_at'] < f['since']: return False
    for k, v in f.items():
        if k.startswith('#'):
            vals = [t[1] for t in e['tags'] if len(t) > 1 and t[0] == k[1:]]
            if not any(x in v for x in vals): return False
    return True

async def handler(ws):
    subs[ws] = {}
    try:
        async for raw in ws:
            m = json.loads(raw)
            if m[0] == 'EVENT':
                e = m[1]
                if 30000 <= e['kind'] < 40000:
                    d = next((t[1] for t in e['tags'] if t and t[0] == 'd'), '')
                    events[:] = [x for x in events if not (x['kind'] == e['kind'] and x['pubkey'] == e['pubkey'] and next((t[1] for t in x['tags'] if t and t[0] == 'd'), '') == d)]
                events.append(e)
                await ws.send(json.dumps(['OK', e['id'], True, '']))
                for w, ss in list(subs.items()):
                    for sid, fs in ss.items():
                        if any(match(f, e) for f in fs):
                            try: await w.send(json.dumps(['EVENT', sid, e]))
                            except Exception: pass
            elif m[0] == 'REQ':
                sid, fs = m[1], m[2:]
                subs[ws][sid] = fs
                for e in events:
                    if any(match(f, e) for f in fs): await ws.send(json.dumps(['EVENT', sid, e]))
                await ws.send(json.dumps(['EOSE', sid]))
            elif m[0] == 'CLOSE':
                subs[ws].pop(m[1], None)
    finally:
        subs.pop(ws, None)

async def main():
    async with websockets.serve(handler, '127.0.0.1', int(sys.argv[1]) if len(sys.argv) > 1 else 7777):
        await asyncio.Future()

asyncio.run(main())
