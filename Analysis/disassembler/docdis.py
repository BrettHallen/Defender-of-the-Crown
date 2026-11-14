#!/usr/bin/env python3
"""Recursive disassembler for DOC.EXE (Defender of the Crown, CGA DOS version).

Usage: python3 docdis.py path/to/DOC.EXE > DOC.ASM
The EXE is a plain MZ large-model program (many code segments, far calls fixed up
by relocations, one data segment DGROUP). Code is found by following the entry point,
far calls (9A + relocation), near calls/jumps, far pointers pushed as seg/offset pairs,
switch tables (jmp cs:[bx+T]) and the remaining 'push bp; mov bp,sp' prologues.
Names for routines and data go in NAMES / DNAMES (names.py next to this file)."""
import sys, struct, os, re
import capstone
from capstone import x86

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from names import NAMES, DNAMES, COMMENTS
except ImportError:
    NAMES, DNAMES, COMMENTS = {}, {}, {}

d = open(sys.argv[1], 'rb').read()
h = struct.unpack('<14H', d[:28])
hdr = h[4] * 16
img = bytearray(d[hdr:])
nrel = h[3]
relocs = set()
for i in range(nrel):
    o, s = struct.unpack('<HH', d[h[12] + 4 * i:h[12] + 4 * i + 4])
    relocs.add(s * 16 + o)
ENTRY = (h[11], h[10])
DSEG = 0x0BCE   # mov bp,0BCEh at the entry: DGROUP
DSLIN = DSEG * 16
IMGLEN = len(img)

def w(a): return struct.unpack('<H', img[a:a + 2])[0]

md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_16)
md.detail = True

insn = {}        # linear -> (seg, insn)
funcs = {}       # linear -> (seg, off)
labels = {}      # linear -> seg
xref = {}        # linear target -> set of caller linear
todo = []
segs = set()
dsrefs = {}      # linear insn -> DS offset (for comments)

def add_func(seg, off, frm=None):
    lin = seg * 16 + off
    if lin >= DSLIN or lin >= IMGLEN: return
    if frm is not None: xref.setdefault(lin, set()).add(frm)
    if lin not in funcs:
        funcs[lin] = (seg, off)
        todo.append((seg, off))
    segs.add(seg)

def add_label(seg, off, frm):
    lin = seg * 16 + off
    if lin >= DSLIN: return
    xref.setdefault(lin, set()).add(frm)
    labels[lin] = seg
    todo.append((seg, off))

def reloc_in(lin, n):
    return [a for a in range(lin, lin + n) if a in relocs]

def walk(seg, off):
    while True:
        lin = seg * 16 + off
        if lin in insn or lin >= DSLIN or off > 0xFFFF: return
        code = bytes(img[lin:lin + 16])
        try:
            i = next(md.disasm(code, off, 1))
        except StopIteration:
            return
        insn[lin] = (seg, i)
        m = i.mnemonic
        b = i.bytes
        nxt = off + i.size
        if b[0] == 0x9A:   # call far ptr
            toff, tseg = struct.unpack('<HH', b[1:5])
            if lin + 3 in relocs:
                add_func(tseg, toff, lin)
        elif b[0] == 0xEA:
            toff, tseg = struct.unpack('<HH', b[1:5])
            if lin + 3 in relocs:
                add_func(tseg, toff, lin)
            return
        elif m == 'call':
            op = i.operands[0]
            if op.type == x86.X86_OP_IMM:
                add_func(seg, op.imm & 0xFFFF, lin)
        elif m.startswith('j') or m.startswith('loop') or m == 'jcxz':
            op = i.operands[0]
            if op.type == x86.X86_OP_IMM:
                add_label(seg, op.imm & 0xFFFF, lin)
                if m == 'jmp': return
            else:
                # switch table: jmp word ptr cs:[bx + T]
                if m == 'jmp' and op.type == x86.X86_OP_MEM and op.mem.segment == x86.X86_REG_CS and op.mem.base != 0:
                    t = op.mem.disp & 0xFFFF
                    k = 0
                    while k < 256:
                        a = seg * 16 + t + 2 * k
                        if a in insn: break
                        tgt = w(a)
                        if tgt == 0 or tgt > 0xF000 or seg * 16 + tgt >= DSLIN: break
                        add_label(seg, tgt, lin); k += 1
                        swtab.setdefault(seg * 16 + t, k)
                        swtab[seg * 16 + t] = k
                return
        elif m in ('ret', 'retf', 'iret', 'hlt'):
            return
        # far pointer pushed: push seg (reloc) ; push imm off   or mov ax,seg ; push ax ; mov ax,off
        if b[0] == 0xB8 and (lin + 1) in relocs:
            pass
        # DS reference comment
        for op in i.operands:
            if op.type == x86.X86_OP_MEM and op.mem.base == 0 and op.mem.index == 0 and op.mem.segment in (0, x86.X86_REG_DS):
                dsrefs[lin] = op.mem.disp & 0xFFFF
        off = nxt

