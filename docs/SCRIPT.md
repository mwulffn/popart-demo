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

Transition rule: every cut is a **hard slam on the beat** — the new
scene's copper list replaces the old one at the vblank of a song-
position boundary, no fade, no wipe. (Production note: the original
draft specified a "squeegee pass" wipe; cut during implementation —
the straight jump cut on the downbeat is more honest to the print
metaphor and to how silkscreen editions actually land: one pull, next
sheet. Documented in journal.md.) No crossfades anywhere: Pop Art
doesn't blend, it prints.

---

> **REVISION (canvas cut):** pacing pass + one new scene, 3:09 total
> unchanged. Title and conveyor halved (both overstayed their one
> idea), freed positions fund SCENE 5C "THE CANVAS" — the full-screen
> 256-color print. New map: title 0-1, warhol 2-7, dots 8-9, dive
> 10-13, comic 14-17, conveyor 18-19, brillo 20-23, canvas 24-27,
> credits 28-33. Every cut stays on a pattern change.

## SCENE 1 — "THE TITLE PRINT RUN" (pos 0-1, 0:00-0:11, 11 s)

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

COLOR: dots print in ink near-black on paper. The scene is split down
the middle: pos 0 = the print run, all 8 passes at two per bar, paper
background; pos 1 = the payoff, finished title riding background
COLOR00 slams — yellow → magenta → cyan → orange, one per kick.
(Revision note: the four-position original had the same two halves
but 11 s each; halved, the structure survives — build, then slam —
with no dead time.)

MUSIC: intro drums pos 0 = dots stamping (one pass per half-bar);
pos 1 = kick-synced background slams. Horn hook enters pos 2 = the
cut itself.

CUT: hard slam at end of pos 1, on the horn entry.

## SCENE 2 — "EDITION OF EIGHT" (pos 2-7, 0:11-0:45, 33 s)

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

CUT: hard slam at end of pos 7.

## SCENE 3 — "THE SCREEN ITSELF" (pos 8-9, 0:45-0:56, 11 s)

VISUAL: Process made visible: the halftone screen with nothing printed
on it. Full-screen field of **giant Ben-Day dots** (16×16 px cells,
20×16 grid) whose radii animate a slow two-sine plasma — the dot screen
breathing. Single bitplane of dots, CPU-rendered from a radius-indexed
tile table (16 dot sizes), double-buffered.

COLOR: paper background. Dot color banded by copper into three
horizontal process-color bands: magenta / yellow / cyan — the three
print heads. Bands' boundaries slide slowly (copper list rewritten per
frame). For its first position (pos 8) the plasma is barely moving —
flat dot grid, machine idling; at pos 9 amplitude jumps to full and
the band boundaries start moving. Dot phase resets (visible "thump"
of the screen) on each downbeat.

MUSIC: A-section groove throughout; the idle→full jump is the scene's
own build, one position each.

CUT: hard slam at end of pos 9 — the camera falls INTO the screen.

## SCENE 3B — "THE DIVE" (pos 10-13, 0:56-1:18, 22 s)

VISUAL: The technical flex. Full-screen **rotozoomer** (chunky pixels,
CPU-rendered, Kalms c2p to 4 AGA bitplanes, line-doubled by copper):
the texture is the floppy print itself, tiling to infinity. The camera
is inside the halftone: through the breakdown (pos 10-11) we are so
close the Ben-Day dots are boulders, slowly rotating — the sparse
drums are the dolly's pace; the camera pulls out and the dots resolve
into the floppy, then into a FIELD of floppies repeating to the
horizon — the edition unbounded; when the B-section synths land at
pos 12 the spin accelerates and the zoom breathes with the music.

COLOR: the 16-color floppy palette. On every kick the whole world
flashes one of the scene-2 print-run variants for 2 frames (BPLCON4
palette shift — the silkscreen pass applied to all of reality).

MUSIC: breakdown = slow dolly, B-section = acceleration. Kick =
variant flash + zoom pulse.

CUT: hard slam at end of pos 13.

## SCENE 4 — "WHAAM!" (pos 14-17, 1:18-1:40, 22 s)

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

MUSIC: B-section tail into the A-reprise: snare = stamp, downbeat =
flash+shake. Loud, dumb, heroic — the comic panel at gallery scale.

CUT: hard slam at end of pos 17.

## SCENE 5 — "PRODUCTION LINE" (pos 18-19, 1:40-1:51, 11 s)

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

MUSIC: A-section reprise. Scroll speed locked to tempo. (Revision
note: halved from four positions — a conveyor belt makes its point in
two bars; by the third the eye has priced it.)

CUT: hard slam at end of pos 19.

## SCENE 5B — "BRILLO BOX" (pos 20-23, 1:51-2:13, 22 s)

VISUAL: Warhol put the supermarket carton on a gallery plinth; we put
the floppy in 3D space. A **real-time flat-shaded vector floppy** —
box body, shutter and label as raised face details — tumbling at
heroic scale, blitter line-drawn and blitter-filled, double buffered.
Faces in flat pop colors with THICK BLACK OUTLINES: not a rendering,
a printed cartoon of an object that happens to rotate. No gouraud, no
gradients — Pop Art doesn't shade, it fills.

COLOR: each visible face holds one flat color from the pop palette;
on every downbeat the face-color assignment rotates one step (the
print queue advancing across the object). Background paper.

MUSIC: A-section reprise; halfway through (pos 22) the tumble speed
kicks up a notch.

CUT: hard slam at end of pos 23.

## SCENE 5C — "THE CANVAS" (pos 24-27, 2:13-2:36, 22 s)

VISUAL: The finished work. After five scenes of process — screens,
stamps, conveyors, cartons — the demo finally hangs a painting: one
full-screen **256-color print** (320×256, 8 AGA bitplanes, 64-bit
fetch — the whole palette register file used at once), Flux-generated
in the house style: Lichtenstein weeping girl, Ben-Day dots, bold
outlines, holding up a floppy disk. The scene-2 object returns as
*subject matter* — the consumer good promoted to art object.

MOTION: none. Nothing animates, nothing scrolls, no copper tricks —
the one scene in the demo that does not move is the one that shows
the art. (Demoscene tradition: the hand-pixeled gallery picture,
displayed with pride and zero irony.)

COLOR: all 256 of them — the demo's palette-restraint thesis broken
exactly once, for the masterpiece.

MUSIC: A-reprise tail; when the B-reprise lands at pos 26, one
2-frame paper flash — the last squeegee pass of the demo.

CUT: hard slam at end of pos 27.

## SCENE 6 — "COLOPHON" (pos 28-33, 2:36-3:09, 33 s)

VISUAL: Credits as silkscreen prints. Three credit cards, ~11 s each
(2 positions per card), each card slammed on (no fade) with a small
squeegee pass. Text rendered as 2-plane misregistration: plane 0 =
text, plane 1 = same text offset (+2,+1) px; palette: %01 cyan,
%10 magenta, %11 ink — the off-register print that proves it's a print.

CARD 1 (pos 28-29):      POPART
                         a demo in nine print runs

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
  `pos < 2 → title, < 8 → warhol, < 10 → dots, < 14 → dive,
  < 18 → comic, < 20 → conveyor, < 24 → brillo, < 28 → canvas,
  else credits`.
- Groove is swing (F05/F03 alternating, tempo 115): kick = row mod 8
  == 0 (downbeat), snare = row mod 8 == 4, bar = 16 rows, position =
  4 bars. All from ptplayer row counter (PatternPos/16), exported.
- Every effect double-buffers or is copper-only; target steady 50 fps
  except scene 3 (25 fps acceptable — dots may render every 2nd frame).
