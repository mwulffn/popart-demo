;=====================================================================
; scene3.asm — "THE SCREEN ITSELF" (song pos 10-15)
;
; The halftone screen with nothing printed on it: a 20x16 grid of
; 16x16 px Ben-Day dots, radii driven by a three-sine plasma (CPU,
; double buffered, one bitplane). Three process-color bands (magenta/
; yellow/cyan COLOR01 splits) slide down the screen — the print heads.
; During the pat-0 breakdown (pos 10-11) the plasma is damped to a
; near-uniform grid (the machine idling); the B-section entry at pos 12
; snaps it to full amplitude. Each kick thumps the diagonal phase.
;=====================================================================

	include	"src/custom.i"

	xdef	sc3_init
	xdef	sc3_update

	xref	songpos
	xref	songrow

	section	code,code

;---------------------------------------------------------------------
sc3_init:
	; clear both dot buffers
	lea	s3_buf0,a0
	move.w	#2*10240/4-1,d0
	moveq	#0,d1
.clr:	move.l	d1,(a0)+
	dbf	d0,.clr
	clr.w	s3_frame
	clr.w	s3_beat
	move.w	#40,s3_t1
	move.w	#80,s3_t2
	clr.w	s3_t3
	lea	cop_scene3,a0
	move.l	a0,COP1LC(a6)
	rts

;---------------------------------------------------------------------
sc3_update:
	; --- pick back buffer, render plasma dots into it ---
	lea	s3_buf0,a1
	move.w	s3_frame,d0
	addq.w	#1,d0
	move.w	d0,s3_frame
	btst	#0,d0
	beq.s	.buf
	lea	s3_buf1,a1
.buf:	move.l	a1,-(sp)		; keep for the copper poke

	; phase advance (thump the diagonal on each kick)
	addq.w	#2,s3_t1
	subq.w	#3,s3_t2
	addq.w	#1,s3_t3
	move.w	songpos,d0
	lsl.w	#6,d0
	add.w	songrow,d0
	lsr.w	#3,d0
	cmp.w	s3_beat,d0
	beq.s	.nothump
	move.w	d0,s3_beat
	add.w	#32,s3_t3
.nothump:

	; damping: pos 10-11 (breakdown) -> flat grid around level 8
	moveq	#0,d7			; d7 = 0: full amplitude
	cmp.w	#12,songpos
	bge.s	.amp
	moveq	#1,d7			; damped
.amp:
	lea	sintab(pc),a0
	lea	dottab(pc),a3
	moveq	#0,d5			; celly 0..15
.yloop:	moveq	#0,d4			; cellx 0..19
	; row terms for this celly
	move.w	d5,d1
	mulu	#19,d1
	add.w	s3_t2,d1
	and.w	#255,d1
	move.b	(a0,d1.w),d6		; sin(y*19+t2)
	ext.w	d6
.xloop:	move.w	d4,d0
	mulu	#13,d0
	add.w	s3_t1,d0
	and.w	#255,d0
	moveq	#0,d2
	move.b	(a0,d0.w),d2		; sin(x*13+t1)
	add.w	d6,d2
	move.w	d4,d0
	mulu	#7,d0
	move.w	d5,d1
	mulu	#9,d1
	add.w	d1,d0
	add.w	s3_t3,d0
	and.w	#255,d0
	moveq	#0,d3
	move.b	(a0,d0.w),d3		; sin(x*7+y*9+t3)
	add.w	d3,d2			; 0..252
	lsr.w	#4,d2			; intensity 0..15
	tst.w	d7
	beq.s	.full
	; damped: 8 + (i-8)/4
	subq.w	#8,d2
	asr.w	#2,d2
	addq.w	#8,d2
.full:
	; stamp dot tile: dest = buf + celly*640 + cellx*2
	; (celly*640 = celly*512 + celly*128)
	move.w	d5,d0
	lsl.w	#8,d0
	lsl.w	#1,d0			; celly*512
	move.w	d5,d1
	lsl.w	#7,d1			; celly*128
	add.w	d1,d0
	add.w	d4,d0
	add.w	d4,d0			; + cellx*2
	lea	(a1,d0.w),a2		; d0 max 15*640+38 = 9638, fits .w
	lsl.w	#5,d2			; intensity*32
	lea	(a3,d2.w),a4
	rept	16
	move.w	(a4)+,(a2)
	lea	40(a2),a2
	endr

	addq.w	#1,d4
	cmp.w	#20,d4
	blt	.xloop
	addq.w	#1,d5
	cmp.w	#16,d5
	blt	.yloop

	; --- flip: point copper at the freshly rendered buffer ---
	move.l	(sp)+,d0
	move.w	d0,cop3_bpl+6
	swap	d0
	move.w	d0,cop3_bpl+2

	; --- slide the three color-band boundaries (copper WAITs) ---
	move.w	s3_frame,d0
	lsl.w	#1,d0
	and.w	#255,d0
	move.b	(a0,d0.w),d1		; 0..84
	ext.w	d1
	lsr.w	#1,d1			; 0..42
	add.w	#$2c+64,d1		; boundary 1: lines 64..106
	move.b	d1,cop3_band1
	move.w	s3_frame,d0
	move.w	d0,d2
	lsr.w	#1,d2
	add.w	#85,d2
	and.w	#255,d2
	move.b	(a0,d2.w),d1
	ext.w	d1
	lsr.w	#1,d1
	add.w	#$2c+140,d1		; boundary 2: lines 140..182
	move.b	d1,cop3_band2
	rts

	include	"build/art/dottab.i"
	include	"build/art/sintab.i"

;---------------------------------------------------------------------
	section	s3data,data_c
;---------------------------------------------------------------------
cop_scene3:
	dc.w	$01fc,$0000		; FMODE
	dc.w	$0102,$0000		; BPLCON1
	dc.w	$0104,$0024		; BPLCON2
	dc.w	$010c,$0011		; BPLCON4: palette 0
	dc.w	$0108,$0000		; BPL1MOD
	dc.w	$010a,$0000		; BPL2MOD
cop3_bpl:
	dc.w	$00e0,$0000		; BPL1PTH
	dc.w	$00e2,$0000		; BPL1PTL
	dc.w	$0180,COL_PAPER
	dc.w	$0182,COL_MAG		; band 1: magenta head
	dc.w	$0100,$1200		; BPLCON0: 1 plane
cop3_band1:
	dc.w	$6c05,$fffe		; WAIT boundary 1 (V byte poked)
	dc.w	$0182,COL_YEL		; band 2: yellow head
cop3_band2:
	dc.w	$b805,$fffe		; WAIT boundary 2 (V byte poked)
	dc.w	$0182,COL_CYAN		; band 3: cyan head
	dc.w	$ffff,$fffe

;---------------------------------------------------------------------
	section	s3bss,bss_c
;---------------------------------------------------------------------
s3_buf0:	ds.b	10240
s3_buf1:	ds.b	10240

	section	s3vars,bss
s3_frame:	ds.w	1
s3_beat:	ds.w	1
s3_t1:		ds.w	1
s3_t2:		ds.w	1
s3_t3:		ds.w	1
