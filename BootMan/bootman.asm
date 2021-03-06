; BootMan - Bootloader of arduMan
; Official site: <https://github.com/AlexGuo1998/BootMan>

.nolist
.include <m32u4def.inc>
.include "arduman.inc"
.list

.equ BL_START = FOURTHBOOTSTART
.equ VECTOR_START = FOURTHBOOTSTART + 0x10

#define sdcmd(x)                 ((x) | 0x40)
#define FSINFO_SIZE              18
#define GETFSINFO_WORKING_AREA   35
#define FINDFILE_WORKING_AREA    32

.org BL_START
	jmp bl

.org VECTOR_START
;TODO re-arrange vector, re-define address
entry_flashfile:
	jmp flashfile
entry_flashpage:
	jmp flashpage
entry_sdinit:
	jmp sdinit
entry_sdreadsect:
	jmp sdreadsect
entry_getfsinfo:
	jmp getfsinfo
entry_findfile:
	jmp findfile

;normal boot sequence
bl:
	clr r1
	out SREG, r1
	ldi YH, HIGH(RAMEND)
	ldi YL, LOW(RAMEND)
	out SPH, YH
	out SPL, YL
	;TODO stop WDT?
	;TODO check button, flash "LOADER  BIN" automatically(?)
	;or game select menu(?)

	;TODO fill "LOADER  BIN"
	;rcall flashfile
start_app:
jmp_0:
	jmp 0


