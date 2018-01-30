;
; zxps2adapter.asm
;
; Created: 19.12.2016 22:07:23
; Author : LZ
;
;
; 2017.01.10 -- v.0.1
;
; 2017.02.07 -- v.0.2
;               RESET functionality has been added
;
; 2018.01.25 -- v.1.1
;               CPLD support
;

.cseg
.org		0x0000
			rjmp start

;--------------------------------------------------------------
; interrupt vector table
;--------------------------------------------------------------
;;.org		INT0addr
;;			rjmp INT0_Intr

.org		OC1Aaddr
			rjmp TIMER1_Intr

.org		PCI1addr
			rjmp PCI1_Intr

;;.org		PCI2addr
;;			rjmp PCI2_Intr

.org		SPMRaddr+2

; Constants and definition

.def scan_timeout	= r11 ; scan timeout
.def scan_clock		= r12 ; scan clock
.def scan_bits		= r13 ; scan data bits accumulator
.def scan_code		= r14 ; scan code
.def scan_count		= r18 ; scan counter
.def temp			= r16 ; temporary data register
.def temp0			= r17 ; temporary data register

.def param			= r20
.def scan_state		= r22 ; scan code state
.def sc_temp		= r23 ; temp
.def top_hi			= r24 ; table top, high
.def top_lo			= r25 ; table top, low

.macro DBG_PIN_INIT
    sbi		DDRC, PORTC3
.endmacro
.macro DBG_PIN_SET
	sbi		PORTC, PORTC3
.endmacro
.macro DBG_PIN_CLR
	cbi		PORTC, PORTC3
.endmacro

.macro RESET_PIN_INIT
    sbi		DDRC, PORTC2
.endmacro
.macro RESET_PIN_SET
	sbi		PORTC, PORTC2
.endmacro
.macro RESET_PIN_CLR
	cbi		PORTC, PORTC2
.endmacro

.equ FLAG_ADDR_LOW = 0		; one of address line is low
.equ TABLE_ROW_SIZE = 4		; <PS/2 Scan Code> <ZX KD0..KD4> <ZX KD0..KD4>
.equ SCAN_STATE_IDLE = 0
.equ SCAN_STATE_E0 = 1
.equ SCAN_STATE_F0 = 2

; keyboard key numbers
.equ K_CS   = 0
.equ K_A    = 1
.equ K_Q    = 2
.equ K_1    = 3
.equ K_0    = 4
.equ K_P    = 5
.equ K_ENT  = 6
.equ K_SP   = 7
.equ K_Z    = 8 
.equ K_S    = 9 
.equ K_W    = 10
.equ K_2    = 11
.equ K_9    = 12
.equ K_O    = 13
.equ K_L    = 14
.equ K_SS   = 15
.equ K_X    = 16
.equ K_D    = 17
.equ K_E    = 18
.equ K_3    = 19
.equ K_8    = 20
.equ K_I    = 21
.equ K_K    = 22
.equ K_M    = 23
.equ K_C    = 24
.equ K_F    = 25
.equ K_R    = 26
.equ K_4    = 27
.equ K_7    = 28
.equ K_U    = 29
.equ K_J    = 30
.equ K_N    = 31
.equ K_V    = 32
.equ K_G    = 33
.equ K_T    = 34
.equ K_5    = 35
.equ K_6    = 36
.equ K_Y    = 37
.equ K_H    = 38
.equ K_B    = 39

; no key
.equ K_MGC  = 40    ; magic key
.equ K_RST  = 41    ; CPU reset
.equ K_NONE = 63    ; no key

;--------------------------------------------------------------
; Strat program
;--------------------------------------------------------------

