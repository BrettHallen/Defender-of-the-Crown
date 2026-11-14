#!/usr/bin/env python3
"""Recursive disassembler for a flat 16-bit binary (boot code, GameSYS, the game program).
Usage: flatdis.py FILE BASE ENTRY[,ENTRY...] [names.txt] [--prologues] [--ds DATAFILE]
Follows near calls and jumps from the entries and switch tables (jmp cs:[bx+T]);
with --prologues also every C prologue (push bp / mov bp,sp, alone or after push si /
push di) in the bytes not yet reached. --ds names a file loaded as the data segment
(the booter's BH): DS strings are shown as comments. Unreached bytes are shown as data.
names.txt lines: HEXADDR name [; comment]"""
import sys, capstone, struct
from capstone import x86
args = [a for a in sys.argv[1:]]
prologues = '--prologues' in args
if prologues: args.remove('--prologues')
dsdata = None
if '--ds' in args:
    i = args.index('--ds'); dsdata = open(args[i + 1], 'rb').read(); del args[i:i + 2]
data = open(args[0], 'rb').read()
base = int(args[1], 16)
entries = [int(x, 16) for x in args[2].split(',')]
names = {}
if len(args) > 3:
    for l in open(args[3]):
        l = l.strip()
        if not l or l.startswith('#'): continue
        a, n = l.split(None, 1)
        names[int(a, 16)] = n
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_16); md.detail = True
insn = {}; funcs = set(entries); labels = set(); todo = list(entries)
end = base + len(data)
swtab = {}
valtab = {}
owner = bytearray(len(data))
# A program that starts with a near jmp over a block of data (AA/AB/AC: 0103 up to main):
# that block is data, never code (otherwise the prologue scan finds code-like bytes in it).
datarange = None
if entries[0] == base and data[0] in (0xE9, 0xEB):
    n = 3 if data[0] == 0xE9 else 2
    tgt = (base + n + (struct.unpack('<h', data[1:3])[0] if n == 3 else struct.unpack('<b', data[1:2])[0])) & 0xFFFF
    if base + n < tgt < end:
        datarange = (base + n, tgt)
        for k in range(n, tgt - base): owner[k] = 1
def run():
  while todo:
      a = todo.pop()
      while base <= a < end and a not in insn:
          try: i = next(md.disasm(data[a - base:a - base + 16], a, 1))
          except StopIteration: break
          if any(owner[a - base + k] for k in range(i.size)): break   # overlaps code already found
          for k in range(i.size): owner[a - base + k] = 1
          insn[a] = i
          m = i.mnemonic
          if m == 'call' and i.operands[0].type == x86.X86_OP_IMM:
              t = i.operands[0].imm & 0xFFFF; funcs.add(t); todo.append(t)
          elif (m.startswith('j') or m.startswith('loop')) and i.operands[0].type == x86.X86_OP_IMM:
              t = i.operands[0].imm & 0xFFFF; labels.add(t); todo.append(t)
              if m == 'jmp': break
          elif m == 'jmp' and i.operands[0].type == x86.X86_OP_MEM and i.operands[0].mem.segment == x86.X86_REG_CS and i.operands[0].mem.base != 0 and i.operands[0].mem.disp < 0x100:
              # value search: mov cx, N / mov bx, VALUES / cmp cs:[bx], ax ... loop / jmp cs:[bx + 2N] (the targets follow the N values)
              n = tv = None
              for b in range(a - 1, a - 30, -1):
                  j = insn.get(b)
                  if j is not None and j.mnemonic == 'mov' and j.op_str.startswith('bx, 0x') and tv is None: tv = j.operands[1].imm & 0xFFFF
                  if j is not None and j.mnemonic == 'mov' and j.op_str.startswith('cx, ') and j.operands[1].type == x86.X86_OP_IMM and n is None: n = j.operands[1].imm & 0xFFFF
              if n and tv and i.operands[0].mem.disp == 2 * n and base <= tv and tv + 4 * n <= end:
                  valtab[tv] = n; t = tv + 2 * n; swtab[t] = n
                  for k in range(n):
                      tg = struct.unpack('<H', data[t + 2 * k - base:t + 2 * k + 2 - base])[0]
                      if base <= tg < end: labels.add(tg); todo.append(tg)
              break
          elif m == 'jmp' and i.operands[0].type == x86.X86_OP_MEM and i.operands[0].mem.segment == x86.X86_REG_CS and i.operands[0].mem.base != 0:
              t = i.operands[0].mem.disp & 0xFFFF; k = 0
              # table size from the bounds check just before (cmp reg, n / ja or jbe): n + 1 entries
              lim = 64
              for b in range(a - 1, a - 40, -1):
                  j = insn.get(b)
                  if j is not None and j.mnemonic == 'cmp' and len(j.operands) == 2 and j.operands[1].type == x86.X86_OP_IMM:
                      lim = (j.operands[1].imm & 0xFFFF) + 1; break
              while k < lim and base <= t + 2 * k + 2 <= end and (t + 2 * k) not in insn:
                  tg = struct.unpack('<H', data[t + 2 * k - base:t + 2 * k + 2 - base])[0]
                  if not (base <= tg < end): break
                  labels.add(tg); todo.append(tg); k += 1
              if k: swtab[t] = k
              break
          elif m in ('jmp', 'ret', 'retf', 'iret', 'hlt', 'ljmp'):
              break
          a += i.size
