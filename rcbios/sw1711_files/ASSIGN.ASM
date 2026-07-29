; ============================================================================
; THIS IS A DISASSEMBLED RECONSTRUCTION, NOT THE ORIGINAL SOURCE.
;
; No original assembly source for ASSIGN.COM has been found. Every label,
; comment, and piece of structural interpretation below (routine names,
; the drive/format-code encoding, the BIOS vendor-table cross-references)
; was derived by disassembling the binary and reasoning about its control
; flow and I/O ports — it is a reconstruction, not a recovered original.
; Where that interpretation is inferred rather than independently
; confirmed, it is flagged as such in the comments (see BIOS ADDRESSES
; below in particular).
; ============================================================================
;
; ASSIGN.COM — RC700 Floppy Format Assignment Utility
; Reconstructed by disassembly, 2026-07-29
;
; Source: rcbios/sw1711_files/ASSIGN.COM (384 bytes, loads at 0100H)
;         from SW1711-I8.imd (rel.2.3 maxi system disk)
; MD5 of original binary: 9ca4e3a6075c02d96e57f31e3a5f2d2a
;
; Reassembles byte-identical to the original 384-byte ASSIGN.COM (verified
; with z88dk-z80asm; see build note at EOF).
;
; PURPOSE:
;   Lets the operator override the floppy disk format (single density /
;   double density) that the BIOS uses for drive A and/or drive B, without
;   re-running CONFI or rebooting. Command line syntax (repeatable):
;
;       ASSIGN d:=SS      (or)      ASSIGN d:=DD
;
;   where d is A or B. Several assignments may be given on one line,
;   e.g. "ASSIGN A:=DD B:=SS". Any drive not mentioned keeps its current
;   BIOS setting (the program preloads its working table from the live
;   BIOS values before parsing, see GOTFMT below).
;
; MECHANISM:
;   The command tail at 0080H is scanned character-by-character (GETCH).
;   Recognized "d:=SS"/"d:=DD" assignments are written into a 2-byte
;   working table (WORKFMT_A/WORKFMT_B); anything else resyncs the parser
;   (silently — there is no error message for malformed input). When the
;   tail is exhausted, GETCH itself dispatches to FINISH, which pokes the
;   working table back into the BIOS's per-drive format bytes, prints an
;   "insert disk" prompt, waits for <RETURN>, issues a BDOS disk reset, and
;   returns to the CCP.
;
;   The poke is skipped on "maxi" (hard-disk-equipped) systems: FINISH
;   reads SW1 (port 14H) bit 7 first, matching the mini/maxi test in
;   CONFI.COM's track-0 config read/write routine (see CONFI_ANALYSIS.md,
;   "sub_03F6h"), and only writes when that bit is clear.
;
; BIOS ADDRESSES (56K system, DA00H jump table — confirmed for this disk
; by AUTOEXEC.ASM and CONFI_ANALYSIS.md, both reconstructed from the same
; SW1711-I8.imd):
;   DA00H = start of the standard 17-entry CP/M 2.2 jump table (BOOT,
;           WBOOT, CONST, CONIN, CONOUT, LIST, PUNCH, READER, HOME,
;           SELDSK, SETTRK, SETSEC, SETDMA, READ, WRITE, LISTST, SECTRAN);
;           this program obtains DA00H at runtime from the target address
;           of "JP DA00H" at location 0000H, so it works unmodified across
;           BIOS memory-size variants. This part is a plain fact of the
;           disassembly (LD HL,(0001H) / LD DE,0034H / ADD HL,DE at
;           0112H-0118H, re-verified byte-for-byte from the raw .COM),
;           independent of everything below.
;
;   *** UNRESOLVED CONTRADICTION — DA34H/DA35H, what this program pokes ***
;   The BIOS+034H target that FINISH (01AAH-01B5H) writes 2 bytes into is,
;   per this same repo's own byte-verified rel.2.1/rel.2.2 BIOS diff
;   (rcbios/ANALYSIS.md, "Non-Standard Extension Area after SECTRAN"),
;   labelled WR5A/WR5B — the runtime SIO Write-Register-5 values for
;   serial channels A and B, NOT a per-drive floppy format table. That
;   labelling is itself corroborated two more ways in ANALYSIS.md: (a) its
;   INIT trace shows WR5A being loaded from disk config-block offset
;   +00EH masked with 060H, and CONFI.COM's own documented G.1.4 parameter
;   ("Bits/char", SIO-A WR3/WR5) independently names config+00EH as that
;   same Tx-bits/char field; (b) ANALYSIS.md's neighbouring DA36H=MTYPE
;   matches AUTOEXEC.ASM's independently-reconstructed DA36H=MTYPE on
;   this exact disk, tying the whole table's alignment down. The real
;   per-drive floppy format table, per the same document, instead lives
;   at BIOS+039H..046H (FD0-FD14, 15 bytes, 020H=mini/0FFH=not present) —
;   a different location, size, and encoding than anything ASSIGN.COM
;   touches.
;
;   Against that: docs/CPM_USERS_GUIDE_NOTES.md (transcribed from the
;   official CP/M for RC702 User's Guide, RCSL 42-i2190) independently
;   confirms ASSIGN's *purpose* in prose ("Assign SD/DD format to 8"
;   drive") — matching this disassembly's command grammar (driveletter
;   ':' '=' "SS"/"DD") — but its own BIOS extended-jump-table offsets
;   (WFITR/READS/LINSEL/EXIT/CLOCK/HRDFMT at +033H/+036H/+039H/+03CH/
;   +03FH/+042H) disagree with ANALYSIS.md's byte-verified offsets for
;   the very same routines (+04AH/+04DH/+050H/+053H/+056H/+059H), so it
;   cannot be used to arbitrate this.
;
;   Net effect: the offset computation (BIOS+034H) is a verified fact;
;   what actually lives there is contested between two sources in this
;   workspace, and this reconstruction cannot resolve it from static
;   analysis alone. The comments below describing DA34H/DA35H as a
;   "floppy format selector" reflect only this program's own control
;   flow (i.e. what it does with the byte it read/wrote), not a
;   confirmed BIOS-side identity — treat that label as UNCONFIRMED and
;   possibly wrong pending a MAME/hardware check or a primary BIOS source
;   for this exact rel.2.3 build.
;
	BDOS	EQU	0005H		; CP/M BDOS entry point
	WBOOTV	EQU	0001H		; holds target address of "JP 0000H" (= BIOS jump-table base)
	CMDTAIL	EQU	0080H		; default DMA/command-tail buffer (length-prefixed)

	PRINTF	EQU	9		; BDOS: print $-terminated string
	CONINF	EQU	1		; BDOS: console input
	OPENF	EQU	15		; BDOS: open file
	CLOSEF	EQU	16		; BDOS: close file
	DELETEF	EQU	19		; BDOS: delete file
	READF	EQU	20		; BDOS: read sequential
	WRITEF	EQU	21		; BDOS: write sequential
	MAKEF	EQU	22		; BDOS: make file
	DSKRSTF	EQU	13		; BDOS: reset disk system
	SETDMAF	EQU	26		; BDOS: set DMA address

	SW1PORT	EQU	014H		; system configuration DIP switch input port
	MINIMAXI EQU	080H		; SW1 bit 7: 0 = mini (floppy-only), 1 = maxi (has fixed disk)

	ORG	0100H