start:

	; Variables initialization
	clr		scan_clock
	clr		scan_bits
	clr		scan_code
	clr		scan_count
	clr		scan_timeout
	ldi		scan_state, SCAN_STATE_IDLE

	; Port setup
	DBG_PIN_INIT

	RESET_PIN_INIT
	RESET_PIN_CLR

    cbi		DDRC, PORTC0	; pin for input as PS/2 CLOCK
    cbi		DDRC, PORTC1	; pin for input as PS/2 DATA
	sbi		PORTC, PORTC0	; pull up on
	sbi		PORTC, PORTC1	; pull up on

    cbi		DDRD, PORTD0	; pin for input as K0 (A9)
    cbi		DDRD, PORTD1	; pin for input as K1 (A10)
    cbi		DDRD, PORTD2	; pin for input as K2 (A11)
    cbi		DDRD, PORTD3	; pin for input as K3 (A12)
    cbi		DDRD, PORTD4	; pin for input as K4 (A13)
    cbi		DDRD, PORTD5	; pin for input as K5 (A14)
    cbi		DDRD, PORTD6	; pin for input as K6 (A15)
    cbi		DDRD, PORTD7	; pin for input as K7 (A16)
	sbi		PORTD, PORTD0	; pull up on
	sbi		PORTD, PORTD1	; pull up on
	sbi		PORTD, PORTD2	; pull up on
	sbi		PORTD, PORTD3	; pull up on
	sbi		PORTD, PORTD4	; pull up on
	sbi		PORTD, PORTD5	; pull up on
	sbi		PORTD, PORTD6	; pull up on
	sbi		PORTD, PORTD7	; pull up on

	; pins PB0,PB1,PB2 for output as SPI_CS, SPI_CLK, SPI_DI
	ldi		temp, (1<<PORTB2)|(1<<PORTB1)|(1<<PORTB0)
	out		DDRB, temp
	ldi		temp, 0x07
	out		PORTB, temp

; Enable INT0 interrupt
;;	ldi		temp, (1<<ISC01)	; The falling edge of INT0 generates an interrupt request
;;	sts		EICRA, temp
;;	ldi		temp, (1<<INT0)
;;	out		EIMSK, temp

; Enable Timer1 interrupt
	ldi		temp, 0x10		; timer value
	sts		OCR1AL, temp
	ldi		temp, 0x00
	sts		OCR1AH, temp

	ldi		temp, TCCR1B
	sbr		temp, (1<<WGM12)
	sts		TCCR1B, temp

	lds		temp, TIMSK1
	sbr		temp, (1<<OCIE1A)
;    sts     TIMSK1, temp

	; Enable pin change interrupt PCINT8 (PC0) 
	ldi		temp, (1<<PCIE1)
	sts		PCICR, temp
	ldi		temp, (1<<PCINT8)
	sts		PCMSK1, temp
	
	ldi		ZH, high(ScanCodeTable<<1)
	ldi		ZL, low(ScanCodeTable<<1)
	ldi		top_hi, high(ScanCodeTableEnd << 1)
	ldi		top_lo, low(ScanCodeTableEnd << 1)

	sei		; enable interrupt

MainLoop:
    nop
	rjmp	MainLoop

;--------------------------------------------------------------
; Scan code processing
;--------------------------------------------------------------
ScanCodeProc:
;	DBG_PIN_SET

	; check state: are we at idle state?
	ldi		sc_temp, SCAN_STATE_IDLE
	cp		scan_state, sc_temp
	brne	ScanStateNotIdle
	; we are at idle state
	; scan code E0?
	ldi		sc_temp, 0xE0
	cp		scan_code, sc_temp
	brne	ScanCodeNotE0
	; scan code is E0
	; set state as E0
	ldi		scan_state, SCAN_STATE_E0
	; switch scan code table for codes with E0
	ldi		ZH, high(ScanCodeTableE0<<1)
	ldi		ZL, low(ScanCodeTableE0<<1)
	ldi		top_hi, high(ScanCodeTableE0End << 1)
	ldi		top_lo, low(ScanCodeTableE0End << 1)
	rjmp	ScanStateEnd

ScanStateNotIdle:
	; check state: are we at F0 state?
	ldi		sc_temp, SCAN_STATE_F0
	cp		scan_state, sc_temp
	breq	ScanStateF0
	; we are at E0 state.
ScanStateE0:
ScanCodeNotE0:
	; scan code F0?
	ldi		sc_temp, 0xF0
	cp		scan_code, sc_temp
	brne	ScanCodeNotF0
	; scan code is F0
	ldi		scan_state, SCAN_STATE_F0
	rjmp	ScanStateEnd

ScanStateF0:
ScanCodeNotF0:
	; find scan code in table
ScanCodeSearchLoop:
	lpm		sc_temp, Z
	cp		sc_temp, scan_code
	breq	ScanCodeFound
	adiw	Z, TABLE_ROW_SIZE
	; check loop end condition
	cp		ZH, top_hi
	brne	ScanCodeSearchLoop
	cp		ZL, top_lo
	brne	ScanCodeSearchLoop
	; scan code not found
	rjmp	ScanCodeStateIdle

