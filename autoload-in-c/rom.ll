; ModuleID = 'rom.c'
source_filename = "rom.c"
target datalayout = "e-m:o-p:16:8-i16:8-i32:8-i64:8-i128:8-f16:8-f32:8-f64:8-f128:8-ve-a:8-n8:16"
target triple = "z80"

%struct.fdc_result_block = type { i8, i8, i8, i8, i8, i8, i8, i8 }
%struct.fdc_command_block = type { i8, i8, i8, i8, i8, i8, i8 }
%struct.format_entry = type { i8, i8 }

@fdc_result = dso_local local_unnamed_addr global %struct.fdc_result_block zeroinitializer, align 1
@drive_select = dso_local local_unnamed_addr global i8 0, align 1
@fdc_isr_delay = dso_local local_unnamed_addr global i8 0, align 1
@fdc_result_delay = dso_local local_unnamed_addr global i8 0, align 1
@fdc_cmd = dso_local local_unnamed_addr global %struct.fdc_command_block zeroinitializer, align 1
@floppy_operation_completed_flag = dso_local global i8 0, align 1
@is_mini = dso_local local_unnamed_addr global i8 0, align 1
@is_mfm = dso_local local_unnamed_addr global i8 0, align 1
@disk_type = dso_local local_unnamed_addr global i8 0, align 1
@more_tracks_to_read = dso_local local_unnamed_addr global i8 0, align 1
@retry_count = dso_local local_unnamed_addr global i8 0, align 1
@dma_transfer_address = dso_local local_unnamed_addr global i16 0, align 1
@dma_transfer_size = dso_local local_unnamed_addr global i16 0, align 1
@bytes_left_to_read = dso_local local_unnamed_addr global i16 0, align 1
@error_saved = dso_local local_unnamed_addr global i8 0, align 1
@code_end = dso_local local_unnamed_addr constant i8 -1, align 1
@.str = private unnamed_addr constant [20 x i8] c"**DISKETTE ERROR** \00", align 1
@sem702_font = internal unnamed_addr constant [1408 x i8] c"\00\00\08\08\00\08\08\08\00\08\08\01@\01@\00\00A\00\01@\00\00A\08\08\01@\08\08\00\1C\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\00\08\08\00\08\08\08\00\08\08\02 \02 \00\00\22\00\02 \00\00\22\08\08\01@\08\08\00\1C\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\14\08\1E\1C\1E>><\22\1C \22\02\22\22>\1E\1C\1E\1C>\22\22\22\22\22><\1C\1C\08\00\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\00\08\08\00\08\08\08\00\08\08\02 \04\10\00\00\1C\00\04\10\00\00\22\08\08\02 \1C\1C6\08\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\14$\22$\02\02\02\22\08 \12\026&\22\22\22\22\22\08\22\22\22\22\22 \0A\22\14\1C\00\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\0Fp\7F\00\00\08\08\00\08\08\08\00\08\08\04\10\18\0C\00\00\00\00\08\08\00\00\14\08\08\02 >>6k\00\00\00\00\0F\0F\0F\0Fpppp\7F\7F\7F\7F\00\00\00\00\0F\0F\0F\0Fpppp\7F\7F\7F\7F\22\22$\02$\02\02\02\22\08 \0A\02**\22\22\22\22\02\08\22\22\22\14\14\10\0A2>*\00\00\00\00\00\0F\0F\0F\0Fpppp\7F\7F\7F\7F\00\00\00\00\0F\0F\0F\0Fpppp\7F\7F\7F\7F\00\00\08\08\00\08\08\08\00\08\08\04\10 \02\00\00\00\00\10\04\00\00\14\08\08\04\10\7F\7F\7F\7F\00\00\00\00\0F\0F\0F\0Fpppp\7F\7F\7F\7F\00\00\00\00\0F\0F\0F\0Fpppp\7F\7F\7F\7F\22\22\1C\02$\0E\0E2>\08 \06\02*2\22\1E\22\1E\1C\08\22\14\22\08\08\08\1E*\22\08\00\00\00\00\00\0F\0F\0F\0Fpppp\7F\7F\7F\7F\00\00\00\00\0F\0F\0F\0Fpppp\7F\7F\7F\7Fx\0Fx\0F\7F\0Fx\7F\7F\08\7F\08\08@\01\01@\00\00`\03\03`\08\04\10\04\10>\7F\7Fk\00\00\00\00\0F\0F\0F\0Fpppp\7F\7F\7F\7F\00\00\00\00\0F\0F\0F\0Fpppp\7F\7F\7F\7F2>$\02$\02\02\22\22\08 \0A\02\22\22\22\02*\0A \08\22\14*\14\08\04\0A&>\08\00\00\00\00\00\0F\0F\0F\0Fpppp\7F\7F\7F\7F\00\00\00\00\0F\0F\0F\0Fpppp\7F\7F\7F\7F\08\08\00\00\08\08\08\00\00\08\08\10\04\00\00\02 \00\00\00\00\04\10\14\04\10\08\08\1C\7F>\08\00\00\00\00\0F\0F\0F\0Fpppp\7F\7F\7F\7F\00\00\00\00\0F\0F\0F\0Fpppp\7F\7F\7F\7F.\22$\22$\02\02\22\22\08\22\12\02\22\22\22\02\12\12\22\08\22\086\22\08\02\0A\22\22\08\00\00\00\00\00\0F\0F\0F\0Fpppp\7F\7F\7F\7F\00\00\00\00\0F\0F\0F\0Fpppp\7F\7F\7F\7F\08\08\00\00\08\08\08\00\00\08\08\10\04\00\00\04\10\00\00\00\00\08\08\14\02 \08\08\1C*\1C\08\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F \22\1E\1C\1E>\02<\22\1C\1C\22>\22\22>\02,\22\1C\08\1C\08\22\22\08>:\1C\22\08\00pppppppppppppppp\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\08\08\00\00\08\08\08\00\00\08\08 \02\00\00\18\0C\00\1C\00\00\10\04\22\02 \08\08\08\08\08\1C\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\7Fpppppppppppppppp\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\08\08\00\00\08\08\08\00\00\08\08 \02\00\00 \02\00\22\00\00 \02\22\01@\08\08\08\1C\08\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00pppppppppppppppp\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\08\08\00\00\08\08\08\00\00\08\08@\01\00\00@\01\00A\00\00@\01A\01@\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\0F\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00pppppppppppppppp\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F\7F", align 1
@banner_string = external dso_local constant [0 x i8], align 1
@display_sw1_status.prefix = internal constant [15 x i8] c"SW1 12345678: \00", align 1
@qr_screen = internal unnamed_addr constant [117 x i8] c"7s353.xt17s355/%5%%7:%5/%5ss#119%iu#s31}fk&y>te`.pr cpwq\22#w(|=7}$!$).sk=d?,|607s35*a%9uq=b55/%5=.|0\22m7>!###!# #! \22##!", align 1
@is_double_sided = internal unnamed_addr global i1 false, align 1
@msg_rc702 = internal constant [7 x i8] c" RC702\00", align 1
@.str.1 = private unnamed_addr constant [31 x i8] c" **NO DISKETTE NOR LINEPROG** \00", align 1
@saved_fdc_command = internal unnamed_addr global i8 0, align 1
@eot_gap3_table = internal unnamed_addr constant [2 x [4 x [2 x %struct.format_entry]]] [[4 x [2 x %struct.format_entry]] [[2 x %struct.format_entry] [%struct.format_entry { i8 26, i8 7 }, %struct.format_entry { i8 52, i8 7 }], [2 x %struct.format_entry] [%struct.format_entry { i8 15, i8 14 }, %struct.format_entry { i8 26, i8 14 }], [2 x %struct.format_entry] [%struct.format_entry { i8 8, i8 27 }, %struct.format_entry { i8 15, i8 27 }], [2 x %struct.format_entry] [%struct.format_entry zeroinitializer, %struct.format_entry { i8 8, i8 53 }]], [4 x [2 x %struct.format_entry]] [[2 x %struct.format_entry] [%struct.format_entry { i8 16, i8 7 }, %struct.format_entry { i8 32, i8 7 }], [2 x %struct.format_entry] [%struct.format_entry { i8 9, i8 14 }, %struct.format_entry { i8 16, i8 14 }], [2 x %struct.format_entry] [%struct.format_entry { i8 5, i8 27 }, %struct.format_entry { i8 9, i8 27 }], [2 x %struct.format_entry] [%struct.format_entry zeroinitializer, %struct.format_entry { i8 5, i8 53 }]]], align 1
@.str.2 = private unnamed_addr constant [7 x i8] c" RC700\00", align 1
@boot_dir = internal unnamed_addr global ptr null, align 1
@.str.3 = private unnamed_addr constant [5 x i8] c"SYSM\00", align 1
@.str.4 = private unnamed_addr constant [5 x i8] c"SYSC\00", align 1
@.str.5 = private unnamed_addr constant [22 x i8] c" **NO SYSTEM FILES** \00", align 1
@.str.6 = private unnamed_addr constant [17 x i8] c" **NO KATALOG** \00", align 1

