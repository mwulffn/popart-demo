;=====================================================================
; scene4.asm — "WHAAM!" (song pos 16-21)
;
; Static Lichtenstein explosion panel (320x256x5, interleaved). On
; every snare a comic burst bob (POP!/BANG!/ZAP!/WHAAM!) is cookie-cut
; onto the panel at one of 8 word-aligned positions; each stamp lives
; 12 frames, then its rect is restored from the pristine panel. On
; every kick: 2-frame white slam (planes off) + decaying horizontal
; shake (BPLCON1).
;
; Blits are word-aligned (no shifter), masks pre-expanded to all 5
; planes, so a stamp is ONE cookie-cut blit: D = (A&B) | (~A&C).
;=====================================================================

	include	"src/custom.i"
	include	"build/art/bobs.i"

	xdef	sc4_init
	xdef	sc4_update

	xref	waitblit
	xref	songpos
	xref	songrow

NSLOTS	equ	4			; concurrent stamps

	section	code,code

;---------------------------------------------------------------------
sc4_init:
	; copy pristine panel -> working screen (2 blits, height limit)
	bsr	waitblit
	move.l	#$09f00000,BLTCON0(a6)
	move.l	#-1,BLTAFWM(a6)
	moveq	#0,d0
	move.w	d0,BLTAMOD(a6)
	move.w	d0,BLTDMOD(a6)
	move.l	#comic_data,BLTAPTH(a6)
	move.l	#s4_screen,BLTDPTH(a6)
	move.w	#640<<6|20,BLTSIZE(a6)	; first 128 display rows (x5)
	bsr	waitblit
	move.l	#comic_data+640*40,BLTAPTH(a6)
	move.l	#s4_screen+640*40,BLTDPTH(a6)
	move.w	#640<<6|20,BLTSIZE(a6)

	; palette (32 colors into bank 0) — BPLCON4 reset to palette 0
	move.w	#$0c00,BPLCON3(a6)
	lea	COMIC_PAL(pc),a0
	lea	COLOR00(a6),a1
	moveq	#32-1,d1
.col:	move.w	(a0)+,(a1)+
	dbf	d1,.col

	; bitplane pointers (5 planes, interleaved)
	lea	cop4_bpl+2,a1
	move.l	#s4_screen,d0
	moveq	#5-1,d1
.bpl:	swap	d0
	move.w	d0,(a1)
	swap	d0
	move.w	d0,4(a1)
	add.l	#40,d0
	addq.w	#8,a1
	dbf	d1,.bpl

	; reset stamp slots / beat trackers
	lea	s4_ttl,a0
	moveq	#NSLOTS-1,d0
.slot:	clr.w	(a0)+
	dbf	d0,.slot
	move.w	#-1,s4_snare
	move.w	#-1,s4_kick
	move.w	#99,s4_kickage
	clr.w	s4_stampn

	lea	cop_scene4,a0
	move.l	a0,COP1LC(a6)
	rts

;---------------------------------------------------------------------
sc4_update:
	; --- age stamps, restore expired rects ---
	lea	s4_ttl,a2
	lea	s4_off,a3
	moveq	#0,d5			; slot
.age:	move.w	(a2),d0
	beq.s	.next
	subq.w	#1,d0
	move.w	d0,(a2)
	bne.s	.next
	move.l	(a3),d0			; restore this rect
	bsr	s4_restore
.next:	addq.w	#2,a2
	addq.w	#4,a3
	addq.w	#1,d5
	cmp.w	#NSLOTS,d5
	blt.s	.age

	; --- beat bookkeeping ---
	move.w	songpos,d0
	lsl.w	#6,d0
	add.w	songrow,d0		; absolute row b
	move.w	d0,d1
	and.w	#7,d1

	addq.w	#1,s4_kickage

	cmp.w	#4,d1			; snare = row%8 == 4
	bne.s	.nosnare
	move.w	d0,d2
	lsr.w	#3,d2
	cmp.w	s4_snare,d2
	beq.s	.nosnare
	move.w	d2,s4_snare
	bsr	s4_stamp
.nosnare:
	tst.w	d1			; kick = row%8 == 0
	bne.s	.nokick
	move.w	d0,d2
	lsr.w	#3,d2
	cmp.w	s4_kick,d2
	beq.s	.nokick
	move.w	d2,s4_kick
	clr.w	s4_kickage
.nokick:

	; --- white slam: first 2 frames after a kick ---
	move.w	#$5200,d0		; 5 planes on
	move.w	#COL_PAPER,d1
	cmp.w	#2,s4_kickage
	bge.s	.noslam
	move.w	#$0200,d0		; planes off -> COLOR00 slab
	move.w	#$0fff,d1
.noslam:
	move.w	d0,cop4_con0+2
	move.w	d1,cop4_col0+2

	; --- decaying horizontal shake ---
	moveq	#0,d0
	move.w	s4_kickage,d1
	cmp.w	#6,d1
	bge.s	.noshake
	lea	.shaketab(pc),a0
	add.w	d1,d1
	move.w	(a0,d1.w),d0
.noshake:
	move.w	d0,cop4_con1+2
	rts

.shaketab:
	dc.w	$0088,$00cc,$0044,$00ee,$0022,$0000