ScanCodeFound:
	; read key code (key bit for CPLD register)
	adiw	Z, 1
	lpm		param, Z
	rcall	ScanCodeUpdate		; process the 2nd byte of table's row

	adiw	Z, 1
	lpm		param, Z
	rcall	ScanCodeUpdate		; process the 3rd byte of table's row

ScanCodeStateIdle:
	; reset state
	ldi		ZH, high(ScanCodeTable<<1)
	ldi		ZL, low(ScanCodeTable<<1)
	ldi		top_hi, high(ScanCodeTableEnd << 1)
	ldi		top_lo, low(ScanCodeTableEnd << 1)
	ldi		scan_state, SCAN_STATE_IDLE
	rjmp	ScanStateEnd

ScanStateEnd:
;	DBG_PIN_CLR
	ret

;--------------------------------------------------------------
; Scan code update
; param is 6 bit code key + 1 bit key state (pressed/released) from 'ScanCodeTable'
;--------------------------------------------------------------
ScanCodeUpdate:
	; is action for this scan code?
    cpi     param, K_NONE
	breq	ScanCodeUpdateRet		; no action if zero
	;breq	ScanCodeUpdateRet		; to do: special function for that key

	; action is depended on state
	ldi		sc_temp, SCAN_STATE_F0
	cp		scan_state, sc_temp
	breq	ScanCodeReleased
//ScanCodePressed:
	ori		param, 0b01000000   ; 6 bit - key pressed
	DBG_PIN_CLR
	rcall	CPLD_write          ; write to CPLD
	ret
ScanCodeReleased:
	andi	param, 0b10111111   ; 6 bit - key released
	DBG_PIN_SET
	rcall	CPLD_write	        ; write to CPLD
ScanCodeUpdateRet:
	ret

;--------------------------------------------------------------
; Write data to CPLD via SPI
;--------------------------------------------------------------
CPLD_write:
    ldi     temp, 8         ; bit counter
    cbi		PORTB, PORTB1   ; clear SPI_CLK
    cbi		PORTB, PORTB0   ; clear SPI_CS
write_bit_loop:
    SBRC    param, 0        ; test bit 0 and skip next instruction if bit is cleared
    sbi		PORTB, PORTB2   ; set SPI_DI
    SBRS    param, 0        ; test bit 0 and skip next instruction if bit is set
    cbi		PORTB, PORTB2   ; clear SPI_DI
	lsr		param           ; logical shift right
    sbi		PORTB, PORTB1   ; set SPI_CLK
	dec		temp            ; decrement bit counter, delay for SPI_CLK signal
    cbi		PORTB, PORTB1   ; clear SPI_CLK
	brne	write_bit_loop
    sbi		PORTB, PORTB0   ; set SPI_CS
    cbi		PORTB, PORTB2   ; clear SPI_DI
	ret

;--------------------------------------------------------------
; Interrupt handler for TIMER1
;--------------------------------------------------------------

TIMER1_Intr:
	;clr		scan_count
	;out		PORTD, scan_count ; output value to port D - PORTD
	;inc		scan_count
    reti

;--------------------------------------------------------------
; Interrupt handler INT0: clock signal from PS/2 keyboard
;--------------------------------------------------------------
;;INT0_Intr:
;;
;;	cpi		scan_count, 0	; start bit?
;;	breq	int0_skip
;;	cpi		scan_count, 9	; all data bits received?
;;	brge	int0_skip
;;
;;	in		temp0, PIND		; read PORT D
;;	clc						; clear Carry flag
;;	sbrc	temp0, PORTD3	; skip the next instruction if PORTD3 is cleared	
;;	sec						; set carry bit if PORTD3 isn't cleared
;;	ror		scan_bits		; carry bit is shifted to 7 bit 'scan_bits'
;;
;;int0_skip:
;;	inc		scan_count			; increment scan code counter
;;	cpi		scan_count, 11
;;	brlt	int0_return
;;	; done
;;	mov		scan_code, scan_bits
;;	clr		scan_count
;;	clr		scan_bits
;;
;;int0_return:
;;	reti