; Function Attrs: minsize nounwind optsize
define dso_local void @nothing_int() local_unnamed_addr #0 {
entry:
  tail call void asm sideeffect "ei", ""() #10, !srcloc !8
  ret void
}

; Function Attrs: minsize nounwind optsize
define dso_local void @refresh_crt_dma_50hz_interrupt() local_unnamed_addr #0 {
entry:
  tail call fastcc void @refresh_crt_dma_50hz_body() #11
  tail call void asm sideeffect "ei", ""() #10, !srcloc !8
  ret void
}

; Function Attrs: alwaysinline minsize nounwind optsize
define internal fastcc void @refresh_crt_dma_50hz_body() unnamed_addr #1 {
entry:
  %0 = tail call i8 asm sideeffect "in $0, ($1)", "=a,i"(i8 1) #10, !srcloc !9
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -6, i8 6) #10, !srcloc !10
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -4, i8 0) #10, !srcloc !11
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -12, i8 48) #10, !srcloc !12
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -12, i8 120) #10, !srcloc !13
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -11, i8 -49) #10, !srcloc !14
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -11, i8 7) #10, !srcloc !15
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -6, i8 2) #10, !srcloc !16
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 14, i8 -41) #10, !srcloc !17
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 14, i8 1) #10, !srcloc !18
  ret void
}

; Function Attrs: minsize nounwind optsize
define dso_local void @floppy_completed_operation_interrupt() local_unnamed_addr #0 {
entry:
  store volatile i8 2, ptr @floppy_operation_completed_flag, align 1, !tbaa !19
  %0 = tail call i8 asm sideeffect "in $0, ($1)", "=a,i"(i8 4) #10, !srcloc !20
  %1 = and i8 %0, 16
  %tobool.not.i = icmp eq i8 %1, 0
  br i1 %tobool.not.i, label %if.else.i, label %if.then.i

if.then.i:                                        ; preds = %entry
  tail call fastcc void @fdc_read_result() #11
  br label %floppy_completed_operation_body.exit

if.else.i:                                        ; preds = %entry
  tail call fastcc void @fdc_write_when_ready(i8 noundef zeroext 8) #11
  %call.i = tail call fastcc zeroext i8 @fdc_read_when_ready() #11
  store i8 %call.i, ptr @fdc_result, align 1, !tbaa !21
  %cmp.not.i = icmp slt i8 %call.i, -64
  br i1 %cmp.not.i, label %floppy_completed_operation_body.exit, label %if.then.i1

if.then.i1:                                       ; preds = %if.else.i
  %call2.i = tail call fastcc zeroext i8 @fdc_read_when_ready() #11
  store i8 %call2.i, ptr getelementptr inbounds nuw (i8, ptr @fdc_result, i16 1), align 1, !tbaa !23
  br label %floppy_completed_operation_body.exit

floppy_completed_operation_body.exit:             ; preds = %if.then.i1, %if.else.i, %if.then.i
  tail call void asm sideeffect "ei", ""() #10, !srcloc !8
  ret void
}

; Function Attrs: minsize noreturn nounwind optsize
define dso_local void @main_relocated() local_unnamed_addr #2 {
entry:
  tail call void asm sideeffect "ld i, a", "a"(i8 96) #10, !srcloc !24
  tail call void asm sideeffect "im 2", ""() #10, !srcloc !25
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 18, i8 2) #10, !srcloc !26
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 19, i8 4) #10, !srcloc !27
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 18, i8 79) #10, !srcloc !28
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 19, i8 15) #10, !srcloc !29
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 18, i8 -125) #10, !srcloc !30
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 19, i8 -125) #10, !srcloc !31
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 12, i8 8) #10, !srcloc !32
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 12, i8 71) #10, !srcloc !33
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 12, i8 32) #10, !srcloc !34
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 13, i8 71) #10, !srcloc !35
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 13, i8 32) #10, !srcloc !36
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 14, i8 -41) #10, !srcloc !37
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 14, i8 1) #10, !srcloc !38
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 15, i8 -41) #10, !srcloc !39
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 15, i8 1) #10, !srcloc !40
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -8, i8 32) #10, !srcloc !41
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -5, i8 -64) #10, !srcloc !42
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -6, i8 0) #10, !srcloc !43
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -5, i8 74) #10, !srcloc !44
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 1, i8 0) #10, !srcloc !45
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 0, i8 79) #10, !srcloc !46
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 0, i8 -104) #10, !srcloc !47
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 0, i8 122) #10, !srcloc !48
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 0, i8 93) #10, !srcloc !49
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 1, i8 -128) #10, !srcloc !50
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 0, i8 0) #10, !srcloc !51
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 0, i8 0) #10, !srcloc !52
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 1, i8 -32) #10, !srcloc !53
  tail call fastcc void @load_chargen_font() #11
  tail call fastcc void @delay(i8 noundef zeroext 2, i8 noundef zeroext -66) #11
  br label %while.cond.i

while.cond.i:                                     ; preds = %while.cond.i, %entry
  %0 = tail call i8 asm sideeffect "in $0, ($1)", "=a,i"(i8 4) #10, !srcloc !54
  %1 = and i8 %0, 31
  %tobool.not.i = icmp eq i8 %1, 0
  br i1 %tobool.not.i, label %init_fdc.exit, label %while.cond.i, !llvm.loop !55

init_fdc.exit:                                    ; preds = %while.cond.i
  tail call fastcc void @fdc_write_when_ready(i8 noundef zeroext 3) #11
  tail call fastcc void @fdc_write_when_ready(i8 noundef zeroext 79) #11
  tail call fastcc void @fdc_write_when_ready(i8 noundef zeroext 32) #11
  %call = tail call ptr @memset(ptr noundef nonnull inttoptr (i16 30768 to ptr), i16 noundef 32, i16 noundef 2000) #12
  tail call fastcc void @display_banner_and_start_crt() #11
  store i8 3, ptr @fdc_isr_delay, align 1, !tbaa !19
  store i8 4, ptr @fdc_result_delay, align 1, !tbaa !19
  %2 = tail call i8 asm sideeffect "in $0, ($1)", "=a,i"(i8 20) #10, !srcloc !57
  %3 = lshr i8 %2, 7
  store i8 %3, ptr @is_mini, align 1, !tbaa !19
  tail call void asm sideeffect "ei", ""() #10, !srcloc !8
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 20, i8 1) #10, !srcloc !58
  store i8 5, ptr @retry_count, align 1, !tbaa !19
  tail call fastcc void @boot_from_floppy_or_jump_prom1() #11
  br label %for.cond

for.cond:                                         ; preds = %for.cond, %init_fdc.exit
  br label %for.cond
}

; Function Attrs: minsize nounwind optsize
define internal fastcc void @load_chargen_font() unnamed_addr #3 {
entry:
  br label %for.cond

for.cond:                                         ; preds = %for.inc7, %entry
  %line.0 = phi i8 [ 0, %entry ], [ %inc8, %for.inc7 ]
  %p.0 = phi ptr [ @sem702_font, %entry ], [ %p.1, %for.inc7 ]
  %exitcond14.not = icmp eq i8 %line.0, 11
  br i1 %exitcond14.not, label %for.end9, label %for.body

for.body:                                         ; preds = %for.cond
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -46, i8 %line.0) #10, !srcloc !59
  %scevgep = getelementptr i8, ptr %p.0, i16 1
  br label %for.cond2

for.cond2:                                        ; preds = %for.body6, %for.body
  %ch.0 = phi i8 [ 0, %for.body ], [ %inc, %for.body6 ]
  %p.1 = phi ptr [ %p.0, %for.body ], [ %uglygep, %for.body6 ]
  %exitcond.not = icmp eq i8 %ch.0, -128
  br i1 %exitcond.not, label %for.inc7, label %for.body6

for.body6:                                        ; preds = %for.cond2
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -47, i8 %ch.0) #10, !srcloc !60
  %0 = zext i8 %ch.0 to i16
  %uglygep = getelementptr i8, ptr %scevgep, i16 %0
  %1 = load i8, ptr %p.1, align 1, !tbaa !19
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -45, i8 %1) #10, !srcloc !61
  %inc = add nuw i8 %ch.0, 1
  br label %for.cond2, !llvm.loop !62

for.inc7:                                         ; preds = %for.cond2
  %inc8 = add nuw nsw i8 %line.0, 1
  br label %for.cond, !llvm.loop !63

for.end9:                                         ; preds = %for.cond
  ret void
}

; Function Attrs: minsize optsize
declare dso_local ptr @memset(ptr noundef, i16 noundef, i16 noundef) local_unnamed_addr #4

