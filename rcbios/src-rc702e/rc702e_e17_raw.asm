; z80dasm 1.2.0
; command line: z80dasm -a -l -g 0xD700 -S /Users/ravn/z80/rc700-gensmedet/rcbios/src-rc702e/rc702e_e17.sym -b /Users/ravn/z80/rc700-gensmedet/rcbios/src-rc702e/rc702e_e17.blk -o /Users/ravn/z80/rc700-gensmedet/rcbios/src-rc702e/rc702e_e17_raw.asm /Users/ravn/z80/rc700-gensmedet/rcbios/extracted_bios/cpm22_56k_rc702e_rel1.7_mini.bin

	org 0d700h


; BLOCK 'c000' (start 0xd700 end 0xd980)
c000_start:
	di			;d700
	ld hl,00000h		;d701
	ld de,0d480h		;d704
	ld bc,02381h		;d707
	ldir			;d70a
	ld hl,0ed00h		;d70c
	ld de,0ed01h		;d70f
	ld (hl),000h		;d712
	ld bc,01300h		;d714
	ldir			;d717
	ld hl,0d580h		;d719
	ld de,0f680h		;d71c
	ld bc,00180h		;d71f
	ldir			;d722
	ld sp,00080h		;d724
	ld a,(lec25h)		;d727
	ld i,a			;d72a
	im 2			;d72c
	ld a,020h		;d72e
	out (012h),a		;d730
	ld a,022h		;d732
	out (013h),a		;d734
	ld a,04fh		;d736
	out (012h),a		;d738
	ld a,00fh		;d73a
	out (013h),a		;d73c
	ld a,083h		;d73e
	out (012h),a		;d740
	out (013h),a		;d742
	ld a,000h		;d744
	out (00ch),a		;d746
	ld a,(0d500h)		;d748
	out (00ch),a		;d74b
	ld a,(0d501h)		;d74d
	out (00ch),a		;d750
	ld a,(0d502h)		;d752
	out (00dh),a		;d755
	ld a,(0d503h)		;d757
	out (00dh),a		;d75a
	ld a,(0d504h)		;d75c
	out (00eh),a		;d75f
	ld a,(0d505h)		;d761
	out (00eh),a		;d764
	ld a,(0d506h)		;d766
	out (00fh),a		;d769
	ld a,(0d507h)		;d76b
	out (00fh),a		;d76e
	ld hl,0d508h		;d770
	ld b,009h		;d773
	ld c,00ah		;d775
	otir			;d777
	ld hl,0d511h		;d779
	ld b,00bh		;d77c
	ld c,00bh		;d77e
	otir			;d780
	in a,(00ah)		;d782
	ld (0f421h),a		;d784
	ld a,001h		;d787
	out (00ah),a		;d789
	in a,(00ah)		;d78b
	ld (0f422h),a		;d78d
	in a,(00bh)		;d790
	ld (0f423h),a		;d792
	ld a,001h		;d795
	out (00bh),a		;d797
	in a,(00bh)		;d799
	ld (0f424h),a		;d79b
	ld a,020h		;d79e
	out (0f8h),a		;d7a0
	ld a,(0d51ch)		;d7a2
	out (0fbh),a		;d7a5
	ld a,(0d51eh)		;d7a7
	out (0fbh),a		;d7aa
	ld a,(0d51fh)		;d7ac
	out (0fbh),a		;d7af
	in a,(014h)		;d7b1
	and 080h		;d7b3
	jp z,ld7d1h		;d7b5
	ld hl,0d52fh		;d7b8
	ld a,(hl)		;d7bb
	cp 018h			;d7bc
	jp nz,ld7c3h		;d7be
	ld (hl),010h		;d7c1
ld7c3h:
	inc hl			;d7c3
	ld a,(hl)		;d7c4
	cp 018h			;d7c5
	jp nz,ld7cch		;d7c7
	ld (hl),010h		;d7ca
ld7cch:
	ld a,00fh		;d7cc
	ld (0d526h),a		;d7ce
ld7d1h:
	in a,(004h)		;d7d1
	and 01fh		;d7d3
	jp nz,ld7d1h		;d7d5
	ld hl,0d524h		;d7d8
	ld b,(hl)		;d7db
ld7dch:
	inc hl			;d7dc
ld7ddh:
	in a,(004h)		;d7dd
	and 0c0h		;d7df
	cp 080h			;d7e1
	jp nz,ld7ddh		;d7e3
	ld a,(hl)		;d7e6
	out (005h),a		;d7e7
	dec b			;d7e9
	jp nz,ld7dch		;d7ea
	ld hl,0f800h		;d7ed
	ld de,0f801h		;d7f0
	ld bc,007cfh		;d7f3
	ld (hl),020h		;d7f6
	ldir			;d7f8
	ld a,000h		;d7fa
	out (001h),a		;d7fc
	ld a,(0d520h)		;d7fe
	out (000h),a		;d801
	ld a,(0d521h)		;d803
	out (000h),a		;d806
	ld a,(0d522h)		;d808
	out (000h),a		;d80b
	ld a,(0d523h)		;d80d
	out (000h),a		;d810
	ld a,080h		;d812
	out (001h),a		;d814
	ld a,000h		;d816
	out (000h),a		;d818
	out (000h),a		;d81a
	ld a,0e0h		;d81c
	out (001h),a		;d81e
	ld a,023h		;d820
	out (001h),a		;d822
	ld a,(0d50eh)		;d824
	and 060h		;d827
	ld (lda34h),a		;d829
	ld a,(0d519h)		;d82c
	and 060h		;d82f
	ld (lda35h),a		;d831
	ld a,(0d52ch)		;d834
	ld (c008_end),a		;d837
	ld hl,(0d52dh)		;d83a
	ld (0ffe9h),hl		;d83d
	ld a,0ffh		;d840
	ld (0f41bh),a		;d842
	ld (0f41eh),a		;d845
	ld (0f3fdh),a		;d848
	ld hl,str_bootq_end	;d84b
	ld de,0ffedh		;d84e
	ld bc,0000fh		;d851
	ldir			;d854
	ld hl,0d52fh		;d856
	ld de,lda37h		;d859
	ld bc,00010h		;d85c
	ldir			;d85f
	ld hl,ld9a9h		;d861
	call signon_end		;d864
	ld hl,lda3ch		;d867
	xor a			;d86a
	out (0e1h),a		;d86b
	in a,(0e1h)		;d86d
	or a			;d86f
	ld a,004h		;d870
	jr z,ld88ah		;d872
	push hl			;d874
	push af			;d875
	ld hl,ld96fh		;d876
	call signon_end		;d879
	ld hl,ld98dh		;d87c
	call signon_end		;d87f
	pop af			;d882
	pop hl			;d883
ld884h:
	ld (hl),0ffh		;d884
	dec hl			;d886
	dec a			;d887
	jr z,ld884h		;d888
ld88ah:
	inc a			;d88a
ld88bh:
	ld c,a			;d88b
	push af			;d88c
	push hl			;d88d
	call sub_e330h		;d88e
	call sub_e6aeh		;d891
	ld a,b			;d894
	and 010h		;d895
	pop hl			;d897
	jr z,ld89ch		;d898
	ld (hl),0ffh		;d89a
ld89ch:
	dec hl			;d89c
	pop af			;d89d
	dec a			;d89e
	jr nz,ld88bh		;d89f
	xor a			;d8a1
	out (0e6h),a		;d8a2
	out (0e7h),a		;d8a4
	in a,(0e6h)		;d8a6
	or a			;d8a8
	jr z,ld8bah		;d8a9
	ld hl,ld984h		;d8ab
	call signon_end		;d8ae
	ld hl,ld98dh		;d8b1
	call signon_end		;d8b4
	jp ld955h		;d8b7
ld8bah:
	ld hl,0ed01h		;d8ba
	ld de,0ed02h		;d8bd
	ld bc,00100h		;d8c0
	ld (hl),0e5h		;d8c3
	ldir			;d8c5
	ld ix,0f3d1h		;d8c7
	ld iy,0f3d3h		;d8cb
	ld (ix+000h),002h	;d8cf
	ld (iy+000h),000h	;d8d3
ld8d7h:
	call sub_e98eh		;d8d7
	ld a,(0f3e3h)		;d8da
	and 080h		;d8dd
	jr nz,ld8f4h		;d8df
	inc (iy+000h)		;d8e1
	ld a,010h		;d8e4
	cp (iy+000h)		;d8e6
	jr nz,ld8d7h		;d8e9
	xor a			;d8eb
	ld (iy+000h),a		;d8ec
	inc (ix+000h)		;d8ef
	jr nz,ld8d7h		;d8f2
ld8f4h:
	ld a,(0f3d1h)		;d8f4
	cp 011h			;d8f7
	jr nc,ld90ah		;d8f9
	ld hl,ld984h		;d8fb
	call signon_end		;d8fe
	ld hl,str_notinst_end	;d901
	call signon_end		;d904
	jp ld93ch		;d907
ld90ah:
	ld ix,04000h		;d90a
	ld iy,lda3dh		;d90e
	ld (ix+001h),006h	;d912
	ld a,040h		;d916
	ld (lda3dh),a		;d918
	ld a,(0f3d1h)		;d91b
	sub 002h		;d91e
	ld l,a			;d920
	and 080h		;d921
	jr z,ld929h		;d923
	xor a			;d925
	ld (lea89h),a		;d926
ld929h:
	ld h,000h		;d929
	add hl,hl		;d92b
	dec hl			;d92c
	ld (lea8ah),hl		;d92d
	ld hl,ld984h		;d930
	call signon_end		;d933
	ld hl,ld9a3h		;d936
	call signon_end		;d939
ld93ch:
	ld hl,c000_end		;d93c
	call signon_end		;d93f
	ld hl,str_waiting_end	;d942
	call signon_end		;d945
	call sub_ec2ch		;d948
	ld a,e			;d94b
	cp 059h			;d94c
	jr nz,ld955h		;d94e
	ld a,0ffh		;d950
	ld (lda47h),a		;d952
ld955h:
	ld hl,str_clock_end	;d955
	call signon_end		;d958
	ld hl,lda8bh		;d95b
	call signon_end		;d95e
	ld hl,str_timeinit_end	;d961
	call signon_end		;d964
	ld a,00ch		;d967
	ld (lda8bh),a		;d969
	jp ldb5dh		;d96c
ld96fh:
	ld d,e			;d96f
	ld b,l			;d970
	ld b,e			;d971
	ld l,020h		;d972
	ld b,(hl)		;d974
	ld c,h			;d975
	ld c,a			;d976
	ld d,b			;d977
	ld d,b			;d978
	ld e,c			;d979
	jr nz,ld9c0h		;d97a
	ld c,c			;d97c
	ld d,e			;d97d
	ld c,e			;d97e
	nop			;d97f
c000_end:
STR_RAMDISK:

; BLOCK 'str_ramdisk' (start 0xd980 end 0xd98c)
str_ramdisk_start:
	defb 055h		;d980
	defb 053h		;d981
	defb 045h		;d982
	defb 020h		;d983
ld984h:
	defb 052h		;d984
	defb 041h		;d985
	defb 04dh		;d986
	defb 02dh		;d987
	defb 044h		;d988
	defb 049h		;d989
	defb 053h		;d98a
	defb 04bh		;d98b
str_ramdisk_end:
STR_NOTINST:

; BLOCK 'str_notinst' (start 0xd98c end 0xd99f)
str_notinst_start:
	defb 000h		;d98c
ld98dh:
	defb 020h		;d98d
	defb 04eh		;d98e
	defb 04fh		;d98f
	defb 054h		;d990
	defb 020h		;d991
	defb 049h		;d992
	defb 04eh		;d993
	defb 053h		;d994
	defb 054h		;d995
	defb 041h		;d996
	defb 04ch		;d997
	defb 04ch		;d998
	defb 045h		;d999
	defb 044h		;d99a
	defb 02eh		;d99b
	defb 00ah		;d99c
	defb 00dh		;d99d
	defb 000h		;d99e
str_notinst_end:
STR_NOTUSED:

; BLOCK 'str_notused' (start 0xd99f end 0xd9a8)
str_notused_start:
	defb 020h		;d99f
	defb 04eh		;d9a0
	defb 04fh		;d9a1
	defb 054h		;d9a2
ld9a3h:
	defb 020h		;d9a3
	defb 055h		;d9a4
	defb 053h		;d9a5
	defb 045h		;d9a6
	defb 044h		;d9a7
str_notused_end:
STR_WAITING:

; BLOCK 'str_waiting' (start 0xd9a8 end 0xd9bc)
str_waiting_start:
	defb 000h		;d9a8
ld9a9h:
	defb 00ch		;d9a9
	defb 052h		;d9aa
	defb 043h		;d9ab
	defb 037h		;d9ac
	defb 030h		;d9ad
	defb 032h		;d9ae
	defb 045h		;d9af
	defb 020h		;d9b0
	defb 057h		;d9b1
	defb 061h		;d9b2
	defb 069h		;d9b3
	defb 074h		;d9b4
	defb 069h		;d9b5
	defb 06eh		;d9b6
	defb 067h		;d9b7
	defb 02eh		;d9b8
	defb 00dh		;d9b9
	defb 00ah		;d9ba
	defb 000h		;d9bb
str_waiting_end:
STR_BOOTQ:

; BLOCK 'str_bootq' (start 0xd9bc end 0xd9cf)
str_bootq_start:
	defb 020h		;d9bc
	defb 041h		;d9bd
	defb 053h		;d9be
	defb 020h		;d9bf
ld9c0h:
	defb 042h		;d9c0
	defb 04fh		;d9c1
	defb 04fh		;d9c2
	defb 054h		;d9c3
	defb 044h		;d9c4
	defb 049h		;d9c5
	defb 053h		;d9c6
	defb 04bh		;d9c7
	defb 03fh		;d9c8
	defb 028h		;d9c9
	defb 059h		;d9ca
	defb 02fh		;d9cb
	defb 04eh		;d9cc
	defb 029h		;d9cd
	defb 000h		;d9ce
