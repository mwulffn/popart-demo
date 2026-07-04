# Demo Development Journal

## 2026-07-04 — Emulator setup: FS-UAE with GDB + screenshots

### Goal
Find Amiga emulator for demo dev on macOS (arm64). Requirements: boot our
Kickstart 3.1 A1200 ROM, GDB remote debugging, scriptable screenshots.

### Options evaluated
| Emulator | GDB | Screenshots | Verdict |
|----------|-----|-------------|---------|
| FS-UAE 3.2.35 (brew) | No (console debugger only) | Keybind only, not scriptable | Rejected |
| vAmiga | No (open issue #618) | — | Rejected |
| WinUAE | Yes (bartman fork) | Yes | Windows-only |
| **FS-UAE patched (uae-dap bundle)** | **Yes** | **Yes, via GDB monitor cmd** | **Chosen** |

### Chosen: GDB-patched FS-UAE from uae-dap npm package
- Source: `npm pack uae-dap` (v1.1.5) → `package/bin/fs-uae/fs-uae-darwin_x64`
- Copied to `tools/fs-uae-gdb/` (binary + `lib/` dylibs + `fs-uae.dat` + `data/`)
- Based on WinUAE 5.1.0 core, gdbserver patches by @bartman + @prb28
  (`barto_gdbserver.cpp`), same binary vscode-amiga-assembly uses
- x86_64 binary — runs via Rosetta 2 on this arm64 Mac. Works fine.

### Verified working
1. **Boot**: `bin/run-emulator.sh` boots to Kickstart 3.1 screen
   (rainbow checkmark + insert-floppy image confirmed in screenshot)
2. **GDB server**: listens on `localhost:2345`.
   `qSupported` handshake OK: `PacketSize=512;BreakpointCommands+;swbreak+;hwbreak+;QStartNoAckMode+;vContSupported+;QTFrame+`
3. **Screenshots**: GDB monitor command `screenshot <abs-path.png>` → `OK`,
   writes PNG. No macOS screen-recording permission needed (unlike
   `screencapture`, which failed with "could not create image from display").
   `bin/screenshot.py` wraps this.

### Config options (found via `strings` on binary)
- `remote_debugger = <seconds>` — enable gdbserver; value = how long the
  emulator waits for a GDB connection at startup before booting anyway
- `remote_debugger_port = 2345`
- `remote_debugger_trigger = <name>` — optional: wait until a program with
  this name is loaded (used for debugging exe launches from CLI)

### Gotchas
- **One GDB session per launch.** Server does `close()` on client disconnect
  and never re-listens. Restart emulator for a new session, or keep one
  connection open and do everything (including screenshots) through it.
- Emulator is **halted** while waiting for GDB; send `vCont;c` (or `c` in gdb)
  to let kickstart boot.
- Emulator log: `~/Documents/FS-UAE/Cache/Logs/fs-uae.log.txt` — grep
  `GDBSERVER:` to see full packet trace.
- Monitor commands seen in binary: `screenshot`, `profile`, `console`,
  `dumpdma`. Not yet explored beyond screenshot.
- Plain brew fs-uae 3.2.35 also installed (`fs-uae`) — usable as
  reference/second opinion, config at `config/a1200.fs-uae` works for both.

### Next steps
- Toolchain: assembler (vasm) — uae-dap package ships `vasmm68k_mot` +
  `cstool` wasm builds; decide native vs those
- First bootblock/startup code that takes over the machine

## 2026-07-04 (later) — mcp-gdb: debug MCP server adopted from mariposa-2

### What
Adopted local copy of `mariposa-2/tools/mcp-gdb` → `tools/mcp-gdb/`,
registered as MCP server `gdb` (local scope). Solves the
one-GDB-session-per-launch problem: the MCP server process holds the
single persistent connection across tool calls.

### Major adaptation: real GDB unusable → direct RSP client
- Stub (`barto_gdbserver.cpp`) replies `E01` to `vMustReplyEmpty` —
  spec violation, GDB >= 8 aborts connection. VSCode extensions
  unaffected (they ship JS GDB client implementations).
- Packet-fixing proxy attempt hit further incompatibilities (hang).
- Solution: rewrote server to speak RSP directly over socket. Kept
  mariposa architecture (reader thread, queue, lock, lifecycle cleanup).

### Stub protocol findings (verified empirically)
- Interrupt: raw `0x03` byte → `S05`. Works.
- `g` = 18 regs (d0-d7, a0-a7, sr, pc), 8 hex chars each; `p11` = pc
- `m`/`M` memory read/write, `Z0`/`z0` breakpoints, `vCont;c/s`: all work
- Sending non-monitor packets while target RUNS → stub disconnects.
  Halt first (tools do this automatically). `qRcmd` safe while running.
- One request per TCP chunk — never batch packets.
- Python gotcha: socket from `create_connection(timeout=...)` stays in
  timeout mode → rx thread died on 2s silence. `settimeout(None)` fixed.

### Verified end-to-end
registers / read+write memory / step / breakpoints / cont / interrupt /
screenshot-while-running / emulator_log — all green against booted
kickstart. `claude mcp list` shows connected.

### Tools now available (MCP `gdb`)
debug_start, debug_stop, registers, read_memory, write_memory,
breakpoint, step, cont, interrupt, monitor, screenshot, emulator_log.
`monitor("console <cmd>")` = full WinUAE debugger command set.

## 2026-07-04 — Local image generation: Flux.2 dev on MPS via ComfyUI

### Goal
Local image-gen tool for demo assets (reference art, textures, mood boards).
Flux.2 dev, models already in `~/ComfyUI-Shared/models/`.

### Setup
- ComfyUI cloned to `tools/comfyui/` (gitignored), own uv venv (py 3.12,
  torch 2.12.1 MPS). Models resolved from `~/ComfyUI-Shared` via
  `extra_model_paths.yaml`.
- `bin/comfyui-server.sh` — server on 127.0.0.1:8188
- `bin/generate-image.py` — stdlib-only CLI: auto-starts server, submits
  Flux.2 t2i workflow via API, polls history, saves PNG.
- Workflow topology lifted from official example PNG metadata
  (ComfyUI_examples/flux2): UNETLoader → LoraLoaderModelOnly (turbo) →
  BasicGuider + FluxGuidance + CLIPTextEncode (mistral, type "flux2") →
  SamplerCustomAdvanced (euler) + Flux2Scheduler + EmptyFlux2LatentImage.
- Defaults: Turbo LoRA, 8 steps, guidance 2.5. `--no-turbo`: 20 steps,
  guidance 4.0.

### Gotcha: fp8 has no MPS kernels
`flux2_dev_fp8mixed.safetensors` fails on Apple Silicon:
`TypeError: Trying to convert Float8_e4m3fn to the MPS backend but it does
not have support for that dtype.` — fp8 tensors can be *stored* on MPS but
the fp8→bf16 cast kernel doesn't exist; comfy_kitchen's "emulated" fp8 dequant
dies, and even patched it would CPU-roundtrip every layer (unusable).

Fix: one-off offline dequant `tools/convert-fp8-to-bf16.py` — only the 128
MLP weights are fp8 (per-tensor `weight_scale`, rest already bf16);
`bf16 = fp8.float() * weight_scale`. Output:
`flux2_dev_bf16_dequant.safetensors` (60 GB). Loads clean
("manual cast: None"), plain bf16 path on MPS.

### Verified
640x512 turbo generation works end-to-end; first run 216 s including 61 GB
model load onto MPS, warm runs ~130 s (M5 Max, 128 GB — fits fine). Test
images in `screenshots/genimage-test*.png`.

## 2026-07-04 — Toolchain: vasm/vlink/amitools + first bootable demo

### Toolchain (all local, no brew packages existed)
- **vasm 2.0e** (`vasmm68k_mot`) + **vlink 0.18a** — built from
  sun.hasenbraten.de source tarballs → `tools/bin/` (gitignored).
  Flags: `-m68020 -Fhunk`, link `-bamigahunk -s`.
- **amitools 0.8.1** via `uv tool install` → `xdftool` builds bootable ADF
  (`create + format + boot install + write ...`). `hunktool` for inspection.
- **Makefile**: `make` = asm → link → ADF; `make run` = boot it in FS-UAE.

### Milestone: copper bars demo boots from floppy
`src/main.asm` — kills OS (INTENA/DMACON), static copper list waits on 128
lines rewriting COLOR00, CPU palette-cycles the color words each vblank.
- Exe 1516 bytes, bootable OFS ADF with `s/startup-sequence` → `demo`.
- Verified via gdb MCP: bars animate (two screenshots differ), PC=$215052
  ⇒ code hunk runs from fast RAM, copper list correctly placed in chip RAM
  via `section ...,data_c`.

### Machine config: 4 MB fast RAM (common real A1200 setup)
- `--fast_memory=4096` added to `config/a1200.fs-uae`,
  `bin/run-emulator.sh`, and mcp-gdb's hardcoded arg list (server.py —
  NOTE: MCP server must restart to pick up edits; until then pass via
  `extra_args`). Also `--floppy_drive_speed=0` (turbo) everywhere for dev.