; Function Attrs: minsize nounwind optsize
define internal fastcc void @display_banner_and_start_crt() unnamed_addr #3 {
entry:
  %call = tail call ptr @memset(ptr noundef nonnull inttoptr (i16 30768 to ptr), i16 noundef 32, i16 noundef 2000) #12
  %call1 = tail call ptr @memcpy(ptr noundef nonnull inttoptr (i16 30768 to ptr), ptr noundef nonnull @banner_string, i16 noundef 46) #12
  tail call fastcc void @display_sw1_status() #11
  tail call fastcc void @draw_qr() #11
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -6, i8 6) #10, !srcloc !64
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -4, i8 0) #10, !srcloc !65
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -12, i8 48) #10, !srcloc !66
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -12, i8 120) #10, !srcloc !67
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -11, i8 -49) #10, !srcloc !68
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -11, i8 7) #10, !srcloc !69
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -6, i8 2) #10, !srcloc !70
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 1, i8 35) #10, !srcloc !71
  ret void
}

; Function Attrs: minsize nounwind optsize
define internal fastcc void @fdc_read_result() unnamed_addr #5 {
entry:
  br label %for.cond

for.cond:                                         ; preds = %for.body, %entry
  %z80-indexiv.iv = phi i8 [ %3, %for.body ], [ 0, %entry ]
  %.not = icmp eq i8 %z80-indexiv.iv, 7
  br i1 %.not, label %for.end, label %for.body

for.body:                                         ; preds = %for.cond
  %call = tail call fastcc zeroext i8 @fdc_read_when_ready() #11
  %0 = zext i8 %z80-indexiv.iv to i16
  %uglygep = getelementptr i8, ptr @fdc_result, i16 %0
  store i8 %call, ptr %uglygep, align 1, !tbaa !19
  %1 = tail call i8 asm sideeffect "in $0, ($1)", "=a,i"(i8 4) #10, !srcloc !72
  %2 = and i8 %1, 16
  %tobool.not = icmp eq i8 %2, 0
  %3 = add i8 %z80-indexiv.iv, 1
  br i1 %tobool.not, label %if.then, label %for.cond, !llvm.loop !73

if.then:                                          ; preds = %for.body
  %4 = tail call i8 asm sideeffect "in $0, ($1)", "=a,i"(i8 -8) #10, !srcloc !74
  %arrayidx6 = getelementptr inbounds nuw i8, ptr %uglygep, i16 1
  store i8 %4, ptr %arrayidx6, align 1, !tbaa !19
  br label %cleanup

for.end:                                          ; preds = %for.cond
  store i8 -2, ptr @error_saved, align 1, !tbaa !19
  tail call fastcc void @error_display_halt(i8 noundef zeroext -2) #11
  br label %cleanup

cleanup:                                          ; preds = %for.end, %if.then
  ret void
}

; Function Attrs: minsize nounwind optsize
define internal fastcc zeroext i8 @fdc_read_when_ready() unnamed_addr #5 {
entry:
  br label %do.body

do.body:                                          ; preds = %do.cond, %entry
  %t.0 = phi i16 [ 0, %entry ], [ %inc, %do.cond ]
  %0 = tail call i8 asm sideeffect "in $0, ($1)", "=a,i"(i8 4) #10, !srcloc !75
  %cmp = icmp ugt i8 %0, -65
  br i1 %cmp, label %if.then, label %do.cond

if.then:                                          ; preds = %do.body
  %1 = tail call i8 asm sideeffect "in $0, ($1)", "=a,i"(i8 5) #10, !srcloc !76
  br label %cleanup

do.cond:                                          ; preds = %do.body
  %inc = add i16 %t.0, 1
  %tobool.not = icmp eq i16 %inc, 0
  br i1 %tobool.not, label %cleanup, label %do.body, !llvm.loop !77

cleanup:                                          ; preds = %do.cond, %if.then
  %retval.0 = phi i8 [ %1, %if.then ], [ -1, %do.cond ]
  ret i8 %retval.0
}

; Function Attrs: minsize nounwind optsize
define internal fastcc void @error_display_halt(i8 noundef zeroext range(i8 -2, 41) %code) unnamed_addr #5 {
entry:
  store i8 %code, ptr @error_saved, align 1, !tbaa !19
  tail call void asm sideeffect "ei", ""() #10, !srcloc !8
  %0 = load i8, ptr @disk_type, align 1, !tbaa !19
  %1 = and i8 %0, 1
  %tobool.not = icmp eq i8 %1, 0
  br i1 %tobool.not, label %if.end, label %do.end

if.end:                                           ; preds = %entry
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 28, i8 0) #10, !srcloc !78
  %call = tail call ptr @memcpy(ptr noundef nonnull inttoptr (i16 30928 to ptr), ptr noundef nonnull @.str, i16 noundef 19) #12
  tail call fastcc void @halt_forever() #13
  unreachable

do.end:                                           ; preds = %entry
  ret void
}

; Function Attrs: minsize optsize
declare dso_local ptr @memcpy(ptr noundef, ptr noundef, i16 noundef) local_unnamed_addr #4

; Function Attrs: minsize noreturn nounwind optsize
define internal fastcc void @halt_forever() unnamed_addr #2 {
entry:
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 15, i8 3) #10, !srcloc !79
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -6, i8 5) #10, !srcloc !80
  tail call void asm sideeffect "ei", ""() #10, !srcloc !8
  br label %for.cond

for.cond:                                         ; preds = %for.cond, %entry
  br label %for.cond
}

; Function Attrs: minsize nounwind optsize
define internal fastcc void @fdc_write_when_ready(i8 noundef zeroext %val) unnamed_addr #5 {
entry:
  br label %do.body

do.body:                                          ; preds = %do.cond, %entry
  %t.0 = phi i16 [ 0, %entry ], [ %inc, %do.cond ]
  %0 = tail call i8 asm sideeffect "in $0, ($1)", "=a,i"(i8 4) #10, !srcloc !81
  %cmp = icmp slt i8 %0, -64
  br i1 %cmp, label %if.then, label %do.cond

if.then:                                          ; preds = %do.body
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 5, i8 %val) #10, !srcloc !82
  br label %cleanup

do.cond:                                          ; preds = %do.body
  %inc = add i16 %t.0, 1
  %tobool.not = icmp eq i16 %inc, 0
  br i1 %tobool.not, label %cleanup, label %do.body, !llvm.loop !83

cleanup:                                          ; preds = %do.cond, %if.then
  ret void
}

; Function Attrs: minsize nounwind optsize
define internal fastcc void @delay(i8 noundef zeroext range(i8 1, 3) %outer, i8 noundef zeroext range(i8 -66, 3) %inner) unnamed_addr #5 {
entry:
  %0 = icmp eq i8 %outer, 1
  br label %do.body

do.body:                                          ; preds = %entry, %do.end7
  %outer.addr.0 = phi i1 [ %0, %entry ], [ true, %do.end7 ]
  br label %do.body1

do.body1:                                         ; preds = %do.end, %do.body
  %mid.0 = phi i8 [ %inner, %do.body ], [ %dec5, %do.end ]
  br label %do.body2

do.body2:                                         ; preds = %do.body2, %do.body1
  %k.0 = phi i8 [ 0, %do.body1 ], [ %dec, %do.body2 ]
  tail call void asm sideeffect "", ""() #10, !srcloc !84
  %dec = add i8 %k.0, -1
  %tobool3.not = icmp eq i8 %dec, 0
  br i1 %tobool3.not, label %do.end, label %do.body2, !llvm.loop !85

do.end:                                           ; preds = %do.body2
  %dec5 = add i8 %mid.0, -1
  %tobool6.not = icmp eq i8 %dec5, 0
  br i1 %tobool6.not, label %do.end7, label %do.body1, !llvm.loop !86

do.end7:                                          ; preds = %do.end
  br i1 %outer.addr.0, label %do.end11, label %do.body, !llvm.loop !87

do.end11:                                         ; preds = %do.end7
  ret void
}

; Function Attrs: minsize nounwind optsize
define internal fastcc void @display_sw1_status() unnamed_addr #3 {
entry:
  %0 = tail call i8 asm sideeffect "in $0, ($1)", "=a,i"(i8 20) #10, !srcloc !88
  %call = tail call ptr @memcpy(ptr noundef nonnull inttoptr (i16 30826 to ptr), ptr noundef nonnull @display_sw1_status.prefix, i16 noundef 14) #12
  br label %for.cond

for.cond:                                         ; preds = %for.body, %entry
  %sw.0 = phi i8 [ %0, %entry ], [ %2, %for.body ]
  %p.0 = phi ptr [ inttoptr (i16 30840 to ptr), %entry ], [ %uglygep, %for.body ]
  %i.0 = phi i8 [ 0, %entry ], [ %inc, %for.body ]
  %exitcond.not = icmp eq i8 %i.0, 8
  br i1 %exitcond.not, label %for.end, label %for.body

for.body:                                         ; preds = %for.cond
  %and = and i8 %sw.0, 1
  %add = or disjoint i8 %and, 48
  %1 = zext nneg i8 %i.0 to i16
  %uglygep = getelementptr i8, ptr inttoptr (i16 30841 to ptr), i16 %1
  store i8 %add, ptr %p.0, align 1, !tbaa !19
  %2 = lshr i8 %sw.0, 1
  %inc = add nuw nsw i8 %i.0, 1
  br label %for.cond, !llvm.loop !89

for.end:                                          ; preds = %for.cond
  ret void
}

; Function Attrs: minsize nofree norecurse nosync nounwind optsize memory(write, inaccessiblemem: none, target_mem: none)
define internal fastcc void @draw_qr() unnamed_addr #6 {
entry:
  store i8 -124, ptr inttoptr (i16 32032 to ptr), align 32, !tbaa !19
  br label %for.cond

for.cond:                                         ; preds = %for.end, %entry
  %s.0 = phi ptr [ @qr_screen, %entry ], [ %s.1, %for.end ]
  %d.0 = phi ptr [ inttoptr (i16 32033 to ptr), %entry ], [ %add.ptr, %for.end ]
  %r.0 = phi i8 [ 0, %entry ], [ %inc9, %for.end ]
  %exitcond17.not = icmp eq i8 %r.0, 9
  br i1 %exitcond17.not, label %for.end10, label %for.cond2.preheader

for.cond2.preheader:                              ; preds = %for.cond
  %scevgep = getelementptr i8, ptr %s.0, i16 1
  %scevgep15 = getelementptr i8, ptr %d.0, i16 1
  br label %for.cond2

for.cond2:                                        ; preds = %for.cond2.preheader, %for.body6
  %s.1 = phi ptr [ %uglygep, %for.body6 ], [ %s.0, %for.cond2.preheader ]
  %d.1 = phi ptr [ %uglygep16, %for.body6 ], [ %d.0, %for.cond2.preheader ]
  %c.0 = phi i8 [ %inc, %for.body6 ], [ 0, %for.cond2.preheader ]
  %exitcond.not = icmp eq i8 %c.0, 13
  br i1 %exitcond.not, label %for.end, label %for.body6

for.body6:                                        ; preds = %for.cond2
  %0 = zext nneg i8 %c.0 to i16
  %uglygep = getelementptr i8, ptr %scevgep, i16 %0
  %1 = load i8, ptr %s.1, align 1, !tbaa !19
  %uglygep16 = getelementptr i8, ptr %scevgep15, i16 %0
  store i8 %1, ptr %d.1, align 1, !tbaa !19
  %inc = add nuw nsw i8 %c.0, 1
  br label %for.cond2, !llvm.loop !90

for.end:                                          ; preds = %for.cond2
  %add.ptr = getelementptr inbounds nuw i8, ptr %d.1, i16 67
  %inc9 = add nuw nsw i8 %r.0, 1
  br label %for.cond, !llvm.loop !91

for.end10:                                        ; preds = %for.cond
  ret void
}

; Function Attrs: minsize nounwind optsize
define internal fastcc void @boot_from_floppy_or_jump_prom1() unnamed_addr #5 {
entry:
  tail call fastcc void @delay(i8 noundef zeroext 2, i8 noundef zeroext -66) #11
  tail call fastcc void @fdc_write_when_ready(i8 noundef zeroext 4) #11
  %0 = load i8, ptr @drive_select, align 1, !tbaa !19
  tail call fastcc void @fdc_write_when_ready(i8 noundef zeroext %0) #11
  %call = tail call fastcc zeroext i8 @fdc_read_when_ready() #11
  store i8 %call, ptr @fdc_result, align 1, !tbaa !21
  %1 = and i8 %call, 35
  tail call fastcc void @fdc_write_when_ready(i8 noundef zeroext 7) #11
  %2 = load i8, ptr @drive_select, align 1, !tbaa !19
  tail call fastcc void @fdc_write_when_ready(i8 noundef zeroext %2) #11
  %conv2 = zext nneg i8 %1 to i16
  %3 = load i8, ptr @drive_select, align 1, !tbaa !19
  %conv3 = zext i8 %3 to i16
  %add = add nuw nsw i16 %conv3, 32
  %cmp.not = icmp eq i16 %add, %conv2
  br i1 %cmp.not, label %lor.lhs.false, label %cleanup

lor.lhs.false:                                    ; preds = %entry
  %call5 = tail call fastcc zeroext i8 @verify_seek_result(i8 noundef zeroext 0) #11
  %cmp7.not = icmp eq i8 %call5, 0
  br i1 %cmp7.not, label %if.end, label %cleanup

if.end:                                           ; preds = %lor.lhs.false
  store i8 0, ptr @fdc_cmd, align 1, !tbaa !92
  store i8 1, ptr getelementptr inbounds nuw (i8, ptr @fdc_cmd, i16 1), align 1, !tbaa !94
  store i8 1, ptr getelementptr inbounds nuw (i8, ptr @fdc_cmd, i16 2), align 1, !tbaa !95
  %call9 = tail call fastcc zeroext i8 @fdc_detect_sector_size_and_density() #11
  %cmp11 = icmp eq i8 %call9, 0
  br i1 %cmp11, label %if.then13, label %if.end14

if.then13:                                        ; preds = %if.end
  store i1 true, ptr @is_double_sided, align 1
  br label %if.end14

if.end14:                                         ; preds = %if.then13, %if.end
  store i8 0, ptr getelementptr inbounds nuw (i8, ptr @fdc_cmd, i16 1), align 1, !tbaa !94
  %call15 = tail call fastcc zeroext i8 @fdc_detect_sector_size_and_density() #11
  %cmp17.not = icmp eq i8 %call15, 0
  br i1 %cmp17.not, label %if.end20, label %cleanup

if.end20:                                         ; preds = %if.end14
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 24, i8 1) #10, !srcloc !96
  br label %while.cond

while.cond:                                       ; preds = %if.end25, %if.end20
  %4 = load i16, ptr @dma_transfer_size, align 1, !tbaa !97
  tail call fastcc void @fdc_read_data_from_current_location(i16 noundef %4) #11
  %5 = load i8, ptr @fdc_cmd, align 1, !tbaa !92
  %cmp22.not = icmp eq i8 %5, 0
  br i1 %cmp22.not, label %if.end25, label %while.end

if.end25:                                         ; preds = %while.cond
  %call26 = tail call fastcc zeroext i8 @fdc_detect_sector_size_and_density() #11
  br label %while.cond

while.end:                                        ; preds = %while.cond
  store i8 1, ptr @disk_type, align 1, !tbaa !19
  tail call fastcc void @boot_floppy_or_prom() #13
  unreachable

cleanup:                                          ; preds = %if.end14, %entry, %lor.lhs.false
  tail call fastcc void @prom1_if_present() #11
  ret void
}

; Function Attrs: minsize nounwind optsize
define internal fastcc zeroext range(i8 0, 3) i8 @verify_seek_result(i8 noundef zeroext %expected_pcn) unnamed_addr #5 {
entry:
  %call = tail call fastcc zeroext i8 @wait_fdc_ready() #11
  %tobool.not = icmp eq i8 %call, 0
  br i1 %tobool.not, label %if.end, label %return

if.end:                                           ; preds = %entry
  %0 = load i8, ptr @drive_select, align 1, !tbaa !19
  %conv = zext i8 %0 to i16
  %add = add nuw nsw i16 %conv, 32
  %1 = load i8, ptr @fdc_result, align 1, !tbaa !21
  %conv1 = zext i8 %1 to i16
  %cmp.not = icmp eq i16 %add, %conv1
  br i1 %cmp.not, label %lor.lhs.false, label %return

lor.lhs.false:                                    ; preds = %if.end
  %2 = load i8, ptr getelementptr inbounds nuw (i8, ptr @fdc_result, i16 1), align 1, !tbaa !23
  %cmp5.not = icmp eq i8 %expected_pcn, %2
  br i1 %cmp5.not, label %if.end8, label %return

if.end8:                                          ; preds = %lor.lhs.false
  br label %return

return:                                           ; preds = %if.end, %lor.lhs.false, %entry, %if.end8
  %retval.0 = phi i8 [ 0, %if.end8 ], [ 1, %entry ], [ 2, %lor.lhs.false ], [ 2, %if.end ]
  ret i8 %retval.0
}

; Function Attrs: minsize nounwind optsize
define internal fastcc void @prom1_if_present() unnamed_addr #5 {
entry:
  %0 = tail call i8 asm sideeffect "in $0, ($1)", "=a,i"(i8 20) #10, !srcloc !98
  %1 = and i8 %0, 2
  %cmp = icmp eq i8 %1, 0
  br i1 %cmp, label %land.lhs.true, label %do.body

land.lhs.true:                                    ; preds = %entry
  %call = tail call fastcc zeroext i8 @compare_6bytes(ptr noundef nonnull inttoptr (i16 8194 to ptr), ptr noundef nonnull @msg_rc702) #11
  %cmp3 = icmp eq i8 %call, 0
  br i1 %cmp3, label %if.then, label %do.body

if.then:                                          ; preds = %land.lhs.true
  %2 = load i16, ptr inttoptr (i16 8192 to ptr), align 8192, !tbaa !97
  %3 = inttoptr i16 %2 to ptr
  tail call void %3() #12
  ret void

do.body:                                          ; preds = %entry, %land.lhs.true
  %call5 = tail call ptr @memcpy(ptr noundef nonnull inttoptr (i16 30928 to ptr), ptr noundef nonnull @.str.1, i16 noundef 30) #12
  tail call fastcc void @halt_forever() #13
  unreachable
}

; Function Attrs: minsize nounwind optsize
define internal fastcc zeroext range(i8 0, 2) i8 @fdc_detect_sector_size_and_density() unnamed_addr #5 {
entry:
  br label %while.body

while.body:                                       ; preds = %if.end7, %entry
  %storemerge = phi i8 [ 0, %entry ], [ 1, %if.end7 ]
  store i8 %storemerge, ptr @is_mfm, align 1, !tbaa !19
  %call = tail call fastcc zeroext i8 @fdc_select_drive_cylinder_head() #11
  %cmp.not = icmp eq i8 %call, 0
  br i1 %cmp.not, label %if.end, label %return

if.end:                                           ; preds = %while.body
  store i16 4, ptr @dma_transfer_size, align 1, !tbaa !97
  %call2 = tail call fastcc zeroext i8 @fdc_get_result_bytes(i8 noundef zeroext 10, i8 noundef zeroext 1) #11
  %cmp4 = icmp eq i8 %call2, 0
  br i1 %cmp4, label %while.end, label %if.end7

if.end7:                                          ; preds = %if.end
  %0 = load i8, ptr @is_mfm, align 1, !tbaa !19
  %tobool.not = icmp eq i8 %0, 0
  br i1 %tobool.not, label %while.body, label %return

while.end:                                        ; preds = %if.end
  %1 = load i8, ptr getelementptr inbounds nuw (i8, ptr @fdc_result, i16 6), align 1, !tbaa !99
  %2 = and i8 %1, 7
  store i8 %2, ptr getelementptr inbounds nuw (i8, ptr @fdc_cmd, i16 3), align 1, !tbaa !100
  tail call fastcc void @lookup_sectors_and_gap3_for_current_track() #11
  tail call fastcc void @calc_size_of_current_track() #11
  br label %return

return:                                           ; preds = %if.end7, %while.body, %while.end
  %retval.0 = phi i8 [ 0, %while.end ], [ 1, %while.body ], [ 1, %if.end7 ]
  ret i8 %retval.0
}

; Function Attrs: minsize nounwind optsize
define internal fastcc void @fdc_read_data_from_current_location(i16 noundef %total_bytes_to_read) unnamed_addr #5 {
entry:
  store i16 %total_bytes_to_read, ptr @bytes_left_to_read, align 1, !tbaa !97
  br label %while.body

while.body:                                       ; preds = %cleanup, %entry
  %call = tail call fastcc zeroext i8 @fdc_select_drive_cylinder_head() #11
  switch i8 %call, label %if.then5 [
    i8 1, label %if.then
    i8 0, label %if.end6
  ]

if.then:                                          ; preds = %while.body
  tail call fastcc void @prom1_if_present() #11
  br label %return

if.then5:                                         ; preds = %while.body
  tail call fastcc void @error_display_halt(i8 noundef zeroext 6) #11
  br label %return

if.end6:                                          ; preds = %while.body
  tail call fastcc void @calc_size_of_current_track() #11
  %0 = load i16, ptr @bytes_left_to_read, align 1, !tbaa !97
  %1 = load i16, ptr @dma_transfer_size, align 1, !tbaa !97
  %sub = sub nsw i16 %0, %1
  %cmp7 = icmp sgt i16 %sub, 0
  br i1 %cmp7, label %if.end10, label %if.else

if.else:                                          ; preds = %if.end6
  store i16 %0, ptr @dma_transfer_size, align 1, !tbaa !97
  br label %if.end10

if.end10:                                         ; preds = %if.end6, %if.else
  %.sink = phi i8 [ 0, %if.else ], [ 1, %if.end6 ]
  %storemerge = phi i16 [ 0, %if.else ], [ %sub, %if.end6 ]
  store i8 %.sink, ptr @more_tracks_to_read, align 1, !tbaa !19
  store i16 %storemerge, ptr @bytes_left_to_read, align 1, !tbaa !97
  %call11 = tail call fastcc zeroext i8 @fdc_get_result_bytes(i8 noundef zeroext 6, i8 noundef zeroext 5) #11
  %cmp13.not = icmp eq i8 %call11, 0
  br i1 %cmp13.not, label %if.end16, label %if.then15

if.then15:                                        ; preds = %if.end10
  tail call fastcc void @error_display_halt(i8 noundef zeroext 40) #11
  br label %return

if.end16:                                         ; preds = %if.end10
  %2 = load i16, ptr @dma_transfer_size, align 1, !tbaa !97
  %3 = load i16, ptr @dma_transfer_address, align 1, !tbaa !97
  %add = add i16 %3, %2
  store i16 %add, ptr @dma_transfer_address, align 1, !tbaa !97
  store i16 0, ptr @dma_transfer_size, align 1, !tbaa !97
  store i8 1, ptr getelementptr inbounds nuw (i8, ptr @fdc_cmd, i16 2), align 1, !tbaa !95
  %.b = load i1, ptr @is_double_sided, align 1
  %4 = load i8, ptr getelementptr inbounds nuw (i8, ptr @fdc_cmd, i16 1), align 1, !tbaa !94
  %5 = zext i1 %.b to i8
  %cmp19 = icmp eq i8 %4, %5
  br i1 %cmp19, label %if.then21, label %if.else22

if.then21:                                        ; preds = %if.end16
  %6 = load i8, ptr @fdc_cmd, align 1, !tbaa !92
  %inc = add i8 %6, 1
  store i8 %inc, ptr @fdc_cmd, align 1, !tbaa !92
  br label %cleanup

if.else22:                                        ; preds = %if.end16
  %inc23 = add i8 %4, 1
  br label %cleanup

cleanup:                                          ; preds = %if.then21, %if.else22
  %inc23.sink = phi i8 [ 0, %if.then21 ], [ %inc23, %if.else22 ]
  store i8 %inc23.sink, ptr getelementptr inbounds nuw (i8, ptr @fdc_cmd, i16 1), align 1, !tbaa !94
  %7 = load i8, ptr @more_tracks_to_read, align 1, !tbaa !19
  %tobool.not.not = icmp eq i8 %7, 0
  br i1 %tobool.not.not, label %return, label %while.body

return:                                           ; preds = %cleanup, %if.then15, %if.then5, %if.then
  ret void
}

; Function Attrs: minsize noreturn nounwind optsize
define internal fastcc void @boot_floppy_or_prom() unnamed_addr #2 {
entry:
  %call = tail call fastcc zeroext i8 @compare_6bytes(ptr noundef nonnull inttoptr (i16 2 to ptr), ptr noundef nonnull @.str.2) #11
  %cmp = icmp eq i8 %call, 0
  br i1 %cmp, label %while.cond, label %if.end25

while.cond:                                       ; preds = %entry, %if.then7
  %storemerge = phi ptr [ %add.ptr, %if.then7 ], [ inttoptr (i16 2944 to ptr), %entry ]
  store ptr %storemerge, ptr @boot_dir, align 1, !tbaa !101
  %cmp2 = icmp samesign ult ptr %storemerge, inttoptr (i16 3328 to ptr)
  br i1 %cmp2, label %while.body, label %do.body

while.body:                                       ; preds = %while.cond
  %0 = load i8, ptr %storemerge, align 1, !tbaa !19
  %cmp5 = icmp eq i8 %0, 0
  br i1 %cmp5, label %if.then7, label %if.end

if.then7:                                         ; preds = %while.body
  %add.ptr = getelementptr inbounds nuw i8, ptr %storemerge, i16 32
  br label %while.cond, !llvm.loop !104

if.end:                                           ; preds = %while.body
  %call8 = tail call fastcc zeroext i8 @check_sysfile(ptr noundef nonnull %storemerge, ptr noundef nonnull @.str.3) #11
  %cmp10 = icmp eq i8 %call8, 0
  br i1 %cmp10, label %if.then12, label %do.body

if.then12:                                        ; preds = %if.end
  %add.ptr13 = getelementptr inbounds nuw i8, ptr %storemerge, i16 32
  store ptr %add.ptr13, ptr @boot_dir, align 1, !tbaa !101
  %1 = load i8, ptr %add.ptr13, align 1, !tbaa !19
  %cmp15.not = icmp eq i8 %1, 0
  br i1 %cmp15.not, label %do.body, label %land.lhs.true

land.lhs.true:                                    ; preds = %if.then12
  %call17 = tail call fastcc zeroext i8 @check_sysfile(ptr noundef nonnull %add.ptr13, ptr noundef nonnull @.str.4) #11
  %cmp19 = icmp eq i8 %call17, 0
  br i1 %cmp19, label %if.then21, label %do.body

if.then21:                                        ; preds = %land.lhs.true
  tail call fastcc void @floppy_legacy_boot() #11
  br label %do.body

do.body:                                          ; preds = %while.cond, %if.then12, %land.lhs.true, %if.then21, %if.end
  %call24 = tail call ptr @memcpy(ptr noundef nonnull inttoptr (i16 30928 to ptr), ptr noundef nonnull @.str.5, i16 noundef 21) #12
  tail call fastcc void @halt_forever() #13
  unreachable

if.end25:                                         ; preds = %entry
  %call26 = tail call fastcc zeroext i8 @compare_6bytes(ptr noundef nonnull inttoptr (i16 8 to ptr), ptr noundef nonnull @msg_rc702) #11
  %cmp28 = icmp eq i8 %call26, 0
  br i1 %cmp28, label %if.then30, label %do.body32

if.then30:                                        ; preds = %if.end25
  %2 = load volatile i16, ptr null, align 32768, !tbaa !97
  %3 = inttoptr i16 %2 to ptr
  tail call void %3() #12
  br label %do.body32

do.body32:                                        ; preds = %if.end25, %if.then30
  %call33 = tail call ptr @memcpy(ptr noundef nonnull inttoptr (i16 30928 to ptr), ptr noundef nonnull @.str.6, i16 noundef 16) #12
  tail call fastcc void @halt_forever() #13
  unreachable
}

; Function Attrs: minsize nounwind optsize
define internal fastcc zeroext range(i8 0, 2) i8 @wait_fdc_ready() unnamed_addr #5 {
entry:
  br label %while.cond

while.cond:                                       ; preds = %while.body, %entry
  %timeout.addr.0 = phi i8 [ -1, %entry ], [ %dec, %while.body ]
  %dec = add i8 %timeout.addr.0, -1
  %tobool.not = icmp eq i8 %dec, 0
  br i1 %tobool.not, label %return, label %while.body

while.body:                                       ; preds = %while.cond
  tail call fastcc void @delay(i8 noundef zeroext 1, i8 noundef zeroext 2) #11
  %0 = load volatile i8, ptr @floppy_operation_completed_flag, align 1, !tbaa !19
  %tobool1.not = icmp eq i8 %0, 0
  br i1 %tobool1.not, label %while.cond, label %if.then, !llvm.loop !105

if.then:                                          ; preds = %while.body
  tail call void asm sideeffect "di", ""() #10, !srcloc !106
  store volatile i8 0, ptr @floppy_operation_completed_flag, align 1, !tbaa !19
  tail call void asm sideeffect "ei", ""() #10, !srcloc !8
  br label %return

return:                                           ; preds = %while.cond, %if.then
  %retval.0 = phi i8 [ 0, %if.then ], [ 1, %while.cond ]
  ret i8 %retval.0
}

; Function Attrs: minsize nofree norecurse nosync nounwind optsize memory(argmem: read)
define internal fastcc zeroext range(i8 0, 2) i8 @compare_6bytes(ptr nofree noundef readonly captures(none) %a, ptr nofree noundef readonly captures(none) %b) unnamed_addr #7 {
entry:
  %scevgep = getelementptr i8, ptr %b, i16 1
  %scevgep4 = getelementptr i8, ptr %a, i16 1
  br label %do.body

do.body:                                          ; preds = %do.cond, %entry
  %z80-indexiv.iv = phi i8 [ %z80-indexiv.iv.next, %do.cond ], [ 0, %entry ]
  %a.addr.0 = phi ptr [ %uglygep5, %do.cond ], [ %a, %entry ]
  %b.addr.0 = phi ptr [ %uglygep, %do.cond ], [ %b, %entry ]
  %i.0 = phi i8 [ %dec, %do.cond ], [ 6, %entry ]
  %0 = load i8, ptr %a.addr.0, align 1, !tbaa !19
  %1 = load i8, ptr %b.addr.0, align 1, !tbaa !19
  %cmp.not = icmp eq i8 %0, %1
  br i1 %cmp.not, label %do.cond, label %cleanup

do.cond:                                          ; preds = %do.body
  %2 = zext nneg i8 %z80-indexiv.iv to i16
  %uglygep = getelementptr i8, ptr %scevgep, i16 %2
  %uglygep5 = getelementptr i8, ptr %scevgep4, i16 %2
  %dec = add nsw i8 %i.0, -1
  %tobool.not = icmp eq i8 %dec, 0
  %z80-indexiv.iv.next = add nuw nsw i8 %z80-indexiv.iv, 1
  br i1 %tobool.not, label %cleanup, label %do.body, !llvm.loop !107

cleanup:                                          ; preds = %do.cond, %do.body
  %retval.0 = phi i8 [ 1, %do.body ], [ 0, %do.cond ]
  ret i8 %retval.0
}

; Function Attrs: minsize nounwind optsize
define internal fastcc zeroext range(i8 0, 3) i8 @fdc_select_drive_cylinder_head() unnamed_addr #5 {
entry:
  %0 = load i8, ptr getelementptr inbounds nuw (i8, ptr @fdc_cmd, i16 1), align 1, !tbaa !94
  %shl = shl i8 %0, 2
  %1 = load i8, ptr @drive_select, align 1, !tbaa !19
  %or = or i8 %shl, %1
  %2 = load i8, ptr @fdc_cmd, align 1, !tbaa !92
  tail call fastcc void @fdc_write_when_ready(i8 noundef zeroext 15) #11
  %3 = and i8 %or, 7
  tail call fastcc void @fdc_write_when_ready(i8 noundef zeroext %3) #11
  tail call fastcc void @fdc_write_when_ready(i8 noundef zeroext %2) #11
  %4 = load i8, ptr @fdc_cmd, align 1, !tbaa !92
  %call = tail call fastcc zeroext i8 @verify_seek_result(i8 noundef zeroext %4) #11
  ret i8 %call
}

; Function Attrs: minsize nounwind optsize
define internal fastcc zeroext range(i8 0, 2) i8 @fdc_get_result_bytes(i8 noundef zeroext range(i8 6, 11) %cmd, i8 noundef zeroext range(i8 1, 6) %retries) unnamed_addr #5 {
entry:
  store i8 %cmd, ptr @saved_fdc_command, align 1, !tbaa !19
  store i8 %retries, ptr @retry_count, align 1, !tbaa !19
  br label %while.cond

while.cond:                                       ; preds = %if.end12, %entry
  tail call void asm sideeffect "di", ""() #10, !srcloc !106
  store volatile i8 0, ptr @floppy_operation_completed_flag, align 1, !tbaa !19
  tail call void asm sideeffect "ei", ""() #10, !srcloc !8
  %0 = load i8, ptr @saved_fdc_command, align 1, !tbaa !19
  %cmp.not = icmp eq i8 %0, 10
  br i1 %cmp.not, label %if.end, label %if.then

if.then:                                          ; preds = %while.cond
  tail call void asm sideeffect "di", ""() #10, !srcloc !106
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -6, i8 5) #10, !srcloc !108
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -5, i8 69) #10, !srcloc !109
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -4, i8 0) #10, !srcloc !110
  %1 = load i16, ptr @dma_transfer_address, align 1, !tbaa !97
  %conv2 = trunc i16 %1 to i8
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -14, i8 %conv2) #10, !srcloc !111
  %shr = lshr i16 %1, 8
  %conv3 = trunc nuw i16 %shr to i8
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -14, i8 %conv3) #10, !srcloc !112
  %2 = load i16, ptr @dma_transfer_size, align 1, !tbaa !97
  %sub = add i16 %2, -1
  %conv6 = trunc i16 %sub to i8
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -13, i8 %conv6) #10, !srcloc !113
  %shr7 = lshr i16 %sub, 8
  %conv8 = trunc nuw i16 %shr7 to i8
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -13, i8 %conv8) #10, !srcloc !114
  tail call void asm sideeffect "out ($0), $1", "i,a"(i8 -6, i8 1) #10, !srcloc !115
  tail call void asm sideeffect "ei", ""() #10, !srcloc !8
  br label %if.end

if.end:                                           ; preds = %if.then, %while.cond
  %3 = load i8, ptr @saved_fdc_command, align 1, !tbaa !19
  tail call fastcc void @fdc_write_full_cmd(i8 noundef zeroext %3) #11
  %call = tail call fastcc zeroext i8 @wait_fdc_ready() #11
  %tobool.not = icmp eq i8 %call, 0
  br i1 %tobool.not, label %if.end12, label %cleanup

if.end12:                                         ; preds = %if.end
  %call13 = tail call fastcc zeroext i8 @check_fdc_result() #11
  switch i8 %call13, label %while.cond [
    i8 0, label %cleanup.loopexit
    i8 2, label %cleanup
  ]

cleanup.loopexit:                                 ; preds = %if.end12
  br label %cleanup

cleanup:                                          ; preds = %if.end, %if.end12, %cleanup.loopexit
  %retval.0 = phi i8 [ %call13, %cleanup.loopexit ], [ 1, %if.end12 ], [ 1, %if.end ]
  ret i8 %retval.0
}

; Function Attrs: minsize mustprogress nofree norecurse nosync nounwind optsize willreturn memory(readwrite, argmem: none, inaccessiblemem: none, target_mem: none)
define internal fastcc void @lookup_sectors_and_gap3_for_current_track() unnamed_addr #8 {
entry:
  %0 = load i8, ptr @is_mini, align 1, !tbaa !19
  %idxprom = zext i8 %0 to i16
  %arrayidx = getelementptr inbounds nuw [16 x i8], ptr @eot_gap3_table, i16 %idxprom
  %1 = load i8, ptr getelementptr inbounds nuw (i8, ptr @fdc_cmd, i16 3), align 1, !tbaa !100
  %idxprom1 = zext i8 %1 to i16
  %arrayidx2 = getelementptr inbounds nuw [4 x i8], ptr %arrayidx, i16 %idxprom1
  %2 = load i8, ptr @is_mfm, align 1, !tbaa !19
  %idxprom3 = zext i8 %2 to i16
  %arrayidx4 = getelementptr inbounds nuw [2 x i8], ptr %arrayidx2, i16 %idxprom3
  %3 = load i8, ptr %arrayidx4, align 1, !tbaa !116
  store i8 %3, ptr getelementptr inbounds nuw (i8, ptr @fdc_cmd, i16 4), align 1, !tbaa !118
  %gap3 = getelementptr inbounds nuw i8, ptr %arrayidx4, i16 1
  %4 = load i8, ptr %gap3, align 1, !tbaa !119
  store i8 %4, ptr getelementptr inbounds nuw (i8, ptr @fdc_cmd, i16 5), align 1, !tbaa !120
  store i8 -128, ptr getelementptr inbounds nuw (i8, ptr @fdc_cmd, i16 6), align 1, !tbaa !121
  ret void
}

; Function Attrs: minsize nofree norecurse nosync nounwind optsize memory(readwrite, argmem: none, inaccessiblemem: none, target_mem: none)
define internal fastcc void @calc_size_of_current_track() unnamed_addr #9 {
entry:
  %0 = load i8, ptr @disk_type, align 1, !tbaa !19
  %tobool.not = icmp sgt i8 %0, -1
  br i1 %tobool.not, label %cond.false, label %land.lhs.true

land.lhs.true:                                    ; preds = %entry
  %1 = load i8, ptr getelementptr inbounds nuw (i8, ptr @fdc_cmd, i16 1), align 1, !tbaa !94
  %cmp = icmp eq i8 %1, 1
  br i1 %cmp, label %cond.end, label %cond.false

cond.false:                                       ; preds = %land.lhs.true, %entry
  %2 = load i8, ptr getelementptr inbounds nuw (i8, ptr @fdc_cmd, i16 4), align 1, !tbaa !118
  %3 = load i8, ptr getelementptr inbounds nuw (i8, ptr @fdc_cmd, i16 2), align 1, !tbaa !95
  %sub = add i8 %2, 1
  %add = sub i8 %sub, %3
  %4 = zext i8 %add to i16
  br label %cond.end

cond.end:                                         ; preds = %land.lhs.true, %cond.false
  %cond = phi i16 [ %4, %cond.false ], [ 10, %land.lhs.true ]
  %5 = load i8, ptr getelementptr inbounds nuw (i8, ptr @fdc_cmd, i16 3), align 1, !tbaa !100
  %add8 = add i8 %5, 7
  br label %for.cond

for.cond:                                         ; preds = %for.body, %cond.end
  %tb.0 = phi i16 [ %cond, %cond.end ], [ %shl, %for.body ]
  %i.0 = phi i8 [ %add8, %cond.end ], [ %dec, %for.body ]
  %cmp11.not = icmp eq i8 %i.0, 0
  br i1 %cmp11.not, label %for.cond.cleanup, label %for.body

for.cond.cleanup:                                 ; preds = %for.cond
  store i16 %tb.0, ptr @dma_transfer_size, align 1, !tbaa !97
  ret void

for.body:                                         ; preds = %for.cond
  %shl = shl i16 %tb.0, 1
  %dec = add i8 %i.0, -1
  br label %for.cond, !llvm.loop !122
}

; Function Attrs: minsize nounwind optsize
define internal fastcc void @fdc_write_full_cmd(i8 noundef zeroext range(i8 0, 11) %cmd) unnamed_addr #5 {
entry:
  %0 = load i8, ptr @is_mfm, align 1, !tbaa !19
  %tobool.not = icmp eq i8 %0, 0
  %conv1 = select i1 %tobool.not, i8 0, i8 64
  %1 = load i8, ptr getelementptr inbounds nuw (i8, ptr @fdc_cmd, i16 1), align 1, !tbaa !94
  %shl = shl i8 %1, 2
  %2 = load i8, ptr @drive_select, align 1, !tbaa !19
  %or = or i8 %shl, %2
  tail call void asm sideeffect "di", ""() #10, !srcloc !106
  %add = or disjoint i8 %conv1, %cmd
  tail call fastcc void @fdc_write_when_ready(i8 noundef zeroext %add) #11
  tail call fastcc void @fdc_write_when_ready(i8 noundef zeroext %or) #11
  %cmp = icmp eq i8 %cmd, 6
  br i1 %cmp, label %for.cond, label %if.end

for.cond:                                         ; preds = %entry, %for.body
  %z80-indexiv.iv = phi i8 [ %5, %for.body ], [ 0, %entry ]
  %.not = icmp eq i8 %z80-indexiv.iv, 7
  br i1 %.not, label %if.end, label %for.body

for.body:                                         ; preds = %for.cond
  %3 = zext i8 %z80-indexiv.iv to i16
  %uglygep = getelementptr i8, ptr @fdc_cmd, i16 %3
  %4 = load i8, ptr %uglygep, align 1, !tbaa !19
  tail call fastcc void @fdc_write_when_ready(i8 noundef zeroext %4) #11
  %5 = add i8 %z80-indexiv.iv, 1
  br label %for.cond, !llvm.loop !123

if.end:                                           ; preds = %for.cond, %entry
  tail call void asm sideeffect "ei", ""() #10, !srcloc !8
  ret void
}

; Function Attrs: minsize mustprogress nofree norecurse nosync nounwind optsize willreturn memory(readwrite, argmem: none, inaccessiblemem: none, target_mem: none)
define internal fastcc zeroext range(i8 0, 3) i8 @check_fdc_result() unnamed_addr #8 {
entry:
  %0 = load i8, ptr @fdc_result, align 1, !tbaa !21
  %1 = and i8 %0, -61
  %2 = load i8, ptr @drive_select, align 1, !tbaa !19
  %cmp = icmp eq i8 %1, %2
  br i1 %cmp, label %land.lhs.true, label %if.else

land.lhs.true:                                    ; preds = %entry
  %3 = load i8, ptr getelementptr inbounds nuw (i8, ptr @fdc_result, i16 1), align 1, !tbaa !23
  %cmp4 = icmp eq i8 %3, 0
  br i1 %cmp4, label %land.lhs.true6, label %if.else

land.lhs.true6:                                   ; preds = %land.lhs.true
  %4 = load i8, ptr getelementptr inbounds nuw (i8, ptr @fdc_result, i16 2), align 1, !tbaa !124
  %5 = and i8 %4, -65
  %cmp9 = icmp eq i8 %5, 0
  br i1 %cmp9, label %return, label %if.else

if.else:                                          ; preds = %land.lhs.true6, %land.lhs.true, %entry
  %6 = load i8, ptr @retry_count, align 1, !tbaa !19
  %dec = add i8 %6, -1
  store i8 %dec, ptr @retry_count, align 1, !tbaa !19
  %cmp12 = icmp eq i8 %dec, 0
  %conv14 = select i1 %cmp12, i8 2, i8 1
  br label %return

return:                                           ; preds = %land.lhs.true6, %if.else
  %retval.0 = phi i8 [ %conv14, %if.else ], [ 0, %land.lhs.true6 ]
  ret i8 %retval.0
}

; Function Attrs: minsize nofree norecurse nosync nounwind optsize memory(argmem: read)
define internal fastcc zeroext range(i8 0, 2) i8 @check_sysfile(ptr nofree noundef readonly captures(none) %dir, ptr nofree noundef readonly captures(none) %pattern) unnamed_addr #7 {
entry:
  %scevgep14 = getelementptr nuw i8, ptr %dir, i16 1
  %scevgep15 = getelementptr i8, ptr %pattern, i16 1
  br label %do.body

do.body:                                          ; preds = %do.cond, %entry
  %z80-indexiv.iv = phi i8 [ %z80-indexiv.iv.next, %do.cond ], [ 0, %entry ]
  %pattern.addr.0 = phi ptr [ %uglygep16, %do.cond ], [ %pattern, %entry ]
  %i.0 = phi i8 [ %dec, %do.cond ], [ 4, %entry ]
  %0 = zext nneg i8 %z80-indexiv.iv to i16
  %uglygep = getelementptr i8, ptr %scevgep14, i16 %0
  %1 = load i8, ptr %uglygep, align 1, !tbaa !19
  %conv = zext i8 %1 to i16
  %2 = load i8, ptr %pattern.addr.0, align 1, !tbaa !19
  %conv3 = sext i8 %2 to i16
  %cmp.not = icmp eq i16 %conv, %conv3
  br i1 %cmp.not, label %do.cond, label %cleanup