str_bootq_end:
STR_CLOCK:

; BLOCK 'str_clock' (start 0xd9cf end 0xd9dc)
str_clock_start:
	defb 080h		;d9cf
	defb 04bh		;d9d0
	defb 06ch		;d9d1
	defb 02eh		;d9d2
	defb 030h		;d9d3
	defb 030h		;d9d4
	defb 02eh		;d9d5
	defb 030h		;d9d6
	defb 030h		;d9d7
	defb 02eh		;d9d8
	defb 030h		;d9d9
	defb 030h		;d9da
	defb 080h		;d9db
str_clock_end:
STR_TIMEINIT:

; BLOCK 'str_timeinit' (start 0xd9dc end 0xd9f4)
str_timeinit_start:
	defb 054h		;d9dc
	defb 049h		;d9dd
	defb 04dh		;d9de
	defb 045h		;d9df
	defb 020h		;d9e0
	defb 04eh		;d9e1
	defb 04fh		;d9e2
	defb 054h		;d9e3
	defb 020h		;d9e4
	defb 049h		;d9e5
	defb 04eh		;d9e6
	defb 049h		;d9e7
	defb 054h		;d9e8
	defb 049h		;d9e9
	defb 041h		;d9ea
	defb 04ch		;d9eb
	defb 049h		;d9ec
	defb 05ah		;d9ed
	defb 045h		;d9ee
	defb 044h		;d9ef
	defb 02eh		;d9f0
	defb 00ah		;d9f1
	defb 00dh		;d9f2
	defb 000h		;d9f3
str_timeinit_end:

; BLOCK 'c008' (start 0xd9f4 end 0xda33)
c008_start:
	ld a,(bc)		;d9f4
	ld a,(bc)		;d9f5
	ld a,(bc)		;d9f6
	nop			;d9f7
	nop			;d9f8
	nop			;d9f9
	nop			;d9fa
	nop			;d9fb
	nop			;d9fc
	nop			;d9fd
	nop			;d9fe
	nop			;d9ff
	jp ldb54h		;da00
lda03h:
	jp ldb6dh		;da03
	jp lec28h		;da06
	jp sub_ec2ch		;da09
	jp le1e1h		;da0c
	jp ldc53h		;da0f
	jp ldcbah		;da12
	jp ldc93h		;da15
	jp sub_e6aeh		;da18
	jp sub_e330h		;da1b
	jp le3ffh		;da1e
	jp le404h		;da21
	jp le409h		;da24
	jp le411h		;da27
	jp le425h		;da2a
	jp ldc4fh		;da2d
	jp le40eh		;da30
c008_end:
JTVARS:

; BLOCK 'jtvars' (start 0xda33 end 0xda4a)
jtvars_start:
	defb 000h		;da33
lda34h:
	defb 000h		;da34
lda35h:
	defb 000h		;da35
	defb 000h		;da36
lda37h:
	defb 0ffh		;da37
	defb 0ffh		;da38
	defb 0ffh		;da39
	defb 0ffh		;da3a
	defb 0ffh		;da3b
lda3ch:
	defb 0ffh		;da3c
lda3dh:
	defb 0ffh		;da3d
	defb 0ffh		;da3e
lda3fh:
	defb 0ffh		;da3f
	defb 0ffh		;da40
	defb 0ffh		;da41
	defb 0ffh		;da42
	defb 0ffh		;da43
	defb 0ffh		;da44
	defb 0ffh		;da45
	defb 0ffh		;da46
lda47h:
	defb 000h		;da47
	defb 000h		;da48
	defb 000h		;da49
jtvars_end:

; BLOCK 'c010' (start 0xda4a end 0xda5f)
c010_start:
	jp le77ah		;da4a
	jp ldc8fh		;da4d
	jp ldb0ch		;da50
	jp ldac2h		;da53
	jp ldacfh		;da56
	jp ldb6dh		;da59
	jp ldb6dh		;da5c
c010_end:
JTGAP:

; BLOCK 'jtgap' (start 0xda5f end 0xda62)
jtgap_start:
	defb 000h		;da5f
lda60h:
	defb 098h		;da60
	defb 03ah		;da61
jtgap_end:

; BLOCK 'c012' (start 0xda62 end 0xda6e)
c012_start:
	jp ldae5h		;da62
	jp ldb08h		;da65
	jp ldc7ah		;da68
	jp ldc76h		;da6b
c012_end:
JTPAD:

; BLOCK 'jtpad' (start 0xda6e end 0xda70)
jtpad_start:
	defb 000h		;da6e
	defb 000h		;da6f
jtpad_end:

; BLOCK 'c014' (start 0xda70 end 0xda71)
c014_start:
	nop			;da70
c014_end:
ERRMSG:

; BLOCK 'errmsg' (start 0xda71 end 0xda8c)
errmsg_start:
	defb 00dh		;da71
	defb 00ah		;da72
	defb 044h		;da73
	defb 069h		;da74
	defb 073h		;da75
	defb 06bh		;da76
	defb 020h		;da77
	defb 072h		;da78
	defb 065h		;da79
	defb 061h		;da7a
	defb 064h		;da7b
	defb 020h		;da7c
	defb 065h		;da7d
	defb 072h		;da7e
	defb 072h		;da7f
	defb 06fh		;da80
	defb 072h		;da81
	defb 020h		;da82
	defb 02dh		;da83
	defb 020h		;da84
	defb 072h		;da85
	defb 065h		;da86
	defb 073h		;da87
	defb 065h		;da88
	defb 074h		;da89
	defb 000h		;da8a
lda8bh:
	defb 01dh		;da8b
errmsg_end:
SIGNON:

; BLOCK 'signon' (start 0xda8c end 0xdaae)
signon_start:
	defb 052h		;da8c
	defb 043h		;da8d
	defb 037h		;da8e
	defb 030h		;da8f
	defb 032h		;da90
	defb 045h		;da91
	defb 020h		;da92
	defb 035h		;da93
	defb 036h		;da94
	defb 06bh		;da95
	defb 020h		;da96
	defb 043h		;da97
	defb 050h		;da98
	defb 02fh		;da99
	defb 04dh		;da9a
	defb 020h		;da9b
	defb 056h		;da9c
	defb 065h		;da9d
	defb 072h		;da9e
	defb 020h		;da9f
	defb 032h		;daa0
	defb 02eh		;daa1
	defb 032h		;daa2
	defb 020h		;daa3
	defb 052h		;daa4
	defb 065h		;daa5
	defb 06ch		;daa6
	defb 020h		;daa7
	defb 031h		;daa8
	defb 02eh		;daa9
	defb 037h		;daaa
	defb 00dh		;daab
	defb 00ah		;daac
	defb 000h		;daad
signon_end:

; BLOCK 'c017' (start 0xdaae end 0xe9bf)
c017_start:
	ld a,(hl)		;daae
	or a			;daaf
	ret z			;dab0
	push hl			;dab1
	ld c,a			;dab2
	call le1e1h		;dab3
	pop hl			;dab6
	inc hl			;dab7
	jr signon_end		;dab8
ldabah:
	ld hl,c014_end		;daba
	call signon_end		;dabd
ldac0h:
	jr ldac0h		;dac0
ldac2h:
	ld a,0c3h		;dac2
	ld (0ffe7h),a		;dac4
	ld (0ffe8h),hl		;dac7
	ex de,hl		;daca
	ld (0ffdfh),hl		;dacb
	ret			;dace
ldacfh:
	di			;dacf
	or a			;dad0
	jr z,ldadch		;dad1
	ld de,(0fffch)		;dad3
	ld hl,(0fffeh)		;dad7
	ei			;dada
	ret			;dadb
ldadch:
	ld (0fffch),de		;dadc
	ld (0fffeh),hl		;dae0
	ei			;dae3
	ret			;dae4
ldae5h:
	di			;dae5
	or a			;dae6
	jr z,ldaf6h		;dae7
	ld bc,(0fff1h)		;dae9
	ld de,(0fff4h)		;daed
	ld hl,(0fff7h)		;daf1
	ei			;daf4
	ret			;daf5
ldaf6h:
	ld (0fff1h),bc		;daf6
	ld (0fff4h),de		;dafa
	ld (0fff7h),hl		;dafe
	ld a,032h		;db01
	ld (0fffbh),a		;db03
	ei			;db06
	xor a			;db07
ldb08h:
	ld (0fffah),a		;db08
	ret			;db0b
ldb0ch:
	add a,00ah		;db0c
	ld c,a			;db0e
ldb0fh:
	di			;db0f
	ld a,001h		;db10
	out (c),a		;db12
	in a,(c)		;db14
	ei			;db16
	and 001h		;db17
	jr z,ldb0fh		;db19
	ld hl,00002h		;db1b
	call sub_e6a3h		;db1e
	ld d,005h		;db21
	ld a,000h		;db23
	call sub_db4dh		;db25
	dec b			;db28
	ret m			;db29
	sla b			;db2a
	or b			;db2c
	call sub_db4dh		;db2d
	or 080h			;db30
	call sub_db4dh		;db32
	ld hl,00002h		;db35
	call sub_e6a3h		;db38
	ld a,c			;db3b
	cp 00ah			;db3c
	ld a,(0f421h)		;db3e
	jr z,ldb46h		;db41
	ld a,(0f423h)		;db43
ldb46h:
	and 020h		;db46
	jr z,sub_db4dh		;db48
	ld a,0ffh		;db4a
	ret			;db4c
sub_db4dh:
	di			;db4d
	out (c),d		;db4e
	out (c),a		;db50
	ei			;db52
	ret			;db53
ldb54h:
	ld sp,00080h		;db54
	ld hl,lda8bh		;db57
	call signon_end		;db5a
ldb5dh:
	xor a			;db5d
	ld (00004h),a		;db5e
	ld (0f3feh),a		;db61
	ld (0f3dah),a		;db64
	ld (0f3e3h),a		;db67
	ld (0f3dbh),a		;db6a
ldb6dh:
	ei			;db6d
	xor a			;db6e
	ld (0f3dch),a		;db6f
	ld (00003h),a		;db72
	ld (lec26h),a		;db75
	ld (0f3edh),a		;db78
	ld sp,00080h		;db7b
	ld a,(lda47h)		;db7e
	or a			;db81
	jr z,ldbb6h		;db82
	ld hl,0c400h		;db84
	xor a			;db87
	out (0e6h),a		;db88
	out (0e7h),a		;db8a
	ld b,a			;db8c
	ld c,0e8h		;db8d
	ld e,010h		;db8f
	call sub_db9fh		;db91
	ld a,001h		;db94
	out (0e6h),a		;db96
	ld e,006h		;db98
	call sub_db9fh		;db9a
	jr ldbedh		;db9d
sub_db9fh:
	in a,(0e7h)		;db9f
	and 0c0h		;dba1
	jr nz,ldbb3h		;dba3
	xor a			;dba5
	out (0e7h),a		;dba6
ldba8h:
	inir			;dba8
	inc a			;dbaa
	out (0e7h),a		;dbab
	cp e			;dbad
	ret z			;dbae
	ld b,000h		;dbaf
	jr ldba8h		;dbb1
ldbb3h:
	pop hl			;dbb3
	ld c,000h		;dbb4
ldbb6h:
	ld c,a			;dbb6
	call sub_e330h		;dbb7
	call sub_e6aeh		;dbba
	ld bc,0c400h		;dbbd
	call le409h		;dbc0
	ld bc,00001h		;dbc3
	call le3ffh		;dbc6
	ld bc,00000h		;dbc9
	call le404h		;dbcc
ldbcfh:
	push bc			;dbcf
	call le411h		;dbd0
	or a			;dbd3
	jp nz,ldabah		;dbd4
	ld hl,(0f3e7h)		;dbd7
	ld de,00080h		;dbda
	add hl,de		;dbdd
	ld b,h			;dbde
	ld c,l			;dbdf
	call le409h		;dbe0
	pop bc			;dbe3
	inc bc			;dbe4
	call le404h		;dbe5
	ld a,c			;dbe8
	cp 02ch			;dbe9
	jr nz,ldbcfh		;dbeb
ldbedh:
	ld bc,00080h		;dbed
	call le409h		;dbf0
	ld a,0c3h		;dbf3
	ld (00000h),a		;dbf5
	ld hl,lda03h		;dbf8
	ld (00001h),hl		;dbfb
	ld (00005h),a		;dbfe
	ld hl,0cc06h		;dc01
	ld (00006h),hl		;dc04
	ld a,(00004h)		;dc07
	and 00fh		;dc0a
	ld c,a			;dc0c
	ld a,(lda47h)		;dc0d
	cp c			;dc10
	jr z,ldc2fh		;dc11
	call sub_e330h		;dc13
	ld a,h			;dc16
	or l			;dc17
	jr z,ldc29h		;dc18
	ld bc,00002h		;dc1a
	call le3ffh		;dc1d
	call le404h		;dc20
	call le411h		;dc23
	or a			;dc26
	jr z,ldc2fh		;dc27
ldc29h:
	ld a,(lda47h)		;dc29
	ld (00004h),a		;dc2c
ldc2fh:
	ld a,(00004h)		;dc2f
	ld c,a			;dc32
	ld hl,0f3feh		;dc33
	ld a,(hl)		;dc36
	ld (hl),001h		;dc37
	or a			;dc39
	jr z,ldc4ch		;dc3a
	ld a,(0c407h)		;dc3c
	or a			;dc3f
	jr z,ldc4ch		;dc40
	ld hl,0c409h		;dc42
	add a,l			;dc45
	ld l,a			;dc46
	ld a,(hl)		;dc47
	or a			;dc48
	jp z,0c403h		;dc49
ldc4ch:
	jp 0c400h		;dc4c
ldc4fh:
	ld a,(0f41bh)		;dc4f
	ret			;dc52
