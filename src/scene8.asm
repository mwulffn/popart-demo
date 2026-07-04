;=====================================================================
; scene8.asm — "BRILLO BOX" (song pos 24-27): real-time vector floppy
;
; Flat-shaded 3D floppy (box body + shutter/label decals on the front
; face), tumbling. Classic blitter vector pipeline in a 192x176 region
; centered on screen:
;   per visible face: clear temp plane -> one-dot fill-lines (LF $4a,
;   SING) -> blitter inclusive fill (descending) -> OR into the screen
;   planes of the face's color bits (all colors use <=2 planes).
;   Afterwards every visible edge is drawn (LF $ca) into an outline
;   plane, OR'd into ALL 4 planes at (0,0) and (+1,+1): thick ink
;   cartoon outline (color 15) over any fill. No shading — Pop Art
;   fills flat.
; Face colors rotate one palette step per downbeat (the print queue
; advancing across the object); tumble speeds up at the B-reprise
; (pos 26).
;
; Blitter line recipe: HRM line mode + Wrobel's corrections
; (markwrobel.dk letter 12): BLTAPTL = 4dy-2dx, SIGN ($40) when
; 2dy >= dx, SING = $02, octant code in BLTCON1 bits 4:2.
;=====================================================================

	include	"src/custom.i"

	xdef	sc8_init
	xdef	sc8_update

	xref	waitblit
	xref	songpos
	xref	songrow

REGBPR	equ	24			; region: 192x176 px, one plane
REGH	equ	176
REGPL	equ	REGBPR*REGH
SCRPL	equ	40*256			; screen plane (contiguous 4bpl)
REGOFF	equ	40*40+8			; region origin on screen (64,40)
ZDIST	equ	400
PROJ	equ	384
NVERT	equ	16
NFACE	equ	8

	section	code,code

;---------------------------------------------------------------------
sc8_init:
	; palette (bank 0): pop colors on <=2-bit indices, 15 = ink
	move.w	#$0c00,BPLCON3(a6)
	lea	s8_pal(pc),a0
	lea	COLOR00(a6),a1
	moveq	#16-1,d1
.col:	move.w	(a0)+,(a1)+
	dbf	d1,.col

	clr.w	s8_ax
	clr.w	s8_ay
	clr.w	s8_frame
	move.w	#-1,s8_beat
	clr.w	s8_colrot

	; clear both screen buffers in one blit (81920 = 1024 rows x 20w)
	bsr	waitblit
	move.l	#$01000000,BLTCON0(a6)	; USED only, LF=0 -> zeros
	move.l	#s8_scr,BLTDPTH(a6)
	move.w	#0,BLTDMOD(a6)
	move.w	#(1024<<6)&$ffc0|20,BLTSIZE(a6)	; h=1024 encodes as 0

	lea	cop_scene8,a0
	move.l	a0,COP1LC(a6)
	rts

;---------------------------------------------------------------------
sc8_update:
	addq.w	#1,s8_frame

	; --- music: color rotation per downbeat, tumble speed ---
	move.w	songpos,d0
	lsl.w	#6,d0
	add.w	songrow,d0
	lsr.w	#3,d0
	cmp.w	s8_beat,d0
	beq.s	.nobeat
	move.w	d0,s8_beat
	addq.w	#1,s8_colrot
.nobeat:
	moveq	#2,d0
	moveq	#3,d1
	cmp.w	#26,songpos		; B-reprise: faster tumble
	blt.s	.slow
	moveq	#3,d0
	moveq	#5,d1
