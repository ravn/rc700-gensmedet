#!/usr/bin/env python3
"""Generate RC703 rel.1.1 BIOS zmac source from the extracted binary.

rel.1.1 (QD, 9600 B, ORG D480) is 89 % identical to rel.1.2; it lacks two
512-byte blocks that 1.2 inserted (b-offsets 0x0F81 and 0x1380) and has its own
1024-byte tail.  We derive rel.1.1's data-region layout by address-shifting
rel.1.2's regions through the difflib map (regions before the inserts are
unshifted; the middle equal-block shifts -0x400).  Only block (code/data)
boundaries affect byte-identity, so symbols are minimal.

Usage: python3 mkbios_rel11.py ../extracted_bios/cpm22_56k_rel1.1_rc703.bin
"""
import sys, subprocess, os, re, difflib
import mkbios  # reuse rel.1.2 region tables

ORG = 0xD480
HERE = os.path.dirname(os.path.abspath(__file__))
b11 = open(sys.argv[1] if len(sys.argv)>1 else
           os.path.join(HERE,'../extracted_bios/cpm22_56k_rel1.1_rc703.bin'),'rb').read()
b12 = open(os.path.join(HERE,'../extracted_bios/cpm22_56k_rel1.2_rc703.bin'),'rb').read()

# a=rel1.1, b=rel1.2 : build offset map a->addr from difflib
sm = difflib.SequenceMatcher(None, b11, b12, autojunk=False)
def map12to11(addr12):
    """rel1.2 address -> rel1.1 address, or None if 1.2-only."""
    o12 = addr12 - ORG
    for tag,i1,i2,j1,j2 in sm.get_opcodes():
        if tag in ('equal','replace') and j1 <= o12 < j2:
            return ORG + i1 + (o12 - j1)
    return None

CODE_END = 0xE600   # = D480 + 0x1180  (rel1.2 EA00 minus the two 512-B inserts)

# shift rel1.2 DATA_REGIONS into rel1.1 addresses (keep those below CODE_END)
DATA=[]
for s,e,t,lab,com in mkbios.DATA_REGIONS:
    ns, ne = map12to11(s), map12to11(e)
    if ns is None or ne is None: continue
    if ns >= CODE_END: continue
    DATA.append((ns, ne, t, lab, com))
DATA.sort()

def blocks_file(path):
    blks=[]; pos=ORG
    for s,e,t,lab,com in DATA:
        if s>=CODE_END: break
        if pos<s: blks.append((pos,s-1,'code',None))
        bt='worddata' if t=='words' else 'bytedata'
        blks.append((s,min(e,CODE_END-1),bt,lab))
        pos=e+1
    if pos<CODE_END: blks.append((pos,CODE_END-1,'code',None))
    if CODE_END<ORG+len(b11): blks.append((CODE_END,ORG+len(b11)-1,'bytedata','TAIL'))
    with open(path,'w') as f:
        for i,(s,e,bt,lab) in enumerate(blks):
            name=(lab.lower() if lab else f'code{i:03d}')
            f.write(f'{name}:\tstart 0x{s:04X} end 0x{e+1:04X} type {bt}\n')

def sym_file(path):
    with open(path,'w') as f:
        for s,e,t,lab,com in DATA:
            f.write(f'{lab}:\tequ\t0x{s:04X}\n')

blk=os.path.join(HERE,'rc703_rel11.blk'); sym=os.path.join(HERE,'rc703_rel11.sym')
asm=os.path.join(HERE,'rc703_rel11_raw.asm'); out=os.path.join(HERE,'BIOS_REL11.MAC')
binp=os.path.abspath(sys.argv[1] if len(sys.argv)>1 else os.path.join(HERE,'../extracted_bios/cpm22_56k_rel1.1_rc703.bin'))
blocks_file(blk); sym_file(sym)
r=subprocess.run(['z80dasm','-a','-l','-g',f'0x{ORG:04X}','-S',sym,'-b',blk,'-o',asm,binp],capture_output=True,text=True)
if r.returncode: print('z80dasm err:',r.stderr,file=sys.stderr); sys.exit(1)
# convert to zmac
lines=open(asm).read().splitlines()
o=['; RC703 rel.1.1 BIOS — disassembled from cpm22_56k_rel1.1_rc703.bin',
   '; Assembled with: zmac -z --dri -DREL11 src-rc703/BIOS_REL11.MAC','','\t.Z80','']
hdr=True
for ln in lines:
    ln=ln.rstrip()
    if hdr:
        if ln.startswith(';') or ln=='' : continue
        hdr=False
    if ln.strip().startswith('org '): ln=ln.replace('org ','ORG ')
    ln=re.sub(r'\bdefb\b','DB',ln); ln=re.sub(r'\bdefw\b','DW',ln)
    o.append(ln)
open(out,'w').write('\n'.join(o)+'\n')
print(f'wrote {out}  ({len(DATA)} data regions, code_end 0x{CODE_END:04X})',file=sys.stderr)