ldc53h:
	ld a,(0f41bh)		;dc53
	or a			;dc56
	jr z,ldc53h		;dc57
	di			;dc59
	xor a			;dc5a
	ld (0f41bh),a		;dc5b
	ld a,005h		;dc5e
	out (00bh),a		;dc60
	ld a,(lda35h)		;dc62
	add a,08ah		;dc65
	out (00bh),a		;dc67
	ld a,001h		;dc69
	out (00bh),a		;dc6b
	ld a,01fh		;dc6d
	out (00bh),a		;dc6f
	ld a,c			;dc71
	out (009h),a		;dc72
	ei			;dc74
	ret			;dc75
ldc76h:
	ld a,(0f41dh)		;dc76
	ret			;dc79
ldc7ah:
	ld a,(0f41dh)		;dc7a
	or a			;dc7d
	jr z,ldc7ah		;dc7e
	ld a,(0f420h)		;dc80
	push af			;dc83
	xor a			;dc84
	ld (0f41dh),a		;dc85
	ld a,(lda35h)		;dc88
	ld c,00bh		;dc8b
	jr ldca6h		;dc8d
ldc8fh:
	ld a,(0f41ch)		;dc8f
	ret			;dc92
ldc93h:
	ld a,(0f41ch)		;dc93
	or a			;dc96
	jr z,ldc93h		;dc97
	ld a,(0f41fh)		;dc99
	push af			;dc9c
	xor a			;dc9d
	ld (0f41ch),a		;dc9e
	ld a,(lda34h)		;dca1
	ld c,00ah		;dca4
ldca6h:
	di			;dca6
	ld b,005h		;dca7
	out (c),b		;dca9
	add a,08ah		;dcab
	out (c),a		;dcad
	ld a,001h		;dcaf
	out (c),a		;dcb1
	ld a,01fh		;dcb3
	out (c),a		;dcb5
	ei			;dcb7
	pop af			;dcb8
	ret			;dcb9
ldcbah:
	ld a,(0f41eh)		;dcba
	or a			;dcbd
	jr z,ldcbah		;dcbe
	di			;dcc0
	xor a			;dcc1
	ld (0f41eh),a		;dcc2
	ld a,005h		;dcc5
	out (00ah),a		;dcc7
	ld a,(lda34h)		;dcc9
	add a,08ah		;dccc
	out (00ah),a		;dcce
	ld a,001h		;dcd0
	out (00ah),a		;dcd2
	ld a,01fh		;dcd4
	out (00ah),a		;dcd6
	ld a,c			;dcd8
	out (008h),a		;dcd9
	ei			;dcdb
	ret			;dcdc
	ld (0f3fbh),sp		;dcdd
	ld sp,0f620h		;dce1
	push af			;dce4
	ld a,028h		;dce5
	out (00bh),a		;dce7
	ld a,0ffh		;dce9
	ld (0f41bh),a		;dceb
	pop af			;dcee
	ld sp,(0f3fbh)		;dcef
	ei			;dcf3
	reti			;dcf4
	ld (0f3fbh),sp		;dcf6
	ld sp,0f620h		;dcfa
	push af			;dcfd
	in a,(00bh)		;dcfe
	ld (0f423h),a		;dd00
	ld a,010h		;dd03
	out (00bh),a		;dd05
	pop af			;dd07
	ld sp,(0f3fbh)		;dd08
	ei			;dd0c
	reti			;dd0d
	ld (0f3fbh),sp		;dd0f
	ld sp,0f620h		;dd13
	push af			;dd16
	in a,(009h)		;dd17
	ld (0f420h),a		;dd19
	ld a,0ffh		;dd1c
	ld (0f41dh),a		;dd1e
	pop af			;dd21
	ld sp,(0f3fbh)		;dd22
	ei			;dd26
	reti			;dd27
	ld (0f3fbh),sp		;dd29
	ld sp,0f620h		;dd2d
	push af			;dd30
	ld a,001h		;dd31
	out (00bh),a		;dd33
	in a,(00bh)		;dd35
	ld (0f424h),a		;dd37
	ld a,030h		;dd3a
	out (00bh),a		;dd3c
	xor a			;dd3e
	ld (0f420h),a		;dd3f
	cpl			;dd42
	ld (0f41dh),a		;dd43
	pop af			;dd46
	ld sp,(0f3fbh)		;dd47
	ei			;dd4b
	reti			;dd4c
	ld (0f3fbh),sp		;dd4e
	ld sp,0f620h		;dd52
	push af			;dd55
	ld a,028h		;dd56
	out (00ah),a		;dd58
	ld a,0ffh		;dd5a
	ld (0f41eh),a		;dd5c
	pop af			;dd5f
	ld sp,(0f3fbh)		;dd60
	ei			;dd64
	reti			;dd65
	ld (0f3fbh),sp		;dd67
	ld sp,0f620h		;dd6b
	push af			;dd6e
	in a,(00ah)		;dd6f
	ld (0f421h),a		;dd71
	ld a,010h		;dd74
	out (00ah),a		;dd76
	pop af			;dd78
	ld sp,(0f3fbh)		;dd79
	ei			;dd7d
	reti			;dd7e
	ld (0f3fbh),sp		;dd80
	ld sp,0f620h		;dd84
	push af			;dd87
	in a,(008h)		;dd88
	ld (0f41fh),a		;dd8a
	ld a,0ffh		;dd8d
	ld (0f41ch),a		;dd8f
	pop af			;dd92
	ld sp,(0f3fbh)		;dd93
	ei			;dd97
	reti			;dd98
	ld (0f3fbh),sp		;dd9a
	ld sp,0f620h		;dd9e
	push af			;dda1
	ld a,001h		;dda2
	out (00ah),a		;dda4
	in a,(00ah)		;dda6
	ld (0f422h),a		;dda8
	ld a,030h		;ddab
	out (00ah),a		;ddad
	xor a			;ddaf
	ld (0f41fh),a		;ddb0
	cpl			;ddb3
	ld (0f41ch),a		;ddb4
	pop af			;ddb7
	ld sp,(0f3fbh)		;ddb8
	ei			;ddbc
	reti			;ddbd
sub_ddbfh:
	ld a,h			;ddbf
	cpl			;ddc0
	ld h,a			;ddc1
	ld a,l			;ddc2
	cpl			;ddc3
	ld l,a			;ddc4
	ret			;ddc5
sub_ddc6h:
	call sub_ddbfh		;ddc6
	inc hl			;ddc9
	ret			;ddca
sub_ddcbh:
	ld hl,(0ffd2h)		;ddcb
	ld a,l			;ddce
	cp 080h			;ddcf
	ret nz			;ddd1
	ld a,h			;ddd2
	cp 007h			;ddd3
	ret			;ddd5
sub_ddd6h:
	ld a,(0f425h)		;ddd6
	or a			;ddd9
	ld a,c			;ddda
	ret nz			;dddb
	ld b,000h		;dddc
	add hl,bc		;ddde
	ld a,(hl)		;dddf
	ret			;dde0
ldde1h:
	push af			;dde1
	ld a,080h		;dde2
	out (001h),a		;dde4
	ld a,(0ffd1h)		;dde6
	out (000h),a		;dde9
	ld a,(0ffd4h)		;ddeb
	out (000h),a		;ddee
	pop af			;ddf0
	ret			;ddf1
lddf2h:
	ld hl,(0ffd2h)		;ddf2
	ld de,00050h		;ddf5
	add hl,de		;ddf8
	ld (0ffd2h),hl		;ddf9
	ld hl,0ffd4h		;ddfc
	inc (hl)		;ddff
	jr ldde1h		;de00
lde02h:
	ld hl,(0ffd2h)		;de02
	ld de,0ffb0h		;de05
	add hl,de		;de08
	ld (0ffd2h),hl		;de09
	ld hl,0ffd4h		;de0c
	dec (hl)		;de0f
	jr ldde1h		;de10
sub_de12h:
	ld hl,00000h		;de12
	ld (0ffd2h),hl		;de15
	xor a			;de18
	ld (0ffd1h),a		;de19
	ld (0ffd4h),a		;de1c
	ret			;de1f
lde20h:
	cp b			;de20
	ret c			;de21
	sub b			;de22
	jr lde20h		;de23
lde25h:
	ld hl,(0ffd5h)		;de25
	ld d,h			;de28
	ld e,l			;de29
	inc de			;de2a
	ld bc,0004fh		;de2b
	ld (hl),020h		;de2e
	ldir			;de30
	ld a,(0ffdbh)		;de32
	cp 000h			;de35
	ret z			;de37
	ld hl,(0ffdch)		;de38
	ld d,h			;de3b
	ld e,l			;de3c
	inc de			;de3d
	ld bc,00009h		;de3e
	ld (hl),000h		;de41
	ldir			;de43
	ret			;de45
lde46h:
	ld hl,0f850h		;de46
	ld de,0f800h		;de49
	ld bc,00780h		;de4c
	ldir			;de4f
	ld hl,0ff80h		;de51
	ld (0ffd5h),hl		;de54
	ld a,(0ffdbh)		;de57
	cp 000h			;de5a
	jr z,lde25h		;de5c
	ld hl,0f50ah		;de5e
	ld de,0f500h		;de61
	ld bc,000f0h		;de64
	ldir			;de67
	ld hl,0f5f0h		;de69
	ld (0ffdch),hl		;de6c
	jr lde25h		;de6f
sub_de71h:
	ld a,000h		;de71
	ld b,003h		;de73
lde75h:
	srl h			;de75
	rr l			;de77
	rra			;de79
	dec b			;de7a
	jr nz,lde75h		;de7b
	cp 000h			;de7d
	ret z			;de7f
	ld b,005h		;de80
lde82h:
	rra			;de82
	dec b			;de83
	jr nz,lde82h		;de84
	ret			;de86
sub_de87h:
	ld de,0f500h		;de87
	add hl,de		;de8a
	cp 000h			;de8b
	ld b,a			;de8d
	ld a,000h		;de8e
	jr nz,lde95h		;de90
	and (hl)		;de92
	ld (hl),a		;de93
	ret			;de94
lde95h:
	scf			;de95
	rla			;de96
	dec b			;de97
	jr nz,lde95h		;de98
	and (hl)		;de9a
	ld (hl),a		;de9b
	ret			;de9c
lde9dh:
	ld a,000h		;de9d
	cp c			;de9f
	jr z,ldea5h		;dea0
ldea2h:
	ldir			;dea2
	ret			;dea4
ldea5h:
	cp b			;dea5
	jr nz,ldea2h		;dea6
	ret			;dea8
sub_dea9h:
	ld a,000h		;dea9
	cp c			;deab
	jr z,ldeb1h		;deac
ldeaeh:
	lddr			;deae
	ret			;deb0
ldeb1h:
	cp b			;deb1
	jr nz,ldeaeh		;deb2
	ret			;deb4
	out (01ch),a		;deb5
	ret			;deb7
	call sub_de12h		;deb8
	ld a,002h		;debb
	ld (0ffd7h),a		;debd
	ret			;dec0
	ret			;dec1
	ld a,000h		;dec2
	ld (0ffd1h),a		;dec4
	jp ldde1h		;dec7
	ld hl,0f800h		;deca
	ld de,0f801h		;decd
	ld bc,0004fh		;ded0
	ld (hl),020h		;ded3
	ldir			;ded5
	inc hl			;ded7
	inc de			;ded8
	ld bc,0077fh		;ded9
	ld (hl),020h		;dedc
	ldir			;dede
	ld a,020h		;dee0
	ld (0f428h),a		;dee2
	call sub_de12h		;dee5
	call ldde1h		;dee8
	ld a,(0ffdbh)		;deeb
	cp 000h			;deee
	ret z			;def0
	xor a			;def1
	ld (0ffdbh),a		;def2
	ld hl,0f5f9h		;def5
	ld de,0f5f8h		;def8
	ld bc,000f9h		;defb
	ld (hl),000h		;defe
	lddr			;df00
	ret			;df02
	ld de,0f800h		;df03
	ld hl,(0ffd2h)		;df06
	add hl,de		;df09
	ld de,0004fh		;df0a
	add hl,de		;df0d
	ld d,h			;df0e
	ld e,l			;df0f
	dec de			;df10
	ld bc,00000h		;df11
	ld a,(0ffd1h)		;df14
	cpl			;df17
	inc a			;df18
	add a,04fh		;df19
	ld c,a			;df1b
	ld (hl),020h		;df1c
	call sub_dea9h		;df1e
	ld a,(0ffdbh)		;df21
	cp 000h			;df24
	ret z			;df26
	ld hl,(0ffd2h)		;df27
	ld d,000h		;df2a
	ld a,(0ffd1h)		;df2c
	ld e,a			;df2f
	add hl,de		;df30
	call sub_de71h		;df31
	call sub_de87h		;df34
	ld a,(0ffd1h)		;df37
	srl a			;df3a
	srl a			;df3c
	srl a			;df3e
	cpl			;df40
	add a,009h		;df41
	ret m			;df43
	ld c,a			;df44
	ld b,000h		;df45
	inc hl			;df47
	ld d,h			;df48
	ld e,l			;df49
	inc de			;df4a
	ld a,000h		;df4b
	jp lde9dh		;df4d
	ld hl,(0ffd2h)		;df50
	ld a,(0ffd1h)		;df53
	ld c,a			;df56
	ld b,000h		;df57
	add hl,bc		;df59
	call sub_ddc6h		;df5a
	ld de,007cfh		;df5d
	add hl,de		;df60
	ld b,h			;df61
	ld c,l			;df62
	ld hl,0ffcfh		;df63
	ld de,0ffceh		;df66
	ld (hl),020h		;df69
	call sub_dea9h		;df6b
	ld a,(0ffdbh)		;df6e
	cp 000h			;df71
	ret z			;df73
	ld hl,(0ffd2h)		;df74
	ld d,000h		;df77
	ld a,(0ffd1h)		;df79
	ld e,a			;df7c
	add hl,de		;df7d
	call sub_de71h		;df7e
	call sub_de87h		;df81
	call sub_ddbfh		;df84
	ld de,0f5f9h		;df87
	add hl,de		;df8a
	ld a,080h		;df8b
	and h			;df8d
	ret nz			;df8e
	ld b,h			;df8f
	ld c,l			;df90
	ld h,d			;df91
	ld l,e			;df92
	dec de			;df93
	ld (hl),000h		;df94
	jp sub_dea9h		;df96
	ld a,(0ffd1h)		;df99
	cp 000h			;df9c
	jr z,ldfa7h		;df9e
	dec a			;dfa0
	ld (0ffd1h),a		;dfa1
	jp ldde1h		;dfa4
