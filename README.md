# PopArt

An Amiga A1200 (AGA, Kickstart 3.1) demo: nine scenes of copper palette
swaps, Ben-Day dot halftones, blitter bobs, and a 256-color full-screen
print, synced to a public-domain mod track. ~3:09, 68020, fits on one
880 KB floppy.

## What this actually is

**This is an exercise in autonomous AI development, not an Amiga demo
anyone should treat as a reference.** The code, tooling, asset pipeline,
and this repo's history were built end-to-end by Claude Code (Anthropic)
working with a human collaborator steering at the prompt level — writing
68k assembly, driving a GDB-patched emulator to verify every effect on
real hardware timing, generating art via a local diffusion model, and
cleaning up the repo for publication.

It's shared as a record of how far that kind of collaboration can go,
not as demoscene craft. If you want to learn real Amiga demo coding,
go read actual scene productions and their source — this project took
a lot of shortcuts and hand-holding that a human-only production
wouldn't need, and almost certainly has rough edges a real demo coder
would wince at.

## Building

Requires macOS with `vasm`/`vlink`/Shrinkler in `tools/bin/` (gitignored,
build from source — see `CLAUDE.md`), `uv` for the Python asset
generators, and `xdftool` (from [amitools](https://github.com/cnvogelg/amitools))
on `PATH` at `~/.local/bin/xdftool`.

```sh
make          # build/demo.adf — bootable floppy image
make run      # boot it in a plain fs-uae, if installed
make release  # Shrinkler-crunched exe on the disk
```

Running it for real needs a Kickstart 3.1 ROM, which is **not included**
(see Licensing below) — point `config/a1200.fs-uae` or your own emulator
config at a legally obtained copy.

## Layout

See `CLAUDE.md` for the full map (build system, debug workflow, asset
pipeline). Short version: `src/` is the 68k source (framework + one file
per scene), `assets/` holds the original PNG art sources, `music/` the
mod, `docs/` the design brief and shot-by-shot script, `journal.md` the
development log.

## Licensing

The project's own code (`src/`, `bin/`, `tools/mcp-gdb/`, `config/`,
`Makefile`) is MIT — see `LICENSE`.

Not included, not covered by that license, and not redistributable:
- A Kickstart ROM (Cloanto/Hyperion copyright).
- A GDB-patched FS-UAE build used for development (WinUAE-core license
  restricts redistributing modified builds).

Bundled under their own terms:
- `music/kc-dancinonamiga.mod` — "DancinOnAmiga" by
  [Katie Cadet](https://modarchive.org/index.php?request=view_profile&query=84804),
  Public Domain (`music/LICENSE.md`).
- `tools/ptplayer/` — Frank Wille, Unlicense/public domain
  (`tools/ptplayer/LICENSE`).
- `tools/kalms-c2p/` — Mikael Kalms' c2p collection, Public Domain
  (`tools/kalms-c2p/readme.txt`).

`assets/*.png` are original art generated locally with a Flux.2 model
for this project.
