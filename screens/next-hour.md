---
paths:
  - client/src/next/hour/**
---

# next-hour

The public hour (apsu#29), at `#/hour`, open to anyone, signed in or
not, linked from the landing page's footer.

- The window, the next refresh, the commit and when the platform last
  started.
- What it is in one paragraph: every request, job and turn in
  five-minute buckets, times and never words, nothing about any one
  person, and a count under five read as "few".
- **Work per five minutes:** twelve bars, oldest first, each titled with
  its time, count and p95; "few" draws a sliver.
- **By unit of work, slowest first:** kind and name, count, failed, p50,
  p95, mean time in queries and waiting for a connection; a unit with a
  "few" count has no timings. Scrolls sideways on a phone.
- **Pressure now:** background jobs waiting and the oldest's wait, and
  the failures logged this hour by kind.
- Read every minute while open (`GET /v1/hour`, cached for a minute).