ldfa7h:
	ld a,04fh		;dfa7
	ld (0ffd1h),a		;dfa9
	ld hl,(0ffd2h)		;dfac
	ld a,l			;dfaf
	or h			;dfb0
	jp nz,lde02h		;dfb1
	ld hl,00780h		;dfb4
	ld (0ffd2h),hl		;dfb7
	ld a,018h		;dfba
	ld (0ffd4h),a		;dfbc
	jp ldde1h		;dfbf
sub_dfc2h:
	ld a,(0ffd1h)		;dfc2
	cp 04fh			;dfc5
	jr z,ldfd0h		;dfc7
	inc a			;dfc9
	ld (0ffd1h),a		;dfca
	jp ldde1h		;dfcd
ldfd0h:
	ld a,000h		;dfd0
	ld (0ffd1h),a		;dfd2
	call sub_ddcbh		;dfd5
	jp nz,lddf2h		;dfd8
	call ldde1h		;dfdb
	jp lde46h		;dfde
	call sub_dfc2h		;dfe1
	call sub_dfc2h		;dfe4
	call sub_dfc2h		;dfe7
	jr sub_dfc2h		;dfea
	call sub_ddcbh		;dfec
	jp nz,lddf2h		;dfef
	jp lde46h		;dff2
	ld hl,(0ffd2h)		;dff5
	ld a,l			;dff8
	or h			;dff9
	jp nz,lde02h		;dffa
	ld hl,00780h		;dffd
	ld (0ffd2h),hl		;e000
	ld a,018h		;e003
	ld (0ffd4h),a		;e005
	jp ldde1h		;e008
	call sub_de12h		;e00b
	jp ldde1h		;e00e
	ld hl,(0ffd2h)		;e011
	ld b,h			;e014
	ld c,l			;e015
	ld de,0f850h		;e016
	add hl,de		;e019
	ld (0f426h),hl		;e01a
	ld de,0ffb0h		;e01d
	add hl,de		;e020
	ex de,hl		;e021
	ld h,b			;e022
	ld l,c			;e023
	call sub_ddc6h		;e024
	ld bc,00780h		;e027
	add hl,bc		;e02a
	ld b,h			;e02b
	ld c,l			;e02c
	ld hl,(0f426h)		;e02d
	call lde9dh		;e030
	ld hl,0ff80h		;e033
	ld (0ffd5h),hl		;e036
	ld a,(0ffdbh)		;e039
	cp 000h			;e03c
	jp z,lde25h		;e03e
	ld hl,(0ffd2h)		;e041
	call sub_de71h		;e044
	ld b,h			;e047
	ld c,l			;e048
	ld de,0f50ah		;e049
	add hl,de		;e04c
	ld (0f426h),hl		;e04d
	ld de,0fff6h		;e050
	add hl,de		;e053
	ex de,hl		;e054
	ld h,b			;e055
	ld l,c			;e056
	call sub_ddc6h		;e057
	ld bc,000f0h		;e05a
	add hl,bc		;e05d
	ld b,h			;e05e
	ld c,l			;e05f
	ld hl,(0f426h)		;e060
	call lde9dh		;e063
	ld hl,0f5f0h		;e066
	ld (0ffdch),hl		;e069
	jp lde25h		;e06c
	ld hl,(0ffd2h)		;e06f
	ld de,0f800h		;e072
	add hl,de		;e075
	ld (0ffd5h),hl		;e076
	call sub_ddc6h		;e079
	ld de,0ff80h		;e07c
	add hl,de		;e07f
	ld b,h			;e080
	ld c,l			;e081
	ld hl,0ff7fh		;e082
	ld de,0ffcfh		;e085
	call sub_dea9h		;e088
	ld a,(0ffdbh)		;e08b
	cp 000h			;e08e
	jp z,lde25h		;e090
	ld hl,(0ffd2h)		;e093
	call sub_de71h		;e096
	ld de,0f500h		;e099
	add hl,de		;e09c
	ld (0ffdch),hl		;e09d
	call sub_ddc6h		;e0a0
	ld de,0f5f0h		;e0a3
	add hl,de		;e0a6
	ld b,h			;e0a7
	ld c,l			;e0a8
	ld hl,0f5efh		;e0a9
	ld de,0f5f9h		;e0ac
	call sub_dea9h		;e0af
	jp lde25h		;e0b2
	ld a,002h		;e0b5
	ld (0ffdbh),a		;e0b7
	ret			;e0ba
	ld a,001h		;e0bb
	ld (0ffdbh),a		;e0bd
	ret			;e0c0
	ld hl,0f800h		;e0c1
	ld de,0f500h		;e0c4
	ld b,0fah		;e0c7
le0c9h:
	ld a,(de)		;e0c9
	ld c,008h		;e0ca
	cp 000h			;e0cc
	jr nz,le0d8h		;e0ce
le0d0h:
	ld (hl),020h		;e0d0
	inc hl			;e0d2
	dec c			;e0d3
	jr nz,le0d0h		;e0d4
	jr le0e1h		;e0d6
le0d8h:
	rra			;e0d8
	jr c,le0ddh		;e0d9
	ld (hl),020h		;e0db
le0ddh:
	inc hl			;e0dd
	dec c			;e0de
	jr nz,le0d8h		;e0df
le0e1h:
	inc de			;e0e1
	dec b			;e0e2
	jr nz,le0c9h		;e0e3
	ret			;e0e5
le0e6h:
	pop bc			;e0e6
	sbc a,06fh		;e0e7
	ret po			;e0e9
	ld de,0c1e0h		;e0ea
	sbc a,0c1h		;e0ed
	sbc a,099h		;e0ef
	rst 18h			;e0f1
	cp b			;e0f2
	sbc a,0b5h		;e0f3
	sbc a,099h		;e0f5
	rst 18h			;e0f7
	pop hl			;e0f8
	rst 18h			;e0f9
	call pe,0c1dfh		;e0fa
	sbc a,0cah		;e0fd
	sbc a,0c2h		;e0ff
	sbc a,0c1h		;e101
	sbc a,0c1h		;e103
	sbc a,0c1h		;e105
	sbc a,0c1h		;e107
	sbc a,0c1h		;e109
	sbc a,0c1h		;e10b
	sbc a,0b5h		;e10d
	ret po			;e10f
	cp e			;e110
	ret po			;e111
	pop bc			;e112
	ret po			;e113
	pop bc			;e114
	sbc a,0c2h		;e115
	rst 18h			;e117
	pop bc			;e118
	sbc a,0f5h		;e119
	rst 18h			;e11b
	pop bc			;e11c
	sbc a,0c1h		;e11d
	sbc a,00bh		;e11f
	ret po			;e121
	inc bc			;e122
	rst 18h			;e123
	ld d,b			;e124
	rst 18h			;e125
sub_e126h:
	ld a,000h		;e126
	ld (0ffd7h),a		;e128
	ld a,(0ffdah)		;e12b
	rlca			;e12e
	and 03eh		;e12f
	ld c,a			;e131
	ld b,000h		;e132
	ld hl,le0e6h		;e134
	add hl,bc		;e137
	ld e,(hl)		;e138
	inc hl			;e139
	ld d,(hl)		;e13a
	ex de,hl		;e13b
	jp (hl)			;e13c
sub_e13dh:
	ld a,(0ffdah)		;e13d
	and 07fh		;e140
	sub 020h		;e142
	ld hl,0ffd7h		;e144
	dec (hl)		;e147
	jr z,le14eh		;e148
	ld (0ffdeh),a		;e14a
	ret			;e14d
le14eh:
	ld d,a			;e14e
	ld a,(0ffdeh)		;e14f
	ld h,a			;e152
	ld a,(c008_end)		;e153
	or a			;e156
	jr z,le15ah		;e157
	ex de,hl		;e159
le15ah:
	ld a,h			;e15a
	ld b,050h		;e15b
	call lde20h		;e15d
	ld (0ffd1h),a		;e160
	ld a,d			;e163
	ld b,019h		;e164
	call lde20h		;e166
	ld (0ffd4h),a		;e169
	or a			;e16c
	jp z,ldde1h		;e16d
	ld hl,(0ffd2h)		;e170
	ld de,00050h		;e173
le176h:
	add hl,de		;e176
	dec a			;e177
	jr nz,le176h		;e178
	ld (0ffd2h),hl		;e17a
	jp ldde1h		;e17d
sub_e180h:
	ld hl,(0ffd2h)		;e180
	ld d,000h		;e183
	ld a,(0ffd1h)		;e185
	ld e,a			;e188
	add hl,de		;e189
	ld (0ffd8h),hl		;e18a
	ld a,(0ffdah)		;e18d
	cp 0c0h			;e190
	jr c,le196h		;e192
	sub 0c0h		;e194
le196h:
	ld c,a			;e196
	cp 080h			;e197
	jr c,le1a3h		;e199
	and 004h		;e19b
	ld (0f425h),a		;e19d
	ld a,c			;e1a0
	jr le1a9h		;e1a1
le1a3h:
	ld hl,0f680h		;e1a3
	call sub_ddd6h		;e1a6
le1a9h:
	ld hl,(0ffd8h)		;e1a9
	ld de,0f800h		;e1ac
	add hl,de		;e1af
	ld (hl),a		;e1b0
	call sub_dfc2h		;e1b1
	ld a,(0ffdbh)		;e1b4
	cp 002h			;e1b7
	ret nz			;e1b9
	ld hl,(0ffd8h)		;e1ba
	call sub_de71h		;e1bd
	ld de,0f500h		;e1c0
	add hl,de		;e1c3
	cp 000h			;e1c4
	ld b,a			;e1c6
	ld a,001h		;e1c7
	jr nz,le1ceh		;e1c9
	or (hl)			;e1cb
	ld (hl),a		;e1cc
	ret			;e1cd
le1ceh:
	rlca			;e1ce
	dec b			;e1cf
	jr nz,le1ceh		;e1d0
	or (hl)			;e1d2
	ld (hl),a		;e1d3
	ret			;e1d4
sub_e1d5h:
	ld hl,(lda60h)		;e1d5
	ld (0ffebh),hl		;e1d8
	ld a,(0f800h)		;e1db
	cp 0f3h			;e1de
	ret			;e1e0
le1e1h:
	di			;e1e1
	push hl			;e1e2
	ld hl,00000h		;e1e3
	add hl,sp		;e1e6
	ld sp,0f680h		;e1e7
	ei			;e1ea
	push hl			;e1eb
	push af			;e1ec
	push bc			;e1ed
	push de			;e1ee
	call sub_e1d5h		;e1ef
	jr nz,le1fah		;e1f2
	ld a,(0f428h)		;e1f4
	ld (0f800h),a		;e1f7
le1fah:
	ld a,c			;e1fa
	ld (0ffdah),a		;e1fb
	ld a,(0ffd7h)		;e1fe
	or a			;e201
	jr z,le209h		;e202
	call sub_e13dh		;e204
	jr le218h		;e207
le209h:
	ld a,(0ffdah)		;e209
	cp 020h			;e20c
	jr nc,le215h		;e20e
	call sub_e126h		;e210
	jr le218h		;e213
le215h:
	call sub_e180h		;e215
le218h:
	pop de			;e218
	pop bc			;e219
	pop af			;e21a
	pop hl			;e21b
	di			;e21c
	ld sp,hl		;e21d
	pop hl			;e21e
	ei			;e21f
	ret			;e220
	ld (0f3fbh),sp		;e221
	ld sp,0f620h		;e225
	push af			;e228
	push bc			;e229
	push de			;e22a
	push hl			;e22b
	in a,(001h)		;e22c
	ld a,006h		;e22e
	out (0fah),a		;e230
	ld a,007h		;e232
	out (0fah),a		;e234
	out (0fch),a		;e236
	ld hl,0f800h		;e238
	ld a,l			;e23b
	out (0f4h),a		;e23c
	ld a,h			;e23e
	out (0f4h),a		;e23f
	ld hl,007cfh		;e241
	ld a,l			;e244
	out (0f5h),a		;e245
	ld a,h			;e247
	out (0f5h),a		;e248
	ld a,000h		;e24a
	out (0f7h),a		;e24c
	out (0f7h),a		;e24e
	ld a,002h		;e250
	out (0fah),a		;e252
	ld a,003h		;e254
	out (0fah),a		;e256
	ld a,0d7h		;e258
	out (00eh),a		;e25a
	ld a,001h		;e25c
	out (00eh),a		;e25e
	ld hl,0fffch		;e260
	inc (hl)		;e263
	jr nz,le270h		;e264
	inc hl			;e266
	inc (hl)		;e267
	jr nz,le270h		;e268
	inc hl			;e26a
	inc (hl)		;e26b
	jr nz,le270h		;e26c
	inc hl			;e26e
	inc (hl)		;e26f
le270h:
	ld hl,(0ffdfh)		;e270
	ld a,l			;e273
	or h			;e274
	jr z,le280h		;e275
	dec hl			;e277
	ld a,l			;e278
	or h			;e279
	ld (0ffdfh),hl		;e27a
	call z,0ffe7h		;e27d
le280h:
	ld hl,(0ffe1h)		;e280
	ld a,l			;e283
	or h			;e284
	jr z,le290h		;e285
	dec hl			;e287
	ld a,l			;e288
	or h			;e289
	ld (0ffe1h),hl		;e28a
	call z,sub_e699h	;e28d
le290h:
	ld hl,(0ffe3h)		;e290
	ld a,l			;e293
	or h			;e294
	jr z,le2a0h		;e295
	dec hl			;e297
	ld a,l			;e298
	or h			;e299
	ld (0ffe3h),hl		;e29a
	call z,sub_e988h	;e29d