;--------------------------------------------------------------
; Interrupt handler PCI1: clock signal from PS/2 keyboard
;--------------------------------------------------------------
PCI1_Intr:
	in		temp0, PINC		; read PORT C

	sbrc	temp0, PORTC0	; falling edge check: skip the next instruction if PORTC0 is cleared
	reti

	cpi		scan_count, 0	; start bit?
	breq	pci1_skip
	cpi		scan_count, 9	; all data bits received?
	brge	pci1_skip

	clc						; clear Carry flag
	sbrc	temp0, PORTC1	; skip the next instruction if PORTC1 is cleared
	sec						; set carry bit if PORTD3 isn't cleared
	ror		scan_bits		; carry bit is shifted to 7 bit 'scan_bits'

	;ldi		temp0, 0			; debug pin
	;sbrc	scan_bits, 7
	;ldi		temp0, 1
	;out		PORTB, temp0

pci1_skip:
	inc		scan_count			; increment scan code counter
	cpi		scan_count, 11
	brlt	pci1_return
	; done
	mov		scan_code, scan_bits
	clr		scan_count
	clr		scan_bits

	rcall	ScanCodeProc

pci1_return:
	reti

;--------------------------------------------------------------
; Scan code tables
;
;                 D0       D1      D2      D3     D4
; 
;  A8.  A0:       CS  0    Z  8    X  16   C 24   V 32
;  A9.  A1:       A   1    S  9    D  17   F 25   G 33     
;  A10. A2:       Q   2    W  10   E  18   R 26   T 34      
;  A11. A3:       1   3    2  11   3  19   4 27   5 35
;  A12. A4:       0   4    9  12   8  20   7 28   6 36
;  A13. A5:       P   5    O  13   I  21   U 29   Y 37
;  A14. A6:       Ent 6    L  14   K  22   J 30   H 38
;  A15. A7:       Sp  7    SS 15   M  23   N 31   B 39
;--------------------------------------------------------------

