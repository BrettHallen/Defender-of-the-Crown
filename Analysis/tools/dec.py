#!/usr/bin/env python3
"""C-like pseudocode for one routine of a flatdis.py listing (AA/AB/AC.ASM).

Usage: dec.py [-f AB.ASM] NAME|ADDR [...]
Data-segment offsets are named from ds_names.txt (beside this file: HEX name [size]),
e.g. [0x4e7 + bx] -> lord[bx]. Arguments are a1, a2 ... (word-sized, from [bp+N]),
locals l2, l4 ... ([bp-N]). Calls show their pushed arguments; compares show as
`if (a < b) goto L_xxxx`. It follows the compiler's simple patterns (Microsoft C,
small model, push si/di/bp prologue) and is meant for reading, not for recompiling:
check anything subtle in the asm."""
import re, sys, os

here = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]
asm = os.path.join(here, '..', 'AB.ASM')
if args and args[0] == '-f': asm = args[1]; args = args[2:]
L = open(asm).read().split('\n')

DS = []   # (start, size, name, record size, {field offset: name})
p = os.path.join(here, 'ds_names.txt')
if os.path.exists(p):
    for l in open(p):
        l = l.split('#')[0].strip()
        if not l: continue
        f = l.split()
        size = int(f[2], 0) if len(f) > 2 else 2
        rec = int(f[3], 0) if len(f) > 3 else 0
        fields = {}
        for x in f[4:]:
            k, v = x.split('=')
            fields[int(k, 0)] = v
        DS.append((int(f[0], 16), size, f[1], rec, fields))
DS.sort()

def strip_scale(idx, rec):
    if idx is None: return None
    for pat in (r'^\((.*) \* %d\)$' % rec, r'^\(\((.*) \* %d\) \+ (.*)\)$' % rec):
        m = re.match(pat, idx)
        if m and len(m.groups()) == 1: return m.group(1)
    sh = {2: 1, 4: 2, 8: 3, 16: 4}.get(rec)
    if sh:
        m = re.match(r'^' + r'\(' * sh + r'(.*?)' + r' << 1\)' * sh + '$', idx)
        if m: return m.group(1)
        m = re.match(r'^\((.*) << %d\)$' % sh, idx)
        if m: return m.group(1)
    return None

def dsname(off, idx=None):
    for a, n, nm, rec, fields in DS:
        if a <= off < a + n:
            if rec:
                r, fo = divmod(off - a, rec)
                fname = fields.get(fo, '+%d' % fo)
                if idx is None: return '%s[%d].%s' % (nm, r, fname)
                i2 = strip_scale(idx, rec)
                if i2 is not None:
                    return '%s[%s%s].%s' % (nm, i2, (' + %d' % r) if r else '', fname)
                return '%s.%s[%s]' % (nm, fname if not r else '%d.%s' % (r, fname), idx)
            if off == a: return nm if idx is None else '%s[%s]' % (nm, idx)
            return '%s[%d%s]' % (nm, off - a, (' + ' + idx) if idx else '')
    s = 'ds_%X' % off
    return s if idx is None else '%s[%s]' % (s, idx)

def find(name):
    if name.startswith('L_'):
        for i, l in enumerate(L):
            if l.startswith(name + ':'): return i
    pat = re.compile(r'^%s:' % re.escape(name))
    for i, l in enumerate(L):
        if pat.match(l): return i
    a = name.upper().replace('SUB_', '')
    for i, l in enumerate(L):
        if l.startswith(a + '  '):
            j = i
            while not re.match(r'^[A-Za-z]\w*:', L[j]) or L[j].startswith('L_'): j -= 1
            return j
    raise SystemExit('not found: ' + name)

def routine(i):
    name = L[i].split(':')[0]
    out = []
    for l in L[i + 1:]:
        if re.match(r'^[A-Za-z]\w*:', l) and not l.startswith('L_'): break
        m = re.match(r'^(L_[0-9A-F]{4}):', l)
        if m: out.append(('label', m.group(1))); continue
        m = re.match(r'^([0-9A-F]{4})  ([0-9a-f]+)\s+(\S+)\s*(.*?)(\s+;.*)?$', l)
        if m:
            if m.group(5) and 'dialog box' in m.group(5): out.append(('comment', m.group(5).split(';', 1)[1].strip()))
            out.append((int(m.group(1), 16), m.group(3), m.group(4)))
    return name, out