le2a0h:
	ld hl,(0ffebh)		;e2a0
	ld a,l			;e2a3
	or h			;e2a4
	jr z,le2c4h		;e2a5
	dec hl			;e2a7
	ld a,l			;e2a8
	or h			;e2a9
	ld (0ffebh),hl		;e2aa
	jr nz,le2c4h		;e2ad
	ld a,(0f800h)		;e2af
	ld (0f428h),a		;e2b2
	ld a,0f3h		;e2b5
	ld (0f800h),a		;e2b7
	ld a,080h		;e2ba
	out (001h),a		;e2bc
	ld a,020h		;e2be
	out (000h),a		;e2c0
	out (000h),a		;e2c2
le2c4h:
	ld hl,0fffbh		;e2c4
	dec (hl)		;e2c7
	jr nz,le2f2h		;e2c8
	ld (hl),032h		;e2ca
	dec hl			;e2cc
	ld b,002h		;e2cd
	dec hl			;e2cf
le2d0h:
	dec hl			;e2d0
	inc (hl)		;e2d1
	call sub_e320h		;e2d2
	jr nz,le2f2h		;e2d5
	dec b			;e2d7
	jr nz,le2d0h		;e2d8
	dec hl			;e2da
	inc (hl)		;e2db
	call sub_e320h		;e2dc
	ld hl,0fff1h		;e2df
	ld a,(hl)		;e2e2
	cp 032h			;e2e3
	jr nz,le2f2h		;e2e5
	inc hl			;e2e7
	ld a,(hl)		;e2e8
	cp 034h			;e2e9
	jr nz,le2f2h		;e2eb
	ld (hl),030h		;e2ed
	dec hl			;e2ef
	ld (hl),030h		;e2f0
le2f2h:
	ld hl,0fffah		;e2f2
	ld a,(hl)		;e2f5
	or a			;e2f6
	jr nz,le302h		;e2f7
	dec hl			;e2f9
	ld bc,0000ch		;e2fa
	ld de,0f84fh		;e2fd
	lddr			;e300
le302h:
	ld hl,(0ffe5h)		;e302
	ld a,l			;e305
	or h			;e306
	jr z,le30dh		;e307
	dec hl			;e309
	ld (0ffe5h),hl		;e30a
le30dh:
	ld hl,0f42ah		;e30d
	ld a,(hl)		;e310
	or a			;e311
	jr z,le315h		;e312
	dec (hl)		;e314
le315h:
	pop hl			;e315
	pop de			;e316
	pop bc			;e317
	pop af			;e318
	ld sp,(0f3fbh)		;e319
	ei			;e31d
	reti			;e31e
sub_e320h:
	ld a,(hl)		;e320
	cp 03ah			;e321
	ret nz			;e323
	ld (hl),030h		;e324
	dec hl			;e326
	inc (hl)		;e327
	ld a,(hl)		;e328
	cp 036h			;e329
	ret nz			;e32b
	ld (hl),030h		;e32c
	dec hl			;e32e
	ret			;e32f
sub_e330h:
	ld hl,00000h		;e330
	add hl,sp		;e333
	ld sp,0f680h		;e334
	push hl			;e337
	ld hl,00000h		;e338
	ld a,c			;e33b
	cp 007h			;e33c
	jp nc,le3eeh		;e33e
	ex de,hl		;e341
	ld hl,lda37h		;e342
	ld b,000h		;e345
	and 007h		;e347
	ld c,a			;e349
	add hl,bc		;e34a
	ld a,(hl)		;e34b
	cp 0ffh			;e34c
	jp z,le3eeh		;e34e
	ld a,c			;e351
	ld (0f3cbh),a		;e352
	ld bc,00010h		;e355
	ld de,lda37h		;e358
	ld hl,00000h		;e35b
le35eh:
	or a			;e35e
	jr z,le366h		;e35f
	inc de			;e361
	add hl,bc		;e362
	dec a			;e363
	jr le35eh		;e364
le366h:
	ld c,l			;e366
	ld b,h			;e367
	ex de,hl		;e368
	ld a,(hl)		;e369
	ld hl,0f3ebh		;e36a
	cp (hl)			;e36d
	jr z,le37fh		;e36e
	push af			;e370
	push bc			;e371
	ld a,(0f3dbh)		;e372
	or a			;e375
	call nz,sub_e568h	;e376
	xor a			;e379
	ld (0f3dbh),a		;e37a
	pop bc			;e37d
	pop af			;e37e
le37fh:
	ld (0f3ebh),a		;e37f
	call sub_e3f2h		;e382
	ld (0f3e9h),hl		;e385
	inc hl			;e388
	inc hl			;e389
	inc hl			;e38a
	inc hl			;e38b
	ld a,(hl)		;e38c
	ld (0f3ech),a		;e38d
	push bc			;e390
	ld a,(0f3ebh)		;e391
	and 0f8h		;e394
	or a			;e396
	rla			;e397
	ld e,a			;e398
	ld d,000h		;e399
	ld hl,leaa1h		;e39b
	add hl,de		;e39e
	ld de,0f408h		;e39f
	ld bc,00010h		;e3a2
	ldir			;e3a5
	ld hl,(0f408h)		;e3a7
	ld bc,0000dh		;e3aa
	add hl,bc		;e3ad
	ex de,hl		;e3ae
	ld hl,lea93h		;e3af
	ld b,000h		;e3b2
	ld a,(0f3cbh)		;e3b4
	ld c,a			;e3b7
	add hl,bc		;e3b8
	add hl,bc		;e3b9
	ld bc,00002h		;e3ba
	ldir			;e3bd
	pop bc			;e3bf
	ld hl,leb79h		;e3c0
	add hl,bc		;e3c3
	ex de,hl		;e3c4
	ld hl,0000ah		;e3c5
	add hl,de		;e3c8
	ex de,hl		;e3c9
	ld a,(0f408h)		;e3ca
	ld (de),a		;e3cd
	inc de			;e3ce
	ld a,(0f409h)		;e3cf
	ld (de),a		;e3d2
	push hl			;e3d3
	ld hl,0f3ffh		;e3d4
	ld a,(0f3cbh)		;e3d7
	ld (hl),002h		;e3da
	cp 006h			;e3dc
	jr z,le3e6h		;e3de
	dec (hl)		;e3e0
	cp 002h			;e3e1
	jr nc,le3e6h		;e3e3
	dec (hl)		;e3e5
le3e6h:
	ld c,a			;e3e6
	ld a,(hl)		;e3e7
	cp 001h			;e3e8
	call z,sub_e8bfh	;e3ea
	pop de			;e3ed
le3eeh:
	pop hl			;e3ee
	ld sp,hl		;e3ef
	ex de,hl		;e3f0
	ret			;e3f1
sub_e3f2h:
	ld hl,leb32h		;e3f2
	ld a,(0f3ebh)		;e3f5
	and 0f8h		;e3f8
	ld e,a			;e3fa
	ld d,000h		;e3fb
	add hl,de		;e3fd
	ret			;e3fe
le3ffh:
	ld (0f3cch),bc		;e3ff
	ret			;e403
le404h:
	ld (0f3ceh),bc		;e404
	ret			;e408
le409h:
	ld (0f3e7h),bc		;e409
	ret			;e40d
le40eh:
	ld h,b			;e40e
	ld l,c			;e40f
	ret			;e410
le411h:
	xor a			;e411
	ld (0f3dch),a		;e412
	ld a,001h		;e415
	ld (0f3e5h),a		;e417
	ld (0f3e4h),a		;e41a
	ld a,003h		;e41d
	ld (0f3e6h),a		;e41f
	jp le4b1h		;e422
le425h:
	xor a			;e425
	ld (0f3e5h),a		;e426
	ld a,c			;e429
	ld (0f3e6h),a		;e42a
	cp 003h			;e42d
	jr nz,le449h		;e42f
	ld a,(0f40ah)		;e431
	ld (0f3dch),a		;e434
	ld a,(0f3cbh)		;e437
	ld (0f3ddh),a		;e43a
	ld hl,(0f3cch)		;e43d
	ld (0f3deh),hl		;e440
	ld hl,(0f3ceh)		;e443
	ld (0f3e0h),hl		;e446
le449h:
	ld a,(0f3dch)		;e449
	or a			;e44c
	jr z,le4a7h		;e44d
	dec a			;e44f
	ld (0f3dch),a		;e450
	ld a,(0f3cbh)		;e453
	ld hl,0f3ddh		;e456
	cp (hl)			;e459
	jr nz,le4a7h		;e45a
	ld hl,0f3deh		;e45c
	ld a,(0f3cch)		;e45f
	cp (hl)			;e462
	jr nz,le4a7h		;e463
	ld a,(0f3ceh)		;e465
	ld hl,0f3e0h		;e468
	cp (hl)			;e46b
	jr nz,le4a7h		;e46c
	ld hl,(0f3e0h)		;e46e
	inc hl			;e471
	ld (0f3e0h),hl		;e472
	ex de,hl		;e475
	ld hl,0f40bh		;e476
	push bc			;e479
	ld c,(hl)		;e47a
	inc hl			;e47b
	ld b,(hl)		;e47c
	ex de,hl		;e47d
	and a			;e47e
	sbc hl,bc		;e47f
	pop bc			;e481
	jr c,le491h		;e482
	ld hl,00000h		;e484
	ld (0f3e0h),hl		;e487
	ld hl,(0f3deh)		;e48a
	inc hl			;e48d
	ld (0f3deh),hl		;e48e
le491h:
	xor a			;e491
	ld (0f3e4h),a		;e492
	ld a,(0f3ceh)		;e495
	ld hl,0f40dh		;e498
	and (hl)		;e49b
	cp (hl)			;e49c
	ld a,000h		;e49d
	jr nz,le4a2h		;e49f
	inc a			;e4a1
le4a2h:
	ld (0f3e2h),a		;e4a2
	jr le4b1h		;e4a5
le4a7h:
	xor a			;e4a7
	ld (0f3dch),a		;e4a8
	ld a,(0f40dh)		;e4ab
	ld (0f3e4h),a		;e4ae
le4b1h:
	ld hl,00000h		;e4b1
	add hl,sp		;e4b4
	ld sp,0f680h		;e4b5
	push hl			;e4b8
	ld a,(0f40eh)		;e4b9
	ld b,a			;e4bc
	ld hl,(0f3ceh)		;e4bd
le4c0h:
	dec b			;e4c0
	jr z,le4c9h		;e4c1
	srl h			;e4c3
	rr l			;e4c5
	jr le4c0h		;e4c7
le4c9h:
	ld (0f3d8h),hl		;e4c9
	ld hl,0f3dah		;e4cc
	ld a,(hl)		;e4cf
	ld (hl),001h		;e4d0
	or a			;e4d2
	jr z,le4f7h		;e4d3
	ld a,(0f3cbh)		;e4d5
	ld hl,0f3d0h		;e4d8
	cp (hl)			;e4db
	jr nz,le4f0h		;e4dc
	ld hl,0f3d1h		;e4de
	ld a,(0f3cch)		;e4e1
	cp (hl)			;e4e4
	jr nz,le4f0h		;e4e5
	ld a,(0f3d8h)		;e4e7
	ld hl,0f3d3h		;e4ea
	cp (hl)			;e4ed
	jr z,le514h		;e4ee
le4f0h:
	ld a,(0f3dbh)		;e4f0
	or a			;e4f3
	call nz,sub_e568h	;e4f4
le4f7h:
	ld a,(0f3cbh)		;e4f7
	ld (0f3d0h),a		;e4fa
	ld hl,(0f3cch)		;e4fd
	ld (0f3d1h),hl		;e500
	ld hl,(0f3d8h)		;e503
	ld (0f3d3h),hl		;e506
	ld a,(0f3e4h)		;e509
	or a			;e50c
	call nz,sub_e579h	;e50d
	xor a			;e510
	ld (0f3dbh),a		;e511
le514h:
	ld a,(0f3ceh)		;e514
	ld hl,0f40dh		;e517
	and (hl)		;e51a
	ld l,a			;e51b
	ld h,000h		;e51c
	add hl,hl		;e51e
	add hl,hl		;e51f
	add hl,hl		;e520
	add hl,hl		;e521
	add hl,hl		;e522
	add hl,hl		;e523
	add hl,hl		;e524
	ld de,0ed01h		;e525
	add hl,de		;e528
	ex de,hl		;e529
	ld hl,(0f3e7h)		;e52a
	ld bc,00080h		;e52d
	ex de,hl		;e530
	ld a,(0f3e5h)		;e531
	or a			;e534
	jr nz,le53dh		;e535
	ld a,001h		;e537
	ld (0f3dbh),a		;e539
	ex de,hl		;e53c
le53dh:
	ldir			;e53d
	ld a,(0f3e6h)		;e53f
	cp 001h			;e542
	ld hl,0f3e3h		;e544
	ld a,(hl)		;e547
	push af			;e548
	or a			;e549
	jr z,le550h		;e54a
	xor a			;e54c
	ld (0f3dah),a		;e54d
le550h:
	pop af			;e550
	ld (hl),000h		;e551
	jr nz,le565h		;e553
	or a			;e555
	jr nz,le565h		;e556
	xor a			;e558
	ld (0f3dbh),a		;e559
	call sub_e568h		;e55c
	ld hl,0f3e3h		;e55f
	ld a,(hl)		;e562
	ld (hl),000h		;e563
le565h:
	pop hl			;e565
	ld sp,hl		;e566
	ret			;e567
sub_e568h:
	ld a,(0f3ffh)		;e568
	cp 001h			;e56b
	jp z,le835h		;e56d
	jp nc,sub_e98eh		;e570
	call sub_e592h		;e573
	jp le652h		;e576
sub_e579h:
	ld a,(0f3e2h)		;e579
	or a			;e57c
	jr nz,le582h		;e57d
	ld (0f3dch),a		;e57f
le582h:
	ld a,(0f3ffh)		;e582
	cp 001h			;e585
	jp z,le83dh		;e587
	jp nc,le992h		;e58a
	call sub_e592h		;e58d
	jr le60ch		;e590