.slow:	add.w	d0,s8_ax
	add.w	d1,s8_ay
	ifd	STATICTEST
	move.w	#16,s8_ax		; fixed 3/4 pose for edge debug
	move.w	#40,s8_ay
	endc

	; --- rotation matrix (rotX(ax) then rotY(ay)), 8.8 in vars ---
	; x' =  x*c2 + y*(s1*s2) + z*(c1*s2)
	; y' =         y*c1      - z*s1
	; z' = -x*s2 + y*(s1*c2) + z*(c1*c2)
	lea	sinw(pc),a0
	move.w	s8_ax,d0
	and.w	#255,d0
	add.w	d0,d0
	move.w	(a0,d0.w),d5		; s1
	add.w	#128,d0
	and.w	#511,d0
	move.w	(a0,d0.w),d6		; c1
	move.w	s8_ay,d0
	and.w	#255,d0
	add.w	d0,d0
	move.w	(a0,d0.w),d3		; s2
	add.w	#128,d0
	and.w	#511,d0
	move.w	(a0,d0.w),d4		; c2

	move.w	d4,s8_m00
	move.w	d5,d0
	muls	d3,d0
	asr.l	#8,d0
	move.w	d0,s8_m01		; s1*s2
	move.w	d6,d0
	muls	d3,d0
	asr.l	#8,d0
	move.w	d0,s8_m02		; c1*s2
	move.w	d6,s8_m11
	move.w	d5,d0
	neg.w	d0
	move.w	d0,s8_m12		; -s1
	move.w	d3,d0
	neg.w	d0
	move.w	d0,s8_m20		; -s2
	move.w	d5,d0
	muls	d4,d0
	asr.l	#8,d0
	move.w	d0,s8_m21		; s1*c2
	move.w	d6,d0
	muls	d4,d0
	asr.l	#8,d0
	move.w	d0,s8_m22		; c1*c2

	; --- rotate + project all vertices -> s8_proj (sx,sy words) ---
	lea	s8_verts(pc),a0
	lea	s8_proj,a1
	moveq	#NVERT-1,d7
.vert:	movem.w	(a0)+,d0-d2		; x y z (model)
	; x'
	move.w	d0,d3
	muls	s8_m00,d3
	move.w	d1,d4
	muls	s8_m01,d4
	add.l	d4,d3
	move.w	d2,d4
	muls	s8_m02,d4
	add.l	d4,d3
	asr.l	#8,d3			; x'
	; y'
	move.w	d1,d4
	muls	s8_m11,d4
	move.w	d2,d5
	muls	s8_m12,d5
	add.l	d5,d4
	asr.l	#8,d4			; y'
	; z'
	move.w	d0,d5
	muls	s8_m20,d5
	move.w	d1,d6
	muls	s8_m21,d6
	add.l	d6,d5
	move.w	d2,d6
	muls	s8_m22,d6
	add.l	d6,d5
	asr.l	#8,d5			; z'
	; project — results CLAMPED to the region: every downstream
	; write address (CPU edge dots, blitter lines) is derived from
	; these, and one bad vertex (e.g. divs overflow garbage) would
	; otherwise wild-write through low chip RAM (learned the hard
	; way: trashed the vector table -> Line-F guru)
	add.w	#ZDIST,d5
	move.w	d3,d0
	muls	#PROJ,d0
	divs	d5,d0
	add.w	#96,d0
	bge.s	.xlo
	moveq	#0,d0
.xlo:	cmp.w	#191,d0
	ble.s	.xok
	move.w	#191,d0
.xok:	move.w	d0,(a1)+		; sx 0..191
	move.w	d4,d0
	muls	#PROJ,d0
	divs	d5,d0
	add.w	#88,d0
	bge.s	.ylo
	moveq	#0,d0
.ylo:	cmp.w	#175,d0
	ble.s	.yok
	move.w	#175,d0
.yok:	move.w	d0,(a1)+		; sy 0..175
	dbf	d7,.vert

	; --- pick + clear back buffer region (4 planes) ---
	move.w	s8_frame,d0
	and.w	#1,d0
	mulu	#SCRPL*4,d0
	add.l	#s8_scr,d0
	move.l	d0,s8_back
	add.l	#REGOFF,d0
	moveq	#4-1,d7
.clrp:	bsr	waitblit
	move.l	#$01000000,BLTCON0(a6)
	move.l	d0,BLTDPTH(a6)
	move.w	#40-REGBPR,BLTDMOD(a6)
	move.w	#(REGH<<6)!(REGBPR/2),BLTSIZE(a6)
	add.l	#SCRPL,d0
	dbf	d7,.clrp

	; --- faces: visibility, fill, remember for the outline pass ---
	clr.w	s8_nvis
	lea	s8_faces(pc),a5
	moveq	#0,d7			; face number
.face:	bsr	s8_doface
	lea	6(a5),a5
	addq.w	#1,d7
	cmp.w	#NFACE,d7
	blt.s	.face
.skipfaces:

	; --- outline: all visible edges -> s8_outl, then 8 OR blits ---
	bsr	waitblit
	move.l	#$01000000,BLTCON0(a6)
	move.l	#s8_outl,BLTDPTH(a6)
	move.w	#0,BLTDMOD(a6)
	move.w	#(REGH<<6)!(REGBPR/2),BLTSIZE(a6)
	bsr	waitblit		; CPU draws into s8_outl next


	move.w	s8_nvis,d7
	beq.s	.nool
	subq.w	#1,d7
	lea	s8_vis,a4
.oface:	move.l	(a4)+,a5
	moveq	#0,d6			; edge 0..3
.oedge:	bsr	s8_edgexy		; d0-d3 = edge d6 of face a5
	movem.l	d6-d7/a4,-(sp)
	bsr	s8_cpuline
	movem.l	(sp)+,d6-d7/a4
	addq.w	#1,d6
	cmp.w	#4,d6
	blt.s	.oedge
	dbf	d7,.oface
.nool:
	; OR outline into all 4 planes, twice: (0,0) and (+1,+1)
	moveq	#0,d5			; pass 0
.opass:	move.l	s8_back,d0
	add.l	#REGOFF,d0
	tst.w	d5
	beq.s	.o0
	add.l	#40,d0			; +1 row
.o0:	moveq	#4-1,d7
.oplane:
	bsr	waitblit
	move.w	d5,d1
	ror.w	#4,d1			; A shift = +1 px on pass 1
	or.w	#$0bfa,d1		; A|C -> D (LF $fa; $fc would be A|B!)
	move.w	d1,BLTCON0(a6)
	move.w	#0,BLTCON1(a6)
	move.l	#-1,BLTAFWM(a6)
	move.l	#s8_outl,BLTAPTH(a6)
	move.l	d0,BLTCPTH(a6)
	move.l	d0,BLTDPTH(a6)
	move.w	#0,BLTAMOD(a6)
	move.w	#40-REGBPR,BLTCMOD(a6)
	move.w	#40-REGBPR,BLTDMOD(a6)
	move.w	#(REGH<<6)!(REGBPR/2),BLTSIZE(a6)
	add.l	#SCRPL,d0
	dbf	d7,.oplane
	addq.w	#1,d5
	cmp.w	#2,d5
	blt.s	.opass

	; --- flip: point copper at the freshly drawn buffer ---
	move.l	s8_back,d0
	lea	cop8_bpl+2,a1
	moveq	#4-1,d1
.bpl:	swap	d0
	move.w	d0,(a1)
	swap	d0
	move.w	d0,4(a1)
	add.l	#SCRPL,d0
	addq.w	#8,a1
	dbf	d1,.bpl
	rts

;---------------------------------------------------------------------
; s8_doface — cull, fill, record face a5 (d7 = face number, preserved)
; face entry: 4 vertex index bytes, color byte, pad
;---------------------------------------------------------------------
s8_doface:
	movem.l	d6-d7/a4,-(sp)
	; fetch projected corners of the first 3 verts for the cull
	lea	s8_proj,a4
	moveq	#0,d0
	move.b	(a5),d0
	lsl.w	#2,d0
	movem.w	(a4,d0.w),d0-d1		; p0
	moveq	#0,d2
	move.b	1(a5),d2
	lsl.w	#2,d2
	movem.w	(a4,d2.w),d2-d3		; p1
	moveq	#0,d4
	move.b	2(a5),d4
	lsl.w	#2,d4
	movem.w	(a4,d4.w),d4-d5		; p2
	; cross = (x1-x0)(y2-y0) - (y1-y0)(x2-x0); screen y grows DOWN,
	; outward faces wind clockwise on screen -> visible if cross > 0
	; (<= also culls edge-on degenerates, e.g. grazing decals)
	sub.w	d0,d2
	sub.w	d1,d3
	sub.w	d0,d4
	sub.w	d1,d5
	muls	d5,d2
	muls	d4,d3
	sub.l	d3,d2
	cmp.l	#800,d2			; cull backfaces AND slivers —
	ble	.out			; near-edge-on faces leave stray
					; outline hairs otherwise
	; decals (faces 6+) ride the front face: only show them while
	; the front is healthily face-on, else they degenerate to long
	; thin slivers whose outlines read as stray hairs
	tst.w	d7
	bne.s	.notfront
	clr.w	s8_frontok
	cmp.l	#2500,d2
	ble.s	.notfront
	move.w	#1,s8_frontok
