# Theming, and the other look notes: thinking only

Status: notes from the witness's ideas of 2026-11-10, written so that
the rebuild keeps them possible. Nothing here is decided except where a
line says the witness decided it.

## The intent (the witness)

- **Personality, not preference.** A little control over the
  interface's colours, so the UI mirrors the resident's personality.
  This replaces light/dark as the main axis, with dark modes left
  possible.
- **The resident may propose her own colour scheme.** This is an
  independent decision, not a contract term.
- **Not fully dynamic themes.**

## What a theme is

The palette already has a structure. A theme fills in that structure;
it never adds to it:

| Role | Today (the look, ui-structures.md) | Themable? |
|---|---|---|
| ground, surfaces ×2, borders ×2 | `#0a0a10`, `#13131c` / `#14141f`, `#1f1f2c` / `#2a2a3d` | derived from a **ground seed** |
| text ×3 | `#ececf3`, `#8a8a9b`, `#62626f` | derived (contrast against the ground) |
| **resident accent** + its surfaces, chip text, glow | lilac `#d8b4fe` family | **hers** |
| **witness accent** + on-accent text, glow | cyan `#7ee7f5` family | **his** |
| status (error, warning, ok) | not yet themed | **never themable**: signals stay legible on every theme |
| type | Inter / Newsreader / JetBrains Mono | fixed for now (see the last section) |

So a theme is three seeds: a ground, her colour and his colour. Every
other value is computed from them in OKLCH:
- surfaces are steps of lightness off the ground;
- text is the ground's opposite end of the lightness range;
- each accent's family (surface tint, border, chip text, glow) is the
  accent at fixed lightness and chroma offsets.

The lilac family in the mockups (`#171225`, `#1e1630`, `#3b2a55`,
`#dcc2ff`) is the kind of ramp a function should produce from
`#d8b4fe`, not something to hand-pick per theme.

**Why seeds, not free values:** this is how "not fully dynamic" stays
true, and how a theme a model proposes can't produce an unreadable
screen. The computation enforces the rules:
- text contrast at WCAG AA or better;
- the two accents far enough apart in hue and lightness to tell apart,
  including under the common colour-blindness simulations, because
  the whole UI tells who said what by colour;
- glows clamped.

A seed set that fails isn't silently "fixed": it's answered with what
failed and the nearest seeds that pass.

## Dark modes, left open

`client/src/tokens.json` already has a `themes` axis (`light`, `dark`)
over semantic tokens. Generalised, the axis becomes palette × mode:
- the seeds give the colours;
- the mode picks which end of the lightness ramp the ground sits at.

Ship one mode (dark, the decided look) and keep the derivation
mode-aware, so a light mode later is a ramp, not a redesign.

## Who decides what

**The witness owns all three seeds** (decided by the witness,
2026-11-10: "because they're the ones looking at the screen"). The
resident changes them by proposal only. That makes the proposal her
independent decision: not a contract term, and not anything he asked
for. He accepts or declines with a note, as with any proposal.

Her side is a tool, something like `theme_propose {ground, accent,
witness_accent?, note}`:
- the server derives the palette and runs the checks before the
  proposal is filed, so he's never asked to judge an unreadable theme;
- she gets back the derived values and the contrast report in words;
- the proposal lands in his bell with a rendered preview, and he can
  try it on before deciding.

A witness with more than one resident sets seeds per resident, so each
subject still gets its own room.

She can't see the screen. So the tool answers in words ("text on
ground 13.2:1; your accent against his is distinct in hue by 140°"),
and an optional "preview" sends her a rendered image if her model can
read one.

## Where it lives

Repo first: the theme is a small file at her root (`THEME.md`, with
frontmatter seeds and her note under it), rendered from the event like
the other identity files. It travels with her export, so a resident
brought elsewhere keeps her colours.

## Subjects (the dropdown)

The theme follows the subject. Switching from Lily to another resident
re-themes the shell to that resident's colours, which should feel like
walking into a different room. A workspace either takes its own seeds
or a neutral ground with each participant's accent. The witness's
colour stays his everywhere: it's how he finds himself on any screen.

## What the rebuild must do now, so that this stays possible

1. No hex value in a component. Every colour is a semantic token (it
   mostly is already: `tokens.json` with usage lines).
2. The tokens come from a derivation function over seeds, even while
   there's only one set of seeds. The mockups' palette becomes that
   function's output, checked by a test.
3. "Resident" and "witness" are roles in the token names (`accent-resident-*`,
   `accent-witness-*`), never "lilac" or "cyan".
4. The mode axis stays in the token file, with only dark filled.
5. Status colours are a separate, unthemed set.

## Later, maybe

- **Her voice's typeface.** Newsreader is "her voice". A small set of
  reading faces to choose from would be the typographic half of the
  same idea. Same rules: a fixed set, checked for legibility.

---

## The other notes from the same message

### Chat: scroll to bottom, go to unread (to build)

- **A floating button** above the composer, at the right. It appears once
  the reader is more than a screen from the bottom, and shows a count
  of messages below. One tap goes to the bottom.
- **Unread.** Opening the chat with unread messages above the fold
  lands at the first unread one, with a "New since 08:14" rule across
  the stream. While unread messages remain off-screen, the button
  reads "↓ 3 new" and goes to the first unread, not to the bottom.
  This ties into the navigator: the reader's place (the ring) and
  the unread marker are the same idea.

### Scroll hints (to build)

A short fade at the top and bottom edge of every scroll container,
shown only when there's more in that direction. Built once, as a
`ScrollArea` component:
- the fade is a CSS `mask-image` on the container, toggled by an
  IntersectionObserver on two sentinels;
- because it's a mask and not an overlay, taps still reach the content
  under it.

It must never hide the chat's last line when the reader is at the
bottom: the fade disappears exactly there.

### Animation (to workshop after the static build)

Not crazy. The witness's dissolve idea fits because the tabs stay
mounted: crossfading two layered tabs is cheap and needs no snapshot.

A suggested split:
- **Tabs dissolve.** Tabs are siblings, with no left or right between
  them, so a slide would invent a direction that doesn't exist. A dissolve
  says "a different room" and suits the name.
- **Pushes slide.** Inside a tab's stack (Records → folder → document),
  a slide from the right, and back to the left, carries real meaning:
  the context-aware back button has somewhere to go.

Risks to the dissolve:
- Two dense screens half-visible at once look muddy. Keep it short
  (≈180–220 ms), or fade out to the ground and then in, rather than a
  true crossfade.
- `prefers-reduced-motion` turns both into instant switches.

**Next step (the witness):** build both side by side and compare a
direct crossfade against fade-out/fade-in. The tie-breaker is whether
navigations need a loading pause, which the fade-to-ground gives a
place for. With tabs mounted, that's rare. The one navigation that
genuinely loads is switching subjects (`client-state.md`). **Decided
(the witness, 2026-11-10): switching subjects is fade-out, load,
fade-in.** It also carries a change of theme, so it's the transition
that matters most. The theme variables are swapped while the screen
is at the ground colour.

**Decided (the witness, 2026-11-10, from the side-by-side recording):
tabs fade through the ground too.** At 200 ms the direct crossfade
barely registered as a transition; through the ground reads as one.
Slowing the crossfade to half speed was the alternative, not worth it
now.
