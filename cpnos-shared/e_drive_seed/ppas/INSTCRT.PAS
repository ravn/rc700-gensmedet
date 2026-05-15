PROCEDURE crt;
CONST
  pa1: str36 = 'A. Screen width (in characters)...: ';
  pb1: str36 = 'B. Screen height (in lines).......: ';
  pc1: str36 = 'C. GOTOXY lead-in sequence........: ';
  pd1: str36 = 'D. GOTOXY separator sequence......: ';
  pe1: str36 = 'E. GOTOXY terminator sequence.....: ';
  pf1: str36 = 'F. Line before column (YES/NO)....: ';
  pg1: str36 = 'G. Coordinate offset..............: ';
  ph1: str36 = 'H. Coordinate format (0/2/3)......: ';
  pa2: str36 = 'A. CLRHOM sequence................: ';
  pb2: str36 = 'B. CLREOS sequence................: ';
  pc2: str36 = 'C. CLREOL sequence................: ';
  pd2: str36 = 'D. INSLIN sequence................: ';
  pe2: str36 = 'E. DELLIN sequence................: ';
  pa3: str36 = 'A. RVSON sequence.................: ';
  pb3: str36 = 'B. RVSOFF sequence................: ';
  pc3: str36 = 'C. INTON sequence.................: ';
  pd3: str36 = 'D. INTOFF sequence................: ';
  pe3: str36 = 'E. ULNON sequence.................: ';
  pf3: str36 = 'F. ULNOFF sequence................: ';
  pg3: str36 = 'G. BLKON sequence.................: ';
  ph3: str36 = 'H. BLKOFF sequence................: ';
  pi3: str36 = 'I. ALLOFF sequence................: ';

VAR
  sec: integer;
  ch,mc,first,last: char;

PROCEDURE help1;
BEGIN
  writeln('All  fields  on this submenu must be filled in for PolyPascal  to');
  writeln('operate correctly.');
  writeln;
  writeln('SCREEN WIDTH.  This  field defines the number of  characters  per');
  writeln('line  on your video display.  If the display scrolls when writing');
  writeln('to the bottom right character position,  then specify the  screen');
  writeln('width less one.');
  writeln;
  writeln('SCREEN HEIGHT.  This  field defines the number of lines  on  your');
  writeln('video display. Always specify the exact value.');
  writeln;
  writeln('Character  sequences are entered as sequences of hex values  bet-');
  writeln('ween  00 and FF.  Each hex value must be separated from the  sur-');
  writeln('rounding ones by at least one blank.  To enter an empty sequence,');
  writeln('simply enter a blank line.');
  writeln;
  writeln('GOTOXY LEAD-IN SEQUENCE. The character sequence sent prior to the');
  writeln('coordinates. The maximum length is 8.');
  writeln;
  pressreturn;
  writeln('GOTOXY SEPARATOR SEQUENCE.  The character sequence  sent  between');
  writeln('the coordinates. The maximum length is 4.');
  writeln;
  writeln('GOTOXY TERMINATOR SEQUENCE. The character sequence sent after the');
  writeln('coordinates. The maximum length is 4.');
  writeln;
  writeln('LINE BEFORE COLUMN. This field should be set to YES if your video');
  writeln('display  requires  the line coordinate (Y) to be sent before  the');
  writeln('column coordinate (X). Otherwise it should be set to NO.');
  writeln;
  writeln('COORDINATE OFFSET.  This field defines the value (in decimal)  to');
  writeln('be  added to the coordinates before they are transmitted.  If the');
  writeln('coordinate format (see below) is 0,  then 32 is normally used. If');
  writeln('the coordinate format is 2 or 3, then 0 or 1 is normally used.');
  writeln;
  writeln('COORDINATE FORMAT.  A value of 0 in this field indicates that the');
  writeln('coordinates  are  to be transmitted as single bytes using  binary');
  writeln('format.  Other values (2 or 3) indicate that the coordinates  are');
  writeln('to  be transmitted as decimal character strings of 2 or 3 charac-');
  writeln('ters.');
  writeln;
  pressreturn;
END;

PROCEDURE help2;
BEGIN
  writeln('CLRHOM SEQUENCE.  The  function sequence which clears the  screen');
  writeln('and returns the cursor to the top left corner.  The maximum is 8.');
  writeln('This  function sequence must be specified for PolyPascal to  ope-');
  writeln('rate correctly.');
  writeln;
  writeln('All of the following function sequences are optional. The maximum');
  writeln('length is 8 for all sequences.');
  writeln;
  writeln('CLREOS SEQUENCE. The function sequence which clears all character');
  writeln('positions from the cursor to the end of the screen.');
  writeln;
  writeln('CLREOL SEQUENCE. The function sequence which clears all character');
  writeln('positions from the cursor to the end of the current line.');
  writeln;
  writeln('INSLIN SEQUENCE.  The function sequence which scrolls the current');
  writeln('line, and all lines below it, down, and clears the current line.');
  writeln;
  writeln('DELLIN SEQUENCE.  The function sequence which deletes the current');
  writeln('line,  and  scrolls up all lines below it,  with a blank line ap-');
  writeln('pearing at the bottom. The maximum length is 8.');
  writeln;
  pressreturn;
END;

PROCEDURE help3;
BEGIN
  writeln('All of the following function sequences are optional. The maximum');
  writeln('length is 8 for all sequences.');
  writeln;
  writeln('RVSON SEQUENCE. Turns on reverse video.');
  writeln;
  writeln('RVSOFF SEQUENCE. Turns off reverse video.');
  writeln;
  writeln('INTON SEQUENCE. Turns on increased/decreased intensity.');
  writeln;
  writeln('INTOFF SEQUENCE. Turns off increased/decreased intensity.');
  writeln;
  writeln('ULNON SEQUENCE. Turns on underlining.');
  writeln;
  writeln('ULNOFF SEQUENCE. Turns off underlining.');
  writeln;
  writeln('BLKON SEQUENCE. Turns on character blink.');
  writeln;
  writeln('BLKOFF SEQUENCE. Turns off character blink.');
  writeln;
  writeln('ALLOFF SEQUENCE. Turns off all character attributes.');
  writeln;
  pressreturn;
END;

BEGIN {crt}
  sec:=1;
  WITH data DO
  REPEAT
    writeln('CRT CONFIGURATION TABLE (SECTION ',sec,'):');
    writeln;
    CASE sec OF
      1: BEGIN
           writeln(pa1,width);
           writeln(pb1,height);
           writeln(pc1,hexseq(gxyls));
           writeln(pd1,hexseq(gxyss));
           writeln(pe1,hexseq(gxyts));
           writeln(pf1,yesno(255-colblin));
           writeln(pg1,coorofs);
           writeln(ph1,coorfmt);
           mc:='H';
         END;
      2: BEGIN
           writeln(pa2,hexseq(clhs));
           writeln(pb2,hexseq(cess));
           writeln(pc2,hexseq(cels));
           writeln(pd2,hexseq(ilns));
           writeln(pe2,hexseq(dlns));
           mc:='E';
         END;
      3: BEGIN
           writeln(pa3,hexseq(rons));
           writeln(pb3,hexseq(rofs));
           writeln(pc3,hexseq(ions));
           writeln(pd3,hexseq(iofs));
           writeln(pe3,hexseq(uons));
           writeln(pf3,hexseq(uofs));
           writeln(pg3,hexseq(bons));
           writeln(ph3,hexseq(bofs));
           writeln(pi3,hexseq(aofs));
           mc:='I';
         END;
    END;
    writeln;
    writeln('Press RETURN to view more');
    writeln;
    ch:=select('Edit(A-'+mc+'), All(Z), Exit(X), Help(Y)',
      ['A'..mc,'Z','X','Y',^M]);
    IF ch=^M THEN
    IF sec=3 THEN sec:=1 ELSE sec:=sec+1 ELSE
    BEGIN
      IF ch='Z' THEN
      BEGIN
        first:='A'; last:=mc;
      END ELSE
      BEGIN
        first:=ch; last:=ch;
      END;
      FOR ch:=first TO last DO
      CASE sec OF
        1: CASE ch OF
             'A': BEGIN
                    write(pa1); width:=readnum(40,255);
                  END;
             'B': BEGIN
                    write(pb1); height:=readnum(8,255);
                  END;
             'C': BEGIN
                    write(pc1); gxyls:=readseq(8);
                  END;
             'D': BEGIN
                    write(pd1); gxyss:=readseq(4);
                  END;
             'E': BEGIN
                    write(pe1); gxyts:=readseq(4);
                  END;
             'F': BEGIN
                    write(pf1); colblin:=255-readyn;
                  END;
             'G': BEGIN
                    write(pg1); coorofs:=readnum(0,255);
                  END;
             'H': BEGIN
                    write(ph1); coorfmt:=readnum(0,3);
                  END;
             'Y': help1;
           END;
        2: CASE ch OF
             'A': BEGIN
                    write(pa2); clhs:=readseq(8);
                  END;
             'B': BEGIN
                    write(pb2); cess:=readseq(8);
                  END;
             'C': BEGIN
                    write(pc2); cels:=readseq(8);
                  END;
             'D': BEGIN
                    write(pd2); ilns:=readseq(8);
                  END;
             'E': BEGIN
                    write(pe2); dlns:=readseq(8);
                  END;
             'Y': help2;
           END;
        3: CASE ch OF
             'A': BEGIN
                    write(pa3); rons:=readseq(8);
                  END;
             'B': BEGIN
                    write(pb3); rofs:=readseq(8);
                  END;
             'C': BEGIN
                    write(pc3); ions:=readseq(8);
                  END;
             'D': BEGIN
                    write(pd3); iofs:=readseq(8);
                  END;
             'E': BEGIN
                    write(pe3); uons:=readseq(8);
                  END;
             'F': BEGIN
                    write(pf3); uofs:=readseq(8);
                  END;
             'G': BEGIN
                    write(pg3); bons:=readseq(8);
                  END;
             'H': BEGIN
                    write(ph3); bofs:=readseq(8);
                  END;
             'I': BEGIN
                    write(pi3); aofs:=readseq(8);
                  END;
             'Y': help3;
           END;
      END;
      IF ch IN ['A'..mc] THEN writeln;
    END;
  UNTIL ch='X';
