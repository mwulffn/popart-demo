;=====================================================================
; scene1.asm — "THE TITLE PRINT RUN" (song pos 0-3)
;
; POP/ART stencil emerges through 8 halftone print passes: each bar,
; one more 16px-pitch dot sub-grid is OR'd into a work plane (CPU),
; then the visible plane is re-printed as title AND work (one blit).
; From pos 2 (horn hook) the background slams through the pop palette
; on every kick.
;=====================================================================

	include	"src/custom.i"

	xdef	sc1_init
	xdef	sc1_update

	xref	waitblit
	xref	songpos
	xref	songrow

	section	code,code

sc1_init:
	; clear screen + work planes (CPU, init-time)
	lea	s1_screen,a0
	lea	s1_work,a1
	move.w	#10240/4-1,d0
	moveq	#0,d1
.clr:	move.l	d1,(a0)+
	move.l	d1,(a1)+
	dbf	d0,.clr
	move.w	#-1,s1_pass

	; point copper bitplane ptr at the screen plane
	move.l	#s1_screen,d0
	move.w	d0,cop1_bpl+6		; low word
	swap	d0
	move.w	d0,cop1_bpl+2		; high word

	lea	cop_scene1,a0
	move.l	a0,COP1LC(a6)
	rts

sc1_update:
	; --- halftone pass: bar index = (pos*64+row)/16, clamp 0-7 ---
	move.w	songpos,d0
	lsl.w	#6,d0
	add.w	songrow,d0
	lsr.w	#4,d0			; bar number since song start
	cmp.w	#7,d0
	ble.s	.p_ok
	moveq	#7,d0
.p_ok:	cmp.w	s1_pass,d0
	beq	.colors
	move.w	d0,s1_pass

	; OR pass pattern into work plane: 256 rows, pattern repeats
	; every 16 px -> one longword per row, 10 longs across
	lea	dotpass_tab(pc),a0
	lsl.w	#5,d0			; pass * 32 bytes (16 words)
	add.w	d0,a0
	lea	s1_work,a1
	moveq	#15,d2			; 16 pattern rows
.prow:	move.w	(a0)+,d1
	move.w	d1,d0
	swap	d1
	move.w	d0,d1			; d1 = pattern in both words
	lea	(a1),a2
	moveq	#16-1,d3		; 16 screen rows with this pattern
.srow:	; hmm — pattern row r covers screen rows r, r+16, r+32 ...
	or.l	d1,(a2)
	or.l	d1,4(a2)
	or.l	d1,8(a2)
	or.l	d1,12(a2)
	or.l	d1,16(a2)
	or.l	d1,20(a2)
	or.l	d1,24(a2)
	or.l	d1,28(a2)
	or.l	d1,32(a2)
	or.l	d1,36(a2)
	lea	40*16(a2),a2		; next row with same pattern
	dbf	d3,.srow
	lea	40(a1),a1		; next pattern row start
	dbf	d2,.prow

	; print: screen = title AND work (blitter, D = A & B)
	bsr	waitblit
	move.l	#$0dc00000,BLTCON0(a6)	; USEA|USEB|USED, LF=$c0, no shifts
	move.l	#-1,BLTAFWM(a6)
	move.l	#title_data,BLTAPTH(a6)
	move.l	#s1_work,BLTBPTH(a6)
	move.l	#s1_screen,BLTDPTH(a6)
	moveq	#0,d0
	move.w	d0,BLTAMOD(a6)
	move.w	d0,BLTBMOD(a6)
	move.w	d0,BLTDMOD(a6)
	move.w	#256<<6|20,BLTSIZE(a6)

.colors:
	; --- background: paper during the intro, palette slams once the
	;     horn hook lands (pos >= 2), one color per kick (8 rows) ---
	move.w	#COL_PAPER,d0
	cmp.w	#2,songpos
	blt.s	.set
	move.w	songpos,d0
	lsl.w	#6,d0
	add.w	songrow,d0
	lsr.w	#3,d0			; beat count
	and.w	#3,d0
	add.w	d0,d0
	lea	.slam(pc),a0
	move.w	(a0,d0.w),d0
.set:	move.w	d0,cop1_col0+2
	rts

.slam:	dc.w	COL_YEL,COL_MAG,COL_CYAN,COL_ORG

	include	"build/art/dotpass.i"

;---------------------------------------------------------------------
	section	s1data,data_c
;---------------------------------------------------------------------
title_data:
	incbin	"build/art/title.bpl"

cop_scene1:
	dc.w	$01fc,$0000		; FMODE
	dc.w	$0102,$0000		; BPLCON1
	dc.w	$0104,$0024		; BPLCON2
	dc.w	$0108,$0000		; BPL1MOD
	dc.w	$010a,$0000		; BPL2MOD
cop1_bpl:
	dc.w	$00e0,$0000		; BPL1PTH
	dc.w	$00e2,$0000		; BPL1PTL
cop1_col0:
	dc.w	$0180,COL_PAPER
	dc.w	$0182,COL_INK		; COLOR01: the print ink
	dc.w	$0100,$1200		; BPLCON0: 1 plane, color on
	dc.w	$ffff,$fffe

;---------------------------------------------------------------------
	section	s1bss,bss_c
;---------------------------------------------------------------------
s1_screen:	ds.b	10240
s1_work:	ds.b	10240

	section	s1vars,bss
s1_pass:	ds.w	1
