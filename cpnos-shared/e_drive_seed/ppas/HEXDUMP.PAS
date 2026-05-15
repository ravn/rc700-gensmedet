PROGRAM hexdump; {$A+,R-,S+}

{ This program will output a hex dump af any disk file. Each    }
{ line shows the address of the first byte of the line, then 16 }
{ bytes in hex, and then the same bytes in ASCII, if they are   }
{ printable. On running the program, you must specify the name  }
{ of the file to be dumped, and the name of the file or logical }
{ device (CON:, LST:, etc.), which is to receive the dump.      }

TYPE
  sector = ARRAY[0..7,0..15] OF byte;
  hexstring = STRING[4];
  filename = STRING[14];

VAR
  address,l,p,i,j,n: integer;
  ch: char;
  inname,outname: filename;
  buffer: sector;
  infile: FILE;
  outfile: text;

FUNCTION hex(number,digits: integer): hexstring;
CONST
  hexdigit: ARRAY[0..15] OF char = '0123456789ABCDEF';
VAR
  d: integer;
  h: hexstring;
BEGIN
  h[0]:=chr(digits);
  FOR d:=digits DOWNTO 1 DO
  BEGIN
    h[d]:=hexdigit[number AND 15];
    number:=number SHR 4;
  END;
  hex:=h;
END;

BEGIN
  write('Input file name? '); readln(inname);
  IF inname='' THEN halt;
  write('Output file name? '); readln(outname);
  IF outname='' THEN halt;
  assign(infile,inname); {$I-} reset(infile) {$I+};
  IF iores>0 THEN
  BEGIN
    writeln(inname,' does not exist'); halt;
  END;
  assign(outfile,outname); rewrite(outfile);
  address:=0;
  REPEAT
    blockread(infile,buffer,1,n);
    IF n<>0 THEN
    FOR l:=0 TO 7 DO
    BEGIN
      write(outfile,hex(address,4),' ');
      FOR p:=0 TO 15 DO
      BEGIN
	IF p=8 THEN write(outfile,' ');
	write(outfile,hex(buffer[l,p],2):3);
      END;
      write(outfile,'  ');
      FOR p:=0 TO 15 DO
      BEGIN
	ch:=chr(buffer[l,p]);
	IF (ch>=@32) AND (ch<=@126) THEN
	write(outfile,ch) ELSE write(outfile,'.');
      END;
      writeln(outfile);
      address:=address+16;
    END;
  UNTIL n=0;
  close(infile); close(outfile);
END.
