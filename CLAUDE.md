# demo-fable — Amiga demo project

Amiga (A1200, Kickstart 3.1) demo development on macOS. See `journal.md`
for the running development log — append an entry after each significant
milestone or discovery.

## Layout
- `kickstart/` — Kickstart 3.1 rev 40.68 A1200 ROM (do not commit
  elsewhere/redistribute. MUST be purged before publication — it is in
  git history since the root commit, so `git rm` is not enough: rewrite
  history, e.g. `git filter-repo --path kickstart --invert-paths`)
- `tools/fs-uae-gdb/` — GDB-patched FS-UAE (from uae-dap 1.1.5 npm package,
  WinUAE 5.1.0 core, x86_64 via Rosetta)
- `tools/mcp-gdb/` — debug MCP server (adopted from mariposa-2, rewritten
  to speak GDB-RSP directly)
- `config/a1200.fs-uae` — emulator config (also works with plain brew fs-uae)
- `bin/run-emulator.sh` — launch emulator with GDB server on port 2345
- `bin/screenshot.py` — capture PNG via GDB monitor command
- `tools/comfyui/` — ComfyUI checkout + venv (gitignored), models from
  `~/ComfyUI-Shared/models` via `extra_model_paths.yaml`
- `bin/comfyui-server.sh` — launch ComfyUI server on 127.0.0.1:8188
- `bin/generate-image.py` — Flux.2 image generation CLI (see below)
- `screenshots/` — output dir (gitignored)
- `journal.md` — development journal
- `tools/bin/` — vasmm68k_mot + vlink (gitignored; rebuild from
  sun.hasenbraten.de tarballs)
- `src/` — demo source (`main.asm`, `startup-sequence`)
- `Makefile` — `make` = vasm → vlink → bootable ADF (`build/demo.adf`,
  gitignored); `make run` boots it in the emulator

## Asset pipeline

```sh
bin/png2amiga.py in.png -o build/art --colors 32 --scale 320x256 --preview
bin/png2amiga.py logo.png -o build/logo --colors 16 --mask     # + .msk plane
bin/png2amiga.py font.png -o build/font --colors 4 --tile 16x16
```
Emits `.bpl` (planar, interleaved default), `.i` (constants + palette),
optional `.msk`/preview. `--mask` reserves index 0 as transparent.
Full chain: `generate-image.py` at 2x size → `png2amiga.py --scale` down.

## Build & boot cycle

```sh
make                                  # build/demo.adf (xdftool from amitools)
make release                          # shrinkled exe → build/demo-release.adf
debug_start(extra_args="--floppy_drive_0=/abs/build/demo.adf")  # gdb MCP
# wait ~25 s (kickstart + floppy boot), then screenshot() to verify
```

Target machine: **A1200, 2 MB chip + 4 MB fast RAM** (fast_memory=4096 in
config, launcher, and mcp-gdb server.py). Demo fits one 880 KB ADF.
Key asm facts: `-m68020 -Fhunk`; chip-RAM data (copper lists, bitplanes,
samples) goes in `section name,data_c` — code/data hunks load into fast
RAM. DOS-loaded exe via `s/startup-sequence`, takes over machine after
load (no OS exit yet — reset to leave).

## Debugging: use the `gdb` MCP server (preferred)

`tools/mcp-gdb/` — registered as MCP server `gdb`. Holds the one allowed
GDB connection persistently. Typical cycle:

```
debug_start()                 # launches FS-UAE, connects, boots kickstart
registers() / read_memory("0xdff000", 32) / step() / breakpoint("0x...")
cont(); screenshot("/abs/path.png")   # screenshot works while running
debug_stop()
```

Do NOT drive real gdb against the emulator — the stub violates RSP
(`vMustReplyEmpty` → `E01`) and GDB >= 8 aborts. The MCP server speaks
RSP directly. Details: `tools/mcp-gdb/README.md`, journal.md.

## Manual emulator workflow (fallback, no MCP)
```sh
bin/run-emulator.sh &                      # boots A1200 kickstart, gdbserver on :2345
python3 bin/screenshot.py /abs/path.png --boot-wait 5
```

Key facts:
- Emulator **halts waiting for GDB** at startup (up to 200s), then boots.
  Send `vCont;c` / `c` to resume immediately.
- **One GDB session per emulator launch** — server never re-listens after
  disconnect. Everything must flow through that single connection.
- Emulator log with GDB packet trace: `~/Documents/FS-UAE/Cache/Logs/fs-uae.log.txt`
- Monitor commands: `screenshot <path>`, `profile`, `console <uae-dbg-cmd>`
  (full WinUAE debugger), `dumpdma`

## Image generation (Flux.2 dev, local)

```sh
bin/generate-image.py "prompt" -o /abs/path.png [--width 640 --height 512] \
    [--seed N] [--steps N] [--no-turbo]
```

- Auto-starts ComfyUI server if down. First generation ~4 min (94 GB model
  load), warm runs ~2 min at 640x512. Server log: `tools/comfyui/server.log`
- Defaults: Turbo LoRA, 8 steps, guidance 2.5. `--no-turbo` = 20 steps,
  guidance 4.0, better quality but ~2.5x slower
- Dimensions must be multiples of 16
- Models in `~/ComfyUI-Shared/models/`: `flux2_dev_bf16_dequant` (made by
  `tools/convert-fp8-to-bf16.py` — the original fp8mixed checkpoint fails
  on MPS, no fp8 kernels) + `mistral_3_small_flux2_bf16` encoder + Turbo LoRA

## Conventions
- Screenshots: always absolute paths (emulator cwd differs from project)
- Verify graphics changes by booting + screenshot, not by assumption
