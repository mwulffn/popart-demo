;=====================================================================
; scene7.asm — "THE DIVE" (song pos 13-15): chunky rotozoomer
;
; 160 texture samples per line, each written as a doubled word (2 px),
; into a 320x100 chunky buffer in FAST ram; Kalms c2p1x1_4_c5 converts
; to 4 contiguous bitplanes in chip; the copper line-doubles to 200
; display lines (alternating -40/0 modulos), letterboxed with ink bars.
; Texture: the floppy print (128x128, scene-2 palette) tiling forever —
; zoom out and the edition repeats to the horizon, zoom in and the
; Ben-Day dots are boulders. Every kick flashes a scene-2 print-run
; variant over the whole world (BPLCON4) and pulses the zoom.
;
; This runs slower than 50 fps by design (one update = several vblanks;
; music is CIA-driven and unaffected). Frame pacing measured via the
; $668 beacon during bring-up.
;=====================================================================

	include	"src/custom.i"

	xdef	sc7_init
	xdef	sc7_update

	xref	songpos
	xref	songrow
	xref	c2p1x1_4_c5_gen_init
	xref	c2p1x1_4_c5_gen

CHKW	equ	320			; chunky buffer geometry
CHKH	equ	100
PLSIZE	equ	40*CHKH			; one bitplane
TOPLINE	equ	28			; letterbox: display lines 28-227

	section	code,code

;---------------------------------------------------------------------
sc7_init:
	; c2p geometry (matches BPLX/BPLY pinned in src/c2p.asm)
	move.w	#CHKW,d0
	move.w	#CHKH,d1
	moveq	#0,d2
	moveq	#0,d3
	move.w	#40,d4
	move.l	#PLSIZE,d5
	jsr	c2p1x1_4_c5_gen_init

	; palettes: same 8 print runs as scene 2 (shared texture palette)
	lea	floppy_pals(pc),a0
	moveq	#0,d2
.pal:	move.w	d2,d0
	lsr.w	#1,d0
	ror.w	#3,d0
	or.w	#$0c00,d0
	move.w	d0,BPLCON3(a6)
	lea	COLOR00(a6),a1
	btst	#0,d2
	beq.s	.half
	lea	32(a1),a1
.half:	moveq	#16-1,d1
.col:	move.w	(a0)+,(a1)+
	dbf	d1,.col
	addq.w	#1,d2
	cmp.w	#8,d2
	blt.s	.pal
	move.w	#$0c00,BPLCON3(a6)

	clr.w	s7_frame
	move.w	#192,s7_t		; zoom sweep starts fully dived-in
	clr.w	s7_ang
	clr.w	s7_pulse
	move.w	#-1,s7_beat

	lea	cop_scene7,a0
	move.l	a0,COP1LC(a6)
	rts

;---------------------------------------------------------------------
sc7_update:
	addq.w	#1,s7_frame
	addq.w	#1,s7_t

	; --- music: kick pulse + print-run variant flash ---
	move.w	songpos,d0
	lsl.w	#6,d0
	add.w	songrow,d0
	move.w	d0,d2
	lsr.w	#3,d2			; beat number
	cmp.w	s7_beat,d2
	beq.s	.nokick
	move.w	d2,s7_beat
	move.w	#$60,s7_pulse
.nokick:
	move.w	#$0011,d1		; BPLCON4: base palette
	and.w	#7,d0			; rows 0-1 after the kick: flash
	cmp.w	#2,d0
	bge.s	.noflash
	move.w	s7_beat,d1
	moveq	#7,d0
	and.w	d1,d0
	bne.s	.vok
	moveq	#1,d0			; never variant 0 (that's the base)
.vok:	ror.w	#4,d0
	or.w	#$0011,d0
	move.w	d0,d1
.noflash:
	move.w	d1,cop7_con4+2

	; --- zoom = base sweep + decaying kick pulse (8.8) ---
	lea	sinw(pc),a0
	move.w	s7_t,d0
	and.w	#255,d0
	add.w	d0,d0
	move.w	(a0,d0.w),d0		; -256..256
	muls	#$110,d0
	asr.l	#8,d0
	add.w	#$138,d0		; $28..$248
	add.w	s7_pulse,d0
	move.w	d0,d5			; d5 = zoom
	move.w	s7_pulse,d1		; pulse decay
	lsr.w	#1,d1
	move.w	d1,s7_pulse

	; --- rotation: accelerates as the scene builds (updates run at
	;     ~10 fps, so keep the per-update step small and stately) ---
	move.w	songpos,d1
	sub.w	#12,d1			; 1..3
	add.w	d1,s7_ang
	move.w	s7_ang,d1
	and.w	#255,d1

	; du = cos*zoom>>8, dv = sin*zoom>>8   (8.8 words)
	add.w	d1,d1
	move.w	(a0,d1.w),d2		; sin
	move.w	d1,d3
	add.w	#128,d3			; +64 entries = cos
	and.w	#511,d3
	move.w	(a0,d3.w),d3		; cos
	muls	d5,d2
	asr.l	#8,d2			; dv
	muls	d5,d3
	asr.l	#8,d3			; du

	; line starts: u0 = cu - 80*du + 50*dv ; v0 = cv - 80*dv - 50*du
	move.w	d3,d0
	muls	#-80,d0
	move.w	d2,d1
	muls	#50,d1
	add.l	d1,d0
	add.l	#$4000,d0		; center u = 64.0
	move.w	d2,d1
	muls	#-80,d1
	move.w	d3,d4
	muls	#-50,d4
	add.l	d4,d1
	add.l	#$4000,d1		; center v = 64.0
	; d0.l/d1.l = u0/v0 in 8.8 (low word significant)

	; --- render 100 lines x 160 doubled samples ---
	lea	s7_chunky,a0
	lea	floppytex,a2
	lea	dbltab(pc),a3
	move.w	#CHKH-1,d7
