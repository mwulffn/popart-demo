# PopArt — Interpretation

Written before any code, per brief.

## What Pop Art did

Pop Art (Warhol, Lichtenstein, Hamilton, Rosenquist, ~1955–70) took the
*mass-produced commercial image* — the ad, the comic panel, the soup can,
the publicity photo — and moved it, unchanged but enlarged, into the
gallery. Its core operations:

1. **Repetition as subject.** Warhol's Marilyn/soup-can grids: the same
   image printed over and over, each pass in different flat colors. The
   repetition *is* the artwork — it's about mechanical reproduction
   replacing the unique art object.
2. **The printing process made visible.** Ben-Day dots (Lichtenstein),
   silkscreen misregistration (Warhol), CMYK separations. Pop Art doesn't
   hide the reproduction technology — it blows it up until the *process*
   is the picture.
3. **Flat, non-naturalistic color.** Colors assigned by the printing
   plate, not by nature: a face can be pink, orange, or green because
   each print run swaps the palette.
4. **Low subject, high treatment.** Consumer objects and comic-book
   melodrama ("WHAAM!") rendered at heroic scale with total technical
   seriousness.

## Why the Amiga is the right instrument

The mapping is not decoration — it's structural. The Amiga's hardware
*is* a mass-reproduction machine with the same primitives Pop Art
fetishized:

- **Copper palette swaps** = silkscreen color passes. One bitmap, N
  palettes down the screen: literally Warhol's Marilyn grid, executed by
  the display hardware. The image is stored once; the "print runs" are
  free.
- **Ben-Day dots** = halftone rendering. A chunky intensity field
  rendered as a dot grid is Lichtenstein's screen blown up to CRT scale.
  The dots aren't a filter on the effect — the dots ARE the effect.
- **The blitter** = the printing press. Stamping the same bob dozens of
  times per frame is mechanical reproduction as performance.
- **Misregistration** = dual playfield / offset planes. Cheap on Amiga,
  and it's exactly the silkscreen slippage Warhol kept because it proved
  the process.

## The rule for every scene

Every effect must be one of Pop Art's four operations (repetition,
process-made-visible, arbitrary flat color, low subject at heroic scale)
implemented by the piece of Amiga hardware that natively does that
operation. If an effect is merely *styled* pop-art (a nice picture with
dots on it), it's out. The transitions likewise: color-pass flashes and
print-run wipes, not fades.

## Subject matter

One consumer object as the recurring "can": we use the **floppy disk**
itself — the demo's own distribution medium, the scene's own consumer
object, mass-produced, copied, traded. Warhol took the object from the
supermarket shelf; we take ours from the disk box. Secondary subjects:
the comic-panel exclamation (for the impact scene) and the credits as a
silkscreen print run.
