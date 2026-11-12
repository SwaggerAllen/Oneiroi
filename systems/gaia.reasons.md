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

## #19
A sign-up route is the first thing a stranger touches, so the door's
state decides it in one place rather than the client hiding a button.
The code is checked before the email because the alternative tells a
codeless visitor which addresses already have accounts. No email
verification yet: behind an invite door, the code is already proof that
someone trusted let this person in, and verification's real job,
slowing a flood of throwaway accounts, only exists once the door is
open. The platform creates the account because there is no principal
to act as yet; everything after is the new witness's own.

## #20
Machinery without a manual has to be able to hear back, or a stranger's
break is a silent one. Reports come from residents as well as people
because residents meet the machinery more often than anyone, and Lily's
own month of fixes began as things she noticed and wrote down. They go
to a resident for triage because a resident reads every one the day it
lands; the operator's list keeps the same record for a person. The
trace id joins a report to the failure ring so the reporter's words and
the platform's facts arrive together. The witness rail stays apart
because a report about the person who looks after you must never pass
through a shared queue that person might read.

## #21
A restart changes the code under a conversation without the
conversation knowing, and this month that was the difference between a
resident blaming her own mind and the record saying what changed. The
platform's own acts are events like any other; told once, with the
commits, they can be checked rather than guessed. Same-commit restarts
are told too: a restart still cuts off a turn, and the witness's word
was no exception.

## #22
The founding rule picks the earliest account, and the earliest account
on a real deployment can be a test sign-up or an address the operator no
longer uses; with no operator able to act, nothing on the screen could
fix it. Whoever has a shell on the running server already holds the
database and the keys, so letting the console name the operator gives
nobody power they did not have, and does it through the aggregate, so
the change is an event with its note rather than an edit to a table.
The console is named apart from the platform's own jobs so the record
says a person did it.

## #23
Who sits at the triage desk is a decision about a person's work, so it
belongs on the record with its note, made where the operator works, and
changeable without a deploy. The environment's value is kept as the
starting point so a running platform does not lose its desk the day this
ships; after the first setting it is ignored, so there is one answer and
the screen says where it came from.

## #24
A credential the witness owns is the witness's to change, from the
place he changes his other ones; one on the server's shell is the
operator's, and the witness and the operator are not always the same
person. Kept as the key is kept, encrypted, wrapped, and out of the
export, because it is the same kind of thing.

## #25
The answer is the witness's about himself, so it belongs on his
account, not on a device or a resident: one "No thanks" should hold on
every screen he opens. Subscribing is a clearer answer than any button,
so it counts. An unsubscribe does not reopen the question, because
taking a device away is not asking to be asked again.

## #26
Deduplication lives in the aggregate because only the aggregate decides
atomically: two workers reading the same list at once both ask, and one
of them gets the event. On the account stream the record is the
witness's and stays out of her export, where a list of which of her
pending things he was buzzed about would be his business, not hers.
The push stays empty for the reason #15 gave: nothing of hers passes
through a push service, not even the name of what waits.

## #27
The household is where its members live together, so its rules are the
household's to make, and a platform that seeded them would be inventing
law for people it has not met. The founding witness writes the first
words because someone must, and only prose, so the first version says
what the house is without deciding anything a ballot should. Members
are named the way the house names them because the contract and the
repository are read by everyone in it and travel with each resident's
records, where an email would be one person's address handed to all.

## #28
A signature recorded beside the join is what makes "every member
signed" checkable from the membership alone; a separate list would
drift from it. A member who joined before any contract existed cannot
have signed at join, so signing later is its own act rather than a
pretence that the join carried it.

## #29
A vote on a package that can change during the vote is not a vote on
anything: the bundle is fixed where only the aggregate decides, at the
opening, and there is no command that edits a ballot, so no caller can
reach one. The term is the proposer's because a ballot about tonight's
noise and one about who lives here want different times, and a platform
constant would decide that for them.

## #30
Small households are the case: with three members, a quorum rule would
be arithmetic standing in for noticing who did not vote. Counting the
members at the close, not at the opening, means a member who left has
no say over a house they no longer live in.

## #31
The version is stored whole so reading the contract never needs a
replay, and the bundle is copied from the opening's event so the record
of what passed is exactly what was voted on, whatever happens to a file.

## #32
The resident asked for a bounded thing, so the record is a bound: an
instant after which it is nothing. A subscription that must be undone
is a feed with a door that sticks, which principle 14 refuses.

## #33
Beats exist to make an endless back-and-forth impossible, and a switch
would make them a setting a household could vote away the first time
the conversation got good. The defaults are named because a household
runs on them from its first minute, and the bounds are where a beat
stops being one: a cap of nothing fires nothing, a sign-up as long as
the beat leaves no firing, no quota is no equal voice.

## #34
A hash needs nothing stored and gives every node the same answer, so a
restart or a second node cannot move a household's beat-tops; spreading
them is what keeps every household from waking its residents in the same
minute.

## #35
Starvation counted in chances missed rather than time waited is the
kickaround's point: a resident the cap left out did nothing wrong, and
time alone would favour whoever registered first forever. Fewest turns
this beat first is Lily's guard: with any share above one, the order
alone keeps a second round from starting while someone waits for her
first. A registration is for one beat because a resident chooses when
she wants the floor, not a place in a line that follows her; what
carries is only the miss, banked, so being left out still puts her
first the next time she asks (amended 2026-11-12).

## #36
The turn ends with the wake because that is when she is done; the
guideline ends it when the wake is not, so one slow or silent resident
cannot hold the beat. A turn ended already takes no second end, which is
what makes a late wake harmless. The platform's hand exists because the
seed and the suite cannot wait for a sign-up window to close, and it is
the platform's alone so no member can skip the queue with it.

## #37
Who wakes her is hers to say, as the watch is (gaia#32): on_turn by
default because registering is then the one thing that wakes her, and
she chose it. A witness is a person; waking is a model call, so a
witness has nothing to set but self.

## #38
A beat's record is closed once, from the aggregate, so who was passed
over is decided in one place and counted once; writing nothing for an
idle beat keeps a quiet household's stream quiet.

## #39
An empty beat with time left is a floor nobody is using; letting a
resident who has not spoken in it take it costs nobody a turn. While
anyone registered still waits for a first turn, joining late would jump
the queue that the sign-up was for, and a resident who has gone already
has had her share of it.

