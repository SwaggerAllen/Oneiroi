# platform: reasons

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
A JSON formatter with nothing to thread through it is a dependency added
for its own sake; P0.2's Oban and PubSub wrappers are the first things
that carry a trace id.