- Verified: `console dm` → `00200000 4096K Fast memory` after autoconfig.

### Gotchas
- vasm REPT/REPTN + `SET` symbols generate the copper list + gradient
  tables at assembly time — no external codegen step needed.
- mcp-gdb `debug_start(extra_args=...)` passes FS-UAE CLI args; that's how
  the ADF gets into df0.

## 2026-07-04 — png2amiga.py: asset conversion pipeline

`bin/png2amiga.py` (uv script, Pillow) — PNG → planar Amiga data.
Modes: fullscreen art, logos (blitter objects), fonts/sprite sheets.

- Quantize (mediancut, FS dither default) → `.bpl` bitplanes
  (interleaved default, `--planar` for contiguous) + `.i` asm include
  with W/H/PLANES/BPR/MODULO constants and palette (≤32 colors: OCS
  12-bit `dc.w`; >32: AGA 24-bit `dc.l`).
- `--tile WxH`: slices sheet left-right top-bottom, each tile contiguous
  → glyph n = base + n*TILEBYTES. For fonts/sprites.
- `--mask`: alpha ≥128 → `.msk` blitter mask plane; palette index 0
  reserved for transparency (quantizes to N-1 colors).
- `--scale`/`--crop`/`--preview`; width auto-padded to 16 px multiple.
- Verified: planar roundtrip decode == preview (0 px diff); 320x256x5
  fullscreen = 50 KB; mask bit pattern matches test ellipse.
