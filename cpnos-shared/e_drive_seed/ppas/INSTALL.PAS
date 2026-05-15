PROGRAM install; {$A+,R-}

CONST
  maxterm = 40;

TYPE
  str2     = STRING[2];
  str3     = STRING[3];
  str4     = STRING[4];
  str5     = STRING[5];
  str8     = STRING[8];
  str12    = STRING[12];
  str14    = STRING[14];
  str24    = STRING[24];
  str31    = STRING[31];
  str36    = STRING[36];
  str48    = STRING[48];
  charset  = SET OF char;
  filename = RECORD
               drv: byte;
               nam: ARRAY[1..8] OF char;
               ext: ARRAY[1..3] OF char;
             END;
  extstr   = ARRAY[1..3] OF char;
  datarec  = RECORD
               f1: byte;
               edofs,pstwd: integer;
               f2: ARRAY[1..27] OF byte;
               termname: str31;
               width,height: byte;
               gxyls: str8;
               gxyss,gxyts: str4;
               colblin,coorofs,coorfmt: byte;
               clhs,cess,cels,ilns,dlns,rons,rofs,
               ions,iofs,uons,uofs,bons,bofs,aofs: str8;
               f3: ARRAY[1..150] OF byte;
               rdelay: integer;
               altkey: ARRAY[0..255] OF byte;
               xstep,backf,insmf,autof,tabsf,errmod: byte;
               hlpstr,ermstr,wrkstr: filename;
               pasext,bakext,comext,chnext: extstr;
             END;
  pdatrec  = ARRAY[1..590] OF byte;

VAR
  cf,hf: FILE;
  tf: FILE OF str31;
  df: FILE OF pdatrec;
  cfn: str14;
  data: datarec;
  tnam: ARRAY[1..maxterm] OF str31;
  b1: ARRAY[0..1023] OF byte;
  b2: ARRAY[0..511] OF byte;
  b2sec,b2ofs,i: integer;
  insfile: boolean;
  ch: char;

PROCEDURE errhand(errno,errofs: integer);
BEGIN
  IF errno=1 THEN
  BEGIN
    writeln('^C'); halt;
  END;
END;

FUNCTION upcase(s: str24): str24;
VAR
  i: integer;
  u: str24;
BEGIN
  u:='';
  FOR i:=1 TO len(s) DO
  IF (s[i]>='a') AND (s[i]<='z') THEN
  u:=u+chr(ord(s[i])-32) ELSE u:=u+s[i];
  upcase:=u;
END;

FUNCTION hex(number,digits: integer): str4;
CONST
  hexdigits: ARRAY[0..15] OF char = '0123456789ABCDEF';
VAR
  d: integer;
  h: str4;
BEGIN
  h[0]:=chr(digits);
  FOR d:=digits DOWNTO 1 DO
  BEGIN
    h[d]:=hexdigits[number AND 15];
    number:=number SHR 4;
  END;
  hex:=h;
END;

FUNCTION hexseq(seq: str8): str24;
VAR
  i: integer;
  s: str24;
BEGIN
  IF seq='' THEN hexseq:='Unconfigured' ELSE
  BEGIN
    s:='';
    FOR i:=1 TO len(seq) DO s:=s+hex(ord(seq[i]),2)+' ';
    hexseq:=copy(s,1,len(s)-1);
  END;
END;

FUNCTION yesno(flag: integer): str4;
BEGIN
  IF flag<>0 THEN yesno:='YES' ELSE yesno:='NO';
END;

PROCEDURE backsp(n: integer);
VAR
  i: integer;
BEGIN
  FOR i:=1 TO n DO write(^H' '^H);
END;

FUNCTION readnum(min,max: integer): integer;
VAR
  n,p: integer;
  ok: boolean;
  s: str5;
BEGIN
  REPEAT
    buflen:=5; read(s);
    IF s='' THEN ok:=false ELSE
    BEGIN
      val(s,n,p);
      ok:=(p=0) AND (n>=min) AND (n<=max);
    END;
    IF NOT ok THEN backsp(len(s));
  UNTIL ok;
  writeln; readnum:=n;
END;

