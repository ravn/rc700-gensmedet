
{*******************************************************}
{                                                       }
{            PolyFile Version 1.10 (CP/M-80)            }
{                                                       }
{                     DATMAN module                     }
{                                                       }
{                  Copyright (C) 1985                   }
{               PolyData MicroCenter A/S                }
{                                                       }
{*******************************************************}

{$A+,I-,R-}

TYPE
  p_str14 = STRING[14];
  datafile = RECORD
               CASE integer OF
                 0: (f: FILE OF byte;
                     ffre,nfre,int1,int2: integer);
                 1: (fil1,fil2,nrec,recl,crec,fil3: integer;
                     cdrv: byte;
                     cnam: array[1..8] of char;
                     ctyp: array[1..3] of char);
             END;
  p_keystr = STRING[maxksize];
  p_idxrec = RECORD
               dr,nr: integer;
               key: p_keystr;
             END;
  p_nodrec = RECORD
               ne: 0..nodesize;
               nr0: integer;
               e: ARRAY[1..nodesize] OF p_idxrec;
             END;
  p_nodrcp = ^p_nodrec;
  p_pthrec = RECORD
                nr,ep: integer;
              END;
  p_pthlst = ARRAY[1..maxdepth] OF p_pthrec;
  indexfile = RECORD
                d: datafile;
                dupkey: boolean;
                klen,rr,pp: integer;
                path: p_pthlst;
              END;
  p_indxfp = ^indexfile;
  p_nbfrec = RECORD
                n: p_nodrec;
                ifp: p_indxfp;
                nr: integer;
                upd: boolean;
              END;
  p_nbfrcp = ^p_nbfrec;
  p_nodbuf = ARRAY[1..nbufsize] OF p_nbfrec;
  p_nodmap = ARRAY[1..nbufsize] OF integer;
  p_recbuf = RECORD
                  CASE integer OF
                    0: (n: p_nbfrec);
                    1: (r: ARRAY[1..maxrsize] OF byte);
                END;

VAR
  iosts: integer;
  ok: boolean;
  p_rbuf: p_recbuf;
  p_nbuf: p_nodbuf;
  p_nmap: p_nodmap;

PROCEDURE iocheck(VAR datf: datafile; r: integer);
VAR
  p: integer;
BEGIN
  IF iosts<>0 THEN WITH datf DO
  BEGIN
    writeln;
    writeln('PolyFile I/O Error ',iosts);
    writeln('File ',chr(cdrv+64),':',cnam,'.',ctyp,' Record ',r);
    writeln('Program terminated');
    halt;
  END;
END;

PROCEDURE getrec(VAR datf: datafile; r: integer; VAR buffer);
VAR
  b: byte AT buffer;
BEGIN
  seek(datf.f,r); read(datf.f,b);
  iosts:=iores; iocheck(datf,r);
END;

PROCEDURE putrec(VAR datf: datafile; r: integer; VAR buffer);
VAR
  b: byte AT buffer;
BEGIN
  seek(datf.f,r); write(datf.f,b);
  iosts:=iores; iocheck(datf,r);
END;

PROCEDURE makefile(VAR datf: datafile; fnam: p_str14; reclen: integer);
BEGIN
  assign(datf.f,fnam); rewrite(datf.f); iosts:=iores;
  IF iosts=3 THEN ok:=false ELSE
  BEGIN
    iocheck(datf,0); datf.recl:=reclen; datf.ffre:=-1;
    datf.nfre:=0; datf.int1:=0; datf.int2:=0;
    move(datf.ffre,p_rbuf,8); putrec(datf,0,p_rbuf);
    ok:=true;
  END;
END;

PROCEDURE openfile(VAR datf: datafile; fnam: p_str14; reclen: integer);
BEGIN
  assign(datf.f,fnam); reset(datf.f); iosts:=iores;
  IF iosts=2 THEN ok:=false ELSE
  BEGIN
    IF iosts=1 THEN iosts:=0;
    iocheck(datf,0); datf.recl:=reclen;
    getrec(datf,0,p_rbuf); move(p_rbuf,datf.ffre,8);
    ok:=true;
  END;
END;

PROCEDURE closefile(VAR datf: datafile);
BEGIN
  move(datf.ffre,p_rbuf,8); putrec(datf,0,p_rbuf);
  close(datf.f); iosts:=iores; iocheck(datf,0);
END;

PROCEDURE addrec(VAR datf: datafile; VAR r: integer; VAR buffer);
BEGIN
  IF datf.ffre=-1 THEN r:=datf.nrec ELSE
  BEGIN
    r:=datf.ffre; getrec(datf,r,p_rbuf);
    move(p_rbuf,datf.ffre,2); datf.nfre:=datf.nfre-1;
  END;
  putrec(datf,r,buffer);
END;

PROCEDURE deleterec(VAR datf: datafile; r: integer);
BEGIN
  move(datf.ffre,p_rbuf,2); putrec(datf,r,p_rbuf);
  datf.ffre:=r; datf.nfre:=datf.nfre+1;
END;

FUNCTION filelen(VAR datf: datafile): integer;
BEGIN
  filelen:=datf.nrec;
END;

FUNCTION usedrecs(VAR datf: datafile): integer;
BEGIN
  usedrecs:=datf.nrec-datf.nfre-1;
END;

PROCEDURE initindex;
VAR
  i: integer;
