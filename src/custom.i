; custom.i — shared custom-chip register offsets (from CUSTOM = $dff000)
; and the couple of cross-module conventions.

CUSTOM	 equ	$dff000

BLTDDAT	 equ	$000
DMACONR	 equ	$002
VPOSR	 equ	$004
INTENAR	 equ	$01c
INTREQR	 equ	$01e
BLTCON0	 equ	$040
BLTCON1	 equ	$042
BLTAFWM	 equ	$044
BLTALWM	 equ	$046
BLTCPTH	 equ	$048
BLTBPTH	 equ	$04c
BLTAPTH	 equ	$050
BLTAPTL	 equ	$052
BLTDPTH	 equ	$054
BLTSIZE	 equ	$058
BLTCMOD	 equ	$060
BLTBMOD	 equ	$062
BLTAMOD	 equ	$064
BLTDMOD	 equ	$066
BLTBDAT	 equ	$072
BLTADAT	 equ	$074
COP1LC	 equ	$080
COPJMP1	 equ	$088
DIWSTRT	 equ	$08e
DIWSTOP	 equ	$090
DDFSTRT	 equ	$092
DDFSTOP	 equ	$094
DMACON	 equ	$096
INTENA	 equ	$09a
INTREQ	 equ	$09c
BPL1PTH	 equ	$0e0
BPL2PTH	 equ	$0e4
BPL3PTH	 equ	$0e8
BPL4PTH	 equ	$0ec
BPL5PTH	 equ	$0f0
BPLCON0	 equ	$100
BPLCON1	 equ	$102
BPLCON2	 equ	$104
BPLCON3	 equ	$106
BPL1MOD	 equ	$108
BPL2MOD	 equ	$10a
BPLCON4	 equ	$10c
COLOR00	 equ	$180
COLOR01	 equ	$182
FMODE	 equ	$1fc

; pop palette (docs/SCRIPT.md)
COL_PAPER equ	$0fed
COL_INK	  equ	$0112
COL_MAG	  equ	$0f0c
COL_YEL	  equ	$0fd0
COL_CYAN  equ	$00ce
COL_ORG	  equ	$0f60
COL_GRN	  equ	$08e0
