---
paths:
  - client/**
  - storybook/**
---

# client

The React application and its Storybook. Spec §6.15. The skeleton is in
the tree (Vite, React 19, Storybook and the design system's tokens,
P0.3); no screen is. This doc is its file map, the standing decisions
the spec already records, and the phase that builds it, so a design
pass reaching for it finds a record rather than a gap.

## #1 Owns

`client/**`, the skeleton so far, and `storybook/**`, nothing yet.

## #2 Standing decisions

Carried from spec §6.15; the reason for each is there.

- **#3 Mobile-first, built only against the OpenAPI client and the typed channel client.**
- **#4 One Storybook story per state per screen, which is what the design agent produces and the manual test gate drives.**
- **#5 Built from the Oneiroi design system: `tokens.json` unchanged, the twenty components under `client/src/components/` as the only source for those patterns, with the five rules they enforce (attribute everything; the resident's words are never editable by the steward; every approval carries a note; refusal renders in the resident's words; the check-engine light reports the engine).**

## #6 Initial vs target

Initial: the skeleton, P0.3; see spec §6.15. Target: the whole of spec §6.15,
built in P0.3 (the skeleton), P1 (spec §14).

## #7 Depends on

The platform and whatever spec §14's row for its phase names.
