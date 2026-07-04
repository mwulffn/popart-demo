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
;   1 title 0-3 | 2 warhol 4-9 | 3 dots 10-15 | 4 comic 16-21
;   5 conveyor 22-27 | 6 credits 28-33, then SongEnd → end state
;
; Music grid: 64 rows/position, swing F05/F03 @ tempo 115.
; kick = row&7==0, snare = row&7==4, bar = 16 rows.
;=====================================================================

CUSTOM	 equ	$dff000

; custom chip register offsets
DMACONR	 equ	$002
VPOSR	 equ	$004
INTENA	 equ	$09a
INTREQ	 equ	$09c
DMACON	 equ	$096
COP1LC	 equ	$080
COPJMP1	 equ	$088
DIWSTRT	 equ	$08e
DIWSTOP	 equ	$090
DDFSTRT	 equ	$092
DDFSTOP	 equ	$094
BPLCON0	 equ	$100
BPLCON1	 equ	$102
BPLCON2	 equ	$104
BPLCON3	 equ	$106
BPLCON4	 equ	$10c
BPL1MOD	 equ	$108
BPL2MOD	 equ	$10a
COLOR00	 equ	$180
FMODE	 equ	$1fc

; exec offsets
_LVOForbid	equ	-132
_LVOSuperState	equ	-150

	xref	_mt_install
	xref	_mt_init
	xref	_mt_end
	xref	_mt_Enable
	xref	_mt_SongPos
	xref	_mt_PatternPos
	xref	_mt_SongEnd
	xref	_module

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

	; --- music: ptplayer CIA interrupt + module start ---
	move.l	vbrbase,a0
	moveq	#1,d0			; PAL
	jsr	_mt_install
	lea	_module,a0
	sub.l	a1,a1			; samples follow patterns
	moveq	#0,d0			; from song position 0
	jsr	_mt_init
	st	_mt_Enable

	; --- display on: blank copper list until scene 1 installs its own
	lea	cop_blank,a0
	move.l	a0,COP1LC(a6)
	move.w	d0,COPJMP1(a6)
	move.w	#$8280,DMACON(a6)	; master + copper

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

	; after the song ends, stay on the final scene's end state
	tst.b	_mt_SongEnd
	beq.s	.live
	moveq	#33,d0			; clamp to last position
	move.w	d0,songpos
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
; scene dispatch tables
; scene_bounds: first song position NOT belonging to the scene
;---------------------------------------------------------------------
scene_bounds:
	dc.b	4,10,16,22,28,127
	even

scene_inits:
	dc.l	sc1_init,sc2_init,sc3_init,sc4_init,sc5_init,sc6_init
scene_updates:
	dc.l	sc1_update,sc2_update,sc3_update,sc4_update,sc5_update,sc6_update

;=====================================================================
; placeholder scenes — one flat color each, beat flash on the kick.
; Each will be replaced by the real effect, keeping init/update ABI:
; init: copper list + buffers ready; update: called once per frame,
; may trash d0-d1/a0-a1, a6 = CUSTOM preserved.
;=====================================================================

; flat-color placeholder: d0 = base color, beat-flashed toward white
flat_update:
	move.w	songrow,d1
	and.w	#7,d1			; rows 0-1 after each kick: flash
	cmp.w	#2,d1
	bge.s	.set
	move.w	#$0fff,d0
.set:	move.w	d0,cop_color+2
	rts

sc1_init:
sc2_init:
sc3_init:
sc4_init:
sc5_init:
sc6_init:
	lea	cop_blank,a0
	move.l	a0,COP1LC(a6)
	rts

sc1_update:
	move.w	#$0fed,d0		; paper
	bra.s	flat_update
sc2_update:
	move.w	#$0f0c,d0		; magenta
	bra.s	flat_update
sc3_update:
	move.w	#$00ce,d0		; cyan
	bra.s	flat_update
sc4_update:
	move.w	#$0fd0,d0		; yellow
	bra.s	flat_update
sc5_update:
	move.w	#$08e0,d0		; acid green
	bra.s	flat_update
sc6_update:
	move.w	#$0112,d0		; ink
	bra.s	flat_update

;=====================================================================
	section	vars,bss
;=====================================================================
vbrbase:	ds.l	1
framecnt:	ds.l	1
songpos:	ds.w	1
songrow:	ds.w	1
curscene:	ds.w	1

;=====================================================================
	section	coplists,data_c
;=====================================================================
cop_blank:
	dc.w	$01fc,$0000		; FMODE
	dc.w	$0100,$0200		; BPLCON0: no planes
cop_color:
	dc.w	$0180,$0000		; COLOR00, rewritten by scenes
	dc.w	$ffff,$fffe
