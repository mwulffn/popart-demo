;=====================================================================
; scene2.asm — "EDITION OF EIGHT" (song pos 2-7)
;
; One 160x128 16-color print of the floppy, blitted 4x into a 2x2
; grid. Color is pure hardware repetition: 8 print-run palettes
; (4 hue runs + 4 inverted misprints) live in AGA color-table entries
; k*16..k*16+15; the copper rewrites BPLCON4's BPLAM field (XOR on the
; pixel index — the AGA palette-shift trick) twice per scanline
; (left|right cell) so each cell wears its own print run. NB: BPLCON3
; bank bits only redirect color WRITES, they never affect display —
; BPLAM is the display-side mechanism. Palettes rotate one cell per
; song position; on every kick one cell flashes inverted for 4 frames.
;
; Copper layout per line (fixed 16-byte stride, see s2_poke):
;   WAIT(line,$05) MOVE BPLCON4,<L> WAIT(line,$91) MOVE BPLCON4,<R>
;=====================================================================

	include	"src/custom.i"

	xdef	sc2_init
	xdef	sc2_update

	xref	waitblit
	xref	songpos
	xref	songrow

SCR_BPR	    equ	160		; 40 bytes * 4 planes, interleaved
CELLBYTES   equ	SCR_BPR*128	; one grid row of cells
BANKBITS    equ	$0c00		; BPLCON3 base (PF2OF default)

	section	code,code

;---------------------------------------------------------------------
sc2_init:
	; --- print the object 4 times (blitter, interleaved copy) ---
	bsr	waitblit
	move.l	#$09f00000,BLTCON0(a6)	; A->D copy
	move.l	#-1,BLTAFWM(a6)
	moveq	#0,d0
	move.w	d0,BLTAMOD(a6)
	move.w	#20,BLTDMOD(a6)		; dst is twice as wide
	lea	quad_offs(pc),a2
	moveq	#4-1,d7
.quad:	bsr	waitblit
	move.l	#floppy_data,BLTAPTH(a6)
	move.l	#s2_screen,d0
	add.l	(a2)+,d0
	move.l	d0,BLTDPTH(a6)
	move.w	#512<<6|10,BLTSIZE(a6)	; 128 rows * 4 planes, 160px
	dbf	d7,.quad

	; --- load the 8 print-run palettes into color entries 0-127:
	;     palette k -> entries k*16.. (bank k/2, half k&1) ---
	lea	floppy_pals(pc),a0
	moveq	#0,d2			; palette index k
.pal:	move.w	d2,d0
	lsr.w	#1,d0			; bank = k/2
	ror.w	#3,d0			; bank<<13
	or.w	#BANKBITS,d0
	move.w	d0,BPLCON3(a6)
	lea	COLOR00(a6),a1
	btst	#0,d2
	beq.s	.half
	lea	32(a1),a1		; odd palette -> COLOR16-31
.half:	moveq	#16-1,d1
.col:	move.w	(a0)+,(a1)+
	dbf	d1,.col
	addq.w	#1,d2
	cmp.w	#8,d2
	blt.s	.pal
	move.w	#BANKBITS,BPLCON3(a6)

	; --- bitplane pointers into the copper list ---
	lea	cop2_bpl+2,a1
	move.l	#s2_screen,d0
	moveq	#4-1,d1
.bpl:	swap	d0
	move.w	d0,(a1)			; high word
	swap	d0
	move.w	d0,4(a1)		; low word
	add.l	#40,d0			; next interleaved plane
	addq.w	#8,a1
	dbf	d1,.bpl

	; force full repoke + reset flash
	moveq	#-1,d0
	move.l	d0,s2_cache
	move.l	d0,s2_cache+4
	clr.w	s2_flash
	move.w	#-1,s2_beat

	lea	cop_scene2,a0
	move.l	a0,COP1LC(a6)
	rts

;---------------------------------------------------------------------
sc2_update:
	; rotation r = songpos-2, flash cell on each kick
	move.w	songpos,d3
	subq.w	#2,d3			; r = positions into the scene

	; kick detect: beat number = (pos*64+row)/8
	move.w	songpos,d0
	lsl.w	#6,d0
	add.w	songrow,d0
	lsr.w	#3,d0
	cmp.w	s2_beat,d0
	beq.s	.noflash
	move.w	d0,s2_beat
	move.w	d0,d1
	and.w	#3,d1
	move.w	d1,s2_flashcell
	move.w	#4,s2_flash		; frames of misprint left
.noflash:
	tst.w	s2_flash
	beq.s	.banks
	subq.w	#1,s2_flash
.banks:
	; per cell: bank = (cell + r) & 3, +4 if flashing this cell
	lea	s2_want(pc),a2
	moveq	#0,d2			; cell 0..3 (TL TR BL BR)
