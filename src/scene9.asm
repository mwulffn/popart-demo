;=====================================================================
; scene9.asm — "THE CANVAS" (song pos 24-27)
;
; The gallery piece: one full-screen 256-color print (320x256x8,
; contiguous planes, AGA 64-bit fetch). No motion — after five scenes
; of process the demo hangs the finished work and lets it sit. The
; only event: a 2-frame paper flash when the B-reprise lands (pos 26)
; — one last squeegee pass over the masterpiece.
;
; AGA notes: FMODE=3 (8 planes lowres won't fit the DMA slots at
; 16-bit fetch), so DDFSTOP moves to $b8 (5 fetches x 32 cc) and the
; bitplane pointers must be 64-bit aligned — canvas_data sits at
; offset 0 of its own data_c hunk (LoadSeg data is 8-byte aligned)
; and the plane size (10240) keeps every plane aligned.
;=====================================================================

	include	"src/custom.i"

	xdef	sc9_init
	xdef	sc9_update

	xref	songpos
	xref	songrow

PLSIZE	equ	40*256			; one contiguous bitplane

	section	code,code

;---------------------------------------------------------------------
sc9_init:
	; --- 256-color AGA palette: 8 banks x 32; per bank write the
	; high nibbles (LOCT=0), stash the low nibbles, then write them
	; with LOCT=1 ---
	lea	CANVAS_PAL(pc),a0
	moveq	#0,d2			; bank 0..7
.bank:	move.w	d2,d0
	ror.w	#3,d0			; bank -> BPLCON3 bits 15-13
	or.w	#$0c00,d0
	move.w	d0,BPLCON3(a6)
	lea	s9_lobuf,a3
	lea	COLOR00(a6),a1
	moveq	#32-1,d1
.col:	move.l	(a0)+,d0		; $00RRGGBB
	; low nibbles -> $0rgb (stashed)
	move.w	d0,d4
	and.w	#$000f,d4		; b lo
	move.w	d0,d5
	lsr.w	#4,d5
	and.w	#$00f0,d5		; g lo
	or.w	d5,d4
	move.l	d0,d5
	swap	d5			; d5.w = $00RR
	move.w	d5,d6
	and.w	#$000f,d6
	lsl.w	#8,d6			; r lo
	or.w	d6,d4
	move.w	d4,(a3)+
	; high nibbles -> $0RGB (written now)
	move.w	d0,d4
	lsr.w	#4,d4
	and.w	#$000f,d4		; b hi
	move.w	d0,d6
	lsr.w	#8,d6
	and.w	#$00f0,d6		; g hi
	or.w	d6,d4
	and.w	#$00f0,d5
	lsl.w	#4,d5			; r hi
	or.w	d5,d4
	move.w	d4,(a1)+
	dbf	d1,.col
	; LOCT pass: same 32 registers, low nibbles
	move.w	d2,d0
	ror.w	#3,d0
	or.w	#$0c00+$0200,d0		; +LOCT
	move.w	d0,BPLCON3(a6)
	lea	s9_lobuf,a3
	lea	COLOR00(a6),a1
	moveq	#32-1,d1
.lo:	move.w	(a3)+,(a1)+
	dbf	d1,.lo
	addq.w	#1,d2
	cmp.w	#8,d2
	blt	.bank
	move.w	#$0c00,BPLCON3(a6)

	; image color 0 (high nibbles) — the non-slam COLOR00 value for
	; the copper's per-frame write
	move.l	CANVAS_PAL(pc),d0
	move.w	d0,d4
	lsr.w	#4,d4
	and.w	#$000f,d4
	move.w	d0,d5
	lsr.w	#8,d5
	and.w	#$00f0,d5
	or.w	d5,d4
	swap	d0
	and.w	#$00f0,d0
	lsl.w	#4,d0
	or.w	d0,d4
	move.w	d4,s9_col0

	; --- bitplane pointers: 8 contiguous planes ---
	lea	cop9_bpl+2,a1
	move.l	#canvas_data,d0
	moveq	#8-1,d1
.bpl:	swap	d0
	move.w	d0,(a1)
	swap	d0
	move.w	d0,4(a1)
	add.l	#PLSIZE,d0
	addq.w	#8,a1
	dbf	d1,.bpl

	clr.w	s9_slam
	clr.w	s9_seen

	lea	cop_scene9,a0
	move.l	a0,COP1LC(a6)
	rts

;---------------------------------------------------------------------
sc9_update:
	; one 2-frame paper flash when the B-reprise hits (pos 26)
	cmp.w	#26,songpos
	bne.s	.armed
	tst.w	s9_seen
	bne.s	.armed
	st	s9_seen
	move.w	#2,s9_slam
.armed:
	move.w	#$0210,d0		; 8 planes on
	move.w	s9_col0,d1
	tst.w	s9_slam
	beq.s	.set
	subq.w	#1,s9_slam
	move.w	#$0200,d0		; planes off -> COLOR00 slab
	move.w	#$0fff,d1
.set:	move.w	d0,cop9_con0+2
	move.w	d1,cop9_col0+2
	rts

	include	"build/art/canvas.i"

;---------------------------------------------------------------------
	section	s9data,data_c
;---------------------------------------------------------------------
canvas_data:				; MUST stay at section offset 0:
	incbin	"build/art/canvas.bpl"	; FMODE=3 needs 8-byte-aligned
					; BPLxPT; the hunk base is 8-byte
					; aligned (LoadSeg), 10240/plane
					; keeps every plane aligned

cop_scene9:
	dc.w	$01fc,$0003		; FMODE: 64-bit fetch
	dc.w	$0092,$0038		; DDFSTRT
	dc.w	$0094,$00b8		; DDFSTOP: 5 fetches x 32 cc
	dc.w	$0102,$0000		; BPLCON1
	dc.w	$0104,$0024		; BPLCON2
	dc.w	$010c,$0011		; BPLCON4: base palette
	dc.w	$0108,$0000		; BPL1MOD: contiguous, exact fetch
	dc.w	$010a,$0000		; BPL2MOD
cop9_bpl:
	dc.w	$00e0,0,$00e2,0		; BPL1PT
	dc.w	$00e4,0,$00e6,0
	dc.w	$00e8,0,$00ea,0
	dc.w	$00ec,0,$00ee,0
	dc.w	$00f0,0,$00f2,0
	dc.w	$00f4,0,$00f6,0
	dc.w	$00f8,0,$00fa,0
	dc.w	$00fc,0,$00fe,0		; BPL8PT
cop9_col0:
	dc.w	$0180,$0000		; COLOR00 (bank 0 hi, poked)
cop9_con0:
	dc.w	$0100,$0210		; BPLCON0: 8 planes (BPU3)
	dc.w	$ffff,$fffe

;---------------------------------------------------------------------
	section	s9vars,bss
;---------------------------------------------------------------------
s9_lobuf:	ds.w	32
s9_col0:	ds.w	1
s9_slam:	ds.w	1
s9_seen:	ds.w	1
