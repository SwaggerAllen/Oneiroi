# apsu: reasons

## #3
A setting nobody can explain is one every operator sets for nothing, and
a number nobody measured is a guess that survives review; the boot report
is too late to learn either. Spec §6.16, conventions §13.

## #4
Leaving either number implicit is how a platform's probe and an app's
listener come to disagree; Catapult's `render.yaml` records the same
pair for the same reason.

## #5
Catapult measured the module-plug form putting its endpoint at three
compile-connected references and the function-plug form at zero; the
ratchet is armed at zero and every later value is a concession.

## #6
Measured on Catapult (its `mix.exs` records it): a clean `mix compile
--force` and a `mix compile` that reports every substrate call as
forbidden, so the second gate run in a CI job fails on state rather than
code.

## #7
A check that accepts several spellings lets a block drift out of the one
it reads while still looking read; the substrate's `oneiroi:required-env`
fence is the same discipline for the same reason.

## #8
The pipeline escalates two CI reds to a human, so the pressure on a red
test is to skip it; a skip with no owner is a test nobody un-skips.

## #9
A log line nothing can parse is a log line nobody reads at 3am; a log
line carrying a turn's text is a transcript in the wrong store
(conventions §10).

## #12
Spec §7: the application role cannot bypass RLS. One credential and
`SET ROLE` gives the same guarantee whether or not the managed database
lets the owner create a login role, so the deploy does not wait on the
measurement; the tenancy test asserts the role and that DDL is refused.

## #13
A query that forgets its scope sees every tenant's rows, and nothing
about its result says so; raising is the only failure that cannot be
read as success (conventions §12).

## #14
A table without a policy is a tenancy hole the suite cannot see, since
a test seeding one resident passes against it; the lint reads the
migrations because the hole is in the DDL, not the code.

## #15
An event without its actor cannot be attributed, and an approval without
a note is one the resident cannot read first (conventions §6, spec §3.1).
Refused at dispatch because a warning is a log line.

## #16
Measured here: the aliases put both routers, both projectors and every
events file on the compile-connected graph, fifteen edges against a
ratchet at zero, and Catapult's router records the same compiler
behaviour. A dep-free macro module is the honest zero.

## #17
`mix deps.audit` refused `cloak`/`cloak_ecto` (CVE-2026-95105 and
CVE-2026-94206, no fixed release at the time); forty lines over
`:crypto` cost less than a baseline entry that re-blinds the gate.

## #18
A second-precision fake broke the first `:utc_datetime_usec` insert;
per-process because a projector's clock is not the test's.