- Pipeline: generate-image.py (Flux2, 640x512) → png2amiga --scale
  320x256 (2x supersample) → INCBIN.

## 2026-07-04 — Shrinkler cruncher added

- Built from github.com/askeksa/Shrinkler (native, `make`) → `tools/bin/`.
- Demo exe 1516 → 676 bytes self-extracting; verified boots + runs
  identically (screenshots/bars-shrinkled.png). `-h` merges hunks.
- `make release` → `build/demo-release.adf` with shrinkled exe.
- Also has `-d` raw-data mode for crunching individual assets
  (needs decruncher call at runtime — decrunchers in Shrinkler repo).

## 2026-07-04 — PopArt demo: interpretation, music, script (branch popart)

### Decisions
- **Interpretation first** (docs/INTERPRETATION.md): Pop Art = 4 operations
  (repetition, process-made-visible, arbitrary flat color, low subject at
  heroic scale). Rule: every effect must BE one of these operations executed
  by the hardware that natively does it (copper palette passes = silkscreen,
  Ben-Day dots = halftone, blitter = printing press). Styled-only effects
  rejected.
- **Subject: the floppy disk** as the consumer object (our own medium =
  the supermarket shelf). Not obvious; alternatives (soup can pastiche,
  Marilyn) rejected as copying Pop Art's *subjects* instead of applying
  its *method* to our own culture.
- **Music: kc-dancinonamiga.mod** (Katie Cadet, 3:09, 43 KB, 125 BPM).
  Why: verified Public Domain on module page (the modarchive cc-by BROWSE
  list is unreliable — applejuice-4mat listed under cc-by but its page says
  "Mod Archive Distribution license", unusable). Genre literally "Pop
  (general)"; 34 positions × 5.57 s = clean sync lattice; tiny. Runners-up:
  Drozerix "Silicon Dancer" (PD, 3:44, 253 KB — too long, 6× size).
- **Player: ptplayer 6.4** (Frank Wille, public domain, aminet) — scene
  best-of-breed, CIA-timed. tools/ptplayer/ pristine copy.
- **Sync via ptplayer song position/row, not frame counting**: CIA 125 BPM
  tick = exactly 50 Hz but PAL VBL = 49.92 Hz → ~15 frames drift over 3 min.
  Reading replayer state kills the drift; needs small documented patch to
  export mt_SongPos/mt_PatternPos.