REG16 = ['ax', 'bx', 'cx', 'dx', 'si', 'di']
REG8 = {'al': 'ax', 'ah': 'ax', 'bl': 'bx', 'bh': 'bx', 'cl': 'cx', 'ch': 'cx', 'dl': 'dx', 'dh': 'dx'}
JCC = {'je': '==', 'jne': '!=', 'jl': '<', 'jge': '>=', 'jg': '>', 'jle': '<=',
       'jb': '<u', 'jae': '>=u', 'ja': '>u', 'jbe': '<=u', 'js': '<0', 'jns': '>=0'}

class Dec:
    def __init__(s, name, ins):
        s.name, s.ins = name, ins
        s.argbase = 4
        for k in range(min(4, len(ins))):
            if ins[k][1:] == ('mov', 'bp, sp'):
                pushes = sum(1 for j in range(k) if ins[j][1] == 'push')
                s.argbase = 2 + 2 * pushes   # return address + pushed regs (bp included)
        s.r = {}; s.stack = []; s.cmp = None; s.out = []
    def emit(s, t): s.out.append('    ' + t)
    def mem(s, a, byte=False):
        a = a.replace(' ', '')
        seg = ''
        m = re.match(r'^(es|cs|ss):(.*)$', a)
        if m: seg, a = m.group(1) + ':', m.group(2)
        a = a.strip('[]')
        m = re.match(r'^bp([+-])(0x[0-9a-f]+|\d+)$', a)
        if m:
            v = int(m.group(2), 0)
            if m.group(1) == '+': return 'a%d' % ((v - s.argbase) // 2 + 1)
            return 'l%d' % v
        m = re.match(r'^(0x[0-9a-f]+|\d+)$', a)
        if m:
            if seg == 'cs:': return 'cs_%X' % int(a, 0)
            return seg + dsname(int(a, 0))
        m = re.match(r'^(bx|si|di|bp)(?:\+(si|di))?([+-](?:0x[0-9a-f]+|\d+))?$', a)
        if m:
            base = s.val(m.group(1)) if m.group(1) != 'bp' else 'bp'
            idx = base + (' + ' + s.val(m.group(2)) if m.group(2) else '')
            disp = int(m.group(3), 0) if m.group(3) else 0
            if m.group(1) == 'bp':
                return 'frame[%s%+d]' % (s.val(m.group(2)) if m.group(2) else '', disp)
            if disp > 0x40 and not seg: return dsname(disp, idx)
            if disp: return '%s*(%s %+d)' % (seg, idx, disp) if False else '%s[%s %+d]' % (seg + 'mem', idx, disp)
            return '%smem[%s]' % (seg, idx)
        return seg + '[' + a + ']'
    def val(s, x):
        x = x.strip()
        if x in REG16: return s.r.get(x, x)
        if x in REG8:
            v = s.r.get(REG8[x], REG8[x])
            return v if x[1] == 'l' else '(%s >> 8)' % v
        m = re.match(r'^(byte|word|dword) ptr (.*)$', x)
        if m: return s.mem(m.group(2), m.group(1) == 'byte')
        if x.startswith('['): return s.mem(x)
        m = re.match(r'^-?(0x[0-9a-f]+|\d+)$', x)
        if m:
            v = int(x, 0) & 0xFFFF
            return str(v - 0x10000) if v >= 0xFF00 else (str(v) if v < 0x100 else '0x%X' % v)
        return x
    def set(s, dst, expr):
        dst = dst.strip()
        if dst in ('si', 'di'):
            s.emit('%s = %s;' % (dst, expr)); s.r.pop(dst, None); return
        if dst in REG16: s.r[dst] = expr; return
        if dst in REG8:
            s.r[REG8[dst]] = expr if dst[1] == 'l' else '(%s)<<8' % expr; return
        s.emit('%s = %s;' % (s.val(dst), expr))
    def flush(s):
        for k in ('ax', 'bx', 'cx', 'dx'):
            v = s.r.get(k)
            if v is not None and v != k: s.emit('%s = %s;' % (k, v))
        s.r = {}
    def run(s):
        params = set()
        for it in s.ins:
            if it[0] == 'label':
                s.flush(); s.out.append(it[1] + ':'); continue
            if it[0] == 'comment':
                s.emit('/* ' + it[1] + ' */'); continue
            a, mn, ops = it
            o = [x.strip() for x in re.split(r',(?![^\[]*\])', ops)] if ops else []
            if mn in ('push',) and o[0] in ('si', 'di', 'bp') and not s.out and len(s.stack) < 3 and o[0] not in s.r:
                continue
            if mn == 'mov' and ops in ('bp, sp', 'sp, bp'): continue
            if mn == 'pop' and o[0] in ('si', 'di', 'bp', 'es', 'ds'): continue
            if mn in ('push',):
                if o[0] in ('ds', 'es', 'cs'): continue
                s.stack.append(s.val(o[0])); continue
            if mn == 'pop':
                s.r[o[0]] = s.stack.pop() if s.stack else '?'; continue
            if mn == 'call':
                fn = o[0]
                s.emit_call = None
                argsl = list(reversed(s.stack)); s.stack = []
                s.r = {'ax': '%s(%s)' % (fn, ', '.join(argsl))}
                s.pending = s.r['ax']; s.used = False
                s.emit('ax = %s;' % s.r['ax']); s.r['ax'] = 'ax'
                continue
            if mn == 'add' and o[0] == 'sp': continue
            if mn == 'sub' and o[0] == 'sp': continue
            if mn == 'mov':
                s.set(o[0], s.val(o[1])); continue
            if mn in ('lea',):
                s.set(o[0], '&' + s.val(o[1])); continue
            if mn in ('xor', 'sub') and o[0] == o[1]:
                s.set(o[0], '0'); continue
            if mn in ('add', 'sub', 'and', 'or', 'xor', 'imul', 'shl', 'shr', 'sar', 'adc', 'sbb'):
                opc = {'add': '+', 'sub': '-', 'and': '&', 'or': '|', 'xor': '^', 'imul': '*', 'shl': '<<', 'shr': '>>', 'sar': '>>', 'adc': '+c+', 'sbb': '-b-'}[mn]
                if len(o) == 1: o = ['ax', o[0]]
                expr = '(%s %s %s)' % (s.val(o[0]), opc, s.val(o[1]))
                if o[0] in REG16 or o[0] in REG8: s.set(o[0], expr)
                else: s.emit('%s %s= %s;' % (s.val(o[0]), opc, s.val(o[1])))
                s.cmp = (s.val(o[0]), '0'); continue
            if mn in ('inc', 'dec', 'neg', 'not'):
                opx = {'inc': '+ 1', 'dec': '- 1'}.get(mn)
                if o[0] in REG16 or o[0] in REG8:
                    s.set(o[0], ('(%s %s)' % (s.val(o[0]), opx)) if opx else ('%s%s' % ('-' if mn == 'neg' else '~', s.val(o[0]))))
                else: s.emit('%s%s;' % (s.val(o[0]), {'inc': '++', 'dec': '--', 'neg': ' = -' + s.val(o[0]), 'not': ' = ~' + s.val(o[0])}[mn]))
                s.cmp = (s.val(o[0]), '0'); continue
            if mn in ('mul', 'div', 'idiv'):
                if mn == 'mul': s.set('ax', '(%s * %s)' % (s.val('ax'), s.val(o[0])))
                else:
                    q = '(%s / %s)' % (s.val('ax'), s.val(o[0])); rm = '(%s %% %s)' % (s.val('ax'), s.val(o[0]))
                    s.r['ax'] = q; s.r['dx'] = rm
                continue
            if mn in ('cwde', 'cwd', 'cbw', 'cdq'):
                continue
            if mn == 'cmp': s.cmp = (s.val(o[0]), s.val(o[1])); continue
            if mn == 'test':
                s.cmp = ((s.val(o[0]) if o[0] == o[1] else '(%s & %s)' % (s.val(o[0]), s.val(o[1]))), '0'); continue
            if mn in JCC:
                c = s.cmp or ('?', '0')
                op = JCC[mn]
                if op in ('<0', '>=0'): cond = '%s %s 0' % (c[0], op[:-1])
                else: cond = '%s %s %s' % (c[0], op, c[1])
                s.emit('if (%s) goto %s;' % (cond, o[0])); continue
            if mn == 'jmp':
                s.flush(); s.emit('goto %s;' % o[0]); continue
            if mn in ('ret', 'retf'):
                s.emit('return %s;' % s.val('ax')); s.r = {}; continue
            if mn == 'xchg':
                a1, b1 = s.val(o[0]), s.val(o[1]); s.set(o[0], b1); s.set(o[1], a1); continue
            s.emit('/* %04X %s %s */' % (a, mn, ops))
        return s.out

for n in args:
    i = find(n)
    name, ins = routine(i)
    print('%s()  /* %s */' % (name, n))
    print('{')
    for l in Dec(name, ins).run(): print(l)
    print('}\n')
