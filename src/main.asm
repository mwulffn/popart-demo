;=====================================================================
; PopArt — A1200/AGA demo. Framework + scene sequencer.
;
; Structure:
;   start        — OS handoff (Forbid/SuperState), machine takeover,
;                  AGA baseline, ptplayer install, module start
;   mainloop     — wait VBL, read replayer song position/row, dispatch
;                  scene init (on scene change) + scene update (every
;                  frame). Scene switching is driven by the MUSIC
;                  (ptplayer's SongPos), never by frame counting.
;   scenes       — placeholder flats for now; replaced one by one.
;
; Scene boundaries (song positions, see docs/SCRIPT.md):
;   1 title 0-1 | 2 warhol 2-7 | 3 dots 8-9 | 3B dive 10-13
;   4 comic 14-17 | 5 conveyor 18-19 | 5B brillo 20-23
;   5C canvas 24-27 | 6 credits 28-33, then SongEnd → end state
;
; Music grid: 64 rows/position, swing F05/F03 @ tempo 115.
; kick = row&7==0, snare = row&7==4, bar = 16 rows.
;=====================================================================

	include	"src/custom.i"

; exec offsets
_LVOForbid	equ	-132
_LVOSuperState	equ	-150

CIAAPRA		equ	$bfe001		; bit6 = left mouse button, active low

	xref	_mt_install
	xref	_mt_init
	xref	_mt_end
	xref	_mt_Enable
	xref	_mt_SongPos
	xref	_mt_PatternPos
	xref	_mt_SongEnd
	xref	_module

	xref	sc1_init
	xref	sc1_update
	xref	sc2_init
	xref	sc2_update
	xref	sc3_init
	xref	sc3_update
	xref	sc4_init
	xref	sc4_update
	xref	sc5_init
	xref	sc5_update
	xref	sc6_init
	xref	sc6_update
	xref	sc7_init
	xref	sc7_update
	xref	sc8_init
	xref	sc8_update
	xref	sc9_init
	xref	sc9_update

	xdef	songdone

	xdef	waitblit
	xdef	songpos
	xdef	songrow
	xdef	framecnt

;=====================================================================
	section	code,code
;=====================================================================

start:
	; --- OS handoff: supervisor mode + VBR (68020 vectors movable) ---
	move.l	4.w,a6
	jsr	_LVOForbid(a6)
	jsr	_LVOSuperState(a6)	; stay in supervisor forever
	movec	vbr,d0
	move.l	d0,vbrbase

	lea	CUSTOM,a6

	; --- takeover: finish current frame, then silence the machine ---
	bsr	waitvbl
	move.w	#$7fff,INTENA(a6)
	move.w	#$7fff,INTREQ(a6)
	move.w	#$7fff,INTREQ(a6)
	move.w	#$7fff,DMACON(a6)

	; --- AGA baseline: OCS-compatible fetch, sane palette banking ---
	move.w	#$0000,FMODE(a6)	; 16-bit fetch (keep DMA timing simple)
	move.w	#$0c00,BPLCON3(a6)	; bank 0, normal palette access
	move.w	#$0011,BPLCON4(a6)	; default sprite palette MSBs
	move.w	#$0200,BPLCON0(a6)	; no bitplanes yet, color enable
	move.w	#$0000,BPLCON1(a6)
	move.w	#$0024,BPLCON2(a6)	; sprites behind playfields
	move.w	#$2c81,DIWSTRT(a6)	; standard PAL 320x256 window
	move.w	#$2cc1,DIWSTOP(a6)
	move.w	#$0038,DDFSTRT(a6)
	move.w	#$00d0,DDFSTOP(a6)

	; --- display on: blank copper list until scene 1 installs its own
	lea	cop_blank,a0
	move.l	a0,COP1LC(a6)
	move.w	d0,COPJMP1(a6)
	move.w	#$87c0,DMACON(a6)	; master+bitplane+copper+blitter+blithog

	; --- hold on black until left mouse button click — OBS-recording
	; aid only (gives time to arm capture before anything starts);
	; disabled for normal builds, uncomment for a recording session ---
	if 0
.waitclick:
	btst.b	#6,CIAAPRA
	bne.s	.waitclick		; bit6=1 -> button up, keep waiting
	endc

	; --- music: ptplayer CIA interrupt + module start ---
	move.l	vbrbase,a0
	moveq	#1,d0			; PAL
	jsr	_mt_install
	lea	_module,a0
	sub.l	a1,a1			; samples follow patterns
	ifnd	INITPOS
INITPOS	equ	0
	endc
	moveq	#INITPOS,d0		; song start (build with
	jsr	_mt_init		; INITPOS=n to jump to a scene)
	st	_mt_Enable

	move.w	#-1,curscene		; force scene 0 init on first frame

