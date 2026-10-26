# Licensing

Three trees, two licences, and the split is load-bearing (spec §2.1,
`design/decisions-log.md`'s audit):

| Tree | Licence | Why |
| --- | --- | --- |
| the root (the core and the client) | AGPL-3.0-or-later (`LICENSE`) | the platform; served, never conveyed |
| `components/substrate/` | Apache-2.0 (`components/substrate/LICENSE`) | lifted from Catapult under that licence, and consumed by the SDK |
| `sdk/` | Apache-2.0 | the package other agent platforms embed; copyleft would impose terms on them |

Never copy core code into `components/substrate/` or `sdk/`, and never
add a copyleft dependency under either: `mix oneiroi.audit`'s license
check holds each Apache tree's dependency closure to the allow list its
`mix.exs` states. New files take their directory's licence.
