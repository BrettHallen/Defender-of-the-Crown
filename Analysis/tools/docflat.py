#!/usr/bin/env python3
"""DOC.ASM in the flat form dec.py reads, so that DOC.EXE's routines can be
decompiled like AB's: python3 docflat.py [DOC.ASM] > /tmp/DOC_flat.ASM, then
python3 dec.py -f /tmp/DOC_flat.ASM -n doc_ds_names.txt f_050E_04D4 (or a name
from doc_names.txt).
Each routine becomes 'name:' (its name from doc_names.txt if it has one, else
f_SEG_OFF); instruction addresses lose their segment; far calls (lcall) become
calls by name, and jumps and labels take the routine's own L_OFF form."""
import os, re, sys
here = os.path.dirname(os.path.abspath(__file__))
src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, '..', 'DOC.ASM')
names = {}
p = os.path.join(here, 'doc_names.txt')
if os.path.exists(p):
    for l in open(p):
        l = l.split(';')[0].split('#')[0].strip()
        if l:
            a, n = l.split()[:2]
            names['f_' + a.replace(':', '_').upper()] = n
for line in open(src):
    line = line.rstrip('\n')
    m = re.match(r'^(\S+) proc  ; ([0-9A-F]{4}):([0-9A-F]{4})', line)
    if m:   # DOC.ASM names the routines itself now (docdis.py reads doc_names.txt); older listings use f_SEG_OFF
        n = 'f_%s_%s' % (m.group(2), m.group(3))
        print('\n%s: ; %s' % (names.get(n, m.group(1)), n))
        continue
    m = re.match(r'^L_[0-9A-F]{4}_([0-9A-F]{4}):', line)
    if m:
        print('L_%s:' % m.group(1)); continue
    m = re.match(r'^[0-9A-F]{4}:([0-9A-F]{4})  (\S+)\s+(\S+)\s*(.*?)$', line)
    if not m:
        continue
    off, by, mn, ops = m.groups()
    cm = ''
    if ';' in ops:
        ops, cm = ops.split(';', 1); ops = ops.rstrip(); cm = '   ;' + cm
    if mn == 'lcall':
        f = ops.split()[0]
        mn, ops = 'call', names.get(f, f)
    elif (mn.startswith('j') or mn in ('loop', 'call')) and re.match(r'^0x[0-9a-f]+$', ops):
        ops = 'L_%04X' % int(ops, 16)
    print('%s  %s  %s %s%s' % (off, by, mn, ops, cm))