;---------------------------------------------------------------------
; main loop — one iteration per PAL frame
;---------------------------------------------------------------------
mainloop:
	bsr	waitvbl
	addq.l	#1,framecnt

	; music position → songpos/songrow (the demo's only clock)
	moveq	#0,d0
	move.b	_mt_SongPos,d0
	move.w	_mt_PatternPos,d1
	lsr.w	#4,d1			; byte offset → row (16 bytes/row)
	move.w	d0,songpos
	move.w	d1,songrow

	; debug beacon: fixed chip addresses, readable from the debugger
	; without symbols ($660 free after takeover; harmless, stays in)
	move.l	framecnt,$660.w
	move.w	d0,$664.w		; songpos
	move.w	d1,$666.w		; songrow

	; after the song ends: silence the replayer once, freeze the
	; final scene on its end state
	tst.b	_mt_SongEnd
	beq.s	.live
	moveq	#33,d0			; clamp to last position
	move.w	d0,songpos
	tst.b	songdone
	bne.s	.live
	st	songdone
	movem.l	d0-d1/a0-a1,-(sp)
	jsr	_mt_end			; stop audio (a6 = CUSTOM)
	movem.l	(sp)+,d0-d1/a0-a1
.live:
	; scene index from song position
	lea	scene_bounds(pc),a0
	moveq	#0,d2
.find:	cmp.b	(a0)+,d0
	blt.s	.found
	addq.w	#1,d2
	bra.s	.find
.found:
	move.w	d2,d1
	add.w	d1,d1
	add.w	d1,d1			; scene index → table offset
	cmp.w	curscene,d2
	beq.s	.update
	move.w	d2,curscene
	lea	scene_inits(pc),a0
	move.l	(a0,d1.w),a0
	jsr	(a0)			; scene init (copper swap etc.)
	move.w	curscene,d1
	add.w	d1,d1
	add.w	d1,d1
.update:
	lea	scene_updates(pc),a0
	move.l	(a0,d1.w),a0
	jsr	(a0)			; scene per-frame update
	bra	mainloop

;---------------------------------------------------------------------
; waitvbl — wait for start of vertical blank (line 303 edge)
;---------------------------------------------------------------------
waitvbl:
.out:	move.l	VPOSR(a6),d0
	and.l	#$1ff00,d0
	cmp.l	#303<<8,d0
	beq.s	.out			; leave line 303 if already there
.in:	move.l	VPOSR(a6),d0
	and.l	#$1ff00,d0
	cmp.l	#303<<8,d0
	bne.s	.in
	rts

;---------------------------------------------------------------------
; waitblit — wait for blitter idle (with pre-read, 68020-safe)
;---------------------------------------------------------------------
waitblit:
	tst.w	DMACONR(a6)		; bus settle
.w:	btst	#6,DMACONR(a6)
	bne.s	.w
	rts

;---------------------------------------------------------------------
; scene dispatch tables
; scene_bounds: first song position NOT belonging to the scene
;---------------------------------------------------------------------
; canvas timeline: title 0-1, warhol 2-7, dots 8-9, dive 10-13,
; comic 14-17, conveyor 18-19, brillo 20-23, canvas 24-27,
; credits 28-33 — every cut on a pattern change (even position)
scene_bounds:
	dc.b	2,8,10,14,18,20,24,28,127
	even

scene_inits:
	dc.l	sc1_init,sc2_init,sc3_init,sc7_init
	dc.l	sc4_init,sc5_init,sc8_init,sc9_init,sc6_init
scene_updates:
	dc.l	sc1_update,sc2_update,sc3_update,sc7_update
	dc.l	sc4_update,sc5_update,sc8_update,sc9_update,sc6_update

; Scene ABI: init = copper list + buffers ready (may run mid-frame,
; takes effect at next vblank); update = called once per frame after
; waitvbl, a6 = CUSTOM preserved, everything else clobberable.

;=====================================================================
	section	vars,bss
;=====================================================================
vbrbase:	ds.l	1
framecnt:	ds.l	1
songpos:	ds.w	1
songrow:	ds.w	1
curscene:	ds.w	1
songdone:	ds.b	1
		even

;=====================================================================
	section	coplists,data_c
;=====================================================================
; startup copper list: black screen until scene 1 installs its own
cop_blank:
	dc.w	$01fc,$0000		; FMODE
	dc.w	$0100,$0200		; BPLCON0: no planes
	dc.w	$0180,$0000		; COLOR00 black
	dc.w	$ffff,$fffe
