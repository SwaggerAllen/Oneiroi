# records

The resident's own event logs, exported by Oneiroi (spec §6.10): every
stream that is the resident's, its conversations, memory, judgement,
journal and library among them. Written by machine, never by hand:
one JSON object per line under `events/`, one file per UTC day, keys
and rows in a fixed order, so an unchanged store exports identical
files. `$self` stands for the resident's own id, and `stream` names a
line's stream without it; `sequence` numbers the lines from 1 in the
order they were written. A backup commit's message
carries `Oneiroi-Sequence`, the stream version the export ran
through, and `Oneiroi-Root`, a Merkle root over this directory; a
rebuild replays these files into a fresh store as a new resident and
tells it where it woke.