;---------------------------------------------------------------------
; s4_stamp — cookie-cut the next burst at the next position
;---------------------------------------------------------------------
s4_stamp:
	move.w	s4_stampn,d3
	addq.w	#1,s4_stampn

	; slot = n & 3; if still alive, restore its rect first
	move.w	d3,d5
	and.w	#NSLOTS-1,d5
	move.w	d5,d0
	add.w	d0,d0
	lea	s4_ttl,a2
	tst.w	(a2,d0.w)
	beq.s	.free
	lsl.w	#1,d0
	lea	s4_off,a3
	move.l	(a3,d0.w),d0
	bsr	s4_restore
.free:
	; position offset (byte offset into screen) from table
	move.w	d3,d0
	and.w	#7,d0
	add.w	d0,d0
	add.w	d0,d0
	lea	s4_pos(pc),a0
	move.l	(a0,d0.w),d4		; dest offset

	; record slot
	move.w	d5,d0
	add.w	d0,d0
	lea	s4_ttl,a2
	move.w	#12,(a2,d0.w)
	lsl.w	#1,d0
	lea	s4_off,a3
	move.l	d4,(a3,d0.w)

	; bob n&3
	move.w	d3,d0
	and.w	#3,d0
	mulu	#BOB_BYTES,d0

	; cookie-cut: A=mask, B=bob, C=D=screen
	bsr	waitblit
	move.l	#$0fca0000,BLTCON0(a6)	; USEA/B/C/D, LF=$ca
	move.l	#-1,BLTAFWM(a6)
	lea	bobs_msk,a0
	add.l	d0,a0
	move.l	a0,BLTAPTH(a6)
	lea	bobs_data,a0
	add.l	d0,a0
	move.l	a0,BLTBPTH(a6)
	move.l	#s4_screen,a0
	add.l	d4,a0
	move.l	a0,BLTCPTH(a6)
	move.l	a0,BLTDPTH(a6)
	moveq	#0,d0
	move.w	d0,BLTAMOD(a6)
	move.w	d0,BLTBMOD(a6)
	move.w	#40-BOB_BPR,BLTCMOD(a6)
	move.w	#40-BOB_BPR,BLTDMOD(a6)
	move.w	#320<<6|BOB_BPR/2,BLTSIZE(a6)	; 64 rows x 5 planes
	rts

;---------------------------------------------------------------------
; s4_restore — copy pristine panel rect back. d0 = byte offset
;---------------------------------------------------------------------
s4_restore:
	bsr	waitblit
	move.l	#$09f00000,BLTCON0(a6)
	move.l	#-1,BLTAFWM(a6)
	lea	comic_data,a0
	add.l	d0,a0
	move.l	a0,BLTAPTH(a6)
	lea	s4_screen,a0
	add.l	d0,a0
	move.l	a0,BLTDPTH(a6)
	move.w	#40-BOB_BPR,BLTAMOD(a6)
	move.w	#40-BOB_BPR,BLTDMOD(a6)
	move.w	#320<<6|BOB_BPR/2,BLTSIZE(a6)
	rts

; 8 stamp positions, word-aligned, as byte offsets into the interleaved
; screen: offset = y*200 + (x/8). Cells of a 3x3 grid (center-first
; order) — deliberately NON-overlapping: an expiring stamp restores its
; whole rect from the pristine panel, so overlap would erase chunks of
; younger stamps.
; byte offsets must be EVEN (blitter word addressing): x in {16,112,208}
s4_pos:
	dc.l	90*200+14,  8*200+2,   178*200+26, 8*200+26
	dc.l	178*200+2,  8*200+14,  90*200+26,  90*200+2

	include	"build/art/comic.i"

;---------------------------------------------------------------------
	section	s4data,data_c
;---------------------------------------------------------------------
comic_data:
	incbin	"build/art/comic.bpl"
bobs_data:
	incbin	"build/art/bobs.bpl"
bobs_msk:
	incbin	"build/art/bobs.msk"

cop_scene4:
	dc.w	$01fc,$0000		; FMODE
cop4_con1:
	dc.w	$0102,$0000		; BPLCON1 (shake)
	dc.w	$0104,$0024		; BPLCON2
	dc.w	$010c,$0011		; BPLCON4: palette 0
	dc.w	$0108,$00a0		; BPL1MOD: 4*40 interleaved
	dc.w	$010a,$00a0		; BPL2MOD
cop4_bpl:
	dc.w	$00e0,0,$00e2,0
	dc.w	$00e4,0,$00e6,0
	dc.w	$00e8,0,$00ea,0
	dc.w	$00ec,0,$00ee,0
	dc.w	$00f0,0,$00f2,0
cop4_col0:
	dc.w	$0180,COL_PAPER
cop4_con0:
	dc.w	$0100,$5200		; BPLCON0: 5 planes
	dc.w	$ffff,$fffe

;---------------------------------------------------------------------
	section	s4bss,bss_c
;---------------------------------------------------------------------
s4_screen:	ds.b	64000

	section	s4vars,bss
s4_ttl:		ds.w	NSLOTS
s4_off:		ds.l	NSLOTS
s4_snare:	ds.w	1
s4_kick:	ds.w	1
s4_kickage:	ds.w	1
s4_stampn:	ds.w	1
