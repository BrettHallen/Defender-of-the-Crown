#!/usr/bin/env python3
"""Match the routines of two flatdis.py listings (e.g. AB.ASM and AC.ASM).
Usage: matchfuncs.py A.asm B.asm
Each routine becomes a list of instructions with call/jump targets and big
immediates masked; routines are matched exactly first, then by similarity in
address order. Prints B's routines with their match in A (or none) and a score."""
import sys, re, difflib

def routines(path):
    r = {}; cur = None; order = []
    for l in open(path):
        m = re.match(r'^(sub_[0-9A-F]{4}|[A-Za-z]\w*):', l)
        if m and not l.startswith('L_'):
            cur = m.group(1); r[cur] = []; order.append(cur); continue
        m = re.match(r'^([0-9A-F]{4})  ([0-9a-f]+)\s+(\S+)\s*(.*?)(\s+;.*)?$', l)
        if m and cur:
            mn, ops = m.group(3), m.group(4)
            if mn == 'call' or mn.startswith('j') or mn.startswith('loop'): ops = 'T'
            ops = re.sub(r'(sub|L)_[0-9A-F]{4}', 'T', ops)
            ops = re.sub(r'0x[0-9a-f]{3,4}', 'N', ops)
            r[cur].append(mn + ' ' + ops)
    return r, order

a, ao = routines(sys.argv[1]); b, bo = routines(sys.argv[2])
match = {}
used = set()
bykey = {}
for n in ao: bykey.setdefault('\n'.join(a[n]), []).append(n)
for n in bo:
    k = '\n'.join(b[n])
    c = [x for x in bykey.get(k, []) if x not in used]
    if c and b[n]: match[n] = (c[0], 1.0); used.add(c[0])
for n in bo:
    if n in match or not b[n]: continue
    best = None
    for x in ao:
        if x in used or abs(len(a[x]) - len(b[n])) > max(8, len(b[n]) // 2): continue
        r = difflib.SequenceMatcher(None, a[x], b[n], autojunk=False).quick_ratio()
        if best is None or r > best[1]:
            if r > 0.6:
                r = difflib.SequenceMatcher(None, a[x], b[n], autojunk=False).ratio()
                if best is None or r > best[1]: best = (x, r)
    if best and best[1] >= 0.6: match[n] = best; used.add(best[0])
for n in bo:
    m = match.get(n)
    print('%-10s %4d insns  %s' % (n, len(b[n]), ('= %s %.2f' % m) if m else 'NO MATCH'))
