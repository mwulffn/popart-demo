; music.asm — module data. Chip RAM (data_c): Paula reads samples via DMA.
; "DancinOnAmiga" by Katie Cadet, Public Domain (see music/LICENSE.md).

	section music,data_c

	xdef	_module
_module:
	incbin	"music/kc-dancinonamiga.mod"