sub_e592h:
	ld a,(0f3d3h)		;e592
	ld c,a			;e595
	ld a,(0f3ech)		;e596
	ld b,a			;e599
	dec a			;e59a
	cp c			;e59b
	ld a,(0f3d0h)		;e59c
	jr nc,le5abh		;e59f
	or 004h			;e5a1
	ld (0f3edh),a		;e5a3
	ld a,c			;e5a6
	sub b			;e5a7
	ld c,a			;e5a8
	jr le5aeh		;e5a9
le5abh:
	ld (0f3edh),a		;e5ab
le5aeh:
	ld b,000h		;e5ae
	ld hl,(0f40fh)		;e5b0
	add hl,bc		;e5b3
	ld a,(hl)		;e5b4
	ld (0f3f1h),a		;e5b5
	ld a,(0f3d1h)		;e5b8
	ld (0f3f0h),a		;e5bb
	ld hl,0ed01h		;e5be
	ld (0f3eeh),hl		;e5c1
	ld a,(0f3d0h)		;e5c4
	ld hl,0f3d5h		;e5c7
	cp (hl)			;e5ca
	jr nz,le5dch		;e5cb
	ld a,(0f3d1h)		;e5cd
	ld hl,0f3d6h		;e5d0
	cp (hl)			;e5d3
	jr nz,le5dch		;e5d4
	ld a,(0f3d2h)		;e5d6
	inc hl			;e5d9
	cp (hl)			;e5da
	ret z			;e5db
le5dch:
	ld a,(0f3d0h)		;e5dc
	ld (0f3d5h),a		;e5df
	ld hl,(0f3d1h)		;e5e2
	ld (0f3d6h),hl		;e5e5
	call sub_e773h		;e5e8
	call sub_e73fh		;e5eb
	call le77ah		;e5ee
	ld a,(0f3edh)		;e5f1
	and 003h		;e5f4
	add a,020h		;e5f6
	cp b			;e5f8
	ret z			;e5f9
sub_e5fah:
	call sub_e773h		;e5fa
	call sub_e6f6h		;e5fd
	push bc			;e600
	call le77ah		;e601
	call sub_e73fh		;e604
	call le77ah		;e607
	pop bc			;e60a
	ret			;e60b
le60ch:
	ld a,00ah		;e60c
	ld (0f3f2h),a		;e60e
le611h:
	call sub_e67bh		;e611
	call sub_e773h		;e614
	ld hl,(0f3e9h)		;e617
	ld c,(hl)		;e61a
	inc hl			;e61b
	ld b,(hl)		;e61c
	inc hl			;e61d
	call sub_e7b1h		;e61e
	call sub_e671h		;e621
	call sub_e789h		;e624
	ld c,000h		;e627
le629h:
	ld hl,0f3f3h		;e629
	ld a,(hl)		;e62c
	and 0f8h		;e62d
	ret z			;e62f
	and 008h		;e630
	jr nz,le648h		;e632
	ld a,(0f3f2h)		;e634
	dec a			;e637
	ld (0f3f2h),a		;e638
	jr z,le648h		;e63b
	cp 005h			;e63d
	call z,sub_e5fah	;e63f
	xor a			;e642
	cp c			;e643
	jr z,le611h		;e644
	jr le657h		;e646
le648h:
	ld a,c			;e648
	ld (0f3dah),a		;e649
	ld a,001h		;e64c
	ld (0f3e3h),a		;e64e
	ret			;e651
le652h:
	ld a,00ah		;e652
	ld (0f3f2h),a		;e654
le657h:
	call sub_e67bh		;e657
	call sub_e773h		;e65a
	ld hl,(0f3e9h)		;e65d
	ld c,(hl)		;e660
	inc hl			;e661
	ld b,(hl)		;e662
	inc hl			;e663
	call sub_e790h		;e664
	call sub_e676h		;e667
	call sub_e789h		;e66a
	ld c,001h		;e66d
	jr le629h		;e66f
sub_e671h:
	ld a,006h		;e671
	jp le7bah		;e673
sub_e676h:
	ld a,005h		;e676
	jp le7bah		;e678
sub_e67bh:
	in a,(014h)		;e67b
	and 080h		;e67d
	ret z			;e67f
	di			;e680
	ld hl,(0ffe1h)		;e681
	ld a,l			;e684
	or h			;e685
	ld hl,(0ffe9h)		;e686
	ld (0ffe1h),hl		;e689
	ei			;e68c
	ret nz			;e68d
	ld a,001h		;e68e
	out (014h),a		;e690
le692h:
	ld hl,00032h		;e692
	call sub_e6a3h		;e695
	ret			;e698
sub_e699h:
	in a,(014h)		;e699
	and 080h		;e69b
	ret z			;e69d
	ld a,000h		;e69e
	out (014h),a		;e6a0
	ret			;e6a2
sub_e6a3h:
	ld (0ffe5h),hl		;e6a3
le6a6h:
	ld hl,(0ffe5h)		;e6a6
	ld a,l			;e6a9
	or h			;e6aa
	jr nz,le6a6h		;e6ab
	ret			;e6ad
sub_e6aeh:
	ld a,(0f3dbh)		;e6ae
	or a			;e6b1
	jr nz,le6b7h		;e6b2
	ld (0f3dah),a		;e6b4
le6b7h:
	ld a,(0f3ffh)		;e6b7
	cp 001h			;e6ba
	jp z,le93ah		;e6bc
	jr c,le6c7h		;e6bf
	xor a			;e6c1
	out (0e6h),a		;e6c2
	out (0e7h),a		;e6c4
	ret			;e6c6
le6c7h:
	call sub_e67bh		;e6c7
	ld a,(0f3cbh)		;e6ca
	ld (0f3edh),a		;e6cd
	ld (0f3d5h),a		;e6d0
	xor a			;e6d3
	ld (0f3d6h),a		;e6d4
	ld (0f3d7h),a		;e6d7
	call sub_e773h		;e6da
	call sub_e6f6h		;e6dd
	call le77ah		;e6e0
	ret			;e6e3
le6e4h:
	in a,(004h)		;e6e4
	and 0c0h		;e6e6
	cp 080h			;e6e8
	jr nz,le6e4h		;e6ea
	ret			;e6ec
le6edh:
	in a,(004h)		;e6ed
	and 0c0h		;e6ef
	cp 0c0h			;e6f1
	jr nz,le6edh		;e6f3
	ret			;e6f5
sub_e6f6h:
	call le6e4h		;e6f6
	ld a,007h		;e6f9
	out (005h),a		;e6fb
	call le6e4h		;e6fd
	ld a,(0f3edh)		;e700
	and 003h		;e703
	out (005h),a		;e705
	ret			;e707
	call le6e4h		;e708
	ld a,004h		;e70b
	out (005h),a		;e70d
	call le6e4h		;e70f
	ld a,(0f3edh)		;e712
	and 003h		;e715
	out (005h),a		;e717
	call le6edh		;e719
	in a,(005h)		;e71c
	ld (0f3f3h),a		;e71e
	ret			;e721
sub_e722h:
	call le6e4h		;e722
	ld a,008h		;e725
	out (005h),a		;e727
	call le6edh		;e729
	in a,(005h)		;e72c
	ld (0f3f3h),a		;e72e
	and 0c0h		;e731
	cp 080h			;e733
	ret z			;e735
	call le6edh		;e736
	in a,(005h)		;e739
	ld (0f3f4h),a		;e73b
	ret			;e73e
sub_e73fh:
	call le6e4h		;e73f
	ld a,00fh		;e742
	out (005h),a		;e744
	call le6e4h		;e746
	ld a,(0f3edh)		;e749
	and 003h		;e74c
	out (005h),a		;e74e
	call le6e4h		;e750
	ld a,(0f3f0h)		;e753
	out (005h),a		;e756
	ret			;e758
sub_e759h:
	ld hl,0f3f3h		;e759
	ld d,007h		;e75c
le75eh:
	call le6edh		;e75e
	in a,(005h)		;e761
	ld (hl),a		;e763
	inc hl			;e764
	ld a,004h		;e765
le767h:
	dec a			;e767
	jr nz,le767h		;e768
	in a,(004h)		;e76a
	and 010h		;e76c
	ret z			;e76e
	dec d			;e76f
	jr nz,le75eh		;e770
	ret			;e772
sub_e773h:
	di			;e773
	xor a			;e774
	ld (0f3fdh),a		;e775
	ei			;e778
	ret			;e779
le77ah:
	call sub_e789h		;e77a
	ld a,(0f3f3h)		;e77d
	ld b,a			;e780
	ld a,(0f3f4h)		;e781
	ld c,a			;e784
	call sub_e773h		;e785
	ret			;e788
sub_e789h:
	ld a,(0f3fdh)		;e789
	or a			;e78c
	jr z,sub_e789h		;e78d
	ret			;e78f
sub_e790h:
	ld a,005h		;e790
	di			;e792
	out (0fah),a		;e793
	ld a,049h		;e795
le797h:
	out (0fbh),a		;e797
	out (0fch),a		;e799
	ld a,(0f3eeh)		;e79b
	out (0f2h),a		;e79e
	ld a,(0f3efh)		;e7a0
	out (0f2h),a		;e7a3
	ld a,c			;e7a5
	out (0f3h),a		;e7a6
	ld a,b			;e7a8
	out (0f3h),a		;e7a9
	ld a,001h		;e7ab
	out (0fah),a		;e7ad
	ei			;e7af
	ret			;e7b0
sub_e7b1h:
	ld a,005h		;e7b1
	di			;e7b3
	out (0fah),a		;e7b4
	ld a,045h		;e7b6
	jr le797h		;e7b8
le7bah:
	push af			;e7ba
	di			;e7bb
	call le6e4h		;e7bc
	pop af			;e7bf
	ld b,(hl)		;e7c0
	inc hl			;e7c1
	add a,b			;e7c2
	out (005h),a		;e7c3
	call le6e4h		;e7c5
	ld a,(0f3edh)		;e7c8
	out (005h),a		;e7cb
	call le6e4h		;e7cd
	ld a,(0f3f0h)		;e7d0
	out (005h),a		;e7d3
	call le6e4h		;e7d5
	ld a,(0f3edh)		;e7d8
	rra			;e7db
	rra			;e7dc
	and 003h		;e7dd
	out (005h),a		;e7df
	call le6e4h		;e7e1
	ld a,(0f3f1h)		;e7e4
	out (005h),a		;e7e7
	call le6e4h		;e7e9
	ld a,(hl)		;e7ec
	inc hl			;e7ed
	out (005h),a		;e7ee
	call le6e4h		;e7f0
	ld a,(hl)		;e7f3
	inc hl			;e7f4
	out (005h),a		;e7f5
	call le6e4h		;e7f7
	ld a,(hl)		;e7fa
	out (005h),a		;e7fb
	call le6e4h		;e7fd
	ld a,(0f411h)		;e800
	out (005h),a		;e803
	ei			;e805
	ret			;e806
	ld (0f3fbh),sp		;e807
	ld sp,0f620h		;e80b
	push af			;e80e
	push bc			;e80f
	push de			;e810
	push hl			;e811
	ld a,0ffh		;e812
	ld (0f3fdh),a		;e814
	ld a,005h		;e817
le819h:
	dec a			;e819
	jr nz,le819h		;e81a
	in a,(004h)		;e81c
	and 010h		;e81e
	jr nz,le827h		;e820
	call sub_e722h		;e822
	jr le82ah		;e825
le827h:
	call sub_e759h		;e827
le82ah:
	pop hl			;e82a
	pop de			;e82b
	pop bc			;e82c
	pop af			;e82d
	ld sp,(0f3fbh)		;e82e
	ei			;e832
	reti			;e833
le835h:
	ld hl,048fch		;e835
	ld (0f419h),hl		;e838
	jr le843h		;e83b
le83dh:
	ld hl,0449ch		;e83d
	ld (0f419h),hl		;e840
le843h:
	xor a			;e843
	ld (0f3e3h),a		;e844
	call sub_e96bh		;e847
	in a,(0e0h)		;e84a
	and 080h		;e84c
	jr nz,le862h		;e84e
	ld a,(0f405h)		;e850
	ld c,a			;e853
	ld a,(0f3d1h)		;e854
	cp c			;e857
	jr z,le866h		;e858
	ld (0f405h),a		;e85a
	call sub_e94fh		;e85d
	cp 000h			;e860
le862h:
	ld (0f3e3h),a		;e862
	ret nz			;e865
le866h:
	ld a,(0f3d3h)		;e866
	ld c,a			;e869
	ld a,(0f3ech)		;e86a
	ld e,000h		;e86d
	ld b,a			;e86f
	dec a			;e870
	cp c			;e871
	jr nc,le879h		;e872
	ld a,c			;e874
	ld e,002h		;e875
	sub b			;e877
	ld c,a			;e878
le879h:
	ld hl,(0f40fh)		;e879
	ld b,000h		;e87c
	add hl,bc		;e87e
	ld a,(hl)		;e87f
	ld c,e			;e880
	out (0e2h),a		;e881
	ld b,c			;e883
	ld c,0fah		;e884
	ld e,00fh		;e886
	di			;e888
	out (c),e		;e889
	ld c,0f0h		;e88b
	ld de,0ed01h		;e88d
	out (0fch),a		;e890
	out (c),e		;e892
	out (c),d		;e894
	inc c			;e896
	ld hl,(0f3e9h)		;e897
	ld e,(hl)		;e89a
	inc hl			;e89b
	ld d,(hl)		;e89c
	out (c),e		;e89d
	out (c),d		;e89f
	ld de,(0f419h)		;e8a1
	ld a,d			;e8a5
	out (0fbh),a		;e8a6
	ld a,0dch		;e8a8
	and e			;e8aa
	ld d,a			;e8ab
	xor a			;e8ac
	out (0fah),a		;e8ad
	ei			;e8af
	ld c,b			;e8b0
	ld a,0a8h		;e8b1
	and e			;e8b3
	or c			;e8b4
	out (0e0h),a		;e8b5
	call sub_e915h		;e8b7
	and d			;e8ba
	ld (0f3e3h),a		;e8bb
	ret			;e8be