FUNCTION readseq(maxlen: integer): str8;
CONST
  hexdigits: SET OF '0'..'f' = ['0'..'9','A'..'F','a'..'f'];
VAR
  h,i,n,p: integer;
  error: boolean;
  seq: str8;
  s: str24;
BEGIN
  REPEAT
    buflen:=maxlen*3-1; read(s); s:=s+^M;
    error:=false; p:=1; n:=0;
    REPEAT
      WHILE s[p]=' ' DO p:=succ(p);
      IF s[p]=^M THEN i:=0 ELSE
      BEGIN
        i:=p; WHILE NOT(s[p] IN [' ',^M]) DO p:=succ(p);
        val('$'+copy(s,i,p-i),h,i);
        n:=succ(n); seq[n]:=chr(h);
      END;
    UNTIL (s[p]=^M) OR (i<>0);
    IF i<>0 THEN backsp(len(s)-1);
  UNTIL i=0;
  seq[0]:=chr(n); writeln;
  readseq:=seq;
END;

FUNCTION readyn: integer;
VAR
  s: str4;
BEGIN
  REPEAT
    buflen:=3; read(s); s:=upcase(s);
    IF (s<>'YES') AND (s<>'NO') THEN backsp(len(s));
  UNTIL (s='YES') OR (s='NO');
  IF s='YES' THEN readyn:=255 ELSE readyn:=0;
  writeln;
END;

FUNCTION select(prompt: str48; okch: charset): char;
VAR
  ch: char;
BEGIN
  write(prompt,': ');
  REPEAT
    read(kbd,ch);
    IF (ch>='a') AND (ch<='z') THEN ch:=chr(ord(ch)-32);
  UNTIL ch IN okch;
  IF ch=^M THEN backsp(len(prompt)+2) ELSE
  BEGIN
    writeln(ch); writeln;
  END;
  select:=ch;
END;

PROCEDURE pressreturn;
VAR
  ch: char;
BEGIN
  write('Press RETURN...');
  REPEAT read(kbd,ch) UNTIL ch=^M;
  backsp(15);
END;

PROCEDURE resetdisks;
BEGIN
  bdos(37,-1);
END;

PROCEDURE clear1;
BEGIN
  fill(data.termname,332,0);
  WITH data DO
  BEGIN
    width:=79; height:=24; gxyls:=@27'=';
    coorofs:=32; clhs:=@26;
  END;
END;

PROCEDURE clear2;
BEGIN
  fill(data.rdelay,312,0);
  WITH data DO
  BEGIN
    rdelay:=1000; xstep:=16; backf:=255;
    insmf:=255; autof:=255; errmod:=2;
    hlpstr.drv:=0; hlpstr.nam:='PPAS    '; hlpstr.ext:='HLP';
    ermstr.drv:=0; ermstr.nam:='PPAS    '; ermstr.ext:='ERM';
    wrkstr.drv:=0; wrkstr.nam:='WORK    '; wrkstr.ext:='PAS';
    pasext:='PAS'; bakext:='BAK'; comext:='COM'; chnext:='CHN';
  END;
END;

PROCEDURE configure;
VAR
  ch: char;

(*$I INSTCRT*)

PROCEDURE editor;
CONST
  pa: str36 = 'A. Insert mode on (YES/NO)........: ';
  pb: str36 = 'B. Auto-indent on (YES/NO)........: ';
  pc: str36 = 'C. Taulate mode on (YES/NO).......: ';
  pd: str36 = 'D. Replace prompt delay...........: ';
  pe: str36 = 'E. Side scroll step value.........: ';

VAR
  ch: char;

PROCEDURE help;
BEGIN
  writeln('INSERT MODE ON.  This  field defined the  initial  state  of  the');
  writeln('insert mode (INS) when PolyPascal is started.');
  writeln;
  writeln('AUTO-INDENT ON. This field defines the initial state of the auto-');
  writeln('indent tabulator (AUT) when PolyPascal is started.');
  writeln;
  writeln('TABS MODE ON. This field defines the initial state of the tabula-');
  writeln('tor mode (TAB) when PolyPascal is started.');
  writeln;
  writeln('REPLACE PROMPT DELAY. This field is used only by the find/replace');
  writeln('function in the editor. It defines the delay used when moving the');
  writeln('cursor  alternately  between  the replace prompt  and  the  text.');
  writeln('Experiment  to find a suitable value (typical values  range  from');
  writeln('200 to 2000).');
  writeln;
  writeln('SIDE SCROLL STEP VALUE.  This field defines the step size used by');
  writeln('the editor when it scrolls sidewards.  The minimum value is 1 and');
  writeln('the maximum value is the screen width less one.');
  writeln;
  pressreturn;
END;

BEGIN {editor}
  WITH data DO
  REPEAT
    writeln('EDITOR CONFIGURATION TABLE:');
    writeln;
    writeln(pa,yesno(insmf));
    writeln(pb,yesno(autof));
    writeln(pc,yesno(tabsf));
    writeln(pd,rdelay);
    writeln(pe,xstep);
    writeln;
    ch:=select('Edit(A-E), Exit(X), Help(Y)',['A'..'E','X','Y']);
    CASE ch OF
      'A': BEGIN
             write(pa); insmf:=readyn;
           END;
      'B': BEGIN
             write(pb); autof:=readyn;
           END;
      'C': BEGIN
             write(pc); tabsf:=readyn;
           END;
      'D': BEGIN
             write(pd); rdelay:=readnum(0,32767);
           END;
      'E': BEGIN
             write(pe); xstep:=readnum(1,pred(width));
           END;
      'Y': help;
    END;
    IF ch IN ['A'..'E'] THEN writeln;
  UNTIL ch='X';
END;

PROCEDURE misc;
CONST
  pa: str36 = 'A. Use backup files (YES/NO)......: ';
  pb: str36 = 'B. Error message mode (0/1/2).....: ';
  pc: str36 = 'C. Help file name.................: ';
  pd: str36 = 'D. Error message file name........: ';
  pe: str36 = 'E. Default workfile name..........: ';
  pf: str36 = 'F. Default text file type.........: ';
  pg: str36 = 'G. Default backup file type.......: ';
  ph: str36 = 'H. Default program file type......: ';
  pi: str36 = 'I. Default object file type.......: ';
  pj: str36 = 'J. Configuration name.............: ';

VAR
  ch: char;

FUNCTION fnstr(fn: filename): str14;
VAR
  i: integer;
  s: str14;
BEGIN
  WITH fn DO
  BEGIN
    drv:=drv AND $7F;
    IF drv=0 THEN s:='' ELSE s:=chr(drv+64)+':';
    FOR i:=1 TO 8 DO IF nam[i]<>' ' THEN s:=s+nam[i];
    s:=s+'.';
    FOR i:=1 TO 3 DO IF ext[i]<>' ' THEN s:=s+ext[i];
  END;
  fnstr:=s;
END;

PROCEDURE readfn(VAR fn: filename);
VAR
  s: str14;
  f: FILE;
BEGIN
  REPEAT
    buflen:=14; read(s); assign(f,s);
    move(mem[addr(f)+12],fn,12);
    IF fn.nam[1]=' ' THEN backsp(len(s));
  UNTIL fn.nam[1]<>' ';
  writeln;
END;

PROCEDURE readext(VAR ext: extstr);
VAR
  s: str3;
BEGIN
  buflen:=3; readln(s);
  s:=upcase(s)+'   '; move(s[1],ext,3);
END;

PROCEDURE help;
BEGIN
  writeln('USE BAK FILES.  This field must be either YES or NO. If it is set');
  writeln('to YES,  duplicate files will have their type changed to BAK when');
  writeln('the SAVE command is used to save a file.  Otherwise,  such  files');
  writeln('are simply deleted.');
  writeln;
  writeln('ERROR MESSAGE MODE.  The error message mode can be either 0, 1 or');
  writeln('2.  0 means that the error message file should never be loaded. 1');
  writeln('means  that the error message file should only be loaded  if  the');
  writeln('user  confirms it (by answering yes to the prompt when PolyPascal');
  writeln('is  started),  and  2 means that the error  message  file  should');
  writeln('always  be  loaded.  If the error message file is not loaded  the');
  writeln('compiler will output only error numbers and not messages.');
  writeln;
  writeln('HELP FILE NAME. The name of the PolyPascal help file.');
  writeln;
  writeln('ERROR MESSAGE FILE NAME. The name of the PolyPascal error message');
  writeln('file.');
  writeln;
  writeln('DEFAULT WORKFILE NAME. The workfile name is set to this file name');
  writeln('when PolyPascal is started and when the ZAP command is used.');
  writeln;
  pressreturn;
  writeln('DEFAULT TEXT FILE TYPE.  The default type used by the LOAD,  SAVE');
  writeln('and NAME commands.');
  writeln;
  writeln('DEFAULT BACKUP FILE TYPE.  The  type used by the SAVE command  to');
  writeln('create backup files.');
  writeln;
  writeln('DAFAULT PROGRAM FILE TYPE.  The default type used by the  PROGRAM');
  writeln('command.');
  writeln;
  writeln('DEFAULT OBJECT FILE TYPE.  The  default type used by  the  OBJECT');
  writeln('command.');
  writeln;
  writeln('CONFIGURATION NAME.  This function is used to define the name  of');
  writeln('the current  configuration.  If no name is installed,  PolyPascal');
  writeln('will not run, since this indicates an unconfigured copy.');
  writeln;
  pressreturn;
END;

BEGIN {misc}
  WITH data DO
  REPEAT
    writeln('MISCELLANEOUS DATA:');
    writeln;
    writeln(pa,yesno(backf));
    writeln(pb,errmod);
    writeln(pc,fnstr(hlpstr));
    writeln(pd,fnstr(ermstr));
    writeln(pe,fnstr(wrkstr));
    writeln(pf,pasext);
    writeln(pg,bakext);
    writeln(ph,comext);
    writeln(pi,chnext);
    writeln(pj,termname);
    writeln;
    ch:=select('Edit(A-J), Exit(X), Help(Y)',['A'..'J','X','Y']);
    CASE ch OF
      'A': BEGIN
             write(pa); backf:=readyn;
           END;
      'B': BEGIN
             write(pb); errmod:=readnum(0,2);
           END;
      'C': BEGIN
             write(pc); readfn(hlpstr);
             hlpstr.drv:=hlpstr.drv+$80;
           END;
      'D': BEGIN
             write(pd); readfn(ermstr);
             ermstr.drv:=ermstr.drv+$80;
           END;
      'E': BEGIN
             write(pe); readfn(wrkstr);
           END;
      'F': BEGIN
             write(pf); readext(pasext);
           END;
      'G': BEGIN
             write(pg); readext(bakext);
           END;
      'H': BEGIN
             write(ph); readext(comext);
           END;
      'I': BEGIN
             write(pi); readext(chnext);
           END;
      'J': BEGIN
             write(pj); buflen:=31; readln(termname);
           END;
      'Y': help;
    END;
    IF ch IN ['A'..'J'] THEN writeln;
  UNTIL ch='X';
END;

PROCEDURE clear;
BEGIN
  write('Clear configuration data (YES/NO)? ');
  IF readyn<>0 THEN
  BEGIN
    clear1; clear2;
  END;
  writeln;
END;

PROCEDURE help;
BEGIN
  writeln('To do a complete installation of PolyPascal you should go through');
  writeln('all functions of this menu (the order in which you do it is of no');
  writeln('importance,  as  long as you make sure that all fields within all');
  writeln('menus have be inspected and modified if necessary).');
  writeln;
  writeln('CRT CONFIGURATION.  This function is used to view  and/or  modify');
  writeln('the CRT configuration table.');
  writeln;
  writeln('KEYBOARD CONFIGURATION.  This  function  is used to  view  and/or');
  writeln('modify alternate key definitions.');
  writeln;
  writeln('EDITOR CONFIGURATION. This function is used to view and/or modify');
  writeln('the editor configuration table.');
  writeln;
  writeln('MISCELLANEOUS DATA.  This  function  allows you  to  view  and/or');
  writeln('modify various system parameters.');
  writeln;
  pressreturn;
  writeln('CLEAR CONFIGURATION DATA.  This function will initialize all con-');
  writeln('figuration data fields to some appropriate default values. If you');
  writeln('are about to install a new terminal, use this function before the');
  writeln('above ones - this will save you the trouble of manually  removing');
  writeln('the existing values.');
  writeln;
  pressreturn;
