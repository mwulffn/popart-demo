; demo-fable — milestone 1: copper bars (toolchain smoke test)
; A1200 / 68020. Takes over the machine, no OS exit (reset to leave).
; Four gradient bars (red/green/blue/white) palette-cycle through a
; static copper list; the CPU rewrites the color words each vblank.

CUSTOM   equ $dff000
NLINES   equ 128            ; copper gradient lines
TOPLINE  equ $6c            ; first bar line (centered in PAL 256)

        section code,code

start:
        move.w  #$7fff,CUSTOM+$09a      ; INTENA: kill all interrupts
        move.w  #$7fff,CUSTOM+$096      ; DMACON: kill all DMA
        move.w  #$0200,CUSTOM+$100      ; BPLCON0: no bitplanes, color on
        lea     coplist,a0
        move.l  a0,CUSTOM+$080          ; COP1LC
        move.w  d0,CUSTOM+$088          ; COPJMP1 strobe
        move.w  #$8280,CUSTOM+$096      ; DMACON: set copper + master

        moveq   #0,d7                   ; frame counter
mainloop:
.waitvb:
        move.l  CUSTOM+$004,d0          ; VPOSR: wait for line 300
        and.l   #$1ff00,d0
        cmp.l   #300<<8,d0
        bne.s   .waitvb

        lea     coplist+10,a0           ; first color word (after black init)
        lea     gradient,a1
        move.w  d7,d0
        move.w  #NLINES-1,d2
.fill:
        move.w  d0,d1
        and.w   #NLINES-1,d1
        add.w   d1,d1
        move.w  (a1,d1.w),(a0)
        addq.w  #8,a0                   ; next color word (wait+move = 8 bytes)
        addq.w  #1,d0
        dbf     d2,.fill

        addq.w  #1,d7
        bra.s   mainloop

; gradient table: 4 bars x 32 lines, ramp 0..15..0
        section bardata,data

gradient:
        rept 16
        dc.w    REPTN<<8                ; red up
        endr
        rept 16
        dc.w    (15-REPTN)<<8           ; red down
        endr
        rept 16
        dc.w    REPTN<<4                ; green up
        endr
        rept 16
        dc.w    (15-REPTN)<<4           ; green down
        endr
        rept 16
        dc.w    REPTN                   ; blue up
        endr
        rept 16
        dc.w    (15-REPTN)              ; blue down
        endr
        rept 16
        dc.w    REPTN*$111              ; white up
        endr
        rept 16
        dc.w    (15-REPTN)*$111         ; white down
        endr

; copper list — must live in chip RAM (data_c hunk)
        section coplistsec,data_c

coplist:
        dc.w    $0180,$0000             ; frame start: black
LINE    set     TOPLINE
        rept NLINES
        dc.w    (LINE<<8)|$07,$fffe     ; wait for line
        dc.w    $0180,$0000             ; color00, rewritten per frame
LINE    set     LINE+1
        endr
        dc.w    ((TOPLINE+NLINES)<<8)|$07,$fffe
        dc.w    $0180,$0000             ; below bars: black
        dc.w    $ffff,$fffe             ; end of copper list
