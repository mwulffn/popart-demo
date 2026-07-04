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

OBJS := $(BUILD)/main.o $(BUILD)/scene1.o $(BUILD)/ptplayer.o $(BUILD)/music.o

$(BUILD)/%.o: src/%.asm | $(BUILD)
	$(VASM) -m68020 -Fhunk -quiet -o $@ $<

$(BUILD)/music.o: music/kc-dancinonamiga.mod

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
