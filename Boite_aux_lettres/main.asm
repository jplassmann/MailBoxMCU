/*
 * main.asm
 *
 *  Created: 10/05/2018 09:28:08
 *   Author: Ken Pillonel, Jérémy Plassmann
 */ 
.include "macros.asm"
.include "definitions.asm"
.equ	baud	= 9600
.equ	npt = 1484
.def	ctx 	= r20		; character

.macro AFFICHE ;affiche le menu dans lequel l'utilisateur est
	PRINTF LCD
.db	CR,CR,@0,0
	rcall LCD_lf
	mov	r17,r23
	andi r17,@1
	cpi r17,0b00000000
	breq saut
	PRINTF LCD
.db	CR,CR,"ON               ",0
	rcall LCD_back_to_first
	mov a0, r17
	ldi a0, 0x00
	rcall LCD_pos
	mov r17,a0
	rjmp fin
saut:	
	PRINTF LCD
.db	CR,CR,"OFF              ",0
	rcall LCD_back_to_first
	mov a0, r17
	ldi a0, 0x00
	rcall LCD_pos
	mov r17,a0
fin:
.endmacro

.org 0
	jmp reset
	jmp ext_int1
	jmp ext_int2
	jmp reset

ext_int1:
	inc r24
	cpi r24,3
	breq regtozero
	WAIT_MS 300
	reti
regtozero:
	ldi r24, 0
	WAIT_MS 300
	reti

ext_int2:
	WAIT_MS 300
	cpi r24,0
	breq onoff_0

	cpi r24,1
	breq onoff_1

	cpi r24,2
	breq onoff_2
	reti

.macro CA3		;call a subroutine with three arguments in a1:a0 b0
	ldi	a0, low(@1)		;speed and rotation direction
	ldi a1, high(@1)	;speed and rotation direction
	ldi b0, @2			;angle
	rcall	@0
.endmacro


onoff_0:
	mov	r17,r23
	andi r17,0b00000001
	cpi r17,0b00000000
	breq PC+3
	andi r23,0b11111110
	reti
	ori r23,0b00000001
	reti

onoff_1:
	mov	r17,r23
	andi r17,0b00000010
	cpi r17,0b00000000
	breq PC+4
	andi r23,0b11111101
	ldi r28,0
	reti
	ori r23,0b00000010
	reti

onoff_2:
	mov	r17,r23
	andi r17,0b00000100
	cpi r17,0b00000000
	breq of
	andi r23,0b11111011	
	CA3	_s360, (npt+316), 0x0e ;active le moteur servo de 180° cw
	reti
of:
	ori r23,0b00000100	
	CA3 _s360, (npt-310), 0x0e ;active le moteur servo de 180° ccw
	reti

	
reset:
	LDSP RAMEND
	OUTI	EIMSK,0b00000111 ; enable INT0..INT3	;
	OUTI	DDRB,0xff
	sei
	rcall LCD_init
	ldi r24, 0
	ldi r23, 0b00000000
	ldi r28,0
	
	OUTI	ADCSR,(1<<ADEN)+6	; AD Enable, PS=CK/64	
	OUTI	ADMUX,3			; select channel POT (potentiometer)	
	OUTI	DDRE,0b00000010	; make Tx (PE1) an output
	sbi	PORTE,PE1	; set Tx to high	
	sbi	DDRE,SPEAKER				; make pin SPEAKER an output
	rjmp main
	
.include "uart.asm"
.include "lcd.asm"
.include "printf.asm"


display_menu:
	cpi r24,0
	breq go_to_first

	cpi r24,1
	breq go_to_second

	cpi r24,2
	breq go_to_third	
	ret

;passage par rjmp car plus grande porté que branch
go_to_first:
	rjmp first

go_to_second:
	rjmp second

go_to_third:
	rjmp third

first:
	AFFICHE "Notification   ", 0b00000001
	ret

second:
	AFFICHE "Sound          ", 0b00000010
	ret

third:
	AFFICHE "Lock           ", 0b00000100
	ret

;moteur servo
_s360:	
ls3601:
	rcall	servoreg_pulse
	dec		b0
	brne	ls3601
	ret

servoreg_pulse:
	WAIT_US	20000
	MOV2	a3,a2, a1,a0
	P1	PORTB,SERVO1		; pin=1	
lpssp01:	DEC2	a3,a2
	brne	lpssp01
	P0	PORTB,SERVO1		; pin=0
	ret

;connexion UART
wait_bit:
	WAIT_C	(clock/baud)-18	; subtract overhead
	ret
wait_1bit5:
	WAIT_C	(3*clock/2/baud)-18
	ret

putc:	cbi	PORTE,PE1	; set start bit to 0
	rcall	wait_bit	; wait 1-bit period (start bit)
	sec			; set carry
loop:	ror	ctx		; shift LSB into carry
 	C2P	PORTE,PE1	; carry to port
 	rcall	wait_bit	; wait 1-bit period (data bit)
	clc			; clear carry
	tst	ctx		; test c for zero
	brne	loop		; loop back if not zero
	sbi	PORTE,PE1	; set stop bit to 1
	rcall	wait_bit	; wait 1-bit period (stop bit)
	ret

main:
	rcall	display_menu

	cpi r28, 0
	breq PC+5
	sbi	PORTE,SPEAKER
	WAIT_US 500					; insert delay here

	cbi	PORTE,SPEAKER
	WAIT_US	500
	

	sbi	ADCSR,ADSC				; AD start conversion
	WP1	ADCSR,ADSC				; wait if ADIF=0
	in	a0,ADCL					; read low byte first
	in	a1,ADCH					; read high byte second

	push r25
	push r26
	ldi r26, 0x02
	ldi r25, 0x00
	CP2	a1, a0, r26, r25
	pop r25
	pop r26

	brge notif

	ldi r27, 0 ; r27 sert à faire en sorte que le caractere soit envoyé qu'une seule fois
	
	rjmp main

notif:
	mov	r17,r23
	andi r17,0b00000001
	cpi r17,0b00000000
	breq second_mode

	cpi r27,1
	breq second_mode

	push r23
	ldi r23, $61 
	mov r20, r23
	rcall	putc	
	pop r23
	
	WAIT_MS	100		; wait 100 ms
	
	ldi r27,1

second_mode:
	mov	r17,r23
	andi r17,0b00000010
	cpi r17,0b00000000
	breq PC+2

	ldi r28,1

	rjmp main
	