END;

PROCEDURE keyboard;
TYPE
  keyrec = RECORD
             val: byte; str: str12;
           END;
CONST
  stdkey: ARRAY[1..42] OF str2 = (
    ^J,^S,^D,^A,^F,^Q^S,^Q^D,^E,^X,^Q^E,^Q^X,^R,^C,^Q^R,^Q^C,
    ^H,^G,^Q^H,^Q^Y,^T,^Y,^M,^I,^N,^V,^Z,^B,^W,^Q^F,^Q^A,
    ^L,^K^B,^K^K,^K^Y,^K^C,^K^V,^K^P,^K^R,^K^W,^K^H,^K^D,^K^X);
VAR
  c,i,n,m: integer;
  ch,mc: char;
  s: str12;
  akey: ARRAY[1..50] OF keyrec;

FUNCTION keystr(ch: char): str3;
BEGIN
  CASE ch OF
    @32..@126,@128..@255: keystr:='"'+ch+'"';
    @8: keystr:='BS';
    @13: keystr:='CR';
    @27: keystr:='ESC';
    @127: keystr:='DEL';
  OTHERWISE
    keystr:='^'+chr(ord(ch)+64);
  END;
END;

FUNCTION keyseq(ks: str12): str48;
VAR
  i: integer;
  s: str48;
BEGIN
  s:='';
  FOR i:=1 TO len(ks) DO s:=s+keystr(ks[i])+' ';
  keyseq:=copy(s,1,len(s)-1);
END;

PROCEDURE delakey(i: integer);
VAR
  p: integer;
BEGIN
  FOR p:=i+1 TO n DO akey[p-1]:=akey[p]; n:=n-1;
END;

PROCEDURE addakey;
VAR
  i,sl: integer;
  ch: char;
  s: str12;