.cell:	move.w	d3,d0
	add.w	d2,d0
	and.w	#3,d0
	tst.w	s2_flash
	beq.s	.nf
	cmp.w	s2_flashcell,d2
	bne.s	.nf
	addq.w	#4,d0			; inverted bank
.nf:	ror.w	#4,d0			; BPLAM: palette k -> k<<12
	or.w	#$0011,d0		; default sprite palette MSBs
	move.w	d0,(a2)+
	addq.w	#1,d2
	cmp.w	#4,d2
	blt.s	.cell

	; repoke changed cells into the copper list
	lea	s2_want(pc),a2
	lea	s2_cache,a3
	moveq	#0,d2
.chk:	move.w	(a2)+,d0
	cmp.w	(a3),d0
	beq.s	.same
	move.w	d0,(a3)
	move.w	d2,d1
	bsr.s	s2_poke
.same:	addq.w	#2,a3
	addq.w	#1,d2
	cmp.w	#4,d2
	blt.s	.chk
	rts

;---------------------------------------------------------------------
; s2_poke — write BPLCON3 value d0 into all 128 line slots of cell d1
; (0 TL, 1 TR, 2 BL, 3 BR). Line stride 16 bytes; the $ffdf,$fffe
; crossing at display line 212 shifts everything after it by 4 bytes.
;---------------------------------------------------------------------
s2_poke:
	lea	cop2_lines,a0
	moveq	#0,d4			; first line of the cell band
	btst	#1,d1
	beq.s	.top
	move.w	#128,d4
.top:	moveq	#6,d5			; byte offset of L slot in a line
	btst	#0,d1
	beq.s	.left
	moveq	#14,d5			; R slot
.left:	move.w	d4,d6
	add.w	d6,d6
	add.w	d6,d6
	add.w	d6,d6
	add.w	d6,d6			; line*16
	lea	(a0,d6.w),a0
	add.w	d5,a0
	cmp.w	#212,d4			; band entirely below the crossing?
	blt.s	.mixed
	addq.w	#4,a0
	moveq	#128-1,d6
.fast:	move.w	d0,(a0)
	lea	16(a0),a0
	dbf	d6,.fast
	rts
.mixed:	; top band (0-127) never crosses; bottom band from 128 does
	moveq	#128-1,d6
	move.w	d4,d5
.mix:	cmp.w	#212,d5
	bne.s	.put
	addq.w	#4,a0			; skip the $ffdf wait pair once
.put:	move.w	d0,(a0)
	lea	16(a0),a0
	addq.w	#1,d5
	dbf	d6,.mix
	rts

quad_offs:
	dc.l	0,20,CELLBYTES,CELLBYTES+20

s2_want:	ds.w	4		; wanted BPLCON3 per cell (scratch)

	include	"build/art/floppypal.i"

;---------------------------------------------------------------------
	section	s2data,data_c
;---------------------------------------------------------------------
floppy_data:
	incbin	"build/art/floppy.bpl"

cop_scene2:
	dc.w	$01fc,$0000		; FMODE
	dc.w	$0102,$0000		; BPLCON1
	dc.w	$0104,$0024		; BPLCON2
	dc.w	$0108,$0078		; BPL1MOD: 3*40 (interleaved)
	dc.w	$010a,$0078		; BPL2MOD
cop2_bpl:
	dc.w	$00e0,0,$00e2,0		; BPL1PT
	dc.w	$00e4,0,$00e6,0		; BPL2PT
	dc.w	$00e8,0,$00ea,0		; BPL3PT
	dc.w	$00ec,0,$00ee,0		; BPL4PT
	dc.w	$0100,$4200		; BPLCON0: 4 planes

cop2_lines:
LINE	set	$2c
	rept	212			; display lines 0-211
	dc.w	(LINE&$ff)<<8|$05,$fffe
	dc.w	$010c,$0011
	dc.w	(LINE&$ff)<<8|$91,$fffe
	dc.w	$010c,$0011
LINE	set	LINE+1
	endr
	dc.w	$ffdf,$fffe		; cross into V >= 256
	rept	44			; display lines 212-255
	dc.w	(LINE&$ff)<<8|$05,$fffe
	dc.w	$010c,$0011
	dc.w	(LINE&$ff)<<8|$91,$fffe
	dc.w	$010c,$0011
LINE	set	LINE+1
	endr
	dc.w	$ffff,$fffe

;---------------------------------------------------------------------
	section	s2bss,bss_c
;---------------------------------------------------------------------
s2_screen:	ds.b	40960

	section	s2vars,bss
s2_cache:	ds.w	4		; last poked BPLCON3 per cell
s2_flash:	ds.w	1
s2_flashcell:	ds.w	1
s2_beat:	ds.w	1