sub_e8bfh:
	ld a,(0f3cbh)		;e8bf
	ld c,a			;e8c2
	ld (0f407h),a		;e8c3
	ld a,0feh		;e8c6
	add a,c			;e8c8
	rlca			;e8c9
	ld c,a			;e8ca
	ld a,(0f406h)		;e8cb
	cp 0ffh			;e8ce
	jr z,le8d9h		;e8d0
	call sub_e907h		;e8d2
	ld a,(0f405h)		;e8d5
	ld (hl),a		;e8d8
le8d9h:
	ld a,c			;e8d9
	ld (0f406h),a		;e8da
	call sub_e907h		;e8dd
	ld c,0e1h		;e8e0
	ld a,(hl)		;e8e2
	out (c),a		;e8e3
	ld (0f405h),a		;e8e5
	ld hl,lda3fh		;e8e8
	ld a,(0f407h)		;e8eb
	add a,l			;e8ee
	ld l,a			;e8ef
	ld a,(hl)		;e8f0
	and 008h		;e8f1
	out (0e5h),a		;e8f3
	ld a,(hl)		;e8f5
	and 080h		;e8f6
	ld (0f400h),a		;e8f8
	ld a,(0f412h)		;e8fb
	ld b,a			;e8fe
	ld a,(0f406h)		;e8ff
	or b			;e902
	ld (0f406h),a		;e903
	ret			;e906
sub_e907h:
	ld hl,0f401h		;e907
	ld a,(0f406h)		;e90a
	and 006h		;e90d
	rrca			;e90f
	ld e,a			;e910
	ld d,000h		;e911
	add hl,de		;e913
	ret			;e914
sub_e915h:
	di			;e915
	ld b,0ffh		;e916
le918h:
	in a,(0e0h)		;e918
	dec b			;e91a
	jr z,le936h		;e91b
	and 001h		;e91d
	jr z,le918h		;e91f
	ei			;e921
	ld a,0ffh		;e922
	ld (0f42ah),a		;e924
le927h:
	ld a,(0f42ah)		;e927
	or a			;e92a
	jr z,le936h		;e92b
	in a,(0e0h)		;e92d
	and 001h		;e92f
	jr nz,le927h		;e931
	in a,(0e0h)		;e933
	ret			;e935
le936h:
	ei			;e936
	ld a,0f0h		;e937
	ret			;e939
le93ah:
	call sub_e96bh		;e93a
	xor a			;e93d
	ld b,a			;e93e
	ld (0f405h),a		;e93f
sub_e942h:
	ld a,001h		;e942
	or b			;e944
	out (0e0h),a		;e945
	call sub_e915h		;e947
	cpl			;e94a
	rlca			;e94b
	rlca			;e94c
	ld b,a			;e94d
	ret			;e94e
sub_e94fh:
	call sub_e95ch		;e94f
	cp 000h			;e952
	jr nz,le957h		;e954
	ret			;e956
le957h:
	ld b,008h		;e957
	call sub_e942h		;e959
sub_e95ch:
	ld a,(0f405h)		;e95c
	out (0e3h),a		;e95f
	ld a,01dh		;e961
	out (0e0h),a		;e963
	call sub_e915h		;e965
	and 018h		;e968
	ret			;e96a
sub_e96bh:
	ld a,(0f400h)		;e96b
	or a			;e96e
	jr z,sub_e988h		;e96f
	di			;e971
	ld hl,(0ffe3h)		;e972
	ld a,l			;e975
	or h			;e976
	ld hl,(0ffe9h)		;e977
	ld (0ffe3h),hl		;e97a
	ei			;e97d
	ret nz			;e97e
	ld a,(0f406h)		;e97f
	inc a			;e982
	out (0e4h),a		;e983
	jp le692h		;e985
sub_e988h:
	ld a,(0f406h)		;e988
	out (0e4h),a		;e98b
	ret			;e98d
sub_e98eh:
	ld e,0e0h		;e98e
	jr le994h		;e990
le992h:
	ld e,0c0h		;e992
le994h:
	ld hl,0ed01h		;e994
	ld a,(0f3d1h)		;e997
	out (0e6h),a		;e99a
	in a,(0e7h)		;e99c
	and e			;e99e
	ld (0f3e3h),a		;e99f
	ret nz			;e9a2
	ld a,(0f3d3h)		;e9a3
	out (0e7h),a		;e9a6
	ld b,000h		;e9a8
	ld c,0e8h		;e9aa
	ld a,e			;e9ac
	and 020h		;e9ad
	jr z,le9b5h		;e9af
	otir			;e9b1
	jr le9b7h		;e9b3
le9b5h:
	inir			;e9b5
le9b7h:
	in a,(0e7h)		;e9b7
	and 0c0h		;e9b9
	ld (0f3e3h),a		;e9bb
	ret			;e9be
c017_end:
SKEW_MAXI26:

; BLOCK 'skew_maxi26' (start 0xe9bf end 0xe9d9)
skew_maxi26_start:
	defb 001h		;e9bf
	defb 007h		;e9c0
	defb 00dh		;e9c1
	defb 013h		;e9c2
	defb 019h		;e9c3
	defb 005h		;e9c4
	defb 00bh		;e9c5
	defb 011h		;e9c6
	defb 017h		;e9c7
	defb 003h		;e9c8
	defb 009h		;e9c9
	defb 00fh		;e9ca
	defb 015h		;e9cb
	defb 002h		;e9cc
	defb 008h		;e9cd
	defb 00eh		;e9ce
	defb 014h		;e9cf
	defb 01ah		;e9d0
	defb 006h		;e9d1
	defb 00ch		;e9d2
	defb 012h		;e9d3
	defb 018h		;e9d4
	defb 004h		;e9d5
	defb 00ah		;e9d6
	defb 010h		;e9d7
	defb 016h		;e9d8
skew_maxi26_end:
SKEW_MAXI15:

; BLOCK 'skew_maxi15' (start 0xe9d9 end 0xe9e8)
skew_maxi15_start:
	defb 001h		;e9d9
	defb 005h		;e9da
	defb 009h		;e9db
	defb 00dh		;e9dc
	defb 002h		;e9dd
	defb 006h		;e9de
	defb 00ah		;e9df
	defb 00eh		;e9e0
	defb 003h		;e9e1
	defb 007h		;e9e2
	defb 00bh		;e9e3
	defb 00fh		;e9e4
	defb 004h		;e9e5
	defb 008h		;e9e6
	defb 00ch		;e9e7
skew_maxi15_end:
SKEW_QD10A:

; BLOCK 'skew_qd10a' (start 0xe9e8 end 0xe9f2)
skew_qd10a_start:
	defb 001h		;e9e8
	defb 003h		;e9e9
	defb 005h		;e9ea
	defb 007h		;e9eb
	defb 009h		;e9ec
	defb 002h		;e9ed
	defb 004h		;e9ee
	defb 006h		;e9ef
	defb 008h		;e9f0
	defb 00ah		;e9f1
skew_qd10a_end:
SKEW_SEQ26:

; BLOCK 'skew_seq26' (start 0xe9f2 end 0xea0c)
skew_seq26_start:
	defb 001h		;e9f2
	defb 002h		;e9f3
	defb 003h		;e9f4
	defb 004h		;e9f5
	defb 005h		;e9f6
	defb 006h		;e9f7
	defb 007h		;e9f8
	defb 008h		;e9f9
	defb 009h		;e9fa
	defb 00ah		;e9fb
	defb 00bh		;e9fc
	defb 00ch		;e9fd
	defb 00dh		;e9fe
	defb 00eh		;e9ff
	defb 00fh		;ea00
	defb 010h		;ea01
	defb 011h		;ea02
	defb 012h		;ea03
	defb 013h		;ea04
	defb 014h		;ea05
	defb 015h		;ea06
	defb 016h		;ea07
	defb 017h		;ea08
	defb 018h		;ea09
	defb 019h		;ea0a
	defb 01ah		;ea0b
skew_seq26_end:

; BLOCK 'c022' (start 0xea0c end 0xea55)
c022_start:
	jr nz,lea0eh		;ea0c
lea0eh:
	inc bc			;ea0e
	rlca			;ea0f
	nop			;ea10
	sub b			;ea11
	nop			;ea12
	ccf			;ea13
	nop			;ea14
	ret nz			;ea15
	nop			;ea16
	djnz lea19h		;ea17
lea19h:
	nop			;ea19
	nop			;ea1a
	ld b,b			;ea1b
	nop			;ea1c
	inc b			;ea1d
	rrca			;ea1e
	ld bc,00090h		;ea1f
	ld a,a			;ea22
	nop			;ea23
	ret nz			;ea24
	nop			;ea25
	jr nz,lea28h		;ea26
lea28h:
	nop			;ea28
	nop			;ea29
	ld c,b			;ea2a
	nop			;ea2b
	inc b			;ea2c
	rrca			;ea2d
	ld bc,00086h		;ea2e
	ld a,a			;ea31
	nop			;ea32
	ret nz			;ea33
	nop			;ea34
	jr nz,lea37h		;ea35
lea37h:
	ld (bc),a		;ea37
	nop			;ea38
	ld a,b			;ea39
	nop			;ea3a
	inc b			;ea3b
	rrca			;ea3c
	nop			;ea3d
	ld sp,07f02h		;ea3e
	nop			;ea41
	ret nz			;ea42
	nop			;ea43
	jr nz,lea46h		;ea44
lea46h:
	ld (bc),a		;ea46
	nop			;ea47
	ld a,b			;ea48
	nop			;ea49
	inc b			;ea4a
	rrca			;ea4b
	nop			;ea4c
	pop bc			;ea4d
	ld bc,0007fh		;ea4e
	ret nz			;ea51
	nop			;ea52
	nop			;ea53
	nop			;ea54
c022_end:
DPBASE:

; BLOCK 'dpbase' (start 0xea55 end 0xead6)
dpbase_start:
	defb 003h		;ea55
	defb 000h		;ea56
	defb 080h		;ea57
	defb 001h		;ea58
	defb 004h		;ea59
	defb 00fh		;ea5a
	defb 001h		;ea5b
	defb 086h		;ea5c
	defb 000h		;ea5d
	defb 07fh		;ea5e
	defb 000h		;ea5f
	defb 0c0h		;ea60
	defb 000h		;ea61
	defb 000h		;ea62
	defb 000h		;ea63
	defb 003h		;ea64
	defb 000h		;ea65
	defb 080h		;ea66
	defb 001h		;ea67
	defb 005h		;ea68
	defb 01fh		;ea69
	defb 001h		;ea6a
	defb 0ebh		;ea6b
	defb 001h		;ea6c
	defb 0ffh		;ea6d
	defb 001h		;ea6e
	defb 0f0h		;ea6f
	defb 000h		;ea70
	defb 000h		;ea71
	defb 000h		;ea72
	defb 01bh		;ea73
	defb 000h		;ea74
	defb 080h		;ea75
	defb 001h		;ea76
	defb 006h		;ea77
	defb 00fh		;ea78
	defb 003h		;ea79
	defb 0ebh		;ea7a
	defb 001h		;ea7b
	defb 0ffh		;ea7c
	defb 001h		;ea7d
	defb 0c0h		;ea7e
	defb 000h		;ea7f
	defb 000h		;ea80
	defb 000h		;ea81
	defb 01bh		;ea82
	defb 000h		;ea83
	defb 020h		;ea84
	defb 000h		;ea85
	defb 004h		;ea86
	defb 00fh		;ea87
	defb 001h		;ea88
lea89h:
	defb 000h		;ea89
lea8ah:
	defb 000h		;ea8a
	defb 07fh		;ea8b
	defb 000h		;ea8c
	defb 0c0h		;ea8d
	defb 000h		;ea8e
	defb 000h		;ea8f
	defb 000h		;ea90
	defb 002h		;ea91
	defb 000h		;ea92
lea93h:
	defb 002h		;ea93
	defb 000h		;ea94
	defb 002h		;ea95
	defb 000h		;ea96
	defb 002h		;ea97
	defb 000h		;ea98
	defb 002h		;ea99
	defb 000h		;ea9a
	defb 002h		;ea9b
	defb 000h		;ea9c
	defb 002h		;ea9d
	defb 000h		;ea9e
	defb 002h		;ea9f
	defb 000h		;eaa0
leaa1h:
	defb 00ch		;eaa1
	defb 0eah		;eaa2
	defb 008h		;eaa3
	defb 010h		;eaa4
	defb 000h		;eaa5
	defb 000h		;eaa6
	defb 001h		;eaa7
	defb 0f2h		;eaa8
	defb 0e9h		;eaa9
	defb 080h		;eaaa
	defb 000h		;eaab
	defb 000h		;eaac
	defb 000h		;eaad
	defb 000h		;eaae
	defb 000h		;eaaf
	defb 000h		;eab0
	defb 01bh		;eab1
	defb 0eah		;eab2
	defb 010h		;eab3
	defb 020h		;eab4
	defb 000h		;eab5
	defb 001h		;eab6
	defb 002h		;eab7
	defb 0f2h		;eab8
	defb 0e9h		;eab9
	defb 0ffh		;eaba
	defb 008h		;eabb
	defb 000h		;eabc
	defb 000h		;eabd
	defb 000h		;eabe
	defb 000h		;eabf
	defb 000h		;eac0
	defb 02ah		;eac1
	defb 0eah		;eac2
	defb 010h		;eac3
	defb 048h		;eac4
	defb 000h		;eac5
	defb 003h		;eac6
	defb 003h		;eac7
	defb 0e8h		;eac8
	defb 0e9h		;eac9
	defb 0ffh		;eaca
	defb 008h		;eacb
	defb 000h		;eacc
	defb 000h		;eacd
	defb 000h		;eace
	defb 000h		;eacf
	defb 000h		;ead0
	defb 039h		;ead1
	defb 0eah		;ead2
	defb 010h		;ead3
	defb 078h		;ead4
	defb 000h		;ead5
dpbase_end:
DPHINIT:

; BLOCK 'dphinit' (start 0xead6 end 0xeb66)
dphinit_start:
	defb 003h		;ead6
	defb 003h		;ead7
	defb 0d9h		;ead8
	defb 0e9h		;ead9
	defb 0ffh		;eada
	defb 008h		;eadb
	defb 008h		;eadc
	defb 000h		;eadd
	defb 000h		;eade
	defb 000h		;eadf
	defb 000h		;eae0
	defb 048h		;eae1
	defb 0eah		;eae2
	defb 010h		;eae3
	defb 080h		;eae4
	defb 001h		;eae5
	defb 003h		;eae6
	defb 003h		;eae7
	defb 000h		;eae8
	defb 000h		;eae9
	defb 000h		;eaea
	defb 0ffh		;eaeb
	defb 000h		;eaec
	defb 000h		;eaed
	defb 000h		;eaee
	defb 000h		;eaef
	defb 000h		;eaf0
	defb 057h		;eaf1
	defb 0eah		;eaf2
	defb 010h		;eaf3
	defb 080h		;eaf4
	defb 001h		;eaf5
	defb 003h		;eaf6
	defb 003h		;eaf7
	defb 000h		;eaf8
	defb 000h		;eaf9
	defb 000h		;eafa
	defb 0ffh		;eafb
	defb 000h		;eafc
	defb 000h		;eafd
	defb 000h		;eafe
	defb 000h		;eaff
	defb 000h		;eb00
	defb 066h		;eb01
	defb 0eah		;eb02
	defb 020h		;eb03
	defb 080h		;eb04
	defb 001h		;eb05
	defb 003h		;eb06
	defb 003h		;eb07
	defb 000h		;eb08
	defb 000h		;eb09
	defb 000h		;eb0a
	defb 0ffh		;eb0b
	defb 000h		;eb0c
	defb 000h		;eb0d
	defb 000h		;eb0e
	defb 000h		;eb0f
	defb 000h		;eb10
	defb 075h		;eb11
	defb 0eah		;eb12
	defb 040h		;eb13
	defb 080h		;eb14
	defb 001h		;eb15
	defb 003h		;eb16
	defb 003h		;eb17
	defb 000h		;eb18
	defb 000h		;eb19
	defb 000h		;eb1a
	defb 0ffh		;eb1b
	defb 000h		;eb1c
	defb 000h		;eb1d
	defb 000h		;eb1e
	defb 000h		;eb1f
	defb 000h		;eb20
	defb 084h		;eb21
	defb 0eah		;eb22
	defb 020h		;eb23
	defb 010h		;eb24
	defb 000h		;eb25
	defb 001h		;eb26
	defb 002h		;eb27
	defb 000h		;eb28
	defb 000h		;eb29
	defb 000h		;eb2a
	defb 000h		;eb2b
	defb 000h		;eb2c
	defb 000h		;eb2d
	defb 000h		;eb2e
	defb 000h		;eb2f
	defb 000h		;eb30
	defb 020h		;eb31
leb32h:
	defb 07fh		;eb32
	defb 000h		;eb33
	defb 000h		;eb34
	defb 000h		;eb35
	defb 010h		;eb36
	defb 007h		;eb37
	defb 024h		;eb38
	defb 020h		;eb39
	defb 0ffh		;eb3a
	defb 000h		;eb3b
	defb 040h		;eb3c
	defb 001h		;eb3d
	defb 010h		;eb3e
	defb 00eh		;eb3f
	defb 024h		;eb40
	defb 012h		;eb41
	defb 0ffh		;eb42
	defb 001h		;eb43
	defb 040h		;eb44
	defb 002h		;eb45
	defb 009h		;eb46
	defb 01bh		;eb47
	defb 027h		;eb48
	defb 01eh		;eb49
	defb 0ffh		;eb4a
	defb 001h		;eb4b
	defb 040h		;eb4c
	defb 002h		;eb4d
	defb 00fh		;eb4e
	defb 01bh		;eb4f
	defb 04dh		;eb50
	defb 010h		;eb51
	defb 0ffh		;eb52
	defb 001h		;eb53
	defb 018h		;eb54
	defb 000h		;eb55
	defb 000h		;eb56
	defb 020h		;eb57
	defb 000h		;eb58
	defb 010h		;eb59
	defb 0ffh		;eb5a
	defb 001h		;eb5b
	defb 018h		;eb5c
	defb 000h		;eb5d
	defb 000h		;eb5e
	defb 020h		;eb5f
	defb 000h		;eb60
	defb 010h		;eb61
	defb 0ffh		;eb62
	defb 001h		;eb63
	defb 029h		;eb64
	defb 000h		;eb65
dphinit_end:
WKSP1:

; BLOCK 'wksp1' (start 0xeb66 end 0xebc6)
wksp1_start:
	defb 000h		;eb66
	defb 020h		;eb67
	defb 000h		;eb68
	defb 010h		;eb69
	defb 0ffh		;eb6a
	defb 001h		;eb6b
	defb 053h		;eb6c
	defb 000h		;eb6d
	defb 000h		;eb6e
	defb 020h		;eb6f
	defb 000h		;eb70
	defb 010h		;eb71
	defb 000h		;eb72
	defb 001h		;eb73
	defb 000h		;eb74
	defb 000h		;eb75
	defb 000h		;eb76
	defb 000h		;eb77
	defb 000h		;eb78
leb79h:
	defb 000h		;eb79
	defb 000h		;eb7a
	defb 000h		;eb7b
	defb 000h		;eb7c
	defb 000h		;eb7d
	defb 000h		;eb7e
	defb 000h		;eb7f
	defb 000h		;eb80
	defb 001h		;eb81
	defb 0f1h		;eb82
	defb 02ah		;eb83
	defb 0eah		;eb84
	defb 0c8h		;eb85
	defb 0f1h		;eb86
	defb 081h		;eb87
	defb 0f1h		;eb88
	defb 000h		;eb89
	defb 000h		;eb8a
	defb 000h		;eb8b
	defb 000h		;eb8c
	defb 000h		;eb8d
	defb 000h		;eb8e
	defb 000h		;eb8f
	defb 000h		;eb90
	defb 001h		;eb91
	defb 0f1h		;eb92
	defb 02ah		;eb93
	defb 0eah		;eb94
	defb 02fh		;eb95
	defb 0f2h		;eb96
	defb 0e8h		;eb97
	defb 0f1h		;eb98
	defb 000h		;eb99
	defb 000h		;eb9a
	defb 000h		;eb9b
	defb 000h		;eb9c
	defb 000h		;eb9d
	defb 000h		;eb9e
	defb 000h		;eb9f
	defb 000h		;eba0
	defb 001h		;eba1
	defb 0f1h		;eba2
	defb 039h		;eba3
	defb 0eah		;eba4
	defb 096h		;eba5
	defb 0f2h		;eba6
	defb 04fh		;eba7
	defb 0f2h		;eba8
	defb 000h		;eba9
	defb 000h		;ebaa
	defb 000h		;ebab
	defb 000h		;ebac
	defb 000h		;ebad
	defb 000h		;ebae
	defb 000h		;ebaf
	defb 000h		;ebb0
	defb 001h		;ebb1
	defb 0f1h		;ebb2
	defb 02ah		;ebb3
	defb 0eah		;ebb4
	defb 0fdh		;ebb5
	defb 0f2h		;ebb6
	defb 0b6h		;ebb7
	defb 0f2h		;ebb8
	defb 000h		;ebb9
	defb 000h		;ebba
	defb 000h		;ebbb
	defb 000h		;ebbc
	defb 000h		;ebbd
	defb 000h		;ebbe
	defb 000h		;ebbf
	defb 000h		;ebc0
	defb 001h		;ebc1
	defb 0f1h		;ebc2
	defb 02ah		;ebc3
	defb 0eah		;ebc4
	defb 064h		;ebc5
wksp1_end:
DSKCFG:

; BLOCK 'dskcfg' (start 0xebc6 end 0xec27)
dskcfg_start:
	defb 0f3h		;ebc6
	defb 01dh		;ebc7
	defb 0f3h		;ebc8
	defb 000h		;ebc9
	defb 000h		;ebca
	defb 000h		;ebcb
	defb 000h		;ebcc
	defb 000h		;ebcd
	defb 000h		;ebce
	defb 000h		;ebcf
	defb 000h		;ebd0
	defb 001h		;ebd1
	defb 0f1h		;ebd2
	defb 02ah		;ebd3
	defb 0eah		;ebd4
	defb 064h		;ebd5
	defb 0f3h		;ebd6
	defb 084h		;ebd7
	defb 0f3h		;ebd8
	defb 000h		;ebd9
	defb 000h		;ebda
	defb 000h		;ebdb
	defb 000h		;ebdc
	defb 000h		;ebdd
	defb 000h		;ebde
	defb 000h		;ebdf
	defb 000h		;ebe0
	defb 001h		;ebe1
	defb 0f1h		;ebe2
	defb 084h		;ebe3
	defb 0eah		;ebe4
	defb 000h		;ebe5
	defb 000h		;ebe6
	defb 084h		;ebe7
	defb 0f3h		;ebe8
	defb 0fbh		;ebe9
	defb 0edh		;ebea
	defb 04dh		;ebeb
	defb 000h		;ebec
	defb 000h		;ebed
	defb 000h		;ebee
	defb 000h		;ebef
	defb 000h		;ebf0
	defb 000h		;ebf1
	defb 000h		;ebf2
	defb 000h		;ebf3
	defb 000h		;ebf4
	defb 000h		;ebf5
	defb 000h		;ebf6
	defb 000h		;ebf7
	defb 000h		;ebf8
	defb 000h		;ebf9
	defb 000h		;ebfa
	defb 000h		;ebfb
	defb 000h		;ebfc
	defb 000h		;ebfd
	defb 000h		;ebfe
	defb 000h		;ebff
	defb 0e9h		;ec00
	defb 0ebh		;ec01
	defb 0e9h		;ec02
	defb 0ebh		;ec03
	defb 021h		;ec04
	defb 0e2h		;ec05
	defb 007h		;ec06
	defb 0e8h		;ec07
	defb 0e9h		;ec08
	defb 0ebh		;ec09
	defb 0e9h		;ec0a
	defb 0ebh		;ec0b
	defb 0e9h		;ec0c
	defb 0ebh		;ec0d
	defb 0e9h		;ec0e
	defb 0ebh		;ec0f
	defb 0ddh		;ec10
	defb 0dch		;ec11
	defb 0f6h		;ec12
	defb 0dch		;ec13
	defb 00fh		;ec14
	defb 0ddh		;ec15
	defb 029h		;ec16
	defb 0ddh		;ec17
	defb 04eh		;ec18
	defb 0ddh		;ec19
	defb 067h		;ec1a
	defb 0ddh		;ec1b
	defb 080h		;ec1c
	defb 0ddh		;ec1d
	defb 09ah		;ec1e
	defb 0ddh		;ec1f
	defb 042h		;ec20
	defb 0ech		;ec21
	defb 064h		;ec22
	defb 0ech		;ec23
	defb 000h		;ec24
lec25h:
	defb 0ech		;ec25
lec26h:
	defb 000h		;ec26
dskcfg_end:
WKSP2:

; BLOCK 'wksp2' (start 0xec27 end 0xec56)
wksp2_start:
	defb 000h		;ec27
lec28h:
	defb 03ah		;ec28
	defb 026h		;ec29
	defb 0ech		;ec2a
	defb 0c9h		;ec2b
sub_ec2ch:
	defb 03ah		;ec2c
	defb 026h		;ec2d
	defb 0ech		;ec2e
	defb 0b7h		;ec2f
	defb 028h		;ec30
	defb 0fah		;ec31
	defb 0f3h		;ec32
	defb 0afh		;ec33
	defb 032h		;ec34
	defb 026h		;ec35
	defb 0ech		;ec36
	defb 0fbh		;ec37
	defb 0dbh		;ec38
	defb 010h		;ec39
	defb 04fh		;ec3a
	defb 021h		;ec3b
	defb 000h		;ec3c
	defb 0f7h		;ec3d
	defb 0cdh		;ec3e
	defb 0dch		;ec3f
	defb 0ddh		;ec40
	defb 0c9h		;ec41
	defb 0edh		;ec42
	defb 073h		;ec43
	defb 0fbh		;ec44
	defb 0f3h		;ec45
	defb 031h		;ec46
	defb 020h		;ec47
	defb 0f6h		;ec48
	defb 0f5h		;ec49
	defb 03eh		;ec4a
	defb 0ffh		;ec4b
	defb 032h		;ec4c
	defb 026h		;ec4d
	defb 0ech		;ec4e
	defb 0e5h		;ec4f
	defb 0cdh		;ec50
	defb 0d5h		;ec51
	defb 0e1h		;ec52
	defb 0e1h		;ec53
	defb 020h		;ec54
	defb 006h		;ec55
wksp2_end:

; BLOCK 'c028' (start 0xec56 end 0xec78)
c028_start:
	ld a,(0f428h)		;ec56
	ld (0f800h),a		;ec59
	pop af			;ec5c
	ld sp,(0f3fbh)		;ec5d
	ei			;ec61
	reti			;ec62
	ld (0f3fbh),sp		;ec64
	ld sp,0f620h		;ec68
	push af			;ec6b
	ld a,0ffh		;ec6c
	ld (dskcfg_end),a	;ec6e
	pop af			;ec71
	ld (0f3fbh),sp		;ec72
	ei			;ec76
	defb 0edh		;ec77
c028_end:
TRAILING:

; BLOCK 'trailing' (start 0xec78 end 0xec80)
trailing_start:
	defb 04dh		;ec78
	defb 082h		;ec79
	defb 084h		;ec7a
	defb 08bh		;ec7b
	defb 000h		;ec7c
	defb 000h		;ec7d
	defb 000h		;ec7e
	defb 000h		;ec7f
trailing_end:

; BLOCK 'c030' (start 0xec80 end 0xec8a)
c030_start:
	jp 0c75ch		;ec80
	jp 0c758h		;ec83
	ld a,a			;ec86
	nop			;ec87
	nop			;ec88
	defb 001h		;ec89
c030_end:
