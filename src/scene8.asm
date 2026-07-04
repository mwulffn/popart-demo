;=====================================================================
; scene8.asm — "BRILLO BOX" (song pos 20-23): real-time vector floppy
;
; Flat-shaded 3D floppy (box body + shutter/label decals on the front
; face), tumbling. Classic blitter vector pipeline in a 192x176 region
; centered on screen:
;   3 bitplanes: 0 paper, 1-6 pop colors, 7 ink. Per visible face:
;   clear temp plane -> CPU XOR fill-dots -> blitter inclusive fill
;   (descending) -> OR into the screen planes of the face's color
;   bits (<=2 planes each). The label decal is a HOLE: its edges are
;   XOR'd into the front face's own fill pass, so the fill toggles
;   off inside it and paper shows — zero label blits. The shutter is
;   ink (7 = all planes) so a plain OR over the front face is exact.
;   Afterwards every visible edge is drawn once (shared-edge dedup)
;   into an outline plane, merged into all 3 planes at (0,0)+(+1,+1)
;   in one blit per plane (B channel = same plane 1 row up, B-shift
;   1): thick ink cartoon outline (color 7) over any fill. No
;   shading — Pop Art fills flat. All blits are sized to the object
;   / face bounding box, not the region — the blitter is the frame
;   budget here.
; Face colors rotate one palette step per downbeat (the print queue
; advancing across the object); tumble speeds up in the scene's
; second half (pos 22).
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
NEDGE	equ	20

	section	code,code

;---------------------------------------------------------------------
sc8_init:
	; palette (bank 0): 3 bitplanes — 0 paper, 1-6 pop colors, 7 ink
	move.w	#$0c00,BPLCON3(a6)
	lea	s8_pal(pc),a0
	lea	COLOR00(a6),a1
	moveq	#8-1,d1
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
	cmp.w	#22,songpos		; second half: faster tumble
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

	; --- object bounding box over all projected verts, padded 1 px
	; right/down for the thick-outline pass, word-aligned. Every
	; full-region blit below (clears, outline merge) shrinks to it:
	; the object covers a fraction of the 192x176 region and the
	; blitter was the frame's bottleneck ---
	lea	s8_proj,a0
	move.w	#191,d0			; minx
	move.w	#175,d1			; miny
	moveq	#0,d2			; maxx
	moveq	#0,d3			; maxy
	moveq	#NVERT-1,d7
.bb:	move.w	(a0)+,d4
	move.w	(a0)+,d5
	cmp.w	d0,d4
	bge.s	.b1
	move.w	d4,d0
.b1:	cmp.w	d2,d4
	ble.s	.b2
	move.w	d4,d2
.b2:	cmp.w	d1,d5
	bge.s	.b3
	move.w	d5,d1
.b3:	cmp.w	d3,d5
	ble.s	.b4
	move.w	d5,d3
.b4:	dbf	d7,.bb
	addq.w	#1,d2			; +1,+1 outline pass pad
	cmp.w	#191,d2
	ble.s	.bxc
	move.w	#191,d2
.bxc:	addq.w	#1,d3
	cmp.w	#175,d3
	ble.s	.byc
	move.w	#175,d3
.byc:	lsr.w	#4,d0			; -> first word / width / rows
	lsr.w	#4,d2
	sub.w	d0,d2
	addq.w	#1,d2			; width in words
	add.w	d0,d0			; byte offset of first word
	sub.w	d1,d3
	addq.w	#1,d3			; height in rows
	move.w	d0,s8_bbx
	move.w	d2,s8_bbw
	move.w	d1,s8_bby
	move.w	d3,s8_bbh

	; --- pick back buffer; erase only what was drawn there LAST
	; time (its stored bbox — two frames old, double buffered), not
	; the whole region. h=0 first time round: init cleared all ---
	move.w	s8_frame,d0
	and.w	#1,d0
	mulu	#SCRPL*4,d0
	add.l	#s8_scr,d0
	move.l	d0,s8_back
	move.w	s8_frame,d1
	and.w	#1,d1
	lsl.w	#3,d1
	lea	s8_scrbb,a0
	add.w	d1,a0			; this buffer's stale bbox
	move.w	6(a0),d5		; h
	beq.s	.noclr
	add.l	#REGOFF,d0
	moveq	#0,d3
	move.w	4(a0),d3
	mulu	#40,d3
	add.l	d3,d0
	moveq	#0,d1
	move.w	(a0),d1
	add.l	d1,d0			; bbox origin in plane 0
	move.w	2(a0),d2
	move.w	d2,d4
	add.w	d4,d4
	neg.w	d4
	add.w	#40,d4			; DMOD = 40 - 2w
	lsl.w	#6,d5
	or.w	d2,d5			; BLTSIZE
	moveq	#3-1,d7
.clrp:	bsr	waitblit
	move.l	#$01000000,BLTCON0(a6)
	move.l	d0,BLTDPTH(a6)
	move.w	d4,BLTDMOD(a6)
	move.w	d5,BLTSIZE(a6)
	add.l	#SCRPL,d0
	dbf	d7,.clrp
.noclr:	move.w	s8_bbx,(a0)		; remember for next round
	move.w	s8_bbw,2(a0)
	move.w	s8_bby,4(a0)
	move.w	s8_bbh,6(a0)

	; --- faces: visibility, fill, remember for the outline pass ---
	clr.w	s8_vismask
	lea	s8_faces(pc),a5
	moveq	#0,d7			; face number
.face:	bsr	s8_doface
	lea	8(a5),a5
	addq.w	#1,d7
	cmp.w	#NFACE,d7
	blt.s	.face
.skipfaces:

	; --- outline: clear the PREVIOUS frame's outline bbox (plane is
	; single-buffered), CPU-draw visible edges, merge into screen ---
	move.w	s8_olbb+6,d5		; old h (0 first frame: BSS)
	beq.s	.noolc
	moveq	#0,d3
	move.w	s8_olbb+4,d3
	mulu	#REGBPR,d3
	moveq	#0,d1
	move.w	s8_olbb,d1
	add.l	d1,d3
	add.l	#s8_outl,d3
	move.w	s8_olbb+2,d2
	move.w	d2,d4
	add.w	d4,d4
	neg.w	d4
	add.w	#REGBPR,d4		; DMOD = 24 - 2w
	lsl.w	#6,d5
	or.w	d2,d5
	bsr	waitblit
	move.l	#$01000000,BLTCON0(a6)
	move.l	d3,BLTDPTH(a6)
	move.w	d4,BLTDMOD(a6)
	move.w	d5,BLTSIZE(a6)
.noolc:	move.w	s8_bbx,s8_olbb
	move.w	s8_bbw,s8_olbb+2
	move.w	s8_bby,s8_olbb+4
	move.w	s8_bbh,s8_olbb+6
	bsr	waitblit		; CPU draws into s8_outl next


	; shared-edge dedup: each unique edge carries a mask of its
	; adjacent faces and is drawn ONCE if any of them is visible —
	; the per-face loop drew every body edge between two visible
	; faces twice
	move.w	s8_vismask,d5
	beq.s	.nool
	lea	s8_edges(pc),a4
	moveq	#NEDGE-1,d7
.oedge:	move.w	2(a4),d0
	and.w	d5,d0
	beq.s	.oskip
	lea	s8_proj,a0
	moveq	#0,d0
	move.b	(a4),d0
	lsl.w	#2,d0
	movem.w	(a0,d0.w),d0-d1
	moveq	#0,d2
	move.b	1(a4),d2
	lsl.w	#2,d2
	movem.w	(a0,d2.w),d2-d3
	movem.l	d5/d7/a4,-(sp)
	bsr	s8_cpuline
	movem.l	(sp)+,d5/d7/a4
.oskip:	addq.w	#4,a4
	dbf	d7,.oedge
.nool:
	; OR outline into all 3 planes (ink = 7). The second (+1,+1)
	; pass is folded into the B channel: B reads the SAME outline
	; plane one row up with B-shift 1, so D = A|B|C lays down (0,0)
	; and (+1,+1) in one blit per plane, all bbox-sized. bby=0 makes
	; B read the zeroed guard row.
	moveq	#0,d3
	move.w	s8_bby,d3
	mulu	#REGBPR,d3
	moveq	#0,d1
	move.w	s8_bbx,d1
	add.l	d1,d3
	add.l	#s8_outl,d3		; A = outline bbox origin
	moveq	#0,d0
	move.w	s8_bby,d0
	mulu	#40,d0
	add.l	d1,d0
	add.l	s8_back,d0
	add.l	#REGOFF,d0		; C/D = screen bbox origin
	move.w	s8_bbw,d2
	move.w	d2,d4
	add.w	d4,d4
	move.w	#REGBPR,d5
	sub.w	d4,d5			; A/B mod = 24 - 2w
	move.w	#40,d6
	sub.w	d4,d6			; C/D mod = 40 - 2w
	move.w	s8_bbh,d4
	lsl.w	#6,d4
	or.w	d2,d4			; BLTSIZE
	moveq	#3-1,d7
.oplane:
	bsr	waitblit
	move.w	#$0ffe,BLTCON0(a6)	; D = A|B|C
	move.w	#$1000,BLTCON1(a6)	; B shift 1 = the +1 px
	move.l	#-1,BLTAFWM(a6)
	move.l	d3,BLTAPTH(a6)
	move.l	d3,d1
	sub.l	#REGBPR,d1
	move.l	d1,BLTBPTH(a6)		; one row up -> lands +1 down
	move.l	d0,BLTCPTH(a6)
	move.l	d0,BLTDPTH(a6)
	move.w	d5,BLTAMOD(a6)
	move.w	d5,BLTBMOD(a6)
	move.w	d6,BLTCMOD(a6)
	move.w	d6,BLTDMOD(a6)
	move.w	d4,BLTSIZE(a6)
	add.l	#SCRPL,d0
	dbf	d7,.oplane

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
	; decals (faces 6+) ride the front face: hide them once the
	; front is nearly edge-on, else they degenerate to long thin
	; slivers whose outlines read as stray hairs. Updated BEFORE the
	; cull so a backfacing front clears the flag (no stale reuse).
	tst.w	d7
	bne.s	.notfront
	clr.w	s8_frontok
	cmp.l	#1200,d2
	ble.s	.notfront
	move.w	#1,s8_frontok
