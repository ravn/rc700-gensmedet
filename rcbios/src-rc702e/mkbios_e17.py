#!/usr/bin/env python3
"""Generate RC702E rel.1.7 BIOS zmac source. rel.1.7 (mini, ORG D700, 5514 B) is
a distinct earlier RC702E (~59% of rel.2.01).  z80dasm reproduces the (relocated)
code byte-for-byte; only the data regions must be marked.  We map rel.2.01's data
regions to rel.1.7 addresses: strings are located by CONTENT (robust), tables by
a difflib address-shift.  Iterate DATA_REGIONS until verify is byte-identical.
Usage: python3 mkbios_e17.py ../extracted_bios/cpm22_56k_rc702e_rel1.7_mini.bin"""
import sys,os,re,subprocess,difflib
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
import mkbios_e201 as E
HERE=os.path.dirname(os.path.abspath(__file__))
ORG=0xD700
a=open(sys.argv[1] if len(sys.argv)>1 else HERE+'/../extracted_bios/cpm22_56k_rc702e_rel1.7_mini.bin','rb').read()
b=open(HERE+'/../extracted_bios/cpm22_56k_rc702e_rel2.01_mini.bin','rb').read()
sm=difflib.SequenceMatcher(None,a,b,autojunk=False)
def map_b2a(addr_b):
    o=addr_b-ORG
    for tag,i1,i2,j1,j2 in sm.get_opcodes():
        if tag in('equal','replace') and j1<=o<j2: return ORG+i1+(o-j1)
    return None
# build rel1.7 DATA regions: strings located by content in rel2.01 -> find same content in rel1.7
DATA=[]
for s,e,t,lab,com in E.DATA_REGIONS:
    if t=='string':
        content=b[s-ORG:e-ORG+1]
        # find matching string in a: try exact, else map
        idx=a.find(content)
        if idx>=0: DATA.append((ORG+idx, ORG+idx+len(content)-1, t, lab, com)); continue
    ns,ne=map_b2a(s),map_b2a(e)
    if ns is not None and ne is not None and ne>ns: DATA.append((ns,ne,t,lab,com))
DATA.sort()
# drop overlaps
clean=[]; last=-1
for s,e,t,lab,com in DATA:
    if s>last: clean.append((s,e,t,lab,com)); last=e
DATA=clean
END=ORG+len(a)
def blocks(path):
    blk=[]; pos=ORG
    for s,e,t,lab,com in DATA:
        if s>=END: break
        if pos<s: blk.append((pos,s-1,'code',None))
        bt='worddata' if t=='words' else 'bytedata'
        blk.append((s,min(e,END-1),bt,lab)); pos=e+1
    if pos<END: blk.append((pos,END-1,'code',None))
    with open(path,'w') as f:
        for i,(s,e,bt,lab) in enumerate(blk):
            f.write(f"{(lab.lower() if lab else 'c%03d'%i)}:\tstart 0x{s:04X} end 0x{e+1:04X} type {bt}\n")
def syms(path):
    open(path,'w').write('\n'.join(f"{lab}:\tequ\t0x{s:04X}" for s,e,t,lab,com in DATA)+'\n')
blk=HERE+'/rc702e_e17.blk'; sym=HERE+'/rc702e_e17.sym'; asm=HERE+'/rc702e_e17_raw.asm'; out=HERE+'/BIOS_E17.MAC'
blocks(blk); syms(sym)
r=subprocess.run(['z80dasm','-a','-l','-g',f'0x{ORG:04X}','-S',sym,'-b',blk,'-o',asm,os.path.abspath(sys.argv[1])],capture_output=True,text=True)
if r.returncode: print('z80dasm err',r.stderr,file=sys.stderr); sys.exit(1)
o=['; RC702E rel.1.7 BIOS - disassembled','; zmac -z --dri -DREL17 src-rc702e/BIOS_E17.MAC','','\t.Z80','']
hdr=True
for ln in open(asm):
    ln=ln.rstrip()
    if hdr:
        if ln.startswith(';') or ln=='': continue
        hdr=False
    if ln.strip().startswith('org '): ln=ln.replace('org ','ORG ')
    ln=re.sub(r'\bdefb\b','DB',ln); ln=re.sub(r'\bdefw\b','DW',ln)
    o.append(ln)
open(out,'w').write('\n'.join(o)+'\n')
print(f"wrote {out}: {len(DATA)} data regions, END 0x{END:04X}",file=sys.stderr)