BEGIN
  sl:=0; FOR i:=1 TO n DO sl:=sl+len(akey[n].str)+2;
  IF (n=50) OR (sl>240) THEN
  writeln('No room for further definitions') ELSE
  BEGIN
    cbreak:=false; write('Standard: ');
    REPEAT
      read(kbd,ch);
      i:=1; WHILE (i<42) AND (ch<>stdkey[i][1]) DO i:=i+1;
      IF stdkey[i][1]=ch THEN
      BEGIN
        s:=ch; write(keyseq(ch),' '); sl:=len(keyseq(ch))+1;
        IF len(stdkey[i])=2 THEN
        BEGIN
          read(kbd,ch); s:=s+ch;
          i:=1; WHILE (i<42) AND (s<>stdkey[i]) DO i:=i+1;
          IF s=stdkey[i] THEN
          BEGIN
            s:=s+ch; write(keyseq(ch),' '); sl:=sl+len(keyseq(ch))+1;
          END ELSE
          BEGIN
            s:=''; backsp(sl);
          END;
        END;
      END ELSE s:='';
    UNTIL s<>'';
    write('':9-sl,'Alternate: ');
    s:='';
    REPEAT
      read(kbd,ch);
      IF (len(s)<12) AND (ch<>^M) THEN
      BEGIN
        IF len(s)>=1 THEN
        IF ch IN [^A..^Z] THEN ch:=chr(ord(ch)+64) ELSE
        IF ch IN ['a'..'z'] THEN ch:=chr(ord(ch)-32);
        write(keystr(ch),' '); s:=s+ch;
      END;
    UNTIL ch=^M;
    n:=n+1; akey[n].val:=i; akey[n].str:=s;
    writeln; cbreak:=true;
  END;
  writeln;
END;

PROCEDURE help;
BEGIN
  writeln('To be able to benefit fully from the special keys offered by your');
  writeln('keyboard,  PolyPascal allows you to define alternate keys to  in-');
  writeln('voke  selected editor functions.  A typical example  of alternate');
  writeln('keys is defining your  cursor arrows to do the same as ^S, ^D, ^E');
  writeln('and ^X.');
  writeln;
  writeln('To  add  an alternate key definition,  you must first select  the');
  writeln('function for which you want to create an alternative. This you do');
  writeln('by entering the standard key sequence,  i.e.  the sequence listed');
  writeln('in  the manual.  Once you have selected a function,  you will  be');
  writeln('prompted for an alternate key sequence,  to which you must answer');
  writeln('by entering the alternate sequence.  To end the alternate sequen-');
  writeln('ce, press RETURN.');
  writeln;
  writeln('Note  that it is actually possible to override the  standard  key');
  writeln('sequences.  If  you for instance define ^J to be an alternate key');
  writeln('for the ^X function,  the original ^J function will become  inac-');
  writeln('cessible unless you define an alternate sequence for it as well.');
  writeln;
  pressreturn;
END;

BEGIN {keyboard}
  WITH data DO
  BEGIN
    i:=0; n:=0; c:=1;
    WHILE altkey[i]<>0 DO
    BEGIN
      n:=n+1;
      move(altkey[i],akey[n],altkey[i+1]+2);
      i:=i+altkey[i+1]+2;
    END;
    REPEAT
      writeln('ALTERNATE KEY DEFINITIONS:');
      writeln;
      IF n=0 THEN
      BEGIN
        writeln('No alternate keys defined'); writeln;
        ch:=select('Add(Z), Exit(X), Help(Y)',['Z','X','Y']);
      END ELSE
      BEGIN
        IF c+9>n THEN m:=n-c ELSE m:=9;
        FOR i:=0 TO m DO
        BEGIN
          s:=keyseq(stdkey[akey[c+i].val]);
          write(chr(i+65),'. Standard: ',s,'':9-len(s));
          writeln('Alternate: ',keyseq(akey[c+i].str));
        END;
        IF n>10 THEN
        BEGIN
          writeln; writeln('Press RETURN to view more');
        END;
        writeln;
        mc:=chr(m+65);
        ch:=select('Delete(A-'+mc+'), Add(Z), Exit(X), Help(Y)',
          ['A'..mc,'Z','X','Y',^M]);
      END;
      CASE ch OF
        'A'..'J': BEGIN
                    delakey(c+ord(ch)-65);
                    IF (n>0) AND (c>n) THEN c:=c-10;
                  END;
        'Z': BEGIN
               addakey; c:=n-((n-1) MOD 10);
             END;
        'Y': help;
        ^M: BEGIN
              c:=c+10; IF c>n THEN c:=1;
            END;
      END;
    UNTIL ch='X';
    i:=0;
    FOR n:=1 TO n DO
    BEGIN
      move(akey[n],altkey[i],len(akey[n].str)+2);
      i:=i+len(akey[n].str)+2;
    END;
    fill(altkey[i],256-i,0);
  END;
END;