.notfront:
	; cull backfaces AND slivers. Threshold is PER FACE (word at
	; 6(a5), ~1/16 of the face's full-on cross): a flat cutoff sized
	; for the big front face culled the thin 12-unit side faces (max
	; cross ~1100) while still 70% face-on
	move.w	6(a5),d0
	ext.l	d0
	cmp.l	d0,d2
	ble	.out
	cmp.w	#6,d7
	blt.s	.body
	tst.w	s8_frontok
	beq	.out
.body:

	; record for outline pass
	move.w	s8_vismask,d0
	bset	d7,d0
	move.w	d0,s8_vismask

	; color byte 0 = draw NOTHING (label): the front-face fill left
	; a paper hole exactly there; only its ink outline is wanted
	tst.b	4(a5)
	beq	.out

	; face bbox -> blit params: temp clear, fill and composite all
	; shrink to it (a sliver side face costs a sliver blit, not the
	; full region). Temp outside the bbox may hold stale bits from
	; earlier faces — never read, the composite is bbox-sized too.
	lea	s8_proj,a4
	move.l	a5,a0			; 4 vertex index bytes
	move.w	#32767,d0		; minx
	move.w	#32767,d1		; miny
	moveq	#0,d2			; maxx
	moveq	#0,d3			; maxy
	moveq	#4-1,d6
.fbb:	moveq	#0,d4
	move.b	(a0)+,d4
	lsl.w	#2,d4
	move.w	(a4,d4.w),d5		; x
	cmp.w	d0,d5
	bge.s	.f1
	move.w	d5,d0
.f1:	cmp.w	d2,d5
	ble.s	.f2
	move.w	d5,d2
.f2:	move.w	2(a4,d4.w),d5		; y
	cmp.w	d1,d5
	bge.s	.f3
	move.w	d5,d1
.f3:	cmp.w	d3,d5
	ble.s	.f4
	move.w	d5,d3
.f4:	dbf	d6,.fbb
	lsr.w	#4,d0
	lsr.w	#4,d2
	sub.w	d0,d2
	addq.w	#1,d2			; width in words
	add.w	d0,d0			; byte offset of first word
	sub.w	d1,d3
	addq.w	#1,d3			; height in rows
	move.w	d2,d4
	add.w	d4,d4			; 2w
	move.w	#REGBPR,d5
	sub.w	d4,d5
	move.w	d5,s8_fbmodt		; temp mod
	move.w	#40,d5
	sub.w	d4,d5
	move.w	d5,s8_fbmods		; screen mod
	move.w	d3,d5
	lsl.w	#6,d5
	or.w	d2,d5
	move.w	d5,s8_fbsiz		; BLTSIZE
	moveq	#0,d5
	move.w	d1,d5
	mulu	#REGBPR,d5
	add.w	d0,d5
	add.l	#s8_temp,d5
	move.l	d5,s8_fbtmp		; temp bbox origin
	move.w	d1,d5
	add.w	d3,d5
	subq.w	#1,d5
	mulu	#REGBPR,d5
	add.w	d0,d5
	add.w	d4,d5
	subq.w	#2,d5
	add.l	#s8_temp,d5
	move.l	d5,s8_fbend		; last word (descending fill)
	moveq	#0,d5
	move.w	d1,d5
	mulu	#40,d5
	add.w	d0,d5
	add.l	#REGOFF,d5
	move.l	d5,s8_fbscro		; screen offset of bbox origin

	; clear temp plane (bbox only)
	bsr	waitblit
	move.l	#$01000000,BLTCON0(a6)
	move.l	s8_fbtmp,BLTDPTH(a6)
	move.w	s8_fbmodt,BLTDMOD(a6)
	move.w	s8_fbsiz,BLTSIZE(a6)

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

	; front face also XORs the LABEL's edges into the same temp:
	; rows crossing the label toggle fill-on/off/on, so the fill
	; punches a paper-colored hole — the label then costs no blits
	; at all. (The shutter needs no hole: ink = 7 = all planes set,
	; plain OR over any face color still gives 7.)
	tst.w	d7
	bne.s	.nopunch
	tst.w	s8_frontok
	beq.s	.nopunch
	move.l	a5,-(sp)
	lea	s8_faces+(7*8)(pc),a5	; label face entry
	moveq	#0,d6
.pedge:	bsr	s8_edgexy
	movem.l	d6-d7,-(sp)
	bsr	s8_filledge
	movem.l	(sp)+,d6-d7
	addq.w	#1,d6
	cmp.w	#4,d6
	blt.s	.pedge
	move.l	(sp)+,a5
.nopunch:

	; inclusive fill, descending, bbox only. Fill carry is safe:
	; every bbox row has an even dot count (0/2, +2 inside the
	; label hole), so the carry is 0 at each row boundary
	bsr	waitblit
	move.l	#$09f0000a,BLTCON0(a6)	; A->D, DESC+IFE
	move.l	#-1,BLTAFWM(a6)
	move.l	s8_fbend,BLTAPTH(a6)
	move.l	s8_fbend,BLTDPTH(a6)
	move.w	s8_fbmodt,BLTAMOD(a6)
	move.w	s8_fbmodt,BLTDMOD(a6)
	move.w	s8_fbsiz,BLTSIZE(a6)

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
	; composite temp into the screen planes: OR the set-bit planes
	; only. Box faces never overlap (convex); the shutter ORs over
	; the front face but is ink (all bits) so OR is still exact
	move.l	s8_back,d0
	add.l	s8_fbscro,d0
	moveq	#3-1,d7
.plane:	lsr.w	#1,d4
	bcc.s	.nobit
	bsr	waitblit
	move.w	#$0bfa,BLTCON0(a6)	; A|C -> D
	move.w	#0,BLTCON1(a6)
	move.l	#-1,BLTAFWM(a6)
	move.l	s8_fbtmp,BLTAPTH(a6)
	move.l	d0,BLTCPTH(a6)
	move.l	d0,BLTDPTH(a6)
	move.w	s8_fbmodt,BLTAMOD(a6)
	move.w	s8_fbmods,BLTCMOD(a6)
	move.w	s8_fbmods,BLTDMOD(a6)
	move.w	s8_fbsiz,BLTSIZE(a6)
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

; 3-bitplane palette: 0 paper, 1-6 pop colors, 7 ink
s8_pal:
	dc.w	$0fed,$0f0c,$0fd0,$00ce,$08e0,$0f60,$0e11,$0112

; rotating face colors: mag yel cyan grn org red (indices 1-6)
s8_coltab:
	dc.b	1,2,3,4,5,6
	even

s8_verts:
	; floppy body: 100 x 100 x 12 model units
	dc.w	-50,-50,-6,  50,-50,-6,  50,50,-6,  -50,50,-6
	dc.w	-50,-50, 6,  50,-50, 6,  50,50, 6,  -50,50, 6
	; shutter + label: decals on the front face (z=-6)
	dc.w	-12,-46,-6,  34,-46,-6,  34,-12,-6,  -12,-12,-6
	dc.w	-36,  2,-6,  36,  2,-6,  36, 46,-6,  -36, 46,-6

; faces: 4 vertex indices, color ($80|slot = rotating, 0 = outline
; only), pad, sliver-cull threshold (~1/16 of full-on screen cross).
; Decals gate on s8_frontok, their own threshold is a sanity floor.
s8_faces:
	dc.b	0,1,2,3,   $80,0	; front (full-on cross ~9600)
	dc.w	600
	dc.b	5,4,7,6,   $81,0	; back
	dc.w	600
	dc.b	4,5,1,0,   $82,0	; top (thin: full-on ~1100)
	dc.w	70
	dc.b	3,2,6,7,   $83,0	; bottom
	dc.w	70
	dc.b	4,0,3,7,   $84,0	; left
	dc.w	70
	dc.b	1,5,6,2,   $85,0	; right
	dc.w	70
	dc.b	8,9,10,11, 7,0		; shutter: ink, plain OR
	dc.w	8
	dc.b	12,13,14,15, 0,0	; label: hole in front = paper
	dc.w	8

; unique edges: v0, v1, mask of adjacent faces (bit = face number).
; Outline pass draws each once if any adjacent face is visible.
s8_edges:
	dc.b	0,1
	dc.w	(1<<0)!(1<<2)		; front|top
	dc.b	1,2
	dc.w	(1<<0)!(1<<5)		; front|right
	dc.b	2,3
	dc.w	(1<<0)!(1<<3)		; front|bottom
	dc.b	3,0
	dc.w	(1<<0)!(1<<4)		; front|left
	dc.b	4,5
	dc.w	(1<<1)!(1<<2)		; back|top
	dc.b	5,6
	dc.w	(1<<1)!(1<<5)		; back|right
	dc.b	6,7
	dc.w	(1<<1)!(1<<3)		; back|bottom
	dc.b	7,4
	dc.w	(1<<1)!(1<<4)		; back|left
	dc.b	0,4
	dc.w	(1<<2)!(1<<4)		; top|left
	dc.b	1,5
	dc.w	(1<<2)!(1<<5)		; top|right
	dc.b	2,6
	dc.w	(1<<3)!(1<<5)		; bottom|right
	dc.b	3,7
	dc.w	(1<<3)!(1<<4)		; bottom|left
	dc.b	8,9
	dc.w	1<<6			; shutter
	dc.b	9,10
	dc.w	1<<6
	dc.b	10,11
	dc.w	1<<6
	dc.b	11,8
	dc.w	1<<6
	dc.b	12,13
	dc.w	1<<7			; label
	dc.b	13,14
	dc.w	1<<7
	dc.b	14,15
	dc.w	1<<7
	dc.b	15,12
	dc.w	1<<7

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
	dc.w	$0100,$3200		; 3 planes
	dc.w	$ffff,$fffe

;---------------------------------------------------------------------
	section	s8bss,bss_c
;---------------------------------------------------------------------
s8_scr:		ds.b	SCRPL*4*2	; two 4-plane contiguous buffers
s8_temp:	ds.b	REGPL		; polygon fill plane
s8_outlg:	ds.b	REGBPR		; zero guard row: B channel of the
					; outline merge reads bbox row -1
s8_outl:	ds.b	REGPL		; outline plane

	section	s8vars,bss
s8_proj:	ds.w	NVERT*2
s8_back:	ds.l	1
s8_vismask:	ds.w	1
s8_bbx:		ds.w	1		; object bbox blit params
s8_bbw:		ds.w	1		; (byte off / words / row / rows)
s8_bby:		ds.w	1
s8_bbh:		ds.w	1
s8_scrbb:	ds.w	4*2		; stale bbox per screen buffer
s8_olbb:	ds.w	4		; stale bbox of outline plane
s8_fbtmp:	ds.l	1		; face bbox: temp origin
s8_fbend:	ds.l	1		; last word (descending fill)
s8_fbscro:	ds.l	1		; screen offset of bbox origin
s8_fbmodt:	ds.w	1		; temp modulo
s8_fbmods:	ds.w	1		; screen modulo
s8_fbsiz:	ds.w	1		; BLTSIZE
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
