#!/usr/bin/env python3
"""Pair DOC.EXE's routines with AB's by the texts they use.

Usage: docmatch.py DOC.EXE [AB.ASM] [DOC.ASM] > DOC_vs_AB.txt

DOC.EXE (large model, its own data segment) and AB (the booter's EGA program,
small model, the data file BH) were compiled from much the same C source but
share no instructions worth comparing. They do share the texts: the message
boxes and the strings. For every DOC routine this lists the boxes (13-byte
structs: byte x, byte y, byte lines, byte width, 5 bytes, far pointer to the
lines' far pointers) and strings its immediates point at, and the AB routines
whose annotations show the same texts. A routine with no text is paired, where
possible, through its callers and callees (a DOC routine called only from
routines paired with one AB routine's callers ...); those pairs are marked '?'.
"""
import os, re, struct, sys
from collections import defaultdict

here = os.path.dirname(os.path.abspath(__file__))
exe = sys.argv[1]
ab_asm = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, '..', 'AB.ASM')
doc_asm = sys.argv[3] if len(sys.argv) > 3 else os.path.join(here, '..', 'DOC.ASM')

d = open(exe, 'rb').read()
hdr = struct.unpack('<H', d[8:10])[0] * 16
D = d[hdr + 0xBCE * 16:]


def W(o):
    return struct.unpack('<H', D[o:o + 2])[0] if 0 <= o < len(D) - 1 else 0


def cstr(o):
    if not (0 < o < len(D)):
        return None
    s = D[o:o + 200].split(b'\0')[0]
    if len(s) < 4 or any(c < 32 or c > 126 for c in s):
        return None
    return s.decode('latin-1')


def box(o):
    """the lines of the box struct at o, or None"""
    if not (0 < o < len(D) - 13):
        return None
    n = D[o + 2]
    if not (1 <= n <= 20) or W(o + 11) != 0xBCE:
        return None
    p = W(o + 9)
    lines = []
    for i in range(n):
        if W(p + 4 * i + 2) != 0xBCE:
            return None
        s = D[W(p + 4 * i):W(p + 4 * i) + 100].split(b'\0')[0].decode('latin-1')
        lines.append(s)
    return lines


def norm(s):
    return re.sub(r'[^a-z0-9]+', ' ', s.lower()).strip()


# ---------------------------------------------------------------- DOC routines
doc = {}          # name -> {'texts': [...], 'calls': set(), 'lines': n}
cur = None
last_cx = None
ids = {}          # the name DOC.ASM gives a routine -> f_SEG_OFF (docdis.py names them from doc_names.txt)
for line in open(doc_asm):
    m = re.match(r'^(\S+) proc  ; ([0-9A-F]{4}):([0-9A-F]{4})', line)
    if m: ids[m.group(1)] = 'f_%s_%s' % (m.group(2), m.group(3))
for line in open(doc_asm):
    m = re.match(r'^(\S+) proc  ; ([0-9A-F]{4}):([0-9A-F]{4})', line)
    if m:
        cur = 'f_%s_%s' % (m.group(2), m.group(3))
        doc[cur] = {'texts': [], 'calls': set(), 'seq': [], 'n': 0}
        continue
    if not cur or not re.match(r'^[0-9A-F]{4}:[0-9A-F]{4} ', line):
        continue
    doc[cur]['n'] += 1
    m = re.search(r'lcall\s+([A-Za-z_][\w?]*)', line)
    if m and m.group(1) in ids:
        doc[cur]['calls'].add(ids[m.group(1)])
        doc[cur]['seq'].append(ids[m.group(1)])
    m = re.search(r'mov\s+(\w\w), 0x([0-9a-f]+)', line)
    if m:
        v = int(m.group(2), 16)
        if m.group(1) == 'cx':
            last_cx = v
        b = box(v) if m.group(1) in ('cx', 'si') else None
        if b:
            doc[cur]['texts'].append(('box', ' / '.join(b)))
        else:
            s = cstr(v)
            if s and m.group(1) in ('ax', 'cx', 'dx', 'si', 'bx'):
                doc[cur]['texts'].append(('str', s))