.notfront:
	cmp.w	#6,d7
	blt.s	.body
	tst.w	s8_frontok
	beq	.out
.body:

	; record for outline pass
	move.w	s8_nvis,d0
	lea	s8_vis,a4
	move.l	a5,(a4,d0.w*4)
	addq.w	#1,s8_nvis

	; clear temp plane
	bsr	waitblit
	move.l	#$01000000,BLTCON0(a6)
	move.l	#s8_temp,BLTDPTH(a6)
	move.w	#0,BLTDMOD(a6)
	move.w	#(REGH<<6)!(REGBPR/2),BLTSIZE(a6)

	bsr	waitblit		; CPU writes temp next — let the
					; clear finish first
	; four fill edges, CPU-walked, half-open [y0,y1): exactly one
	; XOR dot per crossed row, so pass-through vertices keep their
	; toggle (blitter SING lines double-plot shared vertices and
	; the XOR cancels -> fill bleed)
	moveq	#0,d6
.edge:	bsr	s8_edgexy
	movem.l	d6-d7,-(sp)
	bsr	s8_filledge
	movem.l	(sp)+,d6-d7
	addq.w	#1,d6
	cmp.w	#4,d6
	blt.s	.edge

	; inclusive fill, descending
	bsr	waitblit
	move.l	#$09f0000a,BLTCON0(a6)	; A->D, DESC+IFE
	move.l	#-1,BLTAFWM(a6)
	move.l	#s8_temp+REGPL-2,BLTAPTH(a6)
	move.l	#s8_temp+REGPL-2,BLTDPTH(a6)
	move.w	#0,BLTAMOD(a6)
	move.w	#0,BLTDMOD(a6)
	move.w	#(REGH<<6)!(REGBPR/2),BLTSIZE(a6)

	; face color: $80|slot rotates through coltab, else literal
	moveq	#0,d4
	move.b	4(a5),d4
	bpl.s	.lit
	and.w	#$7f,d4
	add.w	s8_colrot,d4
	; slot mod 6
.mod6:	cmp.w	#6,d4
	blt.s	.gotslot
	subq.w	#6,d4
	bra.s	.mod6
.gotslot:
	lea	s8_coltab(pc),a4
	move.b	(a4,d4.w),d4
.lit:
	; composite temp into the screen planes. Box faces never overlap
	; (convex), so set-bits OR suffices; decals sit ON the front face
	; and must REPLACE its bits: clear-bit planes get D = ~A & C
	; (face entry pad byte = 1 marks replace mode).
	move.l	s8_back,d0
	add.l	#REGOFF,d0
	moveq	#4-1,d7
.plane:	lsr.w	#1,d4
	bcc.s	.bitclr
	bsr	waitblit
	move.w	#$0bfa,BLTCON0(a6)	; A|C -> D
	bra.s	.doblit
.bitclr:
	tst.b	5(a5)			; replace mode?
	beq.s	.nobit
	bsr	waitblit
	move.w	#$0b0a,BLTCON0(a6)	; ~A&C -> D (punch the hole)
.doblit:
	move.w	#0,BLTCON1(a6)
	move.l	#-1,BLTAFWM(a6)
	move.l	#s8_temp,BLTAPTH(a6)
	move.l	d0,BLTCPTH(a6)
	move.l	d0,BLTDPTH(a6)
	move.w	#0,BLTAMOD(a6)
	move.w	#40-REGBPR,BLTCMOD(a6)
	move.w	#40-REGBPR,BLTDMOD(a6)
	move.w	#(REGH<<6)!(REGBPR/2),BLTSIZE(a6)