run()
if prologues:
    while True:
        cov = bytearray(end - base)
        for a, i in insn.items():
            cov[a - base:a - base + i.size] = b'\1' * i.size
        for t, k in swtab.items(): cov[t - base:t - base + 2 * k] = b'\1' * (2 * k)
        for t, k in valtab.items(): cov[t - base:t - base + 2 * k] = b'\1' * (2 * k)
        if datarange: cov[datarange[0] - base:datarange[1] - base] = b'\1' * (datarange[1] - datarange[0])
        new = 0
        for o in range(len(data) - 5):
            if cov[o]: continue
            if data[o:o + 3] == b'\x55\x8b\xec' and not (o >= 2 and data[o - 2:o] == b'\x56\x57') or data[o:o + 5] == b'\x56\x57\x55\x8b\xec':
                if o and not cov[o - 1] and data[o - 1] not in (0xC3, 0x90, 0xCB, 0xCF): continue
                if o and not cov[o - 1] and not (o >= 2 and cov[o - 2]): continue   # after a ret byte that is itself code
                funcs.add(base + o); todo.append(base + o); new += 1
                run()
                break
        if not new: break
def dsstr(o):
    if dsdata is None or o >= len(dsdata) or o < 0x20: return None
    e = o
    while e < len(dsdata) and 32 <= dsdata[e] < 127 and e - o < 50: e += 1
    if e - o >= 4 and e < len(dsdata) and dsdata[e] == 0: return dsdata[o:e].decode()
    return None

def dialogtxt(a, i):
    # mov bx, STRUCT / mov dx, ds / mov ax, bx / mov cx, 0Ch / call (copy the 12-byte struct onto the stack) / call dialog:
    # the struct is x (4-pixel units), y, number of lines, width, icon (-2 no box, -3 box only), ..., word at +9 = table of line pointers
    if dsdata is None or i.mnemonic != 'mov' or not i.op_str.startswith('bx, 0x'): return None
    b = a + i.size; seq = []
    for _ in range(4):
        j = insn.get(b)
        if j is None: return None
        seq.append(j.mnemonic + ' ' + j.op_str); b += j.size
    if seq[:3] != ['mov dx, ds', 'mov ax, bx', 'mov cx, 0xc'] or not seq[3].startswith('call'): return None
    o = i.operands[1].imm & 0xFFFF
    if o + 12 > len(dsdata): return None
    n = dsdata[o + 2]; tp = struct.unpack('<H', dsdata[o + 9:o + 11])[0]; t = []
    for k in range(min(n, 30)):
        if tp + 2 * k + 2 > len(dsdata): break
        q = struct.unpack('<H', dsdata[tp + 2 * k:tp + 2 * k + 2])[0]
        e = dsdata.find(b'\0', q)
        if 0 < q < len(dsdata) and e > 0: t.append(dsdata[q:e].decode('latin1').strip('@ ').strip())
    t = ' / '.join(x for x in t if x)
    if len(t) > 70: t = t[:67] + '...'
    return '   ; dialog box (x %d, y %d, %d lines): "%s"' % (dsdata[o], dsdata[o + 1], n, t)

def nm(t):
    return names.get(t, ('sub_%04X' if t in funcs else 'L_%04X') % t)
a = base; out = sys.stdout
while a < end:
    if a in insn:
        i = insn[a]
        if a in funcs: out.write('\n%s:%s\n' % (nm(a).split(';')[0].strip(), (' ;' + nm(a).split(';',1)[1]) if ';' in nm(a) else ''))
        elif a in labels: out.write('%s:%s\n' % (nm(a).split(';')[0].strip(), (' ;' + nm(a).split(';',1)[1]) if ';' in nm(a) else ''))
        ops = i.op_str
        if i.mnemonic in ('call',) or i.mnemonic.startswith('j') or i.mnemonic.startswith('loop'):
            if i.operands[0].type == x86.X86_OP_IMM: ops = nm(i.operands[0].imm & 0xFFFF).split(';')[0].strip()
        cm = ''
        if dsdata is not None and i.mnemonic in ('mov', 'push') and len(i.operands) and i.operands[-1].type == x86.X86_OP_IMM:
            iv = i.operands[-1].imm & 0xFFFF
            st = dsstr(iv) if iv & 0xFF else None     # xx00h values are usually segments
            if st: cm = '   ; "%s"' % st
            dt = dialogtxt(a, i)
            if dt: cm = dt
        out.write('%04X  %-14s %-6s %s%s\n' % (a, i.bytes.hex(), i.mnemonic, ops, cm)); a += i.size
    elif a in valtab:
        k = valtab[a]
        out.write('%04X  dw %s   ; switch values\n' % (a, ' '.join('%04Xh' % struct.unpack('<H', data[a - base + 2 * j:a - base + 2 * j + 2])[0] for j in range(k)))); a += 2 * k
    elif a in swtab:
        k = swtab[a]
        out.write('%04X  dw %s   ; switch table\n' % (a, ' '.join('L_%04X' % struct.unpack('<H', data[a - base + 2 * j:a - base + 2 * j + 2])[0] for j in range(k)))); a += 2 * k
    else:
        b = a
        while b < end and b not in insn and b not in swtab and b not in valtab and b - a < 16: b += 1
        chunk = data[a - base:b - base]
        txt = ''.join(chr(c) if 32 <= c < 127 else '.' for c in chunk)
        out.write('%04X  db %-48s ; %s\n' % (a, ' '.join('%02x' % c for c in chunk), txt)); a = b
