VASM      := tools/bin/vasmm68k_mot
VLINK     := tools/bin/vlink
SHRINKLER := tools/bin/Shrinkler
XDFTOOL   := $(HOME)/.local/bin/xdftool
BUILD     := build

all: $(BUILD)/demo.adf

# release: shrinkled exe on the disk instead of the plain one
release: $(BUILD)/demo-release.adf

$(BUILD)/demo.shr: $(BUILD)/demo
	$(SHRINKLER) -h $< $@

$(BUILD)/demo-release.adf: $(BUILD)/demo.shr src/startup-sequence
	rm -f $@
	$(XDFTOOL) $@ create + format FABLE + boot install + makedir s \
	    + write src/startup-sequence s/startup-sequence \
	    + write $(BUILD)/demo.shr demo
	@echo "--- $@:" && $(XDFTOOL) $@ list

OBJS := $(BUILD)/main.o $(BUILD)/scene1.o $(BUILD)/scene2.o $(BUILD)/scene3.o $(BUILD)/scene4.o $(BUILD)/scene5.o $(BUILD)/scene6.o $(BUILD)/scene7.o $(BUILD)/scene8.o $(BUILD)/scene9.o $(BUILD)/c2p.o $(BUILD)/ptplayer.o $(BUILD)/music.o

# INITPOS=n starts the song (and the demo) at position n — debug aid
# for jumping straight to a scene (2=warhol 8=dots 10=dive 14=comic
# 18=conveyor 20=brillo 24=canvas 28=credits). Touch src/main.asm when
# changing it.
VASMDEF := $(if $(INITPOS),-DINITPOS=$(INITPOS))

$(BUILD)/%.o: src/%.asm | $(BUILD)
	$(VASM) -m68020 -Fhunk -quiet $(VASMDEF) -o $@ $<

$(BUILD)/music.o: music/kc-dancinonamiga.mod

# scene objects also depend on their INCBIN'd / included assets
$(BUILD)/main.o $(BUILD)/scene1.o $(BUILD)/scene2.o $(BUILD)/scene3.o \
$(BUILD)/scene4.o $(BUILD)/scene5.o $(BUILD)/scene6.o \
$(BUILD)/scene7.o $(BUILD)/scene8.o $(BUILD)/scene9.o: src/custom.i
$(BUILD)/scene1.o: build/art/title.bpl build/art/title.i build/art/dotpass.i
$(BUILD)/scene2.o: build/art/floppy.bpl build/art/floppypal.i
$(BUILD)/scene3.o: build/art/dottab.i build/art/sintab.i
$(BUILD)/scene4.o: build/art/comic.bpl build/art/comic.i \
	build/art/bobs.bpl build/art/bobs.msk build/art/bobs.i
$(BUILD)/scene5.o: build/art/stamp.i
$(BUILD)/scene6.o: build/art/cards.bpl build/art/cards.i build/art/dotpass.i
$(BUILD)/scene7.o: build/art/floppytex.chk build/art/sinw.i build/art/floppypal.i
$(BUILD)/scene8.o: build/art/sinw.i
$(BUILD)/scene9.o: build/art/canvas.bpl build/art/canvas.i

# --- generated art (build/art/): pixel data + asm includes for the
# scenes above. Two families:
#  - pure procedural (PIL, no source image): maketitle/makecards/
#    makestamp/makedots. Old make (3.81) reruns a shared recipe once
#    per stale target in a multi-target rule — harmless here, these
#    are deterministic and sub-second.
#  - derived from assets/*-src.png via png2amiga.py, then further
#    derived-from-derived (floppypal, floppytex/sinw, bobs).
ART := $(BUILD)/art
PILRUN := uv run --with pillow

$(ART):
	mkdir -p $@

$(ART)/title.bpl $(ART)/title.i $(ART)/dotpass.i: bin/maketitle.py | $(ART)
	$(PILRUN) bin/maketitle.py

$(ART)/cards.bpl $(ART)/cards.i: bin/makecards.py | $(ART)
	$(PILRUN) bin/makecards.py

$(ART)/stamp.i: bin/makestamp.py | $(ART)
	$(PILRUN) bin/makestamp.py

$(ART)/dottab.i $(ART)/sintab.i: bin/makedots.py | $(ART)
	$(PILRUN) bin/makedots.py

$(ART)/floppy.bpl $(ART)/floppy.i: assets/floppy-src.png bin/png2amiga.py | $(ART)
	bin/png2amiga.py assets/floppy-src.png -o $(ART)/floppy \
	    --colors 16 --scale 160x128 --preview

$(ART)/comic.bpl $(ART)/comic.i: assets/comic-src.png bin/png2amiga.py | $(ART)
	bin/png2amiga.py assets/comic-src.png -o $(ART)/comic \
	    --colors 32 --scale 320x256 --preview

$(ART)/canvas.bpl $(ART)/canvas.i: assets/canvas_src.png bin/png2amiga.py | $(ART)
	bin/png2amiga.py assets/canvas_src.png -o $(ART)/canvas \
	    --colors 256 --scale 320x256 --planar --preview

$(ART)/floppypal.i: $(ART)/floppy.bpl $(ART)/floppy.i bin/palvariants.py
	$(PILRUN) bin/palvariants.py

$(ART)/floppytex.chk $(ART)/sinw.i: $(ART)/floppy.i bin/makeroto.py
	$(PILRUN) bin/makeroto.py

$(ART)/bobs.bpl $(ART)/bobs.msk $(ART)/bobs.i: $(ART)/comic.i bin/makebobs.py
	$(PILRUN) bin/makebobs.py

$(BUILD)/demo: $(OBJS)
	$(VLINK) -bamigahunk -s -M$(BUILD)/demo.map -o $@ $(OBJS)

$(BUILD)/demo.adf: $(BUILD)/demo src/startup-sequence
	rm -f $@
	$(XDFTOOL) $@ create + format FABLE + boot install + makedir s \
	    + write src/startup-sequence s/startup-sequence \
	    + write $(BUILD)/demo demo
	@echo "--- $@:" && $(XDFTOOL) $@ list

$(BUILD):
	mkdir -p $@

run: $(BUILD)/demo.adf
	bin/run-emulator.sh --floppy_drive_0=$(abspath $(BUILD)/demo.adf)

clean:
	rm -rf $(BUILD)

.PHONY: all release run clean
