;=====================================================================
; scene5.asm — "PRODUCTION LINE" (song pos 18-19)
;
; Four full-width conveyor bands (64 px), all displaying THE SAME
; pre-tiled band bitmap (one row of floppy stamps, pitch 48 px): the
; copper re-loads BPL1PT at every band boundary — store one, print
; four. Bands hardware-scroll (BPLCON1 fine + word-coarse pointer),
; alternating direction, two speeds. Each band is a two-tone print
; (COLOR00/COLOR01 per band via copper); the color queue advances one
; band per downbeat.
;
; Per-band copper block, 24 bytes (see cop5_b0):
;   WAIT(V,$01) COLOR00 COLOR01 BPL1PTH BPL1PTL BPLCON1
;=====================================================================

	include	"src/custom.i"

	xdef	sc5_init
	xdef	sc5_update

	xref	songpos
	xref	songrow

BANDBPR	equ	48			; band bitmap bytes/row (384 px)
PITCH	equ	48			; stamp pitch in px

	section	code,code

;---------------------------------------------------------------------
sc5_init:
	; build the band bitmap: clear, then 8 stamps at 48px pitch,
	; vertically centered (rows 16-47)
	lea	s5_band,a0
	move.w	#64*BANDBPR/4-1,d0
	moveq	#0,d1
.clr:	move.l	d1,(a0)+
	dbf	d0,.clr
	lea	stamp32(pc),a0
	lea	s5_band+16*BANDBPR,a1
	moveq	#0,d2			; row 0..31
.row:	moveq	#8-1,d3			; 8 stamps across
	move.w	(a0)+,d0		; stamp words for this row
	move.w	(a0)+,d1
	move.l	a1,a2
.stmp:	move.w	d0,(a2)
	move.w	d1,2(a2)
	addq.w	#6,a2			; next stamp col (48px)
	dbf	d3,.stmp
	lea	BANDBPR(a1),a1
	addq.w	#1,d2
	cmp.w	#32,d2
	blt.s	.row

	; zero scroll accumulators
	lea	s5_off,a0
	moveq	#0,d0
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)+

	lea	cop_scene5,a0
	move.l	a0,COP1LC(a6)
	rts

;---------------------------------------------------------------------
sc5_update:
	; advance each band's offset (8.8 fixed), wrap at one pitch
	lea	s5_off,a2
	lea	s5_spd(pc),a3
	lea	cop5_b0,a0		; first band block
	moveq	#0,d5			; band index
.band:	move.l	(a2),d0
	add.l	(a3)+,d0		; signed speed
	cmp.l	#PITCH<<8,d0
	blt.s	.nw1
	sub.l	#PITCH<<8,d0
.nw1:	tst.l	d0
	bge.s	.nw2
	add.l	#PITCH<<8,d0
.nw2:	move.l	d0,(a2)+

	; m = px offset 0..47 -> coarse words w, fine scroll v
	asr.l	#8,d0			; m
	move.w	d0,d1
	add.w	#15,d1
	lsr.w	#4,d1			; w = (m+15)/16
	move.w	d1,d2
	lsl.w	#4,d2
	sub.w	d0,d2			; v = w*16 - m  (0..15)
	move.w	d2,d3
	lsl.w	#4,d3
	or.w	d2,d3			; v in both nibbles

	; poke this band's copper block: colors, pointer, scroll
	; color pair index = (absrow/8 + band) & 3
	move.w	songpos,d0
	lsl.w	#6,d0
	add.w	songrow,d0
	lsr.w	#3,d0
	add.w	d5,d0
	and.w	#3,d0
	lsl.w	#2,d0
	lea	s5_cols(pc),a1
	move.w	(a1,d0.w),6(a0)		; COLOR00 value
	move.w	2(a1,d0.w),10(a0)	; COLOR01 value
	move.l	#s5_band,d0
	add.w	d1,d0
	add.w	d1,d0			; + w*2
	move.w	d0,18(a0)		; BPL1PTL
	swap	d0
	move.w	d0,14(a0)		; BPL1PTH
	move.w	d3,22(a0)		; BPLCON1

	lea	24(a0),a0		; next band block
	addq.w	#1,d5
	cmp.w	#4,d5
	blt	.band
	rts

; band speeds, 8.8 px/frame (signed: + = leftward)
s5_spd:	dc.l	$00c0,-$0060,$0060,-$00c0

; two-tone print pairs (COLOR00, COLOR01)
s5_cols:
	dc.w	COL_PAPER,COL_MAG
	dc.w	COL_PAPER,COL_CYAN
	dc.w	COL_INK,COL_YEL
	dc.w	COL_PAPER,COL_GRN

	include	"build/art/stamp.i"

;---------------------------------------------------------------------
	section	s5data,data_c
;---------------------------------------------------------------------
cop_scene5:
	dc.w	$01fc,$0000		; FMODE
	dc.w	$0092,$0030		; DDFSTRT: one word early (scroll room)
	dc.w	$0094,$00d0		; DDFSTOP
	dc.w	$0104,$0024		; BPLCON2
	dc.w	$010c,$0011		; BPLCON4
	dc.w	$0108,$0006		; BPL1MOD: 48-42 fetched
	dc.w	$010a,$0006
	dc.w	$0100,$1200		; 1 plane
cop5_b0:
	dc.w	$2c07,$fffe
	dc.w	$0180,COL_PAPER
	dc.w	$0182,COL_MAG
	dc.w	$00e0,0
	dc.w	$00e2,0
	dc.w	$0102,0
	dc.w	$6c07,$fffe		; band 1
	dc.w	$0180,COL_PAPER
	dc.w	$0182,COL_CYAN
	dc.w	$00e0,0
	dc.w	$00e2,0
	dc.w	$0102,0
	dc.w	$ac07,$fffe		; band 2
	dc.w	$0180,COL_INK
	dc.w	$0182,COL_YEL
	dc.w	$00e0,0
	dc.w	$00e2,0
	dc.w	$0102,0
	dc.w	$ec07,$fffe		; band 3
	dc.w	$0180,COL_PAPER
	dc.w	$0182,COL_GRN
	dc.w	$00e0,0
	dc.w	$00e2,0
	dc.w	$0102,0
	dc.w	$ffff,$fffe

;---------------------------------------------------------------------
	section	s5bss,bss_c
;---------------------------------------------------------------------
s5_band:	ds.b	64*BANDBPR

	section	s5vars,bss
s5_off:		ds.l	4
