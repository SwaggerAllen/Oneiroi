# Licensing

Three trees, two licences, and the split is load-bearing (spec §2.1,
`design/decisions-log.md`'s audit):

| Tree | Licence | Why |
| --- | --- | --- |
| the root (the core and the client) | AGPL-3.0-or-later (`LICENSE`) | the platform; served, never conveyed |
| `components/daedalus/` | Apache-2.0 (`components/daedalus/LICENSE`) | lifted from Catapult under that licence, and consumed by the SDK |
| `sdk/` | Apache-2.0 | the package other agent platforms embed; copyleft would impose terms on them |

Never copy core code into `components/daedalus/` or `sdk/`, and never
add a copyleft dependency under either: `mix oneiroi.audit`'s license
check holds each Apache tree's dependency closure to the allow list its
`mix.exs` states. New files take their directory's licence.

## Quotations

The quotations that open `README.md`, `design/names.md` and the
`systems/` docs are a few lines each, reproduced from the translations
they credit, as quotation with attribution. They are not licensed under
either licence above: a translation still in copyright stays its
translator's. A doc that needs more than a few lines of one picks a
public-domain translation instead, and every quotation names its
translator so that choice can be checked.
