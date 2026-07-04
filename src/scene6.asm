;=====================================================================
; scene6.asm — "COLOPHON" (song pos 28-33 + end state)
;
; Credits as off-register silkscreen prints. ONE text plane per card;
; the misregistration is hardware: BPL1PT and BPL2PT both point into
; the same bitmap, plane 2 one row earlier (image drops 1 px) and
; BPLCON1 PF2H=2 (2 px right). Palette: %01 cyan pass, %10 magenta
; pass, %11 where the passes register = ink.
;
; Cards swap on song position (28/30/32). When the song ends the card
; freezes, the paper slams magenta and the halftone passes print the
; screen out to solid ink (scene 1's dot passes, run on both planes at
; once so even the dots are off-register).
;=====================================================================

	include	"src/custom.i"
	include	"build/art/cards.i"

	xdef	sc6_init
	xdef	sc6_update

	xref	songpos
	xref	songrow
	xref	songdone

	section	code,code

;---------------------------------------------------------------------
sc6_init:
	move.w	#-1,s6_card
	move.w	#-1,s6_pass
	clr.w	s6_timer
	; plane pointers: BPL1 = buf+40 (text), BPL2 = buf (1 row up)
	move.l	#s6_buf+40,d0
	move.w	d0,cop6_bpl+6
	swap	d0
	move.w	d0,cop6_bpl+2
	move.l	#s6_buf,d0
	move.w	d0,cop6_bpl+14
	swap	d0
	move.w	d0,cop6_bpl+10
	move.w	#COL_PAPER,cop6_col0+2
	lea	cop_scene6,a0
	move.l	a0,COP1LC(a6)
	rts

;---------------------------------------------------------------------
sc6_update:
	tst.b	songdone
	bne	.printout

	; card = (songpos-28)/2
	move.w	songpos,d0
	sub.w	#28,d0
	bge.s	.pos
	moveq	#0,d0
.pos:	lsr.w	#1,d0
	cmp.w	#NCARDS-1,d0
	ble.s	.ok
	moveq	#NCARDS-1,d0
.ok:	cmp.w	s6_card,d0
	beq.s	.done
	move.w	d0,s6_card

	; slam the card in: copy card page into buf+40, clear margin row
	lea	s6_buf,a1
	moveq	#0,d1
	moveq	#40/4-1,d2
.mar:	move.l	d1,(a1)+
	dbf	d2,.mar
	lea	cards_data,a0
	mulu	#CARD_SIZE,d0
	add.l	d0,a0
	move.w	#CARD_SIZE/4-1,d2
.cpy:	move.l	(a0)+,(a1)+
	dbf	d2,.cpy
.done:	rts

.printout:
	; paper -> magenta, then print the screen out with dot passes
	move.w	#COL_MAG,cop6_col0+2
	move.w	s6_pass,d0
	cmp.w	#7,d0
	bge.s	.halt
	addq.w	#1,s6_timer
	move.w	s6_timer,d0
	and.w	#3,d0			; one pass every 4 frames
	bne.s	.halt
	addq.w	#1,s6_pass
	move.w	s6_pass,d0
	; OR pass pattern over the whole buffer (257 rows)
	lea	dotpass_tab(pc),a0
	lsl.w	#5,d0
	add.w	d0,a0
	lea	s6_buf,a1
	moveq	#15,d2
.prow:	move.w	(a0)+,d1
	move.w	d1,d0
	swap	d1
	move.w	d0,d1
	move.l	a1,a2
	moveq	#16-1,d3
.srow:	or.l	d1,(a2)
	or.l	d1,4(a2)
	or.l	d1,8(a2)
	or.l	d1,12(a2)
	or.l	d1,16(a2)
	or.l	d1,20(a2)
	or.l	d1,24(a2)
	or.l	d1,28(a2)
	or.l	d1,32(a2)
	or.l	d1,36(a2)
	lea	40*16(a2),a2
	dbf	d3,.srow
	lea	40(a1),a1
	dbf	d2,.prow
.halt:	rts

	include	"build/art/dotpass.i"

;---------------------------------------------------------------------
	section	s6data,data_c
;---------------------------------------------------------------------
cards_data:
	incbin	"build/art/cards.bpl"

cop_scene6:
	dc.w	$01fc,$0000		; FMODE
	dc.w	$0092,$0038		; DDFSTRT back to standard
	dc.w	$0094,$00d0
	dc.w	$0102,$0020		; BPLCON1: PF2H = 2px (even plane)
	dc.w	$0104,$0024
	dc.w	$010c,$0011
	dc.w	$0108,$0000		; contiguous same-bitmap planes
	dc.w	$010a,$0000
cop6_bpl:
	dc.w	$00e0,0,$00e2,0		; BPL1PT: text
	dc.w	$00e4,0,$00e6,0		; BPL2PT: text, 1 row up
cop6_col0:
	dc.w	$0180,COL_PAPER
	dc.w	$0182,COL_CYAN		; %01: cyan pass
	dc.w	$0184,COL_MAG		; %10: magenta pass
	dc.w	$0186,COL_INK		; %11: registered = ink
	dc.w	$0100,$2200		; 2 planes
	dc.w	$ffff,$fffe

;---------------------------------------------------------------------
	section	s6bss,bss_c
;---------------------------------------------------------------------
s6_buf:		ds.b	40*257

	section	s6vars,bss
s6_card:	ds.w	1
s6_pass:	ds.w	1
s6_timer:	ds.w	1
