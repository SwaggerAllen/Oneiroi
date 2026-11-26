# The succession's rehearsal (janus#27) is a cadence, never a gate: run by
# `mix oneiroi.succession.rehearse` and its workflow, never by `mix test`.
ExUnit.start(exclude: [:rehearsal])