- **bin/modinfo.py** written: MOD parser, playtime simulation (F/B/D
  commands), --sync prints time at each song position → scene table.
- **docs/SCRIPT.md**: 6 scenes on position boundaries 4/10/16/22/28/34.
  Transition = "squeegee pass" (copper bar wipe), no crossfades — Pop Art
  prints, it doesn't blend.

## 2026-07-04 — PopArt scenes 1+2 working

- Scene 1 (title print run): 8 halftone passes verified mid-print
  (paper pinholes visible in letters at pass 7), palette slams on kicks.
  Gotcha: forgot BPLEN in DMACON — flat color until bitplane DMA enabled.
- Scene 2 (Warhol grid): **BPLCON3 bank bits are write-side only** — they
  never affect which colors DISPLAY. First build showed 4 identical
  cells. Correct AGA mechanism: BPLCON4 BPLAM (XOR on pixel index) —
  palette k lives at color entries k*16, one copper BPLCON4 write per
  cell edge (per scanline: WAIT $05 / MOVE / WAIT $91 / MOVE, 16-byte
  stride, poked by CPU only on state change). Verified: 4 distinct print
  runs, clean split at x=160.
- bin/palvariants.py: 8 print-run palettes (4 hue rotations, sat pushed
  ×1.6+0.15 so even paper tints like silkscreen ink; 4 inverted
  "misprint" variants for the kick flash).
- mcp-gdb gotcha rediscovered: read_memory/registers HALT the target and
  leave it halted — always cont() after, or use monitor screenshot which
  is safe while running. Also: this FS-UAE build runs uncapped (~3x
  realtime) — wall-clock waits are unreliable, the music beacon is truth.

## 2026-07-04 — PopArt scenes 4-6, release build, full-run verification

### Scene 4 (WHAAM! comic panel)
- Cookie-cut stamps (A=mask B=bob C=D=screen, LF $ca), masks pre-expanded
  to all 5 planes so one blit per stamp; word-aligned positions, no shifts.
- **Bug 1**: overlapping stamp rects — TTL expiry restores the full rect
  from the pristine panel, erasing chunks of younger overlapping stamps.
  Fix: 3x3 non-overlapping position grid.
- **Bug 2**: stamp positions with odd byte offsets (x=8/216 -> offset 1/27)
  — blitter pointers must be even. Symptom: shredded partial bobs. Fix:
  x in {16,112,208}.
- White slam = 2 frames BPLCON0 planes-off + COLOR00 white; shake =
  decaying BPLCON1 values.

### Scene 5 (production line)
- ONE 384x64 band bitmap, 4 copper reloads of BPL1PT = 4 conveyor bands;
  hw scroll = fine BPLCON1 + coarse pointer step, net-left = 16w - v.
  DDFSTRT widened to $30 for scroll headroom (fetch 21 words, modulo 6).
  Two-tone palette per band via copper; queue advances on downbeat.

### Scene 6 (colophon) — misregistration is two pointers into ONE bitmap
- BPL2PT = BPL1PT - 40 (drops image 1px) + BPLCON1 PF2H=2 (2px right);
  palette %01 cyan / %10 magenta / %11 ink. Zero runtime cost.
- Song end: main loop calls _mt_end once (songdone flag), scene 6 slams
  paper magenta and prints the screen out with scene 1's dot passes on
  the shared plane — misregistered halftone flood, then freeze.

### Tooling
- `make INITPOS=n` — starts module (and therefore the whole music-driven
  demo) at song position n. Jump straight to any scene, music synced.
  Indispensable: emulator runs anywhere from 1x to 3x realtime, so
  wall-clock targeting of scenes is hopeless.
- Squeegee-wipe transitions from the script draft were cut: hard slam
  cuts on position boundaries are more honest to the print metaphor
  (documented in SCRIPT.md production note).

### Release + acceptance
- `make release`: Shrinkler 202,844 -> 84,660 bytes; ADF 90 KB / 880 KB.
- Full no-intervention run of demo-release.adf verified in emulator:
  title print-run -> Warhol grid (misprint flash caught) -> CMY dot
  plasma -> comic stamps (BANG!, slam frame caught) -> conveyor ->
  cards 1/2/3 -> song end -> magenta print-out freeze. Audio DMA $f
  throughout; scene cuts land on song positions.