; flash a binary file
; uint8_t flashfile(char *filename);
; r25:r24 = (i)filename pointer(paddled SFN, ex: "FOLDER1    NEWGAME BIN\0")
;     r24 = (o)errnumber (when OK, there's no return)
; TODO: more regs used...
flashfile:
	in r0, SREG
	cli
	push r0

	;don't do test for illegal filename(or length), to save code
	;beacuse illegal filename will fail when going through dirs
	push r25
	push r24
	rcall sdinit
	sbrc r24, 7;r24 < 0x80 = OK
	rjmp flashfile_error_1;else ret r24
	lsr r24
	;push r24 + preserve opertion area
	ldi r20, FSINFO_SIZE + 1
flashfile_push:
	in r23, SPH
	in r22, SPL
	push r24
	dec r20
	brne flashfile_push
	;STACK:
	;filename H:L
	;FSINFO_1(19)
	;  |-useblock?
	;  |-FSINFO(18)
	;STACK_TOP
	;now, r23:r22 = FSINFO = stack_top + 1
	rcall getfsinfo
	sbrc r24, 0;r24 = 0 = OK
	rjmp flashfile_error_2;else err, ret r24
	;findfile
	in ZH, SPH
	in ZL, SPL
	adiw ZH:ZL, 1;Z -> FSINFO_1
	ldd r24, Z+18+1
	ldd r25, Z+18+1+1;r25:r24 -> filename
	movw r23:r22, ZH:ZL;FSINFO_1
	rcall findfile
	;check fileaddr(r21::r18), if fileaddr = 0, err happened
	cp r18, r1
	cpc r19, r1
	cpc r20, r1
	cpc r21, r1
	breq flashfile_error_2;file_addr = 0
	;check filelen(r25::r22), if filelen = 0, hit on a dir or empty file
	;filelen = min(filelen, BL_START * 2)
	adiw r25:r24, 0
	brne flashfile_gt; Filelen > maxfilelen
	cp r22, r1
	cpc r23, r1
	breq flashfile_error_2;file_len = 0
	;else: high 2 bytes are 0, if file_len[1] >= HIGH(BL_START * 2), then file > max
	cpi r23, HIGH(BL_START * 2)
	brlo flashfile_lt
flashfile_gt:
	;set file size to max
	;don't care r25:r24
	ldi r23, HIGH(BL_START * 2)
	clr r22
flashfile_lt:
	;all check passed
	;because there's no way back, all regs are free to use
	;readfile and flash
	in YH, SPH
	in YL, SPL
	adiw YH:YL, 1;Y -> FSINFO_1
	rcall load_r14r9r8
	movw r7:r6, YH:YL
	;raise stack 128B
	ldi r20, 128
flashfile_push_2:
	push r24
	dec r20
	brne flashfile_push_2
	movw r13:r12, r21:r20
	movw r11:r10, r19:r18
	movw r7:r6, r23:r22;file size
	clr r5
	clr r4;TODO
	movw r19:r18, r5:r4
	clr r15;byte offset, 1<<n
	inc r15;r15 = 1
flashfile_loop_reload:
	clr r17
	ldi r16, 128;byte count
	;r23::r20 : sector id(can use for temp)
	;r19:r18  : byte offset(re-loaded each time, can use for temp)
	;r17:r16  : byte count(128)
	;r15      : byte offset
	;r14      : .0=use_blk_addr .4=FAT32
	;r13::r10 : sector id(backup)
	;r9       : SectPerClus - 1(bit mask)
	;r8       : cluster bondary
	;r7:r6    : file size
	;r5:r4    : now page

	;flash now
flashfile_loop:
	in ZH, SPH
	in ZL, SPL
	adiw ZH:ZL, 1;Z -> buffer
	movw r19:r18, r5:r4
	andi r19, 0x01;r19:18 = page addr
	movw r23:r22, r13:r12
	movw r21:r20, r11:r10;file sector
	rcall sdreadsect_use_Z
	;now Z -> buffer[128]
	sub ZL, r16;= 128
	sbc ZH, r1
	movw XH:XL, ZH:ZL
	movw ZH:ZL, r5:r4
	rcall flashpage_use_XZ_as_pointer
	;now X -> buffer[128] (= FSINFO)
	add r4, r16
	adc r5, r1;r5:r4 + 128
	cp r4, r6
	cpc r5, r7
	brsh flashfile_end;r5:r4 >= r7:r6 then end
	lsl r15
	brhc flashfile_loop;if not half-carry, loop
	;else get next sect
	swap r15;r15 = 1
	movw YH:YL, XH:XL
	rcall getnextsect
	sbrs r24, 0;if ret != 0 then skip(go end)
	;else ret = 0, loop
	rjmp flashfile_loop_reload
flashfile_end:
	;jmp 0
	rjmp jmp_0

flashfile_error_2:
	ldi r25, FSINFO_SIZE + 1
flashfile_pop:
	pop r0
	dec r25
	brne flashfile_pop
flashfile_error_1:
	pop r0;FN LOW
	pop r0;FN HIGH
	pop r0;SREG
	out SREG, r0
	ret


; uint8_t getfsinfo(uint8_t use_block_index, FSINFO *info)
; r24     : (i)use_block_index? 1 : 0
;           (o)OK? 0 : 1
; ZH:ZL
; XH:XL
; r25
; r21::r18
; r23:r22 : (i)FSINFO addr
; r1 : (i)0
; ****************************************
; FSINFO(18B)
; 0  uint32_t FATPos(when FAT starts?)
; 4  uint32_t EntryPos
; 8  uint32_t rootdirend(when root dir ends? only in FAT16)
; 12 uint32_t Clus0Pos(when cluster #0(imagine) starts?)
; 16 uint8_t SecPerClus
; 17 uint8_t FAT_type, FAT32 = 1(also in flags, T)
getfsinfo:
	;save regs
	push YH
	push YL
	push r17
	push r16
	push r14
	;push r15;in following instructions
	mov r14, r24;now r14 = use_block_index ? 1 : 0
	movw YH:YL, r23:r22
	;push stack
	ldi r22, GETFSINFO_WORKING_AREA + 1
getfsinfo_push:
	in ZH, SPH
	in ZL, SPL
	push r15
	dec r22
	brne getfsinfo_push
	;now, Z -> stack_top + 1
	;r22 = 0

	;0. read sect0[0], to test if it's raw FAT
	clr r23
	;clr r22;already 0
	movw r21:r20, r23:r22;sector addr = 0
	movw r19:r18, r21:r20;start byte = 0
	clr r17
	ldi r16, 1;byte_count = 1
	rcall sdreadsect_use_Z
	sbrc r24, 0;if r24 = 0 then OK
	rjmp getfsinfo_err;else err
	ld r18, -Z
	andi r18, 0b11111101;for 0xEB/0xE9 test
	cpi r18, 0b11101001
	breq getfsinfo_raw_fat;if EQ, it's raw FAT

	;1. read MBR, find sect_start
	;start_sector = BOOTSECTOR[457::454]
	;Z = &buffer[0]
	ldi r18, LOW(454)
	ldi r19, HIGH(454);start_byte = 454
	;r17 should be 0
	ldi r16, 4;byte_count = 4
	rcall sdreadsect_use_Z;Z = &buffer[4]
	sbrc r24, 0;if r24 = 0 then OK
	rjmp getfsinfo_err;else err
	;1st partition sector to r23::r20
	ld r23, -Z
	ld r22, -Z
	ld r21, -Z
	ld r20, -Z

	;2. read BOOTSECTOR, get FAT type(FAT per sector 32/16), cluster size, cluster bondary,
	;   FAT location, cluster 0 location, root dir pos, (FAT16) root dir size(?).
getfsinfo_raw_fat:
	rcall st_Y_r20
	;movw r25:r24, ZH:ZL
	clr r19
	ldi r18, 13
	;r17 should be 0
	ldi r16, 35
	rcall sdreadsect_use_Z
	;r22::r20 is INVALID
	sbrc r24, 0;if r24 = 0 then OK
	rjmp getfsinfo_err;else err
	;now decode BOOTSECTOR
	;Z pointer 35(+1) bytes away from stack_top
	;reset Z
	sbiw ZH:ZL, 35
	;Z = &BS[13]

	;test FAT16/32
	;T = 1 -> FAT32
	set;assume FAT32
	ldd r15, Z+4;root_ent_count[0]
	cp r15, r1;r1=0
	ldd r15, Z+5;root_ent_count[1]
	cpse r15, r1;if root_ent_cnt = r1 (= 0) then skip
	clt;else, root_ent_count != 0, FAT16, T = 0
	;try to load FATSZ32, if FAT16, fatsz(r23::r20) will be overwrittern later
	;r23::r20 = FATSZ32
	ldd r20, Z+36-13
	ldd r21, Z+36-13+1
	ldd r22, Z+36-13+2
	ldd r23, Z+36-13+3

	;SecPerClus
	ld r15, Z;r15 = sect_per_clus
	;fat loc (= base + RsvdSecCnt)
	movw XH:XL, YH:YL;X is &struct[0](now contain start sector)
	movw YH:YL, ZH:ZL
	adiw YH:YL, 1;Y is 1(+1)B off stack_top
	;*(Y) += *(X)
	clc
	rcall add_XY_2
	;Y is 3(+1)B off, X is 2B off struct
	;save X back to Y
	movw YH:YL, XH:XL

	;EntryLoc (= fatloc + fatSZAll, for FAT16)
	brts getfsinfo_ldfatsz_end;if fat32, fatsz already loaded
	;else overwrite fatsz(r23::r21)
	ldd r20, Z+22-13
	ldd r21, Z+22-13+1
	movw r23:r22, r25:r24;(=0)
getfsinfo_ldfatsz_end:

	;calc FatSZAll = fatsz * numfats
	ldd r18, Z+16-13
	ldi XL, 20
	clr XH
	;X -> r20
	rcall mul_X_4;(r25(carry) = 0)
	;***IMPORTANT*** for wrong cards, r1 can be other than 0
	;r24 MUST equ 0 (for card size < 1TB)
	;proof: if r24 = 1(total size = 0x01000000), for numfats = 2(typical), fatsize = 0x00800000
	;for FAT32, fatcount = fatsize/4 = 0x00200000
	;for minimum cluster size(512B, 1sect), min fs size = fatcount * 512 = 0x40000000 = 1TiB

	sbiw YH:YL, 2;YH:YL = FSINFO(0)
	rcall add_r20_Y;r23::r20 += fatloc
	rcall st_Y_r20;r23::r20 -> Y(FSINFO + 4)

	;RootSirSz = (rootdircnt + 15) >> 4
	ldd r20, Z+17-13
	ldd r21, Z+17-13+1
	;add 15 to r21:r20
	subi r20, -15
	brcs getfsinfo_rootdir_c
	;if not carry then +15 will carry
	inc r21
getfsinfo_rootdir_c:
	;r21:r20 >> 4
	swap r21
	swap r20
	mov r22, r21
	andi r22, 0xF0
	andi r21, 0x0F
	andi r20, 0x0F
	or r20, r22
	movw r23:r22, r25:r24;must be 0(refer to proof above)

	;RootDirEndLoc = EntryLoc + RootDirSz
	rcall add_r20_Y
	rcall st_Y_r20

	;calc 2 * SectPerClus
	mov r20, r15
	lsl r20
	;r20 MUST not overflow
	;proof: cluster size must <= 32KB (64 sects), * 2 <= 128
	;should there be OVF, undim following line
	ser r21
	;sbci r21, 0
	ser r22
	ser r23
	neg r20
	;cls0sec = RootDirEndLoc - (2 * SecPerClus)
	rcall add_r20_Y
	rcall st_Y_r20

	std Y+4, r15;SecPerClus
	bld r1, 0;r1 = 0 | T
	std Y+5, r1;Fat32? 1 : 0
	;adjust entry for FAT32
	brtc getfsinfo_done
	ldd r20, Z+44-13
	ldd r21, Z+44-13+1
	ldd r22, Z+44-13+2
	ldd r23, Z+44-13+3
	mov r18, r15;SectPerClus
	ldi XL, 20
	;XH = 0, for add_r20_Y
	rcall mul_X_4;r25=0
	ldi XL, 20
	;now Y -> cls0sec
	rcall add_XY_4
	sbiw Y, 12;now Y -> entryPos
	rcall st_Y_r20

getfsinfo_done:
	clr r24;r24=0,OK
getfsinfo_err:
	;reset stack
	ldi r16, GETFSINFO_WORKING_AREA + 1
getfsinfo_pop:
	pop r15
	dec r16
	brne getfsinfo_pop
	;at last, r15 = real r15
	pop r14
	pop r16
	pop r17
	pop YL
	pop YH
	clr r1
	ret


.def temp1 = r0
.def temp2 = r25
add_r20_Y:
	ldi XL, 20
	clr XH
; *Y = *Y + *X (4B)
add_XY_4:
	clc
	rcall add_XY_2
add_XY_2:
	rcall add_XY_1;4x loop
add_XY_1:
	ld temp1, X
	ld temp2, Y+
	adc temp1, temp2
	st X+, temp1
	ret
.undef temp1
.undef temp2


st_Y_r20:
	std Y+0, r20
	std Y+1, r21
	std Y+2, r22
	std Y+3, r23
	ret

; YH:YL : (i)FSINFO_EX pointer
; r14   : (o)FAT32, use_block_addr
; r9    : SectPerClus - 1
; r8    : ClusBondary
load_r14r9r8:
	;r14(0) = use_block_addr ? 1 : 0 (?)
	;r14(4) = FAT32 ? 1 : 0 (?)
	ldd r14, Y+17; = FAT_type
	swap r14
	ldd r0, Y+18; = use_block_addr
	or r14, r0
	;load r9(SectPerClus - 1), r8(ClusBondary)
	ldd r9, Y+16
	dec r9
	ldd r8, Y+12;Clus0Pos low
	and r8, r9;mask high bits
	ret

; FSINFO_1(19) : FSINFO(18) + use_block_index(1)
; FILEINFO findfile(char *filename, FSINFO_1 *info)
; r25:r24 : (i)filename pointer
; r23:r22 : (i)FSINFO addr
; TODO more regs used...
; XL      : (o)FileAttr
; ****************************************
; FILEINFO(8B)
;   fileaddr(4B)(sector Index)r21::r18
;   filelen(4B)(bytes)r25::r22
findfile:
	;Y        : filename ptr
	;Z        : buffer ptr
	;r23::r20 : sector id(can use for temp)
	;r19:r18  : byte offset(re-loaded each time, can use for temp)
	;r17:r16  : byte count(32)
	;r15      : which item in sector?(0~15)
	;r14      : .0=use_blk_addr .4=FAT32
	;r13::r10 : sector id(backup)
	;r9       : SectPerClus - 1(bit mask)
	;r8       : cluster bondary
	push YH
	push YL
	;FSINFO_1 ptr push to stack
	push r23
	push r22
	;push r17::r4, and preserve working area
	clr YH
	ldi YL, 18
findfile_push:
	ld r0, -Y
	in ZH, SPH
	in ZL, SPL
	;finally Z = stack_top + 1(working area)
	push r0
	cpi YL, 4-FINDFILE_WORKING_AREA;also preserve working area
	brne findfile_push
	;stack arrangement:
	;saved YH:YL
	;FSINFO_1 pointer(2B)
	;saved r17::r4
	;working area(32B)
	movw YH:YL, r23:r22;Y -> FSINFO_1
	rcall load_r14r9r8
	;T = !(FAT16 && rootdir)
	bst r14, 4
	;infomation we should keep: now sector(r13::r10)? which item in dir(r15)?
	;r23::r20 = nowsect, for bootstrap, = entrypos
	;sector id backup in r13::r10
	ldd r10, Y+4
	ldd r11, Y+5
	ldd r12, Y+6
	ldd r13, Y+7
	movw YH:YL, r25:r24;Y -> filename
	;r17:r16 = 32(0x20)(read 32 bytes)
	clr r17;TODO reload r17?
findfile_reloadcount:
	ldi r16, 32
findfile_newsect:
	;16 entry per sector, held in r15(0..3)
	clr r15
findfile_readentry:
	;r19:r18 = r15 << 5(r15 * 32)
	clr r19
	mov r18, r15
	swap r18
	lsl r18
	rol r19
	;copy sector id back
	movw r23:r22, r13:r12
	movw r21:r20, r11:r10
	;read file entry
	rcall sdreadsect_use_Z
	sbrc r24, 0;if r24 = 0 then OK
	rjmp findfile_err;else err
	;now Z = &dir[32]
	sbiw ZH:ZL, 32-11
	;now Z = &dir[11]
	;compare YZ
	rcall comp_YZ_11_add_Y
	brne findfile_nextfile;if not EQ, find next
	;else found
	;check file_attr
	ldd r19, Z+11;r19 = attr
	sbrc r19, 3;if attr & 0x08(is volume lbl) = 0 then skip
	rjmp findfile_nextfile;else skip
	ldd r18, Y+11;filename[11]
	cpi r18, 0
	breq findfile_found;filename done, OK
	sbrs r19, 4;if this is a dir then skip(OK)
	rjmp findfile_nextfile;else: want to find a dir, but hit on a file, failed
	;TODO or jmp err?
findfile_found:
	adiw YH:YL, 11;Y += 11
	set;not rootdir
	;load new cluster id
	ldd r20, Z+26
	ldd r21, Z+26+1
	ldd r22, Z+20
	ldd r23, Z+20+1
	;save Y
	movw r7:r6, YH:YL
	ldd YL, Z+32+14
	ldd YH, Z+32+14+1
	;Y -> FSINFO_1
	adiw YH:YL, 4
	;translate to sector
	rcall cls_to_sect
	;restore Y
	movw YH:YL, r7:r6
	;clr r15;go from first item
	;(already done)
	ld r18, Y;filename[11]
	cpi r18, 0
	brne findfile_newsect;filename not done then loop
	rjmp findfile_done;done, jmp
findfile_nextfile:
	inc r15
	sbrs r15, 4;half ovf
	rjmp findfile_readentry;not overflow, go nextentry
	;else find next sector
	;save Y
	movw r7:r6, YH:YL
	;save Z
	movw r5:r4, ZH:ZL
	;load Y <- FSINFO_1
	ldd YL, Z+32+14
	ldd YH, Z+32+14+1
	rcall getnextsect
	sbrc r24, 0;r24.0 != 0 then error
	rjmp findfile_err
	;else
	;restore Y
	movw YH:YL, r7:r6
	;restore Z
	movw ZH:ZL, r5:r4
	rjmp findfile_reloadcount

findfile_err:
	clr r13
	clr r12
	movw r11:r10, r13:r12;all 0
findfile_done:
	movw r21:r20, r13:r12
	movw r19:r18, r11:r10
	ldd r22, Z+28+0
	ldd r23, Z+28+1
	ldd r24, Z+28+2
	ldd r25, Z+28+3;file length
	ldd XL, Z+11;TODO file attr needed?
findfile_pop:
	ldi ZH, FINDFILE_WORKING_AREA
findfile_pop_1:
	pop r0
	dec ZH
	brne findfile_pop_1
	;ZH already 0
	ldi ZL, 4
findfile_pop_2:
	pop r0
	st Z+, r0
	cpi ZL, 18
	brne findfile_pop_2
	pop r0
	pop r0
	pop YL
	pop YH
	ret


; lsr r23::r20 for log2(r1 + 1) bits
; (r23::r20 >> 1, r1 >> 1 while r1 != 0)
loop_lsr_r20_r1:
	lsr r23
	ror r22
	ror r21
	ror r20
	lsr r1
	brne loop_lsr_r20_r1;if r1 != 0 then loop
	ret


; lsl r23::r20
; (r23::r20 << 1)
lsl_r20:
	lsl r20
	rol r21
	rol r22
	rol r23
	ret


;compare Y[n] Z[n]
; Y   : (i)pointer + n
;       (o)pointer 
; Z   : (i)pointer + n
;       (o)pointer
; r19 : (o)Z[0]
; r18 : (o)Y[0]
comp_YZ_11_add_Y:
	;for fullname match
	adiw YH:YL, 11
comp_YZ_11_dec:
	cp r0, r0;clear C, set Z
	rcall comp_YZ_1_dec
comp_YZ_10_dec:
	rcall comp_YZ_5_dec
comp_YZ_5_dec:
	;for shorten filename compare
	rcall comp_YZ_1_dec
comp_YZ_4_dec:
	;for sect = rootdirend compare
	rcall comp_YZ_1_dec
comp_YZ_3_dec:
	;for file ext match
	rcall comp_YZ_1_dec
comp_YZ_2_dec:
	rcall comp_YZ_1_dec
comp_YZ_1_dec:
	ld r18, -Y
	ld r19, -Z
	cpc r18, r19
	ret


.def temp = r24
.def carry = r25
; *X = *X * r18, r25 = carry
; r0, r1, r24 used
; ***warning*** after calling, r1 can be other than 0!
mul_X_4:
	rcall mul_X_2
mul_X_2:
	rcall mul_X_1
mul_X_1:
	ld r24, X
	mul r18, temp
	add r0, carry
	movw carry:temp, r1:r0
	st X+, temp
	ret
.undef temp
.undef carry

; void spiinit(void)
; r1  : (i)0
; r18 : (o)(1<<SPE) | (1<<MSTR) = 0b0101_0000
spiinit:
	;set ss to OUTPUT
	sbi SS_DDR, SS_BIT
	;set MISO to pullup
	sbi PORTB, PORTB3

	;set CLK to output
	sbi DDRB, PORTB1
	;set MOSI to output
	sbi DDRB, PORTB2

	;deselect screen
	sbi SCRCS_PORT, SCRCS_BIT
	sbi SCRCS_DDR, SCRCS_BIT
	;deselect SD card
	sbi SDCS_PORT, SDCS_BIT
	sbi SDCS_DDR, SDCS_BIT
	;enable SPI, set master
	ldi r18, (1<<SPE) | (1<<MSTR)
	out SPCR, r18
	;TODO enable 2x?
	;ldi r18, (1<<SPI2X)
	out SPSR, r1
	ret

; r25     : (o)(random junk)
; r23:r22 : (o)0
; r21:r20 : (o)0
; r19     : (o)possbly 0x01 for normal card, 0xFF for no card
; r18     : (o)0xFF
; r1      : (i)0
sd_gospimode:
	;1.set cs high, then apply 74+(10B+) dummy clocks
	ser r18
	rcall send_256_dummy_bytes
	;2.set cs low, issue CMD0(+CRC)
	;CS = LOW
	cbi SDCS_PORT, SDCS_BIT
	;CMD0, arg=0
	ldi r18, sdcmd(0)
	clr r20
	clr r21
	movw r23:r22, r21:r20
	rcall sd_cmd
	ret


; init SD card
; uint8_t sdinit(void)
; XH:XL   : (o)(counter random junk)
; r25     : (o)(random junk)
; r24     : (o)cardmode (0=SD1, 1=SD2, 2=SDHC/SDXC(block index), 0xFF=failed)
; r23:r22 : (o)0
; r21:r20 : (o)0x0200
; r19     : (o)(possibly 0x00)
; r18     : (o)0xFF
; r1      : (i)0
; T(flag) : (o)0=SD1, 1=SD2/SDHC/SDXC
sdinit:
	;0.init SPI, set MISO to pullup
	rcall spiinit
	;TODO
sdinit_nospi:
	rcall sd_gospimode
	ser r24;assume ret = 0xFF

	;if ret != 0x01 then failed
	cpi r19, 0x01
	brne sdinit_end

	;3.issue CMD8(+CRC), to get SD version
	ldi r18, sdcmd(8)
	ldi r20, 0xAA
	ldi r21, 0x01
	rcall sd_cmd
	;if ret = 0b1xxxxxxx then failed
	sbrc r19, 7
	rjmp sdinit_end;TODO direct ret?
	;if ret = 0b0xxxx1xx then sdver1
	com r19;1's complement
	;if ret = 0b1xxxx0xx then sdver1
	bst r19, 2;0 = SD1

	;4.issue CMD55+41, init(timeout 1s)
	movw r21:r20, r23:r22;arg(1,2)=0
	ldi XH, 16;1048576+ Bytes @4MHz(3s+)
acmd41_loop:
	rcall send_256_dummy_bytes ;drop cmd8 remaining bytes, also delay
	ldi r18, sdcmd(55)
	clr r23
	rcall sd_cmd
	ldi r18, sdcmd(41)
	bld r23, 6;if SD2(T=1), arg = 0x4000_0000, else arg = 0
	rcall sd_cmd
	;test counter overflow
	sbiw XH:XL, 1
	breq sdinit_end;0 = fail
	sbrc r19, 0;if ret = 0x00(card ready) then exit loop
	rjmp acmd41_loop;loop

	;5.if SDV2, issue CMD58, to know if card is HCS(use sector for addressing)
	brtc cmd16;sdv1 -> skip
	ldi r18, sdcmd(58)
	rcall sd_cmd
	;if ret = 0b1xxxxxxx then failed
	sbrc r19, 7
	rjmp sdinit_end;TODO direct ret?
	inc r24;r24=0
	rcall spi_trans
	;now r19.6 = 1 -> block index
	sbrc r19, 6
	inc r24;r24=0/1
	rcall send_256_dummy_bytes;drop unused bytes

	;6.issue CMD16 with	0x200, set block size to 512
cmd16:
	inc r24;r24=0/1/2
	ldi r18, sdcmd(16);cmd = 0x16
	clr r23
	ldi r21, 0x02;arg=0x200
	rcall sd_cmd

sdinit_end:
	ret


; r18 : (i)0xFF
; r1  : (i)0
send_256_dummy_bytes:
	rcall spi_trans
	inc r1
	brne send_256_dummy_bytes;eq(zero) = overflow
	ret


; r25             : (o)(random junk)
; r23:r22:r21:r20 : (i)arg
; r19             : (o)return value(can be 0xFF for failed)
; r18             : (i)cmd(must use sdcmd(x)!)
;                   (o)0xFF
sd_cmd:
	;load CRC
	ldi r25, 0x95;assume cmd = 0
	sbrc r18, 3;skip if cmd = 0
	subi r25, (0x95-0x87);for cmd = 8, arg = 0x000001AA
	rcall spi_trans;cmd
	mov r18, r23
	rcall spi_trans;arg3
	mov r18, r22
	rcall spi_trans;arg2
	mov r18, r21
	rcall spi_trans;arg1
	mov r18, r20
	rcall spi_trans;arg0
	mov r18, r25
	rcall spi_trans;crc
	ser r18;0xFF
sd_cmd_wait:
	rcall spi_trans
	dec r25
	breq sd_cmd_fail;r25 = 0(135+ clks), fail(timeout)
	sbrc r19, 7;if bit7 = 0 then OK
	rjmp sd_cmd_wait
	;OK
sd_cmd_fail:
	ret


; transfer a byte
; r19 : (o)data_out
; r18 : (i)data
spi_trans:
	out SPDR, r18
spi_trans_wait:
	in r19, SPSR
	sbrs r19, SPIF
	rjmp spi_trans_wait
	in r19, SPDR
	ret


; uint8_t sdreadsect(uint8_t *buffer, uint32_t sect_index, uint16_t start_byte, uint16_t count, uint8_t block_address)
; ZH:ZL           : (o)pointer to buffer(final)
; XH:XL           : (o)0 if OK, else UNDEF
; r25:r24         : (i)pointer to buffer(moved to ZH:ZL)
; r25             : (o)0 if OK, else UNDEF
;     r24         : (o)OK ? 0 : 1
; r23:r22:r21:r20 : (i)sector
;                   (o)sector or byte address
; r19:r18         : (i)start byte(later moved to XH:XL)
; r19             : (o)out crc(last byte)
;     r18         : (o)0xFF
; r17:r16         : (i)byte count
; r14             : (i)use_block_addr ? xxxxxxx1 : xxxxxxx0 (not use -> addr must * 512)
sdreadsect:
	movw ZH:ZL, r25:r24
sdreadsect_use_Z:
	movw XH:XL, r19:r18
	sbrc r14, 0;if !use_blk_addr then * 512
	rjmp sdreadsect_send;else skip
	clc
	rol r20
	rol r21
	rol r22
	mov r23, r22
	mov r22, r21
	mov r21, r20
	clr r20
sdreadsect_send:
	ldi r18, sdcmd(17);CMD17
	rcall sd_cmd;arg = address
	cpse r19, r1;if r19(ret) = r1 (= 0) then skip
	rjmp ret_1;else ret 1
	;max ~100ms timeout
	ldi r25, 128
sdreadsect_cmd_loop:
	rcall spi_trans
	sbiw r25:r24, 1
	breq ret_1_1;if r25:r24 = 0, fail(timeout)
	sbrc r19, 0;if bit0 = 0 then OK
	rjmp sdreadsect_cmd_loop
	;OK
	sbrs r19, 7;if bit7 = 1 then OK
ret_1_1:
	rjmp ret_1;else fail

	;calc remaining byte, save to r25:r24
	ldi r25, 0x02
	ldi r24, 0x02;0x0202(512+2), for dropping 2B CRC
	sub r24, XL
	sbc r25, XH;substract start byte
	sub r24, r16
	sbc r25, r17;substract byte count

	;now get data
	;drop (start_byte) data
	adiw XH:XL, 0;add 0 to test
	breq sdreadsect_drop_1_skip;if 0 then skip
sdreadsect_drop_1:
	rcall spi_trans
	sbiw XH:XL, 1
	brne sdreadsect_drop_1
sdreadsect_drop_1_skip:
	;fill to buffer
	movw XH:XL, r17:r16
	adiw XH:XL, 0;add 0 to test
	breq sdreadsect_receive_skip;if 0 then skip
sdreadsect_receive:
	rcall spi_trans
	st Z+, r19
	sbiw XH:XL, 1
	brne sdreadsect_receive
sdreadsect_receive_skip:
	;drop remaining data
	adiw r25:r24, 0;add 0 to test
	breq sdreadsect_drop_2_skip;if 0 then skip
sdreadsect_drop_2:
	rcall spi_trans
	sbiw r25:r24, 1
	brne sdreadsect_drop_2
sdreadsect_drop_2_skip:
	;done, ret 0
ret_0:
	clr r24
	ret


getnextsect_isroot:
	adiw YH:YL, 8+4;Y -> RootDirEnd+4
	clr ZH
	ldi ZL, 10+4;Z -> r(10+4)
	cp r0, r0;clear C, set Z
	rcall comp_YZ_4_dec
	breq ret_1_1
	rjmp ret_0

; ZH:ZL    : (o)24 for noroot
;               or 10 for rootdir
; YH:YL    : (i)pointer to FSINFO
;            (o)pointer to FSINFO + 16 for noroot
;                       or FSINFO + 8 for rootdir
;                       or garbage if error
; r24      : (o)OK? 0 : 1
; r23::r20 : (o)nextsect
; r19:r18  : (o)used
; r14      : (i).4 = FAT32? .0 = UseBlkIndex?
; r13::r10 : (i)thissect
;            (o)nextsect
; r9       : (i)SectPerClus - 1(bitmask)
; r8       : (i)cluster bondary
; T(flag)  : (i)FAT16 && root ? 0 : 1
getnextsect_noroot:
	;for real files, not root dir
	;will overwrite T
	;TODO is this needed?
	set
getnextsect:
	;inc thissect
	sec
	adc r10, r1
	adc r11, r1
	adc r12, r1
	adc r13, r1
	brtc getnextsect_isroot;if T = 0 then test for rootdir
	mov r0, r10;this sector low
	and r0, r9;mask
	cp r0, r8;compare with bondary
	brne ret_0;if not eq then go next sector
	;else look up in FAT
	;ClusterID = (sectid - clus0pos) / SectPerClus(use looped lsr)
	;SectOffset = (ClusterID << (FAT32 ? 2 : 1)) % 512
	;FATSect = FATSect0 + (ClusterID / (FAT32 ? 128 : 256))
	;load clus0pos
	ldd r20, Y+12
	ldd r21, Y+12+1
	ldd r22, Y+12+2
	ldd r23, Y+12+3
	;0-clus0pos-1 (= 0xFFFFFFFF - xxx)
	com r20
	com r21
	com r22
	com r23
	;add sectid(r13::r10)
	;don't use add_r20_Y, because overhead to save and restore Y is more than direct adding
	add r20, r10
	adc r21, r11
	adc r22, r12
	adc r23, r13
	;now r23::r20 = (ClusterID + 1) * SectPerClus
	mov r1, r9;sectperclus - 1
	;looped lsr
	sbrc r1, 0;if r1.0 = 0, then assume r1 = 0
	;TODO can be dangerous on bad FS?
	rcall loop_lsr_r20_r1
	;now r23::r20 = ClusterID
	;calc SectOffset
	rcall lsl_r20
	sbrc r14, 4;if FAT16(r14.4 = 0) then skip
	rcall lsl_r20;else lsl
	movw r19:r18, r21:r20;byte offset
	andi r19, 0x01;% 512
	;r1 = 0
	dec r1;r1 = 0xFF
	rcall loop_lsr_r20_r1;lsr 8 times
	inc r1;r1 = 0x01
	rcall loop_lsr_r20_r1;lsr 1 time
	;add FATPos
	rcall add_r20_Y
	;Y is 4B off
	ldi r16, 4;assume FAT32, read 4 bytes
	;no problem if we read 2B out bondary: we'll get useless CRC
	;it's safe to do this:
	clr ZH
	ldi ZL, 20;Z -> r20
	;read FAT
	rcall sdreadsect_use_Z
	sbrc r24, 0;if r24 = 0 then OK
	ret;ret r24
	andi r23, 0x0F;mask unused bits
	sbrs r16, 4;if FAT32 then skip
	movw r23:r22, r25:r24;else(FAT16), clear 2 junk bytes
	;test EOC(End of Chain)
	cpi r20, 0xF8
	cpc r21, r18;r18 = 0xFF
	sbrc r16, 4;FAT16 then skip
	cpc r22, r18
	ldi r18, 0x0F
	sbrc r16, 4
	cpc r23, r18
	brsh ret_1;r23::r20 >= 0x0FFFFFF8 or 0xFFF8
	;now r23::r20 = next ClusID
cls_to_sect:
	;next sector = Clus0Sect + ClusID * SectPerClus
	mov r1, r9
	;lsl
	sbrc r1, 0;if r1.0 = 0, then assume r1 = 0
getnextsect_lsl_loop:
	rcall lsl_r20
	lsr r1
	brne getnextsect_lsl_loop
	;add clus0sect
	adiw YH:YL, 8;Y -> Clus0Sect
	rcall add_r20_Y
	;done!
	movw r13:r12, r23:r22
	movw r11:r10, r21:r20
	ret


; flash a page(64 words/128 bytes) from RAM
; bool flashpage(const uint8_t data[128], uint16_t addr)
; ZH:ZL   : (o)page address
; XH:XL   : (o)data pointer + 128
; r25:r24 : (i)data pointer
; r25     : (o)sreg
;     r24 : (o)OK?1:0
; r23:r22 : (i)address (low 7 bits are ignored)
; r19     : (o)0(?)
; r18     : (o)(1<<SPMEN) | (1<<RWWSRE) (0b00010001)
; r1      : (o)0(always 0)
; r0      : (o)last low_byte(junk)
flashpage:
	;preserve BL section (addr >= BL_START -> ret false)
	cpi r23, HIGH(BL_START)
	brlo flashpage_checkok;if HIGH(addr) < HIGH(bootloader) then OK
	;else: return false
	rjmp ret_0
flashpage_checkok:
.def temp = r18
	;mov data pointer to X
	movw XH:XL, r25:r24
	movw ZH:ZL, r23:r22
flashpage_use_XZ_as_pointer:
	;save SREG
	in r25, SREG
	;save high bit of ZL
	bst ZL, 7
	;Z = 10000000, for writing buffer
	ldi ZL, 0x80
	;disable interrupt
	cli
	;wait for eeprom write
flashpage_wait_eeprom:
	sbic EECR, EEPE
	rjmp flashpage_wait_eeprom
	;load page buffer
	ldi temp, (1<<SPMEN)
flashpage_fill_buffer:
	ld r0, X+
	ld r1, X+
	rcall do_spm
	subi ZL, -2;ZL += 2
	brne flashpage_fill_buffer;if ZL != 0 then loop
	;else: all data (128b) loaded to buffer
	;reset high bit of ZL
	bld ZL, 7
	;erase page
	ldi temp, (1<<SPMEN) | (1<<PGERS)
	rcall do_spm
	;write page
	ldi temp, (1<<SPMEN) | (1<<PGWRT)
	rcall do_spm
	;re-enable access to RWW section
	ldi temp, (1<<SPMEN) | (1<<RWWSRE)
	rcall do_spm
	;done, restore
	clr r1
	out SREG, r25
	;return 1(true)
ret_1:
	ldi r24, 1
	ret


do_spm:
.def spmchk = r19
	; wait for last spm operation
	in spmchk, SPMCSR
	sbrc spmchk, SPMEN
	rjmp do_spm
	out SPMCSR, temp
	spm
	ret
.undef spmchk
.undef temp
