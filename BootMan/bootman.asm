; BootMan - Bootloader of arduMan
; Official site: <https://github.com/AlexGuo1998/BootMan>

.nolist
.include <m32u4def.inc>
.include "arduman.inc"
.list

.equ BL_START = 0x3800
.equ VECTOR_START = 0x3810

#define sdcmd(x) ((x) | 0x40)

.org BL_START
	jmp bl

.org VECTOR_START
;TODO re-arrange vector, re-define address
entry_flash_file:
	jmp flash_file
entry_flash_page:
	jmp flash_page
entry_sdinit:
	jmp sdinit

;normal boot sequence
bl:
	clr r1
	;TODO init register, init stack, etc...
	;check button, flash "LOADER  BIN" automatically(?)
	;or game select menu(?)

	;TODO fill "LOADER  BIN"
	rcall flash_file
start_app:
	jmp 0

; flash a binary file
; uint8_t flash_file(char *filename);
; r25:r24 = filename pointer(paddled SFN, ex: "FOLDER1    NEWGAME BIN\0")
;     r24 = (output)errnumber (when OK, there's no return)
flash_file:
	;don't do test for illegal filename(or length), to save code
	;beacuse illegal filename fill fail when going through dirs
	push r25
	push r24
	rcall sdinit

	ret



; init SD card
; uint8_t sdinit(void)
; r24            = (output) cardmode (0=SD1, 1=SD2, 2=SDHC/SDXC(block index), 0xFF=failed)
; r18~r23 r26~27 = (used)
; T(flag)        = (used) 0=SD1, 1=SD2/SDHC/SDXC
; assert: r1 = 0
sdinit:
	ser r24;assume ret = 0xFF
	clt;assume sdver = SD1(t=0)
	;0.init SPI, set MISO to pullup
	;set ss to OUTPUT
	sbi SS_DDR, SS_BIT
	;set MISO to pullup
	sbi PORTB, PORTB3
	;deselect screen
	sbi SCRCS_PORT, SCRCS_BIT
	sbi SCRCS_DDR, SCRCS_BIT
	;deselect SD card
	sbi SDCS_PORT, SDCS_BIT
	sbi SDCS_DDR, SDCS_BIT
	;enable SPI, set master
	ldi r18, (1<<SPE) | (1<<MSTR)
	out SPCR, r18
	;enable 2x
	ldi r18, (1<<SPI2X)
	out SPSR, r18

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
	;if ret != 0x01 then failed
	cpi r19, 0x01
	brne sdinit_end

	;3.issue CMD8(+CRC), to get SD version
	ldi r18, sdcmd(8)
	ldi r20, 0xAA
	ldi r21, 0x01
	rcall sd_cmd
	;if ret = 0b1xxxxxxx then failed
	sbrs r19, 7
	rjmp sdinit_end;TODO ret?
	;if ret = 0b0xxxx1xx then sdver1
	sbrs r19, 2
	set;else SD2, T=true

	;4.issue CMD55+41, init(timeout 1s)
	movw r21:r20, r23:r22;arg(1,2)=0
	;movw r27:r26, r23:r22;delay counter = 0
	ldi r27, 0b1100_0000;TODO: 16129+ cycles(4s)
acmd41_loop:
	rcall send_256_dummy_bytes ;drop cmd8 remaining bytes, also delay
	ldi r18, sdcmd(55)
	clr r23
	rcall sd_cmd
	ldi r18, sdcmd(41)
	bld r23, 6;if SD2(T=1), arg = 0x4000_0000, else arg = 0
	rcall sd_cmd
	;test counter overflow
	adiw r27:r26, 1
	breq sdinit_end;65536 = fail
	sbrc r19, 1;if ret = 0x00(card ready) then exit loop
	rjmp acmd41_loop;loop

	;5.if SDV2, issue CMD58, to know if card is HCS(use sector for addressing)
	brtc cmd16;sdv1 -> skip
	ldi r18, sdcmd(58)
	rcall sd_cmd
	rcall spi_trans
	;if ret = 0b1xxxxxxx then failed
	sbrs r19, 7
	rjmp sdinit_end;TODO ret?
	inc r24;r24=0
	;now r19.6 = 1 -> block index
	sbrc r19, 6
	inc r24;r24=0/1
	rcall send_256_dummy_bytes;drop unused bytes

	;6.issue CMD16 with	0x200, set block size to 512
cmd16:
	inc r24;r24=0/1/2
	ldi r18, sdcmd(16);cmd = 0x16
	ldi r21, 0x02;arg=0x200
	rcall sd_cmd
	
sdinit_end:
	ret


; bool sd_readsect(uint8_t *buffer, uint32_t sect_index, uint16_t start_byte, uint16_t count, uint8_t block_address)
; r25:r24         = pointer to buffer(moved to ZH:ZL)
;     r24         = (output) OK ? 1 : 0
; r23:r22:r21:r20 = sector
; r19:r18         = start byte(moved to r27:r26)
; r17:r16         = byte count
; r14             = use_block_addr ? 1 : 0 (not use -> addr must * 512)
sd_readsect:
	movw ZH:ZL, r25:r24
	movw r27:r26, r19:r18
	sbrs r14, 0;if use_blk_addr then * 512
	jmp sd_readsect_send;else skip
	clc
	rol r20
	rol r21
	rol r22
	mov r23, r22
	mov r22, r21
	mov r21, r20
	clr r20
sd_readsect_send:
	ldi r18, sdcmd(17);CMD17
	rcall sd_cmd;arg = address
	cpi r19, 0;r19 = 0?
	breq sd_readsect_cmd_ok;0 = OK
	;else return 0
ret_0:
	clr r24
	ret
sd_readsect_cmd_ok:
	rcall spi_trans
	inc r1
	breq ret_0;r1 = 0(256), fail(timeout)
	sbrc r19, 0;if bit0 = 0 then OK
	rjmp sd_readsect_cmd_ok
	;OK
	clr r1;reset r1
	sbrs r19, 7;if bit7 = 1 then OK
	rjmp ret_0;else fail

	;calc remaining byte, save to r25:r24
	ldi r25, 0x02
	ldi r24, 0x02;0x0202(512+2), for dropping 2B CRC
	sub r24, r26
	sbc r25, r27;substract start byte
	sub r24, r16
	sbc r25, r17;substract byte count

	;now get data
	;drop (start_byte) data
sd_readsect_drop_1:
	rcall spi_trans
	sbiw r27:r26, 1
	brne sd_readsect_drop_1
	;fill to buffer
	movw r27:r26, r17:r16
sd_readsect_receive:
	rcall spi_trans
	st Z+, r19
	sbiw r27:r26, 1
	brne sd_readsect_receive
	;drop remaining data
sd_readsect_drop_2:
	rcall spi_trans
	sbiw r25:r24, 1
	brne sd_readsect_drop_2
	;done, ret 1
	rjmp ret_1

; assert r18 = 0xFF
; assert r1 = 0
send_256_dummy_bytes:
	rcall spi_trans
	inc r1
	brne send_256_dummy_bytes;eq(zero) = overflow
	ret

; r18             : cmd(must use sdcmd(x)!)
;                   (used) return 0xFF
; r19             : (output)return value(can be 0xFF for failed)
; r23:r22:r21:r20 : arg
; r24             : (used) crc
; assert: r1 = 0
sd_cmd:
	;load CRC
	ldi r24, 0x95;assume cmd = 0
	sbrc r18, 4;skip if cmd = 0
	subi r24, (0x95-0x87);for cmd = 8, arg = 0x000001AA
	rcall spi_trans;cmd
	mov r18, r23
	rcall spi_trans;arg3
	mov r18, r22
	rcall spi_trans;arg2
	mov r18, r21
	rcall spi_trans;arg1
	mov r18, r20
	rcall spi_trans;arg0
	mov r18, r24
	rcall spi_trans;crc
	ser r18;0xFF
sd_cmd_wait:
	rcall spi_trans
	inc r1
	breq sd_cmd_fail;r1 = 0(256), fail(timeout)
	sbrc r19, 7;if bit7 = 0 then OK
	rjmp sd_cmd_wait
	;OK
	clr r1;reset r1
sd_cmd_fail:
	ret

; transfer a byte
; r18 : data
; r19 : (output) data_out
spi_trans:
	out SPDR, r18
spi_trans_wait:
	in r19, SPSR
	sbrs r19, SPIF
	rjmp spi_trans_wait
	in r19, SPDR
	ret

; flash a page(64 words/128 bytes) from RAM
; bool flash_page(const uint8_t data[128], uint16_t addr)
; r18     : (used) sreg
; r19     : (used) 0(?)
; r23:r22 : address (low 7 bits are ignored)
; r25:r24 : data pointer
; r25     : (used) 0
;     r24 : (output) OK?1:0
; ZH:ZL   : (used) address
flash_page:
	;preserve BL section (addr >= BL_START -> ret false)
	cpi r23, HIGH(BL_START)
	brlo check_ok;if HIGH(addr) < HIGH(bootloader) then OK
	;else: return false
	rjmp ret_0
check_ok:
.def temp = r18
	;save SREG and disable interrupt
	in temp, SREG
	cli
	push temp
	;save r0 (r1 is always 0)
	push r0
	;wait for eeprom write
wait_eeprom:
	sbic EECR, EEPE
	rjmp wait_eeprom
	;erase page
	movw ZH:ZL, r23:r22
	ldi temp, (1<<SPMEN) | (1<<PGERS)
	rcall do_spm
	;mov data pointer to Z
	movw ZH:ZL, r25:r24
	;r25=128, for store loop
	ldi r25, 128
	;load page buffer
	ldi temp, (1<<SPMEN)
load_buffer:
	ld r0, Z+
	ld r1, Z+
	rcall do_spm
	inc r25
	brne load_buffer;if r25 != 0(256) (ne) then loop
	;else: all data (128b) loaded to buffer
	;write page
	movw ZH:ZL, r23:r22
	ldi temp, (1<<SPMEN) | (1<<PGWRT)
	rcall do_spm
	;re-enable access to RWW section
	ldi temp, (1<<SPMEN) | (1<<RWWSRE)
	rcall do_spm

	;done, restore
	pop r0
	clr r1
	pop temp
	out SREG, temp
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