do.cond:                                          ; preds = %do.body
  %uglygep16 = getelementptr i8, ptr %scevgep15, i16 %0
  %dec = add nsw i8 %i.0, -1
  %tobool.not = icmp eq i8 %dec, 0
  %z80-indexiv.iv.next = add nuw nsw i8 %z80-indexiv.iv, 1
  br i1 %tobool.not, label %do.end, label %do.body, !llvm.loop !125

do.end:                                           ; preds = %do.cond
  %arrayidx = getelementptr i8, ptr %dir, i16 8
  %3 = load i8, ptr %arrayidx, align 1, !tbaa !19
  %4 = and i8 %3, 63
  %cmp6.not = icmp ne i8 %4, 19
  %. = zext i1 %cmp6.not to i8
  br label %cleanup

cleanup:                                          ; preds = %do.body, %do.end
  %retval.0 = phi i8 [ %., %do.end ], [ 1, %do.body ]
  ret i8 %retval.0
}

; Function Attrs: minsize nounwind optsize
define internal fastcc void @floppy_legacy_boot() unnamed_addr #5 {
entry:
  %0 = load i8, ptr @is_mini, align 1, !tbaa !19
  %shl = shl i8 %0, 7
  %1 = load i8, ptr @disk_type, align 1, !tbaa !19
  %or = or i8 %shl, %1
  %dec = add i8 %or, -1
  store i8 %dec, ptr @disk_type, align 1, !tbaa !19
  %call = tail call fastcc zeroext i8 @fdc_detect_sector_size_and_density() #11
  store i16 0, ptr @dma_transfer_address, align 1, !tbaa !97
  tail call fastcc void @fdc_read_data_from_current_location(i16 noundef 24576) #11
  store i8 1, ptr @disk_type, align 1, !tbaa !19
  tail call void inttoptr (i16 4096 to ptr)() #12
  ret void
}

attributes #0 = { minsize nounwind optsize "frame-pointer"="all" "interrupt" "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-features"="+static-frame,-recurse" }
attributes #1 = { alwaysinline minsize nounwind optsize "frame-pointer"="all" "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-features"="+static-frame" }
attributes #2 = { minsize noreturn nounwind optsize "frame-pointer"="all" "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-features"="+static-frame,-recurse" }
attributes #3 = { minsize nounwind optsize "frame-pointer"="all" "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-features"="+static-frame" }
attributes #4 = { minsize optsize "frame-pointer"="all" "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-features"="+static-frame" }
attributes #5 = { minsize nounwind optsize "frame-pointer"="all" "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-features"="+static-frame,-recurse" }
attributes #6 = { minsize nofree norecurse nosync nounwind optsize memory(write, inaccessiblemem: none, target_mem: none) "frame-pointer"="all" "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-features"="+static-frame" }
attributes #7 = { minsize nofree norecurse nosync nounwind optsize memory(argmem: read) "frame-pointer"="all" "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-features"="+static-frame,-recurse" }
attributes #8 = { minsize mustprogress nofree norecurse nosync nounwind optsize willreturn memory(readwrite, argmem: none, inaccessiblemem: none, target_mem: none) "frame-pointer"="all" "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-features"="+static-frame,-recurse" }
attributes #9 = { minsize nofree norecurse nosync nounwind optsize memory(readwrite, argmem: none, inaccessiblemem: none, target_mem: none) "frame-pointer"="all" "no-builtins" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-features"="+static-frame,-recurse" }
attributes #10 = { nounwind }
attributes #11 = { minsize nobuiltin optsize "no-builtins" }
attributes #12 = { minsize nobuiltin nounwind optsize "no-builtins" }
attributes #13 = { minsize nobuiltin noreturn optsize "no-builtins" }

!llvm.module.flags = !{!0, !1}
!llvm.ident = !{!2}
!llvm.errno.tbaa = !{!3}

!0 = !{i32 1, !"wchar_size", i32 2}
!1 = !{i32 7, !"frame-pointer", i32 2}
!2 = !{!"clang version 24.0.0git (git@github.com:ravn/llvm-z80.git 8e3f50b65d039fcf523ad9742953a46160ebeddb)"}
!3 = !{!4, !5, i64 0}
!4 = !{!"__libc_errno", !5, i64 0}
!5 = !{!"int", !6, i64 0}
!6 = !{!"omnipotent char", !7, i64 0}
!7 = !{!"Simple C/C++ TBAA"}
!8 = !{i64 113789}
!9 = !{i64 2147619454}
!10 = !{i64 2147619578}
!11 = !{i64 2147619701}
!12 = !{i64 2147619905}
!13 = !{i64 2147620006}
!14 = !{i64 2147620224}
!15 = !{i64 2147620323}
!16 = !{i64 2147620454}
!17 = !{i64 2147620573}
!18 = !{i64 2147620691}
!19 = !{!6, !6, i64 0}
!20 = !{i64 2147620956}
!21 = !{!22, !6, i64 0}
!22 = !{!"", !6, i64 0, !6, i64 1, !6, i64 2, !6, i64 3, !6, i64 4, !6, i64 5, !6, i64 6, !6, i64 7}
!23 = !{!22, !6, i64 1}
!24 = !{i64 114019}
!25 = !{i64 79160}
!26 = !{i64 2147598539}
!27 = !{i64 2147598669}
!28 = !{i64 2147598799}
!29 = !{i64 2147598929}
!30 = !{i64 2147599059}
!31 = !{i64 2147599189}
!32 = !{i64 2147599351}
!33 = !{i64 2147599469}
!34 = !{i64 2147599587}
!35 = !{i64 2147599705}
!36 = !{i64 2147599823}
!37 = !{i64 2147599941}
!38 = !{i64 2147600059}
!39 = !{i64 2147600177}
!40 = !{i64 2147600295}
!41 = !{i64 2147600456}
!42 = !{i64 2147600581}
!43 = !{i64 2147600705}
!44 = !{i64 2147600828}
!45 = !{i64 2147600991}
!46 = !{i64 2147601117}
!47 = !{i64 2147601245}
!48 = !{i64 2147601373}
!49 = !{i64 2147601501}
!50 = !{i64 2147601627}
!51 = !{i64 2147601753}
!52 = !{i64 2147601881}
!53 = !{i64 2147602007}
!54 = !{i64 2147617870}
!55 = distinct !{!55, !56}
!56 = !{!"llvm.loop.mustprogress"}
!57 = !{i64 2147618041}
!58 = !{i64 2147618157}
!59 = !{i64 2147610645}
!60 = !{i64 2147610741}
!61 = !{i64 2147610836}
!62 = distinct !{!62, !56}
!63 = distinct !{!63, !56}
!64 = !{i64 2147612305}
!65 = !{i64 2147612428}
!66 = !{i64 2147612632}
!67 = !{i64 2147612733}
!68 = !{i64 2147612951}
!69 = !{i64 2147613050}
!70 = !{i64 2147613181}
!71 = !{i64 2147613303}
!72 = !{i64 2147613648}
!73 = distinct !{!73, !56}
!74 = !{i64 2147613785}
!75 = !{i64 2147598203}
!76 = !{i64 2147598341}
!77 = distinct !{!77, !56}
!78 = !{i64 2147616354}
!79 = !{i64 2147615995}
!80 = !{i64 2147616122}
!81 = !{i64 2147597901}
!82 = !{i64 2147598022}
!83 = distinct !{!83, !56}
!84 = !{i64 4128}
!85 = distinct !{!85, !56}
!86 = distinct !{!86, !56}
!87 = distinct !{!87, !56}
!88 = !{i64 2147611075}
!89 = distinct !{!89, !56}
!90 = distinct !{!90, !56}
!91 = distinct !{!91, !56}
!92 = !{!93, !6, i64 0}
!93 = !{!"", !6, i64 0, !6, i64 1, !6, i64 2, !6, i64 3, !6, i64 4, !6, i64 5, !6, i64 6}
!94 = !{!93, !6, i64 1}
!95 = !{!93, !6, i64 2}
!96 = !{i64 2147618827}
!97 = !{!5, !5, i64 0}
!98 = !{i64 2147617029}
!99 = !{!22, !6, i64 6}
!100 = !{!93, !6, i64 3}
!101 = !{!102, !102, i64 0}
!102 = !{!"p1 omnipotent char", !103, i64 0}
!103 = !{!"any pointer", !6, i64 0}
!104 = distinct !{!104, !56}
!105 = distinct !{!105, !56}
!106 = !{i64 113718}
!107 = distinct !{!107, !56}
!108 = !{i64 2147614750}
!109 = !{i64 2147614880}
!110 = !{i64 2147614999}
!111 = !{i64 2147615210}
!112 = !{i64 2147615311}
!113 = !{i64 2147615539}
!114 = !{i64 2147615638}
!115 = !{i64 2147615769}
!116 = !{!117, !6, i64 0}
!117 = !{!"", !6, i64 0, !6, i64 1}
!118 = !{!93, !6, i64 4}
!119 = !{!117, !6, i64 1}
!120 = !{!93, !6, i64 5}
!121 = !{!93, !6, i64 6}
!122 = distinct !{!122, !56}
!123 = distinct !{!123, !56}
!124 = !{!22, !6, i64 2}
!125 = distinct !{!125, !56}