swtab = {}
add_func(*ENTRY)
while todo:
    walk(*todo.pop())

# far function pointers in code: mov ax,SEG(reloc) ... mov ax/bx/dx,OFF next to it
def scan_ptrs():
    found = 0
    for lin, (seg, i) in list(insn.items()):
        b = i.bytes
        if b[0] in (0xB8, 0xBA, 0xBB, 0xB9) and lin + 1 in relocs or (b[0] == 0x68 and lin + 1 in relocs):
            tseg = w(lin + 1)
            if tseg >= DSEG: continue
            # look at nearby insns for an immediate offset
            for dl in range(-12, 13):
                j = insn.get(lin + dl)
                if not j or dl == 0: continue
                jb = j[1].bytes
                if jb[0] in (0xB8, 0xBA, 0xBB, 0xB9, 0x68) and len(jb) == 3 and (lin + dl + 1) not in relocs:
                    toff = struct.unpack('<H', jb[1:3])[0]
                    t = tseg * 16 + toff
                    if t < DSLIN and img[t:t + 3] == b'\x55\x8b\xec' and t not in funcs:
                        add_func(tseg, toff, lin); found += 1
    return found
# far pointers in the data segment (relocated words preceded by an offset of a prologue)
for a in sorted(relocs):
    if a >= DSLIN:
        tseg = w(a); toff = w(a - 2)
        t = tseg * 16 + toff
        if tseg < DSEG and t < DSLIN and img[t:t + 3] == b'\x55\x8b\xec':
            add_func(tseg, toff, a)
while todo: walk(*todo.pop())
while scan_ptrs():
    while todo: walk(*todo.pop())

# remaining prologues: push bp; mov bp,sp (55 8B EC) in uncovered gaps
covered = bytearray(DSLIN)
for lin, (seg, i) in insn.items():
    for k in range(i.size): covered[lin + k] = 1
for t, n in swtab.items():
    for k in range(2 * n): covered[t + k] = 1
sortsegs = sorted(segs)
def seg_of(lin):
    s = [x for x in sortsegs if x * 16 <= lin]
    return s[-1] if s else 0
extra = 0
for a in range(DSLIN - 3):
    if not covered[a] and img[a:a + 3] == b'\x55\x8b\xec' and (a == 0 or covered[a - 1] or img[a-1] in (0xCB, 0xC3, 0x90, 0xCA)):
        s = seg_of(a)
        if a not in funcs:
            add_func(s, a - s * 16); extra += 1
            while todo: walk(*todo.pop())
            for lin, (seg, i) in insn.items():
                for k in range(i.size): covered[lin + k] = 1

def dsstr(off):
    a = DSLIN + off
    if a >= IMGLEN: return None
    s = bytearray()
    while a < IMGLEN and 32 <= img[a] < 127 and len(s) < 60:
        s.append(img[a]); a += 1
    if len(s) >= 3 and (a >= IMGLEN or img[a] in (0, 10, 13)):
        return s.decode()
    return None

def fname(lin):
    if lin in NAMES: return NAMES[lin]
    seg, off = funcs[lin]
    return 'f_%04X_%04X' % (seg, off)

out = sys.stdout
out.write('; DOC.EXE (Defender of the Crown, CGA) - generated by docdis.py\n')
out.write('; MZ header %d bytes, %d relocations, entry %04X:%04X, DGROUP at segment %04X\n' % (hdr, nrel, ENTRY[0], ENTRY[1], DSEG))
out.write('; %d routines, %d instructions; addresses are SEG:OFF in the load image (segment 0 = start of image)\n\n' % (len(funcs), len(insn)))
prev = None
lastseg = None
for lin in sorted(set(insn) | set(swtab)):
    if lin in swtab:
        seg = seg_of(lin)
        out.write('%04X:%04X  ; switch table, %d entries:' % (seg, lin - seg*16, swtab[lin]))
        for k in range(swtab[lin]): out.write(' %04X' % w(lin + 2 * k))
        out.write('\n'); prev = lin + 2 * swtab[lin]; continue
    seg, i = insn[lin]
    if prev is not None and lin != prev and lin > prev:
        gap = img[prev:lin]
        if len(gap) and not all(x in (0, 0x90) for x in gap):
            out.write('          ; %d bytes not disassembled\n' % len(gap))
    if seg != lastseg:
        out.write('\n;================ segment %04X ================\n' % seg); lastseg = seg
    if lin in funcs:
        callers = sorted(xref.get(lin, ()))
        out.write('\n%s proc  ; %04X:%04X' % (fname(lin), seg, i.address))
        if callers:
            cs = []
            for c in callers[:8]:
                cf = [f for f in funcs if f <= c]
                if c < DSLIN and cf: cs.append(fname(max(cf)))
                else: cs.append('data:%04X' % (c - DSLIN))
            out.write('  callers: ' + ', '.join(sorted(set(cs))) + (' ...' if len(callers) > 8 else ''))
        if lin in COMMENTS: out.write('\n; ' + COMMENTS[lin].replace('\n', '\n; '))
        out.write('\n')
    elif lin in labels:
        out.write('L_%04X_%04X:\n' % (seg, i.address))
    ops = i.op_str
    cmt = ''
    b = i.bytes
    if b[0] == 0x9A and lin + 3 in relocs:
        toff, tseg = struct.unpack('<HH', b[1:5])
        t = tseg * 16 + toff
        ops = fname(t) if t in funcs else ops
    elif i.mnemonic == 'call' and i.operands[0].type == x86.X86_OP_IMM:
        t = seg * 16 + (i.operands[0].imm & 0xFFFF)
        if t in funcs: ops = fname(t)
    if lin in dsrefs:
        o = dsrefs[lin]
        if o in DNAMES: cmt = DNAMES[o]
    for op in i.operands:
        if op.type == x86.X86_OP_IMM and i.mnemonic in ('mov', 'push') and op.size == 2:
            s = dsstr(op.imm & 0xFFFF)
            if s and (op.imm & 0xFFFF) > 0x40: cmt = (cmt + ' ' if cmt else '') + '"%s"' % s
    out.write('%04X:%04X  %-14s %-6s %s%s\n' % (seg, i.address, b.hex(), i.mnemonic, ops, ('   ; ' + cmt) if cmt else ''))
    prev = lin + i.size
sys.stderr.write('%d routines (%d from prologue scan), %d instructions, %d segments\n' % (len(funcs), extra, len(insn), len(segs)))
cov = sum(covered[:DSLIN]); sys.stderr.write('code coverage %d of %d bytes\n' % (cov, DSLIN))