;========================================================
;= ENTRY POINT                                          =
;========================================================

START:	POP	HL			; 0100 — CCP's return address, left on stack at COM entry
	LD	(RETADDR),HL		; 0101   save it: this is how ASSIGN gets back to the CCP
	LD	SP,STACK		; 0104   switch to a small local stack

;	Append a trailing space to the command tail so GETCH's terminator
;	scan (below) always finds a delimiter after the last token, even
;	when the operator's line has no trailing space of its own.
	LD	HL,CMDTAIL		; 0107
	INC	(HL)			; 010A — bump the length byte twice: once to make
	LD	E,(HL)			; 010B   room for the appended space, once because GETCH's
	INC	(HL)			; 010C   own countdown (below) is pre-decremented
	LD	D,0			; 010D
	ADD	HL,DE			; 010F — HL -> one past the (extended) tail
	LD	(HL),' '		; 0110

;	Locate BIOS+034H/035H (DA34H/DA35H on a 56K system) via the warm-boot
;	vector, so this works unmodified if the BIOS is relocated. NOTE: what
;	this pair of bytes actually is is an UNRESOLVED CONTRADICTION — see
;	the "BIOS ADDRESSES" header note above. Named CURFMT_x/WORKFMT_x/
;	BIOSFMT below for lack of a confirmed identity, not as a claim.
	LD	HL,(WBOOTV)		; 0112 — HL = BIOS jump-table base (target of "JP" at 0000H)
	LD	DE,0034H		; 0115
	ADD	HL,DE			; 0118 — HL -> BIOS+034H (disputed identity, see above)
	LD	(BIOSFMT),HL		; 0119 — remember it, for the poke-back in FINISH