END;

BEGIN {configure}
  WITH data DO
  REPEAT
    writeln('MAIN CONFIGURATION MENU:');
    writeln;
    writeln('1. CRT configuration');
    writeln('2. Keyboard configuration');
    writeln('3. Editor configuration');
    writeln('4. Miscellaneous data');
    writeln('5. Clear configuration data');
    writeln;
    ch:=select('Function(1-5), Exit(X), Help(Y)',['1'..'5','X','Y']);
    CASE ch OF
      '1': crt;
      '2': keyboard;
      '3': editor;
      '4': misc;
      '5': clear;
      'Y': help;
    END;
  UNTIL ch='X';
END;

PROCEDURE noinst;
BEGIN
  writeln('The INSTALL.TRM and INSTALL.DAT data files are not present on the');
  writeln('default  drive,  and therefore you cannot load or  save  standard');
  writeln('configurations.');
  writeln;
  pressreturn;
END;

PROCEDURE lsconfig(load: boolean);
VAR
  i,c,cc: integer;
  ch: char;
  done: boolean;
  ls: str4;

PROCEDURE loadc;
VAR
  ch: char;
  p: ^pdatrec;
BEGIN
  IF tnam[c]<>'' THEN
  BEGIN
    p:=ptr(addr(data.termname)); seek(df,c-1); read(df,p^);
    done:=true;
  END ELSE
  BEGIN
    write('ERROR: Undefined configuration. Press RETURN...');
    REPEAT read(kbd,ch) UNTIL ch=^M;
    backsp(47);
  END;
END;

PROCEDURE savec;
VAR
  p: ^pdatrec;
BEGIN
  seek(tf,c-1); write(tf,data.termname);
  p:=ptr(addr(data.termname)); seek(df,c-1); write(df,p^);
  tnam[c]:=data.termname; done:=true;
END;

PROCEDURE help1;
BEGIN
  writeln('To  load a standard configuration,  simply press the letter deno-');
  writeln('ting that configuration.  If none of the standard  configurations');
  writeln('mentioned  match your computer system,  you will have to  install');
  writeln('PolyPascal manually (using function 2 on the main menu).');
  writeln;
  pressreturn;
END;

PROCEDURE help2;
BEGIN
  writeln('To  save  the current configuration as a standard  configuration,');
  writeln('use  the RETURN key to move to a section that contains  an  empty');
  writeln('entry,  and enter the letter of that entry.  You may, if you wish');
  writeln('save  the  current  configuration on top of  an  existing  confi-');
  writeln('guration,  in which case that cofiguration is lost.  Note that if');
  writeln('the name of the configuration you save is empty,  you will not be');
  writeln('able to load the configuration again.');
  writeln;
  pressreturn;
END;

BEGIN {lsconfig}
  IF insfile THEN
  BEGIN
    cc:=1; done:=false; IF load THEN ls:='Load' ELSE ls:='Save';
    REPEAT
      writeln('STANDARD CONFIGURATIONS (MENU ',(cc+9) DIV 10,'):');
      writeln;
      FOR i:=0 TO 9 DO
      writeln(chr(i+65),'. ',tnam[cc+i]);
      writeln;
      writeln('Press RETURN to view more');
      writeln;
      ch:=select(ls+'(A-J), Exit(X), Help(Y)',['A'..'J','X','Y',^M]);
      CASE ch OF
        'A'..'J': BEGIN
                    c:=cc+ord(ch)-65; IF load THEN loadc ELSE savec;
                  END;
        'X': done:=true;
        'Y': IF load THEN help1 ELSE help2;
        ^M: BEGIN
              cc:=cc+10; IF cc>maxterm THEN cc:=1;
            END;
      END;
    UNTIL done;
  END ELSE noinst;
END;

PROCEDURE getdata;
VAR
  i: integer;
BEGIN
  seek(cf,0); blockread(cf,b1,3,i); move(b1,data,364);
  IF data.pstwd=$9090 THEN
  BEGIN
    b2sec:=(data.edofs+3) DIV 128-2;
    b2ofs:=(data.edofs+3) MOD 128;
    seek(cf,b2sec); blockread(cf,b2,4,i);
    move(b2[b2ofs],data.rdelay,312);
  END ELSE clear2;