BEGIN
  FOR i:=1 TO nbufsize DO
  BEGIN
    p_nbuf[i].ifp:=NIL; p_nbuf[i].upd:=false; p_nmap[i]:=i;
  END;
END;

PROCEDURE p_pack(VAR n: p_nodrec; klen: integer);
VAR
  i: integer;
  p: ARRAY[0..maxint] OF byte AT n;
BEGIN
  IF klen<>maxksize THEN
  FOR i:=1 TO nodesize DO move(n.e[i],p[(i-1)*(klen+5)+3],klen+5);
END;

PROCEDURE p_unpack(VAR n: p_nodrec; klen: integer);
VAR
  i: integer;
  p: ARRAY[0..maxint] OF byte AT n;
BEGIN
  IF klen<>maxksize THEN
  FOR i:=nodesize DOWNTO 1 DO move(p[(i-1)*(klen+5)+3],n.e[i],klen+5);
END;

PROCEDURE makeindex(VAR idxf: indexfile; fnam: p_str14; keylen,s: integer);
VAR
  k: integer;
BEGIN
  k:=(keylen+5)*nodesize+3;
  makefile(idxf.d,fnam,k);
  idxf.dupkey:=s<>0; idxf.klen:=keylen;
  idxf.rr:=0; idxf.pp:=0;
END;

PROCEDURE openindex(VAR idxf: indexfile; fnam: p_str14; keylen,s: integer);
VAR
  k: integer;
BEGIN
  k:=(keylen+5)*nodesize+3;
  openfile(idxf.d,fnam,k);
  idxf.dupkey:=s<>0; idxf.klen:=keylen;
  idxf.rr:=idxf.d.int1; idxf.pp:=0;
END;

PROCEDURE closeindex(VAR idxf: indexfile);
VAR
  i: integer;
BEGIN
  FOR i:=1 TO nbufsize DO WITH p_nbuf[i] DO
  IF ifp=ptr(addr(idxf)) THEN
  BEGIN
    ifp:=NIL;
    IF upd THEN
    BEGIN
      p_pack(n,idxf.klen); putrec(idxf.d,nr,n); upd:=false;
    END;
  END;
  idxf.d.int1:=idxf.rr; closefile(idxf.d);
END;

PROCEDURE p_last(i: integer);
VAR
  j,k: integer;
BEGIN
  j:=1; WHILE (p_nmap[j]<>i) AND (j<nbufsize) DO j:=j+1;
  FOR k:=j TO nbufsize-1 DO p_nmap[k]:=p_nmap[k+1];
  p_nmap[nbufsize]:=i;
END;

PROCEDURE p_getn(VAR idxf: indexfile; r: integer; VAR np: p_nodrcp);
VAR
  i,j,k: integer;
  found: boolean;
BEGIN
  found:=false;
  FOR j:=1 TO nbufsize DO IF NOT found THEN WITH p_nbuf[j] DO
  IF (ifp=ptr(addr(idxf))) AND (nr=r) THEN
  BEGIN
    i:=j; found:=true;
  END;
  IF NOT found THEN
  BEGIN
    i:=p_nmap[1];
    WITH p_nbuf[i] DO
    BEGIN
      IF upd THEN
      BEGIN
        p_pack(n,ifp^.klen); putrec(ifp^.d,nr,n);
      END;
      getrec(idxf.d,r,n); p_unpack(n,idxf.klen);
      ifp:=ptr(addr(idxf)); nr:=r; upd:=false;
    END;
  END;
  p_last(i); np:=ptr(addr(p_nbuf[i]));
END;

PROCEDURE p_newn(VAR idxf: indexfile; VAR r: integer; VAR np: p_nodrcp);
VAR
  i: integer;
BEGIN
  i:=p_nmap[1];
  WITH p_nbuf[i] DO
  BEGIN
    IF upd THEN
    BEGIN
      p_pack(n,ifp^.klen); putrec(ifp^.d,nr,n);
    END;
    addrec(idxf.d,r,n);
    ifp:=ptr(addr(idxf)); nr:=r; upd:=false;
  END;
  p_last(i); np:=ptr(addr(p_nbuf[i]));
END;

PROCEDURE p_updn(np: p_nodrcp);
VAR
  p: p_nbfrcp AT np;
BEGIN
  p^.upd:=true;
END;

PROCEDURE p_retn(VAR np: p_nodrcp);
VAR
  p: p_nbfrcp AT np;
BEGIN
  WITH p^ DO
  BEGIN
    deleterec(ifp^.d,nr); ifp:=NIL; upd:=false;
  END;
END;

PROCEDURE p_xkey(VAR k; klen: integer);
VAR
  key: p_keystr AT k;
BEGIN
  IF ord(key[0])>klen THEN key[0]:=chr(klen);
END;

FUNCTION p_ckey(VAR k1,k2; dr1,dr2: integer; dup: boolean): integer;
VAR
  key1: p_keystr AT k1;
  key2: p_keystr AT k2;
BEGIN
  IF key1=key2 THEN
  IF dup THEN p_ckey:=dr1-dr2 ELSE p_ckey:=0 ELSE
  IF key1>key2 THEN p_ckey:=1 ELSE p_ckey:=-1;
END;

PROCEDURE clearkey(VAR idxf: indexfile);
BEGIN
  idxf.pp:=0;
END;