;	Preload the working table with the BIOS's *current* settings, so a
;	drive not mentioned on the command line is left unchanged.
	LD	A,(HL)			; 011C
	LD	(CURFMT_A),A		; 011D
	INC	HL			; 0120 — -> BIOS+035H (disputed identity, see above)
	LD	A,(HL)			; 0121
	LD	(CURFMT_B),A		; 0122
	LD	HL,(CURFMT_A)		; 0125 — 16-bit copy: (CURFMT_A,CURFMT_B) -> (WORKFMT_A,WORKFMT_B)
	LD	(WORKFMT_A),HL		; 0128

	LD	HL,CMDTAIL		; 012B
	INC	HL			; 012E — -> first character of the command tail (skip length byte)
	LD	(CMDPTR),HL		; 012F
	JP	PARSE			; 0132

;========================================================
;= GETCH — fetch next command-tail character           =
;=   On exhaustion, falls straight into FINISH instead  =
;=   of returning (this routine never returns once the  =
;=   tail's extended length counter reaches zero).      =
;========================================================

GETCH:	LD	HL,CMDTAIL		; 0135
	DEC	(HL)			; 0138 — countdown set up at 010A-010D above
	JP	Z,FINISH		; 0139 — exhausted: go apply the changes and exit
	LD	HL,(CMDPTR)		; 013C
	LD	A,(HL)			; 013F
	INC	HL			; 0140
	LD	(CMDPTR),HL		; 0141
	RET				; 0144

;========================================================
;= PARSE — recognize "d:=SS" / "d:=DD" tokens           =
;=   B = drive index (0=A, 1=B) accumulated while        =
;=   matching; C = format code accumulated (0=SS, 8=DD). =
;=   Any mismatch resyncs to PARSE and tries again from  =
;=   the next character — malformed input is silently    =
;=   skipped, there is no error message.                 =
;========================================================

PARSE:	LD	BC,0000H		; 0145
	CALL	GETCH			; 0148 — expect drive letter
	CP	'A'			; 014B
	JP	Z,GOTDRV		; 014D — 'A' -> drive index stays 0
	CP	'B'			; 0150
	JP	NZ,PARSE		; 0152 — neither A nor B: resync
	INC	B			; 0155 — 'B' -> drive index 1
GOTDRV:	CALL	GETCH			; 0156 — expect ':'
	CP	':'			; 0159
	JP	NZ,PARSE		; 015B
	CALL	GETCH			; 015E — expect '='
	CP	'='			; 0161
	JP	NZ,PARSE		; 0163
	CALL	GETCH			; 0166 — expect 'S' or 'D'
	CP	'S'			; 0169
	JP	Z,GOTS			; 016B
	CP	'D'			; 016E
	JP	NZ,PARSE		; 0170
	CALL	GETCH			; 0173 — expect second 'D'
	CP	'D'			; 0176
	JP	NZ,PARSE		; 0178
	CALL	GETCH			; 017B — expect trailing space
	CP	' '			; 017E
	JP	NZ,PARSE		; 0180
	LD	C,08H			; 0183 — format code: DD
	JP	STORE			; 0185
GOTS:	CALL	GETCH			; 0188 — expect second 'S'
	CP	'S'			; 018B
	JP	NZ,PARSE		; 018D
	CALL	GETCH			; 0190 — expect trailing space
	CP	' '			; 0193
	JP	NZ,PARSE		; 0195
					; format code stays 0 (SS) — C untouched since PARSE's LD BC,0000H
STORE:	LD	HL,WORKFMT_A		; 0198
	LD	D,0			; 019B
	LD	E,B			; 019D
	ADD	HL,DE			; 019E — HL -> WORKFMT_A or WORKFMT_B, selected by drive index
	LD	(HL),C			; 019F — record the format code for that drive
	JP	PARSE			; 01A0 — loop: the command line may assign both drives

;========================================================
;= FINISH — command tail exhausted: apply and exit      =
;========================================================

FINISH:	IN	A,(SW1PORT)		; 01A3 — same SW1 test as CONFI.COM's mini/maxi check
	AND	MINIMAXI		; 01A5
	JP	NZ,PROMPT		; 01A7 — maxi (fixed disk) system: leave BIOS bytes untouched
	LD	HL,(BIOSFMT)		; 01AA — BIOS+034H (disputed identity, see header note)
	LD	A,(WORKFMT_A)		; 01AD
	LD	(HL),A			; 01B0
	INC	HL			; 01B1 — BIOS+035H (disputed identity, see header note)
	LD	A,(WORKFMT_B)		; 01B2
	LD	(HL),A			; 01B5
PROMPT:	LD	DE,MSGINS		; 01B6
	CALL	PRINT			; 01B9
	CALL	CONIN			; 01BC — wait for operator to swap disk and press <RETURN>
	CALL	DSKRST			; 01BF — BDOS: reset disk system, so CP/M re-reads the DPB
	LD	HL,(RETADDR)		; 01C2
	JP	(HL)			; 01C5 — back to the CCP

;========================================================
;= BDOS call stubs                                      =
;=   Only PRINT/CONIN/DSKRST are used above; the file    =
;=   stubs (OPEN..SETDMA) are present in the binary but  =
;=   dead code in this build — no code path calls them.  =
;========================================================

CONIN:	LD	C,CONINF		; 01C6
	JP	BDOS			; 01C8
DSKRST:	LD	C,DSKRSTF		; 01CB
	LD	DE,0003H		; 01CD — loaded but unused: BDOS function 13 ignores DE
	JP	BDOS			; 01D0
OPEN:	LD	C,OPENF			; 01D3
	JP	BDOS			; 01D5
CLOSE:	LD	C,CLOSEF		; 01D8
	JP	BDOS			; 01DA
DELETE:	LD	C,DELETEF		; 01DD
	JP	BDOS			; 01DF
READ:	LD	C,READF			; 01E2
	JP	BDOS			; 01E4
WRITE:	LD	C,WRITEF		; 01E7
	JP	BDOS			; 01E9
MAKE:	LD	C,MAKEF			; 01EC
	JP	BDOS			; 01EE
SETDMA:	LD	C,SETDMAF		; 01F1
	JP	BDOS			; 01F3
PRINT:	LD	C,PRINTF		; 01F6
	JP	BDOS			; 01F8

;========================================================
;= STRING DATA ($-terminated for BDOS function 9)       =
;========================================================

MSGINS:	DB	'INSERT DISK AND TYPE <RETURN>$'	; 01FB

;========================================================
;= WORK AREA (zero-filled in the .COM image; used only  =
;= as RAM once the program is running)                  =
;========================================================

BIOSFMT:	DS	2	; 0219 — &(BIOS+034H), i.e. DA34H (disputed identity, see header note)
CURFMT_A:	DS	1	; 021B — value read from BIOS+034H at startup (disputed identity)
CURFMT_B:	DS	1	; 021C — value read from BIOS+035H at startup (disputed identity)
WORKFMT_A:	DS	1	; 021D — working value for BIOS+034H (seeded from CURFMT_A)
WORKFMT_B:	DS	1	; 021E — working value for BIOS+035H (seeded from CURFMT_B)
CMDPTR:		DS	2	; 021F — GETCH's scan pointer into the command tail
RETADDR:	DS	2	; 0221 — CCP return address, saved by START

STACK	EQU	0263H		; local stack top (~60 bytes of headroom above the work area)

;	Pad out to the original file's length (0280H = 384 bytes) with
;	explicit zero bytes, so the assembled .cim is byte-identical to
;	ASSIGN.COM rather than merely matching over the initialized
;	prefix. A plain "DS n" would reserve this space without emitting
;	bytes into zmac's .cim output; REPT/DB 0/ENDM forces the zeros
;	to actually be written.
	REPT	0280H-$
	DB	0
	ENDM

	END	START

; Build note: assembled with this repo's zmac in Z80 mnemonic mode as
;   zmac -z ASSIGN.ASM
; producing zout/ASSIGN.cim. Verified byte-for-byte identical to all
; 384 bytes of the original ASSIGN.COM: the first 281 bytes come from
; the disassembled code/data above, and the trailing 103 bytes (offset
; 281..383, i.e. 0219H..027FH — the DS-reserved work area and stack)
; are reproduced explicitly via the REPT/DB 0 padding block above,
; since a plain "DS n" does not materialize bytes in zmac's .cim
; output.
