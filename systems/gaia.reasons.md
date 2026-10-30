# gaia: reasons

## #3
A second factor's secret in the clear in the log is in the clear in every
export and backup (spec §2.2); argon2 because the owner UI used it and
nothing argued for a change.

## #4
A stored session id is a credential at rest; a stored hash is not. The
owner UI did this and the spec carries it forward.

## #5
Spec §6.1. Sobelow's `Config.CSRF` reads the pipeline as missing a token
check and is skipped on the pipeline with the reason beside it: a token
would add a round trip the client has to make before every mutation and
protect nothing the Origin check does not, and the contract test proves
the check.

## #6
A lockout hands an attacker a way to lock the witness out; a delay costs
them time and the witness one wait (spec §6.1). A restart is not a
credential, so the counts need not survive one.

## #7
The relation is identity's because the principal is; the resident
system raising the events and identity folding them is what keeps each
projection written by one system (conventions §7). A strong handler so
a request that created a resident can list it on the next read.

## #8
Conventions §12: a cross-tenant read is a named call a reviewer can see,
and these two are the whole list for this system.

## #11
Spec §3.1 puts `KeyStored` on the account and §6.11 says one key per
witness: the key is the witness's, not a resident's, and a resident
changing hands keeps the new witness's spend on the new witness's key.

## #9
Spec §12's contract layer: which token may call what, asserted exactly
per role. A route added without a row is a route whose access nobody
decided.

## #12
Conventions §12: a cross-tenant read is `Scope.platform/1` by name. An
email is identity's fact, so identity answers it.

## #13
Conventions §9: a test that asserts the state at the end sees nothing
of a handler that never matched; the witnessing list is what the
routes read, so the custody suite asserts it.