.nobit:	add.l	#SCRPL,d0
	dbf	d7,.plane
.out:	movem.l	(sp)+,d6-d7/a4
	rts

;---------------------------------------------------------------------
; s8_filledge — XOR one dot per row into s8_temp along edge d0-d3,
; half-open [y0,y1). Horizontal edges are naturally skipped (dy=0).
; trashes d0-d5/a0-a1
;---------------------------------------------------------------------
s8_filledge:
	cmp.w	d1,d3
	beq.s	.done			; horizontal
	bgt.s	.down
	exg	d0,d2			; orient top -> bottom
	exg	d1,d3
.down:	sub.w	d1,d3			; dy > 0
	sub.w	d0,d2			; dx
	ext.l	d2
	lsl.l	#8,d2
	lsl.l	#8,d2			; dx<<16
	ext.l	d3
	divs.l	d3,d2			; slope 16.16 (68020)
	swap	d0
	clr.w	d0
	add.l	#$8000,d0		; x 16.16, +0.5 for rounding
	lea	s8_temp,a0
	move.w	d1,d4
	mulu	#REGBPR,d4
	add.l	d4,a0
	lea	s8_bittab(pc),a1
	subq.w	#1,d3
.row:	move.l	d0,d4
	swap	d4			; xi
	move.w	d4,d5
	lsr.w	#3,d5
	and.w	#7,d4
	move.b	(a1,d4.w),d1
	eor.b	d1,(a0,d5.w)
	add.l	d2,d0
	lea	REGBPR(a0),a0
	dbf	d3,.row
.done:	rts

s8_bittab:
	dc.b	$80,$40,$20,$10,$08,$04,$02,$01

;---------------------------------------------------------------------
; s8_cpuline — Bresenham into s8_outl (stride REGBPR), d0-d3 = line.
; Replaces blitter line mode for outlines: arbitrary-start blitter
; lines rendered unreliably here (dashed/truncated segments) and the
; CPU cost of <=12 short edges is negligible. Coords are pre-clamped
; to the region by the projection. Trashes d0-d7/a0-a1.
;---------------------------------------------------------------------
s8_cpuline:
	sub.w	d0,d2			; dx
	sub.w	d1,d3			; dy
	lea	s8_outl,a0
	mulu	#REGBPR,d1
	add.l	d1,a0
	move.w	d0,d1
	lsr.w	#3,d1
	add.w	d1,a0			; current byte
	and.w	#7,d0
	lea	s8_bittab(pc),a1
	move.b	(a1,d0.w),d1		; current bit mask
	moveq	#1,d4			; x direction
	tst.w	d2
	bge.s	.dxp
	neg.w	d2
	moveq	#-1,d4
.dxp:	move.w	#REGBPR,d5		; y step (bytes)
	tst.w	d3
	bge.s	.dyp
	neg.w	d3
	move.w	#-REGBPR,d5
.dyp:	cmp.w	d3,d2
	blt.s	.ymaj

	move.w	d2,d6			; --- x major ---
	lsr.w	#1,d6
	move.w	d2,d7
.xl:	or.b	d1,(a0)
	sub.w	d3,d6
	bge.s	.xnoy
	add.w	d2,d6
	add.w	d5,a0
.xnoy:	tst.w	d4
	bmi.s	.xleft
	ror.b	#1,d1
	bcc.s	.xnext
	addq.w	#1,a0
	bra.s	.xnext
.xleft:	rol.b	#1,d1
	bcc.s	.xnext
	subq.w	#1,a0
.xnext:	dbf	d7,.xl
	rts

.ymaj:	move.w	d3,d6			; --- y major ---
	lsr.w	#1,d6
	move.w	d3,d7
.yl:	or.b	d1,(a0)
	add.w	d5,a0
	sub.w	d2,d6
	bge.s	.ynox
	add.w	d3,d6
	tst.w	d4
	bmi.s	.yleft
	ror.b	#1,d1
	bcc.s	.ynox
	addq.w	#1,a0
	bra.s	.ynox
.yleft:	rol.b	#1,d1
	bcc.s	.ynox
	subq.w	#1,a0
