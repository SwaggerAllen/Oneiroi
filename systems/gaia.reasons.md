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

The unopened session was split out on 10-31: the steward's login answered
401 invalid credentials during a deploy's overlap, when the session's
dispatch timed out waiting on a projector, so a right password read as a
wrong one and each retry of it grew the delay. A wrong answer about the
password is worse than none; the throttle exists to slow guessing, and a
verified password is not a guess.

## #7
The relation is identity's because the principal is; the resident
system raising the events and identity folding them is what keeps each
projection written by one system (conventions §7). A strong handler so
a request that created a resident can list it on the next read.

## #8
Conventions §12: a cross-tenant read is a named call a reviewer can see,
and these two are the whole list for this system.

## #14
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

## #15
He knew the check-ins were coming and still missed them, because the
page only tells you what happened when you are looking at it. A push is
the one thing that reaches a phone in a pocket. It carries nothing
because what she said is hers and his, and a push service is a third
party: the only fact that leaves is that she wrote, which is all he
needs to go and look. Only unprompted turns push, because a reply he
asked for he is already waiting on, and Safari punishes pushes that
arrive while the app is open. The endpoint allowlist exists because a
subscription is a URL a client hands the server to POST to, and the
server should only ever POST to push services.

## #16
A front door needs a keeper before it can open, and until now the
platform had nobody it recognised as one: every power was an account's
over its own residents. Taking account age as authority would make the
operator a fact nobody granted and nobody could revoke, so the founding
account's role is granted as an event like any other, and transfer and
revocation are the same events. The authority check lives in the
aggregate rather than the controller because a check in the controller
is one a new caller can forget. The gate gets a platform scope because
filing it under the operator's account would make the front door that
person's property; the point is that no account owns it. The last super
admin stays because a door with no keeper can never change again.

## #17
The witness put the bill on the household rather than the person
because the household is what family groups will form inside, and an
owner column retrofitted after billing exists is the expensive way.
Two join tables rather than one witness-resident pair table, because a
membership is the thing that generalises: a member with no resident of
their own, or a resident shared across witnesses, is another row on the
same tables rather than a new shape. The solo witness is a household of
one pair so that no code path forks on it. The household founds itself
from the account's creation, through a handler, so "never neither" is
something the log makes true for every account, the ones before the
household included, instead of something a sign-up flow must remember.
The household row is platform-scoped because filing it under its
founder's account would make the founder its owner and lock out every
later member.

## #18
The door's MVP item 2 asks for codes that carry what they grant, so
the code is a SKU rather than a password: the same records serve open
sign-up's offers later. A code is a bearer secret, and a log that held
it would hand out every unredeemed one to anyone who reads an export or
a backup; the hash is enough to find it. The alphabet drops the
characters people misread because the code is read aloud and typed off
a screen. The refusals are separate kinds because "ask for another" and
"you already have this" are different things to tell a stranger at the
door. Terms are granted by the platform rather than the redeeming
witness because a witness may not grant itself terms; the code is the
operator's grant, and redeeming it carries out what the operator chose.