.cseg
;1 byte scan code for press, prefix F0 for release
ScanCodeTable:
; <PS/2 Scan Code>, <1st key code> <2nd key code> 
.DB 	0x01, K_NONE, K_NONE, 0	;	F9
.DB 	0x03, K_NONE, K_NONE, 0	;	F5
.DB 	0x04, K_NONE, K_NONE, 0	;	F3
.DB 	0x05, K_NONE, K_NONE, 0	;	F1
.DB 	0x06, K_NONE, K_NONE, 0	;	F2
.DB 	0x07, K_RST,  K_NONE, 0	;	F12  -- CPU reset by CPLD
.DB 	0x09, K_NONE, K_NONE, 0	;	F10
.DB 	0x0A, K_MGC,  K_NONE, 0	;	F8   -- magic key
.DB 	0x0B, K_NONE, K_NONE, 0	;	F6
.DB 	0x0C, K_NONE, K_NONE, 0	;	F4
.DB 	0x0D, K_NONE, K_NONE, 0	;	Tab
.DB 	0x0E, K_NONE, K_NONE, 0	;	~
.DB 	0x11, K_NONE, K_NONE, 0	;	Left Alt
.DB 	0x12, K_CS,   K_NONE, 0	;	Left Shift -- CAPS SHIFT
.DB 	0x14, K_NONE, K_NONE, 0	;	Left Ctrl
.DB 	0x15, K_Q,    K_NONE, 0	;	Q
.DB 	0x16, K_1,    K_NONE, 0	;	1
.DB 	0x1A, K_Z,    K_NONE, 0	;	Z
.DB 	0x1B, K_S,    K_NONE, 0	;	S
.DB 	0x1C, K_A,    K_NONE, 0	;	A
.DB 	0x1D, K_W,    K_NONE, 0	;	W
.DB 	0x1E, K_2,    K_NONE, 0	;	2
.DB 	0x21, K_C,    K_NONE, 0	;	C
.DB 	0x22, K_X,    K_NONE, 0	;	X
.DB 	0x23, K_D,    K_NONE, 0	;	D
.DB 	0x24, K_E,    K_NONE, 0	;	E
.DB 	0x25, K_4,    K_NONE, 0	;	4
.DB 	0x26, K_3,    K_NONE, 0	;	3
.DB 	0x29, K_SP,   K_NONE, 0	;	Space
.DB 	0x2A, K_V,    K_NONE, 0	;	V
.DB 	0x2B, K_F,    K_NONE, 0	;	F
.DB 	0x2C, K_T,    K_NONE, 0	;	T
.DB 	0x2D, K_R,    K_NONE, 0	;	R
.DB 	0x2E, K_5,    K_NONE, 0	;	5
.DB 	0x31, K_N,    K_NONE, 0	;	N
.DB 	0x32, K_B,    K_NONE, 0	;	B
.DB 	0x33, K_H,    K_NONE, 0	;	H
.DB 	0x34, K_G,    K_NONE, 0	;	G
.DB 	0x35, K_Y,    K_NONE, 0	;	Y
.DB 	0x36, K_6,    K_NONE, 0	;	6
.DB 	0x3A, K_M,    K_NONE, 0	;	M
.DB 	0x3B, K_J,    K_NONE, 0	;	J
.DB 	0x3C, K_U,    K_NONE, 0	;	U
.DB 	0x3D, K_7,    K_NONE, 0	;	7
.DB 	0x3E, K_8,    K_NONE, 0	;	8
.DB 	0x41, K_SS,   K_N   , 0 ;	,
.DB 	0x42, K_K,    K_NONE, 0	;	K
.DB 	0x43, K_I,    K_NONE, 0	;	I
.DB 	0x44, K_O,    K_NONE, 0	;	O
.DB 	0x45, K_0,    K_NONE, 0	;	0
.DB 	0x46, K_9,    K_NONE, 0	;	9
.DB 	0x49, K_SS,   K_M	, 0 ;	.
.DB 	0x4A, K_SS,   K_V	, 0 ;	/
.DB 	0x4B, K_L,    K_NONE, 0	;	L
.DB 	0x4C, K_SS,   K_O	, 0 ;	;
.DB 	0x4D, K_P,    K_NONE, 0	;	P
.DB 	0x4E, K_SS,   K_J   , 0 ;	-
.DB 	0x52, K_SS,   K_P	, 0 ;	' -> "
.DB 	0x54, K_NONE, K_NONE, 0	;	[
.DB 	0x55, K_SS,   K_L	, 0 ;	=
.DB 	0x58, K_NONE, K_NONE, 0	;	Caps Lock
.DB 	0x59, K_SS,   K_NONE, 0	;	Right Shift -- SYMBOL SHIFT
.DB 	0x5A, K_ENT,  K_NONE, 0	;	Enter
.DB 	0x5B, K_NONE, K_NONE, 0	;	]
.DB 	0x5D, K_SS,   K_V	, 0 ;	\
.DB 	0x66, K_CS,   K_0	, 0 ;	BackSpace
.DB 	0x69, K_1,    K_NONE, 0	;	1
.DB 	0x6B, K_4,    K_NONE, 0	;	4
.DB 	0x6C, K_7,    K_NONE, 0	;	7
.DB 	0x70, K_0,    K_NONE, 0	;	0
.DB 	0x71, K_SS,   K_M	, 0 ;	.
.DB 	0x72, K_2,    K_NONE, 0	;	2
.DB 	0x73, K_5,    K_NONE, 0	;	5
.DB 	0x74, K_6,    K_NONE, 0	;	6
.DB 	0x75, K_8,    K_NONE, 0	;	8
.DB 	0x76, K_CS,   K_1	, 0 ;	Esc
.DB 	0x77, K_NONE, K_NONE, 0	;	Num Lock
.DB 	0x78, K_NONE, K_NONE, 0	;	F11
.DB 	0x79, K_SS,   K_K	, 0 ;	+
.DB 	0x7A, K_3,    K_NONE, 0	;	3
.DB 	0x7B, K_SS,   K_J	, 0 ;	-
.DB 	0x7C, K_SS,   K_B	, 0 ;	*
.DB 	0x7D, K_9,    K_NONE, 0	;	9
.DB 	0x7E, K_NONE, K_NONE, 0	;	Scroll Lock
.DB 	0x83, K_NONE, K_NONE, 0	;	F7
ScanCodeTableEnd:
ScanCodeTableE0:
.DB 	0x75, K_CS, K_7     , 0  ; Up
.DB 	0x6B, K_CS, K_5     , 0  ; Left
.DB 	0x72, K_CS, K_6     , 0  ; Down
.DB 	0x74, K_CS, K_8     , 0  ; Rigth
.DB 	0x4A, K_SS, K_V     , 0  ; /
.DB 	0x5A, K_ENT, K_NONE , 0  ; Enter
ScanCodeTableE0End:	
.DB 	0x00, 0x00, 0x00, 0x00


