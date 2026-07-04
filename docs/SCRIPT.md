# POPART — Demo Script

Format: film script. Times from music start (frame 0 of scene 1).
Music: "DancinOnAmiga" by Katie Cadet (Public Domain), 125 BPM, 4/4,
34 song positions × 5.57 s = 3:09 total. One position = 64 rows = 2 bars.
**All scene cuts land on song-position boundaries** (read live from
ptplayer's song position — not frame counting, no drift).

Music map: pos 0-1 intro (pat 0, sparse: drums+bass), pos 2-9 A-section
(pat 1/2, horn hook enters), pos 10-11 breakdown (pat 0 again), pos 12-17
B-section (pat 3/4/5, synth chords), pos 18-25 A-section reprise,
pos 26-31 B-section reprise, pos 32-33 outro (pat 3).

Palette language for the whole demo (Warhol pop palette, flat, no
gradients except process-color ramps): hot magenta $F0C, cadmium yellow
$FD0, cyan $0CE, orange $F60, acid green $8E0, paper off-white $FED,
ink near-black $112.

Transition rule: every cut is a **squeegee pass** — a horizontal paper-
white bar (copper COLOR00 band, full width, ~40 px tall) sweeps top to
bottom in 12 frames; the new scene's copper list is swapped while the
bar covers mid-screen. Like a silkscreen squeegee dragging the next
color pass. No crossfades anywhere: Pop Art doesn't blend, it prints.

---

## SCENE 1 — "THE TITLE PRINT RUN" (pos 0-3, 0:00-0:22, 22 s)

FADE IN FROM: black (power-on).

VISUAL: Paper-white screen. The word **POP** upper-half, **ART**
lower-half — huge blocky letters filling the screen (bitmap, baked).
The letters are NOT drawn: they are *printed in halftone*. A field of
Ben-Day dots builds the letterforms: at t=0 the screen is blank paper;
each music row (8 frames) a new "print pass" stamps more of the dot
grid (blitter OR of a pre-shifted dot-screen mask through the letter
stencil), so the title emerges the way an image emerges on a silkscreen
— coarse dots first (16 px pitch), then finer interleaved passes
(8 px offset grid) sharpening it.

COLOR: dots print in ink near-black on paper. On the first horn stab of
pos 2 (0:11): background COLOR00 slams from paper to cadmium yellow.
Every downbeat after: background hops yellow → magenta → cyan → orange
(copper writes COLOR00, beat-synced from music row counter). Letters
stay ink. Bottom strip, small print: "a mass-produced audiovisual
product" in 1-plane text.

MUSIC: intro drums (pos 0-1) = dots stamping (one pass per bar).
Horn hook enters pos 2 = first background color slam.

CUT: squeegee pass at end of pos 3.

## SCENE 2 — "EDITION OF EIGHT" (pos 4-9, 0:22-0:55, 33 s)

VISUAL: The consumer object. A pop-art floppy disk (Flux-generated:
3.5" floppy, Lichtenstein treatment, bold outline, flat fills), one
image, 16 colors, 160×128, blitted into a **2×2 grid** — four identical
prints. Each cell wears a different palette: AGA palette banks, copper
writes BPLCON3 at each cell boundary (mid-scanline write at x=160 for
the left/right split — one word, AGA makes the silkscreen swap free).

MOTION: none. The image never moves — this scene is *only* repetition
and color. Every 2 bars (one song position) the four palettes rotate
one cell clockwise. On each downbeat, ONE cell (cycling) gets a 4-frame
inverted-palette flash — the misprint in the edition.

TEXT: none. The object speaks.

MUSIC: A-section groove. Palette rotation on position changes, cell
flashes on downbeats.

CUT: squeegee at end of pos 9, into the breakdown.

## SCENE 3 — "THE SCREEN ITSELF" (pos 10-15, 0:55-1:29, 34 s)

VISUAL: Process made visible: the halftone screen with nothing printed
on it. Full-screen field of **giant Ben-Day dots** (16×16 px cells,
20×16 grid) whose radii animate a slow two-sine plasma — the dot screen
breathing. Single bitplane of dots, CPU-rendered from a radius-indexed
tile table (16 dot sizes), double-buffered.

COLOR: paper background. Dot color banded by copper into three
horizontal process-color bands: magenta / yellow / cyan — the three
print heads. Bands' boundaries slide slowly (copper list rewritten per
frame). During the breakdown (pos 10-11) the plasma is barely moving —
flat dot grid, machine idling; when the B-section synths land at pos 12
(1:06), plasma amplitude jumps to full and the band boundaries start
moving. Dot phase resets (visible "thump" of the screen) on each
downbeat.

MUSIC: pat-0 breakdown = idle grid; B-section entry = full plasma.

CUT: squeegee at end of pos 15.

## SCENE 4 — "WHAAM!" (pos 16-21, 1:29-2:02, 33 s)

VISUAL: The comic panel. Background: Flux-generated comic-book explosion
panel (Lichtenstein pastiche: starburst, thick outlines, halftone
shading), 320×256, 32 colors, static. On EVERY snare hit (row mod 8 == 4
— read from row counter): a comic burst bob (starburst with
word) blitter-stamped at one of 8 pre-set panel positions, cycling
words **POP! / BANG! / ZAP! / WHAAM!** (4 bobs, 96×64, cookie-cut).
Each stamp lives 12 frames then is restored (double-buffered background
restore). On downbeats: 2-frame paper-white full-palette flash +
vertical screen shake (copper BPL pointers offset ±8 px decaying).

COLOR: background palette static; each stamped burst forces its own
sub-palette bank (AGA bank per bob region — bank switch above/below the
stamp row via copper).

MUSIC: A-section reprise: snare = stamp, downbeat = flash+shake. Loud,
dumb, heroic — the comic panel at gallery scale.

CUT: squeegee at end of pos 21.

## SCENE 5 — "PRODUCTION LINE" (pos 22-27, 2:02-2:36, 34 s)

VISUAL: Mass production. Four full-width horizontal **conveyor bands**
(64 px each), every band showing the same pre-tiled row of floppy-disk
prints (32×32 stamps of the scene-2 object, shrunk, tiled with even
gaps). All four bands display THE SAME band bitmap — copper rewrites
BPLxPT at each band boundary; the factory stores one row, prints four.
Bands hardware-scroll horizontally (BPLCON1 + coarse pointer step),
alternating direction per band, one disk-pitch per bar so stamps land
on beat.

COLOR: each band a different flat two-tone print (paper/magenta,
paper/cyan, ink/yellow, paper/acid-green) via per-band palette writes.
On downbeat: the band colors shift down one band (the print queue
advancing).

MUSIC: B-section reprise. Scroll speed locked to tempo.

CUT: squeegee at end of pos 27.

## SCENE 6 — "COLOPHON" (pos 28-33, 2:36-3:09, 33 s)

VISUAL: Credits as silkscreen prints. Three credit cards, ~11 s each
(2 positions per card), each card slammed on (no fade) with a small
squeegee pass. Text rendered as 2-plane misregistration: plane 0 =
text, plane 1 = same text offset (+2,+1) px; palette: %01 cyan,
%10 magenta, %11 ink — the off-register print that proves it's a print.

CARD 1 (pos 28-29):      POPART
                         a demo in six print runs

CARD 2 (pos 30-31):      music: "DancinOnAmiga"
                         Katie Cadet (public domain)
                         code+direction: Claude (Fable 5)
                         tools: vasm / vlink / ptplayer (Frank Wille)

CARD 3 (pos 32-33):      the image is the copy
                         the copy is the image
                         POPART — 2026
                         [small floppy-disk stamp, magenta]

MUSIC: B-section outro (pos 32 = outro pattern). On the final row of
pos 33 the music ends (mt_SongEnd): freeze card 3, background slams to
magenta, dots print over the whole card in 8 passes until the screen is
a solid halftone field — the demo prints itself out. Idle loop (machine
stays taken over; reset to exit — noted on card 3 in small print).

FIN.

---

## Timing implementation notes

- Scene switch = ptplayer song-position table lookup each vblank:
  `pos < 4 → scene1, < 10 → scene2, < 16 → scene3, < 22 → scene4,
  < 28 → scene5, else scene6`. Squeegee starts 12 frames before the
  boundary (position + row lookahead: row ≥ 58 of last position).
- Groove is swing (F05/F03 alternating, tempo 115): kick = row mod 8
  == 0 (downbeat), snare = row mod 8 == 4, bar = 16 rows, position =
  4 bars. All from ptplayer row counter (PatternPos/16), exported.
- Every effect double-buffers or is copper-only; target steady 50 fps
  except scene 3 (25 fps acceptable — dots may render every 2nd frame).