# ---------------------------------------------------------------- AB routines
ab = {}
cur = None
for line in open(ab_asm):
    m = re.match(r'^([a-z_][a-z_0-9]*): ?(;.*)?$', line)
    if m:
        cur = m.group(1)
        ab[cur] = {'texts': [], 'calls': set(), 'seq': [], 'comment': (m.group(2) or '')[2:]}
        continue
    if not cur:
        continue
    m = re.search(r'call\s+([a-z_][a-z_0-9]*)\s*$', line)
    if m:
        ab[cur]['calls'].add(m.group(1))
        ab[cur]['seq'].append(m.group(1))
    m = re.search(r'; dialog box \([^)]*\): "(.*)"\s*$', line)
    if m:
        ab[cur]['texts'].append(('box', m.group(1)))
        continue
    m = re.search(r'; "(.*)"\s*$', line)
    if m and len(m.group(1)) >= 6:
        ab[cur]['texts'].append(('str', m.group(1)))

# an index of AB's texts: the normalised start of each
ab_index = []
for name, r in ab.items():
    for kind, t in r['texts']:
        t = t[:-3] if t.endswith('...') else t
        k = norm(t)
        if len(k) >= 8:
            ab_index.append((k, name, kind))


def ab_for(text):
    k = norm(text)
    hits = set()
    for key, name, kind in ab_index:
        a, b = (key, k) if len(key) <= len(k) else (k, key)
        if len(a) >= 10 and a in b:
            hits.add(name)
    return hits


pairs = {}
for name, r in doc.items():
    votes = defaultdict(int)
    for kind, t in r['texts']:
        for h in ab_for(t):
            votes[h] += 2 if kind == 'box' else 1
    if votes:
        best = max(votes.values())
        pairs[name] = (sorted(h for h, v in votes.items() if v == best), r['texts'])

# ---------------------------------------------------------------- through the call graph
# Each paired routine's calls, in order, against its AB partner's: between two
# calls already paired (or the ends), runs of the same length pair up one to one.
guess = {}


def known_map():
    k = {n: v[0][0] for n, v in pairs.items() if len(v[0]) == 1}
    k.update(guess)
    return k


for _ in range(8):
    known = known_map()
    added = 0
    for name, ab_name in list(known.items()):
        if ab_name not in ab:
            continue
        ds, as_ = doc[name]['seq'], ab[ab_name]['seq']
        # anchors: positions where the DOC call is known and its AB partner occurs next in order
        anchors = [(-1, -1)]
        j = 0
        for i, c in enumerate(ds):
            if c in known:
                try:
                    jj = as_.index(known[c], j)
                except ValueError:
                    continue
                anchors.append((i, jj))
                j = jj + 1
        anchors.append((len(ds), len(as_)))
        for (i0, j0), (i1, j1) in zip(anchors, anchors[1:]):
            seg_d, seg_a = ds[i0 + 1:i1], as_[j0 + 1:j1]
            if len(seg_d) == len(seg_a):
                for x, y in zip(seg_d, seg_a):
                    if x not in known and x not in guess and y not in known.values():
                        guess[x] = y
                        added += 1
    if not added:
        break

# ---------------------------------------------------------------- report
print('# DOC.EXE routines paired with AB by their texts (docmatch.py)')
print('# DOC routine  instructions  -> AB routine(s)  [texts]')
for name in sorted(doc):
    r = doc[name]
    if name in pairs:
        hits, texts = pairs[name]
        print(f'{name}  {r["n"]:5d}  -> {", ".join(hits)}')
        for kind, t in texts[:4]:
            print(f'        {kind}: {t[:90]}')
    elif name in guess:
        print(f'{name}  {r["n"]:5d}  -> {guess[name]} ?  (through the call graph)')
    else:
        print(f'{name}  {r["n"]:5d}  -> (none)')
n = len(pairs) + len(guess)
print(f'# {len(pairs)} paired by text, {len(guess)} through the call graph, {len(doc) - n} not paired, of {len(doc)}')