END;

PROCEDURE putdata;
VAR
  i: integer;
BEGIN
  move(data,b1,364); seek(cf,0); blockwrite(cf,b1,3,i);
  IF data.pstwd=$9090 THEN
  BEGIN
    move(data.rdelay,b2[b2ofs],312);
    seek(cf,b2sec); blockwrite(cf,b2,4,i);
  END;
END;

PROCEDURE help;
BEGIN
  writeln('LOAD STANDARD CONFIGURATION.  This  function is used  to  load  a');
  writeln('standard  configuration,  i.e.  to  load all the parameters  that');
  writeln('define  a specific computer system.  If your computer  system  is');
  writeln('among  the  standard configurations,  then all you need to do  to');
  writeln('install PolyPascal is to load that configuration and exit.  If it');
  writeln('is not,  you must define your computer system manually, using the');
  writeln('function described below.');
  writeln;
  writeln('EDIT CONFIGURATION PARAMETERS.  This function is used to  set  up');
  writeln('new  configurations  and to edit an  existing  configuration.  It');
  writeln('allows  you  to view and/or modify all parameters that  define  a');
  writeln('specific  computer system.  If your computer is not mentioned  in');
  writeln('the  list of standard configurations (see above),  you  must  use');
  writeln('this function to define it manually.');
  writeln;
  writeln('SAVE A STANDARD CONFIGURATION.  This function is used to  add  an');
  writeln('entry to the list of standard configurations.  Normally, you will');
  writeln('not need to use this function.');
  writeln;
  pressreturn;
END;

BEGIN
  ehaddr:=addr(errhand);
  writeln;
  writeln('              PolyPascal-80 V3.10 Install Program');
  writeln;
  writeln('                      Copyright (C) 1985');
  writeln('                   PolyData MicroCenter A/S');
  writeln;
  writeln;
  writeln('This  program is used to view and modify the adjustable parts  of');
  writeln('PolyPascal.  If your copy of PolyPascal is unconfigured, then be-');
  writeln('fore you can use it,  you must install it using this program.  If');
  writeln('your copy is already set up for a specific computer system, there');
  writeln('is no need to run this program,  unless you wish to make personal');
  writeln('adjustments.');
  writeln;
  assign(tf,'INSTALL.TRM'); assign(df,'INSTALL.DAT');
  {$I-} reset(tf); reset(df); {$I+}
  insfile:=iores=0;
  IF insfile THEN
  FOR i:=1 TO maxterm DO read(tf,tnam[i]) ELSE noinst;
  REPEAT
    write('Input file name (RETURN for PPAS.COM)? ');
    buflen:=14; readln(cfn); cfn:=upcase(cfn); writeln;
    IF (cfn='') OR (len(cfn)=2) AND (cfn[2]=':') THEN
    cfn:=cfn+'PPAS';
    IF pos('.',cfn)=0 THEN cfn:=cfn+'.COM';
    assign(cf,cfn); {$I-} reset(cf) {$I+};
    i:=iores;
    IF i<>0 THEN
    BEGIN
      writeln('That file does not exist. Please specify another filename.');
      writeln('You may insert another disk if you wish.');
      writeln;
      resetdisks;
    END;
  UNTIL i=0;
  getdata;
  REPEAT
    writeln('INSTALL PROGRAM MAIN MENU:');
    writeln;
    writeln('1. Load a standard configuration');
    writeln('2. Edit configuration parameters');
    writeln('3. Save a standard configuration');
    writeln;
    write('CURRENT CONFIGURATION: ');
    IF data.termname<>'' THEN
    writeln(data.termname) ELSE writeln('No terminal selected');
    writeln;
    ch:=select('Function(1-3), Exit(X), Help(Y)',['1'..'3','X','Y']);
    CASE ch OF
      '1': lsconfig(true);
      '2': configure;
      '3': lsconfig(false);
      'Y': help;
    END;
  UNTIL ch='X';
  write('Save configuration in ',cfn,' (YES/NO)? ');
  IF readyn<>0 THEN putdata; close(cf);
  IF insfile THEN
  BEGIN
    close(tf); close(df);
  END;
END.