.line:	movem.l	d0-d1/d7,-(sp)
	move.w	d0,d6			; u walks in d6, v walks in d1
	moveq	#16-1,d7		; 16 chunks of 10 samples
	moveq	#0,d5			; d5 high byte stays 0 throughout
.chunk:
	; texture is 256-byte stride, rows doubled: v base = v&$7f00,
	; u wraps free in its 8-bit int part — 9 ops per sample
	rept	10
	move.w	d1,d4
	and.w	#$7f00,d4		; (vint&127)*256
	move.w	d6,d5
	lsr.w	#8,d5			; uint (0-255, wraps in texture)
	add.w	d5,d4
	move.b	(a2,d4.w),d5		; texel 0-15 (high byte still 0)
	move.w	(a3,d5.w*2),(a0)+	; doubled pixel pair
	add.w	d3,d6			; u += du
	add.w	d2,d1			; v += dv
	endr
	dbf	d7,.chunk
	movem.l	(sp)+,d0-d1/d7
	; perpendicular line step: u0 -= dv, v0 += du
	sub.w	d2,d0
	add.w	d3,d1
	dbf	d7,.line

	; --- c2p into the back buffer, then flip ---
	move.w	s7_frame,d0
	and.w	#1,d0
	mulu	#PLSIZE*4,d0
	lea	s7_bpl,a1
	add.l	d0,a1
	move.l	a1,-(sp)
	lea	s7_chunky,a0
	jsr	c2p1x1_4_c5_gen
	move.l	(sp)+,d0
	lea	cop7_bpl+2,a1
	moveq	#4-1,d1
.bpl:	swap	d0
	move.w	d0,(a1)
	swap	d0
	move.w	d0,4(a1)
	add.l	#PLSIZE,d0
	addq.w	#8,a1
	dbf	d1,.bpl
	rts

; 16 words: texel value -> doubled pixel pair (same byte twice)
dbltab:
	dc.w	$0000,$0101,$0202,$0303,$0404,$0505,$0606,$0707
	dc.w	$0808,$0909,$0a0a,$0b0b,$0c0c,$0d0d,$0e0e,$0f0f

	include	"build/art/sinw.i"
	include	"build/art/floppypal.i"

; texture lives in FAST ram (CPU-only reads; chip access would fight
; display DMA)
	section	s7texdata,data
floppytex:
	incbin	"build/art/floppytex.chk"

;---------------------------------------------------------------------
	section	s7data,data_c
;---------------------------------------------------------------------
cop_scene7:
	dc.w	$01fc,$0000		; FMODE
	dc.w	$0092,$0038		; standard DDF
	dc.w	$0094,$00d0
	dc.w	$0102,$0000
	dc.w	$0104,$0024
cop7_con4:
	dc.w	$010c,$0011		; BPLCON4: print-run variant flash
	dc.w	$0108,$0000		; mods start at 0
	dc.w	$010a,$0000
cop7_bpl:
	dc.w	$00e0,0,$00e2,0		; 4 contiguous bitplanes
	dc.w	$00e4,0,$00e6,0
	dc.w	$00e8,0,$00ea,0
	dc.w	$00ec,0,$00ee,0
	dc.w	$0180,COL_INK		; letterbox bars: ink
	dc.w	$0100,$0200		; planes off above the box

	dc.w	(($2c+TOPLINE)<<8)|$07,$fffe
	dc.w	$0100,$4200		; 4 planes on

; line-doubling: after even display lines rewind one row (-40), after
; odd ones advance normally. 200 lines, $ff crossing at display 212.
LINE	set	$2c+TOPLINE
	rept	212-TOPLINE
	dc.w	((LINE&$ff)<<8)|$07,$fffe
	ifeq	(LINE-$2c-TOPLINE)&1
	dc.w	$0108,-40&$ffff
	dc.w	$010a,-40&$ffff
	else
	dc.w	$0108,0
	dc.w	$010a,0
	endc
LINE	set	LINE+1
	endr
	dc.w	$ffdf,$fffe
	rept	228-212			; display lines 212-227
	dc.w	((LINE&$ff)<<8)|$07,$fffe
	ifeq	(LINE-$2c-TOPLINE)&1
	dc.w	$0108,-40&$ffff
	dc.w	$010a,-40&$ffff
	else
	dc.w	$0108,0
	dc.w	$010a,0
	endc
LINE	set	LINE+1
	endr
	dc.w	(($2c+TOPLINE+200)&$ff)<<8|$07,$fffe
	dc.w	$0100,$0200		; planes off below the box
	dc.w	$ffff,$fffe

;---------------------------------------------------------------------
	section	s7bss,bss_c
;---------------------------------------------------------------------
s7_bpl:		ds.b	PLSIZE*4*2	; two 4-plane buffers

	section	s7fast,bss
s7_chunky:	ds.b	CHKW*CHKH
s7_frame:	ds.w	1
s7_t:		ds.w	1
s7_ang:		ds.w	1
s7_pulse:	ds.w	1
s7_beat:	ds.w	1