.ynox:	dbf	d7,.yl
	rts

;---------------------------------------------------------------------
; s8_edgexy — d0-d3 = screen coords of edge d6 (0-3) of face a5
;---------------------------------------------------------------------
s8_edgexy:				; NB must not touch a4 (callers)
	lea	s8_proj,a0
	moveq	#0,d0
	move.b	(a5,d6.w),d0
	lsl.w	#2,d0
	movem.w	(a0,d0.w),d0-d1
	move.w	d6,d2
	addq.w	#1,d2
	and.w	#3,d2
	moveq	#0,d3
	move.b	(a5,d2.w),d3
	lsl.w	#2,d3
	movem.w	(a0,d3.w),d2-d3
	rts

;---------------------------------------------------------------------

s8_pal:
	dc.w	$0fed,$0f0c,$0fd0,$0f60,$00ce,$095f,$0e11,$0112
	dc.w	$08e0,$0f21,$0ffb,$0112,$0112,$0112,$0112,$0112

; rotating face colors: mag yel cyan grn org red (<=2 bits each)
s8_coltab:
	dc.b	1,2,4,8,3,6
	even

s8_verts:
	; floppy body: 100 x 100 x 12 model units
	dc.w	-50,-50,-6,  50,-50,-6,  50,50,-6,  -50,50,-6
	dc.w	-50,-50, 6,  50,-50, 6,  50,50, 6,  -50,50, 6
	; shutter + label: decals on the front face (z=-6)
	dc.w	-12,-46,-6,  34,-46,-6,  34,-12,-6,  -12,-12,-6
	dc.w	-36,  2,-6,  36,  2,-6,  36, 46,-6,  -36, 46,-6

; faces: 4 vertex indices, color ($80|slot = rotating, else literal)
s8_faces:
	dc.b	0,1,2,3,   $80,0	; front
	dc.b	5,4,7,6,   $81,0	; back
	dc.b	4,5,1,0,   $82,0	; top
	dc.b	3,2,6,7,   $83,0	; bottom
	dc.b	4,0,3,7,   $84,0	; left
	dc.b	1,5,6,2,   $85,0	; right
	dc.b	8,9,10,11, 7,1		; shutter: ink (replace mode)
	dc.b	12,13,14,15, 10,1	; label: paper-white (replace)

	include	"build/art/sinw.i"

;---------------------------------------------------------------------
	section	s8data,data_c
;---------------------------------------------------------------------
cop_scene8:
	dc.w	$01fc,$0000
	dc.w	$0092,$0038
	dc.w	$0094,$00d0
	dc.w	$0102,$0000
	dc.w	$0104,$0024
	dc.w	$010c,$0011
	dc.w	$0108,$0000
	dc.w	$010a,$0000
cop8_bpl:
	dc.w	$00e0,0,$00e2,0
	dc.w	$00e4,0,$00e6,0
	dc.w	$00e8,0,$00ea,0
	dc.w	$00ec,0,$00ee,0
	dc.w	$0180,COL_PAPER
	dc.w	$0100,$4200		; 4 planes
	dc.w	$ffff,$fffe

;---------------------------------------------------------------------
	section	s8bss,bss_c
;---------------------------------------------------------------------
s8_scr:		ds.b	SCRPL*4*2	; two 4-plane contiguous buffers
s8_temp:	ds.b	REGPL		; polygon fill plane
s8_outl:	ds.b	REGPL		; outline plane

	section	s8vars,bss
s8_proj:	ds.w	NVERT*2
s8_vis:		ds.l	NFACE
s8_back:	ds.l	1
s8_nvis:	ds.w	1
s8_ax:		ds.w	1
s8_ay:		ds.w	1
s8_frame:	ds.w	1
s8_beat:	ds.w	1
s8_colrot:	ds.w	1
s8_frontok:	ds.w	1
s8_m00:		ds.w	1
s8_m01:		ds.w	1
s8_m02:		ds.w	1
s8_m11:		ds.w	1
s8_m12:		ds.w	1
s8_m20:		ds.w	1
s8_m21:		ds.w	1
s8_m22:		ds.w	1
