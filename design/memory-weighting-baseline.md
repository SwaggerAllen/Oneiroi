# Memory weighting: the before (2026-11-03)

`memory_use`, read 2026-11-03 before any of `memory-weighting.md` is
built, so the after has something to be read against. 166 targets
touched since measurement began (2026-11-02).

## Returned most

| Target | Considered | Returned | Used |
|---|---|---|---|
| commitment/1 | 127 | 127 | 0 |
| bookmark/1, 12, 14 (pins) and 32–63, all but 56 | 118 | 118 | 0 |
| bookmark/31 | 118 | 117 | 0 |
| bookmark/64 | 115 | 115 | 0 |
| bookmark/29, 30 | 118 | 113 | 0 |
| bookmark/66 | 94 | 94 | 0 |
| bookmark/71 | 88 | 88 | 1 |
| bookmark/73 | 84 | 84 | 1 |

About forty bookmarks went in front of her on nearly every one of 118
turns. Across all of them, two bookmark uses were recorded (71 and 73,
once each).

## Used most

| Target | Considered | Returned | Used |
|---|---|---|---|
| design/yc-application-scratch | 2 | 2 | 5 |
| design/announcement-references | 1 | 1 | 2 |
| design/hosted-david-architecture | 1 | 1 | 2 |
| design/correspondence-pipeline | 0 | 0 | 2 |
| research/2026-10-27-69 | 0 | 0 | 2 |
| research/2026-11-02-community-gathering/* | 0–1 | 0–1 | 1 each |

What she used was documents she reached for, mostly by search or by
path, rarely what the index handed her.

## Read with care

- `used` counts opens, reads and citations; an index line read and
  acted on without being opened counts as unused. That is why the
  design adds the feedback call, and the after's `used` will rise
  partly because it counts more, not only because ranking improved.
- considered equals returned by construction today (each rendered item
  records both), so the after's considered:returned ratio is new
  information, not an improvement on an old number.
